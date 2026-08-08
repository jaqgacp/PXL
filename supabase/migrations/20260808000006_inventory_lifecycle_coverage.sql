-- ============================================================================
-- Complete production inventory-writer coverage for WAC, FIFO, and Specific ID.
-- Every existing stock-changing surface delegates valuation to the shared
-- receive/issue/return/transfer authorities and retains source-line evidence.
-- ============================================================================

ALTER TABLE public.credit_memo_lines
  ADD COLUMN IF NOT EXISTS inventory_cost_layer_id UUID
    REFERENCES public.inventory_cost_layers(id),
  ADD COLUMN IF NOT EXISTS lot_number TEXT,
  ADD COLUMN IF NOT EXISTS serial_number TEXT;

ALTER TABLE public.purchase_return_lines
  ADD COLUMN IF NOT EXISTS inventory_cost_layer_id UUID
    REFERENCES public.inventory_cost_layers(id),
  ADD COLUMN IF NOT EXISTS lot_number TEXT,
  ADD COLUMN IF NOT EXISTS serial_number TEXT,
  ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(18,6),
  ADD COLUMN IF NOT EXISTS inventory_cost NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS inventory_transaction_id UUID
    REFERENCES public.inventory_transactions(id);

CREATE OR REPLACE VIEW public.vw_available_inventory_identities
WITH (security_invoker = true)
AS
SELECT
  l.id AS inventory_cost_layer_id,
  l.company_id,
  l.warehouse_id,
  l.item_id,
  l.layer_date,
  l.lot_number,
  l.serial_number,
  l.qty_remaining AS available_qty,
  CASE WHEN l.qty_remaining > 0
       THEN ROUND(l.remaining_value / l.qty_remaining, 6) ELSE 0 END AS unit_cost,
  l.remaining_value,
  l.reference_doc_type,
  l.reference_doc_id,
  l.source_line_id,
  l.origin_inventory_transaction_id
FROM public.inventory_cost_layers l
JOIN public.items i ON i.id = l.item_id
WHERE i.costing_method = 'specific_identification'
  AND l.qty_remaining > 0
  AND l.voided_by_inventory_transaction_id IS NULL;

CREATE OR REPLACE VIEW public.vw_inventory_valuation_reconciliation
WITH (security_invoker = true)
AS
SELECT
  sb.company_id,
  sb.warehouse_id,
  sb.item_id,
  public.fn_item_costing_method(sb.item_id) AS costing_method,
  sb.qty_on_hand,
  sb.total_cost AS stock_balance_value,
  COALESCE(layer_totals.layer_qty, 0) AS active_layer_qty,
  COALESCE(layer_totals.layer_value, 0) AS active_layer_value,
  CASE WHEN public.fn_item_costing_method(sb.item_id) = 'weighted_average'
       THEN 0 ELSE sb.qty_on_hand - COALESCE(layer_totals.layer_qty, 0) END AS quantity_variance,
  CASE WHEN public.fn_item_costing_method(sb.item_id) = 'weighted_average'
       THEN 0 ELSE sb.total_cost - COALESCE(layer_totals.layer_value, 0) END AS value_variance
FROM public.stock_balances sb
LEFT JOIN LATERAL (
  SELECT SUM(l.qty_remaining) AS layer_qty,
         SUM(l.remaining_value) AS layer_value
  FROM public.inventory_cost_layers l
  WHERE l.company_id = sb.company_id
    AND l.warehouse_id = sb.warehouse_id
    AND l.item_id = sb.item_id
    AND l.voided_by_inventory_transaction_id IS NULL
) layer_totals ON true;

GRANT SELECT ON public.vw_available_inventory_identities TO authenticated, service_role;
GRANT SELECT ON public.vw_inventory_valuation_reconciliation TO authenticated, service_role;

-- Return stock at the immutable cost of the original outbound event. Layered
-- methods restore the exact historical allocations; WAC restores the frozen
-- outbound value into the current pool and recomputes the pool average.
CREATE OR REPLACE FUNCTION public.fn_return_inventory(p_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original     inventory_transactions%ROWTYPE;
  v_company_id   UUID := NULLIF(p_data->>'company_id','')::UUID;
  v_warehouse_id UUID := NULLIF(p_data->>'warehouse_id','')::UUID;
  v_item_id      UUID := NULLIF(p_data->>'item_id','')::UUID;
  v_original_id  UUID := NULLIF(p_data->>'original_inventory_transaction_id','')::UUID;
  v_source_line  UUID := NULLIF(p_data->>'source_line_id','')::UUID;
  v_ref_id       UUID := NULLIF(p_data->>'reference_doc_id','')::UUID;
  v_journal_id   UUID := NULLIF(p_data->>'journal_entry_id','')::UUID;
  v_qty          NUMERIC := NULLIF(p_data->>'qty','')::NUMERIC;
  v_date         DATE := COALESCE(NULLIF(p_data->>'transaction_date','')::DATE, CURRENT_DATE);
  v_prior_qty    NUMERIC;
  v_prior_value  NUMERIC;
  v_remaining    NUMERIC;
  v_available    NUMERIC;
  v_take         NUMERIC;
  v_take_value   NUMERIC(18,2);
  v_total        NUMERIC(18,2) := 0;
  v_tx_id        UUID;
  v_alloc        RECORD;
  v_allocs       JSONB := '[]'::JSONB;
BEGIN
  IF v_company_id IS NULL OR NOT public.is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;
  IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'Return quantity must be positive'; END IF;

  SELECT * INTO v_original
  FROM public.inventory_transactions
  WHERE id = v_original_id
  FOR UPDATE;
  IF NOT FOUND OR v_original.company_id <> v_company_id
     OR v_original.warehouse_id <> v_warehouse_id OR v_original.item_id <> v_item_id
     OR v_original.qty >= 0 THEN
    RAISE EXCEPTION 'Original outbound inventory evidence does not match this return'
      USING ERRCODE = '23514';
  END IF;
  IF v_original.reversed_by_inventory_transaction_id IS NOT NULL THEN
    RAISE EXCEPTION 'The original outbound inventory transaction is already reversed'
      USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(SUM(it.qty),0), COALESCE(SUM(it.total_cost),0)
  INTO v_prior_qty, v_prior_value
  FROM public.inventory_transactions it
  WHERE it.restores_inventory_transaction_id = v_original.id
    AND it.qty > 0 AND it.reversed_by_inventory_transaction_id IS NULL;
  IF v_prior_qty + v_qty > ABS(v_original.qty) THEN
    RAISE EXCEPTION 'Return quantity % exceeds the unreturned quantity % from the original issue',
      v_qty, ABS(v_original.qty) - v_prior_qty USING ERRCODE = '23514';
  END IF;

  PERFORM public.fn_ensure_stock_balance(v_company_id, v_warehouse_id, v_item_id);
  PERFORM 1 FROM public.stock_balances
  WHERE company_id=v_company_id AND warehouse_id=v_warehouse_id AND item_id=v_item_id
  FOR UPDATE;

  IF v_original.costing_method = 'weighted_average' THEN
    v_total := CASE WHEN v_prior_qty + v_qty = ABS(v_original.qty)
      THEN ABS(v_original.total_cost) - v_prior_value
      ELSE ROUND(v_qty * ABS(v_original.total_cost) / ABS(v_original.qty), 2) END;
  ELSE
    v_remaining := v_qty;
    FOR v_alloc IN
      SELECT a.*,
        a.quantity - COALESCE((
          SELECT SUM(ra.quantity)
          FROM public.inventory_layer_allocations ra
          JOIN public.inventory_transactions rit ON rit.id=ra.inventory_transaction_id
          WHERE rit.restores_inventory_transaction_id=v_original.id
            AND rit.reversed_by_inventory_transaction_id IS NULL
            AND ra.allocation_kind='return' AND ra.layer_id=a.layer_id
        ),0) AS returnable_qty,
        a.total_cost - COALESCE((
          SELECT SUM(ra.total_cost)
          FROM public.inventory_layer_allocations ra
          JOIN public.inventory_transactions rit ON rit.id=ra.inventory_transaction_id
          WHERE rit.restores_inventory_transaction_id=v_original.id
            AND rit.reversed_by_inventory_transaction_id IS NULL
            AND ra.allocation_kind='return' AND ra.layer_id=a.layer_id
        ),0) AS returnable_value
      FROM public.inventory_layer_allocations a
      JOIN public.inventory_cost_layers source_layer ON source_layer.id=a.layer_id
      WHERE a.inventory_transaction_id=v_original.id AND a.allocation_kind='consume'
      ORDER BY source_layer.layer_date,source_layer.created_at,source_layer.id
    LOOP
      EXIT WHEN v_remaining=0;
      v_available := GREATEST(v_alloc.returnable_qty,0);
      CONTINUE WHEN v_available=0;
      v_take := LEAST(v_available,v_remaining);
      v_take_value := CASE WHEN v_take=v_available THEN v_alloc.returnable_value
        ELSE ROUND(v_take*v_alloc.returnable_value/v_available,2) END;
      UPDATE public.inventory_cost_layers
      SET qty_remaining=qty_remaining+v_take,
          remaining_value=remaining_value+v_take_value,
          is_exhausted=false
      WHERE id=v_alloc.layer_id;
      v_allocs := v_allocs || jsonb_build_array(jsonb_build_object(
        'layer_id',v_alloc.layer_id,'quantity',v_take,
        'unit_cost',ROUND(v_take_value/v_take,6),'total_cost',v_take_value));
      v_total := v_total+v_take_value;
      v_remaining := v_remaining-v_take;
    END LOOP;
    IF v_remaining>0 THEN
      RAISE EXCEPTION 'Original layered issue lacks enough unreturned allocation evidence; short by %',v_remaining
        USING ERRCODE='23514';
    END IF;
  END IF;

  UPDATE public.stock_balances
  SET qty_on_hand=qty_on_hand+v_qty,
      total_cost=total_cost+v_total,
      wac_unit_cost=CASE WHEN v_original.costing_method='weighted_average'
        THEN ROUND((total_cost+v_total)/(qty_on_hand+v_qty),6) ELSE wac_unit_cost END,
      last_receipt_date=v_date, updated_at=now()
  WHERE company_id=v_company_id AND warehouse_id=v_warehouse_id AND item_id=v_item_id;

  INSERT INTO public.inventory_transactions(
    company_id,warehouse_id,item_id,transaction_type,transaction_date,
    qty,unit_cost,total_cost,qty_on_hand_after,costing_method,
    reference_doc_type,reference_doc_id,source_line_id,journal_entry_id,
    lot_number,serial_number,notes,created_by,restores_inventory_transaction_id
  )
  SELECT v_company_id,v_warehouse_id,v_item_id,'receipt',v_date,
    v_qty,ROUND(v_total/v_qty,6),v_total,sb.qty_on_hand,v_original.costing_method,
    COALESCE(NULLIF(p_data->>'reference_doc_type',''),'CM'),v_ref_id,v_source_line,v_journal_id,
    v_original.lot_number,v_original.serial_number,p_data->>'notes',auth.uid(),v_original.id
  FROM public.stock_balances sb
  WHERE sb.company_id=v_company_id AND sb.warehouse_id=v_warehouse_id AND sb.item_id=v_item_id
  RETURNING id INTO v_tx_id;

  INSERT INTO public.inventory_layer_allocations(
    company_id,inventory_transaction_id,layer_id,allocation_kind,quantity,unit_cost,total_cost
  )
  SELECT v_company_id,v_tx_id,(a->>'layer_id')::UUID,'return',
    (a->>'quantity')::NUMERIC,(a->>'unit_cost')::NUMERIC,(a->>'total_cost')::NUMERIC
  FROM jsonb_array_elements(v_allocs) a;

  RETURN jsonb_build_object(
    'inventory_transaction_id',v_tx_id,'costing_method',v_original.costing_method,
    'unit_cost',ROUND(v_total/v_qty,6),'total_cost',v_total,
    'lot_number',v_original.lot_number,'serial_number',v_original.serial_number);
END;
$$;

-- A warehouse transfer is one atomic value-preserving movement. FIFO creates
-- destination layers per consumed source allocation and retains parent lineage;
-- Specific ID moves the same serial/lot; WAC moves the frozen source-pool cost.
CREATE OR REPLACE FUNCTION public.fn_transfer_inventory(p_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID := NULLIF(p_data->>'company_id','')::UUID;
  v_from UUID := NULLIF(p_data->>'from_warehouse_id','')::UUID;
  v_to UUID := NULLIF(p_data->>'to_warehouse_id','')::UUID;
  v_item UUID := NULLIF(p_data->>'item_id','')::UUID;
  v_qty NUMERIC := NULLIF(p_data->>'qty','')::NUMERIC;
  v_date DATE := COALESCE(NULLIF(p_data->>'transaction_date','')::DATE,CURRENT_DATE);
  v_source_line UUID := NULLIF(p_data->>'source_line_id','')::UUID;
  v_out JSONB;
  v_out_id UUID;
  v_in_id UUID;
  v_method TEXT;
  v_total NUMERIC(18,2);
  v_layer RECORD;
  v_new_layer UUID;
BEGIN
  IF v_from=v_to THEN RAISE EXCEPTION 'Source and destination warehouses must differ'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.warehouses WHERE id=v_to AND company_id=v_company_id) THEN
    RAISE EXCEPTION 'Destination warehouse does not belong to the company';
  END IF;

  v_out := public.fn_issue_inventory(jsonb_build_object(
    'company_id',v_company_id,'warehouse_id',v_from,'item_id',v_item,'qty',v_qty,
    'transaction_date',v_date,'transaction_type','transfer_out',
    'reference_doc_type',COALESCE(NULLIF(p_data->>'reference_doc_type',''),'STX'),
    'reference_doc_id',NULLIF(p_data->>'reference_doc_id','')::UUID,
    'source_line_id',v_source_line,
    'inventory_cost_layer_id',NULLIF(p_data->>'inventory_cost_layer_id','')::UUID,
    'lot_number',NULLIF(p_data->>'lot_number',''),
    'serial_number',NULLIF(p_data->>'serial_number',''),
    'notes',p_data->>'notes'));
  v_out_id := (v_out->>'inventory_transaction_id')::UUID;
  v_method := v_out->>'costing_method';
  v_total := (v_out->>'total_cost')::NUMERIC;

  PERFORM public.fn_ensure_stock_balance(v_company_id,v_to,v_item);
  PERFORM 1 FROM public.stock_balances
  WHERE company_id=v_company_id AND warehouse_id=v_to AND item_id=v_item FOR UPDATE;
  UPDATE public.stock_balances
  SET qty_on_hand=qty_on_hand+v_qty,total_cost=total_cost+v_total,
      wac_unit_cost=CASE WHEN v_method='weighted_average'
        THEN ROUND((total_cost+v_total)/(qty_on_hand+v_qty),6) ELSE wac_unit_cost END,
      last_receipt_date=v_date,updated_at=now()
  WHERE company_id=v_company_id AND warehouse_id=v_to AND item_id=v_item;

  INSERT INTO public.inventory_transactions(
    company_id,warehouse_id,item_id,transaction_type,transaction_date,
    qty,unit_cost,total_cost,qty_on_hand_after,costing_method,
    reference_doc_type,reference_doc_id,source_line_id,lot_number,serial_number,notes,created_by
  )
  SELECT v_company_id,v_to,v_item,'transfer_in',v_date,v_qty,ROUND(v_total/v_qty,6),v_total,
    sb.qty_on_hand,v_method,COALESCE(NULLIF(p_data->>'reference_doc_type',''),'STX'),
    NULLIF(p_data->>'reference_doc_id','')::UUID,v_source_line,
    v_out->>'lot_number',v_out->>'serial_number',p_data->>'notes',auth.uid()
  FROM public.stock_balances sb
  WHERE sb.company_id=v_company_id AND sb.warehouse_id=v_to AND sb.item_id=v_item
  RETURNING id INTO v_in_id;

  IF v_method IN ('fifo','specific_identification') THEN
    FOR v_layer IN
      SELECT a.*,l.lot_number,l.serial_number
      FROM public.inventory_layer_allocations a
      JOIN public.inventory_cost_layers l ON l.id=a.layer_id
      WHERE a.inventory_transaction_id=v_out_id AND a.allocation_kind='consume'
      ORDER BY a.id
    LOOP
      INSERT INTO public.inventory_cost_layers(
        company_id,warehouse_id,item_id,layer_date,reference_doc_type,reference_doc_id,
        source_line_id,lot_number,serial_number,original_qty,qty_remaining,unit_cost,
        original_value,remaining_value,is_exhausted,origin_inventory_transaction_id,parent_layer_id
      ) VALUES (
        v_company_id,v_to,v_item,v_date,COALESCE(NULLIF(p_data->>'reference_doc_type',''),'STX'),
        NULLIF(p_data->>'reference_doc_id','')::UUID,v_source_line,v_layer.lot_number,v_layer.serial_number,
        v_layer.quantity,v_layer.quantity,v_layer.unit_cost,v_layer.total_cost,v_layer.total_cost,false,
        v_in_id,v_layer.layer_id
      ) RETURNING id INTO v_new_layer;
      INSERT INTO public.inventory_layer_allocations(
        company_id,inventory_transaction_id,layer_id,allocation_kind,quantity,unit_cost,total_cost
      ) VALUES (v_company_id,v_in_id,v_new_layer,'transfer_in',v_layer.quantity,v_layer.unit_cost,v_layer.total_cost);
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'source_inventory_transaction_id',v_out_id,
    'destination_inventory_transaction_id',v_in_id,
    'costing_method',v_method,'unit_cost',ROUND(v_total/v_qty,6),'total_cost',v_total);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_return_inventory(JSONB) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.fn_transfer_inventory(JSONB) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_return_inventory(JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_transfer_inventory(JSONB) TO service_role;

-- ── Existing writer implementations, now routed through shared authority ───
CREATE OR REPLACE FUNCTION public.fn_post_goods_issue_source_locked_impl(p_issue_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gi goods_issues%ROWTYPE;
  v_line goods_issue_lines%ROWTYPE;
  v_item items%ROWTYPE;
  v_fp_id UUID;
  v_je_id UUID;
  v_line_no INTEGER := 1;
  v_je_total NUMERIC(18,2) := 0;
  v_cost JSONB;
  v_tx_id UUID;
  v_total NUMERIC(18,2);
BEGIN
  SELECT * INTO v_gi FROM public.goods_issues WHERE id=p_issue_id;
  IF NOT FOUND OR NOT public.is_company_member(v_gi.company_id) THEN
    RAISE EXCEPTION 'Goods issue not found or access denied';
  END IF;
  IF v_gi.status<>'draft' THEN RAISE EXCEPTION 'Only draft goods issues can be posted (current: %)',v_gi.status; END IF;
  SELECT id INTO v_fp_id FROM public.fiscal_periods
  WHERE company_id=v_gi.company_id AND start_date<=v_gi.issue_date
    AND end_date>=v_gi.issue_date AND is_locked=false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %',v_gi.issue_date; END IF;

  v_je_id := public.fn_create_posted_journal_entry(
    v_gi.company_id,v_gi.branch_id,
    public.fn_next_document_number(v_gi.company_id,v_gi.branch_id,'JE'),
    v_gi.issue_date,'Goods Issue: '||v_gi.issue_number||COALESCE(' — '||v_gi.purpose,''),
    'INV_GI',p_issue_id,v_fp_id,'posted',0,0,NULL,'regular',false,false,false);

  FOR v_line IN SELECT * FROM public.goods_issue_lines WHERE issue_id=p_issue_id ORDER BY id LOOP
    SELECT * INTO v_item FROM public.items
    WHERE id=v_line.item_id AND company_id=v_gi.company_id AND item_type='inventory_item';
    IF NOT FOUND THEN RAISE EXCEPTION 'Goods issue line item is not an inventory item in this company'; END IF;
    IF v_item.inventory_account_id IS NULL OR COALESCE(v_line.gl_expense_account_id,v_item.cogs_account_id) IS NULL THEN
      RAISE EXCEPTION 'Inventory and expense accounts are required for goods issue item %',v_item.item_code;
    END IF;

    v_cost := public.fn_issue_inventory(jsonb_build_object(
      'company_id',v_gi.company_id,'warehouse_id',v_gi.warehouse_id,
      'item_id',v_line.item_id,'qty',v_line.qty_issued,
      'transaction_date',v_gi.issue_date,'transaction_type','issue',
      'reference_doc_type','INV_GI','reference_doc_id',p_issue_id,
      'source_line_id',v_line.id,'journal_entry_id',v_je_id,
      'inventory_cost_layer_id',v_line.inventory_cost_layer_id,
      'lot_number',v_line.lot_number,'serial_number',v_line.serial_number,
      'project_id',v_gi.project_id,'location_id',v_gi.location_id,
      'functional_entity_id',v_gi.functional_entity_id,
      'notes','Goods issue '||v_gi.issue_number));
    v_tx_id := (v_cost->>'inventory_transaction_id')::UUID;
    v_total := (v_cost->>'total_cost')::NUMERIC;

    UPDATE public.goods_issue_lines
    SET unit_cost=(v_cost->>'unit_cost')::NUMERIC,total_cost=v_total,
        inventory_transaction_id=v_tx_id,
        lot_number=COALESCE(v_cost->>'lot_number',lot_number),
        serial_number=COALESCE(v_cost->>'serial_number',serial_number)
    WHERE id=v_line.id;

    PERFORM public.fn_add_posting_line_push(
      v_je_id,v_line_no,COALESCE(v_line.gl_expense_account_id,v_item.cogs_account_id),
      'Goods issue — '||v_item.description,v_total,0,NULL,NULL,NULL,
      v_gi.department_id,v_gi.cost_center_id,v_gi.project_id,v_gi.location_id,v_gi.functional_entity_id);
    PERFORM public.fn_add_posting_line_push(
      v_je_id,v_line_no+1,v_item.inventory_account_id,
      'Goods issue — '||v_item.description,0,v_total,NULL,NULL,NULL,
      v_gi.department_id,v_gi.cost_center_id,v_gi.project_id,v_gi.location_id,v_gi.functional_entity_id);
    v_line_no:=v_line_no+2;
    v_je_total:=v_je_total+v_total;
  END LOOP;

  PERFORM public.fn_finalize_journal_entry(v_je_id,v_je_total,v_je_total,true);
  UPDATE public.goods_issues SET status='posted',journal_entry_id=v_je_id,
    fiscal_period_id=v_fp_id,posted_at=now(),posted_by=auth.uid(),
    updated_at=now(),updated_by=auth.uid() WHERE id=p_issue_id;
  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_post_stock_adjustment_source_locked_impl(p_adjustment_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_adj stock_adjustments%ROWTYPE;
  v_line stock_adjustment_lines%ROWTYPE;
  v_item items%ROWTYPE;
  v_sb stock_balances%ROWTYPE;
  v_fp_id UUID;
  v_je_id UUID;
  v_line_no INTEGER:=1;
  v_cost JSONB;
  v_tx_id UUID;
  v_uc NUMERIC(18,6);
  v_value NUMERIC(18,2);
  v_signed NUMERIC(18,2);
  v_total NUMERIC(18,2):=0;
BEGIN
  SELECT * INTO v_adj FROM public.stock_adjustments WHERE id=p_adjustment_id;
  IF NOT FOUND OR NOT public.is_company_member(v_adj.company_id) THEN
    RAISE EXCEPTION 'Stock adjustment not found or access denied';
  END IF;
  IF v_adj.status<>'draft' THEN RAISE EXCEPTION 'Only draft stock adjustments can be posted (current: %)',v_adj.status; END IF;
  SELECT id INTO v_fp_id FROM public.fiscal_periods
  WHERE company_id=v_adj.company_id AND start_date<=v_adj.adjustment_date
    AND end_date>=v_adj.adjustment_date AND is_locked=false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %',v_adj.adjustment_date; END IF;

  FOR v_line IN SELECT * FROM public.stock_adjustment_lines WHERE adjustment_id=p_adjustment_id ORDER BY id LOOP
    CONTINUE WHEN v_line.qty_adjusted=0;
    SELECT * INTO v_item FROM public.items
    WHERE id=v_line.item_id AND company_id=v_adj.company_id AND item_type='inventory_item';
    IF NOT FOUND THEN RAISE EXCEPTION 'Adjustment line item is not inventory in this company'; END IF;
    IF v_item.inventory_account_id IS NULL OR v_line.gl_offset_account_id IS NULL THEN
      RAISE EXCEPTION 'Inventory and offset accounts are required for adjustment item %',v_item.item_code;
    END IF;
    v_sb:=public.fn_ensure_stock_balance(v_adj.company_id,v_adj.warehouse_id,v_line.item_id);

    IF v_line.qty_adjusted>0 THEN
      v_uc:=COALESCE(NULLIF(v_line.unit_cost,0),NULLIF(v_sb.wac_unit_cost,0),v_item.standard_cost,0);
      v_tx_id:=public.fn_receive_inventory(jsonb_build_object(
        'company_id',v_adj.company_id,'warehouse_id',v_adj.warehouse_id,
        'item_id',v_line.item_id,'qty',v_line.qty_adjusted,'unit_cost',v_uc,
        'receipt_date',v_adj.adjustment_date,'reference_doc_type','ADJ',
        'reference_doc_id',p_adjustment_id,'source_line_id',v_line.id,
        'lot_number',v_line.lot_number,'serial_number',v_line.serial_number,
        'notes','Stock adjustment '||v_adj.adjustment_number));
      SELECT unit_cost,total_cost INTO v_uc,v_value FROM public.inventory_transactions WHERE id=v_tx_id;
      v_signed:=v_value;
    ELSE
      v_cost:=public.fn_issue_inventory(jsonb_build_object(
        'company_id',v_adj.company_id,'warehouse_id',v_adj.warehouse_id,
        'item_id',v_line.item_id,'qty',ABS(v_line.qty_adjusted),
        'transaction_date',v_adj.adjustment_date,'transaction_type','adjustment_out',
        'reference_doc_type','ADJ','reference_doc_id',p_adjustment_id,
        'source_line_id',v_line.id,'inventory_cost_layer_id',v_line.inventory_cost_layer_id,
        'lot_number',v_line.lot_number,'serial_number',v_line.serial_number,
        'notes','Stock adjustment '||v_adj.adjustment_number));
      v_tx_id:=(v_cost->>'inventory_transaction_id')::UUID;
      v_uc:=(v_cost->>'unit_cost')::NUMERIC;
      v_value:=(v_cost->>'total_cost')::NUMERIC;
      v_signed:=-v_value;
    END IF;
    UPDATE public.stock_adjustment_lines
    SET unit_cost=v_uc,total_cost_impact=v_signed,inventory_transaction_id=v_tx_id,
        lot_number=COALESCE((SELECT lot_number FROM public.inventory_transactions WHERE id=v_tx_id),lot_number),
        serial_number=COALESCE((SELECT serial_number FROM public.inventory_transactions WHERE id=v_tx_id),serial_number)
    WHERE id=v_line.id;
    v_total:=v_total+ABS(v_signed);
  END LOOP;

  IF v_total>0 THEN
    v_je_id:=public.fn_create_posted_journal_entry(
      v_adj.company_id,v_adj.branch_id,
      public.fn_next_document_number(v_adj.company_id,v_adj.branch_id,'JE'),
      v_adj.adjustment_date,'Stock Adjustment: '||v_adj.adjustment_number||' ('||v_adj.reason||')',
      'INV_ADJ',p_adjustment_id,v_fp_id,'posted',v_total,v_total,NULL,'regular',false,false,false);
    FOR v_line IN SELECT * FROM public.stock_adjustment_lines
      WHERE adjustment_id=p_adjustment_id AND total_cost_impact<>0 ORDER BY id LOOP
      SELECT * INTO v_item FROM public.items WHERE id=v_line.item_id;
      v_signed:=v_line.total_cost_impact;
      PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_item.inventory_account_id,
        'Inventory adjustment — '||v_item.description,GREATEST(v_signed,0),GREATEST(-v_signed,0));
      PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no+1,v_line.gl_offset_account_id,
        'Adjustment offset — '||v_item.description,GREATEST(-v_signed,0),GREATEST(v_signed,0));
      v_line_no:=v_line_no+2;
    END LOOP;
    PERFORM public.fn_finalize_journal_entry(v_je_id,v_total,v_total,true);
    UPDATE public.inventory_transactions it SET journal_entry_id=v_je_id
    FROM public.stock_adjustment_lines sal
    WHERE sal.adjustment_id=p_adjustment_id AND sal.inventory_transaction_id=it.id;
  END IF;
  UPDATE public.stock_adjustments SET status='posted',journal_entry_id=v_je_id,
    fiscal_period_id=v_fp_id,posted_at=now(),posted_by=auth.uid(),updated_at=now(),updated_by=auth.uid()
  WHERE id=p_adjustment_id;
  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_post_physical_count_source_locked_impl(p_sheet_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cs physical_count_sheets%ROWTYPE;
  v_line physical_count_sheet_lines%ROWTYPE;
  v_item items%ROWTYPE;
  v_sb stock_balances%ROWTYPE;
  v_fp_id UUID;
  v_je_id UUID;
  v_line_no INTEGER:=1;
  v_variance NUMERIC;
  v_uc NUMERIC(18,6);
  v_value NUMERIC(18,2);
  v_signed NUMERIC(18,2);
  v_total NUMERIC(18,2):=0;
  v_tx_id UUID;
  v_cost JSONB;
  v_var_acct UUID;
BEGIN
  SELECT * INTO v_cs FROM public.physical_count_sheets WHERE id=p_sheet_id;
  IF NOT FOUND OR NOT public.is_company_member(v_cs.company_id) THEN
    RAISE EXCEPTION 'Physical count sheet not found or access denied';
  END IF;
  IF v_cs.status NOT IN ('draft','counting','variance_review') THEN
    RAISE EXCEPTION 'Physical count cannot be posted in status %',v_cs.status;
  END IF;
  SELECT id INTO v_fp_id FROM public.fiscal_periods
  WHERE company_id=v_cs.company_id AND start_date<=v_cs.count_date
    AND end_date>=v_cs.count_date AND is_locked=false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %',v_cs.count_date; END IF;

  FOR v_line IN SELECT * FROM public.physical_count_sheet_lines WHERE count_sheet_id=p_sheet_id ORDER BY id LOOP
    v_variance:=COALESCE(v_line.counted_qty,v_line.system_qty)-v_line.system_qty;
    CONTINUE WHEN v_variance=0;
    SELECT * INTO v_item FROM public.items
    WHERE id=v_line.item_id AND company_id=v_cs.company_id AND item_type='inventory_item';
    IF NOT FOUND THEN RAISE EXCEPTION 'Count line item is not inventory in this company'; END IF;
    v_var_acct:=COALESCE(v_line.gl_variance_account_id,
      (SELECT gl_variance_account_id FROM public.warehouses WHERE id=v_cs.warehouse_id));
    IF v_item.inventory_account_id IS NULL OR v_var_acct IS NULL THEN
      RAISE EXCEPTION 'Inventory and variance accounts are required for count item %',v_item.item_code;
    END IF;
    v_sb:=public.fn_ensure_stock_balance(v_cs.company_id,v_cs.warehouse_id,v_line.item_id);

    IF v_variance>0 THEN
      v_uc:=COALESCE(NULLIF(v_line.unit_cost,0),NULLIF(v_sb.wac_unit_cost,0),v_item.standard_cost,0);
      v_tx_id:=public.fn_receive_inventory(jsonb_build_object(
        'company_id',v_cs.company_id,'warehouse_id',v_cs.warehouse_id,
        'item_id',v_line.item_id,'qty',v_variance,'unit_cost',v_uc,
        'receipt_date',v_cs.count_date,'reference_doc_type','INV_COUNT',
        'reference_doc_id',p_sheet_id,'source_line_id',v_line.id,
        'lot_number',v_line.lot_number,'serial_number',v_line.serial_number,
        'notes','Physical count '||v_cs.count_number));
      SELECT unit_cost,total_cost INTO v_uc,v_value FROM public.inventory_transactions WHERE id=v_tx_id;
      v_signed:=v_value;
    ELSE
      v_cost:=public.fn_issue_inventory(jsonb_build_object(
        'company_id',v_cs.company_id,'warehouse_id',v_cs.warehouse_id,
        'item_id',v_line.item_id,'qty',ABS(v_variance),
        'transaction_date',v_cs.count_date,'transaction_type','count_variance_out',
        'reference_doc_type','INV_COUNT','reference_doc_id',p_sheet_id,
        'source_line_id',v_line.id,'inventory_cost_layer_id',v_line.inventory_cost_layer_id,
        'lot_number',v_line.lot_number,'serial_number',v_line.serial_number,
        'notes','Physical count '||v_cs.count_number));
      v_tx_id:=(v_cost->>'inventory_transaction_id')::UUID;
      v_uc:=(v_cost->>'unit_cost')::NUMERIC;
      v_value:=(v_cost->>'total_cost')::NUMERIC;
      v_signed:=-v_value;
    END IF;
    UPDATE public.physical_count_sheet_lines
    SET unit_cost=v_uc,inventory_transaction_id=v_tx_id,
        lot_number=COALESCE((SELECT lot_number FROM public.inventory_transactions WHERE id=v_tx_id),lot_number),
        serial_number=COALESCE((SELECT serial_number FROM public.inventory_transactions WHERE id=v_tx_id),serial_number)
    WHERE id=v_line.id;
    v_total:=v_total+ABS(v_signed);
  END LOOP;

  IF v_total>0 THEN
    v_je_id:=public.fn_create_posted_journal_entry(
      v_cs.company_id,v_cs.branch_id,
      public.fn_next_document_number(v_cs.company_id,v_cs.branch_id,'JE'),
      v_cs.count_date,'Physical Count Variance: '||v_cs.count_number,
      'INV_COUNT',p_sheet_id,v_fp_id,'posted',v_total,v_total,NULL,'regular',false,false,false);
    FOR v_line IN SELECT * FROM public.physical_count_sheet_lines
      WHERE count_sheet_id=p_sheet_id AND COALESCE(counted_qty,system_qty)<>system_qty ORDER BY id LOOP
      SELECT * INTO v_item FROM public.items WHERE id=v_line.item_id;
      SELECT total_cost INTO v_signed FROM public.inventory_transactions WHERE id=v_line.inventory_transaction_id;
      v_var_acct:=COALESCE(v_line.gl_variance_account_id,
        (SELECT gl_variance_account_id FROM public.warehouses WHERE id=v_cs.warehouse_id));
      PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_item.inventory_account_id,
        'Count variance — '||v_item.description,GREATEST(v_signed,0),GREATEST(-v_signed,0));
      PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no+1,v_var_acct,
        'Count variance — '||v_item.description,GREATEST(-v_signed,0),GREATEST(v_signed,0));
      v_line_no:=v_line_no+2;
    END LOOP;
    PERFORM public.fn_finalize_journal_entry(v_je_id,v_total,v_total,true);
    UPDATE public.inventory_transactions it SET journal_entry_id=v_je_id
    FROM public.physical_count_sheet_lines pcsl
    WHERE pcsl.count_sheet_id=p_sheet_id AND pcsl.inventory_transaction_id=it.id;
  END IF;
  UPDATE public.physical_count_sheets SET status='posted',journal_entry_id=v_je_id,
    fiscal_period_id=v_fp_id,posted_at=now(),posted_by=auth.uid(),updated_at=now(),updated_by=auth.uid()
  WHERE id=p_sheet_id;
  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_post_stock_transfer_source_locked_impl(p_transfer_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx stock_transfers%ROWTYPE;
  v_line stock_transfer_lines%ROWTYPE;
  v_item items%ROWTYPE;
  v_from_wh warehouses%ROWTYPE;
  v_to_wh warehouses%ROWTYPE;
  v_fp_id UUID;
  v_je_id UUID;
  v_move JSONB;
  v_value NUMERIC(18,2);
  v_total NUMERIC(18,2):=0;
BEGIN
  SELECT * INTO v_tx FROM public.stock_transfers WHERE id=p_transfer_id;
  IF NOT FOUND OR NOT public.is_company_member(v_tx.company_id) THEN
    RAISE EXCEPTION 'Stock transfer not found or access denied';
  END IF;
  IF v_tx.status<>'draft' THEN RAISE EXCEPTION 'Only draft transfers can be posted (current: %)',v_tx.status; END IF;
  SELECT * INTO v_from_wh FROM public.warehouses WHERE id=v_tx.from_warehouse_id AND company_id=v_tx.company_id;
  SELECT * INTO v_to_wh FROM public.warehouses WHERE id=v_tx.to_warehouse_id AND company_id=v_tx.company_id;
  IF v_from_wh.id IS NULL OR v_to_wh.id IS NULL THEN RAISE EXCEPTION 'Transfer warehouse does not belong to the company'; END IF;
  SELECT id INTO v_fp_id FROM public.fiscal_periods
  WHERE company_id=v_tx.company_id AND start_date<=v_tx.transfer_date
    AND end_date>=v_tx.transfer_date AND is_locked=false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for date %',v_tx.transfer_date; END IF;

  FOR v_line IN SELECT * FROM public.stock_transfer_lines WHERE transfer_id=p_transfer_id ORDER BY id LOOP
    SELECT * INTO v_item FROM public.items
    WHERE id=v_line.item_id AND company_id=v_tx.company_id AND item_type='inventory_item';
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer line item is not inventory in this company'; END IF;
    v_move:=public.fn_transfer_inventory(jsonb_build_object(
      'company_id',v_tx.company_id,'from_warehouse_id',v_tx.from_warehouse_id,
      'to_warehouse_id',v_tx.to_warehouse_id,'item_id',v_line.item_id,
      'qty',v_line.qty_transferred,'transaction_date',v_tx.transfer_date,
      'reference_doc_type','STX','reference_doc_id',p_transfer_id,
      'source_line_id',v_line.id,'inventory_cost_layer_id',v_line.inventory_cost_layer_id,
      'lot_number',v_line.lot_number,'serial_number',v_line.serial_number,
      'notes','Stock transfer '||v_tx.transfer_number));
    v_value:=(v_move->>'total_cost')::NUMERIC;
    UPDATE public.stock_transfer_lines SET
      unit_cost=(v_move->>'unit_cost')::NUMERIC,total_cost=v_value,
      source_inventory_transaction_id=(v_move->>'source_inventory_transaction_id')::UUID,
      destination_inventory_transaction_id=(v_move->>'destination_inventory_transaction_id')::UUID,
      lot_number=COALESCE((SELECT lot_number FROM public.inventory_transactions
        WHERE id=(v_move->>'source_inventory_transaction_id')::UUID),lot_number),
      serial_number=COALESCE((SELECT serial_number FROM public.inventory_transactions
        WHERE id=(v_move->>'source_inventory_transaction_id')::UUID),serial_number)
    WHERE id=v_line.id;
    v_total:=v_total+v_value;
  END LOOP;

  IF v_total>0 AND v_from_wh.gl_inventory_account_id IS DISTINCT FROM v_to_wh.gl_inventory_account_id THEN
    IF v_from_wh.gl_inventory_account_id IS NULL OR v_to_wh.gl_inventory_account_id IS NULL THEN
      RAISE EXCEPTION 'Both warehouse inventory accounts are required when transfer accounting differs';
    END IF;
    IF v_from_wh.branch_id IS NULL THEN
      RAISE EXCEPTION 'Source warehouse % has no branch for transfer journal numbering',v_from_wh.warehouse_code;
    END IF;
    v_je_id:=public.fn_create_posted_journal_entry(
      v_tx.company_id,NULL,public.fn_next_document_number(v_tx.company_id,v_from_wh.branch_id,'JE'),
      v_tx.transfer_date,'Stock Transfer: '||v_tx.transfer_number,'INV_STX',p_transfer_id,
      v_fp_id,'posted',v_total,v_total,NULL,'regular',false,false,false);
    PERFORM public.fn_add_posting_line_push(v_je_id,1,v_to_wh.gl_inventory_account_id,'Transfer in',v_total,0);
    PERFORM public.fn_add_posting_line_push(v_je_id,2,v_from_wh.gl_inventory_account_id,'Transfer out',0,v_total);
    PERFORM public.fn_finalize_journal_entry(v_je_id,v_total,v_total,true);
    UPDATE public.inventory_transactions it SET journal_entry_id=v_je_id
    FROM public.stock_transfer_lines stl
    WHERE stl.transfer_id=p_transfer_id
      AND it.id IN (stl.source_inventory_transaction_id,stl.destination_inventory_transaction_id);
  END IF;
  UPDATE public.stock_transfers SET status='posted',journal_entry_id=v_je_id,
    fiscal_period_id=v_fp_id,posted_at=now(),posted_by=auth.uid(),updated_at=now(),updated_by=auth.uid()
  WHERE id=p_transfer_id;
  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_save_cash_purchase(
  p_cp_id UUID,p_header JSONB,p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_company UUID:=(p_header->>'company_id')::UUID;
  v_branch UUID:=NULLIF(p_header->>'branch_id','')::UUID;
  v_warehouse UUID:=NULLIF(p_header->>'warehouse_id','')::UUID;
  v_department UUID:=NULLIF(p_header->>'department_id','')::UUID;
  v_cost_center UUID:=NULLIF(p_header->>'cost_center_id','')::UUID;
  v_project UUID:=NULLIF(p_header->>'project_id','')::UUID;
  v_location UUID:=NULLIF(p_header->>'location_id','')::UUID;
  v_functional UUID:=NULLIF(p_header->>'functional_entity_id','')::UUID;
  v_date DATE:=COALESCE(NULLIF(p_header->>'transaction_date','')::DATE,CURRENT_DATE);
BEGIN
  PERFORM public.fn_validate_purchase_dimensions(v_company,v_branch,v_warehouse,v_department,v_cost_center);
  PERFORM public.fn_assert_transaction_dimension('project',v_project,v_company,v_branch,v_date,'Cash Purchase');
  PERFORM public.fn_assert_transaction_dimension('location',v_location,v_company,v_branch,v_date,'Cash Purchase');
  PERFORM public.fn_assert_transaction_dimension('functional_entity',v_functional,v_company,v_branch,v_date,'Cash Purchase');
  v_id:=public.fn_save_cash_purchase_core_20260718(p_cp_id,p_header,p_lines);
  UPDATE public.cash_purchases SET warehouse_id=v_warehouse,department_id=v_department,
    cost_center_id=v_cost_center,project_id=v_project,location_id=v_location,
    functional_entity_id=v_functional,updated_at=now(),updated_by=auth.uid()
  WHERE id=v_id AND company_id=v_company;
  WITH payload AS (
    SELECT ordinality::INTEGER line_number,
      COALESCE(NULLIF(value->>'warehouse_id','')::UUID,v_warehouse) warehouse_id,
      NULLIF(BTRIM(COALESCE(value->>'lot_number','')),'') lot_number,
      NULLIF(BTRIM(COALESCE(value->>'serial_number','')),'') serial_number
    FROM jsonb_array_elements(COALESCE(p_lines,'[]'::JSONB)) WITH ORDINALITY
  )
  UPDATE public.cash_purchase_lines cpl SET warehouse_id=payload.warehouse_id,
    lot_number=payload.lot_number,serial_number=payload.serial_number,updated_at=now(),updated_by=auth.uid()
  FROM payload WHERE cpl.cp_id=v_id AND cpl.line_number=payload.line_number;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_post_cash_purchase(p_cp_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cp cash_purchases%ROWTYPE;
  v_line RECORD;
  v_tx_id UUID;
BEGIN
  SELECT * INTO v_cp FROM public.cash_purchases WHERE id=p_cp_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_company_member(v_cp.company_id) THEN
    RAISE EXCEPTION 'Cash purchase not found or access denied';
  END IF;
  IF v_cp.status<>'draft' THEN
    PERFORM public.fn_post_cash_purchase_core_20260718(p_cp_id);
    RETURN;
  END IF;
  PERFORM public.fn_validate_purchase_dimensions(v_cp.company_id,v_cp.branch_id,v_cp.warehouse_id,
    v_cp.department_id,v_cp.cost_center_id);
  IF EXISTS (
    SELECT 1 FROM public.cash_purchase_lines cpl JOIN public.items i ON i.id=cpl.item_id
    WHERE cpl.cp_id=p_cp_id AND cpl.quantity>0 AND i.item_type='inventory_item'
      AND COALESCE(cpl.warehouse_id,v_cp.warehouse_id) IS NULL
  ) THEN RAISE EXCEPTION 'Warehouse is required to post inventory-item cash purchases'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.cash_purchase_lines cpl JOIN public.items i ON i.id=cpl.item_id
    WHERE cpl.cp_id=p_cp_id AND cpl.quantity>0 AND i.item_type='inventory_item'
      AND (i.inventory_account_id IS NULL OR cpl.expense_account_id IS DISTINCT FROM i.inventory_account_id)
  ) THEN
    RAISE EXCEPTION 'Inventory-item cash purchase lines must use the item inventory control account';
  END IF;

  PERFORM public.fn_post_cash_purchase_core_20260718(p_cp_id);
  SELECT * INTO v_cp FROM public.cash_purchases WHERE id=p_cp_id;
  FOR v_line IN
    SELECT cpl.*,i.item_code FROM public.cash_purchase_lines cpl
    JOIN public.items i ON i.id=cpl.item_id
    WHERE cpl.cp_id=p_cp_id AND cpl.quantity>0 AND i.item_type='inventory_item'
    ORDER BY cpl.line_number
  LOOP
    v_tx_id:=public.fn_receive_inventory(jsonb_build_object(
      'company_id',v_cp.company_id,'warehouse_id',COALESCE(v_line.warehouse_id,v_cp.warehouse_id),
      'item_id',v_line.item_id,'qty',v_line.quantity,
      'unit_cost',ROUND(v_line.net_amount/v_line.quantity,6),
      'receipt_date',v_cp.transaction_date,'reference_doc_type','CP','reference_doc_id',v_cp.id,
      'source_line_id',v_line.id,'journal_entry_id',v_cp.journal_entry_id,
      'lot_number',v_line.lot_number,'serial_number',v_line.serial_number,
      'notes',COALESCE(v_cp.remarks,'Cash Purchase '||v_cp.cp_number)||' line '||v_line.line_number));
    UPDATE public.cash_purchase_lines SET inventory_transaction_id=v_tx_id WHERE id=v_line.id;
  END LOOP;
END;
$$;

ALTER FUNCTION public.fn_save_credit_memo(UUID,JSONB,JSONB,TEXT)
  RENAME TO fn_save_credit_memo_inventory_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_save_credit_memo_inventory_legacy_20260808(UUID,JSONB,JSONB,TEXT)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_save_credit_memo(
  p_cm_id UUID,p_header JSONB,p_lines JSONB,p_next_status TEXT DEFAULT 'draft'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_save_status TEXT:=p_next_status;
  v_current TEXT;
BEGIN
  IF p_next_status='applied' THEN
    IF p_cm_id IS NOT NULL THEN SELECT status INTO v_current FROM public.credit_memos WHERE id=p_cm_id; END IF;
    v_save_status:=CASE WHEN v_current='approved' THEN 'draft' ELSE 'approved' END;
  END IF;
  v_id:=public.fn_save_credit_memo_inventory_legacy_20260808(p_cm_id,p_header,p_lines,v_save_status);
  WITH payload AS (
    SELECT row_number() OVER (ORDER BY ordinality)::INTEGER line_number,
      NULLIF(value->>'inventory_cost_layer_id','')::UUID inventory_cost_layer_id,
      NULLIF(BTRIM(COALESCE(value->>'lot_number','')),'') lot_number,
      NULLIF(BTRIM(COALESCE(value->>'serial_number','')),'') serial_number
    FROM jsonb_array_elements(COALESCE(p_lines,'[]'::JSONB)) WITH ORDINALITY
    WHERE NULLIF(BTRIM(COALESCE(value->>'description','')),'') IS NOT NULL
  )
  UPDATE public.credit_memo_lines cml SET
    inventory_cost_layer_id=payload.inventory_cost_layer_id,
    lot_number=payload.lot_number,serial_number=payload.serial_number,updated_at=now()
  FROM payload WHERE cml.credit_memo_id=v_id AND cml.line_number=payload.line_number;
  IF p_next_status='applied' THEN PERFORM public.fn_post_credit_memo(v_id); END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_post_credit_memo_vat_lump_impl(p_cm_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec credit_memos%ROWTYPE;
  v_ar UUID;
  v_vat UUID;
  v_fp_id UUID;
  v_je_id UUID;
  v_line RECORD;
  v_ret RECORD;
  v_line_no INTEGER:=1;
  v_total_dr NUMERIC(18,2):=0;
  v_total_return NUMERIC(18,2):=0;
  v_cost JSONB;
  v_original_tx UUID;
  v_tx_id UUID;
BEGIN
  SELECT * INTO v_rec FROM public.credit_memos WHERE id=p_cm_id;
  IF NOT FOUND OR NOT public.is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Credit memo not found or access denied';
  END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN RAISE EXCEPTION 'Credit memo cannot post in status %',v_rec.status; END IF;
  v_ar:=public.fn_resolve_posting_account(v_rec.company_id,'AR_TRADE',v_rec.cm_date,
    'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount>0 THEN
    v_vat:=public.fn_resolve_posting_account(v_rec.company_id,'VAT_OUTPUT',v_rec.cm_date,
      'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;
  SELECT id INTO v_fp_id FROM public.fiscal_periods
  WHERE company_id=v_rec.company_id AND start_date<=v_rec.cm_date
    AND end_date>=v_rec.cm_date AND is_locked=false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for CM date %',v_rec.cm_date; END IF;

  -- Restore inventory before opening the journal so its exact historical cost
  -- becomes the accounting amount, not a browser or current-pool estimate.
  FOR v_ret IN
    SELECT cml.*,i.item_code,i.inventory_account_id,i.cogs_account_id,
      COALESCE(sil.inventory_transaction_id,drl.inventory_transaction_id) original_tx
    FROM public.credit_memo_lines cml
    JOIN public.items i ON i.id=cml.item_id
    LEFT JOIN public.sales_invoice_lines sil ON sil.id=cml.invoice_line_id
    LEFT JOIN public.delivery_receipt_lines drl
      ON sil.source_document_type='DR' AND drl.id=sil.source_line_id
    WHERE cml.credit_memo_id=p_cm_id AND i.item_type='inventory_item'
      AND cml.warehouse_id IS NOT NULL AND cml.quantity>0
    ORDER BY cml.line_number
  LOOP
    IF v_ret.original_tx IS NULL THEN
      RAISE EXCEPTION 'Physical return line % has no original outbound inventory evidence',v_ret.line_number
        USING ERRCODE='23514';
    END IF;
    IF v_ret.inventory_account_id IS NULL OR v_ret.cogs_account_id IS NULL THEN
      RAISE EXCEPTION 'Inventory and COGS accounts are required to return item %',v_ret.item_code;
    END IF;
    v_cost:=public.fn_return_inventory(jsonb_build_object(
      'company_id',v_rec.company_id,'warehouse_id',v_ret.warehouse_id,
      'item_id',v_ret.item_id,'qty',v_ret.quantity,'transaction_date',v_rec.cm_date,
      'reference_doc_type','CM','reference_doc_id',v_rec.id,'source_line_id',v_ret.id,
      'original_inventory_transaction_id',v_ret.original_tx,
      'notes','Customer return '||v_rec.cm_number||' line '||v_ret.line_number));
    v_tx_id:=(v_cost->>'inventory_transaction_id')::UUID;
    UPDATE public.credit_memo_lines SET unit_cost=(v_cost->>'unit_cost')::NUMERIC,
      inventory_cost=(v_cost->>'total_cost')::NUMERIC,inventory_transaction_id=v_tx_id,
      lot_number=v_cost->>'lot_number',serial_number=v_cost->>'serial_number',
      inventory_cost_layer_id=(
        SELECT CASE WHEN COUNT(*)=1 THEN MIN(a.layer_id::TEXT)::UUID ELSE NULL END
        FROM public.inventory_layer_allocations a WHERE a.inventory_transaction_id=v_tx_id
      ),updated_at=now()
    WHERE id=v_ret.id;
    v_total_return:=v_total_return+(v_cost->>'total_cost')::NUMERIC;
  END LOOP;

  v_je_id:=public.fn_create_posted_journal_entry(
    v_rec.company_id,v_rec.branch_id,'JE-CM-'||v_rec.cm_number,v_rec.cm_date,
    'Credit Memo '||v_rec.cm_number||' — '||v_rec.customer_name_snapshot,
    'CM',v_rec.id,v_fp_id,'posted',v_rec.total_amount+v_total_return,
    v_rec.total_amount+v_total_return,'system');
  FOR v_line IN
    SELECT revenue_account_id,SUM(net_amount) net_sum,description
    FROM public.credit_memo_lines WHERE credit_memo_id=v_rec.id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id,description
  LOOP
    PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_line.revenue_account_id,
      'Sales return — '||v_line.description,v_line.net_sum,0,'base');
    v_total_dr:=v_total_dr+v_line.net_sum; v_line_no:=v_line_no+1;
  END LOOP;
  IF v_rec.total_vat_amount>0 THEN
    PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_vat,
      'Output VAT reversal — '||v_rec.cm_number,v_rec.total_vat_amount,0,'tax');
    v_total_dr:=v_total_dr+v_rec.total_vat_amount; v_line_no:=v_line_no+1;
  END IF;
  PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_ar,
    'AR — '||v_rec.customer_name_snapshot,0,v_rec.total_amount,'control');
  v_line_no:=v_line_no+1;
  IF ABS(v_rec.total_amount-v_total_dr)>0.02 THEN
    RAISE EXCEPTION 'CM journal entry unbalanced: DR=% CR=%',v_total_dr,v_rec.total_amount;
  END IF;

  FOR v_ret IN
    SELECT cml.*,i.item_code,i.inventory_account_id,i.cogs_account_id
    FROM public.credit_memo_lines cml JOIN public.items i ON i.id=cml.item_id
    WHERE cml.credit_memo_id=p_cm_id AND cml.inventory_transaction_id IS NOT NULL
    ORDER BY cml.line_number
  LOOP
    UPDATE public.inventory_transactions SET journal_entry_id=v_je_id WHERE id=v_ret.inventory_transaction_id;
    IF COALESCE(v_ret.inventory_cost,0)>0 THEN
      PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_ret.inventory_account_id,
        'Inventory returned — '||COALESCE(v_ret.item_code,v_ret.description),v_ret.inventory_cost,0,'base',NULL,v_rec.branch_id);
      v_line_no:=v_line_no+1;
      PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_ret.cogs_account_id,
        'COGS reversal — '||COALESCE(v_ret.item_code,v_ret.description),0,v_ret.inventory_cost,'base',NULL,v_rec.branch_id);
      v_line_no:=v_line_no+1;
    END IF;
  END LOOP;
  PERFORM public.fn_finalize_journal_entry(
    v_je_id,v_rec.total_amount+v_total_return,v_rec.total_amount+v_total_return,true);

  UPDATE public.credit_memos SET status='applied',journal_entry_id=v_je_id,
    posted_at=now(),posted_by=auth.uid(),updated_at=now(),updated_by=auth.uid() WHERE id=p_cm_id;
  IF v_rec.total_vat_amount>0 THEN
    INSERT INTO public.tax_detail_entries(
      company_id,branch_id,source_doc_type,source_doc_id,tax_kind,tax_base,tax_amount,tax_period_id,
      posting_date,document_date,counterparty_id,counterparty_tin,counterparty_name,is_reversal
    ) VALUES (
      v_rec.company_id,v_rec.branch_id,'CM',v_rec.id,'output_vat',-v_rec.total_taxable_amount,
      -v_rec.total_vat_amount,v_fp_id,CURRENT_DATE,v_rec.cm_date,v_rec.customer_id,
      v_rec.customer_tin_snapshot,v_rec.customer_name_snapshot,true);
  END IF;
END;
$$;

-- Exact supplier returns select the still-available layer created by the
-- referenced receipt. FIFO chronology is not substituted for receipt identity.
CREATE OR REPLACE FUNCTION public.fn_issue_inventory_from_layer(p_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID:=NULLIF(p_data->>'company_id','')::UUID;
  v_warehouse UUID:=NULLIF(p_data->>'warehouse_id','')::UUID;
  v_item UUID:=NULLIF(p_data->>'item_id','')::UUID;
  v_layer_id UUID:=NULLIF(p_data->>'inventory_cost_layer_id','')::UUID;
  v_qty NUMERIC:=NULLIF(p_data->>'qty','')::NUMERIC;
  v_method TEXT;
  v_layer inventory_cost_layers%ROWTYPE;
  v_sb stock_balances%ROWTYPE;
  v_value NUMERIC(18,2);
  v_tx_id UUID;
BEGIN
  IF v_company IS NULL OR NOT public.is_company_member(v_company) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_qty IS NULL OR v_qty<=0 THEN RAISE EXCEPTION 'Issue quantity must be positive'; END IF;
  v_method:=public.fn_item_costing_method(v_item);
  IF v_method='weighted_average' THEN RETURN public.fn_issue_inventory(p_data); END IF;
  IF v_layer_id IS NULL THEN RAISE EXCEPTION 'An exact receipt layer is required for this supplier return'; END IF;
  PERFORM public.fn_ensure_stock_balance(v_company,v_warehouse,v_item);
  SELECT * INTO v_sb FROM public.stock_balances
  WHERE company_id=v_company AND warehouse_id=v_warehouse AND item_id=v_item FOR UPDATE;
  SELECT * INTO v_layer FROM public.inventory_cost_layers
  WHERE id=v_layer_id AND company_id=v_company AND warehouse_id=v_warehouse AND item_id=v_item
    AND qty_remaining>0 AND voided_by_inventory_transaction_id IS NULL FOR UPDATE;
  IF NOT FOUND OR v_layer.qty_remaining<v_qty THEN
    RAISE EXCEPTION 'Referenced receipt layer is unavailable or has insufficient unreturned quantity'
      USING ERRCODE='23514';
  END IF;
  IF v_method='specific_identification'
     AND (SELECT specific_id_tracking FROM public.items WHERE id=v_item)='serial'
     AND (v_layer.serial_number IS NULL OR v_qty<>1) THEN
    RAISE EXCEPTION 'Serial-tracked supplier return requires the exact serial and quantity 1'
      USING ERRCODE='23514';
  END IF;
  v_value:=CASE WHEN v_qty=v_layer.qty_remaining THEN v_layer.remaining_value
    ELSE ROUND(v_qty*v_layer.remaining_value/v_layer.qty_remaining,2) END;
  IF v_sb.qty_on_hand<v_qty OR v_sb.total_cost+0.01<v_value THEN
    RAISE EXCEPTION 'Stock quantity or value is insufficient for the exact supplier return'
      USING ERRCODE='23514';
  END IF;
  UPDATE public.inventory_cost_layers SET qty_remaining=qty_remaining-v_qty,
    remaining_value=remaining_value-v_value,is_exhausted=(qty_remaining-v_qty=0)
  WHERE id=v_layer.id;
  UPDATE public.stock_balances SET qty_on_hand=qty_on_hand-v_qty,total_cost=total_cost-v_value,
    last_issue_date=COALESCE(NULLIF(p_data->>'transaction_date','')::DATE,CURRENT_DATE),updated_at=now()
  WHERE company_id=v_company AND warehouse_id=v_warehouse AND item_id=v_item;
  INSERT INTO public.inventory_transactions(
    company_id,warehouse_id,item_id,transaction_type,transaction_date,qty,unit_cost,total_cost,
    qty_on_hand_after,costing_method,reference_doc_type,reference_doc_id,source_line_id,
    journal_entry_id,lot_number,serial_number,notes,created_by
  )
  SELECT v_company,v_warehouse,v_item,'issue',
    COALESCE(NULLIF(p_data->>'transaction_date','')::DATE,CURRENT_DATE),-v_qty,
    ROUND(v_value/v_qty,6),-v_value,sb.qty_on_hand,v_method,
    COALESCE(NULLIF(p_data->>'reference_doc_type',''),'PR'),
    NULLIF(p_data->>'reference_doc_id','')::UUID,NULLIF(p_data->>'source_line_id','')::UUID,
    NULLIF(p_data->>'journal_entry_id','')::UUID,v_layer.lot_number,v_layer.serial_number,
    p_data->>'notes',auth.uid()
  FROM public.stock_balances sb
  WHERE sb.company_id=v_company AND sb.warehouse_id=v_warehouse AND sb.item_id=v_item
  RETURNING id INTO v_tx_id;
  INSERT INTO public.inventory_layer_allocations(
    company_id,inventory_transaction_id,layer_id,allocation_kind,quantity,unit_cost,total_cost
  ) VALUES (v_company,v_tx_id,v_layer.id,'consume',v_qty,ROUND(v_value/v_qty,6),v_value);
  RETURN jsonb_build_object('inventory_transaction_id',v_tx_id,'costing_method',v_method,
    'unit_cost',ROUND(v_value/v_qty,6),'total_cost',v_value,
    'lot_number',v_layer.lot_number,'serial_number',v_layer.serial_number);
END;
$$;
REVOKE ALL ON FUNCTION public.fn_issue_inventory_from_layer(JSONB) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_issue_inventory_from_layer(JSONB) TO service_role;

ALTER FUNCTION public.fn_save_purchase_return(UUID,JSONB,JSONB)
  RENAME TO fn_save_purchase_return_inventory_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_save_purchase_return_inventory_legacy_20260808(UUID,JSONB,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_save_purchase_return(p_return_id UUID,p_header JSONB,p_lines JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  v_id:=public.fn_save_purchase_return_inventory_legacy_20260808(p_return_id,p_header,p_lines);
  WITH payload AS (
    SELECT row_number() OVER (ORDER BY ordinality)::INTEGER line_number,
      NULLIF(value->>'inventory_cost_layer_id','')::UUID inventory_cost_layer_id,
      NULLIF(BTRIM(COALESCE(value->>'lot_number','')),'') lot_number,
      NULLIF(BTRIM(COALESCE(value->>'serial_number','')),'') serial_number
    FROM jsonb_array_elements(COALESCE(p_lines,'[]'::JSONB)) WITH ORDINALITY
    WHERE NULLIF(BTRIM(COALESCE(value->>'description','')),'') IS NOT NULL
  )
  UPDATE public.purchase_return_lines prl SET
    inventory_cost_layer_id=COALESCE(payload.inventory_cost_layer_id,(
      SELECT l.id FROM public.receiving_report_lines rrl
      JOIN public.inventory_cost_layers l ON l.origin_inventory_transaction_id=rrl.inventory_transaction_id
      WHERE rrl.id=prl.rr_line_id ORDER BY l.id LIMIT 1)),
    lot_number=payload.lot_number,serial_number=payload.serial_number,updated_at=now()
  FROM payload WHERE prl.return_id=v_id AND prl.line_number=payload.line_number;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_ship_purchase_return(p_return_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec purchase_returns%ROWTYPE;
  v_line RECORD;
  v_cost JSONB;
  v_prior NUMERIC;
  v_vb_count INTEGER;
BEGIN
  SELECT * INTO v_rec FROM public.purchase_returns WHERE id=p_return_id FOR UPDATE;
  IF NOT FOUND OR NOT public.is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Purchase return not found or access denied'; END IF;
  IF v_rec.status<>'draft' THEN RAISE EXCEPTION 'Only draft returns can be shipped (current: %)',v_rec.status; END IF;
  SELECT COUNT(*) INTO v_vb_count FROM public.vendor_bills vb
  WHERE vb.rr_id=v_rec.rr_id AND vb.company_id=v_rec.company_id
    AND vb.supplier_id=v_rec.supplier_id AND vb.status='posted';
  IF v_vb_count<>1 THEN
    RAISE EXCEPTION 'Purchase return requires exactly one linked posted vendor bill before inventory can ship';
  END IF;

  FOR v_line IN
    SELECT prl.*,rr.warehouse_id,rrl.inventory_transaction_id receipt_tx,
      i.item_type,i.item_code,i.inventory_account_id
    FROM public.purchase_return_lines prl
    JOIN public.receiving_report_lines rrl ON rrl.id=prl.rr_line_id
    JOIN public.receiving_reports rr ON rr.id=rrl.rr_id
    JOIN public.items i ON i.id=prl.item_id
    WHERE prl.return_id=p_return_id AND prl.return_qty>0
    ORDER BY prl.line_number
  LOOP
    SELECT COALESCE(SUM(old.return_qty),0) INTO v_prior
    FROM public.purchase_return_lines old
    JOIN public.purchase_returns oldh ON oldh.id=old.return_id
    WHERE old.rr_line_id=v_line.rr_line_id AND oldh.id<>p_return_id
      AND oldh.status IN ('shipped','completed');
    IF v_prior+v_line.return_qty>v_line.max_qty THEN
      RAISE EXCEPTION 'Supplier return line % exceeds the remaining received quantity',v_line.line_number
        USING ERRCODE='23514';
    END IF;
    IF v_line.item_type<>'inventory_item' THEN CONTINUE; END IF;
    IF v_line.receipt_tx IS NULL OR v_line.warehouse_id IS NULL THEN
      RAISE EXCEPTION 'Supplier return line % has no receipt inventory evidence',v_line.line_number;
    END IF;
    IF v_line.inventory_account_id IS NULL THEN
      RAISE EXCEPTION 'Supplier return inventory line % has no item inventory control account',v_line.line_number;
    END IF;
    v_cost:=public.fn_issue_inventory_from_layer(jsonb_build_object(
      'company_id',v_rec.company_id,'warehouse_id',v_line.warehouse_id,
      'item_id',v_line.item_id,'qty',v_line.return_qty,'transaction_date',v_rec.return_date,
      'reference_doc_type','PR','reference_doc_id',p_return_id,'source_line_id',v_line.id,
      'inventory_cost_layer_id',v_line.inventory_cost_layer_id,
      'lot_number',v_line.lot_number,'serial_number',v_line.serial_number,
      'notes','Purchase return '||v_rec.return_number||' line '||v_line.line_number));
    IF ABS((v_cost->>'total_cost')::NUMERIC-ROUND(v_line.return_qty*v_line.unit_price,2))>0.02 THEN
      RAISE EXCEPTION 'Supplier return line % commercial value % differs from its exact inventory cost %. Use a governed purchase-price-variance workflow.',
        v_line.line_number,ROUND(v_line.return_qty*v_line.unit_price,2),(v_cost->>'total_cost')::NUMERIC
        USING ERRCODE='23514';
    END IF;
    UPDATE public.purchase_return_lines SET
      unit_cost=(v_cost->>'unit_cost')::NUMERIC,inventory_cost=(v_cost->>'total_cost')::NUMERIC,
      inventory_transaction_id=(v_cost->>'inventory_transaction_id')::UUID,
      lot_number=v_cost->>'lot_number',serial_number=v_cost->>'serial_number'
    WHERE id=v_line.id;
  END LOOP;
  UPDATE public.purchase_returns SET status='shipped',updated_at=now(),updated_by=auth.uid()
  WHERE id=p_return_id;
END;
$$;

ALTER FUNCTION public.fn_complete_purchase_return_source_locked_impl(UUID)
  RENAME TO fn_complete_purchase_return_inventory_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_complete_purchase_return_inventory_legacy_20260808(UUID)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_complete_purchase_return_source_locked_impl(p_return_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec purchase_returns%ROWTYPE;
  v_ap UUID;
  v_fp_id UUID;
  v_je_id UUID;
  v_vb_id UUID;
  v_line RECORD;
  v_line_no INTEGER:=1;
  v_total NUMERIC(18,2):=0;
BEGIN
  SELECT * INTO v_rec FROM public.purchase_returns WHERE id=p_return_id;
  IF NOT FOUND OR NOT public.is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Purchase return not found or access denied';
  END IF;
  IF v_rec.status<>'shipped' THEN
    RAISE EXCEPTION 'Only shipped returns can be completed (current: %)',v_rec.status;
  END IF;
  SELECT vb.id INTO v_vb_id FROM public.vendor_bills vb
  WHERE vb.rr_id=v_rec.rr_id AND vb.company_id=v_rec.company_id
    AND vb.supplier_id=v_rec.supplier_id AND vb.status='posted';
  IF v_vb_id IS NULL THEN
    RAISE EXCEPTION 'Purchase return % cannot complete: its receiving report has no linked posted vendor bill',v_rec.return_number;
  END IF;
  v_ap:=public.fn_resolve_posting_account(v_rec.company_id,'AP_TRADE',v_rec.return_date,
    'AP account is not configured for purchase return '||v_rec.return_number);
  SELECT id INTO v_fp_id FROM public.fiscal_periods
  WHERE company_id=v_rec.company_id AND start_date<=v_rec.return_date
    AND end_date>=v_rec.return_date AND is_locked=false LIMIT 1;
  IF v_fp_id IS NULL THEN RAISE EXCEPTION 'No open fiscal period for purchase return date %',v_rec.return_date; END IF;

  SELECT COALESCE(SUM(CASE WHEN i.item_type='inventory_item' THEN prl.inventory_cost
                           ELSE ROUND(prl.return_qty*prl.unit_price,2) END),0)
  INTO v_total
  FROM public.purchase_return_lines prl JOIN public.items i ON i.id=prl.item_id
  WHERE prl.return_id=p_return_id AND prl.return_qty>0;
  IF v_total<=0 THEN RAISE EXCEPTION 'Purchase return has no positive return value'; END IF;

  v_je_id:=public.fn_create_posted_journal_entry(
    v_rec.company_id,v_rec.branch_id,
    public.fn_next_document_number(v_rec.company_id,v_rec.branch_id,'JE'),v_rec.return_date,
    'Purchase Return '||v_rec.return_number||' — '||v_rec.supplier_name_snapshot,
    'PR',v_rec.id,v_fp_id,'posted',v_total,v_total,'system');
  PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_ap,
    'AP reversal — '||v_rec.return_number,v_total,0,'control');
  v_line_no:=v_line_no+1;
  FOR v_line IN
    SELECT prl.*,i.item_type,i.item_code,i.inventory_account_id,
      vbl.expense_account_id bill_account
    FROM public.purchase_return_lines prl
    JOIN public.items i ON i.id=prl.item_id
    LEFT JOIN public.vendor_bill_lines vbl ON vbl.vendor_bill_id=v_vb_id AND vbl.item_id=prl.item_id
    WHERE prl.return_id=p_return_id AND prl.return_qty>0
    ORDER BY prl.line_number
  LOOP
    IF v_line.item_type='inventory_item' THEN
      IF v_line.inventory_transaction_id IS NULL OR v_line.inventory_account_id IS NULL
         OR v_line.inventory_cost IS NULL OR v_line.inventory_cost<=0 THEN
        RAISE EXCEPTION 'Supplier return inventory line % lacks shipped cost evidence or its inventory account',v_line.line_number;
      END IF;
      PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_line.inventory_account_id,
        'Inventory returned — '||COALESCE(v_line.item_code,v_line.description),0,v_line.inventory_cost,'base');
    ELSE
      IF v_line.bill_account IS NULL THEN
        RAISE EXCEPTION 'Supplier return non-inventory line % has no linked bill account',v_line.line_number;
      END IF;
      PERFORM public.fn_add_posting_line_push(v_je_id,v_line_no,v_line.bill_account,
        'Return of: '||v_line.description,0,ROUND(v_line.return_qty*v_line.unit_price,2),'base');
    END IF;
    v_line_no:=v_line_no+1;
  END LOOP;
  PERFORM public.fn_finalize_journal_entry(v_je_id,v_total,v_total,true);
  UPDATE public.inventory_transactions it SET journal_entry_id=v_je_id
  FROM public.purchase_return_lines prl
  WHERE prl.return_id=p_return_id AND prl.inventory_transaction_id=it.id;
  UPDATE public.purchase_returns SET status='completed',journal_entry_id=v_je_id,
    updated_at=now(),updated_by=auth.uid()
  WHERE id=p_return_id;
END;
$$;

ALTER FUNCTION public.fn_save_sales_invoice(UUID,JSONB,JSONB)
  RENAME TO fn_save_sales_invoice_inventory_legacy_20260808;
REVOKE ALL ON FUNCTION public.fn_save_sales_invoice_inventory_legacy_20260808(UUID,JSONB,JSONB)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_save_sales_invoice(p_invoice_id UUID,p_header JSONB,p_lines JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  v_id:=public.fn_save_sales_invoice_inventory_legacy_20260808(p_invoice_id,p_header,p_lines);
  WITH payload AS (
    SELECT ordinality::INTEGER line_number,
      NULLIF(value->>'inventory_cost_layer_id','')::UUID inventory_cost_layer_id,
      NULLIF(BTRIM(COALESCE(value->>'lot_number','')),'') lot_number,
      NULLIF(BTRIM(COALESCE(value->>'serial_number','')),'') serial_number
    FROM jsonb_array_elements(COALESCE(p_lines,'[]'::JSONB)) WITH ORDINALITY
  )
  UPDATE public.sales_invoice_lines sil SET
    inventory_cost_layer_id=payload.inventory_cost_layer_id,
    lot_number=payload.lot_number,serial_number=payload.serial_number,
    updated_at=now(),updated_by=auth.uid()
  FROM payload WHERE sil.sales_invoice_id=v_id AND sil.line_number=payload.line_number;
  RETURN v_id;
END;
$$;

-- Public entrypoints keep their historical browser/service contracts. Source
-- implementations and shared accounting helpers remain private.
REVOKE ALL ON FUNCTION public.fn_save_cash_purchase(UUID,JSONB,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_save_cash_purchase(UUID,JSONB,JSONB) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_post_cash_purchase(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_post_cash_purchase(UUID) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_save_credit_memo(UUID,JSONB,JSONB,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_save_credit_memo(UUID,JSONB,JSONB,TEXT) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_save_purchase_return(UUID,JSONB,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_save_purchase_return(UUID,JSONB,JSONB) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_ship_purchase_return(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_ship_purchase_return(UUID) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_save_sales_invoice(UUID,JSONB,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_save_sales_invoice(UUID,JSONB,JSONB) TO authenticated,service_role;

REVOKE ALL ON FUNCTION public.fn_post_goods_issue_source_locked_impl(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_post_stock_adjustment_source_locked_impl(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_post_physical_count_source_locked_impl(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_post_stock_transfer_source_locked_impl(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_post_credit_memo_vat_lump_impl(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_complete_purchase_return_source_locked_impl(UUID) FROM PUBLIC,anon,authenticated,service_role;
