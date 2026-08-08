-- ══════════════════════════════════════════════════════════════════════════════
-- Backlog 18c — Delivery Receipt cancellation and reversal
--
-- A posted delivery could be neither cancelled nor reversed. A mis-shipped
-- delivery had no correction path, and the cost it parked in Goods Delivered Not
-- Invoiced could be released only by billing it — that is, only by compounding
-- the mistake with an invoice to a customer who never received the goods.
--
-- ── A DEFECT FOUND WHILE BUILDING THIS, and fixed here first ───────────────────
-- `delivery_receipts` became a POSTING document on 2026-08-03 (`20260803000004`
-- added `journal_entry_id`, `posted_at`, `posted_by` and made
-- `fn_post_delivery_receipt` relieve stock). Its status guard, written on
-- 2026-07-04 when a delivery was still only a shipping record, was never widened
-- to match: `trg_guard_header_delivery_receipts` allows exactly `delivered_at`
-- once the row is no longer draft/in_transit.
--
-- So the last statement of `fn_post_delivery_receipt` — the one that stamps
-- `journal_entry_id`, `posted_at` and `posted_by` — is refused by the guard
-- whenever the receipt was marked delivered in an EARLIER transaction. That is
-- exactly what the screen does: it commits the status update, then calls the
-- posting RPC. Reproduced on a fresh local schema, in two separate transactions:
--
--   delivery_receipts <id> is "delivered" and immutable: column(s) [posted_at]
--   cannot change (allowed: status, updated_at, updated_by, delivered_at).
--
-- Every pgTAP file passed throughout, because pgTAP runs inside ONE transaction
-- and the guard's `same_txn` escape hatch then applies. A gate that only ever
-- sees one transaction cannot see this class of defect at all.
--
-- `delivery_receipts` is the ONLY posting document whose guard omits the posting
-- stamps; every other one — sales_invoices, vendor_bills, official receipts,
-- payment vouchers, the inventory documents — lists them. This migration brings
-- it into line and adds the void columns the same guards already allow elsewhere.
--
-- Additive only: no table is dropped, no column removed, no posting path
-- replaced, and `fn_post_delivery_receipt` itself is untouched.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. The void columns, named as `sales_invoices` names them ──────────────────
ALTER TABLE delivery_receipts
  ADD COLUMN IF NOT EXISTS void_reason_id UUID REFERENCES void_reason_codes(id),
  ADD COLUMN IF NOT EXISTS void_memo TEXT;

COMMENT ON COLUMN delivery_receipts.void_reason_id IS
  'Why this delivery was cancelled. Required on void, exactly as on a Sales Invoice.';

-- ── 2. The guard learns that a delivery posts ──────────────────────────────────
-- Same generic guard, same frozen-status list; only the columns a locked row may
-- legitimately change are widened, to the posting stamps its own posting function
-- writes and the void columns the void function below writes.
DROP TRIGGER IF EXISTS trg_guard_header_delivery_receipts ON delivery_receipts;
CREATE TRIGGER trg_guard_header_delivery_receipts
  BEFORE UPDATE OR DELETE ON delivery_receipts
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header(
    'status', 'draft,in_transit',
    'delivered_at,journal_entry_id,posted_at,posted_by,void_reason_id,void_memo',
    '', 'same_txn');

-- ── 3. Cancellation and reversal ───────────────────────────────────────────────
-- Follows `fn_void_sales_invoice` step for step: lock, refuse a second void,
-- require a reason, reverse the journal, put the stock back through the shared
-- costing path, then record the event. It is not a new engine and adds no second
-- posting path — the reversal is `fn_reverse_posted_journal_entry`, the same one
-- every other void uses.
CREATE OR REPLACE FUNCTION public.fn_void_delivery_receipt(
  p_dr_id          UUID,
  p_void_reason_id UUID,
  p_memo           TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec         delivery_receipts%ROWTYPE;
  v_reversal_id UUID;
  v_reason      TEXT;
  v_billed      TEXT;
  v_line        RECORD;
BEGIN
  SELECT * INTO v_rec FROM delivery_receipts WHERE id = p_dr_id FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Delivery receipt not found or access denied';
  END IF;
  IF v_rec.status = 'cancelled' THEN
    RAISE EXCEPTION 'Delivery receipt is already cancelled';
  END IF;

  IF p_void_reason_id IS NOT NULL THEN
    SELECT description INTO v_reason
    FROM void_reason_codes
    WHERE id = p_void_reason_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid or inactive void reason';
    END IF;
  END IF;
  v_reason := COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), v_reason);
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A void reason is required';
  END IF;
  PERFORM set_config('pxl.cas_void_reason', v_reason, true);

  -- An invoice already claims this delivery. Reversing the clearing balance from
  -- underneath it would leave the invoice taking a cost that no longer exists, so
  -- the invoice is voided first and the delivery second — never the other way
  -- round. A draft invoice counts: it is already holding the delivered line
  -- through `uq_sil_delivery_source`, and posting it later would find nothing.
  SELECT si.si_number INTO v_billed
  FROM sales_invoice_lines sil
  JOIN sales_invoices si ON si.id = sil.sales_invoice_id
  JOIN delivery_receipt_lines drl ON drl.id = sil.source_line_id
  WHERE sil.source_document_type = 'DR'
    AND drl.dr_id = v_rec.id
    AND si.status <> 'cancelled'
  LIMIT 1;
  IF v_billed IS NOT NULL THEN
    RAISE EXCEPTION 'Delivery Receipt % is billed by Sales Invoice %. Void that invoice first, then cancel this delivery.',
      v_rec.dr_number, v_billed;
  END IF;

  -- An unposted delivery (draft, in transit, or delivered with nothing stockable
  -- on it) moved no stock and wrote no journal. Cancelling it is a status change
  -- and nothing else.
  IF v_rec.journal_entry_id IS NOT NULL THEN
    PERFORM fn_assert_source_journal_link(
      'DR', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
    );
    v_reversal_id := fn_reverse_posted_journal_entry(
      v_rec.journal_entry_id, CURRENT_DATE,
      'REV', v_rec.id,
      'JE-REV-' || v_rec.dr_number,
      'Reversal of DR ' || v_rec.dr_number || ' (' || v_rec.customer_name_snapshot || ') - ' || v_reason
    );

    FOR v_line IN
      SELECT drl.*, COALESCE(i.costing_method, 'weighted_average') AS costing_method
      FROM delivery_receipt_lines drl
      JOIN items i ON i.id = drl.item_id
      WHERE drl.dr_id = v_rec.id
        AND i.item_type = 'inventory_item'
        AND drl.warehouse_id IS NOT NULL
        AND drl.inventory_transaction_id IS NOT NULL
    LOOP
      PERFORM fn_ensure_stock_balance(v_rec.company_id, v_line.warehouse_id, v_line.item_id);

      UPDATE stock_balances
      SET qty_on_hand      = qty_on_hand + v_line.quantity,
          total_cost       = total_cost + COALESCE(v_line.inventory_cost, 0),
          last_receipt_date = CURRENT_DATE,
          updated_at       = NOW()
      WHERE warehouse_id = v_line.warehouse_id
        AND item_id = v_line.item_id;

      IF v_line.costing_method = 'weighted_average' THEN
        UPDATE stock_balances
        SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
        WHERE warehouse_id = v_line.warehouse_id
          AND item_id = v_line.item_id;
      ELSE
        PERFORM fn_add_cost_layer(
          v_rec.company_id, v_line.warehouse_id, v_line.item_id,
          CURRENT_DATE, v_line.quantity, COALESCE(v_line.unit_cost, 0),
          'DR_VOID', v_rec.id, NULL, NULL
        );
      END IF;

      INSERT INTO inventory_transactions (
        company_id, warehouse_id, item_id, transaction_type, transaction_date,
        qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
        reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by
      )
      SELECT v_rec.company_id, v_line.warehouse_id, v_line.item_id,
        'adjustment_in', CURRENT_DATE,
        v_line.quantity, COALESCE(v_line.unit_cost, 0), COALESCE(v_line.inventory_cost, 0),
        sb.qty_on_hand, v_line.costing_method,
        'DR_VOID', v_rec.id, v_reversal_id,
        'Cancellation restock for Delivery Receipt ' || v_rec.dr_number || ' line ' || v_line.line_number,
        auth.uid()
      FROM stock_balances sb
      WHERE sb.warehouse_id = v_line.warehouse_id
        AND sb.item_id = v_line.item_id;
    END LOOP;
  END IF;

  UPDATE delivery_receipts
  SET status = 'cancelled',
      void_reason_id = p_void_reason_id,
      void_memo = COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), void_memo),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'DR', v_rec.id, 'VOIDED', v_reversal_id,
    jsonb_build_object('void_reason_id', p_void_reason_id, 'reason', v_reason)
  );
END;
$$;

COMMENT ON FUNCTION public.fn_void_delivery_receipt(UUID, UUID, TEXT) IS
  'Backlog 18c: cancels a delivery, reverses its Goods Delivered Not Invoiced journal and puts the stock back through the shared costing path. Refuses while any non-cancelled Sales Invoice bills it.';

REVOKE ALL ON FUNCTION public.fn_void_delivery_receipt(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_void_delivery_receipt(UUID, UUID, TEXT) TO authenticated, service_role;

-- ── 4. A SECOND DEFECT, found because 18c's ordering rule depends on it ────────
-- The rule above says: void the invoice FIRST, then cancel the delivery. Billing
-- a delivery creates a DRAFT Sales Invoice (`billDelivery` on the Delivery
-- Receipts screen), so the very first step of the mis-ship correction is voiding
-- a never-posted document — and that could not be done at all.
--
-- `fn_capture_cas_document_void` resolves the void reason from
-- `pxl.cas_void_reason` and the reason code, then looks for the reversal journal
-- entry with:
--
--     SELECT je.id, COALESCE(v_reason, <je.description>)
--       INTO v_reversal_je, v_reason ...
--
-- A never-posted document has no reversal journal, and `SELECT ... INTO` sets
-- every target to NULL when it matches no row. So the second target ERASED the
-- reason that had just been resolved correctly, and the next line raised
-- "A cancellation/void reason is required for CAS audit evidence" — for a valid,
-- explicitly supplied reason. Reproduced by test `131` assertion 9 before this
-- fix, passing a live reason code AND a memo.
--
-- This trigger is attached to TWELVE document types (SI, VB, PV, OR, CM, DM-S,
-- VC, FT, IBT, BADJ, PCV, CV), so voiding any draft document was refused across
-- all of them. The fallback now lands in its own variable; nothing else about the
-- function changes, and the CAS evidence it writes is unchanged.
CREATE OR REPLACE FUNCTION public.fn_capture_cas_document_void()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old JSONB := TO_JSONB(OLD);
  v_new JSONB := TO_JSONB(NEW);
  v_code TEXT := TG_ARGV[0];
  v_number TEXT := NULLIF(v_new->>TG_ARGV[1], '');
  v_date DATE := NULLIF(v_new->>TG_ARGV[2], '')::DATE;
  v_terminals TEXT[] := STRING_TO_ARRAY(TG_ARGV[3], ',');
  v_party_id UUID;
  v_party_name TEXT;
  v_party_tin TEXT;
  v_amount NUMERIC(15,2);
  v_branch UUID;
  v_reason_id UUID := NULLIF(v_new->>'void_reason_id', '')::UUID;
  v_reason TEXT := NULLIF(BTRIM(current_setting('pxl.cas_void_reason', TRUE)), '');
  v_original_je UUID := NULLIF(v_new->>'journal_entry_id', '')::UUID;
  v_reversal_je UUID;
  v_je_reason TEXT;
  v_issuance_id UUID;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NOT (NEW.status = ANY(v_terminals)) THEN
    RETURN NEW;
  END IF;
  IF TG_TABLE_NAME = 'sales_invoices'
     AND COALESCE((v_new->>'is_cash_sale')::BOOLEAN, FALSE) THEN
    v_code := 'CS';
  END IF;

  IF COALESCE(TG_ARGV[4], '') <> '' THEN
    v_party_id := NULLIF(v_new->>TG_ARGV[4], '')::UUID;
  END IF;
  IF COALESCE(TG_ARGV[6], '') <> '' THEN v_party_name := NULLIF(v_new->>TG_ARGV[6], ''); END IF;
  IF COALESCE(TG_ARGV[7], '') <> '' THEN v_party_tin := NULLIF(v_new->>TG_ARGV[7], ''); END IF;
  IF COALESCE(TG_ARGV[8], '') <> '' THEN v_amount := NULLIF(v_new->>TG_ARGV[8], '')::NUMERIC; END IF;
  IF COALESCE(TG_ARGV[9], '') <> '' THEN v_branch := NULLIF(v_new->>TG_ARGV[9], '')::UUID; END IF;

  IF v_reason_id IS NOT NULL THEN
    SELECT COALESCE(v_reason, vrc.description)
    INTO v_reason
    FROM public.void_reason_codes vrc
    WHERE vrc.id = v_reason_id AND vrc.is_active = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or inactive void reason'; END IF;
  END IF;

  IF v_reason IS NULL AND TG_TABLE_NAME = 'receipts' AND NEW.status = 'bounced' THEN
    v_reason := 'Bounced payment instrument';
  END IF;
  IF v_reason IS NULL THEN
    v_reason := NULLIF(BTRIM(COALESCE(
      v_new->>'memo', v_new->>'remarks', v_new->>'notes', ''
    )), '');
  END IF;

  -- A never-posted document has no reversal journal, and SELECT ... INTO sets
  -- EVERY target to NULL when it finds no row. Reading the reason back into
  -- v_reason therefore ERASED the reason resolved above whenever no reversal
  -- existed, so voiding any draft raised "a reason is required" no matter what
  -- reason was supplied. The fallback now lands in its own variable.
  SELECT je.id,
         NULLIF(BTRIM(REGEXP_REPLACE(COALESCE(je.description, ''), '^.* — ', '')), '')
  INTO v_reversal_je, v_je_reason
  FROM public.journal_entries je
  WHERE je.company_id = NEW.company_id
    AND je.reference_doc_id = NEW.id
    AND je.id IS DISTINCT FROM v_original_je
    AND je.status = 'posted'
  ORDER BY je.created_at DESC
  LIMIT 1;

  v_reason := COALESCE(v_reason, v_je_reason);

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A cancellation/void reason is required for CAS audit evidence';
  END IF;

  SELECT i.id INTO v_issuance_id
  FROM public.cas_document_number_issuances i
  WHERE i.source_table = TG_TABLE_NAME AND i.source_id = NEW.id;

  INSERT INTO public.cas_document_void_events (
    company_id, branch_id, number_issuance_id, source_table, source_id,
    document_code, document_number, document_date, terminal_status,
    reason_code_id, reason_text, event_actor_id,
    original_journal_entry_id, reversal_journal_entry_id,
    party_id, party_type, party_name, party_tin, document_amount,
    source_snapshot, occurred_at
  ) VALUES (
    NEW.company_id, v_branch, v_issuance_id, TG_TABLE_NAME, NEW.id,
    v_code, v_number, v_date, NEW.status,
    v_reason_id, v_reason, auth.uid(),
    v_original_je, v_reversal_je,
    v_party_id, NULLIF(TG_ARGV[5], ''), v_party_name, v_party_tin, v_amount,
    v_old, NOW()
  ) ON CONFLICT (source_table, source_id, terminal_status) DO NOTHING;

  UPDATE public.cas_document_number_issuances
  SET status = 'voided', voided_at = NOW(), void_reason = v_reason
  WHERE id = v_issuance_id AND status IN ('reserved', 'issued');

  RETURN NEW;
END;
$$;


-- ── 5. THE SAME ROOT CAUSE, one layer down: the LINE guard ────────────────────
-- `fn_post_delivery_receipt` also stamps its lines — `unit_cost`,
-- `inventory_cost` and `inventory_transaction_id` are written back after the
-- costing runs. `trg_guard_lines_delivery_receipt_lines` allows line changes only
-- while the parent is draft/in_transit, so that write is refused too once the
-- delivery was marked delivered in an earlier transaction:
--
--   delivery_receipt_lines cannot be changed: parent delivery_receipts <id> is
--   "delivered" (line changes allowed only in: draft, in_transit).
--
-- Reproduced by `scripts/verify_delivery_receipt_lifecycle.mjs` after §2 fixed
-- the header. Both guards had to be widened for a delivery to post at all from
-- the screen; neither could be seen from inside a single transaction.
--
-- `fn_guard_doc_lines` has no per-column allowance, while its header sibling
-- `fn_guard_doc_header` has had one all along. This adds the same idea to the
-- line guard as an OPTIONAL SIXTH argument, so every existing trigger — which
-- passes five — behaves exactly as before. Only UPDATE is affected: inserting or
-- deleting a line on a locked parent stays refused.
CREATE OR REPLACE FUNCTION public.fn_guard_doc_lines()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_table TEXT   := TG_ARGV[0];
  v_fk_col       TEXT   := TG_ARGV[1];
  v_status_col   TEXT   := TG_ARGV[2];
  v_editable     TEXT[] := string_to_array(TG_ARGV[3], ',');
  v_same_txn_ok  BOOLEAN := TG_NARGS > 4 AND TG_ARGV[4] = 'same_txn';
  -- Columns a locked parent's line may still have written to it, so the
  -- document's own posting function can stamp its costing results back.
  v_locked_cols  TEXT[] := CASE WHEN TG_NARGS > 5 AND TG_ARGV[5] <> ''
                                THEN string_to_array(TG_ARGV[5], ',')
                                ELSE ARRAY[]::TEXT[] END;
  v_ids          UUID[];
  v_id           UUID;
  v_status       TEXT;
  v_xmin         BIGINT;
  v_offending    TEXT[];
BEGIN
  -- PXL-AUD-070: preserved verbatim. The bypass needs pxl.allow_demo_reset AND a
  -- privileged session_user; it is not a user-settable flag.
  IF public.fn_demo_reset_bypass_authorized() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_ids := ARRAY[(to_jsonb(NEW)->>v_fk_col)::UUID];
  ELSIF TG_OP = 'DELETE' THEN
    v_ids := ARRAY[(to_jsonb(OLD)->>v_fk_col)::UUID];
  ELSE
    v_ids := ARRAY[(to_jsonb(OLD)->>v_fk_col)::UUID];
    IF to_jsonb(NEW)->>v_fk_col IS DISTINCT FROM to_jsonb(OLD)->>v_fk_col THEN
      v_ids := v_ids || (to_jsonb(NEW)->>v_fk_col)::UUID;
    END IF;
  END IF;

  FOREACH v_id IN ARRAY v_ids LOOP
    IF v_id IS NULL THEN
      RAISE EXCEPTION '% rows must reference a parent document (% is null).',
        TG_TABLE_NAME, v_fk_col;
    END IF;

    EXECUTE format('SELECT %I::text, xmin::text::bigint FROM %I WHERE id = $1',
                   v_status_col, v_parent_table)
      INTO v_status, v_xmin USING v_id;

    IF v_status IS NULL THEN
      RAISE EXCEPTION 'Parent % row % not found for % mutation.',
        v_parent_table, v_id, TG_TABLE_NAME;
    END IF;

    IF v_status = ANY (v_editable) THEN
      CONTINUE;
    END IF;

    IF v_same_txn_ok AND fn_row_written_by_current_txn(v_xmin) THEN
      CONTINUE;
    END IF;

    IF TG_OP = 'UPDATE' AND array_length(v_locked_cols, 1) IS NOT NULL THEN
      v_offending := ARRAY(
        SELECT k FROM jsonb_object_keys(to_jsonb(OLD)) AS k
        WHERE to_jsonb(OLD)->k IS DISTINCT FROM to_jsonb(NEW)->k
          AND k <> ALL (v_locked_cols)
      );
      IF array_length(v_offending, 1) IS NULL THEN
        CONTINUE;
      END IF;
    END IF;

    RAISE EXCEPTION '% cannot be changed: parent % % is "%" (line changes allowed only in: %).',
      TG_TABLE_NAME, v_parent_table, v_id, v_status, array_to_string(v_editable, ', ');
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

COMMENT ON FUNCTION public.fn_guard_doc_lines() IS
  'Generic status-aware line immutability guard (PXL-DA-011). Args: parent table, FK column, parent status column, CSV of editable statuses, optional same_txn flag, optional CSV of columns an UPDATE may still write while the parent is locked (Backlog 18c). PXL-AUD-070: the demo-reset bypass requires fn_demo_reset_bypass_authorized() (pxl.allow_demo_reset=on AND a privileged session_user); a user-settable GUC alone can no longer disable immutability.';

DROP TRIGGER IF EXISTS trg_guard_lines_delivery_receipt_lines ON delivery_receipt_lines;
CREATE TRIGGER trg_guard_lines_delivery_receipt_lines
  BEFORE INSERT OR UPDATE OR DELETE ON delivery_receipt_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines(
    'delivery_receipts', 'dr_id', 'status', 'draft,in_transit', 'same_txn',
    'unit_cost,inventory_cost,inventory_transaction_id,updated_at,updated_by');
