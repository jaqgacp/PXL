-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 3, Batch A
-- (SI / VB / OR / CP post-kernel header UPDATEs)
--
-- The four writers in this batch already create their journal header through
-- fn_create_posted_journal_entry, then issue a direct
--   UPDATE journal_entries SET posting_origin = 'system'
-- immediately after the kernel returns. Those UPDATEs are the only ledger writes
-- in these writers that remain outside the kernel.
--
-- ACCOUNTING + AUDIT EQUALITY
-- Merely passing posting_origin='system' at INSERT time would produce the same
-- final header but would remove the established UPDATE audit event. The kernel is
-- therefore extended by one defaulted capability flag. When requested, it inserts
-- the header with the caller's previous NULL origin and performs the exact same
-- origin UPDATE before returning. The same INSERT and UPDATE triggers fire in the
-- same order, with the same OLD/NEW images, actor, transaction timestamps, and
-- final row. Existing callers default false and are unchanged.
--
-- No new function is admitted to the sanctioned set, no whitelist entry is
-- added, and the guard remains observe-only.
-- ══════════════════════════════════════════════════════════════════════════════

-- Drop-and-recreate, not overload: defaulted overloads make legacy calls
-- ambiguous. The first fourteen parameters and all defaults remain unchanged.
DROP FUNCTION IF EXISTS public.fn_create_posted_journal_entry(
  uuid, uuid, text, date, text, text, uuid, uuid, text, numeric, numeric,
  text, text, boolean
);

CREATE FUNCTION public.fn_create_posted_journal_entry(
  p_company_id         UUID,
  p_branch_id          UUID,
  p_je_number          TEXT,
  p_je_date            DATE,
  p_description        TEXT,
  p_reference_doc_type TEXT,
  p_reference_doc_id   UUID,
  p_fiscal_period_id   UUID    DEFAULT NULL,
  p_status             TEXT    DEFAULT 'posted',
  p_total_debit        NUMERIC DEFAULT 0,
  p_total_credit       NUMERIC DEFAULT 0,
  p_posting_origin     TEXT    DEFAULT NULL,
  p_entry_class        TEXT    DEFAULT 'regular',
  p_auto_reverse       BOOLEAN DEFAULT false,
  -- P5.1 Stage 3: preserve the established post-INSERT origin UPDATE and its
  -- audit event while moving the mutation inside the already-sanctioned kernel.
  p_emit_origin_update BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_period_id UUID;
  v_je_id     UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  PERFORM fn_assert_posting_source(
    p_reference_doc_type,
    p_reference_doc_id,
    p_company_id
  );

  IF p_fiscal_period_id IS NULL THEN
    v_period_id := fn_require_open_fiscal_period(p_company_id, p_je_date, true);
  ELSE
    v_period_id := p_fiscal_period_id;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, entry_class, auto_reverse,
    created_by, updated_by
  ) VALUES (
    p_company_id, p_branch_id, p_je_number, p_je_date, v_period_id,
    p_description, UPPER(BTRIM(p_reference_doc_type)), p_reference_doc_id,
    COALESCE(p_status, 'posted'),
    COALESCE(p_total_debit, 0), COALESCE(p_total_credit, 0),
    CASE WHEN p_emit_origin_update THEN NULL ELSE p_posting_origin END,
    COALESCE(p_entry_class, 'regular'), COALESCE(p_auto_reverse, false),
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  IF p_emit_origin_update THEN
    UPDATE journal_entries
    SET posting_origin = p_posting_origin
    WHERE id = v_je_id;
  END IF;

  RETURN v_je_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_create_posted_journal_entry(
  uuid, uuid, text, date, text, text, uuid, uuid, text, numeric, numeric,
  text, text, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_posted_journal_entry(
  uuid, uuid, text, date, text, text, uuid, uuid, text, numeric, numeric,
  text, text, boolean, boolean
) TO service_role;

-- The transformations below are deliberately exact and fail closed. Re-emitting
-- hundreds of unchanged function lines would obscure review of the four changed
-- call sites; pg_get_functiondef retains the certified body and only the asserted
-- source fragment is replaced.
DO $migration$
DECLARE
  v_signature REGPROCEDURE;
  v_definition TEXT;
  v_before     TEXT;
  v_after      TEXT;
BEGIN
  -- Sales Invoice
  v_signature := 'public.fn_post_sales_invoice(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$    'SI', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;$old$;
  v_after := $new$    'SI', v_rec.id,
    NULL, 'posted', 0, 0, 'system', 'regular', false, true
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 3 source drift: fn_post_sales_invoice';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- Vendor Bill
  v_signature := 'public.fn_post_vendor_bill(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$    'VB', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;$old$;
  v_after := $new$    'VB', v_rec.id,
    NULL, 'posted', 0, 0, 'system', 'regular', false, true
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 3 source drift: fn_post_vendor_bill';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- Official Receipt
  v_signature := 'public.fn_post_receipt(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$    'OR', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;$old$;
  v_after := $new$    'OR', v_rec.id,
    NULL, 'posted', 0, 0, 'system', 'regular', false, true
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 3 source drift: fn_post_receipt';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);

  -- Cash Purchase
  v_signature := 'public.fn_post_cash_purchase_source_locked_impl(uuid)'::REGPROCEDURE;
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  v_before := $old$    'CP', v_rec.id
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;
  UPDATE journal_entries SET posting_origin = 'system' WHERE id = v_je_id;$old$;
  v_after := $new$    'CP', v_rec.id,
    NULL, 'posted', 0, 0, 'system', 'regular', false, true
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;$new$;
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION 'P5.1 Stage 3 source drift: fn_post_cash_purchase_source_locked_impl';
  END IF;
  EXECUTE replace(v_definition, v_before, v_after);
END;
$migration$;

