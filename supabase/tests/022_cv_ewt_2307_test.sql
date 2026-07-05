-- ══════════════════════════════════════════════════════════════════════════════
-- CV-EWT-2307-001 - Check Voucher EWT Feeds Certificates and Cancels Cleanly
-- Finding coverage: PXL-AUD-032 / PXL-AUD-033.
--
-- CV EWT is now validated like PV EWT (current ATC, rate-on-base, explicit
-- base, controlled variance reasons) and must be supplier-linked; the posted
-- tax detail row carries counterparty_id + supplier master identity, so the
-- quarterly Form 2307 batch includes check payments instead of aborting.
-- Legacy supplier-unlinked rows are skipped with a warning count. Cancelling a
-- posted CV inserts the PXL-AUD-027 counter-row (reverses link, dated on the
-- cancel date), so vw_ewt_summary_ap drops both rows.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111122',
        'authenticated', 'authenticated', 'harness-cv-ewt@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111122","role":"authenticated"}', true);

-- ── Company + setup ────────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222233', 'corporation',
        'CV EWT Test Corp', 'Trading', '111-222-333-007',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-cv-ewt@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333344',
        '22222222-2222-2222-2222-222222222233', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444455',
        '22222222-2222-2222-2222-222222222233',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222233',
       '44444444-4444-4444-4444-444444444455',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000071', '22222222-2222-2222-2222-222222222233',
   '1010', 'Cash in Bank',   'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000072', '22222222-2222-2222-2222-222222222233',
   '2010', 'Accounts Payable','liability','credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000073', '22222222-2222-2222-2222-222222222233',
   '2150', 'EWT Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000074', '22222222-2222-2222-2222-222222222233',
   '1300', 'Input VAT',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000075', '22222222-2222-2222-2222-222222222233',
   '5020', 'Rent Expense',   'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222233',
        'aaaaaaaa-0000-0000-0000-000000000072',
        'aaaaaaaa-0000-0000-0000-000000000071',
        'aaaaaaaa-0000-0000-0000-000000000073',
        'aaaaaaaa-0000-0000-0000-000000000074',
        auth.uid(), auth.uid());

INSERT INTO bank_accounts (id, company_id, bank_name, account_number, account_name,
                           gl_account_id, created_by, updated_by)
VALUES ('77777777-7777-7777-7777-777777777788',
        '22222222-2222-2222-2222-222222222233', 'BDO', '001122334455',
        'CV EWT Test Corp', 'aaaaaaaa-0000-0000-0000-000000000071',
        auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666677',
        '22222222-2222-2222-2222-222222222233', 'SUPP-CV1',
        'CV Landlord Corp', '777-888-999-006',
        'Landlord HQ, Taguig', auth.uid(), auth.uid());

-- Expired ATC for the rejection leg (WC140 = 2% is the seeded current code)
INSERT INTO atc_codes (id, code, description, tax_category, rate,
                       effective_from, effective_to, created_by, updated_by)
VALUES ('bbbbbbbb-0000-0000-0000-000000000076', 'WXEXP', 'Expired test code', 'ewt', 5.00,
        '1900-01-01', '2026-01-01', auth.uid(), auth.uid());

-- ── 1-2. Save-time validation: supplier link + rate-on-base (PV parity) ─────────
SELECT throws_like(
  $$INSERT INTO check_vouchers (company_id, branch_id, cv_number, voucher_date,
      bank_account_id, check_number, check_date, payee, payee_tin,
      total_gross_amount, total_ewt_amount, atc_code_id, ewt_tax_base, particulars,
      status, created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-222222222233', '33333333-3333-3333-3333-333333333344',
      'CV-NOSUP', '2026-02-10', '77777777-7777-7777-7777-777777777788', 'CHK-0001',
      '2026-02-10', 'CV Landlord Corp', '777-888-999-006',
      10000, 200, (SELECT id FROM atc_codes WHERE code = 'WC140'), 10000,
      'Rent Feb', 'draft', auth.uid(), auth.uid())$$,
  '%supplier is required when EWT is withheld%',
  'CV EWT without a supplier link is rejected at save time');

SELECT throws_like(
  $$INSERT INTO check_vouchers (company_id, branch_id, cv_number, voucher_date,
      bank_account_id, check_number, check_date, payee, payee_tin, supplier_id,
      total_gross_amount, total_ewt_amount, atc_code_id, ewt_tax_base, particulars,
      status, created_by, updated_by)
    VALUES ('22222222-2222-2222-2222-222222222233', '33333333-3333-3333-3333-333333333344',
      'CV-BADEWT', '2026-02-10', '77777777-7777-7777-7777-777777777788', 'CHK-0002',
      '2026-02-10', 'CV Landlord Corp', '777-888-999-006',
      '66666666-6666-6666-6666-666666666677',
      10000, 250, (SELECT id FROM atc_codes WHERE code = 'WC140'), 10000,
      'Rent Feb', 'draft', auth.uid(), auth.uid())$$,
  '%does not match ATC%Select a variance reason%',
  'CV EWT off the ATC rate on the explicit base is rejected without a variance reason');

-- ── 3-5. Variance reason accepted; expired ATC rejected ─────────────────────────
SELECT lives_ok(
  $$INSERT INTO check_vouchers (id, company_id, branch_id, cv_number, voucher_date,
      bank_account_id, check_number, check_date, payee, payee_tin, supplier_id,
      total_gross_amount, total_ewt_amount, atc_code_id, ewt_rate, ewt_tax_base,
      ewt_variance_reason, particulars, status, created_by, updated_by)
    VALUES ('88888888-8888-8888-8888-888888888899',
      '22222222-2222-2222-2222-222222222233', '33333333-3333-3333-3333-333333333344',
      'CV-000001', '2026-02-10', '77777777-7777-7777-7777-777777777788', 'CHK-0003',
      '2026-02-10', 'CV Landlord Corp', '777-888-999-006',
      '66666666-6666-6666-6666-666666666677',
      10000, 250, (SELECT id FROM atc_codes WHERE code = 'WC140'), 2, 10000,
      'partial_non_taxable', 'Rent Feb', 'draft', auth.uid(), auth.uid())$$,
  'off-rate CV EWT with an authorized variance reason is accepted (PV parity)');

SELECT lives_ok(
  $$UPDATE check_vouchers
    SET total_ewt_amount = 200, ewt_variance_reason = NULL
    WHERE id = '88888888-8888-8888-8888-888888888899'$$,
  'rate-matching CV EWT needs no variance reason');

SELECT throws_like(
  $$UPDATE check_vouchers
    SET atc_code_id = 'bbbbbbbb-0000-0000-0000-000000000076'
    WHERE id = '88888888-8888-8888-8888-888888888899'$$,
  '%inactive, expired, deprecated%',
  'an expired ATC code is rejected on the CV EWT path');

-- ── 6-9. Post: balanced JE + supplier-linked tax detail ─────────────────────────
INSERT INTO check_voucher_lines (cv_id, company_id, line_number, expense_account_id,
                                 description, amount, created_by, updated_by)
VALUES ('88888888-8888-8888-8888-888888888899', '22222222-2222-2222-2222-222222222233',
        1, 'aaaaaaaa-0000-0000-0000-000000000075', 'Office rent February', 10000,
        auth.uid(), auth.uid());

SELECT lives_ok(
  $$SELECT fn_post_check_voucher('88888888-8888-8888-8888-888888888899')$$,
  'validated supplier-linked CV with EWT posts');

SELECT is(
  (SELECT total_debit::text || '|' || total_credit::text FROM journal_entries
   WHERE reference_doc_type = 'CV'
     AND reference_doc_id = '88888888-8888-8888-8888-888888888899'
     AND je_number = 'JE-CV-CV-000001'),
  '10000.00|10000.00',
  'CV JE is balanced at the gross voucher amount');

SELECT is(
  (SELECT SUM(credit_amount) FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE je.reference_doc_type = 'CV'
     AND je.reference_doc_id = '88888888-8888-8888-8888-888888888899'
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000073'),
  200.00::numeric,
  'EWT payable is credited 200.00 (bank gets the 9,800 net)');

SELECT is(
  (SELECT counterparty_id::text || '|' || tax_base::text || '|' || tax_rate::text
          || '|' || tax_amount::text || '|' || counterparty_name
   FROM tax_detail_entries
   WHERE source_doc_type = 'CV'
     AND source_doc_id = '88888888-8888-8888-8888-888888888899'
     AND is_reversal = false),
  '66666666-6666-6666-6666-666666666677|10000.00|2.00|200.00|CV Landlord Corp',
  'tax detail row carries the supplier link, explicit base, ATC rate, and supplier master name');

SELECT is(
  (SELECT COUNT(*)::int FROM vw_ewt_summary_ap
   WHERE transaction_id = '88888888-8888-8888-8888-888888888899'
     AND supplier_id = '66666666-6666-6666-6666-666666666677'
     AND tax_withheld = 200.00),
  1, 'vw_ewt_summary_ap includes the posted CV EWT row');

-- ── 10-12. Quarterly 2307: CV included; unlinked legacy rows skip with warning ──
SELECT lives_ok(
  $$SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222233', 2026, 1)$$,
  'quarterly Form 2307 batch generates with CV EWT in the quarter');

SELECT is(
  (SELECT total_ewt FROM form_2307_issuances
   WHERE company_id = '22222222-2222-2222-2222-222222222233'
     AND supplier_id = '66666666-6666-6666-6666-666666666677'
     AND tax_year = 2026 AND tax_quarter = 1),
  200.00::numeric,
  'the supplier certificate includes the CV withholding');

-- Legacy-style unlinked row (pre-fix CV rows had counterparty_id = NULL)
INSERT INTO tax_detail_entries (company_id, branch_id, source_doc_type, source_doc_id,
        tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, posting_date, document_date,
        counterparty_tin, counterparty_name)
VALUES ('22222222-2222-2222-2222-222222222233', '33333333-3333-3333-3333-333333333344',
        'CV', gen_random_uuid(), 'ewt_payable',
        (SELECT id FROM atc_codes WHERE code = 'WC140'),
        5000, 2, 100, '2026-02-15', '2026-02-15',
        '999-999-999-000', 'Unlinked Legacy Payee');

SELECT is(
  (SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222233', 2026, 1))
    ->> 'skipped_unlinked_count',
  '1',
  'a supplier-unlinked EWT row is SKIPPED with a warning instead of aborting the batch');

-- ── 13-16. Cancel: counter-row convention ───────────────────────────────────────
SELECT lives_ok(
  $$SELECT fn_cancel_check_voucher('88888888-8888-8888-8888-888888888899', 'wrong payee')$$,
  'posted CV with EWT can be cancelled');

SELECT is(
  (SELECT r.document_date::text || '|' || r.tax_amount::text
   FROM tax_detail_entries r
   JOIN tax_detail_entries o ON o.id = r.reverses_tax_detail_id
   WHERE r.source_doc_type = 'CV'
     AND r.source_doc_id = '88888888-8888-8888-8888-888888888899'
     AND r.is_reversal = true),
  CURRENT_DATE::text || '|-200.00',
  'cancel inserts a negating counter-row linked via reverses_tax_detail_id, dated on the cancel date');

SELECT is(
  (SELECT COUNT(*)::int FROM vw_ewt_summary_ap
   WHERE transaction_id = '88888888-8888-8888-8888-888888888899'),
  0, 'vw_ewt_summary_ap drops both the original and the counter-row after cancel');

SELECT throws_like(
  $$SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222233', 2026, 1)$$,
  '%every EWT row%missing a supplier link%',
  'when only unlinked rows remain, generation raises the actionable unlinked message');

SELECT * FROM finish();
ROLLBACK;
