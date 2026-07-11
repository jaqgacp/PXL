-- GL-PREVIEW-PARITY-001 / POSTING-INVARIANTS-001
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(40);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111125',
  'authenticated', 'authenticated', 'posting-preview@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111125","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222225', 'corporation',
  'Posting Preview Test Corp', 'Software Services', '111-222-333-025',
  'vat', 'calendar',
  'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
  'posting-preview@test.local', 'Juan Dela Cruz', 'President',
  auth.uid(), auth.uid()
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '33333333-3333-3333-3333-333333333325',
  '22222222-2222-2222-2222-222222222225', 'HO', 'Head Office',
  'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
  auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES (
  '44444444-4444-4444-4444-444444444425',
  '22222222-2222-2222-2222-222222222225',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
SELECT
  '22222222-2222-2222-2222-222222222225',
  '44444444-4444-4444-4444-444444444425',
  m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
  make_date(2026, m, 1),
  (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
  false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name,
  account_type, normal_balance, is_postable, is_active,
  created_by, updated_by
) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000125', '22222222-2222-2222-2222-222222222225',
   '1010', 'Cash', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000225', '22222222-2222-2222-2222-222222222225',
   '1200', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000325', '22222222-2222-2222-2222-222222222225',
   '2100', 'Output VAT', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000425', '22222222-2222-2222-2222-222222222225',
   '4010', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000525', '22222222-2222-2222-2222-222222222225',
   '9999', 'Inactive Account', 'expense', 'debit', true, false, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000625', '22222222-2222-2222-2222-222222222225',
   '6010', 'Amortization Expense', 'expense', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (
  company_id, ar_account_id, vat_payable_account_id, default_cash_account_id,
  created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222225',
  'aaaaaaaa-0000-0000-0000-000000000225',
  'aaaaaaaa-0000-0000-0000-000000000325',
  'aaaaaaaa-0000-0000-0000-000000000125',
  auth.uid(), auth.uid()
);

INSERT INTO number_series (
  company_id, branch_id, document_type_id, prefix,
  number_length, starting_number, next_number,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222225',
  '33333333-3333-3333-3333-333333333325',
  id, 'SI-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types
WHERE document_code = 'SI';

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555525',
  '22222222-2222-2222-2222-222222222225', 'CUST-001',
  'Preview Customer Inc', '444-555-666-025',
  'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid()
);

CREATE TEMP TABLE t_ctx (key TEXT PRIMARY KEY, id UUID);
CREATE TEMP TABLE t_preview (payload JSONB);
CREATE TEMP TABLE t_amort_preview (payload JSONB);
CREATE TEMP TABLE t_recurring_preview (payload JSONB);

SELECT results_eq(
  $q$
    SELECT document_type
    FROM ref_posting_source_types
    WHERE document_type IN ('FA','FA_DEPR','FA_DISP','FA_IMP','AMORT','PR','REVREC')
    ORDER BY document_type
  $q$,
  $q$
    VALUES
      ('AMORT'::text), ('FA'::text), ('FA_DEPR'::text),
      ('FA_DISP'::text), ('FA_IMP'::text), ('PR'::text), ('REVREC'::text)
  $q$,
  'posting source registry covers fixed-asset and schedule journal types'
);

INSERT INTO fixed_asset_categories (
  id, company_id, category_code, category_name,
  depreciation_method, useful_life_months, salvage_rate,
  gl_asset_account_id, gl_accum_depr_account_id, gl_depr_expense_account_id,
  created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666625',
  '22222222-2222-2222-2222-222222222225',
  'TEST-FA', 'Preview Test Assets', 'straight_line', 12, 0,
  'aaaaaaaa-0000-0000-0000-000000000225',
  'aaaaaaaa-0000-0000-0000-000000000325',
  'aaaaaaaa-0000-0000-0000-000000000625',
  auth.uid(), auth.uid()
);

INSERT INTO journal_entries (
  id, company_id, branch_id, je_number, je_date, fiscal_period_id,
  description, reference_doc_type, status, total_debit, total_credit,
  created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777625',
  '22222222-2222-2222-2222-222222222225',
  '33333333-3333-3333-3333-333333333325',
  'FA-LINK-001', '2026-07-10',
  (SELECT id FROM fiscal_periods
   WHERE company_id = '22222222-2222-2222-2222-222222222225' AND period_number = 7),
  'Fixed asset source-link fixture', 'FA', 'posted', 1200, 1200,
  auth.uid(), auth.uid()
);

INSERT INTO journal_entry_lines (
  je_id, company_id, line_number, account_id, description,
  debit_amount, credit_amount, created_by, updated_by
) VALUES
  ('77777777-7777-7777-7777-777777777625', '22222222-2222-2222-2222-222222222225',
   1, 'aaaaaaaa-0000-0000-0000-000000000225', 'Asset', 1200, 0, auth.uid(), auth.uid()),
  ('77777777-7777-7777-7777-777777777625', '22222222-2222-2222-2222-222222222225',
   2, 'aaaaaaaa-0000-0000-0000-000000000125', 'Cash', 0, 1200, auth.uid(), auth.uid());

INSERT INTO fixed_assets (
  id, company_id, branch_id, asset_number, asset_name, category_id,
  acquisition_date, depreciation_start_date, acquisition_cost, salvage_value,
  useful_life_months, depreciation_method, acquisition_je_id, fiscal_period_id,
  status, created_by, updated_by
) VALUES (
  '88888888-8888-8888-8888-888888888625',
  '22222222-2222-2222-2222-222222222225',
  '33333333-3333-3333-3333-333333333325',
  'FA-TEST-001', 'Preview Test Asset',
  '66666666-6666-6666-6666-666666666625',
  '2026-07-10', '2026-07-31', 1200, 0, 12, 'straight_line',
  '77777777-7777-7777-7777-777777777625',
  (SELECT id FROM fiscal_periods
   WHERE company_id = '22222222-2222-2222-2222-222222222225' AND period_number = 7),
  'active', auth.uid(), auth.uid()
);

SELECT is(
  (SELECT reference_doc_id FROM journal_entries
   WHERE id = '77777777-7777-7777-7777-777777777625'),
  '88888888-8888-8888-8888-888888888625'::uuid,
  'fixed-asset acquisition links its posted journal to the asset source row'
);

INSERT INTO journal_entries (
  id, company_id, branch_id, je_number, je_date, fiscal_period_id,
  description, reference_doc_type, reference_doc_id, status,
  total_debit, total_credit, created_by, updated_by
) VALUES (
  '77777777-7777-7777-7777-777777777725',
  '22222222-2222-2222-2222-222222222225',
  '33333333-3333-3333-3333-333333333325',
  'FA-DEPR-LINK-001', '2026-07-31',
  (SELECT id FROM fiscal_periods
   WHERE company_id = '22222222-2222-2222-2222-222222222225' AND period_number = 7),
  'Fixed asset depreciation source-link fixture', 'FA_DEPR',
  '88888888-8888-8888-8888-888888888625', 'posted', 100, 100,
  auth.uid(), auth.uid()
);

INSERT INTO journal_entry_lines (
  je_id, company_id, line_number, account_id, description,
  debit_amount, credit_amount, created_by, updated_by
) VALUES
  ('77777777-7777-7777-7777-777777777725', '22222222-2222-2222-2222-222222222225',
   1, 'aaaaaaaa-0000-0000-0000-000000000625', 'Depreciation', 100, 0, auth.uid(), auth.uid()),
  ('77777777-7777-7777-7777-777777777725', '22222222-2222-2222-2222-222222222225',
   2, 'aaaaaaaa-0000-0000-0000-000000000325', 'Accumulated depreciation', 0, 100, auth.uid(), auth.uid());

INSERT INTO asset_depreciation_entries (
  id, company_id, asset_id, period_number, entry_date, depreciation_amount,
  accumulated_depr_after, net_book_value_after, status, journal_entry_id,
  posted_at, posted_by
) VALUES (
  '99999999-9999-9999-9999-999999999625',
  '22222222-2222-2222-2222-222222222225',
  '88888888-8888-8888-8888-888888888625',
  1, '2026-07-31', 100, 100, 1100, 'posted',
  '77777777-7777-7777-7777-777777777725', NOW(), auth.uid()
);

SELECT is(
  (SELECT reference_doc_id FROM journal_entries
   WHERE id = '77777777-7777-7777-7777-777777777725'),
  '99999999-9999-9999-9999-999999999625'::uuid,
  'depreciation journal source is the individual schedule entry, not its parent asset'
);

INSERT INTO recurring_journal_templates (
  id, company_id, branch_id, template_name, description, recurrence_type,
  day_of_month, next_run_date, start_date, auto_reverse, is_active,
  created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666725',
  '22222222-2222-2222-2222-222222222225',
  '33333333-3333-3333-3333-333333333325',
  'Preview Recurring Journal', 'Recurring rollback fixture', 'monthly',
  20, '2026-07-20', '2026-07-20', false, true, auth.uid(), auth.uid()
);

INSERT INTO recurring_journal_template_lines (
  template_id, company_id, line_number, account_id, description,
  debit_amount, credit_amount, created_by
) VALUES
  ('66666666-6666-6666-6666-666666666725', '22222222-2222-2222-2222-222222222225',
   1, 'aaaaaaaa-0000-0000-0000-000000000625', 'Recurring expense', 700, 0, auth.uid()),
  ('66666666-6666-6666-6666-666666666725', '22222222-2222-2222-2222-222222222225',
   2, 'aaaaaaaa-0000-0000-0000-000000000125', 'Recurring cash', 0, 700, auth.uid());

INSERT INTO t_recurring_preview
SELECT fn_preview_gl_impact(
  'RECURRING', '66666666-6666-6666-6666-666666666725', '2026-07-20'
);

SELECT is((SELECT payload->>'mode' FROM t_recurring_preview), 'preview',
  'recurring journal returns an exact rollback preview');
SELECT is((SELECT payload->>'posting_date' FROM t_recurring_preview), '2026-07-20',
  'recurring preview uses the operator-selected execution date');
SELECT is((SELECT count(*)::int FROM journal_entries
           WHERE reference_doc_type = 'RECURRING'
             AND reference_doc_id = '66666666-6666-6666-6666-666666666725'),
  0, 'recurring preview persists no journal entry');
SELECT is((SELECT next_run_date FROM recurring_journal_templates
           WHERE id = '66666666-6666-6666-6666-666666666725'),
  '2026-07-20'::date, 'recurring preview rolls schedule advancement back');
SELECT is((SELECT jsonb_array_length(payload->'lines') FROM t_recurring_preview), 2,
  'recurring preview exposes both authoritative template lines');
SELECT is((SELECT (payload->>'total_debit')::numeric FROM t_recurring_preview), 700.00::numeric,
  'recurring preview exposes the exact template amount');

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222225',
    'branch_id', '33333333-3333-3333-3333-333333333325',
    'date', '2026-07-10',
    'customer_id', '55555555-5555-5555-5555-555555555525',
    'customer_name_snapshot', 'Preview Customer Inc',
    'customer_tin_snapshot', '444-555-666-025',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Consulting services',
    'quantity', 1,
    'unit_price', 10000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000425'
  ))
);
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

INSERT INTO t_preview
SELECT fn_preview_gl_impact('SI', (SELECT id FROM t_ctx WHERE key = 'si'));

SELECT is((SELECT payload->>'mode' FROM t_preview), 'preview',
  'saved approved SI returns a server-side preview');
SELECT is((SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')),
  'approved', 'preview rolls the source status back to approved');
SELECT is((SELECT count(*)::int FROM journal_entries WHERE reference_doc_type = 'SI'
           AND reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'si')),
  0, 'preview persists no journal entry');
SELECT is((SELECT count(*)::int FROM tax_detail_entries WHERE source_doc_type = 'SI'
           AND source_doc_id = (SELECT id FROM t_ctx WHERE key = 'si')),
  0, 'preview persists no tax ledger rows');
SELECT is((SELECT jsonb_array_length(payload->'lines') FROM t_preview), 3,
  'preview exposes the three authoritative SI posting lines');
SELECT is((SELECT (payload->>'total_debit')::numeric FROM t_preview), 11200.00::numeric,
  'preview total debit is 11,200.00');
SELECT is((SELECT (payload->>'total_credit')::numeric FROM t_preview), 11200.00::numeric,
  'preview total credit is 11,200.00');
SELECT is(
  (SELECT payload->'lines'->0->>'account_source' FROM t_preview),
  'company_accounting_config.ar_account_id',
  'preview explains the configured AR account source'
);
SELECT is((SELECT payload->>'fiscal_period_name' FROM t_preview), 'Jul 2026',
  'preview exposes the resolved fiscal period');
SELECT is((SELECT payload->>'branch_name' FROM t_preview), 'Head Office',
  'preview exposes the posting branch');

SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key = 'si'));

SELECT is((SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')),
  'posted', 'the same source posts after preview');
SELECT is((SELECT count(*)::int FROM journal_entries WHERE reference_doc_type = 'SI'
           AND reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'si')),
  1, 'posting creates exactly one source journal entry');

SELECT results_eq(
  $q$
    SELECT
      line->>'account_id',
      (line->>'debit')::numeric,
      (line->>'credit')::numeric
    FROM t_preview, jsonb_array_elements(payload->'lines') AS line
    ORDER BY (line->>'line_number')::int
  $q$,
  $q$
    SELECT account_id::text, debit_amount, credit_amount
    FROM journal_entry_lines
    WHERE je_id = (
      SELECT journal_entry_id FROM sales_invoices
      WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')
    )
    ORDER BY line_number
  $q$,
  'preview account/debit/credit rows exactly equal the posted JE'
);

SELECT is(
  fn_preview_gl_impact('SI', (SELECT id FROM t_ctx WHERE key = 'si'))->>'mode',
  'posted',
  'preview RPC switches to the authoritative posted JE after posting'
);

SELECT is(
  fn_get_accounting_trace('SI', (SELECT id FROM t_ctx WHERE key = 'si'), NULL)->>'source_route',
  '/accounting-source?sourceType=SI&sourceId=' || (SELECT id::text FROM t_ctx WHERE key = 'si'),
  'trace contract resolves the generic read-only source route'
);

SELECT is(
  (fn_get_accounting_trace('SI', (SELECT id FROM t_ctx WHERE key = 'si'), NULL)->>'journal_entry_id')::uuid,
  (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si')),
  'trace contract resolves the linked journal entry'
);

INSERT INTO t_ctx
SELECT 'amort_schedule', fn_create_amortization_schedule(
  '22222222-2222-2222-2222-222222222225',
  '33333333-3333-3333-3333-333333333325',
  'Preview Test Amortization', 'One-period preview fixture',
  'aaaaaaaa-0000-0000-0000-000000000125',
  'aaaaaaaa-0000-0000-0000-000000000625',
  1200, '2026-07-10', 1
);

INSERT INTO t_ctx
SELECT 'amort_entry', id
FROM amortization_entries
WHERE schedule_id = (SELECT id FROM t_ctx WHERE key = 'amort_schedule');

INSERT INTO t_amort_preview
SELECT fn_preview_gl_impact('AMORT', (SELECT id FROM t_ctx WHERE key = 'amort_entry'));

SELECT is((SELECT payload->>'mode' FROM t_amort_preview), 'preview',
  'amortization entry returns an exact rollback preview');
SELECT is((SELECT status FROM amortization_entries
           WHERE id = (SELECT id FROM t_ctx WHERE key = 'amort_entry')),
  'pending', 'amortization preview rolls the schedule entry back to pending');
SELECT is((SELECT count(*)::int FROM journal_entries
           WHERE reference_doc_type = 'AMORT'
             AND reference_doc_id = (SELECT id FROM t_ctx WHERE key = 'amort_entry')),
  0, 'amortization preview persists no journal entry');
SELECT is((SELECT jsonb_array_length(payload->'lines') FROM t_amort_preview), 2,
  'amortization preview exposes both authoritative posting lines');
SELECT is((SELECT (payload->>'total_debit')::numeric FROM t_amort_preview), 1200.00::numeric,
  'amortization preview exposes the exact scheduled amount');

INSERT INTO t_ctx
SELECT 'amort_je', fn_post_amortization_entry((SELECT id FROM t_ctx WHERE key = 'amort_entry'));

SELECT results_eq(
  $q$
    SELECT reference_doc_type, reference_doc_id
    FROM journal_entries
    WHERE id = (SELECT id FROM t_ctx WHERE key = 'amort_je')
  $q$,
  $q$
    SELECT 'AMORT'::text, id
    FROM t_ctx
    WHERE key = 'amort_entry'
  $q$,
  'posted amortization journal carries its governed source type and entry id'
);

SELECT is(
  fn_get_accounting_trace(
    'AMORT', (SELECT id FROM t_ctx WHERE key = 'amort_entry'), NULL
  )->>'source_route',
  '/accounting-source?sourceType=AMORT&sourceId=' || (SELECT id::text FROM t_ctx WHERE key = 'amort_entry'),
  'schedule trace resolves to the individual amortization source evidence'
);

SELECT throws_like(
  format(
    $q$SELECT fn_get_accounting_trace('REVREC', %L, %L)$q$,
    (SELECT id FROM t_ctx WHERE key = 'amort_entry'),
    (SELECT id FROM t_ctx WHERE key = 'amort_je')
  ),
  '%source type does not match%',
  'trace rejects a journal/source type mismatch'
);

SELECT throws_like(
  format($q$
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, reference_doc_id, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      '22222222-2222-2222-2222-222222222225',
      '33333333-3333-3333-3333-333333333325',
      'DUP-SOURCE', '2026-07-10',
      (SELECT id FROM fiscal_periods WHERE company_id = '22222222-2222-2222-2222-222222222225'
       AND period_number = 7),
      'Duplicate', 'SI', %L, 'posted', 1, 1, auth.uid(), auth.uid()
    )
  $q$, (SELECT id FROM t_ctx WHERE key = 'si')),
  '%ux_journal_entries_live_source%',
  'source idempotency rejects a second live JE'
);

SELECT throws_like(
  format($q$
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, created_by, updated_by
    ) VALUES (
      %L, '22222222-2222-2222-2222-222222222225', 99,
      'aaaaaaaa-0000-0000-0000-000000000525', 'Invalid account',
      1, 0, auth.uid(), auth.uid()
    )
  $q$, (SELECT journal_entry_id FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'si'))),
  '%active postable account%',
  'all journal writers reject inactive posting accounts'
);

SELECT throws_like(
  $q$
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      '22222222-2222-2222-2222-222222222225',
      '33333333-3333-3333-3333-333333333325',
      'BAD-PERIOD', '2026-07-10',
      (SELECT id FROM fiscal_periods WHERE company_id = '22222222-2222-2222-2222-222222222225'
       AND period_number = 8),
      'Wrong period', 'MANUAL', 'posted', 1, 1, auth.uid(), auth.uid()
    )
  $q$,
  '%fiscal period does not match posting date%',
  'all journal writers use a period that covers the posting date'
);

SELECT throws_like(
  $q$
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, status,
      total_debit, total_credit, created_by, updated_by
    ) VALUES (
      '22222222-2222-2222-2222-222222222225',
      '33333333-3333-3333-3333-333333333325',
      'BAD-TYPE', '2026-07-10',
      (SELECT id FROM fiscal_periods WHERE company_id = '22222222-2222-2222-2222-222222222225'
       AND period_number = 7),
      'Unknown source', 'UNKNOWN', 'posted', 1, 1, auth.uid(), auth.uid()
    )
  $q$,
  '%journal_entries_reference_doc_type_fkey%',
  'unregistered posting source types are rejected'
);

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $q$SELECT fn_create_posted_journal_entry(
    '22222222-2222-2222-2222-222222222225',
    '33333333-3333-3333-3333-333333333325',
    'FORGED', '2026-07-10', 'Forged', 'MANUAL', NULL
  )$q$,
  '42501', NULL,
  'authenticated callers cannot invoke the internal JE mutation primitive'
);
RESET ROLE;

INSERT INTO t_ctx
SELECT 'locked_si', fn_save_sales_invoice(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222225',
    'branch_id', '33333333-3333-3333-3333-333333333325',
    'date', '2026-08-10',
    'customer_id', '55555555-5555-5555-5555-555555555525',
    'customer_name_snapshot', 'Preview Customer Inc',
    'customer_tin_snapshot', '444-555-666-025',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'August services',
    'quantity', 1,
    'unit_price', 1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000425'
  ))
);
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key = 'locked_si'));
UPDATE fiscal_periods SET is_locked = true
WHERE company_id = '22222222-2222-2222-2222-222222222225' AND period_number = 8;

SELECT throws_like(
  format($q$SELECT fn_preview_gl_impact('SI', %L)$q$,
    (SELECT id FROM t_ctx WHERE key = 'locked_si')),
  '%No open fiscal period%',
  'preview exposes the same locked-period rejection as posting'
);

SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key = 'locked_si')),
  'approved',
  'a failed preview leaves the source unchanged'
);

SELECT * FROM finish();
ROLLBACK;
