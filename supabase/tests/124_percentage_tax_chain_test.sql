-- ══════════════════════════════════════════════════════════════════════════════
-- 124 — Percentage tax, the whole chain (Delivery Plan Phase 5, Backlog item 8)
--
-- WHAT THIS GUARDS
--   Percentage tax was calculated nowhere in PXL and never had been, so a
--   Section 116 non-VAT company — the smallest real Philippine business there is
--   — could sell all year and produce nothing to file. This file proves the
--   chain end to end on a company it provisions itself through the current
--   production RPCs: a walk-in cash sale and a credit invoice, both priced
--   through the Tax Engine, both posting DR percentage tax expense / CR
--   percentage tax payable, both writing a tax-ledger row that ties to the
--   General Ledger at zero variance, and both rolling up into a 2551Q and its
--   working paper computed from the posted books rather than in a browser.
--
--   It also proves the governance around the number: percentage-tax codes are
--   offered to exactly the companies that owe the tax, refused to VAT-registered
--   ones, resolved as of the document date, and changed only by closing one
--   version and starting a successor.
--
--   It never reads the canonical/demo seed (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   Recognition is on the sales document (accrual on gross sales). A collection
--   basis for services, a credit-memo reversal of percentage tax, and a rule
--   compelling a PT-registered company to put its code on every line are all
--   recorded in the Product Backlog and are not asserted here.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(37);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '12400000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'percentage-tax@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"12400000-0000-0000-0000-000000000001","role":"authenticated"}', true);

-- The Section 116 taxpayer: non-VAT, percentage-tax registered from 1 Jan 2026.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000c1', 'sole_proprietor', 'Section 116 Traders',
        'Retail and repair services', '355-116-001-00000', 'non_vat', 'calendar',
        '116 Rizal St', 'Unit 1', 'Makati', 'Metro Manila', '1200',
        'percentage-tax@test.local', 'Sofia Reyes', 'Owner', auth.uid(), auth.uid());

-- A VAT-registered neighbour, so the refusals are proven rather than assumed.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000c2', 'corporation', 'VAT Trading Corp',
        'Wholesale', '355-116-002-00000', 'vat', 'calendar',
        '12 Ayala Ave', '', 'Makati', 'Metro Manila', '1200',
        'percentage-tax@test.local', 'Vito Ang', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000d1', '12400000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', '116 Rizal St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('12400000-0000-0000-0000-0000000000f1', '12400000-0000-0000-0000-0000000000c1',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '12400000-0000-0000-0000-0000000000c1', '12400000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('12400000-0000-0000-0000-00000000a001', '12400000-0000-0000-0000-0000000000c1', '1010', 'Cash on Hand',          'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-00000000a002', '12400000-0000-0000-0000-0000000000c1', '1200', 'Accounts Receivable',   'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-00000000a004', '12400000-0000-0000-0000-0000000000c1', '1300', 'Merchandise Inventory', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-00000000a005', '12400000-0000-0000-0000-0000000000c1', '2240', 'Percentage Tax Payable','liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-00000000a006', '12400000-0000-0000-0000-0000000000c1', '4010', 'Merchandise Sales',     'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-00000000a007', '12400000-0000-0000-0000-0000000000c1', '4020', 'Service Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-00000000a008', '12400000-0000-0000-0000-0000000000c1', '5010', 'Cost of Goods Sold',    'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-00000000a009', '12400000-0000-0000-0000-0000000000c1', '5900', 'Inventory Variance',    'expense',   'debit',  true, true, auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-00000000a010', '12400000-0000-0000-0000-0000000000c1', '6600', 'Taxes and Licenses',    'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, default_cash_account_id,
        inventory_account_id, percentage_tax_expense_account_id,
        percentage_tax_payable_account_id, created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000c1',
        '12400000-0000-0000-0000-00000000a002', '12400000-0000-0000-0000-00000000a001',
        '12400000-0000-0000-0000-00000000a004', '12400000-0000-0000-0000-00000000a010',
        '12400000-0000-0000-0000-00000000a005', auth.uid(), auth.uid());

INSERT INTO compliance_profiles (company_id, vat_registered, percentage_tax_registered,
                                 percentage_tax_rate, pt_effective_date, pt_filing_frequency,
                                 created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000c1', false, true, 3.00, '2026-01-01', 'quarterly',
        auth.uid(), auth.uid());
INSERT INTO compliance_profiles (company_id, vat_registered, percentage_tax_registered,
                                 created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000c2', true, false, auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '12400000-0000-0000-0000-0000000000c1', '12400000-0000-0000-0000-0000000000d1',
       rdt.id, rdt.document_code || '-124-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code IN ('OR', 'CS', 'SI');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000e1', '12400000-0000-0000-0000-0000000000c1',
        'CUST-124', 'Barangay Hardware', '444-555-666-124',
        'Makati', 'Makati', auth.uid(), auth.uid());

INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000ab', '12400000-0000-0000-0000-0000000000c1',
        'EA', 'Each', true, auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000ca', '12400000-0000-0000-0000-0000000000c1',
        'GEN', 'General', auth.uid(), auth.uid());

INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   standard_selling_price, standard_cost,
                   sales_account_id, cogs_account_id, inventory_account_id,
                   costing_method, created_by, updated_by)
VALUES
  ('12400000-0000-0000-0000-0000000000bb', '12400000-0000-0000-0000-0000000000c1',
   'GOODS-124', 'Hardware Stock', 'inventory_item',
   '12400000-0000-0000-0000-0000000000ca', '12400000-0000-0000-0000-0000000000ab',
   1000, 600,
   '12400000-0000-0000-0000-00000000a006', '12400000-0000-0000-0000-00000000a008',
   '12400000-0000-0000-0000-00000000a004', 'weighted_average', auth.uid(), auth.uid()),
  ('12400000-0000-0000-0000-0000000000bc', '12400000-0000-0000-0000-0000000000c1',
   'SVC-124', 'Repair Service', 'service',
   '12400000-0000-0000-0000-0000000000ca', '12400000-0000-0000-0000-0000000000ab',
   20000, 0,
   '12400000-0000-0000-0000-00000000a007', NULL, NULL, 'weighted_average',
   auth.uid(), auth.uid());

INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
                        gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
VALUES ('12400000-0000-0000-0000-0000000000ba', '12400000-0000-0000-0000-0000000000c1',
        '12400000-0000-0000-0000-0000000000d1', 'MAIN', 'Main Store',
        '12400000-0000-0000-0000-00000000a004', '12400000-0000-0000-0000-00000000a009',
        auth.uid(), auth.uid());

INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
VALUES ('12400000-0000-0000-0000-0000000000c1', '12400000-0000-0000-0000-0000000000ba',
        '12400000-0000-0000-0000-0000000000bb', 20, 12000, 600);

-- The company's Section 116 code: the governed 3% tax-code version and the
-- 2551Q alphanumeric code PT010.
INSERT INTO percentage_tax_codes (id, company_id, tax_code_id, pt_code, description,
                                  atc_id, rate, form_type, effective_from,
                                  created_by, updated_by)
VALUES ('12400000-0000-0000-0000-00000000c001', '12400000-0000-0000-0000-0000000000c1',
        (SELECT id FROM tax_codes WHERE code = 'PT3-OUT'),
        'PT-116', 'Section 116 percentage tax at 3%',
        (SELECT id FROM atc_codes WHERE code = 'PT010' AND tax_category = 'pt'),
        3.00, '2551Q', '1900-01-01', auth.uid(), auth.uid());

-- The VAT company is given one too, so the refusal is proven against a code
-- that exists rather than against a missing row.
INSERT INTO percentage_tax_codes (id, company_id, tax_code_id, pt_code, description,
                                  atc_id, rate, form_type, effective_from,
                                  created_by, updated_by)
VALUES ('12400000-0000-0000-0000-00000000c002', '12400000-0000-0000-0000-0000000000c2',
        (SELECT id FROM tax_codes WHERE code = 'PT3-OUT'),
        'PT-116', 'Section 116 percentage tax at 3%',
        (SELECT id FROM atc_codes WHERE code = 'PT010' AND tax_category = 'pt'),
        3.00, '2551Q', '1900-01-01', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — One route, two families
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::integer FROM fn_business_tax_codes_asof(
     '12400000-0000-0000-0000-0000000000c1', '2026-02-10', 'output_vat')
   WHERE tax_family = 'percentage_tax'),
  1,
  'the picker offers the Section 116 code to a non-VAT, PT-registered company');   -- 1

SELECT is(
  (SELECT count(*)::integer FROM fn_business_tax_codes_asof(
     '12400000-0000-0000-0000-0000000000c2', '2026-02-10', 'output_vat')
   WHERE tax_family = 'percentage_tax'),
  0,
  'and never offers one to a VAT-registered company');                            -- 2

SELECT is(
  (SELECT count(*)::integer FROM fn_business_tax_codes_asof(
     '12400000-0000-0000-0000-0000000000c1', '2026-02-10', 'input_vat')
   WHERE tax_family = 'percentage_tax'),
  0,
  'percentage tax is the seller''s own tax: a purchase line is never offered it'); -- 3

SELECT throws_like(
  $$SELECT fn_resolve_business_tax_code('12400000-0000-0000-0000-0000000000c2',
      NULL, '12400000-0000-0000-0000-00000000c002', DATE '2026-02-10', 'output_vat')$$,
  '%VAT-registered company cannot use percentage-tax code%',
  'a VAT company is refused a percentage-tax code');                              -- 4

-- A Section 116 line is VAT-exempt AND percentage-taxable. One call, both
-- answers; the VAT-bearing pairing is what the route refuses.
SELECT results_eq(
  $q$SELECT tax_family, code, tax_rate
       FROM fn_resolve_business_tax_code('12400000-0000-0000-0000-0000000000c1',
              (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
              '12400000-0000-0000-0000-00000000c001', DATE '2026-02-10', 'output_vat')
      ORDER BY tax_family$q$,
  $$VALUES ('percentage_tax'::text, 'PT-116'::text, 3.0000::numeric(9,4)),
           ('vat'::text, 'VAT-EXEMPT'::text, 0.0000::numeric(9,4))$$,
  'one route answers for both business taxes on a Section 116 line');             -- 5

SELECT throws_like(
  $$SELECT fn_resolve_business_tax_code('12400000-0000-0000-0000-0000000000c1',
      NULL, '12400000-0000-0000-0000-00000000c002', DATE '2026-02-10', 'output_vat')$$,
  '%belongs to another company%',
  'a percentage-tax code cannot be borrowed from another company');               -- 6

-- The engine: the component exists, and it leaves the price alone.
SELECT results_eq(
  $q$SELECT tax_kind, tax_base, tax_rate, tax_amount, net_amount, gross_amount
       FROM fn_calculate_tax(jsonb_build_object(
              'company_id',             '12400000-0000-0000-0000-0000000000c1',
              'document_date',          '2026-02-10',
              'direction',              'sale',
              'amount',                 10000,
              'percentage_tax_code_id', '12400000-0000-0000-0000-00000000c001'))
      WHERE tax_kind = 'percentage_tax'$q$,
  $$VALUES ('percentage_tax'::text, 10000.00::numeric(15,2), 3.0000::numeric(9,4),
            300.00::numeric(15,2), 10000.00::numeric(15,2), 10000.00::numeric(15,2))$$,
  'the engine charges 3% of gross sales and leaves net and gross untouched');      -- 7

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — The counter sale: 20,000 service + 4,000 goods, PT 3% = 720.00
--   Goods cost 4 x 600 = 2,400. The customer pays 24,000; the shop owes 720.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'cash_sale', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '12400000-0000-0000-0000-0000000000c1',
    'branch_id',              '12400000-0000-0000-0000-0000000000d1',
    'date',                   '2026-02-10',
    'customer_id',            '12400000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Barangay Hardware',
    'customer_tin_snapshot',  '444-555-666-124',
    'warehouse_id',           '12400000-0000-0000-0000-0000000000ba'
  ),
  jsonb_build_array(
    jsonb_build_object(
      'item_id',                '12400000-0000-0000-0000-0000000000bc',
      'description',            'Repair Service',
      'quantity',               1,
      'unit_price',             20000,
      'vat_code_id',            (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
      'percentage_tax_code_id', '12400000-0000-0000-0000-00000000c001'
    ),
    jsonb_build_object(
      'item_id',                '12400000-0000-0000-0000-0000000000bb',
      'description',            'Hardware Stock',
      'quantity',               4,
      'unit_price',             1000,
      'vat_code_id',            (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
      'percentage_tax_code_id', '12400000-0000-0000-0000-00000000c001'
    )
  ),
  0)->>'si_id')::uuid;

SELECT results_eq(
  $q$SELECT total_amount, total_vat_amount, total_percentage_tax_amount
       FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'cash_sale')$q$,
  $$VALUES (24000.00::numeric, 0.00::numeric, 720.00::numeric)$$,
  'the customer is billed 24,000 with no VAT, and the shop owes 720 percentage tax'); -- 8

SELECT results_eq(
  $q$SELECT percentage_tax_base, percentage_tax_rate, percentage_tax_amount
       FROM sales_invoice_lines
      WHERE sales_invoice_id = (SELECT id FROM t_ctx WHERE key = 'cash_sale')
      ORDER BY line_number$q$,
  $$VALUES (20000.00::numeric(15,2), 3.0000::numeric(9,4), 600.00::numeric(15,2)),
           (4000.00::numeric(15,2), 3.0000::numeric(9,4), 120.00::numeric(15,2))$$,
  'every line stamps the base, the resolved rate and the amount it was charged');  -- 9

INSERT INTO t_ctx
SELECT 'cash_je', journal_entry_id FROM sales_invoices
WHERE id = (SELECT id FROM t_ctx WHERE key = 'cash_sale');

SELECT is(
  (SELECT SUM(debit_amount) - SUM(credit_amount) FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key = 'cash_je')),
  0::numeric, 'the cash sale journal balances with percentage tax in it');         -- 10

SELECT is(
  (SELECT debit_amount FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key = 'cash_je')
      AND account_id = '12400000-0000-0000-0000-00000000a010'),
  720.00::numeric, 'percentage tax is expensed at 720.00');                        -- 11

SELECT is(
  (SELECT credit_amount FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key = 'cash_je')
      AND account_id = '12400000-0000-0000-0000-00000000a005'),
  720.00::numeric, 'and owed to the BIR at 720.00');                               -- 12

SELECT is(
  (SELECT debit_amount FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key = 'cash_je')
      AND account_id = '12400000-0000-0000-0000-00000000a002'),
  24000.00::numeric,
  'the receivable is the 24,000 the customer owes: percentage tax is not charged to them'); -- 13

SELECT is(
  (SELECT qty_on_hand FROM stock_balances
    WHERE warehouse_id = '12400000-0000-0000-0000-0000000000ba'
      AND item_id = '12400000-0000-0000-0000-0000000000bb'),
  16::numeric, 'the goods still leave stock: percentage tax changed nothing else'); -- 14

SELECT results_eq(
  $q$SELECT tde.tax_kind, tde.tax_base, tde.tax_rate, tde.tax_amount,
            tc.code, ac.code
       FROM tax_detail_entries tde
       JOIN tax_codes tc ON tc.id = tde.tax_code_id
       JOIN atc_codes ac ON ac.id = tde.atc_code_id
      WHERE tde.company_id = '12400000-0000-0000-0000-0000000000c1'
        AND tde.tax_kind = 'percentage_tax'$q$,
  $$VALUES ('percentage_tax'::text, 24000.00::numeric(15,2), 3.00::numeric(5,2),
            720.00::numeric(15,2), 'PT3-OUT'::text, 'PT010'::text)$$,
  'one ledger row per code, stamped with the tax-code version, its rate and the 2551Q ATC'); -- 15

SELECT is(
  (SELECT percentage_tax_code_id FROM tax_detail_entries
    WHERE company_id = '12400000-0000-0000-0000-0000000000c1'
      AND tax_kind = 'percentage_tax'),
  '12400000-0000-0000-0000-00000000c001'::uuid,
  'the ledger row names the company code version it came from');                   -- 16

SELECT results_eq(
  $q$SELECT ledger_tax_base, ledger_tax_amount, variance, is_reconciled
       FROM fn_percentage_tax_gl_reconciliation(
              '12400000-0000-0000-0000-0000000000c1', DATE '2026-01-01', DATE '2026-03-31')$q$,
  $$VALUES (24000.00::numeric(15,2), 720.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'the percentage tax ledger ties to the payable control account at zero variance'); -- 17

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — The same tax on a credit invoice: 10,000 service, PT 300.00
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '12400000-0000-0000-0000-0000000000c1',
    'branch_id',                 '12400000-0000-0000-0000-0000000000d1',
    'date',                      '2026-03-15',
    'customer_id',               '12400000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot',    'Barangay Hardware',
    'customer_tin_snapshot',     '444-555-666-124',
    'customer_address_snapshot', 'Makati'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',                '12400000-0000-0000-0000-0000000000bc',
    'description',            'Repair Service',
    'quantity',               1,
    'unit_price',             10000,
    'revenue_account_id',     '12400000-0000-0000-0000-00000000a007',
    'vat_code_id',            (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'percentage_tax_code_id', '12400000-0000-0000-0000-00000000c001'
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

SELECT is(
  (SELECT total_percentage_tax_amount FROM sales_invoices
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')),
  300.00::numeric, 'the credit invoice carries 300.00 of percentage tax');         -- 18

INSERT INTO t_ctx
SELECT 'si_je', journal_entry_id FROM sales_invoices
WHERE id = (SELECT id FROM t_ctx WHERE key = 'si');

SELECT is(
  (SELECT SUM(debit_amount) - SUM(credit_amount) FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key = 'si_je')),
  0::numeric, 'the sales invoice journal balances with percentage tax in it');     -- 19

SELECT is(
  (SELECT SUM(credit_amount) FROM journal_entry_lines
    WHERE je_id = (SELECT id FROM t_ctx WHERE key = 'si_je')
      AND account_id = '12400000-0000-0000-0000-00000000a005'),
  300.00::numeric, 'and credits the percentage tax payable');                      -- 20

SELECT results_eq(
  $q$SELECT ledger_tax_base, ledger_tax_amount, variance, is_reconciled
       FROM fn_percentage_tax_gl_reconciliation(
              '12400000-0000-0000-0000-0000000000c1', DATE '2026-01-01', DATE '2026-03-31')$q$,
  $$VALUES (34000.00::numeric(15,2), 1020.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'both documents together still reconcile to the General Ledger at 0.00');        -- 21

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — The 2551Q, computed from the posted books
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $q$SELECT atc_code, tax_rate, taxable_base, tax_due, document_count
       FROM fn_compute_percentage_tax_return(
              '12400000-0000-0000-0000-0000000000c1', 2026, 1)$q$,
  $$VALUES ('PT010'::text, 3.0000::numeric(9,4), 34000.00::numeric(15,2),
            1020.00::numeric(15,2), 2)$$,
  'the quarterly computation groups by ATC, which is how a 2551Q is filed');       -- 22

SELECT is(
  (fn_generate_pt_return('12400000-0000-0000-0000-0000000000c1', 2026, 1)->>'pt_due')::numeric,
  1020.00::numeric, 'generating the return reports 1,020.00 due for Q1');          -- 23

SELECT results_eq(
  $q$SELECT taxable_base, pt_rate, pt_due, pt_still_due, status,
            gross_sales_exempt, gross_sales_zero_rated
       FROM pt_returns
      WHERE company_id = '12400000-0000-0000-0000-0000000000c1'
        AND period_year = 2026 AND period_quarter = 1$q$,
  $$VALUES (34000.00::numeric(15,2), 3.00::numeric(5,2), 1020.00::numeric(15,2),
            1020.00::numeric(15,2), 'draft'::text,
            0.00::numeric(15,2), 0.00::numeric(15,2))$$,
  'the stored return carries the ledger figures, and no VAT-shaped ones');         -- 24

-- Re-pointed by Backlog 8f: this used to read the legacy PT working paper, which
-- listed one row per document. The governed working paper groups by the
-- dimensions the 2551Q is filed on and states how many documents stand behind
-- each figure — the same evidence, in the shape the form is filed in, with the
-- documents themselves reachable through the accounting trace.
SELECT is(
  (SELECT SUM(l.document_count)::integer FROM filing_artifact_lines l
     JOIN filing_artifacts a ON a.id = l.artifact_id
    WHERE a.company_id = '12400000-0000-0000-0000-0000000000c1'
      AND a.form_code = '2551Q'
      AND a.period_year = 2026 AND a.period_number = 1),
  2, 'the working paper schedules both documents behind the one number');          -- 25

SELECT is(
  (SELECT SUM(l.tax_amount) FROM filing_artifact_lines l
     JOIN filing_artifacts a ON a.id = l.artifact_id
    WHERE a.company_id = '12400000-0000-0000-0000-0000000000c1'
      AND a.form_code = '2551Q'
      AND a.period_year = 2026 AND a.period_number = 1),
  1020.00::numeric, 'and the schedule adds up to the return');                     -- 26

SELECT throws_like(
  $$UPDATE pt_returns SET taxable_base = 5000, pt_due = 150, status = 'final'
     WHERE company_id = '12400000-0000-0000-0000-0000000000c1'
       AND period_year = 2026 AND period_quarter = 1$$,
  '%does not reconcile to the posted ledger%',
  'a return may not be filed on a figure the ledger does not support');            -- 27

SELECT lives_ok(
  $$UPDATE pt_returns SET status = 'final'
     WHERE company_id = '12400000-0000-0000-0000-0000000000c1'
       AND period_year = 2026 AND period_quarter = 1$$,
  'a return that agrees with the ledger may be marked final');                     -- 28

SELECT throws_like(
  $$SELECT fn_generate_pt_return('12400000-0000-0000-0000-0000000000c1', 2026, 1)$$,
  '%cannot be regenerated%',
  'and a final return is not silently rewritten underneath the accountant');       -- 29

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — A statutory rate change is a succession, not an edit
--   Section 116 fell to 1% under CREATE and returned to 3%. The document date
--   decides which version applies; the already filed quarter does not move.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO tax_codes (id, code, description, tax_type, rate, is_active, effective_from)
VALUES ('12400000-0000-0000-0000-00000000d001', 'PT1-116', 'Percentage Tax 1% (Section 116)',
        'pt', 1.00, true, '2026-04-01');
INSERT INTO atc_codes (id, code, description, tax_category, rate, is_active, effective_from)
VALUES ('12400000-0000-0000-0000-00000000d002', 'PT011', 'Section 116 at the reduced rate',
        'pt', 1.00, true, '2026-04-01');

SELECT throws_like(
  $$INSERT INTO percentage_tax_codes (company_id, tax_code_id, pt_code, description,
                                      atc_id, rate, form_type, effective_from,
                                      supersedes_percentage_tax_code_id)
     VALUES ('12400000-0000-0000-0000-0000000000c1',
             '12400000-0000-0000-0000-00000000d001', 'PT-116', 'Section 116 at 1%',
             '12400000-0000-0000-0000-00000000d002', 1.00, '2551Q', '2026-04-01',
             '12400000-0000-0000-0000-00000000c001')$$,
  '%overlapping active effective window%',
  'a successor cannot start while the version it replaces is still open');         -- 30

UPDATE percentage_tax_codes SET effective_to = '2026-03-31'
WHERE id = '12400000-0000-0000-0000-00000000c001';

INSERT INTO percentage_tax_codes (id, company_id, tax_code_id, pt_code, description,
                                  atc_id, rate, form_type, effective_from,
                                  supersedes_percentage_tax_code_id, created_by, updated_by)
VALUES ('12400000-0000-0000-0000-00000000c003', '12400000-0000-0000-0000-0000000000c1',
        '12400000-0000-0000-0000-00000000d001', 'PT-116', 'Section 116 at 1%',
        '12400000-0000-0000-0000-00000000d002', 1.00, '2551Q', '2026-04-01',
        '12400000-0000-0000-0000-00000000c001', auth.uid(), auth.uid());

SELECT throws_like(
  $$UPDATE percentage_tax_codes SET rate = 2.00
     WHERE id = '12400000-0000-0000-0000-00000000c001'$$,
  '%immutable after use%',
  'the version that computed a filed quarter can never be edited');                -- 31

SELECT throws_like(
  $$SELECT fn_resolve_business_tax_code('12400000-0000-0000-0000-0000000000c1',
      NULL, '12400000-0000-0000-0000-00000000c001', DATE '2026-05-05', 'output_vat')$$,
  '%is not effective on 2026-05-05%',
  'the superseded version is refused on a date it no longer covers');              -- 32

INSERT INTO t_ctx
SELECT 'q2_sale', (fn_save_cash_sale(
  jsonb_build_object(
    'company_id',             '12400000-0000-0000-0000-0000000000c1',
    'branch_id',              '12400000-0000-0000-0000-0000000000d1',
    'date',                   '2026-05-05',
    'customer_id',            '12400000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot', 'Barangay Hardware',
    'customer_tin_snapshot',  '444-555-666-124',
    'warehouse_id',           '12400000-0000-0000-0000-0000000000ba'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',                '12400000-0000-0000-0000-0000000000bc',
    'description',            'Repair Service',
    'quantity',               1,
    'unit_price',             50000,
    'vat_code_id',            (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'percentage_tax_code_id', '12400000-0000-0000-0000-00000000c003'
  )),
  0)->>'si_id')::uuid;

SELECT is(
  (SELECT total_percentage_tax_amount FROM sales_invoices
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'q2_sale')),
  500.00::numeric,
  'a May sale is taxed at the successor rate of 1%, not at the rate it replaced'); -- 33

SELECT results_eq(
  $q$SELECT taxable_base, pt_rate, pt_due
       FROM pt_returns
      WHERE company_id = '12400000-0000-0000-0000-0000000000c1'
        AND period_year = 2026 AND period_quarter = 2$q$,
  $$VALUES (50000.00::numeric(15,2), 1.00::numeric(5,2), 500.00::numeric(15,2))$$,
  'and Q2 files on its own quarter, leaving the filed Q1 alone')
FROM (SELECT fn_generate_pt_return('12400000-0000-0000-0000-0000000000c1', 2026, 2)) g; -- 34

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — A voided sale owes no percentage tax
--   The tax is recognised on the document, so a document that is voided must
--   take its tax back out — in the journal and in the ledger the return is
--   built from. Q3 is used so the filed Q1 is left exactly as it was filed.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO t_ctx
SELECT 'q3_si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '12400000-0000-0000-0000-0000000000c1',
    'branch_id',                 '12400000-0000-0000-0000-0000000000d1',
    'date',                      '2026-09-08',
    'customer_id',               '12400000-0000-0000-0000-0000000000e1',
    'customer_name_snapshot',    'Barangay Hardware',
    'customer_tin_snapshot',     '444-555-666-124',
    'customer_address_snapshot', 'Makati'
  ),
  jsonb_build_array(jsonb_build_object(
    'item_id',                '12400000-0000-0000-0000-0000000000bc',
    'description',            'Repair Service',
    'quantity',               1,
    'unit_price',             80000,
    'revenue_account_id',     '12400000-0000-0000-0000-00000000a007',
    'vat_code_id',            (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'percentage_tax_code_id', '12400000-0000-0000-0000-00000000c003'
  )));

SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'q3_si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'q3_si'));

SELECT is(
  (SELECT SUM(tax_amount) FROM tax_detail_entries
    WHERE source_doc_id = (SELECT id FROM t_ctx WHERE key = 'q3_si')
      AND tax_kind = 'percentage_tax'),
  800.00::numeric, 'the September invoice recognises 800.00 at the 1% rate');    -- 35

SELECT fn_void_sales_invoice((SELECT id FROM t_ctx WHERE key = 'q3_si'), NULL,
  'mis-billed service');

SELECT results_eq(
  $q$SELECT SUM(tax_amount), COUNT(*)::integer,
            COUNT(percentage_tax_code_id)::integer
       FROM tax_detail_entries
      WHERE source_doc_id = (SELECT id FROM t_ctx WHERE key = 'q3_si')
        AND tax_kind = 'percentage_tax'$q$,
  $$VALUES (0.00::numeric, 2, 2)$$,
  'voiding it counter-posts the tax to nil, and the counter-row keeps its code'); -- 36

SELECT results_eq(
  $q$SELECT ledger_tax_amount, variance, is_reconciled
       FROM fn_percentage_tax_gl_reconciliation(
              '12400000-0000-0000-0000-0000000000c1', DATE '2026-07-01', DATE '2026-09-30')$q$,
  $$VALUES (0.00::numeric(15,2), 0.00::numeric(15,2), true)$$,
  'and the quarter still ties to the General Ledger, at nil');                    -- 37

SELECT * FROM finish();
ROLLBACK;
