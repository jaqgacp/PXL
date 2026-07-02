-- ══════════════════════════════════════════════════════════════════════════════
-- Authenticated table grants (PXL-AUD-026)
--
-- The migration chain defined RLS policies for every table but never granted
-- table privileges: on a migrations-only database the `authenticated` role has
-- no SELECT/INSERT/UPDATE/DELETE on ANY of the 143 public tables, so the whole
-- app is dead through PostgREST. Existing environments only work because they
-- were provisioned under Supabase's legacy auto-expose default privileges —
-- behavior the platform removes on 2026-10-30, at which point ungoverned
-- environments break.
--
-- Every public table has RLS enabled (verified 2026-07-02: 0 tables without),
-- so RLS remains the security boundary; these grants restore the standard
-- Supabase posture. `anon` intentionally receives nothing: the app requires
-- login for all data access.
-- ══════════════════════════════════════════════════════════════════════════════

GRANT USAGE ON SCHEMA public TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Future tables/sequences created by migrations (run as postgres) inherit the
-- same posture automatically.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO service_role;
