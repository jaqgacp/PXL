-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P2A (Sales resolver adoption; = COA Engine Phase B, group 1)
--
-- Migrates ONLY the Sales posting writers to consume the certified COA resolver
-- fn_resolve_account (COA Engine, frozen contract). No accounting behavior change:
-- account_mapping is a config-synced projection (COA Phase A), so
-- fn_resolve_account(company, KEY) == the previously-read company_accounting_config
-- account for every configured key — proven equivalence-identical for all canonical
-- companies (25/25) before this migration. Journal output, numbering, tax,
-- dimensions, audit, and validation are preserved byte-for-byte.
--
-- Scope (Sales family only): fn_post_sales_invoice, fn_post_receipt,
-- fn_save_cash_sale, fn_post_credit_memo_vat_lump_impl, fn_post_debit_memo_vat_lump_impl.
-- OUT OF SCOPE (unchanged): Vendor Bill, Cash Purchase, Vendor Credit, inventory,
-- fixed assets, recurring, fiscal close, manual JE, petty cash, banking, purchase
-- return, and every other writer. No Totality Guard, no tax contract, no dimension
-- migration, no subledger reconciliation, no reversal consolidation.
--
-- Metadata (P1): posting_origin='system' is populated on every Sales journal.
-- line_role is populated on the direct-insert Sales writers (CM/DM/cash sale);
-- SI and Receipt line_role is deferred to P3 (push-builder wiring / dimension push).
-- Key→config mapping (COA Phase A): AR_TRADE↔ar_account_id, VAT_OUTPUT↔vat_payable,
-- CASH_DEFAULT↔default_cash, EWT_WITHHELD↔ewt_withheld, CUSTOMER_ADVANCES↔customer_advances.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Resolver adapter: resolve through the COA engine, preserving the writer's
-- friendly "not configured" message on a missing mapping. Non-postable / wrong-type
-- / inactive account errors surface the resolver's precise message unchanged.
CREATE OR REPLACE FUNCTION fn_resolve_posting_account(
  p_company_id UUID,
  p_key TEXT,
  p_as_of DATE,
  p_unconfigured_msg TEXT
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  BEGIN
    v_id := fn_resolve_account(p_company_id, p_key, '{}'::jsonb, p_as_of);
  EXCEPTION WHEN no_data_found THEN
    RAISE EXCEPTION '%', p_unconfigured_msg USING ERRCODE = 'check_violation';
  END;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION fn_resolve_posting_account(UUID, TEXT, DATE, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_resolve_posting_account(UUID, TEXT, DATE, TEXT) TO authenticated, service_role;
COMMENT ON FUNCTION fn_resolve_posting_account(UUID, TEXT, DATE, TEXT) IS
  'Posting Engine P2A: resolve a posting account through the certified COA resolver, re-raising the caller''s friendly "not configured" message on a missing mapping. The single resolution path for migrated writers.';

-- ══════════════════════════════════════════════════════════════════════════════
-- Sales Invoice
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_sales_invoice(p_invoice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_begin JSONB;
  v_rec sales_invoices%ROWTYPE;
  v_ar UUID;
  v_vat UUID;
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

  -- COA resolver adoption (P2A): AR control + Output VAT via fn_resolve_account.
  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-SI-' || v_rec.si_number, v_rec.date,
    'Sales Invoice ' || v_rec.si_number || ' - ' || v_rec.customer_name_snapshot,
    'SI', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;

  PERFORM fn_add_sales_invoice_posting_line(
    v_je_id, 1, v_ar,
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
      v_je_id, v_line_no, v_vat,
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
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Official Receipt / Sales Receipt
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_receipt(p_receipt_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_begin JSONB;
  v_rec receipts%ROWTYPE;
  v_cash_account UUID;
  v_ar UUID;
  v_advance UUID;
  v_cwt UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_ar_credit NUMERIC(15,2);
  v_advance_credit NUMERIC(15,2);
  v_line_no INTEGER := 1;
  v_line RECORD;
BEGIN
  v_begin := fn_begin_source_posting(
    'OR', p_receipt_id, ARRAY['draft'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM receipts WHERE id = p_receipt_id;
  PERFORM fn_validate_receipt_cwt_ready(p_receipt_id);
  PERFORM fn_validate_settlement_posting('OR', p_receipt_id);

  SELECT
    COALESCE(SUM(payment_amount + cwt_amount) FILTER (WHERE line_type = 'invoice_application'), 0),
    COALESCE(SUM(payment_amount + cwt_amount) FILTER (WHERE line_type = 'customer_advance'), 0)
  INTO v_ar_credit, v_advance_credit
  FROM receipt_lines
  WHERE receipt_id = v_rec.id;

  -- COA resolver adoption (P2A): resolve only the accounts this receipt needs.
  IF v_ar_credit > 0 THEN
    v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.receipt_date,
              'AR control account not configured. Set it up in GL Posting Configuration.');
  END IF;
  IF v_advance_credit > 0 THEN
    v_advance := fn_resolve_posting_account(v_rec.company_id, 'CUSTOMER_ADVANCES', v_rec.receipt_date,
                   'Customer advances account not configured. Set it up in GL Posting Configuration.');
  END IF;
  IF v_rec.total_cwt > 0 THEN
    v_cwt := fn_resolve_posting_account(v_rec.company_id, 'EWT_WITHHELD', v_rec.receipt_date,
               'EWT Withheld account not configured. Set it up in GL Posting Configuration.');
  END IF;

  v_cash_account := v_rec.bank_account_id;
  IF v_cash_account IS NULL AND v_rec.total_amount > 0 THEN
    v_cash_account := fn_resolve_posting_account(v_rec.company_id, 'CASH_DEFAULT', v_rec.receipt_date,
                        'No bank account on receipt and no default cash account configured.');
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-OR-' || v_rec.receipt_number, v_rec.receipt_date,
    'Official Receipt ' || v_rec.receipt_number || ' - ' || v_rec.customer_name_snapshot,
    'OR', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;

  IF v_rec.total_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cash_account,
      'Cash received - ' || v_rec.receipt_number,
      v_rec.total_amount, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_rec.total_cwt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cwt,
      'CWT receivable - ' || v_rec.receipt_number,
      v_rec.total_cwt, 0,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_ar_credit > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_ar,
      'AR cleared - ' || v_rec.receipt_number,
      0, v_ar_credit,
      v_rec.branch_id, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_advance_credit > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_advance,
      'Customer advance - ' || v_rec.receipt_number,
      0, v_advance_credit,
      v_rec.branch_id, NULL, NULL
    );
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE receipts
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_line IN
    SELECT rl.id, rl.payment_amount, rl.cwt_amount, rl.atc_code_id,
           rl.cwt_tax_base, ac.rate AS cwt_rate
    FROM receipt_lines rl
    LEFT JOIN atc_codes ac ON ac.id = rl.atc_code_id
    WHERE rl.receipt_id = v_rec.id
      AND rl.cwt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'OR', v_rec.id, v_line.id,
      'cwt_receivable', NULL, NULL, v_line.atc_code_id,
      ROUND(COALESCE(v_line.cwt_tax_base,
        v_line.payment_amount + v_line.cwt_amount), 2),
      v_line.cwt_rate, v_line.cwt_amount, v_fp_id,
      CURRENT_DATE, v_rec.receipt_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'OR', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.receipt_date)
  );
END;
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Sales Credit Memo
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_credit_memo_vat_lump_impl(p_cm_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       credit_memos%ROWTYPE;
  v_ar        UUID;
  v_vat       UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM credit_memos WHERE id = p_cm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Credit memo cannot be posted in status: %', v_rec.status;
  END IF;

  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.cm_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.cm_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.cm_date
    AND end_date >= v_rec.cm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for CM date %. Create or unlock a fiscal period first.', v_rec.cm_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-CM-' || v_rec.cm_number, v_rec.cm_date, v_fp_id,
    'Credit Memo ' || v_rec.cm_number || ' — ' || v_rec.customer_name_snapshot,
    'CM', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount, 'system',
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  FOR v_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM credit_memo_lines
    WHERE credit_memo_id = v_rec.id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id,
            'Sales return — ' || v_line.ln_desc, v_line.net_sum, 0, 'base', auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_vat,
            'Output VAT reversal — ' || v_rec.cm_number, v_rec.total_vat_amount, 0, 'tax', auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_ar,
          'AR — ' || v_rec.customer_name_snapshot, 0, v_rec.total_amount, 'control', auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'CM journal entry unbalanced: DR=% CR=%. Ensure all CM lines have revenue accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE credit_memos SET
    status = 'applied', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_cm_id;

  -- Negative output VAT in tax ledger (reversal of original SI output VAT)
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CM', v_rec.id,
      'output_vat', -v_rec.total_taxable_amount, -v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.cm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      true
    );
  END IF;
END;
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Sales Debit Memo
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_debit_memo_vat_lump_impl(p_dm_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       debit_memos%ROWTYPE;
  v_ar        UUID;
  v_vat       UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 2;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM debit_memos WHERE id = p_dm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Debit memo cannot be posted in status: %', v_rec.status;
  END IF;

  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.dm_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.dm_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.dm_date
    AND end_date >= v_rec.dm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for DM date %. Create or unlock a fiscal period first.', v_rec.dm_date;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, created_by, updated_by
  ) VALUES (
    v_rec.company_id, v_rec.branch_id,
    'JE-DM-' || v_rec.dm_number, v_rec.dm_date, v_fp_id,
    'Debit Memo ' || v_rec.dm_number || ' — ' || v_rec.customer_name_snapshot,
    'DM', v_rec.id, 'posted',
    v_rec.total_amount, v_rec.total_amount, 'system',
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_ar,
          'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, 'control', auth.uid(), auth.uid());

  FOR v_line IN
    SELECT account_id, SUM(amount) AS amt_sum, description AS ln_desc
    FROM debit_memo_lines
    WHERE debit_memo_id = v_rec.id AND account_id IS NOT NULL
    GROUP BY account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.account_id,
            'DM charge — ' || v_line.ln_desc, 0, v_line.amt_sum, 'base', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.amt_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_vat,
            'Output VAT — ' || v_rec.dm_number, 0, v_rec.total_vat_amount, 'tax', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'DM journal entry unbalanced: DR=% CR=%. Ensure all DM lines have GL accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE debit_memos SET
    status = 'paid', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_dm_id;

  -- Positive output VAT in tax ledger
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'DM', v_rec.id,
      'output_vat', v_rec.total_taxable_amount, v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.dm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      false
    );
  END IF;
END;
$function$;

-- ══════════════════════════════════════════════════════════════════════════════
-- Cash Sale (creates the SI + OR journal pair on save)
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_save_cash_sale(p_header jsonb, p_lines jsonb, p_cwt_amount numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id    UUID;
  v_branch_id     UUID;
  v_si_id         UUID;
  v_receipt_id    UUID;
  v_si_number     TEXT;
  v_or_number     TEXT;
  v_ar            UUID;
  v_vat           UUID;
  v_cwt           UUID;
  v_cash_acct     UUID;
  v_fp_id         UUID;
  v_je_si_id      UUID;
  v_je_or_id      UUID;
  v_grand_total   NUMERIC(15,2) := 0;
  v_total_vat     NUMERIC(15,2) := 0;
  v_total_taxable NUMERIC(15,2) := 0;
  v_total_zero    NUMERIC(15,2) := 0;
  v_total_exempt  NUMERIC(15,2) := 0;
  v_total_cr      NUMERIC(15,2) := 0;
  v_rev_line      RECORD;
  v_rev_line_no   INT;
  v_line          JSONB;
  v_qty           NUMERIC;
  v_price         NUMERIC;
  v_disc          NUMERIC;
  v_net           NUMERIC(15,2);
  v_vat_amt       NUMERIC(15,2);
  v_class         TEXT;
  v_rate          NUMERIC;
  v_has_lines     BOOLEAN := false;
  v_cwt_atc       UUID;
  v_cwt_rate      NUMERIC;
  v_line_no_si    INT := 1;
  v_cash_received NUMERIC(15,2);
  v_net_of_vat    NUMERIC(15,2);
  v_cwt_base      NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id','')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  -- COA resolver adoption (P2A). AR is always required; cash/CWT/VAT are conditional.
  v_ar := fn_resolve_posting_account(v_company_id, 'AR_TRADE', (p_header->>'date')::DATE,
            'AR control account not configured. Set it up in GL Posting Configuration.');

  v_cash_acct := NULLIF(p_header->>'bank_account_id','')::UUID;
  IF v_cash_acct IS NULL THEN
    v_cash_acct := fn_resolve_posting_account(v_company_id, 'CASH_DEFAULT', (p_header->>'date')::DATE,
                     'No cash/bank account specified and no default cash account configured.');
  END IF;

  IF p_cwt_amount > 0 THEN
    v_cwt := fn_resolve_posting_account(v_company_id, 'EWT_WITHHELD', (p_header->>'date')::DATE,
               'EWT Withheld (CWT Receivable) account not configured. Set it up in GL Posting Configuration.');
  END IF;
  -- CWT requires an ATC (PXL-AUD-007 rules, enforced by the receipt-line
  -- validator); the ATC travels in the header as cwt_atc_id.
  v_cwt_atc := NULLIF(p_header->>'cwt_atc_id','')::UUID;
  IF p_cwt_amount > 0 THEN
    SELECT rate INTO v_cwt_rate FROM atc_codes WHERE id = v_cwt_atc;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'date')::DATE
    AND end_date   >= (p_header->>'date')::DATE
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for date %. Create or unlock a fiscal period.', (p_header->>'date')::DATE;
  END IF;

  -- Number series
  v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'CS');
  v_or_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

  -- Recompute amounts from source (UI preview values are not trusted).
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_class, v_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id','')::UUID;
    v_class := COALESCE(v_class, 'exempt');
    v_rate  := COALESCE(v_rate, 0);

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE WHEN v_class = 'regular' THEN ROUND(v_net * v_rate / 100, 2) ELSE 0 END;

    v_grand_total := v_grand_total + v_net + v_vat_amt;
    v_total_vat   := v_total_vat + v_vat_amt;
    CASE v_class
      WHEN 'regular'    THEN v_total_taxable := v_total_taxable + v_net;
      WHEN 'zero_rated' THEN v_total_zero    := v_total_zero + v_net;
      ELSE                   v_total_exempt  := v_total_exempt + v_net;
    END CASE;
    v_has_lines := true;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'Cash sale must have at least one line with a description.';
  END IF;

  -- Output VAT account is required once there is VAT to post.
  IF v_total_vat > 0 THEN
    v_vat := fn_resolve_posting_account(v_company_id, 'VAT_OUTPUT', (p_header->>'date')::DATE,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  -- Insert SI
  INSERT INTO sales_invoices (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    si_number, date, due_date, currency_code, memo,
    total_amount, total_vat_amount, total_taxable_amount,
    total_zero_rated_amount, total_exempt_amount,
    is_cash_sale, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot',
    NULLIF(p_header->>'customer_tin_snapshot',''),
    v_si_number,
    (p_header->>'date')::DATE,
    (p_header->>'date')::DATE,
    COALESCE(NULLIF(p_header->>'currency_code',''),'PHP'),
    NULLIF(p_header->>'memo',''),
    v_grand_total, v_total_vat, v_total_taxable,
    v_total_zero, v_total_exempt,
    true, 'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_si_id;

  -- Insert SI lines with the same recomputed amounts
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    SELECT vc.vat_classification, tc.rate INTO v_class, v_rate
    FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
    WHERE vc.id = NULLIF(v_line->>'vat_code_id','')::UUID;
    v_class := COALESCE(v_class, 'exempt');
    v_rate  := COALESCE(v_rate, 0);

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    v_net   := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);
    v_vat_amt := CASE WHEN v_class = 'regular' THEN ROUND(v_net * v_rate / 100, 2) ELSE 0 END;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number, item_id, description,
      quantity, unit_price, discount_amount, net_amount,
      vat_code_id, vat_amount, total_amount, revenue_account_id,
      created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no_si,
      NULLIF(v_line->>'item_id','')::UUID,
      v_line->>'description',
      v_qty, v_price, v_disc, v_net,
      NULLIF(v_line->>'vat_code_id','')::UUID,
      v_vat_amt, v_net + v_vat_amt,
      NULLIF(v_line->>'revenue_account_id','')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no_si := v_line_no_si + 1;
  END LOOP;

  -- Post SI JE: DR AR, CR Revenue lines, CR VAT Payable
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    'JE-SI-' || v_si_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Sale ' || v_si_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id, 'posted', v_grand_total, v_grand_total, 'system', auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_si_id;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_si_id, v_company_id, 1, v_ar, 'AR — ' || (p_header->>'customer_name_snapshot'), v_grand_total, 0, 'control', auth.uid(), auth.uid());

  v_rev_line_no := 2;
  FOR v_rev_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_rev_line.revenue_account_id, 'Revenue — ' || v_rev_line.ln_desc, 0, v_rev_line.net_sum, 'base', auth.uid(), auth.uid());
    v_total_cr    := v_total_cr + v_rev_line.net_sum;
    v_rev_line_no := v_rev_line_no + 1;
  END LOOP;

  IF v_total_vat > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_si_id, v_company_id, v_rev_line_no, v_vat, 'Output VAT — ' || v_si_number, 0, v_total_vat, 'tax', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_total_vat;
  END IF;

  UPDATE sales_invoices SET
    status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_si_id, approved_by = auth.uid(), approved_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_si_id;

  -- Output VAT tax ledger: one row per VAT code.
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name
  )
  SELECT
    v_company_id, v_branch_id, 'SI', v_si_id,
    'output_vat', sil.vat_code_id,
    SUM(sil.net_amount), COALESCE(SUM(sil.vat_amount), 0), v_fp_id,
    NOW()::DATE, (p_header->>'date')::DATE,
    (p_header->>'customer_id')::UUID,
    NULLIF(p_header->>'customer_tin_snapshot',''),
    p_header->>'customer_name_snapshot'
  FROM sales_invoice_lines sil
  WHERE sil.sales_invoice_id = v_si_id
    AND sil.vat_code_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM companies c
                WHERE c.id = v_company_id AND c.tax_registration = 'vat')
  GROUP BY sil.vat_code_id
  HAVING SUM(sil.net_amount) <> 0 OR COALESCE(SUM(sil.vat_amount), 0) <> 0;

  -- ── Receipt JE ───────────────────────────────────────────────────────────
  v_cash_received := v_grand_total - p_cwt_amount;

  IF p_cwt_amount > 0 THEN
    IF v_cwt_rate IS NULL OR v_cwt_rate <= 0 THEN
      RAISE EXCEPTION 'CWT ATC code is missing, inactive, or has no positive rate.';
    END IF;
    v_net_of_vat := v_grand_total - v_total_vat;
    IF ABS(ROUND(v_net_of_vat * v_cwt_rate / 100.0, 2) - p_cwt_amount) <= 0.02 THEN
      v_cwt_base := v_net_of_vat;
    ELSIF ABS(ROUND(v_grand_total * v_cwt_rate / 100.0, 2) - p_cwt_amount) <= 0.02 THEN
      v_cwt_base := v_grand_total;
    ELSE
      RAISE EXCEPTION 'CWT % does not match ATC rate %%% on the VAT-exclusive base % (expected %) or on the gross % (expected %).',
        p_cwt_amount, v_cwt_rate,
        v_net_of_vat, ROUND(v_net_of_vat * v_cwt_rate / 100.0, 2),
        v_grand_total, ROUND(v_grand_total * v_cwt_rate / 100.0, 2);
    END IF;
  END IF;

  INSERT INTO receipts (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    receipt_number, receipt_date, payment_mode_id, bank_account_id,
    total_amount, total_cwt, remarks, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot',''),
    v_or_number, (p_header->>'date')::DATE,
    COALESCE(NULLIF(p_header->>'payment_mode_id','')::UUID,
             (SELECT id FROM ref_payment_modes WHERE code = 'CASH')), v_cash_acct,
    v_grand_total, p_cwt_amount, 'Cash Sale — ' || v_si_number,
    'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_receipt_id;

  INSERT INTO receipt_lines (receipt_id, company_id, invoice_id, payment_amount, cwt_amount, atc_code_id, cwt_tax_base, created_by, updated_by)
  VALUES (v_receipt_id, v_company_id, v_si_id, v_grand_total - p_cwt_amount, p_cwt_amount, v_cwt_atc,
          CASE WHEN p_cwt_amount > 0 THEN v_cwt_base ELSE NULL END, auth.uid(), auth.uid());

  -- Post receipt JE: DR Cash (net) + DR CWT Receivable = CR AR (gross)
  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, 'JE-OR-' || v_or_number, (p_header->>'date')::DATE, v_fp_id,
    'Cash Receipt ' || v_or_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id, 'posted', v_grand_total, v_grand_total, 'system', auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_or_id;

  -- DR: Cash / Bank (net of CWT)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, 1, v_cash_acct, 'Cash received — ' || v_or_number, v_cash_received, 0, 'base', auth.uid(), auth.uid());

  -- DR: CWT Receivable (tax withheld by customer, to be reclaimed)
  IF p_cwt_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_or_id, v_company_id, 2, v_cwt, 'CWT receivable — ' || v_or_number, p_cwt_amount, 0, 'withholding', auth.uid(), auth.uid());
  END IF;

  -- CR: Accounts Receivable (full invoice amount)
  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_or_id, v_company_id, CASE WHEN p_cwt_amount > 0 THEN 3 ELSE 2 END,
    v_ar, 'AR cleared — ' || v_or_number, 0, v_grand_total, 'control', auth.uid(), auth.uid());

  UPDATE receipts SET status = 'posted', journal_entry_id = v_je_or_id,
    posted_by = auth.uid(), posted_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  -- CWT receivable tax ledger row.
  IF p_cwt_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_company_id, v_branch_id, 'OR', v_receipt_id,
      'cwt_receivable', v_cwt_atc, v_cwt_base, v_cwt_rate, p_cwt_amount, v_fp_id,
      NOW()::DATE, (p_header->>'date')::DATE,
      (p_header->>'customer_id')::UUID,
      NULLIF(p_header->>'customer_tin_snapshot',''),
      p_header->>'customer_name_snapshot'
    );
  END IF;

  RETURN jsonb_build_object(
    'si_id', v_si_id, 'receipt_id', v_receipt_id,
    'si_number', v_si_number, 'receipt_number', v_or_number
  );
END;
$function$;
