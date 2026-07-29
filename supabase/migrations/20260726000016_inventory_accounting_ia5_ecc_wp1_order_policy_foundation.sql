-- =============================================================================
-- IA-5 Economic Costing Chronology Hardening — Work Package 1 (M1)
-- Order-policy and version foundation (dormant, additive, reversible)
--
-- Authority: ADR-C01 (frozen) and ECC-01 (accepted); implementation controlled by
--   docs/PXL/07. Inventory/04. Implementation/
--     IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md  §24 (WP-1), §17 (M1),
--     §6.4 (the six version objects), §19 (security), §21 (dormancy).
--   Authorised by ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md §20.
--
-- Scope (WP-1 only): create the six dormant ECC ordering-policy / version tables,
-- reusing the IA-5 guard / RLS / grant / audit / ENABLE-ALWAYS-immutability /
-- dormancy-CHECK patterns unchanged. Nothing is added to inventory_events; no
-- grant is exposed (SELECT-only, membership-scoped); no ordering, writer,
-- fingerprint, stream, or order-key object is created (WP-2…WP-9); Posting and the
-- Kernel are untouched. The certification-only rank set (effect 10/20/30/40/50;
-- source-type and transition ranks for IA5_CERTIFICATION) is materialised as a
-- rolled-back certification fixture by test 104 — dormant-foundation tables remain
-- empty in every persisted lane (guard 075), exactly as the other IA-5 tables.
--
-- Precondition (design §16.2(4)): inventory_events row count = 0. Verified 0
-- read-only immediately before authoring; a non-zero count is a stop condition,
-- not a backfill exercise.
--
-- Rollback: DROP the six tables + the new guard function in reverse dependency
-- order. Nothing existing is altered, so IA-5 returns byte-identical.
-- =============================================================================

-- Hard stop if an accepted inventory event exists (a source type was enabled
-- without governance). WP-1 must not run against a non-empty event table.
DO $$
BEGIN
  IF (SELECT count(*) FROM public.inventory_events) <> 0 THEN
    RAISE EXCEPTION
      'IA-5 ECC WP-1 stop condition: inventory_events is non-zero (%); this is a governance stop, not a backfill.',
      (SELECT count(*) FROM public.inventory_events);
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. Version objects (§6.4). Every table carries company_id for RLS (§19),
--    an activation_state dormancy CHECK (§21), immutable audit columns, and
--    reuses the IA-5 effective-/activation-dated version shape.
-- ---------------------------------------------------------------------------

-- 6.4(5) Canonical-form version — N-01…N-10 encoding rules + digest identity.
CREATE TABLE public.inventory_canonical_form_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  version_code TEXT NOT NULL,
  digest_algorithm TEXT NOT NULL DEFAULT 'sha256'
    CHECK (digest_algorithm = 'sha256'),
  encoding_rules JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(encoding_rules) = 'object'),
  activated_from DATE NOT NULL,
  activated_to DATE,
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_canonical_form_versions_code_ck
    CHECK (version_code ~ '^[A-Z][A-Z0-9_]{2,39}$'),
  CONSTRAINT inventory_canonical_form_versions_dates_ck
    CHECK (activated_to IS NULL OR activated_to >= activated_from),
  CONSTRAINT inventory_canonical_form_versions_code_uq
    UNIQUE (company_id, version_code)
);
CREATE INDEX inventory_canonical_form_versions_effective_idx
  ON public.inventory_canonical_form_versions (
    company_id, activated_from, COALESCE(activated_to, 'infinity'::date)
  );

-- 6.4(6) Correction-graph version — anchoring semantics, chain rules, proofs.
CREATE TABLE public.inventory_correction_graph_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  version_no INTEGER NOT NULL CHECK (version_no > 0),
  anchoring_semantics JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(anchoring_semantics) = 'object'),
  commutativity_proofs JSONB NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(commutativity_proofs) = 'array'),
  effective_from DATE NOT NULL,
  effective_to DATE,
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_correction_graph_versions_dates_ck
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT inventory_correction_graph_versions_version_uq
    UNIQUE (company_id, version_no)
);
CREATE INDEX inventory_correction_graph_versions_effective_idx
  ON public.inventory_correction_graph_versions (
    company_id, effective_from, COALESCE(effective_to, 'infinity'::date)
  );

-- 6.4(1) Event-order policy version — owns the effect/source-type/transition ranks.
CREATE TABLE public.inventory_event_order_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  policy_code TEXT NOT NULL,
  version_no INTEGER NOT NULL CHECK (version_no > 0),
  effective_from DATE NOT NULL,
  effective_to DATE,
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_event_order_policies_code_ck
    CHECK (policy_code ~ '^[A-Z][A-Z0-9_]{2,39}$'),
  CONSTRAINT inventory_event_order_policies_dates_ck
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT inventory_event_order_policies_code_version_uq
    UNIQUE (company_id, policy_code, version_no)
);
CREATE INDEX inventory_event_order_policies_effective_idx
  ON public.inventory_event_order_policies (
    company_id, policy_code, effective_from, COALESCE(effective_to, 'infinity'::date)
  );

-- 6.4(2) E3 effect-class rank — sparse (N-03), inherits its order policy.
CREATE TABLE public.inventory_event_effect_ranks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  order_policy_id UUID NOT NULL
    REFERENCES public.inventory_event_order_policies(id),
  effect_class TEXT NOT NULL
    CHECK (effect_class IN ('opening','increase','value_only','decrease','allowance')),
  effect_rank SMALLINT NOT NULL CHECK (effect_rank > 0),
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_event_effect_ranks_class_uq
    UNIQUE (order_policy_id, effect_class)
);
CREATE INDEX inventory_event_effect_ranks_policy_idx
  ON public.inventory_event_effect_ranks (order_policy_id);

-- 6.4(3) E4 source-type rank — unique rank AND unique source type per policy.
CREATE TABLE public.inventory_source_type_ranks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  order_policy_id UUID NOT NULL
    REFERENCES public.inventory_event_order_policies(id),
  source_document_type TEXT NOT NULL
    REFERENCES public.ref_inventory_event_source_types(source_document_type),
  source_type_rank SMALLINT NOT NULL CHECK (source_type_rank > 0),
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_source_type_ranks_rank_uq
    UNIQUE (order_policy_id, source_type_rank),
  CONSTRAINT inventory_source_type_ranks_type_uq
    UNIQUE (order_policy_id, source_document_type)
);
CREATE INDEX inventory_source_type_ranks_policy_idx
  ON public.inventory_source_type_ranks (order_policy_id);

-- 6.4(4) E7 lifecycle-transition rank — declares the legal transition set per type.
CREATE TABLE public.inventory_transition_ranks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  order_policy_id UUID NOT NULL
    REFERENCES public.inventory_event_order_policies(id),
  source_document_type TEXT NOT NULL
    REFERENCES public.ref_inventory_event_source_types(source_document_type),
  source_transition TEXT NOT NULL,
  transition_rank SMALLINT NOT NULL CHECK (transition_rank > 0),
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_transition_ranks_transition_ck
    CHECK (source_transition ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  CONSTRAINT inventory_transition_ranks_transition_uq
    UNIQUE (order_policy_id, source_document_type, source_transition)
);
CREATE INDEX inventory_transition_ranks_policy_idx
  ON public.inventory_transition_ranks (order_policy_id);

-- ---------------------------------------------------------------------------
-- 2. Foundation guard (reuses the IA-5 policy-guard pattern): advisory lock,
--    company existence, parent-company consistency for rank rows, and
--    non-overlap for the effective-/activation-dated version rows.
--    New function (additive) so WP-1 rollback is a clean DROP; the existing
--    fn_ia5_guard_inventory_policy_foundation is left byte-unchanged.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ia5_guard_inventory_order_policy_foundation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_company UUID;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended(TG_TABLE_NAME || ':' || NEW.company_id::text, 0)
  );

  IF NOT EXISTS (SELECT 1 FROM public.companies WHERE id = NEW.company_id) THEN
    RAISE EXCEPTION 'IA-5 ECC order-policy company % does not exist', NEW.company_id;
  END IF;

  IF TG_TABLE_NAME = 'inventory_event_order_policies' THEN
    IF EXISTS (
      SELECT 1 FROM public.inventory_event_order_policies p
      WHERE p.company_id = NEW.company_id
        AND p.policy_code = NEW.policy_code
        AND p.id <> NEW.id
        AND daterange(p.effective_from, COALESCE(p.effective_to + 1, 'infinity'::date), '[)')
            && daterange(NEW.effective_from, COALESCE(NEW.effective_to + 1, 'infinity'::date), '[)')
    ) THEN
      RAISE EXCEPTION 'Overlapping IA-5 ECC order policy for company % code %',
        NEW.company_id, NEW.policy_code;
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_canonical_form_versions' THEN
    IF EXISTS (
      SELECT 1 FROM public.inventory_canonical_form_versions v
      WHERE v.company_id = NEW.company_id
        AND v.id <> NEW.id
        AND daterange(v.activated_from, COALESCE(v.activated_to + 1, 'infinity'::date), '[)')
            && daterange(NEW.activated_from, COALESCE(NEW.activated_to + 1, 'infinity'::date), '[)')
    ) THEN
      RAISE EXCEPTION 'Overlapping IA-5 ECC canonical form version for company %',
        NEW.company_id;
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_correction_graph_versions' THEN
    IF EXISTS (
      SELECT 1 FROM public.inventory_correction_graph_versions v
      WHERE v.company_id = NEW.company_id
        AND v.id <> NEW.id
        AND daterange(v.effective_from, COALESCE(v.effective_to + 1, 'infinity'::date), '[)')
            && daterange(NEW.effective_from, COALESCE(NEW.effective_to + 1, 'infinity'::date), '[)')
    ) THEN
      RAISE EXCEPTION 'Overlapping IA-5 ECC correction graph version for company %',
        NEW.company_id;
    END IF;

  ELSIF TG_TABLE_NAME IN (
    'inventory_event_effect_ranks',
    'inventory_source_type_ranks',
    'inventory_transition_ranks'
  ) THEN
    SELECT p.company_id INTO v_parent_company
    FROM public.inventory_event_order_policies p
    WHERE p.id = NEW.order_policy_id;
    IF v_parent_company IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION 'IA-5 ECC rank company % does not match its order policy company %',
        NEW.company_id, v_parent_company;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Guard, immutability, and audit triggers (IA-5 pattern, per new table).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'inventory_canonical_form_versions',
    'inventory_correction_graph_versions',
    'inventory_event_order_policies',
    'inventory_event_effect_ranks',
    'inventory_source_type_ranks',
    'inventory_transition_ranks'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER aa_%I_guard BEFORE INSERT OR UPDATE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION '
      'public.fn_ia5_guard_inventory_order_policy_foundation()',
      v_table, v_table
    );
    EXECUTE format(
      'CREATE TRIGGER zz_%I_immutable BEFORE UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION '
      'public.fn_ia5_reject_immutable_inventory_fact()',
      v_table, v_table
    );
    EXECUTE format(
      'ALTER TABLE public.%I ENABLE ALWAYS TRIGGER zz_%I_immutable',
      v_table, v_table
    );
    EXECUTE format(
      'CREATE TRIGGER trg_%I_audit AFTER INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger()',
      v_table, v_table
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. RLS and privilege ownership (IA-5 pattern: SELECT-only, membership-scoped;
--    no write grant to any role; the guard function is owner-mediated).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'inventory_canonical_form_versions',
    'inventory_correction_graph_versions',
    'inventory_event_order_policies',
    'inventory_event_effect_ranks',
    'inventory_source_type_ranks',
    'inventory_transition_ranks'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated '
      'USING (public.is_company_member(company_id))',
      v_table || '_read', v_table
    );
    EXECUTE format(
      'REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role',
      v_table
    );
    EXECUTE format(
      'GRANT SELECT ON TABLE public.%I TO authenticated, service_role',
      v_table
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_ia5_guard_inventory_order_policy_foundation()
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Documentation of dormancy (no consumer, no grant, no activation).
-- ---------------------------------------------------------------------------
COMMENT ON TABLE public.inventory_event_order_policies IS
  'Dormant IA-5 ECC event-order policy version (WP-1). Owns effect/source-type/'
  'transition ranks. No consumer, no write grant; activation requires governance.';
COMMENT ON TABLE public.inventory_event_effect_ranks IS
  'Dormant IA-5 ECC E3 effect-class rank (sparse, N-03). Empty except in the '
  'rolled-back certification fixture (test 104).';
COMMENT ON TABLE public.inventory_source_type_ranks IS
  'Dormant IA-5 ECC E4 source-type rank. Empty except in the certification fixture.';
COMMENT ON TABLE public.inventory_transition_ranks IS
  'Dormant IA-5 ECC E7 lifecycle-transition rank. Empty except in the certification fixture.';
COMMENT ON TABLE public.inventory_canonical_form_versions IS
  'Dormant IA-5 ECC canonical-form version (N-01…N-10 encoding + sha256 digest identity).';
COMMENT ON TABLE public.inventory_correction_graph_versions IS
  'Dormant IA-5 ECC correction-graph version (anchoring semantics, chain rules, proofs).';
