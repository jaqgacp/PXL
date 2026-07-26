-- POSTING-ENGINE-P51-004 — Stage 4, Batch B (Manual Journal)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

SELECT ok(
  (SELECT p.prosrc !~ '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'
      AND p.prosrc ~ 'fn_create_posted_journal_entry'
      AND p.prosrc ~ 'fn_add_posting_line_push'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  'Manual Journal touches neither ledger table directly');                            -- 1

SELECT ok(
  (SELECT p.prosrc ~ 'fn_assert_manual_postable'
      AND strpos(p.prosrc, 'fn_assert_manual_postable') >
          strpos(p.prosrc, $$RAISE EXCEPTION 'Account % is inactive'$$)
      AND strpos(p.prosrc, 'fn_assert_manual_postable') <
          strpos(p.prosrc, 'v_total_debit  := v_total_debit + v_dr')
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  'the P3C validator remains after all legacy account checks and before totals');      -- 2

SELECT ok(
  (SELECT strpos(p.prosrc, 'SELECT COUNT(*) + 1 INTO v_seq') > 0
      AND strpos(p.prosrc, $$'MJE-' || TO_CHAR(p_je_date, 'YYYYMM')$$) > 0
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  'the established MJE numbering algorithm is unchanged');                           -- 3

SELECT ok(
  (SELECT p.prosrc ~ 'No open fiscal period covers % — posting is not allowed'
      AND strpos(p.prosrc, 'No open fiscal period covers') <
          strpos(p.prosrc, 'SELECT COUNT(*) + 1 INTO v_seq')
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  'period validation and its verbatim message remain before numbering');              -- 4

SELECT ok(
  (SELECT strpos(p.prosrc,
          $$v_fp_id, 'posted', v_total_debit, v_total_credit$$) > 0
      AND strpos(p.prosrc,
          $$NULL, v_entry_class, COALESCE(p_auto_reverse, false)$$) > 0
      AND strpos(p.prosrc, 'false, false') > 0
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_manual_je'),
  'header totals, NULL origin, entry_class, auto_reverse, and deferred validation are explicit'); -- 5

SELECT ok(
  (SELECT p.prosrc ~ 'p_assert_source'
      AND pg_get_function_arguments(p.oid) ~ 'p_assert_source boolean DEFAULT true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_create_posted_journal_entry'),
  'the kernel defaults source assertion on; only an explicit caller preserves deferral'); -- 6

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the guard');                                         -- 7

SELECT ok(
  (SELECT p.prosrc !~ 'fn_post_manual_je'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'Manual Journal adds no classifier exception');                                     -- 8

-- Behavioural fixture.
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f540000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p54-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f540000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f540000-0000-0000-0000-0000000000b1', 'corporation', 'P54 Manual Corp',
        'Services', '383-000-001-00000', 'non_vat', 'calendar',
        'M St', 'M Bldg', 'Makati', 'Metro Manila', '1200',
        'p54-owner@test.local', 'M Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('0f540000-0000-0000-0000-0000000000b2',
        '0f540000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'M St', 'M Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f540000-0000-0000-0000-0000000000f1',
        '0f540000-0000-0000-0000-0000000000b1',
        'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (id, company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
VALUES ('0f540000-0000-0000-0000-0000000000f2',
        '0f540000-0000-0000-0000-0000000000b1',
        '0f540000-0000-0000-0000-0000000000f1',
        5, 'May 2026', '2026-05-01', '2026-05-31', false);

INSERT INTO departments (id, company_id, department_code, department_name,
                         is_active, created_by, updated_by)
VALUES ('0f540000-0000-0000-0000-0000000000d1',
        '0f540000-0000-0000-0000-0000000000b1',
        'OPS', 'Operations', true, auth.uid(), auth.uid());
INSERT INTO cost_centers (id, company_id, cost_center_code, cost_center_name,
                          is_active, created_by, updated_by)
VALUES ('0f540000-0000-0000-0000-0000000000c1',
        '0f540000-0000-0000-0000-0000000000b1',
        'OPS', 'Operations', true, auth.uid(), auth.uid());

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
 ('0f540000-0000-0000-0000-0000000000a1',
  '0f540000-0000-0000-0000-0000000000b1',
  '1000', 'Manual Debit', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
 ('0f540000-0000-0000-0000-0000000000a2',
  '0f540000-0000-0000-0000-0000000000b1',
  '4000', 'Manual Credit', 'revenue', 'credit', true, true, auth.uid(), auth.uid());

CREATE TEMP TABLE t_before AS
SELECT count(*) AS violations FROM sys_posting_guard_violations;

CREATE TEMP TABLE t_manual AS
SELECT fn_post_manual_je(
  '0f540000-0000-0000-0000-0000000000b1',
  '0f540000-0000-0000-0000-0000000000b2',
  '2026-05-15', 'Manual certification', 'MANUAL', true,
  jsonb_build_array(
    jsonb_build_object(
      'account_id','0f540000-0000-0000-0000-0000000000a1',
      'description','Debit line','debit_amount',1250,'credit_amount',0,
      'branch_id','0f540000-0000-0000-0000-0000000000b2',
      'department_id','0f540000-0000-0000-0000-0000000000d1',
      'cost_center_id','0f540000-0000-0000-0000-0000000000c1'),
    jsonb_build_object(
      'account_id','0f540000-0000-0000-0000-0000000000a2',
      'description','Credit line','debit_amount',0,'credit_amount',1250,
      'branch_id','0f540000-0000-0000-0000-0000000000b2',
      'department_id','0f540000-0000-0000-0000-0000000000d1',
      'cost_center_id','0f540000-0000-0000-0000-0000000000c1')
  ),
  'adjusting'
) AS id;

SELECT results_eq(
  $q$SELECT je_number, status, total_debit, total_credit, posting_origin,
            entry_class, auto_reverse, is_auto_reversal, reference_doc_type,
            fiscal_period_id
       FROM journal_entries WHERE id=(SELECT id FROM t_manual)$q$,
  $$VALUES ('MJE-202605-0001'::text, 'posted'::text, 1250::numeric,
            1250::numeric, NULL::text, 'adjusting'::text, true, false,
            'MANUAL'::text, '0f540000-0000-0000-0000-0000000000f2'::uuid)$$,
  'Manual header, numbering, classification, origin, reversal flag, and period are unchanged'); -- 9

SELECT results_eq(
  $q$SELECT line_number, account_id, description, debit_amount, credit_amount,
            line_role, source_line_id, branch_id, department_id, cost_center_id,
            project_id, location_id, functional_entity_id
       FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_manual)
      ORDER BY line_number$q$,
  $$VALUES
    (1, '0f540000-0000-0000-0000-0000000000a1'::uuid, 'Debit line'::text,
     1250::numeric, 0::numeric, NULL::text, NULL::uuid,
     '0f540000-0000-0000-0000-0000000000b2'::uuid,
     '0f540000-0000-0000-0000-0000000000d1'::uuid,
     '0f540000-0000-0000-0000-0000000000c1'::uuid,
     NULL::uuid, NULL::uuid, NULL::uuid),
    (2, '0f540000-0000-0000-0000-0000000000a2'::uuid, 'Credit line'::text,
     0::numeric, 1250::numeric, NULL::text, NULL::uuid,
     '0f540000-0000-0000-0000-0000000000b2'::uuid,
     '0f540000-0000-0000-0000-0000000000d1'::uuid,
     '0f540000-0000-0000-0000-0000000000c1'::uuid,
     NULL::uuid, NULL::uuid, NULL::uuid)$$,
  'Manual lines are byte-identical in order, amounts, roles, provenance, and dimensions'); -- 10

SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
    WHERE table_name='journal_entries' AND record_id=(SELECT id FROM t_manual)
      AND action='INSERT'),
  1, 'Manual Journal still emits exactly one header INSERT audit row');                -- 11

SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
    WHERE table_name='journal_entries' AND record_id=(SELECT id FROM t_manual)
      AND action<>'INSERT'),
  0, 'Manual Journal emits no new header audit action');                              -- 12

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations),
  (SELECT violations::int FROM t_before),
  'posting the Manual Journal adds zero violations');                                 -- 13

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE writer_function='fn_post_manual_je'),
  0, 'Manual Journal is absent from the header and line violation census');           -- 14

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE je_id=(SELECT id FROM t_manual)),
  2, 'Manual Journal line count is unchanged');                                       -- 15

SELECT is(
  (SELECT sum(debit_amount)-sum(credit_amount)
     FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_manual)),
  0::numeric, 'Manual Journal GL remains exactly balanced');                          -- 16

SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
    WHERE source_doc_type='MANUAL' AND source_doc_id=(SELECT id FROM t_manual)),
  0, 'Manual Journal introduces no tax detail');                                      -- 17

SELECT is(
  (SELECT count(*)::int FROM inventory_transactions
    WHERE journal_entry_id=(SELECT id FROM t_manual)),
  0, 'Manual Journal introduces no inventory movement');                             -- 18

SELECT throws_ok(
  $$SELECT fn_post_manual_je(
      '0f540000-0000-0000-0000-0000000000b1',
      '0f540000-0000-0000-0000-0000000000b2',
      '2026-05-15', 'Bad class', 'MANUAL', false,
      jsonb_build_array(
        jsonb_build_object('account_id','0f540000-0000-0000-0000-0000000000a1',
                           'debit_amount',1,'credit_amount',0),
        jsonb_build_object('account_id','0f540000-0000-0000-0000-0000000000a2',
                           'debit_amount',0,'credit_amount',1)),
      'closing')$$,
  'Manual journal entries may only be classified regular, adjusting, or opening (got closing). Closing entries are posted by the year-end close.',
  'entry_class rejection text remains verbatim');                                    -- 19

SELECT throws_ok(
  $$SELECT fn_post_manual_je(
      '0f540000-0000-0000-0000-0000000000b1',
      '0f540000-0000-0000-0000-0000000000b2',
      '2026-06-15', 'Locked period', 'MANUAL', false,
      jsonb_build_array(
        jsonb_build_object('account_id','0f540000-0000-0000-0000-0000000000a1',
                           'debit_amount',1,'credit_amount',0),
        jsonb_build_object('account_id','0f540000-0000-0000-0000-0000000000a2',
                           'debit_amount',0,'credit_amount',1)),
      'regular')$$,
  'No open fiscal period covers 2026-06-15 — posting is not allowed',
  'period rejection text remains verbatim');                                         -- 20

SELECT is(
  (SELECT count(*)::int FROM journal_entries
    WHERE company_id='0f540000-0000-0000-0000-0000000000b1'),
  1, 'failed Manual Journals leave no partial header');                               -- 21

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE company_id='0f540000-0000-0000-0000-0000000000b1'),
  2, 'failed Manual Journals leave no partial lines');                                -- 22

SELECT * FROM finish();
ROLLBACK;
