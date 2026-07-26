-- IA5-IA6-GATE-ORDER-001
-- Verification only. Run against a freshly reset local database.
-- All fixtures and helper functions are transaction-local and rolled back.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '1a5f0000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'ia5-final-order@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

CREATE TEMP TABLE gate_order_context (
  scenario TEXT PRIMARY KEY,
  company_id UUID NOT NULL,
  branch_id UUID NOT NULL,
  warehouse_id UUID NOT NULL,
  item_id UUID NOT NULL,
  uom_id UUID NOT NULL,
  valuation_scope_id UUID NOT NULL
);

CREATE TEMP TABLE gate_order_observation (
  scenario TEXT NOT NULL,
  command_label TEXT NOT NULL,
  source_document_id UUID NOT NULL,
  source_line_id UUID NOT NULL,
  source_occurrence_sequence BIGINT NOT NULL,
  occurrence_id UUID NOT NULL,
  scope_sequence BIGINT NOT NULL,
  economic_order_tuple TEXT NOT NULL,
  event_fingerprint TEXT NOT NULL,
  event_effect TEXT NOT NULL,
  base_quantity NUMERIC NOT NULL,
  PRIMARY KEY (scenario, command_label)
);

CREATE FUNCTION pg_temp.setup_order_scenario(p_scenario TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_company UUID := gen_random_uuid();
  v_branch UUID := gen_random_uuid();
  v_category UUID := gen_random_uuid();
  v_uom UUID := gen_random_uuid();
  v_warehouse UUID := gen_random_uuid();
  v_item UUID := gen_random_uuid();
  v_bundle JSONB;
BEGIN
  INSERT INTO public.companies (
    id, entity_type, registered_name, line_of_business, tin,
    tax_registration, accounting_period,
    address_line_1, address_line_2, city, province, zip_code,
    email, signatory_name, signatory_position, created_by, updated_by,
    functional_currency_code, reporting_currency_code
  ) VALUES (
    v_company, 'corporation', 'IA5 Final Order ' || p_scenario, 'Software',
    substr(translate(md5(p_scenario), 'abcdef', '123456'), 1, 14),
    'vat', 'calendar',
    '1 Test', 'Building', 'Makati', 'Metro Manila', '1200',
    p_scenario || '@ia5-order.test', 'IA5 Owner', 'President',
    '1a5f0000-0000-0000-0000-000000000001',
    '1a5f0000-0000-0000-0000-000000000001', 'PHP', 'PHP'
  );

  INSERT INTO public.user_company_memberships (
    user_id, company_id, role, granted_by
  ) VALUES (
    '1a5f0000-0000-0000-0000-000000000001',
    v_company, 'owner',
    '1a5f0000-0000-0000-0000-000000000001'
  );

  INSERT INTO public.branches (
    id, company_id, branch_code, branch_name,
    address_line_1, address_line_2, city, province, zip_code,
    created_by, updated_by
  ) VALUES (
    v_branch, v_company, 'HO', 'Head Office',
    '1 Test', 'Building', 'Makati', 'Metro Manila', '1200',
    '1a5f0000-0000-0000-0000-000000000001',
    '1a5f0000-0000-0000-0000-000000000001'
  );

  INSERT INTO public.item_categories (
    id, company_id, category_code, category_name
  ) VALUES (
    v_category, v_company, 'G' || substr(md5(p_scenario), 1, 8),
    'IA5 Final Order'
  );

  INSERT INTO public.units_of_measure (
    id, company_id, uom_code, description
  ) VALUES (v_uom, v_company, 'EA', 'Each');

  INSERT INTO public.warehouses (
    id, company_id, branch_id, warehouse_code, warehouse_name,
    created_by, updated_by
  ) VALUES (
    v_warehouse, v_company, v_branch, 'MAIN', 'Main',
    '1a5f0000-0000-0000-0000-000000000001',
    '1a5f0000-0000-0000-0000-000000000001'
  );

  INSERT INTO public.items (
    id, company_id, item_code, description, item_type, category_id, uom_id,
    costing_method, created_by, updated_by
  ) VALUES (
    v_item, v_company, 'ITEM-' || substr(md5(p_scenario), 1, 8),
    'IA5 Order Item', 'inventory_item', v_category, v_uom,
    'weighted_average',
    '1a5f0000-0000-0000-0000-000000000001',
    '1a5f0000-0000-0000-0000-000000000001'
  );

  v_bundle := public.fn_ia5_create_dormant_policy_bundle(
    v_company, v_item, 'warehouse', NULL, v_warehouse,
    'moving_weighted_average', 6::smallint, 'PHP', 2::smallint,
    '2026-01-01', '2026-12-31',
    '1a5f0000-0000-0000-0000-000000000001'
  );

  INSERT INTO gate_order_context VALUES (
    p_scenario, v_company, v_branch, v_warehouse, v_item, v_uom,
    (v_bundle->>'valuation_scope_id')::uuid
  );
END
$$;

CREATE FUNCTION pg_temp.admit_order_command(
  p_scenario TEXT,
  p_command_label TEXT,
  p_event_effect TEXT,
  p_quantity NUMERIC,
  p_effective_at TIMESTAMPTZ,
  p_document_id UUID,
  p_line_id UUID,
  p_source_occurrence_sequence BIGINT,
  p_line_order INTEGER DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_ctx gate_order_context%ROWTYPE;
  v_result JSONB;
  v_event_id UUID;
  v_fingerprint TEXT :=
    md5(p_scenario || ':' || p_command_label) ||
    md5(p_scenario || ':' || p_command_label || ':evidence');
BEGIN
  SELECT * INTO STRICT v_ctx
  FROM gate_order_context
  WHERE scenario = p_scenario;

  v_result := public.fn_ia5_record_dormant_inventory_occurrence(
    v_ctx.company_id,
    'IA5_CERTIFICATION',
    p_document_id,
    p_line_id,
    'ACCEPTED',
    p_source_occurrence_sequence,
    'ia5-final-' || p_scenario || '-' || lower(p_command_label) || '-0001',
    v_fingerprint,
    '2026-07-26T12:00:00Z',
    '1a5f0000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'event_type', 'final_order_' || lower(p_command_label),
      'event_effect', p_event_effect,
      'event_sequence', 1,
      'effective_at', p_effective_at,
      'accounting_date', p_effective_at::date,
      'item_id', v_ctx.item_id,
      'valuation_scope_id', v_ctx.valuation_scope_id,
      'physical_warehouse_id', v_ctx.warehouse_id,
      'source_uom_id', v_ctx.uom_id,
      'base_uom_id', v_ctx.uom_id,
      'source_quantity', p_quantity,
      'base_quantity', p_quantity,
      'uom_conversion_factor', 1.000000000000,
      'immutable_source_evidence', jsonb_build_object(
        'command_label', p_command_label,
        'authoritative_effective_at', p_effective_at,
        'document_line_order', p_line_order
      ),
      'source_evidence_fingerprint', v_fingerprint,
      'reason_code', 'FINAL_EVIDENCE_GATE'
    ))
  );

  v_event_id := (v_result->'event_ids'->>0)::uuid;

  INSERT INTO gate_order_observation
  SELECT
    p_scenario,
    p_command_label,
    p_document_id,
    p_line_id,
    p_source_occurrence_sequence,
    e.occurrence_id,
    e.scope_sequence,
    concat_ws('|',
      e.valuation_scope_id,
      to_char(e.effective_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'),
      COALESCE(e.accounting_date::text, '<null>'),
      e.occurrence_date,
      e.scope_sequence,
      e.source_occurrence_sequence,
      e.event_sequence
    ),
    e.source_evidence_fingerprint,
    e.event_effect,
    e.base_quantity
  FROM public.inventory_events e
  WHERE e.id = v_event_id;

  RETURN v_event_id;
END
$$;

SELECT pg_temp.setup_order_scenario(s)
FROM unnest(ARRAY[
  'ab', 'ba', 'same_document', 'backdated', 'partial'
]) AS s;

-- Same economic commands, same effective time, opposite database arrival order.
SELECT pg_temp.admit_order_command(
  'ab', 'A', 'quantity_increase', 10,
  '2026-07-26T10:00:00Z', gen_random_uuid(), gen_random_uuid(), 1
);
SELECT pg_temp.admit_order_command(
  'ab', 'B', 'quantity_decrease', -6,
  '2026-07-26T10:00:00Z', gen_random_uuid(), gen_random_uuid(), 1
);

SELECT pg_temp.admit_order_command(
  'ba', 'B', 'quantity_decrease', -6,
  '2026-07-26T10:00:00Z', gen_random_uuid(), gen_random_uuid(), 1
);
SELECT pg_temp.admit_order_command(
  'ba', 'A', 'quantity_increase', 10,
  '2026-07-26T10:00:00Z', gen_random_uuid(), gen_random_uuid(), 1
);

SELECT is(
  (SELECT string_agg(command_label, ',' ORDER BY scope_sequence)
   FROM gate_order_observation WHERE scenario='ab'),
  'A,B',
  'A then B assigns economic scope order A,B'
);
SELECT is(
  (SELECT string_agg(command_label, ',' ORDER BY scope_sequence)
   FROM gate_order_observation WHERE scenario='ba'),
  'B,A',
  'B then A assigns economic scope order B,A'
);
SELECT isnt(
  (SELECT string_agg(command_label, ',' ORDER BY scope_sequence)
   FROM gate_order_observation WHERE scenario='ab'),
  (SELECT string_agg(command_label, ',' ORDER BY scope_sequence)
   FROM gate_order_observation WHERE scenario='ba'),
  'equivalent command sets admitted in opposite schedules receive different economic order'
);

-- Same document: line 2 arrives before line 1.
WITH ids AS (
  SELECT gen_random_uuid() AS doc_id,
         gen_random_uuid() AS line_1_id,
         gen_random_uuid() AS line_2_id
)
SELECT pg_temp.admit_order_command(
  'same_document', 'LINE_2', 'quantity_increase', 2,
  '2026-07-26T10:00:00Z', doc_id, line_2_id, 1, 2
) FROM ids;

-- Recover the prior document id, then admit the intended first line.
SELECT pg_temp.admit_order_command(
  'same_document', 'LINE_1', 'quantity_increase', 1,
  '2026-07-26T10:00:00Z',
  (SELECT source_document_id FROM gate_order_observation
   WHERE scenario='same_document' AND command_label='LINE_2'),
  gen_random_uuid(), 1, 1
);

SELECT is(
  (SELECT string_agg(command_label, ',' ORDER BY scope_sequence)
   FROM gate_order_observation WHERE scenario='same_document'),
  'LINE_2,LINE_1',
  'scope order follows admission rather than documented source-line order'
);

-- A backdated event is sorted before an already accepted later-effective event.
SELECT pg_temp.admit_order_command(
  'backdated', 'LATER', 'quantity_increase', 1,
  '2026-07-27T10:00:00Z', gen_random_uuid(), gen_random_uuid(), 1
);
SELECT pg_temp.admit_order_command(
  'backdated', 'BACKDATED', 'quantity_increase', 1,
  '2026-07-25T10:00:00Z', gen_random_uuid(), gen_random_uuid(), 1
);

SELECT is(
  (SELECT string_agg(command_label, ',' ORDER BY
      (split_part(economic_order_tuple, '|', 2)),
      scope_sequence)
   FROM gate_order_observation WHERE scenario='backdated'),
  'BACKDATED,LATER',
  'effective time repositions a backdated event ahead of later accepted facts'
);

-- Partial occurrence 2 arrives before partial occurrence 1 at the same effective time.
WITH ids AS (
  SELECT gen_random_uuid() AS doc_id, gen_random_uuid() AS line_id
)
SELECT pg_temp.admit_order_command(
  'partial', 'PARTIAL_2', 'quantity_increase', 2,
  '2026-07-26T10:00:00Z', doc_id, line_id, 2
) FROM ids;
SELECT pg_temp.admit_order_command(
  'partial', 'PARTIAL_1', 'quantity_increase', 1,
  '2026-07-26T10:00:00Z',
  (SELECT source_document_id FROM gate_order_observation
   WHERE scenario='partial' AND command_label='PARTIAL_2'),
  (SELECT source_line_id FROM gate_order_observation
   WHERE scenario='partial' AND command_label='PARTIAL_2'),
  1
);

SELECT is(
  (SELECT string_agg(command_label, ',' ORDER BY scope_sequence)
   FROM gate_order_observation WHERE scenario='partial'),
  'PARTIAL_2,PARTIAL_1',
  'scope sequence precedes source-occurrence sequence for same-time partial occurrences'
);

-- Economic consequence classifications.
SELECT is(
  (SELECT command_label FROM gate_order_observation
   WHERE scenario='ab' ORDER BY scope_sequence LIMIT 1),
  'A',
  'future FIFO/WAC input begins with stock receipt in A-then-B schedule'
);
SELECT is(
  (SELECT command_label FROM gate_order_observation
   WHERE scenario='ba' ORDER BY scope_sequence LIMIT 1),
  'B',
  'future FIFO/WAC input begins with stock issue in B-then-A schedule'
);
SELECT ok(
  (SELECT command_label FROM gate_order_observation
   WHERE scenario='ab' ORDER BY scope_sequence LIMIT 1)
  <>
  (SELECT command_label FROM gate_order_observation
   WHERE scenario='ba' ORDER BY scope_sequence LIMIT 1),
  'FIFO eligibility and WAC negative-inventory path can differ by admission schedule'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='inventory_events'
      AND column_name IN (
        'source_line_order',
        'authoritative_tie_breaker',
        'economic_precedence_class'
      )
  ),
  'no separate authoritative source-line or economic-precedence key exists'
);

SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_events e
   JOIN gate_order_context c ON c.company_id=e.company_id),
  10,
  'all observations are actual IA-5 events, not a simulated event-store table'
);

TABLE gate_order_observation;

SELECT * FROM finish();
ROLLBACK;
