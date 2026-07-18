-- Purchase document dimensions and inventory-receipt integration.
-- Adds governed header defaults for operational and accounting monitoring while
-- preserving every existing purchase document and the established RPC contracts.

ALTER TABLE purchase_orders
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id),
  ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);

ALTER TABLE receiving_reports
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id),
  ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);

ALTER TABLE vendor_bills
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id),
  ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);

ALTER TABLE cash_purchases
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id),
  ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);

CREATE INDEX IF NOT EXISTS idx_po_purchase_dimensions
  ON purchase_orders (company_id, warehouse_id, department_id, cost_center_id);
CREATE INDEX IF NOT EXISTS idx_rr_purchase_dimensions
  ON receiving_reports (company_id, warehouse_id, department_id, cost_center_id);
CREATE INDEX IF NOT EXISTS idx_vb_purchase_dimensions
  ON vendor_bills (company_id, warehouse_id, department_id, cost_center_id);
CREATE INDEX IF NOT EXISTS idx_cp_purchase_dimensions
  ON cash_purchases (company_id, warehouse_id, department_id, cost_center_id);

CREATE OR REPLACE FUNCTION fn_validate_purchase_dimensions(
  p_company_id UUID,
  p_branch_id UUID,
  p_warehouse_id UUID,
  p_department_id UUID,
  p_cost_center_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dimension_branch UUID;
  v_dimension_department UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  IF p_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches
    WHERE id = p_branch_id AND company_id = p_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Branch is inactive or does not belong to this company';
  END IF;

  IF p_warehouse_id IS NOT NULL THEN
    SELECT branch_id INTO v_dimension_branch
    FROM warehouses
    WHERE id = p_warehouse_id AND company_id = p_company_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Warehouse is inactive or does not belong to this company';
    END IF;
    IF p_branch_id IS NOT NULL AND v_dimension_branch IS NOT NULL
       AND v_dimension_branch <> p_branch_id THEN
      RAISE EXCEPTION 'Warehouse does not belong to the selected branch';
    END IF;
  END IF;

  IF p_department_id IS NOT NULL THEN
    SELECT branch_id INTO v_dimension_branch
    FROM departments
    WHERE id = p_department_id AND company_id = p_company_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Department is inactive or does not belong to this company';
    END IF;
    IF p_branch_id IS NOT NULL AND v_dimension_branch IS NOT NULL
       AND v_dimension_branch <> p_branch_id THEN
      RAISE EXCEPTION 'Department does not belong to the selected branch';
    END IF;
  END IF;

  IF p_cost_center_id IS NOT NULL THEN
    SELECT branch_id, department_id
    INTO v_dimension_branch, v_dimension_department
    FROM cost_centers
    WHERE id = p_cost_center_id AND company_id = p_company_id AND is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Cost center is inactive or does not belong to this company';
    END IF;
    IF p_branch_id IS NOT NULL AND v_dimension_branch IS NOT NULL
       AND v_dimension_branch <> p_branch_id THEN
      RAISE EXCEPTION 'Cost center does not belong to the selected branch';
    END IF;
    IF p_department_id IS NOT NULL AND v_dimension_department IS NOT NULL
       AND v_dimension_department <> p_department_id THEN
      RAISE EXCEPTION 'Cost center does not belong to the selected department';
    END IF;
  END IF;
END;
$$;

-- Keep the public save signatures stable and layer dimension persistence around
-- the already-governed source-document implementations.
ALTER FUNCTION fn_save_purchase_order(UUID, JSONB, JSONB)
  RENAME TO fn_save_purchase_order_core_20260718;

CREATE OR REPLACE FUNCTION fn_save_purchase_order(
  p_po_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := NULLIF(p_header->>'branch_id', '')::UUID;
  v_warehouse_id UUID := NULLIF(p_header->>'warehouse_id', '')::UUID;
  v_department_id UUID := NULLIF(p_header->>'department_id', '')::UUID;
  v_cost_center_id UUID := NULLIF(p_header->>'cost_center_id', '')::UUID;
BEGIN
  PERFORM fn_validate_purchase_dimensions(
    v_company_id, v_branch_id, v_warehouse_id, v_department_id, v_cost_center_id
  );
  v_id := fn_save_purchase_order_core_20260718(p_po_id, p_header, p_lines);
  UPDATE purchase_orders
  SET warehouse_id = v_warehouse_id,
      department_id = v_department_id,
      cost_center_id = v_cost_center_id,
      updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_id AND company_id = v_company_id;
  RETURN v_id;
END;
$$;

ALTER FUNCTION fn_save_receiving_report(UUID, JSONB, JSONB)
  RENAME TO fn_save_receiving_report_core_20260718;

CREATE OR REPLACE FUNCTION fn_save_receiving_report(
  p_rr_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := NULLIF(p_header->>'branch_id', '')::UUID;
  v_warehouse_id UUID;
  v_department_id UUID;
  v_cost_center_id UUID;
BEGIN
  SELECT
    COALESCE(NULLIF(p_header->>'warehouse_id', '')::UUID, po.warehouse_id),
    COALESCE(NULLIF(p_header->>'department_id', '')::UUID, po.department_id),
    COALESCE(NULLIF(p_header->>'cost_center_id', '')::UUID, po.cost_center_id)
  INTO v_warehouse_id, v_department_id, v_cost_center_id
  FROM purchase_orders po
  WHERE po.id = (p_header->>'po_id')::UUID AND po.company_id = v_company_id;

  PERFORM fn_validate_purchase_dimensions(
    v_company_id, v_branch_id, v_warehouse_id, v_department_id, v_cost_center_id
  );
  v_id := fn_save_receiving_report_core_20260718(p_rr_id, p_header, p_lines);
  UPDATE receiving_reports
  SET warehouse_id = v_warehouse_id,
      department_id = v_department_id,
      cost_center_id = v_cost_center_id,
      updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_id AND company_id = v_company_id;
  RETURN v_id;
END;
$$;

ALTER FUNCTION fn_save_vendor_bill(UUID, JSONB, JSONB)
  RENAME TO fn_save_vendor_bill_core_20260718;

CREATE OR REPLACE FUNCTION fn_save_vendor_bill(
  p_bill_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := NULLIF(p_header->>'branch_id', '')::UUID;
  v_rr_id UUID := NULLIF(p_header->>'rr_id', '')::UUID;
  v_warehouse_id UUID := NULLIF(p_header->>'warehouse_id', '')::UUID;
  v_department_id UUID := NULLIF(p_header->>'department_id', '')::UUID;
  v_cost_center_id UUID := NULLIF(p_header->>'cost_center_id', '')::UUID;
BEGIN
  IF v_rr_id IS NOT NULL THEN
    SELECT COALESCE(v_warehouse_id, warehouse_id),
           COALESCE(v_department_id, department_id),
           COALESCE(v_cost_center_id, cost_center_id)
    INTO v_warehouse_id, v_department_id, v_cost_center_id
    FROM receiving_reports
    WHERE id = v_rr_id AND company_id = v_company_id;
  END IF;

  PERFORM fn_validate_purchase_dimensions(
    v_company_id, v_branch_id, v_warehouse_id, v_department_id, v_cost_center_id
  );
  v_id := fn_save_vendor_bill_core_20260718(p_bill_id, p_header, p_lines);
  UPDATE vendor_bills
  SET warehouse_id = v_warehouse_id,
      department_id = v_department_id,
      cost_center_id = v_cost_center_id,
      updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_id AND company_id = v_company_id;
  RETURN v_id;
END;
$$;

ALTER FUNCTION fn_save_cash_purchase(UUID, JSONB, JSONB)
  RENAME TO fn_save_cash_purchase_core_20260718;

CREATE OR REPLACE FUNCTION fn_save_cash_purchase(
  p_cp_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := NULLIF(p_header->>'branch_id', '')::UUID;
  v_warehouse_id UUID := NULLIF(p_header->>'warehouse_id', '')::UUID;
  v_department_id UUID := NULLIF(p_header->>'department_id', '')::UUID;
  v_cost_center_id UUID := NULLIF(p_header->>'cost_center_id', '')::UUID;
BEGIN
  PERFORM fn_validate_purchase_dimensions(
    v_company_id, v_branch_id, v_warehouse_id, v_department_id, v_cost_center_id
  );
  v_id := fn_save_cash_purchase_core_20260718(p_cp_id, p_header, p_lines);
  UPDATE cash_purchases
  SET warehouse_id = v_warehouse_id,
      department_id = v_department_id,
      cost_center_id = v_cost_center_id,
      updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_id AND company_id = v_company_id;
  RETURN v_id;
END;
$$;

-- Goods Receipt confirmation is the authoritative inbound stock event.
ALTER FUNCTION fn_confirm_receiving_report(UUID)
  RENAME TO fn_confirm_receiving_report_status_core_20260718;

CREATE OR REPLACE FUNCTION fn_confirm_receiving_report(p_rr_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rr receiving_reports%ROWTYPE;
  v_receipt RECORD;
BEGIN
  SELECT * INTO v_rr
  FROM receiving_reports
  WHERE id = p_rr_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rr.company_id) THEN
    RAISE EXCEPTION 'Receiving report not found or access denied';
  END IF;
  IF v_rr.status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft RRs can be confirmed (current: %)', v_rr.status;
  END IF;

  PERFORM fn_validate_purchase_dimensions(
    v_rr.company_id, v_rr.branch_id, v_rr.warehouse_id,
    v_rr.department_id, v_rr.cost_center_id
  );

  IF EXISTS (
    SELECT 1
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.company_id <> v_rr.company_id
  ) THEN
    RAISE EXCEPTION 'A receiving-report item does not belong to this company';
  END IF;

  IF v_rr.warehouse_id IS NULL AND EXISTS (
    SELECT 1
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item'
  ) THEN
    RAISE EXCEPTION 'Warehouse is required to confirm inventory-item receipts';
  END IF;

  FOR v_receipt IN
    SELECT rrl.item_id,
           SUM(rrl.received_qty) AS qty,
           ROUND(SUM(rrl.received_qty * rrl.unit_price)
                 / NULLIF(SUM(rrl.received_qty), 0), 6) AS unit_cost
    FROM receiving_report_lines rrl
    JOIN items i ON i.id = rrl.item_id
    WHERE rrl.rr_id = v_rr.id
      AND rrl.received_qty > 0
      AND i.item_type = 'inventory_item'
    GROUP BY rrl.item_id
  LOOP
    PERFORM fn_receive_inventory(jsonb_build_object(
      'company_id', v_rr.company_id,
      'warehouse_id', v_rr.warehouse_id,
      'item_id', v_receipt.item_id,
      'qty', v_receipt.qty,
      'unit_cost', v_receipt.unit_cost,
      'receipt_date', v_rr.rr_date,
      'reference_doc_type', 'RR',
      'reference_doc_id', v_rr.id,
      'notes', COALESCE(v_rr.remarks, 'Goods Receipt ' || v_rr.rr_number)
    ));
  END LOOP;

  PERFORM fn_confirm_receiving_report_status_core_20260718(p_rr_id);
END;
$$;

-- Default journal-line monitoring dimensions from posting purchase documents.
ALTER FUNCTION fn_add_posting_line(UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID)
  RENAME TO fn_add_posting_line_core_20260718;

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
  v_source_type TEXT;
  v_source_id UUID;
  v_source_department UUID;
  v_source_cost_center UUID;
BEGIN
  SELECT reference_doc_type, reference_doc_id
  INTO v_source_type, v_source_id
  FROM journal_entries
  WHERE id = p_je_id;

  IF v_source_type = 'VB' THEN
    SELECT department_id, cost_center_id
    INTO v_source_department, v_source_cost_center
    FROM vendor_bills WHERE id = v_source_id;
  ELSIF v_source_type = 'CP' THEN
    SELECT department_id, cost_center_id
    INTO v_source_department, v_source_cost_center
    FROM cash_purchases WHERE id = v_source_id;
  END IF;

  RETURN fn_add_posting_line_core_20260718(
    p_je_id, p_line_number, p_account_id, p_description,
    p_debit, p_credit, p_branch_id,
    COALESCE(p_department_id, v_source_department),
    COALESCE(p_cost_center_id, v_source_cost_center)
  );
END;
$$;

-- Immediate inventory purchases receive stock only after the governed CP post
-- succeeds. The whole operation remains one database transaction.
ALTER FUNCTION fn_post_cash_purchase(UUID)
  RENAME TO fn_post_cash_purchase_core_20260718;

CREATE OR REPLACE FUNCTION fn_post_cash_purchase(p_cp_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cp cash_purchases%ROWTYPE;
  v_receipt RECORD;
BEGIN
  SELECT * INTO v_cp
  FROM cash_purchases
  WHERE id = p_cp_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_cp.company_id) THEN
    RAISE EXCEPTION 'Cash purchase not found or access denied';
  END IF;

  IF v_cp.status <> 'draft' THEN
    PERFORM fn_post_cash_purchase_core_20260718(p_cp_id);
    RETURN;
  END IF;

  PERFORM fn_validate_purchase_dimensions(
    v_cp.company_id, v_cp.branch_id, v_cp.warehouse_id,
    v_cp.department_id, v_cp.cost_center_id
  );

  IF v_cp.warehouse_id IS NULL AND EXISTS (
    SELECT 1
    FROM cash_purchase_lines cpl
    JOIN items i ON i.id = cpl.item_id
    WHERE cpl.cp_id = v_cp.id AND cpl.quantity > 0
      AND i.item_type = 'inventory_item'
  ) THEN
    RAISE EXCEPTION 'Warehouse is required to post inventory-item cash purchases';
  END IF;

  PERFORM fn_post_cash_purchase_core_20260718(p_cp_id);

  FOR v_receipt IN
    SELECT cpl.item_id,
           SUM(cpl.quantity) AS qty,
           ROUND(SUM(cpl.net_amount) / NULLIF(SUM(cpl.quantity), 0), 6) AS unit_cost
    FROM cash_purchase_lines cpl
    JOIN items i ON i.id = cpl.item_id
    WHERE cpl.cp_id = v_cp.id AND cpl.quantity > 0
      AND i.item_type = 'inventory_item'
    GROUP BY cpl.item_id
  LOOP
    PERFORM fn_receive_inventory(jsonb_build_object(
      'company_id', v_cp.company_id,
      'warehouse_id', v_cp.warehouse_id,
      'item_id', v_receipt.item_id,
      'qty', v_receipt.qty,
      'unit_cost', v_receipt.unit_cost,
      'receipt_date', v_cp.transaction_date,
      'reference_doc_type', 'CP',
      'reference_doc_id', v_cp.id,
      'notes', COALESCE(v_cp.remarks, 'Cash Purchase ' || v_cp.cp_number)
    ));
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION fn_save_purchase_order_core_20260718(UUID, JSONB, JSONB) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_save_receiving_report_core_20260718(UUID, JSONB, JSONB) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_save_vendor_bill_core_20260718(UUID, JSONB, JSONB) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_save_cash_purchase_core_20260718(UUID, JSONB, JSONB) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_confirm_receiving_report_status_core_20260718(UUID) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_add_posting_line_core_20260718(UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_post_cash_purchase_core_20260718(UUID) FROM PUBLIC, authenticated;

REVOKE ALL ON FUNCTION fn_validate_purchase_dimensions(UUID, UUID, UUID, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_save_purchase_order(UUID, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_save_receiving_report(UUID, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_save_vendor_bill(UUID, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_save_cash_purchase(UUID, JSONB, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_confirm_receiving_report(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_add_posting_line(UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_post_cash_purchase(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_validate_purchase_dimensions(UUID, UUID, UUID, UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_save_purchase_order(UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_save_receiving_report(UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_save_vendor_bill(UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_save_cash_purchase(UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_confirm_receiving_report(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_add_posting_line(UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_post_cash_purchase(UUID) TO authenticated, service_role;
