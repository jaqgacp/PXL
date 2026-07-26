-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P2B-001 — Purchasing resolver adoption (COA Engine Phase B, group 2)
--
-- Certifies that the Purchasing posting writers now resolve accounts exclusively
-- through the certified COA resolver, with no accounting behavior change. Byte-for-byte
-- GL equality of real Purchasing postings is proven by the full regression + canonical
-- lanes (test 001 critical flow posts a Vendor Bill, 042 posts Cash Purchase with EWT,
-- 004/035 post Vendor Credit, and canonical 055/057 post the purchasing families — all
-- with exact GL assertions and stay green). This file guards the migration structurally:
-- every Purchasing writer consumes the resolver and no longer reads
-- company_accounting_config, out-of-scope writers remain on legacy resolution, and
-- resolver output equals the previously-read configuration (equivalence).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- ── Resolver adoption: every Purchasing writer now uses the resolver adapter ────
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_vendor_bill','fn_post_cash_purchase_source_locked_impl',
                        'fn_post_vendor_credit_vat_lump_impl')
      AND p.prosrc ~ 'fn_resolve_posting_account'),
  3, 'all 3 Purchasing writers resolve accounts through fn_resolve_posting_account');    -- 1

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_vendor_bill','fn_post_cash_purchase_source_locked_impl',
                        'fn_post_vendor_credit_vat_lump_impl')
      AND p.prosrc ~* 'company_accounting_config'),
  0, 'no Purchasing writer reads company_accounting_config for account resolution');      -- 2

-- ── Scope guard: out-of-scope code remains on legacy config resolution ──────────
-- (Check Voucher is migrated in P2D; use an out-of-scope reconciliation report that
--  reads config to identify control accounts.)
SELECT ok(
  (SELECT p.prosrc ~* 'company_accounting_config' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_ap_subledger_gl_reconciliation_asof'),
  'out-of-scope reconciliation report still reads company_accounting_config (non-vacuous detector)'); -- 3

-- ── Fixture: company + postable accounts + config (drives the config→mapping sync)
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0e0d0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p2b-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  json_build_object('sub','0e0d0000-0000-0000-0000-000000000001','role','authenticated')::text, true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0e0d0000-0000-0000-0000-0000000000b1', 'corporation', 'P2B Purchasing Corp',
        'Trading', '361-000-002-00000', 'vat', 'calendar',
        'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
        'p2b-owner@test.local', 'B Owner', 'President',
        '0e0d0000-0000-0000-0000-000000000001', '0e0d0000-0000-0000-0000-000000000001');

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name, account_type,
       normal_balance, is_postable, lifecycle_status, is_active, created_by, updated_by)
VALUES
 ('0e0d0000-0000-0000-0000-0000000000c1','0e0d0000-0000-0000-0000-0000000000b1','2100','AP','liability','credit',true,'active',true,'0e0d0000-0000-0000-0000-000000000001','0e0d0000-0000-0000-0000-000000000001'),
 ('0e0d0000-0000-0000-0000-0000000000c2','0e0d0000-0000-0000-0000-0000000000b1','1300','Input VAT','asset','debit',true,'active',true,'0e0d0000-0000-0000-0000-000000000001','0e0d0000-0000-0000-0000-000000000001'),
 ('0e0d0000-0000-0000-0000-0000000000c3','0e0d0000-0000-0000-0000-0000000000b1','2150','EWT Payable','liability','credit',true,'active',true,'0e0d0000-0000-0000-0000-000000000001','0e0d0000-0000-0000-0000-000000000001'),
 ('0e0d0000-0000-0000-0000-0000000000c4','0e0d0000-0000-0000-0000-0000000000b1','1010','Cash','asset','debit',true,'active',true,'0e0d0000-0000-0000-0000-000000000001','0e0d0000-0000-0000-0000-000000000001');

INSERT INTO company_accounting_config (company_id, ap_account_id, input_vat_account_id,
       ewt_payable_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('0e0d0000-0000-0000-0000-0000000000b1',
        '0e0d0000-0000-0000-0000-0000000000c1','0e0d0000-0000-0000-0000-0000000000c2',
        '0e0d0000-0000-0000-0000-0000000000c3','0e0d0000-0000-0000-0000-0000000000c4',
        '0e0d0000-0000-0000-0000-000000000001','0e0d0000-0000-0000-0000-000000000001');

-- ── Adapter behavior ────────────────────────────────────────────────────────────
SELECT is(
  fn_resolve_posting_account('0e0d0000-0000-0000-0000-0000000000b1','AP_TRADE',CURRENT_DATE,'AP control account not configured. Set it up in GL Posting Configuration.'),
  '0e0d0000-0000-0000-0000-0000000000c1',
  'fn_resolve_posting_account returns the configured account for a resolvable key');     -- 4
-- AR_TRADE is a known key but this purchasing company left ar_account_id unconfigured,
-- so no mapping exists (no_data_found) -> the adapter re-raises the friendly message.
SELECT throws_like(
  $$SELECT fn_resolve_posting_account('0e0d0000-0000-0000-0000-0000000000b1','AR_TRADE',CURRENT_DATE,'AP control account not configured. Set it up in GL Posting Configuration.')$$,
  '%AP control account not configured%',
  'fn_resolve_posting_account re-raises the friendly message on a missing mapping');     -- 5

-- ── Equivalence: resolver == the previously-read configuration (the whole basis of
--    byte-for-byte GL equality for the migrated writers) ──────────────────────────
SELECT is(fn_resolve_account('0e0d0000-0000-0000-0000-0000000000b1','AP_TRADE'),
          '0e0d0000-0000-0000-0000-0000000000c1', 'AP_TRADE resolves to configured AP');  -- 6
SELECT is(fn_resolve_account('0e0d0000-0000-0000-0000-0000000000b1','VAT_INPUT'),
          '0e0d0000-0000-0000-0000-0000000000c2', 'VAT_INPUT resolves to configured input VAT'); -- 7
SELECT is(fn_resolve_account('0e0d0000-0000-0000-0000-0000000000b1','EWT_PAYABLE'),
          '0e0d0000-0000-0000-0000-0000000000c3', 'EWT_PAYABLE resolves to configured EWT payable'); -- 8
SELECT is(fn_resolve_account('0e0d0000-0000-0000-0000-0000000000b1','CASH_DEFAULT'),
          '0e0d0000-0000-0000-0000-0000000000c4', 'CASH_DEFAULT resolves to configured cash'); -- 9

-- ── Metadata: migrated writers tag posting_origin; direct-insert VC tags line_role ─
-- P5.1 Module 1 routed the memo posters through the kernel, so they now PASS
-- posting_origin as a kernel argument instead of naming the column. Both spellings
-- express the same fact; the behavioural proof (posted header carries 'system')
-- lives in test 092.
SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'posting_origin'
                OR p.prosrc ~ $re$fn_create_posted_journal_entry\([^;]*'system'$re$)
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_vendor_bill','fn_post_cash_purchase_source_locked_impl',
                        'fn_post_vendor_credit_vat_lump_impl')),
  'every Purchasing writer populates the posting_origin metadata');                       -- 10

-- P5.1 Stage 2 Module 2 moved this writer's line INSERTs into the role-carrying
-- persistence helper, so it now PASSES the role positionally instead of naming the
-- column. Both spellings express the same fact; the behavioural proof (persisted
-- line_role values control/base/tax) is test 093 assertion 19.
SELECT ok(
  (SELECT p.prosrc ~ 'line_role' OR p.prosrc ~ 'fn_add_posting_line_push'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_vendor_credit_vat_lump_impl'),
  'the Vendor Credit writer tags line_role on its journal lines');                        -- 11

SELECT * FROM finish();
ROLLBACK;
