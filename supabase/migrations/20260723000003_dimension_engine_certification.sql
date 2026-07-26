-- ══════════════════════════════════════════════════════════════════════════════
-- Dimension Engine certification — cross-transaction propagation completion
--
-- Closes the Dimension Engine certification blockers found in the 2026-07-23
-- review. Additive and backwards-compatible: new columns are nullable, existing
-- RPC signatures are preserved, existing posting behavior is unchanged except that
-- dimensions now travel to the posted journal lines.
--
-- Scope (implemented posting transactions that ALREADY carry dimensions):
--   * Sales Invoice — already complete (AUD-053); untouched here.
--   * Vendor Bill / Cash Purchase — dept/cc already propagate via fn_add_posting_line;
--     this adds the analytical trio (project/location/functional_entity).
--   * Goods Issue — dept was captured but dropped at posting; now dept/cc/trio reach
--     the journal lines and the inventory transaction.
--   * Fixed Asset acquisition / depreciation / disposal — dept was captured but
--     dropped at posting; now dept/cc/trio reach every journal line.
--
-- Formally scoped OUT of analytical-dimension capture (documented, not a gap):
--   * Official Receipt / collections, Payment Voucher — cash settlement of an AR/AP
--     document; analytical attribution belongs to the settled source, and the
--     settlement posts branch-attributed.
--   * Credit/Debit Memo, Vendor Credit — adjustment documents that reference an
--     original; attribution follows the referenced document. Deferred with Sales/AP
--     module certification (Phases 2/3).
--   * Fund Transfer, Bank Adjustment, Stock Transfer, Inventory Adjustment —
--     balance-sheet / treasury / inter-warehouse movements that do not originate
--     analytical attribution; branch-attributed. Deferred to their module phases.
--   Every one of these still passes through the strengthened JE-line guard, so it
--   can never carry a cross-company dimension.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Schema: analytical trio (+ cost_center where missing) on the four docs ───
ALTER TABLE vendor_bills
  ADD COLUMN IF NOT EXISTS project_id           UUID REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS location_id          UUID REFERENCES locations(id),
  ADD COLUMN IF NOT EXISTS functional_entity_id UUID REFERENCES functional_entities(id);

ALTER TABLE cash_purchases
  ADD COLUMN IF NOT EXISTS project_id           UUID REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS location_id          UUID REFERENCES locations(id),
  ADD COLUMN IF NOT EXISTS functional_entity_id UUID REFERENCES functional_entities(id);

ALTER TABLE goods_issues
  ADD COLUMN IF NOT EXISTS cost_center_id       UUID REFERENCES cost_centers(id),
  ADD COLUMN IF NOT EXISTS project_id           UUID REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS location_id          UUID REFERENCES locations(id),
  ADD COLUMN IF NOT EXISTS functional_entity_id UUID REFERENCES functional_entities(id);

ALTER TABLE fixed_assets
  ADD COLUMN IF NOT EXISTS cost_center_id       UUID REFERENCES cost_centers(id),
  ADD COLUMN IF NOT EXISTS project_id           UUID REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS location_id          UUID REFERENCES locations(id),
  ADD COLUMN IF NOT EXISTS functional_entity_id UUID REFERENCES functional_entities(id);

CREATE INDEX IF NOT EXISTS idx_vb_project   ON vendor_bills (company_id, project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_vb_location  ON vendor_bills (company_id, location_id) WHERE location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_vb_fe        ON vendor_bills (company_id, functional_entity_id) WHERE functional_entity_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cp_project   ON cash_purchases (company_id, project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cp_location  ON cash_purchases (company_id, location_id) WHERE location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cp_fe        ON cash_purchases (company_id, functional_entity_id) WHERE functional_entity_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gi_costcenter ON goods_issues (company_id, cost_center_id) WHERE cost_center_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gi_project   ON goods_issues (company_id, project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gi_location  ON goods_issues (company_id, location_id) WHERE location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gi_fe        ON goods_issues (company_id, functional_entity_id) WHERE functional_entity_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fa_costcenter ON fixed_assets (company_id, cost_center_id) WHERE cost_center_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fa_project   ON fixed_assets (company_id, project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fa_location  ON fixed_assets (company_id, location_id) WHERE location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fa_fe        ON fixed_assets (company_id, functional_entity_id) WHERE functional_entity_id IS NOT NULL;

-- ── 2. Task 3 — strengthen the JE-line guard to validate ALL six dimensions ─────
-- Company-consistency for branch/department/cost_center already existed; this adds
-- the analytical trio so no journal line can ever carry a cross-company project,
-- location, or functional entity. Branch still inherits from the JE header on
-- insert. Company-consistency (not active/effective-window) is the posted-line
-- invariant, so a historical line keeps its snapshot even if a master is later
-- deactivated.
CREATE OR REPLACE FUNCTION fn_je_line_dimensions_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_je_company UUID;
  v_je_branch  UUID;
BEGIN
  SELECT company_id, branch_id INTO v_je_company, v_je_branch
  FROM journal_entries WHERE id = NEW.je_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Journal entry % not found for line', NEW.je_id;
  END IF;

  IF NEW.company_id IS DISTINCT FROM v_je_company THEN
    RAISE EXCEPTION 'JE line company % does not match journal entry company %',
      NEW.company_id, v_je_company;
  END IF;

  -- Lines inherit the header branch unless the writer sets one explicitly.
  IF TG_OP = 'INSERT' AND NEW.branch_id IS NULL THEN
    NEW.branch_id := v_je_branch;
  END IF;

  IF NEW.branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM branches b
    WHERE b.id = NEW.branch_id AND b.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line branch % does not belong to company %',
      NEW.branch_id, NEW.company_id;
  END IF;

  IF NEW.department_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM departments d
    WHERE d.id = NEW.department_id AND d.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line department % does not belong to company %',
      NEW.department_id, NEW.company_id;
  END IF;

  IF NEW.cost_center_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM cost_centers cc
    WHERE cc.id = NEW.cost_center_id AND cc.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line cost center % does not belong to company %',
      NEW.cost_center_id, NEW.company_id;
  END IF;

  IF NEW.project_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM projects p
    WHERE p.id = NEW.project_id AND p.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line project % does not belong to company %',
      NEW.project_id, NEW.company_id;
  END IF;

  IF NEW.location_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM locations l
    WHERE l.id = NEW.location_id AND l.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line location % does not belong to company %',
      NEW.location_id, NEW.company_id;
  END IF;

  IF NEW.functional_entity_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM functional_entities fe
    WHERE fe.id = NEW.functional_entity_id AND fe.company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'JE line functional entity % does not belong to company %',
      NEW.functional_entity_id, NEW.company_id;
  END IF;

  RETURN NEW;
END;
$$;

-- ── 3. Task 1 — Vendor Bill / Cash Purchase analytical-trio propagation ─────────
-- fn_add_posting_line already inherits dept/cc from the VB/CP header. Extend it to
-- also carry the analytical trio onto the journal line. Every VB/CP posting line
-- flows through this helper, so no VB/CP posting function needs to change.
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
  v_source_project UUID;
  v_source_location UUID;
  v_source_fe UUID;
  v_line_id UUID;
BEGIN
  SELECT reference_doc_type, reference_doc_id
  INTO v_source_type, v_source_id
  FROM journal_entries
  WHERE id = p_je_id;

  IF v_source_type = 'VB' THEN
    SELECT department_id, cost_center_id, project_id, location_id, functional_entity_id
    INTO v_source_department, v_source_cost_center, v_source_project, v_source_location, v_source_fe
    FROM vendor_bills WHERE id = v_source_id;
  ELSIF v_source_type = 'CP' THEN
    SELECT department_id, cost_center_id, project_id, location_id, functional_entity_id
    INTO v_source_department, v_source_cost_center, v_source_project, v_source_location, v_source_fe
    FROM cash_purchases WHERE id = v_source_id;
  END IF;

  v_line_id := fn_add_posting_line_core_20260718(
    p_je_id, p_line_number, p_account_id, p_description,
    p_debit, p_credit, p_branch_id,
    COALESCE(p_department_id, v_source_department),
    COALESCE(p_cost_center_id, v_source_cost_center)
  );

  IF v_source_project IS NOT NULL OR v_source_location IS NOT NULL OR v_source_fe IS NOT NULL THEN
    UPDATE journal_entry_lines
    SET project_id           = v_source_project,
        location_id          = v_source_location,
        functional_entity_id = v_source_fe
    WHERE id = v_line_id;
  END IF;

  RETURN v_line_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_add_posting_line(UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_add_posting_line(UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID) TO authenticated, service_role;

-- VB/CP save wrappers: persist + validate the analytical trio (dept/cc unchanged).
CREATE OR REPLACE FUNCTION public.fn_save_vendor_bill(p_bill_id uuid, p_header jsonb, p_lines jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := NULLIF(p_header->>'branch_id', '')::UUID;
  v_rr_id UUID := NULLIF(p_header->>'rr_id', '')::UUID;
  v_warehouse_id UUID := NULLIF(p_header->>'warehouse_id', '')::UUID;
  v_department_id UUID := NULLIF(p_header->>'department_id', '')::UUID;
  v_cost_center_id UUID := NULLIF(p_header->>'cost_center_id', '')::UUID;
  v_project_id UUID := NULLIF(p_header->>'project_id', '')::UUID;
  v_location_id UUID := NULLIF(p_header->>'location_id', '')::UUID;
  v_functional_entity_id UUID := NULLIF(p_header->>'functional_entity_id', '')::UUID;
  v_date DATE := COALESCE(NULLIF(p_header->>'bill_date','')::DATE, CURRENT_DATE);
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
  PERFORM fn_assert_transaction_dimension('project', v_project_id, v_company_id, v_branch_id, v_date, 'Vendor Bill');
  PERFORM fn_assert_transaction_dimension('location', v_location_id, v_company_id, v_branch_id, v_date, 'Vendor Bill');
  PERFORM fn_assert_transaction_dimension('functional_entity', v_functional_entity_id, v_company_id, v_branch_id, v_date, 'Vendor Bill');

  v_id := fn_save_vendor_bill_core_20260718(p_bill_id, p_header, p_lines);
  UPDATE vendor_bills
  SET warehouse_id = v_warehouse_id,
      department_id = v_department_id,
      cost_center_id = v_cost_center_id,
      project_id = v_project_id,
      location_id = v_location_id,
      functional_entity_id = v_functional_entity_id,
      updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_id AND company_id = v_company_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_save_cash_purchase(p_cp_id uuid, p_header jsonb, p_lines jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id UUID;
  v_company_id UUID := (p_header->>'company_id')::UUID;
  v_branch_id UUID := NULLIF(p_header->>'branch_id', '')::UUID;
  v_warehouse_id UUID := NULLIF(p_header->>'warehouse_id', '')::UUID;
  v_department_id UUID := NULLIF(p_header->>'department_id', '')::UUID;
  v_cost_center_id UUID := NULLIF(p_header->>'cost_center_id', '')::UUID;
  v_project_id UUID := NULLIF(p_header->>'project_id', '')::UUID;
  v_location_id UUID := NULLIF(p_header->>'location_id', '')::UUID;
  v_functional_entity_id UUID := NULLIF(p_header->>'functional_entity_id', '')::UUID;
  v_date DATE := COALESCE(NULLIF(p_header->>'transaction_date','')::DATE, CURRENT_DATE);
BEGIN
  PERFORM fn_validate_purchase_dimensions(
    v_company_id, v_branch_id, v_warehouse_id, v_department_id, v_cost_center_id
  );
  PERFORM fn_assert_transaction_dimension('project', v_project_id, v_company_id, v_branch_id, v_date, 'Cash Purchase');
  PERFORM fn_assert_transaction_dimension('location', v_location_id, v_company_id, v_branch_id, v_date, 'Cash Purchase');
  PERFORM fn_assert_transaction_dimension('functional_entity', v_functional_entity_id, v_company_id, v_branch_id, v_date, 'Cash Purchase');

  v_id := fn_save_cash_purchase_core_20260718(p_cp_id, p_header, p_lines);
  UPDATE cash_purchases
  SET warehouse_id = v_warehouse_id,
      department_id = v_department_id,
      cost_center_id = v_cost_center_id,
      project_id = v_project_id,
      location_id = v_location_id,
      functional_entity_id = v_functional_entity_id,
      updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_id AND company_id = v_company_id;
  RETURN v_id;
END;
$function$;

-- ── 4. Reusable source-side validator (active / effective-window / branch) ──────
-- Company-scoped rejection of an invalid analytical dimension at save time. NULL is
-- valid (dimensions are optional). Reused by VB/CP/GI/FA writers.
CREATE OR REPLACE FUNCTION public.fn_assert_transaction_dimension(
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
    RAISE EXCEPTION 'Invalid % for %',
      replace(p_dimension_type, '_', ' '), p_context;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_assert_transaction_dimension(TEXT, UUID, UUID, UUID, DATE, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_assert_transaction_dimension(TEXT, UUID, UUID, UUID, DATE, TEXT) TO authenticated, service_role;

-- ── 5. Reversal — already dimension-complete (no change needed) ─────────────────
-- Manual JE reversal (fn_reverse_je) delegates to fn_reverse_posted_journal_entry,
-- and SI void/reversal calls it directly; that function copies every line through
-- fn_add_sales_invoice_posting_line, which already carries all six dimensions
-- (branch, department, cost_center, project, location, functional_entity) onto the
-- reversal lines. No reversal function is modified here.

-- ── 6. Task 2 — Goods Issue posting propagates dept/cc/trio to the GL + inv tx ──
CREATE OR REPLACE FUNCTION public.fn_post_goods_issue_source_locked_impl(p_issue_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_gi      goods_issues%ROWTYPE;
  v_line    goods_issue_lines%ROWTYPE;
  v_item    items%ROWTYPE;
  v_sb      stock_balances%ROWTYPE;
  v_fp_id   UUID;
  v_je_id   UUID;
  v_line_no INT := 1;
  v_layer   RECORD;
  v_uc      NUMERIC;
  v_total   NUMERIC;
  v_je_total NUMERIC := 0;
BEGIN
  SELECT * INTO v_gi FROM goods_issues WHERE id = p_issue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Goods issue not found'; END IF;
  IF NOT is_company_member(v_gi.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_gi.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_gi.company_id
    AND start_date <= v_gi.issue_date AND end_date >= v_gi.issue_date
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %', v_gi.issue_date; END IF;

  -- Create JE header
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_gi.company_id, v_gi.branch_id,
    fn_next_document_number(v_gi.company_id, v_gi.branch_id, 'JE'),
    v_gi.issue_date, v_fp_id,
    'Goods Issue: ' || v_gi.issue_number || COALESCE(' — ' || v_gi.purpose, ''),
    'INV_GI', p_issue_id, 'posted', 0, 0,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN SELECT * FROM goods_issue_lines WHERE issue_id = p_issue_id LOOP
    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    v_sb := fn_ensure_stock_balance(v_gi.company_id, v_gi.warehouse_id, v_line.item_id);

    v_total := 0;

    IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
      SELECT wac_unit_cost INTO v_uc FROM stock_balances
      WHERE warehouse_id = v_gi.warehouse_id AND item_id = v_line.item_id;
      v_uc    := COALESCE(v_uc, 0);
      v_total := ROUND(v_line.qty_issued * v_uc, 2);
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_gi.company_id, v_gi.warehouse_id, v_line.item_id,
          v_line.qty_issued, v_line.lot_number, v_line.serial_number
        )
      LOOP
        v_total := v_total + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
        v_uc    := v_layer.unit_cost;
      END LOOP;
    END IF;

    -- Deduct stock
    UPDATE stock_balances
    SET qty_on_hand     = qty_on_hand - v_line.qty_issued,
        total_cost      = GREATEST(total_cost - v_total, 0),
        last_issue_date = v_gi.issue_date,
        updated_at      = NOW()
    WHERE warehouse_id = v_gi.warehouse_id AND item_id = v_line.item_id;

    IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_gi.warehouse_id AND item_id = v_line.item_id;
    END IF;

    -- Update line cost
    UPDATE goods_issue_lines SET unit_cost = ROUND(v_total / v_line.qty_issued, 6), total_cost = v_total WHERE id = v_line.id;

    -- JE lines: DR Expense / CR Inventory — dimensions travel from the GI header.
    DECLARE v_inv_acct UUID; v_exp_acct UUID;
    BEGIN
      SELECT inventory_account_id, cogs_account_id INTO v_inv_acct, v_exp_acct FROM items WHERE id = v_line.item_id;
      v_exp_acct := COALESCE(v_line.gl_expense_account_id, v_exp_acct);
      IF v_inv_acct IS NOT NULL AND v_exp_acct IS NOT NULL AND v_total > 0 THEN
        INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                         department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
        VALUES
          (v_je_id, v_gi.company_id, v_line_no,     v_exp_acct, 'Goods issue — ' || v_item.description, v_total, 0,
             v_gi.department_id, v_gi.cost_center_id, v_gi.project_id, v_gi.location_id, v_gi.functional_entity_id, auth.uid(), auth.uid()),
          (v_je_id, v_gi.company_id, v_line_no + 1, v_inv_acct, 'Goods issue — ' || v_item.description, 0,       v_total,
             v_gi.department_id, v_gi.cost_center_id, v_gi.project_id, v_gi.location_id, v_gi.functional_entity_id, auth.uid(), auth.uid());
        v_line_no  := v_line_no + 2;
        v_je_total := v_je_total + v_total;
      END IF;
    END;

    -- Transaction log — analytical trio travels onto the inventory movement.
    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by,
      project_id, location_id, functional_entity_id
    )
    SELECT v_gi.company_id, v_gi.warehouse_id, v_line.item_id,
      'issue', v_gi.issue_date,
      -v_line.qty_issued, ROUND(v_total / v_line.qty_issued, 6), -v_total,
      qty_on_hand, v_item.costing_method,
      'INV_GI', p_issue_id, v_line.lot_number, v_line.serial_number, auth.uid(),
      v_gi.project_id, v_gi.location_id, v_gi.functional_entity_id
    FROM stock_balances WHERE warehouse_id = v_gi.warehouse_id AND item_id = v_line.item_id;
  END LOOP;

  -- Update JE totals
  UPDATE journal_entries SET total_debit = v_je_total, total_credit = v_je_total WHERE id = v_je_id;

  UPDATE goods_issues
  SET status = 'posted', journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_issue_id;

  RETURN v_je_id;
END;
$function$;

-- ── 7. Task 2 — Fixed Asset acquisition / depreciation / disposal propagation ───
CREATE OR REPLACE FUNCTION public.fn_register_fixed_asset(p_data jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id   UUID := (p_data->>'company_id')::UUID;
  v_asset_id     UUID;
  v_je_id        UUID;
  v_cat          fixed_asset_categories%ROWTYPE;
  v_fp_id        UUID;
  v_asset_number TEXT;
  v_cost         NUMERIC := (p_data->>'acquisition_cost')::NUMERIC;
  v_salvage      NUMERIC := COALESCE((p_data->>'salvage_value')::NUMERIC, 0);
  v_months       INT     := (p_data->>'useful_life_months')::INT;
  v_method       TEXT    := p_data->>'depreciation_method';
  v_start_date   DATE    := (p_data->>'depreciation_start_date')::DATE;
  v_acq_date     DATE    := (p_data->>'acquisition_date')::DATE;
  v_branch_id    UUID    := (p_data->>'branch_id')::UUID;
  v_cat_id       UUID    := (p_data->>'category_id')::UUID;
  v_credit_acct  UUID    := (p_data->>'credit_account_id')::UUID;
  v_department_id UUID   := NULLIF(p_data->>'department_id','')::UUID;
  v_cost_center_id UUID  := NULLIF(p_data->>'cost_center_id','')::UUID;
  v_project_id   UUID    := NULLIF(p_data->>'project_id','')::UUID;
  v_location_id  UUID    := NULLIF(p_data->>'location_id','')::UUID;
  v_functional_entity_id UUID := NULLIF(p_data->>'functional_entity_id','')::UUID;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_cat FROM fixed_asset_categories WHERE id = v_cat_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset category not found'; END IF;
  IF v_cat.gl_asset_account_id IS NULL THEN RAISE EXCEPTION 'Asset category is missing GL asset account'; END IF;

  -- Validate dimensions (company/active/effective-window/branch).
  PERFORM fn_validate_purchase_dimensions(v_company_id, v_branch_id, NULL, v_department_id, v_cost_center_id);
  PERFORM fn_assert_transaction_dimension('project', v_project_id, v_company_id, v_branch_id, v_acq_date, 'Fixed Asset');
  PERFORM fn_assert_transaction_dimension('location', v_location_id, v_company_id, v_branch_id, v_acq_date, 'Fixed Asset');
  PERFORM fn_assert_transaction_dimension('functional_entity', v_functional_entity_id, v_company_id, v_branch_id, v_acq_date, 'Fixed Asset');

  -- Get or generate asset number
  v_asset_number := COALESCE(NULLIF(p_data->>'asset_number',''), fn_next_document_number(v_company_id, v_branch_id, 'FA'));

  -- Find open fiscal period for acquisition date
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= v_acq_date AND end_date >= v_acq_date AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found covering acquisition date %', v_acq_date;
  END IF;

  -- Post acquisition JE: DR Asset Account / CR Credit Account (cash/AP/bank)
  IF v_credit_acct IS NOT NULL THEN
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, status, total_debit, total_credit,
      created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      fn_next_document_number(v_company_id, v_branch_id, 'JE'),
      v_acq_date, v_fp_id,
      'FA Acquisition: ' || (p_data->>'asset_name'),
      'FA', 'posted', v_cost, v_cost,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;

    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES
      (v_je_id, v_company_id, 1, v_cat.gl_asset_account_id, 'Acquisition — ' || (p_data->>'asset_name'), v_cost, 0,
         v_department_id, v_cost_center_id, v_project_id, v_location_id, v_functional_entity_id, auth.uid(), auth.uid()),
      (v_je_id, v_company_id, 2, v_credit_acct, 'Acquisition — ' || (p_data->>'asset_name'), 0, v_cost,
         v_department_id, v_cost_center_id, v_project_id, v_location_id, v_functional_entity_id, auth.uid(), auth.uid());
  END IF;

  -- Insert asset record
  INSERT INTO fixed_assets (
    company_id, branch_id, department_id, cost_center_id, project_id, location_id, functional_entity_id,
    asset_number, asset_name, description,
    category_id, acquisition_date, depreciation_start_date, acquisition_cost,
    salvage_value, useful_life_months, depreciation_method, serial_number,
    location, supplier_id, acquisition_je_id, fiscal_period_id, status,
    notes, created_by, updated_by
  ) VALUES (
    v_company_id,
    v_branch_id,
    v_department_id, v_cost_center_id, v_project_id, v_location_id, v_functional_entity_id,
    v_asset_number,
    p_data->>'asset_name',
    p_data->>'description',
    v_cat_id,
    v_acq_date,
    v_start_date,
    v_cost,
    v_salvage,
    v_months,
    v_method,
    p_data->>'serial_number',
    p_data->>'location',
    (p_data->>'supplier_id')::UUID,
    v_je_id,
    v_fp_id,
    'active',
    p_data->>'notes',
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_asset_id;

  -- Generate depreciation schedule
  INSERT INTO asset_depreciation_entries (company_id, asset_id, period_number, entry_date, depreciation_amount, accumulated_depr_after, net_book_value_after, status)
  SELECT v_company_id, v_asset_id, s.period_number, s.entry_date, s.depreciation_amount, s.accumulated_depr_after, s.net_book_value_after, 'pending'
  FROM fn_compute_depr_schedule(v_cost, v_salvage, v_months, v_method, v_start_date) s;

  RETURN v_asset_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_post_depreciation_entry_source_locked_impl(p_entry_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_entry  asset_depreciation_entries%ROWTYPE;
  v_asset  fixed_assets%ROWTYPE;
  v_cat    fixed_asset_categories%ROWTYPE;
  v_fp_id  UUID;
  v_je_id  UUID;
BEGIN
  SELECT * INTO v_entry FROM asset_depreciation_entries WHERE id = p_entry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Depreciation entry not found'; END IF;
  IF NOT is_company_member(v_entry.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_entry.status = 'posted' THEN RAISE EXCEPTION 'Entry already posted'; END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = v_entry.asset_id;
  SELECT * INTO v_cat   FROM fixed_asset_categories WHERE id = v_asset.category_id;

  IF v_cat.gl_depr_expense_account_id IS NULL THEN RAISE EXCEPTION 'Category missing Depreciation Expense account'; END IF;
  IF v_cat.gl_accum_depr_account_id IS NULL   THEN RAISE EXCEPTION 'Category missing Accumulated Depreciation account'; END IF;

  -- Find open fiscal period covering entry_date
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_entry.company_id AND start_date <= v_entry.entry_date AND end_date >= v_entry.entry_date AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found covering %', v_entry.entry_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    v_entry.company_id, v_asset.branch_id,
    fn_next_document_number(v_entry.company_id, v_asset.branch_id, 'JE'),
    v_entry.entry_date, v_fp_id,
    'Depreciation — ' || v_asset.asset_name || ' (Period ' || v_entry.period_number || ')',
    'FA_DEPR', v_entry.asset_id, 'posted',
    v_entry.depreciation_amount, v_entry.depreciation_amount,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                   department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
  VALUES
    (v_je_id, v_entry.company_id, 1, v_cat.gl_depr_expense_account_id,
     'Depr — ' || v_asset.asset_name, v_entry.depreciation_amount, 0,
     v_asset.department_id, v_asset.cost_center_id, v_asset.project_id, v_asset.location_id, v_asset.functional_entity_id, auth.uid(), auth.uid()),
    (v_je_id, v_entry.company_id, 2, v_cat.gl_accum_depr_account_id,
     'Accum Depr — ' || v_asset.asset_name, 0, v_entry.depreciation_amount,
     v_asset.department_id, v_asset.cost_center_id, v_asset.project_id, v_asset.location_id, v_asset.functional_entity_id, auth.uid(), auth.uid());

  UPDATE asset_depreciation_entries
  SET status = 'posted', journal_entry_id = v_je_id, posted_at = NOW(), posted_by = auth.uid()
  WHERE id = p_entry_id;

  -- Auto-mark asset as fully depreciated if last entry
  IF v_entry.period_number = v_asset.useful_life_months THEN
    UPDATE fixed_assets SET status = 'fully_depreciated', updated_by = auth.uid(), updated_at = NOW()
    WHERE id = v_asset.id;
  END IF;

  RETURN v_je_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_dispose_fixed_asset(p_data jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id     UUID    := (p_data->>'company_id')::UUID;
  v_asset_id       UUID    := (p_data->>'asset_id')::UUID;
  v_disposal_date  DATE    := (p_data->>'disposal_date')::DATE;
  v_proceeds       NUMERIC := COALESCE((p_data->>'proceeds_amount')::NUMERIC, 0);
  v_asset          fixed_assets%ROWTYPE;
  v_cat            fixed_asset_categories%ROWTYPE;
  v_fp_id          UUID;
  v_je_id          UUID;
  v_disposal_id    UUID;
  v_accum_depr     NUMERIC;
  v_nbv            NUMERIC;
  v_gain_loss      NUMERIC;
  v_line           INT := 1;
  v_proceeds_acct  UUID := (p_data->>'proceeds_account_id')::UUID;
  v_d              UUID;
  v_cc             UUID;
  v_prj            UUID;
  v_loc            UUID;
  v_fe             UUID;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = v_asset_id AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset not found'; END IF;
  IF v_asset.status = 'disposed' THEN RAISE EXCEPTION 'Asset already disposed'; END IF;

  v_d := v_asset.department_id; v_cc := v_asset.cost_center_id;
  v_prj := v_asset.project_id; v_loc := v_asset.location_id; v_fe := v_asset.functional_entity_id;

  SELECT * INTO v_cat FROM fixed_asset_categories WHERE id = v_asset.category_id;

  IF v_cat.gl_asset_account_id IS NULL       THEN RAISE EXCEPTION 'Category missing Asset account'; END IF;
  IF v_cat.gl_accum_depr_account_id IS NULL  THEN RAISE EXCEPTION 'Category missing Accumulated Depreciation account'; END IF;

  -- Compute accumulated depreciation from posted entries
  SELECT COALESCE(SUM(depreciation_amount), 0) INTO v_accum_depr
  FROM asset_depreciation_entries
  WHERE asset_id = v_asset_id AND status = 'posted';

  -- Add impairment losses
  SELECT v_accum_depr + COALESCE(SUM(impairment_loss), 0) INTO v_accum_depr
  FROM asset_impairments WHERE asset_id = v_asset_id;

  v_nbv       := v_asset.acquisition_cost - v_accum_depr;
  v_gain_loss := v_proceeds - v_nbv; -- positive = gain, negative = loss

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= v_disposal_date AND end_date >= v_disposal_date AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for disposal date %', v_disposal_date; END IF;

  -- Build disposal JE
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_company_id, v_asset.branch_id,
    fn_next_document_number(v_company_id, v_asset.branch_id, 'JE'),
    v_disposal_date, v_fp_id,
    'FA Disposal: ' || v_asset.asset_name || ' (' || (p_data->>'disposal_type') || ')',
    'FA_DISP', 'posted',
    v_asset.acquisition_cost + GREATEST(v_gain_loss, 0),
    v_asset.acquisition_cost + GREATEST(v_gain_loss, 0),
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  -- DR Accumulated Depreciation
  IF v_accum_depr > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_accum_depr_account_id,
      'Accum Depr — ' || v_asset.asset_name, v_accum_depr, 0, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- DR Cash/Receivable (proceeds)
  IF v_proceeds > 0 AND v_proceeds_acct IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_proceeds_acct,
      'Proceeds — ' || v_asset.asset_name, v_proceeds, 0, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- DR Loss on Disposal (if loss)
  IF v_gain_loss < 0 AND v_cat.gl_loss_on_disposal_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_loss_on_disposal_account_id,
      'Loss on Disposal — ' || v_asset.asset_name, ABS(v_gain_loss), 0, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- CR Asset Cost
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                   department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
  VALUES (v_je_id, v_company_id, v_line, v_cat.gl_asset_account_id,
    'Asset Cost — ' || v_asset.asset_name, 0, v_asset.acquisition_cost, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());
  v_line := v_line + 1;

  -- CR Gain on Disposal (if gain)
  IF v_gain_loss > 0 AND v_cat.gl_gain_on_disposal_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount,
                                     department_id, cost_center_id, project_id, location_id, functional_entity_id, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_gain_on_disposal_account_id,
      'Gain on Disposal — ' || v_asset.asset_name, 0, v_gain_loss, v_d, v_cc, v_prj, v_loc, v_fe, auth.uid(), auth.uid());
  END IF;

  -- Record disposal
  INSERT INTO asset_disposals (
    company_id, asset_id, disposal_date, disposal_type, proceeds_amount,
    proceeds_account_id, cost_at_disposal, accum_depr_at_disposal,
    net_book_value, gain_loss_amount, journal_entry_id, fiscal_period_id, notes, created_by
  ) VALUES (
    v_company_id, v_asset_id, v_disposal_date, p_data->>'disposal_type',
    v_proceeds, v_proceeds_acct, v_asset.acquisition_cost, v_accum_depr,
    v_nbv, v_gain_loss, v_je_id, v_fp_id, p_data->>'notes', auth.uid()
  ) RETURNING id INTO v_disposal_id;

  -- Update asset status
  UPDATE fixed_assets
  SET status = 'disposed', disposed_at = v_disposal_date, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_asset_id;

  -- Skip remaining pending depreciation entries
  UPDATE asset_depreciation_entries SET status = 'skipped'
  WHERE asset_id = v_asset_id AND status = 'pending';

  RETURN v_je_id;
END;
$function$;

-- ── 8. Task 4 — production dimensional GL report (aggregate + drill-down) ────────
-- Line-grain aggregation of the certified general ledger. Because it is a pure
-- GROUP BY of vw_general_ledger with no join fan-out, every posted line is counted
-- exactly once: SUM over this view equals SUM over vw_general_ledger by construction
-- (the non-double-counting guarantee). security_invoker inherits GL tenant RLS.
CREATE OR REPLACE VIEW public.vw_gl_dimension_summary
WITH (security_invoker = true) AS
SELECT
  gl.company_id,
  gl.branch_id,
  gl.department_id,
  gl.cost_center_id,
  gl.project_id,
  gl.location_id,
  gl.functional_entity_id,
  gl.account_id,
  gl.account_code,
  gl.account_name,
  gl.account_type,
  gl.fiscal_period_id,
  gl.period_name,
  SUM(gl.debit_amount)                        AS total_debit,
  SUM(gl.credit_amount)                       AS total_credit,
  SUM(gl.debit_amount - gl.credit_amount)     AS net_debit,
  COUNT(*)                                    AS line_count
FROM vw_general_ledger gl
GROUP BY
  gl.company_id, gl.branch_id, gl.department_id, gl.cost_center_id,
  gl.project_id, gl.location_id, gl.functional_entity_id,
  gl.account_id, gl.account_code, gl.account_name, gl.account_type,
  gl.fiscal_period_id, gl.period_name;

COMMENT ON VIEW public.vw_gl_dimension_summary IS
  'Dimension Engine certification report: posted GL aggregated by every dimension + account. Line-grain, so dimensional totals reconcile exactly to the undimensioned GL control total (no double counting).';

-- Drill-down by any one dimension with resolved code/name and an Unassigned bucket.
-- Every posted line contributes to exactly one bucket, so the returned rows sum to
-- the GL control total for the company and date range.
CREATE OR REPLACE FUNCTION public.fn_report_gl_by_dimension(
  p_company_id UUID,
  p_dimension TEXT,
  p_date_from DATE DEFAULT NULL,
  p_date_to DATE DEFAULT NULL
)
RETURNS TABLE (
  dimension_id UUID,
  dimension_code TEXT,
  dimension_name TEXT,
  total_debit NUMERIC,
  total_credit NUMERIC,
  net_debit NUMERIC,
  line_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_dim_col  TEXT;
  v_master   TEXT;
  v_code_col TEXT;
  v_name_col TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  CASE p_dimension
    WHEN 'branch'            THEN v_dim_col := 'branch_id';            v_master := 'branches';            v_code_col := 'branch_code';       v_name_col := 'branch_name';
    WHEN 'department'        THEN v_dim_col := 'department_id';        v_master := 'departments';         v_code_col := 'department_code';   v_name_col := 'department_name';
    WHEN 'cost_center'       THEN v_dim_col := 'cost_center_id';       v_master := 'cost_centers';        v_code_col := 'cost_center_code';  v_name_col := 'cost_center_name';
    WHEN 'project'           THEN v_dim_col := 'project_id';           v_master := 'projects';            v_code_col := 'project_code';      v_name_col := 'project_name';
    WHEN 'location'          THEN v_dim_col := 'location_id';          v_master := 'locations';           v_code_col := 'location_code';     v_name_col := 'location_name';
    WHEN 'functional_entity' THEN v_dim_col := 'functional_entity_id'; v_master := 'functional_entities'; v_code_col := 'entity_code';       v_name_col := 'entity_name';
    ELSE RAISE EXCEPTION 'unknown dimension %', p_dimension USING ERRCODE = '22023';
  END CASE;

  RETURN QUERY EXECUTE format(
    $f$
      SELECT
        x.dim_id,
        COALESCE(m.%1$I, '(Unassigned)')::TEXT,
        COALESCE(m.%2$I, '(Unassigned)')::TEXT,
        SUM(x.debit_amount),
        SUM(x.credit_amount),
        SUM(x.debit_amount - x.credit_amount),
        COUNT(*)::BIGINT
      FROM (
        SELECT gl.%3$I AS dim_id, gl.debit_amount, gl.credit_amount
        FROM vw_general_ledger gl
        WHERE gl.company_id = $1
          AND ($2 IS NULL OR gl.je_date >= $2)
          AND ($3 IS NULL OR gl.je_date <= $3)
      ) x
      LEFT JOIN %4$I m ON m.id = x.dim_id
      GROUP BY x.dim_id, m.%1$I, m.%2$I
      ORDER BY 3
    $f$,
    v_code_col, v_name_col, v_dim_col, v_master
  )
  USING p_company_id, p_date_from, p_date_to;
END;
$$;

REVOKE ALL ON FUNCTION fn_report_gl_by_dimension(UUID, TEXT, DATE, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_report_gl_by_dimension(UUID, TEXT, DATE, DATE) TO authenticated, service_role;
GRANT SELECT ON public.vw_gl_dimension_summary TO authenticated, service_role;

COMMENT ON FUNCTION fn_report_gl_by_dimension(UUID, TEXT, DATE, DATE) IS
  'Dimension Engine certification report: drill the posted GL down by one dimension (branch/department/cost_center/project/location/functional_entity) with resolved code/name and an Unassigned bucket; rows reconcile to the GL control total.';

-- ── 9. Task 1 — Manual Journal accepts the analytical trio per line ─────────────
-- Preserves the certified validation/numbering/classification behavior verbatim;
-- only the per-line INSERT is widened to carry project/location/functional_entity.
CREATE OR REPLACE FUNCTION public.fn_post_manual_je(p_company_id uuid, p_branch_id uuid, p_je_date date, p_description text, p_reference_doc_type text, p_auto_reverse boolean, p_lines jsonb, p_entry_class text DEFAULT 'regular'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_total_debit  NUMERIC(15,2) := 0;
  v_total_credit NUMERIC(15,2) := 0;
  v_fp_id        UUID;
  v_je_id        UUID;
  v_je_number    TEXT;
  v_seq          INT;
  v_line         JSONB;
  v_line_no      INT := 0;
  v_dr           NUMERIC(15,2);
  v_cr           NUMERIC(15,2);
  v_account_id   UUID;
  v_postable     BOOLEAN;
  v_active       BOOLEAN;
  v_ref_type     TEXT;
  v_entry_class  TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  IF p_lines IS NULL OR jsonb_array_length(p_lines) < 2 THEN
    RAISE EXCEPTION 'Journal entry must have at least 2 lines';
  END IF;

  v_ref_type := COALESCE(NULLIF(p_reference_doc_type, ''), 'MANUAL');

  v_entry_class := COALESCE(NULLIF(p_entry_class, ''), 'regular');
  IF v_entry_class NOT IN ('regular','adjusting','opening') THEN
    RAISE EXCEPTION 'Manual journal entries may only be classified regular, adjusting, or opening (got %). Closing entries are posted by the year-end close.', v_entry_class;
  END IF;

  -- Validate each line and accumulate totals
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
  LOOP
    v_account_id := NULLIF(v_line->>'account_id', '')::UUID;
    v_dr := COALESCE((v_line->>'debit_amount')::NUMERIC, 0);
    v_cr := COALESCE((v_line->>'credit_amount')::NUMERIC, 0);

    IF v_account_id IS NULL THEN
      RAISE EXCEPTION 'Every line must reference an account';
    END IF;
    IF v_dr < 0 OR v_cr < 0 THEN
      RAISE EXCEPTION 'Line amounts cannot be negative';
    END IF;
    IF v_dr > 0 AND v_cr > 0 THEN
      RAISE EXCEPTION 'A line cannot have both a debit and a credit amount';
    END IF;
    IF v_dr = 0 AND v_cr = 0 THEN
      RAISE EXCEPTION 'A line must have a non-zero debit or credit amount';
    END IF;

    SELECT is_postable, is_active INTO v_postable, v_active
    FROM chart_of_accounts
    WHERE id = v_account_id AND company_id = p_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Account % does not belong to this company', v_account_id;
    END IF;
    IF NOT v_postable THEN
      RAISE EXCEPTION 'Account % is not postable (header / summary account)', v_account_id;
    END IF;
    IF NOT v_active THEN
      RAISE EXCEPTION 'Account % is inactive', v_account_id;
    END IF;

    v_total_debit  := v_total_debit + v_dr;
    v_total_credit := v_total_credit + v_cr;
  END LOOP;

  IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
    RAISE EXCEPTION 'Journal entry must balance: total debit % <> total credit %', v_total_debit, v_total_credit;
  END IF;
  IF v_total_debit <= 0 THEN
    RAISE EXCEPTION 'Journal entry must have at least one non-zero amount';
  END IF;

  -- Open fiscal period required
  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = p_company_id
    AND start_date <= p_je_date AND end_date >= p_je_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period covers % — posting is not allowed', p_je_date;
  END IF;

  -- Generate a unique JE number for this company
  SELECT COUNT(*) + 1 INTO v_seq
  FROM journal_entries
  WHERE company_id = p_company_id AND je_number LIKE 'MJE-' || TO_CHAR(p_je_date, 'YYYYMM') || '-%';
  LOOP
    v_je_number := 'MJE-' || TO_CHAR(p_je_date, 'YYYYMM') || '-' || LPAD(v_seq::TEXT, 4, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM journal_entries WHERE company_id = p_company_id AND je_number = v_je_number
    );
    v_seq := v_seq + 1;
  END LOOP;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status, entry_class,
    total_debit, total_credit, auto_reverse, is_auto_reversal,
    created_by, updated_by
  ) VALUES (
    p_company_id, NULLIF(p_branch_id::TEXT, '')::UUID, v_je_number, p_je_date, v_fp_id,
    COALESCE(p_description, 'Manual Journal Entry'), v_ref_type, NULL, 'posted', v_entry_class,
    v_total_debit, v_total_credit, COALESCE(p_auto_reverse, false), false,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, branch_id, department_id, cost_center_id,
      project_id, location_id, functional_entity_id,
      created_by, updated_by
    ) VALUES (
      v_je_id, p_company_id, v_line_no,
      (v_line->>'account_id')::UUID,
      NULLIF(v_line->>'description', ''),
      COALESCE((v_line->>'debit_amount')::NUMERIC, 0),
      COALESCE((v_line->>'credit_amount')::NUMERIC, 0),
      NULLIF(v_line->>'branch_id', '')::UUID,
      NULLIF(v_line->>'department_id', '')::UUID,
      NULLIF(v_line->>'cost_center_id', '')::UUID,
      NULLIF(v_line->>'project_id', '')::UUID,
      NULLIF(v_line->>'location_id', '')::UUID,
      NULLIF(v_line->>'functional_entity_id', '')::UUID,
      auth.uid(), auth.uid()
    );
  END LOOP;

  RETURN v_je_id;
END;
$function$;
