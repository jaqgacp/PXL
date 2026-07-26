-- ============================================================================
-- IA-5 exact-precision internal call compatibility
-- ============================================================================
-- The authoritative primitive stores its governed scale as SMALLINT.  PL/pgSQL
-- integer literals resolve as INTEGER, so this closed overload provides an
-- exact, range-checked bridge for internal constant-scale calls.  It does not
-- add a client surface and does not round.

CREATE OR REPLACE FUNCTION public.fn_ia5_quantize_exact(
  p_value NUMERIC,
  p_scale INTEGER,
  p_label TEXT DEFAULT 'value'
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = public
AS $$
BEGIN
  IF p_scale < 0 OR p_scale > 12 THEN
    RAISE EXCEPTION 'IA-5 % precision scale % is outside 0..12',
      p_label, p_scale;
  END IF;

  RETURN public.fn_ia5_quantize_exact(
    p_value,
    p_scale::SMALLINT,
    p_label
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_ia5_quantize_exact(NUMERIC, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.fn_ia5_quantize_exact(NUMERIC, INTEGER, TEXT) IS
  'IA-5 internal exact-scale bridge for integer constants; never rounds and has no external EXECUTE grant.';
