-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P5A-001 — Surface Closure (Posting Engine Phase P5.0)
--
-- Certifies the three approved P5.0 closures and proves each is non-vacuous:
--   A. the internal persistence helper fn_add_posting_line is no longer executable
--      by `authenticated`;
--   B. no GL-writing function is executable by `anon` (PUBLIC grants removed), while
--      every legitimate caller keeps exactly the privilege it had;
--   C. six accounting-owned DERIVED tables deny all `authenticated` writes, so their
--      only writers are the SECURITY DEFINER posting functions that own them.
--
-- WHAT THIS IS NOT
--   This is NOT the Kernel Totality Guard. No origin control exists after P5.0: any
--   in-database SECURITY DEFINER function, migration, or seed can still write the
--   ledger. P5.0 closes the EXTERNAL (PostgREST / `authenticated` / `anon`) surface
--   only. posting_origin is not enforced, no posting writer is migrated, and nothing
--   is whitelisted. Those remain P5.1.
--
-- DELIBERATE EXCLUSION, ASSERTED SO IT CANNOT BE MISREAD AS AN OVERSIGHT
--   bank_recon_items and book_tax_reconciliation were investigation candidates but are
--   written DIRECTLY by the UI (BankReconciliationPage / BookToTaxReconciliationPage),
--   so their writers are not all SECURITY DEFINER and closing them would break working
--   features. Section G pins their still-open state.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(45);

CREATE TEMP VIEW v_closed_table AS
SELECT unnest(ARRAY['stock_balances','inventory_cost_layers','inventory_transactions',
                    'asset_depreciation_entries','amortization_entries',
                    'revenue_recognition_entries']) AS tbl;

CREATE TEMP VIEW v_client_entry AS
SELECT unnest(ARRAY[
  'public.fn_close_fiscal_year(uuid, uuid, date)',
  'public.fn_dispose_fixed_asset(jsonb)',
  'public.fn_post_check_voucher(uuid)',
  'public.fn_post_manual_je(uuid, uuid, date, text, text, boolean, jsonb, text)',
  'public.fn_post_receipt(uuid)',
  'public.fn_post_sales_invoice(uuid)',
  'public.fn_post_vendor_bill(uuid)',
  'public.fn_record_impairment(jsonb)',
  'public.fn_register_fixed_asset(jsonb)',
  'public.fn_save_cash_sale(jsonb, jsonb, numeric)']) AS sig;

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — The internal persistence helper is closed to `authenticated`
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  NOT has_function_privilege('authenticated',
    'public.fn_add_posting_line(uuid,integer,uuid,text,numeric,numeric,uuid,uuid,uuid,uuid,uuid,uuid)', 'EXECUTE'),
  'fn_add_posting_line is no longer executable by authenticated');                    -- 1

SELECT ok(
  NOT has_function_privilege('anon',
    'public.fn_add_posting_line(uuid,integer,uuid,text,numeric,numeric,uuid,uuid,uuid,uuid,uuid,uuid)', 'EXECUTE'),
  'fn_add_posting_line is not executable by anon');                                   -- 2

-- The owner path is untouched: posting writers are SECURITY DEFINER and call the helper
-- as the function owner, so closing the caller-facing grant cannot affect them.
SELECT ok(
  has_function_privilege('postgres',
    'public.fn_add_posting_line(uuid,integer,uuid,text,numeric,numeric,uuid,uuid,uuid,uuid,uuid,uuid)', 'EXECUTE'),
  'the owner retains EXECUTE — the SECURITY DEFINER posting path is intact');         -- 3

-- Every other internal journal/tax persistence helper stays closed too.
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('fn_create_posted_journal_entry','fn_finalize_journal_entry',
                        'fn_add_posting_line','fn_add_posting_line_push',
                        'fn_add_posting_line_core_20260718','fn_add_sales_invoice_posting_line',
                        'fn_add_tax_detail','fn_reverse_posted_journal_entry',
                        'fn_reverse_tax_detail_entries')
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  0, 'no internal journal or tax-ledger persistence helper is callable by authenticated'); -- 4

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — No GL writer is reachable by `anon`; legitimate callers keep parity
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosrc ~ '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_entr'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')),
  0, 'zero GL-writing functions are executable by anon');                             -- 5

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosrc ~ '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_entr'
      AND p.proacl::text ~ '(^|,)=X/'),
  0, 'no GL-writing function retains a PUBLIC EXECUTE grant');                        -- 6

-- Capability parity: the ten client entry points keep authenticated AND service_role.
SELECT is(
  (SELECT count(*)::int FROM v_client_entry WHERE NOT has_function_privilege('authenticated', sig, 'EXECUTE')),
  0, 'all ten client entry points remain executable by authenticated (no capability lost)'); -- 7

SELECT is(
  (SELECT count(*)::int FROM v_client_entry WHERE NOT has_function_privilege('service_role', sig, 'EXECUTE')),
  0, 'all ten client entry points remain executable by service_role (status quo preserved)'); -- 8

SELECT is(
  (SELECT count(*)::int FROM v_client_entry WHERE has_function_privilege('anon', sig, 'EXECUTE')),
  0, 'none of the ten client entry points is executable by anon');                    -- 9

-- Kernel indirection means the client entry points no longer contain raw ledger SQL.
-- Pin the same frozen public capability surface by OID instead of source-text shape.
SELECT set_eq(
  $$SELECT p.proname::text
      FROM v_client_entry v
      JOIN pg_proc p ON p.oid=(v.sig::regprocedure)::oid
     WHERE has_function_privilege('authenticated', p.oid, 'EXECUTE')$$,
  $$VALUES ('fn_close_fiscal_year'),('fn_dispose_fixed_asset'),('fn_post_check_voucher'),
           ('fn_post_manual_je'),('fn_post_receipt'),('fn_post_sales_invoice'),
           ('fn_post_vendor_bill'),('fn_record_impairment'),('fn_register_fixed_asset'),
           ('fn_save_cash_sale')$$,
  'the authenticated posting capability surface remains exactly the ten client entry points'); -- 10

-- Trigger functions: unreachable by every caller role, yet their triggers survive.
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_link_fixed_asset_journal_source',
                        'fn_link_purchase_return_journal_source',
                        'fn_link_schedule_journal_source')
      AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
        OR has_function_privilege('anon', p.oid, 'EXECUTE'))),
  0, 'the three journal-linking trigger functions are unreachable by anon and authenticated'); -- 11

SELECT is(
  (SELECT count(*)::int FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE NOT t.tgisinternal
      AND p.proname IN ('fn_link_fixed_asset_journal_source',
                        'fn_link_purchase_return_journal_source',
                        'fn_link_schedule_journal_source')),
  7, 'all seven triggers using those functions still exist (revoking EXECUTE does not unwire them)'); -- 12

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Derived accounting tables: structural policy shape
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM v_closed_table t
    WHERE NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                       WHERE n.nspname='public' AND c.relname=t.tbl AND c.relrowsecurity)),
  0, 'RLS remains enabled on all six closed tables');                                 -- 13

-- A write policy denies unconditionally when every expression it actually carries is
-- `false`; INSERT carries only WITH CHECK and DELETE only USING, so an absent
-- expression is normalised to 'false' rather than treated as a failure.
SELECT is(
  (SELECT count(*)::int FROM v_closed_table t JOIN pg_policies p
      ON p.schemaname='public' AND p.tablename=t.tbl AND p.cmd<>'SELECT'
    WHERE coalesce(p.qual,'false') <> 'false' OR coalesce(p.with_check,'false') <> 'false'),
  0, 'every write policy on the six tables denies unconditionally');                  -- 14

SELECT is(
  (SELECT count(*)::int FROM v_closed_table t JOIN pg_policies p
      ON p.schemaname='public' AND p.tablename=t.tbl AND p.cmd<>'SELECT'),
  18, 'each of the six tables carries exactly three explicit deny-all write policies'); -- 15

SELECT is(
  (SELECT count(*)::int FROM v_closed_table t
    WHERE NOT EXISTS (SELECT 1 FROM pg_policies p
                       WHERE p.schemaname='public' AND p.tablename=t.tbl AND p.cmd='SELECT')),
  0, 'the membership-scoped SELECT policy is preserved on every closed table');       -- 16

-- Regression guard: P5.0 must not have touched the ledger's own policy set.
SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename IN ('journal_entries','journal_entry_lines')),
  2, 'journal_entries and journal_entry_lines still carry exactly their two SELECT policies'); -- 17

SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename='tax_detail_entries'),
  4, 'the certified tax_detail_entries policy set is unchanged');                     -- 18

-- Ownership premise: every writer of the six tables really is SECURITY DEFINER, so the
-- denial cannot strand a legitimate path.
SELECT is(
  (SELECT count(*)::int FROM v_closed_table t
     JOIN pg_proc p ON p.prosrc ~ ('(INSERT INTO|UPDATE|DELETE FROM)\s+'||t.tbl||'\M')
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE NOT p.prosecdef),
  0, 'every function writing a closed table is SECURITY DEFINER');                    -- 19

-- ══════════════════════════════════════════════════════════════════════════════
-- Fixture — a real member of a real company with real inventory
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f500000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p5a-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f500000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f500000-0000-0000-0000-0000000000b1', 'corporation', 'P5A Surface Corp',
        'Trading', '392-000-001-00000', 'vat', 'calendar',
        'S St', 'S Bldg', 'Makati', 'Metro Manila', '1200',
        'p5a-owner@test.local', 'S Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0f500000-0000-0000-0000-0000000000b2', '0f500000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'S St', 'S Bldg', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f500000-0000-0000-0000-0000000000f1', '0f500000-0000-0000-0000-0000000000b1',
        'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '0f500000-0000-0000-0000-0000000000b1', '0f500000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES
  ('0f500000-0000-0000-0000-0000000000a1', '0f500000-0000-0000-0000-0000000000b1', '1200', 'Accounts Receivable', 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f500000-0000-0000-0000-0000000000a2', '0f500000-0000-0000-0000-0000000000b1', '2100', 'Output VAT Payable',  'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f500000-0000-0000-0000-0000000000a3', '0f500000-0000-0000-0000-0000000000b1', '4010', 'Sales Revenue',       'revenue',   'credit', true, true, auth.uid(), auth.uid()),
  ('0f500000-0000-0000-0000-0000000000a4', '0f500000-0000-0000-0000-0000000000b1', '1400', 'Inventory',           'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('0f500000-0000-0000-0000-0000000000a5', '0f500000-0000-0000-0000-0000000000b1', '5010', 'Cost of Goods Sold',  'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id, created_by, updated_by)
VALUES ('0f500000-0000-0000-0000-0000000000b1',
        '0f500000-0000-0000-0000-0000000000a1', '0f500000-0000-0000-0000-0000000000a2',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number, is_active, created_by, updated_by)
SELECT '0f500000-0000-0000-0000-0000000000b1', '0f500000-0000-0000-0000-0000000000b2',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code = 'SI';

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('0f500000-0000-0000-0000-0000000000c1', '0f500000-0000-0000-0000-0000000000b1', 'CUST-P5A',
        'P5A Customer Inc', '391-000-001-00000', 'Customer HQ', 'Customer HQ', auth.uid(), auth.uid());

INSERT INTO item_categories (id, company_id, category_code, category_name)
VALUES ('0f500000-0000-0000-0000-0000000000e1', '0f500000-0000-0000-0000-0000000000b1', 'CAT', 'General');
INSERT INTO units_of_measure (id, company_id, uom_code, description)
VALUES ('0f500000-0000-0000-0000-0000000000e2', '0f500000-0000-0000-0000-0000000000b1', 'PC', 'Piece');
INSERT INTO warehouses (id, company_id, warehouse_code, warehouse_name, branch_id, created_by, updated_by)
VALUES ('0f500000-0000-0000-0000-0000000000e3', '0f500000-0000-0000-0000-0000000000b1', 'WH1', 'Main WH',
        '0f500000-0000-0000-0000-0000000000b2', auth.uid(), auth.uid());
INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   inventory_account_id, cogs_account_id, costing_method, created_by, updated_by)
VALUES ('0f500000-0000-0000-0000-0000000000e4', '0f500000-0000-0000-0000-0000000000b1',
        'ITEM-P5A', 'Traded Item', 'inventory_item',
        '0f500000-0000-0000-0000-0000000000e1', '0f500000-0000-0000-0000-0000000000e2',
        '0f500000-0000-0000-0000-0000000000a4', '0f500000-0000-0000-0000-0000000000a5',
        'weighted_average', auth.uid(), auth.uid());
INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, wac_unit_cost, total_cost)
VALUES ('0f500000-0000-0000-0000-0000000000b1', '0f500000-0000-0000-0000-0000000000e3',
        '0f500000-0000-0000-0000-0000000000e4', 100, 50, 5000);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — Authenticated write probes, proven non-vacuous
--
-- Non-vacuity has two halves. First, the probing identity must be a genuine, readable
-- member — otherwise a denial proves nothing but absent membership. Second, the same
-- rows must remain writable through the SECURITY DEFINER path (Section E).
--
-- INSERT is denied by WITH CHECK (false), which RAISES. UPDATE and DELETE are denied by
-- USING (false), which silently filters every candidate row: the statement is legal and
-- succeeds, but touches nothing. The correct proof for those is therefore not an error
-- but UNCHANGED STATE, asserted after the attempt.
-- ══════════════════════════════════════════════════════════════════════════════
CREATE TEMP TABLE t_closed_pre AS
SELECT (SELECT qty_on_hand FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1') AS sb_qty,
       (SELECT total_cost  FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1') AS sb_cost,
       (SELECT wac_unit_cost FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1') AS sb_wac,
       (SELECT count(*) FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1') AS sb_rows;

SET LOCAL ROLE authenticated;

SELECT ok(is_company_member('0f500000-0000-0000-0000-0000000000b1'),
  'the probing identity is a genuine company member (denials below are not vacuous)');   -- 20

SELECT is(
  (SELECT count(*)::int FROM stock_balances
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  1, 'and it can READ the closed table — only writing is denied');                       -- 21

-- ── INSERT: denied by WITH CHECK (false), which raises 42501 ──────────────────
SELECT throws_ok(
  $$INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, wac_unit_cost, total_cost)
    VALUES ('0f500000-0000-0000-0000-0000000000b1','0f500000-0000-0000-0000-0000000000e3',
            '0f500000-0000-0000-0000-0000000000e4', 1, 1, 1)$$,
  '42501', NULL, 'authenticated cannot INSERT stock_balances');                          -- 22

SELECT throws_ok(
  $$INSERT INTO inventory_transactions (company_id, warehouse_id, item_id, transaction_type,
      transaction_date, qty, unit_cost, total_cost, qty_on_hand_after, reference_doc_type,
      reference_doc_id, created_by)
    VALUES ('0f500000-0000-0000-0000-0000000000b1','0f500000-0000-0000-0000-0000000000e3',
            '0f500000-0000-0000-0000-0000000000e4','issue', '2026-03-01', -1, 1, -1, 99,
            'SI', '0f500000-0000-0000-0000-0000000000c1', auth.uid())$$,
  '42501', NULL, 'authenticated cannot INSERT inventory_transactions');                  -- 23

SELECT throws_ok(
  $$INSERT INTO inventory_cost_layers (company_id, warehouse_id, item_id, layer_date,
      original_qty, qty_remaining, unit_cost)
    VALUES ('0f500000-0000-0000-0000-0000000000b1','0f500000-0000-0000-0000-0000000000e3',
            '0f500000-0000-0000-0000-0000000000e4','2026-03-01', 10, 10, 5)$$,
  '42501', NULL, 'authenticated cannot INSERT inventory_cost_layers');                   -- 24

SELECT throws_ok(
  $$INSERT INTO asset_depreciation_entries (company_id, asset_id, period_number, entry_date,
      depreciation_amount, accumulated_depr_after, net_book_value_after, status)
    VALUES ('0f500000-0000-0000-0000-0000000000b1','0f500000-0000-0000-0000-0000000000e4',
            1, '2026-03-01', 100, 100, 900, 'posted')$$,
  '42501', NULL, 'authenticated cannot INSERT asset_depreciation_entries');              -- 25

-- ── UPDATE / DELETE: legal statements that must touch nothing ─────────────────
SELECT lives_ok($$
  UPDATE stock_balances SET qty_on_hand = qty_on_hand + 500
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1';
  UPDATE stock_balances SET wac_unit_cost = wac_unit_cost * 10, total_cost = total_cost * 10
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1';
  DELETE FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1';
  UPDATE inventory_transactions SET total_cost = total_cost * 10
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1';
  UPDATE inventory_cost_layers SET qty_remaining = qty_remaining + 50
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1';
  UPDATE asset_depreciation_entries SET depreciation_amount = 0
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1';
  UPDATE amortization_entries SET status = 'posted'
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1';
  UPDATE revenue_recognition_entries SET status = 'posted'
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1';
$$, 'the derived-table UPDATE/DELETE battery is denied by row filtering');             -- 26

RESET ROLE;

SELECT is(
  (SELECT qty_on_hand FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  (SELECT sb_qty FROM t_closed_pre),
  'stock_balances quantity is unchanged after the UPDATE attempt');                      -- 27

SELECT is(
  (SELECT wac_unit_cost || '/' || total_cost FROM stock_balances
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  (SELECT sb_wac || '/' || sb_cost FROM t_closed_pre),
  'stock_balances valuation is unchanged — the COGS tamper path is closed');             -- 28

SELECT is(
  (SELECT count(*) FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  (SELECT sb_rows FROM t_closed_pre),
  'stock_balances survived the DELETE attempt');                                         -- 29

SELECT is(
  (SELECT count(*)::int FROM inventory_transactions
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  0, 'no inventory movement was created or altered by the member');                      -- 30

SELECT is(
  (SELECT count(*)::int FROM inventory_cost_layers
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1' AND qty_remaining > 0),
  0, 'no cost layer was created or altered by the member');                              -- 31

SELECT is(
  (SELECT count(*)::int FROM asset_depreciation_entries
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1')
  + (SELECT count(*)::int FROM amortization_entries
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1')
  + (SELECT count(*)::int FROM revenue_recognition_entries
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  0, 'no depreciation, amortization, or revenue-recognition entry was authored by the member'); -- 32

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  0, 'the ledger was untouched — it was already closed and stays closed');               -- 33

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — SECURITY DEFINER proof + accounting equality
--
-- The same rows the member could not touch are written normally by the posting writer,
-- and the accounting output is exactly the certified result. This is what makes every
-- denial above a closure of an ILLEGITIMATE path rather than a broken feature.
-- ══════════════════════════════════════════════════════════════════════════════
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
CREATE TEMP TABLE t_pre AS
SELECT (SELECT qty_on_hand FROM stock_balances
         WHERE company_id='0f500000-0000-0000-0000-0000000000b1') AS qty,
       (SELECT count(*) FROM inventory_transactions
         WHERE company_id='0f500000-0000-0000-0000-0000000000b1') AS itx;

INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','0f500000-0000-0000-0000-0000000000b1',
    'branch_id', '0f500000-0000-0000-0000-0000000000b2',
    'date','2026-03-10',
    'customer_id','0f500000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot','P5A Customer Inc',
    'customer_tin_snapshot','391-000-001-00000',
    'customer_address_snapshot','Customer HQ',
    'warehouse_id','0f500000-0000-0000-0000-0000000000e3'),
  jsonb_build_array(jsonb_build_object(
    'description','Traded goods','quantity',10,'unit_price',1000,
    'item_id','0f500000-0000-0000-0000-0000000000e4',
    'warehouse_id','0f500000-0000-0000-0000-0000000000e3',
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
    'revenue_account_id','0f500000-0000-0000-0000-0000000000a3')));
SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
SELECT lives_ok(
  $$SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'))$$,
  'the SECURITY DEFINER posting writer still posts through the closed tables');          -- 34

-- The full journal, unchanged: AR / Revenue / Output VAT / COGS / Inventory.
SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount
       FROM journal_entry_lines jel JOIN chart_of_accounts coa ON coa.id = jel.account_id
      WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices
                          WHERE id=(SELECT id FROM t_ctx WHERE key='si'))
      ORDER BY jel.line_number$q$,
  $$VALUES (1, '1200'::text, 11200.00::numeric, 0.00::numeric),
           (2, '4010'::text, 0.00::numeric, 10000.00::numeric),
           (3, '2100'::text, 0.00::numeric, 1200.00::numeric),
           (4, '5010'::text, 500.00::numeric, 0.00::numeric),
           (5, '1400'::text, 0.00::numeric, 500.00::numeric)$$,
  'journal lines, accounts, order, and amounts are the certified output');               -- 35

SELECT is(
  (SELECT total_debit || '/' || total_credit || '/' || status FROM journal_entries
    WHERE id = (SELECT journal_entry_id FROM sales_invoices WHERE id=(SELECT id FROM t_ctx WHERE key='si'))),
  '11700.00/11700.00/posted', 'journal header totals and status are unchanged');         -- 36

-- Inventory impact: the writer moved exactly what it should through the closed tables.
SELECT is(
  (SELECT qty_on_hand FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  (SELECT qty - 10 FROM t_pre),
  'stock_balances was decremented by the posting writer (10 units issued)');             -- 37

SELECT is(
  (SELECT total_cost FROM stock_balances WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  4500.00::numeric, 'stock_balances valuation was maintained by the posting writer');    -- 38

SELECT is(
  (SELECT count(*)::int FROM inventory_transactions
    WHERE company_id='0f500000-0000-0000-0000-0000000000b1'),
  (SELECT itx + 1 FROM t_pre)::int,
  'the posting writer recorded exactly one inventory movement');                         -- 39

SELECT is(
  (SELECT sum(tax_amount) FROM tax_detail_entries
    WHERE source_doc_type='SI' AND source_doc_id=(SELECT id FROM t_ctx WHERE key='si')),
  1200.00::numeric, 'tax detail is unchanged');                                          -- 40

SELECT is(
  (SELECT count(*)::int FROM journal_entry_lines jel
     JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.id = (SELECT journal_entry_id FROM sales_invoices WHERE id=(SELECT id FROM t_ctx WHERE key='si'))
      AND jel.branch_id = '0f500000-0000-0000-0000-0000000000b2'),
  5, 'all five posted lines still carry the branch dimension');                          -- 41

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — Later-phase compatibility
-- ══════════════════════════════════════════════════════════════════════════════
-- P5.1 supersedes the original P5.0 phase boundary without weakening the certified
-- P5.0 external-surface closure.
SELECT is(
  (SELECT count(*)::int FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid='public.fn_guard_journal_kernel_origin()'::regprocedure
      AND t.tgrelid IN ('journal_entries'::regclass, 'journal_entry_lines'::regclass)),
  2, 'the later P5.1 observe-only guard coexists with the P5.0 surface closure');          -- 42

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.prosrc ~ 'INSERT INTO\s+journal_entries'
      AND p.proname <> 'fn_create_posted_journal_entry'),
  0, 'P5.1 drains forward header insertion without reopening the P5.0 surface');          -- 43

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION G — Deliberate exclusions, pinned so they read as decisions
-- ══════════════════════════════════════════════════════════════════════════════
-- These two remain member-writable because the UI writes them directly. Closing them
-- would break BankReconciliationPage and BookToTaxReconciliationPage. If a future change
-- makes their writers SECURITY DEFINER, this assertion fails and prompts the closure.
SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename IN ('bank_recon_items','book_tax_reconciliation')
      AND cmd <> 'SELECT' AND coalesce(with_check, qual) = 'is_company_member(company_id)'),
  5, 'bank_recon_items and book_tax_reconciliation remain member-writable by decision (UI writes them directly)'); -- 44

SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename='fiscal_periods' AND cmd <> 'SELECT'),
  3, 'fiscal_periods keeps its MDP-03 permission-gated write policies (period lock is not a P5.0 item)'); -- 45

SELECT * FROM finish();
ROLLBACK;
