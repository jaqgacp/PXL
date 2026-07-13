-- ══════════════════════════════════════════════════════════════════════════════
-- WHT-REMITTANCE-001 - Controlled EWT remittance / CWT application flow
-- Finding coverage: PXL-AUD-041 (and the PXL-AUD-034 remitted_prior residue).
--
-- A governed withholding_remittances document posts a JE classified WHTREM.
-- fn_wht_gl_reconciliation excludes WHTREM movements, so a legitimate
-- mid-quarter EWT remittance (0619-E) no longer breaks the QAP export or the
-- 1601EQ finalization gate — while an uncontrolled MANUAL remittance JE still
-- (correctly) surfaces as variance. 1601EQ remitted_prior is derived from the
-- controlled remittances and validated at finalization. The CWT-application
-- side (crediting CWT Receivable) is excluded symmetrically.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111199',
        'authenticated', 'authenticated', 'harness-wht-remit@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111199","role":"authenticated"}', true);

-- ── Company + setup ────────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-2222222222a1', 'corporation',
        'WHT Remit Test Corp', 'Trading', '111-222-333-099',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-wht-remit@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-3333333333a1',
        '22222222-2222-2222-2222-2222222222a1', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-4444444444a1',
        '22222222-2222-2222-2222-2222222222a1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-2222222222a1',
       '44444444-4444-4444-4444-4444444444a1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-0000000000a1', '22222222-2222-2222-2222-2222222222a1',
   '1010', 'Cash in Bank',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a2', '22222222-2222-2222-2222-2222222222a1',
   '2010', 'Accounts Payable',   'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a3', '22222222-2222-2222-2222-2222222222a1',
   '2150', 'EWT Payable',        'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a4', '22222222-2222-2222-2222-2222222222a1',
   '1300', 'Input VAT',          'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a5', '22222222-2222-2222-2222-2222222222a1',
   '5020', 'Rent Expense',       'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a6', '22222222-2222-2222-2222-2222222222a1',
   '1155', 'CWT Receivable',     'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000a7', '22222222-2222-2222-2222-2222222222a1',
   '2200', 'Income Tax Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, ewt_withheld_account_id,
        input_vat_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-2222222222a1',
        'aaaaaaaa-0000-0000-0000-0000000000a2',
        'aaaaaaaa-0000-0000-0000-0000000000a1',
        'aaaaaaaa-0000-0000-0000-0000000000a3',
        'aaaaaaaa-0000-0000-0000-0000000000a6',
        'aaaaaaaa-0000-0000-0000-0000000000a4',
        auth.uid(), auth.uid());

INSERT INTO bank_accounts (id, company_id, bank_name, account_number, account_name,
                           gl_account_id, created_by, updated_by)
VALUES ('77777777-7777-7777-7777-7777777777a1',
        '22222222-2222-2222-2222-2222222222a1', 'BDO', '001122334499',
        'WHT Remit Test Corp', 'aaaaaaaa-0000-0000-0000-0000000000a1',
        auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-6666666666a1',
        '22222222-2222-2222-2222-2222222222a1', 'SUPP-WR1',
        'Remit Landlord Corp', '777-888-999-099',
        'Landlord HQ, Taguig', auth.uid(), auth.uid());

-- Q1 withholding evidence: posted CV in January, EWT 200 on base 10,000 (WC140 2%).
INSERT INTO check_vouchers (id, company_id, branch_id, cv_number, voucher_date,
    bank_account_id, check_number, check_date, payee, payee_tin, supplier_id,
    total_gross_amount, total_ewt_amount, atc_code_id, ewt_rate, ewt_tax_base,
    particulars, status, created_by, updated_by)
VALUES ('88888888-8888-8888-8888-8888888888a1',
    '22222222-2222-2222-2222-2222222222a1', '33333333-3333-3333-3333-3333333333a1',
    'CV-000001', '2026-01-15', '77777777-7777-7777-7777-7777777777a1', 'CHK-0001',
    '2026-01-15', 'Remit Landlord Corp', '777-888-999-099',
    '66666666-6666-6666-6666-6666666666a1',
    10000, 200, (SELECT id FROM atc_codes WHERE code = 'WC140'), 2, 10000,
    'Rent January', 'draft', auth.uid(), auth.uid());

INSERT INTO check_voucher_lines (cv_id, company_id, line_number, expense_account_id,
                                 description, amount, created_by, updated_by)
VALUES ('88888888-8888-8888-8888-8888888888a1', '22222222-2222-2222-2222-2222222222a1',
        1, 'aaaaaaaa-0000-0000-0000-0000000000a5', 'Office rent January', 10000,
        auth.uid(), auth.uid());

SELECT fn_post_check_voucher('88888888-8888-8888-8888-8888888888a1');

-- ── 1. Baseline: EWT Payable ledger reconciles to the GL control account ────────
SELECT is(
  (SELECT is_reconciled::text || '|' || gl_amount::text
   FROM fn_wht_gl_reconciliation('22222222-2222-2222-2222-2222222222a1',
                                 '2026-01-01', '2026-03-31')
   WHERE tax_kind = 'ewt_payable'),
  'true|200.00',
  'EWT Payable reconciles (ledger 200 = GL 200) before any remittance');

-- ── 2. Save + post a controlled EWT remittance (0619-E) covering January ────────
SELECT lives_ok(
  $$SELECT fn_save_withholding_remittance(
      NULL, '22222222-2222-2222-2222-2222222222a1',
      '33333333-3333-3333-3333-3333333333a1',
      'REM-0619E-2026-01', 'ewt_payable', '0619E',
      2026, 1, NULL, '2026-02-10', 200,
      'aaaaaaaa-0000-0000-0000-0000000000a1', 'EFPS-0619E-JAN', 'January EWT remittance')$$,
  'a draft EWT remittance saves');

SELECT lives_ok(
  $$SELECT fn_post_withholding_remittance(
      (SELECT id FROM withholding_remittances WHERE remittance_number = 'REM-0619E-2026-01'))$$,
  'the EWT remittance posts (DR EWT Payable / CR Cash)');

-- ── 3. The remittance JE is classified WHTREM and really hit EWT Payable ────────
SELECT is(
  (SELECT je.reference_doc_type
   FROM withholding_remittances wr
   JOIN journal_entries je ON je.id = wr.journal_entry_id
   WHERE wr.remittance_number = 'REM-0619E-2026-01'),
  'WHTREM',
  'the remittance journal entry carries the governed WHTREM source type');

SELECT is(
  (SELECT COALESCE(SUM(jel.credit_amount - jel.debit_amount), 0)::text
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE jel.account_id = 'aaaaaaaa-0000-0000-0000-0000000000a3'
     AND je.status = 'posted'),
  '0.00',
  'net EWT Payable GL movement is 0 after remittance (accrual 200 less remittance 200)');

-- ── 4. Reconciliation still passes because WHTREM is excluded ────────────────────
SELECT is(
  (SELECT is_reconciled::text || '|' || gl_amount::text
   FROM fn_wht_gl_reconciliation('22222222-2222-2222-2222-2222222222a1',
                                 '2026-01-01', '2026-03-31')
   WHERE tax_kind = 'ewt_payable'),
  'true|200.00',
  'EWT Payable still reconciles after the controlled remittance (WHTREM excluded)');

-- ── 5. QAP export for the quarter now succeeds (was hard-blocked before) ────────
SELECT lives_ok(
  $$SELECT fn_snapshot_wht_export('22222222-2222-2222-2222-2222222222a1', 'QAP', 2026, 1)$$,
  'QAP export succeeds for a quarter with a mid-quarter remittance');

-- ── 6. remitted_prior is derived from the controlled remittance ─────────────────
SELECT is(
  fn_compute_ewt_remitted_prior('22222222-2222-2222-2222-2222222222a1', 2026, 1)::text,
  '200.00',
  'fn_compute_ewt_remitted_prior sums the January 0619-E remittance');

-- ── 7. 1601EQ finalizes when remitted_prior matches the remittances ─────────────
SELECT lives_ok(
  $$INSERT INTO ewt_returns (id, company_id, period_year, period_quarter,
      total_tax_base, total_ewt_withheld, remitted_prior, still_due, status,
      created_by, updated_by)
    VALUES ('99999999-9999-9999-9999-9999999999a1',
      '22222222-2222-2222-2222-2222222222a1', 2026, 1,
      10000, 200, 200, 0, 'final', auth.uid(), auth.uid())$$,
  '1601EQ finalizes with remitted_prior 200 matching the derived remittances');

-- ── 8. Wrong remitted_prior is rejected against the derived figure ──────────────
SELECT throws_like(
  $$INSERT INTO ewt_returns (company_id, period_year, period_quarter,
      total_tax_base, total_ewt_withheld, remitted_prior, still_due, status,
      created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-2222222222a1', 2026, 1,
      10000, 200, 0, 200, 'final', auth.uid(), auth.uid())$$,
  '%remitted prior%does not match%',
  'finalization is blocked when remitted_prior diverges from the controlled remittances');

-- ── 9-10. Voiding the remittance reverses the JE and clears remitted_prior ──────
SELECT lives_ok(
  $$SELECT fn_void_withholding_remittance(
      (SELECT id FROM withholding_remittances WHERE remittance_number = 'REM-0619E-2026-01'),
      'Filed under the wrong period')$$,
  'a posted EWT remittance can be voided (reversing JE)');

SELECT is(
  fn_compute_ewt_remitted_prior('22222222-2222-2222-2222-2222222222a1', 2026, 1)::text,
  '0.00',
  'a voided remittance no longer counts toward remitted_prior');

-- Reconciliation stays balanced: original and reversal are both WHTREM-excluded.
SELECT is(
  (SELECT is_reconciled::text
   FROM fn_wht_gl_reconciliation('22222222-2222-2222-2222-2222222222a1',
                                 '2026-01-01', '2026-03-31')
   WHERE tax_kind = 'ewt_payable'),
  'true',
  'EWT Payable still reconciles after the remittance is voided');

-- ── 11. Posting a non-draft remittance is rejected ──────────────────────────────
SELECT throws_like(
  $$SELECT fn_post_withholding_remittance(
      (SELECT id FROM withholding_remittances WHERE remittance_number = 'REM-0619E-2026-01'))$$,
  '%Only draft remittances can be posted%',
  'a voided remittance cannot be re-posted');

-- ── 12-13. CWT application is excluded symmetrically (SAWT side) ─────────────────
-- No CWT withholding exists (cwt_receivable ledger = 0). Applying CWT against
-- income tax due credits CWT Receivable; without the WHTREM exclusion the GL
-- would show -100 vs ledger 0 and block the SAWT export.
SELECT lives_ok(
  $$SELECT fn_post_withholding_remittance(
      fn_save_withholding_remittance(
        NULL, '22222222-2222-2222-2222-2222222222a1',
        '33333333-3333-3333-3333-3333333333a1',
        'REM-CWT-2026-Q1', 'cwt_receivable', 'ITR',
        2026, NULL, 1, '2026-03-20', 100,
        'aaaaaaaa-0000-0000-0000-0000000000a7', NULL, 'Apply CWT to income tax due'))$$,
  'a CWT application posts (DR Income Tax Payable / CR CWT Receivable)');

SELECT is(
  (SELECT is_reconciled::text
   FROM fn_wht_gl_reconciliation('22222222-2222-2222-2222-2222222222a1',
                                 '2026-01-01', '2026-03-31')
   WHERE tax_kind = 'cwt_receivable'),
  'true',
  'CWT Receivable still reconciles after the application (WHTREM excluded)');

-- ── 14. An uncontrolled MANUAL remittance JE still surfaces as variance ─────────
-- Proves the exclusion is selective: only the governed WHTREM document is
-- trusted; a hand-posted MANUAL debit to EWT Payable still breaks reconciliation.
SELECT lives_ok(
  $$SELECT fn_post_manual_je(
      '22222222-2222-2222-2222-2222222222a1',
      '33333333-3333-3333-3333-3333333333a1',
      '2026-03-31', 'EWT remittance (uncontrolled)', 'MANUAL', false,
      '[{"account_id":"aaaaaaaa-0000-0000-0000-0000000000a3","debit_amount":50,"credit_amount":0},
        {"account_id":"aaaaaaaa-0000-0000-0000-0000000000a1","debit_amount":0,"credit_amount":50}]'::jsonb)$$,
  'an uncontrolled manual remittance JE posts against EWT Payable');

SELECT is(
  (SELECT is_reconciled::text || '|' || variance::text
   FROM fn_wht_gl_reconciliation('22222222-2222-2222-2222-2222222222a1',
                                 '2026-01-01', '2026-03-31')
   WHERE tax_kind = 'ewt_payable'),
  'false|50.00',
  'a MANUAL remittance JE is NOT excluded and correctly breaks reconciliation');

SELECT * FROM finish();
ROLLBACK;
