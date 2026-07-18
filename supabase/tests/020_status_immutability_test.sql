-- ══════════════════════════════════════════════════════════════════════════════
-- IMMUT-001 - Status-aware immutability guards (PXL-DA-011)
--
-- Proves that posted/approved documents, their lines, and their journal
-- entries reject direct tampering issued from a DIFFERENT transaction than
-- the one that created them (the PostgREST client surface: every REST call
-- runs in its own transaction), while controlled lifecycle RPCs — void,
-- credit memo apply — keep working across transactions, and no-change
-- full-payload re-saves are tolerated.
--
-- NOTE: unlike the other test files, this file COMMITs its fixtures — the
-- same-transaction construction exception would otherwise make every
-- tamper attempt look legitimate. A trigger-disabled, company-scoped teardown
-- at the end keeps repeated suite runs isolated.
-- Assertions run as postgres: the guards are triggers and fire beneath
-- RLS, so blocking here proves the control holds for ANY role.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(25);

-- ── Fixtures (committed below) ─────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111120', 'authenticated', 'authenticated',
        'immut-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

-- Session-level (not transaction-local) claims: they must survive the COMMIT.
SELECT set_config('request.jwt.claims',
  json_build_object('sub', '11111111-1111-1111-1111-111111111120',
                    'role', 'authenticated')::text, false);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222220', 'corporation',
        'Immutability Test Corp', 'Software Services', '111-222-333-020',
        'vat', 'calendar', 'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'immut-owner@test.local', 'Juan Dela Cruz', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333320', '22222222-2222-2222-2222-222222222220',
        'HO', 'Head Office', 'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444420',
        '22222222-2222-2222-2222-222222222220',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222220',
       '44444444-4444-4444-4444-444444444420',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000120', '22222222-2222-2222-2222-222222222220',
   '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000220', '22222222-2222-2222-2222-222222222220',
   '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000320', '22222222-2222-2222-2222-222222222220',
   '4010', 'Service Revenue',     'revenue',   'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222220',
        'aaaaaaaa-0000-0000-0000-000000000120',
        'aaaaaaaa-0000-0000-0000-000000000220',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222220',
       '33333333-3333-3333-3333-333333333320',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('SI', 'CM');

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('55555555-5555-5555-5555-555555555520',
        '22222222-2222-2222-2222-222222222220', 'CUST-020',
        'Immut Customer Inc', '444-555-666-020',
        'Customer HQ, Taguig', 'Customer HQ, Taguig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

-- Posted SI with its journal entry
INSERT INTO t_ctx SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '22222222-2222-2222-2222-222222222220',
    'branch_id',                 '33333333-3333-3333-3333-333333333320',
    'date',                      '2026-05-10',
    'customer_id',               '55555555-5555-5555-5555-555555555520',
    'customer_name_snapshot',    'Immut Customer Inc',
    'customer_tin_snapshot',     '444-555-666-020',
    'customer_address_snapshot', 'Customer HQ, Taguig'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000320'
  )));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));

INSERT INTO t_ctx SELECT 'si_je', je.id FROM journal_entries je
WHERE je.reference_doc_id = (SELECT id FROM t_ctx WHERE key='si')
  AND je.company_id = '22222222-2222-2222-2222-222222222220';

-- Approved CM (apply-from-approved is exercised cross-transaction below)
INSERT INTO t_ctx SELECT 'cm', fn_save_credit_memo(NULL,
  jsonb_build_object(
    'company_id',             '22222222-2222-2222-2222-222222222220',
    'branch_id',              '33333333-3333-3333-3333-333333333320',
    'customer_id',            '55555555-5555-5555-5555-555555555520',
    'customer_name_snapshot', 'Immut Customer Inc',
    'customer_tin_snapshot',  '444-555-666-020',
    'cm_date',                '2026-05-12',
    'reason_code_id',         (SELECT id FROM ref_reason_codes WHERE code = 'CM_OVERBILLING')
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Overbilling adjustment',
    'quantity',           1,
    'unit_price',         1000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000320'
  )),
  'approved');

-- Approved quotation (direct-write document family)
INSERT INTO sales_quotations (id, company_id, branch_id, customer_id,
                              customer_name_snapshot, quotation_number,
                              quotation_date, validity_date, total_amount,
                              status, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666620', '22222222-2222-2222-2222-222222222220',
        '33333333-3333-3333-3333-333333333320', '55555555-5555-5555-5555-555555555520',
        'Immut Customer Inc', 'QT-IMMUT-20', '2026-05-11', '2026-06-11', 5000,
        'draft', auth.uid(), auth.uid());
INSERT INTO sales_quotation_lines (quotation_id, company_id, description,
                                   quantity, unit_price, discount_amount,
                                   net_amount, line_number, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666620', '22222222-2222-2222-2222-222222222220',
        'Quoted services', 1, 5000, 0, 5000, 1, auth.uid(), auth.uid());
UPDATE sales_quotations SET status = 'approved'
WHERE id = '66666666-6666-6666-6666-666666666620';

-- ── 1. Same-transaction construction is recognized while still open ────────────
SELECT ok(
  fn_row_written_by_current_txn(
    (SELECT xmin::text::bigint FROM journal_entries
     WHERE id = (SELECT id FROM t_ctx WHERE key='si_je'))),
  'a journal entry created by this open transaction is recognized as ours');

COMMIT;

-- ══════════════════════════════════════════════════════════════════════════════
-- From here every statement runs in its own transaction, exactly like a
-- PostgREST client call.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 2-7. Posted JE and its lines reject tampering ──────────────────────────────
SELECT throws_like(
  $q$UPDATE journal_entry_lines SET debit_amount = debit_amount + 100
     WHERE je_id = (SELECT id FROM t_ctx WHERE key='si_je') AND line_number = 1$q$,
  '%cannot be changed%',
  'posted JE line amounts cannot be updated from another transaction');

SELECT throws_like(
  $q$DELETE FROM journal_entry_lines
     WHERE je_id = (SELECT id FROM t_ctx WHERE key='si_je')$q$,
  '%cannot be changed%',
  'posted JE lines cannot be deleted');

SELECT throws_like(
  $q$INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id,
       description, debit_amount, credit_amount, created_by, updated_by)
     VALUES ((SELECT id FROM t_ctx WHERE key='si_je'),
             '22222222-2222-2222-2222-222222222220', 99,
             'aaaaaaaa-0000-0000-0000-000000000120', 'injected', 100, 0,
             auth.uid(), auth.uid())$q$,
  '%cannot be changed%',
  'lines cannot be injected into a posted JE');

SELECT throws_like(
  $q$UPDATE journal_entries SET description = 'tampered'
     WHERE id = (SELECT id FROM t_ctx WHERE key='si_je')$q$,
  '%immutable%',
  'posted JE description is immutable');

SELECT throws_like(
  $q$UPDATE journal_entries SET total_debit = total_debit + 100
     WHERE id = (SELECT id FROM t_ctx WHERE key='si_je')$q$,
  '%immutable%',
  'posted JE totals are immutable');

SELECT throws_like(
  $q$DELETE FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='si_je')$q$,
  '%cannot be deleted%',
  'posted JE cannot be deleted');

-- ── 8. Committed rows are no longer "ours" ─────────────────────────────────────
SELECT ok(
  NOT fn_row_written_by_current_txn(
    (SELECT xmin::text::bigint FROM journal_entries
     WHERE id = (SELECT id FROM t_ctx WHERE key='si_je'))),
  'a committed journal entry row is not recognized as written by this transaction');

-- ── 9-12. Posted SI header: business fields frozen, no-op re-save tolerated ────
SELECT throws_like(
  $q$UPDATE sales_invoices SET total_amount = total_amount + 500
     WHERE id = (SELECT id FROM t_ctx WHERE key='si')$q$,
  '%immutable%',
  'posted SI total cannot change');

SELECT throws_like(
  $q$UPDATE sales_invoices SET customer_name_snapshot = 'Someone Else'
     WHERE id = (SELECT id FROM t_ctx WHERE key='si')$q$,
  '%immutable%',
  'posted SI customer snapshot cannot change');

SELECT throws_like(
  $q$DELETE FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')$q$,
  '%cannot be deleted%',
  'posted SI cannot be deleted');

SELECT lives_ok(
  $q$UPDATE sales_invoices
     SET total_amount = total_amount, date = date, customer_id = customer_id
     WHERE id = (SELECT id FROM t_ctx WHERE key='si')$q$,
  'a full-payload re-save with unchanged values is tolerated');

-- ── 13-15. Controlled void still works and reverses the JE ─────────────────────
SELECT lives_ok(
  $q$SELECT fn_void_sales_invoice(
       (SELECT id FROM t_ctx WHERE key='si'),
       (SELECT id FROM void_reason_codes WHERE code = 'WRONG_AMOUNT'),
       'IMMUT-001 controlled void')$q$,
  'controlled void RPC still works on a guarded posted SI');

SELECT is(
  (SELECT status FROM sales_invoices WHERE id = (SELECT id FROM t_ctx WHERE key='si')),
  'cancelled',
  'voided SI reaches cancelled through the controlled path');

SELECT is(
  (SELECT status FROM journal_entries WHERE id = (SELECT id FROM t_ctx WHERE key='si_je')),
  'reversed',
  'void reverses the original JE through the allowed status transition');

-- ── 16-19. Approved CM: lines and business fields frozen ───────────────────────
SELECT throws_like(
  $q$INSERT INTO credit_memo_lines (credit_memo_id, company_id, line_number,
       description, quantity, unit_price, net_amount, vat_amount, total_amount,
       created_by, updated_by)
     VALUES ((SELECT id FROM t_ctx WHERE key='cm'),
             '22222222-2222-2222-2222-222222222220', 99,
             'injected', 1, 999, 999, 0, 999, auth.uid(), auth.uid())$q$,
  '%cannot be changed%',
  'lines cannot be injected into an approved CM');

SELECT throws_like(
  $q$UPDATE credit_memo_lines SET net_amount = net_amount + 100
     WHERE credit_memo_id = (SELECT id FROM t_ctx WHERE key='cm')$q$,
  '%cannot be changed%',
  'approved CM line amounts cannot be updated');

SELECT throws_like(
  $q$DELETE FROM credit_memo_lines
     WHERE credit_memo_id = (SELECT id FROM t_ctx WHERE key='cm')$q$,
  '%cannot be changed%',
  'approved CM lines cannot be deleted directly');

SELECT throws_like(
  $q$UPDATE credit_memos SET customer_name_snapshot = 'Someone Else'
     WHERE id = (SELECT id FROM t_ctx WHERE key='cm')$q$,
  '%immutable%',
  'approved CM business fields are immutable');

-- ── 20-22. CM apply (approved → applied) still works cross-transaction ─────────
SELECT lives_ok(
  $q$SELECT fn_save_credit_memo(
       (SELECT id FROM t_ctx WHERE key='cm'),
       jsonb_build_object(
         'company_id',             '22222222-2222-2222-2222-222222222220',
         'branch_id',              '33333333-3333-3333-3333-333333333320',
         'customer_id',            '55555555-5555-5555-5555-555555555520',
         'customer_name_snapshot', 'Immut Customer Inc',
         'customer_tin_snapshot',  '444-555-666-020',
         'cm_date',                '2026-05-12',
         'reason_code_id',         (SELECT id FROM ref_reason_codes WHERE code = 'CM_OVERBILLING')
       ),
       jsonb_build_array(jsonb_build_object(
         'description',        'Overbilling adjustment',
         'quantity',           1,
         'unit_price',         1000,
         'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
         'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000320'
       )),
       'applied')$q$,
  'applying an approved CM through the RPC still works');

SELECT is(
  (SELECT status FROM credit_memos WHERE id = (SELECT id FROM t_ctx WHERE key='cm')),
  'applied',
  'CM reaches applied through the controlled path');

SELECT ok(
  (SELECT journal_entry_id IS NOT NULL FROM credit_memos
   WHERE id = (SELECT id FROM t_ctx WHERE key='cm')),
  'applied CM is linked to its journal entry');

-- ── 23-25. Approved quotation frozen (direct-write document family) ────────────
SELECT throws_like(
  $q$UPDATE sales_quotation_lines SET unit_price = 1
     WHERE quotation_id = '66666666-6666-6666-6666-666666666620'$q$,
  '%cannot be changed%',
  'approved quotation lines cannot be updated');

SELECT throws_like(
  $q$UPDATE sales_quotations SET total_amount = 1
     WHERE id = '66666666-6666-6666-6666-666666666620'$q$,
  '%immutable%',
  'approved quotation total cannot change');

SELECT throws_like(
  $q$DELETE FROM sales_quotations
     WHERE id = '66666666-6666-6666-6666-666666666620'$q$,
  '%cannot be deleted%',
  'approved quotation cannot be deleted');

SELECT * FROM finish();

SET session_replication_role = replica;
DO $$
DECLARE
  v_table RECORD;
BEGIN
  FOR v_table IN
    SELECT DISTINCT c.table_schema, c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema
     AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_schema = 'public'
      AND c.column_name = 'company_id'
      AND c.table_name <> 'companies'
    ORDER BY c.table_name
  LOOP
    EXECUTE format(
      'DELETE FROM %I.%I WHERE company_id = %L',
      v_table.table_schema,
      v_table.table_name,
      '22222222-2222-2222-2222-222222222220'
    );
  END LOOP;
END;
$$;
DELETE FROM companies
WHERE id = '22222222-2222-2222-2222-222222222220';
DELETE FROM auth.users
WHERE id = '11111111-1111-1111-1111-111111111120';
SET session_replication_role = origin;
