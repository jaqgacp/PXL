-- POSTING-ENGINE-P51-006 — Stage 6 (Treasury writers)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

CREATE TEMP VIEW v_treasury_writer AS
SELECT unnest(ARRAY[
  'fn_post_bank_adjustment_source_locked_impl',
  'fn_post_fund_transfer_source_locked_impl',
  'fn_post_inter_branch_transfer_source_locked_impl',
  'fn_approve_petty_cash_voucher_source_locked_impl',
  'fn_post_petty_cash_replenishment_source_locked_impl',
  'fn_post_check_voucher'
]) AS proname;

SELECT is(
  (SELECT count(*)::int
     FROM v_treasury_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~
      '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'),
  0, 'no Treasury writer mutates either ledger table directly');                     -- 1

SELECT is(
  (SELECT count(*)::int
     FROM v_treasury_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'fn_create_posted_journal_entry'
      AND p.prosrc ~ 'fn_add_posting_line_push'),
  6, 'all six Treasury writers use the existing header and line kernels');           -- 2

SELECT is(
  (SELECT count(*)::int
     FROM v_treasury_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'No open fiscal period for'),
  6, 'all Treasury period validations and message sites remain');                    -- 3

SELECT is(
  (SELECT count(*)::int
     FROM v_treasury_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ $$status != 'draft'$$),
  6, 'all Treasury draft lifecycle gates remain');                                   -- 4

SELECT ok(
  (SELECT p.prosrc ~ 'fn_validate_payment_voucher_line_ewt'
      AND p.prosrc ~ 'tax_detail_entries'
      AND p.prosrc ~ 'v_atc_rate'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_check_voucher'),
  'Check Voucher validation and tax-detail provenance remain intact');                -- 5

SELECT ok(
  (SELECT p.prosrc ~ $$'JE-CV-' \|\| v_rec.cv_number$$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_check_voucher'),
  'Check Voucher source-derived journal numbering remains intact');                  -- 6

SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'journal_entry_id = v_je_id'
                   AND p.prosrc ~ 'posted_at = NOW\(\)')
     FROM v_treasury_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'),
  'Treasury document linking and posting timestamps remain intact');                  -- 7

SELECT ok(
  (SELECT p.prosrc ~ 'petty_cash_vouchers SET status = ''replenished'''
      AND p.prosrc ~ 'replenishment_id = v_rec.id'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_post_petty_cash_replenishment_source_locked_impl'),
  'Petty Cash Replenishment lifecycle side effects remain intact');                  -- 8

SELECT ok(
  (SELECT p.prosrc !~
      'fn_post_bank_adjustment|fn_post_fund_transfer|fn_post_inter_branch_transfer|fn_approve_petty_cash|fn_post_petty_cash|fn_post_check_voucher'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'Treasury adds no writer or exception to the classifier');                         -- 9

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the guard');                                        -- 10

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE writer_function IN (SELECT proname FROM v_treasury_writer)),
  0, 'Treasury writers are absent from the current violation census');               -- 11

SELECT is(
  (SELECT count(*)::int
     FROM v_treasury_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'fn_add_posting_line_push'),
  6, 'Treasury journal ordering is expressed only through explicit line numbers');   -- 12

SELECT * FROM finish();
ROLLBACK;
