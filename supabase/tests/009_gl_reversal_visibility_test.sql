-- ══════════════════════════════════════════════════════════════════════════════
-- GL-REVERSAL-001 - JE Reversal Nets to Zero in GL/TB (PXL-AUD-024)
--
-- fn_reverse_je (and all void paths) post a swapped-line counter-JE and mark
-- the original 'reversed'. Report views must show BOTH so reversed activity
-- nets to zero. Before 20260702000005 the views excluded the original but
-- included the counter-JE, applying every reversal twice.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(9);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111120',
        'authenticated', 'authenticated', 'harness-glrev@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111120","role":"authenticated"}', true);

-- ── Company + minimal accounting setup ─────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222230', 'corporation',
        'GL Reversal Test Corp', 'Software Services', '111-222-333-010',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-glrev@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333340',
        '22222222-2222-2222-2222-222222222230', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444460',
        '22222222-2222-2222-2222-222222222230',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222230',
       '44444444-4444-4444-4444-444444444460',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000071', '22222222-2222-2222-2222-222222222230',
   '1010', 'Cash in Bank',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000072', '22222222-2222-2222-2222-222222222230',
   '2100', 'Output VAT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000073', '22222222-2222-2222-2222-222222222230',
   '5010', 'Office Expense',     'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, vat_payable_account_id,
        default_cash_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222230',
        'aaaaaaaa-0000-0000-0000-000000000072',
        'aaaaaaaa-0000-0000-0000-000000000071',
        auth.uid(), auth.uid());

-- ── Post and reverse a manual JE ───────────────────────────────────────────────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'je', fn_post_manual_je('22222222-2222-2222-2222-222222222230',
    '33333333-3333-3333-3333-333333333340', '2026-03-10',
    'Office supplies paid in cash', 'MANUAL', false,
    jsonb_build_array(
      jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000073', 'debit_amount', 1000),
      jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000071', 'credit_amount', 1000)
    ));

SELECT is(
  (SELECT SUM(debit_amount) - SUM(credit_amount) FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222230'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000073'),
  1000.00::numeric,
  'before reversal: GL shows the expense debit of 1,000.00');

SELECT lives_ok(
  format('SELECT fn_reverse_je(%L, %L::date)', (SELECT id FROM t_ctx WHERE key='je'), '2026-03-15'),
  'posted manual JE can be reversed');

-- Both entries stay visible and the account nets to zero
SELECT is(
  (SELECT count(*)::int FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222230'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000073'),
  2,
  'after reversal: GL shows both the original and the reversing line for the account');

SELECT is(
  (SELECT count(DISTINCT je_status)::int FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222230'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000073'),
  2,
  'after reversal: GL retains the reversed original and the posted counter-entry');

SELECT is(
  (SELECT SUM(debit_amount) - SUM(credit_amount) FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222230'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000073'),
  0.00::numeric,
  'after reversal: the expense account nets to zero in the GL (was -1,000.00 before the fix)');

SELECT is(
  (SELECT SUM(net_movement) FROM vw_trial_balance
   WHERE company_id = '22222222-2222-2222-2222-222222222230'
     AND account_id = 'aaaaaaaa-0000-0000-0000-000000000073'),
  0.00::numeric,
  'after reversal: the expense account nets to zero in the trial balance');

SELECT is(
  (SELECT SUM(debit_amount) - SUM(credit_amount) FROM vw_general_ledger
   WHERE company_id = '22222222-2222-2222-2222-222222222230'),
  0.00::numeric,
  'whole GL still nets to zero after the reversal');

-- ── VAT reconciliation follows the same visibility rule ────────────────────────
INSERT INTO t_ctx
SELECT 'vat_je', fn_post_manual_je('22222222-2222-2222-2222-222222222230',
    '33333333-3333-3333-3333-333333333340', '2026-04-10',
    'Unsupported VAT adjustment to be reversed', 'MANUAL', false,
    jsonb_build_array(
      jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000073', 'debit_amount', 500),
      jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000072', 'credit_amount', 500)
    ));

SELECT is(
  (SELECT variance FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222230',
      '2026-04-01', '2026-04-30') WHERE tax_kind = 'output_vat'),
  -500.00::numeric(15,2),
  'unsupported JE on the VAT control account creates a -500.00 reconciliation variance');

SELECT fn_reverse_je((SELECT id FROM t_ctx WHERE key='vat_je'), '2026-04-20'::date);

SELECT results_eq(
  $q$SELECT gl_amount, variance, is_reconciled
     FROM fn_vat_gl_reconciliation('22222222-2222-2222-2222-222222222230',
                                   '2026-04-01', '2026-04-30')
     WHERE tax_kind = 'output_vat'$q$,
  $$VALUES (0.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'same-period reversal restores VAT reconciliation to zero variance');

SELECT * FROM finish();
ROLLBACK;
