-- Sales Invoice completeness foundation.
--
-- This closes the source-backed gaps that already have platform masters:
-- VAT Price Basis persistence, supported operational dimensions, warehouse
-- capture, inventory/COGS posting for inventory items, and stock restoration
-- on void. Project, Location, and Functional Entity are intentionally not
-- added here because this schema has no governed master-data source for them.

CREATE OR REPLACE FUNCTION fn_block_si_line_mutation_after_draft()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
  v_posting_internal BOOLEAN := COALESCE(current_setting('pxl.sales_invoice_posting_internal', true), '') = 'on';
BEGIN
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
$$;

ALTER TABLE sales_invoices
  ADD COLUMN IF NOT EXISTS vat_price_basis TEXT NOT NULL DEFAULT 'exclusive',
  ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id),
  ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id),
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS salesperson_id UUID REFERENCES employees(id),
  ADD COLUMN IF NOT EXISTS account_owner_id UUID REFERENCES employees(id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sales_invoices_vat_price_basis_check'
  ) THEN
    ALTER TABLE sales_invoices
      ADD CONSTRAINT sales_invoices_vat_price_basis_check
      CHECK (vat_price_basis IN ('exclusive', 'inclusive'));
  END IF;
END;
$$;

ALTER TABLE sales_invoice_lines
  ADD COLUMN IF NOT EXISTS warehouse_id UUID REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id),
  ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id),
  ADD COLUMN IF NOT EXISTS salesperson_id UUID REFERENCES employees(id),
  ADD COLUMN IF NOT EXISTS inventory_account_id UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS cogs_account_id UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(18,6),
  ADD COLUMN IF NOT EXISTS inventory_cost NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID REFERENCES inventory_transactions(id),
  ADD COLUMN IF NOT EXISTS remarks TEXT,
  ADD COLUMN IF NOT EXISTS source_document_type TEXT,
  ADD COLUMN IF NOT EXISTS source_line_id UUID;

CREATE INDEX IF NOT EXISTS idx_si_department_id ON sales_invoices (department_id) WHERE department_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_si_cost_center_id ON sales_invoices (cost_center_id) WHERE cost_center_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_si_warehouse_id ON sales_invoices (warehouse_id) WHERE warehouse_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sil_warehouse_id ON sales_invoice_lines (warehouse_id) WHERE warehouse_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sil_department_id ON sales_invoice_lines (department_id) WHERE department_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sil_cost_center_id ON sales_invoice_lines (cost_center_id) WHERE cost_center_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sil_inventory_tx ON sales_invoice_lines (inventory_transaction_id) WHERE inventory_transaction_id IS NOT NULL;

COMMENT ON COLUMN sales_invoices.vat_price_basis IS
  'User-selected invoice pricing basis. exclusive means entered commercial prices exclude VAT; inclusive means entered commercial prices include VAT.';
COMMENT ON COLUMN sales_invoice_lines.warehouse_id IS
  'Warehouse used for Sales Invoice inventory-item stock and COGS posting.';
COMMENT ON COLUMN sales_invoice_lines.inventory_cost IS
  'Authoritative inventory cost consumed by Sales Invoice posting for this line.';
COMMENT ON COLUMN sales_invoice_lines.inventory_transaction_id IS
  'Inventory transaction generated by Sales Invoice posting for this line.';

CREATE OR REPLACE FUNCTION fn_validate_sales_invoice_accounting_ready(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id FROM sales_invoices WHERE id = p_invoice_id;
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Sales invoice not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Sales invoice must have at least one line before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
      AND revenue_account_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice line must have a revenue account before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines sil
    LEFT JOIN chart_of_accounts coa
      ON coa.id = sil.revenue_account_id
     AND coa.company_id = v_company_id
     AND coa.is_active = true
     AND coa.is_postable = true
    WHERE sil.sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(sil.description), '') IS NOT NULL
      AND coa.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice revenue account must be active, postable, and belong to the invoice company.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(description), '') IS NOT NULL
      AND vat_code_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice line must have a VAT code before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines sil
    LEFT JOIN vat_codes vc
      ON vc.id = sil.vat_code_id
     AND vc.is_active = true
     AND vc.transaction_type = 'output_vat'
    WHERE sil.sales_invoice_id = p_invoice_id
      AND NULLIF(TRIM(sil.description), '') IS NOT NULL
      AND vc.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice VAT code must be active and valid for output VAT.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoices si
    LEFT JOIN departments d
      ON d.id = si.department_id
     AND d.company_id = si.company_id
     AND COALESCE(d.is_active, true) = true
    WHERE si.id = p_invoice_id
      AND si.department_id IS NOT NULL
      AND d.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Sales invoice department must be active and belong to the invoice company.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoices si
    LEFT JOIN cost_centers cc
      ON cc.id = si.cost_center_id
     AND cc.company_id = si.company_id
     AND COALESCE(cc.is_active, true) = true
    WHERE si.id = p_invoice_id
      AND si.cost_center_id IS NOT NULL
      AND cc.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Sales invoice cost center must be active and belong to the invoice company.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    WHERE sil.sales_invoice_id = p_invoice_id
      AND i.item_type = 'inventory_item'
      AND sil.warehouse_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every inventory item sales invoice line must have a warehouse before approval or posting.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    LEFT JOIN warehouses w
      ON w.id = sil.warehouse_id
     AND w.company_id = v_company_id
     AND w.is_active = true
    WHERE sil.sales_invoice_id = p_invoice_id
      AND i.item_type = 'inventory_item'
      AND w.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Every sales invoice warehouse must be active and belong to the invoice company.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    LEFT JOIN chart_of_accounts inv
      ON inv.id = COALESCE(sil.inventory_account_id, i.inventory_account_id)
     AND inv.company_id = v_company_id
     AND inv.is_active = true
     AND inv.is_postable = true
    LEFT JOIN chart_of_accounts cogs
      ON cogs.id = COALESCE(sil.cogs_account_id, i.cogs_account_id)
     AND cogs.company_id = v_company_id
     AND cogs.is_active = true
     AND cogs.is_postable = true
    WHERE sil.sales_invoice_id = p_invoice_id
      AND i.item_type = 'inventory_item'
      AND (inv.id IS NULL OR cogs.id IS NULL)
  ) THEN
    RAISE EXCEPTION 'Inventory item sales invoice lines require active Inventory and COGS accounts.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    LEFT JOIN stock_balances sb
      ON sb.warehouse_id = sil.warehouse_id
     AND sb.item_id = sil.item_id
    WHERE sil.sales_invoice_id = p_invoice_id
      AND i.item_type = 'inventory_item'
      AND COALESCE(sb.qty_on_hand, 0) < sil.quantity
  ) THEN
    RAISE EXCEPTION 'Insufficient stock for one or more Sales Invoice inventory lines.';
  END IF;
END;
$$;

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
  v_customer_id    UUID;
  v_invoice_date   DATE;
  v_vat_basis      TEXT;
  v_department_id  UUID;
  v_cost_center_id UUID;
  v_warehouse_id   UUID;
  v_salesperson_id UUID;
  v_account_owner_id UUID;
  v_si_number      TEXT;
  v_fiscal_period  UUID;
  v_current_status TEXT;
  v_line           JSONB;
  v_item           items%ROWTYPE;
  v_vat_class      TEXT;
  v_vat_rate       NUMERIC(9,4);
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_disc           NUMERIC(15,2);
  v_commercial     NUMERIC(15,2);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_line_warehouse_id UUID;
  v_line_department_id UUID;
  v_line_cost_center_id UUID;
  v_line_salesperson_id UUID;
  v_line_revenue_account_id UUID;
  v_line_inventory_account_id UUID;
  v_line_cogs_account_id UUID;
  v_taxable        NUMERIC(15,2) := 0;
  v_zero_rated     NUMERIC(15,2) := 0;
  v_exempt         NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_grand_total    NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
  v_customer_cwt   BOOLEAN;
  v_customer_atc   UUID;
  v_cwt_amount     NUMERIC(15,2);
  v_cwt_atc        UUID;
  v_cwt_base       NUMERIC(15,2);
  v_cwt_rate       NUMERIC(9,4);
  v_cwt_expected   NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;
  v_customer_id := (p_header->>'customer_id')::UUID;
  v_invoice_date := (p_header->>'date')::DATE;
  v_vat_basis := COALESCE(NULLIF(p_header->>'vat_price_basis', ''), 'exclusive');
  v_department_id := NULLIF(p_header->>'department_id', '')::UUID;
  v_cost_center_id := NULLIF(p_header->>'cost_center_id', '')::UUID;
  v_warehouse_id := NULLIF(p_header->>'warehouse_id', '')::UUID;
  v_salesperson_id := NULLIF(p_header->>'salesperson_id', '')::UUID;
  v_account_owner_id := NULLIF(p_header->>'account_owner_id', '')::UUID;

  IF v_vat_basis NOT IN ('exclusive', 'inclusive') THEN
    RAISE EXCEPTION 'VAT Price Basis must be VAT Exclusive or VAT Inclusive.';
  END IF;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;
  IF v_department_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM departments WHERE id = v_department_id AND company_id = v_company_id AND COALESCE(is_active, true) = true
  ) THEN
    RAISE EXCEPTION 'Department does not belong to this company or is inactive';
  END IF;
  IF v_cost_center_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM cost_centers WHERE id = v_cost_center_id AND company_id = v_company_id AND COALESCE(is_active, true) = true
  ) THEN
    RAISE EXCEPTION 'Cost Center does not belong to this company or is inactive';
  END IF;
  IF v_warehouse_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM warehouses WHERE id = v_warehouse_id AND company_id = v_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Warehouse does not belong to this company or is inactive';
  END IF;
  IF v_salesperson_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM employees WHERE id = v_salesperson_id AND company_id = v_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Salesperson does not belong to this company or is inactive';
  END IF;
  IF v_account_owner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM employees WHERE id = v_account_owner_id AND company_id = v_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Account Owner does not belong to this company or is inactive';
  END IF;

  SELECT is_subject_to_cwt, default_cwt_atc_code_id
    INTO v_customer_cwt, v_customer_atc
  FROM customers
  WHERE id = v_customer_id
    AND company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= v_invoice_date
    AND end_date   >= v_invoice_date
    AND is_locked = false
  LIMIT 1;

  IF p_invoice_id IS NULL THEN
    v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');

    INSERT INTO sales_invoices (
      company_id, branch_id, si_number, date, fiscal_period_id,
      customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
      payment_terms_id, due_date, currency_code, vat_price_basis, reference, memo,
      department_id, cost_center_id, warehouse_id, salesperson_id, account_owner_id,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_vat_amount, total_amount, cwt_amount_expected, cwt_atc_code_id, cwt_tax_base,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_si_number, v_invoice_date, v_fiscal_period,
      v_customer_id, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'customer_address_snapshot', ''),
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      NULLIF(p_header->>'due_date', '')::DATE,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      v_vat_basis,
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      v_department_id, v_cost_center_id, v_warehouse_id, v_salesperson_id, v_account_owner_id,
      0, 0, 0, 0, 0, NULL, NULL, NULL,
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
      branch_id = v_branch_id, date = v_invoice_date, fiscal_period_id = v_fiscal_period,
      customer_id = v_customer_id,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      customer_address_snapshot = NULLIF(p_header->>'customer_address_snapshot', ''),
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      vat_price_basis = v_vat_basis,
      reference = NULLIF(p_header->>'reference', ''), memo = NULLIF(p_header->>'memo', ''),
      department_id = v_department_id,
      cost_center_id = v_cost_center_id,
      warehouse_id = v_warehouse_id,
      salesperson_id = v_salesperson_id,
      account_owner_id = v_account_owner_id,
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      total_vat_amount = 0, total_amount = 0,
      cwt_amount_expected = NULL, cwt_atc_code_id = NULL, cwt_tax_base = NULL,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_si_id;
  END IF;

  DELETE FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    v_item := NULL;
    IF NULLIF(v_line->>'item_id', '') IS NOT NULL THEN
      SELECT * INTO v_item
      FROM items
      WHERE id = NULLIF(v_line->>'item_id', '')::UUID
        AND company_id = v_company_id
        AND COALESCE(is_active, true) = true;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Sales invoice item does not belong to this company or is inactive';
      END IF;
    END IF;

    SELECT vc.vat_classification, tc.rate
    INTO v_vat_class, v_vat_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id', '')::UUID;

    v_vat_class := COALESCE(v_vat_class, 'exempt');
    v_vat_rate  := COALESCE(v_vat_rate, 0);

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := COALESCE(NULLIF(v_line->>'discount_amount', '')::NUMERIC, 0);
    IF v_disc = 0 AND COALESCE(NULLIF(v_line->>'discount_percent', '')::NUMERIC, 0) > 0 THEN
      v_disc := ROUND(v_qty * v_price * COALESCE((v_line->>'discount_percent')::NUMERIC, 0) / 100, 2);
    END IF;
    v_disc := GREATEST(v_disc, 0);
    v_commercial := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);

    IF v_vat_basis = 'inclusive' AND v_vat_class = 'regular' AND v_vat_rate > 0 THEN
      v_net := ROUND(v_commercial / (1 + (v_vat_rate / 100)), 2);
      v_vat_amt := v_commercial - v_net;
      v_total_line := v_commercial;
    ELSE
      v_net := v_commercial;
      v_vat_amt := CASE WHEN v_vat_class = 'regular' THEN ROUND(v_net * v_vat_rate / 100, 2) ELSE 0 END;
      v_total_line := v_net + v_vat_amt;
    END IF;

    IF v_item.id IS NOT NULL AND v_item.item_type = 'inventory_item' THEN
      v_line_warehouse_id := COALESCE(NULLIF(v_line->>'warehouse_id', '')::UUID, v_warehouse_id);
    ELSE
      v_line_warehouse_id := NULLIF(v_line->>'warehouse_id', '')::UUID;
    END IF;
    v_line_department_id := COALESCE(NULLIF(v_line->>'department_id', '')::UUID, v_department_id);
    v_line_cost_center_id := COALESCE(NULLIF(v_line->>'cost_center_id', '')::UUID, v_cost_center_id);
    v_line_salesperson_id := COALESCE(NULLIF(v_line->>'salesperson_id', '')::UUID, v_salesperson_id);
    v_line_revenue_account_id := COALESCE(NULLIF(v_line->>'revenue_account_id', '')::UUID, v_item.sales_account_id);
    v_line_inventory_account_id := COALESCE(NULLIF(v_line->>'inventory_account_id', '')::UUID, v_item.inventory_account_id);
    v_line_cogs_account_id := COALESCE(NULLIF(v_line->>'cogs_account_id', '')::UUID, v_item.cogs_account_id);

    IF v_line_warehouse_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM warehouses WHERE id = v_line_warehouse_id AND company_id = v_company_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Line warehouse does not belong to this company or is inactive';
    END IF;
    IF v_line_department_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM departments WHERE id = v_line_department_id AND company_id = v_company_id AND COALESCE(is_active, true) = true
    ) THEN
      RAISE EXCEPTION 'Line department does not belong to this company or is inactive';
    END IF;
    IF v_line_cost_center_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM cost_centers WHERE id = v_line_cost_center_id AND company_id = v_company_id AND COALESCE(is_active, true) = true
    ) THEN
      RAISE EXCEPTION 'Line cost center does not belong to this company or is inactive';
    END IF;
    IF v_line_salesperson_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM employees WHERE id = v_line_salesperson_id AND company_id = v_company_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Line salesperson does not belong to this company or is inactive';
    END IF;

    CASE v_vat_class
      WHEN 'regular' THEN v_taxable := v_taxable + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE v_exempt := v_exempt + v_net;
    END CASE;
    v_total_vat   := v_total_vat + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number,
      item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, vat_amount, total_amount,
      revenue_account_id, warehouse_id, department_id, cost_center_id, salesperson_id,
      inventory_account_id, cogs_account_id, remarks, source_document_type, source_line_id,
      created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID,
      v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0),
      v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      v_line_revenue_account_id, v_line_warehouse_id, v_line_department_id, v_line_cost_center_id, v_line_salesperson_id,
      v_line_inventory_account_id, v_line_cogs_account_id, NULLIF(v_line->>'remarks', ''),
      NULLIF(v_line->>'source_document_type', ''), NULLIF(v_line->>'source_line_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'At least one non-empty line item is required';
  END IF;

  v_cwt_amount := NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC;
  IF COALESCE(v_cwt_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Expected CWT cannot be negative';
  END IF;

  IF COALESCE(v_cwt_amount, 0) > 0 THEN
    IF NOT COALESCE(v_customer_cwt, false) THEN
      RAISE EXCEPTION 'Expected CWT is only allowed when the customer is subject to CWT';
    END IF;
    IF v_customer_atc IS NULL THEN
      RAISE EXCEPTION 'Customer is subject to CWT but has no default CWT ATC';
    END IF;

    v_cwt_atc := COALESCE(NULLIF(p_header->>'cwt_atc_code_id', '')::UUID, v_customer_atc);
    IF v_cwt_atc <> v_customer_atc THEN
      RAISE EXCEPTION 'Sales invoice expected CWT ATC must match the customer default CWT ATC';
    END IF;
    IF NOT fn_atc_code_is_current(v_cwt_atc, 'ewt', v_invoice_date) THEN
      RAISE EXCEPTION 'Customer default CWT ATC is not active/current on the sales invoice date';
    END IF;

    SELECT rate INTO v_cwt_rate
    FROM atc_codes
    WHERE id = v_cwt_atc;

    v_cwt_base := COALESCE(
      NULLIF(p_header->>'cwt_tax_base', '')::NUMERIC,
      ROUND(v_taxable + v_zero_rated + v_exempt, 2)
    );
    IF COALESCE(v_cwt_base, 0) <= 0 THEN
      RAISE EXCEPTION 'Expected CWT taxable base must be positive when expected CWT is recorded';
    END IF;

    v_cwt_expected := ROUND(v_cwt_base * COALESCE(v_cwt_rate, 0) / 100, 2);
    IF ABS(v_cwt_expected - v_cwt_amount) > 0.02 THEN
      RAISE EXCEPTION 'Sales invoice expected CWT % does not match customer ATC expected % on base %',
        v_cwt_amount, v_cwt_expected, v_cwt_base;
    END IF;
  ELSE
    v_cwt_amount := NULL;
    v_cwt_atc := NULL;
    v_cwt_base := NULL;
  END IF;

  UPDATE sales_invoices SET
    total_taxable_amount    = v_taxable,
    total_zero_rated_amount = v_zero_rated,
    total_exempt_amount     = v_exempt,
    total_vat_amount        = v_total_vat,
    total_amount            = v_grand_total,
    cwt_amount_expected     = v_cwt_amount,
    cwt_atc_code_id         = v_cwt_atc,
    cwt_tax_base            = v_cwt_base,
    updated_at              = NOW(),
    updated_by              = auth.uid()
  WHERE id = v_si_id;

  RETURN v_si_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_post_sales_invoice(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_begin JSONB;
  v_rec sales_invoices%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_je_id UUID;
  v_fp_id UUID;
  v_line RECORD;
  v_inv_line RECORD;
  v_tax RECORD;
  v_stock stock_balances%ROWTYPE;
  v_layer RECORD;
  v_line_no INTEGER := 1;
  v_total_debit NUMERIC(15,2) := 0;
  v_total_credit NUMERIC(15,2) := 0;
  v_total_cost NUMERIC(18,2);
  v_unit_cost NUMERIC(18,6);
  v_inventory_tx_id UUID;
BEGIN
  v_begin := fn_begin_source_posting(
    'SI', p_invoice_id, ARRAY['approved'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM sales_invoices WHERE id = p_invoice_id;
  PERFORM fn_validate_sales_invoice_accounting_ready(p_invoice_id);
  PERFORM fn_validate_sales_invoice_vat_registration(p_invoice_id);
  PERFORM fn_validate_invoice_posting_totals('SI', p_invoice_id);
  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;

  IF NOT FOUND OR v_cfg.ar_account_id IS NULL THEN
    RAISE EXCEPTION 'AR control account not configured. Set it up in GL Posting Configuration.';
  END IF;
  IF v_rec.total_vat_amount > 0 AND v_cfg.vat_payable_account_id IS NULL THEN
    RAISE EXCEPTION 'VAT Payable account not configured. Set it up in GL Posting Configuration.';
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-SI-' || v_rec.si_number, v_rec.date,
    'Sales Invoice ' || v_rec.si_number || ' - ' || v_rec.customer_name_snapshot,
    'SI', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  PERFORM fn_add_posting_line(
    v_je_id, 1, v_cfg.ar_account_id,
    'AR - ' || v_rec.customer_name_snapshot,
    v_rec.total_amount, 0,
    v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id
  );
  v_line_no := 2;
  v_total_debit := v_rec.total_amount;

  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum,
           sil.description AS line_description,
           COALESCE(sil.department_id, v_rec.department_id) AS department_id,
           COALESCE(sil.cost_center_id, v_rec.cost_center_id) AS cost_center_id
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description,
             COALESCE(sil.department_id, v_rec.department_id),
             COALESCE(sil.cost_center_id, v_rec.cost_center_id)
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.revenue_account_id,
      'Revenue - ' || v_line.line_description,
      0, v_line.net_sum,
      v_rec.branch_id, v_line.department_id, v_line.cost_center_id
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_line.net_sum;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cfg.vat_payable_account_id,
      'Output VAT - ' || v_rec.si_number,
      0, v_rec.total_vat_amount,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_rec.total_vat_amount;
  END IF;

  FOR v_inv_line IN
    SELECT sil.*,
           i.item_code,
           i.description AS item_description,
           i.item_type,
           COALESCE(i.costing_method, 'weighted_average') AS costing_method,
           COALESCE(sil.inventory_account_id, i.inventory_account_id) AS resolved_inventory_account_id,
           COALESCE(sil.cogs_account_id, i.cogs_account_id) AS resolved_cogs_account_id
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    WHERE sil.sales_invoice_id = v_rec.id
      AND i.item_type = 'inventory_item'
  LOOP
    IF v_inv_line.warehouse_id IS NULL THEN
      RAISE EXCEPTION 'Warehouse is required for inventory item line %', v_inv_line.line_number;
    END IF;
    IF v_inv_line.resolved_inventory_account_id IS NULL OR v_inv_line.resolved_cogs_account_id IS NULL THEN
      RAISE EXCEPTION 'Inventory and COGS accounts are required for inventory item line %', v_inv_line.line_number;
    END IF;

    PERFORM fn_ensure_stock_balance(v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id);
    SELECT * INTO v_stock
    FROM stock_balances
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id
    FOR UPDATE;

    IF COALESCE(v_stock.qty_on_hand, 0) < v_inv_line.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for item %. On hand: %, requested: %',
        v_inv_line.item_code, COALESCE(v_stock.qty_on_hand, 0), v_inv_line.quantity;
    END IF;

    v_total_cost := 0;
    v_unit_cost := 0;

    IF v_inv_line.costing_method = 'weighted_average' THEN
      v_unit_cost := COALESCE(v_stock.wac_unit_cost, 0);
      v_total_cost := ROUND(v_inv_line.quantity * v_unit_cost, 2);
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
          v_inv_line.quantity, NULL, NULL
        )
      LOOP
        v_total_cost := v_total_cost + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
        v_unit_cost := v_layer.unit_cost;
      END LOOP;
      IF v_inv_line.quantity > 0 THEN
        v_unit_cost := ROUND(v_total_cost / v_inv_line.quantity, 6);
      END IF;
    END IF;

    UPDATE stock_balances
    SET qty_on_hand = qty_on_hand - v_inv_line.quantity,
        total_cost = GREATEST(total_cost - v_total_cost, 0),
        last_issue_date = v_rec.date,
        updated_at = NOW()
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id;

    IF v_inv_line.costing_method = 'weighted_average' THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_inv_line.warehouse_id
        AND item_id = v_inv_line.item_id;
    END IF;

    IF v_total_cost > 0 THEN
      PERFORM fn_add_posting_line(
        v_je_id, v_line_no, v_inv_line.resolved_cogs_account_id,
        'COGS - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        v_total_cost, 0,
        v_rec.branch_id,
        COALESCE(v_inv_line.department_id, v_rec.department_id),
        COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id)
      );
      v_line_no := v_line_no + 1;
      PERFORM fn_add_posting_line(
        v_je_id, v_line_no, v_inv_line.resolved_inventory_account_id,
        'Inventory - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        0, v_total_cost,
        v_rec.branch_id,
        COALESCE(v_inv_line.department_id, v_rec.department_id),
        COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id)
      );
      v_line_no := v_line_no + 1;
      v_total_debit := v_total_debit + v_total_cost;
      v_total_credit := v_total_credit + v_total_cost;
    END IF;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by
    )
    SELECT v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
      'issue', v_rec.date,
      -v_inv_line.quantity, v_unit_cost, -v_total_cost,
      qty_on_hand, v_inv_line.costing_method,
      'SI', v_rec.id, v_je_id,
      'Sales Invoice ' || v_rec.si_number || ' line ' || v_inv_line.line_number,
      auth.uid()
    FROM stock_balances
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id
    RETURNING id INTO v_inventory_tx_id;

    PERFORM set_config('pxl.sales_invoice_posting_internal', 'on', true);
    UPDATE sales_invoice_lines
    SET inventory_account_id = v_inv_line.resolved_inventory_account_id,
        cogs_account_id = v_inv_line.resolved_cogs_account_id,
        unit_cost = v_unit_cost,
        inventory_cost = v_total_cost,
        inventory_transaction_id = v_inventory_tx_id,
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE id = v_inv_line.id;
    PERFORM set_config('pxl.sales_invoice_posting_internal', '', true);
  END LOOP;

  IF ABS(v_total_debit - v_total_credit) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Check line revenue, VAT, inventory, and COGS configuration.',
      v_total_debit, v_total_credit;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_tax IN
    SELECT sil.vat_code_id,
           SUM(sil.net_amount) AS tax_base,
           COALESCE(SUM(sil.vat_amount), 0) AS tax_amount
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY sil.vat_code_id
    HAVING SUM(sil.net_amount) <> 0 OR COALESCE(SUM(sil.vat_amount), 0) <> 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'SI', v_rec.id, NULL,
      'output_vat', NULL, v_tax.vat_code_id, NULL,
      v_tax.tax_base, NULL, v_tax.tax_amount, v_fp_id,
      CURRENT_DATE, v_rec.date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'SI', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.date)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_void_sales_invoice(
  p_invoice_id UUID,
  p_void_reason_id UUID,
  p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
  v_reversal_id UUID;
  v_period_id UUID;
  v_reason TEXT;
  v_line RECORD;
BEGIN
  SELECT * INTO v_rec
  FROM sales_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Sales invoice not found or access denied';
  END IF;
  IF v_rec.status = 'cancelled' THEN
    RAISE EXCEPTION 'Invoice is already voided';
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

  IF v_rec.status = 'posted' THEN
    PERFORM fn_assert_source_journal_link(
      'SI', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
    );
    v_reversal_id := fn_reverse_posted_journal_entry(
      v_rec.journal_entry_id, CURRENT_DATE,
      'REV', v_rec.id,
      'JE-REV-' || v_rec.si_number,
      'Reversal of SI ' || v_rec.si_number || ' (' || v_rec.customer_name_snapshot || ') - ' || v_reason
    );
    SELECT fiscal_period_id INTO v_period_id
    FROM journal_entries WHERE id = v_reversal_id;
    PERFORM fn_reverse_tax_detail_entries('SI', v_rec.id, CURRENT_DATE, v_period_id);

    FOR v_line IN
      SELECT sil.*, i.item_type, COALESCE(i.costing_method, 'weighted_average') AS costing_method
      FROM sales_invoice_lines sil
      JOIN items i ON i.id = sil.item_id
      WHERE sil.sales_invoice_id = v_rec.id
        AND i.item_type = 'inventory_item'
        AND sil.warehouse_id IS NOT NULL
        AND sil.inventory_transaction_id IS NOT NULL
    LOOP
      PERFORM fn_ensure_stock_balance(v_rec.company_id, v_line.warehouse_id, v_line.item_id);

      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand + v_line.quantity,
          total_cost = total_cost + COALESCE(v_line.inventory_cost, 0),
          last_receipt_date = CURRENT_DATE,
          updated_at = NOW()
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
          'SI_VOID', v_rec.id, NULL, NULL
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
        qty_on_hand, v_line.costing_method,
        'SI_VOID', v_rec.id, v_reversal_id,
        'Void restoration for Sales Invoice ' || v_rec.si_number || ' line ' || v_line.line_number,
        auth.uid()
      FROM stock_balances
      WHERE warehouse_id = v_line.warehouse_id
        AND item_id = v_line.item_id;
    END LOOP;
  END IF;

  UPDATE sales_invoices
  SET status = 'cancelled',
      void_reason_id = p_void_reason_id,
      memo = COALESCE(NULLIF(BTRIM(COALESCE(p_memo, '')), ''), memo),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'SI', v_rec.id, 'VOIDED', v_reversal_id,
    jsonb_build_object('void_reason_id', p_void_reason_id, 'reason', v_reason)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_validate_sales_invoice_accounting_ready(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_save_sales_invoice(UUID, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_post_sales_invoice(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_void_sales_invoice(UUID, UUID, TEXT) TO authenticated, service_role;
