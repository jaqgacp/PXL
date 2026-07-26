-- ══════════════════════════════════════════════════════════════════════════════
-- Posting Engine — Phase P5.1 Stage 1 (Kernel Totality Guard, OBSERVE-ONLY)
--
-- Implements the frozen §4.6 Kernel Totality Guard in its first, non-enforcing
-- stage, plus the kernel capability and evidence infrastructure the staged
-- migration of the 24 direct-insert forward writers depends on.
--
-- THE GUARD IS NOT ARMED. It records; it rejects nothing. Arming is a separate
-- one-line migration and is gated on the violation census draining to zero.
--
-- ── HOW ORIGIN IS PROVEN (design note) ────────────────────────────────────────
-- The frozen spec suggests "a transaction-scoped posting-context flag set only by
-- the kernel". A settable flag is exactly the shape that produced Critical
-- PXL-AUD-070 (the `pxl.allow_demo_reset` GUC the `authenticated` role could set),
-- so this implementation does NOT use one. It reads the plpgsql call stack via
-- GET DIAGNOSTICS ... PG_CONTEXT, which a caller cannot fabricate: a write is
-- kernel-origin if and only if a sanctioned kernel is genuinely on the stack.
-- This satisfies the frozen intent structurally and removes the bypass class.
--
-- HONEST SCOPE OF THE CONTROL: this is a *discipline* control, not an
-- authorization control. Authorization is owned by RLS (closed in P5.0, where the
-- ledger already has zero write policies for `authenticated`). The guard's threat
-- model is in-database code — a future function, migration, or developer shortcut
-- writing the ledger outside the kernel.
--
-- ── WHY THE KERNEL SIGNATURE IS EXTENDED (material finding) ───────────────────
-- The 24 direct-insert writers CANNOT be routed through the 7-argument kernel
-- byte-for-byte. Verified against the live catalog:
--   • 23 of 24 resolve their own fiscal period and raise their OWN user-visible
--     "No open fiscal period …" message (23 distinct wordings; three are asserted
--     by existing tests). The kernel resolves internally and raises one shared
--     message, so routing through it would change 23 user-visible behaviours.
--   • Every one of them writes computed header totals; the kernel writes 0/0 and
--     relies on fn_finalize_journal_entry, which none of them calls.
--   • Four set `posting_origin`; three set `entry_class` / `auto_reverse`. The
--     7-argument kernel cannot express any of these.
-- The kernel is therefore extended ADDITIVELY so a writer can hand it what it
-- already writes — its own resolved period, status, totals, and metadata — and
-- keep its own validation and messages verbatim. No accounting rule, ordering, or
-- posting plan changes. Per the P3A finding, an additive OVERLOAD is not
-- deployment-safe ("function ... is not unique" at CALL time), so the function is
-- dropped and re-created with defaulted parameters; all seven existing 7-argument
-- callers keep resolving and behave identically.
-- ══════════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 1 — Violation evidence
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sys_posting_guard_violations (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  observed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  table_name         TEXT NOT NULL,
  operation          TEXT NOT NULL,
  company_id         UUID,
  je_id              UUID,
  je_number          TEXT,
  reference_doc_type TEXT,
  writer_function    TEXT,
  origin_context     TEXT NOT NULL,
  session_user_name  TEXT NOT NULL,
  current_user_name  TEXT NOT NULL,
  maintenance_lane   BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE public.sys_posting_guard_violations IS
  'Posting Engine P5.1 evidence: every journal write whose call stack does not contain '
  'a sanctioned kernel. Written by the observe-only Kernel Totality Guard. The guard is '
  'armed only once this table drains to zero outside the maintenance lane.';

CREATE INDEX IF NOT EXISTS idx_pgv_writer ON public.sys_posting_guard_violations (writer_function, table_name);

ALTER TABLE public.sys_posting_guard_violations ENABLE ROW LEVEL SECURITY;

-- Evidence is system-owned. `authenticated` may read violations for its own
-- companies (so the condition is diagnosable in-product) and may never write.
DROP POLICY IF EXISTS pgv_read ON public.sys_posting_guard_violations;
CREATE POLICY pgv_read ON public.sys_posting_guard_violations
  FOR SELECT TO authenticated
  USING (company_id IS NOT NULL AND is_company_member(company_id));
DROP POLICY IF EXISTS pgv_no_direct_insert ON public.sys_posting_guard_violations;
CREATE POLICY pgv_no_direct_insert ON public.sys_posting_guard_violations
  FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS pgv_no_direct_update ON public.sys_posting_guard_violations;
CREATE POLICY pgv_no_direct_update ON public.sys_posting_guard_violations
  FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS pgv_no_direct_delete ON public.sys_posting_guard_violations;
CREATE POLICY pgv_no_direct_delete ON public.sys_posting_guard_violations
  FOR DELETE TO authenticated USING (false);

GRANT SELECT ON public.sys_posting_guard_violations TO authenticated;

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 2 — The Kernel Totality Guard (OBSERVE-ONLY)
--
-- Enforcement is a compile-time constant here, not a runtime setting. There is
-- deliberately no GUC, no config row, and no session knob that could arm or
-- disarm the guard: arming is a governed migration that flips this constant after
-- the census drains. That is what keeps this control free of the PXL-AUD-070
-- bypass class.
-- ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_posting_kernel_origin(p_context TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  -- The two sanctioned kernels of the frozen §4.7 census, plus the line-persistence
  -- helpers they and the migrated writers delegate to, and the finalizer that owns
  -- the header total update. Nothing else is kernel-origin.
  SELECT p_context ~ ('fn_create_posted_journal_entry'
                   || '|fn_reverse_posted_journal_entry'
                   || '|fn_finalize_journal_entry'
                   || '|fn_add_posting_line'
                   || '|fn_add_sales_invoice_posting_line');
$$;

CREATE OR REPLACE FUNCTION public.fn_guard_journal_kernel_origin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  -- P5.1 Stage 1: observe only. Arming flips this to true in its own migration,
  -- after the violation census drains to zero.
  c_enforce  CONSTANT BOOLEAN := false;
  v_ctx      TEXT;
  v_row      JSONB;
  v_writer   TEXT;
  v_maint    BOOLEAN;
BEGIN
  GET DIAGNOSTICS v_ctx = PG_CONTEXT;

  IF fn_posting_kernel_origin(v_ctx) THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  -- The trigger serves two tables with different column sets, so the row is read
  -- as jsonb: a RECORD field reference would have to resolve against both shapes.
  IF TG_OP = 'DELETE' THEN v_row := to_jsonb(OLD); ELSE v_row := to_jsonb(NEW); END IF;

  -- Innermost non-guard plpgsql frame: the function that actually issued the write.
  -- Any schema qualifier must be accepted; anchoring on `public.` alone would skip
  -- the innermost frame and mis-attribute the write to an outer caller.
  SELECT m[1] INTO v_writer
  FROM regexp_matches(v_ctx, 'PL/pgSQL function (?:[a-zA-Z0-9_]+\.)?([a-zA-Z0-9_]+)\(', 'g') m
  WHERE m[1] <> 'fn_guard_journal_kernel_origin'
  LIMIT 1;

  -- The sanctioned maintenance/seed lane of frozen §4.6 (canonical seed, demo
  -- reset). It reuses the certified privileged-session_user gate from PXL-AUD-070
  -- rather than introducing a second, weaker one.
  v_maint := fn_demo_reset_bypass_authorized();

  INSERT INTO sys_posting_guard_violations (
    table_name, operation, company_id, je_id, je_number, reference_doc_type,
    writer_function, origin_context, session_user_name, current_user_name, maintenance_lane
  ) VALUES (
    TG_TABLE_NAME, TG_OP,
    (v_row->>'company_id')::UUID,
    COALESCE(v_row->>'je_id', v_row->>'id')::UUID,
    v_row->>'je_number',
    v_row->>'reference_doc_type',
    COALESCE(v_writer, '(direct SQL)'), v_ctx, session_user, current_user, v_maint
  );

  IF c_enforce AND NOT v_maint THEN
    RAISE EXCEPTION
      'Posting Engine totality: % on % did not originate from a sanctioned kernel (writer: %)',
      TG_OP, TG_TABLE_NAME, COALESCE(v_writer, '(direct SQL)')
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_guard_journal_kernel_origin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_posting_kernel_origin(TEXT) FROM PUBLIC;

-- The guard runs LAST among BEFORE triggers (alphabetical order within timing), so
-- it observes only writes that every existing invariant already accepted; it can
-- neither mask nor reorder an existing rejection.
DROP TRIGGER IF EXISTS zz_trg_journal_entries_kernel_origin ON public.journal_entries;
CREATE TRIGGER zz_trg_journal_entries_kernel_origin
  BEFORE INSERT OR UPDATE OR DELETE ON public.journal_entries
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_journal_kernel_origin();

DROP TRIGGER IF EXISTS zz_trg_journal_entry_lines_kernel_origin ON public.journal_entry_lines;
CREATE TRIGGER zz_trg_journal_entry_lines_kernel_origin
  BEFORE INSERT OR UPDATE OR DELETE ON public.journal_entry_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_journal_kernel_origin();

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 3 — posting_origin (P1 metadata field, §4.1 / invariant 13)
--
-- Backfill rule, provably unambiguous and the exact semantics of invariant 13:
-- a journal authored through the manual-journal path is `manual`; every other
-- journal is engine-generated, therefore `system`. Only NULLs are touched; no
-- existing value is overwritten. On a fresh schema this is a no-op (empty table),
-- so it changes no canonical output — it repairs pre-existing rows only.
-- Per-writer population is NOT introduced here: each writer starts setting the
-- column as it migrates, so the current canonical output stays byte-for-byte.
-- ──────────────────────────────────────────────────────────────────────────────
UPDATE public.journal_entries
SET posting_origin = CASE WHEN reference_doc_type = 'MANUAL' THEN 'manual' ELSE 'system' END
WHERE posting_origin IS NULL;

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 4 — Kernel capability extension (additive; all existing callers unchanged)
--
-- Drop-and-recreate, not an overload: P3A proved an additive overload makes every
-- existing call ambiguous at CALL time. The first seven parameters and their
-- semantics are untouched, so the seven current callers
-- (fn_post_sales_invoice, fn_post_vendor_bill, fn_post_receipt,
--  fn_post_payment_voucher, fn_post_cash_purchase_source_locked_impl,
--  fn_post_withholding_remittance, fn_reverse_posted_journal_entry)
-- keep resolving to the same behaviour: period resolved internally, status
-- 'posted', totals 0/0, no metadata.
-- ──────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.fn_create_posted_journal_entry(uuid, uuid, text, date, text, text, uuid);

CREATE FUNCTION public.fn_create_posted_journal_entry(
  p_company_id         UUID,
  p_branch_id          UUID,
  p_je_number          TEXT,
  p_je_date            DATE,
  p_description        TEXT,
  p_reference_doc_type TEXT,
  p_reference_doc_id   UUID,
  -- Additive: a migrating writer hands the kernel what it already writes, so its
  -- own validation, period resolution, and error messages survive verbatim.
  p_fiscal_period_id   UUID    DEFAULT NULL,
  p_status             TEXT    DEFAULT 'posted',
  p_total_debit        NUMERIC DEFAULT 0,
  p_total_credit       NUMERIC DEFAULT 0,
  p_posting_origin     TEXT    DEFAULT NULL,
  p_entry_class        TEXT    DEFAULT 'regular',
  p_auto_reverse       BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_period_id UUID;
  v_je_id     UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  PERFORM fn_assert_posting_source(
    p_reference_doc_type,
    p_reference_doc_id,
    p_company_id
  );

  -- A caller that already resolved and validated its own period supplies it, so
  -- its own "No open fiscal period …" wording is the one the user still sees.
  IF p_fiscal_period_id IS NULL THEN
    v_period_id := fn_require_open_fiscal_period(p_company_id, p_je_date, true);
  ELSE
    v_period_id := p_fiscal_period_id;
  END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, posting_origin, entry_class, auto_reverse,
    created_by, updated_by
  ) VALUES (
    p_company_id, p_branch_id, p_je_number, p_je_date, v_period_id,
    p_description, UPPER(BTRIM(p_reference_doc_type)), p_reference_doc_id,
    COALESCE(p_status, 'posted'),
    COALESCE(p_total_debit, 0), COALESCE(p_total_credit, 0),
    p_posting_origin, COALESCE(p_entry_class, 'regular'), COALESCE(p_auto_reverse, false),
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_je_id;

  RETURN v_je_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fn_create_posted_journal_entry(
  uuid, uuid, text, date, text, text, uuid, uuid, text, numeric, numeric, text, text, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_posted_journal_entry(
  uuid, uuid, text, date, text, text, uuid, uuid, text, numeric, numeric, text, text, boolean
) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 5 — MODULE 1 MIGRATION: the memo lump posters (CM / DM / VC)
--
-- Chosen first because the three are uniform, self-contained, and already set
-- every header column the extended kernel now carries. Each keeps its own status
-- gate, its own period resolution, and its own verbatim error message; only the
-- direct INSERT is replaced by the kernel call. Line construction, ordering,
-- line_role, amounts, tax-detail writes, and document status updates are copied
-- through unchanged.
--
-- Header equality per writer (asserted in test 092):
--   je_number, je_date, fiscal_period_id, description, reference_doc_type/id,
--   status='posted', total_debit=total_credit=<document total>,
--   posting_origin='system', entry_class='regular', auto_reverse=false.
-- ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_post_credit_memo_vat_lump_impl(p_cm_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       credit_memos%ROWTYPE;
  v_ar        UUID;
  v_vat       UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_dr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM credit_memos WHERE id = p_cm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Credit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Credit memo cannot be posted in status: %', v_rec.status;
  END IF;

  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.cm_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.cm_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.cm_date
    AND end_date >= v_rec.cm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for CM date %. Create or unlock a fiscal period first.', v_rec.cm_date;
  END IF;

  -- P5.1 Module 1: the direct header INSERT is replaced by the sanctioned kernel.
  -- Every value below is the one this function previously wrote itself.
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-CM-' || v_rec.cm_number, v_rec.cm_date,
    'Credit Memo ' || v_rec.cm_number || ' — ' || v_rec.customer_name_snapshot,
    'CM', v_rec.id,
    v_fp_id, 'posted', v_rec.total_amount, v_rec.total_amount, 'system'
  );

  FOR v_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM credit_memo_lines
    WHERE credit_memo_id = v_rec.id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.revenue_account_id,
            'Sales return — ' || v_line.ln_desc, v_line.net_sum, 0, 'base', auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_line.net_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_vat,
            'Output VAT reversal — ' || v_rec.cm_number, v_rec.total_vat_amount, 0, 'tax', auth.uid(), auth.uid());
    v_total_dr := v_total_dr + v_rec.total_vat_amount;
    v_line_no  := v_line_no + 1;
  END IF;

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, v_line_no, v_ar,
          'AR — ' || v_rec.customer_name_snapshot, 0, v_rec.total_amount, 'control', auth.uid(), auth.uid());

  IF ABS(v_rec.total_amount - v_total_dr) > 0.02 THEN
    RAISE EXCEPTION 'CM journal entry unbalanced: DR=% CR=%. Ensure all CM lines have revenue accounts.', v_total_dr, v_rec.total_amount;
  END IF;

  UPDATE credit_memos SET
    status = 'applied', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_cm_id;

  -- Negative output VAT in tax ledger (reversal of original SI output VAT)
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'CM', v_rec.id,
      'output_vat', -v_rec.total_taxable_amount, -v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.cm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      true
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_post_debit_memo_vat_lump_impl(p_dm_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       debit_memos%ROWTYPE;
  v_ar        UUID;
  v_vat       UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 2;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM debit_memos WHERE id = p_dm_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Debit memo not found'; END IF;
  IF NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF v_rec.status NOT IN ('draft','approved') THEN
    RAISE EXCEPTION 'Debit memo cannot be posted in status: %', v_rec.status;
  END IF;

  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.dm_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.dm_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.dm_date
    AND end_date >= v_rec.dm_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for DM date %. Create or unlock a fiscal period first.', v_rec.dm_date;
  END IF;

  -- P5.1 Module 1: the direct header INSERT is replaced by the sanctioned kernel.
  -- Every value below is the one this function previously wrote itself.
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-DM-' || v_rec.dm_number, v_rec.dm_date,
    'Debit Memo ' || v_rec.dm_number || ' — ' || v_rec.customer_name_snapshot,
    'DM', v_rec.id,
    v_fp_id, 'posted', v_rec.total_amount, v_rec.total_amount, 'system'
  );

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_ar,
          'AR — ' || v_rec.customer_name_snapshot, v_rec.total_amount, 0, 'control', auth.uid(), auth.uid());

  FOR v_line IN
    SELECT account_id, SUM(amount) AS amt_sum, description AS ln_desc
    FROM debit_memo_lines
    WHERE debit_memo_id = v_rec.id AND account_id IS NOT NULL
    GROUP BY account_id, description
  LOOP
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.account_id,
            'DM charge — ' || v_line.ln_desc, 0, v_line.amt_sum, 'base', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.amt_sum;
    v_line_no  := v_line_no + 1;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_vat,
            'Output VAT — ' || v_rec.dm_number, 0, v_rec.total_vat_amount, 'tax', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'DM journal entry unbalanced: DR=% CR=%. Ensure all DM lines have GL accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE debit_memos SET
    status = 'paid', journal_entry_id = v_je_id,
    posted_at = NOW(), posted_by = auth.uid(),
    updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_dm_id;

  -- Positive output VAT in tax ledger
  IF v_rec.total_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'DM', v_rec.id,
      'output_vat', v_rec.total_taxable_amount, v_rec.total_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.dm_date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot,
      false
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_post_vendor_credit_vat_lump_impl(p_vc_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec       vendor_credits%ROWTYPE;
  v_ap        UUID;
  v_input_vat UUID;
  v_fp_id     UUID;
  v_je_id     UUID;
  v_line      RECORD;
  v_line_no   INT := 1;
  v_total_cr  NUMERIC(15,2) := 0;
BEGIN
  SELECT * INTO v_rec FROM vendor_credits WHERE id = p_vc_id;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN RAISE EXCEPTION 'Not found or access denied'; END IF;
  IF v_rec.status != 'draft' THEN RAISE EXCEPTION 'Only draft vendor credits can be posted (current: %)', v_rec.status; END IF;

  v_ap := fn_resolve_posting_account(v_rec.company_id, 'AP_TRADE', v_rec.credit_date,
            'AP control account not configured. Set it in GL Posting Configuration.');
  IF v_rec.total_input_vat_amount > 0 THEN
    v_input_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_INPUT', v_rec.credit_date,
                     'Input VAT account not configured. Set it in GL Posting Configuration.');
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_rec.company_id AND start_date <= v_rec.credit_date
    AND end_date >= v_rec.credit_date AND is_locked = false LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for credit date %. Create or unlock a fiscal period first.', v_rec.credit_date;
  END IF;

  -- P5.1 Module 1: the direct header INSERT is replaced by the sanctioned kernel.
  -- Every value below is the one this function previously wrote itself.
  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-VC-' || v_rec.vc_number, v_rec.credit_date,
    'Vendor Credit ' || v_rec.vc_number || ' — ' || v_rec.supplier_name_snapshot,
    'VC', v_rec.id,
    v_fp_id, 'posted', v_rec.total_amount, v_rec.total_amount, 'system'
  );

  INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
  VALUES (v_je_id, v_rec.company_id, 1, v_ap,
          'AP — ' || v_rec.supplier_name_snapshot, v_rec.total_amount, 0, 'control', auth.uid(), auth.uid());

  FOR v_line IN
    SELECT expense_account_id, SUM(net_amount) AS net_sum, description AS ln_desc
    FROM vendor_credit_lines
    WHERE vc_id = v_rec.id AND expense_account_id IS NOT NULL
    GROUP BY expense_account_id, description
  LOOP
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_line.expense_account_id,
            'Credit reversal — ' || v_line.ln_desc, 0, v_line.net_sum, 'base', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_line.net_sum;
  END LOOP;

  IF v_rec.total_input_vat_amount > 0 THEN
    v_line_no := v_line_no + 1;
    INSERT INTO journal_entry_lines (je_id, company_id, line_number, account_id, description, debit_amount, credit_amount, line_role, created_by, updated_by)
    VALUES (v_je_id, v_rec.company_id, v_line_no, v_input_vat,
            'Input VAT reversal — ' || v_rec.vc_number, 0, v_rec.total_input_vat_amount, 'tax', auth.uid(), auth.uid());
    v_total_cr := v_total_cr + v_rec.total_input_vat_amount;
  END IF;

  IF ABS(v_rec.total_amount - v_total_cr) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry unbalanced: DR=% CR=%. Ensure all lines have expense accounts.', v_rec.total_amount, v_total_cr;
  END IF;

  UPDATE vendor_credits SET status = 'open', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  -- Negative input VAT in tax ledger (reversal of original bill input VAT)
  IF v_rec.total_input_vat_amount > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, tax_base, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name,
      is_reversal
    ) VALUES (
      v_rec.company_id, v_rec.branch_id, 'VC', v_rec.id,
      'input_vat', -v_rec.total_taxable_amount, -v_rec.total_input_vat_amount, v_fp_id,
      NOW()::DATE, v_rec.credit_date,
      v_rec.supplier_id, v_rec.supplier_tin_snapshot, v_rec.supplier_name_snapshot,
      true
    );
  END IF;
END;
$function$;
