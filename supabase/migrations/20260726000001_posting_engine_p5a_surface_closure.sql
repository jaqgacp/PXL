-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.0 (Surface Closure)
--
-- Implements ONLY the three items approved after the P5 architecture review. This
-- migration does NOT introduce the Kernel Totality Guard (§4.6), does NOT enforce
-- posting_origin, does NOT migrate any of the 24 direct-insert forward writers, and
-- whitelists nothing. Those remain P5.1 and are not started here.
--
-- WHAT THE INVESTIGATION FOUND (live catalog; authoritative over prose)
--   The General Ledger itself is already closed to external callers: journal_entries
--   and journal_entry_lines have RLS enabled with a SELECT policy and ZERO write
--   policies, so `authenticated` is denied by absence of policy despite holding table
--   grants. The exposed surfaces were elsewhere:
--
--     (a) fn_add_posting_line — a pure persistence helper since P3A (one INSERT, a
--         membership check, no admission control) carried an explicit EXECUTE grant to
--         `authenticated`. It has NO client caller anywhere in src/. Its only containment
--         was the parent-status immutability trigger.
--     (b) Ten client-entry GL writers plus three trigger functions carried EXECUTE for
--         PUBLIC (`=X/postgres`), which is why `anon` resolved as privileged. Latent
--         only — `anon` holds no table SELECT and auth.uid() is NULL — but it violates
--         default-deny.
--     (c) Six accounting-owned DERIVED tables carried membership-only write policies,
--         letting any company member author computed accounting state directly through
--         PostgREST. This was demonstrated: UPDATE stock_balances (1 row) and
--         INSERT INTO inventory_transactions (1 row) both succeeded as a genuine member.
--         fn_post_sales_invoice reads stock_balances.wac_unit_cost to compute COGS, so a
--         member could pre-set valuation and have the certified engine post a COGS amount
--         derived from tampered state, with no journal and no accounting audit.
--
-- WHY THIS IS SAFE
--   Every writer of all six tables is SECURITY DEFINER (28 functions verified), so the
--   legitimate paths run as the table owner and are unaffected by RLS. The frontend
--   reads all six and writes none (verified across src/). No pgTAP test writes them
--   while impersonating `authenticated`.
--
-- WHAT IS DELIBERATELY EXCLUDED (material finding — see the P5.0 report)
--   bank_recon_items and book_tax_reconciliation were named as candidates by the
--   investigation on the assumption that their writers were all SECURITY DEFINER. That
--   assumption is FALSE: BankReconciliationPage.tsx writes bank_recon_items directly
--   (.delete()/.insert()) and BookToTaxReconciliationPage.tsx writes
--   book_tax_reconciliation directly (.insert()/.update()). Closing them would break
--   working UI, which the accounting contract forbids. They stay open and are carried
--   forward as their own scoped item.
--
-- ACCOUNTING CONTRACT
--   Zero accounting behaviour change. No function body, no posting writer, no policy on
--   journal_entries / journal_entry_lines / tax_detail_entries, and no schema object is
--   modified. This migration only removes privileges that no legitimate path uses.
-- ══════════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────────────
-- PART A — Internal persistence helper: remove the `authenticated` EXECUTE grant
--
-- fn_add_posting_line is invoked only from inside SECURITY DEFINER posting writers,
-- which execute as the function owner and therefore do not consult this grant.
-- service_role (a privileged backend key that already bypasses RLS) is left as-is;
-- narrowing it is not part of the approved scope.
-- ──────────────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.fn_add_posting_line(
  uuid, integer, uuid, text, numeric, numeric,
  uuid, uuid, uuid, uuid, uuid, uuid
) FROM authenticated;

-- ──────────────────────────────────────────────────────────────────────────────
-- PART B — Remove PUBLIC (and therefore `anon`) EXECUTE from GL writers
--
-- These functions were left at PostgreSQL's default `PUBLIC = EXECUTE`. A PUBLIC grant
-- cannot be revoked from one role, so each is revoked from PUBLIC and then re-granted
-- to exactly the roles that legitimately held it. `authenticated` and `service_role`
-- keep the privilege they already had; `anon` loses it. Four of these already carried an
-- explicit service_role grant, which is the established convention in this schema.
-- ──────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_sig TEXT;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.fn_close_fiscal_year(uuid, uuid, date)',
    'public.fn_dispose_fixed_asset(jsonb)',
    'public.fn_post_check_voucher(uuid)',
    'public.fn_post_manual_je(uuid, uuid, date, text, text, boolean, jsonb, text)',
    'public.fn_post_receipt(uuid)',
    'public.fn_post_sales_invoice(uuid)',
    'public.fn_post_vendor_bill(uuid)',
    'public.fn_record_impairment(jsonb)',
    'public.fn_register_fixed_asset(jsonb)',
    'public.fn_save_cash_sale(jsonb, jsonb, numeric)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', v_sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_sig);
  END LOOP;
END;
$$;

-- Trigger functions are never invoked by a caller: PostgreSQL checks EXECUTE at
-- CREATE TRIGGER time, not at fire time, so the already-created triggers keep working
-- with no grant to anyone. These three write journal_entries and must not be reachable.
REVOKE EXECUTE ON FUNCTION public.fn_link_fixed_asset_journal_source()    FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_link_purchase_return_journal_source() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_link_schedule_journal_source()        FROM PUBLIC;

-- ──────────────────────────────────────────────────────────────────────────────
-- PART C — Accounting-owned derived tables: member-writable -> deny-all writes
--
-- This applies the pattern already certified on tax_detail_entries: keep the existing
-- membership-scoped SELECT policy untouched, and replace every write policy with an
-- explicit, self-documenting denial. Writes continue to flow exclusively through the
-- SECURITY DEFINER posting writers that own each table.
--
-- Explicit denial is preferred over simply dropping the write policies: default-deny by
-- absence is invisible to a reader and indistinguishable from an oversight, whereas a
-- `false` policy states the ownership rule and is directly assertable in the guard test.
-- ──────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_tbl    TEXT;
  v_policy TEXT;
BEGIN
  FOREACH v_tbl IN ARRAY ARRAY[
    'stock_balances',              -- inventory quantity + valuation (wac_unit_cost, total_cost)
    'inventory_cost_layers',       -- FIFO/specific cost layers consumed by COGS
    'inventory_transactions',      -- inventory movement ledger
    'asset_depreciation_entries',  -- fixed-asset depreciation ledger
    'amortization_entries',        -- amortization schedule ledger
    'revenue_recognition_entries'  -- revenue recognition schedule ledger
  ] LOOP
    -- Drop only the WRITE policies; the SELECT policy is the read contract and stays.
    FOR v_policy IN
      SELECT policyname FROM pg_policies
      WHERE schemaname = 'public' AND tablename = v_tbl AND cmd <> 'SELECT'
    LOOP
      EXECUTE format('DROP POLICY %I ON public.%I', v_policy, v_tbl);
    END LOOP;

    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (false)',
      v_tbl || '_no_direct_insert', v_tbl);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (false) WITH CHECK (false)',
      v_tbl || '_no_direct_update', v_tbl);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (false)',
      v_tbl || '_no_direct_delete', v_tbl);
  END LOOP;
END;
$$;

COMMENT ON TABLE public.stock_balances IS
  'Inventory quantity and valuation. Owned by the SECURITY DEFINER posting writers; '
  'authenticated writes are denied by policy (Posting Engine P5.0). Reads are membership-scoped.';
COMMENT ON TABLE public.inventory_cost_layers IS
  'Inventory cost layers consumed by COGS. Owned by the SECURITY DEFINER posting writers; '
  'authenticated writes are denied by policy (Posting Engine P5.0). Reads are membership-scoped.';
COMMENT ON TABLE public.inventory_transactions IS
  'Inventory movement ledger. Owned by the SECURITY DEFINER posting writers; '
  'authenticated writes are denied by policy (Posting Engine P5.0). Reads are membership-scoped.';
COMMENT ON TABLE public.asset_depreciation_entries IS
  'Fixed-asset depreciation ledger. Owned by the SECURITY DEFINER posting writers; '
  'authenticated writes are denied by policy (Posting Engine P5.0). Reads are membership-scoped.';
COMMENT ON TABLE public.amortization_entries IS
  'Amortization schedule ledger. Owned by the SECURITY DEFINER posting writers; '
  'authenticated writes are denied by policy (Posting Engine P5.0). Reads are membership-scoped.';
COMMENT ON TABLE public.revenue_recognition_entries IS
  'Revenue recognition schedule ledger. Owned by the SECURITY DEFINER posting writers; '
  'authenticated writes are denied by policy (Posting Engine P5.0). Reads are membership-scoped.';
