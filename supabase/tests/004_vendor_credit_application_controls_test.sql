-- ══════════════════════════════════════════════════════════════════════════════
-- VC-APPLICATION-DATE-001     - User-Controlled Application Date (PXL-AUD-020)
-- VC-APPLICATION-REVERSAL-001 - Controlled Application Reversal (PXL-AUD-021)
--
-- Test book scenarios:
--   DATE-001:     VB 2026-04-05 for 9,000; VC 2026-04-10 for 3,000; applied
--                 2026-04-15. Aging as of 2026-04-14 shows 9,000; as of
--                 2026-04-30 shows 6,000. Date must be validated server-side.
--   REVERSAL-001: VC 2026-05-10 for 2,500 applied in full 2026-05-12, then
--                 reversed through the controlled RPC on 2026-05-15: balances
--                 and status restored, reversal evidence retained, direct
--                 insert/delete of application rows denied.
--
-- Uses VAT-exempt lines so document totals equal the test book amounts.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111114',
        'authenticated', 'authenticated', 'harness-vc@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111114","role":"authenticated"}', true);

-- ── Company / branch / periods / COA / config / series / supplier ──────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222225', 'corporation',
        'VC Controls Test Corp', 'Software Services', '111-222-333-003',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-vc@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333336',
        '22222222-2222-2222-2222-222222222225', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444447',
        '22222222-2222-2222-2222-222222222225',
        'FY2026', '2026-01-01', '2026-12-31', true);

-- December is locked to exercise the open-period validation on application dates.
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222225',
       '44444444-4444-4444-4444-444444444447',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       (m = 12)
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000031', '22222222-2222-2222-2222-222222222225',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000032', '22222222-2222-2222-2222-222222222225',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000033', '22222222-2222-2222-2222-222222222225',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000034', '22222222-2222-2222-2222-222222222225',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, input_vat_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222225',
        'aaaaaaaa-0000-0000-0000-000000000032',
        'aaaaaaaa-0000-0000-0000-000000000031',
        'aaaaaaaa-0000-0000-0000-000000000033',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222225',
       '33333333-3333-3333-3333-333333333336',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'VC');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666668',
        '22222222-2222-2222-2222-222222222225', 'SUPP-001',
        'VC Controls Supplier Corp', '777-888-999-002',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

-- ── Shared helper: save+approve+post an exempt vendor bill ─────────────────────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
-- The denial tests below run under SET LOCAL ROLE authenticated and still need
-- to read document ids from the temp context table.
GRANT SELECT ON t_ctx TO authenticated;

CREATE FUNCTION pg_temp.mk_bill(p_key text, p_inv text, p_date date, p_amount numeric)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  v_id := fn_save_vendor_bill(NULL,
    jsonb_build_object(
      'company_id',              '22222222-2222-2222-2222-222222222225',
      'branch_id',               '33333333-3333-3333-3333-333333333336',
      'supplier_id',             '66666666-6666-6666-6666-666666666668',
      'supplier_name_snapshot',  'VC Controls Supplier Corp',
      'supplier_tin_snapshot',   '777-888-999-002',
      'supplier_invoice_number', p_inv,
      'bill_date',               p_date::text
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'Professional services',
      'quantity',           1,
      'unit_price',         p_amount,
      'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000034'
    )));
  PERFORM fn_approve_vendor_bill(v_id);
  PERFORM fn_post_vendor_bill(v_id);
  INSERT INTO t_ctx VALUES (p_key, v_id);
END;
$$;

CREATE FUNCTION pg_temp.mk_credit(p_key text, p_date date, p_amount numeric)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  v_id := fn_save_vendor_credit(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222225',
      'branch_id',              '33333333-3333-3333-3333-333333333336',
      'supplier_id',            '66666666-6666-6666-6666-666666666668',
      'supplier_name_snapshot', 'VC Controls Supplier Corp',
      'supplier_tin_snapshot',  '777-888-999-002',
      'credit_date',            p_date::text
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'Service credit',
      'quantity',           1,
      'unit_price',         p_amount,
      'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000034'
    )));
  PERFORM fn_post_vendor_credit(v_id);
  INSERT INTO t_ctx VALUES (p_key, v_id);
END;
$$;

-- ══════════════════════════════════════════════════════════════════════════════
-- VC-APPLICATION-DATE-001
-- ══════════════════════════════════════════════════════════════════════════════
SELECT pg_temp.mk_bill('vb1', 'SUP-INV-0001', '2026-04-05', 9000);
SELECT pg_temp.mk_credit('vc1', '2026-04-10', 3000);

SELECT is((SELECT status FROM vendor_credits WHERE id = (SELECT id FROM t_ctx WHERE key='vc1')),
  'open', 'posted vendor credit is open and available');

-- Date validation: before the credit date
SELECT throws_like(
  format('SELECT fn_apply_vendor_credit(%L, %L, 3000, %L)',
         (SELECT id FROM t_ctx WHERE key='vc1'),
         (SELECT id FROM t_ctx WHERE key='vb1'),
         '2026-04-09'::date),
  '%cannot be before vendor credit date%',
  'application date before the vendor credit date is rejected');

-- Date validation: locked fiscal period
SELECT throws_like(
  format('SELECT fn_apply_vendor_credit(%L, %L, 3000, %L)',
         (SELECT id FROM t_ctx WHERE key='vc1'),
         (SELECT id FROM t_ctx WHERE key='vb1'),
         '2026-12-15'::date),
  '%No open fiscal period%',
  'application date in a locked fiscal period is rejected');

-- Valid application on the user-controlled date
INSERT INTO t_ctx
SELECT 'vca1', fn_apply_vendor_credit(
  (SELECT id FROM t_ctx WHERE key='vc1'),
  (SELECT id FROM t_ctx WHERE key='vb1'),
  3000, '2026-04-15'::date, 'Applied per test book VC-APPLICATION-DATE-001');

SELECT is(
  (SELECT applied_date FROM vendor_credit_applications
   WHERE id = (SELECT id FROM t_ctx WHERE key='vca1')),
  '2026-04-15'::date, 'stored applied_date is the user-selected date, not the system date');

SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222225', '2026-04-14')
   WHERE bill_id = (SELECT id FROM t_ctx WHERE key='vb1')),
  9000.00::numeric, 'aging as of 2026-04-14 still shows 9,000.00 — application dated 04-15');

SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222225', '2026-04-30')
   WHERE bill_id = (SELECT id FROM t_ctx WHERE key='vb1')),
  6000.00::numeric, 'aging as of 2026-04-30 shows 6,000.00 after the application');

SELECT is(
  (SELECT remaining_balance FROM vendor_credits WHERE id = (SELECT id FROM t_ctx WHERE key='vc1')),
  0.00::numeric, 'vendor credit remaining balance is zero after full application');

-- ══════════════════════════════════════════════════════════════════════════════
-- VC-APPLICATION-REVERSAL-001
-- ══════════════════════════════════════════════════════════════════════════════
SELECT pg_temp.mk_bill('vb2', 'SUP-INV-0002', '2026-05-01', 4000);
SELECT pg_temp.mk_credit('vc2', '2026-05-10', 2500);

INSERT INTO t_ctx
SELECT 'vca2', fn_apply_vendor_credit(
  (SELECT id FROM t_ctx WHERE key='vc2'),
  (SELECT id FROM t_ctx WHERE key='vb2'),
  2500, '2026-05-12'::date, 'Applied per test book VC-APPLICATION-REVERSAL-001');

SELECT is(
  (SELECT remaining_balance FROM vendor_credits WHERE id = (SELECT id FROM t_ctx WHERE key='vc2')),
  0.00::numeric, 'second credit fully applied: remaining balance 0.00');
SELECT is(
  (SELECT status FROM vendor_credits WHERE id = (SELECT id FROM t_ctx WHERE key='vc2')),
  'applied', 'second credit status is applied');
SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222225', '2026-05-12')
   WHERE bill_id = (SELECT id FROM t_ctx WHERE key='vb2')),
  1500.00::numeric, 'bill reduced to 1,500.00 while the application is active');

-- Direct writes to application rows are denied for authenticated users
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  format($q$INSERT INTO vendor_credit_applications
          (company_id, vendor_credit_id, vendor_bill_id, applied_amount, applied_date)
          VALUES (%L, %L, %L, 100, %L)$q$,
         '22222222-2222-2222-2222-222222222225',
         (SELECT id FROM t_ctx WHERE key='vc2'),
         (SELECT id FROM t_ctx WHERE key='vb2'),
         '2026-05-13'::date),
  '42501', NULL,
  'direct insert into vendor_credit_applications is denied for authenticated users');

-- DELETE policy USING (false) hides every row for authenticated users: the
-- direct delete silently matches nothing instead of erroring. The row-survival
-- assertion right below proves the control held.
DELETE FROM vendor_credit_applications WHERE id = (SELECT id FROM t_ctx WHERE key='vca2');
SELECT pass('direct delete of vendor_credit_applications matches no rows under RLS');

RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM vendor_credit_applications
   WHERE id = (SELECT id FROM t_ctx WHERE key='vca2')),
  1, 'application row survives the denied direct delete');

-- Controlled reversal through the RPC
SELECT lives_ok(
  format('SELECT fn_reverse_vendor_credit_application(%L, %L, %L)',
         (SELECT id FROM t_ctx WHERE key='vca2'),
         '2026-05-15'::date, 'Reversed per test book VC-APPLICATION-REVERSAL-001'),
  'owner can reverse the application through the controlled RPC');

SELECT is(
  (SELECT remaining_balance FROM vendor_credits WHERE id = (SELECT id FROM t_ctx WHERE key='vc2')),
  2500.00::numeric, 'reversal restores the vendor credit remaining balance to 2,500.00');
SELECT is(
  (SELECT status FROM vendor_credits WHERE id = (SELECT id FROM t_ctx WHERE key='vc2')),
  'open', 'reversal restores the vendor credit status to open');
SELECT ok(
  (SELECT reversed_at IS NOT NULL AND reversed_by IS NOT NULL
   FROM vendor_credit_applications
   WHERE id = (SELECT id FROM t_ctx WHERE key='vca2')),
  'reversal evidence (reversed_at, reversed_by) is preserved on the application row');

SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(
     '22222222-2222-2222-2222-222222222225', '2026-05-31')
   WHERE bill_id = (SELECT id FROM t_ctx WHERE key='vb2')),
  4000.00::numeric, 'aging as of 2026-05-31 restores the bill to 4,000.00 after the reversal');

SELECT * FROM finish();
ROLLBACK;
