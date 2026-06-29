-- ══════════════════════════════════════════════════════════════════════════════
-- ATOMIC SAVE + STATUS TRANSITION RPCs
-- Replaces multi-round-trip direct table writes with single SECURITY DEFINER
-- transactions. Each RPC validates membership and business rules internally.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Schema additions ──────────────────────────────────────────────────────────

ALTER TABLE sales_invoices
  ADD COLUMN IF NOT EXISTS approved_by  UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at  TIMESTAMPTZ;

-- ── Sales Invoice RPCs ────────────────────────────────────────────────────────

-- fn_save_sales_invoice
-- Atomically saves header + lines in a single transaction.
-- Creates a new SI (status='draft') or updates an existing draft/approved SI.
-- Number generation and fiscal period resolution happen here, not in the UI.
-- Returns the SI UUID.

CREATE OR REPLACE FUNCTION fn_save_sales_invoice(
  p_invoice_id  UUID,     -- null for new, existing id for edit
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
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  -- Cross-company integrity: validate branch and customer belong to this company
  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  -- Resolve open fiscal period for the document date
  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'date')::DATE
    AND end_date   >= (p_header->>'date')::DATE
    AND is_locked = false
  LIMIT 1;

  IF p_invoice_id IS NULL THEN
    -- New document: generate number and insert as draft
    v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');

    INSERT INTO sales_invoices (
      company_id, branch_id, si_number, date, fiscal_period_id,
      customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
      payment_terms_id, due_date, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_vat_amount, total_amount, cwt_amount_expected,
      status, created_by, updated_by
    ) VALUES (
      v_company_id,
      v_branch_id,
      v_si_number,
      (p_header->>'date')::DATE,
      v_fiscal_period,
      (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'customer_address_snapshot', ''),
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      NULLIF(p_header->>'due_date', '')::DATE,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''),
      NULLIF(p_header->>'memo', ''),
      COALESCE((p_header->>'total_taxable_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_zero_rated_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_exempt_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_vat_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC,
      'draft',
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_si_id;

  ELSE
    -- Existing document: validate it can still be edited
    SELECT id, status INTO v_si_id, v_current_status
    FROM sales_invoices
    WHERE id = p_invoice_id AND company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Sales invoice not found or access denied';
    END IF;
    IF v_current_status NOT IN ('draft', 'approved') THEN
      RAISE EXCEPTION 'Cannot edit a % sales invoice', v_current_status;
    END IF;

    UPDATE sales_invoices SET
      branch_id                 = v_branch_id,
      date                      = (p_header->>'date')::DATE,
      fiscal_period_id          = v_fiscal_period,
      customer_id               = (p_header->>'customer_id')::UUID,
      customer_name_snapshot    = p_header->>'customer_name_snapshot',
      customer_tin_snapshot     = NULLIF(p_header->>'customer_tin_snapshot', ''),
      customer_address_snapshot = NULLIF(p_header->>'customer_address_snapshot', ''),
      payment_terms_id          = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      due_date                  = NULLIF(p_header->>'due_date', '')::DATE,
      currency_code             = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference                 = NULLIF(p_header->>'reference', ''),
      memo                      = NULLIF(p_header->>'memo', ''),
      total_taxable_amount      = COALESCE((p_header->>'total_taxable_amount')::NUMERIC, 0),
      total_zero_rated_amount   = COALESCE((p_header->>'total_zero_rated_amount')::NUMERIC, 0),
      total_exempt_amount       = COALESCE((p_header->>'total_exempt_amount')::NUMERIC, 0),
      total_vat_amount          = COALESCE((p_header->>'total_vat_amount')::NUMERIC, 0),
      total_amount              = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      cwt_amount_expected       = NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC,
      updated_at                = NOW(),
      updated_by                = auth.uid()
    WHERE id = v_si_id;
  END IF;

  -- Replace lines atomically
  DELETE FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id;

  INSERT INTO sales_invoice_lines (
    sales_invoice_id, company_id, line_number, item_id, description,
    quantity, uom_id, unit_price, discount_percent, discount_amount,
    net_amount, vat_code_id, vat_amount, total_amount, revenue_account_id,
    created_by, updated_by
  )
  SELECT
    v_si_id,
    v_company_id,
    (l->>'line_number')::INT,
    NULLIF(l->>'item_id', '')::UUID,
    l->>'description',
    COALESCE((l->>'quantity')::NUMERIC, 1),
    NULLIF(l->>'uom_id', '')::UUID,
    COALESCE((l->>'unit_price')::NUMERIC, 0),
    COALESCE((l->>'discount_percent')::NUMERIC, 0),
    COALESCE((l->>'discount_amount')::NUMERIC, 0),
    COALESCE((l->>'net_amount')::NUMERIC, 0),
    NULLIF(l->>'vat_code_id', '')::UUID,
    COALESCE((l->>'vat_amount')::NUMERIC, 0),
    COALESCE((l->>'total_amount')::NUMERIC, 0),
    NULLIF(l->>'revenue_account_id', '')::UUID,
    auth.uid(),
    auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE NULLIF(TRIM(l->>'description'), '') IS NOT NULL;

  RETURN v_si_id;
END;
$$;

-- fn_approve_sales_invoice
-- Transitions a draft SI to approved.
-- Future: if an approval_workflow is configured, route to the approver instead.

CREATE OR REPLACE FUNCTION fn_approve_sales_invoice(p_invoice_id UUID)
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
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft invoices can be approved (current status: %)', v_rec.status;
  END IF;

  UPDATE sales_invoices
  SET status = 'approved', approved_by = auth.uid(), approved_at = NOW(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- fn_post_sales_invoice
-- Transitions an approved SI to posted. Records who posted and when.
-- GL journal entry creation is stubbed here — implement in Sprint 9 GL module.

CREATE OR REPLACE FUNCTION fn_post_sales_invoice(p_invoice_id UUID)
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
    RAISE EXCEPTION 'Only approved invoices can be posted (current status: %)', v_rec.status;
  END IF;

  -- Sprint 9 GL stub: when the GL module is built, create journal entries here:
  --   DR  Accounts Receivable (customer control account)  = total_amount
  --   CR  Revenue accounts (by line, from revenue_account_id)
  --   CR  VAT Payable (output VAT)                        = total_vat_amount
  --   Then: UPDATE sales_invoices SET journal_entry_id = <new_je_id>

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- fn_void_sales_invoice
-- Cancels a sales invoice regardless of current status (draft/approved/posted).
-- SECURITY DEFINER bypasses the UPDATE policy which only allows draft/approved edits.
-- BIR rule: voided SI numbers are never reused (enforced at number-series level).

CREATE OR REPLACE FUNCTION fn_void_sales_invoice(
  p_invoice_id    UUID,
  p_void_reason_id UUID,
  p_memo          TEXT DEFAULT NULL
)
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
  IF v_rec.status = 'cancelled' THEN
    RAISE EXCEPTION 'Invoice is already voided';
  END IF;

  IF p_void_reason_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM void_reason_codes WHERE id = p_void_reason_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid or inactive void reason';
  END IF;

  UPDATE sales_invoices
  SET
    status          = 'cancelled',
    void_reason_id  = p_void_reason_id,
    memo            = COALESCE(NULLIF(p_memo, ''), v_rec.memo),
    updated_by      = auth.uid(),
    updated_at      = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- ── Receipt RPCs ──────────────────────────────────────────────────────────────

-- fn_save_receipt
-- Atomically saves receipt header + lines. Returns receipt UUID.

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
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := COALESCE(NULLIF(p_header->>'branch_id', ''), NULL)::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF v_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM customers WHERE id = (p_header->>'customer_id')::UUID AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  IF p_receipt_id IS NULL THEN
    v_receipt_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

    INSERT INTO receipts (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      receipt_number, receipt_date, payment_mode_id, reference_number, bank_account_id,
      total_amount, total_cwt, remarks, status, created_by, updated_by
    ) VALUES (
      v_company_id,
      v_branch_id,
      (p_header->>'customer_id')::UUID,
      p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      v_receipt_number,
      (p_header->>'receipt_date')::DATE,
      (p_header->>'payment_mode_id')::UUID,
      NULLIF(p_header->>'reference_number', ''),
      NULLIF(p_header->>'bank_account_id', '')::UUID,
      COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      NULLIF(p_header->>'remarks', ''),
      'draft',
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_receipt_id;

  ELSE
    SELECT id, status INTO v_receipt_id, v_current_status
    FROM receipts WHERE id = p_receipt_id AND company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Receipt not found or access denied';
    END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % receipt', v_current_status;
    END IF;

    UPDATE receipts SET
      branch_id              = v_branch_id,
      customer_id            = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot  = NULLIF(p_header->>'customer_tin_snapshot', ''),
      receipt_date           = (p_header->>'receipt_date')::DATE,
      payment_mode_id        = (p_header->>'payment_mode_id')::UUID,
      reference_number       = NULLIF(p_header->>'reference_number', ''),
      bank_account_id        = NULLIF(p_header->>'bank_account_id', '')::UUID,
      total_amount           = COALESCE((p_header->>'total_amount')::NUMERIC, 0),
      total_cwt              = COALESCE((p_header->>'total_cwt')::NUMERIC, 0),
      remarks                = NULLIF(p_header->>'remarks', ''),
      updated_at             = NOW(),
      updated_by             = auth.uid()
    WHERE id = v_receipt_id;
  END IF;

  -- Replace lines atomically
  DELETE FROM receipt_lines WHERE receipt_id = v_receipt_id;

  INSERT INTO receipt_lines (
    receipt_id, company_id, invoice_id, payment_amount, cwt_amount, forex_adjustment, atc_code_id,
    created_by, updated_by
  )
  SELECT
    v_receipt_id,
    v_company_id,
    NULLIF(l->>'invoice_id', '')::UUID,
    COALESCE((l->>'payment_amount')::NUMERIC, 0),
    COALESCE((l->>'cwt_amount')::NUMERIC, 0),
    COALESCE((l->>'forex_adjustment')::NUMERIC, 0),
    NULLIF(l->>'atc_code_id', '')::UUID,
    auth.uid(),
    auth.uid()
  FROM jsonb_array_elements(p_lines) AS l
  WHERE COALESCE((l->>'payment_amount')::NUMERIC, 0) != 0;

  RETURN v_receipt_id;
END;
$$;

-- fn_post_receipt
-- Transitions a draft receipt to posted.
-- Sprint 9 GL stub: when GL is built, create journal entries here.

CREATE OR REPLACE FUNCTION fn_post_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec receipts%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'draft' THEN
    RAISE EXCEPTION 'Only draft receipts can be posted (current status: %)', v_rec.status;
  END IF;

  -- Sprint 9 GL stub: when GL is built, create journal entries here:
  --   DR  Cash/Bank (from payment_mode/bank_account)  = total_amount
  --   DR  EWT Withheld (if total_cwt > 0)             = total_cwt
  --   CR  Accounts Receivable (customer)              = total_amount + total_cwt

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(), updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_receipt_id;
END;
$$;

-- fn_bounce_receipt
-- Marks a posted receipt as bounced (dishonored cheque etc.).
-- SECURITY DEFINER bypasses the UPDATE policy (posted rows cannot be updated directly).

CREATE OR REPLACE FUNCTION fn_bounce_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec receipts%ROWTYPE;
BEGIN
  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Receipt not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status != 'posted' THEN
    RAISE EXCEPTION 'Only posted receipts can be marked as bounced (current status: %)', v_rec.status;
  END IF;

  UPDATE receipts
  SET status = 'bounced', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_receipt_id;
END;
$$;

-- ── Grant execute to authenticated users ──────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_save_sales_invoice(UUID, JSONB, JSONB)    TO authenticated;
GRANT EXECUTE ON FUNCTION fn_approve_sales_invoice(UUID)               TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_sales_invoice(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION fn_void_sales_invoice(UUID, UUID, TEXT)      TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_receipt(UUID, JSONB, JSONB)          TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_receipt(UUID)                        TO authenticated;
GRANT EXECUTE ON FUNCTION fn_bounce_receipt(UUID)                      TO authenticated;
