-- WHT-MASTER-CONSOLIDATION-001 - retire duplicate withholding masters
--
-- PXL-AUD-044: customers use one CWT flag/default ATC, suppliers use one AP
-- EWT default ATC, and the unused ewt_codes/fwt_codes wrappers plus
-- default_ewt_code_id columns are gone.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

SELECT is(to_regclass('public.ewt_codes'), NULL::regclass, 'ewt_codes table is retired');
SELECT is(to_regclass('public.fwt_codes'), NULL::regclass, 'fwt_codes table is retired');

SELECT is(
  (SELECT COUNT(*)::int FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'customers' AND column_name = 'is_withholding_agent'),
  0,
  'legacy customers.is_withholding_agent column is retired');

SELECT is(
  (SELECT COUNT(*)::int FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'customers' AND column_name = 'default_ewt_code_id'),
  0,
  'legacy customers.default_ewt_code_id column is retired');

SELECT is(
  (SELECT COUNT(*)::int FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'default_ewt_code_id'),
  0,
  'legacy suppliers.default_ewt_code_id column is retired');

SELECT is(
  (SELECT COUNT(*)::int FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'items' AND column_name = 'default_ewt_code_id'),
  0,
  'legacy items.default_ewt_code_id column is retired');

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111245',
        'authenticated', 'authenticated', 'harness-wht-master@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111245","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222245', 'corporation',
        'Withholding Master Consolidation Corp', 'Trading', '111-222-333-245',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-wht-master@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

SELECT lives_ok(
  $$INSERT INTO customers (
      id, company_id, customer_code, registered_name, tin,
      default_tax_type, registered_address, delivery_address,
      is_subject_to_cwt, default_cwt_atc_code_id,
      created_by, updated_by
    )
    VALUES (
      '33333333-3333-3333-3333-333333333245',
      '22222222-2222-2222-2222-222222222245',
      'CUST-WHT-ONE', 'Customer CWT Corp', '123-456-789-245',
      'vat_registered', 'Customer HQ', 'Customer HQ',
      false, (SELECT id FROM atc_codes WHERE code = 'WC158'),
      auth.uid(), auth.uid()
    )$$,
  'customer saves one CWT default ATC without the legacy withholding flag');

SELECT results_eq(
  $$SELECT is_subject_to_cwt, default_cwt_atc_code_id IS NOT NULL
    FROM customers
    WHERE id = '33333333-3333-3333-3333-333333333245'$$,
  $$VALUES (true, true)$$,
  'customer CWT trigger auto-enables the single surviving CWT flag');

SELECT ok(
  fn_atc_code_used((SELECT default_cwt_atc_code_id FROM customers WHERE id = '33333333-3333-3333-3333-333333333245')),
  'ATC usage guard recognizes customer default CWT ATC');

SELECT lives_ok(
  $$INSERT INTO suppliers (
      id, company_id, supplier_code, registered_name, tin,
      default_tax_type, registered_address,
      is_subject_to_ewt, default_atc_code_id,
      created_by, updated_by
    )
    VALUES (
      '44444444-4444-4444-4444-444444444245',
      '22222222-2222-2222-2222-222222222245',
      'SUP-WHT-ONE', 'Supplier EWT Corp', '987-654-321-245',
      'vat_registered', 'Supplier HQ',
      false, (SELECT id FROM atc_codes WHERE code = 'WC140'),
      auth.uid(), auth.uid()
    )$$,
  'supplier saves one AP EWT default ATC without the legacy default EWT code');

SELECT results_eq(
  $$SELECT is_subject_to_ewt, default_atc_code_id IS NOT NULL
    FROM suppliers
    WHERE id = '44444444-4444-4444-4444-444444444245'$$,
  $$VALUES (true, true)$$,
  'supplier EWT trigger auto-enables the single surviving AP EWT flag');

SELECT ok(
  fn_atc_code_used((SELECT default_atc_code_id FROM suppliers WHERE id = '44444444-4444-4444-4444-444444444245')),
  'ATC usage guard recognizes supplier default AP EWT ATC');

SELECT * FROM finish();
ROLLBACK;
