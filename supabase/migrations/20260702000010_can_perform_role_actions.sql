-- ══════════════════════════════════════════════════════════════════════════════
-- CAN_PERFORM ROLE/ACTION ENFORCEMENT (DEC-009)
-- Finding coverage: PXL-DA-003 / PXL-AUD-004, plus the role-gate half of
-- PXL-DA-012 (approver-not-creator SoD continues there).
--
-- Central matrix per DEC-009 on the existing owner/admin/member/viewer roles:
--   owner/admin  -> every action (setup, master data, create/edit, approve,
--                   post, void/cancel/bounce, reverse, compliance filing)
--   member       -> create/edit drafts and operational master data only
--   viewer/none  -> nothing (read-only via existing SELECT policies)
--
-- Enforcement is centralized in the lifecycle status gate that every posting,
-- void, cancel, bounce, reversal, approval, and filing path must pass through
-- (SECURITY DEFINER RPCs included — BEFORE triggers fire on their DML and
-- auth.uid() remains the calling user). This replaces the can_admin_company
-- stopgap check with the role/action matrix and closes the approval hole:
-- 'approved' joins the default restricted-status list, so members can no
-- longer approve SI/OR/VB/PV.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Central role/action matrix ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_can_perform(
  p_company_id UUID,
  p_action TEXT,
  p_document_type TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  IF p_company_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT role INTO v_role
  FROM user_company_memberships
  WHERE user_id = auth.uid()
    AND company_id = p_company_id;

  IF v_role IN ('owner', 'admin') THEN
    RETURN TRUE;
  ELSIF v_role = 'member' THEN
    -- Capture-only authority: drafts and operational master data.
    RETURN p_action IN ('create', 'edit', 'master_data');
  END IF;

  RETURN FALSE; -- viewer, non-member, anonymous
END;
$$;

COMMENT ON FUNCTION fn_can_perform(UUID, TEXT, TEXT) IS
  'DEC-009 role/action matrix. p_document_type is recorded for future '
  'per-document-type refinement (e.g. accountant/bookkeeper roles) and is not '
  'yet consulted; authority is role/action based.';

GRANT EXECUTE ON FUNCTION fn_can_perform(UUID, TEXT, TEXT) TO authenticated;

-- ── 2. Lifecycle gate routes through the matrix ────────────────────────────────
-- Same trigger function name so all existing triggers (core SI/OR/VB/PV with the
-- default list, plus the V2 tables with explicit status arguments) pick this up
-- without re-creation. Default restricted list now includes 'approved'.
CREATE OR REPLACE FUNCTION fn_require_admin_for_accounting_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_restricted_statuses TEXT[];
  v_action TEXT;
BEGIN
  v_restricted_statuses := CASE
    WHEN TG_NARGS > 0 THEN TG_ARGV
    ELSE ARRAY['approved', 'posted', 'cancelled', 'bounced', 'reversed']
  END;

  IF (TG_OP = 'INSERT' AND NEW.status = ANY(v_restricted_statuses))
     OR (TG_OP = 'UPDATE'
         AND NEW.status IS DISTINCT FROM OLD.status
         AND NEW.status = ANY(v_restricted_statuses)) THEN

    v_company_id := CASE
      WHEN TG_OP = 'INSERT' THEN NEW.company_id
      ELSE COALESCE(NEW.company_id, OLD.company_id)
    END;

    v_action := CASE NEW.status
      WHEN 'approved'  THEN 'approve'
      WHEN 'cancelled' THEN 'cancel'
      WHEN 'bounced'   THEN 'bounce'
      WHEN 'reversed'  THEN 'reverse'
      ELSE 'post' -- posted, filed, final, locked, closed, applied, paid, sent, ...
    END;

    IF NOT fn_can_perform(v_company_id, v_action, TG_TABLE_NAME) THEN
      RAISE EXCEPTION 'Access denied: owner/admin role required to % % (status %)',
        v_action, TG_TABLE_NAME, NEW.status;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ── 3. Close remaining lifecycle gaps ──────────────────────────────────────────
-- Petty cash voucher approval was ungated (its trigger listed only
-- posted/cancelled/reversed); journal_entries had no lifecycle gate at all
-- (direct writes are blocked by RLS, but SECURITY DEFINER paths were unguarded).
DROP TRIGGER IF EXISTS trg_admin_lifecycle_petty_cash_vouchers_insert ON petty_cash_vouchers;
CREATE TRIGGER trg_admin_lifecycle_petty_cash_vouchers_insert
  BEFORE INSERT ON petty_cash_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle('approved', 'posted', 'cancelled', 'reversed');

DROP TRIGGER IF EXISTS trg_admin_lifecycle_petty_cash_vouchers ON petty_cash_vouchers;
CREATE TRIGGER trg_admin_lifecycle_petty_cash_vouchers
  BEFORE UPDATE OF status ON petty_cash_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle('approved', 'posted', 'cancelled', 'reversed');

DROP TRIGGER IF EXISTS trg_admin_lifecycle_journal_entries_insert ON journal_entries;
CREATE TRIGGER trg_admin_lifecycle_journal_entries_insert
  BEFORE INSERT ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle('posted', 'reversed');

DROP TRIGGER IF EXISTS trg_admin_lifecycle_journal_entries ON journal_entries;
CREATE TRIGGER trg_admin_lifecycle_journal_entries
  BEFORE UPDATE OF status ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle('posted', 'reversed');

-- ── 4. Operational master data per DEC-009 ─────────────────────────────────────
-- Members may create/edit customers, suppliers, and items; viewers may not.
-- Deletion stays owner/admin: master data referenced by documents should be
-- deactivated by members, removed only by an admin.
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['customers', 'suppliers', 'items'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'auth_insert_' || t, t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR INSERT TO authenticated
         WITH CHECK (fn_can_perform(company_id, ''master_data'', %L))',
      'auth_insert_' || t, t, t);

    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'auth_update_' || t, t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR UPDATE TO authenticated
         USING (fn_can_perform(company_id, ''master_data'', %L))
         WITH CHECK (fn_can_perform(company_id, ''master_data'', %L))',
      'auth_update_' || t, t, t, t);

    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', 'auth_delete_' || t, t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR DELETE TO authenticated
         USING (can_admin_company(company_id))',
      'auth_delete_' || t, t);
  END LOOP;
END;
$$;
