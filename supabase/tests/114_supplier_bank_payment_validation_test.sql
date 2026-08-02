-- Delivery Plan Phase 3 supplier-bank proof on fresh tenant data.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(15);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111175',
        'authenticated', 'authenticated', 'supplier-bank@test.local', '',
        now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111175","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-0000-0000-0000-000000000175', 'corporation',
        'Fresh Payables Inc', 'Business Services', '175-222-333-000', 'vat', 'calendar',
        'Unit 9', '', 'Makati', 'Metro Manila', '1200', 'supplier-bank@test.local',
        'Liza Cruz', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-0000-0000-0000-000000000175',
        '22222222-0000-0000-0000-000000000175', 'HO', 'Head Office',
        'Unit 9', '', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-0000-0000-0000-000000000175',
        '22222222-0000-0000-0000-000000000175', 'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
VALUES ('22222222-0000-0000-0000-000000000175',
        '44444444-0000-0000-0000-000000000175', 1, 'Jan 2026',
        '2026-01-01', '2026-01-31', false);

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000180', '22222222-0000-0000-0000-000000000175',
   '1010', 'Cash in Bank', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000181', '22222222-0000-0000-0000-000000000175',
   '1150', 'Supplier Advances', 'asset', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, default_cash_account_id, supplier_down_payments_account_id,
  created_by, updated_by
) VALUES (
  '22222222-0000-0000-0000-000000000175',
  'aaaaaaaa-0000-0000-0000-000000000180',
  'aaaaaaaa-0000-0000-0000-000000000181', auth.uid(), auth.uid()
);

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-0000-0000-0000-000000000175',
       '33333333-0000-0000-0000-000000000175', id, 'PV-', 6, 1, 1,
       true, auth.uid(), auth.uid()
FROM ref_document_types WHERE document_code = 'PV';

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, default_tax_type, is_active,
                       created_by, updated_by)
VALUES
  ('55555555-0000-0000-0000-000000000175',
   '22222222-0000-0000-0000-000000000175', 'SUP-BANK',
   'Fresh Banked Supplier Inc', '175-555-111-00000', 'Makati, Metro Manila',
   'vat_registered', true, auth.uid(), auth.uid()),
  ('55555555-0000-0000-0000-000000000176',
   '22222222-0000-0000-0000-000000000175', 'SUP-OTHER',
   'Other Fresh Supplier Inc', '175-555-222-00000', 'Taguig, Metro Manila',
   'vat_registered', true, auth.uid(), auth.uid());

INSERT INTO supplier_bank_accounts (
  id, company_id, supplier_id, bank_id, account_name, account_number,
  account_type, bank_branch, is_default, verification_status, created_by, updated_by
)
SELECT '66666666-0000-0000-0000-000000000175',
       '22222222-0000-0000-0000-000000000175',
       '55555555-0000-0000-0000-000000000175', id,
       'Fresh Banked Supplier Inc', '001122334455', 'checking', 'Makati', true,
       'unverified', auth.uid(), auth.uid()
FROM ref_banks WHERE bank_code = 'BDO';

SELECT is(
  (SELECT verification_status FROM supplier_bank_accounts
   WHERE id = '66666666-0000-0000-0000-000000000175'),
  'unverified', 'E1: supplier payment instructions begin explicitly unverified');

SELECT fn_save_payment_voucher(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-0000-0000-0000-000000000175',
    'branch_id', '33333333-0000-0000-0000-000000000175',
    'supplier_id', '55555555-0000-0000-0000-000000000175',
    'supplier_name_snapshot', 'Fresh Banked Supplier Inc',
    'supplier_tin_snapshot', '175-555-111-00000',
    'voucher_date', '2026-01-15',
    'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'BANK_XFER')
  ),
  jsonb_build_array(jsonb_build_object(
    'line_type', 'supplier_down_payment', 'payment_amount', 250, 'ewt_amount', 0
  ))
) AS missing_bank_voucher_id \gset

SELECT throws_ok(
  $$SELECT fn_post_payment_voucher('$$ || :'missing_bank_voucher_id' || $$'::uuid)$$,
  'P0001',
  'A verified supplier bank account is required for bank-transfer vouchers',
  'E1b: the database rejects a bank transfer without a supplier payee account');

SELECT throws_ok(
  $$SELECT fn_save_payment_voucher(
    NULL,
    jsonb_build_object(
      'company_id', '22222222-0000-0000-0000-000000000175',
      'branch_id', '33333333-0000-0000-0000-000000000175',
      'supplier_id', '55555555-0000-0000-0000-000000000176',
      'supplier_name_snapshot', 'Other Fresh Supplier Inc',
      'supplier_tin_snapshot', '175-555-222-00000',
      'voucher_date', '2026-01-15',
      'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'BANK_XFER'),
      'supplier_bank_account_id', '66666666-0000-0000-0000-000000000175'
    ),
    jsonb_build_array(jsonb_build_object(
      'line_type', 'supplier_down_payment', 'payment_amount', 1000, 'ewt_amount', 0
    ))
  )$$,
  'P0001',
  'Selected payee bank account is inactive or does not belong to this supplier and company',
  'E2: a voucher cannot select another supplier''s bank account');

SELECT fn_save_payment_voucher(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-0000-0000-0000-000000000175',
    'branch_id', '33333333-0000-0000-0000-000000000175',
    'supplier_id', '55555555-0000-0000-0000-000000000175',
    'supplier_name_snapshot', 'Fresh Banked Supplier Inc',
    'supplier_tin_snapshot', '175-555-111-00000',
    'voucher_date', '2026-01-15',
    'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'BANK_XFER'),
    'supplier_bank_account_id', '66666666-0000-0000-0000-000000000175',
    'remarks', 'Fresh supplier bank validation'
  ),
  jsonb_build_array(jsonb_build_object(
    'line_type', 'supplier_down_payment', 'payment_amount', 1000, 'ewt_amount', 0
  ))
) AS voucher_id \gset

SELECT is(
  (SELECT payee_account_number_snapshot FROM payment_vouchers WHERE id = :'voucher_id'::uuid),
  '001122334455', 'E3: saving captures the selected payee account number');

SELECT is(
  (SELECT payee_bank_name_snapshot FROM payment_vouchers WHERE id = :'voucher_id'::uuid),
  'BDO Unibank, Inc.', 'E4: saving resolves and snapshots the governed bank name');

SELECT throws_ok(
  $$SELECT fn_post_payment_voucher('$$ || :'voucher_id' || $$'::uuid)$$,
  'P0001',
  'Selected payee bank account must be verified before posting the payment voucher',
  'E5: an unverified payee account blocks voucher posting');

SELECT is(
  (SELECT status FROM payment_vouchers WHERE id = :'voucher_id'::uuid),
  'draft', 'E6: a rejected posting attempt leaves the voucher draft');

UPDATE supplier_bank_accounts
SET verification_status = 'verified'
WHERE id = '66666666-0000-0000-0000-000000000175';

SELECT ok(
  (SELECT verified_by = auth.uid() AND verified_at IS NOT NULL
   FROM supplier_bank_accounts WHERE id = '66666666-0000-0000-0000-000000000175'),
  'E7: verification records its actor and timestamp');

SELECT fn_save_payment_voucher(
  :'voucher_id'::uuid,
  jsonb_build_object(
    'company_id', '22222222-0000-0000-0000-000000000175',
    'branch_id', '33333333-0000-0000-0000-000000000175',
    'supplier_id', '55555555-0000-0000-0000-000000000175',
    'supplier_name_snapshot', 'Fresh Banked Supplier Inc',
    'supplier_tin_snapshot', '175-555-111-00000',
    'voucher_date', '2026-01-15',
    'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'BANK_XFER'),
    'supplier_bank_account_id', '66666666-0000-0000-0000-000000000175'
  ),
  jsonb_build_array(jsonb_build_object(
    'line_type', 'supplier_down_payment', 'payment_amount', 1000, 'ewt_amount', 0
  ))
);

SELECT lives_ok(
  $$SELECT fn_post_payment_voucher('$$ || :'voucher_id' || $$'::uuid)$$,
  'E8: a verified payee account permits the production voucher posting RPC');

SELECT is(
  (SELECT status FROM payment_vouchers WHERE id = :'voucher_id'::uuid),
  'posted', 'E9: the voucher reaches posted status');

SELECT is(
  (SELECT count(*)::int FROM journal_entries
   WHERE reference_doc_type = 'PV' AND reference_doc_id = :'voucher_id'::uuid
     AND status = 'posted'),
  1, 'E10: payment still posts exactly one journal through the Accounting Kernel');

SELECT is(
  (SELECT round(sum(debit_amount - credit_amount), 2) FROM journal_entry_lines
   WHERE je_id = (SELECT journal_entry_id FROM payment_vouchers WHERE id = :'voucher_id'::uuid)),
  0.00::numeric, 'E11: the payment journal remains balanced');

UPDATE supplier_bank_accounts
SET account_number = '998877665544'
WHERE id = '66666666-0000-0000-0000-000000000175';

SELECT is(
  (SELECT verification_status FROM supplier_bank_accounts
   WHERE id = '66666666-0000-0000-0000-000000000175'),
  'unverified', 'E12: changing verified payment instructions invalidates verification');

SELECT is(
  (SELECT payee_account_number_snapshot FROM payment_vouchers WHERE id = :'voucher_id'::uuid),
  '001122334455', 'E13: later master edits cannot rewrite the posted voucher snapshot');

SELECT is(
  (SELECT count(*)::int FROM inventory_events),
  0, 'E14: supplier-bank delivery leaves dormant IA-5 untouched');

SELECT * FROM finish();
ROLLBACK;
