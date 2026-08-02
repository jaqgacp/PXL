-- Delivery Plan Phase 3: opening AR/AP must continue into the ordinary
-- collection and disbursement workflows. Fresh tenant data only.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(14);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111179',
        'authenticated', 'authenticated', 'opening-settlement@test.local', '',
        now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111179","role":"authenticated"}', true);

SELECT fn_provision_company(
    jsonb_build_object(
      'template_code', 'PH_STANDARD',
      'company', jsonb_build_object(
        'company_code', 'OPENSET1', 'entity_type', 'corporation',
        'registered_name', 'Opening Settlement Trading Inc',
        'trade_name', 'Opening Settlement', 'line_of_business', 'Wholesale Trading',
        'psic_code', '46900', 'tin', '179-222-333-00000',
        'tax_registration', 'vat', 'accounting_period', 'calendar',
        'address_line_1', 'Unit 11', 'address_line_2', 'Settlement Building', 'city', 'Makati',
        'province', 'Metro Manila', 'zip_code', '1200',
        'email', 'opening-settlement@test.local',
        'signatory_name', 'Nina Reyes', 'signatory_position', 'President',
        'workspace_accent_color', '#14532D',
        'functional_currency_code', 'PHP', 'reporting_currency_code', 'PHP'
      ),
      'fiscal_year', jsonb_build_object('start_date', '2026-01-01', 'year_name', 'FY2026'),
      'default_branch', jsonb_build_object(
        'branch_code', 'HO', 'branch_name', 'Head Office',
        'branch_type', 'head_office', 'tin_branch_code', '00000'
      ),
      'default_warehouse', jsonb_build_object(
        'warehouse_code', 'MAIN', 'warehouse_name', 'Main Warehouse',
        'warehouse_type', 'main'
      )
    ),
    'phase3-opening-settlement-001'
  ) AS provision_result \gset

SELECT is(
  (:'provision_result'::jsonb)->>'status',
  'succeeded', 'E1: the test begins from the production company-provisioning workflow');

SELECT id AS company_id FROM companies WHERE company_code = 'OPENSET1' \gset
SELECT id AS branch_id FROM branches WHERE company_id = :'company_id'::uuid AND branch_code = 'HO' \gset
SELECT account_id AS ar_account_id FROM account_mapping
WHERE company_id = :'company_id'::uuid AND key_code = 'AR_TRADE' \gset
SELECT account_id AS ap_account_id FROM account_mapping
WHERE company_id = :'company_id'::uuid AND key_code = 'AP_TRADE' \gset
SELECT id AS equity_account_id FROM chart_of_accounts
WHERE company_id = :'company_id'::uuid AND account_type = 'equity'
  AND is_active AND is_postable ORDER BY account_code LIMIT 1 \gset

-- Company provisioning deliberately leaves document sequencing as an explicit
-- operator choice. Complete the minimum Payment Voucher series setup here.
INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT :'company_id'::uuid, :'branch_id'::uuid, id, 'PV-', 6, 1, 1,
       true, auth.uid(), auth.uid()
FROM ref_document_types WHERE document_code = 'PV';

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, default_tax_type,
                       is_active, created_by, updated_by)
VALUES ('55555555-0000-0000-0000-000000000179', :'company_id'::uuid,
        'CUS-OPEN-SET', 'Opening Settlement Customer Inc', '179-555-111-00000',
        'Makati, Metro Manila', 'Makati, Metro Manila', 'vat_registered', true,
        auth.uid(), auth.uid());

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, default_tax_type, is_active,
                       created_by, updated_by)
VALUES ('66666666-0000-0000-0000-000000000179', :'company_id'::uuid,
        'SUP-OPEN-SET', 'Opening Settlement Supplier Inc', '179-666-111-00000',
        'Taguig, Metro Manila', 'vat_registered', true, auth.uid(), auth.uid());

SELECT fn_save_opening_balance(
  NULL,
  jsonb_build_object(
    'company_id', :'company_id', 'branch_id', :'branch_id',
    'batch_number', 'OB-SETTLEMENT-001', 'cutover_date', '2026-01-01',
    'description', 'Opening subledger settlement proof'
  ),
  jsonb_build_array(jsonb_build_object(
    'account_id', :'equity_account_id', 'description', 'Opening equity',
    'debit_amount', 0, 'credit_amount', 400
  )),
  jsonb_build_array(jsonb_build_object(
    'customer_id', '55555555-0000-0000-0000-000000000179',
    'legacy_invoice_number', 'LEG-SI-SET-001', 'invoice_date', '2025-12-15',
    'due_date', '2026-01-15', 'original_amount', 1000
  )),
  jsonb_build_array(jsonb_build_object(
    'supplier_id', '66666666-0000-0000-0000-000000000179',
    'legacy_bill_number', 'LEG-VB-SET-001', 'supplier_invoice_number', 'SUP-LEG-001',
    'bill_date', '2025-12-10', 'due_date', '2026-01-10', 'original_amount', 600
  )),
  '[]'::jsonb,
  '[]'::jsonb
) AS batch_id \gset

SELECT lives_ok(
  $$SELECT fn_post_opening_balance('$$ || :'batch_id' || $$'::uuid)$$,
  'E2: a balanced opening AR/AP cut-over posts through the production RPC');

SELECT id AS opening_ar_id FROM opening_balance_ar_lines WHERE batch_id = :'batch_id'::uuid \gset
SELECT id AS opening_ap_id FROM opening_balance_ap_lines WHERE batch_id = :'batch_id'::uuid \gset

SELECT fn_save_receipt(
  NULL,
  jsonb_build_object(
    'company_id', :'company_id', 'branch_id', :'branch_id',
    'customer_id', '55555555-0000-0000-0000-000000000179',
    'customer_name_snapshot', 'Opening Settlement Customer Inc',
    'customer_tin_snapshot', '179-555-111-00000',
    'receipt_date', '2026-01-15',
    'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'CASH')
  ),
  jsonb_build_array(jsonb_build_object(
    'line_type', 'invoice_application', 'opening_ar_line_id', :'opening_ar_id',
    'payment_amount', 250, 'cwt_amount', 0, 'forex_adjustment', 0
  ))
) AS receipt_id \gset

SELECT lives_ok(
  $$SELECT fn_post_receipt('$$ || :'receipt_id' || $$'::uuid)$$,
  'E3: the ordinary Receipt posting RPC settles an opening invoice');

SELECT fn_save_payment_voucher(
  NULL,
  jsonb_build_object(
    'company_id', :'company_id', 'branch_id', :'branch_id',
    'supplier_id', '66666666-0000-0000-0000-000000000179',
    'supplier_name_snapshot', 'Opening Settlement Supplier Inc',
    'supplier_tin_snapshot', '179-666-111-00000',
    'voucher_date', '2026-01-15',
    'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'CASH')
  ),
  jsonb_build_array(jsonb_build_object(
    'line_type', 'bill_application', 'opening_ap_line_id', :'opening_ap_id',
    'payment_amount', 150, 'ewt_amount', 0
  ))
) AS voucher_id \gset

SELECT lives_ok(
  $$SELECT fn_post_payment_voucher('$$ || :'voucher_id' || $$'::uuid)$$,
  'E4: the ordinary Payment Voucher posting RPC settles an opening bill');

SELECT is(
  (SELECT balance_due FROM fn_ar_aging_asof(:'company_id'::uuid, '2026-01-31',
    '55555555-0000-0000-0000-000000000179')),
  750.00::numeric, 'E5: AR aging reduces the opening invoice by the posted receipt');

SELECT is(
  (SELECT balance_due FROM fn_ap_aging_asof(:'company_id'::uuid, '2026-01-31',
    '66666666-0000-0000-0000-000000000179')),
  450.00::numeric, 'E6: AP aging reduces the opening bill by the posted voucher');

SELECT is(
  (SELECT round(sum(debit_amount - credit_amount), 2) FROM journal_entry_lines
   WHERE company_id = :'company_id'::uuid AND account_id = :'ar_account_id'::uuid),
  750.00::numeric, 'E7: opening AR and its collection reconcile to the GL control');

SELECT is(
  (SELECT round(sum(credit_amount - debit_amount), 2) FROM journal_entry_lines
   WHERE company_id = :'company_id'::uuid AND account_id = :'ap_account_id'::uuid),
  450.00::numeric, 'E8: opening AP and its payment reconcile to the GL control');

SELECT is(
  (SELECT count(*)::int FROM receipt_lines
   WHERE receipt_id = :'receipt_id'::uuid AND opening_ar_line_id = :'opening_ar_id'::uuid
     AND invoice_id IS NULL AND line_type = 'invoice_application'),
  1, 'E9: the receipt preserves an explicit opening-item relationship');

SELECT is(
  (SELECT count(*)::int FROM payment_voucher_lines
   WHERE payment_voucher_id = :'voucher_id'::uuid AND opening_ap_line_id = :'opening_ap_id'::uuid
     AND vendor_bill_id IS NULL AND line_type = 'bill_application'),
  1, 'E10: the voucher preserves an explicit opening-item relationship');

SELECT throws_ok(
  $$SELECT fn_save_receipt(
    NULL,
    jsonb_build_object(
      'company_id', '$$ || :'company_id' || $$', 'branch_id', '$$ || :'branch_id' || $$',
      'customer_id', '55555555-0000-0000-0000-000000000179',
      'customer_name_snapshot', 'Opening Settlement Customer Inc',
      'customer_tin_snapshot', '179-555-111-00000', 'receipt_date', '2026-01-20',
      'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'CASH')
    ),
    jsonb_build_array(jsonb_build_object(
      'line_type', 'invoice_application', 'opening_ar_line_id', '$$ || :'opening_ar_id' || $$',
      'payment_amount', 800, 'cwt_amount', 0
    )))$$,
  'P0001',
  'Receipt application exceeds opening invoice ' || :'opening_ar_id' || ' outstanding balance',
  'E11: save-time validation rejects opening-AR over-application');

SELECT throws_ok(
  $$SELECT fn_save_payment_voucher(
    NULL,
    jsonb_build_object(
      'company_id', '$$ || :'company_id' || $$', 'branch_id', '$$ || :'branch_id' || $$',
      'supplier_id', '66666666-0000-0000-0000-000000000179',
      'supplier_name_snapshot', 'Opening Settlement Supplier Inc',
      'supplier_tin_snapshot', '179-666-111-00000', 'voucher_date', '2026-01-20',
      'payment_mode_id', (SELECT id FROM ref_payment_modes WHERE code = 'CASH')
    ),
    jsonb_build_array(jsonb_build_object(
      'line_type', 'bill_application', 'opening_ap_line_id', '$$ || :'opening_ap_id' || $$',
      'payment_amount', 500, 'ewt_amount', 0
    )))$$,
  'P0001',
  'Payment application exceeds opening bill ' || :'opening_ap_id' || ' outstanding balance',
  'E12: save-time validation rejects opening-AP over-application');

SELECT throws_ok(
  $$SELECT fn_reverse_opening_balance('$$ || :'batch_id' || $$'::uuid, '2026-01-31',
    'Attempt after operations')$$,
  'P0001', 'Opening balances cannot be reversed after operational journals exist',
  'E13: posted settlements make the cut-over immutable');

SELECT is(
  (SELECT count(*)::int FROM inventory_events WHERE company_id = :'company_id'::uuid),
  0, 'E14: opening settlement leaves dormant IA-5 untouched');

SELECT * FROM finish();
ROLLBACK;
