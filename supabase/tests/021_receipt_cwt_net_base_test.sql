-- ══════════════════════════════════════════════════════════════════════════════
-- CWT-NET-BASE-001 - Statutory VAT-Exclusive CWT on Receipts (PXL-AUD-031)
--
-- A VAT sales invoice of 11,200 (10,000 net + 1,200 output VAT) is collected
-- with the statutorily correct CWT: 2% of the VAT-EXCLUSIVE income payment
-- (base 10,000, CWT 200, cash 11,000). Previously fn_validate_receipt_line_cwt
-- derived the base as payment + CWT (gross) and REJECTED this entry. Asserts
-- the net-base OR posts a balanced JE and the correct tax ledger base, the
-- legacy gross convention still validates (fallback), variance-reason
-- mechanics mirror the PV side, partial collections carry proportional bases,
-- and cash sales accept the net convention and record the matching base.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111121',
        'authenticated', 'authenticated', 'harness-cwtnet@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111121","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222231', 'corporation',
        'CWT Net Base Test Corp', 'Software Services', '111-222-333-021',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-cwtnet@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333331',
        '22222222-2222-2222-2222-222222222231', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444431',
        '22222222-2222-2222-2222-222222222231',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222231',
       '44444444-4444-4444-4444-444444444431',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000061', '22222222-2222-2222-2222-222222222231',
   '1010', 'Cash in Bank',       'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000062', '22222222-2222-2222-2222-222222222231',
   '1200', 'Accounts Receivable','asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000063', '22222222-2222-2222-2222-222222222231',
   '1250', 'CWT Receivable',     'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000064', '22222222-2222-2222-2222-222222222231',
   '2100', 'Output VAT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000065', '22222222-2222-2222-2222-222222222231',
   '4010', 'Service Revenue',    'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        ewt_withheld_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222231',
        'aaaaaaaa-0000-0000-0000-000000000062',
        'aaaaaaaa-0000-0000-0000-000000000064',
        'aaaaaaaa-0000-0000-0000-000000000063',
        'aaaaaaaa-0000-0000-0000-000000000061',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222231',
       '33333333-3333-3333-3333-333333333331',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'OR', 'CS');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555531',
        '22222222-2222-2222-2222-222222222231', 'CUST-001',
        'Net Base Withholding Agent Inc', '444-555-666-021',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

-- ── SI1: 10,000 net + 1,200 output VAT = 11,200, posted ────────────────────────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

INSERT INTO t_ctx
SELECT 'si1', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222231',
    'branch_id',               '33333333-3333-3333-3333-333333333331',
    'date',                    '2026-01-15',
    'customer_id',             '55555555-5555-5555-5555-555555555531',
    'customer_name_snapshot',  'Net Base Withholding Agent Inc',
    'customer_tin_snapshot',   '444-555-666-021',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000065'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si1'));

SELECT is((SELECT total_amount FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si1')),
  11200.00::numeric, 'SI1 grand total is 11,200.00 (10,000 net + 1,200 VAT)');

-- ── OR1: the statutory entry — cash 11,000 + CWT 200 on explicit base 10,000 ──
SELECT lives_ok($q$
  INSERT INTO t_ctx
  SELECT 'or1', fn_save_receipt(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222231',
      'branch_id',              '33333333-3333-3333-3333-333333333331',
      'customer_id',            '55555555-5555-5555-5555-555555555531',
      'customer_name_snapshot', 'Net Base Withholding Agent Inc',
      'customer_tin_snapshot',  '444-555-666-021',
      'receipt_date',           '2026-01-20',
      'payment_mode_id',        (SELECT id FROM ref_payment_modes LIMIT 1),
      'total_amount',           11000,
      'total_cwt',              200
    ),
    jsonb_build_array(jsonb_build_object(
      'invoice_id',     (SELECT id FROM t_ctx WHERE key='si1'),
      'payment_amount', 11000,
      'cwt_amount',     200,
      'atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140'),
      'cwt_tax_base',   10000
    )))$q$,
  'OR with statutory CWT (2% of the VAT-exclusive 10,000 base) saves — previously rejected');

SELECT lives_ok(
  format('SELECT fn_post_receipt(%L)', (SELECT id FROM t_ctx WHERE key='or1')),
  'net-base OR posts');

INSERT INTO t_ctx
SELECT 'or1_je', journal_entry_id FROM receipts WHERE id = (SELECT id FROM t_ctx WHERE key='or1');

SELECT is(
  (SELECT total_debit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='or1_je')),
  (SELECT total_credit FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='or1_je')),
  'OR1 journal entry is balanced');
SELECT is((SELECT debit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='or1_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000061'),
  11000.00::numeric, 'OR1 JE debits cash 11,000.00');
SELECT is((SELECT debit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='or1_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000063'),
  200.00::numeric, 'OR1 JE debits CWT receivable 200.00');
SELECT is((SELECT credit_amount FROM journal_entry_lines
           WHERE je_id = (SELECT id FROM t_ctx WHERE key='or1_je')
             AND account_id = 'aaaaaaaa-0000-0000-0000-000000000062'),
  11200.00::numeric, 'OR1 JE credits AR 11,200.00 — invoice fully cleared');

SELECT results_eq(
  format($q$SELECT tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'OR' AND source_doc_id = %L AND tax_kind = 'cwt_receivable'$q$,
         (SELECT id FROM t_ctx WHERE key='or1')),
  $$VALUES (10000.00::numeric, 200.00::numeric)$$,
  'OR1 tax ledger row carries the VAT-exclusive base 10,000.00 and CWT 200.00');

SELECT is(
  (SELECT (11200
    - COALESCE((SELECT sum(rl.payment_amount + rl.cwt_amount) FROM receipt_lines rl
                JOIN receipts r ON r.id = rl.receipt_id AND r.status = 'posted'
                WHERE rl.invoice_id = (SELECT id FROM t_ctx WHERE key='si1')), 0))::numeric),
  0.00::numeric, 'SI1 outstanding balance is zero after the net-base OR');

-- ── Validator mechanics (direct calls, PV parity) ──────────────────────────────
SELECT lives_ok(
  format($q$SELECT fn_validate_receipt_line_cwt(%L, 10976, 224, %L, NULL, NULL)$q$,
         '22222222-2222-2222-2222-222222222231',
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  'legacy gross convention (no explicit base, fallback payment + CWT) still validates');

SELECT throws_like(
  format($q$SELECT fn_validate_receipt_line_cwt(%L, 10900, 300, %L, 10000, NULL)$q$,
         '22222222-2222-2222-2222-222222222231',
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  '%Select a variance reason%',
  'CWT not matching the ATC rate on the explicit base is rejected without a variance reason');

SELECT lives_ok(
  format($q$SELECT fn_validate_receipt_line_cwt(%L, 10900, 300, %L, 10000, 'other_authorized')$q$,
         '22222222-2222-2222-2222-222222222231',
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  'the same variance passes with an authorized variance reason');

SELECT throws_like(
  format($q$SELECT fn_validate_receipt_line_cwt(%L, 10900, 300, %L, 10000, 'because')$q$,
         '22222222-2222-2222-2222-222222222231',
         (SELECT id FROM atc_codes WHERE code = 'WC140')),
  '%Invalid CWT variance reason%',
  'an unrecognized variance reason is rejected');

-- ── SI2 + partial collection with proportional net base ────────────────────────
INSERT INTO t_ctx
SELECT 'si2', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222231',
    'branch_id',               '33333333-3333-3333-3333-333333333331',
    'date',                    '2026-02-10',
    'customer_id',             '55555555-5555-5555-5555-555555555531',
    'customer_name_snapshot',  'Net Base Withholding Agent Inc',
    'customer_tin_snapshot',   '444-555-666-021',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting retainer',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000065'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si2'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si2'));

INSERT INTO t_ctx
SELECT 'or2', fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222231',
    'branch_id',              '33333333-3333-3333-3333-333333333331',
    'customer_id',            '55555555-5555-5555-5555-555555555531',
    'customer_name_snapshot', 'Net Base Withholding Agent Inc',
    'customer_tin_snapshot',  '444-555-666-021',
    'receipt_date',           '2026-02-20',
    'payment_mode_id',        (SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',           5500,
    'total_cwt',              100
  ),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',     (SELECT id FROM t_ctx WHERE key='si2'),
    'payment_amount', 5500,
    'cwt_amount',     100,
    'atc_code_id',    (SELECT id FROM atc_codes WHERE code = 'WC140'),
    'cwt_tax_base',   5000
  )));

SELECT lives_ok(
  format('SELECT fn_post_receipt(%L)', (SELECT id FROM t_ctx WHERE key='or2')),
  'partial collection posts with a proportional VAT-exclusive base');

SELECT results_eq(
  format($q$SELECT tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'OR' AND source_doc_id = %L AND tax_kind = 'cwt_receivable'$q$,
         (SELECT id FROM t_ctx WHERE key='or2')),
  $$VALUES (5000.00::numeric, 100.00::numeric)$$,
  'partial OR tax ledger row: base 5,000.00 (half the net), CWT 100.00');

SELECT is(
  (SELECT (11200
    - COALESCE((SELECT sum(rl.payment_amount + rl.cwt_amount) FROM receipt_lines rl
                JOIN receipts r ON r.id = rl.receipt_id AND r.status = 'posted'
                WHERE rl.invoice_id = (SELECT id FROM t_ctx WHERE key='si2')), 0))::numeric),
  5600.00::numeric, 'SI2 outstanding is 5,600.00 after the half collection');

-- ── Cash sale: net convention accepted and recorded ────────────────────────────
INSERT INTO t_ctx
SELECT 'cs1', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222231',
    'branch_id',              '33333333-3333-3333-3333-333333333331',
    'date',                   '2026-03-05',
    'customer_id',            '55555555-5555-5555-5555-555555555531',
    'customer_name_snapshot', 'Net Base Withholding Agent Inc',
    'customer_tin_snapshot',  '444-555-666-021',
    'cwt_atc_id',             (SELECT id FROM atc_codes WHERE code = 'WC140')::text
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Over-the-counter service',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000065'
  )),
  200)->>'receipt_id')::uuid;

SELECT results_eq(
  format($q$SELECT tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'OR' AND source_doc_id = %L AND tax_kind = 'cwt_receivable'$q$,
         (SELECT id FROM t_ctx WHERE key='cs1')),
  $$VALUES (10000.00::numeric, 200.00::numeric)$$,
  'cash sale with net-convention CWT records the VAT-exclusive base 10,000.00');

SELECT is((SELECT jel.debit_amount FROM journal_entry_lines jel
           JOIN receipts r ON r.journal_entry_id = jel.je_id
           WHERE r.id = (SELECT id FROM t_ctx WHERE key='cs1')
             AND jel.account_id = 'aaaaaaaa-0000-0000-0000-000000000061'),
  11000.00::numeric, 'cash sale receipt JE debits cash 11,000.00 (net of the 200.00 CWT)');

-- Legacy gross convention on a cash sale still works, and records the gross base
INSERT INTO t_ctx
SELECT 'cs2', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222231',
    'branch_id',              '33333333-3333-3333-3333-333333333331',
    'date',                   '2026-03-06',
    'customer_id',            '55555555-5555-5555-5555-555555555531',
    'customer_name_snapshot', 'Net Base Withholding Agent Inc',
    'customer_tin_snapshot',  '444-555-666-021',
    'cwt_atc_id',             (SELECT id FROM atc_codes WHERE code = 'WC140')::text
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Over-the-counter service',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000065'
  )),
  224)->>'receipt_id')::uuid;

SELECT results_eq(
  format($q$SELECT tax_base, tax_amount FROM tax_detail_entries
          WHERE source_doc_type = 'OR' AND source_doc_id = %L AND tax_kind = 'cwt_receivable'$q$,
         (SELECT id FROM t_ctx WHERE key='cs2')),
  $$VALUES (11200.00::numeric, 224.00::numeric)$$,
  'cash sale with legacy gross-convention CWT records the gross base 11,200.00');

-- A CWT matching neither convention is rejected with both expectations shown
SELECT throws_like(
  $q$SELECT fn_save_cash_sale(
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222231',
      'branch_id',              '33333333-3333-3333-3333-333333333331',
      'date',                   '2026-03-07',
      'customer_id',            '55555555-5555-5555-5555-555555555531',
      'customer_name_snapshot', 'Net Base Withholding Agent Inc',
      'customer_tin_snapshot',  '444-555-666-021',
      'cwt_atc_id',             (SELECT id FROM atc_codes WHERE code = 'WC140')::text
    ),
    jsonb_build_array(jsonb_build_object(
      'description',        'Over-the-counter service',
      'quantity',           1,
      'unit_price',         10000,
      'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
      'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000065'
    )),
    150)$q$,
  '%does not match ATC rate%',
  'cash sale CWT matching neither the net nor the gross convention is rejected');

SELECT * FROM finish();
ROLLBACK;
