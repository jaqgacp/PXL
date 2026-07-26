-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P3C (Manual Journal Control)
--
-- Implements ONLY objective O-D of the frozen phase specification
-- `docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_P3_SPEC.md` §6, enforcing the
-- frozen COA Posting Control Contract (`PXL_COA_ENGINE_SPEC.md` §5). No later phase
-- (P3D preview convergence) is implemented here.
--
-- WHAT CHANGES
--   `fn_assert_manual_postable` was delivered by COA Phase A and has had ZERO runtime
--   callers since (certification observation O3). This migration wires it into
--   `fn_post_manual_je` — one `PERFORM` inside the existing per-line validation loop.
--   A manual journal line may no longer target a control (subledger-owned) account;
--   control-account movement must originate from the owning subledger.
--
-- WHAT DOES NOT CHANGE
--   The function body is reproduced verbatim from its certified definition (migration
--   20260723000003); the ONLY textual difference is the added PERFORM. Validation
--   ORDER is preserved: the new call runs AFTER the existing account checks (belongs to
--   company / is_postable / is_active), so every pre-P3C rejection keeps its exact
--   message and every valid manual journal posts byte-for-byte identically —
--   same numbering (`MJE-YYYYMM-NNNN`), entry_class, reference_doc_type, auto_reverse,
--   fiscal period, line order, amounts, descriptions, and all six dimensions.
--   Permissions, audit behavior, the posting pipeline, and the signature are untouched.
--
-- WHY EXACTLY ONE LIVE REJECTION IS ADDED
--   `fn_assert_manual_postable` = `fn_assert_postable_leaf` + a control-account test.
--   `fn_assert_postable_leaf` → `fn_is_account_postable`, which tests is_postable,
--   lifecycle_status='active', leaf-ness, and effective dating. Against the certified
--   database each of those is already inert:
--     * is_postable / lifecycle — the existing loop already rejects a non-postable or
--       inactive account first, and `fn_coa_change_policy_guard` keeps `is_active` in
--       sync with `lifecycle_status` (`NEW.is_active := (NEW.lifecycle_status='active')`);
--     * leaf-ness — zero postable accounts have children;
--     * effective dating — zero accounts carry effective_from/effective_to.
--   The control-account test is therefore the only predicate that can fire, which is
--   exactly the permitted behavior change.
--
-- AS-OF SEMANTICS
--   `p_je_date` is passed as the as-of date so effective dating is evaluated at the
--   accounting date, consistent with COA §4.5 and with every P2 resolver call, rather
--   than at wall-clock time.
--
-- CANONICAL SAFETY (verified before implementation)
--   Whole database: 0 accounts flagged `is_control_account`; 0 journal lines of any
--   document type on a control account; 0 postable non-leaf accounts; 0 effective-dated
--   accounts. Replaying the validator over every existing journal_entry_line — at both
--   the journal date and CURRENT_DATE — rejects 0 rows. No existing data is invalidated.
-- ══════════════════════════════════════════════════════════════════════════════

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

    -- P3C: the frozen COA §5 posting control. Runs AFTER the existing checks so every
    -- pre-P3C rejection keeps its exact message; it therefore adds exactly one live
    -- rejection — a manual line targeting a control (subledger-owned) account.
    PERFORM fn_assert_manual_postable(v_account_id, p_je_date);

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
