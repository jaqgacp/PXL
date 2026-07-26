-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P3D-001 — GL Preview Resolver Convergence (frozen P3 spec §5, O-C)
--
-- Certifies that GL-impact preview obtains posting accounts from the same certified
-- resolver actual posting uses, closing COA certification observation O2. This is the
-- resolver-convergence subset only — shared physical Plan-builder identity,
-- source_fingerprint equivalence, and the whole-census preview≡actual grid remain P8.
--
-- Census result the certification rests on: only the Sales Invoice preview projects
-- posting accounts of its own. Every other supported type previews by executing its REAL
-- posting writer inside a subtransaction and rolling it back, so those paths already
-- resolve exactly as actual posting does; fn_gl_impact_payload renders an already-posted
-- journal and reads configuration only to derive a descriptive provenance label.
--
-- Structural proof is combined with REAL preview execution against a live invoice:
-- projected preview accounts are compared to the accounts the actual posting writer
-- resolves AND to the accounts the posted journal ends up carrying.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(38);

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — Preview census (inventory is complete and pinned)
-- ══════════════════════════════════════════════════════════════════════════════
SELECT set_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname ~ 'preview|gl_impact'$$,
  $$VALUES ('fn_gl_impact_payload'),('fn_preview_gl_impact'),('fn_preview_gl_impact_core'),
           ('fn_preview_sales_invoice_gl_impact'),('fn_preview_sales_invoice_gl_impact_aud053_core')$$,
  'the GL-preview function inventory is exactly the five censused functions');          -- 1

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname ~ 'preview|gl_impact'
    GROUP BY p.proname HAVING count(*) > 1),
  NULL, 'no GL-preview function is overloaded (unambiguous resolution)');               -- 2

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — The migrated function: resolver in, direct config resolution out
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT p.prosrc ~ 'fn_resolve_posting_account' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_sales_invoice_gl_impact_aud053_core'),
  'the SI preview core resolves through the certified adapter');                        -- 3

SELECT is(
  (SELECT (SELECT count(*)::int FROM regexp_matches(p.prosrc, 'v_cfg\.\w+ AS account_id', 'g'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_sales_invoice_gl_impact_aud053_core'),
  0, 'no projected preview account_id is derived directly from company_accounting_config'); -- 4

SELECT ok(
  (SELECT p.prosrc ~ 'AR_TRADE' AND p.prosrc ~ 'VAT_OUTPUT'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_sales_invoice_gl_impact_aud053_core'),
  'the SI preview core uses the same AR_TRADE and VAT_OUTPUT keys as actual posting');   -- 5

-- As-of date: preview must resolve on the same expression actual posting uses.
SELECT ok(
  (SELECT p.prosrc ~ $re$fn_resolve_posting_account\(v_rec\.company_id, 'AR_TRADE', v_rec\.date$re$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_sales_invoice_gl_impact_aud053_core'),
  'preview resolves AR_TRADE as of the invoice date');                                  -- 6
SELECT ok(
  (SELECT p.prosrc ~ $re$fn_resolve_posting_account\(v_rec\.company_id, 'VAT_OUTPUT', v_rec\.date$re$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_sales_invoice_gl_impact_aud053_core'),
  'preview resolves VAT_OUTPUT as of the invoice date');                                -- 7
SELECT ok(
  (SELECT p.prosrc ~ $re$fn_resolve_posting_account\(v_rec\.company_id, 'AR_TRADE', v_rec\.date$re$
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_sales_invoice'),
  'actual posting resolves AR_TRADE as of the same invoice date (as-of parity)');        -- 8

-- Every preview consumer must go through the adapter, never fn_resolve_account directly.
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname ~ 'preview|gl_impact'
      AND p.prosrc ~ '(?<!posting_)fn_resolve_account\s*\('),
  0, 'no preview function calls fn_resolve_account directly, bypassing the adapter');    -- 9

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Paths certified UNCHANGED (documented ownership models)
-- ══════════════════════════════════════════════════════════════════════════════
-- fn_gl_impact_payload renders a posted journal; every configuration reference is a
-- comparison against an already-resolved line account, i.e. a provenance label.
-- Every cfg. reference is either the join key or a `WHEN jel.account_id = cfg.x`
-- provenance comparison; none produces an account value.
SELECT is(
  (SELECT (SELECT count(*)::int FROM regexp_matches(p.prosrc, 'cfg\.\w+', 'g'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_gl_impact_payload'),
  (SELECT (SELECT count(*)::int FROM regexp_matches(p.prosrc, 'WHEN jel\.account_id = cfg\.\w+', 'g'))
         + (SELECT count(*)::int FROM regexp_matches(p.prosrc, 'cfg\.company_id', 'g'))
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_gl_impact_payload'),
  'every config read in fn_gl_impact_payload is a provenance comparison or the join key'); -- 10

SELECT ok(
  (SELECT p.prosrc !~ 'fn_resolve' AND p.prosrc ~ 'journal_entry_lines'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_gl_impact_payload'),
  'fn_gl_impact_payload resolves no account — it renders posted journal lines');          -- 11

-- The non-SI routes preview by executing the real writer and rolling it back.
SELECT ok(
  (SELECT p.prosrc ~ '__PXL_GL_PREVIEW_ROLLBACK__' AND p.prosrc ~ 'fn_post_vendor_bill'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_gl_impact_core'),
  'non-SI preview executes the real posting writer inside a rolled-back subtransaction'); -- 12

-- No caller routes to an obsolete implementation.
SELECT ok(
  (SELECT p.prosrc ~ 'fn_preview_sales_invoice_gl_impact_aud053_core'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_sales_invoice_gl_impact'),
  'the SI preview wrapper routes to the migrated core');                                  -- 13
SELECT ok(
  (SELECT p.prosrc ~ 'fn_preview_sales_invoice_gl_impact\s*\('
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_gl_impact_core'),
  'the generic dispatcher routes SI to the migrated wrapper');                            -- 14

-- Signature / grant safety.
SELECT is(
  (SELECT pg_get_function_result(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_sales_invoice_gl_impact_aud053_core'),
  'jsonb', 'the migrated core still returns jsonb');                                      -- 15
SELECT ok(
  (SELECT p.prosecdef AND p.proconfig::text ~ 'search_path=public'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_preview_sales_invoice_gl_impact_aud053_core'),
  'the migrated core keeps SECURITY DEFINER with a pinned search_path');                  -- 16
SELECT ok(
  has_function_privilege('authenticated', 'public.fn_preview_sales_invoice_gl_impact(uuid,date)', 'EXECUTE'),
  'the authenticated preview entry point retains EXECUTE');                               -- 17

-- ══════════════════════════════════════════════════════════════════════════════
-- Fixture — one VAT company with a saved, unposted Sales Invoice
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f3d0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p3d-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"0f3d0000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000b1', 'corporation', 'P3D Preview Corp',
        'Consulting', '397-000-001-00000', 'vat', 'calendar',
        'D St', 'D Bldg', 'Makati', 'Metro Manila', '1200',
        'p3d-owner@test.local', 'D Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000b2', '0f3d0000-0000-0000-0000-0000000000b1',
        'HO', 'Head Office', 'D St', 'D Bldg', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f3d0000-0000-0000-0000-0000000000f1', '0f3d0000-0000-0000-0000-0000000000b1', 'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name, start_date, end_date, is_locked)
SELECT '0f3d0000-0000-0000-0000-0000000000b1', '0f3d0000-0000-0000-0000-0000000000f1',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES
  ('0f3d0000-0000-0000-0000-0000000000a1', '0f3d0000-0000-0000-0000-0000000000b1', '1200', 'Accounts Receivable', 'asset', 'debit', true, true, auth.uid(), auth.uid()),
  ('0f3d0000-0000-0000-0000-0000000000a2', '0f3d0000-0000-0000-0000-0000000000b1', '2100', 'Output VAT Payable', 'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('0f3d0000-0000-0000-0000-0000000000a3', '0f3d0000-0000-0000-0000-0000000000b1', '4010', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000b1',
        '0f3d0000-0000-0000-0000-0000000000a1', '0f3d0000-0000-0000-0000-0000000000a2',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number, is_active, created_by, updated_by)
SELECT '0f3d0000-0000-0000-0000-0000000000b1', '0f3d0000-0000-0000-0000-0000000000b2',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code = 'SI';

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000c1', '0f3d0000-0000-0000-0000-0000000000b1', 'CUST-1',
        'Preview Customer Inc', '398-000-001-00000', 'Customer HQ', 'Customer HQ', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
INSERT INTO t_ctx
SELECT 'si', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '0f3d0000-0000-0000-0000-0000000000b1',
    'branch_id',                 '0f3d0000-0000-0000-0000-0000000000b2',
    'date',                      '2026-03-10',
    'customer_id',               '0f3d0000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot',    'Preview Customer Inc',
    'customer_tin_snapshot',     '398-000-001-00000',
    'customer_address_snapshot', 'Customer HQ'),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'),
    'revenue_account_id', '0f3d0000-0000-0000-0000-0000000000a3')));

CREATE TEMP TABLE t_pre AS
SELECT (SELECT count(*) FROM journal_entries)        AS je,
       (SELECT count(*) FROM journal_entry_lines)    AS jel,
       (SELECT count(*) FROM tax_detail_entries)     AS tax,
       (SELECT count(*) FROM inventory_transactions) AS inv,
       (SELECT count(*) FROM transaction_events)     AS evt,
       (SELECT coalesce(sum(next_number),0) FROM number_series) AS series,
       (SELECT status FROM sales_invoices WHERE id=(SELECT id FROM t_ctx WHERE key='si')) AS si_status;

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — Real preview execution: resolver-sourced accounts
-- ══════════════════════════════════════════════════════════════════════════════
CREATE TEMP TABLE t_pv AS
SELECT fn_preview_sales_invoice_gl_impact((SELECT id FROM t_ctx WHERE key='si'), NULL) AS p;

SELECT is(
  (SELECT (l->>'account_id')::uuid FROM t_pv, jsonb_array_elements(p->'lines') l
    WHERE l->>'account_source' = 'company_accounting_config.ar_account_id'),
  fn_resolve_account('0f3d0000-0000-0000-0000-0000000000b1','AR_TRADE'),
  'the previewed AR account equals the certified resolver result');                       -- 18

SELECT is(
  (SELECT (l->>'account_id')::uuid FROM t_pv, jsonb_array_elements(p->'lines') l
    WHERE l->>'account_source' = 'company_accounting_config.vat_payable_account_id'),
  fn_resolve_account('0f3d0000-0000-0000-0000-0000000000b1','VAT_OUTPUT'),
  'the previewed Output VAT account equals the certified resolver result');               -- 19

SELECT results_eq(
  $q$SELECT (l->>'line_number')::int, l->>'account_code', l->>'account_source',
            (l->>'debit')::numeric, (l->>'credit')::numeric
       FROM t_pv, jsonb_array_elements(p->'lines') l
      ORDER BY (l->>'line_number')::int$q$,
  $$VALUES (1, '1200'::text, 'company_accounting_config.ar_account_id'::text, 11200.00::numeric, 0.00::numeric),
           (2, '4010'::text, 'document_line_account'::text, 0.00::numeric, 10000.00::numeric),
           (3, '2100'::text, 'company_accounting_config.vat_payable_account_id'::text, 0.00::numeric, 1200.00::numeric)$$,
  'preview line order, accounts, provenance labels, and amounts are unchanged');           -- 20

SELECT ok((SELECT (p->>'balanced')::boolean FROM t_pv), 'the preview payload is balanced'); -- 21
SELECT is((SELECT (p->>'total_debit')::numeric FROM t_pv), 11200.00::numeric,
  'preview total debit is unchanged');                                                     -- 22
SELECT is((SELECT (p->>'total_credit')::numeric FROM t_pv), 11200.00::numeric,
  'preview total credit is unchanged');                                                    -- 23

-- Payload shape: exact top-level and line key sets.
SELECT set_eq(
  $$SELECT jsonb_object_keys(p) FROM t_pv$$,
  $$VALUES ('mode'),('journal_entry_id'),('je_number'),('posting_date'),('fiscal_period_id'),
           ('fiscal_period_name'),('branch_id'),('branch_name'),('source_doc_type'),
           ('source_doc_id'),('source_display_name'),('source_route'),('rule_explanation'),
           ('total_debit'),('total_credit'),('balanced'),('lines')$$,
  'the preview payload top-level key set is unchanged');                                   -- 24

SELECT set_eq(
  $$SELECT DISTINCT jsonb_object_keys(l) FROM t_pv, jsonb_array_elements(p->'lines') l$$,
  $$VALUES ('line_number'),('account_id'),('account_code'),('account_name'),('account_source'),
           ('description'),('debit'),('credit'),('branch_id'),('department_id'),('cost_center_id'),
           ('project_id'),('location_id'),('functional_entity_id'),
           ('impact_group'),('accounting_effect'),('source_type'),('source_line_id'),('item_id'),
           ('item_code'),('warehouse_id'),('warehouse_code'),('quantity'),('unit_cost'),
           ('total_cost'),('valuation_method'),('inventory_movement_id')$$,
  'the preview line key set is unchanged');                                                -- 25

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — Preview is side-effect free
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is((SELECT count(*) FROM journal_entries), (SELECT je FROM t_pre),
  'preview created no journal entry');                                                     -- 26
SELECT is((SELECT count(*) FROM journal_entry_lines), (SELECT jel FROM t_pre),
  'preview created no journal entry line');                                                -- 27
SELECT is(
  (SELECT (SELECT count(*) FROM tax_detail_entries)||'/'||(SELECT count(*) FROM inventory_transactions)
       ||'/'||(SELECT count(*) FROM transaction_events)
       ||'/'||(SELECT coalesce(sum(next_number),0) FROM number_series)),
  (SELECT tax||'/'||inv||'/'||evt||'/'||series FROM t_pre),
  'preview consumed no tax ledger, inventory, event, or number-series state');             -- 28
SELECT is((SELECT status FROM sales_invoices WHERE id=(SELECT id FROM t_ctx WHERE key='si')),
  (SELECT si_status FROM t_pre), 'preview did not change the document status');            -- 29

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — Preview account == actually posted account
-- ══════════════════════════════════════════════════════════════════════════════
SELECT lives_ok($$SELECT fn_approve_sales_invoice((SELECT id FROM t_ctx WHERE key='si'));
                  SELECT fn_post_sales_invoice((SELECT id FROM t_ctx WHERE key='si'))$$,
  'the previewed invoice posts for real');                                                 -- 30

SELECT results_eq(
  $q$SELECT jel.line_number, coa.account_code, jel.debit_amount, jel.credit_amount
       FROM journal_entry_lines jel
       JOIN chart_of_accounts coa ON coa.id = jel.account_id
      WHERE jel.je_id = (SELECT journal_entry_id FROM sales_invoices
                          WHERE id=(SELECT id FROM t_ctx WHERE key='si'))
      ORDER BY jel.line_number$q$,
  $q$SELECT (l->>'line_number')::int, l->>'account_code',
            (l->>'debit')::numeric(15,2), (l->>'credit')::numeric(15,2)
       FROM t_pv, jsonb_array_elements(p->'lines') l
      ORDER BY (l->>'line_number')::int$q$,
  'every previewed account, amount, and line position equals the posted journal');         -- 31

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION G — Missing mapping fails closed, as a structured blocker (not a raw raise)
-- ══════════════════════════════════════════════════════════════════════════════
-- A second company whose AR is deliberately unconfigured: the resolver cannot resolve
-- AR_TRADE, and the preview must still return its structured payload.
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000b9', 'corporation', 'P3D Unconfigured Corp',
        'Consulting', '397-000-002-00000', 'vat', 'calendar',
        'U St', 'U Bldg', 'Makati', 'Metro Manila', '1200',
        'p3d-owner@test.local', 'U Owner', 'President', auth.uid(), auth.uid());
INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000b8', '0f3d0000-0000-0000-0000-0000000000b9',
        'HO', 'Head Office', 'U St', 'U Bldg', 'Makati', 'Metro Manila', '1200', auth.uid(), auth.uid());
INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('0f3d0000-0000-0000-0000-0000000000f9', '0f3d0000-0000-0000-0000-0000000000b9', 'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name, start_date, end_date, is_locked)
SELECT '0f3d0000-0000-0000-0000-0000000000b9', '0f3d0000-0000-0000-0000-0000000000f9',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'), make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;
INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000a9', '0f3d0000-0000-0000-0000-0000000000b9', '4010', 'Service Revenue', 'revenue', 'credit', true, true, auth.uid(), auth.uid());
INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number, is_active, created_by, updated_by)
SELECT '0f3d0000-0000-0000-0000-0000000000b9', '0f3d0000-0000-0000-0000-0000000000b8',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt WHERE rdt.document_code = 'SI';
INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000c9', '0f3d0000-0000-0000-0000-0000000000b9', 'CUST-9',
        'Unconfigured Customer', '398-000-002-00000', 'HQ', 'HQ', auth.uid(), auth.uid());

INSERT INTO t_ctx
SELECT 'si9', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '0f3d0000-0000-0000-0000-0000000000b9',
    'branch_id',                 '0f3d0000-0000-0000-0000-0000000000b8',
    'date',                      '2026-03-10',
    'customer_id',               '0f3d0000-0000-0000-0000-0000000000c9',
    'customer_name_snapshot',    'Unconfigured Customer',
    'customer_tin_snapshot',     '398-000-002-00000',
    'customer_address_snapshot', 'HQ'),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         5000,
    'revenue_account_id', '0f3d0000-0000-0000-0000-0000000000a9')));

-- Non-vacuity of the fail-closed case: the mapping genuinely does not exist, and the
-- resolver genuinely raises for it (so the preview's structured payload is a deliberate
-- containment of a real failure, not the absence of one).
SELECT is(
  (SELECT count(*)::int FROM account_mapping
    WHERE company_id='0f3d0000-0000-0000-0000-0000000000b9' AND key_code='AR_TRADE'),
  0, 'the fixture company genuinely has no AR_TRADE mapping (non-vacuous)');               -- 32

SELECT throws_ok(
  $$SELECT fn_resolve_posting_account('0f3d0000-0000-0000-0000-0000000000b9','AR_TRADE','2026-03-10','AR control account not configured. Set it up in GL Posting Configuration.')$$,
  NULL, NULL,
  'the resolver itself raises for the unresolvable mapping (fail-closed at the seam)');    -- 33

SELECT lives_ok(
  $$SELECT fn_preview_sales_invoice_gl_impact((SELECT id FROM t_ctx WHERE key='si9'), NULL)$$,
  'preview contains that failure and still returns a structured payload');                 -- 34

SELECT is(
  (SELECT l->>'account_code'
     FROM (SELECT fn_preview_sales_invoice_gl_impact((SELECT id FROM t_ctx WHERE key='si9'), NULL) AS p) q,
          jsonb_array_elements(q.p->'lines') l
    WHERE l->>'account_source' = 'company_accounting_config.ar_account_id'),
  'Missing AR Account',
  'the unresolvable AR account fails closed as the established structured blocker');       -- 35

SELECT is(
  (SELECT l->>'account_id'
     FROM (SELECT fn_preview_sales_invoice_gl_impact((SELECT id FROM t_ctx WHERE key='si9'), NULL) AS p) q,
          jsonb_array_elements(q.p->'lines') l
    WHERE l->>'account_source' = 'company_accounting_config.ar_account_id'),
  NULL, 'the blocker line carries no account_id');                                         -- 36

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION H — Change detection: preview follows the RESOLVER, not the config column
--
-- The whole point of O2 is drift between company_accounting_config and account_mapping.
-- Point the AR mapping at a different account while leaving the config column alone: a
-- pre-P3D preview would have shown the config account (drift); the migrated preview must
-- show the resolver's account, which is what actual posting would use.
-- ══════════════════════════════════════════════════════════════════════════════
INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active, created_by, updated_by)
VALUES ('0f3d0000-0000-0000-0000-0000000000a4', '0f3d0000-0000-0000-0000-0000000000b1', '1201', 'AR - Reassigned', 'asset', 'debit', true, true, auth.uid(), auth.uid());

INSERT INTO t_ctx
SELECT 'si2', fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id',                '0f3d0000-0000-0000-0000-0000000000b1',
    'branch_id',                 '0f3d0000-0000-0000-0000-0000000000b2',
    'date',                      '2026-04-10',
    'customer_id',               '0f3d0000-0000-0000-0000-0000000000c1',
    'customer_name_snapshot',    'Preview Customer Inc',
    'customer_tin_snapshot',     '398-000-001-00000',
    'customer_address_snapshot', 'Customer HQ'),
  jsonb_build_array(jsonb_build_object(
    'description',        'Consulting services',
    'quantity',           1,
    'unit_price',         2000,
    'revenue_account_id', '0f3d0000-0000-0000-0000-0000000000a3')));

UPDATE account_mapping SET account_id = '0f3d0000-0000-0000-0000-0000000000a4'
WHERE company_id = '0f3d0000-0000-0000-0000-0000000000b1' AND key_code = 'AR_TRADE';

SELECT is(
  (SELECT ar_account_id FROM company_accounting_config
    WHERE company_id='0f3d0000-0000-0000-0000-0000000000b1'),
  '0f3d0000-0000-0000-0000-0000000000a1'::uuid,
  'the config column still points at the original AR account (drift is real)');            -- 37

SELECT is(
  (SELECT (l->>'account_id')::uuid
     FROM (SELECT fn_preview_sales_invoice_gl_impact((SELECT id FROM t_ctx WHERE key='si2'), NULL) AS p) q,
          jsonb_array_elements(q.p->'lines') l
    WHERE l->>'account_source' = 'company_accounting_config.ar_account_id'),
  '0f3d0000-0000-0000-0000-0000000000a4'::uuid,
  'preview follows the resolver, not the config column — O2 drift is closed');             -- 38

SELECT * FROM finish();
ROLLBACK;
