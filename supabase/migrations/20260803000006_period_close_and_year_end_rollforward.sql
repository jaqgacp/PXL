-- ══════════════════════════════════════════════════════════════════════════════
-- Period close and year-end roll-forward (Delivery Plan Phase 6, Backlog 18d)
--
-- Completes the accounting cycle. Before this migration the cycle stopped at the
-- financial statements:
--
--   * `fn_close_fiscal_year` existed but **could never commit**. It posted the
--     closing journal with `reference_doc_type = 'CLOSE'` and a NULL
--     `reference_doc_id`, while the CLOSE row of `ref_posting_source_types`
--     pointed at `journal_entries`. The deferred constraint trigger
--     `trg_journal_entry_source_integrity` resolves every posted entry's source
--     at COMMIT, and a NULL source id for a non-MANUAL type raises. Test `040`
--     never saw it because pgTAP rolls back, and a deferred constraint that is
--     never committed is never checked. Executed evidence, not prose: the same
--     transaction with `SET CONSTRAINTS ALL IMMEDIATE` fails with
--     "Posting source id is required for source type CLOSE".
--   * No user interface reached the close engine. The "Close Year" button wrote
--     `fiscal_years.status = 'closed'` straight through PostgREST and posted
--     nothing, so a year could be marked closed with revenue and expense still
--     sitting in the profit-and-loss accounts.
--   * Period close was a raw `UPDATE fiscal_periods SET is_locked` from the
--     browser: no validation, no sequence, no reason, no register, and nothing
--     stopping a period from being reopened behind an already-closed one.
--   * Nothing prevented a second closing journal for the same fiscal year, so a
--     re-close would have credited retained earnings twice.
--
-- ── What this migration establishes ───────────────────────────────────────────
--
--   1. **The fiscal year is the closing journal's source document.** CLOSE now
--      resolves against `fiscal_years`, the closing entry carries
--      `reference_doc_id = fiscal_year_id`, and the source assertion is enforced
--      rather than skipped. The close can commit, and the accounting trace can
--      drill from a fiscal year to the journal that closed it.
--
--   2. **`fiscal_close_runs`** — the governed register of every close and
--      reopen. Two partial unique indexes make duplication structurally
--      impossible: at most one live close per period and at most one live close
--      per fiscal year. A reopen supersedes the close it undoes; nothing is
--      deleted and nothing is rewritten.
--
--   3. **A governed period close** — `fn_period_close_readiness` states the
--      checks, `fn_close_accounting_period` enforces the blocking ones and locks
--      the period, `fn_reopen_accounting_period` reopens it against a required
--      reason. Periods close in date order and reopen in reverse date order, so
--      a posting can never slip in behind a closed period.
--      `fn_close_accounting_quarter` is the same period close applied to the
--      three periods of a quarter — a quarter is not a separate close, because
--      PXL's fiscal calendar is monthly.
--
--   4. **A repeatable year-end close.** The closing journal is unchanged in
--      shape (one line per profit-and-loss account, balanced by retained
--      earnings, direct to retained earnings per DEC-019) and still goes through
--      the Accounting Kernel. What is new: prior fiscal years must be closed
--      first, the register makes a duplicate close impossible, the target period
--      is reopened for the duration of the posting so a fully closed year can
--      still be closed, and the next fiscal year is opened automatically with
--      the same retained-earnings destination.
--
--   5. **A year-end reopen** — `fn_reopen_fiscal_year` posts the counter-closing
--      journal through the same kernel, classified `closing` so a subsequent
--      re-close recomputes the same net income instead of doubling it. The
--      original closing journal is never touched.
--
--   6. **The lock itself is governed.** `fiscal_periods.is_locked` and
--      `fiscal_years.status` may now only change from inside the four close
--      functions (or the certified maintenance lane), so the close engine is the
--      only way the books are opened and shut.
--
-- No Posting Engine or Accounting Kernel change: every ledger write in this file
-- goes through `fn_create_posted_journal_entry` and `fn_add_posting_line_push`,
-- and the six-function kernel classifier is untouched.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. The fiscal year is the closing journal's governed source ────────────────
-- CLOSE previously pointed at `journal_entries`, which made the closing entry its
-- own source and forced a NULL reference the resolver rejects. A year-end closing
-- journal's source document is the fiscal year being closed.

UPDATE ref_posting_source_types
SET source_table            = 'fiscal_years',
    document_number_column  = 'year_name',
    document_date_column    = 'end_date',
    status_column           = 'status',
    route_path              = '/fiscal-years',
    display_name            = 'Fiscal Year Close'
WHERE document_type = 'CLOSE';

-- The journal-event capture chose the entry's own id for CLOSE because CLOSE had
-- no real source. It has one now, so the close records its transaction event
-- against the fiscal year like every other governed document.
CREATE OR REPLACE FUNCTION public.fn_capture_journal_entry_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_before_status TEXT;
  v_after_status TEXT;
  v_event_type TEXT;
  v_source_type TEXT;
  v_source_id UUID;
BEGIN
  IF NEW.company_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_after_status := NEW.status;
    v_event_type := CASE
      WHEN lower(coalesce(v_after_status, '')) = 'posted' THEN 'POSTED'
      ELSE 'CREATED'
    END;
  ELSE
    v_before_status := OLD.status;
    v_after_status := NEW.status;
    IF v_after_status IS NOT DISTINCT FROM v_before_status
       AND NEW.reference_doc_id IS DISTINCT FROM OLD.reference_doc_id
       AND lower(coalesce(NEW.status, '')) = 'posted' THEN
      v_event_type := 'POSTED';
    ELSIF v_after_status IS NOT DISTINCT FROM v_before_status THEN
      RETURN NEW;
    ELSE
      v_event_type := fn_transaction_event_type_for_status(v_before_status, v_after_status);
    END IF;
  END IF;

  v_source_type := coalesce(NULLIF(NEW.reference_doc_type, ''), 'MANUAL');
  -- MANUAL is the only posted entry that is legitimately its own source.
  v_source_id := CASE
    WHEN NEW.reference_doc_id IS NOT NULL AND v_source_type <> 'MANUAL'
      THEN NEW.reference_doc_id
    ELSE NEW.id
  END;

  -- Fixed-asset and some schedule writers create the journal before the source
  -- row exists.  The link triggers attach reference_doc_id shortly afterward;
  -- record the semantic event on that link update instead of failing the insert.
  IF v_source_type NOT IN ('MANUAL', 'CLOSE', 'REV')
     AND NEW.reference_doc_id IS NULL THEN
    RETURN NEW;
  END IF;

  BEGIN
    PERFORM fn_record_transaction_event(
      NEW.company_id,
      v_source_type,
      v_source_id,
      v_event_type,
      'public.journal_entries',
      v_before_status,
      v_after_status,
      NULL,
      NEW.id,
      jsonb_build_object(
        'source', 'journal_entry_status_trigger',
        'je_number', NEW.je_number,
        'entry_class', NEW.entry_class,
        'reference_doc_type', NEW.reference_doc_type,
        'reference_doc_id', NEW.reference_doc_id
      )
    );
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'Posting source %.% does not exist' THEN
      RETURN NEW;
    END IF;
    RAISE;
  END;

  RETURN NEW;
END;
$function$;

-- ── 2. The close register ──────────────────────────────────────────────────────
-- One row per governed close or reopen. `superseded_by_id` points a close at the
-- reopen that undid it, which is what the partial unique indexes below read to
-- decide whether a close is still live.

CREATE TABLE IF NOT EXISTS public.fiscal_close_runs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID NOT NULL REFERENCES companies(id),
  fiscal_year_id    UUID NOT NULL REFERENCES fiscal_years(id) ON DELETE CASCADE,
  fiscal_period_id  UUID REFERENCES fiscal_periods(id) ON DELETE CASCADE,
  close_type        TEXT NOT NULL CHECK (close_type IN ('period', 'year')),
  action            TEXT NOT NULL CHECK (action IN ('close', 'reopen')),
  quarter_number    INTEGER CHECK (quarter_number BETWEEN 1 AND 4),
  effective_date    DATE NOT NULL,
  reason            TEXT,
  checks            JSONB NOT NULL DEFAULT '[]'::jsonb,
  closing_je_id     UUID REFERENCES journal_entries(id),
  net_income        NUMERIC(18,2),
  retained_earnings_account_id UUID REFERENCES chart_of_accounts(id),
  superseded_by_id  UUID REFERENCES fiscal_close_runs(id),
  performed_by      UUID,
  performed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fiscal_close_runs_period_scope_chk
    CHECK ((close_type = 'period') = (fiscal_period_id IS NOT NULL))
);

COMMENT ON TABLE public.fiscal_close_runs IS
  'Governed register of every accounting-period and fiscal-year close and reopen. Append-only apart from the single superseded_by_id stamp a reopen writes on the close it undoes. The two partial unique indexes make a duplicate live close structurally impossible, which is what makes the close idempotent.';

-- At most one live close per period, and at most one per fiscal year. This is the
-- duplicate-closing-entry guard: a second year-end close cannot be recorded, and
-- a close that cannot be recorded cannot be posted, because the register insert
-- and the journal share one transaction.
CREATE UNIQUE INDEX IF NOT EXISTS ux_fiscal_close_runs_live_period
  ON public.fiscal_close_runs (company_id, fiscal_period_id)
  WHERE close_type = 'period' AND action = 'close' AND superseded_by_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_fiscal_close_runs_live_year
  ON public.fiscal_close_runs (company_id, fiscal_year_id)
  WHERE close_type = 'year' AND action = 'close' AND superseded_by_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_fiscal_close_runs_company_year
  ON public.fiscal_close_runs (company_id, fiscal_year_id, performed_at DESC);

ALTER TABLE public.fiscal_close_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fiscal_close_runs_read" ON public.fiscal_close_runs;
CREATE POLICY "fiscal_close_runs_read" ON public.fiscal_close_runs
  FOR SELECT TO authenticated USING (is_company_member(company_id));

-- Writes belong to the close engine alone. Explicit denial rather than absence:
-- the rule is then readable in the schema and directly assertable in the test.
DROP POLICY IF EXISTS "fiscal_close_runs_no_direct_insert" ON public.fiscal_close_runs;
CREATE POLICY "fiscal_close_runs_no_direct_insert" ON public.fiscal_close_runs
  FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS "fiscal_close_runs_no_direct_update" ON public.fiscal_close_runs;
CREATE POLICY "fiscal_close_runs_no_direct_update" ON public.fiscal_close_runs
  FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS "fiscal_close_runs_no_direct_delete" ON public.fiscal_close_runs;
CREATE POLICY "fiscal_close_runs_no_direct_delete" ON public.fiscal_close_runs
  FOR DELETE TO authenticated USING (false);

-- Immutability: a recorded close or reopen is evidence. The only permitted
-- mutation is stamping a live close with the reopen that supersedes it, once.
CREATE OR REPLACE FUNCTION public.fn_guard_fiscal_close_run_immutability()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'A fiscal close run is permanent evidence and cannot be deleted';
  END IF;

  IF OLD.superseded_by_id IS NOT NULL THEN
    RAISE EXCEPTION 'Fiscal close run % is already superseded and cannot change again', OLD.id;
  END IF;

  IF NEW.superseded_by_id IS NULL THEN
    RAISE EXCEPTION 'A fiscal close run may only be updated to record the reopen that supersedes it';
  END IF;

  IF (to_jsonb(NEW) - 'superseded_by_id') IS DISTINCT FROM (to_jsonb(OLD) - 'superseded_by_id') THEN
    RAISE EXCEPTION 'Only superseded_by_id may change on a fiscal close run';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_fiscal_close_runs_immutability ON public.fiscal_close_runs;
CREATE TRIGGER trg_fiscal_close_runs_immutability
  BEFORE UPDATE OR DELETE ON public.fiscal_close_runs
  FOR EACH ROW EXECUTE FUNCTION fn_guard_fiscal_close_run_immutability();

DROP TRIGGER IF EXISTS trg_audit_fiscal_close_runs ON public.fiscal_close_runs;
CREATE TRIGGER trg_audit_fiscal_close_runs
  AFTER INSERT OR UPDATE OR DELETE ON public.fiscal_close_runs
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

GRANT SELECT ON public.fiscal_close_runs TO authenticated;

-- ── 3. Only the close engine may open or shut a period ─────────────────────────
-- Same technique as the armed Posting Engine kernel guard: read the PL/pgSQL call
-- stack and require the write to originate inside a sanctioned function. Without
-- this, `fiscal_periods.is_locked` and `fiscal_years.status` remain directly
-- writable through PostgREST by any company admin, which would leave every rule
-- below advisory. Every other column of both tables stays freely maintainable.

CREATE OR REPLACE FUNCTION public.fn_fiscal_close_engine_origin(p_context TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $function$
  -- The four governed close entry points, matched as exact function names in a
  -- PL/pgSQL stack frame. The opening parenthesis prevents a lookalike name from
  -- inheriting close-engine status.
  SELECT p_context ~ ('fn_close_accounting_period\('
                   || '|fn_reopen_accounting_period\('
                   || '|fn_close_fiscal_year\('
                   || '|fn_reopen_fiscal_year\(');
$function$;

CREATE OR REPLACE FUNCTION public.fn_guard_fiscal_lock_origin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ctx TEXT;
BEGIN
  -- The two tables have different column sets, and PL/pgSQL resolves every field
  -- reference in a boolean expression whether or not the guard short-circuits, so
  -- each table is read on its own branch.
  IF TG_TABLE_NAME = 'fiscal_periods' THEN
    IF NEW.is_locked IS NOT DISTINCT FROM OLD.is_locked THEN
      RETURN NEW;
    END IF;
  ELSE
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
      RETURN NEW;
    END IF;
  END IF;

  GET DIAGNOSTICS v_ctx = PG_CONTEXT;
  IF fn_fiscal_close_engine_origin(v_ctx) THEN
    RETURN NEW;
  END IF;

  -- The certified demo/maintenance lane (PXL-AUD-070): an explicit GUC plus a
  -- privileged connection login, which an authenticated PostgREST caller can
  -- never satisfy.
  IF fn_demo_reset_bypass_authorized() THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION
    'Period locking is governed: use the close engine (fn_close_accounting_period, fn_reopen_accounting_period, fn_close_fiscal_year, fn_reopen_fiscal_year) rather than writing %.% directly',
    TG_TABLE_NAME,
    CASE WHEN TG_TABLE_NAME = 'fiscal_periods' THEN 'is_locked' ELSE 'status' END
    USING ERRCODE = 'check_violation';
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_fiscal_period_lock ON public.fiscal_periods;
CREATE TRIGGER trg_guard_fiscal_period_lock
  BEFORE UPDATE OF is_locked ON public.fiscal_periods
  FOR EACH ROW EXECUTE FUNCTION fn_guard_fiscal_lock_origin();

DROP TRIGGER IF EXISTS trg_guard_fiscal_year_status ON public.fiscal_years;
CREATE TRIGGER trg_guard_fiscal_year_status
  BEFORE UPDATE OF status ON public.fiscal_years
  FOR EACH ROW EXECUTE FUNCTION fn_guard_fiscal_lock_origin();

-- ── 4. Period-close readiness ──────────────────────────────────────────────────
-- The checks the close enforces, stated as data so the same answer drives the
-- screen and the engine. Blocking checks are accounting invariants; advisory
-- checks are housekeeping that is recorded on the close but does not stop it.

CREATE OR REPLACE FUNCTION public.fn_period_close_readiness(
  p_company_id       UUID,
  p_fiscal_period_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_period      fiscal_periods%ROWTYPE;
  v_year_status TEXT;
  v_prior_open  TEXT;
  v_out_of_bal  NUMERIC(18,2);
  v_drafts      INTEGER;
  v_recon       INTEGER;
  v_recurring   INTEGER;
  v_checks      JSONB := '[]'::jsonb;
  v_blocking    INTEGER := 0;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_period FROM fiscal_periods
  WHERE id = p_fiscal_period_id AND company_id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fiscal period % not found for this company', p_fiscal_period_id;
  END IF;

  SELECT status INTO v_year_status FROM fiscal_years WHERE id = v_period.fiscal_year_id;

  -- Blocking: the period is still open.
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'code', 'period_open', 'label', 'Period is open',
    'severity', 'blocking', 'ok', NOT COALESCE(v_period.is_locked, false),
    'detail', CASE WHEN COALESCE(v_period.is_locked, false)
                   THEN v_period.period_name || ' is already closed'
                   ELSE 'Open' END));

  -- Blocking: the owning fiscal year is still open.
  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'code', 'fiscal_year_open', 'label', 'Fiscal year is open',
    'severity', 'blocking', 'ok', v_year_status = 'open',
    'detail', CASE WHEN v_year_status = 'open' THEN 'Open'
                   ELSE 'The fiscal year is closed; reopen the year first' END));

  -- Blocking: periods close in date order, so no posting can land behind a
  -- closed period.
  SELECT fp.period_name INTO v_prior_open
  FROM fiscal_periods fp
  WHERE fp.company_id = p_company_id
    AND fp.end_date < v_period.end_date
    AND fp.is_locked = false
  ORDER BY fp.end_date
  LIMIT 1;

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'code', 'prior_periods_closed', 'label', 'Earlier periods are closed',
    'severity', 'blocking', 'ok', v_prior_open IS NULL,
    'detail', COALESCE(v_prior_open || ' is still open', 'All earlier periods closed')));

  -- Blocking: the ledger balances up to the period end. A period cannot be
  -- declared final over an out-of-balance general ledger.
  SELECT COALESCE(ROUND(SUM(jel.debit_amount) - SUM(jel.credit_amount), 2), 0)
  INTO v_out_of_bal
  FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id = jel.je_id
  WHERE jel.company_id = p_company_id
    AND je.status IN ('posted', 'reversed')
    AND je.je_date <= v_period.end_date;

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'code', 'ledger_balanced', 'label', 'General ledger balances',
    'severity', 'blocking', 'ok', COALESCE(v_out_of_bal, 0) = 0,
    'detail', 'Out of balance ' || TO_CHAR(COALESCE(v_out_of_bal, 0), 'FM999999999990.00')));

  -- Advisory: work that should normally be finished, recorded on the close.
  SELECT COUNT(*)::INTEGER INTO v_drafts
  FROM journal_entries
  WHERE company_id = p_company_id AND fiscal_period_id = p_fiscal_period_id
    AND status = 'draft';

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'code', 'no_draft_journals', 'label', 'No draft journal entries in the period',
    'severity', 'advisory', 'ok', v_drafts = 0,
    'detail', CASE WHEN v_drafts = 0 THEN 'None'
                   ELSE v_drafts || ' draft entr' || CASE WHEN v_drafts = 1 THEN 'y' ELSE 'ies' END END));

  SELECT COUNT(*)::INTEGER INTO v_recon
  FROM bank_reconciliations
  WHERE company_id = p_company_id
    AND recon_year = EXTRACT(YEAR FROM v_period.start_date)::INTEGER
    AND recon_month = EXTRACT(MONTH FROM v_period.start_date)::INTEGER
    AND status <> 'finalized';

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'code', 'bank_reconciliations_finalized', 'label', 'Bank reconciliations finalized',
    'severity', 'advisory', 'ok', v_recon = 0,
    'detail', CASE WHEN v_recon = 0 THEN 'All finalized' ELSE v_recon || ' not finalized' END));

  SELECT COUNT(*)::INTEGER INTO v_recurring
  FROM recurring_journal_templates
  WHERE company_id = p_company_id AND is_active = true
    AND next_run_date <= v_period.end_date;

  v_checks := v_checks || jsonb_build_array(jsonb_build_object(
    'code', 'recurring_templates_run', 'label', 'Recurring journals are up to date',
    'severity', 'advisory', 'ok', v_recurring = 0,
    'detail', CASE WHEN v_recurring = 0 THEN 'None pending' ELSE v_recurring || ' pending' END));

  SELECT COUNT(*)::INTEGER INTO v_blocking
  FROM jsonb_array_elements(v_checks) c
  WHERE c->>'severity' = 'blocking' AND (c->>'ok')::BOOLEAN = false;

  RETURN jsonb_build_object(
    'fiscal_period_id', p_fiscal_period_id,
    'period_name', v_period.period_name,
    'period_start', v_period.start_date,
    'period_end', v_period.end_date,
    'is_locked', COALESCE(v_period.is_locked, false),
    'ready', v_blocking = 0,
    'blocking_failures', v_blocking,
    'checks', v_checks
  );
END;
$function$;

-- ── 5. Close an accounting period ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_close_accounting_period(
  p_company_id       UUID,
  p_fiscal_period_id UUID,
  p_note             TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_period    fiscal_periods%ROWTYPE;
  v_readiness JSONB;
  v_failed    TEXT;
  v_run_id    UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: closing an accounting period requires company admin rights';
  END IF;

  SELECT * INTO v_period FROM fiscal_periods
  WHERE id = p_fiscal_period_id AND company_id = p_company_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fiscal period % not found for this company', p_fiscal_period_id;
  END IF;

  v_readiness := fn_period_close_readiness(p_company_id, p_fiscal_period_id);

  IF NOT (v_readiness->>'ready')::BOOLEAN THEN
    SELECT string_agg(c->>'detail', '; ' ORDER BY c->>'code') INTO v_failed
    FROM jsonb_array_elements(v_readiness->'checks') c
    WHERE c->>'severity' = 'blocking' AND (c->>'ok')::BOOLEAN = false;
    RAISE EXCEPTION 'Cannot close %: %', v_period.period_name, v_failed;
  END IF;

  UPDATE fiscal_periods
  SET is_locked = true, updated_at = NOW()
  WHERE id = p_fiscal_period_id;

  INSERT INTO fiscal_close_runs (
    company_id, fiscal_year_id, fiscal_period_id, close_type, action,
    quarter_number, effective_date, reason, checks, performed_by
  ) VALUES (
    p_company_id, v_period.fiscal_year_id, p_fiscal_period_id, 'period', 'close',
    ((v_period.period_number - 1) / 3) + 1, v_period.end_date,
    NULLIF(BTRIM(COALESCE(p_note, '')), ''), v_readiness->'checks', auth.uid()
  ) RETURNING id INTO v_run_id;

  RETURN v_run_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_close_accounting_period(UUID, UUID, TEXT) IS
  'Governed monthly close: enforces the blocking readiness checks (period open, fiscal year open, every earlier period already closed, general ledger in balance), locks the period, and records the close with its full check payload in fiscal_close_runs. Posts no journal — an accounting period close is a lock, not an entry.';

-- ── 6. Reopen an accounting period ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_reopen_accounting_period(
  p_company_id       UUID,
  p_fiscal_period_id UUID,
  p_reason           TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_period      fiscal_periods%ROWTYPE;
  v_year_status TEXT;
  v_later       TEXT;
  v_reason      TEXT := NULLIF(BTRIM(COALESCE(p_reason, '')), '');
  v_run_id      UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: reopening an accounting period requires company admin rights';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A reason is required to reopen a closed accounting period';
  END IF;

  SELECT * INTO v_period FROM fiscal_periods
  WHERE id = p_fiscal_period_id AND company_id = p_company_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fiscal period % not found for this company', p_fiscal_period_id;
  END IF;
  IF NOT COALESCE(v_period.is_locked, false) THEN
    RAISE EXCEPTION '% is already open', v_period.period_name;
  END IF;

  SELECT status INTO v_year_status FROM fiscal_years WHERE id = v_period.fiscal_year_id;
  IF v_year_status <> 'open' THEN
    RAISE EXCEPTION 'Fiscal year is closed; reopen the fiscal year before reopening %', v_period.period_name;
  END IF;

  -- Reopen is last-in, first-out. Reopening a period behind a closed one would
  -- let a posting land before a period already declared final.
  SELECT fp.period_name INTO v_later
  FROM fiscal_periods fp
  WHERE fp.company_id = p_company_id
    AND fp.end_date > v_period.end_date
    AND fp.is_locked = true
  ORDER BY fp.end_date DESC
  LIMIT 1;

  IF v_later IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot reopen % while the later period % is still closed', v_period.period_name, v_later;
  END IF;

  UPDATE fiscal_periods
  SET is_locked = false, updated_at = NOW()
  WHERE id = p_fiscal_period_id;

  INSERT INTO fiscal_close_runs (
    company_id, fiscal_year_id, fiscal_period_id, close_type, action,
    quarter_number, effective_date, reason, performed_by
  ) VALUES (
    p_company_id, v_period.fiscal_year_id, p_fiscal_period_id, 'period', 'reopen',
    ((v_period.period_number - 1) / 3) + 1, v_period.end_date, v_reason, auth.uid()
  ) RETURNING id INTO v_run_id;

  UPDATE fiscal_close_runs
  SET superseded_by_id = v_run_id
  WHERE company_id = p_company_id
    AND fiscal_period_id = p_fiscal_period_id
    AND close_type = 'period' AND action = 'close'
    AND superseded_by_id IS NULL;

  RETURN v_run_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_reopen_accounting_period(UUID, UUID, TEXT) IS
  'Governed period reopen against a required reason. Reopens strictly last-in-first-out so a posting can never land behind a period that is still closed, and supersedes the close it undoes rather than erasing it.';

-- ── 7. Quarterly close ─────────────────────────────────────────────────────────
-- PXL's fiscal calendar is monthly, so a quarter close is not a separate close:
-- it is the same governed period close applied to the quarter's three periods in
-- date order. Periods already closed are skipped, which makes a repeat call a
-- no-op rather than an error.

CREATE OR REPLACE FUNCTION public.fn_close_accounting_quarter(
  p_company_id     UUID,
  p_fiscal_year_id UUID,
  p_quarter        INTEGER,
  p_note           TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r       RECORD;
  v_count INTEGER := 0;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: closing a quarter requires company admin rights';
  END IF;
  IF p_quarter IS NULL OR p_quarter < 1 OR p_quarter > 4 THEN
    RAISE EXCEPTION 'Quarter must be 1, 2, 3 or 4 (got %)', p_quarter;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM fiscal_years
    WHERE id = p_fiscal_year_id AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'Fiscal year % not found for this company', p_fiscal_year_id;
  END IF;

  FOR r IN
    SELECT id FROM fiscal_periods
    WHERE company_id = p_company_id
      AND fiscal_year_id = p_fiscal_year_id
      AND period_number BETWEEN (p_quarter - 1) * 3 + 1 AND p_quarter * 3
      AND is_locked = false
    ORDER BY period_number
  LOOP
    PERFORM fn_close_accounting_period(
      p_company_id, r.id,
      COALESCE(NULLIF(BTRIM(COALESCE(p_note, '')), ''), 'Q' || p_quarter || ' close')
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$;

COMMENT ON FUNCTION public.fn_close_accounting_quarter(UUID, UUID, INTEGER, TEXT) IS
  'Closes the three monthly periods of a quarter through fn_close_accounting_period in date order. PXL keeps a monthly fiscal calendar, so a quarter close is the same close applied three times rather than a second closing concept.';

-- ── 8. Roll the calendar forward ───────────────────────────────────────────────
-- Idempotent: a fiscal year that already covers the day after the closing year
-- ends is returned as-is. The retained-earnings destination is inherited, so a
-- company that has closed once never has to configure it again.

CREATE OR REPLACE FUNCTION public.fn_open_next_fiscal_year(
  p_company_id     UUID,
  p_fiscal_year_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_year      fiscal_years%ROWTYPE;
  v_start     DATE;
  v_end       DATE;
  v_name      TEXT;
  v_next_id   UUID;
BEGIN
  SELECT * INTO v_year FROM fiscal_years
  WHERE id = p_fiscal_year_id AND company_id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fiscal year % not found for this company', p_fiscal_year_id;
  END IF;

  v_start := v_year.end_date + 1;
  v_end   := (v_start + INTERVAL '1 year' - INTERVAL '1 day')::DATE;

  SELECT id INTO v_next_id FROM fiscal_years
  WHERE company_id = p_company_id AND start_date = v_start;
  IF v_next_id IS NULL THEN
    SELECT id INTO v_next_id FROM fiscal_years
    WHERE company_id = p_company_id
      AND start_date <= v_start AND end_date >= v_start;
  END IF;

  IF v_next_id IS NULL THEN
    v_name := 'FY' || TO_CHAR(v_start, 'YYYY');
    IF EXISTS (SELECT 1 FROM fiscal_years WHERE company_id = p_company_id AND year_name = v_name) THEN
      v_name := 'FY' || TO_CHAR(v_start, 'YYYY') || '/' || TO_CHAR(v_end, 'YY');
    END IF;

    INSERT INTO fiscal_years (
      company_id, year_name, start_date, end_date, is_calendar, status,
      retained_earnings_id, created_by, updated_by
    ) VALUES (
      p_company_id, v_name, v_start, v_end,
      (EXTRACT(MONTH FROM v_start) = 1 AND EXTRACT(DAY FROM v_start) = 1),
      'open', v_year.retained_earnings_id, auth.uid(), auth.uid()
    ) RETURNING id INTO v_next_id;
  ELSIF (SELECT retained_earnings_id FROM fiscal_years WHERE id = v_next_id) IS NULL THEN
    UPDATE fiscal_years SET retained_earnings_id = v_year.retained_earnings_id
    WHERE id = v_next_id;
  END IF;

  PERFORM fn_generate_fiscal_periods(v_next_id);
  RETURN v_next_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_open_next_fiscal_year(UUID, UUID) IS
  'Idempotently opens the fiscal year that follows the given one, with its twelve periods and the same retained-earnings destination. Called by the year-end close so the roll-forward needs no separate operator step.';

-- ── 9. Year-end close ──────────────────────────────────────────────────────────
-- The closing journal keeps the shape, numbering, ordering and direct-to-retained
-- earnings treatment established by PXL-AUD-013 and DEC-019, and still reaches
-- the ledger only through the Accounting Kernel. What changes: the fiscal year is
-- now the journal's source document (so the entry can commit), prior years must
-- be closed first, the register makes a duplicate close impossible, the target
-- period is reopened for the length of the posting so a fully closed year can
-- still be closed, and the next year is opened automatically.

CREATE OR REPLACE FUNCTION public.fn_close_fiscal_year(
  p_company_id uuid,
  p_fiscal_year_id uuid,
  p_close_date date DEFAULT NULL
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_year         fiscal_years%ROWTYPE;
  v_re_id        UUID;
  v_re_postable  BOOLEAN;
  v_re_active    BOOLEAN;
  v_re_type      TEXT;
  v_close_date   DATE;
  v_fp_id        UUID;
  v_prior_open   TEXT;
  v_je_id        UUID;
  v_je_number    TEXT;
  v_seq          INT;
  v_line_no      INT := 0;
  v_close_debit  NUMERIC(15,2) := 0;
  v_close_credit NUMERIC(15,2) := 0;
  v_net_dr       NUMERIC(15,2) := 0;
  v_net_income   NUMERIC(15,2);
  v_re_debit     NUMERIC(15,2);
  v_re_credit    NUMERIC(15,2);
  v_total_debit  NUMERIC(15,2);
  v_total_credit NUMERIC(15,2);
  r              RECORD;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: closing a fiscal year requires company admin rights';
  END IF;

  SELECT * INTO v_year FROM fiscal_years
  WHERE id = p_fiscal_year_id AND company_id = p_company_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fiscal year % not found for this company', p_fiscal_year_id;
  END IF;
  IF v_year.status = 'closed' THEN
    RAISE EXCEPTION 'Fiscal year % is already closed', v_year.year_name;
  END IF;

  -- Years close in order. Closing 2027 while 2026 is open would leave the prior
  -- year's profit in the income accounts and make every comparative meaningless.
  SELECT fy.year_name INTO v_prior_open
  FROM fiscal_years fy
  WHERE fy.company_id = p_company_id
    AND fy.end_date < v_year.start_date
    AND fy.status <> 'closed'
    AND EXISTS (
      SELECT 1 FROM journal_entries je
      WHERE je.company_id = p_company_id
        AND je.status IN ('posted', 'reversed')
        AND je.je_date BETWEEN fy.start_date AND fy.end_date
    )
  ORDER BY fy.end_date
  LIMIT 1;

  IF v_prior_open IS NOT NULL THEN
    RAISE EXCEPTION 'Fiscal year % carries posted activity and is still open; close it before closing %',
      v_prior_open, v_year.year_name;
  END IF;

  -- Retained earnings destination must be a postable, active equity account.
  v_re_id := v_year.retained_earnings_id;
  IF v_re_id IS NULL THEN
    RAISE EXCEPTION 'Fiscal year % has no retained earnings account configured', v_year.year_name;
  END IF;
  SELECT is_postable, is_active, account_type
    INTO v_re_postable, v_re_active, v_re_type
  FROM chart_of_accounts WHERE id = v_re_id AND company_id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Retained earnings account does not belong to this company';
  END IF;
  IF v_re_type <> 'equity' THEN
    RAISE EXCEPTION 'Retained earnings account must be an equity account';
  END IF;
  IF NOT v_re_postable THEN
    RAISE EXCEPTION 'Retained earnings account is not postable';
  END IF;
  IF NOT v_re_active THEN
    RAISE EXCEPTION 'Retained earnings account is inactive';
  END IF;

  v_close_date := COALESCE(p_close_date, v_year.end_date);
  IF v_close_date < v_year.start_date OR v_close_date > v_year.end_date THEN
    RAISE EXCEPTION 'Close date % must fall within fiscal year % (% to %)',
      v_close_date, v_year.year_name, v_year.start_date, v_year.end_date;
  END IF;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = p_company_id AND fiscal_year_id = p_fiscal_year_id
    AND start_date <= v_close_date AND end_date >= v_close_date
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No fiscal period covers the close date %', v_close_date;
  END IF;

  -- The monthly close normally locks December before the year is closed, and the
  -- posting guard admits only an open period. The close owns the calendar, so it
  -- reopens its own target for the length of the posting and locks everything at
  -- the end.
  UPDATE fiscal_periods SET is_locked = false, updated_at = NOW()
  WHERE id = v_fp_id AND is_locked = true;

  -- Aggregate this year's profit-and-loss close amounts (regular + adjusting +
  -- opening only) so a re-close can never double-count prior closing entries.
  SELECT
    COALESCE(SUM(CASE WHEN t.net_dr < 0 THEN -t.net_dr ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN t.net_dr > 0 THEN  t.net_dr ELSE 0 END), 0),
    COALESCE(SUM(t.net_dr), 0)
  INTO v_close_debit, v_close_credit, v_net_dr
  FROM (
    SELECT SUM(jel.debit_amount) - SUM(jel.credit_amount) AS net_dr
    FROM journal_entry_lines jel
    JOIN journal_entries je ON je.id = jel.je_id
    JOIN chart_of_accounts coa ON coa.id = jel.account_id
    WHERE jel.company_id = p_company_id
      AND je.status IN ('posted','reversed')
      AND je.entry_class IN ('regular','adjusting','opening')
      AND je.je_date BETWEEN v_year.start_date AND v_year.end_date
      AND coa.account_type IN ('revenue','expense')
    GROUP BY jel.account_id
    HAVING ABS(SUM(jel.debit_amount) - SUM(jel.credit_amount)) > 0.005
  ) t;

  -- net_dr = Sum(debit - credit) over P&L accounts = expenses - revenue.
  v_net_income := -v_net_dr;

  IF v_close_debit <> 0 OR v_close_credit <> 0 THEN
    v_re_debit  := CASE WHEN v_net_income < 0 THEN -v_net_income ELSE 0 END;
    v_re_credit := CASE WHEN v_net_income > 0 THEN  v_net_income ELSE 0 END;
    v_total_debit  := v_close_debit  + v_re_debit;
    v_total_credit := v_close_credit + v_re_credit;

    IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
      RAISE EXCEPTION 'Internal error: closing entry does not balance (% vs %)', v_total_debit, v_total_credit;
    END IF;

    SELECT COUNT(*) + 1 INTO v_seq FROM journal_entries
    WHERE company_id = p_company_id AND je_number LIKE 'CLOSE-' || TO_CHAR(v_close_date, 'YYYY') || '-%';
    LOOP
      v_je_number := 'CLOSE-' || TO_CHAR(v_close_date, 'YYYY') || '-' || LPAD(v_seq::TEXT, 4, '0');
      EXIT WHEN NOT EXISTS (SELECT 1 FROM journal_entries WHERE company_id = p_company_id AND je_number = v_je_number);
      v_seq := v_seq + 1;
    END LOOP;

    v_je_id := fn_create_posted_journal_entry(
      p_company_id, NULL,
      v_je_number, v_close_date,
      'Year-end closing of ' || v_year.year_name,
      'CLOSE', p_fiscal_year_id,
      v_fp_id, 'posted', v_total_debit, v_total_credit,
      NULL, 'closing', false, false, true
    );

    -- One line per P&L account, posted on the side that zeroes its balance.
    FOR r IN
      SELECT jel.account_id,
             SUM(jel.debit_amount) - SUM(jel.credit_amount) AS net_dr,
             MIN(coa.account_code) AS account_code
      FROM journal_entry_lines jel
      JOIN journal_entries je ON je.id = jel.je_id
      JOIN chart_of_accounts coa ON coa.id = jel.account_id
      WHERE jel.company_id = p_company_id
        AND je.status IN ('posted','reversed')
        AND je.entry_class IN ('regular','adjusting','opening')
        AND je.je_date BETWEEN v_year.start_date AND v_year.end_date
        AND coa.account_type IN ('revenue','expense')
      GROUP BY jel.account_id
      HAVING ABS(SUM(jel.debit_amount) - SUM(jel.credit_amount)) > 0.005
      ORDER BY MIN(coa.account_code)
    LOOP
      v_line_no := v_line_no + 1;
      PERFORM fn_add_posting_line_push(
        v_je_id, v_line_no, r.account_id, 'Year-end close',
        CASE WHEN r.net_dr < 0 THEN -r.net_dr ELSE 0 END,
        CASE WHEN r.net_dr > 0 THEN  r.net_dr ELSE 0 END
      );
    END LOOP;

    -- Retained-earnings balancing line: net income increases equity (credit),
    -- a net loss decreases it (debit).
    IF v_re_debit > 0.005 OR v_re_credit > 0.005 THEN
      v_line_no := v_line_no + 1;
      PERFORM fn_add_posting_line_push(
        v_je_id, v_line_no, v_re_id,
        CASE WHEN v_net_income >= 0
          THEN 'Net income to retained earnings'
          ELSE 'Net loss to retained earnings'
        END,
        v_re_debit, v_re_credit
      );
    END IF;
  END IF;

  -- Every period of the year is closed by the year close. Periods that were not
  -- closed monthly get their own register row, so the register stays a complete
  -- statement of what is closed.
  INSERT INTO fiscal_close_runs (
    company_id, fiscal_year_id, fiscal_period_id, close_type, action,
    quarter_number, effective_date, reason, performed_by
  )
  SELECT p_company_id, p_fiscal_year_id, fp.id, 'period', 'close',
         ((fp.period_number - 1) / 3) + 1, fp.end_date,
         'Closed by the year-end close of ' || v_year.year_name, auth.uid()
  FROM fiscal_periods fp
  WHERE fp.company_id = p_company_id
    AND fp.fiscal_year_id = p_fiscal_year_id
    AND NOT EXISTS (
      SELECT 1 FROM fiscal_close_runs prior
      WHERE prior.fiscal_period_id = fp.id AND prior.close_type = 'period'
        AND prior.action = 'close' AND prior.superseded_by_id IS NULL
    );

  -- Lock all periods of the year and mark the year closed.
  UPDATE fiscal_periods SET is_locked = true, updated_at = NOW()
  WHERE fiscal_year_id = p_fiscal_year_id;
  UPDATE fiscal_years SET status = 'closed', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_fiscal_year_id;

  -- The year close is recorded exactly once. The partial unique index on the
  -- register is what makes a second closing journal impossible.
  INSERT INTO fiscal_close_runs (
    company_id, fiscal_year_id, close_type, action, effective_date,
    closing_je_id, net_income, retained_earnings_account_id, performed_by
  ) VALUES (
    p_company_id, p_fiscal_year_id, 'year', 'close', v_close_date,
    v_je_id, ROUND(COALESCE(v_net_income, 0), 2), v_re_id, auth.uid()
  );

  -- Roll forward: next year, its periods, and the same retained-earnings home.
  PERFORM fn_open_next_fiscal_year(p_company_id, p_fiscal_year_id);

  RETURN v_je_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_close_fiscal_year(UUID, UUID, DATE) IS
  'Year-end close: posts one balanced closing journal (entry_class=closing, reference_doc_type=CLOSE sourced on the fiscal year) that zeroes the year''s revenue/expense accounts and carries net income/loss to fiscal_years.retained_earnings_id, records the close in fiscal_close_runs, locks the year''s periods, marks the year closed, and opens the next fiscal year with the same retained-earnings destination. Direct-to-retained-earnings close (no Income Summary) per DEC-019. A duplicate close is structurally impossible: the register carries a partial unique index on the live year close.';

-- ── 10. Year-end reopen ────────────────────────────────────────────────────────
-- Immutability is absolute: the closing journal is never edited, voided or
-- deleted. The reopen posts its exact counter through the same kernel, classified
-- `closing` so the aggregation that computes net income continues to ignore both
-- entries and a re-close reproduces the same figure rather than doubling it.

CREATE OR REPLACE FUNCTION public.fn_reopen_fiscal_year(
  p_company_id     UUID,
  p_fiscal_year_id UUID,
  p_reason         TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_year        fiscal_years%ROWTYPE;
  v_reason      TEXT := NULLIF(BTRIM(COALESCE(p_reason, '')), '');
  v_later       TEXT;
  v_run         fiscal_close_runs%ROWTYPE;
  v_close_je    journal_entries%ROWTYPE;
  v_reversal_id UUID;
  v_je_number   TEXT;
  v_seq         INT;
  v_line_no     INT := 0;
  v_run_id      UUID;
  r             RECORD;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: reopening a fiscal year requires company admin rights';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A reason is required to reopen a closed fiscal year';
  END IF;

  SELECT * INTO v_year FROM fiscal_years
  WHERE id = p_fiscal_year_id AND company_id = p_company_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fiscal year % not found for this company', p_fiscal_year_id;
  END IF;
  IF v_year.status <> 'closed' THEN
    RAISE EXCEPTION 'Fiscal year % is not closed', v_year.year_name;
  END IF;

  -- Last-in, first-out, for the same reason periods reopen that way.
  SELECT fy.year_name INTO v_later
  FROM fiscal_years fy
  WHERE fy.company_id = p_company_id
    AND fy.start_date > v_year.end_date
    AND fy.status = 'closed'
  ORDER BY fy.start_date
  LIMIT 1;

  IF v_later IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot reopen % while the later fiscal year % is still closed',
      v_year.year_name, v_later;
  END IF;

  SELECT * INTO v_run FROM fiscal_close_runs
  WHERE company_id = p_company_id AND fiscal_year_id = p_fiscal_year_id
    AND close_type = 'year' AND action = 'close' AND superseded_by_id IS NULL
  FOR UPDATE;

  -- Periods reopen first: the counter journal has to post into the year it is
  -- putting back, and the posting guard admits only an open period.
  UPDATE fiscal_periods SET is_locked = false, updated_at = NOW()
  WHERE fiscal_year_id = p_fiscal_year_id AND is_locked = true;

  IF v_run.id IS NOT NULL AND v_run.closing_je_id IS NOT NULL THEN
    SELECT * INTO v_close_je FROM journal_entries WHERE id = v_run.closing_je_id;

    SELECT COUNT(*) + 1 INTO v_seq FROM journal_entries
    WHERE company_id = p_company_id
      AND je_number LIKE 'REOPEN-' || TO_CHAR(v_close_je.je_date, 'YYYY') || '-%';
    LOOP
      v_je_number := 'REOPEN-' || TO_CHAR(v_close_je.je_date, 'YYYY') || '-' || LPAD(v_seq::TEXT, 4, '0');
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM journal_entries WHERE company_id = p_company_id AND je_number = v_je_number
      );
      v_seq := v_seq + 1;
    END LOOP;

    v_reversal_id := fn_create_posted_journal_entry(
      p_company_id, v_close_je.branch_id,
      v_je_number, v_close_je.je_date,
      'Reopening of ' || v_year.year_name || ' — ' || v_reason,
      'CLOSE', p_fiscal_year_id,
      v_close_je.fiscal_period_id, 'posted',
      v_close_je.total_credit, v_close_je.total_debit,
      NULL, 'closing', false, false, true
    );

    FOR r IN
      SELECT line_number, account_id, description, debit_amount, credit_amount,
             branch_id, department_id, cost_center_id
      FROM journal_entry_lines
      WHERE je_id = v_close_je.id
      ORDER BY line_number
    LOOP
      v_line_no := v_line_no + 1;
      PERFORM fn_add_posting_line_push(
        v_reversal_id, v_line_no, r.account_id,
        'REOPEN — ' || COALESCE(r.description, ''),
        r.credit_amount, r.debit_amount,
        NULL, NULL, r.branch_id, r.department_id, r.cost_center_id
      );
    END LOOP;
  END IF;

  UPDATE fiscal_years
  SET status = 'open', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = p_fiscal_year_id;

  INSERT INTO fiscal_close_runs (
    company_id, fiscal_year_id, close_type, action, effective_date, reason,
    closing_je_id, performed_by
  ) VALUES (
    p_company_id, p_fiscal_year_id, 'year', 'reopen', v_year.end_date, v_reason,
    v_reversal_id, auth.uid()
  ) RETURNING id INTO v_run_id;

  -- The year close and every period close it covered are superseded together:
  -- the periods are open again, so their closes are no longer live.
  UPDATE fiscal_close_runs
  SET superseded_by_id = v_run_id
  WHERE company_id = p_company_id
    AND fiscal_year_id = p_fiscal_year_id
    AND action = 'close'
    AND superseded_by_id IS NULL
    AND id <> v_run_id;

  RETURN v_reversal_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_reopen_fiscal_year(UUID, UUID, TEXT) IS
  'Governed year-end reopen against a required reason. Posts the exact counter of the closing journal through the Accounting Kernel, classified closing so a later re-close recomputes the same net income instead of doubling it, unlocks the year''s periods, reopens the year, and supersedes the close it undoes. The original closing journal is never modified.';

-- ── 11. Grants ─────────────────────────────────────────────────────────────────
-- Default-deny: PUBLIC (and therefore anon) is revoked from every new function,
-- and only the roles that legitimately need it are granted back.

DO $$
DECLARE
  v_sig TEXT;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.fn_period_close_readiness(uuid, uuid)',
    'public.fn_close_accounting_period(uuid, uuid, text)',
    'public.fn_reopen_accounting_period(uuid, uuid, text)',
    'public.fn_close_accounting_quarter(uuid, uuid, integer, text)',
    'public.fn_reopen_fiscal_year(uuid, uuid, text)'
  ] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', v_sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_sig);
  END LOOP;
END;
$$;

-- Internal: the roll-forward is a step of the close, not a client capability; the
-- two guards are trigger bodies no caller invokes; and the origin classifier is
-- closed to every role exactly as fn_posting_kernel_origin already is.
REVOKE EXECUTE ON FUNCTION public.fn_open_next_fiscal_year(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_guard_fiscal_close_run_immutability() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_guard_fiscal_lock_origin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_fiscal_close_engine_origin(text) FROM PUBLIC;
