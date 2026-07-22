-- PXL-AUD-069: Non-security_invoker reporting views bypass RLS (Critical, cross-company leak).
--
-- Nine postgres-owned reporting views were created without `security_invoker`.
-- A view without security_invoker executes with the view OWNER's privileges;
-- because these views are owned by `postgres` (BYPASSRLS) and are granted SELECT
-- to `authenticated`, they returned other companies' rows to any logged-in user
-- through PostgREST — bypassing the Row-Level Security enforced on their base
-- tables. Confirmed empirically: an authenticated member of only one company read
-- another company's AP aging, payment register, receipt register, and SLP/RELIEF
-- export.
--
-- Fix (entirely server-side): enable `security_invoker = on` so each view is
-- evaluated with the CALLER's privileges, applying the base tables' RLS to the
-- authenticated user. Legitimate members still see their own company's rows
-- (base-table member SELECT policies) and non-members see zero rows. No client
-- filtering, no RLS weakening. All referenced base tables already grant SELECT to
-- `authenticated`, and the two global reference tables (ref_reason_codes,
-- vat_codes) have permissive read policies, so no legitimate access regresses.
--
-- This ALTER is idempotent (re-running sets the same option).

ALTER VIEW public.vw_ap_aging              SET (security_invoker = on);
ALTER VIEW public.vw_credit_memo_register  SET (security_invoker = on);
ALTER VIEW public.vw_debit_memo_register   SET (security_invoker = on);
ALTER VIEW public.vw_deposits_in_transit   SET (security_invoker = on);
ALTER VIEW public.vw_outstanding_checks    SET (security_invoker = on);
ALTER VIEW public.vw_payment_register      SET (security_invoker = on);
ALTER VIEW public.vw_receipt_register      SET (security_invoker = on);
ALTER VIEW public.vw_sdm_register          SET (security_invoker = on);
ALTER VIEW public.vw_slp_export            SET (security_invoker = on);
