-- ══════════════════════════════════════════════════════════════════════════════
-- HARDENING: ATC consolidation, AR view CWT fix, server-side computation,
-- approved-edit lock, over-application guard, tax calendar RPC,
-- audit line triggers, global tax write restriction, membership cleanup note.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Broaden atc_codes tax_category check to include 'pt' ──────────────────
ALTER TABLE atc_codes DROP CONSTRAINT IF EXISTS atc_codes_tax_type_check;
ALTER TABLE atc_codes DROP CONSTRAINT IF EXISTS atc_codes_tax_category_check;
ALTER TABLE atc_codes ADD CONSTRAINT atc_codes_tax_category_check
  CHECK (tax_category IN ('ewt', 'fwt', 'pt'));

-- ── 2. Consolidate ref_atc_codes into atc_codes ───────────────────────────────
-- Insert ref_atc_codes rows that don't already exist in atc_codes by code.
-- Uses the ref_atc_codes UUID so FK references stay valid after FK migration.

INSERT INTO atc_codes (id, code, description, tax_category, rate, is_active)
SELECT r.id, r.atc_code, r.description, 'ewt', r.tax_rate, r.is_active
FROM ref_atc_codes r
WHERE NOT EXISTS (SELECT 1 FROM atc_codes a WHERE a.code = r.atc_code);

-- For codes that exist in both (same code, different UUIDs):
-- remap receipt_lines.atc_code_id from ref_atc_codes UUID → atc_codes UUID
UPDATE receipt_lines rl
SET atc_code_id = (
  SELECT a.id FROM atc_codes a
  INNER JOIN ref_atc_codes r ON r.atc_code = a.code
  WHERE r.id = rl.atc_code_id
)
WHERE rl.atc_code_id IN (SELECT id FROM ref_atc_codes);

-- Same for form_2307_tracking
UPDATE form_2307_tracking ft
SET atc_code_id = (
  SELECT a.id FROM atc_codes a
  INNER JOIN ref_atc_codes r ON r.atc_code = a.code
  WHERE r.id = ft.atc_code_id
)
WHERE ft.atc_code_id IN (SELECT id FROM ref_atc_codes);

-- Migrate receipt_lines FK from ref_atc_codes → atc_codes
ALTER TABLE receipt_lines
  DROP CONSTRAINT IF EXISTS receipt_lines_atc_code_id_fkey,
  ADD CONSTRAINT receipt_lines_atc_code_id_fkey FOREIGN KEY (atc_code_id) REFERENCES atc_codes(id);

-- Migrate form_2307_tracking FK
ALTER TABLE form_2307_tracking
  DROP CONSTRAINT IF EXISTS form_2307_tracking_atc_code_id_fkey,
  ADD CONSTRAINT form_2307_tracking_atc_code_id_fkey FOREIGN KEY (atc_code_id) REFERENCES atc_codes(id);

-- Drop ref_atc_codes (policies must be dropped first)
DROP POLICY IF EXISTS "read_ref_atc_codes" ON ref_atc_codes;
DROP TABLE IF EXISTS ref_atc_codes;

-- ── 3. Fix vw_customer_ledger: receipt credit should clear total_amount + total_cwt ─
-- AR is debited at total_amount + total_cwt when posting (CWT clears AR too).
-- The ledger must credit the same amount so AR aging and ledger agree.

CREATE OR REPLACE VIEW vw_customer_ledger AS
SELECT
  si.company_id, si.customer_id, si.date AS transaction_date,
  'SI'::TEXT AS doc_type, si.si_number AS doc_number,
  COALESCE(si.memo, 'Sales Invoice') AS description,
  si.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
  si.created_at
FROM sales_invoices si
WHERE si.status = 'posted'

UNION ALL

SELECT
  r.company_id, r.customer_id, r.receipt_date AS transaction_date,
  'OR'::TEXT AS doc_type, r.receipt_number AS doc_number,
  COALESCE(r.remarks, 'Official Receipt') AS description,
  0::NUMERIC AS debit_amount, (r.total_amount + r.total_cwt) AS credit_amount,
  r.created_at
FROM receipts r
WHERE r.status = 'posted'

UNION ALL

SELECT
  cm.company_id, cm.customer_id, cm.cm_date AS transaction_date,
  'CM'::TEXT AS doc_type, cm.cm_number AS doc_number,
  COALESCE(cm.remarks, 'Credit Memo') AS description,
  0::NUMERIC AS debit_amount, cm.total_amount AS credit_amount,
  cm.created_at
FROM credit_memos cm
WHERE cm.status IN ('approved', 'applied')

UNION ALL

SELECT
  dm.company_id, dm.customer_id, dm.dm_date AS transaction_date,
  'DM'::TEXT AS doc_type, dm.dm_number AS doc_number,
  COALESCE(dm.remarks, 'Debit Memo') AS description,
  dm.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
  dm.created_at
FROM debit_memos dm
WHERE dm.status IN ('approved', 'paid');

-- ── 4. Restrict global tax table writes to company admins ─────────────────────
-- Any authenticated user could previously modify BIR reference data.
-- Restrict INSERT/UPDATE to users who admin at least one company.
-- This is a pragmatic check until a system-admin role is added.

CREATE OR REPLACE FUNCTION is_any_company_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_company_memberships
    WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
  );
$$;

DROP POLICY IF EXISTS "auth_write_tax_codes"  ON tax_codes;
DROP POLICY IF EXISTS "auth_update_tax_codes" ON tax_codes;
DROP POLICY IF EXISTS "auth_write_vat_codes"  ON vat_codes;
DROP POLICY IF EXISTS "auth_update_vat_codes" ON vat_codes;
DROP POLICY IF EXISTS "auth_write_atc_codes"  ON atc_codes;
DROP POLICY IF EXISTS "auth_update_atc_codes" ON atc_codes;

CREATE POLICY "admin_write_tax_codes"  ON tax_codes  FOR INSERT TO authenticated WITH CHECK (is_any_company_admin());
CREATE POLICY "admin_update_tax_codes" ON tax_codes  FOR UPDATE TO authenticated USING (is_any_company_admin());
CREATE POLICY "admin_write_vat_codes"  ON vat_codes  FOR INSERT TO authenticated WITH CHECK (is_any_company_admin());
CREATE POLICY "admin_update_vat_codes" ON vat_codes  FOR UPDATE TO authenticated USING (is_any_company_admin());
CREATE POLICY "admin_write_atc_codes"  ON atc_codes  FOR INSERT TO authenticated WITH CHECK (is_any_company_admin());
CREATE POLICY "admin_update_atc_codes" ON atc_codes  FOR UPDATE TO authenticated USING (is_any_company_admin());

-- ── 5. fn_mark_tax_event_filed ────────────────────────────────────────────────
-- Direct update of tax_calendar_events was blocked by status update policies.
-- This SECURITY DEFINER RPC validates membership and handles the transition.

CREATE OR REPLACE FUNCTION fn_mark_tax_event_filed(
  p_event_id      UUID,
  p_date_filed    DATE,
  p_efps_ref      TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev tax_calendar_events%ROWTYPE;
BEGIN
  SELECT * INTO v_ev FROM tax_calendar_events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tax calendar event not found'; END IF;
  IF NOT is_company_member(v_ev.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_ev.status = 'filed' THEN RAISE EXCEPTION 'Event is already filed'; END IF;

  UPDATE tax_calendar_events
  SET status = 'filed',
      date_filed = COALESCE(p_date_filed, CURRENT_DATE),
      efps_reference_no = p_efps_ref,
      updated_at = NOW()
  WHERE id = p_event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_mark_tax_event_filed(UUID, DATE, TEXT) TO authenticated;

-- ── 6. Extend audit triggers to transactional line tables ─────────────────────

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'sales_invoice_lines',
    'receipt_lines',
    'credit_memo_lines',
    'debit_memo_lines',
    'sales_order_lines',
    'delivery_receipt_lines'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_audit_%1$s ON %1$s;
       CREATE TRIGGER trg_audit_%1$s
         AFTER INSERT OR UPDATE OR DELETE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();',
      t
    );
  END LOOP;
END;
$$;

-- ── 7. fn_save_sales_invoice: reject approved, server-side VAT computation ────
-- Approved SIs cannot be edited. Revert to draft first via fn_revert_si_to_draft.
-- Server now recomputes all line amounts from source data; UI preview values
-- are accepted only for display purposes, never trusted for the ledger.

CREATE OR REPLACE FUNCTION fn_save_sales_invoice(
  p_invoice_id  UUID,
  p_header      JSONB,
  p_lines       JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_si_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_si_number      TEXT;
  v_fiscal_period  UUID;
  v_current_status TEXT;
  -- Line computation
  v_line           JSONB;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(5,2);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_disc           NUMERIC(15,2);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  -- Totals
  v_taxable        NUMERIC(15,2) := 0;
  v_zero_rated     NUMERIC(15,2) := 0;
  v_exempt         NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_grand_total    NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'date')::DATE
    AND end_date   >= (p_header->>'date')::DATE
    AND is_locked = false
  LIMIT 1;

  IF p_invoice_id IS NULL THEN
    v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');

    INSERT INTO sales_invoices (
      company_id, branch_id, si_number, date, fiscal_period_id,
      customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
      payment_terms_id, due_date, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_vat_amount, total_amount, cwt_amount_expected,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_si_number, (p_header->>'date')::DATE, v_fiscal_period,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'customer_address_snapshot', ''),
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      NULLIF(p_header->>'due_date', '')::DATE,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      0, 0, 0, 0, 0, -- totals computed below
      NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_si_id;

  ELSE
    SELECT id, status INTO v_si_id, v_current_status
    FROM sales_invoices WHERE id = p_invoice_id AND company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Sales invoice not found or access denied';
    END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % sales invoice. Revert to draft first.', v_current_status;
    END IF;

    UPDATE sales_invoices SET
      branch_id = v_branch_id, date = (p_header->>'date')::DATE, fiscal_period_id = v_fiscal_period,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      customer_address_snapshot = NULLIF(p_header->>'customer_address_snapshot', ''),
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference = NULLIF(p_header->>'reference', ''), memo = NULLIF(p_header->>'memo', ''),
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      total_vat_amount = 0, total_amount = 0, -- recomputed below
      cwt_amount_expected = NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_si_id;
  END IF;

  -- Replace lines and compute server-side totals
  DELETE FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    -- Look up VAT classification and rate for this line
    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);

    -- Recompute amounts from source — UI preview values not trusted
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
    v_total_line := v_net + v_vat_amt;

    -- Accumulate header totals
    CASE v_vat_class
      WHEN 'regular'   THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number,
      item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, vat_amount, total_amount,
      revenue_account_id, created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID,
      v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0),
      v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'At least one non-empty line item is required';
  END IF;

  -- Write server-computed totals back to header
  UPDATE sales_invoices SET
    total_taxable_amount    = v_taxable,
    total_zero_rated_amount = v_zero_rated,
    total_exempt_amount     = v_exempt,
    total_vat_amount        = v_total_vat,
    total_amount            = v_grand_total,
    updated_at              = NOW()
  WHERE id = v_si_id;

  RETURN v_si_id;
END;
$$;

-- ── 8. fn_revert_si_to_draft ──────────────────────────────────────────────────
-- Allows an approved (not yet posted/cancelled) SI to return to draft so
-- it can be edited. Clears the approval record.

CREATE OR REPLACE FUNCTION fn_revert_si_to_draft(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'approved' THEN
    RAISE EXCEPTION 'Only approved invoices can be reverted to draft (current status: %)', v_rec.status;
  END IF;

  UPDATE sales_invoices
  SET status = 'draft', approved_by = NULL, approved_at = NULL,
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_invoice_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_sales_invoice(UUID, JSONB, JSONB)  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_revert_si_to_draft(UUID)                TO authenticated;

-- ── 9. fn_save_receipt: add over-application check ────────────────────────────

CREATE OR REPLACE FUNCTION fn_save_receipt(
  p_receipt_id  UUID,
  p_header      JSONB,
  p_lines       JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt_id     UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_receipt_number TEXT;
  v_current_status TEXT;
  -- Line validation
  v_line           JSONB;
  v_inv_id         UUID;
  v_pay_amt        NUMERIC(15,2);
  v_outstanding    NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := COALESCE(NULLIF(p_header->>'branch_id', ''), NULL)::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF v_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id
  ) THEN RAISE EXCEPTION 'Branch does not belong to this company'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id
  ) THEN RAISE EXCEPTION 'Customer does not belong to this company'; END IF;

  -- Validate each line: no over-application, no cross-company invoices
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_inv_id := NULLIF(v_line->>'invoice_id', '')::UUID;
    v_pay_amt := COALESCE((v_line->>'payment_amount')::NUMERIC, 0);
    CONTINUE WHEN v_inv_id IS NULL OR v_pay_amt <= 0;

    -- Verify invoice belongs to this company
    IF NOT EXISTS (SELECT 1 FROM sales_invoices WHERE id = v_inv_id AND company_id = v_company_id) THEN
      RAISE EXCEPTION 'Invoice % does not belong to this company', v_inv_id;
    END IF;

    -- Compute outstanding balance (total - already applied payments, excluding current receipt)
    SELECT si.total_amount - COALESCE(SUM(rl.payment_amount + rl.cwt_amount), 0)
    INTO v_outstanding
    FROM sales_invoices si
    LEFT JOIN receipt_lines rl
      ON rl.invoice_id = si.id
      AND rl.receipt_id != COALESCE(p_receipt_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND rl.receipt_id IN (SELECT id FROM receipts WHERE status != 'bounced')
    WHERE si.id = v_inv_id
    GROUP BY si.total_amount;

    IF v_pay_amt + COALESCE((v_line->>'cwt_amount')::NUMERIC, 0) > COALESCE(v_outstanding, 0) + 0.02 THEN
      RAISE EXCEPTION 'Payment of % exceeds outstanding balance of % for invoice', v_pay_amt, COALESCE(v_outstanding, 0);
    END IF;
  END LOOP;

  IF p_receipt_id IS NULL THEN
    v_receipt_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

    INSERT INTO receipts (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      receipt_number, receipt_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_cwt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot', ''),
      v_receipt_number, (p_header->>'receipt_date')::DATE,
      (p_header->>'payment_mode_id')::UUID,
      NULLIF(p_header->>'reference_number', ''), NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      NULLIF(p_header->>'remarks', ''), 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_receipt_id;

  ELSE
    SELECT id, status INTO v_receipt_id, v_current_status
    FROM receipts WHERE id = p_receipt_id AND company_id = v_company_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found or access denied'; END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % receipt', v_current_status;
    END IF;

    UPDATE receipts SET
      branch_id = v_branch_id, customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      receipt_date = (p_header->>'receipt_date')::DATE,
      payment_mode_id = (p_header->>'payment_mode_id')::UUID,
      reference_number = NULLIF(p_header->>'reference_number', ''),
      bank_account_id = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_cwt = COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      remarks = NULLIF(p_header->>'remarks', ''),
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_receipt_id;
  END IF;

  DELETE FROM receipt_lines WHERE receipt_id = v_receipt_id;

  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, forex_adjustment, atc_code_id, created_by, updated_by)
  SELECT v_receipt_id, v_company_id,
    NULLIF(l->>'invoice_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'cwt_amount')::NUMERIC, 0),
    COALESCE((l->>'forex_adjustment')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    auth.uid(), auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) != 0;

  RETURN v_receipt_id;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_save_receipt(UUID, JSONB, JSONB) TO authenticated;

-- ── 10. Membership cleanup documentation ──────────────────────────────────────
-- Migration 008 bootstrapped all users × companies as 'admin'.
-- Migration 009 removed the auto-grant triggers, but existing memberships remain.
-- To remediate in a production environment, identify and remove excess memberships:
--
-- MANUAL REVIEW (do not run blindly — may lock legitimate users out):
-- DELETE FROM user_company_memberships ucm
-- WHERE role = 'admin'
--   AND NOT EXISTS (
--     SELECT 1 FROM companies c WHERE c.id = ucm.company_id AND c.created_by = ucm.user_id
--   )
--   AND granted_by = ucm.user_id; -- bootstrap pattern: user granted themselves
--
-- After cleanup, each user should only have memberships for companies they own or
-- were explicitly invited to. The creator-owner trigger (migration 009) handles
-- new companies going forward.
