-- ============================================================================
-- IA-5 immutable-authority diagnostic correction
-- ============================================================================
-- Corrects the guard diagnostic placeholder.  Trigger enforcement and SQLSTATE
-- remain unchanged.

CREATE OR REPLACE FUNCTION public.fn_ia5_reject_immutable_inventory_fact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '23514',
    MESSAGE = format(
      'IA-5 immutable Inventory authority rejects %s on public.%I',
      TG_OP,
      TG_TABLE_NAME
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_ia5_reject_immutable_inventory_fact()
  FROM PUBLIC, anon, authenticated, service_role;
