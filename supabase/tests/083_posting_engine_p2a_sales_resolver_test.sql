-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P2A-001 — Sales resolver adoption (COA Engine Phase B, group 1)
--
-- Certifies that the Sales posting writers now resolve accounts exclusively through
-- the certified COA resolver, with no accounting behavior change. Byte-for-byte GL
-- equality of real Sales postings is proven by the full regression + canonical lanes
-- (test 001 critical flow, 054 SI completeness, canonical 055/057 all post SI/OR/
-- CM/DM/cash-sale with exact GL assertions and stay green). This file guards the
-- migration structurally: every Sales writer consumes the resolver and no longer
-- reads company_accounting_config, out-of-scope writers remain on legacy resolution,
-- and resolver output equals the previously-read configuration (equivalence).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- ── Resolver adoption: every Sales writer now uses the resolver adapter ─────────
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_sales_invoice_costing_legacy_20260808','fn_post_receipt','fn_save_cash_sale_costing_legacy_20260808',
                        'fn_post_credit_memo_vat_lump_impl','fn_post_debit_memo_vat_lump_impl')
      AND p.prosrc ~ 'fn_resolve_posting_account'),
  5, 'all 5 Sales writers resolve accounts through fn_resolve_posting_account');        -- 1

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_sales_invoice_costing_legacy_20260808','fn_post_receipt','fn_save_cash_sale_costing_legacy_20260808',
                        'fn_post_credit_memo_vat_lump_impl','fn_post_debit_memo_vat_lump_impl')
      AND p.prosrc ~* 'company_accounting_config'),
  0, 'no Sales writer reads company_accounting_config for account resolution');          -- 2

-- ── Scope guard: out-of-scope code remains on legacy config resolution ──────────
-- (Vendor Bill and Check Voucher are migrated in P2B/P2D; use an out-of-scope
--  reconciliation report that reads config to identify control accounts.)
SELECT ok(
  (SELECT p.prosrc ~* 'company_accounting_config' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_ap_subledger_gl_reconciliation_asof'),
  'out-of-scope reconciliation report still reads company_accounting_config (non-vacuous detector)'); -- 3

-- ── Fixture: company + postable accounts + config (drives the config→mapping sync)
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0e0c0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p2a-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  json_build_object('sub','0e0c0000-0000-0000-0000-000000000001','role','authenticated')::text, true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0e0c0000-0000-0000-0000-0000000000a1', 'corporation', 'P2A Sales Corp',
        'Trading', '361-000-001-00000', 'vat', 'calendar',
        'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
        'p2a-owner@test.local', 'A Owner', 'President',
        '0e0c0000-0000-0000-0000-000000000001', '0e0c0000-0000-0000-0000-000000000001');

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name, account_type,
       normal_balance, is_postable, lifecycle_status, is_active, created_by, updated_by)
VALUES
 ('0e0c0000-0000-0000-0000-0000000000f1','0e0c0000-0000-0000-0000-0000000000a1','1100','AR','asset','debit',true,'active',true,'0e0c0000-0000-0000-0000-000000000001','0e0c0000-0000-0000-0000-000000000001'),
 ('0e0c0000-0000-0000-0000-0000000000f2','0e0c0000-0000-0000-0000-0000000000a1','2200','Output VAT','liability','credit',true,'active',true,'0e0c0000-0000-0000-0000-000000000001','0e0c0000-0000-0000-0000-000000000001'),
 ('0e0c0000-0000-0000-0000-0000000000f3','0e0c0000-0000-0000-0000-0000000000a1','1010','Cash','asset','debit',true,'active',true,'0e0c0000-0000-0000-0000-000000000001','0e0c0000-0000-0000-0000-000000000001'),
 ('0e0c0000-0000-0000-0000-0000000000f4','0e0c0000-0000-0000-0000-0000000000a1','1410','CWT','asset','debit',true,'active',true,'0e0c0000-0000-0000-0000-000000000001','0e0c0000-0000-0000-0000-000000000001'),
 ('0e0c0000-0000-0000-0000-0000000000f5','0e0c0000-0000-0000-0000-0000000000a1','2100','Customer Advances','liability','credit',true,'active',true,'0e0c0000-0000-0000-0000-000000000001','0e0c0000-0000-0000-0000-000000000001');

INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
       default_cash_account_id, ewt_withheld_account_id, customer_advances_account_id, created_by, updated_by)
VALUES ('0e0c0000-0000-0000-0000-0000000000a1',
        '0e0c0000-0000-0000-0000-0000000000f1','0e0c0000-0000-0000-0000-0000000000f2',
        '0e0c0000-0000-0000-0000-0000000000f3','0e0c0000-0000-0000-0000-0000000000f4',
        '0e0c0000-0000-0000-0000-0000000000f5',
        '0e0c0000-0000-0000-0000-000000000001','0e0c0000-0000-0000-0000-000000000001');

-- ── Adapter behavior ────────────────────────────────────────────────────────────
SELECT is(
  fn_resolve_posting_account('0e0c0000-0000-0000-0000-0000000000a1','AR_TRADE',CURRENT_DATE,'AR control account not configured. Set it up in GL Posting Configuration.'),
  '0e0c0000-0000-0000-0000-0000000000f1',
  'fn_resolve_posting_account returns the configured account for a resolvable key');     -- 4
-- AP_TRADE is a known key but this company left ap_account_id unconfigured, so no
-- mapping exists (no_data_found) -> the adapter re-raises the friendly message.
SELECT throws_like(
  $$SELECT fn_resolve_posting_account('0e0c0000-0000-0000-0000-0000000000a1','AP_TRADE',CURRENT_DATE,'AR control account not configured. Set it up in GL Posting Configuration.')$$,
  '%AR control account not configured%',
  'fn_resolve_posting_account re-raises the friendly message on a missing mapping');     -- 5

-- ── Equivalence: resolver == the previously-read configuration (the whole basis of
--    byte-for-byte GL equality for the migrated writers) ──────────────────────────
SELECT is(fn_resolve_account('0e0c0000-0000-0000-0000-0000000000a1','AR_TRADE'),
          '0e0c0000-0000-0000-0000-0000000000f1', 'AR_TRADE resolves to configured AR'); -- 6
SELECT is(fn_resolve_account('0e0c0000-0000-0000-0000-0000000000a1','VAT_OUTPUT'),
          '0e0c0000-0000-0000-0000-0000000000f2', 'VAT_OUTPUT resolves to configured output VAT'); -- 7
SELECT is(fn_resolve_account('0e0c0000-0000-0000-0000-0000000000a1','CASH_DEFAULT'),
          '0e0c0000-0000-0000-0000-0000000000f3', 'CASH_DEFAULT resolves to configured cash'); -- 8
SELECT is(fn_resolve_account('0e0c0000-0000-0000-0000-0000000000a1','EWT_WITHHELD'),
          '0e0c0000-0000-0000-0000-0000000000f4', 'EWT_WITHHELD resolves to configured CWT'); -- 9
SELECT is(fn_resolve_account('0e0c0000-0000-0000-0000-0000000000a1','CUSTOMER_ADVANCES'),
          '0e0c0000-0000-0000-0000-0000000000f5', 'CUSTOMER_ADVANCES resolves to configured advances'); -- 10

-- ── Metadata: migrated direct-insert writers tag posting_origin/line_role ────────
-- P5.1 Module 1 routed the memo posters through the kernel, so they now PASS
-- posting_origin as a kernel argument instead of naming the column. Both spellings
-- express the same fact; the behavioural proof (posted header carries 'system')
-- lives in test 092.
SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'posting_origin'
                OR p.prosrc ~ $re$fn_create_posted_journal_entry\([^;]*'system'$re$)
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_sales_invoice_costing_legacy_20260808','fn_post_receipt','fn_save_cash_sale_costing_legacy_20260808',
                        'fn_post_credit_memo_vat_lump_impl','fn_post_debit_memo_vat_lump_impl')),
  'every Sales writer populates the posting_origin metadata');                           -- 11

SELECT * FROM finish();
ROLLBACK;
