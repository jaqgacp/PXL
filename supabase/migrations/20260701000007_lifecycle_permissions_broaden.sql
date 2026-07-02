-- ══════════════════════════════════════════════════════════════════════════════
-- PERMISSIONS HARDENING V2: broaden lifecycle status authorization
-- Finding coverage: PXL-DA-003 / PXL-AUD-004.
-- Keeps draft/pending data entry available to company members, but requires
-- owner/admin for authoritative accounting, inventory, asset, and filing states.
-- ══════════════════════════════════════════════════════════════════════════════

-- This replaces the V1 lifecycle helper while preserving behavior for existing
-- triggers that pass no arguments. New triggers pass the restricted statuses for
-- each table, avoiding one global status list that would over-block drafts.
CREATE OR REPLACE FUNCTION fn_require_admin_for_accounting_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_restricted_statuses TEXT[];
BEGIN
  v_restricted_statuses := CASE
    WHEN TG_NARGS > 0 THEN TG_ARGV
    ELSE ARRAY['posted','cancelled','bounced','reversed']
  END;

  IF TG_OP = 'INSERT' AND NEW.status = ANY(v_restricted_statuses) THEN
    v_company_id := NEW.company_id;
    IF NOT can_admin_company(v_company_id) THEN
      RAISE EXCEPTION 'Access denied: owner/admin role required to create % with status %',
        TG_TABLE_NAME, NEW.status;
    END IF;
  ELSIF TG_OP = 'UPDATE'
     AND NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status = ANY(v_restricted_statuses) THEN
    v_company_id := COALESCE(NEW.company_id, OLD.company_id);
    IF NOT can_admin_company(v_company_id) THEN
      RAISE EXCEPTION 'Access denied: owner/admin role required to change % status to %',
        TG_TABLE_NAME, NEW.status;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Optional setup/control hardening beyond the first critical-flow prerequisites.
-- These tables define dimensions, workflow, feature flags, and tax/compliance
-- behavior; normal document entry should not depend on ordinary users changing
-- them directly.
CREATE OR REPLACE PROCEDURE pxl_admin_write_policy(
  p_table TEXT,
  p_insert_policy TEXT,
  p_update_policy TEXT,
  p_delete_policy TEXT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  EXECUTE format('DROP POLICY IF EXISTS %I ON %I', p_insert_policy, p_table);
  EXECUTE format(
    'CREATE POLICY %I ON %I FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id))',
    p_insert_policy, p_table
  );

  EXECUTE format('DROP POLICY IF EXISTS %I ON %I', p_update_policy, p_table);
  EXECUTE format(
    'CREATE POLICY %I ON %I FOR UPDATE TO authenticated USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id))',
    p_update_policy, p_table
  );

  IF p_delete_policy IS NOT NULL THEN
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', p_delete_policy, p_table);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR DELETE TO authenticated USING (can_admin_company(company_id))',
      p_delete_policy, p_table
    );
  END IF;
END;
$$;

CALL pxl_admin_write_policy('departments', 'auth_insert_departments', 'auth_update_departments', 'auth_delete_departments');
CALL pxl_admin_write_policy('cost_centers', 'auth_insert_cost_centers', 'auth_update_cost_centers', 'auth_delete_cost_centers');
CALL pxl_admin_write_policy('exchange_rates', 'auth_insert_exchange_rates', 'auth_update_exchange_rates', 'auth_delete_exchange_rates');
CALL pxl_admin_write_policy('sys_feature_enablement', 'auth_insert_feature_enablement', 'auth_update_feature_enablement', 'auth_delete_feature_enablement');
CALL pxl_admin_write_policy('approval_workflows', 'auth_insert_approval_workflows', 'auth_update_approval_workflows', 'auth_delete_approval_workflows');
CALL pxl_admin_write_policy('approval_workflow_steps', 'auth_insert_workflow_steps', 'auth_update_workflow_steps', 'auth_delete_workflow_steps');
CALL pxl_admin_write_policy('approval_instances', 'auth_insert_approval_instances', 'auth_update_approval_instances', 'auth_delete_approval_instances');
CALL pxl_admin_write_policy('ewt_codes', 'auth_insert_ewt_codes', 'auth_update_ewt_codes', 'auth_delete_ewt_codes');
CALL pxl_admin_write_policy('fwt_codes', 'auth_insert_fwt_codes', 'auth_update_fwt_codes', 'auth_delete_fwt_codes');
CALL pxl_admin_write_policy('percentage_tax_codes', 'auth_insert_pt_codes', 'auth_update_pt_codes', 'auth_delete_pt_codes');
CALL pxl_admin_write_policy('compliance_profiles', 'auth_insert_compliance_profiles', 'auth_update_compliance_profiles', 'auth_delete_compliance_profiles');
CALL pxl_admin_write_policy('payment_terms', 'auth_insert_payment_terms', 'auth_update_payment_terms', 'auth_delete_payment_terms');
CALL pxl_admin_write_policy('item_categories', 'auth_insert_item_categories', 'auth_update_item_categories', 'auth_delete_item_categories');
CALL pxl_admin_write_policy('units_of_measure', 'auth_insert_uom', 'auth_update_uom', 'auth_delete_uom');

DROP PROCEDURE pxl_admin_write_policy(TEXT, TEXT, TEXT, TEXT);

-- Attach lifecycle triggers where the table exists and has a status column.
CREATE OR REPLACE PROCEDURE pxl_lifecycle_trigger(
  p_table TEXT,
  VARIADIC p_statuses TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status_args TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = p_table
      AND column_name = 'status'
  ) THEN
    RETURN;
  END IF;

  SELECT string_agg(quote_literal(s), ', ')
  INTO v_status_args
  FROM unnest(p_statuses) AS s;

  EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', 'trg_admin_lifecycle_' || p_table || '_insert', p_table);
  EXECUTE format(
    'CREATE TRIGGER %I
       BEFORE INSERT ON %I
       FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle(%s)',
    'trg_admin_lifecycle_' || p_table || '_insert', p_table, v_status_args
  );

  EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', 'trg_admin_lifecycle_' || p_table, p_table);
  EXECUTE format(
    'CREATE TRIGGER %I
       BEFORE UPDATE OF status ON %I
       FOR EACH ROW EXECUTE FUNCTION fn_require_admin_for_accounting_lifecycle(%s)',
    'trg_admin_lifecycle_' || p_table, p_table, v_status_args
  );
END;
$$;

-- Sales / AR
CALL pxl_lifecycle_trigger('credit_memos', 'approved', 'applied', 'paid', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('debit_memos', 'approved', 'applied', 'paid', 'posted', 'cancelled', 'reversed');

-- Purchasing / AP
CALL pxl_lifecycle_trigger('purchase_orders', 'approved', 'cancelled', 'closed');
CALL pxl_lifecycle_trigger('receiving_reports', 'approved', 'posted', 'cancelled', 'closed');
CALL pxl_lifecycle_trigger('cash_purchases', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('vendor_credits', 'open', 'applied', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('supplier_debit_memos', 'approved', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('purchase_returns', 'approved', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('form_2307_issuances', 'generated', 'sent', 'acknowledged', 'cancelled');

-- Banking / treasury
CALL pxl_lifecycle_trigger('petty_cash_replenishments', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('petty_cash_vouchers', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('cash_count_sheets', 'posted', 'approved', 'cancelled');
CALL pxl_lifecycle_trigger('fund_transfers', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('inter_branch_transfers', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('bank_adjustments', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('check_vouchers', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('bank_reconciliations', 'final', 'posted', 'locked', 'cancelled');

-- Inventory
CALL pxl_lifecycle_trigger('stock_adjustments', 'posted', 'approved', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('stock_transfers', 'posted', 'approved', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('goods_issues', 'posted', 'approved', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('physical_count_sheets', 'posted', 'approved', 'cancelled', 'closed');

-- Fixed assets, amortization, and revenue recognition
CALL pxl_lifecycle_trigger('asset_depreciation_entries', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('amortization_entries', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('amortization_schedules', 'cancelled', 'closed');
CALL pxl_lifecycle_trigger('revenue_recognition_entries', 'posted', 'cancelled', 'reversed');
CALL pxl_lifecycle_trigger('revenue_recognition_schedules', 'cancelled', 'closed');

-- Compliance filings/snapshots
CALL pxl_lifecycle_trigger('pt_returns', 'final', 'filed');
CALL pxl_lifecycle_trigger('vat_returns', 'final', 'filed');
CALL pxl_lifecycle_trigger('ewt_returns', 'final', 'filed');
CALL pxl_lifecycle_trigger('compliance_pt_working_papers_headers', 'final', 'filed');
CALL pxl_lifecycle_trigger('compliance_vat_working_papers_headers', 'final', 'filed');
CALL pxl_lifecycle_trigger('compliance_1601eq_working_papers_headers', 'final', 'filed');

DROP PROCEDURE pxl_lifecycle_trigger(TEXT, VARIADIC TEXT[]);
