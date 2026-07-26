-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P2D-001 — Banking/Payments/Purchase-return resolver adoption
--                          (COA Engine Phase B, group 4)
--
-- Certifies that the remaining forward posting writers that read
-- company_accounting_config now resolve accounts exclusively through the certified
-- COA resolver fn_resolve_account (via the fn_resolve_posting_account adapter), with
-- no accounting behavior change. Byte-for-byte GL equality of real postings is proven
-- by the full regression + canonical lanes: Payment Voucher (test 001 critical flow,
-- 006 PV+EWT, 034/043/051, canonical 055/057 which post 5 vouchers), Check Voucher
-- (022 CV EWT 2307, 023, 036), Purchase Return (031), and Withholding Remittance (036)
-- all post with exact GL assertions and stay green. This file guards the migration
-- structurally: the four migrated writers consume the resolver and no longer read
-- company_accounting_config; already-compliant Banking/reversal writers are certified
-- unchanged; and resolver output equals the previously-read configuration (equivalence).
--
-- P2D makes NO metadata change (unlike P2A/P2B): posting_origin/line_role are left
-- exactly as they were, honoring the byte-for-byte-equivalent constraint.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- ── Resolver adoption: every migrated P2D writer now uses the resolver adapter ──
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_payment_voucher','fn_post_check_voucher',
                        'fn_complete_purchase_return_source_locked_impl','fn_post_withholding_remittance')
      AND p.prosrc ~ 'fn_resolve_posting_account'),
  4, 'all 4 migrated P2D writers resolve accounts through fn_resolve_posting_account');   -- 1

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_payment_voucher','fn_post_check_voucher',
                        'fn_complete_purchase_return_source_locked_impl','fn_post_withholding_remittance')
      AND p.prosrc ~* 'company_accounting_config'),
  0, 'no migrated P2D writer reads company_accounting_config for account resolution');     -- 2

-- ── Certified without change: Banking + reversal writers were already config-free ──
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_bank_adjustment_source_locked_impl',
                        'fn_post_fund_transfer_source_locked_impl',
                        'fn_post_inter_branch_transfer_source_locked_impl',
                        'fn_cancel_payment_voucher','fn_cancel_check_voucher',
                        'fn_void_withholding_remittance','fn_cancel_bank_adjustment',
                        'fn_cancel_fund_transfer','fn_cancel_inter_branch_transfer')
      AND p.prosrc ~* 'company_accounting_config'),
  0, 'already-compliant Banking/reversal writers read zero company_accounting_config (certified unchanged)'); -- 3

-- ── Non-vacuous: an out-of-scope reporting function still reads config ──────────
SELECT ok(
  (SELECT p.prosrc ~* 'company_accounting_config' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_ap_subledger_gl_reconciliation_asof'),
  'config-read detector is non-vacuous (an out-of-scope reconciliation report still reads config)'); -- 4

-- ── Fixture: company + postable accounts + config (drives the config→mapping sync)
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0e0e0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'p2d-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  json_build_object('sub','0e0e0000-0000-0000-0000-000000000001','role','authenticated')::text, true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('0e0e0000-0000-0000-0000-0000000000b1', 'corporation', 'P2D Payments Corp',
        'Trading', '361-000-004-00000', 'vat', 'calendar',
        'D St', 'D Bldg', 'Makati', 'Metro Manila', '1200',
        'p2d-owner@test.local', 'D Owner', 'President',
        '0e0e0000-0000-0000-0000-000000000001', '0e0e0000-0000-0000-0000-000000000001');

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name, account_type,
       normal_balance, is_postable, lifecycle_status, is_active, created_by, updated_by)
VALUES
 ('0e0e0000-0000-0000-0000-0000000000c1','0e0e0000-0000-0000-0000-0000000000b1','2100','AP','liability','credit',true,'active',true,'0e0e0000-0000-0000-0000-000000000001','0e0e0000-0000-0000-0000-000000000001'),
 ('0e0e0000-0000-0000-0000-0000000000c2','0e0e0000-0000-0000-0000-0000000000b1','1450','Supplier Downpayments','asset','debit',true,'active',true,'0e0e0000-0000-0000-0000-000000000001','0e0e0000-0000-0000-0000-000000000001'),
 ('0e0e0000-0000-0000-0000-0000000000c3','0e0e0000-0000-0000-0000-0000000000b1','2150','EWT Payable','liability','credit',true,'active',true,'0e0e0000-0000-0000-0000-000000000001','0e0e0000-0000-0000-0000-000000000001'),
 ('0e0e0000-0000-0000-0000-0000000000c4','0e0e0000-0000-0000-0000-0000000000b1','1410','EWT Withheld','asset','debit',true,'active',true,'0e0e0000-0000-0000-0000-000000000001','0e0e0000-0000-0000-0000-000000000001'),
 ('0e0e0000-0000-0000-0000-0000000000c5','0e0e0000-0000-0000-0000-0000000000b1','1010','Cash','asset','debit',true,'active',true,'0e0e0000-0000-0000-0000-000000000001','0e0e0000-0000-0000-0000-000000000001');

INSERT INTO company_accounting_config (company_id, ap_account_id, supplier_down_payments_account_id,
       ewt_payable_account_id, ewt_withheld_account_id, default_cash_account_id, created_by, updated_by)
VALUES ('0e0e0000-0000-0000-0000-0000000000b1',
        '0e0e0000-0000-0000-0000-0000000000c1','0e0e0000-0000-0000-0000-0000000000c2',
        '0e0e0000-0000-0000-0000-0000000000c3','0e0e0000-0000-0000-0000-0000000000c4',
        '0e0e0000-0000-0000-0000-0000000000c5',
        '0e0e0000-0000-0000-0000-000000000001','0e0e0000-0000-0000-0000-000000000001');

-- ── Adapter behavior ────────────────────────────────────────────────────────────
SELECT is(
  fn_resolve_posting_account('0e0e0000-0000-0000-0000-0000000000b1','AP_TRADE',CURRENT_DATE,'AP control account not configured. Set it up in GL Posting Configuration.'),
  '0e0e0000-0000-0000-0000-0000000000c1',
  'fn_resolve_posting_account returns the configured account for a resolvable key');     -- 5
-- AR_TRADE is a known key but this payments company left ar_account_id unconfigured,
-- so no mapping exists (no_data_found) -> the adapter re-raises the friendly message.
SELECT throws_like(
  $$SELECT fn_resolve_posting_account('0e0e0000-0000-0000-0000-0000000000b1','AR_TRADE',CURRENT_DATE,'AP control account not configured. Set it up in GL Posting Configuration.')$$,
  '%AP control account not configured%',
  'fn_resolve_posting_account re-raises the friendly message on a missing mapping');     -- 6

-- ── Equivalence: resolver == the previously-read configuration ─────────────────
SELECT is(fn_resolve_account('0e0e0000-0000-0000-0000-0000000000b1','AP_TRADE'),
          '0e0e0000-0000-0000-0000-0000000000c1', 'AP_TRADE resolves to configured AP');  -- 7
SELECT is(fn_resolve_account('0e0e0000-0000-0000-0000-0000000000b1','SUPPLIER_DOWNPAYMENTS'),
          '0e0e0000-0000-0000-0000-0000000000c2', 'SUPPLIER_DOWNPAYMENTS resolves to configured downpayments'); -- 8
SELECT is(fn_resolve_account('0e0e0000-0000-0000-0000-0000000000b1','EWT_PAYABLE'),
          '0e0e0000-0000-0000-0000-0000000000c3', 'EWT_PAYABLE resolves to configured EWT payable'); -- 9
SELECT is(fn_resolve_account('0e0e0000-0000-0000-0000-0000000000b1','EWT_WITHHELD'),
          '0e0e0000-0000-0000-0000-0000000000c4', 'EWT_WITHHELD resolves to configured EWT withheld'); -- 10
SELECT is(fn_resolve_account('0e0e0000-0000-0000-0000-0000000000b1','CASH_DEFAULT'),
          '0e0e0000-0000-0000-0000-0000000000c5', 'CASH_DEFAULT resolves to configured cash'); -- 11

SELECT * FROM finish();
ROLLBACK;
