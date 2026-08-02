-- POSTING-ENGINE-P51-005 — Stage 5, Batch C (Inventory GL persistence)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

CREATE TEMP VIEW v_inventory_writer AS
SELECT unnest(ARRAY[
  'fn_post_goods_issue_source_locked_impl',
  'fn_post_physical_count_source_locked_impl',
  'fn_post_stock_adjustment_source_locked_impl',
  'fn_post_stock_transfer_source_locked_impl'
]) AS proname;

SELECT is(
  (SELECT count(*)::int
     FROM v_inventory_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~
      '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'),
  0, 'no core Inventory writer mutates either ledger table directly');                -- 1

SELECT is(
  (SELECT count(*)::int
     FROM v_inventory_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'fn_create_posted_journal_entry'
      AND p.prosrc ~ 'fn_add_posting_line_push'),
  4, 'all four Inventory writers use the existing header and line kernels');          -- 2

SELECT is(
  (SELECT count(*)::int
     FROM v_inventory_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~* 'company_accounting_config'),
  0, 'Inventory account ownership remains item/warehouse scoped');                    -- 3

-- PXL-AUD-073 governs inventory control and purchase clearing through
-- company_accounting_config. No COGS, variance or offset key was invented.
SELECT is(
  (SELECT count(*)::int FROM ref_mapping_key
    WHERE key_code ~* 'cogs|variance|offset'),
  0, 'no COGS/variance/offset mapping keys were invented');                           -- 4

SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'inventory_transactions'
                   AND p.prosrc ~ 'stock_balances')
     FROM v_inventory_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'),
  'Inventory balance and movement persistence remains in every writer');              -- 5

SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'fn_next_document_number')
     FROM v_inventory_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'),
  'Inventory journal numbering calls are unchanged');                                -- 6

SELECT ok(
  (SELECT p.prosrc ~ 'p_persist_totals'
      AND pg_get_function_arguments(p.oid) ~
          'p_persist_totals boolean DEFAULT false'
      AND p.prosrc ~ 'IF p_persist_totals THEN\s+UPDATE journal_entries'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  'the finalizer has an explicit default-off exact totals persistence path');         -- 7

SELECT ok(
  (SELECT p.prosrc ~ $$reference_doc_type = 'INV_COUNT'$$
      AND p.prosrc ~ $$RAISE EXCEPTION 'Posted journal entry % has no lines'$$
      AND p.prosrc ~ $$RAISE EXCEPTION 'Journal entry % is unbalanced$$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  'the certified one-argument finalizer validation and zero-line carve-out remain'); -- 8

SELECT ok(
  (SELECT p.prosrc !~
      'fn_post_goods_issue|fn_post_physical_count|fn_post_stock_adjustment|fn_post_stock_transfer'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'Batch C adds no writer or exception to the classifier');                           -- 9

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the guard');                                         -- 10

-- Minimal exact-update probe for Goods Issue / Physical Count audit parity.
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f550000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p55-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f550000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f550000-0000-0000-0000-0000000000b1', 'corporation', 'P55 Inventory Corp',
        'Trading', '382-000-001-00000', 'non_vat', 'calendar',
        'I St', 'I Bldg', 'Makati', 'Metro Manila', '1200',
        'p55-owner@test.local', 'I Owner', 'President', auth.uid(), auth.uid());
INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('0f550000-0000-0000-0000-0000000000b2',
        '0f550000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'I St', 'I Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());
INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f550000-0000-0000-0000-0000000000f1',
        '0f550000-0000-0000-0000-0000000000b1',
        'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (id, company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
VALUES ('0f550000-0000-0000-0000-0000000000f2',
        '0f550000-0000-0000-0000-0000000000b1',
        '0f550000-0000-0000-0000-0000000000f1',
        6, 'Jun 2026', '2026-06-01', '2026-06-30', false);

CREATE TEMP TABLE t_before AS
SELECT count(*) AS violations FROM sys_posting_guard_violations;
CREATE TEMP TABLE t_journal AS
SELECT fn_create_posted_journal_entry(
  '0f550000-0000-0000-0000-0000000000b1',
  '0f550000-0000-0000-0000-0000000000b2',
  'JE-P55-TOTALS', '2026-06-15', 'Inventory totals probe',
  'MANUAL', NULL, NULL, 'posted', 0, 0, NULL, 'regular', false, false, true
) AS id;
SELECT fn_finalize_journal_entry(
  (SELECT id FROM t_journal), 250, 250, true
);

SELECT results_eq(
  $q$SELECT action
       FROM sys_audit_logs
      WHERE table_name='journal_entries' AND record_id=(SELECT id FROM t_journal)
      ORDER BY CASE action WHEN 'INSERT' THEN 1 ELSE 2 END$q$,
  $$VALUES ('INSERT'::text), ('UPDATE'::text)$$,
  'the historical header INSERT then totals UPDATE audit sequence is preserved');    -- 11

SELECT results_eq(
  $q$SELECT (old_data->>'total_debit')::numeric,
            (old_data->>'total_credit')::numeric,
            (new_data->>'total_debit')::numeric,
            (new_data->>'total_credit')::numeric
       FROM sys_audit_logs
      WHERE table_name='journal_entries' AND record_id=(SELECT id FROM t_journal)
        AND action='UPDATE'$q$,
  $$VALUES (0::numeric, 0::numeric, 250::numeric, 250::numeric)$$,
  'the totals UPDATE audit OLD/NEW images are unchanged');                            -- 12

SELECT results_eq(
  $q$SELECT total_debit, total_credit, posting_origin, entry_class, auto_reverse
       FROM journal_entries WHERE id=(SELECT id FROM t_journal)$q$,
  $$VALUES (250::numeric, 250::numeric, NULL::text, 'regular'::text, false)$$,
  'the final inventory-style header totals and metadata are unchanged');              -- 13

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations),
  (SELECT violations::int FROM t_before),
  'kernel-owned header creation and totals update add zero violations');              -- 14

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE writer_function IN (
      'fn_post_goods_issue_source_locked_impl',
      'fn_post_physical_count_source_locked_impl',
      'fn_post_stock_adjustment_source_locked_impl',
      'fn_post_stock_transfer_source_locked_impl')),
  0, 'the four Inventory writers are absent from the violation census');              -- 15

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  1, 'the finalizer retains one unambiguous signature');                              -- 16

SELECT is(
  (SELECT count(*)::int
     FROM v_inventory_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'No open fiscal period for date %'),
  4, 'all four period rejection messages remain verbatim');                           -- 17

SELECT is(
  (SELECT count(*)::int
     FROM v_inventory_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ $$IF .*status = 'posted' THEN RAISE EXCEPTION 'Already posted'$$),
  4, 'all four lifecycle rejection messages remain verbatim');                        -- 18

SELECT * FROM finish();
ROLLBACK;
