-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-07 — Company Accounting & Compliance Configuration Provisioning
--          (gaps MD-06, MD-07, MD-31)
--
-- Gives a company the accounting config, compliance profile, and explicit
-- functional/reporting currency it needs to transact and file — as REUSABLE
-- BACKEND capabilities (callable by the future MDP-08 wizard / operators). No UI,
-- no onboarding wizard, no posting-logic change, no tax-engine calculation change,
-- and no multi-currency transaction processing (that stays future work).
--
-- ── Inventory result (what already exists — NOT rebuilt) ──────────────────────
-- * company_accounting_config exists (control-account map only: ar/ap/vat/input_vat
--   /ewt_withheld/ewt_payable/default_cash/customer_advances/supplier_down_payments;
--   UNIQUE(company_id); admin-gated RLS; updated_at trigger). It is NOT auto-created
--   and — unlike the other reference/config masters — was NOT audit-trigger covered
--   (MDP-02 consciously deferred its audit coverage to THIS owning package).
-- * compliance_profiles exists (rich statutory profile; UNIQUE(company_id);
--   is_active; already fn_audit_trigger-covered via 20260701000005_audit_cas.sql;
--   an INSERT/UPDATE regenerates the tax calendar). It is NOT auto-created.
-- * companies has legal/tax identity but NO functional-currency field — currency is
--   implicitly PHP (MD-31). currencies (currency_code UNIQUE, PHP seeded is_base)
--   and exchange_rates already exist.
-- * MDP-04 fn_sync_coa_control_accounts(company) reconciles COA control/subledger/
--   tax flags FROM company_accounting_config; MDP-05 fn_seed_company_coa seeds a
--   COA whose canonical codes this package maps into the config. Both are reused.
--
-- ── What this migration adds (only the genuine gaps) ──────────────────────────
--   1. companies.functional_currency_code / reporting_currency_code — explicit,
--      defaulting to PHP, FK to currencies (MD-31 + reporting preference).
--   2. Audit coverage for company_accounting_config (completes MDP-02's deferral).
--   3. fn_provision_company_accounting_config(company) — idempotently creates the
--      config row and maps control accounts from the company's own COA by the
--      canonical PH_STANDARD codes (fills NULLs only), then reconciles COA flags
--      via fn_sync_coa_control_accounts. (MD-06)
--   4. fn_validate_company_accounting_config(company) — returns the set of coherence
--      problems (empty = valid): row present, each mapped account belongs to the
--      company, is postable, and has the expected account_type; currencies active.
--   5. fn_provision_compliance_profile(company) — idempotently creates a default
--      compliance profile derived from companies.tax_registration. (MD-07)
--
-- Governance reuse (MDP-01/05/06 pattern): every function is SECURITY DEFINER,
-- self-checks can_admin_company(company), and is idempotent (ON CONFLICT on the
-- existing UNIQUE(company_id) keys; mapping fills only NULL columns so manual
-- designations survive). Provisioned rows flow through the existing per-table audit
-- triggers (config coverage added here; compliance already covered), so no new
-- audit path is introduced. Additive, forward-only; no RLS change to existing
-- tables, no posting/tax-calculation change.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Explicit functional / reporting currency on the company (MD-31) ────────
-- Additive columns defaulting to PHP, so existing companies keep today's implicit
-- behavior. FK to currencies(currency_code) (already UNIQUE) keeps the value valid.
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS functional_currency_code TEXT NOT NULL DEFAULT 'PHP'
    REFERENCES currencies(currency_code),
  ADD COLUMN IF NOT EXISTS reporting_currency_code  TEXT NOT NULL DEFAULT 'PHP'
    REFERENCES currencies(currency_code);

COMMENT ON COLUMN companies.functional_currency_code IS
  'MDP-07 (MD-31): the company functional/base currency for the books. Defaults to PHP; multi-currency transaction processing remains future work.';
COMMENT ON COLUMN companies.reporting_currency_code IS
  'MDP-07: the currency financial statements are presented in. Defaults to PHP (= functional currency for single-currency books).';

-- ── 2. Complete MDP-02's deferred audit coverage for company_accounting_config ─
DROP TRIGGER IF EXISTS trg_audit_company_accounting_config ON company_accounting_config;
CREATE TRIGGER trg_audit_company_accounting_config
  AFTER INSERT OR UPDATE OR DELETE ON company_accounting_config
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- ── 3. Provision a company's accounting config (MD-06) ────────────────────────
-- Idempotently creates the config row, then maps control accounts from the
-- company's own chart_of_accounts by the canonical PH_STANDARD codes seeded by
-- MDP-05. Only NULL columns are filled, so manual mappings survive re-runs. Finally
-- reconciles COA control/subledger/tax flags via the MDP-04 sync function.
CREATE OR REPLACE FUNCTION fn_provision_company_accounting_config(p_company_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config_id UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision accounting config for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  INSERT INTO company_accounting_config (company_id, created_by, updated_by)
  VALUES (p_company_id, auth.uid(), auth.uid())
  ON CONFLICT (company_id) DO NOTHING;

  -- Map control accounts from the company's own COA by canonical code, filling
  -- only columns that are still NULL (never overriding an explicit mapping). Each
  -- source account is matched within the company (UNIQUE(company_id, account_code))
  -- and required to be postable.
  UPDATE company_accounting_config cfg
     SET ar_account_id           = COALESCE(cfg.ar_account_id,           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1200' AND is_postable)),
         default_cash_account_id = COALESCE(cfg.default_cash_account_id, (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1010' AND is_postable)),
         vat_payable_account_id  = COALESCE(cfg.vat_payable_account_id,  (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2100' AND is_postable)),
         ewt_withheld_account_id = COALESCE(cfg.ewt_withheld_account_id, (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1410' AND is_postable)),
         ap_account_id           = COALESCE(cfg.ap_account_id,           (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2010' AND is_postable)),
         input_vat_account_id    = COALESCE(cfg.input_vat_account_id,    (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '1400' AND is_postable)),
         ewt_payable_account_id  = COALESCE(cfg.ewt_payable_account_id,  (SELECT id FROM chart_of_accounts WHERE company_id = p_company_id AND account_code = '2110' AND is_postable)),
         updated_by              = auth.uid()
  WHERE cfg.company_id = p_company_id;

  -- Keep COA control/subledger/tax flags consistent with the mapped accounts.
  PERFORM fn_sync_coa_control_accounts(p_company_id);

  SELECT id INTO v_config_id FROM company_accounting_config WHERE company_id = p_company_id;
  RETURN v_config_id;
END;
$$;

-- ── 4. Validate a company's accounting config (MD-06) ─────────────────────────
-- Returns one row per coherence problem; an empty result means the config is valid.
-- Checks: config row present; each mapped account belongs to the company, is
-- postable, and carries the expected account_type; functional/reporting currency
-- reference an active currency.
CREATE OR REPLACE FUNCTION fn_validate_company_accounting_config(p_company_id UUID)
RETURNS TABLE (check_code TEXT, detail TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to validate accounting config for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM company_accounting_config WHERE company_id = p_company_id) THEN
    RETURN QUERY SELECT 'config_missing'::TEXT,
      format('no company_accounting_config row for company %s', p_company_id);
    RETURN;
  END IF;

  RETURN QUERY
  WITH cfg AS (
    SELECT * FROM company_accounting_config WHERE company_id = p_company_id
  ),
  mapped(label, account_id, expected_type) AS (
    SELECT 'ar_account_id',           ar_account_id,           'asset'     FROM cfg WHERE ar_account_id IS NOT NULL
    UNION ALL SELECT 'default_cash_account_id', default_cash_account_id, 'asset'     FROM cfg WHERE default_cash_account_id IS NOT NULL
    UNION ALL SELECT 'vat_payable_account_id',  vat_payable_account_id,  'liability' FROM cfg WHERE vat_payable_account_id IS NOT NULL
    UNION ALL SELECT 'input_vat_account_id',    input_vat_account_id,    'asset'     FROM cfg WHERE input_vat_account_id IS NOT NULL
    UNION ALL SELECT 'ewt_withheld_account_id', ewt_withheld_account_id, 'asset'     FROM cfg WHERE ewt_withheld_account_id IS NOT NULL
    UNION ALL SELECT 'ewt_payable_account_id',  ewt_payable_account_id,  'liability' FROM cfg WHERE ewt_payable_account_id IS NOT NULL
    UNION ALL SELECT 'ap_account_id',           ap_account_id,           'liability' FROM cfg WHERE ap_account_id IS NOT NULL
    UNION ALL SELECT 'customer_advances_account_id',      customer_advances_account_id,      'asset'     FROM cfg WHERE customer_advances_account_id IS NOT NULL
    UNION ALL SELECT 'supplier_down_payments_account_id', supplier_down_payments_account_id, 'liability' FROM cfg WHERE supplier_down_payments_account_id IS NOT NULL
  )
  -- account missing / belongs to another company
  SELECT 'account_not_in_company', format('%s -> account %s is not a chart_of_accounts row of this company', m.label, m.account_id)
  FROM mapped m
  WHERE NOT EXISTS (SELECT 1 FROM chart_of_accounts c WHERE c.id = m.account_id AND c.company_id = p_company_id)
  UNION ALL
  -- account not postable
  SELECT 'account_not_postable', format('%s -> account %s is not postable', m.label, c.account_code)
  FROM mapped m JOIN chart_of_accounts c ON c.id = m.account_id AND c.company_id = p_company_id
  WHERE c.is_postable = false
  UNION ALL
  -- account wrong type
  SELECT 'account_wrong_type', format('%s -> account %s is %s, expected %s', m.label, c.account_code, c.account_type, m.expected_type)
  FROM mapped m JOIN chart_of_accounts c ON c.id = m.account_id AND c.company_id = p_company_id
  WHERE c.account_type <> m.expected_type
  UNION ALL
  -- currency inactive
  SELECT 'currency_inactive', format('%s currency %s is not an active currency', lbl, code)
  FROM (
    SELECT 'functional' AS lbl, functional_currency_code AS code FROM companies WHERE id = p_company_id
    UNION ALL
    SELECT 'reporting'  AS lbl, reporting_currency_code  AS code FROM companies WHERE id = p_company_id
  ) cc
  WHERE NOT EXISTS (SELECT 1 FROM currencies cu WHERE cu.currency_code = cc.code AND cu.is_active);
END;
$$;

-- ── 5. Provision a company's compliance profile (MD-07) ───────────────────────
-- Idempotently creates a default compliance profile derived from the company's
-- BIR tax_registration. INSERTing fires the existing tax-calendar generation
-- trigger, so the company also gets a coherent filing calendar.
CREATE OR REPLACE FUNCTION fn_provision_compliance_profile(p_company_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tax_registration TEXT;
  v_profile_id       UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision a compliance profile for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  SELECT tax_registration INTO v_tax_registration FROM companies WHERE id = p_company_id;
  IF v_tax_registration IS NULL THEN
    RAISE EXCEPTION 'company % not found', p_company_id USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO compliance_profiles (
    company_id,
    vat_registered, vat_filing_frequency,
    percentage_tax_registered, percentage_tax_rate, pt_filing_frequency,
    income_tax_regime, corporate_tax_rate,
    created_by, updated_by)
  VALUES (
    p_company_id,
    (v_tax_registration = 'vat'),
    CASE WHEN v_tax_registration = 'vat' THEN 'quarterly' ELSE NULL END,
    (v_tax_registration = 'non_vat'),
    CASE WHEN v_tax_registration = 'non_vat' THEN 3.00 ELSE NULL END,
    CASE WHEN v_tax_registration = 'non_vat' THEN 'quarterly' ELSE NULL END,
    'rcit', 25.00,
    auth.uid(), auth.uid())
  ON CONFLICT (company_id) DO NOTHING;

  SELECT id INTO v_profile_id FROM compliance_profiles WHERE company_id = p_company_id;
  RETURN v_profile_id;
END;
$$;

-- ── 6. Least privilege: functions self-check authority; grant execute ─────────
REVOKE ALL ON FUNCTION fn_provision_company_accounting_config(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_validate_company_accounting_config(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_provision_compliance_profile(UUID)       FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_provision_company_accounting_config(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_company_accounting_config(UUID)  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_provision_compliance_profile(UUID)        TO authenticated, service_role;

COMMENT ON FUNCTION fn_provision_company_accounting_config(UUID) IS
  'MDP-07 (MD-06): creates company_accounting_config and maps control accounts from the company COA by canonical code (fills NULLs only), then reconciles COA flags. Idempotent; admin-gated.';
COMMENT ON FUNCTION fn_validate_company_accounting_config(UUID) IS
  'MDP-07 (MD-06): returns the set of accounting-config coherence problems (empty = valid). Admin-gated.';
COMMENT ON FUNCTION fn_provision_compliance_profile(UUID) IS
  'MDP-07 (MD-07): creates a default compliance_profiles row derived from companies.tax_registration. Idempotent; admin-gated.';
