-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 readiness closure (OBSERVE-ONLY)
--
-- The approved forward-writer census is now fully routed through the frozen
-- Posting Engine kernels. This migration closes two residual structural risks:
--   1. remove an obsolete, unreachable line helper that still contained raw ledger
--      persistence outside the sanctioned helper set;
--   2. anchor every classifier member at its opening parenthesis so a function
--      whose name merely begins with a sanctioned name is never classified as
--      kernel-origin.
--
-- The sanctioned set does not grow. The guard remains observe-only.
-- ══════════════════════════════════════════════════════════════════════════════

DO $migration$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname <> 'fn_add_posting_line_core_20260718'
      AND strpos(p.prosrc, 'fn_add_posting_line_core_20260718') > 0
  ) THEN
    RAISE EXCEPTION
      'P5.1 readiness closure: legacy line helper still has a database caller';
  END IF;
END;
$migration$;

DROP FUNCTION public.fn_add_posting_line_core_20260718(
  uuid, integer, uuid, text, numeric, numeric, uuid, uuid, uuid
);

CREATE OR REPLACE FUNCTION public.fn_posting_kernel_origin(p_context TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $function$
  -- The same six sanctioned persistence functions, now matched as exact function
  -- names in a PL/pgSQL stack frame. The opening parenthesis prevents lookalike
  -- names (for example fn_add_posting_line_extra) from inheriting kernel status.
  SELECT p_context ~ ('fn_create_posted_journal_entry\('
                   || '|fn_reverse_posted_journal_entry\('
                   || '|fn_finalize_journal_entry\('
                   || '|fn_add_posting_line\('
                   || '|fn_add_posting_line_push\('
                   || '|fn_add_sales_invoice_posting_line\(');
$function$;

REVOKE ALL ON FUNCTION public.fn_posting_kernel_origin(TEXT)
  FROM PUBLIC, anon, authenticated;

