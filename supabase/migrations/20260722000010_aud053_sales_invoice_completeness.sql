-- PXL-AUD-053 — Sales Invoice completeness certification.
--
-- Closes the remaining supported Sales Invoice analytical-dimension chain:
-- form/API payload -> SI header/line storage -> server validation -> posting ->
-- GL/inventory evidence -> report/export views -> audit JSON. Existing posting
-- behavior for every other transaction remains unchanged.

-- ---------------------------------------------------------------------------
-- Source-backed analytical dimensions.
-- ---------------------------------------------------------------------------

ALTER TABLE sales_invoices
  ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES locations(id),
  ADD COLUMN IF NOT EXISTS functional_entity_id UUID REFERENCES functional_entities(id);

ALTER TABLE sales_invoice_lines
  ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES locations(id),
  ADD COLUMN IF NOT EXISTS functional_entity_id UUID REFERENCES functional_entities(id);

ALTER TABLE journal_entry_lines
  ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES locations(id),
  ADD COLUMN IF NOT EXISTS functional_entity_id UUID REFERENCES functional_entities(id);

ALTER TABLE inventory_transactions
  ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES locations(id),
  ADD COLUMN IF NOT EXISTS functional_entity_id UUID REFERENCES functional_entities(id);

CREATE INDEX IF NOT EXISTS idx_sales_invoices_project
  ON sales_invoices (company_id, project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sales_invoices_location
  ON sales_invoices (company_id, location_id) WHERE location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sales_invoices_functional_entity
  ON sales_invoices (company_id, functional_entity_id) WHERE functional_entity_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sales_invoice_lines_project
  ON sales_invoice_lines (company_id, project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sales_invoice_lines_location
  ON sales_invoice_lines (company_id, location_id) WHERE location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sales_invoice_lines_functional_entity
  ON sales_invoice_lines (company_id, functional_entity_id) WHERE functional_entity_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_project
  ON journal_entry_lines (company_id, project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_location
  ON journal_entry_lines (company_id, location_id) WHERE location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_functional_entity
  ON journal_entry_lines (company_id, functional_entity_id) WHERE functional_entity_id IS NOT NULL;

COMMENT ON COLUMN sales_invoices.project_id IS
  'AUD-053: optional governed Project header default for Sales Invoice lines and posting.';
COMMENT ON COLUMN sales_invoices.location_id IS
  'AUD-053: optional governed Location header default for Sales Invoice lines and posting.';
COMMENT ON COLUMN sales_invoices.functional_entity_id IS
  'AUD-053: optional governed Functional Entity header default for Sales Invoice lines and posting.';
COMMENT ON COLUMN journal_entry_lines.project_id IS
  'Optional analytical Project propagated by source posting engines; AUD-053 first wires Sales Invoice.';
COMMENT ON COLUMN journal_entry_lines.location_id IS
  'Optional analytical Location propagated by source posting engines; AUD-053 first wires Sales Invoice.';
COMMENT ON COLUMN journal_entry_lines.functional_entity_id IS
  'Optional analytical Functional Entity propagated by source posting engines; AUD-053 first wires Sales Invoice.';

CREATE OR REPLACE FUNCTION public.fn_guard_sales_invoice_dimension_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NEW.project_id IS NOT DISTINCT FROM OLD.project_id
     AND NEW.location_id IS NOT DISTINCT FROM OLD.location_id
     AND NEW.functional_entity_id IS NOT DISTINCT FROM OLD.functional_entity_id THEN
    RETURN NEW;
  END IF;

  SELECT status INTO v_status
  FROM sales_invoices
  WHERE id = OLD.sales_invoice_id;

  IF v_status NOT IN ('draft', 'approved') THEN
    RAISE EXCEPTION 'Sales Invoice dimensions are immutable after posting; use the governed void/reversal flow';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_sales_invoice_dimension_immutability
  ON sales_invoice_lines;
CREATE TRIGGER trg_guard_sales_invoice_dimension_immutability
  BEFORE UPDATE OF project_id, location_id, functional_entity_id
  ON sales_invoice_lines
  FOR EACH ROW
  EXECUTE FUNCTION fn_guard_sales_invoice_dimension_immutability();

CREATE OR REPLACE FUNCTION public.fn_guard_sales_invoice_header_dimensions()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.project_id IS DISTINCT FROM OLD.project_id
     OR NEW.location_id IS DISTINCT FROM OLD.location_id
     OR NEW.functional_entity_id IS DISTINCT FROM OLD.functional_entity_id THEN
    IF OLD.status NOT IN ('draft', 'approved') THEN
      RAISE EXCEPTION 'Sales Invoice dimensions are immutable after posting; use the governed void/reversal flow';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_sales_invoice_header_dimensions
  ON sales_invoices;
CREATE TRIGGER trg_guard_sales_invoice_header_dimensions
  BEFORE UPDATE OF project_id, location_id, functional_entity_id
  ON sales_invoices
  FOR EACH ROW
  EXECUTE FUNCTION fn_guard_sales_invoice_header_dimensions();

-- The existing save RPC remains the authoritative commercial calculation. Keep
-- it versioned and wrap only dimension validation/persistence.
ALTER FUNCTION public.fn_save_sales_invoice(UUID, JSONB, JSONB)
  RENAME TO fn_save_sales_invoice_aud053_core;

REVOKE ALL ON FUNCTION public.fn_save_sales_invoice_aud053_core(UUID, JSONB, JSONB)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_assert_sales_invoice_dimension(
  p_dimension_type TEXT,
  p_dimension_id UUID,
  p_company_id UUID,
  p_branch_id UUID,
  p_as_of DATE,
  p_context TEXT
)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
  IF p_dimension_id IS NOT NULL
     AND NOT fn_is_valid_dimension(
       p_dimension_type, p_dimension_id, p_company_id, p_branch_id, p_as_of
     ) THEN
    RAISE EXCEPTION 'Invalid % for Sales Invoice %',
      replace(p_dimension_type, '_', ' '), p_context;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_add_sales_invoice_posting_line(
  p_je_id UUID,
  p_line_number INTEGER,
  p_account_id UUID,
  p_description TEXT,
  p_debit NUMERIC,
  p_credit NUMERIC,
  p_branch_id UUID,
  p_department_id UUID,
  p_cost_center_id UUID,
  p_project_id UUID,
  p_location_id UUID,
  p_functional_entity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_add_posting_line(
    p_je_id, p_line_number, p_account_id, p_description, p_debit, p_credit,
    p_branch_id, p_department_id, p_cost_center_id
  );

  UPDATE journal_entry_lines
  SET project_id = p_project_id,
      location_id = p_location_id,
      functional_entity_id = p_functional_entity_id
  WHERE je_id = p_je_id
    AND line_number = p_line_number;
END;
$$;

-- Reversals preserve every analytical dimension from the immutable original
-- line. This is additive for other posting sources and is required for an exact
-- Sales Invoice correction trail.
CREATE OR REPLACE FUNCTION public.fn_reverse_posted_journal_entry(
  p_original_je_id UUID,
  p_reversal_date DATE,
  p_reference_doc_type TEXT,
  p_reference_doc_id UUID,
  p_je_number TEXT,
  p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original journal_entries%ROWTYPE;
  v_reversal_id UUID;
  v_line RECORD;
BEGIN
  SELECT * INTO v_original
  FROM journal_entries
  WHERE id = p_original_je_id
  FOR UPDATE;

  IF NOT FOUND OR NOT is_company_member(v_original.company_id) THEN
    RAISE EXCEPTION 'Original journal entry not found or access denied';
  END IF;

  PERFORM fn_assert_posting_source(
    v_original.reference_doc_type,
    v_original.reference_doc_id,
    v_original.company_id
  );

  IF v_original.reversed_by_je_id IS NOT NULL THEN
    RETURN v_original.reversed_by_je_id;
  END IF;
  IF v_original.status <> 'posted' THEN
    RAISE EXCEPTION 'Only posted journal entries can be reversed (current status: %)',
      v_original.status;
  END IF;

  v_reversal_id := fn_create_posted_journal_entry(
    v_original.company_id,
    v_original.branch_id,
    p_je_number,
    COALESCE(p_reversal_date, CURRENT_DATE),
    p_description,
    UPPER(BTRIM(p_reference_doc_type)),
    p_reference_doc_id
  );

  FOR v_line IN
    SELECT *
    FROM journal_entry_lines
    WHERE je_id = v_original.id
    ORDER BY line_number
  LOOP
    PERFORM fn_add_sales_invoice_posting_line(
      v_reversal_id, v_line.line_number, v_line.account_id,
      'REVERSAL — ' || COALESCE(v_line.description, ''),
      v_line.credit_amount, v_line.debit_amount,
      v_line.branch_id, v_line.department_id, v_line.cost_center_id,
      v_line.project_id, v_line.location_id, v_line.functional_entity_id
    );
  END LOOP;

  PERFORM fn_finalize_journal_entry(v_reversal_id);

  UPDATE journal_entries
  SET status = 'reversed',
      reversed_by_je_id = v_reversal_id,
      updated_by = auth.uid(),
      updated_at = NOW()
  WHERE id = v_original.id;

  RETURN v_reversal_id;
END;
$$;

ALTER FUNCTION public.fn_void_sales_invoice(UUID, UUID, TEXT)
  RENAME TO fn_void_sales_invoice_aud053_core;

REVOKE ALL ON FUNCTION public.fn_void_sales_invoice_aud053_core(UUID, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_void_sales_invoice(
  p_invoice_id UUID,
  p_void_reason_id UUID,
  p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_void_sales_invoice_aud053_core(
    p_invoice_id, p_void_reason_id, p_memo
  );

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

-- Sales Invoice posting remains otherwise identical to the certified engine;
-- only the three governed dimensions are added to its grouping/evidence.
CREATE OR REPLACE FUNCTION public.fn_post_sales_invoice(p_invoice_id UUID)
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

  PERFORM fn_add_sales_invoice_posting_line(
    v_je_id, 1, v_cfg.ar_account_id,
    'AR - ' || v_rec.customer_name_snapshot,
    v_rec.total_amount, 0,
    v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
    v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
  );
  v_line_no := 2;
  v_total_debit := v_rec.total_amount;

  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum,
           sil.description AS line_description,
           COALESCE(sil.department_id, v_rec.department_id) AS department_id,
           COALESCE(sil.cost_center_id, v_rec.cost_center_id) AS cost_center_id,
           COALESCE(sil.project_id, v_rec.project_id) AS project_id,
           COALESCE(sil.location_id, v_rec.location_id) AS location_id,
           COALESCE(
             sil.functional_entity_id, v_rec.functional_entity_id
           ) AS functional_entity_id
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description,
             COALESCE(sil.department_id, v_rec.department_id),
             COALESCE(sil.cost_center_id, v_rec.cost_center_id),
             COALESCE(sil.project_id, v_rec.project_id),
             COALESCE(sil.location_id, v_rec.location_id),
             COALESCE(sil.functional_entity_id, v_rec.functional_entity_id)
  LOOP
    PERFORM fn_add_sales_invoice_posting_line(
      v_je_id, v_line_no, v_line.revenue_account_id,
      'Revenue - ' || v_line.line_description,
      0, v_line.net_sum,
      v_rec.branch_id, v_line.department_id, v_line.cost_center_id,
      v_line.project_id, v_line.location_id, v_line.functional_entity_id
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_line.net_sum;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    PERFORM fn_add_sales_invoice_posting_line(
      v_je_id, v_line_no, v_cfg.vat_payable_account_id,
      'Output VAT - ' || v_rec.si_number,
      0, v_rec.total_vat_amount,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
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
    IF v_inv_line.resolved_inventory_account_id IS NULL
       OR v_inv_line.resolved_cogs_account_id IS NULL THEN
      RAISE EXCEPTION 'Inventory and COGS accounts are required for inventory item line %', v_inv_line.line_number;
    END IF;

    PERFORM fn_ensure_stock_balance(
      v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id
    );
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
      SET wac_unit_cost = CASE
        WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_inv_line.warehouse_id
        AND item_id = v_inv_line.item_id;
    END IF;

    IF v_total_cost > 0 THEN
      PERFORM fn_add_sales_invoice_posting_line(
        v_je_id, v_line_no, v_inv_line.resolved_cogs_account_id,
        'COGS - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        v_total_cost, 0,
        v_rec.branch_id,
        COALESCE(v_inv_line.department_id, v_rec.department_id),
        COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
        COALESCE(v_inv_line.project_id, v_rec.project_id),
        COALESCE(v_inv_line.location_id, v_rec.location_id),
        COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
      );
      v_line_no := v_line_no + 1;
      PERFORM fn_add_sales_invoice_posting_line(
        v_je_id, v_line_no, v_inv_line.resolved_inventory_account_id,
        'Inventory - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        0, v_total_cost,
        v_rec.branch_id,
        COALESCE(v_inv_line.department_id, v_rec.department_id),
        COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
        COALESCE(v_inv_line.project_id, v_rec.project_id),
        COALESCE(v_inv_line.location_id, v_rec.location_id),
        COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
      );
      v_line_no := v_line_no + 1;
      v_total_debit := v_total_debit + v_total_cost;
      v_total_credit := v_total_credit + v_total_cost;
    END IF;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by,
      project_id, location_id, functional_entity_id
    )
    SELECT v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
      'issue', v_rec.date,
      -v_inv_line.quantity, v_unit_cost, -v_total_cost,
      qty_on_hand, v_inv_line.costing_method,
      'SI', v_rec.id, v_je_id,
      'Sales Invoice ' || v_rec.si_number || ' line ' || v_inv_line.line_number,
      auth.uid(),
      COALESCE(v_inv_line.project_id, v_rec.project_id),
      COALESCE(v_inv_line.location_id, v_rec.location_id),
      COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
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
    HAVING SUM(sil.net_amount) <> 0
       OR COALESCE(SUM(sil.vat_amount), 0) <> 0
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

CREATE OR REPLACE FUNCTION public.fn_save_sales_invoice(
  p_invoice_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := (p_header->>'branch_id')::UUID;
  v_date DATE := COALESCE((p_header->>'date')::DATE, CURRENT_DATE);
  v_project_id UUID := NULLIF(p_header->>'project_id', '')::UUID;
  v_location_id UUID := NULLIF(p_header->>'location_id', '')::UUID;
  v_functional_entity_id UUID := NULLIF(p_header->>'functional_entity_id', '')::UUID;
  v_line JSONB;
  v_line_number INTEGER := 0;
BEGIN
  IF UPPER(COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP')) <> 'PHP' THEN
    RAISE EXCEPTION
      'Foreign-currency Sales Invoices are not supported; currency_code must be PHP';
  END IF;

  PERFORM fn_assert_sales_invoice_dimension(
    'project', v_project_id, v_company_id, v_branch_id, v_date, 'header'
  );
  PERFORM fn_assert_sales_invoice_dimension(
    'location', v_location_id, v_company_id, v_branch_id, v_date, 'header'
  );
  PERFORM fn_assert_sales_invoice_dimension(
    'functional_entity', v_functional_entity_id,
    v_company_id, v_branch_id, v_date, 'header'
  );

  FOR v_line IN SELECT value FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB))
  LOOP
    v_line_number := v_line_number + 1;
    IF NULLIF(v_line->>'source_document_type', '') IS NOT NULL THEN
      IF v_line->>'source_document_type' <> 'sales_order' THEN
        RAISE EXCEPTION 'Unsupported Sales Invoice source document type % on line %',
          v_line->>'source_document_type', v_line_number;
      END IF;
      IF NOT EXISTS (
        SELECT 1
        FROM sales_order_lines sol
        JOIN sales_orders so ON so.id = sol.sales_order_id
        WHERE sol.id = NULLIF(v_line->>'source_line_id', '')::UUID
          AND sol.company_id = v_company_id
          AND so.company_id = v_company_id
          AND so.customer_id = (p_header->>'customer_id')::UUID
      ) THEN
        RAISE EXCEPTION 'Invalid Sales Order source line for Sales Invoice line %',
          v_line_number;
      END IF;
    END IF;
    PERFORM fn_assert_sales_invoice_dimension(
      'project', COALESCE(NULLIF(v_line->>'project_id', '')::UUID, v_project_id),
      v_company_id, v_branch_id, v_date, 'line ' || v_line_number
    );
    PERFORM fn_assert_sales_invoice_dimension(
      'location', COALESCE(NULLIF(v_line->>'location_id', '')::UUID, v_location_id),
      v_company_id, v_branch_id, v_date, 'line ' || v_line_number
    );
    PERFORM fn_assert_sales_invoice_dimension(
      'functional_entity',
      COALESCE(NULLIF(v_line->>'functional_entity_id', '')::UUID, v_functional_entity_id),
      v_company_id, v_branch_id, v_date, 'line ' || v_line_number
    );
  END LOOP;

  v_invoice_id := fn_save_sales_invoice_aud053_core(p_invoice_id, p_header, p_lines);

  UPDATE sales_invoices
  SET project_id = v_project_id,
      location_id = v_location_id,
      functional_entity_id = v_functional_entity_id,
      updated_by = auth.uid(),
      updated_at = NOW()
  WHERE id = v_invoice_id;

  WITH payload AS (
    SELECT
      ordinality::INTEGER AS line_number,
      NULLIF(value->>'project_id', '')::UUID AS project_id,
      NULLIF(value->>'location_id', '')::UUID AS location_id,
      NULLIF(value->>'functional_entity_id', '')::UUID AS functional_entity_id
    FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) WITH ORDINALITY
  )
  UPDATE sales_invoice_lines sil
  SET project_id = COALESCE(payload.project_id, v_project_id),
      location_id = COALESCE(payload.location_id, v_location_id),
      functional_entity_id = COALESCE(
        payload.functional_entity_id, v_functional_entity_id
      ),
      updated_by = auth.uid(),
      updated_at = NOW()
  FROM payload
  WHERE sil.sales_invoice_id = v_invoice_id
    AND sil.line_number = payload.line_number;

  RETURN v_invoice_id;
END;
$$;

ALTER FUNCTION public.fn_validate_sales_invoice_accounting_ready(UUID)
  RENAME TO fn_validate_sales_invoice_accounting_ready_aud053_core;

REVOKE ALL ON FUNCTION public.fn_validate_sales_invoice_accounting_ready_aud053_core(UUID)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_validate_sales_invoice_accounting_ready(
  p_invoice_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice sales_invoices%ROWTYPE;
  v_line RECORD;
BEGIN
  PERFORM fn_validate_sales_invoice_accounting_ready_aud053_core(p_invoice_id);

  SELECT * INTO STRICT v_invoice
  FROM sales_invoices
  WHERE id = p_invoice_id;

  IF UPPER(COALESCE(v_invoice.currency_code, 'PHP')) <> 'PHP' THEN
    RAISE EXCEPTION
      'Foreign-currency Sales Invoices are not supported; currency_code must be PHP';
  END IF;

  PERFORM fn_assert_sales_invoice_dimension(
    'project', v_invoice.project_id, v_invoice.company_id,
    v_invoice.branch_id, v_invoice.date, 'header'
  );
  PERFORM fn_assert_sales_invoice_dimension(
    'location', v_invoice.location_id, v_invoice.company_id,
    v_invoice.branch_id, v_invoice.date, 'header'
  );
  PERFORM fn_assert_sales_invoice_dimension(
    'functional_entity', v_invoice.functional_entity_id, v_invoice.company_id,
    v_invoice.branch_id, v_invoice.date, 'header'
  );

  FOR v_line IN
    SELECT line_number, project_id, location_id, functional_entity_id
    FROM sales_invoice_lines
    WHERE sales_invoice_id = p_invoice_id
  LOOP
    PERFORM fn_assert_sales_invoice_dimension(
      'project', v_line.project_id, v_invoice.company_id,
      v_invoice.branch_id, v_invoice.date, 'line ' || v_line.line_number
    );
    PERFORM fn_assert_sales_invoice_dimension(
      'location', v_line.location_id, v_invoice.company_id,
      v_invoice.branch_id, v_invoice.date, 'line ' || v_line.line_number
    );
    PERFORM fn_assert_sales_invoice_dimension(
      'functional_entity', v_line.functional_entity_id, v_invoice.company_id,
      v_invoice.branch_id, v_invoice.date, 'line ' || v_line.line_number
    );
  END LOOP;
END;
$$;

ALTER FUNCTION public.fn_preview_sales_invoice_gl_impact(UUID, DATE)
  RENAME TO fn_preview_sales_invoice_gl_impact_aud053_core;

REVOKE ALL ON FUNCTION public.fn_preview_sales_invoice_gl_impact_aud053_core(UUID, DATE)
  FROM PUBLIC, anon, authenticated;

-- Preserve the certified preview payload and enrich its lines. Draft revenue
-- rows are rebuilt at the new-dimension grain so two otherwise-identical lines
-- with different analytical assignments never collapse into one preview row.
CREATE OR REPLACE FUNCTION public.fn_preview_sales_invoice_gl_impact(
  p_invoice_id UUID,
  p_posting_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payload JSONB;
  v_invoice sales_invoices%ROWTYPE;
  v_lines JSONB;
BEGIN
  v_payload := fn_preview_sales_invoice_gl_impact_aud053_core(
    p_invoice_id, p_posting_date
  );

  SELECT * INTO STRICT v_invoice
  FROM sales_invoices
  WHERE id = p_invoice_id;

  IF v_payload->>'mode' = 'posted' THEN
    WITH base AS (
      SELECT value AS obj, ordinality
      FROM jsonb_array_elements(v_payload->'lines') WITH ORDINALITY
    ),
    enriched AS (
      SELECT
        base.ordinality,
        base.obj || jsonb_build_object(
          'project_id', jel.project_id,
          'location_id', jel.location_id,
          'functional_entity_id', jel.functional_entity_id
        ) AS obj
      FROM base
      LEFT JOIN journal_entry_lines jel
        ON jel.je_id = (v_payload->>'journal_entry_id')::UUID
       AND jel.line_number = (base.obj->>'line_number')::INTEGER
    )
    SELECT COALESCE(jsonb_agg(obj ORDER BY ordinality), '[]'::JSONB)
    INTO v_lines
    FROM enriched;
  ELSE
    WITH base AS (
      SELECT value AS obj, ordinality
      FROM jsonb_array_elements(v_payload->'lines') WITH ORDINALITY
    ),
    non_revenue AS (
      SELECT
        CASE base.obj->>'accounting_effect'
          WHEN 'RECEIVABLE' THEN 10::NUMERIC
          WHEN 'TAX' THEN 40::NUMERIC
          WHEN 'COGS' THEN 50 + base.ordinality
          WHEN 'INVENTORY' THEN 60 + base.ordinality
          ELSE 80 + base.ordinality
        END AS sort_key,
        base.obj || jsonb_build_object(
          'project_id', COALESCE(sil.project_id, v_invoice.project_id),
          'location_id', COALESCE(sil.location_id, v_invoice.location_id),
          'functional_entity_id', COALESCE(
            sil.functional_entity_id, v_invoice.functional_entity_id
          )
        ) AS obj
      FROM base
      LEFT JOIN sales_invoice_lines sil
        ON sil.id = NULLIF(base.obj->>'source_line_id', '')::UUID
      WHERE base.obj->>'accounting_effect' <> 'REVENUE'
    ),
    revenue_source AS (
      SELECT
        sil.revenue_account_id AS account_id,
        COALESCE(NULLIF(TRIM(sil.description), ''), 'Sales invoice line') AS description,
        COALESCE(sil.department_id, v_invoice.department_id) AS department_id,
        COALESCE(sil.cost_center_id, v_invoice.cost_center_id) AS cost_center_id,
        COALESCE(sil.project_id, v_invoice.project_id) AS project_id,
        COALESCE(sil.location_id, v_invoice.location_id) AS location_id,
        COALESCE(
          sil.functional_entity_id, v_invoice.functional_entity_id
        ) AS functional_entity_id,
        SUM(sil.net_amount) AS credit
      FROM sales_invoice_lines sil
      WHERE sil.sales_invoice_id = v_invoice.id
      GROUP BY
        sil.revenue_account_id,
        COALESCE(NULLIF(TRIM(sil.description), ''), 'Sales invoice line'),
        COALESCE(sil.department_id, v_invoice.department_id),
        COALESCE(sil.cost_center_id, v_invoice.cost_center_id),
        COALESCE(sil.project_id, v_invoice.project_id),
        COALESCE(sil.location_id, v_invoice.location_id),
        COALESCE(sil.functional_entity_id, v_invoice.functional_entity_id)
    ),
    revenue AS (
      SELECT
        20 + ROW_NUMBER() OVER (
          ORDER BY account_id::TEXT NULLS FIRST, description,
                   project_id::TEXT NULLS FIRST,
                   location_id::TEXT NULLS FIRST,
                   functional_entity_id::TEXT NULLS FIRST
        ) AS sort_key,
        jsonb_build_object(
          'account_id', source.account_id,
          'account_code', COALESCE(coa.account_code, 'Missing Revenue Account'),
          'account_name', COALESCE(coa.account_name, ''),
          'account_source', CASE WHEN source.account_id IS NULL
            THEN 'missing_revenue_account' ELSE 'document_line_account' END,
          'description', 'Revenue - ' || source.description,
          'debit', 0,
          'credit', ROUND(source.credit, 2),
          'branch_id', v_invoice.branch_id,
          'department_id', source.department_id,
          'cost_center_id', source.cost_center_id,
          'project_id', source.project_id,
          'location_id', source.location_id,
          'functional_entity_id', source.functional_entity_id,
          'impact_group', 'COMMERCIAL',
          'accounting_effect', 'REVENUE',
          'source_type', 'Invoice Line',
          'source_line_id', NULL,
          'item_id', NULL,
          'item_code', NULL,
          'warehouse_id', NULL,
          'warehouse_code', NULL,
          'quantity', NULL,
          'unit_cost', NULL,
          'total_cost', NULL,
          'valuation_method', NULL,
          'inventory_movement_id', NULL
        ) AS obj
      FROM revenue_source source
      LEFT JOIN chart_of_accounts coa
        ON coa.id = source.account_id
       AND coa.company_id = v_invoice.company_id
    ),
    combined AS (
      SELECT sort_key, obj FROM non_revenue
      UNION ALL
      SELECT sort_key, obj FROM revenue
    ),
    ordered AS (
      SELECT
        obj,
        ROW_NUMBER() OVER (ORDER BY sort_key)::INTEGER AS line_number
      FROM combined
    )
    SELECT COALESCE(
      jsonb_agg(
        (obj - 'line_number') || jsonb_build_object('line_number', line_number)
        ORDER BY line_number
      ),
      '[]'::JSONB
    )
    INTO v_lines
    FROM ordered;
  END IF;

  RETURN jsonb_set(v_payload, '{lines}', COALESCE(v_lines, '[]'::JSONB), true);
END;
$$;

-- Existing report/API contracts retain all columns in place; dimension fields
-- are appended so current consumers remain compatible.
CREATE OR REPLACE VIEW public.vw_general_ledger
WITH (security_invoker = true) AS
SELECT
  jel.id            AS line_id,
  jel.je_id,
  jel.company_id,
  COALESCE(jel.branch_id, je.branch_id) AS branch_id,
  je.fiscal_period_id,
  fp.period_name,
  fp.start_date     AS period_start,
  fp.end_date       AS period_end,
  je.je_date,
  je.je_number,
  je.description    AS je_description,
  je.reference_doc_type,
  je.reference_doc_id,
  je.status         AS je_status,
  je.is_auto_reversal,
  je.reversed_by_je_id,
  jel.account_id,
  coa.account_code,
  coa.account_name,
  coa.account_type,
  coa.normal_balance,
  jel.line_number,
  jel.description   AS line_description,
  jel.debit_amount,
  jel.credit_amount,
  jel.department_id,
  jel.cost_center_id,
  je.entry_class,
  jel.project_id,
  jel.location_id,
  jel.functional_entity_id
FROM journal_entry_lines jel
JOIN journal_entries je ON je.id = jel.je_id
JOIN chart_of_accounts coa ON coa.id = jel.account_id
LEFT JOIN fiscal_periods fp ON fp.id = je.fiscal_period_id
WHERE je.status IN ('posted', 'reversed');

CREATE OR REPLACE VIEW public.vw_sales_invoice_register
WITH (security_invoker = true) AS
SELECT
  si.company_id, si.branch_id, si.date,
  si.si_number, si.customer_name_snapshot, si.customer_tin_snapshot,
  si.total_taxable_amount, si.total_zero_rated_amount, si.total_exempt_amount,
  si.total_vat_amount, si.total_amount, si.status,
  si.void_reason_id, si.memo, si.reference,
  si.id AS invoice_id,
  si.project_id,
  (SELECT p.project_code FROM projects p WHERE p.id = si.project_id) AS project_code,
  (SELECT p.project_name FROM projects p WHERE p.id = si.project_id) AS project_name,
  si.location_id,
  (SELECT l.location_code FROM locations l WHERE l.id = si.location_id) AS location_code,
  (SELECT l.location_name FROM locations l WHERE l.id = si.location_id) AS location_name,
  si.functional_entity_id,
  (SELECT fe.entity_code FROM functional_entities fe
   WHERE fe.id = si.functional_entity_id) AS functional_entity_code,
  (SELECT fe.entity_name FROM functional_entities fe
   WHERE fe.id = si.functional_entity_id) AS functional_entity_name
FROM sales_invoices si;

REVOKE ALL ON FUNCTION public.fn_assert_sales_invoice_dimension(
  TEXT, UUID, UUID, UUID, DATE, TEXT
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_add_sales_invoice_posting_line(
  UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC,
  UUID, UUID, UUID, UUID, UUID, UUID
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_guard_sales_invoice_header_dimensions()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_guard_sales_invoice_dimension_immutability()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_save_sales_invoice(UUID, JSONB, JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_validate_sales_invoice_accounting_ready(UUID)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_post_sales_invoice(UUID)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_void_sales_invoice(UUID, UUID, TEXT)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_preview_sales_invoice_gl_impact(UUID, DATE)
  TO authenticated;

COMMENT ON FUNCTION public.fn_preview_sales_invoice_gl_impact(UUID, DATE) IS
  'AUD-053: Sales Invoice accounting impact with Project, Location, and Functional Entity on preview and posted lines.';
COMMENT ON VIEW public.vw_sales_invoice_register IS
  'Sales Invoice sales-report/API/export view, including governed header analytical dimensions.';
