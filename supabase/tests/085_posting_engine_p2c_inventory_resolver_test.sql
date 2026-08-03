-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P2C-001 — Inventory resolver certification (COA Engine Phase B, group 3)
--
-- P2C is an EVIDENCE-BASED CERTIFICATION, not a forced migration. Investigation
-- (2026-07-25) established that the Inventory posting writers already satisfy the
-- frozen Phase P2 invariant: they read ZERO company_accounting_config. They resolve
-- posting accounts from explicit, per-entity account OWNERSHIP —
--   • goods issue      → items.inventory_account_id / items.cogs_account_id
--                        (line override goods_issue_lines.gl_expense_account_id)
--   • physical count   → items.inventory_account_id / warehouses.gl_variance_account_id
--                        (line override gl_variance_account_id)
--   • stock adjustment → items.inventory_account_id / line gl_offset_account_id
--   • stock transfer   → warehouses.gl_inventory_account_id (from/to)
-- There is no company-level config lookup and no duplicated account-resolution logic
-- to remove, so no inventory writer is changed by this phase.
--
-- Item/warehouse-scoped inventory account resolution through fn_resolve_account is
-- OUTSIDE the frozen P2 scope: it would require new mapping keys (INVENTORY/COGS/
-- VARIANCE/OFFSET) and, for warehouse-scoped accounts, a warehouse_id qualifier that
-- the frozen account_mapping contract does not have. That is a future COA enhancement
-- project after the Posting Engine resolver migration completes — not P2C work.
--
-- This test certifies the invariant structurally and is non-vacuous (it proves the
-- config-read detector fires on a writer that DOES read config).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- ── The four Inventory posting writers are present ─────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_goods_issue_source_locked_impl',
                        'fn_post_physical_count_source_locked_impl',
                        'fn_post_stock_adjustment_source_locked_impl',
                        'fn_post_stock_transfer_source_locked_impl')),
  4, 'the four Inventory posting writers are present');                                  -- 1

-- ── P2 invariant: no Inventory writer (impl or wrapper) reads company_accounting_config
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_goods_issue','fn_post_goods_issue_source_locked_impl',
                        'fn_post_physical_count','fn_post_physical_count_source_locked_impl',
                        'fn_post_stock_adjustment','fn_post_stock_adjustment_source_locked_impl',
                        'fn_post_stock_transfer','fn_post_stock_transfer_source_locked_impl')
      AND p.prosrc ~* 'company_accounting_config'),
  0, 'no Inventory posting writer reads company_accounting_config (P2 invariant already satisfied)'); -- 2

-- ── Positive evidence: accounts come from explicit item/warehouse-scoped ownership ─
SELECT ok(
  (SELECT bool_and(p.prosrc ~ 'inventory_account_id')
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('fn_post_goods_issue_source_locked_impl',
                        'fn_post_physical_count_source_locked_impl',
                        'fn_post_stock_adjustment_source_locked_impl',
                        'fn_post_stock_transfer_source_locked_impl')),
  'every Inventory writer resolves accounts from item/warehouse-scoped account ownership'); -- 3

-- ── Boundary: PXL-AUD-073 introduced exactly two governed inventory keys —
--    INVENTORY_CONTROL and PURCHASE_CLEARING — so a goods receipt can post to a
--    configured control account instead of moving stock with no ledger effect.
--    Per-item and per-warehouse account resolution remains future COA work, and
--    no COGS, variance or offset key exists. ─────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM ref_mapping_key
    WHERE key_code ~* 'cogs|variance|offset'),
  0, 'ref_mapping_key has no COGS/variance/offset key — item/warehouse-scoped resolution is future COA work'); -- 4

-- SALES_DELIVERY_CLEARING joined on 2026-08-03: the outbound mirror of
-- PURCHASE_CLEARING, so a delivery can relieve stock into goods-delivered-not-
-- invoiced and the invoice can recognise it as COGS without relieving twice.
SELECT set_eq(
  $$SELECT key_code::text FROM ref_mapping_key WHERE key_code ~* 'invent|goods|clearing'$$,
  $$VALUES ('INVENTORY_CONTROL'), ('PURCHASE_CLEARING'), ('SALES_DELIVERY_CLEARING')$$,
  'exactly the three governed inventory movement keys exist');

-- ── Non-vacuous: the config-read detector fires on code that DOES read config ────
-- (Check Voucher is migrated in P2D; an out-of-scope reconciliation report still
--  reads config to identify control accounts.)
SELECT ok(
  (SELECT p.prosrc ~* 'company_accounting_config' FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_ap_subledger_gl_reconciliation_asof'),
  'config-read detector is non-vacuous (an out-of-scope reconciliation report still reads config)'); -- 5

SELECT * FROM finish();
ROLLBACK;
