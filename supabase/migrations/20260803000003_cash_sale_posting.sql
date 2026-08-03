-- ═══════════════════════════════════════════════════════════════════════════
-- Delivery Plan Phase 5 item 3 — Cash Sale posting.
--
-- THE GAP
--   `fn_save_cash_sale` created a cash-sale Sales Invoice and its Official
--   Receipt, posted both journals, and wrote the VAT and CWT ledger rows — but
--   it never touched inventory. A cash sale of an inventory item credited
--   revenue and left the stock on the books: no COGS, no inventory relief, no
--   `inventory_transactions` row. Sales Invoice has done all three since
--   PXL-AUD-053; Cash Sale, the counter-sale path a retail pilot actually uses,
--   did not. That is the outbound entry point this migration closes.
--
--   Its line model was also thinner than the document needs. A cash-sale line
--   carried an item, a description, a quantity, a price and a VAT code. It
--   could not name a warehouse (so inventory could not be relieved from
--   anywhere), could not carry a dimension, could not be priced VAT-inclusive
--   even though `sales_invoices.vat_price_basis` existed for exactly that, and
--   could not carry its own withholding tax code — withholding was one ATC and
--   one amount for the whole document.
--
-- WHAT THIS CHANGES
--   1. Business Tax and Withholding Tax are BOTH per line. One counter sale of
--      goods withheld under WC158 and services withheld under WC160 is now a
--      single document with two correctly-withheld lines, and the tax ledger
--      carries one `cwt_receivable` row per ATC — which is what a 2307 and a
--      1601-EQ are assembled from.
--   2. Cash Sale relieves inventory and posts COGS through the same costing
--      path as `fn_post_sales_invoice`: weighted-average or FIFO layers,
--      stock-balance update, `inventory_transactions` issue row, and the line's
--      resolved unit cost written back.
--   3. VAT-inclusive pricing works, because the line asks the Tax Engine with
--      the document's `vat_price_basis` instead of assuming exclusive.
--   4. Lines carry warehouse, department, cost center, salesperson and account
--      overrides, so the Lines workspace can encode a line without the user
--      leaving the tab.
--
--   Every existing caller keeps working. A cash sale whose lines carry no
--   withholding ATC still uses the header `cwt_atc_id` + `p_cwt_amount`
--   convention, with the same VAT-exclusive-or-gross base reconciliation and
--   the same messages.
--
-- WHAT THIS DOES NOT CHANGE
--   No tax arithmetic moves: `fn_calculate_tax` remains the only function that
--   turns a rate into an amount, and this file performs none. Percentage tax is
--   still calculated nowhere — a PT cash sale needs a PT liability posting line
--   and a filing artifact, and that chain ships whole or not at all.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Withholding becomes a line-level fact ───────────────────────────────
-- The document header keeps `cwt_amount_expected` / `cwt_atc_code_id` /
-- `cwt_tax_base` as the single-ATC summary it always was. These columns carry
-- the itemised truth when a document mixes treatments.
ALTER TABLE sales_invoice_lines
  ADD COLUMN IF NOT EXISTS withholding_atc_code_id UUID REFERENCES atc_codes(id),
  ADD COLUMN IF NOT EXISTS withholding_tax_base NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS withholding_tax_rate NUMERIC(9,4),
  ADD COLUMN IF NOT EXISTS withholding_tax_amount NUMERIC(15,2);

CREATE INDEX IF NOT EXISTS idx_sil_withholding_atc
  ON sales_invoice_lines (company_id, withholding_atc_code_id)
  WHERE withholding_atc_code_id IS NOT NULL;

COMMENT ON COLUMN sales_invoice_lines.withholding_atc_code_id IS
  'The withholding tax code the user selected for THIS line. A document may mix goods and services withheld under different ATCs; the header summary cannot express that.';
COMMENT ON COLUMN sales_invoice_lines.withholding_tax_base IS
  'System-derived: the VAT-exclusive base the Tax Engine withheld on for this line.';
COMMENT ON COLUMN sales_invoice_lines.withholding_tax_rate IS
  'System-derived: the rate of the exact ATC version the Tax Engine resolved on the document date. Stamped so the posted line explains itself without re-resolving configuration — and so the posting layer never has to read the ATC master.';
COMMENT ON COLUMN sales_invoice_lines.withholding_tax_amount IS
  'System-derived by fn_calculate_tax from the ATC version in force on the document date. Never user-entered.';

-- ── 2. A receipt line may settle line-itemised withholding ─────────────────
-- `receipt_lines` is UNIQUE (receipt_id, invoice_id): one settlement row per
-- invoice, so a single row cannot name two ATCs. Rather than weaken the
-- settlement key, the row declares WHERE its withholding detail lives. With
-- 'atc' (the default, and every pre-existing row) nothing changes: one ATC,
-- validated against its own governed rate. With 'invoice_lines' the amount is
-- validated against the sum the Tax Engine already computed on the invoice's
-- lines, and naming a single ATC is refused as misleading.
ALTER TABLE receipt_lines
  ADD COLUMN IF NOT EXISTS cwt_source TEXT NOT NULL DEFAULT 'atc';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'receipt_lines_cwt_source_chk'
      AND conrelid = 'public.receipt_lines'::regclass
  ) THEN
    ALTER TABLE receipt_lines ADD CONSTRAINT receipt_lines_cwt_source_chk
      CHECK (cwt_source IN ('atc', 'invoice_lines'));
  END IF;
END $$;

COMMENT ON COLUMN receipt_lines.cwt_source IS
  'Where this line''s withholding detail lives: ''atc'' (one ATC on the line, the default) or ''invoice_lines'' (itemised per line on the settled invoice, because the document mixes ATCs).';

-- ── 3. The CWT validator learns the second source ──────────────────────────
DROP FUNCTION IF EXISTS public.fn_validate_receipt_line_cwt(
  UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT, DATE);

CREATE OR REPLACE FUNCTION public.fn_validate_receipt_line_cwt(
  p_company_id          UUID,
  p_payment_amount      NUMERIC,
  p_cwt_amount          NUMERIC,
  p_atc_code_id         UUID,
  p_cwt_tax_base        NUMERIC DEFAULT NULL,
  p_cwt_variance_reason TEXT    DEFAULT NULL,
  p_document_date       DATE    DEFAULT NULL,
  p_cwt_source          TEXT    DEFAULT 'atc',
  p_invoice_id          UUID    DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rate      NUMERIC(8,4);
  v_code      TEXT;
  v_base      NUMERIC(15,2);
  v_expected  NUMERIC(15,2);
  v_reason    TEXT;
  v_as_of     DATE := COALESCE(p_document_date, CURRENT_DATE);
  v_line_cwt  NUMERIC(15,2);
  v_line_base NUMERIC(15,2);
BEGIN
  IF COALESCE(p_payment_amount, 0) < 0 OR COALESCE(p_cwt_amount, 0) < 0 OR COALESCE(p_cwt_tax_base, 0) < 0 THEN
    RAISE EXCEPTION 'Payment, CWT, and CWT taxable base cannot be negative.';
  END IF;

  IF COALESCE(p_cwt_amount, 0) = 0 AND COALESCE(p_cwt_tax_base, 0) = 0 THEN
    RETURN;
  END IF;

  -- ── Line-itemised withholding ────────────────────────────────────────────
  -- The invoice's own lines already hold Tax-Engine-computed withholding per
  -- ATC. The receipt line settles their sum; it does not re-derive a rate,
  -- because there is no single rate to re-derive.
  IF p_cwt_source = 'invoice_lines' THEN
    IF p_invoice_id IS NULL THEN
      RAISE EXCEPTION 'Line-itemised CWT requires the invoice it settles.';
    END IF;
    IF p_atc_code_id IS NOT NULL THEN
      RAISE EXCEPTION 'A line-itemised CWT receipt line must not name a single ATC; the detail is on the invoice lines.';
    END IF;

    SELECT COALESCE(SUM(sil.withholding_tax_amount), 0),
           COALESCE(SUM(sil.withholding_tax_base), 0)
      INTO v_line_cwt, v_line_base
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = p_invoice_id
      AND sil.withholding_atc_code_id IS NOT NULL;

    IF v_line_cwt <= 0 THEN
      RAISE EXCEPTION 'No line-level withholding exists on the settled invoice.';
    END IF;
    IF ABS(v_line_cwt - COALESCE(p_cwt_amount, 0)) > 0.02 THEN
      RAISE EXCEPTION 'CWT % does not match the invoice line-level withholding total %.',
        p_cwt_amount, v_line_cwt;
    END IF;
    IF p_cwt_tax_base IS NOT NULL AND ABS(v_line_base - p_cwt_tax_base) > 0.02 THEN
      RAISE EXCEPTION 'CWT taxable base % does not match the invoice line-level withholding base %.',
        p_cwt_tax_base, v_line_base;
    END IF;
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
$function$;

GRANT EXECUTE ON FUNCTION public.fn_validate_receipt_line_cwt(
  UUID, NUMERIC, NUMERIC, UUID, NUMERIC, TEXT, DATE, TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_require_receipt_line_cwt_validation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_document_date DATE;
BEGIN
  SELECT receipt_date INTO v_document_date
  FROM receipts WHERE id = NEW.receipt_id;

  PERFORM fn_validate_receipt_line_cwt(
    NEW.company_id,
    NEW.payment_amount,
    NEW.cwt_amount,
    NEW.atc_code_id,
    NEW.cwt_tax_base,
    NEW.cwt_variance_reason,
    v_document_date,
    NEW.cwt_source,
    NEW.invoice_id
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_receipt_line_cwt_validation ON receipt_lines;
CREATE TRIGGER trg_receipt_line_cwt_validation
  BEFORE INSERT OR UPDATE OF company_id, payment_amount, cwt_amount, atc_code_id,
    cwt_tax_base, cwt_variance_reason, cwt_source, invoice_id
  ON receipt_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_receipt_line_cwt_validation();

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Cash Sale
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_save_cash_sale(
  p_header jsonb, p_lines jsonb, p_cwt_amount numeric DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id    UUID;
  v_branch_id     UUID;
  v_date          DATE;
  v_basis         TEXT;
  v_hdr_warehouse UUID;
  v_hdr_dept      UUID;
  v_hdr_cc        UUID;
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
  v_total_cogs    NUMERIC(15,2) := 0;
  v_line_cwt      NUMERIC(15,2) := 0;
  v_line_cwt_base NUMERIC(15,2) := 0;
  v_cwt_total     NUMERIC(15,2) := 0;
  v_cwt_source    TEXT := 'atc';
  v_rev_line      RECORD;
  v_inv_line      RECORD;
  v_line_no       INT;
  v_line          JSONB;
  v_item          items%ROWTYPE;
  v_qty           NUMERIC(15,4);
  v_price         NUMERIC(15,4);
  v_disc          NUMERIC(15,2);
  v_commercial    NUMERIC(15,2);
  v_net           NUMERIC(15,2);
  v_vat_amt       NUMERIC(15,2);
  v_class         TEXT;
  v_wht_atc       UUID;
  v_wht_amt       NUMERIC(15,2);
  v_wht_base      NUMERIC(15,2);
  v_wht_rate      NUMERIC(9,4);
  v_has_lines     BOOLEAN := false;
  v_line_warehouse UUID;
  v_line_dept     UUID;
  v_line_cc       UUID;
  v_cwt_atc       UUID;
  v_cwt_rate      NUMERIC;
  v_cash_received NUMERIC(15,2);
  v_net_of_vat    NUMERIC(15,2);
  v_cwt_base      NUMERIC(15,2);
  v_cwt_exclusive_expected NUMERIC(15,2);
  v_cwt_gross_expected     NUMERIC(15,2);
  v_stock         stock_balances%ROWTYPE;
  v_layer         RECORD;
  v_total_cost    NUMERIC(18,2);
  v_unit_cost     NUMERIC(18,6);
  v_inventory_tx_id UUID;
BEGIN
  v_company_id    := (p_header->>'company_id')::UUID;
  v_branch_id     := NULLIF(p_header->>'branch_id','')::UUID;
  v_date          := (p_header->>'date')::DATE;
  v_basis         := LOWER(COALESCE(NULLIF(p_header->>'vat_price_basis',''), 'exclusive'));
  v_hdr_warehouse := NULLIF(p_header->>'warehouse_id','')::UUID;
  v_hdr_dept      := NULLIF(p_header->>'department_id','')::UUID;
  v_hdr_cc        := NULLIF(p_header->>'cost_center_id','')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF v_basis NOT IN ('exclusive', 'inclusive') THEN
    RAISE EXCEPTION 'VAT Price Basis must be VAT Exclusive or VAT Inclusive.';
  END IF;

  -- COA resolver adoption (P2A). AR is always required; cash/CWT/VAT are conditional.
  v_ar := fn_resolve_posting_account(v_company_id, 'AR_TRADE', v_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');

  v_cash_acct := NULLIF(p_header->>'bank_account_id','')::UUID;
  IF v_cash_acct IS NULL THEN
    v_cash_acct := fn_resolve_posting_account(v_company_id, 'CASH_DEFAULT', v_date,
                     'No cash/bank account specified and no default cash account configured.');
  END IF;

  -- CWT requires an ATC (PXL-AUD-007 rules, enforced by the receipt-line
  -- validator); the document-level ATC travels in the header as cwt_atc_id.
  v_cwt_atc := NULLIF(p_header->>'cwt_atc_id','')::UUID;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= v_date
    AND end_date   >= v_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for date %. Create or unlock a fiscal period.', v_date;
  END IF;

  -- Number series
  v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'CS');
  v_or_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

  -- Draft header first: the lines are the source of every total, and the line
  -- guards require the invoice to be a draft while they are written.
  INSERT INTO sales_invoices (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    si_number, date, due_date, currency_code, memo, vat_price_basis,
    department_id, cost_center_id, warehouse_id,
    total_amount, total_vat_amount, total_taxable_amount,
    total_zero_rated_amount, total_exempt_amount,
    is_cash_sale, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot',
    NULLIF(p_header->>'customer_tin_snapshot',''),
    v_si_number, v_date, v_date,
    COALESCE(NULLIF(p_header->>'currency_code',''),'PHP'),
    NULLIF(p_header->>'memo',''), v_basis,
    v_hdr_dept, v_hdr_cc, v_hdr_warehouse,
    0, 0, 0, 0, 0,
    true, 'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_si_id;

  -- ── One pass: the Tax Engine prices each line, the line is written, the
  -- document totals accumulate. UI preview values are never trusted.
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    v_item := NULL;
    IF NULLIF(v_line->>'item_id','') IS NOT NULL THEN
      SELECT * INTO v_item FROM items
      WHERE id = NULLIF(v_line->>'item_id','')::UUID
        AND company_id = v_company_id
        AND COALESCE(is_active, true) = true;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cash sale item does not belong to this company or is inactive';
      END IF;
    END IF;

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := COALESCE(NULLIF(v_line->>'discount_amount','')::NUMERIC, 0);
    IF v_disc = 0 AND COALESCE(NULLIF(v_line->>'discount_percent','')::NUMERIC, 0) > 0 THEN
      v_disc := ROUND(v_qty * v_price * (v_line->>'discount_percent')::NUMERIC / 100, 2);
    END IF;
    v_disc := GREATEST(v_disc, 0);
    v_commercial := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);

    v_wht_atc := NULLIF(v_line->>'withholding_atc_code_id','')::UUID;

    -- Business tax and withholding tax for this line, from the one engine, on
    -- the document date, in the document's price basis.
    SELECT
      MAX(c.classification)  FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.net_amount)      FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.tax_amount)      FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.tax_base)        FILTER (WHERE c.tax_kind = 'ewt'),
      MAX(c.tax_rate)        FILTER (WHERE c.tax_kind = 'ewt'),
      MAX(c.tax_amount)      FILTER (WHERE c.tax_kind = 'ewt')
      INTO v_class, v_net, v_vat_amt, v_wht_base, v_wht_rate, v_wht_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           v_date,
           'direction',               'sale',
           'amount',                  v_commercial,
           'price_basis',             v_basis,
           'vat_code_id',             NULLIF(v_line->>'vat_code_id',''),
           'withholding_atc_code_id', v_wht_atc
         )) c;

    IF v_wht_atc IS NOT NULL AND v_wht_amt IS NULL THEN
      RAISE EXCEPTION 'Line % withholding tax code is inactive, deprecated, or not effective on %.',
        v_line_no, v_date;
    END IF;

    v_line_warehouse := COALESCE(NULLIF(v_line->>'warehouse_id','')::UUID, v_hdr_warehouse);
    v_line_dept      := COALESCE(NULLIF(v_line->>'department_id','')::UUID, v_hdr_dept);
    v_line_cc        := COALESCE(NULLIF(v_line->>'cost_center_id','')::UUID, v_hdr_cc);

    IF v_line_warehouse IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM warehouses WHERE id = v_line_warehouse AND company_id = v_company_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Line warehouse does not belong to this company or is inactive';
    END IF;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, discount_percent, discount_amount, net_amount,
      vat_code_id, vat_amount, total_amount,
      withholding_atc_code_id, withholding_tax_base, withholding_tax_rate, withholding_tax_amount,
      revenue_account_id, inventory_account_id, cogs_account_id,
      warehouse_id, department_id, cost_center_id, salesperson_id, remarks,
      created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id','')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id','')::UUID, v_price,
      COALESCE(NULLIF(v_line->>'discount_percent','')::NUMERIC, 0), v_disc, v_net,
      NULLIF(v_line->>'vat_code_id','')::UUID, v_vat_amt, v_net + v_vat_amt,
      v_wht_atc, v_wht_base, v_wht_rate, v_wht_amt,
      COALESCE(NULLIF(v_line->>'revenue_account_id','')::UUID, v_item.sales_account_id),
      COALESCE(NULLIF(v_line->>'inventory_account_id','')::UUID, v_item.inventory_account_id),
      COALESCE(NULLIF(v_line->>'cogs_account_id','')::UUID, v_item.cogs_account_id),
      v_line_warehouse, v_line_dept, v_line_cc,
      NULLIF(v_line->>'salesperson_id','')::UUID, NULLIF(v_line->>'remarks',''),
      auth.uid(), auth.uid()
    );

    v_grand_total := v_grand_total + v_net + v_vat_amt;
    v_total_vat   := v_total_vat + v_vat_amt;
    CASE v_class
      WHEN 'regular'    THEN v_total_taxable := v_total_taxable + v_net;
      WHEN 'zero_rated' THEN v_total_zero    := v_total_zero + v_net;
      ELSE                   v_total_exempt  := v_total_exempt + v_net;
    END CASE;
    IF v_wht_atc IS NOT NULL THEN
      v_line_cwt      := v_line_cwt + COALESCE(v_wht_amt, 0);
      v_line_cwt_base := v_line_cwt_base + COALESCE(v_wht_base, 0);
    END IF;
    v_has_lines := true;
    v_line_no   := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'Cash sale must have at least one line with a description.';
  END IF;

  -- ── Which withholding convention is this document using? ─────────────────
  IF v_line_cwt > 0 THEN
    v_cwt_source := 'invoice_lines';
    IF COALESCE(p_cwt_amount, 0) > 0
       AND ABS(COALESCE(p_cwt_amount, 0) - v_line_cwt) > 0.02 THEN
      RAISE EXCEPTION 'Cash sale CWT % does not match the line-level withholding total %.',
        p_cwt_amount, v_line_cwt;
    END IF;
    IF v_cwt_atc IS NOT NULL THEN
      RAISE EXCEPTION 'A cash sale whose lines carry withholding tax codes must not also carry a document-level ATC.';
    END IF;
    v_cwt_total := v_line_cwt;
    v_cwt_base  := v_line_cwt_base;
  ELSE
    v_cwt_total := COALESCE(p_cwt_amount, 0);
  END IF;

  -- Output VAT account is required once there is VAT to post.
  IF v_total_vat > 0 THEN
    v_vat := fn_resolve_posting_account(v_company_id, 'VAT_OUTPUT', v_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;
  IF v_cwt_total > 0 THEN
    v_cwt := fn_resolve_posting_account(v_company_id, 'EWT_WITHHELD', v_date,
               'EWT Withheld (CWT Receivable) account not configured. Set it up in GL Posting Configuration.');
  END IF;

  UPDATE sales_invoices SET
    total_amount            = v_grand_total,
    total_vat_amount        = v_total_vat,
    total_taxable_amount    = v_total_taxable,
    total_zero_rated_amount = v_total_zero,
    total_exempt_amount     = v_total_exempt,
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_si_id;

  -- ── Inventory costing, while the invoice is still a draft ────────────────
  -- Same path as fn_post_sales_invoice: lock the balance, cost the issue by the
  -- item's costing method, relieve stock, and write the resolved cost back to
  -- the line. The journal needs the total before it is created, so the costing
  -- runs first and the GL lines follow.
  FOR v_inv_line IN
    SELECT sil.id, sil.line_number, sil.item_id, sil.quantity, sil.warehouse_id,
           sil.description, i.item_code,
           COALESCE(i.costing_method, 'weighted_average') AS costing_method,
           COALESCE(sil.inventory_account_id, i.inventory_account_id) AS inv_acct,
           COALESCE(sil.cogs_account_id, i.cogs_account_id) AS cogs_acct
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    WHERE sil.sales_invoice_id = v_si_id
      AND i.item_type = 'inventory_item'
    ORDER BY sil.line_number
  LOOP
    IF v_inv_line.warehouse_id IS NULL THEN
      RAISE EXCEPTION 'Warehouse is required for inventory item line %', v_inv_line.line_number;
    END IF;
    IF v_inv_line.inv_acct IS NULL OR v_inv_line.cogs_acct IS NULL THEN
      RAISE EXCEPTION 'Inventory and COGS accounts are required for inventory item line %', v_inv_line.line_number;
    END IF;

    PERFORM fn_ensure_stock_balance(v_company_id, v_inv_line.warehouse_id, v_inv_line.item_id);
    SELECT * INTO v_stock FROM stock_balances
    WHERE warehouse_id = v_inv_line.warehouse_id AND item_id = v_inv_line.item_id
    FOR UPDATE;

    IF COALESCE(v_stock.qty_on_hand, 0) < v_inv_line.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for item %. On hand: %, requested: %',
        v_inv_line.item_code, COALESCE(v_stock.qty_on_hand, 0), v_inv_line.quantity;
    END IF;

    v_total_cost := 0;
    v_unit_cost  := 0;
    IF v_inv_line.costing_method = 'weighted_average' THEN
      v_unit_cost  := COALESCE(v_stock.wac_unit_cost, 0);
      v_total_cost := ROUND(v_inv_line.quantity * v_unit_cost, 2);
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
          v_inv_line.quantity, NULL, NULL)
      LOOP
        v_total_cost := v_total_cost + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
      END LOOP;
      IF v_inv_line.quantity > 0 THEN
        v_unit_cost := ROUND(v_total_cost / v_inv_line.quantity, 6);
      END IF;
    END IF;

    UPDATE stock_balances
    SET qty_on_hand    = qty_on_hand - v_inv_line.quantity,
        total_cost     = GREATEST(total_cost - v_total_cost, 0),
        last_issue_date = v_date,
        updated_at     = NOW()
    WHERE warehouse_id = v_inv_line.warehouse_id AND item_id = v_inv_line.item_id;

    IF v_inv_line.costing_method = 'weighted_average' THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_inv_line.warehouse_id AND item_id = v_inv_line.item_id;
    END IF;

    UPDATE sales_invoice_lines
    SET inventory_account_id = v_inv_line.inv_acct,
        cogs_account_id      = v_inv_line.cogs_acct,
        unit_cost            = v_unit_cost,
        inventory_cost       = v_total_cost,
        updated_by = auth.uid(), updated_at = NOW()
    WHERE id = v_inv_line.id;

    v_total_cogs := v_total_cogs + v_total_cost;
  END LOOP;

  -- ── Sales journal: DR AR / CR revenue / CR output VAT / DR COGS / CR inventory
  v_je_si_id := fn_create_posted_journal_entry(
    v_company_id, v_branch_id,
    'JE-SI-' || v_si_number, v_date,
    'Cash Sale ' || v_si_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id,
    v_fp_id, 'posted', v_grand_total + v_total_cogs, v_grand_total + v_total_cogs,
    'system', 'regular', false, false, false
  );

  PERFORM fn_add_posting_line_push(
    v_je_si_id, 1, v_ar,
    'AR — ' || (p_header->>'customer_name_snapshot'),
    v_grand_total, 0, 'control', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
  );

  v_line_no := 2;
  FOR v_rev_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc,
           department_id, cost_center_id
    FROM sales_invoice_lines
    WHERE sales_invoice_id = v_si_id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description, department_id, cost_center_id
  LOOP
    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_line_no, v_rev_line.revenue_account_id,
      'Revenue — ' || v_rev_line.ln_desc,
      0, v_rev_line.net_sum, 'base', NULL, v_branch_id,
      COALESCE(v_rev_line.department_id, v_hdr_dept),
      COALESCE(v_rev_line.cost_center_id, v_hdr_cc)
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_total_vat > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_line_no, v_vat,
      'Output VAT — ' || v_si_number,
      0, v_total_vat, 'tax', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
    );
    v_line_no := v_line_no + 1;
  END IF;

  FOR v_inv_line IN
    SELECT sil.id, sil.line_number, sil.item_id, sil.quantity, sil.warehouse_id,
           sil.description, sil.inventory_cost, sil.unit_cost,
           sil.inventory_account_id, sil.cogs_account_id,
           sil.department_id, sil.cost_center_id,
           i.item_code, COALESCE(i.costing_method, 'weighted_average') AS costing_method
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    WHERE sil.sales_invoice_id = v_si_id
      AND i.item_type = 'inventory_item'
    ORDER BY sil.line_number
  LOOP
    IF COALESCE(v_inv_line.inventory_cost, 0) > 0 THEN
      PERFORM fn_add_posting_line_push(
        v_je_si_id, v_line_no, v_inv_line.cogs_account_id,
        'COGS — ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        v_inv_line.inventory_cost, 0, 'base', NULL, v_branch_id,
        COALESCE(v_inv_line.department_id, v_hdr_dept),
        COALESCE(v_inv_line.cost_center_id, v_hdr_cc)
      );
      v_line_no := v_line_no + 1;
      PERFORM fn_add_posting_line_push(
        v_je_si_id, v_line_no, v_inv_line.inventory_account_id,
        'Inventory — ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        0, v_inv_line.inventory_cost, 'base', NULL, v_branch_id,
        COALESCE(v_inv_line.department_id, v_hdr_dept),
        COALESCE(v_inv_line.cost_center_id, v_hdr_cc)
      );
      v_line_no := v_line_no + 1;
    END IF;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by
    )
    SELECT v_company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
      'issue', v_date,
      -v_inv_line.quantity, COALESCE(v_inv_line.unit_cost, 0), -COALESCE(v_inv_line.inventory_cost, 0),
      sb.qty_on_hand, v_inv_line.costing_method,
      'SI', v_si_id, v_je_si_id,
      'Cash Sale ' || v_si_number || ' line ' || v_inv_line.line_number,
      auth.uid()
    FROM stock_balances sb
    WHERE sb.warehouse_id = v_inv_line.warehouse_id AND sb.item_id = v_inv_line.item_id
    RETURNING id INTO v_inventory_tx_id;

    UPDATE sales_invoice_lines
    SET inventory_transaction_id = v_inventory_tx_id,
        updated_by = auth.uid(), updated_at = NOW()
    WHERE id = v_inv_line.id;
  END LOOP;

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
    NOW()::DATE, v_date,
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

  -- ── Receipt ──────────────────────────────────────────────────────────────
  v_cash_received := v_grand_total - v_cwt_total;

  IF v_cwt_total > 0 AND v_cwt_source = 'atc' THEN
    v_net_of_vat := v_grand_total - v_total_vat;

    -- The ATC version in force on the cash-sale date governs, exactly as it
    -- does on every other withholding path.
    SELECT c.tax_rate, c.tax_amount INTO v_cwt_rate, v_cwt_exclusive_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           v_date,
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
           'document_date',           v_date,
           'direction',               'sale',
           'amount',                  0,
           'withholding_atc_code_id', v_cwt_atc,
           'withholding_base',        v_grand_total
         )) c
    WHERE c.tax_kind = 'ewt';

    IF ABS(v_cwt_exclusive_expected - v_cwt_total) <= 0.02 THEN
      v_cwt_base := v_net_of_vat;
    ELSIF ABS(v_cwt_gross_expected - v_cwt_total) <= 0.02 THEN
      v_cwt_base := v_grand_total;
    ELSE
      RAISE EXCEPTION 'CWT % does not match ATC rate %%% on the VAT-exclusive base % (expected %) or on the gross % (expected %).',
        v_cwt_total, v_cwt_rate,
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
    v_or_number, v_date,
    COALESCE(NULLIF(p_header->>'payment_mode_id','')::UUID,
             (SELECT id FROM ref_payment_modes WHERE code = 'CASH')), v_cash_acct,
    v_grand_total, v_cwt_total, 'Cash Sale — ' || v_si_number,
    'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_receipt_id;

  INSERT INTO receipt_lines (
    receipt_id, company_id, invoice_id, payment_amount, cwt_amount,
    atc_code_id, cwt_tax_base, cwt_source, created_by, updated_by
  ) VALUES (
    v_receipt_id, v_company_id, v_si_id, v_grand_total - v_cwt_total, v_cwt_total,
    CASE WHEN v_cwt_source = 'atc' THEN v_cwt_atc ELSE NULL END,
    CASE WHEN v_cwt_total > 0 THEN v_cwt_base ELSE NULL END,
    CASE WHEN v_cwt_total > 0 THEN v_cwt_source ELSE 'atc' END,
    auth.uid(), auth.uid()
  );

  -- Post receipt JE: DR Cash (net) + DR CWT Receivable = CR AR (gross)
  v_je_or_id := fn_create_posted_journal_entry(
    v_company_id, v_branch_id,
    'JE-OR-' || v_or_number, v_date,
    'Cash Receipt ' || v_or_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id,
    v_fp_id, 'posted', v_grand_total, v_grand_total,
    'system', 'regular', false, false, false
  );

  PERFORM fn_add_posting_line_push(
    v_je_or_id, 1, v_cash_acct,
    'Cash received — ' || v_or_number,
    v_cash_received, 0, 'base', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
  );

  IF v_cwt_total > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_or_id, 2, v_cwt,
      'CWT receivable — ' || v_or_number,
      v_cwt_total, 0, 'withholding', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
    );
  END IF;

  PERFORM fn_add_posting_line_push(
    v_je_or_id, CASE WHEN v_cwt_total > 0 THEN 3 ELSE 2 END,
    v_ar, 'AR cleared — ' || v_or_number,
    0, v_grand_total, 'control', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
  );

  UPDATE receipts SET status = 'posted', journal_entry_id = v_je_or_id,
    posted_by = auth.uid(), posted_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  -- ── CWT receivable tax ledger ────────────────────────────────────────────
  -- One row per ATC when the lines are itemised, because a 2307 and a 1601-EQ
  -- are assembled per ATC, not per document.
  IF v_cwt_total > 0 AND v_cwt_source = 'invoice_lines' THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    )
    SELECT
      v_company_id, v_branch_id, 'OR', v_receipt_id,
      'cwt_receivable', sil.withholding_atc_code_id,
      SUM(sil.withholding_tax_base), MAX(sil.withholding_tax_rate), SUM(sil.withholding_tax_amount), v_fp_id,
      NOW()::DATE, v_date,
      (p_header->>'customer_id')::UUID,
      NULLIF(p_header->>'customer_tin_snapshot',''),
      p_header->>'customer_name_snapshot'
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_si_id
      AND sil.withholding_atc_code_id IS NOT NULL
    GROUP BY sil.withholding_atc_code_id;
  ELSIF v_cwt_total > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_company_id, v_branch_id, 'OR', v_receipt_id,
      'cwt_receivable', v_cwt_atc, v_cwt_base, v_cwt_rate, v_cwt_total, v_fp_id,
      NOW()::DATE, v_date,
      (p_header->>'customer_id')::UUID,
      NULLIF(p_header->>'customer_tin_snapshot',''),
      p_header->>'customer_name_snapshot'
    );
  END IF;

  RETURN jsonb_build_object(
    'si_id', v_si_id, 'receipt_id', v_receipt_id,
    'si_number', v_si_number, 'receipt_number', v_or_number,
    'total_amount', v_grand_total, 'total_cwt', v_cwt_total,
    'total_cogs', v_total_cogs
  );
END;
$function$;

COMMENT ON FUNCTION public.fn_save_cash_sale(jsonb, jsonb, numeric) IS
  'Cash Sale: prices every line through the Tax Engine (business tax and withholding tax, both per line, both as of the document date), relieves inventory and posts COGS through the same costing path as fn_post_sales_invoice, then settles the invoice with an Official Receipt. Percentage tax is deliberately absent.';
