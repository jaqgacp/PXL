-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-10 — Party Masters Enrichment (gaps MD-17, MD-18, MD-19)
--
-- Brings the customer/supplier masters to professional completeness: governed
-- group masters (replacing free text), a real multi-contact master, and duplicate-
-- TIN detection. Backend only — no UI, no transaction-form change, no posting/tax
-- change, no approval routing.
--
-- ── Inventory result (what already exists — NOT rebuilt / NOT duplicated) ──────
-- * customers / suppliers exist, are company-scoped (UNIQUE(company_id, code)),
--   member-gated (is_company_member), and audit-covered (fn_audit_trigger). They
--   already carry registered_name, trade_name, business_style, tin, default_tax_type,
--   default_terms_id, default_currency_id, default_gl_account_id, is_active, ATC/CWT
--   withholding defaults; customers additionally carry tin_branch_code, credit_limit,
--   delivery_address. These are LEFT UNCHANGED except for the two additive group FKs.
-- * Philippine TIN is ALREADY normalized to the canonical XXX-XXX-XXX-XXXXX format
--   and CHECK-constrained on both masters (20260715000001_philippine_tin_standard.sql:
--   fn_format_ph_tin / fn_ph_tin_digits + per-table normalize triggers). So MD-19 is
--   NOT about format — it is about DUPLICATE DETECTION, which is genuinely missing.
-- MISSING (this package): governed customer/supplier GROUP masters (groups are free
--   text today — MD-17); a multi-contact master (only a single embedded contact_person
--   — MD-18); and duplicate-TIN control (parties are unique by code, not TIN — MD-19).
--
-- ── What this migration adds (only the genuine gaps) ──────────────────────────
--   1. customer_groups / supplier_groups — governed company-scoped group masters;
--      additive nullable customers.customer_group_id / suppliers.supplier_group_id
--      FKs. The legacy free-text *_group columns are PRESERVED (non-destructive
--      fallback) and safely backfilled into the new masters.
--   2. party_contacts — one contacts master linked to a customer XOR a supplier,
--      with at-most-one primary per party; the single embedded contact_person is
--      preserved and backfilled as the primary contact.
--   3. fn_party_tin_duplicates(company, type, tin, exclude) — side-effect-free
--      detection of same-company, same-type parties sharing a normalized TIN
--      (warn/decide at the caller; no hard unique — legitimate branch/dual-role
--      duplicates exist).
--
-- Reuse: member-gated RLS (customers/suppliers pattern), MDP-02 fn_audit_trigger,
-- the existing fn_format_ph_tin normalization, and company/branch isolation helpers.
-- Additive, forward-only, idempotent; existing party records are preserved and never
-- silently rewritten. No engineering findings.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Group masters ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customer_groups (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID NOT NULL REFERENCES companies(id),
  group_code  TEXT NOT NULL,
  group_name  TEXT NOT NULL,
  description TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_by  UUID,
  updated_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, group_code)
);

CREATE TABLE IF NOT EXISTS supplier_groups (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID NOT NULL REFERENCES companies(id),
  group_code  TEXT NOT NULL,
  group_name  TEXT NOT NULL,
  description TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_by  UUID,
  updated_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, group_code)
);

CREATE INDEX IF NOT EXISTS idx_customer_groups_company ON customer_groups (company_id);
CREATE INDEX IF NOT EXISTS idx_supplier_groups_company ON supplier_groups (company_id);

-- Additive governed-group FKs on the party masters (legacy free-text columns kept).
ALTER TABLE customers ADD COLUMN IF NOT EXISTS customer_group_id UUID REFERENCES customer_groups(id);
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS supplier_group_id UUID REFERENCES supplier_groups(id);
CREATE INDEX IF NOT EXISTS idx_customers_group ON customers (customer_group_id) WHERE customer_group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_suppliers_group ON suppliers (supplier_group_id) WHERE supplier_group_id IS NOT NULL;

-- ── 2. Contacts master ────────────────────────────────────────────────────────
-- A contact belongs to exactly one party (a customer XOR a supplier). company_id is
-- validated against the parent by fn_party_contact_company_guard (isolation).
CREATE TABLE IF NOT EXISTS party_contacts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    UUID NOT NULL REFERENCES companies(id),
  customer_id   UUID REFERENCES customers(id) ON DELETE CASCADE,
  supplier_id   UUID REFERENCES suppliers(id) ON DELETE CASCADE,
  contact_name  TEXT NOT NULL,
  position      TEXT,
  email         TEXT,
  phone_number  TEXT,
  mobile_number TEXT,
  is_primary    BOOLEAN NOT NULL DEFAULT false,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  description   TEXT,
  created_by    UUID,
  updated_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT party_contacts_one_party_check CHECK (num_nonnulls(customer_id, supplier_id) = 1)
);

CREATE INDEX IF NOT EXISTS idx_party_contacts_customer ON party_contacts (customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_party_contacts_supplier ON party_contacts (supplier_id) WHERE supplier_id IS NOT NULL;
-- At most one primary contact per party.
CREATE UNIQUE INDEX IF NOT EXISTS uq_party_contacts_primary_customer
  ON party_contacts (customer_id) WHERE customer_id IS NOT NULL AND is_primary;
CREATE UNIQUE INDEX IF NOT EXISTS uq_party_contacts_primary_supplier
  ON party_contacts (supplier_id) WHERE supplier_id IS NOT NULL AND is_primary;

-- ── 3. updated_at triggers ────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_customer_groups_updated_at ON customer_groups;
CREATE TRIGGER trg_customer_groups_updated_at BEFORE UPDATE ON customer_groups
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_supplier_groups_updated_at ON supplier_groups;
CREATE TRIGGER trg_supplier_groups_updated_at BEFORE UPDATE ON supplier_groups
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
DROP TRIGGER IF EXISTS trg_party_contacts_updated_at ON party_contacts;
CREATE TRIGGER trg_party_contacts_updated_at BEFORE UPDATE ON party_contacts
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── 4. Party-contact company/isolation guard ──────────────────────────────────
CREATE OR REPLACE FUNCTION fn_party_contact_company_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_parent_company UUID;
BEGIN
  -- Defer the XOR (exactly-one-party) rule to party_contacts_one_party_check so a
  -- both/neither row fails with the constraint's 23514 rather than a lookup error.
  IF num_nonnulls(NEW.customer_id, NEW.supplier_id) <> 1 THEN
    RETURN NEW;
  END IF;

  IF NEW.customer_id IS NOT NULL THEN
    SELECT company_id INTO v_parent_company FROM customers WHERE id = NEW.customer_id;
  ELSE
    SELECT company_id INTO v_parent_company FROM suppliers WHERE id = NEW.supplier_id;
  END IF;

  IF v_parent_company IS NULL THEN
    RAISE EXCEPTION 'party for contact does not exist' USING ERRCODE = '23503';
  END IF;
  IF NEW.company_id IS NULL THEN
    NEW.company_id := v_parent_company;
  ELSIF NEW.company_id <> v_parent_company THEN
    RAISE EXCEPTION 'contact company must match its party company' USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_party_contacts_company_guard ON party_contacts;
CREATE TRIGGER trg_party_contacts_company_guard
  BEFORE INSERT OR UPDATE ON party_contacts
  FOR EACH ROW EXECUTE FUNCTION fn_party_contact_company_guard();

-- ── 5. RLS — company-member gated (mirrors customers / suppliers) ─────────────
ALTER TABLE customer_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_contacts  ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['customer_groups','supplier_groups','party_contacts'] LOOP
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

-- ── 6. Audit coverage (reuse the MDP-02 fn_audit_trigger mechanism) ───────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['customer_groups','supplier_groups','party_contacts'] LOOP
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

-- ── 7. Duplicate-TIN detection (MD-19) ────────────────────────────────────────
-- Side-effect-free: returns same-company, same-party-type rows whose stored TIN
-- equals the normalized input. Callers (forms/imports) decide whether a match is a
-- true duplicate or a legitimate exception (e.g. an entity that is both a customer
-- and a supplier, or distinct BIR branches). No hard unique constraint is imposed.
CREATE OR REPLACE FUNCTION fn_party_tin_duplicates(
  p_company_id UUID,
  p_party_type TEXT,
  p_tin        TEXT,
  p_exclude_id UUID DEFAULT NULL
)
RETURNS TABLE (party_id UUID, party_code TEXT, party_name TEXT)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_norm TEXT := fn_format_ph_tin(p_tin);
BEGIN
  IF v_norm IS NULL THEN
    RETURN;  -- nothing to compare
  END IF;

  IF p_party_type = 'customer' THEN
    RETURN QUERY
      SELECT c.id, c.customer_code, c.registered_name
      FROM customers c
      WHERE c.company_id = p_company_id
        AND c.tin = v_norm
        AND (p_exclude_id IS NULL OR c.id <> p_exclude_id);
  ELSIF p_party_type = 'supplier' THEN
    RETURN QUERY
      SELECT s.id, s.supplier_code, s.registered_name
      FROM suppliers s
      WHERE s.company_id = p_company_id
        AND s.tin = v_norm
        AND (p_exclude_id IS NULL OR s.id <> p_exclude_id);
  ELSE
    RAISE EXCEPTION 'unknown party type %', p_party_type USING ERRCODE = '22023';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_party_tin_duplicates(UUID, TEXT, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_party_tin_duplicates(UUID, TEXT, TEXT, UUID) TO authenticated, service_role;
REVOKE ALL ON FUNCTION fn_party_contact_company_guard() FROM PUBLIC;

-- ── 8. Non-destructive backfill of existing data ──────────────────────────────
-- Free-text groups → governed masters (original text preserved as the fallback and
-- as the code/name), then link parties. Runs on any pre-existing rows; on a fresh
-- replay the party tables are empty, so this is a no-op.
INSERT INTO customer_groups (company_id, group_code, group_name)
SELECT DISTINCT company_id, btrim(customer_group), btrim(customer_group)
FROM customers
WHERE customer_group IS NOT NULL AND btrim(customer_group) <> ''
ON CONFLICT (company_id, group_code) DO NOTHING;

UPDATE customers c
   SET customer_group_id = g.id
FROM customer_groups g
WHERE g.company_id = c.company_id
  AND g.group_code = btrim(c.customer_group)
  AND c.customer_group IS NOT NULL AND btrim(c.customer_group) <> ''
  AND c.customer_group_id IS NULL;

INSERT INTO supplier_groups (company_id, group_code, group_name)
SELECT DISTINCT company_id, btrim(supplier_group), btrim(supplier_group)
FROM suppliers
WHERE supplier_group IS NOT NULL AND btrim(supplier_group) <> ''
ON CONFLICT (company_id, group_code) DO NOTHING;

UPDATE suppliers s
   SET supplier_group_id = g.id
FROM supplier_groups g
WHERE g.company_id = s.company_id
  AND g.group_code = btrim(s.supplier_group)
  AND s.supplier_group IS NOT NULL AND btrim(s.supplier_group) <> ''
  AND s.supplier_group_id IS NULL;

-- Single embedded contact_person → primary party_contact (only where not already
-- present, so replay does not duplicate).
INSERT INTO party_contacts (company_id, customer_id, contact_name, email, phone_number, is_primary, created_by, updated_by)
SELECT c.company_id, c.id, btrim(c.contact_person), c.email, c.phone_number, true, c.created_by, c.updated_by
FROM customers c
WHERE c.contact_person IS NOT NULL AND btrim(c.contact_person) <> ''
  AND NOT EXISTS (SELECT 1 FROM party_contacts pc WHERE pc.customer_id = c.id);

INSERT INTO party_contacts (company_id, supplier_id, contact_name, email, phone_number, is_primary, created_by, updated_by)
SELECT s.company_id, s.id, btrim(s.contact_person), s.email, s.phone_number, true, s.created_by, s.updated_by
FROM suppliers s
WHERE s.contact_person IS NOT NULL AND btrim(s.contact_person) <> ''
  AND NOT EXISTS (SELECT 1 FROM party_contacts pc WHERE pc.supplier_id = s.id);

-- ── 9. Comments ────────────────────────────────────────────────────────────────
COMMENT ON TABLE customer_groups IS 'MDP-10 (MD-17): governed company-scoped customer group master. Legacy customers.customer_group free text is preserved as fallback.';
COMMENT ON TABLE supplier_groups IS 'MDP-10 (MD-17): governed company-scoped supplier group master. Legacy suppliers.supplier_group free text is preserved as fallback.';
COMMENT ON TABLE party_contacts  IS 'MDP-10 (MD-18): multi-contact master linked to a customer XOR a supplier; at most one primary per party. The single embedded contact_person is preserved.';
COMMENT ON FUNCTION fn_party_tin_duplicates(UUID, TEXT, TEXT, UUID) IS
  'MDP-10 (MD-19): side-effect-free detection of same-company, same-type parties sharing a normalized TIN. Warn/decide at the caller; no hard unique (legitimate branch/dual-role duplicates exist).';
COMMENT ON FUNCTION fn_party_contact_company_guard() IS
  'MDP-10: BEFORE INSERT/UPDATE guard forcing party_contacts.company_id to match the parent customer/supplier company (tenant isolation).';
