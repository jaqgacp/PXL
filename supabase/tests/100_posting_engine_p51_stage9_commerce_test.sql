-- POSTING-ENGINE-P51-009 — Stage 9 (Purchase Return + Cash Sale)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

CREATE TEMP VIEW v_commerce_writer AS
SELECT unnest(ARRAY[
  'fn_complete_purchase_return_source_locked_impl',
  'fn_save_cash_sale'
]) AS proname;

SELECT is(
  (SELECT count(*)::int
     FROM v_commerce_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~
      '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'),
  0, 'neither Commerce writer mutates a ledger table directly');                    -- 1

SELECT is(
  (SELECT count(*)::int
     FROM v_commerce_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'fn_create_posted_journal_entry'
      AND p.prosrc ~ 'fn_add_posting_line_push'),
  2, 'both Commerce writers use the existing header and line kernels');              -- 2

SELECT ok(
  (SELECT p.prosrc ~ 'p_discard_journal'
      AND pg_get_function_arguments(p.oid) ~
          'p_discard_journal boolean DEFAULT false'
      AND p.prosrc ~
          'IF p_discard_journal THEN\s+UPDATE journal_entries'
      AND p.prosrc ~ 'DELETE FROM journal_entry_lines'
      AND p.prosrc ~ 'DELETE FROM journal_entries'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  'the Purchase Return fallback sequence is exact and default-off');                -- 3

SELECT ok(
  (SELECT p.prosrc ~ 'p_discard_journal => true'
      AND p.prosrc ~ 'v_je_id := NULL'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_complete_purchase_return_source_locked_impl'),
  'Purchase Return retains its historical no-JE fallback');                         -- 4

SELECT ok(
  (SELECT p.prosrc ~ 'fn_resolve_posting_account'
      AND p.prosrc ~ 'v_vb_count'
      AND p.prosrc ~ 'v_total_cr = 0'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_complete_purchase_return_source_locked_impl'),
  'Purchase Return validation, posted-bill attribution, and fallback gate remain'); -- 5

SELECT ok(
  (SELECT strpos(p.prosrc, 'ROUND(v_net * v_rate / 100, 2)') > 0
      AND p.prosrc ~ 'CWT % does not match ATC rate'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_save_cash_sale'),
  'Cash Sale calculation and CWT validation remain unchanged');                     -- 6

SELECT is(
  (SELECT (SELECT count(*)::int
             FROM regexp_matches(
               p.prosrc, 'fn_create_posted_journal_entry', 'g'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_save_cash_sale'),
  2, 'Cash Sale still creates exactly the SI and OR journals');                      -- 7

SELECT is(
  (SELECT (SELECT count(*)::int
             FROM regexp_matches(
               p.prosrc, 'fn_add_posting_line_push', 'g'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_save_cash_sale'),
  6, 'Cash Sale retains its six conditional/loop line sites');                      -- 8

SELECT ok(
  (SELECT p.prosrc ~ $$'system', 'regular', false, false, false$$
      AND p.prosrc ~ $$'control'$$
      AND p.prosrc ~ $$'base'$$
      AND p.prosrc ~ $$'tax'$$
      AND p.prosrc ~ $$'withholding'$$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_save_cash_sale'),
  'Cash Sale posting_origin and every line role remain explicit');                  -- 9

SELECT ok(
  (SELECT p.prosrc ~ 'tax_detail_entries'
      AND p.prosrc ~ $$'output_vat'$$
      AND p.prosrc ~ $$'cwt_receivable'$$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_save_cash_sale'),
  'Cash Sale tax-detail persistence remains unchanged');                           -- 10

SELECT ok(
  (SELECT p.prosrc ~ 'sales_invoices SET'
      AND p.prosrc ~ 'receipts SET status'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_save_cash_sale'),
  'Cash Sale document lifecycle remains unchanged');                              -- 11

SELECT ok(
  (SELECT p.prosrc ~ 'fn_next_document_number'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_complete_purchase_return_source_locked_impl')
   AND
   (SELECT p.prosrc ~ 'fn_next_document_number'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_save_cash_sale'),
  'Purchase Return and Cash Sale numbering calls remain');                         -- 12

SELECT ok(
  (SELECT p.prosrc !~ 'fn_complete_purchase_return|fn_save_cash_sale'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'Stage 9 adds no writer or exception to the classifier');                         -- 13

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the guard');                                       -- 14

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE writer_function IN (SELECT proname FROM v_commerce_writer)),
  0, 'both Commerce writers are absent from the current violation census');         -- 15

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN (
        'fn_complete_purchase_return_source_locked_impl',
        'fn_save_cash_sale',
        'fn_post_manual_je',
        'fn_close_fiscal_year',
        'fn_execute_recurring_template_source_locked_impl')
      AND p.prosrc ~
        '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'),
  0, 'all complex lifecycle writers are structurally drained');                    -- 16

SELECT * FROM finish();
ROLLBACK;
