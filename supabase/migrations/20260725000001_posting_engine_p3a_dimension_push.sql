-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P3A (Dimension Push)
--
-- Implements ONLY objective O-A of the frozen phase specification
-- `docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_P3_SPEC.md` §3 / §11 (sub-phase
-- P3a), under the frozen Tier 2 architecture `PXL_POSTING_ENGINE_SPEC.md` §2.3
-- (push-not-pull) and §5.2 (Dimension Engine consumption). No later phase (P3B
-- fiscal close, P3C manual-JE control, P3D preview convergence) is implemented here.
--
-- WHAT CHANGES
--   fn_add_posting_line becomes a pure persistence helper. It accepts all six
--   governed dimensions explicitly and performs ONE insert. It no longer:
--     * reads journal_entries.reference_doc_type / reference_doc_id to discover a source,
--     * dispatches on the hardcoded document types 'VB' / 'CP',
--     * reads vendor_bills / cash_purchases (no source lookup),
--     * infers a dimension via COALESCE(parameter, pulled_source_value),
--     * issues a follow-up UPDATE on journal_entry_lines for project/location/
--       functional_entity.
--   The two document writers that relied on that pull — fn_post_vendor_bill and
--   fn_post_cash_purchase_source_locked_impl — now own dimension resolution and push
--   the document header's six dimensions on every line, exactly as the Sales writers
--   already do.
--
-- WHAT DOES NOT CHANGE
--   The Dimension Engine remains the only dimension validator: trg_je_line_dimensions_guard
--   fires on the same INSERT and sees pushed values instead of pulled ones. The helper's
--   admission and accounting controls are preserved byte-for-byte (journal FOR UPDATE lock,
--   is_company_member check, fn_require_postable_account, exactly-one-positive-amount check),
--   as are its EXECUTE grants. Journal count/order, account_id, debit, credit, all six
--   dimensions, descriptions, references, posting_origin, line_role, numbering, VAT, EWT,
--   AP, inventory, and approvals are unchanged for every document type.
--   fn_post_vendor_bill and fn_post_cash_purchase_source_locked_impl are reproduced verbatim
--   from their certified P2B bodies (migration 20260724000004); the ONLY textual difference
--   is the dimension argument list of the four fn_add_posting_line calls in each.
--
-- EQUIVALENCE PROOF (why the GL is byte-for-byte identical)
--   The retired pull read `vendor_bills`/`cash_purchases` WHERE id = journal_entries.
--   reference_doc_id. Both writers create their journal with reference_doc_id = v_rec.id
--   and hold v_rec as a %ROWTYPE snapshot of that same row, taken before the journal is
--   created and never re-written before the lines are inserted. Pushing v_rec.<dimension>
--   therefore yields the identical value the pull produced, and both callers previously
--   passed NULL for department/cost_center, so COALESCE(NULL, pulled) == pushed.
--   Every other caller posts a journal whose reference_doc_type is 'PV', 'OR', 'WHTREM',
--   'SI', or 'REV' — the pull never fired for them, so their lines are unaffected.
--
-- AUDIT-EVENT DIFFERENCE (the only permitted behavioral difference, spec §3.8 / Risk R2)
--   A Vendor Bill / Cash Purchase line is now written by one INSERT instead of
--   INSERT-then-UPDATE. journal_entry_lines carries no audit trigger, so no sys_audit_logs
--   or transaction_events row changes; the difference is one fewer statement and one fewer
--   (redundant) firing of the line guards. No GL value changes.
--
-- SIGNATURE SAFETY (spec Risk R3)
--   PostgreSQL treats the 9-argument and the 12-argument form as two distinct functions,
--   and a 9-argument call against both is rejected at CALL time with
--   "function ... is not unique". An additive overload is therefore NOT deployment-safe.
--   The 9-argument function is dropped and re-created with twelve parameters (the three new
--   ones DEFAULT NULL) so exactly one candidate exists and every existing 9-argument call
--   site keeps resolving. The prior REVOKE/GRANT set is re-applied verbatim.
-- ══════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════════
-- Pure persistence helper — six pushed dimensions, one insert, no source lookup
-- ══════════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.fn_add_posting_line(
  UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID);

CREATE FUNCTION public.fn_add_posting_line(
  p_je_id UUID,
  p_line_number INTEGER,
  p_account_id UUID,
  p_description TEXT,
  p_debit NUMERIC DEFAULT 0,
  p_credit NUMERIC DEFAULT 0,
  p_branch_id UUID DEFAULT NULL,
  p_department_id UUID DEFAULT NULL,
  p_cost_center_id UUID DEFAULT NULL,
  p_project_id UUID DEFAULT NULL,
  p_location_id UUID DEFAULT NULL,
  p_functional_entity_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_line_id UUID;
BEGIN
  SELECT company_id INTO v_company_id
  FROM journal_entries
  WHERE id = p_je_id
  FOR UPDATE;

  IF v_company_id IS NULL OR NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Journal entry not found or access denied';
  END IF;

  PERFORM fn_require_postable_account(v_company_id, p_account_id, 'Journal line account');

  IF COALESCE(p_debit, 0) < 0 OR COALESCE(p_credit, 0) < 0
     OR (COALESCE(p_debit, 0) > 0) = (COALESCE(p_credit, 0) > 0) THEN
    RAISE EXCEPTION 'A journal line must contain exactly one positive debit or credit amount';
  END IF;

  -- One insert. The six dimensions are written exactly as handed in; the Dimension
  -- Engine guard (trg_je_line_dimensions_guard) validates them on this INSERT.
  INSERT INTO journal_entry_lines (
    je_id, company_id, line_number, account_id, description,
    debit_amount, credit_amount, branch_id, department_id, cost_center_id,
    project_id, location_id, functional_entity_id,
    created_by, updated_by
  ) VALUES (
    p_je_id, v_company_id, p_line_number, p_account_id, p_description,
    COALESCE(p_debit, 0), COALESCE(p_credit, 0),
    p_branch_id, p_department_id, p_cost_center_id,
    p_project_id, p_location_id, p_functional_entity_id,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_line_id;

  RETURN v_line_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_add_posting_line(
  UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_add_posting_line(
  UUID, INTEGER, UUID, TEXT, NUMERIC, NUMERIC, UUID, UUID, UUID, UUID, UUID, UUID)
  TO authenticated, service_role;

-- ══════════════════════════════════════════════════════════════════════════════
-- Vendor Bill — the writer now owns dimension resolution (verbatim P2B body, six
-- pushed dimensions on each of its four posting lines)
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_vendor_bill(p_bill_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_begin JSONB;
  v_rec vendor_bills%ROWTYPE;
  v_ap UUID;
  v_input_vat UUID;
  v_ewt UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_line RECORD;
  v_tax RECORD;
  v_line_no INTEGER := 1;
  v_total_debit NUMERIC(15,2) := 0;
  v_accrued_ewt NUMERIC(15,2) := 0;
  v_ap_credit NUMERIC(15,2) := 0;
BEGIN
  v_begin := fn_begin_source_posting(
    'VB', p_bill_id, ARRAY['approved'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM vendor_bills WHERE id = p_bill_id;
  PERFORM fn_validate_vendor_bill_accounting_ready(p_bill_id);
  PERFORM fn_validate_vendor_bill_vat_registration(p_bill_id);
  PERFORM fn_validate_invoice_posting_totals('VB', p_bill_id);

  -- COA resolver adoption (P2B): AP control + Input VAT + EWT Payable via fn_resolve_account.
  v_ap := fn_resolve_posting_account(v_rec.company_id, 'AP_TRADE', v_rec.bill_date,
            'AP control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_input_vat_amount > 0 THEN
    v_input_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_INPUT', v_rec.bill_date,
                     'Input VAT account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT COALESCE(SUM(vbl.ewt_amount), 0)::NUMERIC(15,2)
  INTO v_accrued_ewt
  FROM vendor_bill_lines vbl
  WHERE vbl.vendor_bill_id = v_rec.id;

  IF v_accrued_ewt > 0 THEN
    v_ewt := fn_resolve_posting_account(v_rec.company_id, 'EWT_PAYABLE', v_rec.bill_date,
               'EWT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  v_ap_credit := ROUND(v_rec.total_amount - v_accrued_ewt, 2);
  IF v_ap_credit <= 0 THEN
    RAISE EXCEPTION 'Vendor bill source EWT % cannot equal or exceed bill total %.',
      v_accrued_ewt, v_rec.total_amount;
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-VB-' || v_rec.bill_number, v_rec.bill_date,
    'Vendor Bill ' || v_rec.bill_number || ' - ' || v_rec.supplier_name_snapshot,
    'VB', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;

  FOR v_line IN
    SELECT vbl.expense_account_id, SUM(vbl.net_amount) AS net_sum,
           vbl.description AS line_description
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.expense_account_id IS NOT NULL
    GROUP BY vbl.expense_account_id, vbl.description
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.expense_account_id,
      'Expense - ' || v_line.line_description,
      v_line.net_sum, 0,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_total_debit := v_total_debit + v_line.net_sum;
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_input_vat,
      'Input VAT - ' || v_rec.bill_number,
      v_rec.total_input_vat_amount, 0,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_total_debit := v_total_debit + v_rec.total_input_vat_amount;
    v_line_no := v_line_no + 1;
  END IF;

  PERFORM fn_add_posting_line(
    v_je_id, v_line_no, v_ap,
    'AP - ' || v_rec.supplier_name_snapshot,
    0, v_ap_credit,
    v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
    v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
  );
  v_line_no := v_line_no + 1;

  IF v_accrued_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_ewt,
      'EWT accrued - ' || v_rec.bill_number,
      0, v_accrued_ewt,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
  END IF;

  IF ABS((v_ap_credit + v_accrued_ewt) - v_total_debit) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Ensure all lines have expense accounts.',
      v_total_debit, v_ap_credit + v_accrued_ewt;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE vendor_bills
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_tax IN
    SELECT vbl.vat_code_id,
           SUM(vbl.net_amount) AS tax_base,
           COALESCE(SUM(vbl.input_vat_amount), 0) AS tax_amount
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY vbl.vat_code_id
    HAVING SUM(vbl.net_amount) <> 0 OR COALESCE(SUM(vbl.input_vat_amount), 0) <> 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id, NULL,
      'input_vat', NULL, v_tax.vat_code_id, NULL,
      v_tax.tax_base, NULL, v_tax.tax_amount, v_fp_id,
      CURRENT_DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
    );
  END LOOP;

  FOR v_tax IN
    SELECT vbl.id, vbl.ewt_atc_code_id, vbl.ewt_tax_base, vbl.ewt_amount,
           vbl.ewt_income_nature, ac.rate AS ewt_rate
    FROM vendor_bill_lines vbl
    LEFT JOIN atc_codes ac ON ac.id = vbl.ewt_atc_code_id
    WHERE vbl.vendor_bill_id = v_rec.id
      AND vbl.ewt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'VB', v_rec.id, v_tax.id,
      'ewt_payable', NULL, NULL, v_tax.ewt_atc_code_id,
      v_tax.ewt_tax_base, v_tax.ewt_rate, v_tax.ewt_amount, v_fp_id,
      CURRENT_DATE, v_rec.bill_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      v_tax.ewt_income_nature
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'VB', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.bill_date, 'ewt_recognition', 'accrual_at_source')
  );
END;
$function$;
-- ══════════════════════════════════════════════════════════════════════════════
-- Cash Purchase — the writer now owns dimension resolution (verbatim P2B body, six
-- pushed dimensions on each of its four posting lines)
-- ══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_post_cash_purchase_source_locked_impl(p_cp_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       cash_purchases%ROWTYPE;
  v_cash_acct UUID;
  v_input_vat UUID;
  v_ewt       UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_tax       RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
  v_gross_total NUMERIC(15,2) := 0;
  v_total_ewt NUMERIC(15,2) := 0;
  v_cash_total NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM cash_purchases WHERE id = p_cp_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft cash purchases can be posted (current: %)', v_rec.status; END IF;

  PERFORM fn_validate_cash_purchase_ewt_ready(p_cp_id);

  -- COA resolver adoption (P2B): cash (form account or CASH_DEFAULT), Input VAT, EWT Payable.
  v_cash_acct := v_rec.payment_account_id;
  IF v_cash_acct IS NULL THEN
    v_cash_acct := fn_resolve_posting_account(v_rec.company_id, 'CASH_DEFAULT', v_rec.transaction_date,
                     'Payment account not set. Add it on the form or configure a default cash account.');
  END IF;
  IF v_rec.total_input_vat_amount > 0 THEN
    v_input_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_INPUT', v_rec.transaction_date,
                     'Input VAT account not configured. Set it in GL Posting Configuration.');
  END IF;

  v_total_ewt := COALESCE(v_rec.total_ewt_amount, 0);
  IF v_total_ewt > 0 THEN
    v_ewt := fn_resolve_posting_account(v_rec.company_id, 'EWT_PAYABLE', v_rec.transaction_date,
               'EWT Payable account not configured. Set it in GL Posting Configuration.');
  END IF;
  IF v_total_ewt > 0 AND v_rec.supplier_id IS NULL THEN
    RAISE EXCEPTION 'Supplier is required when cash purchase EWT is recorded.';
  END IF;

  v_gross_total := ROUND(
    COALESCE(v_rec.total_taxable_amount, 0)
    + COALESCE(v_rec.total_zero_rated_amount, 0)
    + COALESCE(v_rec.total_exempt_amount, 0)
    + COALESCE(v_rec.total_input_vat_amount, 0),
    2
  );
  v_cash_total := COALESCE(v_rec.total_amount, 0);

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-CP-' || v_rec.cp_number, v_rec.transaction_date,
    'Cash Purchase ' || v_rec.cp_number || COALESCE(' - ' || v_rec.supplier_name_snapshot, ''),
    'CP', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM cash_purchase_lines
    WHERE cp_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_line.expense_account_id,
      'Expense - ' || v_line.ln_desc,
      v_line.net_sum, 0,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_input_vat,
      'Input VAT - ' || v_rec.cp_number,
      v_rec.total_input_vat_amount, 0,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_total_dr := v_total_dr + v_rec.total_input_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  IF v_total_ewt > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_ewt,
      'EWT withheld - ' || v_rec.cp_number,
      0, v_total_ewt,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_line_no := v_line_no + 1;
  END IF;

  IF v_cash_total > 0 THEN
    PERFORM fn_add_posting_line(
      v_je_id, v_line_no, v_cash_acct,
      'Cash paid - ' || v_rec.cp_number,
      0, v_cash_total,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
  ELSIF v_cash_total < 0 THEN
    RAISE EXCEPTION 'Cash purchase cash total cannot be negative.';
  END IF;

  IF ABS(v_gross_total - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% expected gross %. Ensure all lines have expense accounts.',
      v_total_dr, v_gross_total;
  END IF;
  IF ABS(v_gross_total - (v_cash_total + v_total_ewt)) > 0.02 THEN
    RAISE EXCEPTION 'Cash purchase gross % must equal cash % plus EWT %.',
      v_gross_total, v_cash_total, v_total_ewt;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE cash_purchases SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name
  )
  SELECT
    v_rec.company_id, v_rec.branch_id, 'CP', v_rec.id,
    'input_vat', cpl.vat_code_id,
    SUM(cpl.net_amount), COALESCE(SUM(cpl.input_vat_amount), 0), v_fp_id,
    NOW()::DATE, v_rec.transaction_date,
    v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot
  FROM cash_purchase_lines cpl
  WHERE cpl.cp_id = v_rec.id
    AND cpl.vat_code_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM companies c
                WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat')
  GROUP BY cpl.vat_code_id
  HAVING SUM(cpl.net_amount) <> 0 OR COALESCE(SUM(cpl.input_vat_amount), 0) <> 0;

  FOR v_tax IN
    SELECT cpl.id, cpl.ewt_atc_code_id, cpl.ewt_tax_base, cpl.ewt_amount,
           cpl.ewt_income_nature, cpl.net_amount, cpl.input_vat_amount,
           ac.rate AS ewt_rate
    FROM cash_purchase_lines cpl
    LEFT JOIN atc_codes ac ON ac.id = cpl.ewt_atc_code_id
    WHERE cpl.cp_id = v_rec.id
      AND cpl.ewt_amount > 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'CP', v_rec.id, v_tax.id,
      'ewt_payable', NULL, NULL, v_tax.ewt_atc_code_id,
      ROUND(COALESCE(v_tax.ewt_tax_base, v_tax.net_amount), 2),
      v_tax.ewt_rate, v_tax.ewt_amount, v_fp_id,
      CURRENT_DATE, v_rec.transaction_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      v_tax.ewt_income_nature
    );
  END LOOP;
END;
$function$;
