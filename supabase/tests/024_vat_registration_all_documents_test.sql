-- ══════════════════════════════════════════════════════════════════════════════
-- VAT-REG-ALL-DOCS-001 - VAT registration, direction, ledger, and export gates
--
-- Completes PXL-AUD-006 across CM/DM/cash sale/cash purchase/vendor credit and
-- advances the separate PXL-AUD-014 / PXL-DA-008 VAT-ledger work.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(35);

-- ── Identity and companies ────────────────────────────────────────────────────

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111124',
        'authenticated', 'authenticated', 'vat-all-docs@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111124","role":"authenticated"}', true);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
)
VALUES
  ('22222222-2222-2222-2222-222222222274', 'corporation',
   'All Docs Non-VAT Corp', 'Services', '111-222-333-074',
   'non_vat', 'calendar', '1 Test St', '', 'Makati', 'Metro Manila', '1200',
   'nonvat@test.local', 'Nora Nonvat', 'President', auth.uid(), auth.uid()),
  ('22222222-2222-2222-2222-222222222275', 'corporation',
   'All Docs Exempt Corp', 'Services', '111-222-333-075',
   'exempt', 'calendar', '2 Test St', '', 'Makati', 'Metro Manila', '1200',
   'exempt@test.local', 'Erin Exempt', 'President', auth.uid(), auth.uid()),
  ('22222222-2222-2222-2222-222222222276', 'corporation',
   'All Docs VAT Corp', 'Services', '111-222-333-076',
   'vat', 'calendar', '3 Test St', '', 'Makati', 'Metro Manila', '1200',
   'vat@test.local', 'Victor Vat', 'President', auth.uid(), auth.uid());

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
)
VALUES
  ('33333333-3333-3333-3333-333333333374', '22222222-2222-2222-2222-222222222274',
   'HO', 'Head Office', '1 Test St', '', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid()),
  ('33333333-3333-3333-3333-333333333375', '22222222-2222-2222-2222-222222222275',
   'HO', 'Head Office', '2 Test St', '', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid()),
  ('33333333-3333-3333-3333-333333333376', '22222222-2222-2222-2222-222222222276',
   'HO', 'Head Office', '3 Test St', '', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address, created_by, updated_by
)
VALUES
  ('55555555-5555-5555-5555-555555555574', '22222222-2222-2222-2222-222222222274',
   'C-NV', 'Non-VAT Customer', '444-555-666-074', 'Makati', 'Makati', auth.uid(), auth.uid()),
  ('55555555-5555-5555-5555-555555555576', '22222222-2222-2222-2222-222222222276',
   'C-VAT', 'VAT Customer', '444-555-666-076', 'Makati', 'Makati', auth.uid(), auth.uid());

INSERT INTO suppliers (
  id, company_id, supplier_code, registered_name, tin,
  registered_address, created_by, updated_by
)
VALUES
  ('66666666-6666-6666-6666-666666666674', '22222222-2222-2222-2222-222222222274',
   'S-NV', 'Non-VAT Supplier', '777-888-999-074', 'Pasig', auth.uid(), auth.uid()),
  ('66666666-6666-6666-6666-666666666676', '22222222-2222-2222-2222-222222222276',
   'S-VAT', 'VAT Supplier', '777-888-999-076', 'Pasig', auth.uid(), auth.uid());

-- VAT-company posting setup used by the CM/DM/VC ledger assertions.
INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444476',
        '22222222-2222-2222-2222-222222222276',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
VALUES ('44444444-4444-4444-4444-444444444477',
        '22222222-2222-2222-2222-222222222276',
        '44444444-4444-4444-4444-444444444476', 1, 'Jan 2026',
        '2026-01-01', '2026-01-31', false);

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name, account_type,
  normal_balance, is_postable, is_active, created_by, updated_by
)
VALUES
  ('aaaaaaaa-0000-0000-0000-0000000000c1', '22222222-2222-2222-2222-222222222276', '1010', 'Cash', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c2', '22222222-2222-2222-2222-222222222276', '1200', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c3', '22222222-2222-2222-2222-222222222276', '2010', 'Accounts Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c4', '22222222-2222-2222-2222-222222222276', '4010', 'Sales', 'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c5', '22222222-2222-2222-2222-222222222276', '5010', 'Expense', 'expense', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c6', '22222222-2222-2222-2222-222222222276', '2020', 'Output VAT', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-0000000000c7', '22222222-2222-2222-2222-222222222276', '1210', 'Input VAT', 'asset', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, ap_account_id, default_cash_account_id,
  vat_payable_account_id, input_vat_account_id,
  created_by, updated_by
)
VALUES ('22222222-2222-2222-2222-222222222276',
        'aaaaaaaa-0000-0000-0000-0000000000c2',
        'aaaaaaaa-0000-0000-0000-0000000000c3',
        'aaaaaaaa-0000-0000-0000-0000000000c1',
        'aaaaaaaa-0000-0000-0000-0000000000c6',
        'aaaaaaaa-0000-0000-0000-0000000000c7',
        auth.uid(), auth.uid());

-- ── Parent documents ──────────────────────────────────────────────────────────

INSERT INTO sales_invoices (
  id, company_id, branch_id, customer_id, customer_name_snapshot,
  customer_tin_snapshot, si_number, date, is_cash_sale, status,
  created_by, updated_by
)
VALUES
  ('71000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222274',
   '33333333-3333-3333-3333-333333333374', '55555555-5555-5555-5555-555555555574',
   'Non-VAT Customer', '444-555-666-074', 'CS-NV-1', '2026-01-10', true, 'draft', auth.uid(), auth.uid()),
  ('71000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   '33333333-3333-3333-3333-333333333376', '55555555-5555-5555-5555-555555555576',
   'VAT Customer', '444-555-666-076', 'CS-VAT-1', '2026-01-10', true, 'draft', auth.uid(), auth.uid());

INSERT INTO credit_memos (
  id, company_id, branch_id, customer_id, customer_name_snapshot,
  customer_tin_snapshot, cm_number, cm_date, reason_code_id,
  total_net_amount, total_vat_amount, total_amount,
  total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
  status, created_by, updated_by
)
VALUES
  ('72000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222274',
   '33333333-3333-3333-3333-333333333374', '55555555-5555-5555-5555-555555555574',
   'Non-VAT Customer', '444-555-666-074', 'CM-NV-1', '2026-01-11',
   (SELECT id FROM ref_reason_codes WHERE applies_to IN ('credit_memo','both') ORDER BY id LIMIT 1),
   0, 0, 0, 0, 0, 0, 'draft', auth.uid(), auth.uid()),
  ('72000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   '33333333-3333-3333-3333-333333333376', '55555555-5555-5555-5555-555555555576',
   'VAT Customer', '444-555-666-076', 'CM-VAT-1', '2026-01-11',
   (SELECT id FROM ref_reason_codes WHERE applies_to IN ('credit_memo','both') ORDER BY id LIMIT 1),
   1500, 120, 1620, 1000, 500, 0, 'draft', auth.uid(), auth.uid());

INSERT INTO debit_memos (
  id, company_id, branch_id, customer_id, customer_name_snapshot,
  customer_tin_snapshot, dm_number, dm_date, reason_code_id,
  total_net_amount, total_vat_amount, total_amount,
  total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
  status, created_by, updated_by
)
VALUES
  ('73000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222274',
   '33333333-3333-3333-3333-333333333374', '55555555-5555-5555-5555-555555555574',
   'Non-VAT Customer', '444-555-666-074', 'DM-NV-1', '2026-01-12',
   (SELECT id FROM ref_reason_codes WHERE applies_to IN ('debit_memo','both') ORDER BY id LIMIT 1),
   0, 0, 0, 0, 0, 0, 'draft', auth.uid(), auth.uid()),
  ('73000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   '33333333-3333-3333-3333-333333333376', '55555555-5555-5555-5555-555555555576',
   'VAT Customer', '444-555-666-076', 'DM-VAT-1', '2026-01-12',
   (SELECT id FROM ref_reason_codes WHERE applies_to IN ('debit_memo','both') ORDER BY id LIMIT 1),
   1500, 120, 1620, 1000, 500, 0, 'draft', auth.uid(), auth.uid());

INSERT INTO cash_purchases (
  id, company_id, branch_id, cp_number, transaction_date,
  total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
  total_input_vat_amount, total_amount, status, created_by, updated_by
)
VALUES
  ('74000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222274',
   '33333333-3333-3333-3333-333333333374', 'CP-NV-1', '2026-01-13', 0, 0, 0, 0, 0, 'draft', auth.uid(), auth.uid()),
  ('74000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222275',
   '33333333-3333-3333-3333-333333333375', 'CP-EX-1', '2026-01-13', 0, 0, 0, 0, 0, 'draft', auth.uid(), auth.uid()),
  ('74000000-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222276',
   '33333333-3333-3333-3333-333333333376', 'CP-VAT-1', '2026-01-13', 0, 0, 0, 0, 0, 'draft', auth.uid(), auth.uid());

INSERT INTO vendor_credits (
  id, company_id, branch_id, vc_number, credit_date, supplier_id,
  supplier_name_snapshot, supplier_tin_snapshot,
  total_taxable_amount, total_input_vat_amount, total_amount,
  remaining_balance, status, created_by, updated_by
)
VALUES
  ('75000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222274',
   '33333333-3333-3333-3333-333333333374', 'VC-NV-1', '2026-01-14',
   '66666666-6666-6666-6666-666666666674', 'Non-VAT Supplier', '777-888-999-074',
   0, 0, 0, 0, 'draft', auth.uid(), auth.uid()),
  ('75000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   '33333333-3333-3333-3333-333333333376', 'VC-VAT-1', '2026-01-14',
   '66666666-6666-6666-6666-666666666676', 'VAT Supplier', '777-888-999-076',
   1000, 120, 1620, 1620, 'draft', auth.uid(), auth.uid());

-- 1. Six line and six header trigger pairs are installed.
SELECT is(
  (SELECT count(*)::int
   FROM pg_trigger
   WHERE NOT tgisinternal
     AND tgname IN (
       'trg_si_line_vat_registration', 'trg_vb_line_vat_registration',
       'trg_cm_line_vat_registration', 'trg_dm_line_vat_registration',
       'trg_cp_line_vat_registration', 'trg_vc_line_vat_registration',
       'trg_si_vat_registration_status', 'trg_vb_vat_registration_status',
       'trg_cm_vat_registration_status', 'trg_dm_vat_registration_status',
       'trg_cp_vat_registration_status', 'trg_vc_vat_registration_status'
     )),
  12,
  'all VAT-bearing line/header trigger pairs are installed');

-- ── Non-VAT / exempt and direction negatives ─────────────────────────────────

SELECT throws_like(
  $q$INSERT INTO credit_memo_lines
      (credit_memo_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('72000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'VAT CM', 1, 1000, 1000,
              (SELECT id FROM vat_codes WHERE vat_code='VAT-12'), 120, 1120)$q$,
  '%Non-VAT or exempt companies cannot use VAT-bearing code%',
  'non-VAT credit memo rejects a VAT-bearing output code');

SELECT throws_like(
  $q$INSERT INTO debit_memo_lines
      (debit_memo_id, company_id, line_number, description, amount,
       vat_code_id, vat_amount, total_amount)
      VALUES ('73000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'VAT DM', 1000,
              (SELECT id FROM vat_codes WHERE vat_code='VAT-12'), 120, 1120)$q$,
  '%Non-VAT or exempt companies cannot use VAT-bearing code%',
  'non-VAT debit memo rejects a VAT-bearing output code');

SELECT throws_like(
  $q$INSERT INTO sales_invoice_lines
      (sales_invoice_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('71000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'VAT cash sale', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='VAT-12'), 120, 1120)$q$,
  '%Non-VAT or exempt companies cannot use VAT-bearing code%',
  'non-VAT cash sale rejects a VAT-bearing output code');

SELECT throws_like(
  $q$INSERT INTO cash_purchase_lines
      (cp_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, input_vat_amount, total_amount)
      VALUES ('74000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'VAT CP', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='IVAT-12'), 120, 1120)$q$,
  '%Non-VAT or exempt companies cannot use VAT-bearing code%',
  'non-VAT cash purchase rejects a VAT-bearing input code');

SELECT throws_like(
  $q$INSERT INTO vendor_credit_lines
      (vc_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, input_vat_amount, total_amount)
      VALUES ('75000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'VAT VC', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='IVAT-12'), 120, 1120)$q$,
  '%Non-VAT or exempt companies cannot use VAT-bearing code%',
  'non-VAT vendor credit rejects a VAT-bearing input code');

SELECT throws_like(
  $q$INSERT INTO cash_purchase_lines
      (cp_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, input_vat_amount, total_amount)
      VALUES ('74000000-0000-0000-0000-000000000002',
              '22222222-2222-2222-2222-222222222275', 1, 'VAT exempt CP', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='IVAT-12'), 120, 1120)$q$,
  '%Non-VAT or exempt companies cannot use VAT-bearing code%',
  'exempt-company cash purchase rejects a VAT-bearing input code');

SELECT throws_like(
  $q$INSERT INTO credit_memo_lines
      (credit_memo_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('72000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222276', 1, 'Cross-company bypass', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='VAT-12'), 120, 1120)$q$,
  '%line company does not match its document company%',
  'line company cannot bypass the parent company registration');

SELECT throws_like(
  $q$INSERT INTO credit_memo_lines
      (credit_memo_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('72000000-0000-0000-0000-000000000002',
              '22222222-2222-2222-2222-222222222276', 99, 'Wrong direction', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='IVAT-12'), 120, 1120)$q$,
  '%is for input_vat, not output_vat%',
  'output document rejects an input VAT code');

SELECT throws_like(
  $q$INSERT INTO cash_purchase_lines
      (cp_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, input_vat_amount, total_amount)
      VALUES ('74000000-0000-0000-0000-000000000003',
              '22222222-2222-2222-2222-222222222276', 99, 'Wrong direction', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='VAT-12'), 120, 1120)$q$,
  '%is for output_vat, not input_vat%',
  'input document rejects an output VAT code');

SELECT throws_like(
  $q$INSERT INTO credit_memo_lines
      (credit_memo_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('72000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 2, 'Forged amount', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='VAT-EXEMPT'), 120, 1120)$q$,
  '%cannot record a non-zero Credit memo line VAT amount%',
  'zero-rate code cannot carry a forged non-VAT line amount');

SELECT throws_like(
  $$UPDATE credit_memos SET total_vat_amount=120
    WHERE id='72000000-0000-0000-0000-000000000001'$$,
  '%cannot record a non-zero Credit memo header VAT amount%',
  'non-VAT output header rejects a direct VAT total');

SELECT throws_like(
  $$UPDATE vendor_credits SET total_input_vat_amount=120
    WHERE id='75000000-0000-0000-0000-000000000001'$$,
  '%cannot record a non-zero Vendor credit header VAT amount%',
  'non-VAT input header rejects a direct VAT total');

-- ── Zero-rate documents remain usable ─────────────────────────────────────────

SELECT lives_ok(
  $q$INSERT INTO credit_memo_lines
      (credit_memo_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('72000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'Exempt CM', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='VAT-EXEMPT'), 0, 1000)$q$,
  'non-VAT credit memo accepts an exempt output code');

SELECT lives_ok(
  $q$INSERT INTO debit_memo_lines
      (debit_memo_id, company_id, line_number, description, amount,
       vat_code_id, vat_amount, total_amount)
      VALUES ('73000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'Exempt DM', 1000,
              (SELECT id FROM vat_codes WHERE vat_code='VAT-EXEMPT'), 0, 1000)$q$,
  'non-VAT debit memo accepts an exempt output code');

SELECT lives_ok(
  $q$INSERT INTO sales_invoice_lines
      (sales_invoice_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('71000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'Exempt cash sale', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='VAT-EXEMPT'), 0, 1000)$q$,
  'non-VAT cash sale accepts an exempt output code');

SELECT lives_ok(
  $q$INSERT INTO cash_purchase_lines
      (cp_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, input_vat_amount, total_amount)
      VALUES ('74000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'Exempt CP', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='IVAT-EXEMPT'), 0, 1000)$q$,
  'non-VAT cash purchase accepts an exempt input code');

SELECT lives_ok(
  $q$INSERT INTO vendor_credit_lines
      (vc_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, input_vat_amount, total_amount)
      VALUES ('75000000-0000-0000-0000-000000000001',
              '22222222-2222-2222-2222-222222222274', 1, 'Exempt VC', 1, 1000,
              1000, (SELECT id FROM vat_codes WHERE vat_code='IVAT-EXEMPT'), 0, 1000)$q$,
  'non-VAT vendor credit accepts an exempt input code');

-- ── VAT-company posting and per-code tax ledger ───────────────────────────────

INSERT INTO credit_memo_lines (
  credit_memo_id, company_id, line_number, description, quantity, unit_price,
  net_amount, vat_code_id, vat_amount, total_amount, revenue_account_id
)
VALUES
  ('72000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   1, 'Regular CM', 1, 1000, 1000, (SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
   120, 1120, 'aaaaaaaa-0000-0000-0000-0000000000c4'),
  ('72000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   2, 'Zero CM', 1, 500, 500, (SELECT id FROM vat_codes WHERE vat_code='VAT-0-EXPORT'),
   0, 500, 'aaaaaaaa-0000-0000-0000-0000000000c4');

INSERT INTO debit_memo_lines (
  debit_memo_id, company_id, line_number, description, amount,
  vat_code_id, vat_amount, total_amount, account_id
)
VALUES
  ('73000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   1, 'Regular DM', 1000, (SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
   120, 1120, 'aaaaaaaa-0000-0000-0000-0000000000c4'),
  ('73000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   2, 'Zero DM', 500, (SELECT id FROM vat_codes WHERE vat_code='VAT-0-EXPORT'),
   0, 500, 'aaaaaaaa-0000-0000-0000-0000000000c4');

INSERT INTO vendor_credit_lines (
  vc_id, company_id, line_number, description, quantity, unit_price,
  net_amount, vat_code_id, input_vat_amount, total_amount, expense_account_id
)
VALUES
  ('75000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   1, 'Regular VC', 1, 1000, 1000, (SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
   120, 1120, 'aaaaaaaa-0000-0000-0000-0000000000c5'),
  ('75000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222276',
   2, 'Zero VC', 1, 500, 500, (SELECT id FROM vat_codes WHERE vat_code='IVAT-0'),
   0, 500, 'aaaaaaaa-0000-0000-0000-0000000000c5');

SELECT lives_ok(
  $$SELECT fn_post_credit_memo('72000000-0000-0000-0000-000000000002')$$,
  'VAT credit memo posts through the stable public RPC');
SELECT lives_ok(
  $$SELECT fn_post_debit_memo('73000000-0000-0000-0000-000000000002')$$,
  'VAT debit memo posts through the stable public RPC');
SELECT lives_ok(
  $$SELECT fn_post_vendor_credit('75000000-0000-0000-0000-000000000002')$$,
  'VAT vendor credit posts through the stable public RPC');

SELECT results_eq(
  $q$SELECT vc.vat_code, t.tax_base, t.tax_amount, t.is_reversal
     FROM tax_detail_entries t
     JOIN vat_codes vc ON vc.id=t.vat_code_id
     WHERE t.source_doc_type='CM'
       AND t.source_doc_id='72000000-0000-0000-0000-000000000002'
     ORDER BY vc.vat_code$q$,
  $$VALUES ('VAT-0-EXPORT'::text, -500.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('VAT-12'::text, -1000.00::numeric(15,2), -120.00::numeric(15,2), true)$$,
  'credit memo writes negative output VAT rows per VAT code');

SELECT results_eq(
  $q$SELECT vc.vat_code, t.tax_base, t.tax_amount, t.is_reversal
     FROM tax_detail_entries t
     JOIN vat_codes vc ON vc.id=t.vat_code_id
     WHERE t.source_doc_type='DM'
       AND t.source_doc_id='73000000-0000-0000-0000-000000000002'
     ORDER BY vc.vat_code$q$,
  $$VALUES ('VAT-0-EXPORT'::text, 500.00::numeric(15,2), 0.00::numeric(15,2), false),
           ('VAT-12'::text, 1000.00::numeric(15,2), 120.00::numeric(15,2), false)$$,
  'debit memo writes positive output VAT rows per VAT code');

SELECT results_eq(
  $q$SELECT vc.vat_code, t.tax_base, t.tax_amount, t.is_reversal
     FROM tax_detail_entries t
     JOIN vat_codes vc ON vc.id=t.vat_code_id
     WHERE t.source_doc_type='VC'
       AND t.source_doc_id='75000000-0000-0000-0000-000000000002'
     ORDER BY vc.vat_code$q$,
  $$VALUES ('IVAT-0'::text, -500.00::numeric(15,2), 0.00::numeric(15,2), true),
           ('IVAT-12'::text, -1000.00::numeric(15,2), -120.00::numeric(15,2), true)$$,
  'vendor credit writes negative input VAT rows per VAT code');

SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE source_doc_type IN ('CM','DM','VC') AND vat_code_id IS NULL),
  0,
  'new CM/DM/VC postings leave no legacy lump VAT rows');

-- ── Direct tax-ledger writes are denied by effect ─────────────────────────────

SET LOCAL ROLE authenticated;

SELECT throws_like(
  $q$INSERT INTO tax_detail_entries
      (company_id, source_doc_type, source_doc_id, tax_kind,
       tax_base, tax_amount, posting_date, document_date)
      VALUES ('22222222-2222-2222-2222-222222222276', 'FORGED', gen_random_uuid(),
              'output_vat', 1000, 120, CURRENT_DATE, CURRENT_DATE)$q$,
  '%new row violates row-level security policy%',
  'authenticated client cannot insert tax-detail evidence directly');

SELECT lives_ok(
  $$UPDATE tax_detail_entries SET tax_amount=999
    WHERE source_doc_type='CM'
      AND source_doc_id='72000000-0000-0000-0000-000000000002'$$,
  'authenticated direct tax-detail update is silently denied by RLS');

SELECT is(
  (SELECT tax_amount FROM tax_detail_entries
   WHERE source_doc_type='CM'
     AND source_doc_id='72000000-0000-0000-0000-000000000002'
     AND vat_code_id=(SELECT id FROM vat_codes WHERE vat_code='VAT-12')),
  -120.00::numeric,
  'denied direct update leaves the stored tax amount unchanged');

SELECT lives_ok(
  $$DELETE FROM tax_detail_entries
    WHERE source_doc_type='CM'
      AND source_doc_id='72000000-0000-0000-0000-000000000002'$$,
  'authenticated direct tax-detail delete is silently denied by RLS');

SELECT is(
  (SELECT count(*)::int FROM tax_detail_entries
   WHERE source_doc_type='CM'
     AND source_doc_id='72000000-0000-0000-0000-000000000002'),
  2,
  'tax-detail evidence remains unchanged after denied mutations');

-- ── VAT export gates preserve non-VAT CAS books ───────────────────────────────

SELECT throws_like(
  $$SELECT fn_snapshot_vat_export('22222222-2222-2222-2222-222222222274', 'SLSP', 2026, 1, 'all')$$,
  '%requires a VAT-registered company%',
  'non-VAT company cannot create an SLSP export snapshot');

SELECT throws_like(
  $$SELECT fn_snapshot_cas_export('22222222-2222-2222-2222-222222222274', 'slsp', 2026, 1, 'slsp.dat')$$,
  '%requires a VAT-registered company%',
  'non-VAT company cannot create a CAS SLSP export');

SELECT throws_like(
  $$SELECT fn_snapshot_cas_export('22222222-2222-2222-2222-222222222275', 'relief', 2026, 1, 'relief.dat')$$,
  '%requires a VAT-registered company%',
  'exempt company cannot create a CAS RELIEF export');

SELECT lives_ok(
  $$SELECT fn_snapshot_vat_export('22222222-2222-2222-2222-222222222276', 'SLSP', 2026, 1, 'all')$$,
  'VAT company retains the existing VAT export path');

SELECT lives_ok(
  $$SELECT fn_snapshot_cas_export('22222222-2222-2222-2222-222222222274', 'general_ledger', 2026, 1, 'gl.dat')$$,
  'non-VAT company retains non-VAT CAS general-ledger export');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
