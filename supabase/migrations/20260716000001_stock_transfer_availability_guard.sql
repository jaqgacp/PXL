-- Enforce warehouse-level availability on stock transfers before mutating stock.
--
-- PXL-AUD-054: fn_post_stock_transfer previously updated the source warehouse
-- balance without checking qty_on_hand, allowing negative stock even when the
-- canonical demo configuration requires negative inventory to be disabled.
--
-- The same migration also adds a narrow, opt-in reset escape hatch to document
-- immutability triggers. It is only active when the caller has explicitly set
-- `pxl.allow_demo_reset = 'on'`, which is required by canonical_demo_reset.sql.

CREATE OR REPLACE FUNCTION public.fn_block_si_line_mutation_after_draft()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
  v_posting_internal BOOLEAN := COALESCE(current_setting('pxl.sales_invoice_posting_internal', true), '') = 'on';
BEGIN
  IF current_setting('pxl.allow_demo_reset', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.sales_invoice_id;
  ELSE
    v_parent_id := NEW.sales_invoice_id;
  END IF;

  SELECT status INTO v_status
  FROM sales_invoices
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Sales invoice not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    IF v_posting_internal
       AND TG_OP = 'UPDATE'
       AND NEW.id IS NOT DISTINCT FROM OLD.id
       AND NEW.sales_invoice_id IS NOT DISTINCT FROM OLD.sales_invoice_id
       AND NEW.company_id IS NOT DISTINCT FROM OLD.company_id
       AND NEW.line_number IS NOT DISTINCT FROM OLD.line_number
       AND NEW.item_id IS NOT DISTINCT FROM OLD.item_id
       AND NEW.description IS NOT DISTINCT FROM OLD.description
       AND NEW.quantity IS NOT DISTINCT FROM OLD.quantity
       AND NEW.uom_id IS NOT DISTINCT FROM OLD.uom_id
       AND NEW.unit_price IS NOT DISTINCT FROM OLD.unit_price
       AND NEW.discount_percent IS NOT DISTINCT FROM OLD.discount_percent
       AND NEW.discount_amount IS NOT DISTINCT FROM OLD.discount_amount
       AND NEW.net_amount IS NOT DISTINCT FROM OLD.net_amount
       AND NEW.vat_code_id IS NOT DISTINCT FROM OLD.vat_code_id
       AND NEW.vat_amount IS NOT DISTINCT FROM OLD.vat_amount
       AND NEW.total_amount IS NOT DISTINCT FROM OLD.total_amount
       AND NEW.revenue_account_id IS NOT DISTINCT FROM OLD.revenue_account_id
       AND NEW.warehouse_id IS NOT DISTINCT FROM OLD.warehouse_id
       AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id
       AND NEW.cost_center_id IS NOT DISTINCT FROM OLD.cost_center_id
       AND NEW.salesperson_id IS NOT DISTINCT FROM OLD.salesperson_id
       AND NEW.remarks IS NOT DISTINCT FROM OLD.remarks
       AND NEW.source_document_type IS NOT DISTINCT FROM OLD.source_document_type
       AND NEW.source_line_id IS NOT DISTINCT FROM OLD.source_line_id
       AND NEW.created_by IS NOT DISTINCT FROM OLD.created_by
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Sales invoice lines cannot be changed when the invoice status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_block_receipt_line_mutation_after_draft()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF current_setting('pxl.allow_demo_reset', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.receipt_id;
  ELSE
    v_parent_id := NEW.receipt_id;
  END IF;

  SELECT status INTO v_status
  FROM receipts
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Receipt not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Receipt lines cannot be changed when the receipt status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_block_vb_line_mutation_after_draft()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF current_setting('pxl.allow_demo_reset', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.vendor_bill_id;
  ELSE
    v_parent_id := NEW.vendor_bill_id;
  END IF;

  SELECT status INTO v_status
  FROM vendor_bills
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Vendor bill not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Vendor bill lines cannot be changed when the bill status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_block_pv_line_mutation_after_draft()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF current_setting('pxl.allow_demo_reset', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.payment_voucher_id;
  ELSE
    v_parent_id := NEW.payment_voucher_id;
  END IF;

  SELECT status INTO v_status
  FROM payment_vouchers
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Payment voucher lines cannot be changed when the voucher status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

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
  v_ids          UUID[];
  v_id           UUID;
  v_status       TEXT;
  v_xmin         BIGINT;
BEGIN
  IF current_setting('pxl.allow_demo_reset', true) = 'on' THEN
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

    RAISE EXCEPTION '% cannot be changed: parent % % is "%" (line changes allowed only in: %).',
      TG_TABLE_NAME, v_parent_table, v_id, v_status, array_to_string(v_editable, ', ');
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

COMMENT ON FUNCTION public.fn_guard_doc_lines() IS
  'Generic status-aware line immutability guard (PXL-DA-011). Args: parent table, FK column, parent status column, CSV of editable statuses, optional same_txn flag. Demo reset bypass requires pxl.allow_demo_reset=on.';

CREATE OR REPLACE FUNCTION public.fn_guard_doc_header()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status_col  TEXT   := TG_ARGV[0];
  v_editable    TEXT[] := string_to_array(TG_ARGV[1], ',');
  v_extra       TEXT[] := CASE WHEN TG_NARGS > 2 AND TG_ARGV[2] <> ''
                               THEN string_to_array(TG_ARGV[2], ',')
                               ELSE ARRAY[]::TEXT[] END;
  v_frozen      TEXT[] := CASE WHEN TG_NARGS > 3 AND TG_ARGV[3] <> ''
                               THEN string_to_array(TG_ARGV[3], ',')
                               ELSE ARRAY[]::TEXT[] END;
  v_same_txn_ok BOOLEAN := TG_NARGS > 4 AND TG_ARGV[4] = 'same_txn';
  v_old         JSONB;
  v_new         JSONB;
  v_old_status  TEXT;
  v_allowed     TEXT[];
  v_offending   TEXT[];
  v_xmin        BIGINT;
BEGIN
  IF current_setting('pxl.allow_demo_reset', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_old := to_jsonb(OLD);
  v_old_status := v_old->>v_status_col;

  IF v_old_status = ANY (v_editable) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_same_txn_ok THEN
    EXECUTE format('SELECT xmin::text::bigint FROM %I WHERE id = $1', TG_TABLE_NAME)
      INTO v_xmin USING OLD.id;
    IF fn_row_written_by_current_txn(v_xmin) THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '% % cannot be deleted in status "%" (deletable only in: %); void or reverse instead.',
      TG_TABLE_NAME, OLD.id, v_old_status, array_to_string(v_editable, ', ');
  END IF;

  IF v_old_status = ANY (v_frozen) THEN
    v_allowed := ARRAY['updated_at', 'updated_by'];
  ELSE
    v_allowed := ARRAY[v_status_col, 'updated_at', 'updated_by'] || v_extra;
  END IF;

  v_new := to_jsonb(NEW);
  v_offending := ARRAY(
    SELECT k FROM jsonb_object_keys(v_old) AS k
    WHERE v_old->k IS DISTINCT FROM v_new->k
      AND k <> ALL (v_allowed)
  );

  IF array_length(v_offending, 1) IS NOT NULL THEN
    RAISE EXCEPTION '% % is "%" and immutable: column(s) [%] cannot change (allowed: %).',
      TG_TABLE_NAME, OLD.id, v_old_status,
      array_to_string(v_offending, ', '), array_to_string(v_allowed, ', ');
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.fn_guard_doc_header() IS
  'Generic status-aware header immutability guard (PXL-DA-011). Args: status column, CSV editable statuses, CSV extra allowed columns when locked, CSV frozen statuses, optional same_txn flag. Demo reset bypass requires pxl.allow_demo_reset=on.';

CREATE OR REPLACE FUNCTION public.fn_post_stock_transfer_source_locked_impl(p_transfer_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tx       stock_transfers%ROWTYPE;
  v_line     stock_transfer_lines%ROWTYPE;
  v_item     items%ROWTYPE;
  v_from_wh  warehouses%ROWTYPE;
  v_to_wh    warehouses%ROWTYPE;
  v_from_sb  stock_balances%ROWTYPE;
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

    SELECT * INTO v_from_sb
    FROM stock_balances
    WHERE warehouse_id = v_tx.from_warehouse_id
      AND item_id = v_line.item_id
    FOR UPDATE;

    IF COALESCE(v_from_sb.qty_on_hand, 0) < v_line.qty_transferred THEN
      RAISE EXCEPTION 'Insufficient stock for transfer item %. Source warehouse on hand: %, requested: %',
        COALESCE(v_item.item_code, v_item.description),
        COALESCE(v_from_sb.qty_on_hand, 0),
        v_line.qty_transferred;
    END IF;

    v_uc := 0;
    v_total := 0;

    IF v_item.costing_method = 'weighted_average'
       OR v_item.costing_method IS NULL THEN
      v_uc := COALESCE(v_from_sb.wac_unit_cost, 0);
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
