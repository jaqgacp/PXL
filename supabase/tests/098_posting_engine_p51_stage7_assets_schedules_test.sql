-- POSTING-ENGINE-P51-007 — Stage 7 (Fixed Assets + Schedules)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

CREATE TEMP VIEW v_asset_schedule_writer AS
SELECT unnest(ARRAY[
  'fn_post_depreciation_entry_source_locked_impl',
  'fn_post_amortization_entry_source_locked_impl',
  'fn_post_revenue_recognition_entry_source_locked_impl',
  'fn_register_fixed_asset',
  'fn_dispose_fixed_asset',
  'fn_record_impairment'
]) AS proname;

SELECT is(
  (SELECT count(*)::int
     FROM v_asset_schedule_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~
      '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'),
  0, 'no Fixed Asset or schedule writer mutates either ledger table directly');       -- 1

SELECT is(
  (SELECT count(*)::int
     FROM v_asset_schedule_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'fn_create_posted_journal_entry'
      AND p.prosrc ~ 'fn_add_posting_line_push'),
  6, 'all six writers use the existing header and line kernels');                    -- 2

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_link_fixed_asset_journal_source',
                        'fn_link_schedule_journal_source',
                        'fn_link_purchase_return_journal_source',
                        'fn_complete_secondary_posting')
      AND p.prosrc ~ 'UPDATE\s+journal_entries'),
  0, 'all post-insert source links are kernel-routed');                              -- 3

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_link_fixed_asset_journal_source',
                        'fn_link_schedule_journal_source',
                        'fn_link_purchase_return_journal_source',
                        'fn_complete_secondary_posting')
      AND p.prosrc ~ 'fn_finalize_journal_entry'),
  4, 'all four source-link paths use the sanctioned finalizer');                     -- 4

SELECT ok(
  (SELECT pg_get_function_arguments(p.oid) ~
          'p_link_source boolean DEFAULT false'
      AND p.prosrc ~ 'IF p_link_source THEN\s+UPDATE journal_entries'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  'source linking is explicit and default-off');                                    -- 5

SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'fn_next_document_number'
                   OR p.prosrc ~ $$'AMT-' \|\| TO_CHAR$$
                   OR p.prosrc ~ $$'RR-' \|\| TO_CHAR$$)
     FROM v_asset_schedule_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'),
  'all established asset and schedule numbering algorithms remain');                -- 6

SELECT ok(
  (SELECT p.prosrc ~ 'fn_compute_depr_schedule'
      AND p.prosrc ~ 'asset_depreciation_entries'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_register_fixed_asset'),
  'asset acquisition still generates the identical depreciation schedule');         -- 7

SELECT ok(
  (SELECT p.prosrc ~ 'asset_disposals'
      AND p.prosrc ~ $$status = 'disposed'$$
      AND p.prosrc ~ $$status = 'skipped'$$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_dispose_fixed_asset'),
  'asset disposal evidence and lifecycle remain intact');                            -- 8

SELECT ok(
  (SELECT p.prosrc ~ 'asset_impairments'
      AND p.prosrc ~ $$status = 'impaired'$$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_record_impairment'),
  'impairment evidence and lifecycle remain intact');                                -- 9

SELECT is(
  (SELECT count(*)::int
     FROM v_asset_schedule_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'No open fiscal period'),
  6, 'all period validation sites and messages remain');                            -- 10

SELECT ok(
  (SELECT p.prosrc !~
      'fn_post_depreciation|fn_post_amortization|fn_post_revenue_recognition|fn_register_fixed_asset|fn_dispose_fixed_asset|fn_record_impairment|fn_link_'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'Stage 7 adds no writer, trigger, or exception to the classifier');                -- 11

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the guard');                                        -- 12

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE writer_function IN (
      SELECT proname FROM v_asset_schedule_writer
      UNION ALL SELECT 'fn_link_fixed_asset_journal_source'
      UNION ALL SELECT 'fn_link_schedule_journal_source')),
  0, 'asset, schedule, and link paths are absent from the current violation census'); -- 13

SELECT ok(
  (SELECT p.prosrc ~ 'department_id'
      AND p.prosrc ~ 'cost_center_id'
      AND p.prosrc ~ 'project_id'
      AND p.prosrc ~ 'location_id'
      AND p.prosrc ~ 'functional_entity_id'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_register_fixed_asset'),
  'all five optional asset analytical dimensions remain pushed');                   -- 14

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  1, 'the finalizer retains one unambiguous signature');                             -- 15

SELECT ok(
  (SELECT bool_and(p.prosrc ~
           'fn_add_posting_line_push\(\s+v_je_id, 1'
                   AND p.prosrc ~
           'fn_add_posting_line_push\(\s+v_je_id, 2')
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_amortization_entry_source_locked_impl',
                        'fn_post_revenue_recognition_entry_source_locked_impl')),
  'schedule journal line order remains explicitly 1 then 2');                       -- 16

SELECT * FROM finish();
ROLLBACK;
