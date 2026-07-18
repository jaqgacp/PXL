-- Restore posting-period parity for Sales Invoice GL previews.
--
-- The specialized Sales Invoice preview added in 20260715000004 resolves an
-- open period for display but does not reject an approved invoice when no open
-- period covers the posting date. Keep the existing implementation as an
-- internal versioned function and put the invariant back at the public entry
-- point without changing posted-document previews.

DO $$
BEGIN
  IF to_regprocedure('public.fn_preview_gl_impact_core(text,uuid,date)') IS NULL THEN
    ALTER FUNCTION public.fn_preview_gl_impact(TEXT, UUID, DATE)
      RENAME TO fn_preview_gl_impact_core;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_preview_gl_impact_core(TEXT, UUID, DATE)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_preview_gl_impact(
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
  v_company_id UUID;
  v_effective_posting_date DATE;
  v_has_posted_journal BOOLEAN;
BEGIN
  IF v_type = 'SI' AND p_source_doc_id IS NOT NULL THEN
    SELECT
      si.company_id,
      COALESCE(p_posting_date, si.date, CURRENT_DATE),
      EXISTS (
        SELECT 1
        FROM public.journal_entries je
        WHERE je.reference_doc_type = 'SI'
          AND je.reference_doc_id = si.id
          AND je.status IN ('posted', 'reversed')
      )
    INTO v_company_id, v_effective_posting_date, v_has_posted_journal
    FROM public.sales_invoices si
    WHERE si.id = p_source_doc_id;

    -- The core function owns not-found and membership errors. This guard only
    -- applies to an accessible, not-yet-posted Sales Invoice preview.
    IF v_company_id IS NOT NULL
       AND public.is_company_member(v_company_id)
       AND NOT COALESCE(v_has_posted_journal, false)
       AND NOT EXISTS (
         SELECT 1
         FROM public.fiscal_periods fp
         WHERE fp.company_id = v_company_id
           AND v_effective_posting_date BETWEEN fp.start_date AND fp.end_date
           AND COALESCE(fp.is_locked, false) = false
       ) THEN
      RAISE EXCEPTION 'No open fiscal period found for posting date %',
        v_effective_posting_date;
    END IF;
  END IF;

  RETURN public.fn_preview_gl_impact_core(
    p_source_doc_type,
    p_source_doc_id,
    p_posting_date
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_preview_gl_impact(TEXT, UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_preview_gl_impact(TEXT, UUID, DATE)
  TO authenticated;

COMMENT ON FUNCTION public.fn_preview_gl_impact(TEXT, UUID, DATE) IS
  'Public GL preview entry point. Enforces open-period parity for unposted Sales Invoices before delegating to the versioned preview engine.';

COMMENT ON FUNCTION public.fn_preview_gl_impact_core(TEXT, UUID, DATE) IS
  'Internal versioned GL preview engine retained by 20260716000005. Invoke through fn_preview_gl_impact.';
