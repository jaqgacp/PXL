-- ══════════════════════════════════════════════════════════════════════════════
-- COA Engine — Phase A (additive foundation)
--
-- Implements the frozen COA Engine contract
--   docs/PXL/02. Accounting Core/PXL_COA_ENGINE_SPEC.md
-- as a NEW, non-breaking layer beside the existing schema. Phase A rewires NO
-- posting consumer, changes NO Posting Engine behavior, and does NOT touch MDP-05
-- provisioning. company_accounting_config remains the single writable operational
-- authority; account_mapping is an additively-seeded, kept-in-sync projection of
-- it; fn_resolve_account is equivalence-tested to return exactly today's config.
--
-- Delivers: ref_mapping_key, account_mapping, fn_resolve_account (deterministic,
-- fail-closed, ambiguity-rejecting), the vw_company_accounting_config compat view
-- + config→mapping sync, the account lifecycle framework, change-policy
-- enforcement, the FS registry (fs_structure/account_fs_map), and the canonical
-- PXL Standard COA fixture generator. All new base tables carry RLS + audit and
-- are registered in the coverage matrix + guard 075.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 0. Lifecycle status on chart_of_accounts (Contract 3, additive) ─────────────
ALTER TABLE chart_of_accounts
  ADD COLUMN IF NOT EXISTS lifecycle_status TEXT NOT NULL DEFAULT 'active'
    CHECK (lifecycle_status IN ('draft','active','deprecated','archived','locked'));

-- Back-compat backfill: existing inactive accounts map to 'deprecated'. Runs
-- before the change-policy guard exists, so it is unguarded and touches no
-- immutable identity attribute.
UPDATE chart_of_accounts SET lifecycle_status = 'deprecated'
 WHERE is_active = false AND lifecycle_status = 'active';

COMMENT ON COLUMN chart_of_accounts.lifecycle_status IS
  'COA Engine (Contract 3): draft/active/deprecated/archived/locked; is_active is kept in sync (active <=> is_active).';

-- ── 1. ref_mapping_key — seed-governed semantic key catalog (Contract 1) ────────
CREATE TABLE IF NOT EXISTS ref_mapping_key (
  key_code              TEXT PRIMARY KEY,
  description           TEXT NOT NULL,
  expected_account_type TEXT
    CHECK (expected_account_type IS NULL OR expected_account_type IN
      ('asset','liability','equity','revenue','expense')),
  is_active             BOOLEAN NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE ref_mapping_key IS
  'COA Engine (Contract 1): fixed vocabulary of resolvable semantic account references. Seed-only (added by migration); not a runtime write.';

-- Phase A seeds exactly the keys backed by a current company_accounting_config
-- column (1:1, reversible). Further keys are added by migration as consumers adopt.
INSERT INTO ref_mapping_key (key_code, description, expected_account_type) VALUES
  ('AR_TRADE',              'Trade accounts receivable control',            'asset'),
  ('AP_TRADE',              'Trade accounts payable control',               'liability'),
  ('VAT_OUTPUT',            'Output VAT payable',                           'liability'),
  ('VAT_INPUT',             'Input VAT (creditable)',                       'asset'),
  ('EWT_WITHHELD',          'Expanded withholding tax withheld / creditable','asset'),
  ('EWT_PAYABLE',           'Expanded withholding tax payable',             'liability'),
  ('CASH_DEFAULT',          'Default cash / cash-in-bank account',          'asset'),
  ('CUSTOMER_ADVANCES',     'Customer advances / unearned',                 'liability'),
  ('SUPPLIER_DOWNPAYMENTS', 'Supplier down payments / advances to suppliers','asset')
ON CONFLICT (key_code) DO NOTHING;

ALTER TABLE ref_mapping_key ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ref_mapping_key FROM PUBLIC;
GRANT SELECT ON ref_mapping_key TO authenticated;
DROP POLICY IF EXISTS refkey_read ON ref_mapping_key;
CREATE POLICY refkey_read ON ref_mapping_key FOR SELECT TO authenticated USING (true);
-- No write policy: the catalog is seed/migration-only (service_role/superuser).

-- ── 2. account_mapping — effective-dated bindings with coexisting qualifiers ─────
CREATE TABLE IF NOT EXISTS account_mapping (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     UUID NOT NULL REFERENCES companies(id),
  key_code       TEXT NOT NULL REFERENCES ref_mapping_key(key_code),
  -- Independent, coexisting qualifiers. A mapping is the AND of its non-null
  -- qualifiers; a null qualifier matches anything. Precedence (most significant
  -- first): document_type > party > item > item_group > tax_profile > branch.
  branch_id       UUID REFERENCES branches(id),
  document_type   TEXT,
  party_id        UUID,          -- polymorphic (customer/supplier); validated at Phase B wiring
  item_id         UUID REFERENCES items(id),
  item_group_id   UUID,          -- item category; validated at Phase B wiring
  tax_profile_id  UUID,          -- tax profile; validated at Phase B wiring
  account_id     UUID NOT NULL REFERENCES chart_of_accounts(id),
  effective_from DATE,
  effective_to   DATE,
  reason_code    TEXT,
  source         TEXT NOT NULL DEFAULT 'manual'
                   CHECK (source IN ('config_sync','manual','migration')),
  created_by     UUID,
  updated_by     UUID,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (effective_from IS NULL OR effective_to IS NULL OR effective_to >= effective_from)
);

COMMENT ON TABLE account_mapping IS
  'COA Engine (Contract 1): company-scoped, effective-dated ref_mapping_key -> account bindings with coexisting qualifiers. Phase A: derived projection of company_accounting_config (config remains the sole writable authority).';

-- At most one CURRENT (open) binding per exact scope tuple, nulls treated equal.
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_mapping_current
  ON account_mapping (company_id, key_code, branch_id, document_type,
                      party_id, item_id, item_group_id, tax_profile_id)
  NULLS NOT DISTINCT
  WHERE effective_to IS NULL;
CREATE INDEX IF NOT EXISTS idx_account_mapping_lookup
  ON account_mapping (company_id, key_code);

DROP TRIGGER IF EXISTS trg_account_mapping_updated_at ON account_mapping;
CREATE TRIGGER trg_account_mapping_updated_at
  BEFORE UPDATE ON account_mapping FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_audit_account_mapping ON account_mapping;
CREATE TRIGGER trg_audit_account_mapping
  AFTER INSERT OR UPDATE OR DELETE ON account_mapping
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

ALTER TABLE account_mapping ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON account_mapping FROM PUBLIC;
GRANT SELECT ON account_mapping TO authenticated;
DROP POLICY IF EXISTS am_read ON account_mapping;
CREATE POLICY am_read ON account_mapping FOR SELECT TO authenticated
  USING (is_company_member(company_id));
-- No authenticated write policy in Phase A: writes flow only through the config
-- sync (DEFINER) so company_accounting_config stays the single writable authority.

-- ── 3. Config → mapping sync (keeps the projection in step with the authority) ──
CREATE OR REPLACE FUNCTION fn_sync_account_mapping_from_config(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg   company_accounting_config%ROWTYPE;
  r       RECORD;
  v_count INTEGER := 0;
BEGIN
  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = p_company_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  FOR r IN
    SELECT * FROM (VALUES
      ('AR_TRADE',              v_cfg.ar_account_id),
      ('AP_TRADE',              v_cfg.ap_account_id),
      ('VAT_OUTPUT',            v_cfg.vat_payable_account_id),
      ('VAT_INPUT',             v_cfg.input_vat_account_id),
      ('EWT_WITHHELD',          v_cfg.ewt_withheld_account_id),
      ('EWT_PAYABLE',           v_cfg.ewt_payable_account_id),
      ('CASH_DEFAULT',          v_cfg.default_cash_account_id),
      ('CUSTOMER_ADVANCES',     v_cfg.customer_advances_account_id),
      ('SUPPLIER_DOWNPAYMENTS', v_cfg.supplier_down_payments_account_id)
    ) AS t(key_code, account_id)
    WHERE t.account_id IS NOT NULL
  LOOP
    UPDATE account_mapping m
       SET account_id = r.account_id, source = 'config_sync', updated_at = now()
     WHERE m.company_id = p_company_id
       AND m.key_code = r.key_code
       AND m.branch_id IS NULL AND m.document_type IS NULL AND m.party_id IS NULL
       AND m.item_id IS NULL AND m.item_group_id IS NULL AND m.tax_profile_id IS NULL
       AND m.effective_to IS NULL;
    IF NOT FOUND THEN
      INSERT INTO account_mapping (company_id, key_code, account_id, source)
      VALUES (p_company_id, r.key_code, r.account_id, 'config_sync');
    END IF;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION fn_sync_account_mapping_from_config(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_sync_account_mapping_from_config(UUID) TO service_role;
COMMENT ON FUNCTION fn_sync_account_mapping_from_config(UUID) IS
  'COA Engine (Contract 1): upserts the company-scope account_mapping projection from company_accounting_config. Idempotent; additive-only.';

CREATE OR REPLACE FUNCTION fn_account_mapping_sync_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_sync_account_mapping_from_config(NEW.company_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_account_mapping ON company_accounting_config;
CREATE TRIGGER trg_sync_account_mapping
  AFTER INSERT OR UPDATE ON company_accounting_config
  FOR EACH ROW EXECUTE FUNCTION fn_account_mapping_sync_trigger();

-- One-time backfill of companies that already have config at migration time.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT company_id FROM company_accounting_config LOOP
    PERFORM fn_sync_account_mapping_from_config(r.company_id);
  END LOOP;
END;
$$;

-- ── 4. fn_resolve_account — deterministic, fail-closed, ambiguity-rejecting ──────
CREATE OR REPLACE FUNCTION fn_resolve_account(
  p_company_id UUID,
  p_key_code   TEXT,
  p_context    JSONB DEFAULT '{}'::jsonb,
  p_as_of      DATE  DEFAULT CURRENT_DATE
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key           ref_mapping_key%ROWTYPE;
  v_account_id    UUID;
  v_match_count   INTEGER;
  v_acct_type     TEXT;
  v_postable      BOOLEAN;
  v_lifecycle     TEXT;
  v_acct_company  UUID;
  v_override      UUID := NULLIF(p_context->>'override_account_id','')::uuid;
  v_override_auth BOOLEAN := COALESCE((p_context->>'override_authorized')::boolean, false);
  v_branch  UUID := NULLIF(p_context->>'branch_id','')::uuid;
  v_doctype TEXT := NULLIF(p_context->>'document_type','');
  v_party   UUID := NULLIF(p_context->>'party_id','')::uuid;
  v_item    UUID := NULLIF(p_context->>'item_id','')::uuid;
  v_itemgrp UUID := NULLIF(p_context->>'item_group_id','')::uuid;
  v_taxprof UUID := NULLIF(p_context->>'tax_profile_id','')::uuid;
BEGIN
  -- Membership safety: a logged-in caller may only resolve within its own
  -- company (service/superuser contexts have no auth.uid() and are allowed).
  IF auth.uid() IS NOT NULL AND NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'COA resolver: not a member of company %', p_company_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 1. Key validity (fail-closed on unknown/inactive).
  SELECT * INTO v_key FROM ref_mapping_key WHERE key_code = p_key_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COA resolver: unknown ref_mapping_key %', p_key_code
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT v_key.is_active THEN
    RAISE EXCEPTION 'COA resolver: ref_mapping_key % is inactive', p_key_code
      USING ERRCODE = 'check_violation';
  END IF;

  -- 2. Authorized transaction-level override wins outright.
  IF v_override IS NOT NULL THEN
    IF NOT v_override_auth THEN
      RAISE EXCEPTION 'COA resolver: transaction override for % supplied without authorization', p_key_code
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    v_account_id := v_override;
  ELSE
    -- 3+4. Matching candidates ranked by lexicographic specificity. The integer
    -- weights are powers of two ordered so a higher-priority qualifier always
    -- outranks any combination of lower ones (32 > 16+8+4+2+1).
    WITH candidates AS (
      SELECT m.account_id,
             (CASE WHEN m.document_type  IS NOT NULL THEN 32 ELSE 0 END)
           + (CASE WHEN m.party_id       IS NOT NULL THEN 16 ELSE 0 END)
           + (CASE WHEN m.item_id        IS NOT NULL THEN  8 ELSE 0 END)
           + (CASE WHEN m.item_group_id  IS NOT NULL THEN  4 ELSE 0 END)
           + (CASE WHEN m.tax_profile_id IS NOT NULL THEN  2 ELSE 0 END)
           + (CASE WHEN m.branch_id      IS NOT NULL THEN  1 ELSE 0 END) AS specificity
        FROM account_mapping m
       WHERE m.company_id = p_company_id
         AND m.key_code   = p_key_code
         AND (m.effective_from IS NULL OR m.effective_from <= p_as_of)
         AND (m.effective_to   IS NULL OR p_as_of <= m.effective_to)
         AND (m.branch_id      IS NULL OR m.branch_id      = v_branch)
         AND (m.document_type  IS NULL OR m.document_type  = v_doctype)
         AND (m.party_id       IS NULL OR m.party_id       = v_party)
         AND (m.item_id        IS NULL OR m.item_id        = v_item)
         AND (m.item_group_id  IS NULL OR m.item_group_id  = v_itemgrp)
         AND (m.tax_profile_id IS NULL OR m.tax_profile_id = v_taxprof)
    ),
    ranked AS (
      SELECT account_id, rank() OVER (ORDER BY specificity DESC) AS rk
        FROM candidates
    )
    SELECT count(*) FILTER (WHERE rk = 1),
           (array_agg(account_id) FILTER (WHERE rk = 1))[1]
      INTO v_match_count, v_account_id
      FROM ranked;

    IF v_match_count = 0 THEN
      RAISE EXCEPTION 'COA resolver: no active mapping for key % in company % as of %',
        p_key_code, p_company_id, p_as_of USING ERRCODE = 'no_data_found';
    ELSIF v_match_count > 1 THEN
      RAISE EXCEPTION 'COA resolver: ambiguous equal-specificity mappings (% candidates) for key % in company %',
        v_match_count, p_key_code, p_company_id USING ERRCODE = 'cardinality_violation';
    END IF;
  END IF;

  -- 5. Validate the resolved account (fail-closed).
  SELECT account_type, is_postable, lifecycle_status, company_id
    INTO v_acct_type, v_postable, v_lifecycle, v_acct_company
    FROM chart_of_accounts WHERE id = v_account_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'COA resolver: mapped account % does not exist', v_account_id
      USING ERRCODE = 'no_data_found';
  END IF;
  IF v_acct_company <> p_company_id THEN
    RAISE EXCEPTION 'COA resolver: mapped account % is not in company %', v_account_id, p_company_id
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_key.expected_account_type IS NOT NULL AND v_acct_type <> v_key.expected_account_type THEN
    RAISE EXCEPTION 'COA resolver: account % type % does not match expected % for key %',
      v_account_id, v_acct_type, v_key.expected_account_type, p_key_code USING ERRCODE = 'check_violation';
  END IF;
  IF v_postable IS NOT TRUE THEN
    RAISE EXCEPTION 'COA resolver: account % for key % is not postable', v_account_id, p_key_code
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_lifecycle <> 'active' THEN
    RAISE EXCEPTION 'COA resolver: account % for key % lifecycle is % (not active)', v_account_id, p_key_code, v_lifecycle
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN v_account_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_resolve_account(UUID, TEXT, JSONB, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_resolve_account(UUID, TEXT, JSONB, DATE) TO authenticated, service_role;
COMMENT ON FUNCTION fn_resolve_account(UUID, TEXT, JSONB, DATE) IS
  'COA Engine (Contract 1): deterministic, fail-closed account resolution by most-specific matching mapping; rejects ambiguous equal-specificity matches; validates postable/active/type. Not wired into posting in Phase A.';

-- ── 5. Compatibility view over company_accounting_config ────────────────────────
CREATE OR REPLACE VIEW vw_company_accounting_config
WITH (security_invoker = true) AS
SELECT
  c.id AS company_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'AR_TRADE'))[1]              AS ar_account_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'AP_TRADE'))[1]              AS ap_account_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'VAT_OUTPUT'))[1]            AS vat_payable_account_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'VAT_INPUT'))[1]             AS input_vat_account_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'EWT_WITHHELD'))[1]          AS ewt_withheld_account_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'EWT_PAYABLE'))[1]           AS ewt_payable_account_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'CASH_DEFAULT'))[1]          AS default_cash_account_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'CUSTOMER_ADVANCES'))[1]     AS customer_advances_account_id,
  (array_agg(am.account_id) FILTER (WHERE am.key_code = 'SUPPLIER_DOWNPAYMENTS'))[1] AS supplier_down_payments_account_id
FROM companies c
LEFT JOIN account_mapping am
  ON am.company_id = c.id
 AND am.effective_to IS NULL
 AND am.branch_id IS NULL AND am.document_type IS NULL AND am.party_id IS NULL
 AND am.item_id IS NULL AND am.item_group_id IS NULL AND am.tax_profile_id IS NULL
GROUP BY c.id;

COMMENT ON VIEW vw_company_accounting_config IS
  'COA Engine (Contract 1): reconstructs the legacy company_accounting_config shape from the current account_mapping projection so readers can migrate onto the resolver. security_invoker.';

-- ── 6. Account lifecycle transitions (Contract 3) ───────────────────────────────
CREATE OR REPLACE FUNCTION fn_is_valid_lifecycle_transition(p_old TEXT, p_new TEXT)
RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE
AS $$
  SELECT p_old = p_new
      OR (p_old || '>' || p_new) IN (
        'draft>active','draft>archived',
        'active>deprecated','active>locked',
        'deprecated>active','deprecated>archived','deprecated>locked',
        'locked>active','locked>deprecated',
        'archived>deprecated'
      );
$$;
COMMENT ON FUNCTION fn_is_valid_lifecycle_transition(TEXT, TEXT) IS
  'COA Engine (Contract 3): true iff the account lifecycle edge old->new is permitted (or a no-op).';

-- ── 7. Change-policy + lifecycle guard on chart_of_accounts (Contract 4) ────────
CREATE OR REPLACE FUNCTION fn_coa_change_policy_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_history BOOLEAN;
  v_balance     NUMERIC;
BEGIN
  IF TG_OP = 'DELETE' THEN
    SELECT EXISTS (
      SELECT 1 FROM journal_entry_lines l
        JOIN journal_entries je ON je.id = l.je_id
       WHERE l.account_id = OLD.id AND je.status IN ('posted','reversed')
    ) INTO v_has_history;
    IF v_has_history THEN
      RAISE EXCEPTION 'COA change policy: account % has posted history and cannot be deleted (deprecate/archive instead)', OLD.account_code
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;

  -- UPDATE path
  SELECT EXISTS (
    SELECT 1 FROM journal_entry_lines l
      JOIN journal_entries je ON je.id = l.je_id
     WHERE l.account_id = OLD.id AND je.status IN ('posted','reversed')
  ) INTO v_has_history;

  IF v_has_history THEN
    IF NEW.account_type IS DISTINCT FROM OLD.account_type THEN
      RAISE EXCEPTION 'COA change policy: account_type is immutable once account % has posted history', OLD.account_code USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.normal_balance IS DISTINCT FROM OLD.normal_balance THEN
      RAISE EXCEPTION 'COA change policy: normal_balance is immutable once account % has posted history', OLD.account_code USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.is_postable IS DISTINCT FROM OLD.is_postable THEN
      RAISE EXCEPTION 'COA change policy: posting role (is_postable) is immutable once account % has posted history', OLD.account_code USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.is_control_account IS DISTINCT FROM OLD.is_control_account THEN
      RAISE EXCEPTION 'COA change policy: is_control_account is immutable once account % has posted history', OLD.account_code USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF NEW.lifecycle_status IS DISTINCT FROM OLD.lifecycle_status THEN
    IF NOT fn_is_valid_lifecycle_transition(OLD.lifecycle_status, NEW.lifecycle_status) THEN
      RAISE EXCEPTION 'COA change policy: illegal lifecycle transition %->% for account %', OLD.lifecycle_status, NEW.lifecycle_status, OLD.account_code
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.lifecycle_status = 'archived' THEN
      SELECT COALESCE(SUM(l.debit_amount - l.credit_amount), 0)
        INTO v_balance
        FROM journal_entry_lines l
        JOIN journal_entries je ON je.id = l.je_id
       WHERE l.account_id = OLD.id AND je.status = 'posted';
      IF v_balance <> 0 THEN
        RAISE EXCEPTION 'COA change policy: account % cannot be archived with non-zero posted balance (%).', OLD.account_code, v_balance
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    -- Keep is_active in sync with lifecycle for back-compat.
    NEW.is_active := (NEW.lifecycle_status = 'active');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_coa_change_policy_guard ON chart_of_accounts;
CREATE TRIGGER trg_coa_change_policy_guard
  BEFORE UPDATE OR DELETE ON chart_of_accounts
  FOR EACH ROW EXECUTE FUNCTION fn_coa_change_policy_guard();

CREATE OR REPLACE FUNCTION fn_transition_account_lifecycle(
  p_account_id UUID, p_new_status TEXT, p_reason TEXT DEFAULT NULL)
RETURNS chart_of_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r chart_of_accounts%ROWTYPE;
BEGIN
  SELECT * INTO r FROM chart_of_accounts WHERE id = p_account_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account % not found', p_account_id USING ERRCODE = 'no_data_found';
  END IF;
  IF NOT can_admin_company(r.company_id) THEN
    RAISE EXCEPTION 'not authorized to change account lifecycle for company %', r.company_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  UPDATE chart_of_accounts SET lifecycle_status = p_new_status
   WHERE id = p_account_id RETURNING * INTO r;   -- guard validates the edge
  RETURN r;
END;
$$;
REVOKE ALL ON FUNCTION fn_transition_account_lifecycle(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_transition_account_lifecycle(UUID, TEXT, TEXT) TO authenticated, service_role;
COMMENT ON FUNCTION fn_transition_account_lifecycle(UUID, TEXT, TEXT) IS
  'COA Engine (Contract 3): admin-gated account lifecycle transition; the change-policy guard enforces edge validity and archive-balance rules; audited via the COA audit trigger.';

-- ── 8. Posting-control validators (Contract 2 — framework, not wired) ────────────
CREATE OR REPLACE FUNCTION fn_account_is_leaf(p_account_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT NOT EXISTS (SELECT 1 FROM chart_of_accounts c WHERE c.parent_id = p_account_id);
$$;

CREATE OR REPLACE FUNCTION fn_is_account_postable(p_account_id UUID, p_as_of DATE DEFAULT CURRENT_DATE)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE r chart_of_accounts%ROWTYPE;
BEGIN
  SELECT * INTO r FROM chart_of_accounts WHERE id = p_account_id;
  IF NOT FOUND THEN RETURN false; END IF;
  RETURN r.is_postable
     AND r.lifecycle_status = 'active'
     AND fn_account_is_leaf(p_account_id)
     AND (r.effective_from IS NULL OR r.effective_from <= p_as_of)
     AND (r.effective_to   IS NULL OR p_as_of <= r.effective_to);
END;
$$;

CREATE OR REPLACE FUNCTION fn_assert_postable_leaf(p_account_id UUID, p_as_of DATE DEFAULT CURRENT_DATE)
RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT fn_is_account_postable(p_account_id, p_as_of) THEN
    RAISE EXCEPTION 'COA posting control: account % is not a postable, active, in-window leaf account', p_account_id
      USING ERRCODE = 'check_violation';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_assert_manual_postable(p_account_id UUID, p_as_of DATE DEFAULT CURRENT_DATE)
RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_control BOOLEAN;
BEGIN
  PERFORM fn_assert_postable_leaf(p_account_id, p_as_of);
  SELECT is_control_account INTO v_control FROM chart_of_accounts WHERE id = p_account_id;
  IF v_control THEN
    RAISE EXCEPTION 'COA posting control: control account % may not be posted by a manual journal; its movement must originate from the owning subledger', p_account_id
      USING ERRCODE = 'check_violation';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_account_is_leaf(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_is_account_postable(UUID, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_assert_postable_leaf(UUID, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_assert_manual_postable(UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_account_is_leaf(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_is_account_postable(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_assert_postable_leaf(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_assert_manual_postable(UUID, DATE) TO authenticated, service_role;

-- ── 9. Financial Statement Registry (Contract 5 — framework) ────────────────────
CREATE TABLE IF NOT EXISTS fs_structure (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    UUID NOT NULL REFERENCES companies(id),
  statement     TEXT NOT NULL CHECK (statement IN ('balance_sheet','income_statement','cash_flow')),
  line_code     TEXT NOT NULL,
  line_label    TEXT NOT NULL,
  parent_id     UUID REFERENCES fs_structure(id),
  display_order INTEGER NOT NULL DEFAULT 0,
  is_subtotal   BOOLEAN NOT NULL DEFAULT false,
  created_by    UUID,
  updated_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, statement, line_code)
);

CREATE TABLE IF NOT EXISTS account_fs_map (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID NOT NULL REFERENCES companies(id),
  account_id      UUID NOT NULL REFERENCES chart_of_accounts(id),
  fs_structure_id UUID NOT NULL REFERENCES fs_structure(id),
  statement       TEXT NOT NULL CHECK (statement IN ('balance_sheet','income_statement','cash_flow')),
  effective_from  DATE,
  effective_to    DATE,
  display_order   INTEGER NOT NULL DEFAULT 0,
  created_by      UUID,
  updated_by      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (effective_from IS NULL OR effective_to IS NULL OR effective_to >= effective_from)
);

-- Exactly one ACTIVE (open) mapping per account per statement.
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_fs_map_active
  ON account_fs_map (company_id, account_id, statement)
  WHERE effective_to IS NULL;
CREATE INDEX IF NOT EXISTS idx_account_fs_map_account ON account_fs_map (company_id, account_id);

DROP TRIGGER IF EXISTS trg_fs_structure_updated_at ON fs_structure;
CREATE TRIGGER trg_fs_structure_updated_at
  BEFORE UPDATE ON fs_structure FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_account_fs_map_updated_at ON account_fs_map;
CREATE TRIGGER trg_account_fs_map_updated_at
  BEFORE UPDATE ON account_fs_map FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_audit_fs_structure ON fs_structure;
CREATE TRIGGER trg_audit_fs_structure
  AFTER INSERT OR UPDATE OR DELETE ON fs_structure FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();
DROP TRIGGER IF EXISTS trg_audit_account_fs_map ON account_fs_map;
CREATE TRIGGER trg_audit_account_fs_map
  AFTER INSERT OR UPDATE OR DELETE ON account_fs_map FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

ALTER TABLE fs_structure   ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_fs_map ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON fs_structure   FROM PUBLIC;
REVOKE ALL ON account_fs_map FROM PUBLIC;
GRANT SELECT ON fs_structure   TO authenticated;
GRANT SELECT ON account_fs_map TO authenticated;
DROP POLICY IF EXISTS fss_read ON fs_structure;
CREATE POLICY fss_read ON fs_structure FOR SELECT TO authenticated USING (is_company_member(company_id));
DROP POLICY IF EXISTS afm_read ON account_fs_map;
CREATE POLICY afm_read ON account_fs_map FOR SELECT TO authenticated USING (is_company_member(company_id));
-- Writes flow through the DEFINER provisioning/sync helpers (config authority),
-- keeping the inline chart_of_accounts.fs_* the single writable FS authority in Phase A.

COMMENT ON TABLE fs_structure IS
  'COA Engine (Contract 5): per-company, per-statement ordered FS line hierarchy. Phase A framework; live population is Phase B.';
COMMENT ON TABLE account_fs_map IS
  'COA Engine (Contract 5): effective-dated account -> FS line mapping; one active mapping per account per statement (historical reproduction).';

-- ── 10. Canonical PXL Standard COA fixture generator (Contract 9) ────────────────
-- Reusable generator for the canonical PH-SME chart with complete metadata plus a
-- populated FS registry. Phase A: certification/test fixture only — it does NOT
-- run against live/canonical companies and does not touch MDP-05 provisioning.
CREATE OR REPLACE FUNCTION fn_provision_pxl_standard_coa(
  p_company_id UUID, p_created_by UUID DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  INSERT INTO chart_of_accounts (
    company_id, account_code, account_name, account_type, normal_balance,
    is_postable, is_control_account, allow_subledger, subledger_type,
    fs_group, fs_subgroup, cash_flow_category, is_tax_account, is_operating_expense,
    lifecycle_status, is_active, effective_from, created_by, updated_by)
  SELECT p_company_id, d.code, d.name, d.atype, d.nbal,
         d.postable, d.control, d.subled, d.subtype,
         d.fsgroup, d.fssub, d.cashflow, d.taxacct, d.opex,
         'active', true, DATE '2024-01-01', p_created_by, p_created_by
  FROM (VALUES
    -- code, name, type, normal_balance, postable, control, subledger, subtype, fs_group, fs_subgroup, cash_flow, tax, opex
    ('1000','Cash on Hand',                 'asset','debit',    true, false,false,NULL,        'assets','current_assets','operating',false,false),
    ('1010','Cash in Bank',                 'asset','debit',    true, false,true, 'bank',      'assets','current_assets','operating',false,false),
    ('1100','Accounts Receivable - Trade',  'asset','debit',    true, true, true, 'receivable','assets','current_assets','operating',false,false),
    ('1110','Allowance for Doubtful Accts', 'asset','credit',   true, false,false,NULL,        'assets','current_assets','operating',false,false),
    ('1200','Advances to Suppliers',        'asset','debit',    true, false,false,NULL,        'assets','current_assets','operating',false,false),
    ('1300','Inventory',                    'asset','debit',    true, true, true, 'inventory', 'assets','current_assets','operating',false,false),
    ('1400','Input VAT',                    'asset','debit',    true, false,false,NULL,        'assets','current_assets','operating',true, false),
    ('1410','Creditable Withholding Tax',   'asset','debit',    true, false,false,NULL,        'assets','current_assets','operating',true, false),
    ('1500','Prepaid Expenses',             'asset','debit',    true, false,false,NULL,        'assets','current_assets','operating',false,false),
    ('1600','Property, Plant & Equipment',  'asset','debit',    true, true, true, 'fixed_asset','assets','non_current_assets','investing',false,false),
    ('1610','Accumulated Depreciation',     'asset','credit',   true, false,false,NULL,        'assets','non_current_assets','investing',false,false),
    ('2000','Accounts Payable - Trade',     'liability','credit',true, true, true, 'payable',  'liabilities','current_liabilities','operating',false,false),
    ('2100','Customer Advances',            'liability','credit',true, false,false,NULL,        'liabilities','current_liabilities','operating',false,false),
    ('2200','Output VAT',                   'liability','credit',true, false,false,NULL,        'liabilities','current_liabilities','operating',true, false),
    ('2210','EWT Payable',                  'liability','credit',true, false,false,NULL,        'liabilities','current_liabilities','operating',true, false),
    ('2220','SSS / PhilHealth / Pag-IBIG Payable','liability','credit',true,false,false,NULL,  'liabilities','current_liabilities','operating',false,false),
    ('2230','Income Tax Payable',           'liability','credit',true, false,false,NULL,        'liabilities','current_liabilities','operating',true, false),
    ('2300','Loans Payable',                'liability','credit',true, false,false,NULL,        'liabilities','non_current_liabilities','financing',false,false),
    ('3000','Share Capital',                'equity','credit',  true, false,false,NULL,         'equity','equity','financing',false,false),
    ('3100','Retained Earnings',            'equity','credit',  true, false,false,NULL,         'equity','equity','financing',false,false),
    ('4000','Sales Revenue',                'revenue','credit', true, false,false,NULL,         'revenue','revenue','operating',false,false),
    ('4100','Sales Returns & Allowances',   'revenue','debit',  true, false,false,NULL,         'revenue','revenue','operating',false,false),
    ('4200','Service Revenue',              'revenue','credit', true, false,false,NULL,         'revenue','revenue','operating',false,false),
    ('4900','Other Income',                 'revenue','credit', true, false,false,NULL,         'other_income','other_income','operating',false,false),
    ('5000','Cost of Goods Sold',           'expense','debit',  true, false,false,NULL,         'cost_of_sales','cost_of_sales','operating',false,false),
    ('6000','Salaries & Wages',             'expense','debit',  true, false,false,NULL,         'expenses','operating_expenses','operating',false,true),
    ('6100','Rent Expense',                 'expense','debit',  true, false,false,NULL,         'expenses','operating_expenses','operating',false,true),
    ('6200','Utilities Expense',            'expense','debit',  true, false,false,NULL,         'expenses','operating_expenses','operating',false,true),
    ('6300','Depreciation Expense',         'expense','debit',  true, false,false,NULL,         'expenses','operating_expenses','operating',false,true),
    ('6400','Office Supplies Expense',      'expense','debit',  true, false,false,NULL,         'expenses','operating_expenses','operating',false,true),
    ('6500','Professional Fees',            'expense','debit',  true, false,false,NULL,         'expenses','operating_expenses','operating',false,true),
    ('6600','Taxes & Licenses',             'expense','debit',  true, false,false,NULL,         'expenses','operating_expenses','operating',false,true),
    ('6900','Interest Expense',             'expense','debit',  true, false,false,NULL,         'other_expenses','other_expenses','financing',false,false)
  ) AS d(code,name,atype,nbal,postable,control,subled,subtype,fsgroup,fssub,cashflow,taxacct,opex)
  WHERE NOT EXISTS (
    SELECT 1 FROM chart_of_accounts c
     WHERE c.company_id = p_company_id AND c.account_code = d.code);

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- FS structure lines (one per fs_group per statement) + effective-dated mapping.
  INSERT INTO fs_structure (company_id, statement, line_code, line_label, display_order, created_by, updated_by)
  SELECT p_company_id, s.statement, s.line_code, s.line_label, s.ord, p_created_by, p_created_by
  FROM (VALUES
    ('balance_sheet','assets','Assets',10),
    ('balance_sheet','liabilities','Liabilities',20),
    ('balance_sheet','equity','Equity',30),
    ('income_statement','revenue','Revenue',10),
    ('income_statement','cost_of_sales','Cost of Sales',20),
    ('income_statement','expenses','Operating Expenses',30),
    ('income_statement','other_income','Other Income',40),
    ('income_statement','other_expenses','Other Expenses',50)
  ) AS s(statement,line_code,line_label,ord)
  WHERE NOT EXISTS (
    SELECT 1 FROM fs_structure f
     WHERE f.company_id = p_company_id AND f.statement = s.statement AND f.line_code = s.line_code);

  INSERT INTO account_fs_map (company_id, account_id, fs_structure_id, statement, effective_from, display_order, created_by, updated_by)
  SELECT p_company_id, c.id, f.id, c.fs_statement, DATE '2024-01-01', 0, p_created_by, p_created_by
  FROM chart_of_accounts c
  JOIN fs_structure f
    ON f.company_id = c.company_id
   AND f.statement = c.fs_statement
   AND f.line_code = c.fs_group
  WHERE c.company_id = p_company_id
    AND NOT EXISTS (
      SELECT 1 FROM account_fs_map m
       WHERE m.company_id = c.company_id AND m.account_id = c.id
         AND m.statement = c.fs_statement AND m.effective_to IS NULL);

  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION fn_provision_pxl_standard_coa(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_provision_pxl_standard_coa(UUID, UUID) TO service_role;
COMMENT ON FUNCTION fn_provision_pxl_standard_coa(UUID, UUID) IS
  'COA Engine (canonical dataset): generates the PXL Standard PH-SME chart with complete metadata + populated FS registry for a company. Phase A: certification/test fixture only; does not modify live provisioning or MDP-05.';
