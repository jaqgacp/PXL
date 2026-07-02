-- ══════════════════════════════════════════════════════════════════════════════
-- F2307-ISSUED-001 - Server-Side 2307 Generation and Status Locks (PXL-AUD-015)
--
-- Posted PV EWT detail (explicit base + income nature) feeds quarter-batch
-- generation through fn_generate_form_2307_issued. Asserts: generated
-- certificate totals and ATC-level line detail, regeneration refreshing a
-- 'generated' certificate after new withholding, sent-status locking via
-- fn_update_form_2307_issued_status, and denial of direct table writes.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111117',
        'authenticated', 'authenticated', 'harness-2307@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111117","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222228', 'corporation',
        'Form 2307 Test Corp', 'Software Services', '111-222-333-006',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-2307@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333339',
        '22222222-2222-2222-2222-222222222228', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444450',
        '22222222-2222-2222-2222-222222222228',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222228',
       '44444444-4444-4444-4444-444444444450',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000061', '22222222-2222-2222-2222-222222222228',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000062', '22222222-2222-2222-2222-222222222228',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000063', '22222222-2222-2222-2222-222222222228',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000064', '22222222-2222-2222-2222-222222222228',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000065', '22222222-2222-2222-2222-222222222228',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222228',
        'aaaaaaaa-0000-0000-0000-000000000062',
        'aaaaaaaa-0000-0000-0000-000000000061',
        'aaaaaaaa-0000-0000-0000-000000000063',
        'aaaaaaaa-0000-0000-0000-000000000064',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222228',
       '33333333-3333-3333-3333-333333333339',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'PV');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666671',
        '22222222-2222-2222-2222-222222222228', 'SUPP-001',
        '2307 Test Supplier Corp', '777-888-999-005',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

-- ── VB 11,200 + partial PV helpers (EWT 2% on explicit 5,000 base per PV) ──────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
-- The denial tests below run under SET LOCAL ROLE authenticated and still need
-- to read ids from the temp context table.
GRANT SELECT ON t_ctx TO authenticated;

INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222228',
    'branch_id',               '33333333-3333-3333-3333-333333333339',
    'supplier_id',             '66666666-6666-6666-6666-666666666671',
    'supplier_name_snapshot',  '2307 Test Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-005',
    'supplier_invoice_number', 'SUP-INV-0001',
    'bill_date',               '2026-01-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000065'
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));

CREATE FUNCTION pg_temp.mk_pv(p_key text, p_date date)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  v_id := fn_save_payment_voucher(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222228',
      'branch_id',              '33333333-3333-3333-3333-333333333339',
      'supplier_id',            '66666666-6666-6666-6666-666666666671',
      'supplier_name_snapshot', '2307 Test Supplier Corp',
      'supplier_tin_snapshot',  '777-888-999-005',
      'voucher_date',           p_date::text,
      'total_amount',           5500,
      'total_ewt',              100
    ),
    jsonb_build_array(jsonb_build_object(
      'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key='vb'),
      'payment_amount',    5500,
      'ewt_amount',        100,
      'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
      'ewt_tax_base',      5000,
      'ewt_income_nature', 'Contractor services'
    )));
  PERFORM fn_post_payment_voucher(v_id);
  INSERT INTO t_ctx VALUES (p_key, v_id);
END;
$$;

-- ── First PV in Q1 2026, then generate the quarter batch ───────────────────────
SELECT pg_temp.mk_pv('pv1', '2026-02-05');

SELECT lives_ok(
  $$SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222228', 2026, 1)$$,
  'owner can generate Q1 2026 Form 2307 certificates through the RPC');

INSERT INTO t_ctx
SELECT 'issuance', id FROM form_2307_issuances
WHERE company_id = '22222222-2222-2222-2222-222222222228'
  AND tax_year = 2026 AND tax_quarter = 1;

SELECT is(
  (SELECT status FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='issuance')),
  'generated', 'one certificate is created in generated status');
SELECT is(
  (SELECT total_ewt FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='issuance')),
  100.00::numeric, 'certificate total EWT is 100.00 after the first PV');
SELECT results_eq(
  format($q$SELECT atc_code, nature_of_income, tax_base, tax_rate, tax_withheld
          FROM form_2307_issuance_lines WHERE issuance_id = %L$q$,
         (SELECT id FROM t_ctx WHERE key='issuance')),
  $$VALUES ('WC140'::text, 'Contractor services'::text, 5000.00::numeric,
            2.00::numeric(5,2), 100.00::numeric)$$,
  'certificate line carries ATC, income nature, explicit base, rate, and withheld amount');

-- ── Second PV in the same quarter, regenerate: totals refresh ──────────────────
SELECT pg_temp.mk_pv('pv2', '2026-03-05');

SELECT lives_ok(
  $$SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222228', 2026, 1)$$,
  'a generated certificate can be regenerated after new withholding');

SELECT is(
  (SELECT total_ewt FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='issuance')),
  200.00::numeric, 'regeneration refreshes total EWT to 200.00');
SELECT is(
  (SELECT total_tax_base FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='issuance')),
  10000.00::numeric, 'regeneration refreshes the total tax base to 10,000.00');
SELECT is(
  (SELECT count(*)::int FROM form_2307_issuance_lines
   WHERE issuance_id = (SELECT id FROM t_ctx WHERE key='issuance')),
  1, 'regeneration replaces lines instead of duplicating the ATC group');

-- ── Sent status locks the certificate ──────────────────────────────────────────
SELECT lives_ok(
  format($q$SELECT fn_update_form_2307_issued_status(%L, 'sent', '2026-04-05')$q$,
         (SELECT id FROM t_ctx WHERE key='issuance')),
  'certificate can be marked sent through the status RPC');

SELECT is(
  (SELECT status FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='issuance')),
  'sent', 'certificate status is sent with a recorded date');

-- Regeneration must not alter a sent certificate
SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222228', 2026, 1);

SELECT is(
  (SELECT status || '|' || total_ewt::text FROM form_2307_issuances
   WHERE id = (SELECT id FROM t_ctx WHERE key='issuance')),
  'sent|200.00', 'sent certificate is locked: regeneration leaves status and totals unchanged');

-- ── Direct table writes are denied for authenticated users ─────────────────────
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  format($q$UPDATE form_2307_issuances SET status = 'acknowledged' WHERE id = %L$q$,
         (SELECT id FROM t_ctx WHERE key='issuance')),
  '42501', NULL,
  'direct status update on form_2307_issuances is denied');

SELECT throws_ok(
  format($q$INSERT INTO form_2307_issuance_lines
          (issuance_id, company_id, atc_code, nature_of_income, tax_base, tax_withheld)
          VALUES (%L, %L, 'WC140', 'Fabricated', 999, 999)$q$,
         (SELECT id FROM t_ctx WHERE key='issuance'),
         '22222222-2222-2222-2222-222222222228'),
  '42501', NULL,
  'direct insert into form_2307_issuance_lines is denied');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
