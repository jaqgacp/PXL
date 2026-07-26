-- POSTING-ENGINE-P51-008 — Stage 8 (Recurring + Fiscal Close)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

CREATE TEMP VIEW v_system_writer AS
SELECT unnest(ARRAY[
  'fn_execute_recurring_template_source_locked_impl',
  'fn_close_fiscal_year'
]) AS proname;

SELECT is(
  (SELECT count(*)::int
     FROM v_system_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~
      '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'),
  0, 'neither system-generated writer mutates a ledger table directly');             -- 1

SELECT is(
  (SELECT count(*)::int
     FROM v_system_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'fn_create_posted_journal_entry'
      AND p.prosrc ~ 'fn_add_posting_line_push'),
  2, 'both system-generated writers use the existing kernels');                     -- 2

SELECT ok(
  (SELECT p.prosrc ~ $$'RJE-' \|\| TO_CHAR\(p_je_date, 'YYYYMM'\)$$
      AND p.prosrc ~ 'SELECT COUNT\(\*\) \+ 1 INTO v_seq'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_execute_recurring_template_source_locked_impl'),
  'Recurring numbering is unchanged');                                              -- 3

SELECT ok(
  (SELECT p.prosrc ~ $$'CLOSE-' \|\| TO_CHAR\(v_close_date, 'YYYY'\)$$
      AND p.prosrc ~ 'SELECT COUNT\(\*\) \+ 1 INTO v_seq'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_close_fiscal_year'),
  'Fiscal Close numbering is unchanged');                                           -- 4

SELECT ok(
  (SELECT p.prosrc ~ $$'closing'$$
      AND p.prosrc ~ 'v_total_debit, v_total_credit'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_close_fiscal_year'),
  'Fiscal Close entry_class and totals remain explicit');                           -- 5

SELECT ok(
  (SELECT p.prosrc ~ 'fn_reverse_je'
      AND p.prosrc ~ 'p_mark_auto_reversal => true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_execute_recurring_template_source_locked_impl'),
  'Recurring reversal orchestration and marker remain');                            -- 6

SELECT ok(
  (SELECT pg_get_function_arguments(p.oid) ~
          'p_mark_auto_reversal boolean DEFAULT false'
      AND p.prosrc ~ 'IF p_mark_auto_reversal THEN\s+UPDATE journal_entries'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  'auto-reversal marking is explicit, exact, and default-off');                     -- 7

SELECT ok(
  (SELECT p.prosrc ~ 'ORDER BY line_number'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_execute_recurring_template_source_locked_impl'),
  'Recurring source-line ordering remains explicit');                               -- 8

SELECT ok(
  (SELECT p.prosrc ~ 'ORDER BY MIN\(coa.account_code\)'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_close_fiscal_year'),
  'Fiscal Close P&L line ordering remains explicit');                               -- 9

SELECT ok(
  (SELECT p.prosrc ~ $$status = 'closed'$$
      AND p.prosrc ~ 'fiscal_periods SET is_locked = true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_close_fiscal_year'),
  'Fiscal Close year/period lifecycle remains intact');                            -- 10

SELECT ok(
  (SELECT p.prosrc ~ 'next_run_date = v_next'
      AND p.prosrc ~ 'last_run_date = p_je_date'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_execute_recurring_template_source_locked_impl'),
  'Recurring schedule advancement remains intact');                                -- 11

SELECT ok(
  (SELECT p.prosrc !~ 'fn_execute_recurring|fn_close_fiscal_year'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'Stage 8 adds no writer or exception to the classifier');                         -- 12

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the guard');                                       -- 13

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE writer_function IN (SELECT proname FROM v_system_writer)),
  0, 'both system-generated writers are absent from the violation census');         -- 14

SELECT * FROM finish();
ROLLBACK;
