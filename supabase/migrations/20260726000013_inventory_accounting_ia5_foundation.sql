-- =============================================================================
-- Inventory Accounting Architecture — IA-5 dormant foundation
--
-- This migration is additive. It introduces immutable, method-neutral event,
-- source, policy, precision, occurrence, and projection-version evidence. It
-- does not route a current workflow through these objects, mutate historical
-- Inventory data, calculate a costing method, or write a journal.
--
-- Rollback boundary:
--   * before IA-6 activation, these dormant objects may be removed by a future
--     governed rollback migration after proving that they contain no accepted
--     non-certification occurrence;
--   * the four nullable/defaulted stock_balances projection-evidence columns
--     may be removed after the same proof;
--   * the fn_receive_inventory privilege closure may be restored only by an
--     explicit governed decision. Existing RR/CP/seed owner-mediated calls do
--     not require an external EXECUTE grant.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Dormant source-type registry
-- ---------------------------------------------------------------------------

CREATE TABLE public.ref_inventory_event_source_types (
  source_document_type TEXT PRIMARY KEY,
  owner_engine TEXT NOT NULL,
  is_certification_only BOOLEAN NOT NULL DEFAULT true,
  is_production_enabled BOOLEAN NOT NULL DEFAULT false,
  removal_phase TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ref_inventory_event_source_types_code_ck
    CHECK (source_document_type ~ '^[A-Z][A-Z0-9_]{2,39}$'),
  CONSTRAINT ref_inventory_event_source_types_dormant_ck
    CHECK (NOT is_production_enabled),
  CONSTRAINT ref_inventory_event_source_types_cert_ck
    CHECK (is_certification_only)
);

INSERT INTO public.ref_inventory_event_source_types (
  source_document_type,
  owner_engine,
  is_certification_only,
  is_production_enabled,
  removal_phase
) VALUES (
  'IA5_CERTIFICATION',
  'Inventory',
  true,
  false,
  'IA-6'
);

-- ---------------------------------------------------------------------------
-- 2. Effective-dated precision, accounting, formula, and scope identity
-- ---------------------------------------------------------------------------

CREATE TABLE public.inventory_precision_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  policy_code TEXT NOT NULL,
  version_no INTEGER NOT NULL CHECK (version_no > 0),
  quantity_scale SMALLINT NOT NULL CHECK (quantity_scale BETWEEN 0 AND 6),
  valuation_amount_scale SMALLINT NOT NULL DEFAULT 8
    CHECK (valuation_amount_scale = 8),
  unit_rate_scale SMALLINT NOT NULL DEFAULT 12
    CHECK (unit_rate_scale = 12),
  transaction_currency_code TEXT NOT NULL
    CHECK (transaction_currency_code ~ '^[A-Z]{3}$'),
  transaction_currency_scale SMALLINT NOT NULL
    CHECK (transaction_currency_scale BETWEEN 0 AND 8),
  functional_currency_code TEXT NOT NULL
    CHECK (functional_currency_code ~ '^[A-Z]{3}$'),
  functional_currency_scale SMALLINT NOT NULL
    CHECK (functional_currency_scale BETWEEN 0 AND 8),
  gl_basis_scale SMALLINT NOT NULL
    CHECK (gl_basis_scale BETWEEN 0 AND 8),
  effective_from DATE NOT NULL,
  effective_to DATE,
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_precision_policies_dates_ck
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT inventory_precision_policies_gl_scale_ck
    CHECK (gl_basis_scale = functional_currency_scale),
  CONSTRAINT inventory_precision_policies_code_version_uq
    UNIQUE (company_id, policy_code, version_no)
);

CREATE INDEX inventory_precision_policies_effective_idx
  ON public.inventory_precision_policies (
    company_id,
    effective_from,
    COALESCE(effective_to, 'infinity'::date)
  );

CREATE TABLE public.inventory_accounting_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  profile_code TEXT NOT NULL,
  version_no INTEGER NOT NULL CHECK (version_no > 0),
  accounting_framework TEXT NOT NULL DEFAULT 'PFRS_IAS2_IAS8'
    CHECK (accounting_framework = 'PFRS_IAS2_IAS8'),
  precision_policy_id UUID NOT NULL
    REFERENCES public.inventory_precision_policies(id),
  effective_from DATE NOT NULL,
  effective_to DATE,
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_accounting_profiles_dates_ck
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT inventory_accounting_profiles_code_version_uq
    UNIQUE (company_id, profile_code, version_no)
);

CREATE INDEX inventory_accounting_profiles_effective_idx
  ON public.inventory_accounting_profiles (
    company_id,
    effective_from,
    COALESCE(effective_to, 'infinity'::date)
  );

CREATE TABLE public.inventory_cost_formula_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  accounting_profile_id UUID NOT NULL
    REFERENCES public.inventory_accounting_profiles(id),
  policy_group_code TEXT NOT NULL,
  version_no INTEGER NOT NULL CHECK (version_no > 0),
  costing_method TEXT NOT NULL
    CHECK (costing_method IN (
      'fifo',
      'moving_weighted_average',
      'specific_identification'
    )),
  allowed_scope_type TEXT NOT NULL
    CHECK (allowed_scope_type IN ('company', 'branch', 'warehouse')),
  method_change_classification TEXT NOT NULL DEFAULT 'initial'
    CHECK (method_change_classification IN (
      'initial',
      'retrospective_policy_change',
      'earliest_practicable_conversion'
    )),
  transition_from_policy_id UUID
    REFERENCES public.inventory_cost_formula_policies(id),
  transition_evidence JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(transition_evidence) = 'object'),
  effective_from DATE NOT NULL,
  effective_to DATE,
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_cost_formula_policies_dates_ck
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT inventory_cost_formula_policies_transition_ck
    CHECK (
      (method_change_classification = 'initial'
        AND transition_from_policy_id IS NULL)
      OR
      (method_change_classification <> 'initial'
        AND transition_from_policy_id IS NOT NULL
        AND transition_evidence <> '{}'::jsonb)
    ),
  CONSTRAINT inventory_cost_formula_policies_code_version_uq
    UNIQUE (company_id, policy_group_code, version_no)
);

CREATE INDEX inventory_cost_formula_policies_effective_idx
  ON public.inventory_cost_formula_policies (
    company_id,
    policy_group_code,
    effective_from,
    COALESCE(effective_to, 'infinity'::date)
  );

CREATE TABLE public.inventory_valuation_scopes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  item_id UUID NOT NULL REFERENCES public.items(id),
  accounting_profile_id UUID NOT NULL
    REFERENCES public.inventory_accounting_profiles(id),
  cost_formula_policy_id UUID NOT NULL
    REFERENCES public.inventory_cost_formula_policies(id),
  scope_code TEXT NOT NULL,
  scope_type TEXT NOT NULL
    CHECK (scope_type IN ('company', 'branch', 'warehouse')),
  branch_id UUID REFERENCES public.branches(id),
  warehouse_id UUID REFERENCES public.warehouses(id),
  valuation_currency_code TEXT NOT NULL
    CHECK (valuation_currency_code ~ '^[A-Z]{3}$'),
  effective_from DATE NOT NULL,
  effective_to DATE,
  activation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (activation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_valuation_scopes_dates_ck
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT inventory_valuation_scopes_component_ck
    CHECK (
      (scope_type = 'company' AND branch_id IS NULL AND warehouse_id IS NULL)
      OR
      (scope_type = 'branch' AND branch_id IS NOT NULL AND warehouse_id IS NULL)
      OR
      (scope_type = 'warehouse' AND branch_id IS NULL AND warehouse_id IS NOT NULL)
    ),
  CONSTRAINT inventory_valuation_scopes_code_version_uq
    UNIQUE (company_id, item_id, scope_code, effective_from)
);

CREATE INDEX inventory_valuation_scopes_effective_idx
  ON public.inventory_valuation_scopes (
    company_id,
    item_id,
    effective_from,
    COALESCE(effective_to, 'infinity'::date)
  );

-- Internal mutable allocator. It assigns a governed sequence; the sequence is
-- evidence of accepted order and is not a stock or valuation projection.
CREATE TABLE public.inventory_valuation_scope_sequences (
  valuation_scope_id UUID PRIMARY KEY
    REFERENCES public.inventory_valuation_scopes(id),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  last_sequence BIGINT NOT NULL DEFAULT 0 CHECK (last_sequence >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-- ---------------------------------------------------------------------------
-- 3. Atomic occurrence and immutable method-neutral event facts
-- ---------------------------------------------------------------------------

CREATE TABLE public.inventory_occurrences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  atomic_occurrence_id UUID NOT NULL UNIQUE,
  company_id UUID NOT NULL REFERENCES public.companies(id),
  source_document_type TEXT NOT NULL
    REFERENCES public.ref_inventory_event_source_types(source_document_type),
  source_document_id UUID NOT NULL,
  source_line_id UUID NOT NULL,
  source_transition TEXT NOT NULL,
  source_occurrence_sequence BIGINT NOT NULL
    CHECK (source_occurrence_sequence > 0),
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  occurrence_state TEXT NOT NULL
    CHECK (occurrence_state IN ('accepted', 'rejected')),
  occurred_at TIMESTAMPTZ NOT NULL,
  event_ids UUID[] NOT NULL DEFAULT '{}'::uuid[],
  event_count INTEGER NOT NULL DEFAULT 0 CHECK (event_count >= 0),
  projection_effect_count INTEGER NOT NULL DEFAULT 0
    CHECK (projection_effect_count = 0),
  posting_request_id UUID,
  posting_result_id UUID,
  audit_identity UUID NOT NULL,
  failure_code TEXT,
  failure_evidence JSONB,
  retry_of_occurrence_id UUID REFERENCES public.inventory_occurrences(id),
  foundation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (foundation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_occurrences_transition_ck
    CHECK (source_transition ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  CONSTRAINT inventory_occurrences_idempotency_ck
    CHECK (length(idempotency_key) BETWEEN 16 AND 200),
  CONSTRAINT inventory_occurrences_fingerprint_ck
    CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  CONSTRAINT inventory_occurrences_atomic_identity_ck
    CHECK (atomic_occurrence_id = id AND audit_identity = id),
  CONSTRAINT inventory_occurrences_dormant_posting_ck
    CHECK (posting_request_id IS NULL AND posting_result_id IS NULL),
  CONSTRAINT inventory_occurrences_state_evidence_ck
    CHECK (
      (occurrence_state = 'accepted'
        AND event_count > 0
        AND cardinality(event_ids) = event_count
        AND failure_code IS NULL
        AND failure_evidence IS NULL)
      OR
      (occurrence_state = 'rejected'
        AND event_count = 0
        AND cardinality(event_ids) = 0
        AND failure_code IS NOT NULL
        AND failure_evidence IS NOT NULL
        AND jsonb_typeof(failure_evidence) = 'object')
    ),
  CONSTRAINT inventory_occurrences_company_idempotency_uq
    UNIQUE (company_id, idempotency_key),
  CONSTRAINT inventory_occurrences_logical_source_uq
    UNIQUE (
      company_id,
      source_document_type,
      source_document_id,
      source_line_id,
      source_transition,
      source_occurrence_sequence
    )
);

CREATE INDEX inventory_occurrences_source_idx
  ON public.inventory_occurrences (
    company_id,
    source_document_type,
    source_document_id,
    source_line_id,
    source_transition,
    source_occurrence_sequence
  );

CREATE TABLE public.inventory_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  occurrence_id UUID NOT NULL REFERENCES public.inventory_occurrences(id),
  source_document_type TEXT NOT NULL
    REFERENCES public.ref_inventory_event_source_types(source_document_type),
  source_document_id UUID NOT NULL,
  source_line_id UUID NOT NULL,
  source_transition TEXT NOT NULL,
  source_occurrence_sequence BIGINT NOT NULL
    CHECK (source_occurrence_sequence > 0),
  event_type TEXT NOT NULL,
  event_effect TEXT NOT NULL
    CHECK (event_effect IN (
      'quantity_increase',
      'quantity_decrease',
      'value_only'
    )),
  event_sequence INTEGER NOT NULL CHECK (event_sequence > 0),
  scope_sequence BIGINT NOT NULL CHECK (scope_sequence > 0),
  effective_at TIMESTAMPTZ NOT NULL,
  accounting_date DATE,
  occurrence_date DATE NOT NULL,
  item_id UUID NOT NULL REFERENCES public.items(id),
  valuation_scope_id UUID NOT NULL
    REFERENCES public.inventory_valuation_scopes(id),
  accounting_profile_id UUID NOT NULL
    REFERENCES public.inventory_accounting_profiles(id),
  cost_formula_policy_id UUID NOT NULL
    REFERENCES public.inventory_cost_formula_policies(id),
  precision_policy_id UUID NOT NULL
    REFERENCES public.inventory_precision_policies(id),
  costing_method TEXT NOT NULL
    CHECK (costing_method IN (
      'fifo',
      'moving_weighted_average',
      'specific_identification'
    )),
  physical_warehouse_id UUID REFERENCES public.warehouses(id),
  physical_location_id UUID REFERENCES public.locations(id),
  lot_number TEXT,
  serial_number TEXT,
  source_uom_id UUID NOT NULL REFERENCES public.units_of_measure(id),
  base_uom_id UUID NOT NULL REFERENCES public.units_of_measure(id),
  source_quantity NUMERIC(38,6) NOT NULL,
  base_quantity NUMERIC(38,6) NOT NULL,
  uom_conversion_factor NUMERIC(38,12) NOT NULL
    CHECK (uom_conversion_factor > 0),
  valuation_currency_code TEXT NOT NULL
    CHECK (valuation_currency_code ~ '^[A-Z]{3}$'),
  reversal_of_event_id UUID REFERENCES public.inventory_events(id),
  correction_of_event_id UUID REFERENCES public.inventory_events(id),
  predecessor_event_id UUID REFERENCES public.inventory_events(id),
  immutable_source_evidence JSONB NOT NULL,
  source_evidence_fingerprint TEXT NOT NULL,
  journal_entry_id UUID REFERENCES public.journal_entries(id),
  reason_code TEXT NOT NULL,
  foundation_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (foundation_state = 'dormant'),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_events_event_type_ck
    CHECK (event_type ~ '^[a-z][a-z0-9_]{2,49}$'),
  CONSTRAINT inventory_events_transition_ck
    CHECK (source_transition ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  CONSTRAINT inventory_events_quantity_direction_ck
    CHECK (
      (event_effect = 'quantity_increase'
        AND source_quantity > 0
        AND base_quantity > 0)
      OR
      (event_effect = 'quantity_decrease'
        AND source_quantity < 0
        AND base_quantity < 0)
      OR
      (event_effect = 'value_only'
        AND source_quantity = 0
        AND base_quantity = 0)
    ),
  CONSTRAINT inventory_events_source_evidence_ck
    CHECK (
      jsonb_typeof(immutable_source_evidence) = 'object'
      AND immutable_source_evidence <> '{}'::jsonb
    ),
  CONSTRAINT inventory_events_evidence_fingerprint_ck
    CHECK (source_evidence_fingerprint ~ '^[0-9a-f]{64}$'),
  CONSTRAINT inventory_events_dormant_posting_ck
    CHECK (journal_entry_id IS NULL),
  CONSTRAINT inventory_events_ancestry_ck
    CHECK (
      id IS DISTINCT FROM reversal_of_event_id
      AND id IS DISTINCT FROM correction_of_event_id
      AND id IS DISTINCT FROM predecessor_event_id
    ),
  CONSTRAINT inventory_events_occurrence_event_uq
    UNIQUE (occurrence_id, event_sequence),
  CONSTRAINT inventory_events_scope_sequence_uq
    UNIQUE (valuation_scope_id, scope_sequence),
  CONSTRAINT inventory_events_logical_event_uq
    UNIQUE (
      company_id,
      source_document_type,
      source_document_id,
      source_line_id,
      source_transition,
      source_occurrence_sequence,
      event_sequence
    )
);

CREATE INDEX inventory_events_deterministic_order_idx
  ON public.inventory_events (
    valuation_scope_id,
    effective_at,
    accounting_date,
    occurrence_date,
    scope_sequence,
    source_occurrence_sequence,
    event_sequence
  );

CREATE INDEX inventory_events_source_idx
  ON public.inventory_events (
    company_id,
    source_document_type,
    source_document_id,
    source_line_id
  );

CREATE TABLE public.inventory_event_source_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  inventory_event_id UUID NOT NULL REFERENCES public.inventory_events(id),
  relationship_type TEXT NOT NULL
    CHECK (relationship_type IN (
      'primary',
      'split',
      'partial',
      'predecessor',
      'reversal',
      'correction',
      'transfer_pair'
    )),
  source_document_type TEXT NOT NULL
    REFERENCES public.ref_inventory_event_source_types(source_document_type),
  source_document_id UUID NOT NULL,
  source_line_id UUID NOT NULL,
  source_transition TEXT NOT NULL,
  source_occurrence_sequence BIGINT NOT NULL
    CHECK (source_occurrence_sequence > 0),
  related_inventory_event_id UUID REFERENCES public.inventory_events(id),
  immutable_relationship_evidence JSONB NOT NULL
    CHECK (
      jsonb_typeof(immutable_relationship_evidence) = 'object'
      AND immutable_relationship_evidence <> '{}'::jsonb
    ),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_event_source_links_event_relation_uq
    UNIQUE (inventory_event_id, relationship_type, source_line_id,
            source_occurrence_sequence)
);

CREATE INDEX inventory_event_source_links_reverse_idx
  ON public.inventory_event_source_links (
    company_id,
    source_document_type,
    source_document_id,
    source_line_id
  );

CREATE TABLE public.inventory_event_values (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  inventory_event_id UUID NOT NULL REFERENCES public.inventory_events(id),
  value_role TEXT NOT NULL
    CHECK (value_role ~ '^[a-z][a-z0-9_]{2,49}$'),
  transaction_currency_code TEXT NOT NULL
    CHECK (transaction_currency_code ~ '^[A-Z]{3}$'),
  functional_currency_code TEXT NOT NULL
    CHECK (functional_currency_code ~ '^[A-Z]{3}$'),
  transaction_currency_scale SMALLINT NOT NULL
    CHECK (transaction_currency_scale BETWEEN 0 AND 8),
  functional_currency_scale SMALLINT NOT NULL
    CHECK (functional_currency_scale BETWEEN 0 AND 8),
  valuation_amount_scale SMALLINT NOT NULL DEFAULT 8
    CHECK (valuation_amount_scale = 8),
  unit_rate_scale SMALLINT NOT NULL DEFAULT 12
    CHECK (unit_rate_scale = 12),
  authoritative_transaction_amount NUMERIC(38,8) NOT NULL,
  authoritative_functional_amount NUMERIC(38,8) NOT NULL,
  gl_basis_amount NUMERIC(38,8) NOT NULL,
  derived_unit_rate NUMERIC(38,12),
  exchange_rate_identity TEXT,
  residual_units BIGINT NOT NULL DEFAULT 0,
  calculation_evidence JSONB NOT NULL
    CHECK (
      jsonb_typeof(calculation_evidence) = 'object'
      AND calculation_evidence <> '{}'::jsonb
    ),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_event_values_currency_metadata_ck
    CHECK (
      (transaction_currency_code = functional_currency_code
        AND exchange_rate_identity IS NULL)
      OR
      (transaction_currency_code <> functional_currency_code
        AND exchange_rate_identity IS NOT NULL)
    ),
  CONSTRAINT inventory_event_values_transaction_scale_ck
    CHECK (
      authoritative_transaction_amount
        = round(authoritative_transaction_amount, transaction_currency_scale)
    ),
  CONSTRAINT inventory_event_values_functional_scale_ck
    CHECK (
      gl_basis_amount = round(gl_basis_amount, functional_currency_scale)
    ),
  CONSTRAINT inventory_event_values_role_uq
    UNIQUE (inventory_event_id, value_role)
);

CREATE TABLE public.inventory_event_allocations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  inventory_event_value_id UUID NOT NULL
    REFERENCES public.inventory_event_values(id),
  allocation_sequence INTEGER NOT NULL CHECK (allocation_sequence > 0),
  allocation_key TEXT NOT NULL,
  authoritative_valuation_amount NUMERIC(38,8) NOT NULL,
  gl_basis_amount NUMERIC(38,8) NOT NULL,
  residual_rank INTEGER NOT NULL CHECK (residual_rank > 0),
  residual_units BIGINT NOT NULL DEFAULT 0,
  is_final_allocation BOOLEAN NOT NULL DEFAULT false,
  allocation_evidence JSONB NOT NULL
    CHECK (
      jsonb_typeof(allocation_evidence) = 'object'
      AND allocation_evidence <> '{}'::jsonb
    ),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_event_allocations_sequence_uq
    UNIQUE (inventory_event_value_id, allocation_sequence),
  CONSTRAINT inventory_event_allocations_key_uq
    UNIQUE (inventory_event_value_id, allocation_key)
);

-- ---------------------------------------------------------------------------
-- 4. Dormant projection-version evidence and current projection classification
-- ---------------------------------------------------------------------------

CREATE TABLE public.inventory_projection_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  valuation_scope_id UUID NOT NULL
    REFERENCES public.inventory_valuation_scopes(id),
  projection_type TEXT NOT NULL
    CHECK (projection_type IN (
      'stock',
      'reservation',
      'method_state',
      'report'
    )),
  replay_watermark_sequence BIGINT NOT NULL CHECK (replay_watermark_sequence >= 0),
  source_event_count BIGINT NOT NULL CHECK (source_event_count >= 0),
  projection_row_count BIGINT NOT NULL CHECK (projection_row_count >= 0),
  projection_fingerprint TEXT NOT NULL
    CHECK (projection_fingerprint ~ '^[0-9a-f]{64}$'),
  projection_state TEXT NOT NULL DEFAULT 'dormant'
    CHECK (projection_state = 'dormant'),
  rebuilt_by UUID NOT NULL REFERENCES auth.users(id),
  rebuilt_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT inventory_projection_versions_scope_kind_uq
    UNIQUE (
      valuation_scope_id,
      projection_type,
      replay_watermark_sequence
    )
);

ALTER TABLE public.stock_balances
  ADD COLUMN projection_authority TEXT NOT NULL DEFAULT 'legacy_active'
    CHECK (projection_authority = 'legacy_active'),
  ADD COLUMN projection_version_id UUID
    REFERENCES public.inventory_projection_versions(id),
  ADD COLUMN projection_watermark_sequence BIGINT
    CHECK (projection_watermark_sequence IS NULL
           OR projection_watermark_sequence >= 0),
  ADD COLUMN projection_fingerprint TEXT
    CHECK (projection_fingerprint IS NULL
           OR projection_fingerprint ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT stock_balances_ia5_legacy_projection_ck
    CHECK (
      projection_authority = 'legacy_active'
      AND projection_version_id IS NULL
      AND projection_watermark_sequence IS NULL
      AND projection_fingerprint IS NULL
    );

COMMENT ON TABLE public.stock_balances IS
  'Legacy-active current stock/valuation projection. IA-5 classifies it explicitly '
  'but does not change its writers or accounting behavior. It is not historical '
  'event truth and remains active until a separately certified later-phase cut-over.';

COMMENT ON TABLE public.inventory_transactions IS
  'Legacy-active Inventory movement ledger. IA-5 adds a separate dormant immutable '
  'event authority and does not backfill, infer, or route current workflows into it.';

COMMENT ON TABLE public.inventory_cost_layers IS
  'Legacy-active generic cost-layer state. IA-5 does not reinterpret historical WAC, '
  'FIFO, or Specific-ID rows; method-specific authorities begin only in later phases.';

-- ---------------------------------------------------------------------------
-- 5. Exact fixed-point primitives
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_ia5_quantize_exact(
  p_value NUMERIC,
  p_scale SMALLINT,
  p_label TEXT DEFAULT 'value'
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p_value IS NULL THEN
    RAISE EXCEPTION '% is required', p_label;
  END IF;
  IF p_scale < 0 OR p_scale > 12 THEN
    RAISE EXCEPTION '% scale % is outside the supported 0..12 range',
      p_label, p_scale;
  END IF;
  IF p_value <> round(p_value, p_scale) THEN
    RAISE EXCEPTION '% exceeds its governed scale %', p_label, p_scale;
  END IF;
  IF abs(p_value) >= power(10::numeric, 38 - p_scale) THEN
    RAISE EXCEPTION '% exceeds NUMERIC(38,%) capacity', p_label, p_scale;
  END IF;
  RETURN p_value;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_ia5_derive_unit_rate(
  p_authoritative_amount NUMERIC,
  p_base_quantity NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p_authoritative_amount IS NULL THEN
    RAISE EXCEPTION 'Authoritative amount is required';
  END IF;
  IF p_base_quantity IS NULL OR p_base_quantity = 0 THEN
    RAISE EXCEPTION 'A non-zero base quantity is required';
  END IF;
  RETURN round(p_authoritative_amount / abs(p_base_quantity), 12);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Foundation guards
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_ia5_reject_immutable_inventory_fact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '23514',
    MESSAGE = format(
      'IA-5 immutable Inventory authority rejects % on public.%I',
      TG_OP,
      TG_TABLE_NAME
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_ia5_guard_inventory_policy_foundation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_currency TEXT;
  v_parent_company UUID;
  v_parent_from DATE;
  v_parent_to DATE;
  v_profile_id UUID;
  v_method TEXT;
  v_scope_type TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended(TG_TABLE_NAME || ':' || NEW.company_id::text, 0)
  );

  SELECT functional_currency_code
  INTO v_company_currency
  FROM public.companies
  WHERE id = NEW.company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory policy company % does not exist', NEW.company_id;
  END IF;

  IF TG_TABLE_NAME = 'inventory_precision_policies' THEN
    IF NEW.functional_currency_code <> v_company_currency THEN
      RAISE EXCEPTION
        'Inventory functional currency % does not match company currency %',
        NEW.functional_currency_code,
        v_company_currency;
    END IF;
    IF EXISTS (
      SELECT 1
      FROM public.inventory_precision_policies p
      WHERE p.company_id = NEW.company_id
        AND p.id <> NEW.id
        AND daterange(
              p.effective_from,
              COALESCE(p.effective_to + 1, 'infinity'::date),
              '[)'
            )
            && daterange(
              NEW.effective_from,
              COALESCE(NEW.effective_to + 1, 'infinity'::date),
              '[)'
            )
    ) THEN
      RAISE EXCEPTION 'Overlapping Inventory precision policy for company %',
        NEW.company_id;
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_accounting_profiles' THEN
    SELECT p.company_id, p.effective_from, p.effective_to
    INTO v_parent_company, v_parent_from, v_parent_to
    FROM public.inventory_precision_policies p
    WHERE p.id = NEW.precision_policy_id;
    IF v_parent_company IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION 'Inventory profile precision policy company mismatch';
    END IF;
    IF NEW.effective_from < v_parent_from
       OR (v_parent_to IS NOT NULL
           AND COALESCE(NEW.effective_to, 'infinity'::date) > v_parent_to) THEN
      RAISE EXCEPTION 'Inventory profile exceeds precision-policy effective period';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM public.inventory_accounting_profiles p
      WHERE p.company_id = NEW.company_id
        AND p.id <> NEW.id
        AND daterange(
              p.effective_from,
              COALESCE(p.effective_to + 1, 'infinity'::date),
              '[)'
            )
            && daterange(
              NEW.effective_from,
              COALESCE(NEW.effective_to + 1, 'infinity'::date),
              '[)'
            )
    ) THEN
      RAISE EXCEPTION 'Overlapping Inventory accounting profile for company %',
        NEW.company_id;
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_cost_formula_policies' THEN
    SELECT p.company_id, p.effective_from, p.effective_to
    INTO v_parent_company, v_parent_from, v_parent_to
    FROM public.inventory_accounting_profiles p
    WHERE p.id = NEW.accounting_profile_id;
    IF v_parent_company IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION 'Inventory cost-formula profile company mismatch';
    END IF;
    IF NEW.effective_from < v_parent_from
       OR (v_parent_to IS NOT NULL
           AND COALESCE(NEW.effective_to, 'infinity'::date) > v_parent_to) THEN
      RAISE EXCEPTION 'Inventory cost-formula policy exceeds profile period';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM public.inventory_cost_formula_policies p
      WHERE p.company_id = NEW.company_id
        AND p.policy_group_code = NEW.policy_group_code
        AND p.id <> NEW.id
        AND daterange(
              p.effective_from,
              COALESCE(p.effective_to + 1, 'infinity'::date),
              '[)'
            )
            && daterange(
              NEW.effective_from,
              COALESCE(NEW.effective_to + 1, 'infinity'::date),
              '[)'
            )
    ) THEN
      RAISE EXCEPTION
        'Overlapping Inventory cost-formula policy for company % group %',
        NEW.company_id,
        NEW.policy_group_code;
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_valuation_scopes' THEN
    SELECT p.company_id, p.accounting_profile_id, p.costing_method,
           p.allowed_scope_type, p.effective_from, p.effective_to
    INTO v_parent_company, v_profile_id, v_method, v_scope_type,
         v_parent_from, v_parent_to
    FROM public.inventory_cost_formula_policies p
    WHERE p.id = NEW.cost_formula_policy_id;
    IF v_parent_company IS DISTINCT FROM NEW.company_id
       OR v_profile_id IS DISTINCT FROM NEW.accounting_profile_id THEN
      RAISE EXCEPTION 'Inventory valuation scope policy/profile company mismatch';
    END IF;
    IF v_scope_type <> NEW.scope_type THEN
      RAISE EXCEPTION
        'Inventory valuation scope type % is not allowed by policy type %',
        NEW.scope_type,
        v_scope_type;
    END IF;
    IF NEW.effective_from < v_parent_from
       OR (v_parent_to IS NOT NULL
           AND COALESCE(NEW.effective_to, 'infinity'::date) > v_parent_to) THEN
      RAISE EXCEPTION 'Inventory valuation scope exceeds formula-policy period';
    END IF;
    IF NEW.valuation_currency_code <> v_company_currency THEN
      RAISE EXCEPTION
        'Inventory valuation currency % does not match company currency %',
        NEW.valuation_currency_code,
        v_company_currency;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.items i
      WHERE i.id = NEW.item_id AND i.company_id = NEW.company_id
    ) THEN
      RAISE EXCEPTION 'Inventory valuation-scope item/company mismatch';
    END IF;
    IF NEW.branch_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.branches b
      WHERE b.id = NEW.branch_id AND b.company_id = NEW.company_id
    ) THEN
      RAISE EXCEPTION 'Inventory valuation-scope branch/company mismatch';
    END IF;
    IF NEW.warehouse_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.warehouses w
      WHERE w.id = NEW.warehouse_id AND w.company_id = NEW.company_id
    ) THEN
      RAISE EXCEPTION 'Inventory valuation-scope warehouse/company mismatch';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM public.inventory_valuation_scopes s
      WHERE s.company_id = NEW.company_id
        AND s.item_id = NEW.item_id
        AND s.scope_code = NEW.scope_code
        AND s.id <> NEW.id
        AND daterange(
              s.effective_from,
              COALESCE(s.effective_to + 1, 'infinity'::date),
              '[)'
            )
            && daterange(
              NEW.effective_from,
              COALESCE(NEW.effective_to + 1, 'infinity'::date),
              '[)'
            )
    ) THEN
      RAISE EXCEPTION
        'Overlapping Inventory valuation scope for company %, item %, scope %',
        NEW.company_id,
        NEW.item_id,
        NEW.scope_code;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_ia5_guard_inventory_event_fact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.inventory_events%ROWTYPE;
  v_occurrence public.inventory_occurrences%ROWTYPE;
  v_scope public.inventory_valuation_scopes%ROWTYPE;
  v_formula public.inventory_cost_formula_policies%ROWTYPE;
  v_profile public.inventory_accounting_profiles%ROWTYPE;
  v_precision public.inventory_precision_policies%ROWTYPE;
BEGIN
  IF TG_TABLE_NAME = 'inventory_events' THEN
    SELECT * INTO v_occurrence
    FROM public.inventory_occurrences
    WHERE id = NEW.occurrence_id;

    SELECT * INTO v_scope
    FROM public.inventory_valuation_scopes
    WHERE id = NEW.valuation_scope_id;

    SELECT * INTO v_formula
    FROM public.inventory_cost_formula_policies
    WHERE id = NEW.cost_formula_policy_id;

    SELECT * INTO v_profile
    FROM public.inventory_accounting_profiles
    WHERE id = NEW.accounting_profile_id;

    SELECT * INTO v_precision
    FROM public.inventory_precision_policies
    WHERE id = NEW.precision_policy_id;

    IF v_occurrence.company_id IS DISTINCT FROM NEW.company_id
       OR v_occurrence.source_document_type IS DISTINCT FROM NEW.source_document_type
       OR v_occurrence.source_document_id IS DISTINCT FROM NEW.source_document_id
       OR v_occurrence.source_line_id IS DISTINCT FROM NEW.source_line_id
       OR v_occurrence.source_transition IS DISTINCT FROM NEW.source_transition
       OR v_occurrence.source_occurrence_sequence
            IS DISTINCT FROM NEW.source_occurrence_sequence THEN
      RAISE EXCEPTION 'Inventory event source identity differs from its occurrence';
    END IF;

    IF v_scope.company_id IS DISTINCT FROM NEW.company_id
       OR v_scope.item_id IS DISTINCT FROM NEW.item_id
       OR v_scope.accounting_profile_id IS DISTINCT FROM NEW.accounting_profile_id
       OR v_scope.cost_formula_policy_id
            IS DISTINCT FROM NEW.cost_formula_policy_id
       OR v_scope.valuation_currency_code
            IS DISTINCT FROM NEW.valuation_currency_code THEN
      RAISE EXCEPTION 'Inventory event valuation-scope identity mismatch';
    END IF;

    IF v_formula.company_id IS DISTINCT FROM NEW.company_id
       OR v_formula.accounting_profile_id
            IS DISTINCT FROM NEW.accounting_profile_id
       OR v_formula.costing_method IS DISTINCT FROM NEW.costing_method THEN
      RAISE EXCEPTION 'Inventory event cost-formula policy mismatch';
    END IF;

    IF v_profile.company_id IS DISTINCT FROM NEW.company_id
       OR v_profile.precision_policy_id
            IS DISTINCT FROM NEW.precision_policy_id
       OR v_precision.company_id IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION 'Inventory event accounting/precision profile mismatch';
    END IF;

    IF NEW.effective_at::date < v_scope.effective_from
       OR (v_scope.effective_to IS NOT NULL
           AND NEW.effective_at::date > v_scope.effective_to)
       OR NEW.effective_at::date < v_formula.effective_from
       OR (v_formula.effective_to IS NOT NULL
           AND NEW.effective_at::date > v_formula.effective_to)
       OR NEW.effective_at::date < v_profile.effective_from
       OR (v_profile.effective_to IS NOT NULL
           AND NEW.effective_at::date > v_profile.effective_to)
       OR NEW.effective_at::date < v_precision.effective_from
       OR (v_precision.effective_to IS NOT NULL
           AND NEW.effective_at::date > v_precision.effective_to) THEN
      RAISE EXCEPTION 'Inventory event is outside an effective policy period';
    END IF;

    PERFORM public.fn_ia5_quantize_exact(
      NEW.source_quantity,
      v_precision.quantity_scale,
      'source quantity'
    );
    PERFORM public.fn_ia5_quantize_exact(
      NEW.base_quantity,
      v_precision.quantity_scale,
      'base quantity'
    );

    IF NOT EXISTS (
      SELECT 1 FROM public.units_of_measure u
      WHERE u.id = NEW.source_uom_id AND u.company_id = NEW.company_id
    ) OR NOT EXISTS (
      SELECT 1 FROM public.units_of_measure u
      WHERE u.id = NEW.base_uom_id AND u.company_id = NEW.company_id
    ) THEN
      RAISE EXCEPTION 'Inventory event UOM/company mismatch';
    END IF;

    IF NEW.physical_warehouse_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.warehouses w
      WHERE w.id = NEW.physical_warehouse_id
        AND w.company_id = NEW.company_id
    ) THEN
      RAISE EXCEPTION 'Inventory event warehouse/company mismatch';
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_event_source_links' THEN
    SELECT * INTO v_event
    FROM public.inventory_events
    WHERE id = NEW.inventory_event_id;
    IF v_event.company_id IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION 'Inventory event source-link company mismatch';
    END IF;
    IF NEW.relationship_type = 'primary'
       AND (
         v_event.source_document_type
           IS DISTINCT FROM NEW.source_document_type
         OR v_event.source_document_id
           IS DISTINCT FROM NEW.source_document_id
         OR v_event.source_line_id
           IS DISTINCT FROM NEW.source_line_id
         OR v_event.source_transition
           IS DISTINCT FROM NEW.source_transition
         OR v_event.source_occurrence_sequence
           IS DISTINCT FROM NEW.source_occurrence_sequence
       ) THEN
      RAISE EXCEPTION 'Primary Inventory source link differs from event identity';
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_event_values' THEN
    SELECT * INTO v_event
    FROM public.inventory_events
    WHERE id = NEW.inventory_event_id;
    SELECT * INTO v_precision
    FROM public.inventory_precision_policies
    WHERE id = v_event.precision_policy_id;
    IF v_event.company_id IS DISTINCT FROM NEW.company_id THEN
      RAISE EXCEPTION 'Inventory event-value company mismatch';
    END IF;
    IF NEW.transaction_currency_code
         IS DISTINCT FROM v_precision.transaction_currency_code
       OR NEW.functional_currency_code
         IS DISTINCT FROM v_precision.functional_currency_code
       OR NEW.transaction_currency_scale
         IS DISTINCT FROM v_precision.transaction_currency_scale
       OR NEW.functional_currency_scale
         IS DISTINCT FROM v_precision.functional_currency_scale
       OR NEW.valuation_amount_scale
         IS DISTINCT FROM v_precision.valuation_amount_scale
       OR NEW.unit_rate_scale
         IS DISTINCT FROM v_precision.unit_rate_scale THEN
      RAISE EXCEPTION 'Inventory event-value precision metadata mismatch';
    END IF;
    PERFORM public.fn_ia5_quantize_exact(
      NEW.authoritative_transaction_amount,
      v_precision.valuation_amount_scale,
      'authoritative transaction amount'
    );
    PERFORM public.fn_ia5_quantize_exact(
      NEW.authoritative_functional_amount,
      v_precision.valuation_amount_scale,
      'authoritative functional amount'
    );
    PERFORM public.fn_ia5_quantize_exact(
      NEW.gl_basis_amount,
      v_precision.gl_basis_scale,
      'GL-basis amount'
    );
    IF NEW.derived_unit_rate IS NOT NULL THEN
      PERFORM public.fn_ia5_quantize_exact(
        NEW.derived_unit_rate,
        v_precision.unit_rate_scale,
        'derived unit rate'
      );
    END IF;

  ELSIF TG_TABLE_NAME = 'inventory_event_allocations' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.inventory_event_values v
      WHERE v.id = NEW.inventory_event_value_id
        AND v.company_id = NEW.company_id
    ) THEN
      RAISE EXCEPTION 'Inventory event allocation company mismatch';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Internal dormant foundation services
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_ia5_create_dormant_policy_bundle(
  p_company_id UUID,
  p_item_id UUID,
  p_scope_type TEXT,
  p_branch_id UUID,
  p_warehouse_id UUID,
  p_costing_method TEXT,
  p_quantity_scale SMALLINT,
  p_transaction_currency_code TEXT,
  p_transaction_currency_scale SMALLINT,
  p_effective_from DATE,
  p_effective_to DATE,
  p_actor_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_currency TEXT;
  v_precision_id UUID := gen_random_uuid();
  v_profile_id UUID := gen_random_uuid();
  v_formula_id UUID := gen_random_uuid();
  v_scope_id UUID := gen_random_uuid();
  v_precision_version INTEGER;
  v_profile_version INTEGER;
  v_formula_version INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.user_company_memberships m
    WHERE m.user_id = p_actor_id
      AND m.company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'IA-5 policy actor is not a company member';
  END IF;

  SELECT functional_currency_code
  INTO v_company_currency
  FROM public.companies
  WHERE id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IA-5 policy company does not exist';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.items i
    WHERE i.id = p_item_id AND i.company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'IA-5 policy item does not belong to the company';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('ia5-policy:' || p_company_id::text, 0)
  );

  SELECT COALESCE(max(version_no), 0) + 1
  INTO v_precision_version
  FROM public.inventory_precision_policies
  WHERE company_id = p_company_id;

  SELECT COALESCE(max(version_no), 0) + 1
  INTO v_profile_version
  FROM public.inventory_accounting_profiles
  WHERE company_id = p_company_id;

  SELECT COALESCE(max(version_no), 0) + 1
  INTO v_formula_version
  FROM public.inventory_cost_formula_policies
  WHERE company_id = p_company_id
    AND policy_group_code = 'IA5_CERTIFICATION';

  INSERT INTO public.inventory_precision_policies (
    id, company_id, policy_code, version_no,
    quantity_scale, valuation_amount_scale, unit_rate_scale,
    transaction_currency_code, transaction_currency_scale,
    functional_currency_code, functional_currency_scale, gl_basis_scale,
    effective_from, effective_to, created_by
  ) VALUES (
    v_precision_id, p_company_id, 'IA5_CERTIFICATION', v_precision_version,
    p_quantity_scale, 8, 12,
    upper(p_transaction_currency_code), p_transaction_currency_scale,
    v_company_currency, 2, 2,
    p_effective_from, p_effective_to, p_actor_id
  );

  INSERT INTO public.inventory_accounting_profiles (
    id, company_id, profile_code, version_no, precision_policy_id,
    effective_from, effective_to, created_by
  ) VALUES (
    v_profile_id, p_company_id, 'IA5_CERTIFICATION', v_profile_version,
    v_precision_id, p_effective_from, p_effective_to, p_actor_id
  );

  INSERT INTO public.inventory_cost_formula_policies (
    id, company_id, accounting_profile_id, policy_group_code, version_no,
    costing_method, allowed_scope_type,
    effective_from, effective_to, created_by
  ) VALUES (
    v_formula_id, p_company_id, v_profile_id, 'IA5_CERTIFICATION',
    v_formula_version, p_costing_method, p_scope_type,
    p_effective_from, p_effective_to, p_actor_id
  );

  INSERT INTO public.inventory_valuation_scopes (
    id, company_id, item_id, accounting_profile_id, cost_formula_policy_id,
    scope_code, scope_type, branch_id, warehouse_id,
    valuation_currency_code, effective_from, effective_to, created_by
  ) VALUES (
    v_scope_id, p_company_id, p_item_id, v_profile_id, v_formula_id,
    'IA5-' || v_scope_id::text, p_scope_type, p_branch_id, p_warehouse_id,
    v_company_currency, p_effective_from, p_effective_to, p_actor_id
  );

  RETURN jsonb_build_object(
    'precision_policy_id', v_precision_id,
    'accounting_profile_id', v_profile_id,
    'cost_formula_policy_id', v_formula_id,
    'valuation_scope_id', v_scope_id,
    'activation_state', 'dormant'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_ia5_record_dormant_inventory_occurrence(
  p_company_id UUID,
  p_source_document_type TEXT,
  p_source_document_id UUID,
  p_source_line_id UUID,
  p_source_transition TEXT,
  p_source_occurrence_sequence BIGINT,
  p_idempotency_key TEXT,
  p_request_fingerprint TEXT,
  p_occurred_at TIMESTAMPTZ,
  p_actor_id UUID,
  p_events JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_occurrence_id UUID := gen_random_uuid();
  v_existing public.inventory_occurrences%ROWTYPE;
  v_inserted UUID;
  v_event_ids UUID[] := '{}'::uuid[];
  v_event_id UUID;
  v_event JSONB;
  v_value JSONB;
  v_scope public.inventory_valuation_scopes%ROWTYPE;
  v_formula public.inventory_cost_formula_policies%ROWTYPE;
  v_profile public.inventory_accounting_profiles%ROWTYPE;
  v_precision public.inventory_precision_policies%ROWTYPE;
  v_event_count INTEGER;
  v_i INTEGER;
  v_scope_sequence BIGINT;
  v_source_quantity NUMERIC;
  v_base_quantity NUMERIC;
  v_conversion_factor NUMERIC;
  v_transaction_amount NUMERIC;
  v_functional_amount NUMERIC;
  v_gl_basis_amount NUMERIC;
  v_unit_rate NUMERIC;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.user_company_memberships m
    WHERE m.user_id = p_actor_id
      AND m.company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'IA-5 occurrence actor is not a company member';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.ref_inventory_event_source_types s
    WHERE s.source_document_type = p_source_document_type
      AND s.is_certification_only
      AND NOT s.is_production_enabled
  ) THEN
    RAISE EXCEPTION
      'Inventory source type % is unavailable in dormant IA-5',
      p_source_document_type;
  END IF;

  IF p_source_document_id IS NULL OR p_source_line_id IS NULL THEN
    RAISE EXCEPTION 'IA-5 source document and source line are required';
  END IF;
  IF p_source_occurrence_sequence IS NULL
     OR p_source_occurrence_sequence <= 0 THEN
    RAISE EXCEPTION 'IA-5 source occurrence sequence must be positive';
  END IF;
  IF p_idempotency_key IS NULL
     OR length(p_idempotency_key) NOT BETWEEN 16 AND 200 THEN
    RAISE EXCEPTION 'IA-5 idempotency key length must be 16..200';
  END IF;
  IF p_request_fingerprint IS NULL
     OR p_request_fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'IA-5 request fingerprint must be 64 lowercase hex characters';
  END IF;
  IF p_events IS NULL
     OR jsonb_typeof(p_events) <> 'array'
     OR jsonb_array_length(p_events) = 0 THEN
    RAISE EXCEPTION 'IA-5 occurrence requires a non-empty event array';
  END IF;

  SELECT *
  INTO v_existing
  FROM public.inventory_occurrences
  WHERE company_id = p_company_id
    AND idempotency_key = p_idempotency_key;

  IF FOUND THEN
    IF v_existing.request_fingerprint <> p_request_fingerprint
       OR v_existing.source_document_type <> p_source_document_type
       OR v_existing.source_document_id <> p_source_document_id
       OR v_existing.source_line_id <> p_source_line_id
       OR v_existing.source_transition <> p_source_transition
       OR v_existing.source_occurrence_sequence
            <> p_source_occurrence_sequence THEN
      RAISE EXCEPTION 'IA-5 idempotency key was reused with different content';
    END IF;
    RETURN jsonb_build_object(
      'occurrence_id', v_existing.id,
      'occurrence_state', v_existing.occurrence_state,
      'duplicate', true,
      'event_ids', to_jsonb(v_existing.event_ids)
    );
  END IF;

  v_event_count := jsonb_array_length(p_events);
  FOR v_i IN 0..v_event_count - 1 LOOP
    v_event_ids := array_append(v_event_ids, gen_random_uuid());
  END LOOP;

  INSERT INTO public.inventory_occurrences (
    id, atomic_occurrence_id, company_id,
    source_document_type, source_document_id, source_line_id,
    source_transition, source_occurrence_sequence,
    idempotency_key, request_fingerprint, occurrence_state, occurred_at,
    event_ids, event_count, projection_effect_count,
    posting_request_id, posting_result_id, audit_identity,
    created_by
  ) VALUES (
    v_occurrence_id, v_occurrence_id, p_company_id,
    p_source_document_type, p_source_document_id, p_source_line_id,
    p_source_transition, p_source_occurrence_sequence,
    p_idempotency_key, p_request_fingerprint, 'accepted', p_occurred_at,
    v_event_ids, v_event_count, 0,
    NULL, NULL, v_occurrence_id,
    p_actor_id
  )
  ON CONFLICT (company_id, idempotency_key) DO NOTHING
  RETURNING id INTO v_inserted;

  IF v_inserted IS NULL THEN
    SELECT *
    INTO v_existing
    FROM public.inventory_occurrences
    WHERE company_id = p_company_id
      AND idempotency_key = p_idempotency_key;
    IF v_existing.request_fingerprint <> p_request_fingerprint
       OR v_existing.source_document_type <> p_source_document_type
       OR v_existing.source_document_id <> p_source_document_id
       OR v_existing.source_line_id <> p_source_line_id
       OR v_existing.source_transition <> p_source_transition
       OR v_existing.source_occurrence_sequence
            <> p_source_occurrence_sequence THEN
      RAISE EXCEPTION 'IA-5 idempotency key was reused with different content';
    END IF;
    RETURN jsonb_build_object(
      'occurrence_id', v_existing.id,
      'occurrence_state', v_existing.occurrence_state,
      'duplicate', true,
      'event_ids', to_jsonb(v_existing.event_ids)
    );
  END IF;

  FOR v_i IN 0..v_event_count - 1 LOOP
    v_event := p_events->v_i;
    v_event_id := v_event_ids[v_i + 1];

    SELECT * INTO v_scope
    FROM public.inventory_valuation_scopes
    WHERE id = (v_event->>'valuation_scope_id')::uuid
      AND company_id = p_company_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'IA-5 event valuation scope is missing or belongs to another company';
    END IF;

    SELECT * INTO v_formula
    FROM public.inventory_cost_formula_policies
    WHERE id = v_scope.cost_formula_policy_id;
    SELECT * INTO v_profile
    FROM public.inventory_accounting_profiles
    WHERE id = v_scope.accounting_profile_id;
    SELECT * INTO v_precision
    FROM public.inventory_precision_policies
    WHERE id = v_profile.precision_policy_id;

    v_source_quantity := (v_event->>'source_quantity')::numeric;
    v_base_quantity := (v_event->>'base_quantity')::numeric;
    v_conversion_factor := (v_event->>'uom_conversion_factor')::numeric;

    PERFORM public.fn_ia5_quantize_exact(
      v_source_quantity,
      v_precision.quantity_scale,
      'source quantity'
    );
    PERFORM public.fn_ia5_quantize_exact(
      v_base_quantity,
      v_precision.quantity_scale,
      'base quantity'
    );
    PERFORM public.fn_ia5_quantize_exact(
      v_conversion_factor,
      12,
      'UOM conversion factor'
    );

    IF v_base_quantity
       <> round(v_source_quantity * v_conversion_factor,
                v_precision.quantity_scale) THEN
      RAISE EXCEPTION 'IA-5 base quantity does not equal governed UOM conversion';
    END IF;

    INSERT INTO public.inventory_valuation_scope_sequences (
      valuation_scope_id,
      company_id,
      last_sequence
    ) VALUES (
      v_scope.id,
      p_company_id,
      0
    )
    ON CONFLICT (valuation_scope_id) DO NOTHING;

    UPDATE public.inventory_valuation_scope_sequences
    SET last_sequence = last_sequence + 1,
        updated_at = clock_timestamp()
    WHERE valuation_scope_id = v_scope.id
      AND company_id = p_company_id
    RETURNING last_sequence INTO v_scope_sequence;

    IF v_scope_sequence IS NULL THEN
      RAISE EXCEPTION 'IA-5 valuation-scope sequence company mismatch';
    END IF;

    INSERT INTO public.inventory_events (
      id, company_id, occurrence_id,
      source_document_type, source_document_id, source_line_id,
      source_transition, source_occurrence_sequence,
      event_type, event_effect, event_sequence, scope_sequence,
      effective_at, accounting_date, occurrence_date,
      item_id, valuation_scope_id, accounting_profile_id,
      cost_formula_policy_id, precision_policy_id, costing_method,
      physical_warehouse_id, physical_location_id,
      lot_number, serial_number,
      source_uom_id, base_uom_id,
      source_quantity, base_quantity, uom_conversion_factor,
      valuation_currency_code,
      reversal_of_event_id, correction_of_event_id, predecessor_event_id,
      immutable_source_evidence, source_evidence_fingerprint,
      reason_code, created_by
    ) VALUES (
      v_event_id, p_company_id, v_occurrence_id,
      p_source_document_type, p_source_document_id, p_source_line_id,
      p_source_transition, p_source_occurrence_sequence,
      v_event->>'event_type', v_event->>'event_effect',
      (v_event->>'event_sequence')::integer, v_scope_sequence,
      (v_event->>'effective_at')::timestamptz,
      NULLIF(v_event->>'accounting_date', '')::date,
      p_occurred_at::date,
      (v_event->>'item_id')::uuid, v_scope.id, v_profile.id,
      v_formula.id, v_precision.id, v_formula.costing_method,
      NULLIF(v_event->>'physical_warehouse_id', '')::uuid,
      NULLIF(v_event->>'physical_location_id', '')::uuid,
      NULLIF(v_event->>'lot_number', ''),
      NULLIF(v_event->>'serial_number', ''),
      (v_event->>'source_uom_id')::uuid,
      (v_event->>'base_uom_id')::uuid,
      v_source_quantity, v_base_quantity, v_conversion_factor,
      v_scope.valuation_currency_code,
      NULLIF(v_event->>'reversal_of_event_id', '')::uuid,
      NULLIF(v_event->>'correction_of_event_id', '')::uuid,
      NULLIF(v_event->>'predecessor_event_id', '')::uuid,
      v_event->'immutable_source_evidence',
      v_event->>'source_evidence_fingerprint',
      v_event->>'reason_code',
      p_actor_id
    );

    INSERT INTO public.inventory_event_source_links (
      company_id, inventory_event_id, relationship_type,
      source_document_type, source_document_id, source_line_id,
      source_transition, source_occurrence_sequence,
      immutable_relationship_evidence, created_by
    ) VALUES (
      p_company_id, v_event_id, 'primary',
      p_source_document_type, p_source_document_id, p_source_line_id,
      p_source_transition, p_source_occurrence_sequence,
      jsonb_build_object(
        'request_fingerprint', p_request_fingerprint,
        'source_evidence_fingerprint',
          v_event->>'source_evidence_fingerprint'
      ),
      p_actor_id
    );

    v_value := v_event->'value';
    IF v_value IS NOT NULL AND jsonb_typeof(v_value) <> 'null' THEN
      IF jsonb_typeof(v_value) <> 'object' THEN
        RAISE EXCEPTION 'IA-5 event value must be an object';
      END IF;

      v_transaction_amount :=
        (v_value->>'authoritative_transaction_amount')::numeric;
      v_functional_amount :=
        (v_value->>'authoritative_functional_amount')::numeric;
      v_gl_basis_amount := (v_value->>'gl_basis_amount')::numeric;

      PERFORM public.fn_ia5_quantize_exact(
        v_transaction_amount,
        v_precision.valuation_amount_scale,
        'authoritative transaction amount'
      );
      PERFORM public.fn_ia5_quantize_exact(
        v_functional_amount,
        v_precision.valuation_amount_scale,
        'authoritative functional amount'
      );
      PERFORM public.fn_ia5_quantize_exact(
        v_gl_basis_amount,
        v_precision.gl_basis_scale,
        'GL-basis amount'
      );

      IF v_value ? 'derived_unit_rate' THEN
        v_unit_rate := (v_value->>'derived_unit_rate')::numeric;
        PERFORM public.fn_ia5_quantize_exact(
          v_unit_rate,
          v_precision.unit_rate_scale,
          'derived unit rate'
        );
      ELSE
        v_unit_rate := NULL;
      END IF;

      INSERT INTO public.inventory_event_values (
        company_id, inventory_event_id, value_role,
        transaction_currency_code, functional_currency_code,
        transaction_currency_scale, functional_currency_scale,
        valuation_amount_scale, unit_rate_scale,
        authoritative_transaction_amount,
        authoritative_functional_amount,
        gl_basis_amount, derived_unit_rate,
        exchange_rate_identity, residual_units,
        calculation_evidence, created_by
      ) VALUES (
        p_company_id, v_event_id, v_value->>'value_role',
        v_precision.transaction_currency_code,
        v_precision.functional_currency_code,
        v_precision.transaction_currency_scale,
        v_precision.functional_currency_scale,
        v_precision.valuation_amount_scale,
        v_precision.unit_rate_scale,
        v_transaction_amount,
        v_functional_amount,
        v_gl_basis_amount,
        v_unit_rate,
        NULLIF(v_value->>'exchange_rate_identity', ''),
        COALESCE((v_value->>'residual_units')::bigint, 0),
        v_value->'calculation_evidence',
        p_actor_id
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'occurrence_id', v_occurrence_id,
    'occurrence_state', 'accepted',
    'duplicate', false,
    'event_ids', to_jsonb(v_event_ids)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Effective-period, consistency, immutability, and audit triggers
-- ---------------------------------------------------------------------------

CREATE TRIGGER aa_inventory_precision_policies_guard
BEFORE INSERT OR UPDATE ON public.inventory_precision_policies
FOR EACH ROW EXECUTE FUNCTION public.fn_ia5_guard_inventory_policy_foundation();

CREATE TRIGGER aa_inventory_accounting_profiles_guard
BEFORE INSERT OR UPDATE ON public.inventory_accounting_profiles
FOR EACH ROW EXECUTE FUNCTION public.fn_ia5_guard_inventory_policy_foundation();

CREATE TRIGGER aa_inventory_cost_formula_policies_guard
BEFORE INSERT OR UPDATE ON public.inventory_cost_formula_policies
FOR EACH ROW EXECUTE FUNCTION public.fn_ia5_guard_inventory_policy_foundation();

CREATE TRIGGER aa_inventory_valuation_scopes_guard
BEFORE INSERT OR UPDATE ON public.inventory_valuation_scopes
FOR EACH ROW EXECUTE FUNCTION public.fn_ia5_guard_inventory_policy_foundation();

CREATE TRIGGER aa_inventory_events_guard
BEFORE INSERT ON public.inventory_events
FOR EACH ROW EXECUTE FUNCTION public.fn_ia5_guard_inventory_event_fact();

CREATE TRIGGER aa_inventory_event_source_links_guard
BEFORE INSERT ON public.inventory_event_source_links
FOR EACH ROW EXECUTE FUNCTION public.fn_ia5_guard_inventory_event_fact();

CREATE TRIGGER aa_inventory_event_values_guard
BEFORE INSERT ON public.inventory_event_values
FOR EACH ROW EXECUTE FUNCTION public.fn_ia5_guard_inventory_event_fact();

CREATE TRIGGER aa_inventory_event_allocations_guard
BEFORE INSERT ON public.inventory_event_allocations
FOR EACH ROW EXECUTE FUNCTION public.fn_ia5_guard_inventory_event_fact();

DO $$
DECLARE
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'ref_inventory_event_source_types',
    'inventory_precision_policies',
    'inventory_accounting_profiles',
    'inventory_cost_formula_policies',
    'inventory_valuation_scopes',
    'inventory_occurrences',
    'inventory_events',
    'inventory_event_source_links',
    'inventory_event_values',
    'inventory_event_allocations',
    'inventory_projection_versions'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER zz_%I_immutable '
      'BEFORE UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION '
      'public.fn_ia5_reject_immutable_inventory_fact()',
      v_table,
      v_table
    );
    EXECUTE format(
      'ALTER TABLE public.%I ENABLE ALWAYS TRIGGER zz_%I_immutable',
      v_table,
      v_table
    );
  END LOOP;
END;
$$;

DO $$
DECLARE
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'inventory_precision_policies',
    'inventory_accounting_profiles',
    'inventory_cost_formula_policies',
    'inventory_valuation_scopes',
    'inventory_occurrences',
    'inventory_events',
    'inventory_event_source_links',
    'inventory_event_values',
    'inventory_event_allocations',
    'inventory_projection_versions'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%I_audit '
      'AFTER INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger()',
      v_table,
      v_table
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. RLS and privilege ownership
-- ---------------------------------------------------------------------------

ALTER TABLE public.ref_inventory_event_source_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY ref_inventory_event_source_types_read
  ON public.ref_inventory_event_source_types
  FOR SELECT TO authenticated
  USING (true);

DO $$
DECLARE
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'inventory_precision_policies',
    'inventory_accounting_profiles',
    'inventory_cost_formula_policies',
    'inventory_valuation_scopes',
    'inventory_valuation_scope_sequences',
    'inventory_occurrences',
    'inventory_events',
    'inventory_event_source_links',
    'inventory_event_values',
    'inventory_event_allocations',
    'inventory_projection_versions'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated '
      'USING (public.is_company_member(company_id))',
      v_table || '_read',
      v_table
    );
  END LOOP;
END;
$$;

REVOKE ALL ON TABLE public.ref_inventory_event_source_types
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.ref_inventory_event_source_types
  TO authenticated, service_role;

DO $$
DECLARE
  v_table TEXT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'inventory_precision_policies',
    'inventory_accounting_profiles',
    'inventory_cost_formula_policies',
    'inventory_valuation_scopes',
    'inventory_valuation_scope_sequences',
    'inventory_occurrences',
    'inventory_events',
    'inventory_event_source_links',
    'inventory_event_values',
    'inventory_event_allocations',
    'inventory_projection_versions'
  ] LOOP
    EXECUTE format(
      'REVOKE ALL ON TABLE public.%I '
      'FROM PUBLIC, anon, authenticated, service_role',
      v_table
    );
    EXECUTE format(
      'GRANT SELECT ON TABLE public.%I TO authenticated, service_role',
      v_table
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_ia5_quantize_exact(NUMERIC, SMALLINT, TEXT)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_ia5_derive_unit_rate(NUMERIC, NUMERIC)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_ia5_reject_immutable_inventory_fact()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_ia5_guard_inventory_policy_foundation()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_ia5_guard_inventory_event_fact()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_ia5_create_dormant_policy_bundle(
  UUID, UUID, TEXT, UUID, UUID, TEXT, SMALLINT,
  TEXT, SMALLINT, DATE, DATE, UUID
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_ia5_record_dormant_inventory_occurrence(
  UUID, TEXT, UUID, UUID, TEXT, BIGINT, TEXT, TEXT,
  TIMESTAMPTZ, UUID, JSONB
) FROM PUBLIC, anon, authenticated, service_role;

-- Mandatory closure of the one generic externally executable Inventory
-- mutator. Existing RR and Cash Purchase functions remain SECURITY DEFINER and
-- call this owner-owned helper without an external grant. Canonical seeds run
-- as migration/database owner and are likewise unchanged.
REVOKE ALL ON FUNCTION public.fn_receive_inventory(JSONB)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.fn_receive_inventory(JSONB) IS
  'IA-5 internalised legacy compatibility helper. Not client/service executable. '
  'Current owner-mediated RR and Cash Purchase callers remain unchanged. '
  'Mandatory final retirement: IA-7 acquisition cut-over.';

COMMENT ON FUNCTION public.fn_ia5_record_dormant_inventory_occurrence(
  UUID, TEXT, UUID, UUID, TEXT, BIGINT, TEXT, TEXT,
  TIMESTAMPTZ, UUID, JSONB
) IS
  'Internal IA-5 dormant occurrence/event authority. It cannot write current '
  'stock, cost layers, projections, or journals and has no external EXECUTE grant.';

COMMENT ON TABLE public.inventory_events IS
  'Dormant IA-5 immutable method-neutral Inventory event authority. No current '
  'workflow reads or writes this table; no historical rows are backfilled.';

COMMENT ON TABLE public.inventory_occurrences IS
  'Dormant IA-5 company/source-line occurrence and idempotency evidence. '
  'Accepted facts are append-only and have zero projection and Posting effects.';
