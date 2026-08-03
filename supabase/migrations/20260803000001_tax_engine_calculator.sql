-- ═══════════════════════════════════════════════════════════════════════════
-- Delivery Plan Phase 4 — Tax Engine (the calculator).  PAD-001 decided:
-- Accounting-owned, ONE calculator.
--
-- WHAT THIS CHANGES
--   Before this migration eleven functions computed a Philippine tax amount
--   from a rate, each with its own copy of the rules (censused by
--   supabase/tests/090, assertion 6).  They agreed by coincidence, not by
--   construction, and exactly one of them handled VAT-inclusive pricing.
--   After it, `fn_calculate_tax` is the only function in the schema that
--   turns a rate into a tax amount.  Every other function asks it.
--
-- WHAT THIS DOES NOT CHANGE
--   No posting function, no Accounting Kernel path, no journal shape, no
--   tax-ledger row, no account resolution.  The Posting Engine still computes
--   no tax; it consumes stored facts exactly as before.
--
-- THE ONE DELIBERATE BEHAVIOUR CHANGE
--   `fn_save_cash_sale` resolved its CWT rate with
--       SELECT rate FROM atc_codes WHERE id = <atc>
--   with no is_active, no deprecated_at and no effective-date filter, while
--   every other withholding path in PXL filtered all four.  A cash sale could
--   therefore withhold at a superseded rate.  Routing it through the engine
--   applies the same governed ATC versioning as everywhere else.  This is a
--   correctness fix, it is asserted by test 117, and test 090's fixture was
--   corrected to stop depending on the unfiltered lookup.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── The tax component contract ─────────────────────────────────────────────
-- One row per tax that applies to one line of one document.  `net_amount` and
-- `gross_amount` are carried on every component so a caller never has to
-- re-derive the VAT-exclusive base itself — re-deriving it is precisely how
-- the seven calculators drifted apart.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'tax_component'
  ) THEN
    CREATE TYPE public.tax_component AS (
      tax_kind       TEXT,           -- output_vat | input_vat | ewt | fwt
      vat_code_id    UUID,
      tax_code_id    UUID,
      atc_code_id    UUID,
      atc_code       TEXT,           -- NULL when the ATC did not resolve
      atc_description TEXT,          -- the resolved version's description
      classification TEXT,           -- regular | zero_rated | exempt (VAT only)
      tax_base       NUMERIC(15,2),
      tax_rate       NUMERIC(9,4),   -- NULL when the ATC did not resolve
      tax_amount     NUMERIC(15,2),  -- NULL when the ATC did not resolve
      net_amount     NUMERIC(15,2),
      gross_amount   NUMERIC(15,2),
      price_basis    TEXT            -- exclusive | inclusive
    );
  END IF;
END $$;

COMMENT ON TYPE public.tax_component IS
  'Tax Engine output contract (Delivery Plan Phase 4, PAD-001). One row per tax applying to one document line.';

-- ── The calculator ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_calculate_tax(p_context JSONB)
RETURNS SETOF public.tax_component
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id   UUID          := NULLIF(BTRIM(p_context->>'company_id'), '')::UUID;
  v_date         DATE          := COALESCE(NULLIF(BTRIM(p_context->>'document_date'), '')::DATE, CURRENT_DATE);
  v_direction    TEXT          := LOWER(COALESCE(NULLIF(BTRIM(p_context->>'direction'), ''), 'sale'));
  v_basis        TEXT          := LOWER(COALESCE(NULLIF(BTRIM(p_context->>'price_basis'), ''), 'exclusive'));
  v_amount       NUMERIC(15,2) := ROUND(COALESCE(NULLIF(BTRIM(p_context->>'amount'), '')::NUMERIC, 0), 2);
  v_vat_code_id  UUID          := NULLIF(BTRIM(p_context->>'vat_code_id'), '')::UUID;
  v_atc_id       UUID          := NULLIF(BTRIM(p_context->>'withholding_atc_code_id'), '')::UUID;
  v_atc_category TEXT          := LOWER(COALESCE(NULLIF(BTRIM(p_context->>'withholding_category'), ''), 'ewt'));
  v_wht_base     NUMERIC(15,2) := ROUND(NULLIF(BTRIM(p_context->>'withholding_base'), '')::NUMERIC, 2);
  v_class        TEXT;
  v_txn_type     TEXT;
  v_tax_code_id  UUID;
  v_rate         NUMERIC(9,4);
  v_net          NUMERIC(15,2);
  v_vat          NUMERIC(15,2);
  v_gross        NUMERIC(15,2);
  v_kind         TEXT;
  v_atc_code     TEXT;
  v_atc_desc     TEXT;
  v_atc_rate     NUMERIC(9,4);
  v_wht_amount   NUMERIC(15,2);
  v_row          public.tax_component;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'fn_calculate_tax requires company_id in the tax context.';
  END IF;
  IF v_direction NOT IN ('sale', 'purchase') THEN
    RAISE EXCEPTION 'fn_calculate_tax direction must be sale or purchase, not %.', v_direction;
  END IF;
  IF v_basis NOT IN ('exclusive', 'inclusive') THEN
    RAISE EXCEPTION 'fn_calculate_tax price_basis must be exclusive or inclusive, not %.', v_basis;
  END IF;
  IF v_atc_category NOT IN ('ewt', 'fwt') THEN
    RAISE EXCEPTION 'fn_calculate_tax withholding_category must be ewt or fwt, not %.', v_atc_category;
  END IF;

  -- ── VAT ──────────────────────────────────────────────────────────────────
  -- A VAT component is ALWAYS emitted, even when no VAT code was supplied, so
  -- that `net_amount` has exactly one definition in the product.  An absent or
  -- unknown code is exempt at 0% — the behaviour every caller had before.
  SELECT vc.vat_classification, vc.transaction_type, vc.tax_code_id, tc.rate
    INTO v_class, v_txn_type, v_tax_code_id, v_rate
  FROM vat_codes vc
  JOIN tax_codes tc ON tc.id = vc.tax_code_id
  WHERE vc.id = v_vat_code_id;

  v_class := COALESCE(v_class, 'exempt');
  v_rate  := COALESCE(v_rate, 0);
  v_kind  := COALESCE(v_txn_type,
                      CASE v_direction WHEN 'sale' THEN 'output_vat' ELSE 'input_vat' END);

  IF v_basis = 'inclusive' AND v_class = 'regular' AND v_rate > 0 THEN
    -- Back the tax out of a tax-inclusive price. The VAT is the residual, so
    -- net + VAT always reconstitutes the quoted price to the centavo.
    v_net   := ROUND(v_amount / (1 + (v_rate / 100)), 2);
    v_vat   := v_amount - v_net;
    v_gross := v_amount;
  ELSE
    v_net   := v_amount;
    v_vat   := CASE WHEN v_class = 'regular' THEN ROUND(v_net * v_rate / 100, 2) ELSE 0 END;
    v_gross := v_net + v_vat;
  END IF;

  v_row := ROW(v_kind, v_vat_code_id, v_tax_code_id, NULL, NULL, NULL, v_class,
               v_net, v_rate, v_vat, v_net, v_gross, v_basis)::public.tax_component;
  RETURN NEXT v_row;

  -- ── Withholding (EWT / CWT at source, or FWT) ────────────────────────────
  -- The ATC version in force ON THE DOCUMENT DATE governs.  A rate that is
  -- inactive, deprecated, superseded or not yet effective does not resolve;
  -- the component is returned with a NULL rate so the caller can raise its own
  -- domain-specific message rather than inherit a generic one.
  IF v_atc_id IS NOT NULL THEN
    SELECT ac.code, ac.description, ac.rate INTO v_atc_code, v_atc_desc, v_atc_rate
    FROM atc_codes ac
    WHERE ac.id = v_atc_id
      AND ac.is_active = true
      AND ac.deprecated_at IS NULL
      AND ac.tax_category = v_atc_category
      AND ac.effective_from <= v_date
      AND (ac.effective_to IS NULL OR ac.effective_to >= v_date);

    v_wht_base   := ROUND(COALESCE(v_wht_base, v_net), 2);
    v_wht_amount := CASE WHEN v_atc_rate IS NULL
                         THEN NULL
                         ELSE ROUND(v_wht_base * v_atc_rate / 100.0, 2) END;

    v_row := ROW(v_atc_category, NULL, NULL, v_atc_id, v_atc_code, v_atc_desc, NULL,
                 v_wht_base, v_atc_rate, v_wht_amount, v_net, v_gross, v_basis)::public.tax_component;
    RETURN NEXT v_row;
  END IF;

  RETURN;
END;
$function$;

COMMENT ON FUNCTION public.fn_calculate_tax(JSONB) IS
  'The Tax Engine. The only function in PXL that turns a governed tax rate into a tax amount (PAD-001, Delivery Plan Phase 4). Percentage tax is deliberately absent: no document reaches it yet, and foundation without a caller is what this repository has already paid for once.';

REVOKE ALL ON FUNCTION public.fn_calculate_tax(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_tax(JSONB) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- The eleven callers. Each keeps every commercial rule, validation, message
-- and side effect it had; only the tax arithmetic moved out.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── fn_save_sales_invoice_aud053_core ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_save_sales_invoice_aud053_core(p_invoice_id uuid, p_header jsonb, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := COALESCE(NULLIF(v_line->>'discount_amount', '')::NUMERIC, 0);
    IF v_disc = 0 AND COALESCE(NULLIF(v_line->>'discount_percent', '')::NUMERIC, 0) > 0 THEN
      v_disc := ROUND(v_qty * v_price * COALESCE((v_line->>'discount_percent')::NUMERIC, 0) / 100, 2);
    END IF;
    v_disc := GREATEST(v_disc, 0);
    v_commercial := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);

    -- VAT comes from the Tax Engine, which owns both price bases (PAD-001).
    -- This routine previously held the product's ONLY VAT-inclusive
    -- implementation; it is now shared by every document type.
    SELECT c.classification, c.net_amount, c.tax_amount, c.gross_amount
      INTO v_vat_class, v_net, v_vat_amt, v_total_line
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',    v_company_id,
           'document_date', v_invoice_date,
           'direction',     'sale',
           'amount',        v_commercial,
           'price_basis',   v_vat_basis,
           'vat_code_id',   NULLIF(v_line->>'vat_code_id', '')
         )) c
    WHERE c.tax_kind IN ('input_vat', 'output_vat');

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

    v_cwt_base := COALESCE(
      NULLIF(p_header->>'cwt_tax_base', '')::NUMERIC,
      ROUND(v_taxable + v_zero_rated + v_exempt, 2)
    );
    IF COALESCE(v_cwt_base, 0) <= 0 THEN
      RAISE EXCEPTION 'Expected CWT taxable base must be positive when expected CWT is recorded';
    END IF;

    -- Expected creditable withholding also comes from the Tax Engine.
    SELECT c.tax_rate, c.tax_amount INTO v_cwt_rate, v_cwt_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           v_invoice_date,
           'direction',               'sale',
           'amount',                  0,
           'withholding_atc_code_id', v_cwt_atc,
           'withholding_base',        v_cwt_base
         )) c
    WHERE c.tax_kind = 'ewt';
    v_cwt_expected := COALESCE(v_cwt_expected, 0);
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
$function$

;

-- ── fn_save_cash_sale ──────────────────────────────────────────
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
  v_has_lines     BOOLEAN := false;
  v_cwt_atc       UUID;
  v_cwt_rate      NUMERIC;
  v_line_no_si    INT := 1;
  v_cash_received NUMERIC(15,2);
  v_net_of_vat    NUMERIC(15,2);
  v_cwt_base      NUMERIC(15,2);
  v_cwt_exclusive_expected NUMERIC(15,2);
  v_cwt_gross_expected     NUMERIC(15,2);
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

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    SELECT c.classification, c.net_amount, c.tax_amount
      INTO v_class, v_net, v_vat_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',    v_company_id,
           'document_date', (p_header->>'date')::DATE,
           'direction',     'sale',
           'amount',        GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0),
           'vat_code_id',   NULLIF(v_line->>'vat_code_id','')
         )) c
    WHERE c.tax_kind IN ('input_vat', 'output_vat');

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

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);
    SELECT c.classification, c.net_amount, c.tax_amount
      INTO v_class, v_net, v_vat_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',    v_company_id,
           'document_date', (p_header->>'date')::DATE,
           'direction',     'sale',
           'amount',        GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0),
           'vat_code_id',   NULLIF(v_line->>'vat_code_id','')
         )) c
    WHERE c.tax_kind IN ('input_vat', 'output_vat');

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
  v_je_si_id := fn_create_posted_journal_entry(
    v_company_id, v_branch_id,
    'JE-SI-' || v_si_number, (p_header->>'date')::DATE,
    'Cash Sale ' || v_si_number || ' — '
      || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id,
    v_fp_id, 'posted', v_grand_total, v_grand_total,
    'system', 'regular', false, false, false
  );

  PERFORM fn_add_posting_line_push(
    v_je_si_id, 1, v_ar,
    'AR — ' || (p_header->>'customer_name_snapshot'),
    v_grand_total, 0, 'control'
  );

  v_rev_line_no := 2;
  FOR v_rev_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_rev_line_no, v_rev_line.revenue_account_id,
      'Revenue — ' || v_rev_line.ln_desc,
      0, v_rev_line.net_sum, 'base'
    );
    v_total_cr    := v_total_cr + v_rev_line.net_sum;
    v_rev_line_no := v_rev_line_no + 1;
  END LOOP;

  IF v_total_vat > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_rev_line_no, v_vat,
      'Output VAT — ' || v_si_number,
      0, v_total_vat, 'tax'
    );
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
    v_net_of_vat := v_grand_total - v_total_vat;

    -- The ATC version in force on the cash-sale date governs, exactly as it
    -- does on every other withholding path. Before PAD-001 this routine read
    -- the rate straight from the master by id, with no active, deprecation or
    -- effective-date filter, so a cash sale could withhold at a superseded
    -- rate. It now asks the Tax Engine like everyone else.
    SELECT c.tax_rate, c.tax_amount INTO v_cwt_rate, v_cwt_exclusive_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           (p_header->>'date')::DATE,
           'direction',               'sale',
           'amount',                  0,
           'withholding_atc_code_id', v_cwt_atc,
           'withholding_base',        v_net_of_vat
         )) c
    WHERE c.tax_kind = 'ewt';

    IF v_cwt_rate IS NULL OR v_cwt_rate <= 0 THEN
      RAISE EXCEPTION 'CWT ATC code is missing, inactive, or has no positive rate.';
    END IF;

    SELECT c.tax_amount INTO v_cwt_gross_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           (p_header->>'date')::DATE,
           'direction',               'sale',
           'amount',                  0,
           'withholding_atc_code_id', v_cwt_atc,
           'withholding_base',        v_grand_total
         )) c
    WHERE c.tax_kind = 'ewt';

    IF ABS(v_cwt_exclusive_expected - p_cwt_amount) <= 0.02 THEN
      v_cwt_base := v_net_of_vat;
    ELSIF ABS(v_cwt_gross_expected - p_cwt_amount) <= 0.02 THEN
      v_cwt_base := v_grand_total;
    ELSE
      RAISE EXCEPTION 'CWT % does not match ATC rate %%% on the VAT-exclusive base % (expected %) or on the gross % (expected %).',
        p_cwt_amount, v_cwt_rate,
        v_net_of_vat, v_cwt_exclusive_expected,
        v_grand_total, v_cwt_gross_expected;
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
  v_je_or_id := fn_create_posted_journal_entry(
    v_company_id, v_branch_id,
    'JE-OR-' || v_or_number, (p_header->>'date')::DATE,
    'Cash Receipt ' || v_or_number || ' — '
      || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id,
    v_fp_id, 'posted', v_grand_total, v_grand_total,
    'system', 'regular', false, false, false
  );

  -- DR: Cash / Bank (net of CWT)
  PERFORM fn_add_posting_line_push(
    v_je_or_id, 1, v_cash_acct,
    'Cash received — ' || v_or_number,
    v_cash_received, 0, 'base'
  );

  -- DR: CWT Receivable (tax withheld by customer, to be reclaimed)
  IF p_cwt_amount > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_or_id, 2, v_cwt,
      'CWT receivable — ' || v_or_number,
      p_cwt_amount, 0, 'withholding'
    );
  END IF;

  -- CR: Accounts Receivable (full invoice amount)
  PERFORM fn_add_posting_line_push(
    v_je_or_id, CASE WHEN p_cwt_amount > 0 THEN 3 ELSE 2 END,
    v_ar, 'AR cleared — ' || v_or_number,
    0, v_grand_total, 'control'
  );

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
$function$

;

-- ── fn_save_credit_memo ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_save_credit_memo(p_cm_id uuid, p_header jsonb, p_lines jsonb, p_next_status text DEFAULT 'draft'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_cm_number      TEXT;
  v_current_status TEXT;
  v_effective_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
  v_total_taxable  NUMERIC(15,2) := 0;
  v_total_zero     NUMERIC(15,2) := 0;
  v_total_exempt   NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_next_status NOT IN ('draft','approved','applied','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;

  v_effective_status := CASE WHEN p_next_status = 'applied' THEN 'approved' ELSE p_next_status END;

  IF p_cm_id IS NULL THEN
    v_cm_number := fn_next_document_number(v_company_id, v_branch_id, 'CM');
    INSERT INTO credit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      invoice_id, cm_number, cm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'invoice_id', '')::UUID,
      v_cm_number, (p_header->>'cm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0, 0,
      v_effective_status, auth.uid(), auth.uid()
    ) RETURNING id INTO v_cm_id;
  ELSE
    SELECT id, status INTO v_cm_id, v_current_status
    FROM credit_memos WHERE id = p_cm_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found or access denied'; END IF;
    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','applied','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','applied','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition credit memo from % to %', v_current_status, p_next_status;
    END IF;
    UPDATE credit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      invoice_id = NULLIF(p_header->>'invoice_id', '')::UUID,
      cm_date = (p_header->>'cm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0,
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cm_id;
  END IF;

  DELETE FROM credit_memo_lines WHERE credit_memo_id = v_cm_id;
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    SELECT c.classification, c.net_amount, c.tax_amount
      INTO v_vat_class, v_net, v_vat_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',    v_company_id,
           'document_date', (p_header->>'cm_date')::DATE,
           'direction',     'sale',
           'amount',        GREATEST(ROUND(v_qty * v_price, 2), 0),
           'vat_code_id',   NULLIF(v_line->>'vat_code_id', '')
         )) c
    WHERE c.tax_kind IN ('input_vat', 'output_vat');
    v_total_line := v_net + v_vat_amt;
    v_total_net  := v_total_net + v_net;
    v_total_vat  := v_total_vat + v_vat_amt;
    v_total_amt  := v_total_amt + v_total_line;
    IF    v_vat_class = 'regular'   THEN v_total_taxable := v_total_taxable + v_net;
    ELSIF v_vat_class = 'zero_rated' THEN v_total_zero   := v_total_zero    + v_net;
    ELSE                                  v_total_exempt  := v_total_exempt  + v_net;
    END IF;
    INSERT INTO credit_memo_lines (
      credit_memo_id, company_id, line_number,
      invoice_line_id, item_id, description, quantity, unit_price,
      net_amount, vat_code_id, vat_amount, total_amount, revenue_account_id,
      created_by, updated_by
    ) VALUES (
      v_cm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'invoice_line_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_qty, v_price,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'revenue_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE credit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    total_taxable_amount = v_total_taxable, total_zero_rated_amount = v_total_zero,
    total_exempt_amount = v_total_exempt,
    updated_at = NOW()
  WHERE id = v_cm_id;

  IF p_next_status = 'applied' THEN
    PERFORM fn_post_credit_memo(v_cm_id);
  END IF;
  RETURN v_cm_id;
END;
$function$

;

-- ── fn_save_debit_memo ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_save_debit_memo(p_dm_id uuid, p_header jsonb, p_lines jsonb, p_next_status text DEFAULT 'draft'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_dm_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_dm_number      TEXT;
  v_current_status TEXT;
  v_effective_status TEXT;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_amount         NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_total_net      NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_total_amt      NUMERIC(15,2) := 0;
  v_total_taxable  NUMERIC(15,2) := 0;
  v_total_zero     NUMERIC(15,2) := 0;
  v_total_exempt   NUMERIC(15,2) := 0;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;
  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF p_next_status NOT IN ('draft','approved','paid','cancelled') THEN
    RAISE EXCEPTION 'Invalid status: %', p_next_status;
  END IF;
  v_effective_status := CASE WHEN p_next_status = 'paid' THEN 'approved' ELSE p_next_status END;

  IF p_dm_id IS NULL THEN
    v_dm_number := fn_next_document_number(v_company_id, v_branch_id, 'DM-S');
    INSERT INTO debit_memos (
      company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
      source_doc_type, source_doc_id, dm_number, dm_date, reason_code_id, remarks,
      total_net_amount, total_vat_amount, total_amount,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id,
      (p_header->>'customer_id')::UUID, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'source_doc_type', ''),
      NULLIF(p_header->>'source_doc_id', '')::UUID,
      v_dm_number, (p_header->>'dm_date')::DATE,
      (p_header->>'reason_code_id')::UUID,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0, 0,
      v_effective_status, auth.uid(), auth.uid()
    ) RETURNING id INTO v_dm_id;
  ELSE
    SELECT id, status INTO v_dm_id, v_current_status
    FROM debit_memos WHERE id = p_dm_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found or access denied'; END IF;
    IF NOT (
      (v_current_status = 'draft'    AND p_next_status IN ('draft','approved','paid','cancelled')) OR
      (v_current_status = 'approved' AND p_next_status IN ('draft','paid','cancelled'))
    ) THEN
      RAISE EXCEPTION 'Cannot transition debit memo from % to %', v_current_status, p_next_status;
    END IF;
    UPDATE debit_memos SET
      branch_id = v_branch_id,
      customer_id = (p_header->>'customer_id')::UUID,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      source_doc_type = NULLIF(p_header->>'source_doc_type', ''),
      source_doc_id = NULLIF(p_header->>'source_doc_id', '')::UUID,
      dm_date = (p_header->>'dm_date')::DATE,
      reason_code_id = (p_header->>'reason_code_id')::UUID,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_net_amount = 0, total_vat_amount = 0, total_amount = 0,
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      status = v_effective_status,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_dm_id;
  END IF;

  DELETE FROM debit_memo_lines WHERE debit_memo_id = v_dm_id;
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    SELECT c.classification, c.net_amount, c.tax_amount
      INTO v_vat_class, v_amount, v_vat_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',    v_company_id,
           'document_date', (p_header->>'dm_date')::DATE,
           'direction',     'sale',
           'amount',        GREATEST(COALESCE((v_line->>'amount')::NUMERIC, 0), 0),
           'vat_code_id',   NULLIF(v_line->>'vat_code_id', '')
         )) c
    WHERE c.tax_kind IN ('input_vat', 'output_vat');
    v_total_line := v_amount + v_vat_amt;
    v_total_net  := v_total_net + v_amount;
    v_total_vat  := v_total_vat + v_vat_amt;
    v_total_amt  := v_total_amt + v_total_line;
    IF    v_vat_class = 'regular'    THEN v_total_taxable := v_total_taxable + v_amount;
    ELSIF v_vat_class = 'zero_rated' THEN v_total_zero   := v_total_zero    + v_amount;
    ELSE                                  v_total_exempt  := v_total_exempt  + v_amount;
    END IF;
    INSERT INTO debit_memo_lines (
      debit_memo_id, company_id, line_number,
      account_id, item_id, description, amount,
      vat_code_id, vat_amount, total_amount,
      created_by, updated_by
    ) VALUES (
      v_dm_id, v_company_id, v_line_no,
      NULLIF(v_line->>'account_id', '')::UUID, NULLIF(v_line->>'item_id', '')::UUID,
      v_line->>'description', v_amount,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  UPDATE debit_memos SET
    total_net_amount = v_total_net, total_vat_amount = v_total_vat, total_amount = v_total_amt,
    total_taxable_amount = v_total_taxable, total_zero_rated_amount = v_total_zero,
    total_exempt_amount = v_total_exempt,
    updated_at = NOW()
  WHERE id = v_dm_id;

  IF p_next_status = 'paid' THEN
    PERFORM fn_post_debit_memo(v_dm_id);
  END IF;
  RETURN v_dm_id;
END;
$function$

;

-- ── fn_save_vendor_bill_core_20260718 ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_save_vendor_bill_core_20260718(p_bill_id uuid, p_header jsonb, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
  v_document_date  DATE;
  v_line           JSONB;
  v_vat_class      TEXT;
  v_tax            public.tax_component;
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
  v_total_ewt      NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
  v_ewt_policy     TEXT;
  v_supplier_ewt   BOOLEAN := false;
  v_supplier_atc   UUID;
  v_line_ewt_atc   UUID;
  v_line_ewt_base  NUMERIC(15,2);
  v_line_ewt_amt   NUMERIC(15,2);
  v_line_ewt_rate  NUMERIC(8,4);
  v_line_ewt_desc  TEXT;
  v_line_ewt_nature TEXT;
  v_line_ewt_reason TEXT;
BEGIN
  v_company_id    := (p_header->>'company_id')::UUID;
  v_branch_id     := NULLIF(p_header->>'branch_id', '')::UUID;
  v_supplier_id   := NULLIF(p_header->>'supplier_id', '')::UUID;
  v_rr_id         := NULLIF(BTRIM(p_header->>'rr_id'), '')::UUID;
  v_document_date := (p_header->>'bill_date')::DATE;
  v_ewt_policy    := fn_company_ap_ewt_policy(v_company_id);

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  SELECT COALESCE(s.is_subject_to_ewt, false), s.default_atc_code_id
  INTO v_supplier_ewt, v_supplier_atc
  FROM suppliers s
  WHERE s.id = v_supplier_id
    AND s.company_id = v_company_id;

  IF NOT FOUND THEN
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
    AND start_date <= v_document_date
    AND end_date >= v_document_date
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
      v_document_date, NULLIF(p_header->>'due_date', '')::DATE,
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
      bill_date = v_document_date,
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

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := GREATEST(COALESCE((v_line->>'discount_amount')::NUMERIC, 0), 0);

    v_line_ewt_atc := NULL;
    v_line_ewt_base := NULL;
    v_line_ewt_amt := 0;
    v_line_ewt_rate := NULL;
    v_line_ewt_desc := NULL;
    v_line_ewt_nature := NULL;
    v_line_ewt_reason := NULL;

    IF v_ewt_policy = 'accrual_at_source' THEN
      v_line_ewt_atc := COALESCE(
        NULLIF(BTRIM(v_line->>'ewt_atc_code_id'), '')::UUID,
        CASE WHEN v_supplier_ewt THEN v_supplier_atc ELSE NULL END
      );
      v_line_ewt_base := NULLIF(BTRIM(v_line->>'ewt_tax_base'), '')::NUMERIC;
      v_line_ewt_amt := COALESCE(NULLIF(BTRIM(v_line->>'ewt_amount'), '')::NUMERIC, 0);
      v_line_ewt_nature := NULLIF(BTRIM(v_line->>'ewt_income_nature'), '');
      v_line_ewt_reason := NULLIF(BTRIM(v_line->>'ewt_variance_reason'), '');
    END IF;

    -- Every tax on this line comes from the Tax Engine. This routine no longer
    -- knows what a VAT rate or an ATC rate is (PAD-001).
    FOR v_tax IN
      SELECT * FROM fn_calculate_tax(jsonb_build_object(
        'company_id',              v_company_id,
        'document_date',           v_document_date,
        'direction',               'purchase',
        'amount',                  GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0),
        'vat_code_id',             NULLIF(v_line->>'vat_code_id', ''),
        'withholding_atc_code_id', v_line_ewt_atc,
        'withholding_base',        v_line_ewt_base
      ))
    LOOP
      IF v_tax.tax_kind IN ('input_vat', 'output_vat') THEN
        v_vat_class := v_tax.classification;
        v_net       := v_tax.net_amount;
        v_vat_amt   := v_tax.tax_amount;
      ELSE
        v_line_ewt_rate := v_tax.tax_rate;
        v_line_ewt_desc := v_tax.atc_description;

        IF v_line_ewt_rate IS NULL THEN
          RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on vendor bill date %. ', v_document_date;
        END IF;

        v_line_ewt_base := v_tax.tax_base;
        IF (NOT (v_line ? 'ewt_amount')) OR NULLIF(BTRIM(v_line->>'ewt_amount'), '') IS NULL THEN
          v_line_ewt_amt := v_tax.tax_amount;
        END IF;
        v_line_ewt_nature := COALESCE(
          v_line_ewt_nature,
          NULLIF(BTRIM(v_line->>'description'), ''),
          v_line_ewt_desc
        );
      END IF;
    END LOOP;
    v_total_line := v_net + v_vat_amt;

    IF v_ewt_policy = 'accrual_at_source' THEN
      IF v_line_ewt_atc IS NOT NULL
         OR COALESCE(v_line_ewt_base, 0) > 0
         OR COALESCE(v_line_ewt_amt, 0) > 0 THEN
        PERFORM fn_validate_payment_voucher_line_ewt(
          v_company_id,
          0,
          v_line_ewt_amt,
          v_line_ewt_atc,
          v_line_ewt_base,
          v_line_ewt_reason,
          v_document_date
        );
      END IF;
    END IF;

    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt + v_net;
    END CASE;
    v_total_vat   := v_total_vat + v_vat_amt;
    v_grand_total := v_grand_total + v_total_line;
    v_total_ewt   := v_total_ewt + COALESCE(v_line_ewt_amt, 0);
    v_has_lines   := true;

    INSERT INTO vendor_bill_lines (
      vendor_bill_id, company_id, line_number, item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, input_vat_amount, total_amount,
      expense_account_id, ewt_atc_code_id, ewt_tax_base, ewt_amount,
      ewt_income_nature, ewt_variance_reason, created_by, updated_by
    ) VALUES (
      v_bill_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0), v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      v_line_ewt_atc, v_line_ewt_base, COALESCE(v_line_ewt_amt, 0),
      v_line_ewt_nature, v_line_ewt_reason,
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
    ewt_amount_expected = CASE
      WHEN v_ewt_policy = 'accrual_at_source' THEN ROUND(v_total_ewt, 2)
      ELSE ewt_amount_expected
    END,
    updated_at = NOW()
  WHERE id = v_bill_id;

  RETURN v_bill_id;
END;
$function$

;

-- ── fn_save_cash_purchase_core_20260718 ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_save_cash_purchase_core_20260718(p_cp_id uuid, p_header jsonb, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cp_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_cp_number    TEXT;
  v_cur_status   TEXT;
  v_fiscal_period UUID;
  v_doc_date     DATE;
  v_supplier_id  UUID;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_vat_class    TEXT;
  v_tax          public.tax_component;
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_net          NUMERIC(15,2);
  v_vat_amt      NUMERIC(15,2);
  v_line_gross   NUMERIC(15,2);
  v_line_cash    NUMERIC(15,2);
  v_ewt_atc_id   UUID;
  v_ewt_base     NUMERIC(15,2);
  v_ewt_amt      NUMERIC(15,2);
  v_ewt_rate     NUMERIC(8,4);
  v_ewt_nature   TEXT;
  v_ewt_reason   TEXT;
  v_taxable      NUMERIC(15,2) := 0;
  v_zero_rated   NUMERIC(15,2) := 0;
  v_exempt       NUMERIC(15,2) := 0;
  v_total_vat    NUMERIC(15,2) := 0;
  v_gross_total  NUMERIC(15,2) := 0;
  v_total_ewt    NUMERIC(15,2) := 0;
  v_cash_total   NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;
  v_doc_date   := (p_header->>'transaction_date')::DATE;
  v_supplier_id := NULLIF(p_header->>'supplier_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= v_doc_date
    AND end_date   >= v_doc_date
    AND is_locked = false LIMIT 1;

  IF p_cp_id IS NULL THEN
    v_cp_number := fn_next_document_number(v_company_id, v_branch_id, 'CP');
    INSERT INTO cash_purchases (
      company_id, branch_id, cp_number, transaction_date,
      supplier_id, supplier_name_snapshot, supplier_tin_snapshot,
      payment_account_id, payment_method, reference_number,
      fiscal_period_id, remarks, total_taxable_amount, total_zero_rated_amount,
      total_exempt_amount, total_input_vat_amount, total_ewt_amount, total_amount,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_cp_number, v_doc_date,
      v_supplier_id,
      NULLIF(p_header->>'supplier_name_snapshot', ''),
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'payment_account_id', '')::UUID,
      COALESCE(NULLIF(p_header->>'payment_method', ''), 'cash'),
      NULLIF(p_header->>'reference_number', ''),
      v_fiscal_period,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0, 0, 0,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_cp_id;
  ELSE
    SELECT id, status INTO v_cp_id, v_cur_status
    FROM cash_purchases WHERE id = p_cp_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash purchase not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % cash purchase', v_cur_status; END IF;
    UPDATE cash_purchases SET
      transaction_date = v_doc_date,
      supplier_id = v_supplier_id,
      supplier_name_snapshot = NULLIF(p_header->>'supplier_name_snapshot', ''),
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      payment_account_id = NULLIF(p_header->>'payment_account_id', '')::UUID,
      payment_method = COALESCE(NULLIF(p_header->>'payment_method', ''), 'cash'),
      reference_number = NULLIF(p_header->>'reference_number', ''),
      fiscal_period_id = v_fiscal_period,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_taxable_amount = 0, total_zero_rated_amount = 0,
      total_exempt_amount = 0, total_input_vat_amount = 0,
      total_ewt_amount = 0, total_amount = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_cp_id;
  END IF;

  DELETE FROM cash_purchase_lines WHERE cp_id = v_cp_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    v_qty   := GREATEST(COALESCE(NULLIF(v_line->>'quantity', '')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE(NULLIF(v_line->>'unit_price', '')::NUMERIC, 0), 0);

    v_ewt_atc_id := COALESCE(
      NULLIF(v_line->>'ewt_atc_code_id', '')::UUID,
      NULLIF(v_line->>'atc_code_id', '')::UUID
    );
    v_ewt_base := NULLIF(v_line->>'ewt_tax_base', '')::NUMERIC;
    v_ewt_amt := COALESCE(NULLIF(v_line->>'ewt_amount', '')::NUMERIC, 0);
    v_ewt_nature := NULLIF(v_line->>'ewt_income_nature', '');
    v_ewt_reason := NULLIF(v_line->>'ewt_variance_reason', '');

    -- Every tax on this line comes from the Tax Engine (PAD-001).
    FOR v_tax IN
      SELECT * FROM fn_calculate_tax(jsonb_build_object(
        'company_id',              v_company_id,
        'document_date',           v_doc_date,
        'direction',               'purchase',
        'amount',                  GREATEST(ROUND(v_qty * v_price, 2), 0),
        'vat_code_id',             NULLIF(v_line->>'vat_code_id', ''),
        'withholding_atc_code_id', v_ewt_atc_id,
        'withholding_base',        v_ewt_base
      ))
    LOOP
      IF v_tax.tax_kind IN ('input_vat', 'output_vat') THEN
        v_vat_class  := v_tax.classification;
        v_net        := v_tax.net_amount;
        v_vat_amt    := v_tax.tax_amount;
        v_line_gross := v_tax.gross_amount;
      ELSE
        v_ewt_base := v_tax.tax_base;
        v_ewt_rate := v_tax.tax_rate;
        IF COALESCE(v_ewt_amt, 0) = 0 AND COALESCE(v_ewt_base, 0) > 0 THEN
          IF v_ewt_rate IS NULL THEN
            RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on cash purchase date %.',
              v_doc_date;
          END IF;
          v_ewt_amt := v_tax.tax_amount;
        END IF;
      END IF;
    END LOOP;

    IF v_ewt_atc_id IS NOT NULL OR v_ewt_base IS NOT NULL OR v_ewt_amt > 0 THEN
      PERFORM fn_require_company_ewt_payable_enabled(v_company_id, 'Cash purchase');
      PERFORM fn_validate_payment_voucher_line_ewt(
        v_company_id,
        ROUND(v_line_gross - v_ewt_amt, 2),
        v_ewt_amt,
        v_ewt_atc_id,
        v_ewt_base,
        v_ewt_reason,
        v_doc_date
      );
    END IF;

    IF v_ewt_amt > v_line_gross + 0.02 THEN
      RAISE EXCEPTION 'Cash purchase line EWT % exceeds gross line amount %.',
        v_ewt_amt, v_line_gross;
    END IF;
    v_line_cash := ROUND(v_line_gross - v_ewt_amt, 2);

    CASE v_vat_class
      WHEN 'regular'    THEN v_taxable    := v_taxable    + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE                   v_exempt     := v_exempt     + v_net;
    END CASE;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_gross_total := v_gross_total + v_line_gross;
    v_total_ewt   := v_total_ewt   + v_ewt_amt;
    v_cash_total  := v_cash_total  + v_line_cash;
    INSERT INTO cash_purchase_lines (
      cp_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, net_amount,
      vat_code_id, input_vat_amount, total_amount,
      expense_account_id, ewt_atc_code_id, ewt_tax_base, ewt_amount,
      ewt_income_nature, ewt_variance_reason, created_by, updated_by
    ) VALUES (
      v_cp_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price, v_net,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_line_cash,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      v_ewt_atc_id, v_ewt_base, v_ewt_amt, v_ewt_nature, v_ewt_reason,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  IF v_total_ewt > 0 AND v_supplier_id IS NULL THEN
    RAISE EXCEPTION 'Supplier is required when cash purchase EWT is recorded.';
  END IF;

  UPDATE cash_purchases SET
    total_taxable_amount = v_taxable, total_zero_rated_amount = v_zero_rated,
    total_exempt_amount = v_exempt, total_input_vat_amount = v_total_vat,
    total_ewt_amount = v_total_ewt, total_amount = v_cash_total, updated_at = NOW()
  WHERE id = v_cp_id;

  PERFORM fn_validate_cash_purchase_ewt_ready(v_cp_id);
  RETURN v_cp_id;
END;
$function$

;

-- ── fn_save_vendor_credit ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_save_vendor_credit(p_vc_id uuid, p_header jsonb, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_vc_id        UUID;
  v_company_id   UUID;
  v_branch_id    UUID;
  v_vc_number    TEXT;
  v_cur_status   TEXT;
  v_fiscal_period UUID;
  v_line         JSONB;
  v_line_no      INT := 1;
  v_vat_class    TEXT;
  v_qty          NUMERIC(15,4);
  v_price        NUMERIC(15,4);
  v_net          NUMERIC(15,2);
  v_vat_amt      NUMERIC(15,2);
  v_taxable      NUMERIC(15,2) := 0;
  v_total_vat    NUMERIC(15,2) := 0;
  v_grand_total  NUMERIC(15,2) := 0;
  v_has_lines    BOOLEAN := false;
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := NULLIF(p_header->>'branch_id', '')::UUID;

  IF NOT is_company_member(v_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF NOT EXISTS (SELECT 1 FROM suppliers WHERE id = (p_header->>'supplier_id')::UUID AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= (p_header->>'credit_date')::DATE
    AND end_date   >= (p_header->>'credit_date')::DATE
    AND is_locked = false LIMIT 1;

  IF p_vc_id IS NULL THEN
    v_vc_number := fn_next_document_number(v_company_id, v_branch_id, 'VC');
    INSERT INTO vendor_credits (
      company_id, branch_id, vc_number, credit_date, supplier_id,
      supplier_name_snapshot, supplier_tin_snapshot, supplier_cm_no,
      reference_bill_id, fiscal_period_id, remarks,
      total_taxable_amount, total_input_vat_amount, total_amount, remaining_balance,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_vc_number,
      (p_header->>'credit_date')::DATE,
      (p_header->>'supplier_id')::UUID,
      p_header->>'supplier_name_snapshot',
      NULLIF(p_header->>'supplier_tin_snapshot', ''),
      NULLIF(p_header->>'supplier_cm_no', ''),
      NULLIF(p_header->>'reference_bill_id', '')::UUID,
      v_fiscal_period,
      NULLIF(p_header->>'remarks', ''),
      0, 0, 0, 0,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_vc_id;
  ELSE
    SELECT id, status INTO v_vc_id, v_cur_status
    FROM vendor_credits WHERE id = p_vc_id AND company_id = v_company_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vendor credit not found'; END IF;
    IF v_cur_status != 'draft' THEN RAISE EXCEPTION 'Cannot edit a % vendor credit', v_cur_status; END IF;
    UPDATE vendor_credits SET
      credit_date = (p_header->>'credit_date')::DATE,
      supplier_id = (p_header->>'supplier_id')::UUID,
      supplier_name_snapshot = p_header->>'supplier_name_snapshot',
      supplier_tin_snapshot = NULLIF(p_header->>'supplier_tin_snapshot', ''),
      supplier_cm_no = NULLIF(p_header->>'supplier_cm_no', ''),
      reference_bill_id = NULLIF(p_header->>'reference_bill_id', '')::UUID,
      fiscal_period_id = v_fiscal_period,
      remarks = NULLIF(p_header->>'remarks', ''),
      total_taxable_amount = 0, total_input_vat_amount = 0,
      total_amount = 0, remaining_balance = 0,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_vc_id;
  END IF;

  DELETE FROM vendor_credit_lines WHERE vc_id = v_vc_id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;
    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    SELECT c.classification, c.net_amount, c.tax_amount
      INTO v_vat_class, v_net, v_vat_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',    v_company_id,
           'document_date', (p_header->>'credit_date')::DATE,
           'direction',     'purchase',
           'amount',        GREATEST(ROUND(v_qty * v_price, 2), 0),
           'vat_code_id',   NULLIF(v_line->>'vat_code_id', '')
         )) c
    WHERE c.tax_kind IN ('input_vat', 'output_vat');
    IF v_vat_class = 'regular' THEN v_taxable := v_taxable + v_net; END IF;
    v_total_vat   := v_total_vat   + v_vat_amt;
    v_grand_total := v_grand_total + v_net + v_vat_amt;
    INSERT INTO vendor_credit_lines (
      vc_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, net_amount,
      vat_code_id, input_vat_amount, total_amount,
      expense_account_id, created_by, updated_by
    ) VALUES (
      v_vc_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID, v_price, v_net,
      NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_net + v_vat_amt,
      NULLIF(v_line->>'expense_account_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
    v_has_lines := true;
  END LOOP;
  IF NOT v_has_lines THEN RAISE EXCEPTION 'At least one line is required'; END IF;
  UPDATE vendor_credits SET
    total_taxable_amount = v_taxable, total_input_vat_amount = v_total_vat,
    total_amount = v_grand_total, remaining_balance = v_grand_total,
    updated_at = NOW()
  WHERE id = v_vc_id;
  RETURN v_vc_id;
END;
$function$

;

-- ── fn_validate_payment_voucher_line_ewt ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_validate_payment_voucher_line_ewt(p_company_id uuid, p_payment_amount numeric, p_ewt_amount numeric, p_atc_code_id uuid, p_ewt_tax_base numeric DEFAULT NULL::numeric, p_ewt_variance_reason text DEFAULT NULL::text, p_document_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rate     NUMERIC(8,4);
  v_code     TEXT;
  v_expected NUMERIC(15,2);
  v_base     NUMERIC(15,2);
  v_reason   TEXT;
  v_as_of    DATE := COALESCE(p_document_date, CURRENT_DATE);
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_ewt_amount, 0) < 0 OR COALESCE(p_ewt_tax_base, 0) < 0 THEN
    RAISE EXCEPTION 'Payment, EWT, and EWT taxable base cannot be negative.';
  END IF;

  IF COALESCE(p_ewt_amount, 0) = 0 AND COALESCE(p_ewt_tax_base, 0) = 0 THEN
    RETURN;
  END IF;

  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when EWT amount or taxable base is specified.';
  END IF;

  -- The base is a commercial figure this validator owns; the RATE and the
  -- EXPECTED amount come from the Tax Engine, which is the only place in PXL
  -- that turns a governed rate into a tax amount (PAD-001).
  v_base := ROUND(COALESCE(p_ewt_tax_base, p_payment_amount + p_ewt_amount, 0), 2);

  SELECT c.atc_code, c.tax_rate, c.tax_amount INTO v_code, v_rate, v_expected
  FROM fn_calculate_tax(jsonb_build_object(
         'company_id',              p_company_id,
         'document_date',           v_as_of,
         'direction',               'purchase',
         'amount',                  0,
         'withholding_atc_code_id', p_atc_code_id,
         'withholding_base',        v_base
       )) c
  WHERE c.tax_kind = 'ewt';

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on document date %.', v_as_of;
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive EWT rate.', v_code;
  END IF;

  IF v_base <= 0 THEN
    RAISE EXCEPTION 'EWT taxable base is required when EWT is withheld.';
  END IF;
  IF ABS(v_expected - COALESCE(p_ewt_amount, 0)) <= 0.02 THEN
    RETURN;
  END IF;

  v_reason := NULLIF(BTRIM(COALESCE(p_ewt_variance_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'EWT amount % does not match ATC % rate %%% on taxable base %. Expected EWT is %. Select a variance reason to proceed.',
      p_ewt_amount, v_code, v_rate, v_base, v_expected;
  END IF;

  IF v_reason NOT IN ('rounding', 'partial_non_taxable', 'bir_ruling', 'supplier_exempt', 'other_authorized') THEN
    RAISE EXCEPTION 'Invalid EWT variance reason: %', v_reason;
  END IF;
END;
$function$

;

-- ── fn_validate_receipt_line_cwt ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_validate_receipt_line_cwt(p_company_id uuid, p_payment_amount numeric, p_cwt_amount numeric, p_atc_code_id uuid, p_cwt_tax_base numeric DEFAULT NULL::numeric, p_cwt_variance_reason text DEFAULT NULL::text, p_document_date date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rate     NUMERIC(8,4);
  v_code     TEXT;
  v_base     NUMERIC(15,2);
  v_expected NUMERIC(15,2);
  v_reason   TEXT;
  v_as_of    DATE := COALESCE(p_document_date, CURRENT_DATE);
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_cwt_amount, 0) < 0 OR COALESCE(p_cwt_tax_base, 0) < 0 THEN
    RAISE EXCEPTION 'Payment, CWT, and CWT taxable base cannot be negative.';
  END IF;

  IF COALESCE(p_cwt_amount, 0) = 0 AND COALESCE(p_cwt_tax_base, 0) = 0 THEN
    RETURN;
  END IF;

  IF p_atc_code_id IS NULL THEN
    RAISE EXCEPTION 'ATC code is required when CWT amount or taxable base is specified.';
  END IF;

  -- Explicit base preferred (VAT-exclusive income payment); legacy fallback is
  -- payment + CWT (gross) so pre-existing rows and gross-convention withholding
  -- remain recordable (PXL-AUD-031 semantics preserved). The base is commercial
  -- and owned here; the RATE and EXPECTED amount come from the Tax Engine.
  v_base := ROUND(COALESCE(p_cwt_tax_base, COALESCE(p_payment_amount, 0) + COALESCE(p_cwt_amount, 0)), 2);

  SELECT c.atc_code, c.tax_rate, c.tax_amount INTO v_code, v_rate, v_expected
  FROM fn_calculate_tax(jsonb_build_object(
         'company_id',              p_company_id,
         'document_date',           v_as_of,
         'direction',               'sale',
         'amount',                  0,
         'withholding_atc_code_id', p_atc_code_id,
         'withholding_base',        v_base
       )) c
  WHERE c.tax_kind = 'ewt';

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on document date %.', v_as_of;
  END IF;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RAISE EXCEPTION 'ATC code % must have a positive withholding rate.', v_code;
  END IF;

  IF v_base <= 0 THEN
    RAISE EXCEPTION 'CWT taxable base is required when CWT is recorded.';
  END IF;
  IF ABS(v_expected - COALESCE(p_cwt_amount, 0)) <= 0.02 THEN
    RETURN;
  END IF;

  v_reason := NULLIF(BTRIM(COALESCE(p_cwt_variance_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'CWT amount % does not match ATC % rate %%% on taxable base %. Expected CWT is %. Select a variance reason to proceed.',
      p_cwt_amount, v_code, v_rate, v_base, v_expected;
  END IF;

  IF v_reason NOT IN ('rounding', 'partial_non_taxable', 'bir_ruling', 'supplier_exempt', 'other_authorized') THEN
    RAISE EXCEPTION 'Invalid CWT variance reason: %', v_reason;
  END IF;
END;
$function$

;

-- ── fn_apply_vendor_bill_line_ewt_profile ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_apply_vendor_bill_line_ewt_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_bill_company UUID;
  v_bill_date DATE;
  v_supplier_id UUID;
  v_policy TEXT;
  v_supplier_ewt BOOLEAN := false;
  v_supplier_atc UUID;
  v_has_ewt BOOLEAN;
  v_kind TEXT := 'services';
  v_rate NUMERIC(8,4);
  v_expected NUMERIC(15,2);
  v_description TEXT;
BEGIN
  SELECT vb.company_id, vb.bill_date, vb.supplier_id, fn_company_ap_ewt_policy(vb.company_id)
  INTO v_bill_company, v_bill_date, v_supplier_id, v_policy
  FROM vendor_bills vb
  WHERE vb.id = NEW.vendor_bill_id;

  IF v_bill_company IS NULL THEN
    RAISE EXCEPTION 'Vendor bill not found for EWT validation.';
  END IF;
  IF NEW.company_id IS DISTINCT FROM v_bill_company THEN
    RAISE EXCEPTION 'Vendor bill line company does not match its vendor bill.';
  END IF;

  SELECT COALESCE(s.is_subject_to_ewt, false), s.default_atc_code_id
  INTO v_supplier_ewt, v_supplier_atc
  FROM suppliers s
  WHERE s.id = v_supplier_id
    AND s.company_id = NEW.company_id;

  v_has_ewt := NEW.ewt_atc_code_id IS NOT NULL
            OR NEW.ewt_tax_base IS NOT NULL
            OR COALESCE(NEW.ewt_amount, 0) > 0;

  IF v_policy = 'accrual_at_source'
     AND NOT v_has_ewt
     AND COALESCE(v_supplier_ewt, false) THEN
    IF v_supplier_atc IS NOT NULL THEN
      NEW.ewt_atc_code_id := v_supplier_atc;
    ELSIF fn_company_twa_auto_ewt_enabled(NEW.company_id, v_bill_date) THEN
      SELECT CASE WHEN i.item_type = 'inventory_item' THEN 'goods' ELSE 'services' END
      INTO v_kind
      FROM items i
      WHERE i.id = NEW.item_id
        AND i.company_id = NEW.company_id;

      NEW.ewt_atc_code_id := fn_twa_ewt_atc_asof(COALESCE(v_kind, 'services'), v_bill_date);
    END IF;
  END IF;

  IF NEW.ewt_atc_code_id IS NOT NULL THEN
    NEW.ewt_tax_base := ROUND(COALESCE(NEW.ewt_tax_base, NEW.net_amount, 0), 2);

    SELECT c.tax_rate, c.atc_description, c.tax_amount
    INTO v_rate, v_description, v_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              NEW.company_id,
           'document_date',           v_bill_date,
           'direction',               'purchase',
           'amount',                  0,
           'withholding_atc_code_id', NEW.ewt_atc_code_id,
           'withholding_base',        NEW.ewt_tax_base
         )) c
    WHERE c.tax_kind = 'ewt';

    IF v_rate IS NULL THEN
      RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on vendor bill date %.', v_bill_date;
    END IF;

    IF COALESCE(NEW.ewt_amount, 0) = 0 AND COALESCE(NEW.ewt_tax_base, 0) > 0 THEN
      NEW.ewt_amount := v_expected;
    END IF;
    NEW.ewt_income_nature := COALESCE(
      NULLIF(BTRIM(NEW.ewt_income_nature), ''),
      NULLIF(BTRIM(NEW.description), ''),
      v_description
    );
  END IF;

  v_has_ewt := NEW.ewt_atc_code_id IS NOT NULL
            OR NEW.ewt_tax_base IS NOT NULL
            OR COALESCE(NEW.ewt_amount, 0) > 0;

  IF v_has_ewt THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Vendor bill');

    IF v_policy <> 'accrual_at_source' THEN
      RAISE EXCEPTION 'Vendor bill source EWT is disabled by AP EWT policy %. Use payment voucher EWT instead.',
        v_policy;
    END IF;

    PERFORM fn_validate_payment_voucher_line_ewt(
      NEW.company_id,
      0,
      COALESCE(NEW.ewt_amount, 0),
      NEW.ewt_atc_code_id,
      NEW.ewt_tax_base,
      NEW.ewt_variance_reason,
      v_bill_date
    );
  END IF;

  NEW.ewt_amount := COALESCE(NEW.ewt_amount, 0);
  RETURN NEW;
END;
$function$

;

-- ── fn_apply_cash_purchase_line_ewt_profile ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_apply_cash_purchase_line_ewt_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_document_date DATE;
  v_rate NUMERIC(8,4);
  v_expected NUMERIC(15,2);
  v_description TEXT;
  v_has_ewt BOOLEAN;
  v_gross NUMERIC(15,2);
BEGIN
  SELECT transaction_date
  INTO v_document_date
  FROM cash_purchases
  WHERE id = NEW.cp_id;

  IF v_document_date IS NULL THEN
    RAISE EXCEPTION 'Cash purchase header is required before EWT validation.';
  END IF;

  IF NEW.ewt_atc_code_id IS NOT NULL THEN
    NEW.ewt_tax_base := ROUND(COALESCE(NEW.ewt_tax_base, NEW.net_amount, 0), 2);

    SELECT c.tax_rate, c.atc_description, c.tax_amount
    INTO v_rate, v_description, v_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              NEW.company_id,
           'document_date',           v_document_date,
           'direction',               'purchase',
           'amount',                  0,
           'withholding_atc_code_id', NEW.ewt_atc_code_id,
           'withholding_base',        NEW.ewt_tax_base
         )) c
    WHERE c.tax_kind = 'ewt';

    IF v_rate IS NULL THEN
      RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on cash purchase date %.',
        v_document_date;
    END IF;

    IF COALESCE(NEW.ewt_amount, 0) = 0 AND COALESCE(NEW.ewt_tax_base, 0) > 0 THEN
      NEW.ewt_amount := v_expected;
    END IF;
    NEW.ewt_income_nature := COALESCE(
      NULLIF(BTRIM(NEW.ewt_income_nature), ''),
      NULLIF(BTRIM(NEW.description), ''),
      v_description
    );
  END IF;

  NEW.ewt_amount := COALESCE(NEW.ewt_amount, 0);
  v_has_ewt := NEW.ewt_atc_code_id IS NOT NULL
            OR NEW.ewt_tax_base IS NOT NULL
            OR NEW.ewt_amount > 0;

  IF v_has_ewt THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Cash purchase');

    PERFORM fn_validate_payment_voucher_line_ewt(
      NEW.company_id,
      ROUND(COALESCE(NEW.net_amount, 0) + COALESCE(NEW.input_vat_amount, 0) - NEW.ewt_amount, 2),
      NEW.ewt_amount,
      NEW.ewt_atc_code_id,
      NEW.ewt_tax_base,
      NEW.ewt_variance_reason,
      v_document_date
    );
  END IF;

  v_gross := ROUND(COALESCE(NEW.net_amount, 0) + COALESCE(NEW.input_vat_amount, 0), 2);
  IF NEW.ewt_amount > v_gross + 0.02 THEN
    RAISE EXCEPTION 'Cash purchase line EWT % exceeds gross line amount %.',
      NEW.ewt_amount, v_gross;
  END IF;
  NEW.total_amount := ROUND(v_gross - NEW.ewt_amount, 2);

  RETURN NEW;
END;
$function$

;

