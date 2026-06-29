-- ══════════════════════════════════════════════════════════════════════════════
-- REAL AUDIT LOG TRIGGERS
-- Replaces manual log calls with automatic DB-level triggers on key tables.
-- Uses sys_audit_logs (id, company_id, table_name, record_id, action,
-- old_data, new_data, changed_by, changed_at).
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_record     JSONB;
  v_company_id UUID;
BEGIN
  -- Works for INSERT, UPDATE, DELETE
  v_record := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;

  -- companies table uses its own 'id' as the tenant identifier
  v_company_id := CASE
    WHEN TG_TABLE_NAME = 'companies' THEN (v_record->>'id')::UUID
    ELSE (v_record->>'company_id')::UUID
  END;

  INSERT INTO sys_audit_logs (
    company_id,
    table_name,
    record_id,
    action,
    old_data,
    new_data,
    changed_by
  ) VALUES (
    v_company_id,
    TG_TABLE_NAME,
    (v_record->>'id')::UUID,
    TG_OP,
    CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
    CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
    auth.uid()
  );

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- ── Apply to key tables ───────────────────────────────────────────────────────
-- Limit to high-value tables: master data, transactional headers.
-- Line-level changes are captured implicitly via parent document headers.

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'companies',
    'branches',
    'customers',
    'suppliers',
    'items',
    'sales_invoices',
    'receipts',
    'credit_memos',
    'debit_memos',
    'sales_orders',
    'delivery_receipts'
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
