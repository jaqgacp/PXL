-- ══════════════════════════════════════════════════════════════════════════════
-- Backlog 10 — Governed tax-code maintenance: succession through the governed path
--
-- Test 039 proves the RULE: a used version's rate and identity are frozen, and a
-- statutory rate change must become a successor. Test 060 proves the AUTHORITY:
-- only a provisioned statutory-config maintainer may write, and every write is
-- audited once with its reason.
--
-- What neither could prove, because it did not exist: that the succession is
-- REACHABLE. RLS denies every direct client INSERT on these three tables, and the
-- governed upserts took no `supersedes` argument — so the only outcome an
-- application could produce was an ORPHAN successor, a new version whose
-- `supersedes_*_id` was NULL and which was therefore indistinguishable from an
-- unrelated code sharing a name.
--
-- This file asserts the closing of that gap:
--   * the succession link is recorded through the governed path, on all three
--     global families;
--   * "close the window and start the successor" is ONE transaction — a failing
--     successor leaves the predecessor's window open, never a code that resolves
--     to nothing;
--   * succession is what a USED version accepts, and an in-place rate change is
--     still what it refuses;
--   * a successor that starts on or before its predecessor is refused, as is one
--     whose live window overlaps an existing version;
--   * none of it is available to a non-maintainer.
--
-- Runs as `authenticated` so RLS and the SECURITY DEFINER path are real.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(34);

-- Users: an ordinary authenticated user and a provisioned maintainer.
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-111111111730'::uuid, 'succ-ordinary@test.local'),
  ('11111111-1111-1111-1111-111111111731'::uuid, 'succ-maintainer@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

INSERT INTO bir_config_maintainers (user_id, note)
VALUES ('11111111-1111-1111-1111-111111111731', 'succession test maintainer');

-- A company, only so that a posted tax-ledger row can make a version "used".
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222730', 'corporation',
   'Succession Test Corp', 'Wholesale', '311-222-730-00000',
   'vat', 'calendar', 'Succ St', 'Succ Bldg', 'Makati',
   'Metro Manila', '1200', 'succ@test.local', 'Succ Owner', 'President',
   '11111111-1111-1111-1111-111111111731', '11111111-1111-1111-1111-111111111731');

-- Seed the version-1 rows as superuser; the governed path is exercised below.
INSERT INTO tax_codes (id, code, description, tax_type, rate, effective_from, is_active)
VALUES ('44444444-4444-4444-4444-444444444730', 'SUCCVAT', 'Succession VAT 12%', 'vat', 12,
        DATE '2026-01-01', true);

INSERT INTO atc_codes (id, code, description, tax_category, rate, effective_from, is_active)
VALUES ('44444444-4444-4444-4444-444444444731', 'SUCCATC', 'Succession ATC 2%', 'ewt', 2,
        DATE '2026-01-01', true);

-- A second ATC family whose window is already closed, so a plain governed insert
-- can carry its own succession link without overlapping anything.
INSERT INTO atc_codes (id, code, description, tax_category, rate, effective_from, effective_to, is_active)
VALUES ('44444444-4444-4444-4444-444444444733', 'LINKATC', 'Link ATC 1%', 'ewt', 1,
        DATE '2026-01-01', DATE '2026-06-30', true);

INSERT INTO vat_codes (id, tax_code_id, vat_code, description, vat_classification,
                       transaction_type, effective_from, is_active)
VALUES ('44444444-4444-4444-4444-444444444732', '44444444-4444-4444-4444-444444444730',
        'SUCCVATC', 'Succession output VAT', 'regular', 'output_vat',
        DATE '2026-01-01', true);

-- Make the tax-code version USED: succession must be what a used version accepts.
INSERT INTO tax_detail_entries (company_id, source_doc_type, source_doc_id, tax_kind,
                                tax_code_id, tax_base, tax_rate, tax_amount,
                                posting_date, document_date)
VALUES ('22222222-2222-2222-2222-222222222730', 'SI',
        '99999999-9999-9999-9999-999999999730', 'output_vat',
        '44444444-4444-4444-4444-444444444730', 1000.00, 12.00, 120.00,
        DATE '2026-03-01', DATE '2026-03-01');

SET LOCAL ROLE authenticated;

-- ── 1. The gap that was closed: authority ───────────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111730');
SELECT is(fn_is_bir_config_maintainer(), false, 'ordinary user is not a statutory-config maintainer');
SELECT throws_ok(
  $q$SELECT fn_tax_code_succeed('44444444-4444-4444-4444-444444444730', DATE '2026-07-01', 14)$q$,
  '42501', NULL, 'an ordinary user cannot start a tax-code successor');
SELECT throws_ok(
  $q$SELECT fn_atc_code_succeed('44444444-4444-4444-4444-444444444731', DATE '2026-07-01', 3)$q$,
  '42501', NULL, 'an ordinary user cannot start an ATC successor');
SELECT throws_ok(
  $q$SELECT fn_vat_code_succeed('44444444-4444-4444-4444-444444444732', DATE '2026-07-01',
       '44444444-4444-4444-4444-444444444730')$q$,
  '42501', NULL, 'an ordinary user cannot start a VAT-code successor');

-- ── 2. Tax code: the governed succession a used version accepts ─────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111731');
SELECT ok(fn_tax_code_used('44444444-4444-4444-4444-444444444730'),
  'the version under test has priced a posted document');

SELECT throws_ok(
  $q$SELECT fn_tax_code_upsert('SUCCVAT','Succession VAT 12%','vat',14,
       '44444444-4444-4444-4444-444444444730')$q$,
  NULL, NULL, 'even a maintainer cannot rewrite a used version''s rate in place');

SELECT lives_ok(
  $q$SELECT fn_tax_code_succeed('44444444-4444-4444-4444-444444444730', DATE '2026-07-01', 14,
       NULL, NULL, 'RR 3-2026')$q$,
  'a maintainer succeeds a used tax code through the governed path');

SELECT is(
  (SELECT effective_to FROM tax_codes WHERE id = '44444444-4444-4444-4444-444444444730'),
  DATE '2026-06-30', 'the predecessor''s window closes the day before the successor starts');
SELECT is(
  (SELECT rate FROM tax_codes WHERE id = '44444444-4444-4444-4444-444444444730'),
  12.00, 'the predecessor keeps the rate that priced its documents');
SELECT is(
  (SELECT count(*)::int FROM tax_codes WHERE code = 'SUCCVAT'), 2,
  'the code now has two versions, not one rewritten row');
SELECT is(
  (SELECT supersedes_tax_code_id FROM tax_codes
   WHERE code = 'SUCCVAT' AND effective_from = DATE '2026-07-01'),
  '44444444-4444-4444-4444-444444444730'::uuid,
  'the successor records the version it supersedes — the link is no longer orphaned');
SELECT is(
  (SELECT rate FROM tax_codes WHERE code = 'SUCCVAT' AND effective_from = DATE '2026-07-01'),
  14.00, 'the successor carries the new statutory rate');

-- Resolution is the point of all of it: each document date finds its own version.
SELECT is(fn_tax_code_version_asof('SUCCVAT', DATE '2026-03-01'),
  '44444444-4444-4444-4444-444444444730'::uuid,
  'a March document still resolves to the 12% version');
SELECT is(fn_tax_code_version_asof('SUCCVAT', DATE '2026-08-01'),
  (SELECT id FROM tax_codes WHERE code = 'SUCCVAT' AND effective_from = DATE '2026-07-01'),
  'an August document resolves to the 14% successor');

SELECT is(
  (SELECT count(*)::int FROM sys_audit_logs
   WHERE table_name = 'tax_codes' AND new_data->>'_change_reason' LIKE 'RR 3-2026%'), 2,
  'the succession audits both halves — the closed predecessor and the new successor');

-- ── 3. A successor may not start on or before the version it replaces ───────────
SELECT throws_ok(
  $q$SELECT fn_tax_code_succeed('44444444-4444-4444-4444-444444444730', DATE '2026-01-01', 15)$q$,
  '23514', NULL, 'a successor starting on the predecessor''s own start date is refused');
SELECT throws_ok(
  $q$SELECT fn_tax_code_succeed('44444444-4444-4444-4444-444444444730', DATE '2025-06-01', 15)$q$,
  '23514', NULL, 'a successor starting before its predecessor is refused');

-- ── 4. Succession is ONE transaction ───────────────────────────────────────────
-- The successor insert below fails on the duplicate (code, effective_from) index.
-- If the two halves were separate calls, the predecessor's window would already
-- have moved. It must not have.
SELECT throws_ok(
  $q$SELECT fn_tax_code_succeed('44444444-4444-4444-4444-444444444730', DATE '2026-07-01', 16)$q$,
  NULL, NULL, 'a successor colliding with an existing version is refused');
SELECT is(
  (SELECT effective_to FROM tax_codes WHERE id = '44444444-4444-4444-4444-444444444730'),
  DATE '2026-06-30',
  'a refused succession leaves the predecessor''s window exactly as it was');

-- ── 5. ATC: same governed succession, where no version-rules trigger exists ─────
SELECT lives_ok(
  $q$SELECT fn_atc_code_succeed('44444444-4444-4444-4444-444444444731', DATE '2026-07-01', 3,
       NULL, 'ATC rate change')$q$,
  'a maintainer succeeds an ATC through the governed path');
SELECT is(
  (SELECT effective_to FROM atc_codes WHERE id = '44444444-4444-4444-4444-444444444731'),
  DATE '2026-06-30', 'the ATC predecessor''s window closes the day before its successor');
SELECT is(
  (SELECT supersedes_atc_code_id FROM atc_codes
   WHERE code = 'SUCCATC' AND effective_from = DATE '2026-07-01'),
  '44444444-4444-4444-4444-444444444731'::uuid,
  'the ATC successor records the version it supersedes');
SELECT is(
  (SELECT rate FROM atc_codes WHERE code = 'SUCCATC' AND effective_from = DATE '2026-07-01'),
  3.00, 'the ATC successor carries the new rate');
SELECT is(fn_atc_code_is_current('44444444-4444-4444-4444-444444444731', 'ewt', DATE '2026-08-01'),
  false, 'the superseded ATC is no longer current after its window closes');

-- The overlap rule is trg_atc_version_rules'; the governed path does not restate
-- it, so this asserts the guard is still reached through the RPC.
SELECT throws_ok(
  $q$SELECT fn_atc_code_upsert('SUCCATC','overlapping','ewt',4, NULL, true, DATE '2026-09-01')$q$,
  'P0001', NULL,
  'a second live ATC version overlapping an open window is refused through the governed path');

-- ── 6. VAT code: the successor points at the tax-code version holding the rate ──
SELECT lives_ok(
  $q$SELECT fn_vat_code_succeed('44444444-4444-4444-4444-444444444732', DATE '2026-07-01',
       (SELECT id FROM tax_codes WHERE code = 'SUCCVAT' AND effective_from = DATE '2026-07-01'),
       NULL, NULL, 'VAT rate change')$q$,
  'a maintainer succeeds a VAT code through the governed path');
SELECT is(
  (SELECT effective_to FROM vat_codes WHERE id = '44444444-4444-4444-4444-444444444732'),
  DATE '2026-06-30', 'the VAT predecessor''s window closes the day before its successor');
SELECT is(
  (SELECT supersedes_vat_code_id FROM vat_codes
   WHERE vat_code = 'SUCCVATC' AND effective_from = DATE '2026-07-01'),
  '44444444-4444-4444-4444-444444444732'::uuid,
  'the VAT successor records the version it supersedes');
SELECT is(
  (SELECT tc.rate FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
   WHERE vc.vat_code = 'SUCCVATC' AND vc.effective_from = DATE '2026-07-01'),
  14.00, 'the VAT successor resolves to the tax-code version carrying the new rate');

-- vat_codes had no version-rules trigger at all; this asserts the one added with
-- Backlog 10, so the family is guarded exactly as the other two are.
SELECT throws_ok(
  $q$SELECT fn_vat_code_upsert('44444444-4444-4444-4444-444444444730','SUCCVATC','overlapping',
       'regular','output_vat', NULL, NULL, true, DATE '2026-09-01')$q$,
  'P0001', NULL,
  'a second live VAT version overlapping an open window is refused through the governed path');
SELECT throws_ok(
  $q$SELECT fn_vat_code_succeed('44444444-4444-4444-4444-444444444732', DATE '2027-01-01',
       '44444444-4444-4444-4444-444444444730')$q$,
  '23514', NULL,
  'a VAT successor still pointing at the old tax-code version is refused');

-- ── 7. The link may also be recorded directly on a governed insert ──────────────
SELECT lives_ok(
  $q$SELECT fn_atc_code_upsert('LINKATC','successor by insert','ewt',5, NULL, true,
       DATE '2026-07-01', NULL, 'link on insert',
       '44444444-4444-4444-4444-444444444733')$q$,
  'a governed insert can record its own succession link');
SELECT is(
  (SELECT supersedes_atc_code_id FROM atc_codes
   WHERE code = 'LINKATC' AND effective_from = DATE '2026-07-01'),
  '44444444-4444-4444-4444-444444444733'::uuid,
  'the link recorded on insert points at the stated predecessor');
SELECT throws_ok(
  $q$SELECT fn_atc_code_upsert('OTHERATC','wrong predecessor','ewt',5, NULL, true,
       DATE '2027-06-01', NULL, 'mismatched',
       '44444444-4444-4444-4444-444444444733')$q$,
  'P0001', NULL, 'a successor may not supersede a version of a different code');

SELECT * FROM finish();
ROLLBACK;
