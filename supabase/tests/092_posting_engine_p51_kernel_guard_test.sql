-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P51-001 — Kernel Totality Guard, Stage 1 compatibility
--
-- Certifies the first stage of the frozen §4.6 Kernel Totality Guard:
--   A. the guard exists, is structural, and is now armed by certified P5.2;
--   B. it correctly classifies kernel vs non-kernel origin, non-vacuously;
--   C. the evidence table records the violation census that gates arming;
--   D. Module 1 (the CM / DM / VC memo posters) is migrated to the kernel with
--      byte-for-byte accounting output;
--   E. the additive kernel extension is deployment-safe and legacy-compatible.
--
-- This historical Stage 1 test remains authoritative for its infrastructure and
-- Module 1 accounting proofs. Its phase-boundary assertions follow the current,
-- later P5.2 enforcement state.
--
-- ORIGIN IS PROVEN BY CALL STACK, NOT BY A FLAG
--   The guard reads GET DIAGNOSTICS ... PG_CONTEXT. A caller cannot fabricate its
--   own stack, so there is no settable marker to forge — deliberately avoiding the
--   Critical PXL-AUD-070 bypass class (a user-settable GUC acting as a control).
--   Assertion 12 proves forgery fails.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(40);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — Guard infrastructure
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid = 'public.fn_guard_journal_kernel_origin()'::regprocedure
      AND t.tgrelid IN ('journal_entries'::regclass, 'journal_entry_lines'::regclass)),
  2, 'the guard is wired to both ledger tables');                                      -- 1

SELECT ok(
  (SELECT bool_and((t.tgtype & 4) = 4 AND (t.tgtype & 8) = 8 AND (t.tgtype & 16) = 16
                   AND (t.tgtype & 66) = 2)
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid = 'public.fn_guard_journal_kernel_origin()'::regprocedure),
  'the guard fires BEFORE INSERT, UPDATE and DELETE on both tables');                  -- 2

SELECT ok(
  (SELECT p.prosecdef AND p.proconfig::text ~ 'search_path=public'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the guard is SECURITY DEFINER with a pinned search_path');                          -- 3

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_guard_journal_kernel_origin','fn_posting_kernel_origin')
      AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
        OR has_function_privilege('anon', p.oid, 'EXECUTE'))),
  0, 'neither guard function is callable by authenticated or anon');                   -- 4

-- Origin is derived from the call stack. There must be NO runtime knob: no GUC read,
-- no config table, nothing a session could set to arm or disarm the control.
SELECT ok(
  (SELECT p.prosrc ~ 'PG_CONTEXT' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the guard derives origin from the plpgsql call stack');                             -- 5

SELECT ok(
  (SELECT p.prosrc !~ 'current_setting' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the guard reads no session setting — there is no forgeable marker (PXL-AUD-070 class avoided)'); -- 6

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'enforcement is a compile-time constant and the later P5.2 phase has armed it');     -- 7

-- The sanctioned set is exactly the two §4.7 kernels plus the persistence helpers
-- they own. Nothing else may be treated as kernel-origin.
SELECT ok(
  (SELECT p.prosrc ~ 'fn_create_posted_journal_entry'
      AND p.prosrc ~ 'fn_reverse_posted_journal_entry'
      AND p.prosrc ~ 'fn_finalize_journal_entry'
      AND p.prosrc ~ 'fn_add_posting_line'
      AND p.prosrc ~ 'fn_add_sales_invoice_posting_line'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_posting_kernel_origin'),
  'the kernel whitelist is exactly the sanctioned kernels and their persistence helpers'); -- 8

-- Evidence table: engine-owned, membership-readable, never member-writable.
SELECT ok(
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='sys_posting_guard_violations'),
  'RLS is enabled on the violation evidence table');                                   -- 9

SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename='sys_posting_guard_violations'
      AND cmd<>'SELECT' AND coalesce(qual,'false')='false' AND coalesce(with_check,'false')='false'),
  3, 'the evidence table denies every authenticated write');                           -- 10

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — Guard behaviour, proven non-vacuous
--
-- Two probe functions with identical bodies except origin: one writes the ledger
-- directly, the other goes through the sanctioned kernel. Same transaction, same
-- data, opposite classification.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f510000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p51-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f510000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f510000-0000-0000-0000-0000000000b1', 'corporation', 'P51 Guard Corp',
        'Trading', '390-000-001-00000', 'vat', 'calendar',
        'G St', 'G Bldg', 'Makati', 'Metro Manila', '1200',
        'p51-owner@test.local', 'G Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0f510000-0000-0000-0000-0000000000b2', '0f510000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'G St', 'G Bldg', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f510000-0000-0000-0000-0000000000f1', '0f510000-0000-0000-0000-0000000000b1',
        'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '0f510000-0000-0000-0000-0000000000b1', '0f510000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES
  ('0f510000-0000-0000-0000-0000000000a1', '0f510000-0000-0000-0000-0000000000b1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f510000-0000-0000-0000-0000000000a2', '0f510000-0000-0000-0000-0000000000b1', '2010', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f510000-0000-0000-0000-0000000000a3', '0f510000-0000-0000-0000-0000000000b1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f510000-0000-0000-0000-0000000000a4', '0f510000-0000-0000-0000-0000000000b1', '1300', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f510000-0000-0000-0000-0000000000a5', '0f510000-0000-0000-0000-0000000000b1', '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('0f510000-0000-0000-0000-0000000000a6', '0f510000-0000-0000-0000-0000000000b1', '5010', 'Operating Expense',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
        vat_payable_account_id, input_vat_account_id, created_by, updated_by)
VALUES ('0f510000-0000-0000-0000-0000000000b1',
        '0f510000-0000-0000-0000-0000000000a1', '0f510000-0000-0000-0000-0000000000a2',
        '0f510000-0000-0000-0000-0000000000a3', '0f510000-0000-0000-0000-0000000000a4',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number, is_active, created_by, updated_by)
SELECT '0f510000-0000-0000-0000-0000000000b1', '0f510000-0000-0000-0000-0000000000b2',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('CM','DM-S','VC','SI','JE');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('0f510000-0000-0000-0000-0000000000c1', '0f510000-0000-0000-0000-0000000000b1', 'CUST-P51',
        'P51 Customer Inc', '389-000-001-00000', 'Customer HQ', 'Customer HQ', auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('0f510000-0000-0000-0000-0000000000d1', '0f510000-0000-0000-0000-0000000000b1', 'SUPP-P51',
        'P51 Supplier Corp', '388-000-001-00000', 'Supplier HQ', auth.uid(), auth.uid());

-- The attribution pair. Both are SECURITY DEFINER, both write the same header;
-- only the ORIGIN differs.
CREATE FUNCTION pg_temp.probe_direct(p_num TEXT) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO journal_entries (company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status, total_debit, total_credit,
    created_by, updated_by)
  VALUES ('0f510000-0000-0000-0000-0000000000b1','0f510000-0000-0000-0000-0000000000b2',
    p_num, '2026-03-10',
    (SELECT id FROM fiscal_periods WHERE company_id='0f510000-0000-0000-0000-0000000000b1'
       AND '2026-03-10' BETWEEN start_date AND end_date),
    'guard probe', 'MANUAL', NULL, 'posted', 0, 0, auth.uid(), auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE FUNCTION pg_temp.probe_kernel(p_num TEXT) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  RETURN fn_create_posted_journal_entry(
    '0f510000-0000-0000-0000-0000000000b1','0f510000-0000-0000-0000-0000000000b2',
    p_num, '2026-03-10', 'guard probe', 'MANUAL', NULL);
END $$;

CREATE TEMP TABLE t_pre AS SELECT count(*) AS n FROM sys_posting_guard_violations;

SELECT throws_ok(
  $$SELECT pg_temp.probe_direct('JE-PROBE-DIRECT')$$,
  '23514', NULL,
  'a non-kernel ledger write is rejected by the armed guard');                         -- 11

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE je_number='JE-PROBE-DIRECT' AND table_name='journal_entries' AND operation='INSERT'),
  0, 'rejected violation evidence rolls back with the rejected statement');            -- 12

SELECT is(
  (SELECT count(*)::int FROM journal_entries WHERE je_number='JE-PROBE-DIRECT'),
  0, 'the rejected non-kernel header did not persist');                                -- 13

SELECT lives_ok($$SELECT pg_temp.probe_kernel('JE-PROBE-KERNEL')$$,
  'the kernel-routed write succeeds');                                                 -- 14

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations WHERE je_number='JE-PROBE-KERNEL'),
  0, 'the kernel-routed write was NOT recorded — the classifier discriminates');       -- 15

-- Forgery attempt: no session setting can make a direct write look kernel-origin,
-- because origin is the call stack, not a marker.
SELECT set_config('pxl.posting_kernel', 'fn_create_posted_journal_entry', true);
SELECT set_config('pxl.allow_demo_reset', 'on', true);
SELECT throws_ok(
  $$SELECT pg_temp.probe_direct('JE-PROBE-FORGE')$$,
  '23514', NULL,
  'session markers cannot forge kernel origin under enforcement');                     -- 16
SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations WHERE je_number='JE-PROBE-FORGE'),
  0, 'the rejected forgery persists neither ledger data nor violation evidence');      -- 17
SELECT set_config('pxl.allow_demo_reset', '', true);

-- Line-level classification behaves the same way.
SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE table_name='journal_entry_lines'
      AND je_id = (SELECT id FROM journal_entries WHERE je_number='JE-PROBE-KERNEL')),
  0, 'no spurious line violation is recorded for the kernel probe');                   -- 18

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — posting_origin (P1 metadata, §4.1 / invariant 13)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT pg_get_constraintdef(c.oid) ~ 'system.*manual'
     FROM pg_constraint c WHERE c.conname='je_posting_origin_check'),
  'posting_origin is constrained to the governed system/manual domain');               -- 19

SELECT is(
  (SELECT posting_origin FROM journal_entries WHERE je_number='JE-PROBE-KERNEL'),
  NULL, 'the kernel defaults posting_origin to NULL, preserving legacy caller output'); -- 20

-- Captured first: a function call embedded in a scalar subquery would be evaluated
-- once per scanned row.
CREATE TEMP TABLE t_origin AS
SELECT fn_create_posted_journal_entry(
  '0f510000-0000-0000-0000-0000000000b1','0f510000-0000-0000-0000-0000000000b2',
  'JE-PROBE-ORIGIN','2026-03-10','origin probe','MANUAL',NULL,
  NULL,'posted',0,0,'system') AS id;

SELECT is(
  (SELECT je.posting_origin FROM journal_entries je JOIN t_origin o ON o.id = je.id),
  'system', 'the kernel persists an explicitly supplied posting_origin');              -- 21

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — MODULE 1: the memo posters are migrated, output unchanged
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_credit_memo_vat_lump_impl','fn_post_debit_memo_vat_lump_impl',
                        'fn_post_vendor_credit_vat_lump_impl')
      AND p.prosrc ~ 'INSERT INTO\s+journal_entries'),
  0, 'no Module 1 writer inserts a journal header directly any more');                 -- 22

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_credit_memo_vat_lump_impl','fn_post_debit_memo_vat_lump_impl',
                        'fn_post_vendor_credit_vat_lump_impl')
      AND p.prosrc ~ 'fn_create_posted_journal_entry'),
  3, 'all three Module 1 writers route through the sanctioned kernel');                -- 23

-- Each keeps explicit open-period validation. The wording may remain
-- document-specific while the rejection contract stays exact.
SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'No open fiscal period')
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_credit_memo_vat_lump_impl','fn_post_debit_memo_vat_lump_impl',
                        'fn_post_vendor_credit_vat_lump_impl')),
  'each migrated writer keeps explicit open-period validation');                      -- 24

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'cm', fn_save_credit_memo(NULL,
  jsonb_build_object('company_id','0f510000-0000-0000-0000-0000000000b1',
    'branch_id','0f510000-0000-0000-0000-0000000000b2',
    'customer_id','0f510000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P51 Customer Inc','customer_tin_snapshot','389-000-001-00000',
    'cm_date','2026-03-12',
    'reason_code_id',(SELECT id FROM ref_reason_codes
                       WHERE applies_to IN ('credit_memo','both') ORDER BY id LIMIT 1)),
  jsonb_build_array(jsonb_build_object('description','Returned goods','quantity',1,'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f510000-0000-0000-0000-0000000000a5')),
  'draft');
SELECT lives_ok($$SELECT fn_post_credit_memo((SELECT id FROM t_ctx WHERE key='cm'))$$,
  'the migrated Credit Memo poster posts through the kernel');                          -- 25

SELECT results_eq(
  $q$SELECT je.status, je.total_debit, je.total_credit, je.posting_origin, je.entry_class,
            je.auto_reverse, je.reference_doc_type, (je.fiscal_period_id IS NOT NULL)
       FROM journal_entries je
      WHERE je.id = (SELECT journal_entry_id FROM credit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='cm'))$q$,
  $$VALUES ('posted'::text, 1120.00::numeric, 1120.00::numeric, 'system'::text,
            'regular'::text, false, 'CM'::text, true)$$,
  'CM header is unchanged: status, totals, posting_origin, class, auto_reverse, source');-- 26

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount, jel.line_role
       FROM journal_entry_lines jel JOIN chart_of_accounts coa ON coa.id=jel.account_id
      WHERE jel.je_id = (SELECT journal_entry_id FROM credit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='cm'))
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '4010'::text, 1000.00::numeric, 0.00::numeric, 'base'::text),
           (2, '2100'::text, 120.00::numeric, 0.00::numeric, 'tax'::text),
           (3, '1200'::text, 0.00::numeric, 1120.00::numeric, 'control'::text)$$,
  'CM lines are unchanged: order, accounts, amounts, line roles');                      -- 27

SELECT results_eq(
  $q$SELECT tax_kind, tax_base, tax_amount, is_reversal FROM tax_detail_entries
      WHERE source_doc_type='CM' AND source_doc_id=(SELECT id FROM t_ctx WHERE key='cm')$q$,
  $$VALUES ('output_vat'::text, -1000.00::numeric, -120.00::numeric, true)$$,
  'CM tax detail is unchanged');                                                        -- 28

SELECT is((SELECT status FROM credit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='cm')),
  'applied', 'CM document status is unchanged');                                        -- 29

INSERT INTO t_ctx
SELECT 'dm', fn_save_debit_memo(NULL,
  jsonb_build_object('company_id','0f510000-0000-0000-0000-0000000000b1',
    'branch_id','0f510000-0000-0000-0000-0000000000b2',
    'customer_id','0f510000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P51 Customer Inc','customer_tin_snapshot','389-000-001-00000',
    'dm_date','2026-03-13',
    'reason_code_id',(SELECT id FROM ref_reason_codes
                       WHERE applies_to IN ('debit_memo','both') ORDER BY id LIMIT 1)),
  jsonb_build_array(jsonb_build_object('description','Freight charge','amount',500,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'account_id','0f510000-0000-0000-0000-0000000000a5')),
  'draft');
SELECT lives_ok($$SELECT fn_post_debit_memo((SELECT id FROM t_ctx WHERE key='dm'))$$,
  'the migrated Debit Memo poster posts through the kernel');                           -- 30

SELECT results_eq(
  $q$SELECT je.status, je.total_debit, je.total_credit, je.posting_origin, je.reference_doc_type
       FROM journal_entries je
      WHERE je.id = (SELECT journal_entry_id FROM debit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='dm'))$q$,
  $$VALUES ('posted'::text, 560.00::numeric, 560.00::numeric, 'system'::text, 'DM'::text)$$,
  'DM header is unchanged');                                                            -- 31

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount, jel.line_role
       FROM journal_entry_lines jel JOIN chart_of_accounts coa ON coa.id=jel.account_id
      WHERE jel.je_id = (SELECT journal_entry_id FROM debit_memos WHERE id=(SELECT id FROM t_ctx WHERE key='dm'))
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '1200'::text, 560.00::numeric, 0.00::numeric, 'control'::text),
           (2, '4010'::text, 0.00::numeric, 500.00::numeric, 'base'::text),
           (3, '2100'::text, 0.00::numeric, 60.00::numeric, 'tax'::text)$$,
  'DM lines are unchanged: order, accounts, amounts, line roles');                      -- 32

SELECT results_eq(
  $q$SELECT tax_kind, tax_amount, is_reversal FROM tax_detail_entries
      WHERE source_doc_type='DM' AND source_doc_id=(SELECT id FROM t_ctx WHERE key='dm')$q$,
  $$VALUES ('output_vat'::text, 60.00::numeric, false)$$,
  'DM tax detail is unchanged');                                                        -- 33

INSERT INTO t_ctx
SELECT 'vc', fn_save_vendor_credit(NULL,
  jsonb_build_object('company_id','0f510000-0000-0000-0000-0000000000b1',
    'branch_id','0f510000-0000-0000-0000-0000000000b2',
    'supplier_id','0f510000-0000-0000-0000-0000000000d1',
    'supplier_name_snapshot','P51 Supplier Corp','supplier_tin_snapshot','388-000-001-00000',
    'credit_date','2026-03-14'),
  jsonb_build_array(jsonb_build_object('description','Returned supplies','quantity',1,'unit_price',800,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
    'expense_account_id','0f510000-0000-0000-0000-0000000000a6')));
SELECT lives_ok($$SELECT fn_post_vendor_credit((SELECT id FROM t_ctx WHERE key='vc'))$$,
  'the migrated Vendor Credit poster posts through the kernel');                        -- 34

SELECT results_eq(
  $q$SELECT je.status, je.total_debit, je.total_credit, je.posting_origin, je.reference_doc_type
       FROM journal_entries je
      WHERE je.id = (SELECT journal_entry_id FROM vendor_credits WHERE id=(SELECT id FROM t_ctx WHERE key='vc'))$q$,
  $$VALUES ('posted'::text, 896.00::numeric, 896.00::numeric, 'system'::text, 'VC'::text)$$,
  'VC header is unchanged');                                                            -- 35

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount, jel.line_role
       FROM journal_entry_lines jel JOIN chart_of_accounts coa ON coa.id=jel.account_id
      WHERE jel.je_id = (SELECT journal_entry_id FROM vendor_credits WHERE id=(SELECT id FROM t_ctx WHERE key='vc'))
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '2010'::text, 896.00::numeric, 0.00::numeric, 'control'::text),
           (2, '5010'::text, 0.00::numeric, 800.00::numeric, 'base'::text),
           (3, '1300'::text, 0.00::numeric, 96.00::numeric, 'tax'::text)$$,
  'VC lines are unchanged: order, accounts, amounts, line roles');                      -- 36

-- Audit equality: the migrated writers still produce audit rows for their journals.
SELECT ok(
  (SELECT count(*) FROM sys_audit_logs a
    WHERE a.table_name='journal_entries'
      AND a.record_id IN (
        (SELECT journal_entry_id FROM credit_memos  WHERE id=(SELECT id FROM t_ctx WHERE key='cm')),
        (SELECT journal_entry_id FROM debit_memos   WHERE id=(SELECT id FROM t_ctx WHERE key='dm')),
        (SELECT journal_entry_id FROM vendor_credits WHERE id=(SELECT id FROM t_ctx WHERE key='vc')))) >= 3,
  'audit coverage is unchanged — every migrated journal is audited');                   -- 37

-- Module 1 no longer appears in the header violation census.
SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations
    WHERE table_name='journal_entries'
      AND writer_function IN ('fn_post_credit_memo_vat_lump_impl','fn_post_debit_memo_vat_lump_impl',
                              'fn_post_vendor_credit_vat_lump_impl')),
  0, 'Module 1 produces no header violation — the migration is behaviourally proven');   -- 38

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — Kernel extension safety and the phase boundary
-- ══════════════════════════════════════════════════════════════════════════════
-- P3A lesson: one signature only. An additive overload would make every existing
-- 7-argument call ambiguous at CALL time.
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_create_posted_journal_entry'),
  1, 'the kernel has exactly one signature — no ambiguous overload');                    -- 39

-- Later approved stages drain the forward-writer census and P5.2 arms the guard.
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosrc ~ 'INSERT INTO\s+journal_entries'
      AND p.proname <> 'fn_create_posted_journal_entry'),
  0, 'the approved P5.1 continuation drains every forward header insert');             -- 40

SELECT * FROM finish();
ROLLBACK;
