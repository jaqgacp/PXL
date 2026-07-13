-- ══════════════════════════════════════════════════════════════════════════════
-- ATC-DOCDATE-VERSION-001 - ATC validity is evaluated as of the document date,
-- and one official ATC code may carry successive effective-dated rate versions.
-- Finding coverage: PXL-AUD-035 (document-date validation) / PXL-AUD-036 (rate
-- versioning). Trusted replacement for the held-out draft 20260710000004.
--
-- Scenario: WI777 withholding is 1% through 2026-06-30 and 2% from 2026-07-01
-- (a BIR rate change under the same official code). Documents dated in June must
-- use the 1% version; documents dated in July must use the 2% version; the wrong
-- version for a given document date is rejected. A backdated check voucher in an
-- open period validates against the version in force on the voucher date, not
-- today's version. Version integrity (overlap, successor linkage), effective_from
-- immutability once used, and rate immutability once used are enforced.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111124',
        'authenticated', 'authenticated', 'harness-atcver@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111124","role":"authenticated"}', true);

-- ── Company + minimal setup for the check-voucher caller path ────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222244', 'corporation',
        'ATC Version Test Corp', 'Trading', '111-222-333-024',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-atcver@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333355',
        '22222222-2222-2222-2222-222222222244', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444466',
        '22222222-2222-2222-2222-222222222244',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222244',
       '44444444-4444-4444-4444-444444444466',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES ('aaaaaaaa-0000-0000-0000-000000000241', '22222222-2222-2222-2222-222222222244',
        '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO bank_accounts (id, company_id, bank_name, account_number, account_name,
                           gl_account_id, created_by, updated_by)
VALUES ('77777777-7777-7777-7777-777777777799',
        '22222222-2222-2222-2222-222222222244', 'BDO', '009988776655',
        'ATC Version Test Corp', 'aaaaaaaa-0000-0000-0000-000000000241',
        auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666688',
        '22222222-2222-2222-2222-222222222244', 'SUPP-ATC1',
        'ATC Landlord Corp', '777-888-999-024',
        'Landlord HQ, Taguig', auth.uid(), auth.uid());

-- ── Versioned ATC: WI777 1% -> 2% under the same official code ──────────────────
INSERT INTO atc_codes (id, code, description, tax_category, rate, is_active,
                       effective_from, effective_to, created_by, updated_by)
VALUES ('cccccccc-0000-0000-0000-000000000001', 'WI777', 'Rent 1% (through Jun 2026)',
        'ewt', 1.00, true, '1900-01-01', '2026-06-30', auth.uid(), auth.uid());

INSERT INTO atc_codes (id, code, description, tax_category, rate, is_active,
                       effective_from, supersedes_atc_code_id, created_by, updated_by)
VALUES ('cccccccc-0000-0000-0000-000000000002', 'WI777', 'Rent 2% (from Jul 2026)',
        'ewt', 2.00, true, '2026-07-01',
        'cccccccc-0000-0000-0000-000000000001', auth.uid(), auth.uid());

-- ── 1-2. As-of resolver returns the version in force on the given date ──────────
SELECT is(
  fn_atc_version_asof('WI777', 'ewt', DATE '2026-06-15'),
  'cccccccc-0000-0000-0000-000000000001'::uuid,
  'resolver returns the 1% version for a June document date');

SELECT is(
  fn_atc_version_asof('WI777', 'ewt', DATE '2026-07-15'),
  'cccccccc-0000-0000-0000-000000000002'::uuid,
  'resolver returns the 2% version for a July document date');

-- ── 3. Global code uniqueness is replaced by version-aware uniqueness ───────────
SELECT is(
  (SELECT count(*) FROM atc_codes WHERE code = 'WI777')::int,
  2,
  'one official ATC code can carry two effective-dated versions');

-- ── 4-6. PV EWT validator honors the document date ──────────────────────────────
SELECT throws_like(
  $$SELECT fn_validate_payment_voucher_line_ewt(
      '22222222-2222-2222-2222-222222222244', 9800, 200,
      'cccccccc-0000-0000-0000-000000000002', 10000, NULL, DATE '2026-06-15')$$,
  '%not effective on document date 2026-06-15%',
  'the 2% version is rejected on a June-dated document (not yet effective)');

SELECT lives_ok(
  $$SELECT fn_validate_payment_voucher_line_ewt(
      '22222222-2222-2222-2222-222222222244', 9900, 100,
      'cccccccc-0000-0000-0000-000000000001', 10000, NULL, DATE '2026-06-15')$$,
  'the 1% version validates a June-dated document (100 = 1% of 10,000)');

SELECT lives_ok(
  $$SELECT fn_validate_payment_voucher_line_ewt(
      '22222222-2222-2222-2222-222222222244', 9800, 200,
      'cccccccc-0000-0000-0000-000000000002', 10000, NULL, DATE '2026-07-15')$$,
  'the 2% version validates a July-dated document (200 = 2% of 10,000)');

-- ── 7-8. OR CWT validator honors the document date ──────────────────────────────
SELECT throws_like(
  $$SELECT fn_validate_receipt_line_cwt(
      '22222222-2222-2222-2222-222222222244', 9800, 200,
      'cccccccc-0000-0000-0000-000000000002', 10000, NULL, DATE '2026-06-15')$$,
  '%not effective on document date 2026-06-15%',
  'CWT: the 2% version is rejected on a June-dated receipt');

SELECT lives_ok(
  $$SELECT fn_validate_receipt_line_cwt(
      '22222222-2222-2222-2222-222222222244', 9900, 100,
      'cccccccc-0000-0000-0000-000000000001', 10000, NULL, DATE '2026-06-15')$$,
  'CWT: the 1% version validates a June-dated receipt');

-- ── 9. Backdated check voucher validates against the voucher-date version ───────
-- Under CURRENT_DATE (2026-07-13) the 1% version is expired; evaluated as of the
-- 2026-06-20 voucher date it is valid, so the backdated CV is accepted.
SELECT lives_ok(
  $$INSERT INTO check_vouchers (company_id, branch_id, cv_number, voucher_date,
      bank_account_id, check_number, check_date, payee, payee_tin, supplier_id,
      total_gross_amount, total_ewt_amount, atc_code_id, ewt_tax_base, particulars,
      status, created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-222222222244', '33333333-3333-3333-3333-333333333355',
      'CV-BACKDATED', '2026-06-20', '77777777-7777-7777-7777-777777777799', 'CHK-9001',
      '2026-06-20', 'ATC Landlord Corp', '777-888-999-024',
      '66666666-6666-6666-6666-666666666688',
      10100, 100, 'cccccccc-0000-0000-0000-000000000001', 10000,
      'Rent June', 'draft', auth.uid(), auth.uid())$$,
  'a backdated June CV validates against the 1% version in force on the voucher date');

-- ── 10. A not-yet-effective version is rejected on the earlier voucher date ──────
SELECT throws_like(
  $$INSERT INTO check_vouchers (company_id, branch_id, cv_number, voucher_date,
      bank_account_id, check_number, check_date, payee, payee_tin, supplier_id,
      total_gross_amount, total_ewt_amount, atc_code_id, ewt_tax_base, particulars,
      status, created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-222222222244', '33333333-3333-3333-3333-333333333355',
      'CV-FUTUREATC', '2026-06-20', '77777777-7777-7777-7777-777777777799', 'CHK-9002',
      '2026-06-20', 'ATC Landlord Corp', '777-888-999-024',
      '66666666-6666-6666-6666-666666666688',
      10200, 200, 'cccccccc-0000-0000-0000-000000000002', 10000,
      'Rent June', 'draft', auth.uid(), auth.uid())$$,
  '%not effective on document date 2026-06-20%',
  'the 2% version cannot be used on a June-dated check voucher');

-- ── 11. Overlap guard: no two active versions may cover the same window ─────────
SELECT throws_like(
  $$INSERT INTO atc_codes (code, description, tax_category, rate, is_active, effective_from)
    VALUES ('WI777', 'Rent 3% overlap', 'ewt', 3.00, true, '2026-08-01')$$,
  '%overlapping active effective window%',
  'a third active version overlapping the open 2% window is rejected');

-- ── 12. Successor linkage must keep the same official code ──────────────────────
SELECT throws_like(
  $$INSERT INTO atc_codes (code, description, tax_category, rate, is_active,
        effective_from, supersedes_atc_code_id)
    VALUES ('WI999', 'Wrong code successor', 'ewt', 2.00, true, '2027-01-01',
        'cccccccc-0000-0000-0000-000000000001')$$,
  '%same official code%',
  'a successor pointing at a different official code is rejected');

-- ── 13. Mark the 1% version as used (posted tax ledger row) ─────────────────────
INSERT INTO tax_detail_entries (company_id, source_doc_type, source_doc_id, tax_kind,
                                atc_code_id, tax_base, tax_amount, posting_date, document_date)
VALUES ('22222222-2222-2222-2222-222222222244', 'PV', gen_random_uuid(), 'ewt_payable',
        'cccccccc-0000-0000-0000-000000000001', 10000, 100, '2026-06-20', '2026-06-20');

-- ── 14. effective_from is immutable once the version is used ─────────────────────
SELECT throws_like(
  $$UPDATE atc_codes SET effective_from = '2026-01-01'
    WHERE id = 'cccccccc-0000-0000-0000-000000000001'$$,
  '%effective start are immutable%',
  'the effective start of a used ATC version cannot be moved');

-- ── 15. effective_to stays adjustable so a window can be closed ──────────────────
SELECT lives_ok(
  $$UPDATE atc_codes SET effective_to = '2026-06-29'
    WHERE id = 'cccccccc-0000-0000-0000-000000000001'$$,
  'the effective end of a used ATC version can still be closed');

-- ── 16. Rate remains immutable once used ─────────────────────────────────────────
SELECT throws_like(
  $$UPDATE atc_codes SET rate = 9.00
    WHERE id = 'cccccccc-0000-0000-0000-000000000001'$$,
  '%immutable after use%',
  'the rate of a used ATC version cannot be changed in place');

SELECT * FROM finish();
ROLLBACK;
