-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-12 — Tax Reference Consolidation (gap MD-32)
--
-- MD-32 was already resolved by prior work; this test LOCKS the consolidated
-- invariants as a permanent regression gate and proves the thin MDP-12 surface:
--   * ref_atc_codes / ewt_codes / fwt_codes are gone; atc_codes is the single ATC
--     source; the former ref_atc_codes FKs point to atc_codes.
--   * vw_tax_reference_catalog unifies tax_codes ∪ atc_codes (with is_current).
--   * fn_tax_reference_asof delegates to the existing as-of resolvers (normalized,
--     validated), and the underlying masters stay MDP-01 read-only (governed).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000',
       '11111111-1111-1111-1111-1111111110c1', 'authenticated', 'authenticated',
       'mdp12@test.local', '', now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}';

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- ── Consolidation invariants (MD-32 already resolved — lock it) ───────────────
SELECT ok(to_regclass('public.ref_atc_codes') IS NULL,
  'ref_atc_codes has been dropped (ATC consolidation complete)');
SELECT ok(to_regclass('public.ewt_codes') IS NULL AND to_regclass('public.fwt_codes') IS NULL,
  'the parallel ewt_codes / fwt_codes tables have been consolidated away');
SELECT is(
  (SELECT confrelid::regclass::text FROM pg_constraint WHERE conname='receipt_lines_atc_code_id_fkey'),
  'atc_codes', 'the former ref_atc_codes FK (receipt_lines.atc_code_id) now targets atc_codes');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110c1');

-- ── Consolidated catalog (vw_tax_reference_catalog) ───────────────────────────
SELECT has_view('vw_tax_reference_catalog');
SELECT ok(
  (SELECT count(*)::int FROM vw_tax_reference_catalog WHERE reference_type='tax_code') > 0,
  'the catalog exposes tax_codes references');
SELECT ok(
  (SELECT count(*)::int FROM vw_tax_reference_catalog WHERE reference_type='atc_code') > 0,
  'the catalog exposes atc_codes references');
SELECT ok(
  (SELECT bool_or(is_current) FROM vw_tax_reference_catalog
   WHERE reference_type='tax_code' AND code='VAT12-OUT'),
  'a seeded active in-window tax code reports is_current = true');
SELECT ok(
  (SELECT count(*)::int FROM vw_tax_reference_catalog) > 0,
  'the catalog is readable by an authenticated user (security_invoker)');

-- ── Canonical as-of facade (delegates to existing resolvers) ──────────────────
SELECT is(
  fn_tax_reference_asof('tax_code','VAT12-OUT'),
  fn_tax_code_version_asof('VAT12-OUT'),
  'fn_tax_reference_asof(tax_code) delegates to fn_tax_code_version_asof');
SELECT is(
  fn_tax_reference_asof('atc_code','WC158','ewt'),
  fn_atc_version_asof('WC158','ewt'),
  'fn_tax_reference_asof(atc_code) delegates to fn_atc_version_asof');
SELECT is(
  fn_tax_reference_asof('atc_code','wc158','ewt'),
  fn_tax_reference_asof('atc_code','WC158','ewt'),
  'the facade normalizes the code (case-insensitive) before resolving');
SELECT ok(
  fn_tax_reference_asof('tax_code','NO-SUCH-CODE') IS NULL,
  'the facade returns NULL for a code that does not resolve');
SELECT throws_ok(
  $q$SELECT fn_tax_reference_asof('atc_code','WC158')$q$,
  '22023', NULL, 'resolving an ATC code without a tax_category raises');
SELECT throws_ok(
  $q$SELECT fn_tax_reference_asof('mystery','WC158','ewt')$q$,
  '22023', NULL, 'an unknown reference type raises');

-- ── Governance preserved (MDP-01 read-only) ───────────────────────────────────
SELECT throws_ok(
  $q$INSERT INTO atc_codes (code, description, tax_category, rate)
     VALUES ('ZZZ999','Rogue','ewt',1.0)$q$,
  '42501', NULL, 'atc_codes remains read-only to authenticated users (MDP-01 governance)');
SELECT throws_ok(
  $q$INSERT INTO tax_codes (code, description, tax_type, rate)
     VALUES ('ZZZ999','Rogue','vat',1.0)$q$,
  '42501', NULL, 'tax_codes remains read-only to authenticated users (MDP-01 governance)');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
