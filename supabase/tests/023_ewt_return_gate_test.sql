-- ══════════════════════════════════════════════════════════════════════════════
-- EWT-RETURN-GATE-001 - 1601EQ Reconciliation Gate
-- Finding coverage: PXL-AUD-034 (pairs with PXL-AUD-041).
--
-- 1601EQ figures are server-computable from the ewt_payable tax ledger
-- (fn_compute_ewt_return) and a return cannot be marked final/filed unless
-- its figures match that ledger within 0.01, still_due equals withheld less
-- remitted_prior, and the ledger reconciles to the EWT Payable GL control
-- account for the quarter (fn_wht_gl_reconciliation). Draft rows stay
-- free-entry; metadata-only updates of a validated return pass; an
-- uncontrolled remittance JE on the control account (the PXL-AUD-041
-- scenario) blocks finalization with a variance error.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111123',
        'authenticated', 'authenticated', 'harness-ewt-gate@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111123","role":"authenticated"}', true);

-- ── Company + setup ────────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222234', 'corporation',
        'EWT Gate Test Corp', 'Trading', '111-222-333-008',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-ewt-gate@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333345',
        '22222222-2222-2222-2222-222222222234', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444456',
        '22222222-2222-2222-2222-222222222234',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222234',
       '44444444-4444-4444-4444-444444444456',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000081', '22222222-2222-2222-2222-222222222234',
   '1010', 'Cash in Bank',   'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000082', '22222222-2222-2222-2222-222222222234',
   '2010', 'Accounts Payable','liability','credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000083', '22222222-2222-2222-2222-222222222234',
   '2150', 'EWT Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000084', '22222222-2222-2222-2222-222222222234',
   '1300', 'Input VAT',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000085', '22222222-2222-2222-2222-222222222234',
   '5020', 'Rent Expense',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222234',
        'aaaaaaaa-0000-0000-0000-000000000082',
        'aaaaaaaa-0000-0000-0000-000000000081',
        'aaaaaaaa-0000-0000-0000-000000000083',
        'aaaaaaaa-0000-0000-0000-000000000084',
        auth.uid(), auth.uid());

INSERT INTO bank_accounts (id, company_id, bank_name, account_number, account_name,
                           gl_account_id, created_by, updated_by)
VALUES ('77777777-7777-7777-7777-777777777789',
        '22222222-2222-2222-2222-222222222234', 'BDO', '001122334466',
        'EWT Gate Test Corp', 'aaaaaaaa-0000-0000-0000-000000000081',
        auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666678',
        '22222222-2222-2222-2222-222222222234', 'SUPP-EG1',
        'Gate Landlord Corp', '777-888-999-007',
        'Landlord HQ, Taguig', auth.uid(), auth.uid());

-- Q1 withholding evidence: posted CV, EWT 200 on explicit base 10,000 (WC140 2%)
INSERT INTO check_vouchers (id, company_id, branch_id, cv_number, voucher_date,
    bank_account_id, check_number, check_date, payee, payee_tin, supplier_id,
    total_gross_amount, total_ewt_amount, atc_code_id, ewt_rate, ewt_tax_base,
    particulars, status, created_by, updated_by)
VALUES ('88888888-8888-8888-8888-888888888900',
    '22222222-2222-2222-2222-222222222234', '33333333-3333-3333-3333-333333333345',
    'CV-000001', '2026-02-10', '77777777-7777-7777-7777-777777777789', 'CHK-0001',
    '2026-02-10', 'Gate Landlord Corp', '777-888-999-007',
    '66666666-6666-6666-6666-666666666678',
    10000, 200, (SELECT id FROM atc_codes WHERE code = 'WC140'), 2, 10000,
    'Rent Feb', 'draft', auth.uid(), auth.uid());

INSERT INTO check_voucher_lines (cv_id, company_id, line_number, expense_account_id,
                                 description, amount, created_by, updated_by)
VALUES ('88888888-8888-8888-8888-888888888900', '22222222-2222-2222-2222-222222222234',
        1, 'aaaaaaaa-0000-0000-0000-000000000085', 'Office rent February', 10000,
        auth.uid(), auth.uid());

SELECT fn_post_check_voucher('88888888-8888-8888-8888-888888888900');

-- ── 1. Server-side computation reads the tax ledger ─────────────────────────────
SELECT is(
  (SELECT total_tax_base::text || '|' || total_ewt_withheld::text
   FROM fn_compute_ewt_return('22222222-2222-2222-2222-222222222234', 2026, 1)),
  '10000.00|200.00',
  'fn_compute_ewt_return returns the quarterly ledger totals');

-- ── 2. Draft rows stay free-entry ───────────────────────────────────────────────
SELECT lives_ok(
  $$INSERT INTO ewt_returns (id, company_id, period_year, period_quarter,
      total_tax_base, total_ewt_withheld, remitted_prior, still_due, status,
      created_by, updated_by)
    VALUES ('99999999-9999-9999-9999-999999999911',
      '22222222-2222-2222-2222-222222222234', 2026, 1,
      9999, 150, 0, 150, 'draft', auth.uid(), auth.uid())$$,
  'a draft 1601EQ return saves with diverging figures (gate applies at final/filed only)');

-- ── 3-5. Finalization blocked: ledger mismatch, bad arithmetic, negative prior ──
SELECT throws_like(
  $$UPDATE ewt_returns SET status = 'final'
    WHERE id = '99999999-9999-9999-9999-999999999911'$$,
  '%does not match the tax ledger%',
  'final is blocked while the return figures diverge from the tax ledger');

SELECT throws_like(
  $$UPDATE ewt_returns
    SET status = 'final', total_tax_base = 10000, total_ewt_withheld = 200,
        remitted_prior = 0, still_due = 999
    WHERE id = '99999999-9999-9999-9999-999999999911'$$,
  '%still due%does not equal%',
  'final is blocked when still_due does not equal withheld less remitted prior');

SELECT throws_like(
  $$UPDATE ewt_returns
    SET status = 'final', total_tax_base = 10000, total_ewt_withheld = 200,
        remitted_prior = -50, still_due = 250
    WHERE id = '99999999-9999-9999-9999-999999999911'$$,
  '%remitted prior%cannot be negative%',
  'final is blocked when remitted_prior is negative');

-- ── 6-8. Matching figures finalize; metadata edits and filing still work ────────
SELECT lives_ok(
  $$UPDATE ewt_returns
    SET status = 'final', total_tax_base = 10000, total_ewt_withheld = 200,
        remitted_prior = 0, still_due = 200
    WHERE id = '99999999-9999-9999-9999-999999999911'$$,
  'final succeeds with ledger-matching figures on a reconciled quarter');

SELECT lives_ok(
  $$UPDATE ewt_returns SET reference_no = 'EFPS-2026Q1-001'
    WHERE id = '99999999-9999-9999-9999-999999999911'$$,
  'metadata-only update of a validated final return passes the gate');

SELECT lives_ok(
  $$UPDATE ewt_returns SET status = 'filed', filed_date = '2026-04-25'
    WHERE id = '99999999-9999-9999-9999-999999999911'$$,
  'final-to-filed re-validates and succeeds while the quarter still reconciles');

-- ── 9-11. Uncontrolled remittance JE breaks GL reconciliation (AUD-041 lane) ────
INSERT INTO check_vouchers (id, company_id, branch_id, cv_number, voucher_date,
    bank_account_id, check_number, check_date, payee, payee_tin, supplier_id,
    total_gross_amount, total_ewt_amount, atc_code_id, ewt_rate, ewt_tax_base,
    particulars, status, created_by, updated_by)
VALUES ('88888888-8888-8888-8888-888888888901',
    '22222222-2222-2222-2222-222222222234', '33333333-3333-3333-3333-333333333345',
    'CV-000002', '2026-05-10', '77777777-7777-7777-7777-777777777789', 'CHK-0002',
    '2026-05-10', 'Gate Landlord Corp', '777-888-999-007',
    '66666666-6666-6666-6666-666666666678',
    15000, 300, (SELECT id FROM atc_codes WHERE code = 'WC140'), 2, 15000,
    'Rent May', 'draft', auth.uid(), auth.uid());

INSERT INTO check_voucher_lines (cv_id, company_id, line_number, expense_account_id,
                                 description, amount, created_by, updated_by)
VALUES ('88888888-8888-8888-8888-888888888901', '22222222-2222-2222-2222-222222222234',
        1, 'aaaaaaaa-0000-0000-0000-000000000085', 'Office rent May', 15000,
        auth.uid(), auth.uid());

SELECT lives_ok(
  $$SELECT fn_post_check_voucher('88888888-8888-8888-8888-888888888901')$$,
  'Q2 CV with EWT posts (ledger 15,000 base / 300 withheld)');

SELECT lives_ok(
  $$SELECT fn_post_manual_je(
      '22222222-2222-2222-2222-222222222234',
      '33333333-3333-3333-3333-333333333345',
      '2026-05-31', 'EWT remittance (uncontrolled)', 'MANUAL', false,
      '[{"account_id":"aaaaaaaa-0000-0000-0000-000000000083","debit_amount":300,"credit_amount":0},
        {"account_id":"aaaaaaaa-0000-0000-0000-000000000081","debit_amount":0,"credit_amount":300}]'::jsonb)$$,
  'an uncontrolled manual remittance JE posts against the EWT Payable control account');

SELECT throws_like(
  $$INSERT INTO ewt_returns (company_id, period_year, period_quarter,
      total_tax_base, total_ewt_withheld, remitted_prior, still_due, status,
      created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-222222222234', 2026, 2,
      15000, 300, 0, 300, 'final', auth.uid(), auth.uid())$$,
  '%does not reconcile to GL account%',
  'final is blocked when the tax ledger does not reconcile to the EWT Payable GL account');

-- ── 12. The unreconciled quarter can still be saved as draft ────────────────────
SELECT lives_ok(
  $$INSERT INTO ewt_returns (company_id, period_year, period_quarter,
      total_tax_base, total_ewt_withheld, remitted_prior, still_due, status,
      created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-222222222234', 2026, 2,
      15000, 300, 0, 300, 'draft', auth.uid(), auth.uid())$$,
  'the unreconciled quarter still saves as a draft return');

SELECT * FROM finish();
ROLLBACK;
