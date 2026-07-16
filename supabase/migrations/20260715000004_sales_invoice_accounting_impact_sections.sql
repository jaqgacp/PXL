-- Sales Invoice separated accounting impact presentation.
--
-- This enriches the Sales Invoice GL impact response with impact grouping and
-- source metadata so the UI can present commercial/revenue accounting apart
-- from inventory/cost accounting while preserving one balanced journal impact.

CREATE OR REPLACE FUNCTION fn_preview_sales_invoice_gl_impact(
  p_invoice_id UUID,
  p_posting_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec sales_invoices%ROWTYPE;
  v_cfg company_accounting_config%ROWTYPE;
  v_je journal_entries%ROWTYPE;
  v_je_id UUID;
  v_posting_date DATE;
  v_fp_id UUID;
  v_fp_name TEXT;
  v_branch_name TEXT;
  v_source_route TEXT;
  v_display_name TEXT;
  v_lines JSONB;
  v_total_debit NUMERIC(15,2) := 0;
  v_total_credit NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec
  FROM sales_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Sales invoice not found or access denied';
  END IF;

  SELECT * INTO v_cfg
  FROM company_accounting_config
  WHERE company_id = v_rec.company_id;

  SELECT * INTO v_je
  FROM journal_entries
  WHERE reference_doc_type = 'SI'
    AND reference_doc_id = p_invoice_id
    AND status IN ('posted', 'reversed')
  ORDER BY created_at DESC
  LIMIT 1;
  v_je_id := v_je.id;

  v_posting_date := COALESCE(p_posting_date, v_je.je_date, v_rec.date, CURRENT_DATE);

  SELECT fp.id, fp.period_name
    INTO v_fp_id, v_fp_name
  FROM fiscal_periods fp
  WHERE fp.company_id = v_rec.company_id
    AND v_posting_date BETWEEN fp.start_date AND fp.end_date
    AND COALESCE(fp.is_locked, false) = false
  ORDER BY fp.start_date DESC
  LIMIT 1;

  SELECT branch_name INTO v_branch_name
  FROM branches
  WHERE id = v_rec.branch_id;

  SELECT route_path, display_name
    INTO v_source_route, v_display_name
  FROM ref_posting_source_types
  WHERE document_type = 'SI';

  IF v_je_id IS NOT NULL THEN
    WITH line_sources AS (
      SELECT
        sil.id AS source_line_id,
        sil.line_number,
        sil.description,
        sil.quantity,
        sil.revenue_account_id,
        COALESCE(sil.department_id, v_rec.department_id) AS department_id,
        COALESCE(sil.cost_center_id, v_rec.cost_center_id) AS cost_center_id,
        sil.item_id,
        i.item_code,
        i.item_type,
        COALESCE(i.costing_method, 'weighted_average') AS valuation_method,
        sil.warehouse_id,
        w.warehouse_code,
        COALESCE(sil.inventory_account_id, i.inventory_account_id) AS inventory_account_id,
        COALESCE(sil.cogs_account_id, i.cogs_account_id) AS cogs_account_id,
        sil.unit_cost,
        sil.inventory_cost,
        sil.inventory_transaction_id
      FROM sales_invoice_lines sil
      LEFT JOIN items i ON i.id = sil.item_id
      LEFT JOIN warehouses w ON w.id = sil.warehouse_id
      WHERE sil.sales_invoice_id = v_rec.id
    ),
    classified AS (
      SELECT
        jel.line_number,
        jel.account_id,
        coa.account_code,
        coa.account_name,
        CASE
          WHEN jel.account_id = v_cfg.ar_account_id THEN 'company_accounting_config.ar_account_id'
          WHEN jel.account_id = v_cfg.vat_payable_account_id THEN 'company_accounting_config.vat_payable_account_id'
          WHEN ls.cogs_account_id = jel.account_id AND jel.description = 'COGS - ' || COALESCE(ls.item_code, ls.description) THEN 'item_cogs_account_id'
          WHEN ls.inventory_account_id = jel.account_id AND jel.description = 'Inventory - ' || COALESCE(ls.item_code, ls.description) THEN 'item_inventory_account_id'
          WHEN ls.revenue_account_id = jel.account_id AND jel.description = 'Revenue - ' || ls.description THEN 'document_line_account'
          ELSE 'document or module posting rule'
        END AS account_source,
        jel.description,
        jel.debit_amount AS debit,
        jel.credit_amount AS credit,
        jel.branch_id,
        jel.department_id,
        jel.cost_center_id,
        CASE
          WHEN ls.cogs_account_id = jel.account_id AND jel.description = 'COGS - ' || COALESCE(ls.item_code, ls.description) THEN 'INVENTORY'
          WHEN ls.inventory_account_id = jel.account_id AND jel.description = 'Inventory - ' || COALESCE(ls.item_code, ls.description) THEN 'INVENTORY'
          ELSE 'COMMERCIAL'
        END AS impact_group,
        CASE
          WHEN jel.account_id = v_cfg.ar_account_id THEN 'RECEIVABLE'
          WHEN jel.account_id = v_cfg.vat_payable_account_id THEN 'TAX'
          WHEN ls.cogs_account_id = jel.account_id AND jel.description = 'COGS - ' || COALESCE(ls.item_code, ls.description) THEN 'COGS'
          WHEN ls.inventory_account_id = jel.account_id AND jel.description = 'Inventory - ' || COALESCE(ls.item_code, ls.description) THEN 'INVENTORY'
          WHEN ls.revenue_account_id = jel.account_id AND jel.description = 'Revenue - ' || ls.description THEN 'REVENUE'
          ELSE 'OTHER'
        END AS accounting_effect,
        CASE
          WHEN jel.account_id = v_cfg.ar_account_id THEN 'Invoice Header'
          WHEN jel.account_id = v_cfg.vat_payable_account_id THEN 'Tax Calculation'
          WHEN ls.source_line_id IS NOT NULL THEN 'Invoice Line'
          ELSE 'Posting Rule'
        END AS source_type,
        ls.source_line_id,
        ls.item_id,
        ls.item_code,
        ls.warehouse_id,
        ls.warehouse_code,
        ls.quantity,
        ls.unit_cost,
        ls.inventory_cost AS total_cost,
        ls.valuation_method,
        ls.inventory_transaction_id AS inventory_movement_id
      FROM journal_entry_lines jel
      JOIN chart_of_accounts coa ON coa.id = jel.account_id
      LEFT JOIN LATERAL (
        SELECT *
        FROM line_sources candidate
        WHERE (
          candidate.cogs_account_id = jel.account_id
          AND jel.description = 'COGS - ' || COALESCE(candidate.item_code, candidate.description)
        ) OR (
          candidate.inventory_account_id = jel.account_id
          AND jel.description = 'Inventory - ' || COALESCE(candidate.item_code, candidate.description)
        ) OR (
          candidate.revenue_account_id = jel.account_id
          AND jel.description = 'Revenue - ' || candidate.description
        )
        ORDER BY candidate.line_number
        LIMIT 1
      ) ls ON true
      WHERE jel.je_id = v_je_id
    )
    SELECT
      COALESCE(jsonb_agg(jsonb_build_object(
        'line_number', line_number,
        'account_id', account_id,
        'account_code', account_code,
        'account_name', account_name,
        'account_source', account_source,
        'description', description,
        'debit', debit,
        'credit', credit,
        'branch_id', branch_id,
        'department_id', department_id,
        'cost_center_id', cost_center_id,
        'impact_group', impact_group,
        'accounting_effect', accounting_effect,
        'source_type', source_type,
        'source_line_id', source_line_id,
        'item_id', item_id,
        'item_code', item_code,
        'warehouse_id', warehouse_id,
        'warehouse_code', warehouse_code,
        'quantity', quantity,
        'unit_cost', unit_cost,
        'total_cost', total_cost,
        'valuation_method', valuation_method,
        'inventory_movement_id', inventory_movement_id
      ) ORDER BY line_number), '[]'::jsonb),
      COALESCE(SUM(debit), 0),
      COALESCE(SUM(credit), 0)
    INTO v_lines, v_total_debit, v_total_credit
    FROM classified;

    RETURN jsonb_build_object(
      'mode', 'posted',
      'journal_entry_id', v_je_id,
      'je_number', v_je.je_number,
      'posting_date', v_je.je_date,
      'fiscal_period_id', v_je.fiscal_period_id,
      'fiscal_period_name', COALESCE(v_fp_name, (SELECT period_name FROM fiscal_periods WHERE id = v_je.fiscal_period_id)),
      'branch_id', v_je.branch_id,
      'branch_name', v_branch_name,
      'source_doc_type', 'SI',
      'source_doc_id', p_invoice_id,
      'source_display_name', COALESCE(v_display_name, 'Sales Invoice'),
      'source_route', CASE WHEN v_source_route IS NOT NULL
                           THEN v_source_route || '?id=' || p_invoice_id::TEXT
                           ELSE NULL END,
      'rule_explanation',
        'Posted journal lines are the authoritative Sales Invoice accounting impact. Sections are presentation groupings only.',
      'total_debit', ROUND(v_total_debit, 2),
      'total_credit', ROUND(v_total_credit, 2),
      'balanced', ABS(v_total_debit - v_total_credit) <= 0.01,
      'lines', v_lines
    );
  END IF;

  WITH inventory_costs AS (
    SELECT
      sil.id AS source_line_id,
      sil.line_number,
      sil.description,
      sil.item_id,
      i.item_code,
      i.item_type,
      COALESCE(i.costing_method, 'weighted_average') AS valuation_method,
      sil.quantity,
      sil.warehouse_id,
      w.warehouse_code,
      COALESCE(sil.department_id, v_rec.department_id) AS department_id,
      COALESCE(sil.cost_center_id, v_rec.cost_center_id) AS cost_center_id,
      COALESCE(sil.inventory_account_id, i.inventory_account_id) AS inventory_account_id,
      COALESCE(sil.cogs_account_id, i.cogs_account_id) AS cogs_account_id,
      COALESCE(NULLIF(sil.unit_cost, 0), sb.wac_unit_cost, i.standard_cost, 0) AS unit_cost,
      ROUND(
        sil.quantity * COALESCE(NULLIF(sil.unit_cost, 0), sb.wac_unit_cost, i.standard_cost, 0),
        2
      ) AS total_cost
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    LEFT JOIN warehouses w ON w.id = sil.warehouse_id
    LEFT JOIN stock_balances sb
      ON sb.warehouse_id = sil.warehouse_id
     AND sb.item_id = sil.item_id
    WHERE sil.sales_invoice_id = v_rec.id
      AND i.item_type = 'inventory_item'
  ),
  raw_rows AS (
    SELECT
      10::NUMERIC AS sort_key,
      v_cfg.ar_account_id AS account_id,
      'company_accounting_config.ar_account_id'::TEXT AS account_source,
      'Accounts receivable'::TEXT AS description,
      v_rec.total_amount::NUMERIC AS debit,
      0::NUMERIC AS credit,
      v_rec.branch_id AS branch_id,
      v_rec.department_id AS department_id,
      v_rec.cost_center_id AS cost_center_id,
      'COMMERCIAL'::TEXT AS impact_group,
      'RECEIVABLE'::TEXT AS accounting_effect,
      'Invoice Header'::TEXT AS source_type,
      NULL::UUID AS source_line_id,
      NULL::UUID AS item_id,
      NULL::TEXT AS item_code,
      NULL::UUID AS warehouse_id,
      NULL::TEXT AS warehouse_code,
      NULL::NUMERIC AS quantity,
      NULL::NUMERIC AS unit_cost,
      NULL::NUMERIC AS total_cost,
      NULL::TEXT AS valuation_method,
      NULL::UUID AS inventory_movement_id
    WHERE COALESCE(v_rec.total_amount, 0) <> 0

    UNION ALL

    SELECT
      20 + ROW_NUMBER() OVER (
        ORDER BY revenue_account_id::TEXT NULLS FIRST, line_description,
                 department_id::TEXT NULLS FIRST, cost_center_id::TEXT NULLS FIRST
      ) AS sort_key,
      revenue_account_id AS account_id,
      CASE WHEN revenue_account_id IS NULL
           THEN 'missing_revenue_account'
           ELSE 'document_line_account'
      END AS account_source,
      'Revenue - ' || line_description AS description,
      0::NUMERIC AS debit,
      net_sum AS credit,
      v_rec.branch_id AS branch_id,
      department_id,
      cost_center_id,
      'COMMERCIAL'::TEXT AS impact_group,
      'REVENUE'::TEXT AS accounting_effect,
      'Invoice Line'::TEXT AS source_type,
      NULL::UUID AS source_line_id,
      NULL::UUID AS item_id,
      NULL::TEXT AS item_code,
      NULL::UUID AS warehouse_id,
      NULL::TEXT AS warehouse_code,
      NULL::NUMERIC AS quantity,
      NULL::NUMERIC AS unit_cost,
      NULL::NUMERIC AS total_cost,
      NULL::TEXT AS valuation_method,
      NULL::UUID AS inventory_movement_id
    FROM (
      SELECT
        sil.revenue_account_id,
        COALESCE(NULLIF(TRIM(sil.description), ''), 'Sales invoice line') AS line_description,
        COALESCE(sil.department_id, v_rec.department_id) AS department_id,
        COALESCE(sil.cost_center_id, v_rec.cost_center_id) AS cost_center_id,
        SUM(sil.net_amount) AS net_sum
      FROM sales_invoice_lines sil
      WHERE sil.sales_invoice_id = v_rec.id
      GROUP BY
        sil.revenue_account_id,
        COALESCE(NULLIF(TRIM(sil.description), ''), 'Sales invoice line'),
        COALESCE(sil.department_id, v_rec.department_id),
        COALESCE(sil.cost_center_id, v_rec.cost_center_id)
    ) revenue_rows

    UNION ALL

    SELECT
      40::NUMERIC AS sort_key,
      v_cfg.vat_payable_account_id AS account_id,
      'company_accounting_config.vat_payable_account_id'::TEXT AS account_source,
      'Output VAT - ' || v_rec.si_number AS description,
      0::NUMERIC AS debit,
      v_rec.total_vat_amount::NUMERIC AS credit,
      v_rec.branch_id AS branch_id,
      v_rec.department_id AS department_id,
      v_rec.cost_center_id AS cost_center_id,
      'COMMERCIAL'::TEXT AS impact_group,
      'TAX'::TEXT AS accounting_effect,
      'Tax Calculation'::TEXT AS source_type,
      NULL::UUID AS source_line_id,
      NULL::UUID AS item_id,
      NULL::TEXT AS item_code,
      NULL::UUID AS warehouse_id,
      NULL::TEXT AS warehouse_code,
      NULL::NUMERIC AS quantity,
      NULL::NUMERIC AS unit_cost,
      NULL::NUMERIC AS total_cost,
      NULL::TEXT AS valuation_method,
      NULL::UUID AS inventory_movement_id
    WHERE COALESCE(v_rec.total_vat_amount, 0) <> 0

    UNION ALL

    SELECT
      50 + (line_number * 2)::NUMERIC AS sort_key,
      cogs_account_id AS account_id,
      CASE WHEN cogs_account_id IS NULL
           THEN 'missing_cogs_account'
           ELSE 'item_cogs_account_id'
      END AS account_source,
      'COGS - ' || COALESCE(item_code, description) AS description,
      total_cost AS debit,
      0::NUMERIC AS credit,
      v_rec.branch_id AS branch_id,
      department_id,
      cost_center_id,
      'INVENTORY'::TEXT AS impact_group,
      'COGS'::TEXT AS accounting_effect,
      'Invoice Line'::TEXT AS source_type,
      source_line_id,
      item_id,
      item_code,
      warehouse_id,
      warehouse_code,
      quantity,
      unit_cost,
      total_cost,
      valuation_method,
      NULL::UUID AS inventory_movement_id
    FROM inventory_costs
    WHERE COALESCE(total_cost, 0) > 0

    UNION ALL

    SELECT
      51 + (line_number * 2)::NUMERIC AS sort_key,
      inventory_account_id AS account_id,
      CASE WHEN inventory_account_id IS NULL
           THEN 'missing_inventory_account'
           ELSE 'item_inventory_account_id'
      END AS account_source,
      'Inventory - ' || COALESCE(item_code, description) AS description,
      0::NUMERIC AS debit,
      total_cost AS credit,
      v_rec.branch_id AS branch_id,
      department_id,
      cost_center_id,
      'INVENTORY'::TEXT AS impact_group,
      'INVENTORY'::TEXT AS accounting_effect,
      'Invoice Line'::TEXT AS source_type,
      source_line_id,
      item_id,
      item_code,
      warehouse_id,
      warehouse_code,
      quantity,
      unit_cost,
      total_cost,
      valuation_method,
      NULL::UUID AS inventory_movement_id
    FROM inventory_costs
    WHERE COALESCE(total_cost, 0) > 0
  ),
  ordered_rows AS (
    SELECT
      ROW_NUMBER() OVER (ORDER BY sort_key)::INTEGER AS line_number,
      account_id,
      account_source,
      description,
      ROUND(COALESCE(debit, 0), 2) AS debit,
      ROUND(COALESCE(credit, 0), 2) AS credit,
      branch_id,
      department_id,
      cost_center_id,
      impact_group,
      accounting_effect,
      source_type,
      source_line_id,
      item_id,
      item_code,
      warehouse_id,
      warehouse_code,
      quantity,
      unit_cost,
      total_cost,
      valuation_method,
      inventory_movement_id
    FROM raw_rows
    WHERE ABS(COALESCE(debit, 0)) > 0.005
       OR ABS(COALESCE(credit, 0)) > 0.005
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'line_number', r.line_number,
      'account_id', r.account_id,
      'account_code', COALESCE(coa.account_code, CASE r.account_source
        WHEN 'missing_revenue_account' THEN 'Missing Revenue Account'
        WHEN 'missing_cogs_account' THEN 'Missing COGS Account'
        WHEN 'missing_inventory_account' THEN 'Missing Inventory Account'
        WHEN 'company_accounting_config.ar_account_id' THEN 'Missing AR Account'
        WHEN 'company_accounting_config.vat_payable_account_id' THEN 'Missing VAT Payable Account'
        ELSE 'Missing Account'
      END),
      'account_name', COALESCE(coa.account_name, ''),
      'account_source', r.account_source,
      'description', r.description,
      'debit', r.debit,
      'credit', r.credit,
      'branch_id', r.branch_id,
      'department_id', r.department_id,
      'cost_center_id', r.cost_center_id,
      'impact_group', r.impact_group,
      'accounting_effect', r.accounting_effect,
      'source_type', r.source_type,
      'source_line_id', r.source_line_id,
      'item_id', r.item_id,
      'item_code', r.item_code,
      'warehouse_id', r.warehouse_id,
      'warehouse_code', r.warehouse_code,
      'quantity', r.quantity,
      'unit_cost', r.unit_cost,
      'total_cost', r.total_cost,
      'valuation_method', r.valuation_method,
      'inventory_movement_id', r.inventory_movement_id
    ) ORDER BY r.line_number), '[]'::jsonb),
    COALESCE(SUM(r.debit), 0),
    COALESCE(SUM(r.credit), 0)
  INTO v_lines, v_total_debit, v_total_credit
  FROM ordered_rows r
  LEFT JOIN chart_of_accounts coa
    ON coa.id = r.account_id
   AND coa.company_id = v_rec.company_id;

  RETURN jsonb_build_object(
    'mode', 'preview',
    'journal_entry_id', NULL,
    'je_number', NULL,
    'posting_date', v_posting_date,
    'fiscal_period_id', v_fp_id,
    'fiscal_period_name', v_fp_name,
    'branch_id', v_rec.branch_id,
    'branch_name', v_branch_name,
    'source_doc_type', 'SI',
    'source_doc_id', p_invoice_id,
    'source_display_name', COALESCE(v_display_name, 'Sales Invoice'),
    'source_route', CASE WHEN v_source_route IS NOT NULL
                         THEN v_source_route || '?id=' || p_invoice_id::TEXT
                         ELSE NULL END,
    'rule_explanation',
      'Preview generated from the saved Sales Invoice. Sections are presentation groupings only; posted journal lines remain authoritative.',
    'total_debit', ROUND(v_total_debit, 2),
    'total_credit', ROUND(v_total_credit, 2),
    'balanced', ABS(v_total_debit - v_total_credit) <= 0.01,
    'lines', v_lines
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_preview_gl_impact(
  p_source_doc_type TEXT,
  p_source_doc_id UUID,
  p_posting_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := UPPER(BTRIM(p_source_doc_type));
  v_je_id UUID;
  v_payload JSONB;
  v_message TEXT;
  v_effective_posting_date DATE;
  v_marker CONSTANT TEXT := '__PXL_GL_PREVIEW_ROLLBACK__';
BEGIN
  IF p_source_doc_id IS NULL THEN
    RAISE EXCEPTION 'A saved source document is required for server-side GL preview';
  END IF;

  IF v_type = 'SI' THEN
    RETURN fn_preview_sales_invoice_gl_impact(p_source_doc_id, p_posting_date);
  END IF;

  IF v_type <> 'RECURRING' THEN
    SELECT id INTO v_je_id
    FROM journal_entries
    WHERE reference_doc_type = v_type
      AND reference_doc_id = p_source_doc_id
      AND status IN ('posted', 'reversed')
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  IF v_je_id IS NOT NULL THEN
    RETURN fn_gl_impact_payload(v_je_id, 'posted', NULL);
  END IF;

  BEGIN
    CASE v_type
      WHEN 'OR'        THEN PERFORM fn_post_receipt(p_source_doc_id);
      WHEN 'CM'        THEN PERFORM fn_post_credit_memo(p_source_doc_id);
      WHEN 'DM'        THEN PERFORM fn_post_debit_memo(p_source_doc_id);
      WHEN 'VB'        THEN PERFORM fn_post_vendor_bill(p_source_doc_id);
      WHEN 'PV'        THEN PERFORM fn_post_payment_voucher(p_source_doc_id);
      WHEN 'CP'        THEN PERFORM fn_post_cash_purchase(p_source_doc_id);
      WHEN 'VC'        THEN PERFORM fn_post_vendor_credit(p_source_doc_id);
      WHEN 'PR'        THEN PERFORM fn_complete_purchase_return(p_source_doc_id);
      WHEN 'FT'        THEN PERFORM fn_post_fund_transfer(p_source_doc_id);
      WHEN 'IBT'       THEN PERFORM fn_post_inter_branch_transfer(p_source_doc_id);
      WHEN 'BADJ'      THEN PERFORM fn_post_bank_adjustment(p_source_doc_id);
      WHEN 'PCV'       THEN PERFORM fn_approve_petty_cash_voucher(p_source_doc_id);
      WHEN 'PCR'       THEN PERFORM fn_post_petty_cash_replenishment(p_source_doc_id);
      WHEN 'CV'        THEN PERFORM fn_post_check_voucher(p_source_doc_id);
      WHEN 'INV_ADJ'   THEN v_je_id := fn_post_stock_adjustment(p_source_doc_id);
      WHEN 'INV_STX'   THEN v_je_id := fn_post_stock_transfer(p_source_doc_id);
      WHEN 'INV_GI'    THEN v_je_id := fn_post_goods_issue(p_source_doc_id);
      WHEN 'INV_COUNT' THEN v_je_id := fn_post_physical_count(p_source_doc_id);
      WHEN 'FA_DEPR'   THEN v_je_id := fn_post_depreciation_entry(p_source_doc_id);
      WHEN 'AMORT'     THEN v_je_id := fn_post_amortization_entry(p_source_doc_id);
      WHEN 'REVREC'    THEN v_je_id := fn_post_revenue_recognition_entry(p_source_doc_id);
      WHEN 'RECURRING' THEN
        SELECT COALESCE(p_posting_date, next_run_date, start_date, CURRENT_DATE)
        INTO v_effective_posting_date
        FROM recurring_journal_templates
        WHERE id = p_source_doc_id;
        IF v_effective_posting_date IS NULL THEN
          RAISE EXCEPTION 'Recurring journal template not found';
        END IF;
        v_je_id := fn_execute_recurring_template(p_source_doc_id, v_effective_posting_date);
      ELSE RAISE EXCEPTION 'GL preview is not supported for source type %', v_type;
    END CASE;

    IF v_je_id IS NULL THEN
      SELECT id INTO v_je_id
      FROM journal_entries
      WHERE reference_doc_type = v_type
        AND reference_doc_id = p_source_doc_id
        AND status = 'posted'
      ORDER BY created_at DESC
      LIMIT 1;
    END IF;

    IF v_je_id IS NULL THEN
      v_payload := jsonb_build_object(
        'mode', 'preview',
        'source_doc_type', v_type,
        'source_doc_id', p_source_doc_id,
        'total_debit', 0,
        'total_credit', 0,
        'balanced', true,
        'rule_explanation', 'This transaction has no GL impact under its current posting rules.',
        'lines', '[]'::jsonb
      );
    ELSE
      PERFORM fn_finalize_journal_entry(v_je_id);
      v_payload := fn_gl_impact_payload(
        v_je_id,
        'preview',
        'Exact rollback preview: the source posting RPC was executed inside a database subtransaction and fully rolled back.'
      );
    END IF;

    RAISE EXCEPTION USING MESSAGE = v_marker, ERRCODE = 'P0001';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> v_marker THEN
      RAISE;
    END IF;
  END;

  RETURN v_payload;
END;
$$;

GRANT EXECUTE ON FUNCTION fn_preview_sales_invoice_gl_impact(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_preview_gl_impact(TEXT, UUID, DATE) TO authenticated;

COMMENT ON FUNCTION fn_preview_sales_invoice_gl_impact(UUID, DATE) IS
  'Sales Invoice accounting impact payload with commercial and inventory/cost classifications. Preview rows are non-authoritative; posted rows come from immutable journal and inventory evidence.';
