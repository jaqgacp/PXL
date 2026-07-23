-- PXL-AUD-070: Posted-document immutability guards were bypassable by any
-- authenticated user (Critical production-integrity defect).
--
-- Root cause
-- ----------
-- The status-immutability trigger family (fn_guard_doc_header, fn_guard_doc_lines,
-- and the four fn_block_*_line_mutation_after_draft functions) short-circuited
-- immutability enforcement whenever the session GUC `pxl.allow_demo_reset` was
-- set to 'on'. `pxl.allow_demo_reset` is a placeholder GUC (USERSET): ANY role,
-- including `authenticated`, can `SET pxl.allow_demo_reset = 'on'` in its own
-- session. A company member could therefore set the GUC and then UPDATE or
-- DELETE a POSTED document (check vouchers, bank reconciliations, journal
-- entries, and every other guarded header/line table where the member holds a
-- direct DML grant under an `is_company_member` policy), defeating audit
-- immutability entirely.
--
-- Fix
-- ---
-- The demo/maintenance bypass is now gated on an UNSPOOFABLE privileged context,
-- not a user-settable flag. `fn_demo_reset_bypass_authorized()` requires BOTH:
--   1. the explicit opt-in GUC `pxl.allow_demo_reset = 'on'` (unchanged), AND
--   2. the session LOGIN role (`session_user`) to be a privileged maintenance
--      role — one carrying `rolsuper` or `rolbypassrls`.
--
-- `session_user` is the role established at connection time. It is NOT changed by
-- `SET ROLE`, by `SECURITY DEFINER`, or by any client-controllable statement;
-- only a superuser may change it (via `SET SESSION AUTHORIZATION`). The
-- canonical demo reset/seed run through a direct `postgres`/service maintenance
-- connection (privileged). Every PostgREST request runs as `session_user =
-- authenticator` (no `rolsuper`, no `rolbypassrls`) regardless of the JWT role,
-- so no browser/API caller can satisfy the check even after setting the GUC.
--
-- This migration only changes ENFORCEMENT of posted-document immutability. No
-- business-critical field, transaction shape, posting path, accounting rule, or
-- reporting view is altered. The maintenance/demo-reset behavior is preserved
-- verbatim for the privileged contexts that legitimately use it.

-- ─────────────────────────────────────────────────────────────────────────────
-- Privileged-context helpers
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_role_is_privileged_maintenance(p_role name)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- A privileged maintenance role is one that can already read/mutate across
  -- tenants by design: a superuser or a BYPASSRLS role (postgres, service_role,
  -- supabase_admin). The untrusted PostgREST roles (authenticator, authenticated,
  -- anon) carry neither attribute and can never be classified privileged here.
  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles r
    WHERE r.rolname = p_role
      AND (r.rolsuper OR r.rolbypassrls)
  );
$function$;

COMMENT ON FUNCTION public.fn_role_is_privileged_maintenance(name) IS
  'PXL-AUD-070: TRUE only when the named role is a privileged maintenance role (rolsuper OR rolbypassrls). Used to gate the demo-reset immutability bypass on an unspoofable login context. authenticator/authenticated/anon are never privileged.';

CREATE OR REPLACE FUNCTION public.fn_demo_reset_bypass_authorized()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- The controlled demo/maintenance immutability bypass is authorized ONLY when
  -- the caller has explicitly opted in via the GUC AND is connected as a
  -- privileged maintenance login. `session_user` is the connection login role;
  -- it is immune to SET ROLE / SECURITY DEFINER / client GUCs, so an
  -- authenticated PostgREST caller (session_user = authenticator) can never
  -- authorize the bypass even after setting pxl.allow_demo_reset = 'on'.
  SELECT COALESCE(current_setting('pxl.allow_demo_reset', true) = 'on', false)
     AND public.fn_role_is_privileged_maintenance(session_user);
$function$;

COMMENT ON FUNCTION public.fn_demo_reset_bypass_authorized() IS
  'PXL-AUD-070: Authoritative gate for the posted-document immutability demo/maintenance bypass. Requires pxl.allow_demo_reset=on AND a privileged session_user (fn_role_is_privileged_maintenance). Every immutability guard MUST route its bypass through this function; a bare current_setting(''pxl.allow_demo_reset'') short-circuit is the class of defect PXL-AUD-070 remediates (guarded by test 078).';

-- ─────────────────────────────────────────────────────────────────────────────
-- Core line-immutability guards (PXL-AUD-070: privileged-gated bypass)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_block_si_line_mutation_after_draft()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
  v_posting_internal BOOLEAN := COALESCE(current_setting('pxl.sales_invoice_posting_internal', true), '') = 'on';
BEGIN
  IF public.fn_demo_reset_bypass_authorized() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.sales_invoice_id;
  ELSE
    v_parent_id := NEW.sales_invoice_id;
  END IF;

  SELECT status INTO v_status
  FROM sales_invoices
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Sales invoice not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    IF v_posting_internal
       AND TG_OP = 'UPDATE'
       AND NEW.id IS NOT DISTINCT FROM OLD.id
       AND NEW.sales_invoice_id IS NOT DISTINCT FROM OLD.sales_invoice_id
       AND NEW.company_id IS NOT DISTINCT FROM OLD.company_id
       AND NEW.line_number IS NOT DISTINCT FROM OLD.line_number
       AND NEW.item_id IS NOT DISTINCT FROM OLD.item_id
       AND NEW.description IS NOT DISTINCT FROM OLD.description
       AND NEW.quantity IS NOT DISTINCT FROM OLD.quantity
       AND NEW.uom_id IS NOT DISTINCT FROM OLD.uom_id
       AND NEW.unit_price IS NOT DISTINCT FROM OLD.unit_price
       AND NEW.discount_percent IS NOT DISTINCT FROM OLD.discount_percent
       AND NEW.discount_amount IS NOT DISTINCT FROM OLD.discount_amount
       AND NEW.net_amount IS NOT DISTINCT FROM OLD.net_amount
       AND NEW.vat_code_id IS NOT DISTINCT FROM OLD.vat_code_id
       AND NEW.vat_amount IS NOT DISTINCT FROM OLD.vat_amount
       AND NEW.total_amount IS NOT DISTINCT FROM OLD.total_amount
       AND NEW.revenue_account_id IS NOT DISTINCT FROM OLD.revenue_account_id
       AND NEW.warehouse_id IS NOT DISTINCT FROM OLD.warehouse_id
       AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id
       AND NEW.cost_center_id IS NOT DISTINCT FROM OLD.cost_center_id
       AND NEW.salesperson_id IS NOT DISTINCT FROM OLD.salesperson_id
       AND NEW.remarks IS NOT DISTINCT FROM OLD.remarks
       AND NEW.source_document_type IS NOT DISTINCT FROM OLD.source_document_type
       AND NEW.source_line_id IS NOT DISTINCT FROM OLD.source_line_id
       AND NEW.created_by IS NOT DISTINCT FROM OLD.created_by
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Sales invoice lines cannot be changed when the invoice status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_block_receipt_line_mutation_after_draft()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF public.fn_demo_reset_bypass_authorized() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.receipt_id;
  ELSE
    v_parent_id := NEW.receipt_id;
  END IF;

  SELECT status INTO v_status
  FROM receipts
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Receipt not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Receipt lines cannot be changed when the receipt status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_block_vb_line_mutation_after_draft()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF public.fn_demo_reset_bypass_authorized() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.vendor_bill_id;
  ELSE
    v_parent_id := NEW.vendor_bill_id;
  END IF;

  SELECT status INTO v_status
  FROM vendor_bills
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Vendor bill not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Vendor bill lines cannot be changed when the bill status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_block_pv_line_mutation_after_draft()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_id UUID;
  v_status TEXT;
BEGIN
  IF public.fn_demo_reset_bypass_authorized() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_parent_id := OLD.payment_voucher_id;
  ELSE
    v_parent_id := NEW.payment_voucher_id;
  END IF;

  SELECT status INTO v_status
  FROM payment_vouchers
  WHERE id = v_parent_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found for line mutation.';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Payment voucher lines cannot be changed when the voucher status is %.', v_status;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_guard_doc_lines()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_parent_table TEXT   := TG_ARGV[0];
  v_fk_col       TEXT   := TG_ARGV[1];
  v_status_col   TEXT   := TG_ARGV[2];
  v_editable     TEXT[] := string_to_array(TG_ARGV[3], ',');
  v_same_txn_ok  BOOLEAN := TG_NARGS > 4 AND TG_ARGV[4] = 'same_txn';
  v_ids          UUID[];
  v_id           UUID;
  v_status       TEXT;
  v_xmin         BIGINT;
BEGIN
  IF public.fn_demo_reset_bypass_authorized() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_ids := ARRAY[(to_jsonb(NEW)->>v_fk_col)::UUID];
  ELSIF TG_OP = 'DELETE' THEN
    v_ids := ARRAY[(to_jsonb(OLD)->>v_fk_col)::UUID];
  ELSE
    v_ids := ARRAY[(to_jsonb(OLD)->>v_fk_col)::UUID];
    IF to_jsonb(NEW)->>v_fk_col IS DISTINCT FROM to_jsonb(OLD)->>v_fk_col THEN
      v_ids := v_ids || (to_jsonb(NEW)->>v_fk_col)::UUID;
    END IF;
  END IF;

  FOREACH v_id IN ARRAY v_ids LOOP
    IF v_id IS NULL THEN
      RAISE EXCEPTION '% rows must reference a parent document (% is null).',
        TG_TABLE_NAME, v_fk_col;
    END IF;

    EXECUTE format('SELECT %I::text, xmin::text::bigint FROM %I WHERE id = $1',
                   v_status_col, v_parent_table)
      INTO v_status, v_xmin USING v_id;

    IF v_status IS NULL THEN
      RAISE EXCEPTION 'Parent % row % not found for % mutation.',
        v_parent_table, v_id, TG_TABLE_NAME;
    END IF;

    IF v_status = ANY (v_editable) THEN
      CONTINUE;
    END IF;

    IF v_same_txn_ok AND fn_row_written_by_current_txn(v_xmin) THEN
      CONTINUE;
    END IF;

    RAISE EXCEPTION '% cannot be changed: parent % % is "%" (line changes allowed only in: %).',
      TG_TABLE_NAME, v_parent_table, v_id, v_status, array_to_string(v_editable, ', ');
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

COMMENT ON FUNCTION public.fn_guard_doc_lines() IS
  'Generic status-aware line immutability guard (PXL-DA-011). Args: parent table, FK column, parent status column, CSV of editable statuses, optional same_txn flag. PXL-AUD-070: the demo-reset bypass requires fn_demo_reset_bypass_authorized() (pxl.allow_demo_reset=on AND a privileged session_user); a user-settable GUC alone can no longer disable immutability.';

CREATE OR REPLACE FUNCTION public.fn_guard_doc_header()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status_col  TEXT   := TG_ARGV[0];
  v_editable    TEXT[] := string_to_array(TG_ARGV[1], ',');
  v_extra       TEXT[] := CASE WHEN TG_NARGS > 2 AND TG_ARGV[2] <> ''
                               THEN string_to_array(TG_ARGV[2], ',')
                               ELSE ARRAY[]::TEXT[] END;
  v_frozen      TEXT[] := CASE WHEN TG_NARGS > 3 AND TG_ARGV[3] <> ''
                               THEN string_to_array(TG_ARGV[3], ',')
                               ELSE ARRAY[]::TEXT[] END;
  v_same_txn_ok BOOLEAN := TG_NARGS > 4 AND TG_ARGV[4] = 'same_txn';
  v_old         JSONB;
  v_new         JSONB;
  v_old_status  TEXT;
  v_allowed     TEXT[];
  v_offending   TEXT[];
  v_xmin        BIGINT;
BEGIN
  IF public.fn_demo_reset_bypass_authorized() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_old := to_jsonb(OLD);
  v_old_status := v_old->>v_status_col;

  IF v_old_status = ANY (v_editable) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_same_txn_ok THEN
    EXECUTE format('SELECT xmin::text::bigint FROM %I WHERE id = $1', TG_TABLE_NAME)
      INTO v_xmin USING OLD.id;
    IF fn_row_written_by_current_txn(v_xmin) THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '% % cannot be deleted in status "%" (deletable only in: %); void or reverse instead.',
      TG_TABLE_NAME, OLD.id, v_old_status, array_to_string(v_editable, ', ');
  END IF;

  IF v_old_status = ANY (v_frozen) THEN
    v_allowed := ARRAY['updated_at', 'updated_by'];
  ELSE
    v_allowed := ARRAY[v_status_col, 'updated_at', 'updated_by'] || v_extra;
  END IF;

  v_new := to_jsonb(NEW);
  v_offending := ARRAY(
    SELECT k FROM jsonb_object_keys(v_old) AS k
    WHERE v_old->k IS DISTINCT FROM v_new->k
      AND k <> ALL (v_allowed)
  );

  IF array_length(v_offending, 1) IS NOT NULL THEN
    RAISE EXCEPTION '% % is "%" and immutable: column(s) [%] cannot change (allowed: %).',
      TG_TABLE_NAME, OLD.id, v_old_status,
      array_to_string(v_offending, ', '), array_to_string(v_allowed, ', ');
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.fn_guard_doc_header() IS
  'Generic status-aware header immutability guard (PXL-DA-011). Args: status column, CSV editable statuses, CSV extra allowed columns when locked, CSV frozen statuses, optional same_txn flag. PXL-AUD-070: the demo-reset bypass requires fn_demo_reset_bypass_authorized() (pxl.allow_demo_reset=on AND a privileged session_user); a user-settable GUC alone can no longer disable immutability.';
