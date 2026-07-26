-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P3A-001 — Dimension Push (frozen P3 spec §3 / §11 sub-phase P3a)
--
-- Certifies that fn_add_posting_line is a pure persistence helper: it accepts all six
-- governed dimensions, performs exactly one insert, and performs no source lookup, no
-- document-type dispatch, no follow-up UPDATE, and no dimension inference. The document
-- writers (Vendor Bill, Cash Purchase) now own dimension resolution and push the
-- document header's six dimensions onto every posted line. The Dimension Engine guard
-- remains the only dimension validator.
--
-- Byte-for-byte accounting equality is proven two ways: (a) the full regression and
-- canonical lanes (001/003/004/006/031/042/050/051 and canonical 055/057/058 post
-- Vendor Bills and Cash Purchases with exact GL assertions and stay green), and
-- (b) sections C/D below, which post a real Vendor Bill and a real Cash Purchase whose
-- headers carry all six dimensions and assert the complete resulting GL — line count,
-- order, accounts, amounts, descriptions, and every dimension — against the pre-P3A
-- output captured from the same fixture.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(28);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — Helper contract (structural)
-- ══════════════════════════════════════════════════════════════════════════════

-- Exactly one candidate: an additive overload would make every surviving 9-argument
-- call site raise "function ... is not unique" at CALL time (spec Risk R3).
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  1, 'fn_add_posting_line has exactly one signature (no ambiguous overload)');       -- 1

SELECT is(
  (SELECT pg_get_function_identity_arguments(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  'p_je_id uuid, p_line_number integer, p_account_id uuid, p_description text, '
  'p_debit numeric, p_credit numeric, p_branch_id uuid, p_department_id uuid, '
  'p_cost_center_id uuid, p_project_id uuid, p_location_id uuid, p_functional_entity_id uuid',
  'fn_add_posting_line accepts all six governed dimensions explicitly');             -- 2

SELECT is(
  (SELECT pronargdefaults::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  8, 'the three new dimension parameters default to NULL (9-argument callers still resolve)'); -- 3

SELECT ok(
  (SELECT p.prosrc !~* '(vendor_bills|cash_purchases)' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  'fn_add_posting_line performs no source-document lookup');                          -- 4

SELECT ok(
  (SELECT p.prosrc !~* 'reference_doc_type' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  'fn_add_posting_line performs no document-type dispatch');                          -- 5

SELECT ok(
  (SELECT p.prosrc !~* 'UPDATE\s+journal_entry_lines' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  'fn_add_posting_line performs no follow-up UPDATE on journal_entry_lines');         -- 6

SELECT is(
  (SELECT (SELECT count(*)::int FROM regexp_matches(p.prosrc, 'INSERT\s+INTO\s+journal_entry_lines', 'g'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  1, 'fn_add_posting_line performs exactly one insert');                              -- 7

SELECT ok(
  (SELECT p.prosrc !~* 'COALESCE\s*\(\s*p_(department_id|cost_center_id|project_id|location_id|functional_entity_id)'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_add_posting_line'),
  'fn_add_posting_line performs no dimension inference');                             -- 8

-- Zero pull dispatch survives anywhere in the posting-line helper family.
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname ~ '^fn_add_.*posting_line'
      AND p.prosrc ~* '(vendor_bills|cash_purchases)'),
  0, 'no posting-line helper reaches back into a source document for dimensions');     -- 9

-- Permissions. P3A itself changed none: it re-created the helper with the grant intact.
-- Posting Engine **P5.0 (Surface Closure)** subsequently revoked the `authenticated`
-- grant, because P3A had reduced this function to a pure persistence helper with no
-- legitimate client caller. The assertion is inverted rather than dropped, so the
-- surface stays pinned and a regression that re-grants it still fails here.
-- Owning evidence: supabase/tests/091_posting_engine_p5a_surface_closure_test.sql.
SELECT ok(
  NOT has_function_privilege('authenticated', 'public.fn_add_posting_line(uuid,integer,uuid,text,numeric,numeric,uuid,uuid,uuid,uuid,uuid,uuid)', 'EXECUTE'),
  'the push helper is closed to authenticated (P5.0); the SECURITY DEFINER path is unaffected'); -- 10
SELECT ok(
  has_function_privilege('service_role', 'public.fn_add_posting_line(uuid,integer,uuid,text,numeric,numeric,uuid,uuid,uuid,uuid,uuid,uuid)', 'EXECUTE'),
  'service_role retains EXECUTE on the push helper');                                 -- 11
SELECT ok(
  NOT has_function_privilege('anon', 'public.fn_add_posting_line(uuid,integer,uuid,text,numeric,numeric,uuid,uuid,uuid,uuid,uuid,uuid)', 'EXECUTE'),
  'PUBLIC/anon is still denied EXECUTE on the push helper');                          -- 12

-- Writers own dimension resolution.
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_vendor_bill','fn_post_cash_purchase_source_locked_impl')
      AND p.prosrc ~ 'v_rec\.project_id'
      AND p.prosrc ~ 'v_rec\.location_id'
      AND p.prosrc ~ 'v_rec\.functional_entity_id'
      AND p.prosrc ~ 'v_rec\.department_id'
      AND p.prosrc ~ 'v_rec\.cost_center_id'),
  2, 'both previously pull-dependent writers push all six dimensions');               -- 13

-- ══════════════════════════════════════════════════════════════════════════════
-- Fixture — one VAT/EWT company with all six governed dimensions
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f3a0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p3a-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"0f3a0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000b1', 'corporation', 'P3A Dimension Push Corp',
        'Professional Services', '393-000-001-00000', 'vat', 'calendar',
        'P St', 'P Bldg', 'Makati', 'Metro Manila', '1200',
        'p3a-owner@test.local', 'P Owner', 'President', auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, ewt_registered, is_twa,
                                 twa_auto_ewt_enabled, is_active, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000b1', true, false, false, true, auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000b2', '0f3a0000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'P St', 'P Bldg', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

-- A second company, used only to prove the Dimension Engine guard is non-vacuous.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000b9', 'corporation', 'P3A Foreign Corp',
        'Trading', '393-000-002-00000', 'vat', 'calendar',
        'F St', 'F Bldg', 'Makati', 'Metro Manila', '1200',
        'p3a-owner@test.local', 'F Owner', 'President', auth.uid(), auth.uid());
INSERT INTO departments (id, company_id, department_code, department_name, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000e1', '0f3a0000-0000-0000-0000-0000000000b9', 'FGN', 'Foreign Dept', auth.uid(), auth.uid());

INSERT INTO departments (id, company_id, department_code, department_name, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000d1', '0f3a0000-0000-0000-0000-0000000000b1', 'FIN', 'Finance', auth.uid(), auth.uid());
INSERT INTO cost_centers (id, company_id, cost_center_code, cost_center_name, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000d2', '0f3a0000-0000-0000-0000-0000000000b1', 'CC-1', 'Admin CC', auth.uid(), auth.uid());
INSERT INTO projects (id, company_id, branch_id, project_code, project_name)
VALUES ('0f3a0000-0000-0000-0000-0000000000d3', '0f3a0000-0000-0000-0000-0000000000b1', '0f3a0000-0000-0000-0000-0000000000b2', 'PRJ-1', 'Push Project');
INSERT INTO locations (id, company_id, location_code, location_name)
VALUES ('0f3a0000-0000-0000-0000-0000000000d4', '0f3a0000-0000-0000-0000-0000000000b1', 'LOC-1', 'Push Site');
INSERT INTO functional_entities (id, company_id, entity_code, entity_name)
VALUES ('0f3a0000-0000-0000-0000-0000000000d5', '0f3a0000-0000-0000-0000-0000000000b1', 'FE-1', 'Push Segment');

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f3a0000-0000-0000-0000-0000000000f1', '0f3a0000-0000-0000-0000-0000000000b1', 'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name, start_date, end_date, is_locked)
SELECT '0f3a0000-0000-0000-0000-0000000000b1', '0f3a0000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES
  ('0f3a0000-0000-0000-0000-0000000000a1', '0f3a0000-0000-0000-0000-0000000000b1', '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('0f3a0000-0000-0000-0000-0000000000a2', '0f3a0000-0000-0000-0000-0000000000b1', '1300', 'Input VAT', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('0f3a0000-0000-0000-0000-0000000000a3', '0f3a0000-0000-0000-0000-0000000000b1', '2010', 'Accounts Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f3a0000-0000-0000-0000-0000000000a4', '0f3a0000-0000-0000-0000-0000000000b1', '2150', 'EWT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f3a0000-0000-0000-0000-0000000000a5', '0f3a0000-0000-0000-0000-0000000000b1', '5010', 'Professional Fees Expense', 'expense', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id, input_vat_account_id,
        ewt_payable_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000b1',
        '0f3a0000-0000-0000-0000-0000000000a3', '0f3a0000-0000-0000-0000-0000000000a2',
        '0f3a0000-0000-0000-0000-0000000000a4', '0f3a0000-0000-0000-0000-0000000000a1',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number, is_active, created_by, updated_by)
SELECT '0f3a0000-0000-0000-0000-0000000000b1', '0f3a0000-0000-0000-0000-0000000000b2',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('VB', 'CP');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin, registered_address,
                       is_subject_to_ewt, default_atc_code_id, created_by, updated_by)
VALUES ('0f3a0000-0000-0000-0000-0000000000c1', '0f3a0000-0000-0000-0000-0000000000b1', 'SUPP-1',
        'Push Supplier Corp', '394-000-001-00000', 'Supplier HQ, Pasig',
        true, (SELECT id FROM atc_codes WHERE code = 'WC140'), auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — Vendor Bill: the writer pushes; the GL is unchanged
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '0f3a0000-0000-0000-0000-0000000000b1',
    'branch_id',               '0f3a0000-0000-0000-0000-0000000000b2',
    'supplier_id',             '0f3a0000-0000-0000-0000-0000000000c1',
    'supplier_name_snapshot',  'Push Supplier Corp',
    'supplier_tin_snapshot',   '394-000-001-00000',
    'supplier_invoice_number', 'SUP-INV-P3A',
    'bill_date',               '2026-03-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Professional fee',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', '0f3a0000-0000-0000-0000-0000000000a5',
    'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',       10000,
    'ewt_amount',         200,
    'ewt_income_nature',  'Professional fees'
  )));

UPDATE vendor_bills
SET department_id        = '0f3a0000-0000-0000-0000-0000000000d1',
    cost_center_id       = '0f3a0000-0000-0000-0000-0000000000d2',
    project_id           = '0f3a0000-0000-0000-0000-0000000000d3',
    location_id          = '0f3a0000-0000-0000-0000-0000000000d4',
    functional_entity_id = '0f3a0000-0000-0000-0000-0000000000d5'
WHERE id = (SELECT id FROM t_ctx WHERE key = 'vb');

SELECT lives_ok($$SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb'))$$,
  'dimension-bearing Vendor Bill approves');                                          -- 14
SELECT lives_ok($$SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key = 'vb'))$$,
  'dimension-bearing Vendor Bill posts through the push helper');                     -- 15

INSERT INTO t_ctx SELECT 'vb_je', journal_entry_id FROM vendor_bills WHERE id = (SELECT id FROM t_ctx WHERE key = 'vb');

-- Full GL equality: line order, accounts, descriptions, and amounts unchanged from
-- the pre-P3A output of this fixture.
SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.description, jel.debit_amount, jel.credit_amount
       FROM journal_entry_lines jel
       JOIN chart_of_accounts coa ON coa.id = jel.account_id
      WHERE jel.je_id = (SELECT id FROM t_ctx WHERE key='vb_je')
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '5010'::text, 'Expense - Professional fee'::text, 10000.00::numeric(15,2), 0.00::numeric(15,2)),
           (2, '1300'::text, 'Input VAT - VB-000001'::text, 1200.00::numeric(15,2), 0.00::numeric(15,2)),
           (3, '2010'::text, 'AP - Push Supplier Corp'::text, 0.00::numeric(15,2), 11000.00::numeric(15,2)),
           (4, '2150'::text, 'EWT accrued - VB-000001'::text, 0.00::numeric(15,2), 200.00::numeric(15,2))$$,
  'Vendor Bill GL is byte-for-byte identical to the pre-P3A output');                 -- 16

-- Every line carries every pushed dimension.
SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key='vb_je')
      AND branch_id            = '0f3a0000-0000-0000-0000-0000000000b2'
      AND department_id        = '0f3a0000-0000-0000-0000-0000000000d1'
      AND cost_center_id       = '0f3a0000-0000-0000-0000-0000000000d2'
      AND project_id           = '0f3a0000-0000-0000-0000-0000000000d3'
      AND location_id          = '0f3a0000-0000-0000-0000-0000000000d4'
      AND functional_entity_id = '0f3a0000-0000-0000-0000-0000000000d5'),
  4, 'all four Vendor Bill lines carry all six pushed dimensions');                   -- 17

-- line_role and posting_origin are untouched by P3A (byte-for-byte constraint).
SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key='vb_je') AND line_role IS NULL),
  4, 'P3A adds no line_role to Vendor Bill lines');                                   -- 18
SELECT is(
  (SELECT posting_origin FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='vb_je')),
  'system', 'Vendor Bill posting_origin is unchanged');                               -- 19

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Cash Purchase: the writer pushes; the GL is unchanged
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'cp', fn_save_cash_purchase(NULL,
  jsonb_build_object(
    'company_id',             '0f3a0000-0000-0000-0000-0000000000b1',
    'branch_id',              '0f3a0000-0000-0000-0000-0000000000b2',
    'transaction_date',       '2026-03-11',
    'supplier_id',            '0f3a0000-0000-0000-0000-0000000000c1',
    'supplier_name_snapshot', 'Push Supplier Corp',
    'supplier_tin_snapshot',  '394-000-001-00000'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Professional fee',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', '0f3a0000-0000-0000-0000-0000000000a5',
    'ewt_atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'ewt_tax_base',       10000,
    'ewt_amount',         200,
    'ewt_income_nature',  'Professional fees'
  )));

UPDATE cash_purchases
SET department_id        = '0f3a0000-0000-0000-0000-0000000000d1',
    cost_center_id       = '0f3a0000-0000-0000-0000-0000000000d2',
    project_id           = '0f3a0000-0000-0000-0000-0000000000d3',
    location_id          = '0f3a0000-0000-0000-0000-0000000000d4',
    functional_entity_id = '0f3a0000-0000-0000-0000-0000000000d5'
WHERE id = (SELECT id FROM t_ctx WHERE key = 'cp');

SELECT lives_ok($$SELECT fn_post_cash_purchase((SELECT id FROM t_ctx WHERE key = 'cp'))$$,
  'dimension-bearing Cash Purchase posts through the push helper');                   -- 20

INSERT INTO t_ctx SELECT 'cp_je', journal_entry_id FROM cash_purchases WHERE id = (SELECT id FROM t_ctx WHERE key = 'cp');

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.description, jel.debit_amount, jel.credit_amount
       FROM journal_entry_lines jel
       JOIN chart_of_accounts coa ON coa.id = jel.account_id
      WHERE jel.je_id = (SELECT id FROM t_ctx WHERE key='cp_je')
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '5010'::text, 'Expense - Professional fee'::text, 10000.00::numeric(15,2), 0.00::numeric(15,2)),
           (2, '1300'::text, 'Input VAT - CP-000001'::text, 1200.00::numeric(15,2), 0.00::numeric(15,2)),
           (3, '2150'::text, 'EWT withheld - CP-000001'::text, 0.00::numeric(15,2), 200.00::numeric(15,2)),
           (4, '1010'::text, 'Cash paid - CP-000001'::text, 0.00::numeric(15,2), 11000.00::numeric(15,2))$$,
  'Cash Purchase GL is byte-for-byte identical to the pre-P3A output');               -- 21

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key='cp_je')
      AND branch_id            = '0f3a0000-0000-0000-0000-0000000000b2'
      AND department_id        = '0f3a0000-0000-0000-0000-0000000000d1'
      AND cost_center_id       = '0f3a0000-0000-0000-0000-0000000000d2'
      AND project_id           = '0f3a0000-0000-0000-0000-0000000000d3'
      AND location_id          = '0f3a0000-0000-0000-0000-0000000000d4'
      AND functional_entity_id = '0f3a0000-0000-0000-0000-0000000000d5'),
  4, 'all four Cash Purchase lines carry all six pushed dimensions');                 -- 22

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — Reversal is unaffected (reversal journals are 'REV'; the retired pull
-- never fired for them, and the reversal writer already pushed all six dimensions)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT lives_ok(
  $$SELECT fn_void_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'),
      (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'), 'P3A reversal check')$$,
  'posted Vendor Bill voids through the reversal writer');                            -- 23

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines jel
     JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '0f3a0000-0000-0000-0000-0000000000b1'
      AND je.reference_doc_type = 'REV'
      AND jel.department_id        = '0f3a0000-0000-0000-0000-0000000000d1'
      AND jel.cost_center_id       = '0f3a0000-0000-0000-0000-0000000000d2'
      AND jel.project_id           = '0f3a0000-0000-0000-0000-0000000000d3'
      AND jel.location_id          = '0f3a0000-0000-0000-0000-0000000000d4'
      AND jel.functional_entity_id = '0f3a0000-0000-0000-0000-0000000000d5'),
  4, 'reversal lines preserve all six dimensions');                                   -- 24

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — The helper persists exactly what it is handed (no inference), and the
-- Dimension Engine remains the only validator (non-vacuous)
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'helper_probe_je', fn_create_posted_journal_entry(
  '0f3a0000-0000-0000-0000-0000000000b1',
  '0f3a0000-0000-0000-0000-0000000000b2',
  'P3AJE-0001', '2026-03-12', 'P3A no-inference helper probe',
  'VB', (SELECT id FROM t_ctx WHERE key='vb'),
  NULL, 'draft', 0, 0, NULL, 'regular', false, false, true
);

-- A 'VB'-typed journal whose bill carries all six dimensions: under the retired pull
-- this line would have inherited them. The pure helper writes the NULLs it was handed.
SELECT lives_ok(
  $$SELECT fn_add_posting_line((SELECT id FROM t_ctx WHERE key='helper_probe_je'), 1,
      '0f3a0000-0000-0000-0000-0000000000a5', 'No inference', 100, 0,
      '0f3a0000-0000-0000-0000-0000000000b2')$$,
  'the helper accepts a 9-argument call (backward-compatible signature)');             -- 25

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key='helper_probe_je') AND line_number = 1
      AND department_id IS NULL AND cost_center_id IS NULL AND project_id IS NULL
      AND location_id IS NULL AND functional_entity_id IS NULL),
  1, 'a VB-typed journal line inherits nothing from the bill — no dimension inference'); -- 26

SELECT is(
  (SELECT branch_id FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key='helper_probe_je') AND line_number = 1),
  '0f3a0000-0000-0000-0000-0000000000b2'::uuid,
  'the pushed branch is persisted exactly as handed in');                              -- 27

-- The Dimension Engine guard still rejects a cross-company dimension pushed through
-- the helper (proves the guard is the validator and that it is not vacuous).
SELECT throws_like(
  $$SELECT fn_add_posting_line((SELECT id FROM t_ctx WHERE key='helper_probe_je'), 2,
      '0f3a0000-0000-0000-0000-0000000000a5', 'Cross-company dimension', 0, 100,
      '0f3a0000-0000-0000-0000-0000000000b2', '0f3a0000-0000-0000-0000-0000000000e1', NULL,
      NULL, NULL, NULL)$$,
  '%does not belong to company%',
  'the Dimension Engine guard rejects a cross-company pushed dimension');              -- 28

SELECT * FROM finish();
ROLLBACK;
