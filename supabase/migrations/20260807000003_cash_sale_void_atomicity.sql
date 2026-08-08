-- ══════════════════════════════════════════════════════════════════════════════
-- PXL-AUD-076 — Voiding a Cash Sale left its collection on the books
--
-- A Cash Sale is ONE business event. PXL records it as TWO documents, because
-- that is what the BIR expects: a sales document (CS series) and the Official
-- Receipt that collects it. `fn_save_cash_sale` creates both in one act and
-- returns both ids.
--
-- Voiding did not. `fn_void_sales_invoice` withdrew the invoice half — revenue,
-- output VAT or percentage tax, COGS and inventory all reversed correctly — and
-- never touched the receipt half. The receipt's `DR Cash / CR AR` journal stayed
-- posted. Per voided cash sale, the books were left with:
--
--   * Cash OVERSTATED by the full amount of the sale;
--   * a phantom CREDIT in Accounts Receivable for a customer who owes nothing;
--   * a `posted` Official Receipt collecting a sale that no longer exists.
--
-- The journal still balanced, so the trial balance could not see it, and no
-- reconciliation in the product covers cash. Reproduced on a fresh schema by
-- `scripts/verify_posting_lifecycles.mjs`: CS-…-000001 `cancelled` while
-- OR-…-000001 for ₱5,600.00 remained `posted`.
--
-- REACHABLE, not latent. `CashSalesPage.tsx` exposes no void action, but
-- `SalesInvoicePage.tsx` calls `fn_void_sales_invoice` and its list filters only
-- on company and status — so cash sales appear in the Sales Invoice list and can
-- be voided from there.
--
-- ── THE FIX: name the business event, and route every surface into it ──────────
-- `fn_void_cash_sale` becomes the authority for "withdraw this cash sale". It is
-- an ORCHESTRATOR, not a new engine: both halves are reversed by
-- `fn_reverse_posted_journal_entry`, the same primitive every other void uses,
-- and each half's reversal stays owned by its own document's core.
--
-- `fn_void_sales_invoice` DELEGATES to it when the invoice is a cash sale. That
-- is what stops the general Sales Invoice surface bypassing the governed path:
-- the surface is not blocked, it is routed. No screen has to know the
-- difference, so there is no browser-side coordination to get wrong.
--
-- One function is one transaction, so a cash-sale void is atomic: both halves
-- reverse, or neither does.
--
-- Additive and structural only: no table, column, policy or posting path
-- changes, and the two document cores keep their existing behaviour.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. One receipt-reversal implementation, with its terminal state a parameter
-- Extracted verbatim from `fn_bounce_receipt`, which until now was the only way
-- to reverse a posted receipt and could only ever land on `bounced`. A bounced
-- cheque and a withdrawn sale are different business events that need the same
-- mechanism, so the mechanism moves here and the terminal state becomes the
-- caller's to state. Private: reachable only through a named business act.
CREATE OR REPLACE FUNCTION public.fn_reverse_receipt_core(
  p_receipt_id      UUID,
  p_terminal_status TEXT,
  p_reason          TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec         receipts%ROWTYPE;
  v_reversal_id UUID;
  v_period_id   UUID;
  v_event       TEXT;
BEGIN
  IF p_terminal_status NOT IN ('bounced', 'cancelled') THEN
    RAISE EXCEPTION 'Unsupported receipt terminal status %', p_terminal_status
      USING ERRCODE = '23514';
  END IF;
  v_event := CASE WHEN p_terminal_status = 'bounced' THEN 'BOUNCED' ELSE 'VOIDED' END;

  SELECT * INTO v_rec FROM receipts WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Receipt not found or access denied';
  END IF;
  IF v_rec.status <> 'posted' OR v_rec.journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Only a posted receipt can be reversed (current status: %)', v_rec.status;
  END IF;

  -- CAS evidence needs a reason for any terminal transition; the caller's reason
  -- carries through to `fn_capture_cas_document_void`.
  PERFORM set_config('pxl.cas_void_reason', p_reason, true);

  PERFORM fn_assert_source_journal_link(
    'OR', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
  );

  v_reversal_id := fn_reverse_posted_journal_entry(
    v_rec.journal_entry_id, CURRENT_DATE,
    'REV', v_rec.id,
    'JE-REV-' || v_rec.receipt_number,
    'Reversal of Receipt ' || v_rec.receipt_number || ' - ' || p_reason
  );

  SELECT fiscal_period_id INTO v_period_id
  FROM journal_entries WHERE id = v_reversal_id;

  -- Any CWT the customer withheld on this collection goes back with it.
  PERFORM fn_reverse_tax_detail_entries('OR', v_rec.id, CURRENT_DATE, v_period_id);
  PERFORM fn_invalidate_form2307_received_for_receipt(
    v_rec.id,
    'Receipt ' || v_rec.receipt_number || ' ' || p_terminal_status || ' on ' || CURRENT_DATE::TEXT
  );

  UPDATE receipts
  SET status = p_terminal_status, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'OR', v_rec.id, v_event, v_reversal_id,
    jsonb_build_object('reversal_date', CURRENT_DATE, 'reason', p_reason)
  );

  RETURN v_reversal_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_reverse_receipt_core(UUID, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.fn_reverse_receipt_core(UUID, TEXT, TEXT) IS
  'PXL-AUD-076: the one receipt-reversal implementation. Private; reached through fn_bounce_receipt or fn_void_cash_sale.';

-- ── 2. Bouncing a receipt becomes a face over that one implementation ──────────
CREATE OR REPLACE FUNCTION public.fn_bounce_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_number TEXT;
BEGIN
  SELECT receipt_number INTO v_number FROM receipts WHERE id = p_receipt_id;
  PERFORM fn_reverse_receipt_core(
    p_receipt_id, 'bounced',
    'Bounced Receipt ' || COALESCE(v_number, p_receipt_id::TEXT)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_bounce_receipt(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_bounce_receipt(UUID) TO authenticated, service_role;

-- ── 3. The void's dimension stamping, stated once ─────────────────────────────
-- Lifted unchanged out of `fn_void_sales_invoice` so both the ordinary invoice
-- void and the cash-sale void inherit it instead of restating it.
CREATE OR REPLACE FUNCTION public.fn_stamp_void_inventory_dimensions(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE inventory_transactions it
  SET project_id = COALESCE(sil.project_id, si.project_id),
      location_id = COALESCE(sil.location_id, si.location_id),
      functional_entity_id = COALESCE(
        sil.functional_entity_id, si.functional_entity_id
      )
  FROM sales_invoices si
  JOIN sales_invoice_lines sil
    ON sil.sales_invoice_id = si.id
  WHERE si.id = p_invoice_id
    AND it.reference_doc_type = 'SI_VOID'
    AND it.reference_doc_id = si.id
    AND it.item_id = sil.item_id
    AND it.warehouse_id = sil.warehouse_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_stamp_void_inventory_dimensions(UUID)
  FROM PUBLIC, anon, authenticated;

-- ── 4. The named business act ─────────────────────────────────────────────────
-- Withdraw a cash sale: both documents, one transaction, one reason.
CREATE OR REPLACE FUNCTION public.fn_void_cash_sale(
  p_invoice_id     UUID,
  p_void_reason_id UUID,
  p_memo           TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec    sales_invoices%ROWTYPE;
  v_reason TEXT;
  v_receipt RECORD;
  v_count  INT := 0;
BEGIN
  SELECT * INTO v_rec FROM sales_invoices WHERE id = p_invoice_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Sales invoice not found or access denied';
  END IF;
  IF NOT COALESCE(v_rec.is_cash_sale, false) THEN
    RAISE EXCEPTION 'Document % is not a cash sale; void it as a Sales Invoice.',
      v_rec.si_number USING ERRCODE = '23514';
  END IF;

  -- Resolve the reason the same way every other void does, so the message and
  -- the CAS evidence match what an accountant sees elsewhere.
  IF p_void_reason_id IS NOT NULL THEN
    SELECT description INTO v_reason
    FROM void_reason_codes WHERE id = p_void_reason_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid or inactive void reason';
    END IF;
  END IF;
  v_reason := COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), v_reason);
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A void reason is required';
  END IF;

  -- The invoice half first: its core refuses a second void, which is what makes
  -- repeating this call safe — no half can be reversed twice.
  PERFORM fn_void_sales_invoice_aud053_core(p_invoice_id, p_void_reason_id, p_memo);
  PERFORM fn_stamp_void_inventory_dimensions(p_invoice_id);

  -- Then the collection half. A cash sale creates one receipt, but the link is
  -- read as a set so a future multi-receipt structure cannot silently leak one.
  FOR v_receipt IN
    SELECT DISTINCT r.id, r.receipt_number
    FROM receipts r
    JOIN receipt_lines rl ON rl.receipt_id = r.id
    WHERE rl.invoice_id = p_invoice_id
      AND r.company_id = v_rec.company_id
      AND r.status = 'posted'
  LOOP
    PERFORM fn_reverse_receipt_core(
      v_receipt.id, 'cancelled',
      'Cash Sale ' || v_rec.si_number || ' voided - ' || v_reason
    );
    v_count := v_count + 1;
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'SI', p_invoice_id, 'VOIDED', NULL,
    jsonb_build_object(
      'cash_sale', true, 'receipts_cancelled', v_count,
      'void_reason_id', p_void_reason_id, 'reason', v_reason)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_void_cash_sale(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_void_cash_sale(UUID, UUID, TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_void_cash_sale(UUID, UUID, TEXT) IS
  'PXL-AUD-076: withdraw a cash sale as one business event — invoice half and Official Receipt half, one transaction, one reason. Orchestrates the two document cores; adds no reversal engine.';

-- ── 5. The general Sales Invoice surface is routed, not blocked ───────────────
-- A cash sale reached through the Sales Invoice list is voided correctly without
-- the screen knowing it is a cash sale.
CREATE OR REPLACE FUNCTION public.fn_void_sales_invoice(
  p_invoice_id     UUID,
  p_void_reason_id UUID,
  p_memo           TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_is_cash_sale BOOLEAN;
BEGIN
  SELECT COALESCE(is_cash_sale, false) INTO v_is_cash_sale
  FROM sales_invoices WHERE id = p_invoice_id;

  IF v_is_cash_sale THEN
    PERFORM fn_void_cash_sale(p_invoice_id, p_void_reason_id, p_memo);
    RETURN;
  END IF;

  PERFORM fn_void_sales_invoice_aud053_core(p_invoice_id, p_void_reason_id, p_memo);
  PERFORM fn_stamp_void_inventory_dimensions(p_invoice_id);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_void_sales_invoice(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_void_sales_invoice(UUID, UUID, TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_void_sales_invoice(UUID, UUID, TEXT) IS
  'Void a Sales Invoice. A cash sale is delegated to fn_void_cash_sale so the collection half is withdrawn with it (PXL-AUD-076); an ordinary invoice takes the core path unchanged.';
