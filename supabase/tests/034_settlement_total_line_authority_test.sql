-- ══════════════════════════════════════════════════════════════════════════════
-- SETTLEMENT-TOTAL-AUTHORITY-001 - PV/OR header cash + withholding totals are
-- derived from lines, and posting rejects any header/line divergence.
-- Finding coverage: PXL-AUD-038 (header/line divergence) / PXL-AUD-048 (tolerance
-- alignment — the GL now takes the line-sum withholding figure).
--
-- Scenario: a crafted client sends `fn_save_payment_voucher` / `fn_save_receipt`
-- a header cash total (and EWT/CWT total) that disagrees with the line sums. The
-- server must ignore the client header and store the line-derived totals, so the
-- posted JE (which reads the header) equals the subledger and tax ledger. A
-- draft whose header is tampered after save is rejected at posting.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111134',
        'authenticated', 'authenticated', 'harness-settle@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111134","role":"authenticated"}', true);

-- ── Company + setup (AP side + AR side) ─────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222234', 'corporation',
        'Settlement Total Test Corp', 'Services', '111-222-333-034',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-settle@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333345',
        '22222222-2222-2222-2222-222222222234', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444467',
        '22222222-2222-2222-2222-222222222234',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222234',
       '44444444-4444-4444-4444-444444444467',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000341', '22222222-2222-2222-2222-222222222234',
   '1010', 'Cash in Bank',        'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000342', '22222222-2222-2222-2222-222222222234',
   '2010', 'Accounts Payable',    'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000343', '22222222-2222-2222-2222-222222222234',
   '2150', 'EWT Payable',         'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000344', '22222222-2222-2222-2222-222222222234',
   '1300', 'Input VAT',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000345', '22222222-2222-2222-2222-222222222234',
   '5010', 'Professional Fees',   'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000346', '22222222-2222-2222-2222-222222222234',
   '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000347', '22222222-2222-2222-2222-222222222234',
   '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000348', '22222222-2222-2222-2222-222222222234',
   '1250', 'CWT Receivable',      'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000349', '22222222-2222-2222-2222-222222222234',
   '4010', 'Service Revenue',     'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id, ar_account_id,
        default_cash_account_id, ewt_payable_account_id, ewt_withheld_account_id,
        input_vat_account_id, vat_payable_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222234',
        'aaaaaaaa-0000-0000-0000-000000000342',
        'aaaaaaaa-0000-0000-0000-000000000346',
        'aaaaaaaa-0000-0000-0000-000000000341',
        'aaaaaaaa-0000-0000-0000-000000000343',
        'aaaaaaaa-0000-0000-0000-000000000348',
        'aaaaaaaa-0000-0000-0000-000000000344',
        'aaaaaaaa-0000-0000-0000-000000000347',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222234',
       '33333333-3333-3333-3333-333333333345',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'PV', 'SI', 'OR');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666690',
        '22222222-2222-2222-2222-222222222234', 'SUPP-034',
        'Settlement Supplier Corp', '777-888-999-034',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555534',
        '22222222-2222-2222-2222-222222222234', 'CUST-034',
        'Settlement Customer Inc', '444-555-666-034',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ── Posted VB: 10,000 net + 1,200 input VAT = 11,200 ───────────────────────────
INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222234',
    'branch_id',  '33333333-3333-3333-3333-333333333345',
    'supplier_id','66666666-6666-6666-6666-666666666690',
    'supplier_name_snapshot','Settlement Supplier Corp',
    'supplier_tin_snapshot','777-888-999-034',
    'supplier_invoice_number','SUP-INV-034',
    'bill_date','2026-01-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description','Contractor services','quantity',1,'unit_price',10000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id','aaaaaaaa-0000-0000-0000-000000000345'
  )));
SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));

-- ══ PV side (PXL-AUD-038 / 048) ═════════════════════════════════════════════════
-- Save with a BOGUS header total_amount (99,999) and total_ewt (88,888); the
-- single line pays 5,000 and withholds 100 (2% of the explicit 5,000 base).
INSERT INTO t_ctx
SELECT 'pv1', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id','22222222-2222-2222-2222-222222222234',
    'branch_id','33333333-3333-3333-3333-333333333345',
    'supplier_id','66666666-6666-6666-6666-666666666690',
    'supplier_name_snapshot','Settlement Supplier Corp',
    'supplier_tin_snapshot','777-888-999-034',
    'voucher_date','2026-02-05',
    'total_amount', 99999,
    'total_ewt', 88888
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',(SELECT id FROM t_ctx WHERE key='vb'),
    'payment_amount',5000,
    'ewt_amount',100,
    'atc_code_id',(SELECT id FROM atc_codes WHERE code = 'WC130'),
    'ewt_tax_base',5000
  )));

SELECT is(
  (SELECT total_amount FROM payment_vouchers WHERE id = (SELECT id FROM t_ctx WHERE key='pv1')),
  5000.00::numeric,
  'PV header total_amount is derived from the line payment sum, not the bogus 99,999 client value');

SELECT is(
  (SELECT total_ewt FROM payment_vouchers WHERE id = (SELECT id FROM t_ctx WHERE key='pv1')),
  100.00::numeric,
  'PV header total_ewt equals the line EWT sum exactly (no client 88,888, no 0.02 drift)');

SELECT lives_ok(
  format('SELECT fn_post_payment_voucher(%L)', (SELECT id FROM t_ctx WHERE key='pv1')),
  'the line-derived PV posts');

SELECT is(
  (SELECT jel.credit_amount
   FROM journal_entries je
   JOIN journal_entry_lines jel ON jel.je_id = je.id
   WHERE je.reference_doc_type = 'PV'
     AND je.reference_doc_id = (SELECT id FROM t_ctx WHERE key='pv1')
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000341'),
  5000.00::numeric,
  'the posted PV JE credits Cash by the line-sum 5,000, not the client header total');

-- Divergence rejection: tamper a saved draft PV header, then post.
INSERT INTO t_ctx
SELECT 'pv2', fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id','22222222-2222-2222-2222-222222222234',
    'branch_id','33333333-3333-3333-3333-333333333345',
    'supplier_id','66666666-6666-6666-6666-666666666690',
    'supplier_name_snapshot','Settlement Supplier Corp',
    'supplier_tin_snapshot','777-888-999-034',
    'voucher_date','2026-02-06'
  ),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',(SELECT id FROM t_ctx WHERE key='vb'),
    'payment_amount',3000
  )));
UPDATE payment_vouchers SET total_amount = 4000
WHERE id = (SELECT id FROM t_ctx WHERE key='pv2');

SELECT throws_like(
  format('SELECT fn_post_payment_voucher(%L)', (SELECT id FROM t_ctx WHERE key='pv2')),
  '%total amount%does not match line payment total%',
  'a PV whose header was tampered to diverge from its lines is rejected at posting');

-- ══ OR side (PXL-AUD-038) ═══════════════════════════════════════════════════════
-- Posted SI: 10,000 net + 1,200 output VAT = 11,200.
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','22222222-2222-2222-2222-222222222234',
    'branch_id','33333333-3333-3333-3333-333333333345',
    'date','2026-01-15',
    'customer_id','55555555-5555-5555-5555-555555555534',
    'customer_name_snapshot','Settlement Customer Inc',
    'customer_tin_snapshot','444-555-666-034',
    'customer_address_snapshot','Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description','Consulting services','quantity',1,'unit_price',10000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id','aaaaaaaa-0000-0000-0000-000000000349'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));

-- Save with a BOGUS header total_amount (77,777); the line collects 11,000 cash
-- and 200 CWT (2% of the explicit 10,000 base).
INSERT INTO t_ctx
SELECT 'or1', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id','22222222-2222-2222-2222-222222222234',
    'branch_id','33333333-3333-3333-3333-333333333345',
    'customer_id','55555555-5555-5555-5555-555555555534',
    'customer_name_snapshot','Settlement Customer Inc',
    'customer_tin_snapshot','444-555-666-034',
    'receipt_date','2026-01-20',
    'payment_mode_id',(SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount', 77777,
    'total_cwt', 55555
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',(SELECT id FROM t_ctx WHERE key='si'),
    'payment_amount',11000,
    'cwt_amount',200,
    'atc_code_id',(SELECT id FROM atc_codes WHERE code = 'WC140'),
    'cwt_tax_base',10000
  )));

SELECT is(
  (SELECT total_amount FROM receipts WHERE id = (SELECT id FROM t_ctx WHERE key='or1')),
  11000.00::numeric,
  'OR header total_amount is derived from the line payment sum, not the bogus 77,777 client value');

SELECT lives_ok(
  format('SELECT fn_post_receipt(%L)', (SELECT id FROM t_ctx WHERE key='or1')),
  'the line-derived OR posts');

SELECT is(
  (SELECT jel.debit_amount
   FROM journal_entries je
   JOIN journal_entry_lines jel ON jel.je_id = je.id
   WHERE je.reference_doc_type = 'OR'
     AND je.reference_doc_id = (SELECT id FROM t_ctx WHERE key='or1')
     AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000341'),
  11000.00::numeric,
  'the posted OR JE debits Cash by the line-sum 11,000, not the client header total');

SELECT * FROM finish();
ROLLBACK;
