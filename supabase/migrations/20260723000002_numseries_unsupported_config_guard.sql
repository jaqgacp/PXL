-- Number Series Engine certification hardening (2026-07-23).
--
-- Contract alignment: the governed allocator fn_next_document_number produces a
-- CONTINUOUS number as CONCAT(prefix, LPAD(sequence, padding), suffix). It does
-- NOT inject a dynamic year and does NOT reset the sequence on any period
-- boundary. For Philippine CAS/BIR-registered documents this continuous,
-- non-resetting behavior is the correct and compliant behavior.
--
-- Two number_series configuration columns could previously be set to values the
-- allocator silently ignores: has_dynamic_year = true and
-- reset_frequency <> 'never'. A setup surface that stores a value the engine
-- never honors is a contract mismatch (the number-format preview can promise a
-- year/reset that the issued number will never contain). This guard makes the
-- engine contract truthful and fail-closed: an unsupported configuration is
-- rejected with an actionable message instead of being accepted and ignored.
--
-- Scope: number_series enforcement only. No allocator, registry, consumer,
-- posting, tax, or reporting behavior changes. No existing series is affected
-- (every series already uses has_dynamic_year = false and
-- reset_frequency = 'never'); the guard prevents the divergence from recurring.
-- This CREATE OR REPLACE preserves every existing ATP / no-backward / identity
-- protection in fn_guard_cas_number_series verbatim.

CREATE OR REPLACE FUNCTION public.fn_guard_cas_number_series()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_evidence BOOLEAN := FALSE;
BEGIN
  -- Contract guard: reject configuration the continuous allocator never honors.
  IF COALESCE(NEW.has_dynamic_year, FALSE) THEN
    RAISE EXCEPTION 'Number series dynamic-year injection is not supported; embed the year in the static prefix (e.g. prefix "SI-2026-") and keep has_dynamic_year = false'
      USING ERRCODE = 'P0001';
  END IF;
  IF COALESCE(NEW.reset_frequency, 'never') <> 'never' THEN
    RAISE EXCEPTION 'Number series periodic reset (%) is not supported; governed CAS numbering is continuous. Use reset_frequency = never', NEW.reset_frequency
      USING ERRCODE = 'P0001';
  END IF;

  IF (NEW.atp_series_start IS NULL) <> (NEW.atp_series_end IS NULL) THEN
    RAISE EXCEPTION 'ATP series start and end must be configured together';
  END IF;
  IF NEW.atp_series_start IS NOT NULL AND (
    NEW.atp_series_start < 1 OR NEW.atp_series_end < NEW.atp_series_start
  ) THEN
    RAISE EXCEPTION 'Invalid ATP range % to %',
      NEW.atp_series_start, NEW.atp_series_end;
  END IF;
  IF NEW.atp_series_end IS NOT NULL
     AND COALESCE(NEW.current_sequence, 0) > NEW.atp_series_end THEN
    RAISE EXCEPTION 'ATP end % is below current sequence %',
      NEW.atp_series_end, NEW.current_sequence;
  END IF;

  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.current_sequence, 0) < COALESCE(OLD.current_sequence, 0)
     OR COALESCE(NEW.next_number, 1) < COALESCE(OLD.next_number, 1) THEN
    RAISE EXCEPTION 'Document sequence counters cannot move backward; issued numbers are never reusable';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.cas_document_number_issuances i
    WHERE i.number_series_id = OLD.id
  ) INTO v_has_evidence;

  IF v_has_evidence AND (
    NEW.company_id IS DISTINCT FROM OLD.company_id OR
    NEW.branch_id IS DISTINCT FROM OLD.branch_id OR
    NEW.document_type_id IS DISTINCT FROM OLD.document_type_id OR
    NEW.document_code IS DISTINCT FROM OLD.document_code OR
    NEW.prefix IS DISTINCT FROM OLD.prefix OR
    NEW.suffix IS DISTINCT FROM OLD.suffix OR
    NEW.padding IS DISTINCT FROM OLD.padding OR
    NEW.number_length IS DISTINCT FROM OLD.number_length OR
    NEW.has_dynamic_year IS DISTINCT FROM OLD.has_dynamic_year OR
    NEW.reset_frequency IS DISTINCT FROM OLD.reset_frequency OR
    NEW.atp_series_start IS DISTINCT FROM OLD.atp_series_start
  ) THEN
    RAISE EXCEPTION 'A number series with issuance evidence cannot change tenant, branch, document identity, format, reset rule, or ATP start';
  END IF;

  IF v_has_evidence
     AND OLD.atp_series_end IS NOT NULL
     AND NEW.atp_series_end IS NOT NULL
     AND NEW.atp_series_end < OLD.atp_series_end THEN
    RAISE EXCEPTION 'ATP series end cannot shrink after number issuance';
  END IF;

  RETURN NEW;
END;
$$;
