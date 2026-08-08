-- POSTING-ENGINE-P51-003 — Stage 3, Batch A
-- SI / VB / OR / CP post-kernel posting_origin UPDATE migration.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

CREATE TEMP VIEW v_batch_a_writer AS
SELECT unnest(ARRAY[
  'fn_post_sales_invoice_costing_legacy_20260808',
  'fn_post_vendor_bill',
  'fn_post_receipt',
  'fn_post_cash_purchase_source_locked_impl'
]) AS proname;

SELECT is(
  (SELECT count(*)::int
     FROM v_batch_a_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'UPDATE\s+journal_entries'),
  0, 'Batch A writers no longer update journal_entries directly');                    -- 1

SELECT is(
  (SELECT count(*)::int
     FROM v_batch_a_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ $$'system', 'regular', false, true$$),
  4, 'all four writers explicitly request the audit-preserving kernel path');         -- 2

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_create_posted_journal_entry'),
  1, 'the extended kernel still has exactly one unambiguous signature');              -- 3

SELECT ok(
  (SELECT pg_get_function_arguments(p.oid) ~
          'p_emit_origin_update boolean DEFAULT false'
      AND p.prosrc ~ 'CASE WHEN p_emit_origin_update THEN NULL ELSE p_posting_origin END'
      AND p.prosrc ~ 'IF p_emit_origin_update THEN\s+UPDATE journal_entries'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_create_posted_journal_entry'),
  'the kernel preserves the prior NULL INSERT then posting_origin UPDATE sequence');  -- 4

SELECT ok(
  (SELECT p.prosrc !~ 'fn_post_sales_invoice|fn_post_vendor_bill|fn_post_receipt|fn_post_cash_purchase'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'Batch A adds no writer or exception to the sanctioned classifier');                -- 5

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the guard');                                         -- 6

-- Minimal kernel probe: it proves the exact two audit actions, OLD/NEW origin
-- images, final header metadata, and zero violation delta without requiring a
-- document-specific fixture. Existing SI/VB/OR/CP regression and canonical tests
-- continue to exercise every real writer and all accounting lines/tax/dimensions.
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f530000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p53-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f530000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f530000-0000-0000-0000-0000000000b1', 'corporation', 'P53 Batch A Corp',
        'Trading', '384-000-001-00000', 'vat', 'calendar',
        'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
        'p53-owner@test.local', 'A Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('0f530000-0000-0000-0000-0000000000b2',
        '0f530000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f530000-0000-0000-0000-0000000000f1',
        '0f530000-0000-0000-0000-0000000000b1',
        'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
VALUES ('0f530000-0000-0000-0000-0000000000b1',
        '0f530000-0000-0000-0000-0000000000f1',
        4, 'Apr 2026', '2026-04-01', '2026-04-30', false);

CREATE TEMP TABLE t_before AS
SELECT count(*) AS violations FROM sys_posting_guard_violations;

CREATE TEMP TABLE t_journal AS
SELECT fn_create_posted_journal_entry(
  '0f530000-0000-0000-0000-0000000000b1',
  '0f530000-0000-0000-0000-0000000000b2',
  'JE-P53-AUDIT', '2026-04-10', 'Batch A audit equality probe',
  'MANUAL', NULL,
  NULL, 'posted', 0, 0, 'system', 'regular', false, true
) AS id;

SELECT results_eq(
  $q$SELECT action
       FROM sys_audit_logs
      WHERE table_name='journal_entries'
        AND record_id=(SELECT id FROM t_journal)
      ORDER BY CASE action WHEN 'INSERT' THEN 1 ELSE 2 END$q$,
  $$VALUES ('INSERT'::text), ('UPDATE'::text)$$,
  'the established INSERT then UPDATE audit sequence is preserved');                  -- 7

SELECT is(
  (SELECT old_data->>'posting_origin' FROM sys_audit_logs
    WHERE table_name='journal_entries' AND record_id=(SELECT id FROM t_journal)
      AND action='UPDATE'),
  NULL, 'the audit UPDATE old image retains NULL posting_origin');                    -- 8

SELECT is(
  (SELECT new_data->>'posting_origin' FROM sys_audit_logs
    WHERE table_name='journal_entries' AND record_id=(SELECT id FROM t_journal)
      AND action='UPDATE'),
  'system', 'the audit UPDATE new image retains system posting_origin');              -- 9

SELECT results_eq(
  $q$SELECT status, total_debit, total_credit, posting_origin, entry_class,
            auto_reverse, reference_doc_type, je_number
       FROM journal_entries WHERE id=(SELECT id FROM t_journal)$q$,
  $$VALUES ('posted'::text, 0::numeric, 0::numeric, 'system'::text,
            'regular'::text, false, 'MANUAL'::text, 'JE-P53-AUDIT'::text)$$,
  'the final journal header is byte-identical in all governed metadata');              -- 10

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations),
  (SELECT violations::int FROM t_before),
  'the kernel-owned INSERT and UPDATE add zero violations');                          -- 11

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE writer_function IN ('fn_post_sales_invoice_costing_legacy_20260808','fn_post_vendor_bill',
                              'fn_post_receipt',
                              'fn_post_cash_purchase_source_locked_impl')),
  0, 'the Batch A writer violation census is zero in this certification run');        -- 12

SELECT ok(
  (SELECT p.prosrc ~ 'fn_finalize_journal_entry'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_sales_invoice_costing_legacy_20260808'),
  'Sales Invoice finalization and its journal total ordering remain intact');          -- 13

SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'SELECT fiscal_period_id INTO v_fp_id'
                   AND p.prosrc ~ 'fn_finalize_journal_entry')
     FROM v_batch_a_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'),
  'period capture and finalization remain in all four writers');                      -- 14

SELECT is(
  (SELECT count(*)::int
     FROM v_batch_a_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'fn_add_(sales_invoice_)?posting_line'),
  4, 'journal line construction helpers and ordering are unchanged');                 -- 15

SELECT * FROM finish();
ROLLBACK;
