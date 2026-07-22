-- ============================================================================
-- PXL-AUD-069 - Permanent guard: no authenticated-granted view may bypass RLS
--
-- This guard prevents the whole class of defect fixed under PXL-AUD-069 from
-- reappearing. A view is a cross-company exposure risk when ALL of the following
-- hold:
--   * it is granted SELECT to the `authenticated` role (reachable via PostgREST);
--   * its OWNER bypasses RLS (a superuser or BYPASSRLS role, e.g. `postgres`);
--   * it is NOT declared security_invoker (so it runs with the owner's
--     RLS-bypassing privileges); AND
--   * its definition embeds no tenant-isolation predicate
--     (is_company_member / user_company_memberships / auth.uid / can_admin_company).
--
-- Any such view returns other tenants' rows to any authenticated user. The guard
-- asserts the set of such views is empty. It runs in every regression and
-- canonical lane, so adding a new authenticated view without security_invoker (or
-- an explicit membership predicate) fails the build.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(2);

CREATE TEMP TABLE _rls_bypassing_views AS
SELECT c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'v'
  -- reachable by authenticated users via PostgREST
  AND EXISTS (
    SELECT 1 FROM information_schema.role_table_grants g
    WHERE g.table_schema = 'public' AND g.table_name = c.relname
      AND g.grantee = 'authenticated' AND g.privilege_type = 'SELECT')
  -- owner bypasses RLS
  AND EXISTS (
    SELECT 1 FROM pg_roles r
    WHERE r.oid = c.relowner AND (r.rolsuper OR r.rolbypassrls))
  -- not security_invoker
  AND NOT (coalesce(c.reloptions::text, '') ~* 'security_invoker=(on|true)')
  -- and no embedded tenant-isolation predicate
  AND pg_get_viewdef(c.oid, true) !~* '(is_company_member|user_company_memberships|auth\.uid|can_admin_company)';

SELECT is(
  (SELECT count(*)::int FROM _rls_bypassing_views),
  0,
  'no authenticated-granted, RLS-bypassing view lacks tenant isolation (security_invoker or membership predicate)');

SELECT is(
  (SELECT coalesce(string_agg(relname, ', ' ORDER BY relname), '(none)') FROM _rls_bypassing_views),
  '(none)',
  'offending view list is empty');

SELECT * FROM finish();
ROLLBACK;
