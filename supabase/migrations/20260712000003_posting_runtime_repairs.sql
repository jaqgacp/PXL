-- Runtime posting repairs discovered while validating the deployed function
-- bodies against the physical schema.
--
-- 1. Restore the explicit receiving-report link used by vendor bills and
--    purchase returns.
-- 2. Keep physical-count variance cost derived instead of writing a missing
--    redundant column.
-- 3. Allocate stock-transfer JE numbers from the source warehouse branch while
--    retaining the intentionally branch-less JE header.

-- ---------------------------------------------------------------------------
-- Vendor bill -> receiving report source link
-- ---------------------------------------------------------------------------

ALTER TABLE public.vendor_bills
  ADD COLUMN IF NOT EXISTS rr_id UUID REFERENCES public.receiving_reports(id);

CREATE INDEX IF NOT EXISTS idx_vendor_bills_rr_id
  ON public.vendor_bills (rr_id);

CREATE OR REPLACE FUNCTION public.fn_save_vendor_bill(
  p_bill_id UUID,
  p_header  JSONB,
  p_lines   JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_bill_id        UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_supplier_id    UUID;
  v_rr_id          UUID;
  v_bill_number    TEXT;
  v_current_status TEXT;
  v_fiscal_period  UUID;
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
  v_taxable        NUMERIC(15,2) := 0;
  v_zero_rated     NUMERIC(15,2) := 0;
  v_exempt         NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_grand_total    NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
BEGIN
  v_company_id  := (p_header->>'company_id')::UUID;
  v_branch_id   := NULLIF(p_header->>'branch_id', '')::UUID;
  v_supplier_id := NULLIF(p_header->>'supplier_id', '')::UUID;
  v_rr_id       := NULLIF(BTRIM(p_header->>'rr_id'), '')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM suppliers
    WHERE id = v_supplier_id
      AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  IF v_rr_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM receiving_reports rr
    WHERE rr.id = v_rr_id
      AND rr.company_id = v_company_id
      AND rr.supplier_id = v_supplier_id
      AND rr.status = 'received'
  ) THEN
    RAISE EXCEPTION 'Receiving report must be received and belong to the same company and supplier';
  END IF;

  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'bill_date')::DATE
    AND end_date >= (p_header->>'bill_date')::DATE
    AND is_locked = false
  LIMIT 1;

  IF p_bill_id IS NULL THEN
    v_bill_number := fn_next_document_number(v_company_id, v_branch_id, 'VB');
    INSERT INTO vendor_bills (
      company_id, branch_id, supplier_id, rr_id,
      supplier_name_snapshot, supplier_tin_snapshot,
      bill_number, supplier_invoice_number, bill_date, due_date, fiscal_period_id,
      payment_terms_id, currency_code, reference, memo,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_input_vat_amount, total_amount, ewt_amount_expected,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_supplier_id, v_rr_id,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      v_bill_number, NULLIF(p_header->>'supplier_invoice_number', ''),
      (p_header->>'bill_date')::DATE, NULLIF(p_header->>'due_date', '')::DATE,
      v_fiscal_period, NULLIF(p_header->>'payment_terms_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      0, 0, 0, 0, 0,
      NULLIF(p_header->>'ewt_amount_expected', '')::NUMERIC,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_bill_id;
  ELSE
    SELECT id, status INTO v_bill_id, v_current_status
    FROM vendor_bills
    WHERE id = p_bill_id
      AND company_id = v_company_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Vendor bill not found or access denied';
    END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % vendor bill. Revert to draft first.', v_current_status;
    END IF;

    UPDATE vendor_bills SET
      branch_id = v_branch_id,
      supplier_id = v_supplier_id,
      rr_id = v_rr_id,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      supplier_invoice_number = NULLIF(p_header->>'supplier_invoice_number', ''),
      bill_date = (p_header->>'bill_date')::DATE,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      fiscal_period_id = v_fiscal_period,
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      reference = NULLIF(p_header->>'reference', ''),
      memo = NULLIF(p_header->>'memo', ''),
      ewt_amount_expected = NULLIF(p_header->>'ewt_amount_expected', '')::NUMERIC,
      total_taxable_amount = 0,
      total_zero_rated_amount = 0,
      total_exempt_amount = 0,
      total_input_vat_amount = 0,
      total_amount = 0,
      updated_at = NOW(),
      updated_by = auth.uid()
    WHERE id = v_bill_id;
  END IF;

  DELETE FROM vendor_bill_lines WHERE vendor_bill_id = v_bill_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_vat_class, v_vat_rate
    FROM vat_codes vc
    JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE
      WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2)
      ELSE 0
    END;
    v_total_line := v_net + v_vat_amt;

    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt + v_net;
    END CASE;
    v_total_vat   := v_total_vat + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO vendor_bill_lines (
      vendor_bill_id, company_id, line_number, item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, input_vat_amount, total_amount,
      expense_account_id, created_by, updated_by
    ) VALUES (
      v_bill_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0), v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'At least one non-empty line is required';
  END IF;

  UPDATE vendor_bills SET
    total_taxable_amount = v_taxable,
    total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt,
    total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total,
    updated_at = NOW()
  WHERE id = v_bill_id;

  RETURN v_bill_id;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Stock transfer implementation: source-branch numbering, branch-less JE
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_post_stock_transfer_source_locked_impl(
  p_transfer_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_tx       stock_transfers%ROWTYPE;
  v_line     stock_transfer_lines%ROWTYPE;
  v_item     items%ROWTYPE;
  v_from_wh  warehouses%ROWTYPE;
  v_to_wh    warehouses%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line_no  INT := 1;
  v_layer    RECORD;
  v_uc       NUMERIC;
  v_total    NUMERIC := 0;
BEGIN
  SELECT * INTO v_tx FROM stock_transfers WHERE id = p_transfer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found'; END IF;
  IF NOT is_company_member(v_tx.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_tx.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT * INTO v_from_wh FROM warehouses WHERE id = v_tx.from_warehouse_id;
  SELECT * INTO v_to_wh   FROM warehouses WHERE id = v_tx.to_warehouse_id;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_tx.company_id
    AND start_date <= v_tx.transfer_date
    AND end_date >= v_tx.transfer_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for date %', v_tx.transfer_date;
  END IF;

  FOR v_line IN
    SELECT * FROM stock_transfer_lines WHERE transfer_id = p_transfer_id
  LOOP
    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    PERFORM fn_ensure_stock_balance(
      v_tx.company_id, v_tx.from_warehouse_id, v_line.item_id
    );
    PERFORM fn_ensure_stock_balance(
      v_tx.company_id, v_tx.to_warehouse_id, v_line.item_id
    );

    v_uc := 0;
    v_total := 0;

    IF v_item.costing_method = 'weighted_average'
       OR v_item.costing_method IS NULL THEN
      SELECT wac_unit_cost INTO v_uc
      FROM stock_balances
      WHERE warehouse_id = v_tx.from_warehouse_id
        AND item_id = v_line.item_id;
      v_uc    := COALESCE(v_uc, 0);
      v_total := ROUND(v_line.qty_transferred * v_uc, 2);

      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand - v_line.qty_transferred,
          total_cost = GREATEST(total_cost - v_total, 0),
          last_issue_date = v_tx.transfer_date,
          updated_at = NOW()
      WHERE warehouse_id = v_tx.from_warehouse_id
        AND item_id = v_line.item_id;

      PERFORM fn_update_wac(
        v_tx.to_warehouse_id, v_line.item_id, v_line.qty_transferred, v_uc
      );
      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand + v_line.qty_transferred,
          total_cost = total_cost + v_total,
          last_receipt_date = v_tx.transfer_date,
          updated_at = NOW()
      WHERE warehouse_id = v_tx.to_warehouse_id
        AND item_id = v_line.item_id;
      UPDATE stock_balances
      SET wac_unit_cost = CASE
        WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6)
        ELSE 0
      END
      WHERE warehouse_id = v_tx.to_warehouse_id
        AND item_id = v_line.item_id;
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_tx.company_id, v_tx.from_warehouse_id, v_line.item_id,
          v_line.qty_transferred, v_line.lot_number, v_line.serial_number
        )
      LOOP
        v_total := v_total + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
        PERFORM fn_add_cost_layer(
          v_tx.company_id, v_tx.to_warehouse_id, v_line.item_id,
          v_tx.transfer_date, v_layer.qty_consumed, v_layer.unit_cost,
          'STX', p_transfer_id, v_line.lot_number, v_line.serial_number
        );
        v_uc := v_layer.unit_cost;
      END LOOP;

      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand - v_line.qty_transferred,
          total_cost = GREATEST(total_cost - v_total, 0),
          last_issue_date = v_tx.transfer_date,
          updated_at = NOW()
      WHERE warehouse_id = v_tx.from_warehouse_id
        AND item_id = v_line.item_id;

      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand + v_line.qty_transferred,
          total_cost = total_cost + v_total,
          last_receipt_date = v_tx.transfer_date,
          updated_at = NOW()
      WHERE warehouse_id = v_tx.to_warehouse_id
        AND item_id = v_line.item_id;
    END IF;

    UPDATE stock_transfer_lines
    SET unit_cost = ROUND(v_total / v_line.qty_transferred, 6),
        total_cost = v_total
    WHERE id = v_line.id;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
    )
    SELECT v_tx.company_id, v_tx.from_warehouse_id, v_line.item_id,
      'transfer_out', v_tx.transfer_date,
      -v_line.qty_transferred, ROUND(v_total / v_line.qty_transferred, 6), -v_total,
      qty_on_hand, v_item.costing_method,
      'STX', p_transfer_id, v_line.lot_number, v_line.serial_number, auth.uid()
    FROM stock_balances
    WHERE warehouse_id = v_tx.from_warehouse_id
      AND item_id = v_line.item_id;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
    )
    SELECT v_tx.company_id, v_tx.to_warehouse_id, v_line.item_id,
      'transfer_in', v_tx.transfer_date,
      v_line.qty_transferred, ROUND(v_total / v_line.qty_transferred, 6), v_total,
      qty_on_hand, v_item.costing_method,
      'STX', p_transfer_id, v_line.lot_number, v_line.serial_number, auth.uid()
    FROM stock_balances
    WHERE warehouse_id = v_tx.to_warehouse_id
      AND item_id = v_line.item_id;
  END LOOP;

  IF v_from_wh.gl_inventory_account_id IS NOT NULL
     AND v_to_wh.gl_inventory_account_id IS NOT NULL
     AND v_from_wh.gl_inventory_account_id <> v_to_wh.gl_inventory_account_id THEN

    IF v_from_wh.branch_id IS NULL THEN
      RAISE EXCEPTION
        'Source warehouse % has no branch; cannot allocate a JE number for stock transfer %',
        v_from_wh.warehouse_code, v_tx.transfer_number;
    END IF;

    SELECT SUM(total_cost) INTO v_total
    FROM stock_transfer_lines
    WHERE transfer_id = p_transfer_id;

    -- branch_id remains intentionally absent from the JE header. Cross-branch
    -- stock transfers use the source branch only to govern number allocation.
    INSERT INTO journal_entries (
      company_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_tx.company_id,
      fn_next_document_number(v_tx.company_id, v_from_wh.branch_id, 'JE'),
      v_tx.transfer_date, v_fp_id,
      'Stock Transfer: ' || v_tx.transfer_number,
      'INV_STX', p_transfer_id, 'posted', v_total, v_total,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;

    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES
      (
        v_je_id, v_tx.company_id, 1, v_to_wh.gl_inventory_account_id,
        'Transfer in', v_total, 0, auth.uid(), auth.uid()
      ),
      (
        v_je_id, v_tx.company_id, 2, v_from_wh.gl_inventory_account_id,
        'Transfer out', 0, v_total, auth.uid(), auth.uid()
      );
  END IF;

  UPDATE stock_transfers
  SET status = 'posted',
      journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id,
      posted_at = NOW(),
      posted_by = auth.uid(),
      updated_by = auth.uid(),
      updated_at = NOW()
  WHERE id = p_transfer_id;

  RETURN v_je_id;
END;
$function$;


-- ---------------------------------------------------------------------------
-- Purchase return implementation (the public wrapper remains authoritative)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_complete_purchase_return_source_locked_impl(
  p_return_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_rec        purchase_returns%ROWTYPE;
  v_cfg        company_accounting_config%ROWTYPE;
  v_fp_id      UUID;
  v_je_id      UUID;
  v_vb_id      UUID;
  v_vb_count   INTEGER := 0;
  v_line       RECORD;
  v_line_no    INT := 1;
  v_total_cr   NUMERIC(15,2) := 0;
  v_ret_total  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec
  FROM purchase_returns
  WHERE id = p_return_id;

  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Not found or access denied';
  END IF;
  IF v_rec.status != 'shipped' THEN
    RAISE EXCEPTION 'Only shipped returns can be completed (current: %)', v_rec.status;
  END IF;

  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;

  SELECT COUNT(*)::INTEGER
  INTO v_vb_count
  FROM vendor_bills vb
  WHERE vb.rr_id = v_rec.rr_id
    AND vb.company_id = v_rec.company_id
    AND vb.supplier_id = v_rec.supplier_id
    AND vb.status = 'posted';

  IF v_vb_count = 0 THEN
    RAISE EXCEPTION
      'Purchase return % cannot complete: its receiving report has no linked posted vendor bill',
      v_rec.return_number;
  ELSIF v_vb_count > 1 THEN
    RAISE EXCEPTION
      'Purchase return % cannot complete: its receiving report is linked to % posted vendor bills; an unambiguous bill link is required',
      v_rec.return_number, v_vb_count;
  END IF;

  SELECT vb.id INTO v_vb_id
  FROM vendor_bills vb
  WHERE vb.rr_id = v_rec.rr_id
    AND vb.company_id = v_rec.company_id
    AND vb.supplier_id = v_rec.supplier_id
    AND vb.status = 'posted';

  IF v_cfg.ap_account_id IS NULL THEN
    RAISE EXCEPTION 'AP account is not configured for purchase return %',
      v_rec.return_number;
  END IF;

  -- A return against a posted bill reverses AP on the return's accounting date.
  IF v_vb_id IS NOT NULL THEN
    SELECT id INTO v_fp_id
    FROM fiscal_periods
    WHERE company_id = v_rec.company_id
      AND start_date <= v_rec.return_date
      AND end_date >= v_rec.return_date
      AND is_locked = false
    LIMIT 1;

    IF v_fp_id IS NULL THEN
      RAISE EXCEPTION 'No open fiscal period for purchase return date %', v_rec.return_date;
    END IF;

    SELECT COALESCE(SUM(prl.return_qty * prl.unit_price), 0)
    INTO v_ret_total
    FROM purchase_return_lines prl
    WHERE prl.return_id = p_return_id;

    IF v_ret_total > 0 THEN
      INSERT INTO journal_entries (
        company_id, branch_id, je_number, je_date, fiscal_period_id,
        description, reference_doc_type, reference_doc_id, status,
        total_debit, total_credit, created_by, updated_by
      ) VALUES (
        v_rec.company_id, v_rec.branch_id,
        fn_next_document_number(v_rec.company_id, v_rec.branch_id, 'JE'),
        v_rec.return_date, v_fp_id,
        'Purchase Return ' || v_rec.return_number || ' — ' || v_rec.supplier_name_snapshot,
        'PR', v_rec.id, 'posted',
        v_ret_total, v_ret_total,
        auth.uid(), auth.uid()
      ) RETURNING id INTO v_je_id;

      INSERT INTO journal_entry_lines (
        je_id, company_id, line_number, account_id, description,
        debit_amount, credit_amount, created_by, updated_by
      ) VALUES (
        v_je_id, v_rec.company_id, 1, v_cfg.ap_account_id,
        'AP reversal — ' || v_rec.return_number,
        v_ret_total, 0, auth.uid(), auth.uid()
      );

      FOR v_line IN
        SELECT vbl.expense_account_id,
               SUM(LEAST(prl.return_qty, rrl.received_qty) * prl.unit_price) AS rev_amount,
               vbl.description AS ln_desc
        FROM purchase_return_lines prl
        JOIN receiving_report_lines rrl ON rrl.id = prl.rr_line_id
        JOIN vendor_bill_lines vbl
          ON vbl.vendor_bill_id = v_vb_id
         AND vbl.item_id = prl.item_id
        WHERE prl.return_id = p_return_id
          AND vbl.expense_account_id IS NOT NULL
        GROUP BY vbl.expense_account_id, vbl.description
      LOOP
        v_line_no := v_line_no + 1;
        INSERT INTO journal_entry_lines (
          je_id, company_id, line_number, account_id, description,
          debit_amount, credit_amount, created_by, updated_by
        ) VALUES (
          v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
          'Return of: ' || v_line.ln_desc,
          0, v_line.rev_amount, auth.uid(), auth.uid()
        );
        v_total_cr := v_total_cr + v_line.rev_amount;
      END LOOP;

      -- Preserve the historical no-JE fallback when none of the returned items
      -- can be mapped to an expense account on the linked posted bill.
      IF v_total_cr = 0 THEN
        UPDATE journal_entries
        SET total_debit = 0, total_credit = 0
        WHERE id = v_je_id;
        DELETE FROM journal_entry_lines WHERE je_id = v_je_id;
        DELETE FROM journal_entries WHERE id = v_je_id;
        v_je_id := NULL;
      END IF;
    END IF;
  END IF;

  UPDATE purchase_returns SET
    status = 'completed',
    journal_entry_id = v_je_id,
    updated_by = auth.uid(),
    updated_at = NOW()
  WHERE id = p_return_id;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Physical count implementation: variance cost remains a derived value
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_post_physical_count_source_locked_impl(
  p_sheet_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_cs       physical_count_sheets%ROWTYPE;
  v_line     physical_count_sheet_lines%ROWTYPE;
  v_item     items%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line_no  INT := 1;
  v_variance NUMERIC;
  v_uc       NUMERIC;
  v_je_total NUMERIC := 0;
BEGIN
  SELECT * INTO v_cs
  FROM physical_count_sheets
  WHERE id = p_sheet_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Count sheet not found'; END IF;
  IF NOT is_company_member(v_cs.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_cs.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT id INTO v_fp_id
  FROM fiscal_periods
  WHERE company_id = v_cs.company_id
    AND start_date <= v_cs.count_date
    AND end_date >= v_cs.count_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period for date %', v_cs.count_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_cs.company_id, v_cs.branch_id,
    fn_next_document_number(v_cs.company_id, v_cs.branch_id, 'JE'),
    v_cs.count_date, v_fp_id,
    'Physical Count Variance: ' || v_cs.count_number,
    'INV_COUNT', p_sheet_id, 'posted', 0, 0,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN
    SELECT * FROM physical_count_sheet_lines WHERE count_sheet_id = p_sheet_id
  LOOP
    v_variance := COALESCE(v_line.counted_qty, v_line.system_qty) - v_line.system_qty;
    CONTINUE WHEN v_variance = 0;

    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    PERFORM fn_ensure_stock_balance(
      v_cs.company_id, v_cs.warehouse_id, v_line.item_id
    );

    SELECT wac_unit_cost INTO v_uc
    FROM stock_balances
    WHERE warehouse_id = v_cs.warehouse_id
      AND item_id = v_line.item_id;
    v_uc := COALESCE(
      CASE WHEN v_line.unit_cost > 0 THEN v_line.unit_cost ELSE NULL END,
      v_uc, v_item.standard_cost, 0
    );

    UPDATE stock_balances
    SET qty_on_hand = qty_on_hand + v_variance,
        total_cost = GREATEST(total_cost + (v_variance * v_uc), 0),
        updated_at = NOW()
    WHERE warehouse_id = v_cs.warehouse_id
      AND item_id = v_line.item_id;

    IF v_item.costing_method = 'weighted_average'
       OR v_item.costing_method IS NULL THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE
        WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6)
        ELSE 0
      END
      WHERE warehouse_id = v_cs.warehouse_id
        AND item_id = v_line.item_id;
    END IF;

    IF v_item.costing_method IN ('fifo', 'specific_identification') THEN
      IF v_variance > 0 THEN
        PERFORM fn_add_cost_layer(
          v_cs.company_id, v_cs.warehouse_id, v_line.item_id,
          v_cs.count_date, v_variance, v_uc, 'COUNT', p_sheet_id,
          v_line.lot_number, v_line.serial_number
        );
      ELSE
        PERFORM fn_consume_cost_layers(
          v_cs.company_id, v_cs.warehouse_id, v_line.item_id,
          ABS(v_variance), v_line.lot_number, v_line.serial_number
        );
      END IF;
    END IF;

    -- counted/system quantity and the frozen unit cost are sufficient to
    -- reproduce variance cost; inventory_transactions stores the posted value.
    UPDATE physical_count_sheet_lines
    SET unit_cost = v_uc
    WHERE id = v_line.id;

    DECLARE
      v_inv_acct UUID;
      v_var_acct UUID;
      v_impact   NUMERIC;
    BEGIN
      SELECT inventory_account_id INTO v_inv_acct
      FROM items
      WHERE id = v_line.item_id;
      v_var_acct := COALESCE(
        v_line.gl_variance_account_id,
        (
          SELECT gl_variance_account_id
          FROM warehouses
          WHERE id = v_cs.warehouse_id
        )
      );
      v_impact := ROUND(v_variance * v_uc, 2);
      v_je_total := v_je_total + ABS(v_impact);

      IF v_inv_acct IS NOT NULL AND v_var_acct IS NOT NULL THEN
        INSERT INTO journal_entry_lines (
          je_id, company_id, line_number, account_id, description,
          debit_amount, credit_amount, created_by, updated_by
        ) VALUES
          (
            v_je_id, v_cs.company_id, v_line_no, v_inv_acct,
            'Count variance — ' || v_item.description,
            GREATEST(v_impact, 0), GREATEST(-v_impact, 0), auth.uid(), auth.uid()
          ),
          (
            v_je_id, v_cs.company_id, v_line_no + 1, v_var_acct,
            'Count variance — ' || v_item.description,
            GREATEST(-v_impact, 0), GREATEST(v_impact, 0), auth.uid(), auth.uid()
          );
        v_line_no := v_line_no + 2;
      END IF;
    END;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id,
      transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
    )
    SELECT v_cs.company_id, v_cs.warehouse_id, v_line.item_id,
      CASE
        WHEN v_variance >= 0 THEN 'count_variance_in'
        ELSE 'count_variance_out'
      END,
      v_cs.count_date,
      v_variance, v_uc, ROUND(v_variance * v_uc, 2),
      qty_on_hand, v_item.costing_method,
      'INV_COUNT', p_sheet_id, v_line.lot_number, v_line.serial_number, auth.uid()
    FROM stock_balances
    WHERE warehouse_id = v_cs.warehouse_id
      AND item_id = v_line.item_id;
  END LOOP;

  UPDATE journal_entries
  SET total_debit = v_je_total,
      total_credit = v_je_total
  WHERE id = v_je_id;

  UPDATE physical_count_sheets
  SET status = 'posted',
      journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id,
      posted_at = NOW(),
      posted_by = auth.uid(),
      updated_by = auth.uid(),
      updated_at = NOW()
  WHERE id = p_sheet_id;

  RETURN v_je_id;
END;
$function$;

-- CREATE OR REPLACE retains existing privileges. Repeat the internal ACL
-- contract explicitly so these implementation helpers cannot become RPCs.
REVOKE ALL ON FUNCTION public.fn_complete_purchase_return_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_post_stock_transfer_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_post_physical_count_source_locked_impl(UUID)
  FROM PUBLIC, anon, authenticated, service_role;
