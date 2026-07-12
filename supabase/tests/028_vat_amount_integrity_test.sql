-- VAT-AMOUNT-INTEGRITY-001 - server-authoritative operational VAT amounts
--
-- Proves that every VAT-bearing document family ignores client-supplied
-- derived amounts, uses the VAT master rate in its SECURITY DEFINER save RPC,
-- and cannot be mutated around those RPCs by an authenticated application
-- caller. The posted SI/VB fixtures also reconcile document -> tax ledger ->
-- GL control account -> ledger-backed VAT review.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(25);

-- ── Identity and accounting-ready VAT company ────────────────────────────────

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
)
VALUES
  (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111128',
    'authenticated', 'authenticated', 'vat-integrity@test.local', '',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}', '{}'
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111129',
    'authenticated', 'authenticated', 'vat-integrity-outsider@test.local', '',
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}', '{}'
  );

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111128","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
)
VALUES (
  '22222222-2222-2222-2222-222222222278', 'corporation',
  'VAT Integrity Test Corp', 'Professional Services', '111-222-333-078',
  'vat', 'calendar',
  '28 Test Street', '', 'Makati', 'Metro Manila', '1200',
  'vat-integrity@test.local', 'Victor Integrity', 'President',
  auth.uid(), auth.uid()
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
)
VALUES (
  '33333333-3333-3333-3333-333333333378',
  '22222222-2222-2222-2222-222222222278',
  'HO', 'Head Office', '28 Test Street', '', 'Makati', 'Metro Manila', '1200',
  auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (
  id, company_id, year_name, start_date, end_date, is_calendar
)
VALUES (
  '44444444-4444-4444-4444-444444444478',
  '22222222-2222-2222-2222-222222222278',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
VALUES (
  '44444444-4444-4444-4444-444444444479',
  '22222222-2222-2222-2222-222222222278',
  '44444444-4444-4444-4444-444444444478',
  1, 'Jan 2026', '2026-01-01', '2026-01-31', false
);

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name, account_type,
  normal_balance, is_postable, is_active, created_by, updated_by
)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000281', '22222222-2222-2222-2222-222222222278', '1010', 'Cash', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000282', '22222222-2222-2222-2222-222222222278', '1200', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000283', '22222222-2222-2222-2222-222222222278', '1300', 'Input VAT', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000284', '22222222-2222-2222-2222-222222222278', '2010', 'Accounts Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000285', '22222222-2222-2222-2222-222222222278', '2100', 'Output VAT', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000286', '22222222-2222-2222-2222-222222222278', '4010', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000287', '22222222-2222-2222-2222-222222222278', '5010', 'Professional Fees', 'expense', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, ap_account_id, default_cash_account_id,
  vat_payable_account_id, input_vat_account_id,
  created_by, updated_by
)
VALUES (
  '22222222-2222-2222-2222-222222222278',
  'aaaaaaaa-0000-0000-0000-000000000282',
  'aaaaaaaa-0000-0000-0000-000000000284',
  'aaaaaaaa-0000-0000-0000-000000000281',
  'aaaaaaaa-0000-0000-0000-000000000285',
  'aaaaaaaa-0000-0000-0000-000000000283',
  auth.uid(), auth.uid()
);

INSERT INTO number_series (
  company_id, branch_id, document_type_id, prefix,
  number_length, starting_number, next_number,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222278',
  '33333333-3333-3333-3333-333333333378',
  rdt.id, 'VAT-' || rdt.document_code || '-',
  6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'VB', 'CM', 'DM-S', 'CP', 'VC');

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address, created_by, updated_by
)
VALUES (
  '55555555-5555-5555-5555-555555555578',
  '22222222-2222-2222-2222-222222222278',
  'C-VAT-028', 'VAT Integrity Customer', '444-555-666-078',
  'Taguig', 'Taguig', auth.uid(), auth.uid()
);

INSERT INTO suppliers (
  id, company_id, supplier_code, registered_name, tin,
  registered_address, created_by, updated_by
)
VALUES (
  '66666666-6666-6666-6666-666666666678',
  '22222222-2222-2222-2222-222222222278',
  'S-VAT-028', 'VAT Integrity Supplier', '777-888-999-078',
  'Pasig', auth.uid(), auth.uid()
);

CREATE TEMP TABLE t_vat_ctx (key TEXT PRIMARY KEY, id UUID NOT NULL);
GRANT SELECT ON TABLE t_vat_ctx TO authenticated;

-- 1-2. The table mutation surface is absent; SELECT policies/grants remain.
SELECT is(
  (
    SELECT count(*)::int
    FROM information_schema.role_table_grants
    WHERE grantee IN ('PUBLIC', 'anon', 'authenticated')
      AND table_schema = 'public'
      AND table_name = ANY (ARRAY[
        'sales_invoices', 'sales_invoice_lines',
        'vendor_bills', 'vendor_bill_lines',
        'credit_memos', 'credit_memo_lines',
        'debit_memos', 'debit_memo_lines',
        'cash_purchases', 'cash_purchase_lines',
        'vendor_credits', 'vendor_credit_lines',
        'vw_sales_invoice_register', 'vw_vendor_bill_register'
      ])
      AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
  ),
  0,
  'application roles have no direct mutation grants on VAT source tables'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'sales_invoices', 'sales_invoice_lines',
        'vendor_bills', 'vendor_bill_lines',
        'credit_memos', 'credit_memo_lines',
        'debit_memos', 'debit_memo_lines',
        'cash_purchases', 'cash_purchase_lines',
        'vendor_credits', 'vendor_credit_lines'
      ])
      AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
  ),
  0,
  'VAT source tables expose no dormant application write policies'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM pg_class
    WHERE oid IN (
      'public.vw_sales_invoice_register'::regclass,
      'public.vw_vendor_bill_register'::regclass
    )
      AND reloptions @> ARRAY['security_invoker=true']
  ),
  2,
  'updatable VAT register views execute with the caller RLS posture'
);

-- ── Sales invoice: mixed classifications and forged payload fields ───────────

INSERT INTO t_vat_ctx
SELECT 'si', fn_save_sales_invoice(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222278',
    'branch_id', '33333333-3333-3333-3333-333333333378',
    'date', '2026-01-15',
    'customer_id', '55555555-5555-5555-5555-555555555578',
    'customer_name_snapshot', 'VAT Integrity Customer',
    'customer_tin_snapshot', '444-555-666-078',
    'customer_address_snapshot', 'Taguig',
    'total_taxable_amount', 999999,
    'total_vat_amount', 999999,
    'total_amount', 999999
  ),
  jsonb_build_array(
    jsonb_build_object(
      'description', 'Regular service', 'quantity', 2, 'unit_price', 1000,
      'discount_amount', 200, 'net_amount', 1, 'vat_amount', 999,
      'total_amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000286'
    ),
    jsonb_build_object(
      'description', 'Zero-rated service', 'quantity', 1, 'unit_price', 500,
      'net_amount', 1, 'vat_amount', 999, 'total_amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-0-EXPORT'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000286'
    ),
    jsonb_build_object(
      'description', 'Exempt service', 'quantity', 1, 'unit_price', 250,
      'net_amount', 1, 'vat_amount', 999, 'total_amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000286'
    )
  )
);

SELECT results_eq(
  $q$SELECT line_number, net_amount, vat_amount, total_amount
     FROM sales_invoice_lines
     WHERE sales_invoice_id = (SELECT id FROM t_vat_ctx WHERE key = 'si')
     ORDER BY line_number$q$,
  $$VALUES
      (1, 1800.00::numeric, 216.00::numeric, 2016.00::numeric),
      (2,  500.00::numeric,   0.00::numeric,  500.00::numeric),
      (3,  250.00::numeric,   0.00::numeric,  250.00::numeric)$$,
  'SI save ignores forged derived fields and uses the VAT master rate'
);

SELECT results_eq(
  $q$SELECT total_taxable_amount, total_zero_rated_amount,
            total_exempt_amount, total_vat_amount, total_amount
     FROM sales_invoices
     WHERE id = (SELECT id FROM t_vat_ctx WHERE key = 'si')$q$,
  $$VALUES (1800.00::numeric, 500.00::numeric, 250.00::numeric,
            216.00::numeric, 2766.00::numeric)$$,
  'SI header classifications and totals are rebuilt from server-computed lines'
);

SELECT lives_ok(
  format(
    'SELECT fn_approve_sales_invoice(%L); SELECT fn_post_sales_invoice(%L)',
    (SELECT id FROM t_vat_ctx WHERE key = 'si'),
    (SELECT id FROM t_vat_ctx WHERE key = 'si')
  ),
  'mixed-classification SI approves and posts through the governed RPCs'
);

SELECT results_eq(
  $q$SELECT vc.vat_code, t.tax_base, t.tax_amount
     FROM tax_detail_entries t
     JOIN vat_codes vc ON vc.id = t.vat_code_id
     WHERE t.source_doc_type = 'SI'
       AND t.source_doc_id = (SELECT id FROM t_vat_ctx WHERE key = 'si')
     ORDER BY vc.vat_code$q$,
  $$VALUES
      ('VAT-0-EXPORT'::text, 500.00::numeric,   0.00::numeric),
      ('VAT-12'::text,       1800.00::numeric, 216.00::numeric),
      ('VAT-EXEMPT'::text,    250.00::numeric,   0.00::numeric)$$,
  'SI tax ledger preserves regular, zero-rated, and exempt bases per code'
);

SELECT is(
  (
    SELECT COALESCE(sum(credit_amount - debit_amount), 0)
    FROM journal_entry_lines
    WHERE je_id = (
      SELECT journal_entry_id FROM sales_invoices
      WHERE id = (SELECT id FROM t_vat_ctx WHERE key = 'si')
    )
      AND account_id = 'aaaaaaaa-0000-0000-0000-000000000285'
  ),
  216.00::numeric,
  'SI GL output-VAT control amount equals the server-computed tax ledger'
);

SELECT results_eq(
  $q$SELECT gross_sales, exempt_sales, zero_rated_sales, taxable_base, output_vat
     FROM vw_output_vat_review
     WHERE source_doc_type = 'SI'
       AND source_doc_id = (SELECT id FROM t_vat_ctx WHERE key = 'si')$q$,
  $$VALUES (2766.00::numeric, 250.00::numeric, 500.00::numeric,
            1800.00::numeric, 216.00::numeric)$$,
  'ledger-backed output VAT review equals the posted SI and GL'
);

-- ── Vendor bill: same server authority on input VAT ──────────────────────────

INSERT INTO t_vat_ctx
SELECT 'vb', fn_save_vendor_bill(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222278',
    'branch_id', '33333333-3333-3333-3333-333333333378',
    'supplier_id', '66666666-6666-6666-6666-666666666678',
    'supplier_name_snapshot', 'VAT Integrity Supplier',
    'supplier_tin_snapshot', '777-888-999-078',
    'supplier_invoice_number', 'SUP-028',
    'bill_date', '2026-01-16',
    'total_input_vat_amount', 999999,
    'total_amount', 999999
  ),
  jsonb_build_array(
    jsonb_build_object(
      'description', 'Regular purchase', 'quantity', 3, 'unit_price', 400,
      'discount_amount', 200, 'net_amount', 1, 'input_vat_amount', 999,
      'total_amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000287'
    ),
    jsonb_build_object(
      'description', 'Zero-rated purchase', 'quantity', 1, 'unit_price', 400,
      'net_amount', 1, 'input_vat_amount', 999, 'total_amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-0'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000287'
    ),
    jsonb_build_object(
      'description', 'Exempt purchase', 'quantity', 1, 'unit_price', 200,
      'net_amount', 1, 'input_vat_amount', 999, 'total_amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-EXEMPT'),
      'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000287'
    )
  )
);

SELECT results_eq(
  $q$SELECT line_number, net_amount, input_vat_amount, total_amount
     FROM vendor_bill_lines
     WHERE vendor_bill_id = (SELECT id FROM t_vat_ctx WHERE key = 'vb')
     ORDER BY line_number$q$,
  $$VALUES
      (1, 1000.00::numeric, 120.00::numeric, 1120.00::numeric),
      (2,  400.00::numeric,   0.00::numeric,  400.00::numeric),
      (3,  200.00::numeric,   0.00::numeric,  200.00::numeric)$$,
  'VB save ignores forged derived fields and uses the VAT master rate'
);

SELECT results_eq(
  $q$SELECT total_taxable_amount, total_zero_rated_amount,
            total_exempt_amount, total_input_vat_amount, total_amount
     FROM vendor_bills
     WHERE id = (SELECT id FROM t_vat_ctx WHERE key = 'vb')$q$,
  $$VALUES (1000.00::numeric, 400.00::numeric, 200.00::numeric,
            120.00::numeric, 1720.00::numeric)$$,
  'VB header classifications and totals are rebuilt from server-computed lines'
);

SELECT lives_ok(
  format(
    'SELECT fn_approve_vendor_bill(%L); SELECT fn_post_vendor_bill(%L)',
    (SELECT id FROM t_vat_ctx WHERE key = 'vb'),
    (SELECT id FROM t_vat_ctx WHERE key = 'vb')
  ),
  'mixed-classification VB approves and posts through the governed RPCs'
);

SELECT results_eq(
  $q$SELECT vc.vat_code, t.tax_base, t.tax_amount
     FROM tax_detail_entries t
     JOIN vat_codes vc ON vc.id = t.vat_code_id
     WHERE t.source_doc_type = 'VB'
       AND t.source_doc_id = (SELECT id FROM t_vat_ctx WHERE key = 'vb')
     ORDER BY vc.vat_code$q$,
  $$VALUES
      ('IVAT-0'::text,       400.00::numeric,   0.00::numeric),
      ('IVAT-12'::text,     1000.00::numeric, 120.00::numeric),
      ('IVAT-EXEMPT'::text,  200.00::numeric,   0.00::numeric)$$,
  'VB tax ledger preserves regular, zero-rated, and exempt bases per code'
);

SELECT is(
  (
    SELECT COALESCE(sum(debit_amount - credit_amount), 0)
    FROM journal_entry_lines
    WHERE je_id = (
      SELECT journal_entry_id FROM vendor_bills
      WHERE id = (SELECT id FROM t_vat_ctx WHERE key = 'vb')
    )
      AND account_id = 'aaaaaaaa-0000-0000-0000-000000000283'
  ),
  120.00::numeric,
  'VB GL input-VAT control amount equals the server-computed tax ledger'
);

SELECT results_eq(
  $q$SELECT gross_purchases, exempt_purchases, zero_rated, taxable_base, input_vat
     FROM vw_input_vat_review
     WHERE source_doc_type = 'VB'
       AND source_doc_id = (SELECT id FROM t_vat_ctx WHERE key = 'vb')$q$,
  $$VALUES (1720.00::numeric, 200.00::numeric, 400.00::numeric,
            1000.00::numeric, 120.00::numeric)$$,
  'ledger-backed input VAT review equals the posted VB and GL'
);

-- ── Remaining VAT document families use the same master-rate authority ───────

INSERT INTO t_vat_ctx
SELECT 'cm', fn_save_credit_memo(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222278',
    'branch_id', '33333333-3333-3333-3333-333333333378',
    'customer_id', '55555555-5555-5555-5555-555555555578',
    'customer_name_snapshot', 'VAT Integrity Customer',
    'customer_tin_snapshot', '444-555-666-078',
    'cm_date', '2026-01-17',
    'reason_code_id', (
      SELECT id FROM ref_reason_codes
      WHERE applies_to IN ('credit_memo', 'both') ORDER BY id LIMIT 1
    ),
    'total_vat_amount', 999999, 'total_amount', 999999
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Forged CM payload', 'quantity', 2, 'unit_price', 500,
    'net_amount', 1, 'vat_amount', 999, 'total_amount', 1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000286'
  )),
  'draft'
);

SELECT results_eq(
  $q$SELECT l.net_amount, l.vat_amount, l.total_amount,
            h.total_net_amount, h.total_vat_amount, h.total_amount
     FROM credit_memos h
     JOIN credit_memo_lines l ON l.credit_memo_id = h.id
     WHERE h.id = (SELECT id FROM t_vat_ctx WHERE key = 'cm')$q$,
  $$VALUES (1000.00::numeric, 120.00::numeric, 1120.00::numeric,
            1000.00::numeric, 120.00::numeric, 1120.00::numeric)$$,
  'CM line and header amounts are computed by the save RPC'
);

INSERT INTO t_vat_ctx
SELECT 'dm', fn_save_debit_memo(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222278',
    'branch_id', '33333333-3333-3333-3333-333333333378',
    'customer_id', '55555555-5555-5555-5555-555555555578',
    'customer_name_snapshot', 'VAT Integrity Customer',
    'customer_tin_snapshot', '444-555-666-078',
    'dm_date', '2026-01-18',
    'reason_code_id', (
      SELECT id FROM ref_reason_codes
      WHERE applies_to IN ('debit_memo', 'both') ORDER BY id LIMIT 1
    ),
    'total_vat_amount', 999999, 'total_amount', 999999
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Forged DM payload', 'amount', 1000,
    'vat_amount', 999, 'total_amount', 1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'account_id', 'aaaaaaaa-0000-0000-0000-000000000286'
  )),
  'draft'
);

SELECT results_eq(
  $q$SELECT l.amount, l.vat_amount, l.total_amount,
            h.total_net_amount, h.total_vat_amount, h.total_amount
     FROM debit_memos h
     JOIN debit_memo_lines l ON l.debit_memo_id = h.id
     WHERE h.id = (SELECT id FROM t_vat_ctx WHERE key = 'dm')$q$,
  $$VALUES (1000.00::numeric, 120.00::numeric, 1120.00::numeric,
            1000.00::numeric, 120.00::numeric, 1120.00::numeric)$$,
  'DM line and header amounts are computed by the save RPC'
);

INSERT INTO t_vat_ctx
SELECT 'cp', fn_save_cash_purchase(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222278',
    'branch_id', '33333333-3333-3333-3333-333333333378',
    'transaction_date', '2026-01-19',
    'supplier_id', '66666666-6666-6666-6666-666666666678',
    'supplier_name_snapshot', 'VAT Integrity Supplier',
    'supplier_tin_snapshot', '777-888-999-078',
    'payment_account_id', 'aaaaaaaa-0000-0000-0000-000000000281',
    'total_input_vat_amount', 999999, 'total_amount', 999999
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Forged CP payload', 'quantity', 2, 'unit_price', 500,
    'net_amount', 1, 'input_vat_amount', 999, 'total_amount', 1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000287'
  ))
);

SELECT results_eq(
  $q$SELECT l.net_amount, l.input_vat_amount, l.total_amount,
            h.total_taxable_amount, h.total_input_vat_amount, h.total_amount
     FROM cash_purchases h
     JOIN cash_purchase_lines l ON l.cp_id = h.id
     WHERE h.id = (SELECT id FROM t_vat_ctx WHERE key = 'cp')$q$,
  $$VALUES (1000.00::numeric, 120.00::numeric, 1120.00::numeric,
            1000.00::numeric, 120.00::numeric, 1120.00::numeric)$$,
  'cash-purchase line and header amounts are computed by the save RPC'
);

INSERT INTO t_vat_ctx
SELECT 'vc', fn_save_vendor_credit(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222278',
    'branch_id', '33333333-3333-3333-3333-333333333378',
    'credit_date', '2026-01-20',
    'supplier_id', '66666666-6666-6666-6666-666666666678',
    'supplier_name_snapshot', 'VAT Integrity Supplier',
    'supplier_tin_snapshot', '777-888-999-078',
    'total_input_vat_amount', 999999, 'total_amount', 999999
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Forged VC payload', 'quantity', 2, 'unit_price', 500,
    'net_amount', 1, 'input_vat_amount', 999, 'total_amount', 1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000287'
  ))
);

SELECT results_eq(
  $q$SELECT l.net_amount, l.input_vat_amount, l.total_amount,
            h.total_taxable_amount, h.total_input_vat_amount,
            h.total_amount, h.remaining_balance
     FROM vendor_credits h
     JOIN vendor_credit_lines l ON l.vc_id = h.id
     WHERE h.id = (SELECT id FROM t_vat_ctx WHERE key = 'vc')$q$,
  $$VALUES (1000.00::numeric, 120.00::numeric, 1120.00::numeric,
            1000.00::numeric, 120.00::numeric, 1120.00::numeric,
            1120.00::numeric)$$,
  'vendor-credit line, header, and open balance are computed by the save RPC'
);

-- Foreign-company fixtures prove the simple register views no longer execute
-- with their postgres owner's RLS-bypass posture.
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111129","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
)
VALUES (
  '22222222-2222-2222-2222-222222222279', 'corporation',
  'Foreign VAT Integrity Corp', 'Trading', '111-222-333-079',
  'vat', 'calendar', '29 Foreign Street', '', 'Cebu City', 'Cebu', '6000',
  'foreign-vat@test.local', 'Foreign Owner', 'President', auth.uid(), auth.uid()
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
)
VALUES (
  '33333333-3333-3333-3333-333333333379',
  '22222222-2222-2222-2222-222222222279',
  'HO', 'Foreign Head Office', '29 Foreign Street', '', 'Cebu City', 'Cebu', '6000',
  auth.uid(), auth.uid()
);

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address, created_by, updated_by
)
VALUES (
  '55555555-5555-5555-5555-555555555579',
  '22222222-2222-2222-2222-222222222279',
  'C-FOREIGN-028', 'Foreign Customer', '444-555-666-079',
  'Cebu City', 'Cebu City', auth.uid(), auth.uid()
);

INSERT INTO suppliers (
  id, company_id, supplier_code, registered_name, tin,
  registered_address, created_by, updated_by
)
VALUES (
  '66666666-6666-6666-6666-666666666679',
  '22222222-2222-2222-2222-222222222279',
  'S-FOREIGN-028', 'Foreign Supplier', '777-888-999-079',
  'Cebu City', auth.uid(), auth.uid()
);

INSERT INTO sales_invoices (
  id, company_id, branch_id, customer_id, customer_name_snapshot,
  customer_tin_snapshot, si_number, date, status, created_by, updated_by
)
VALUES (
  '77777777-0000-0000-0000-000000000281',
  '22222222-2222-2222-2222-222222222279',
  '33333333-3333-3333-3333-333333333379',
  '55555555-5555-5555-5555-555555555579',
  'Foreign Customer', '444-555-666-079', 'FOREIGN-SI-028', '2026-01-15',
  'draft', auth.uid(), auth.uid()
);

INSERT INTO vendor_bills (
  id, company_id, branch_id, supplier_id, supplier_name_snapshot,
  supplier_tin_snapshot, bill_number, bill_date, status, created_by, updated_by
)
VALUES (
  '77777777-0000-0000-0000-000000000282',
  '22222222-2222-2222-2222-222222222279',
  '33333333-3333-3333-3333-333333333379',
  '66666666-6666-6666-6666-666666666679',
  'Foreign Supplier', '777-888-999-079', 'FOREIGN-VB-028', '2026-01-16',
  'draft', auth.uid(), auth.uid()
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111128","role":"authenticated"}',
  true
);

-- ── Application role cannot bypass the amount engine ────────────────────────

SET LOCAL ROLE authenticated;

SELECT throws_like(
  format(
    'UPDATE sales_invoices SET total_vat_amount = 999999 WHERE id = %L',
    (SELECT id FROM t_vat_ctx WHERE key = 'si')
  ),
  '%permission denied for table sales_invoices%',
  'authenticated client cannot forge a VAT document header'
);

SELECT throws_like(
  format(
    'UPDATE cash_purchase_lines SET input_vat_amount = 999999 WHERE cp_id = %L',
    (SELECT id FROM t_vat_ctx WHERE key = 'cp')
  ),
  '%permission denied for table cash_purchase_lines%',
  'authenticated client cannot forge a VAT document line'
);

SELECT throws_like(
  format(
    'UPDATE vw_sales_invoice_register SET total_vat_amount = 999999 WHERE invoice_id = %L',
    (SELECT id FROM t_vat_ctx WHERE key = 'si')
  ),
  '%permission denied for view vw_sales_invoice_register%',
  'authenticated client cannot forge VAT through an updatable register view'
);

SELECT is(
  (
    SELECT count(*)::int
    FROM (
      SELECT company_id
      FROM vw_sales_invoice_register
      WHERE company_id = '22222222-2222-2222-2222-222222222279'
      UNION ALL
      SELECT company_id
      FROM vw_vendor_bill_register
      WHERE company_id = '22222222-2222-2222-2222-222222222279'
    ) foreign_register_rows
  ),
  0,
  'security-invoker register views hide foreign-company VAT documents'
);

SELECT throws_like(
  'TRUNCATE TABLE sales_invoice_lines',
  '%permission denied for table sales_invoice_lines%',
  'authenticated client cannot truncate VAT source evidence'
);

SELECT lives_ok(
  format(
    $sql$
      SELECT fn_save_cash_purchase(
        %L,
        jsonb_build_object(
          'company_id', '22222222-2222-2222-2222-222222222278',
          'branch_id', '33333333-3333-3333-3333-333333333378',
          'transaction_date', '2026-01-19',
          'supplier_id', '66666666-6666-6666-6666-666666666678',
          'supplier_name_snapshot', 'VAT Integrity Supplier',
          'supplier_tin_snapshot', '777-888-999-078',
          'payment_account_id', 'aaaaaaaa-0000-0000-0000-000000000281'
        ),
        jsonb_build_array(jsonb_build_object(
          'description', 'RPC-only edit', 'quantity', 2, 'unit_price', 500,
          'net_amount', 1, 'input_vat_amount', 999, 'total_amount', 1000,
          'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
          'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000287'
        ))
      )
    $sql$,
    (SELECT id FROM t_vat_ctx WHERE key = 'cp')
  ),
  'authenticated application caller retains the server-authoritative save RPC'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
