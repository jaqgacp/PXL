-- ══════════════════════════════════════════════════════════════════════════════
-- NUMBER SERIES FUNCTION HARDENING
-- Adds: SET search_path = public (prevents search_path injection),
--       membership check (prevents cross-company sequence exhaustion),
--       restricted execute grant (revoke from PUBLIC, grant to authenticated).
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_next_document_number(
  p_company_id    UUID,
  p_branch_id     UUID,
  p_document_code TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_series    number_series%ROWTYPE;
  v_seq       BIGINT;
  v_padded    TEXT;
  v_number    TEXT;
BEGIN
  -- Membership check: callers can only generate numbers for their own company
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_series
  FROM number_series
  WHERE company_id    = p_company_id
    AND branch_id     = p_branch_id
    AND document_code = p_document_code
    AND is_active     = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active number series for document code "%" in this branch. Set one up under Number Series Setup.', p_document_code;
  END IF;

  v_seq := v_series.current_sequence + 1;

  UPDATE number_series
  SET current_sequence = v_seq, updated_at = NOW()
  WHERE id = v_series.id;

  v_padded := LPAD(v_seq::TEXT, v_series.padding, '0');
  v_number := CONCAT(
    COALESCE(v_series.prefix, ''),
    v_padded,
    COALESCE(v_series.suffix, '')
  );

  RETURN v_number;
END;
$$;

-- Restrict execution: revoke from PUBLIC (default implicit grant),
-- then grant only to authenticated users.
REVOKE EXECUTE ON FUNCTION fn_next_document_number(UUID, UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION fn_next_document_number(UUID, UUID, TEXT) TO authenticated;
