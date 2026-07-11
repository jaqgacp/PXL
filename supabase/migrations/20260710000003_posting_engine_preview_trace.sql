-- Shared posting invariants, exact GL preview, and accounting trace contracts.
-- Implements PXL-DA-001 and lays a narrowed foundation for PXL-DA-002 / 004.

CREATE TABLE ref_posting_source_types (
  document_type TEXT PRIMARY KEY,
  source_table REGCLASS,
  document_number_column NAME,
  document_date_column NAME,
  status_column NAME,
  route_path TEXT NOT NULL,
  display_name TEXT NOT NULL,
  allows_multiple_journal_entries BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true
);

INSERT INTO ref_posting_source_types (
  document_type, source_table, document_number_column, document_date_column,
  status_column, route_path, display_name, allows_multiple_journal_entries
) VALUES
  ('SI',        'sales_invoices',                 'si_number',         'date',               'status', '/sales-invoices',              'Sales Invoice', false),
  ('OR',        'receipts',                       'receipt_number',    'receipt_date',       'status', '/receipts',                    'Receipt', false),
  ('CM',        'credit_memos',                   'cm_number',         'cm_date',            'status', '/credit-memos',                'Credit Memo', false),
  ('DM',        'debit_memos',                    'dm_number',         'dm_date',            'status', '/debit-memos',                 'Debit Memo', false),
  ('VB',        'vendor_bills',                   'bill_number',       'bill_date',          'status', '/vendor-bills',                'Vendor Bill', false),
  ('PV',        'payment_vouchers',               'voucher_number',    'voucher_date',       'status', '/payment-vouchers',            'Payment Voucher', false),
  ('CP',        'cash_purchases',                 'cp_number',         'transaction_date',   'status', '/cash-purchases',              'Cash Purchase', false),
  ('VC',        'vendor_credits',                 'vc_number',         'credit_date',        'status', '/vendor-credits',              'Vendor Credit', false),
  ('PR',        'purchase_returns',               'return_number',     'return_date',        'status', '/purchase-returns',            'Purchase Return', false),
  ('FT',        'fund_transfers',                 'ft_number',         'transfer_date',      'status', '/fund-transfers',              'Fund Transfer', false),
  ('IBT',       'inter_branch_transfers',         'ibt_number',        'transfer_date',      'status', '/inter-branch-transfers',       'Inter-Branch Transfer', false),
  ('BADJ',      'bank_adjustments',               'ba_number',         'adjustment_date',    'status', '/bank-adjustments',            'Bank Adjustment', false),
  ('PCV',       'petty_cash_vouchers',            'pcv_number',        'voucher_date',       'status', '/petty-cash-vouchers',         'Petty Cash Voucher', false),
  ('PCR',       'petty_cash_replenishments',      'pcr_number',        'replenishment_date', 'status', '/petty-cash-replenishment',    'Petty Cash Replenishment', false),
  ('CV',        'check_vouchers',                 'cv_number',         'voucher_date',       'status', '/check-vouchers',              'Check Voucher', false),
  ('INV_ADJ',   'stock_adjustments',              'adjustment_number', 'adjustment_date',    'status', '/stock-adjustment',            'Stock Adjustment', false),
  ('INV_STX',   'stock_transfers',                'transfer_number',   'transfer_date',      'status', '/stock-transfer',              'Stock Transfer', false),
  ('INV_GI',    'goods_issues',                   'issue_number',      'issue_date',         'status', '/goods-issue',                 'Goods Issue', false),
  ('INV_COUNT', 'physical_count_sheets',          'count_number',      'count_date',         'status', '/physical-count',              'Physical Count', false),
  ('FA',        'fixed_assets',                   'asset_number',      'acquisition_date',   'status', '/asset-register',              'Fixed Asset Acquisition', false),
  ('FA_DEPR',   'asset_depreciation_entries',     'period_number',     'entry_date',         'status', '/depreciation-run',            'Fixed Asset Depreciation', false),
  ('FA_DISP',   'asset_disposals',                'asset_id',          'disposal_date',      NULL,     '/asset-disposal',             'Fixed Asset Disposal', false),
  ('FA_IMP',    'asset_impairments',              'asset_id',          'impairment_date',    NULL,     '/asset-impairment',           'Fixed Asset Impairment', false),
  ('AMORT',     'amortization_entries',            'period_number',     'entry_date',         'status', '/amortization-run',           'Amortization Entry', false),
  ('REVREC',    'revenue_recognition_entries',     'period_number',     'entry_date',         'status', '/revenue-recognition-run',     'Revenue Recognition Entry', false),
  ('MANUAL',    'journal_entries',                'je_number',         'je_date',            'status', '/journal-entries',             'Manual Journal Entry', true),
  ('RECURRING', 'recurring_journal_templates',    'template_name',     NULL,                 'status', '/recurring-journal-templates', 'Recurring Journal', true),
  ('REV',       NULL,                             NULL,                NULL,                 NULL,     '/reversal-review',             'Reversal', true);

ALTER TABLE ref_posting_source_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY ref_posting_source_types_read
  ON ref_posting_source_types FOR SELECT TO authenticated USING (true);
GRANT SELECT ON ref_posting_source_types TO authenticated;

ALTER TABLE journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_reference_doc_type_check;

ALTER TABLE journal_entries
  ADD CONSTRAINT journal_entries_reference_doc_type_fkey
  FOREIGN KEY (reference_doc_type)
  REFERENCES ref_posting_source_types(document_type);

-- Fixed-asset writers create the journal before the source row, so their
-- historical functions could only populate the source type. Attach the
-- durable source id when the source row is inserted/updated. This also makes
-- preview/trace lookup use the actual depreciation entry rather than the
-- parent asset, which can have many depreciation journals.
CREATE OR REPLACE FUNCTION fn_link_fixed_asset_journal_source()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je_id UUID;
BEGIN
  v_je_id := CASE TG_TABLE_NAME
    WHEN 'fixed_assets'
      THEN NULLIF(to_jsonb(NEW)->>'acquisition_je_id', '')::UUID
    WHEN 'asset_depreciation_entries'
      THEN NULLIF(to_jsonb(NEW)->>'journal_entry_id', '')::UUID
    WHEN 'asset_disposals'
      THEN NULLIF(to_jsonb(NEW)->>'journal_entry_id', '')::UUID
    WHEN 'asset_impairments'
      THEN NULLIF(to_jsonb(NEW)->>'journal_entry_id', '')::UUID
  END;

  IF v_je_id IS NOT NULL THEN
    UPDATE journal_entries
    SET reference_doc_id = NEW.id,
        updated_at = NOW()
    WHERE id = v_je_id
      AND reference_doc_id IS DISTINCT FROM NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_link_fixed_asset_acquisition_je ON fixed_assets;
CREATE TRIGGER trg_link_fixed_asset_acquisition_je
  AFTER INSERT OR UPDATE OF acquisition_je_id ON fixed_assets
  FOR EACH ROW EXECUTE FUNCTION fn_link_fixed_asset_journal_source();

DROP TRIGGER IF EXISTS trg_link_fixed_asset_depreciation_je ON asset_depreciation_entries;
CREATE TRIGGER trg_link_fixed_asset_depreciation_je
  AFTER INSERT OR UPDATE OF journal_entry_id ON asset_depreciation_entries
  FOR EACH ROW EXECUTE FUNCTION fn_link_fixed_asset_journal_source();

DROP TRIGGER IF EXISTS trg_link_fixed_asset_disposal_je ON asset_disposals;
CREATE TRIGGER trg_link_fixed_asset_disposal_je
  AFTER INSERT OR UPDATE OF journal_entry_id ON asset_disposals
  FOR EACH ROW EXECUTE FUNCTION fn_link_fixed_asset_journal_source();

DROP TRIGGER IF EXISTS trg_link_fixed_asset_impairment_je ON asset_impairments;
CREATE TRIGGER trg_link_fixed_asset_impairment_je
  AFTER INSERT OR UPDATE OF journal_entry_id ON asset_impairments
  FOR EACH ROW EXECUTE FUNCTION fn_link_fixed_asset_journal_source();

CREATE OR REPLACE FUNCTION fn_link_schedule_journal_source()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT;
BEGIN
  v_type := CASE TG_TABLE_NAME
    WHEN 'amortization_entries' THEN 'AMORT'
    WHEN 'revenue_recognition_entries' THEN 'REVREC'
  END;

  IF NEW.je_id IS NOT NULL THEN
    UPDATE journal_entries
    SET reference_doc_type = v_type,
        reference_doc_id = NEW.id,
        updated_at = NOW()
    WHERE id = NEW.je_id
      AND (reference_doc_type IS DISTINCT FROM v_type OR reference_doc_id IS DISTINCT FROM NEW.id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_link_amortization_entry_je ON amortization_entries;
CREATE TRIGGER trg_link_amortization_entry_je
  AFTER INSERT OR UPDATE OF je_id ON amortization_entries
  FOR EACH ROW EXECUTE FUNCTION fn_link_schedule_journal_source();

DROP TRIGGER IF EXISTS trg_link_revenue_recognition_entry_je ON revenue_recognition_entries;
CREATE TRIGGER trg_link_revenue_recognition_entry_je
  AFTER INSERT OR UPDATE OF je_id ON revenue_recognition_entries
  FOR EACH ROW EXECUTE FUNCTION fn_link_schedule_journal_source();

CREATE OR REPLACE FUNCTION fn_link_purchase_return_journal_source()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.journal_entry_id IS NOT NULL THEN
    UPDATE journal_entries
    SET reference_doc_type = 'PR',
        reference_doc_id = NEW.id,
        updated_at = NOW()
    WHERE id = NEW.journal_entry_id
      AND (reference_doc_type IS DISTINCT FROM 'PR' OR reference_doc_id IS DISTINCT FROM NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_link_purchase_return_je ON purchase_returns;
CREATE TRIGGER trg_link_purchase_return_je
  AFTER INSERT OR UPDATE OF journal_entry_id ON purchase_returns
  FOR EACH ROW EXECUTE FUNCTION fn_link_purchase_return_journal_source();

-- Backfill source links for any fixed-asset journals that predate the trigger.
-- The status immutability guard also protects journal_entries, so bypass only
-- user triggers for this one migration-owned evidence repair.
SET session_replication_role = replica;

UPDATE journal_entries je
SET reference_doc_id = fa.id,
    updated_at = NOW()
FROM fixed_assets fa
WHERE je.id = fa.acquisition_je_id
  AND je.reference_doc_type = 'FA'
  AND je.reference_doc_id IS DISTINCT FROM fa.id;

UPDATE journal_entries je
SET reference_doc_id = ade.id,
    updated_at = NOW()
FROM asset_depreciation_entries ade
WHERE je.id = ade.journal_entry_id
  AND je.reference_doc_type = 'FA_DEPR'
  AND je.reference_doc_id IS DISTINCT FROM ade.id;

UPDATE journal_entries je
SET reference_doc_id = ad.id,
    updated_at = NOW()
FROM asset_disposals ad
WHERE je.id = ad.journal_entry_id
  AND je.reference_doc_type = 'FA_DISP'
  AND je.reference_doc_id IS DISTINCT FROM ad.id;

UPDATE journal_entries je
SET reference_doc_id = ai.id,
    updated_at = NOW()
FROM asset_impairments ai
WHERE je.id = ai.journal_entry_id
  AND je.reference_doc_type = 'FA_IMP'
  AND je.reference_doc_id IS DISTINCT FROM ai.id;

UPDATE journal_entries je
SET reference_doc_type = 'AMORT',
    reference_doc_id = ae.id,
    updated_at = NOW()
FROM amortization_entries ae
WHERE je.id = ae.je_id
  AND (je.reference_doc_type IS DISTINCT FROM 'AMORT' OR je.reference_doc_id IS DISTINCT FROM ae.id);

UPDATE journal_entries je
SET reference_doc_type = 'REVREC',
    reference_doc_id = rre.id,
    updated_at = NOW()
FROM revenue_recognition_entries rre
WHERE je.id = rre.je_id
  AND (je.reference_doc_type IS DISTINCT FROM 'REVREC' OR je.reference_doc_id IS DISTINCT FROM rre.id);

UPDATE journal_entries je
SET reference_doc_type = 'PR',
    reference_doc_id = pr.id,
    updated_at = NOW()
FROM purchase_returns pr
WHERE je.id = pr.journal_entry_id
  AND (je.reference_doc_type IS DISTINCT FROM 'PR' OR je.reference_doc_id IS DISTINCT FROM pr.id);

SET session_replication_role = origin;

-- One live original JE per one-shot source. Recurring templates and legacy
-- fixed-asset writers are excluded because they do not supply a stable source
-- id when the journal row is first inserted; their trace links are maintained
-- separately above.
CREATE UNIQUE INDEX ux_journal_entries_live_source
  ON journal_entries (company_id, reference_doc_type, reference_doc_id)
  WHERE reference_doc_id IS NOT NULL
    AND status IN ('posted', 'reversed')
    AND je_number NOT LIKE '%-REV-%'
    AND je_number NOT LIKE 'JE-VOID-%'
    AND reference_doc_type IN (
      'SI','OR','CM','DM','VB','PV','CP','VC','FT','IBT','BADJ','PCV','PCR','CV',
      'PR','INV_ADJ','INV_STX','INV_GI','INV_COUNT','AMORT','REVREC'
    );

CREATE OR REPLACE FUNCTION fn_require_open_fiscal_period(
  p_company_id UUID,
  p_posting_date DATE,
  p_lock BOOLEAN DEFAULT true
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_id UUID;
BEGIN
  IF p_company_id IS NULL OR p_posting_date IS NULL THEN
    RAISE EXCEPTION 'Company and posting date are required';
  END IF;

  IF p_lock THEN
    SELECT id INTO v_period_id
    FROM fiscal_periods
    WHERE company_id = p_company_id
      AND start_date <= p_posting_date
      AND end_date >= p_posting_date
      AND is_locked = false
    ORDER BY start_date DESC
    LIMIT 1
    FOR UPDATE;
  ELSE
    SELECT id INTO v_period_id
    FROM fiscal_periods
    WHERE company_id = p_company_id
      AND start_date <= p_posting_date
      AND end_date >= p_posting_date
      AND is_locked = false
    ORDER BY start_date DESC
    LIMIT 1;
  END IF;

  IF v_period_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period covers posting date %', p_posting_date;
  END IF;

  RETURN v_period_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_postable_account(
  p_company_id UUID,
  p_account_id UUID,
  p_context TEXT DEFAULT 'Posting account'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_account_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM chart_of_accounts
    WHERE id = p_account_id
      AND company_id = p_company_id
      AND is_active = true
      AND is_postable = true
  ) THEN
    RAISE EXCEPTION '% must be an active postable account in the posting company', p_context;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_create_posted_journal_entry(
  p_company_id UUID,
  p_branch_id UUID,
  p_je_number TEXT,
  p_je_date DATE,
  p_description TEXT,
  p_reference_doc_type TEXT,
  p_reference_doc_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_id UUID;
  v_je_id UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  v_period_id := fn_require_open_fiscal_period(p_company_id, p_je_date, true);

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    p_company_id, p_branch_id, p_je_number, p_je_date, v_period_id,
    p_description, p_reference_doc_type, p_reference_doc_id, 'posted',
    0, 0, auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_add_posting_line(
  p_je_id UUID,
  p_line_number INTEGER,
  p_account_id UUID,
  p_description TEXT,
  p_debit NUMERIC DEFAULT 0,
  p_credit NUMERIC DEFAULT 0,
  p_branch_id UUID DEFAULT NULL,
  p_department_id UUID DEFAULT NULL,
  p_cost_center_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_line_id UUID;
BEGIN
  SELECT company_id INTO v_company_id
  FROM journal_entries
  WHERE id = p_je_id
  FOR UPDATE;

  IF v_company_id IS NULL OR NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Journal entry not found or access denied';
  END IF;

  PERFORM fn_require_postable_account(v_company_id, p_account_id, 'Journal line account');

  IF COALESCE(p_debit, 0) < 0 OR COALESCE(p_credit, 0) < 0
     OR (COALESCE(p_debit, 0) > 0) = (COALESCE(p_credit, 0) > 0) THEN
    RAISE EXCEPTION 'A journal line must contain exactly one positive debit or credit amount';
  END IF;

  INSERT INTO journal_entry_lines (
    je_id, company_id, line_number, account_id, description,
    debit_amount, credit_amount, branch_id, department_id, cost_center_id,
    created_by, updated_by
  ) VALUES (
    p_je_id, v_company_id, p_line_number, p_account_id, p_description,
    COALESCE(p_debit, 0), COALESCE(p_credit, 0),
    p_branch_id, p_department_id, p_cost_center_id,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_line_id;

  RETURN v_line_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_finalize_journal_entry(p_je_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je journal_entries%ROWTYPE;
  v_debit NUMERIC(15,2);
  v_credit NUMERIC(15,2);
  v_line_count INTEGER;
BEGIN
  SELECT * INTO v_je
  FROM journal_entries
  WHERE id = p_je_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Journal entry not found';
  END IF;

  SELECT
    COALESCE(ROUND(SUM(debit_amount), 2), 0),
    COALESCE(ROUND(SUM(credit_amount), 2), 0),
    COUNT(*)
  INTO v_debit, v_credit, v_line_count
  FROM journal_entry_lines
  WHERE je_id = p_je_id;

  IF v_line_count = 0 THEN
    IF v_je.reference_doc_type = 'INV_COUNT'
       AND COALESCE(v_je.total_debit, 0) = 0
       AND COALESCE(v_je.total_credit, 0) = 0 THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Posted journal entry % has no lines', v_je.je_number;
  END IF;

  IF ABS(v_debit - v_credit) > 0.01 THEN
    RAISE EXCEPTION 'Journal entry % is unbalanced: debit % <> credit %',
      v_je.je_number, v_debit, v_credit;
  END IF;

  IF v_debit <= 0 THEN
    RAISE EXCEPTION 'Journal entry % has no financial amount', v_je.je_number;
  END IF;

  IF COALESCE(v_je.total_debit, 0) <> v_debit
     OR COALESCE(v_je.total_credit, 0) <> v_credit THEN
    UPDATE journal_entries
    SET total_debit = v_debit,
        total_credit = v_credit,
        updated_at = NOW()
    WHERE id = p_je_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_guard_journal_entry_posting()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_id UUID;
BEGIN
  IF NEW.branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches
    WHERE id = NEW.branch_id AND company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'Journal entry branch does not belong to the posting company';
  END IF;

  IF NEW.status = 'posted' AND TG_OP = 'INSERT' THEN
    v_period_id := fn_require_open_fiscal_period(NEW.company_id, NEW.je_date, false);
    IF NEW.fiscal_period_id IS DISTINCT FROM v_period_id THEN
      RAISE EXCEPTION 'Journal entry fiscal period does not match posting date %', NEW.je_date;
    END IF;
  ELSIF NEW.status = 'posted' AND (
    OLD.status IS DISTINCT FROM NEW.status
    OR OLD.je_date IS DISTINCT FROM NEW.je_date
    OR OLD.fiscal_period_id IS DISTINCT FROM NEW.fiscal_period_id
    OR OLD.company_id IS DISTINCT FROM NEW.company_id
  ) THEN
    v_period_id := fn_require_open_fiscal_period(NEW.company_id, NEW.je_date, false);
    IF NEW.fiscal_period_id IS DISTINCT FROM v_period_id THEN
      RAISE EXCEPTION 'Journal entry fiscal period does not match posting date %', NEW.je_date;
    END IF;
  END IF;

  IF COALESCE(NEW.total_debit, 0) < 0 OR COALESCE(NEW.total_credit, 0) < 0 THEN
    RAISE EXCEPTION 'Journal entry totals cannot be negative';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_journal_entry_posting_guard ON journal_entries;
CREATE TRIGGER trg_journal_entry_posting_guard
  BEFORE INSERT OR UPDATE OF company_id, branch_id, je_date, fiscal_period_id, status, total_debit, total_credit
  ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION fn_guard_journal_entry_posting();

CREATE OR REPLACE FUNCTION fn_guard_journal_entry_line()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id
  FROM journal_entries
  WHERE id = NEW.je_id;

  IF v_company_id IS NULL OR NEW.company_id IS DISTINCT FROM v_company_id THEN
    RAISE EXCEPTION 'Journal line company must match its journal entry';
  END IF;

  PERFORM fn_require_postable_account(v_company_id, NEW.account_id, 'Journal line account');

  IF COALESCE(NEW.debit_amount, 0) < 0 OR COALESCE(NEW.credit_amount, 0) < 0
     OR (COALESCE(NEW.debit_amount, 0) > 0) = (COALESCE(NEW.credit_amount, 0) > 0) THEN
    RAISE EXCEPTION 'A journal line must contain exactly one positive debit or credit amount';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_journal_entry_line_posting_guard ON journal_entry_lines;
CREATE TRIGGER trg_journal_entry_line_posting_guard
  BEFORE INSERT OR UPDATE OF je_id, company_id, account_id, debit_amount, credit_amount
  ON journal_entry_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_journal_entry_line();

CREATE OR REPLACE FUNCTION fn_enforce_journal_entry_balanced()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je_id UUID;
  v_status TEXT;
BEGIN
  IF TG_TABLE_NAME = 'journal_entries' THEN
    v_je_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
  ELSE
    v_je_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.je_id ELSE NEW.je_id END;
  END IF;

  SELECT status INTO v_status FROM journal_entries WHERE id = v_je_id;
  IF v_status IN ('posted', 'reversed') THEN
    PERFORM fn_finalize_journal_entry(v_je_id);
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_journal_entry_balanced_deferred ON journal_entries;
CREATE CONSTRAINT TRIGGER trg_journal_entry_balanced_deferred
  AFTER INSERT OR UPDATE OF status, total_debit, total_credit
  ON journal_entries
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_journal_entry_balanced();

DROP TRIGGER IF EXISTS trg_journal_line_balanced_deferred ON journal_entry_lines;
CREATE CONSTRAINT TRIGGER trg_journal_line_balanced_deferred
  AFTER INSERT OR UPDATE OR DELETE
  ON journal_entry_lines
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_journal_entry_balanced();

CREATE OR REPLACE FUNCTION fn_gl_impact_payload(
  p_je_id UUID,
  p_mode TEXT DEFAULT 'posted',
  p_rule_explanation TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je journal_entries%ROWTYPE;
  v_lines JSONB;
  v_period_name TEXT;
  v_branch_name TEXT;
  v_source_route TEXT;
  v_display_name TEXT;
BEGIN
  SELECT * INTO v_je FROM journal_entries WHERE id = p_je_id;
  IF NOT FOUND OR NOT is_company_member(v_je.company_id) THEN
    RAISE EXCEPTION 'Journal entry not found or access denied';
  END IF;

  SELECT period_name INTO v_period_name FROM fiscal_periods WHERE id = v_je.fiscal_period_id;
  SELECT branch_name INTO v_branch_name FROM branches WHERE id = v_je.branch_id;
  SELECT route_path, display_name INTO v_source_route, v_display_name
  FROM ref_posting_source_types
  WHERE document_type = v_je.reference_doc_type;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'line_number', jel.line_number,
    'account_id', jel.account_id,
    'account_code', coa.account_code,
    'account_name', coa.account_name,
    'account_source', CASE
      WHEN jel.account_id = cfg.ar_account_id THEN 'company_accounting_config.ar_account_id'
      WHEN jel.account_id = cfg.ap_account_id THEN 'company_accounting_config.ap_account_id'
      WHEN jel.account_id = cfg.vat_payable_account_id THEN 'company_accounting_config.vat_payable_account_id'
      WHEN jel.account_id = cfg.input_vat_account_id THEN 'company_accounting_config.input_vat_account_id'
      WHEN jel.account_id = cfg.ewt_withheld_account_id THEN 'company_accounting_config.ewt_withheld_account_id'
      WHEN jel.account_id = cfg.ewt_payable_account_id THEN 'company_accounting_config.ewt_payable_account_id'
      WHEN jel.account_id = cfg.default_cash_account_id THEN 'company_accounting_config.default_cash_account_id'
      ELSE 'document or module posting rule'
    END,
    'description', jel.description,
    'debit', jel.debit_amount,
    'credit', jel.credit_amount,
    'branch_id', jel.branch_id,
    'department_id', jel.department_id,
    'cost_center_id', jel.cost_center_id
  ) ORDER BY jel.line_number), '[]'::jsonb)
  INTO v_lines
  FROM journal_entry_lines jel
  JOIN chart_of_accounts coa ON coa.id = jel.account_id
  LEFT JOIN company_accounting_config cfg ON cfg.company_id = v_je.company_id
  WHERE jel.je_id = v_je.id;

  RETURN jsonb_build_object(
    'mode', p_mode,
    'journal_entry_id', CASE WHEN p_mode = 'posted' THEN v_je.id ELSE NULL END,
    'je_number', CASE WHEN p_mode = 'posted' THEN v_je.je_number ELSE NULL END,
    'posting_date', v_je.je_date,
    'fiscal_period_id', v_je.fiscal_period_id,
    'fiscal_period_name', v_period_name,
    'branch_id', v_je.branch_id,
    'branch_name', v_branch_name,
    'source_doc_type', v_je.reference_doc_type,
    'source_doc_id', v_je.reference_doc_id,
    'source_display_name', v_display_name,
    'source_route', CASE WHEN v_source_route IS NOT NULL AND v_je.reference_doc_id IS NOT NULL
                         THEN v_source_route || '?id=' || v_je.reference_doc_id::text
                         ELSE v_source_route END,
    'rule_explanation', COALESCE(p_rule_explanation,
      'Posted journal lines are the authoritative accounting impact.'),
    'total_debit', v_je.total_debit,
    'total_credit', v_je.total_credit,
    'balanced', ABS(v_je.total_debit - v_je.total_credit) <= 0.01,
    'lines', v_lines
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_preview_gl_impact(
  p_source_doc_type TEXT,
  p_source_doc_id UUID,
  p_posting_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(p_source_doc_type));
  v_je_id UUID;
  v_payload JSONB;
  v_message TEXT;
  v_effective_posting_date DATE;
  v_marker CONSTANT TEXT := '__PXL_GL_PREVIEW_ROLLBACK__';
BEGIN
  IF p_source_doc_id IS NULL THEN
    RAISE EXCEPTION 'A saved source document is required for server-side GL preview';
  END IF;

  IF v_type <> 'RECURRING' THEN
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE reference_doc_type = v_type
      AND reference_doc_id = p_source_doc_id
      AND status IN ('posted', 'reversed')
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  IF v_je_id IS NOT NULL THEN
    RETURN fn_gl_impact_payload(v_je_id, 'posted', NULL);
  END IF;

  BEGIN
    CASE v_type
      WHEN 'SI'        THEN PERFORM fn_post_sales_invoice(p_source_doc_id);
      WHEN 'OR'        THEN PERFORM fn_post_receipt(p_source_doc_id);
      WHEN 'CM'        THEN PERFORM fn_post_credit_memo(p_source_doc_id);
      WHEN 'DM'        THEN PERFORM fn_post_debit_memo(p_source_doc_id);
      WHEN 'VB'        THEN PERFORM fn_post_vendor_bill(p_source_doc_id);
      WHEN 'PV'        THEN PERFORM fn_post_payment_voucher(p_source_doc_id);
      WHEN 'CP'        THEN PERFORM fn_post_cash_purchase(p_source_doc_id);
      WHEN 'VC'        THEN PERFORM fn_post_vendor_credit(p_source_doc_id);
      WHEN 'PR'        THEN PERFORM fn_complete_purchase_return(p_source_doc_id);
      WHEN 'FT'        THEN PERFORM fn_post_fund_transfer(p_source_doc_id);
      WHEN 'IBT'       THEN PERFORM fn_post_inter_branch_transfer(p_source_doc_id);
      WHEN 'BADJ'      THEN PERFORM fn_post_bank_adjustment(p_source_doc_id);
      WHEN 'PCV'       THEN PERFORM fn_approve_petty_cash_voucher(p_source_doc_id);
      WHEN 'PCR'       THEN PERFORM fn_post_petty_cash_replenishment(p_source_doc_id);
      WHEN 'CV'        THEN PERFORM fn_post_check_voucher(p_source_doc_id);
      WHEN 'INV_ADJ'   THEN v_je_id := fn_post_stock_adjustment(p_source_doc_id);
      WHEN 'INV_STX'   THEN v_je_id := fn_post_stock_transfer(p_source_doc_id);
      WHEN 'INV_GI'    THEN v_je_id := fn_post_goods_issue(p_source_doc_id);
      WHEN 'INV_COUNT' THEN v_je_id := fn_post_physical_count(p_source_doc_id);
      WHEN 'FA_DEPR'   THEN v_je_id := fn_post_depreciation_entry(p_source_doc_id);
      WHEN 'AMORT'     THEN v_je_id := fn_post_amortization_entry(p_source_doc_id);
      WHEN 'REVREC'    THEN v_je_id := fn_post_revenue_recognition_entry(p_source_doc_id);
      WHEN 'RECURRING' THEN
        SELECT COALESCE(p_posting_date, next_run_date, start_date, CURRENT_DATE)
        INTO v_effective_posting_date
        FROM recurring_journal_templates
        WHERE id = p_source_doc_id;
        IF v_effective_posting_date IS NULL THEN
          RAISE EXCEPTION 'Recurring journal template not found';
        END IF;
        v_je_id := fn_execute_recurring_template(p_source_doc_id, v_effective_posting_date);
      ELSE RAISE EXCEPTION 'GL preview is not supported for source type %', v_type;
    END CASE;

    IF v_je_id IS NULL THEN
      SELECT id INTO v_je_id
      FROM journal_entries
      WHERE reference_doc_type = v_type
        AND reference_doc_id = p_source_doc_id
        AND status = 'posted'
      ORDER BY created_at DESC
      LIMIT 1;
    END IF;

    IF v_je_id IS NULL THEN
      v_payload := jsonb_build_object(
        'mode', 'preview',
        'source_doc_type', v_type,
        'source_doc_id', p_source_doc_id,
        'total_debit', 0,
        'total_credit', 0,
        'balanced', true,
        'rule_explanation', 'This transaction has no GL impact under its current posting rules.',
        'lines', '[]'::jsonb
      );
    ELSE
      PERFORM fn_finalize_journal_entry(v_je_id);
      v_payload := fn_gl_impact_payload(
        v_je_id,
        'preview',
        'Exact rollback preview: the source posting RPC was executed inside a database subtransaction and fully rolled back.'
      );
    END IF;

    RAISE EXCEPTION USING MESSAGE = v_marker, ERRCODE = 'P0001';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> v_marker THEN
      RAISE;
    END IF;
  END;

  RETURN v_payload;
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_accounting_trace(
  p_source_doc_type TEXT DEFAULT NULL,
  p_source_doc_id UUID DEFAULT NULL,
  p_journal_entry_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := NULLIF(UPPER(BTRIM(COALESCE(p_source_doc_type, ''))), '');
  v_je_id UUID := p_journal_entry_id;
  v_je journal_entries%ROWTYPE;
  v_ref ref_posting_source_types%ROWTYPE;
  v_source JSONB;
  v_source_company UUID;
  v_source_number TEXT;
  v_source_date DATE;
  v_source_status TEXT;
  v_sql TEXT;
  v_audit JSONB;
BEGIN
  IF v_je_id IS NULL AND v_type IS NOT NULL AND p_source_doc_id IS NOT NULL THEN
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE reference_doc_type = v_type
      AND reference_doc_id = p_source_doc_id
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  IF v_je_id IS NOT NULL THEN
    SELECT * INTO v_je FROM journal_entries WHERE id = v_je_id;
    IF NOT FOUND OR NOT is_company_member(v_je.company_id) THEN
      RAISE EXCEPTION 'Journal entry not found or access denied';
    END IF;

    IF v_type IS NOT NULL AND v_type IS DISTINCT FROM v_je.reference_doc_type THEN
      RAISE EXCEPTION 'Journal entry source type does not match the requested accounting source';
    END IF;
    IF p_source_doc_id IS NOT NULL
       AND v_je.reference_doc_id IS NOT NULL
       AND p_source_doc_id IS DISTINCT FROM v_je.reference_doc_id THEN
      RAISE EXCEPTION 'Journal entry source id does not match the requested accounting source';
    END IF;

    v_type := COALESCE(v_type, v_je.reference_doc_type);
    p_source_doc_id := COALESCE(p_source_doc_id, v_je.reference_doc_id);
    IF v_type = 'MANUAL' AND p_source_doc_id IS NULL THEN
      p_source_doc_id := v_je.id;
    END IF;
  END IF;

  SELECT * INTO v_ref
  FROM ref_posting_source_types
  WHERE document_type = v_type AND is_active = true;

  IF v_ref.document_type IS NULL THEN
    RAISE EXCEPTION 'Unknown accounting source type %', COALESCE(v_type, '<null>');
  END IF;

  IF v_ref.source_table IS NOT NULL AND p_source_doc_id IS NOT NULL THEN
    v_sql := format('SELECT to_jsonb(t) FROM %s t WHERE t.id = $1', v_ref.source_table);
    EXECUTE v_sql INTO v_source USING p_source_doc_id;

    IF v_source IS NOT NULL THEN
      v_source_company := NULLIF(v_source->>'company_id', '')::UUID;
      IF v_source_company IS NOT NULL AND NOT is_company_member(v_source_company) THEN
        RAISE EXCEPTION 'Accounting source not found or access denied';
      END IF;
      IF v_ref.document_number_column IS NOT NULL THEN
        v_source_number := v_source->>v_ref.document_number_column::text;
      END IF;
      IF v_ref.document_date_column IS NOT NULL THEN
        v_source_date := NULLIF(v_source->>v_ref.document_date_column::text, '')::DATE;
      END IF;
      IF v_ref.status_column IS NOT NULL THEN
        v_source_status := v_source->>v_ref.status_column::text;
      END IF;
    END IF;
  END IF;

  IF v_source IS NULL AND v_je_id IS NULL THEN
    RAISE EXCEPTION 'Accounting source not found or access denied';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'action', action,
    'changed_by', changed_by,
    'changed_at', changed_at
  ) ORDER BY changed_at DESC), '[]'::jsonb)
  INTO v_audit
  FROM sys_audit_logs
  WHERE record_id = p_source_doc_id
    AND company_id = COALESCE(v_source_company, v_je.company_id);

  RETURN jsonb_build_object(
    'source_doc_type', v_type,
    'source_doc_id', p_source_doc_id,
    'source_display_name', v_ref.display_name,
    'source_number', v_source_number,
    'source_date', v_source_date,
    'source_status', v_source_status,
    'source_route', CASE WHEN p_source_doc_id IS NOT NULL
                         THEN v_ref.route_path || '?id=' || p_source_doc_id::text
                         ELSE v_ref.route_path END,
    'journal_entry_id', v_je_id,
    'journal_route', CASE WHEN v_je_id IS NOT NULL
                          THEN '/journal-entries?jeId=' || v_je_id::text END,
    'general_ledger_route', CASE WHEN v_je_id IS NOT NULL
                                 THEN '/general-ledger?jeId=' || v_je_id::text END,
    'gl_impact', CASE WHEN v_je_id IS NOT NULL THEN fn_gl_impact_payload(v_je_id, 'posted', NULL) END,
    'audit_events', v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_require_open_fiscal_period(UUID, DATE, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_require_postable_account(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_preview_gl_impact(TEXT, UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_get_accounting_trace(TEXT, UUID, UUID) TO authenticated;

-- Mutation primitives are intentionally internal. Module posting RPCs execute
-- them as their SECURITY DEFINER owner; PostgREST callers cannot assemble or
-- finalize posted entries directly.
REVOKE ALL ON FUNCTION fn_create_posted_journal_entry(UUID, UUID, TEXT, DATE, TEXT, TEXT, UUID) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_add_posting_line(UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_finalize_journal_entry(UUID) FROM PUBLIC, authenticated;

COMMENT ON FUNCTION fn_preview_gl_impact(TEXT, UUID, DATE) IS
  'Executes the authoritative source posting RPC inside a rollback-only subtransaction and returns its exact JE lines and posting context without persisting any side effect.';

COMMENT ON FUNCTION fn_get_accounting_trace(TEXT, UUID, UUID) IS
  'Stable drill contract joining a governed source document, its journal entry, GL impact, routes, and audit evidence.';
