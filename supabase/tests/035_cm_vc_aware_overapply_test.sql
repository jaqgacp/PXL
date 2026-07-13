-- ══════════════════════════════════════════════════════════════════════════════
-- CM-VC-OVERAPPLY-001 - Over-apply guards net applied credit memos / vendor credits
-- Finding coverage: PXL-AUD-039.
--
-- AR: an 11,200 SI with a 2,000 applied credit memo has a 9,200 collectible; a
-- receipt for 11,200 must be rejected and a receipt for 9,200 accepted.
-- AP mirror: an 11,200 VB with a 2,000 applied vendor credit has a 9,200
-- payable; a PV for 11,200 must be rejected and a PV for 9,200 accepted.
-- Previously both guards ignored the credit and permitted the full-original
-- payment, driving the subledger negative and inflating the CWT/EWT base.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111135',
        'authenticated', 'authenticated', 'harness-cmvc@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111135","role":"authenticated"}', true);

-- ── Company + setup (AR + AP) ───────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222235', 'corporation',
        'Overapply Guard Test Corp', 'Services', '111-222-333-035',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-cmvc@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333356',
        '22222222-2222-2222-2222-222222222235', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444468',
        '22222222-2222-2222-2222-222222222235',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222235',
       '44444444-4444-4444-4444-444444444468',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000351', '22222222-2222-2222-2222-222222222235',
   '1010', 'Cash in Bank',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000352', '22222222-2222-2222-2222-222222222235',
   '2010', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000353', '22222222-2222-2222-2222-222222222235',
   '2150', 'EWT Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000354', '22222222-2222-2222-2222-222222222235',
   '1300', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000355', '22222222-2222-2222-2222-222222222235',
   '5010', 'Professional Fees',   'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000356', '22222222-2222-2222-2222-222222222235',
   '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000357', '22222222-2222-2222-2222-222222222235',
   '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000358', '22222222-2222-2222-2222-222222222235',
   '1250', 'CWT Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000359', '22222222-2222-2222-2222-222222222235',
   '4010', 'Service Revenue',     'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id, ar_account_id,
        default_cash_account_id, ewt_payable_account_id, ewt_withheld_account_id,
        input_vat_account_id, vat_payable_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222235',
        'aaaaaaaa-0000-0000-0000-000000000352',
        'aaaaaaaa-0000-0000-0000-000000000356',
        'aaaaaaaa-0000-0000-0000-000000000351',
        'aaaaaaaa-0000-0000-0000-000000000353',
        'aaaaaaaa-0000-0000-0000-000000000358',
        'aaaaaaaa-0000-0000-0000-000000000354',
        'aaaaaaaa-0000-0000-0000-000000000357',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222235',
       '33333333-3333-3333-3333-333333333356',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'PV', 'SI', 'OR', 'CM', 'VC');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666691',
        '22222222-2222-2222-2222-222222222235', 'SUPP-035',
        'Overapply Supplier Corp', '777-888-999-035',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555535',
        '22222222-2222-2222-2222-222222222235', 'CUST-035',
        'Overapply Customer Inc', '444-555-666-035',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══ AR side: SI 11,200 with a 2,000 applied credit memo → 9,200 collectible ═════
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','22222222-2222-2222-2222-222222222235',
    'branch_id','33333333-3333-3333-3333-333333333356',
    'date','2026-01-15',
    'customer_id','55555555-5555-5555-5555-555555555535',
    'customer_name_snapshot','Overapply Customer Inc',
    'customer_tin_snapshot','444-555-666-035',
    'customer_address_snapshot','Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description','Consulting','quantity',1,'unit_price',10000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id','aaaaaaaa-0000-0000-0000-000000000359'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));

INSERT INTO t_ctx
SELECT 'cm', fn_save_credit_memo(NULL,
  jsonb_build_object(
    'company_id','22222222-2222-2222-2222-222222222235',
    'branch_id','33333333-3333-3333-3333-333333333356',
    'customer_id','55555555-5555-5555-5555-555555555535',
    'customer_name_snapshot','Overapply Customer Inc',
    'customer_tin_snapshot','444-555-666-035',
    'invoice_id',(SELECT id FROM t_ctx WHERE key='si'),
    'cm_date','2026-01-16',
    'reason_code_id',(SELECT id FROM ref_reason_codes WHERE code = 'CM_OTHER')
  ),
  jsonb_build_array(jsonb_build_object(
    'description','Billing adjustment','quantity',1,'unit_price',2000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id','aaaaaaaa-0000-0000-0000-000000000359'
  )),
  'applied');

SELECT is(
  (SELECT status FROM credit_memos WHERE id = (SELECT id FROM t_ctx WHERE key='cm')),
  'applied',
  'a 2,000 credit memo is applied against the 11,200 invoice');

SELECT throws_like(
  $$SELECT fn_save_receipt(NULL,
    jsonb_build_object(
      'company_id','22222222-2222-2222-2222-222222222235',
      'branch_id','33333333-3333-3333-3333-333333333356',
      'customer_id','55555555-5555-5555-5555-555555555535',
      'customer_name_snapshot','Overapply Customer Inc',
      'customer_tin_snapshot','444-555-666-035',
      'receipt_date','2026-01-20',
      'payment_mode_id',(SELECT id FROM ref_payment_modes LIMIT 1)),
    jsonb_build_array(jsonb_build_object(
      'invoice_id',(SELECT id FROM t_ctx WHERE key='si'),
      'payment_amount',11200,'cwt_amount',0)))$$,
  '%exceeds outstanding balance%',
  'a receipt for the full 11,200 is rejected — the 2,000 applied CM leaves only 9,200 collectible');

SELECT lives_ok(
  $$SELECT fn_save_receipt(NULL,
    jsonb_build_object(
      'company_id','22222222-2222-2222-2222-222222222235',
      'branch_id','33333333-3333-3333-3333-333333333356',
      'customer_id','55555555-5555-5555-5555-555555555535',
      'customer_name_snapshot','Overapply Customer Inc',
      'customer_tin_snapshot','444-555-666-035',
      'receipt_date','2026-01-20',
      'payment_mode_id',(SELECT id FROM ref_payment_modes LIMIT 1)),
    jsonb_build_array(jsonb_build_object(
      'invoice_id',(SELECT id FROM t_ctx WHERE key='si'),
      'payment_amount',9200,'cwt_amount',0)))$$,
  'a receipt for the net 9,200 collectible is accepted');

-- ══ AP side: VB 11,200 with a 2,000 applied vendor credit → 9,200 payable ═══════
INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','22222222-2222-2222-2222-222222222235',
    'branch_id','33333333-3333-3333-3333-333333333356',
    'supplier_id','66666666-6666-6666-6666-666666666691',
    'supplier_name_snapshot','Overapply Supplier Corp',
    'supplier_tin_snapshot','777-888-999-035',
    'supplier_invoice_number','SUP-INV-035',
    'bill_date','2026-01-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description','Contractor services','quantity',1,'unit_price',10000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id','aaaaaaaa-0000-0000-0000-000000000355'
  )));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));

INSERT INTO t_ctx
SELECT 'vc', fn_save_vendor_credit(NULL,
  jsonb_build_object(
    'company_id','22222222-2222-2222-2222-222222222235',
    'branch_id','33333333-3333-3333-3333-333333333356',
    'supplier_id','66666666-6666-6666-6666-666666666691',
    'supplier_name_snapshot','Overapply Supplier Corp',
    'supplier_tin_snapshot','777-888-999-035',
    'credit_date','2026-01-12'
  ),
  jsonb_build_array(jsonb_build_object(
    'description','Service credit','quantity',1,'unit_price',2000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
    'expense_account_id','aaaaaaaa-0000-0000-0000-000000000355'
  )));
SELECT fn_post_vendor_credit((SELECT id FROM t_ctx WHERE key='vc'));

SELECT lives_ok(
  format('SELECT fn_apply_vendor_credit(%L, %L, 2000, %L, %L)',
         (SELECT id FROM t_ctx WHERE key='vc'),
         (SELECT id FROM t_ctx WHERE key='vb'),
         '2026-01-15'::date, 'Applied per CM-VC-OVERAPPLY-001'),
  'a 2,000 vendor credit is applied against the 11,200 bill');

SELECT throws_like(
  $$SELECT fn_save_payment_voucher(NULL,
    jsonb_build_object(
      'company_id','22222222-2222-2222-2222-222222222235',
      'branch_id','33333333-3333-3333-3333-333333333356',
      'supplier_id','66666666-6666-6666-6666-666666666691',
      'supplier_name_snapshot','Overapply Supplier Corp',
      'supplier_tin_snapshot','777-888-999-035',
      'voucher_date','2026-01-20'),
    jsonb_build_array(jsonb_build_object(
      'vendor_bill_id',(SELECT id FROM t_ctx WHERE key='vb'),
      'payment_amount',11200)))$$,
  '%exceeds outstanding AP balance%',
  'a PV for the full 11,200 is rejected — the 2,000 applied VC leaves only 9,200 payable');

SELECT lives_ok(
  $$SELECT fn_save_payment_voucher(NULL,
    jsonb_build_object(
      'company_id','22222222-2222-2222-2222-222222222235',
      'branch_id','33333333-3333-3333-3333-333333333356',
      'supplier_id','66666666-6666-6666-6666-666666666691',
      'supplier_name_snapshot','Overapply Supplier Corp',
      'supplier_tin_snapshot','777-888-999-035',
      'voucher_date','2026-01-20'),
    jsonb_build_array(jsonb_build_object(
      'vendor_bill_id',(SELECT id FROM t_ctx WHERE key='vb'),
      'payment_amount',9200)))$$,
  'a PV for the net 9,200 payable is accepted');

SELECT * FROM finish();
ROLLBACK;
