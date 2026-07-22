-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-11 — Attribution & Reference Masters (gaps MD-20, MD-25, MD-26)
--
-- Adds the small reference/attribution masters professional operations expect:
-- governed salesperson (and symmetric buyer) designation, a bank reference master,
-- and company-scoped payment modes with GL mapping. Reusable reference masters ONLY
-- — future modules consume them. No UI, no posting/tax change, no banking/treasury/
-- AR/AP/ownership redesign.
--
-- ── Inventory result (what already exists — NOT rebuilt / NOT duplicated) ──────
-- * Salesperson attribution ALREADY EXISTS as sales_invoices/… .salesperson_id ->
--   employees(id) (validated same-company + active by fn_save_sales_invoice). There
--   is NO standalone salesperson table and creating one would fork that FK, so MD-20
--   is delivered as a GOVERNED DESIGNATION on the employees master, not a new party.
-- * bank_accounts (company-scoped, GL-mapped, branch-aware, is_active, audit-covered)
--   already are the "company bank references"; only bank_name is free text (MD-25).
-- * ref_payment_modes is a GLOBAL read-only reference consumed by receipts / payment
--   vouchers / cash docs via payment_mode_id FKs — left UNTOUCHED. It has no company
--   scope and no GL mapping (MD-26).
-- * ref_reason_codes / ref_rdo_codes / ref_document_types / ref_compliance_forms
--   already cover the other lookup masters. employees & bank_accounts are audit-covered.
-- MISSING (this package): a governed salesperson/buyer designation (MD-20), a bank
--   reference master (MD-25), and company-scoped payment modes with GL mapping (MD-26).
--
-- ── What this migration adds (only the genuine gaps) ──────────────────────────
--   1. employees.is_salesperson / is_buyer designation flags + fn_is_valid_attribution
--      reusable checker (contract for future transaction packages). The existing
--      salesperson_id FK and SI validation are unchanged.
--   2. ref_banks — global read-only bank reference master (seeded PH banks); additive
--      nullable bank_accounts.bank_id FK; legacy bank_name preserved + best-effort
--      backfilled (non-destructive).
--   3. company_payment_modes — company-scoped payment modes referencing the global
--      ref_payment_modes, each mapped to a postable same-company GL account, member-
--      gated + audited. ref_payment_modes and all existing payment_mode_id FKs are
--      untouched.
--
-- Reuse: member-gated RLS (employees/bank_accounts pattern), MDP-01 read-only
-- reference governance (ref_banks), MDP-02 fn_audit_trigger, company/branch isolation
-- helpers. Additive, forward-only, idempotent; existing records preserved. No findings.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Salesperson / Buyer designation on the employees master (MD-20) ────────
ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS is_salesperson BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_buyer       BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN employees.is_salesperson IS
  'MDP-11 (MD-20): marks the employee as a selectable salesperson. The salesperson master is the set of active employees with this flag; the existing sales_invoices.salesperson_id FK is unchanged.';
COMMENT ON COLUMN employees.is_buyer IS
  'MDP-11: marks the employee as a selectable buyer/purchaser (symmetric to is_salesperson) for future purchasing attribution.';

-- Reusable, side-effect-free attribution checker for future transaction packages:
-- true only when the employee exists for the company, is active, and carries the
-- requested designation. A NULL employee is valid (attribution is optional).
CREATE OR REPLACE FUNCTION fn_is_valid_attribution(
  p_kind        TEXT,
  p_employee_id UUID,
  p_company_id  UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
  IF p_employee_id IS NULL THEN
    RETURN true;
  END IF;
  IF p_kind NOT IN ('salesperson','buyer') THEN
    RAISE EXCEPTION 'unknown attribution kind %', p_kind USING ERRCODE = '22023';
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM employees e
    WHERE e.id = p_employee_id
      AND e.company_id = p_company_id
      AND e.is_active
      AND ((p_kind = 'salesperson' AND e.is_salesperson)
        OR (p_kind = 'buyer'       AND e.is_buyer))
  );
END;
$$;

REVOKE ALL ON FUNCTION fn_is_valid_attribution(TEXT, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_is_valid_attribution(TEXT, UUID, UUID) TO authenticated, service_role;
COMMENT ON FUNCTION fn_is_valid_attribution(TEXT, UUID, UUID) IS
  'MDP-11 (MD-20): reusable side-effect-free check that an employee is an active, designated salesperson/buyer of the company. NULL employee = valid (optional). For future transaction packages.';

-- ── 2. Bank reference master (MD-25) ──────────────────────────────────────────
-- Global read-only reference (MDP-01 pattern): authenticated read, deny-by-default
-- writes, maintained by migration/operator; seeded with common Philippine banks.
CREATE TABLE IF NOT EXISTS ref_banks (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bank_code  TEXT NOT NULL UNIQUE,
  bank_name  TEXT NOT NULL,
  swift_code TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ref_banks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ref_banks_read ON ref_banks;
CREATE POLICY ref_banks_read ON ref_banks FOR SELECT TO authenticated USING (true);
-- No write policy → deny-by-default; maintained by migration/operator.
REVOKE ALL ON TABLE ref_banks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE ref_banks TO authenticated;
GRANT ALL    ON TABLE ref_banks TO service_role;

INSERT INTO ref_banks (bank_code, bank_name, swift_code, sort_order) VALUES
  ('BDO',   'BDO Unibank, Inc.',                         'BNORPHMM', 1),
  ('BPI',   'Bank of the Philippine Islands',            'BOPIPHMM', 2),
  ('MBTC',  'Metropolitan Bank & Trust Company',         'MBTCPHMM', 3),
  ('LBP',   'Land Bank of the Philippines',              'TLBPPHMM', 4),
  ('PNB',   'Philippine National Bank',                  'PNBMPHMM', 5),
  ('SECB',  'Security Bank Corporation',                 'SETCPHMM', 6),
  ('UBP',   'UnionBank of the Philippines',              'UBPHPHMM', 7),
  ('RCBC',  'Rizal Commercial Banking Corporation',      'RCBCPHMM', 8),
  ('CHIB',  'China Banking Corporation',                 'CHBKPHMM', 9),
  ('EWB',   'EastWest Banking Corporation',              'EWBCPHMM', 10),
  ('DBP',   'Development Bank of the Philippines',        'DBPHPHMM', 11),
  ('PSB',   'Philippine Savings Bank',                   'PHSBPHMM', 12),
  ('AUB',   'Asia United Bank Corporation',              'AUBKPHMM', 13),
  ('OTHER', 'Other / Not Listed',                        NULL,       99)
ON CONFLICT (bank_code) DO NOTHING;

-- Additive governed-bank FK on company bank accounts (legacy bank_name kept).
ALTER TABLE bank_accounts ADD COLUMN IF NOT EXISTS bank_id UUID REFERENCES ref_banks(id);
CREATE INDEX IF NOT EXISTS idx_bank_accounts_bank ON bank_accounts (bank_id) WHERE bank_id IS NOT NULL;

-- Best-effort non-destructive backfill: link by exact (case-insensitive) name.
UPDATE bank_accounts ba
   SET bank_id = rb.id
FROM ref_banks rb
WHERE ba.bank_id IS NULL
  AND upper(btrim(ba.bank_name)) = upper(btrim(rb.bank_name));

COMMENT ON TABLE ref_banks IS 'MDP-11 (MD-25): global read-only bank reference master (MDP-01 governance). bank_accounts.bank_id links to it; legacy bank_accounts.bank_name is preserved as fallback.';
COMMENT ON COLUMN bank_accounts.bank_id IS 'MDP-11 (MD-25): optional link to the ref_banks reference master; bank_name remains the free-text fallback.';

-- ── 3. Company-scoped payment modes with GL mapping (MD-26) ───────────────────
CREATE TABLE IF NOT EXISTS company_payment_modes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID NOT NULL REFERENCES companies(id),
  payment_mode_id UUID NOT NULL REFERENCES ref_payment_modes(id),
  gl_account_id   UUID NOT NULL REFERENCES chart_of_accounts(id),
  description     TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID,
  updated_by      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, payment_mode_id)
);
CREATE INDEX IF NOT EXISTS idx_company_payment_modes_company ON company_payment_modes (company_id);

-- GL-mapping integrity: the mapped account must belong to the same company and be
-- postable (FK alone cannot enforce the company match).
CREATE OR REPLACE FUNCTION fn_company_payment_mode_gl_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_acct_company UUID;
  v_postable     BOOLEAN;
BEGIN
  SELECT company_id, is_postable INTO v_acct_company, v_postable
  FROM chart_of_accounts WHERE id = NEW.gl_account_id;

  IF v_acct_company IS NULL THEN
    RAISE EXCEPTION 'GL account % does not exist', NEW.gl_account_id USING ERRCODE = '23503';
  END IF;
  IF v_acct_company <> NEW.company_id THEN
    RAISE EXCEPTION 'payment-mode GL account must belong to the same company' USING ERRCODE = '23514';
  END IF;
  IF NOT v_postable THEN
    RAISE EXCEPTION 'payment-mode GL account must be postable' USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_company_payment_mode_gl_guard ON company_payment_modes;
CREATE TRIGGER trg_company_payment_mode_gl_guard
  BEFORE INSERT OR UPDATE ON company_payment_modes
  FOR EACH ROW EXECUTE FUNCTION fn_company_payment_mode_gl_guard();

DROP TRIGGER IF EXISTS trg_company_payment_modes_updated_at ON company_payment_modes;
CREATE TRIGGER trg_company_payment_modes_updated_at
  BEFORE UPDATE ON company_payment_modes
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

REVOKE ALL ON FUNCTION fn_company_payment_mode_gl_guard() FROM PUBLIC;
COMMENT ON TABLE company_payment_modes IS 'MDP-11 (MD-26): company-scoped payment modes mapping a global ref_payment_modes entry to a postable same-company GL account. Additive; ref_payment_modes and existing payment_mode_id FKs are untouched.';

-- ── 4. RLS — company-member gated (mirrors bank_accounts / employees) ─────────
ALTER TABLE company_payment_modes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "auth_read_company_payment_modes"   ON company_payment_modes;
DROP POLICY IF EXISTS "auth_insert_company_payment_modes" ON company_payment_modes;
DROP POLICY IF EXISTS "auth_update_company_payment_modes" ON company_payment_modes;
DROP POLICY IF EXISTS "auth_delete_company_payment_modes" ON company_payment_modes;
CREATE POLICY "auth_read_company_payment_modes"   ON company_payment_modes FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_insert_company_payment_modes" ON company_payment_modes FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "auth_update_company_payment_modes" ON company_payment_modes FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "auth_delete_company_payment_modes" ON company_payment_modes FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── 5. Audit coverage (reuse the MDP-02 fn_audit_trigger mechanism) ───────────
-- ref_banks is a static global read-only reference (like ref_payment_modes) and is
-- not trigger-audited. employees & bank_accounts are already covered, so the flag /
-- bank_id changes are captured. Only the new company-scoped master is added here.
DROP TRIGGER IF EXISTS trg_audit_company_payment_modes ON company_payment_modes;
CREATE TRIGGER trg_audit_company_payment_modes
  AFTER INSERT OR UPDATE OR DELETE ON company_payment_modes
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();
