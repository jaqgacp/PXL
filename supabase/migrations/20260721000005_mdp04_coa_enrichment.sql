-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-04 — Chart of Accounts Enrichment (gaps MD-09, MD-10, MD-11, MD-12, MD-13)
--
-- Upgrades `chart_of_accounts` into a production-ready ERP master by adding the
-- classification metadata needed for configurable statutory financial statements,
-- control-account/subledger governance, cash-flow reporting, cost classification,
-- and an effective-date window. All changes are ADDITIVE and backward-compatible:
--   * existing columns, posting logic, and RLS are untouched;
--   * every new column is nullable or defaulted, so existing INSERTs still work;
--   * backfill is deterministic and re-runnable (guarded WHERE the value is unset),
--     so re-apply never clobbers later manual classification.
--
-- Existing COA capabilities already present (NOT re-added): parent-child hierarchy
-- (`parent_id`), posting-vs-header (`is_postable`), normal balance, account type
-- (asset/liability/equity/revenue/expense), active lifecycle (`is_active`),
-- company scoping (`company_id` + unique code), currency, and audit coverage
-- (`fn_audit_trigger`, from MDP-02/earlier). This migration adds only the
-- genuinely missing classification metadata.
--
-- WHY each column:
--   MD-09 Financial-statement classification:
--     * fs_statement  — routes each account to the Balance Sheet or Income
--       Statement. Derivable purely from account_type, so it is a GENERATED STORED
--       column: always correct, never needs backfill or manual upkeep.
--     * fs_group      — primary FS grouping line (assets/liabilities/equity/
--       revenue/cost_of_sales/expenses/other_income/other_expenses) that drives
--       configurable statement grouping.
--     * fs_subgroup   — finer, free-text sub-line (e.g. "Current Assets",
--       "Cash and Cash Equivalents") the FS renderer can nest under fs_group.
--   MD-10 Control-account / subledger governance:
--     * is_control_account — this GL account is a summary/control account whose
--       detail is maintained in a subledger.
--     * allow_subledger    — postings should flow via a subledger, not manual GL.
--     * subledger_type     — which subledger reconciles to it (receivable/payable/
--       inventory/fixed_asset/bank/tax). Reconciled with company_accounting_config
--       by fn_sync_coa_control_accounts (below).
--   MD-11 Cash-flow classification:
--     * cash_flow_category — operating/investing/financing, for the cash-flow
--       statement (Phase 8). Backfilled to 'operating' for P&L accounts (the
--       indirect-method operating section starts from net income).
--   MD-12 Cost / tax classification flags:
--     * is_tax_account       — account holds a statutory tax balance (VAT/EWT).
--     * cost_behavior        — direct/indirect cost analysis.
--     * is_capitalizable     — expenditure that may be capitalized to an asset.
--     * is_operating_expense — operating-expense grouping for the Income Statement.
--   MD-13 Effective dating:
--     * effective_from / effective_to — account validity window. Columns +
--       constraint only; enforcement in the posting path is deliberately NOT wired
--       here (that would change posting logic) and is left to the Phase 8 posting/
--       reporting work — the capability exists without altering current posting.
--
-- Idempotent (ADD COLUMN IF NOT EXISTS, DROP/ADD CONSTRAINT, CREATE OR REPLACE,
-- guarded backfill). Forward-only. Rollback = drop the added columns/constraints/
-- function; no posted data is touched.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. MD-09 Financial-statement classification ───────────────────────────────
ALTER TABLE chart_of_accounts
  ADD COLUMN IF NOT EXISTS fs_statement TEXT
    GENERATED ALWAYS AS (
      CASE WHEN account_type IN ('asset','liability','equity')
           THEN 'balance_sheet' ELSE 'income_statement' END
    ) STORED,
  ADD COLUMN IF NOT EXISTS fs_group    TEXT,
  ADD COLUMN IF NOT EXISTS fs_subgroup TEXT;

-- ── 2. MD-10 Control-account / subledger governance ───────────────────────────
ALTER TABLE chart_of_accounts
  ADD COLUMN IF NOT EXISTS is_control_account BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS allow_subledger    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS subledger_type     TEXT;

-- ── 3. MD-11 Cash-flow classification ─────────────────────────────────────────
ALTER TABLE chart_of_accounts
  ADD COLUMN IF NOT EXISTS cash_flow_category TEXT;

-- ── 4. MD-12 Cost / tax classification flags ──────────────────────────────────
ALTER TABLE chart_of_accounts
  ADD COLUMN IF NOT EXISTS is_tax_account       BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS cost_behavior        TEXT,
  ADD COLUMN IF NOT EXISTS is_capitalizable     BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_operating_expense BOOLEAN NOT NULL DEFAULT false;

-- ── 5. MD-13 Effective-date window ────────────────────────────────────────────
ALTER TABLE chart_of_accounts
  ADD COLUMN IF NOT EXISTS effective_from DATE,
  ADD COLUMN IF NOT EXISTS effective_to   DATE;

-- ── 6. Vocabulary + sanity constraints (allow NULL for optional attributes) ────
ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_fs_group_check;
ALTER TABLE chart_of_accounts ADD  CONSTRAINT coa_fs_group_check CHECK (
  fs_group IS NULL OR fs_group IN (
    'assets','liabilities','equity','revenue',
    'cost_of_sales','expenses','other_income','other_expenses'));

ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_subledger_type_check;
ALTER TABLE chart_of_accounts ADD  CONSTRAINT coa_subledger_type_check CHECK (
  subledger_type IS NULL OR subledger_type IN (
    'receivable','payable','inventory','fixed_asset','bank','tax'));

ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_cash_flow_category_check;
ALTER TABLE chart_of_accounts ADD  CONSTRAINT coa_cash_flow_category_check CHECK (
  cash_flow_category IS NULL OR cash_flow_category IN ('operating','investing','financing'));

ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_cost_behavior_check;
ALTER TABLE chart_of_accounts ADD  CONSTRAINT coa_cost_behavior_check CHECK (
  cost_behavior IS NULL OR cost_behavior IN ('direct','indirect'));

ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_effective_window_check;
ALTER TABLE chart_of_accounts ADD  CONSTRAINT coa_effective_window_check CHECK (
  effective_from IS NULL OR effective_to IS NULL OR effective_to >= effective_from);

-- ── 7. Reusable control-account reconciliation (MD-10) ─────────────────────────
-- Sets the COA control/subledger/tax flags from company_accounting_config so the
-- flags stay consistent with the configured control accounts. Reused by this
-- migration's backfill and available to company-provisioning packages (MDP-05/07).
-- Never sets a flag to false, so manual designations on other accounts survive.
CREATE OR REPLACE FUNCTION fn_sync_coa_control_accounts(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  WITH cfg AS (
    SELECT * FROM company_accounting_config WHERE company_id = p_company_id
  ),
  mapping(account_id, sub, is_tax) AS (
    SELECT ar_account_id,                  'receivable', false FROM cfg WHERE ar_account_id IS NOT NULL
    UNION ALL SELECT ap_account_id,               'payable',    false FROM cfg WHERE ap_account_id IS NOT NULL
    UNION ALL SELECT customer_advances_account_id,'receivable', false FROM cfg WHERE customer_advances_account_id IS NOT NULL
    UNION ALL SELECT supplier_down_payments_account_id,'payable',false FROM cfg WHERE supplier_down_payments_account_id IS NOT NULL
    UNION ALL SELECT default_cash_account_id,      'bank',      false FROM cfg WHERE default_cash_account_id IS NOT NULL
    UNION ALL SELECT vat_payable_account_id,        'tax',      true  FROM cfg WHERE vat_payable_account_id IS NOT NULL
    UNION ALL SELECT input_vat_account_id,          'tax',      true  FROM cfg WHERE input_vat_account_id IS NOT NULL
    UNION ALL SELECT ewt_withheld_account_id,       'tax',      true  FROM cfg WHERE ewt_withheld_account_id IS NOT NULL
    UNION ALL SELECT ewt_payable_account_id,        'tax',      true  FROM cfg WHERE ewt_payable_account_id IS NOT NULL
  ),
  deduped AS (
    SELECT account_id,
           max(sub)         AS sub,        -- config accounts are distinct; max() is a stable tiebreak
           bool_or(is_tax)  AS is_tax
    FROM mapping
    GROUP BY account_id
  ),
  updated AS (
    UPDATE chart_of_accounts c
       SET is_control_account = true,
           allow_subledger    = true,
           subledger_type     = d.sub,
           is_tax_account     = c.is_tax_account OR d.is_tax
      FROM deduped d
     WHERE c.id = d.account_id
       AND c.company_id = p_company_id
    RETURNING 1
  )
  SELECT count(*)::INTEGER INTO v_count FROM updated;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION fn_sync_coa_control_accounts(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_sync_coa_control_accounts(UUID) TO service_role;

COMMENT ON FUNCTION fn_sync_coa_control_accounts(UUID) IS
  'Reconciles chart_of_accounts control/subledger/tax flags with company_accounting_config for a company (MDP-04, gap MD-10). Additive-only; reusable by company provisioning.';

-- ── 7b. Classification invariant: auto-default FS group / cash-flow on write ───
-- Makes FS classification a self-maintaining invariant of the master: every new
-- or edited account carries a valid fs_group so the financial statements can
-- always group it, while explicit (refined) values are preserved. Deterministic,
-- fills only NULLs, and never touches posting or amounts.
CREATE OR REPLACE FUNCTION fn_default_coa_classification()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.fs_group IS NULL THEN
    NEW.fs_group := CASE NEW.account_type
      WHEN 'asset'     THEN 'assets'
      WHEN 'liability' THEN 'liabilities'
      WHEN 'equity'    THEN 'equity'
      WHEN 'revenue'   THEN 'revenue'
      ELSE                  'expenses'
    END;
  END IF;
  IF NEW.cash_flow_category IS NULL
     AND NEW.account_type IN ('revenue','expense') THEN
    NEW.cash_flow_category := 'operating';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_default_coa_classification ON chart_of_accounts;
CREATE TRIGGER trg_default_coa_classification
  BEFORE INSERT OR UPDATE ON chart_of_accounts
  FOR EACH ROW EXECUTE FUNCTION fn_default_coa_classification();

-- ── 8. Deterministic, re-runnable backfill of existing accounts ───────────────
-- fs_group: coarse-but-always-correct bucket per account_type (users refine via
-- fs_subgroup); guarded so manual reclassification survives re-apply.
UPDATE chart_of_accounts
   SET fs_group = CASE account_type
     WHEN 'asset'     THEN 'assets'
     WHEN 'liability' THEN 'liabilities'
     WHEN 'equity'    THEN 'equity'
     WHEN 'revenue'   THEN 'revenue'
     ELSE                  'expenses'
   END
 WHERE fs_group IS NULL;

-- cash_flow_category: P&L accounts feed the operating section (indirect method).
UPDATE chart_of_accounts
   SET cash_flow_category = 'operating'
 WHERE cash_flow_category IS NULL
   AND account_type IN ('revenue','expense');

-- Control/subledger/tax flags: reconcile every configured company's COA.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT DISTINCT company_id FROM company_accounting_config LOOP
    PERFORM fn_sync_coa_control_accounts(r.company_id);
  END LOOP;
END;
$$;

COMMENT ON COLUMN chart_of_accounts.fs_statement IS 'MD-09: Balance Sheet vs Income Statement, generated from account_type.';
COMMENT ON COLUMN chart_of_accounts.fs_group     IS 'MD-09: primary financial-statement grouping line.';
COMMENT ON COLUMN chart_of_accounts.is_control_account IS 'MD-10: summary/control account whose detail lives in a subledger.';
COMMENT ON COLUMN chart_of_accounts.cash_flow_category IS 'MD-11: operating/investing/financing for the cash-flow statement.';
COMMENT ON COLUMN chart_of_accounts.effective_from IS 'MD-13: account validity window start (enforcement deferred to Phase 8 posting/reporting).';
