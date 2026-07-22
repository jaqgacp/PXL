-- ============================================================================
-- PXL-AUD-069 - Reporting-view tenant isolation (Permissions/RLS Engine)
--
-- Nine postgres-owned reporting views previously executed WITHOUT
-- security_invoker and bypassed RLS, leaking other companies' financial data to
-- any authenticated user through PostgREST. Migration
-- 20260722000011_aud069_reporting_view_rls_isolation.sql enables
-- security_invoker on all nine.
--
-- This test proves the fix two ways:
--   (1) Behaviorally, end-to-end, on a representative view (vw_payment_register
--       over payment_vouchers): a member of company A reads only company A's row;
--       a member of company B and a non-member of A read zero of A's rows.
--   (2) Structurally, that ALL nine remediated views carry security_invoker.
--       security_invoker is a single view-level property that makes PostgreSQL
--       apply the caller's RLS uniformly regardless of the view body, so the
--       behavioral proof of the mechanism extends to every view that has it.
-- The permanent catalog guard 077 independently prevents any authenticated view
-- from reappearing without tenant isolation.
--
-- Runs as `authenticated` with JWT claims so the broad SELECT policies on the
-- base tables are exercised exactly as PostgREST would.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- ── Actors ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000','a9000000-0000-0000-0000-000000000a01',
   'authenticated','authenticated','iso-a@test.local','',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000','a9000000-0000-0000-0000-000000000b02',
   'authenticated','authenticated','iso-b@test.local','',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000','a9000000-0000-0000-0000-000000000c03',
   'authenticated','authenticated','iso-c@test.local','',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}');

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- ── Companies (creator-owner trigger makes each actor a member of their own) ──
SELECT pg_temp.as_user('a9000000-0000-0000-0000-000000000a01');
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period, address_line_1,
                       address_line_2, city, province, zip_code, email,
                       signatory_name, signatory_position, created_by, updated_by)
VALUES ('c9000000-0000-0000-0000-0000000000a1','corporation','ISO Company A',
        'Trading','311-222-701-00000','vat','calendar','1 A St','Bldg A','Makati',
        'NCR','1200','a@iso.local','Signer A','President',
        'a9000000-0000-0000-0000-000000000a01','a9000000-0000-0000-0000-000000000a01');

SELECT pg_temp.as_user('a9000000-0000-0000-0000-000000000b02');
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period, address_line_1,
                       address_line_2, city, province, zip_code, email,
                       signatory_name, signatory_position, created_by, updated_by)
VALUES ('c9000000-0000-0000-0000-0000000000b2','corporation','ISO Company B',
        'Trading','311-222-702-00000','vat','calendar','1 B St','Bldg B','Makati',
        'NCR','1200','b@iso.local','Signer B','President',
        'a9000000-0000-0000-0000-000000000b02','a9000000-0000-0000-0000-000000000b02');

SELECT pg_temp.as_user('a9000000-0000-0000-0000-000000000c03');
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period, address_line_1,
                       address_line_2, city, province, zip_code, email,
                       signatory_name, signatory_position, created_by, updated_by)
VALUES ('c9000000-0000-0000-0000-0000000000c3','corporation','ISO Company C',
        'Trading','311-222-703-00000','vat','calendar','1 C St','Bldg C','Makati',
        'NCR','1200','c@iso.local','Signer C','President',
        'a9000000-0000-0000-0000-000000000c03','a9000000-0000-0000-0000-000000000c03');

-- ── Company-A business fixture (triggers disabled: we test RLS, not the CAS/SOD
--    insert-time controls, which are covered by their own tests) ──────────────
INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address)
VALUES ('50000000-0000-0000-0000-0000000000a1','c9000000-0000-0000-0000-0000000000a1',
        'SUP-A','ISO Supplier A','411-222-701-00000','Supplier A Address');

ALTER TABLE payment_vouchers DISABLE TRIGGER USER;
INSERT INTO payment_vouchers (id, company_id, supplier_id, supplier_name_snapshot,
                              voucher_number, voucher_date)
VALUES ('60000000-0000-0000-0000-0000000000a1','c9000000-0000-0000-0000-0000000000a1',
        '50000000-0000-0000-0000-0000000000a1','ISO Supplier A','PV-ISO-A-1','2026-01-15');
ALTER TABLE payment_vouchers ENABLE TRIGGER USER;

-- ── Behavioral isolation through the (now security_invoker) view ─────────────
SET LOCAL ROLE authenticated;

SELECT pg_temp.as_user('a9000000-0000-0000-0000-000000000a01');
SELECT is(
  (SELECT count(*)::int FROM vw_payment_register
     WHERE id = '60000000-0000-0000-0000-0000000000a1'),
  1,
  'member of company A CAN read own-company payment voucher through vw_payment_register');
SELECT is(
  (SELECT count(DISTINCT company_id)::int FROM vw_payment_register),
  1,
  'member of company A sees only their own company through the view (no cross-company rows)');

SELECT pg_temp.as_user('a9000000-0000-0000-0000-000000000b02');
SELECT is(
  (SELECT count(*)::int FROM vw_payment_register
     WHERE id = '60000000-0000-0000-0000-0000000000a1'),
  0,
  'member of company B CANNOT read company A payment voucher through the view');

SELECT pg_temp.as_user('a9000000-0000-0000-0000-000000000c03');
SELECT is(
  (SELECT count(*)::int FROM vw_payment_register
     WHERE company_id = 'c9000000-0000-0000-0000-0000000000a1'),
  0,
  'non-member of company A receives zero company-A rows through the view');

-- ── Structural: every remediated view carries security_invoker ───────────────
SELECT is(
  (SELECT count(*)::int FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'v'
      AND coalesce(c.reloptions::text,'') ~* 'security_invoker=(on|true)'
      AND c.relname IN ('vw_ap_aging','vw_credit_memo_register','vw_debit_memo_register',
                        'vw_deposits_in_transit','vw_outstanding_checks','vw_payment_register',
                        'vw_receipt_register','vw_sdm_register','vw_slp_export')),
  9,
  'all nine remediated reporting views have security_invoker enabled');

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'v'
       AND c.relname IN ('vw_ap_aging','vw_credit_memo_register','vw_debit_memo_register',
                         'vw_deposits_in_transit','vw_outstanding_checks','vw_payment_register',
                         'vw_receipt_register','vw_sdm_register','vw_slp_export')
       AND NOT (coalesce(c.reloptions::text,'') ~* 'security_invoker=(on|true)')),
  'no remediated reporting view remains without security_invoker');

SELECT * FROM finish();
ROLLBACK;
