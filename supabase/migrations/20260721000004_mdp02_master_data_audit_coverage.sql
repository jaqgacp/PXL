-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-02 (gap MD-30) — Master-Data Audit Coverage
--
-- Purpose: close the remaining reference/config master-data audit-trail gaps by
-- attaching the EXISTING generic `fn_audit_trigger` to the master tables that are
-- still uncovered. This is the audit-coverage package; it reuses the established
-- trigger mechanism and does NOT invent a new pattern and does NOT touch the
-- MDP-01 / PXL-AUD-063 governed-RPC audit surfaces.
--
-- ── Coverage inventory result (working-tree reality) ──────────────────────────
-- Most reference/config masters the MD-30 gap named are ALREADY covered by
-- `fn_audit_trigger` (attached in 20260630000021_gap_fill and 20260701000005_
-- audit_cas): chart_of_accounts, payment_terms, number_series, departments,
-- cost_centers, warehouses, bank_accounts, compliance_profiles, employees,
-- approval_workflows, sys_feature_enablement, plus every party/item/transaction
-- master. The global statutory tax-reference tables (tax_codes, vat_codes,
-- atc_codes) and BIR config (bir_forms, bir_form_mappings) are deliberately
-- RPC-audited (MDP-01 / PXL-AUD-063) and MUST NOT receive a trigger — doing so
-- would double-log. `ewt_codes` / `fwt_codes` / `ref_atc_codes` do not exist
-- (consolidated earlier).
--
-- The genuinely-uncovered reference/config masters in MDP-02's named scope are
-- exactly these three company-scoped tables, written today via direct RLS-gated
-- client DML with NO audit capture:
--   * units_of_measure       (UOM master)
--   * item_categories        (item category master)
--   * percentage_tax_codes   (company-scoped percentage-tax code master — the
--                             tax-code master not covered by MDP-01's global RPC
--                             governance; MDP-01 explicitly left it out of scope)
--
-- All three carry `company_id`, so `fn_audit_trigger` records company context,
-- actor (auth.uid()), action, before/after row images, and timestamp exactly as
-- for every other trigger-audited master. Free-text change reasons are not
-- captured for trigger-audited masters (that is only for the governed global
-- statutory RPCs) — an accepted, documented trade-off for company-scoped masters.
--
-- Out of MDP-02 scope (named for later packages, deliberately NOT touched here):
--   * fiscal_years / fiscal_periods            -> MDP-06 (fiscal provisioning)
--   * user_company_memberships                 -> MDP-03 (access control & SOD)
--   * company_accounting_config                -> MDP-07 (config provisioning)
--   * currencies / exchange_rates, ref_* seeds -> static reference data
--   * fixed_asset_categories                   -> Fixed Assets phase
--
-- Idempotent (DROP TRIGGER IF EXISTS / CREATE TRIGGER), forward-only. No schema
-- change, no RLS change, no backfill. Rollback = drop the three added triggers.
-- ══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'units_of_measure',
    'item_categories',
    'percentage_tax_codes'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_audit_%1$s ON %1$s;
       CREATE TRIGGER trg_audit_%1$s
         AFTER INSERT OR UPDATE OR DELETE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();',
      t
    );
  END LOOP;
END;
$$;
