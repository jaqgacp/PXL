-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-13 — Item Master Inventory Readiness (gaps MD-21, MD-22, MD-23, MD-24)
--
-- Completes the item-master fields Phase 4 (Inventory) certification will depend on.
-- Backend / master-data ONLY: no inventory movement, valuation, costing engine,
-- reservations, transfers, UI, reports, or posting change. Provisioning/validation/
-- resolver helpers only.
--
-- ── Inventory result (what already exists — NOT rebuilt / NOT duplicated) ──────
-- * items: company-scoped (UNIQUE(company_id,item_code)), member-gated RLS,
--   audit-covered. Already has item_type (inventory_item/service/non_inventory),
--   category_id, uom_id, single barcode, pricing, GL accounts, NULLABLE
--   costing_method (fifo/weighted_average/specific_identification), min_stock_level,
--   reorder_point, is_active. These are LEFT UNCHANGED.
-- * units_of_measure already carries is_base_unit / base_uom_id / conversion_factor
--   (company UOM-level conversion). MD-23 is about ITEM-specific alternate UOMs.
-- * warehouses (company-scoped, GL-mapped, is_active) exist. No company inventory
--   defaults table exists.
-- MISSING: company default costing/negative-stock policy + default warehouse (MD-21/22);
--   item-level negative-stock override, reorder policy fields, preferred supplier,
--   serial/batch capability flags; item UOM conversions (MD-23); item multi-barcode
--   + media (MD-24).
--
-- Reuse: MDP-07 company-config pattern (company_inventory_config + provision/validate),
-- MDP-09/10 child-master conventions (company-isolation guard, member RLS, audit),
-- MDP-12 resolver-facade style (fn_item_* effective-policy helpers).
-- Additive, forward-only, idempotent. No engineering findings.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Company inventory defaults (MD-21 / MD-22 / warehouse default) ──────────
CREATE TABLE IF NOT EXISTS company_inventory_config (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID NOT NULL UNIQUE REFERENCES companies(id),
  default_costing_method TEXT NOT NULL DEFAULT 'weighted_average'
                          CHECK (default_costing_method IN ('fifo','weighted_average','specific_identification')),
  negative_stock_policy TEXT NOT NULL DEFAULT 'block'
                          CHECK (negative_stock_policy IN ('block','allow','warn')),
  default_warehouse_id  UUID REFERENCES warehouses(id),
  created_by            UUID,
  updated_by            UUID,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_company_inventory_config_updated_at ON company_inventory_config;
CREATE TRIGGER trg_company_inventory_config_updated_at
  BEFORE UPDATE ON company_inventory_config FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Default warehouse must belong to the same company.
CREATE OR REPLACE FUNCTION fn_company_inventory_config_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_wh_company UUID;
BEGIN
  IF NEW.default_warehouse_id IS NOT NULL THEN
    SELECT company_id INTO v_wh_company FROM warehouses WHERE id = NEW.default_warehouse_id;
    IF v_wh_company IS NULL THEN
      RAISE EXCEPTION 'default warehouse % does not exist', NEW.default_warehouse_id USING ERRCODE = '23503';
    END IF;
    IF v_wh_company <> NEW.company_id THEN
      RAISE EXCEPTION 'default warehouse must belong to the same company' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_company_inventory_config_guard ON company_inventory_config;
CREATE TRIGGER trg_company_inventory_config_guard
  BEFORE INSERT OR UPDATE ON company_inventory_config
  FOR EACH ROW EXECUTE FUNCTION fn_company_inventory_config_guard();

ALTER TABLE company_inventory_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cic_inv_read"   ON company_inventory_config;
DROP POLICY IF EXISTS "cic_inv_insert" ON company_inventory_config;
DROP POLICY IF EXISTS "cic_inv_update" ON company_inventory_config;
CREATE POLICY "cic_inv_read"   ON company_inventory_config FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cic_inv_insert" ON company_inventory_config FOR INSERT TO authenticated WITH CHECK (can_admin_company(company_id));
CREATE POLICY "cic_inv_update" ON company_inventory_config FOR UPDATE TO authenticated USING (can_admin_company(company_id));

DROP TRIGGER IF EXISTS trg_audit_company_inventory_config ON company_inventory_config;
CREATE TRIGGER trg_audit_company_inventory_config
  AFTER INSERT OR UPDATE OR DELETE ON company_inventory_config
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- ── 2. Provision + validate company inventory defaults (MDP-07 pattern) ───────
CREATE OR REPLACE FUNCTION fn_provision_company_inventory_config(p_company_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to provision inventory config for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  INSERT INTO company_inventory_config (company_id, default_warehouse_id, created_by, updated_by)
  VALUES (
    p_company_id,
    (SELECT id FROM warehouses WHERE company_id = p_company_id AND is_active ORDER BY warehouse_code LIMIT 1),
    auth.uid(), auth.uid())
  ON CONFLICT (company_id) DO NOTHING;

  SELECT id INTO v_id FROM company_inventory_config WHERE company_id = p_company_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_company_inventory_config(p_company_id UUID)
RETURNS TABLE (check_code TEXT, detail TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to validate inventory config for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM company_inventory_config WHERE company_id = p_company_id) THEN
    RETURN QUERY SELECT 'config_missing'::TEXT, format('no company_inventory_config row for company %s', p_company_id);
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 'default_warehouse_not_in_company'::TEXT,
         format('default warehouse %s is not a warehouse of this company', cic.default_warehouse_id)
  FROM company_inventory_config cic
  WHERE cic.company_id = p_company_id
    AND cic.default_warehouse_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM warehouses w WHERE w.id = cic.default_warehouse_id AND w.company_id = p_company_id)
  UNION ALL
  SELECT 'default_warehouse_inactive'::TEXT,
         format('default warehouse %s is inactive', cic.default_warehouse_id)
  FROM company_inventory_config cic
  JOIN warehouses w ON w.id = cic.default_warehouse_id AND w.company_id = p_company_id
  WHERE cic.company_id = p_company_id AND w.is_active = false;
END;
$$;

-- ── 3. Item-master additive fields (MD-21 override, reorder, sourcing, tracking)
ALTER TABLE items
  ADD COLUMN IF NOT EXISTS negative_stock_policy TEXT,
  ADD COLUMN IF NOT EXISTS max_stock_level     NUMERIC(15,4),
  ADD COLUMN IF NOT EXISTS safety_stock        NUMERIC(15,4),
  ADD COLUMN IF NOT EXISTS reorder_quantity    NUMERIC(15,4),
  ADD COLUMN IF NOT EXISTS preferred_supplier_id UUID REFERENCES suppliers(id),
  ADD COLUMN IF NOT EXISTS track_serial        BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS track_batch         BOOLEAN NOT NULL DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'items_negative_stock_policy_chk' AND conrelid = 'public.items'::regclass) THEN
    ALTER TABLE items ADD CONSTRAINT items_negative_stock_policy_chk
      CHECK (negative_stock_policy IS NULL OR negative_stock_policy IN ('block','allow','warn'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'items_reorder_nonneg_chk' AND conrelid = 'public.items'::regclass) THEN
    ALTER TABLE items ADD CONSTRAINT items_reorder_nonneg_chk
      CHECK ((max_stock_level  IS NULL OR max_stock_level  >= 0)
         AND (safety_stock     IS NULL OR safety_stock     >= 0)
         AND (reorder_quantity IS NULL OR reorder_quantity >= 0));
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_items_preferred_supplier ON items (preferred_supplier_id) WHERE preferred_supplier_id IS NOT NULL;

-- Preferred supplier must belong to the item's company.
CREATE OR REPLACE FUNCTION fn_item_reference_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_sup_company UUID;
BEGIN
  IF NEW.preferred_supplier_id IS NOT NULL THEN
    SELECT company_id INTO v_sup_company FROM suppliers WHERE id = NEW.preferred_supplier_id;
    IF v_sup_company IS NULL THEN
      RAISE EXCEPTION 'preferred supplier % does not exist', NEW.preferred_supplier_id USING ERRCODE = '23503';
    END IF;
    IF v_sup_company <> NEW.company_id THEN
      RAISE EXCEPTION 'preferred supplier must belong to the same company' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_item_reference_guard ON items;
CREATE TRIGGER trg_item_reference_guard
  BEFORE INSERT OR UPDATE OF preferred_supplier_id ON items
  FOR EACH ROW EXECUTE FUNCTION fn_item_reference_guard();

-- ── 4. Effective-policy resolvers (never NULL: item override → company → default)
CREATE OR REPLACE FUNCTION fn_item_costing_method(p_item_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(i.costing_method, cic.default_costing_method, 'weighted_average')
  FROM items i
  LEFT JOIN company_inventory_config cic ON cic.company_id = i.company_id
  WHERE i.id = p_item_id;
$$;

CREATE OR REPLACE FUNCTION fn_item_negative_stock_policy(p_item_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(i.negative_stock_policy, cic.negative_stock_policy, 'block')
  FROM items i
  LEFT JOIN company_inventory_config cic ON cic.company_id = i.company_id
  WHERE i.id = p_item_id;
$$;

-- ── 5. Item child masters: UOM conversions, barcodes, media ───────────────────
-- Shared company-isolation guard: forces company_id to the parent item's company,
-- and (where the row has a uom_id) requires that UOM to be same-company too.
CREATE OR REPLACE FUNCTION fn_item_child_company_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_item_company UUID;
  v_uom_id       UUID;
  v_uom_company  UUID;
BEGIN
  SELECT company_id INTO v_item_company FROM items WHERE id = NEW.item_id;
  IF v_item_company IS NULL THEN
    RAISE EXCEPTION 'item % does not exist', NEW.item_id USING ERRCODE = '23503';
  END IF;

  IF NEW.company_id IS NULL THEN
    NEW.company_id := v_item_company;
  ELSIF NEW.company_id <> v_item_company THEN
    RAISE EXCEPTION 'child row company must match its item company' USING ERRCODE = '23514';
  END IF;

  IF (to_jsonb(NEW) ? 'uom_id') THEN
    v_uom_id := (to_jsonb(NEW) ->> 'uom_id')::UUID;
    IF v_uom_id IS NOT NULL THEN
      SELECT company_id INTO v_uom_company FROM units_of_measure WHERE id = v_uom_id;
      IF v_uom_company IS NULL OR v_uom_company <> v_item_company THEN
        RAISE EXCEPTION 'uom must belong to the item company' USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 5a. Item UOM conversions (MD-23) — per-item alternate UOMs with a factor to base.
CREATE TABLE IF NOT EXISTS item_uom_conversions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     UUID NOT NULL REFERENCES companies(id),
  item_id        UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  uom_id         UUID NOT NULL REFERENCES units_of_measure(id),
  factor_to_base NUMERIC(18,6) NOT NULL CHECK (factor_to_base > 0),
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_by     UUID,
  updated_by     UUID,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (item_id, uom_id)
);
CREATE INDEX IF NOT EXISTS idx_item_uom_conversions_item ON item_uom_conversions (item_id);

-- 5b. Item barcodes (MD-24) — multiple barcodes; single items.barcode kept as fallback.
CREATE TABLE IF NOT EXISTS item_barcodes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID NOT NULL REFERENCES companies(id),
  item_id     UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  barcode     TEXT NOT NULL,
  uom_id      UUID REFERENCES units_of_measure(id),
  is_primary  BOOLEAN NOT NULL DEFAULT false,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_by  UUID,
  updated_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, barcode)
);
CREATE INDEX IF NOT EXISTS idx_item_barcodes_item ON item_barcodes (item_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_item_barcodes_primary ON item_barcodes (item_id) WHERE is_primary;

-- 5c. Item media (MD-24) — images/documents metadata.
CREATE TABLE IF NOT EXISTS item_media (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID NOT NULL REFERENCES companies(id),
  item_id     UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  media_type  TEXT NOT NULL DEFAULT 'image' CHECK (media_type IN ('image','document','other')),
  url         TEXT NOT NULL,
  title       TEXT,
  is_primary  BOOLEAN NOT NULL DEFAULT false,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_by  UUID,
  updated_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_item_media_item ON item_media (item_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_item_media_primary ON item_media (item_id) WHERE is_primary;

-- Triggers (guard + updated_at + audit + RLS) for the three child masters.
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['item_uom_conversions','item_barcodes','item_media'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%1$s_company_guard ON %1$s;
                    CREATE TRIGGER trg_%1$s_company_guard BEFORE INSERT OR UPDATE ON %1$s
                      FOR EACH ROW EXECUTE FUNCTION fn_item_child_company_guard();', t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%1$s_updated_at ON %1$s;
                    CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON %1$s
                      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();', t);
    EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_%1$s ON %1$s;
                    CREATE TRIGGER trg_audit_%1$s AFTER INSERT OR UPDATE OR DELETE ON %1$s
                      FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();', t);
    EXECUTE format('ALTER TABLE %1$s ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS "auth_read_%1$s"   ON %1$s;', t);
    EXECUTE format('DROP POLICY IF EXISTS "auth_insert_%1$s" ON %1$s;', t);
    EXECUTE format('DROP POLICY IF EXISTS "auth_update_%1$s" ON %1$s;', t);
    EXECUTE format('DROP POLICY IF EXISTS "auth_delete_%1$s" ON %1$s;', t);
    EXECUTE format('CREATE POLICY "auth_read_%1$s"   ON %1$s FOR SELECT TO authenticated USING (is_company_member(company_id));', t);
    EXECUTE format('CREATE POLICY "auth_insert_%1$s" ON %1$s FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));', t);
    EXECUTE format('CREATE POLICY "auth_update_%1$s" ON %1$s FOR UPDATE TO authenticated USING (is_company_member(company_id));', t);
    EXECUTE format('CREATE POLICY "auth_delete_%1$s" ON %1$s FOR DELETE TO authenticated USING (is_company_member(company_id));', t);
  END LOOP;
END;
$$;

-- ── 6. Least privilege + comments ─────────────────────────────────────────────
REVOKE ALL ON FUNCTION fn_provision_company_inventory_config(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_validate_company_inventory_config(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_item_costing_method(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_item_negative_stock_policy(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_company_inventory_config_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_item_reference_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_item_child_company_guard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_provision_company_inventory_config(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_company_inventory_config(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_item_costing_method(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_item_negative_stock_policy(UUID) TO authenticated, service_role;

COMMENT ON TABLE company_inventory_config IS 'MDP-13 (MD-21/22): per-company inventory defaults — default costing method, negative-stock policy, default warehouse. Admin-gated; the resolver fallback for items.';
COMMENT ON TABLE item_uom_conversions IS 'MDP-13 (MD-23): per-item alternate UOMs with a factor to the item base UOM. Company-scoped, member-gated, audited.';
COMMENT ON TABLE item_barcodes IS 'MDP-13 (MD-24): additional item barcodes (single items.barcode preserved as fallback); at most one primary per item.';
COMMENT ON TABLE item_media IS 'MDP-13 (MD-24): item image/document metadata; at most one primary per item.';
COMMENT ON FUNCTION fn_item_costing_method(UUID) IS 'MDP-13 (MD-22): effective costing method for an item (item override → company default → weighted_average). Never NULL; for future inventory/valuation consumers.';
COMMENT ON FUNCTION fn_item_negative_stock_policy(UUID) IS 'MDP-13 (MD-21): effective negative-stock policy for an item (item override → company default → block). Never NULL.';
