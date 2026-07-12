-- PXL-AUD-051: reconcile document-code drift between ref_document_types, UI
-- readiness codes, and RPC numbering codes; repair branch-less numbering calls.
--
-- Two independent defects are closed here:
--   1. Registry gap: shipped functions request document codes JE, FA, SDM, and
--      PRT that do not exist in ref_document_types, so a registry-consistent
--      number-series setup cannot satisfy them. This adds the four governed
--      rows. (DM-S already exists; the DebitMemosPage readiness code is fixed on
--      the frontend to match its fn_save_debit_memo 'DM-S' numbering.)
--   2. Branch-less numbering: eight fixed-asset/inventory functions call the
--      two-argument fn_next_document_number(company_id, code) signature, which
--      does not exist (numbering is per company+branch+code under DEC-006), so
--      those posting paths fail at runtime. Each caller now passes the branch it
--      already writes onto the journal_entries row it is creating. The held-out
--      arbitrary-branch overload from 20260710000005 is deliberately NOT used.
--
-- This migration does not depend on or redefine the held-out ATC/CAS migrations
-- 20260710000004/00005. CREATE OR REPLACE preserves the existing REVOKE/GRANT
-- ACLs on the *_source_locked_impl helpers (still owner-only).

-- ---------------------------------------------------------------------------
-- 1. Governed registry rows for every code shipped functions actually request.
-- ---------------------------------------------------------------------------
INSERT INTO ref_document_types (category, document_code, document_name, is_bir_registered, sort_order)
VALUES
  ('accounting', 'JE',  'Journal Entry',        false, 30),
  ('accounting', 'FA',  'Fixed Asset Number',   false, 31),
  ('purchasing', 'SDM', 'Supplier Debit Memo',  false, 18),
  ('purchasing', 'PRT', 'Purchase Return',      false, 19)
ON CONFLICT (document_code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Branch-scoped repair of the eight two-argument numbering callers.
--    Bodies are the deployed definitions with the numbering call corrected to
--    pass the transaction branch already used on the adjacent JE insert.
-- ---------------------------------------------------------------------------
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
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_cat FROM fixed_asset_categories WHERE id = v_cat_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset category not found'; END IF;
  IF v_cat.gl_asset_account_id IS NULL THEN RAISE EXCEPTION 'Asset category is missing GL asset account'; END IF;

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

    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES
      (v_je_id, v_company_id, 1, v_cat.gl_asset_account_id, 'Acquisition — ' || (p_data->>'asset_name'), v_cost, 0, auth.uid(), auth.uid()),
      (v_je_id, v_company_id, 2, v_credit_acct, 'Acquisition — ' || (p_data->>'asset_name'), 0, v_cost, auth.uid(), auth.uid());
  END IF;

  -- Insert asset record
  INSERT INTO fixed_assets (
    company_id, branch_id, department_id, asset_number, asset_name, description,
    category_id, acquisition_date, depreciation_start_date, acquisition_cost,
    salvage_value, useful_life_months, depreciation_method, serial_number,
    location, supplier_id, acquisition_je_id, fiscal_period_id, status,
    notes, created_by, updated_by
  ) VALUES (
    v_company_id,
    v_branch_id,
    (p_data->>'department_id')::UUID,
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
$function$
;


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
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = v_asset_id AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset not found'; END IF;
  IF v_asset.status = 'disposed' THEN RAISE EXCEPTION 'Asset already disposed'; END IF;

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
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_accum_depr_account_id,
      'Accum Depr — ' || v_asset.asset_name, v_accum_depr, 0, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- DR Cash/Receivable (proceeds)
  IF v_proceeds > 0 AND v_proceeds_acct IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_proceeds_acct,
      'Proceeds — ' || v_asset.asset_name, v_proceeds, 0, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- DR Loss on Disposal (if loss)
  IF v_gain_loss < 0 AND v_cat.gl_loss_on_disposal_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_loss_on_disposal_account_id,
      'Loss on Disposal — ' || v_asset.asset_name, ABS(v_gain_loss), 0, auth.uid(), auth.uid());
    v_line := v_line + 1;
  END IF;

  -- CR Asset Cost
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES (v_je_id, v_company_id, v_line, v_cat.gl_asset_account_id,
    'Asset Cost — ' || v_asset.asset_name, 0, v_asset.acquisition_cost, auth.uid(), auth.uid());
  v_line := v_line + 1;

  -- CR Gain on Disposal (if gain)
  IF v_gain_loss > 0 AND v_cat.gl_gain_on_disposal_account_id IS NOT NULL THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES (v_je_id, v_company_id, v_line, v_cat.gl_gain_on_disposal_account_id,
      'Gain on Disposal — ' || v_asset.asset_name, 0, v_gain_loss, auth.uid(), auth.uid());
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
$function$
;


CREATE OR REPLACE FUNCTION public.fn_record_impairment(p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id       UUID    := (p_data->>'company_id')::UUID;
  v_asset_id         UUID    := (p_data->>'asset_id')::UUID;
  v_imp_date         DATE    := (p_data->>'impairment_date')::DATE;
  v_recoverable      NUMERIC := COALESCE((p_data->>'recoverable_amount')::NUMERIC, 0);
  v_asset            fixed_assets%ROWTYPE;
  v_cat              fixed_asset_categories%ROWTYPE;
  v_carrying         NUMERIC;
  v_accum_depr       NUMERIC;
  v_loss             NUMERIC;
  v_fp_id            UUID;
  v_je_id            UUID;
  v_imp_loss_acct    UUID := (p_data->>'gl_impairment_loss_account_id')::UUID;
  v_accum_imp_acct   UUID := (p_data->>'gl_accum_impairment_account_id')::UUID;
BEGIN
  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT * INTO v_asset FROM fixed_assets WHERE id = v_asset_id AND company_id = v_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Asset not found'; END IF;
  IF v_asset.status = 'disposed' THEN RAISE EXCEPTION 'Cannot impair a disposed asset'; END IF;

  SELECT * INTO v_cat FROM fixed_asset_categories WHERE id = v_asset.category_id;

  -- Use category accounts if not overridden
  v_imp_loss_acct  := COALESCE(v_imp_loss_acct,  v_cat.gl_impairment_loss_account_id);
  v_accum_imp_acct := COALESCE(v_accum_imp_acct, v_cat.gl_accum_depr_account_id);

  IF v_imp_loss_acct IS NULL  THEN RAISE EXCEPTION 'No Impairment Loss GL account specified'; END IF;
  IF v_accum_imp_acct IS NULL THEN RAISE EXCEPTION 'No Accumulated Impairment GL account specified'; END IF;

  -- Current carrying amount (cost - accumulated depr - prior impairments)
  SELECT COALESCE(SUM(depreciation_amount), 0) INTO v_accum_depr
  FROM asset_depreciation_entries WHERE asset_id = v_asset_id AND status = 'posted';

  SELECT v_accum_depr + COALESCE(SUM(impairment_loss), 0) INTO v_accum_depr
  FROM asset_impairments WHERE asset_id = v_asset_id;

  v_carrying := v_asset.acquisition_cost - v_accum_depr;

  IF v_recoverable >= v_carrying THEN
    RAISE EXCEPTION 'Recoverable amount (%) must be less than carrying amount (%) for impairment to exist', v_recoverable, v_carrying;
  END IF;

  v_loss := v_carrying - v_recoverable;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id AND start_date <= v_imp_date AND end_date >= v_imp_date AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for impairment date %', v_imp_date; END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, status, total_debit, total_credit,
    created_by, updated_by
  ) VALUES (
    v_company_id, v_asset.branch_id,
    fn_next_document_number(v_company_id, v_asset.branch_id, 'JE'),
    v_imp_date, v_fp_id,
    'Impairment Loss — ' || v_asset.asset_name,
    'FA_IMP', 'posted', v_loss, v_loss,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_company_id, 1, v_imp_loss_acct,  'Impairment Loss — ' || v_asset.asset_name, v_loss, 0, auth.uid(), auth.uid()),
    (v_je_id, v_company_id, 2, v_accum_imp_acct, 'Accum Impairment — ' || v_asset.asset_name, 0, v_loss, auth.uid(), auth.uid());

  INSERT INTO asset_impairments (
    company_id, asset_id, impairment_date,
    carrying_amount_before, recoverable_amount, impairment_loss,
    gl_impairment_loss_account_id, gl_accum_impairment_account_id,
    journal_entry_id, fiscal_period_id, notes, created_by
  ) VALUES (
    v_company_id, v_asset_id, v_imp_date,
    v_carrying, v_recoverable, v_loss,
    v_imp_loss_acct, v_accum_imp_acct,
    v_je_id, v_fp_id, p_data->>'notes', auth.uid()
  );

  UPDATE fixed_assets SET status = 'impaired', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_asset_id;

  RETURN v_je_id;
END;
$function$
;


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

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
  VALUES
    (v_je_id, v_entry.company_id, 1, v_cat.gl_depr_expense_account_id,
     'Depr — ' || v_asset.asset_name, v_entry.depreciation_amount, 0, auth.uid(), auth.uid()),
    (v_je_id, v_entry.company_id, 2, v_cat.gl_accum_depr_account_id,
     'Accum Depr — ' || v_asset.asset_name, 0, v_entry.depreciation_amount, auth.uid(), auth.uid());

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
$function$
;


CREATE OR REPLACE FUNCTION public.fn_post_stock_adjustment_source_locked_impl(p_adjustment_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_adj      stock_adjustments%ROWTYPE;
  v_line     stock_adjustment_lines%ROWTYPE;
  v_item     items%ROWTYPE;
  v_wh       warehouses%ROWTYPE;
  v_sb       stock_balances%ROWTYPE;
  v_fp_id    UUID;
  v_je_id    UUID;
  v_line_no  INT := 1;
  v_total_impact NUMERIC := 0;
BEGIN
  SELECT * INTO v_adj FROM stock_adjustments WHERE id = p_adjustment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Adjustment not found'; END IF;
  IF NOT is_company_member(v_adj.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_adj.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT * INTO v_wh FROM warehouses WHERE id = v_adj.warehouse_id;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_adj.company_id
    AND start_date <= v_adj.adjustment_date AND end_date >= v_adj.adjustment_date
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %', v_adj.adjustment_date; END IF;

  -- Process each line
  FOR v_line IN SELECT * FROM stock_adjustment_lines WHERE adjustment_id = p_adjustment_id LOOP
    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    v_sb := fn_ensure_stock_balance(v_adj.company_id, v_adj.warehouse_id, v_line.item_id);

    IF v_line.qty_adjusted < 0 AND v_sb.qty_on_hand < ABS(v_line.qty_adjusted) THEN
      RAISE EXCEPTION 'Item % has insufficient stock. On hand: %, trying to reduce by: %',
        v_item.description, v_sb.qty_on_hand, ABS(v_line.qty_adjusted);
    END IF;

    -- Determine unit cost for adjustment
    DECLARE v_uc NUMERIC;
    BEGIN
      v_uc := CASE
        WHEN v_line.unit_cost > 0 THEN v_line.unit_cost
        WHEN v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL
          THEN COALESCE(v_sb.wac_unit_cost, v_item.standard_cost, 0)
        ELSE v_item.standard_cost
      END;

      -- Update stock balance
      UPDATE stock_balances
      SET qty_on_hand   = qty_on_hand + v_line.qty_adjusted,
          total_cost    = GREATEST(total_cost + (v_line.qty_adjusted * v_uc), 0),
          updated_at    = NOW()
      WHERE warehouse_id = v_adj.warehouse_id AND item_id = v_line.item_id;

      -- Refresh WAC
      IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
        UPDATE stock_balances
        SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
        WHERE warehouse_id = v_adj.warehouse_id AND item_id = v_line.item_id;
      END IF;

      -- For FIFO positive adjustments: add layer; negative: consume via FIFO
      IF v_item.costing_method IN ('fifo','specific_identification') THEN
        IF v_line.qty_adjusted > 0 THEN
          PERFORM fn_add_cost_layer(v_adj.company_id, v_adj.warehouse_id, v_line.item_id,
            v_adj.adjustment_date, v_line.qty_adjusted, v_uc, 'ADJ', p_adjustment_id,
            v_line.lot_number, v_line.serial_number);
        ELSIF v_line.qty_adjusted < 0 THEN
          PERFORM fn_consume_cost_layers(v_adj.company_id, v_adj.warehouse_id, v_line.item_id,
            ABS(v_line.qty_adjusted), v_line.lot_number, v_line.serial_number);
        END IF;
      END IF;

      -- Accumulate GL impact
      v_total_impact := v_total_impact + (v_line.qty_adjusted * v_uc);

      -- Update line with resolved cost
      UPDATE stock_adjustment_lines
      SET unit_cost         = v_uc,
          total_cost_impact = ROUND(v_line.qty_adjusted * v_uc, 2)
      WHERE id = v_line.id;

      -- Transaction log
      INSERT INTO inventory_transactions (
        company_id, warehouse_id, item_id,
        transaction_type, transaction_date,
        qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
        reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
      )
      SELECT v_adj.company_id, v_adj.warehouse_id, v_line.item_id,
        CASE WHEN v_line.qty_adjusted >= 0 THEN 'adjustment_in' ELSE 'adjustment_out' END,
        v_adj.adjustment_date,
        v_line.qty_adjusted, v_uc, ROUND(v_line.qty_adjusted * v_uc, 2),
        qty_on_hand, v_item.costing_method,
        'ADJ', p_adjustment_id, v_line.lot_number, v_line.serial_number, auth.uid()
      FROM stock_balances WHERE warehouse_id = v_adj.warehouse_id AND item_id = v_line.item_id;
    END;
  END LOOP;

  -- Post GL entry if there is a non-zero impact
  IF ABS(v_total_impact) > 0 THEN
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_adj.company_id, v_adj.branch_id,
      fn_next_document_number(v_adj.company_id, v_adj.branch_id, 'JE'),
      v_adj.adjustment_date, v_fp_id,
      'Stock Adjustment: ' || v_adj.adjustment_number || ' (' || v_adj.reason || ')',
      'INV_ADJ', p_adjustment_id, 'posted',
      GREATEST(v_total_impact, 0), GREATEST(-v_total_impact, 0),
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;

    -- Build JE lines per line (using item's inventory and offset accounts)
    FOR v_line IN SELECT sal.*, i.inventory_account_id
      FROM stock_adjustment_lines sal
      JOIN items i ON i.id = sal.item_id
      WHERE sal.adjustment_id = p_adjustment_id
    LOOP
      DECLARE v_inv_acct UUID; v_off_acct UUID; v_impact NUMERIC;
      BEGIN
        v_inv_acct := v_line.gl_offset_account_id; -- reuse field for simplicity
        SELECT inventory_account_id INTO v_inv_acct FROM items WHERE id = v_line.item_id;
        v_off_acct := v_line.gl_offset_account_id;
        v_impact   := ROUND(v_line.qty_adjusted * v_line.unit_cost, 2);

        IF v_inv_acct IS NOT NULL AND v_off_acct IS NOT NULL AND v_impact <> 0 THEN
          -- Positive: DR Inventory / CR Offset. Negative: DR Offset / CR Inventory
          INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
          VALUES
            (v_je_id, v_adj.company_id, v_line_no,     v_inv_acct, 'Inventory adj', GREATEST(v_impact,0), GREATEST(-v_impact,0), auth.uid(), auth.uid()),
            (v_je_id, v_adj.company_id, v_line_no + 1, v_off_acct, 'Adj offset',    GREATEST(-v_impact,0), GREATEST(v_impact,0), auth.uid(), auth.uid());
          v_line_no := v_line_no + 2;
        END IF;
      END;
    END LOOP;
  END IF;

  UPDATE stock_adjustments
  SET status = 'posted', journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_adjustment_id;

  RETURN v_je_id;
END;
$function$
;


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
    AND start_date <= v_tx.transfer_date AND end_date >= v_tx.transfer_date
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %', v_tx.transfer_date; END IF;

  FOR v_line IN SELECT * FROM stock_transfer_lines WHERE transfer_id = p_transfer_id LOOP
    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    PERFORM fn_ensure_stock_balance(v_tx.company_id, v_tx.from_warehouse_id, v_line.item_id);
    PERFORM fn_ensure_stock_balance(v_tx.company_id, v_tx.to_warehouse_id,   v_line.item_id);

    v_uc := 0;
    v_total := 0;

    IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
      -- WAC: use source WAC cost
      SELECT wac_unit_cost INTO v_uc FROM stock_balances
      WHERE warehouse_id = v_tx.from_warehouse_id AND item_id = v_line.item_id;
      v_uc    := COALESCE(v_uc, 0);
      v_total := ROUND(v_line.qty_transferred * v_uc, 2);

      -- Deduct from source
      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand - v_line.qty_transferred,
          total_cost  = GREATEST(total_cost - v_total, 0),
          last_issue_date = v_tx.transfer_date, updated_at = NOW()
      WHERE warehouse_id = v_tx.from_warehouse_id AND item_id = v_line.item_id;

      -- Add to destination (re-computes WAC at destination)
      PERFORM fn_update_wac(v_tx.to_warehouse_id, v_line.item_id, v_line.qty_transferred, v_uc);
      UPDATE stock_balances
      SET qty_on_hand      = qty_on_hand + v_line.qty_transferred,
          total_cost       = total_cost + v_total,
          last_receipt_date = v_tx.transfer_date, updated_at = NOW()
      WHERE warehouse_id = v_tx.to_warehouse_id AND item_id = v_line.item_id;
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_tx.to_warehouse_id AND item_id = v_line.item_id;

    ELSE
      -- FIFO / Specific ID: consume layers at source, recreate at destination
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_tx.company_id, v_tx.from_warehouse_id, v_line.item_id,
          v_line.qty_transferred, v_line.lot_number, v_line.serial_number
        )
      LOOP
        v_total := v_total + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
        -- Create layer at destination preserving cost and date
        PERFORM fn_add_cost_layer(
          v_tx.company_id, v_tx.to_warehouse_id, v_line.item_id,
          v_tx.transfer_date, v_layer.qty_consumed, v_layer.unit_cost,
          'STX', p_transfer_id, v_line.lot_number, v_line.serial_number
        );
        v_uc := v_layer.unit_cost; -- last unit cost for logging
      END LOOP;

      UPDATE stock_balances
      SET qty_on_hand = qty_on_hand - v_line.qty_transferred,
          total_cost  = GREATEST(total_cost - v_total, 0),
          last_issue_date = v_tx.transfer_date, updated_at = NOW()
      WHERE warehouse_id = v_tx.from_warehouse_id AND item_id = v_line.item_id;

      UPDATE stock_balances
      SET qty_on_hand       = qty_on_hand + v_line.qty_transferred,
          total_cost        = total_cost + v_total,
          last_receipt_date = v_tx.transfer_date, updated_at = NOW()
      WHERE warehouse_id = v_tx.to_warehouse_id AND item_id = v_line.item_id;
    END IF;

    -- Update line totals
    UPDATE stock_transfer_lines
    SET unit_cost = ROUND(v_total / v_line.qty_transferred, 6), total_cost = v_total
    WHERE id = v_line.id;

    -- Transaction log
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
    FROM stock_balances WHERE warehouse_id = v_tx.from_warehouse_id AND item_id = v_line.item_id;

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
    FROM stock_balances WHERE warehouse_id = v_tx.to_warehouse_id AND item_id = v_line.item_id;
  END LOOP;

  -- GL entry only if warehouses have different inventory GL accounts
  IF v_from_wh.gl_inventory_account_id IS NOT NULL
     AND v_to_wh.gl_inventory_account_id IS NOT NULL
     AND v_from_wh.gl_inventory_account_id <> v_to_wh.gl_inventory_account_id THEN

    SELECT SUM(total_cost) INTO v_total FROM stock_transfer_lines WHERE transfer_id = p_transfer_id;

    INSERT INTO journal_entries (
      company_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      v_tx.company_id, fn_next_document_number(v_tx.company_id, v_tx.branch_id, 'JE'),
      v_tx.transfer_date, v_fp_id,
      'Stock Transfer: ' || v_tx.transfer_number,
      'INV_STX', p_transfer_id, 'posted', v_total, v_total,
      auth.uid(), auth.uid()
    ) RETURNING id INTO v_je_id;

    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
    VALUES
      (v_je_id, v_tx.company_id, 1, v_to_wh.gl_inventory_account_id,   'Transfer in',  v_total, 0,       auth.uid(), auth.uid()),
      (v_je_id, v_tx.company_id, 2, v_from_wh.gl_inventory_account_id, 'Transfer out', 0,       v_total, auth.uid(), auth.uid());
  END IF;

  UPDATE stock_transfers
  SET status = 'posted', journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_transfer_id;

  RETURN v_je_id;
END;
$function$
;


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

    -- JE lines: DR Expense / CR Inventory
    DECLARE v_inv_acct UUID; v_exp_acct UUID;
    BEGIN
      SELECT inventory_account_id, cogs_account_id INTO v_inv_acct, v_exp_acct FROM items WHERE id = v_line.item_id;
      v_exp_acct := COALESCE(v_line.gl_expense_account_id, v_exp_acct);
      IF v_inv_acct IS NOT NULL AND v_exp_acct IS NOT NULL AND v_total > 0 THEN
        INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
        VALUES
          (v_je_id, v_gi.company_id, v_line_no,     v_exp_acct, 'Goods issue — ' || v_item.description, v_total, 0,       auth.uid(), auth.uid()),
          (v_je_id, v_gi.company_id, v_line_no + 1, v_inv_acct, 'Goods issue — ' || v_item.description, 0,       v_total, auth.uid(), auth.uid());
        v_line_no  := v_line_no + 2;
        v_je_total := v_je_total + v_total;
      END IF;
    END;

    -- Transaction log
    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, lot_number, serial_number, created_by
    )
    SELECT v_gi.company_id, v_gi.warehouse_id, v_line.item_id,
      'issue', v_gi.issue_date,
      -v_line.qty_issued, ROUND(v_total / v_line.qty_issued, 6), -v_total,
      qty_on_hand, v_item.costing_method,
      'INV_GI', p_issue_id, v_line.lot_number, v_line.serial_number, auth.uid()
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
$function$
;


CREATE OR REPLACE FUNCTION public.fn_post_physical_count_source_locked_impl(p_sheet_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
  SELECT * INTO v_cs FROM physical_count_sheets WHERE id = p_sheet_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Count sheet not found'; END IF;
  IF NOT is_company_member(v_cs.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_cs.status = 'posted' THEN RAISE EXCEPTION 'Already posted'; END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_cs.company_id
    AND start_date <= v_cs.count_date AND end_date >= v_cs.count_date
    AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %', v_cs.count_date; END IF;

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

  FOR v_line IN SELECT * FROM physical_count_sheet_lines WHERE count_sheet_id = p_sheet_id LOOP
    v_variance := COALESCE(v_line.counted_qty, v_line.system_qty) - v_line.system_qty;
    CONTINUE WHEN v_variance = 0;

    SELECT * INTO v_item FROM items WHERE id = v_line.item_id;
    PERFORM fn_ensure_stock_balance(v_cs.company_id, v_cs.warehouse_id, v_line.item_id);

    -- Determine unit cost for variance
    SELECT wac_unit_cost INTO v_uc FROM stock_balances
    WHERE warehouse_id = v_cs.warehouse_id AND item_id = v_line.item_id;
    v_uc := COALESCE(
      CASE WHEN v_line.unit_cost > 0 THEN v_line.unit_cost ELSE NULL END,
      v_uc, v_item.standard_cost, 0
    );

    -- Apply variance to stock balance
    UPDATE stock_balances
    SET qty_on_hand = qty_on_hand + v_variance,
        total_cost  = GREATEST(total_cost + (v_variance * v_uc), 0),
        updated_at  = NOW()
    WHERE warehouse_id = v_cs.warehouse_id AND item_id = v_line.item_id;

    IF v_item.costing_method = 'weighted_average' OR v_item.costing_method IS NULL THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_cs.warehouse_id AND item_id = v_line.item_id;
    END IF;

    -- For FIFO: add/consume layer for variance
    IF v_item.costing_method IN ('fifo','specific_identification') THEN
      IF v_variance > 0 THEN
        PERFORM fn_add_cost_layer(v_cs.company_id, v_cs.warehouse_id, v_line.item_id,
          v_cs.count_date, v_variance, v_uc, 'COUNT', p_sheet_id, v_line.lot_number, v_line.serial_number);
      ELSE
        PERFORM fn_consume_cost_layers(v_cs.company_id, v_cs.warehouse_id, v_line.item_id,
          ABS(v_variance), v_line.lot_number, v_line.serial_number);
      END IF;
    END IF;

    -- Update line variance cost
    UPDATE physical_count_sheet_lines
    SET unit_cost      = v_uc,
        variance_cost  = ROUND(v_variance * v_uc, 2)
    WHERE id = v_line.id;

    -- GL: DR/CR Inventory / CR/DR Variance Account
    DECLARE v_inv_acct UUID; v_var_acct UUID; v_impact NUMERIC;
    BEGIN
      SELECT inventory_account_id INTO v_inv_acct FROM items WHERE id = v_line.item_id;
      v_var_acct := COALESCE(
        v_line.gl_variance_account_id,
        (SELECT gl_variance_account_id FROM warehouses WHERE id = v_cs.warehouse_id)
      );
      v_impact := ROUND(v_variance * v_uc, 2);
      v_je_total := v_je_total + ABS(v_impact);

      IF v_inv_acct IS NOT NULL AND v_var_acct IS NOT NULL THEN
        INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, created_by, updated_by)
        VALUES
          (v_je_id, v_cs.company_id, v_line_no,     v_inv_acct, 'Count variance — ' || v_item.description,
            GREATEST(v_impact,0), GREATEST(-v_impact,0), auth.uid(), auth.uid()),
          (v_je_id, v_cs.company_id, v_line_no + 1, v_var_acct, 'Count variance — ' || v_item.description,
            GREATEST(-v_impact,0), GREATEST(v_impact,0), auth.uid(), auth.uid());
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
      CASE WHEN v_variance >= 0 THEN 'count_variance_in' ELSE 'count_variance_out' END,
      v_cs.count_date,
      v_variance, v_uc, ROUND(v_variance * v_uc, 2),
      qty_on_hand, v_item.costing_method,
      'INV_COUNT', p_sheet_id, v_line.lot_number, v_line.serial_number, auth.uid()
    FROM stock_balances WHERE warehouse_id = v_cs.warehouse_id AND item_id = v_line.item_id;
  END LOOP;

  UPDATE journal_entries SET total_debit = v_je_total, total_credit = v_je_total WHERE id = v_je_id;

  UPDATE physical_count_sheets
  SET status = 'posted', journal_entry_id = v_je_id,
      fiscal_period_id = v_fp_id, posted_at = NOW(), posted_by = auth.uid(),
      updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_sheet_id;

  RETURN v_je_id;
END;
$function$
;


