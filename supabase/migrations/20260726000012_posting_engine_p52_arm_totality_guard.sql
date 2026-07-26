-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.2: arm the Kernel Totality Guard
--
-- P5.1 certified:
--   * zero forward writers outside the kernel;
--   * zero canonical violation events;
--   * exactly six sanctioned persistence functions.
--
-- P5.2 changes only enforcement:
--   * c_enforce becomes true;
--   * every non-kernel mutation is rejected, including maintenance/replay code.
--   * obsolete client DML grants on the two ledger tables are removed so an
--     unauthorized UPDATE/DELETE raises rather than becoming an RLS no-op.
--
-- The maintenance classification remains evidence metadata, but it is no longer
-- an enforcement exception. No classifier member, routing rule, or accounting
-- behavior changes.
-- ══════════════════════════════════════════════════════════════════════════════

DO $migration$
DECLARE
  v_signature  REGPROCEDURE :=
    'public.fn_guard_journal_kernel_origin()'::REGPROCEDURE;
  v_definition TEXT;
  v_before     TEXT;
  v_after      TEXT;
BEGIN
  SELECT pg_get_functiondef(v_signature) INTO v_definition;

  v_before := 'c_enforce  CONSTANT BOOLEAN := false;';
  v_after  := 'c_enforce  CONSTANT BOOLEAN := true;';
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION
      'P5.2 source drift: observe-mode enforcement constant not found';
  END IF;
  v_definition := replace(v_definition, v_before, v_after);

  v_before := 'IF c_enforce AND NOT v_maint THEN';
  v_after  := 'IF c_enforce THEN';
  IF strpos(v_definition, v_before) = 0 THEN
    RAISE EXCEPTION
      'P5.2 source drift: maintenance enforcement exception not found';
  END IF;

  EXECUTE replace(v_definition, v_before, v_after);
END;
$migration$;

REVOKE ALL ON FUNCTION public.fn_guard_journal_kernel_origin()
  FROM PUBLIC, anon, authenticated;

REVOKE INSERT, UPDATE, DELETE
  ON TABLE public.journal_entries, public.journal_entry_lines
  FROM PUBLIC, anon, authenticated;

-- Replay/migration sessions commonly use session_replication_role=replica.
-- An ALWAYS trigger is therefore required for totality to remain non-bypassable.
ALTER TABLE public.journal_entries
  ENABLE ALWAYS TRIGGER zz_trg_journal_entries_kernel_origin;
ALTER TABLE public.journal_entry_lines
  ENABLE ALWAYS TRIGGER zz_trg_journal_entry_lines_kernel_origin;
