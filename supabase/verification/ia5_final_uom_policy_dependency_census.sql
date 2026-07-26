-- IA5-IA6-GATE-UOM-POLICY-001
-- Verification only. All fixtures and effects are rolled back.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(16);

INSERT INTO auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data
) VALUES(
  '00000000-0000-0000-0000-000000000000',
  '1a5f4000-0000-0000-0000-000000000001',
  'authenticated','authenticated','ia5-final-uom@test.local','',
  now(),now(),now(),'{"provider":"email","providers":["email"]}','{}'
);
INSERT INTO public.companies(
  id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,
  email,signatory_name,signatory_position,created_by,updated_by,
  functional_currency_code,reporting_currency_code
) VALUES(
  '1a5f4000-0000-0000-0000-000000000101','corporation','IA5 Final UOM',
  'Software','950-400-001-00000','vat','calendar','1','B','Makati','MM',
  '1200','uom@test.local','Owner','President',
  '1a5f4000-0000-0000-0000-000000000001',
  '1a5f4000-0000-0000-0000-000000000001','PHP','PHP'
);
INSERT INTO public.user_company_memberships(user_id,company_id,role,granted_by)
VALUES(
  '1a5f4000-0000-0000-0000-000000000001',
  '1a5f4000-0000-0000-0000-000000000101','owner',
  '1a5f4000-0000-0000-0000-000000000001'
);
INSERT INTO public.branches(
  id,company_id,branch_code,branch_name,address_line_1,address_line_2,
  city,province,zip_code,created_by,updated_by
) VALUES(
  '1a5f4000-0000-0000-0000-000000000201',
  '1a5f4000-0000-0000-0000-000000000101','HO','Head',
  '1','B','Makati','MM','1200',
  '1a5f4000-0000-0000-0000-000000000001',
  '1a5f4000-0000-0000-0000-000000000001'
);
INSERT INTO public.item_categories(id,company_id,category_code,category_name)
VALUES(
  '1a5f4000-0000-0000-0000-000000000301',
  '1a5f4000-0000-0000-0000-000000000101','UOM','UOM'
);
INSERT INTO public.units_of_measure(id,company_id,uom_code,description)
VALUES
  ('1a5f4000-0000-0000-0000-000000000401',
   '1a5f4000-0000-0000-0000-000000000101','EA','Each'),
  ('1a5f4000-0000-0000-0000-000000000402',
   '1a5f4000-0000-0000-0000-000000000101','ALT','Unattached alternate');
INSERT INTO public.warehouses(
  id,company_id,branch_id,warehouse_code,warehouse_name,created_by,updated_by
) VALUES(
  '1a5f4000-0000-0000-0000-000000000501',
  '1a5f4000-0000-0000-0000-000000000101',
  '1a5f4000-0000-0000-0000-000000000201','MAIN','Main',
  '1a5f4000-0000-0000-0000-000000000001',
  '1a5f4000-0000-0000-0000-000000000001'
);
INSERT INTO public.items(
  id,company_id,item_code,description,item_type,category_id,uom_id,
  costing_method,created_by,updated_by
) VALUES(
  '1a5f4000-0000-0000-0000-000000000601',
  '1a5f4000-0000-0000-0000-000000000101','UOM-ITEM','UOM Item',
  'inventory_item','1a5f4000-0000-0000-0000-000000000301',
  '1a5f4000-0000-0000-0000-000000000401','weighted_average',
  '1a5f4000-0000-0000-0000-000000000001',
  '1a5f4000-0000-0000-0000-000000000001'
);

CREATE TEMP TABLE gate_uom_context AS
SELECT
  '1a5f4000-0000-0000-0000-000000000101'::uuid company_id,
  '1a5f4000-0000-0000-0000-000000000001'::uuid actor_id,
  '1a5f4000-0000-0000-0000-000000000601'::uuid item_id,
  '1a5f4000-0000-0000-0000-000000000501'::uuid warehouse_id,
  '1a5f4000-0000-0000-0000-000000000401'::uuid base_uom_id,
  '1a5f4000-0000-0000-0000-000000000402'::uuid unattached_uom_id,
  (
    public.fn_ia5_create_dormant_policy_bundle(
      '1a5f4000-0000-0000-0000-000000000101',
      '1a5f4000-0000-0000-0000-000000000601',
      'warehouse',NULL,'1a5f4000-0000-0000-0000-000000000501',
      'moving_weighted_average',6::smallint,'PHP',2::smallint,
      '2026-01-01',NULL,
      '1a5f4000-0000-0000-0000-000000000001'
    )->>'valuation_scope_id'
  )::uuid valuation_scope_id;

SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='units_of_measure'
      AND column_name IN('quantity_scale','precision_scale','indivisible_unit')
  ),
  'UOM master has no item/UOM precision or indivisible-unit authority'
);
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='item_uom_conversions'
      AND column_name IN(
        'quantity_scale','precision_scale','residual_policy','version_no',
        'effective_from','effective_to'
      )
  ),
  'item UOM conversion has no precision, residual, or version identity'
);
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_events'
      AND column_name IN(
        'item_uom_conversion_id','uom_conversion_version_id',
        'quantity_residual','indivisible_residual'
      )
  ),
  'IA-5 event has no governed conversion FK or indivisible residual'
);
SELECT like(
  (SELECT prosrc FROM pg_proc
   WHERE oid='public.fn_ia5_record_dormant_inventory_occurrence(
     uuid,text,uuid,uuid,text,bigint,text,text,timestamptz,uuid,jsonb
   )'::regprocedure),
  '%v_conversion_factor := (v_event->>''uom_conversion_factor'')::numeric%',
  'admission reads the conversion factor from caller payload'
);

CREATE TEMP TABLE gate_uom_admission AS
SELECT public.fn_ia5_record_dormant_inventory_occurrence(
  company_id,'IA5_CERTIFICATION',gen_random_uuid(),gen_random_uuid(),
  'ACCEPTED',1,'ia5-final-uom-unattached-0001',
  md5('uom')||md5('uom:request'),
  '2026-07-26T10:00:00Z',actor_id,
  jsonb_build_array(jsonb_build_object(
    'event_type','uom_unattached_receipt',
    'event_effect','quantity_increase',
    'event_sequence',1,
    'effective_at','2026-07-26T10:00:00Z',
    'accounting_date','2026-07-26',
    'item_id',item_id,
    'valuation_scope_id',valuation_scope_id,
    'physical_warehouse_id',warehouse_id,
    'source_uom_id',unattached_uom_id,
    'base_uom_id',base_uom_id,
    'source_quantity','1.000000',
    'base_quantity','0.333333',
    'uom_conversion_factor','0.333333333333',
    'immutable_source_evidence',jsonb_build_object(
      'claimed_conversion','one third',
      'mathematical_result','0.333333333333'
    ),
    'source_evidence_fingerprint',repeat('c',64),
    'reason_code','FINAL_UOM_GATE'
  ))
) AS result
FROM gate_uom_context;

SELECT is(
  (SELECT result->>'occurrence_state' FROM gate_uom_admission),
  'accepted',
  'same-company UOM not governed for the item is accepted'
);
SELECT is(
  (SELECT base_quantity::text
   FROM public.inventory_events
   WHERE company_id=(SELECT company_id FROM gate_uom_context)),
  '0.333333',
  'admission stores the rounded six-decimal base quantity'
);
SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_events e
   JOIN gate_uom_context c ON c.company_id=e.company_id
   LEFT JOIN public.item_uom_conversions u
     ON u.company_id=e.company_id
    AND u.item_id=e.item_id
    AND u.uom_id=e.source_uom_id
   WHERE u.id IS NULL),
  1,
  'accepted event has no governed item-UOM conversion row'
);
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_events'
      AND column_name LIKE '%residual%'
  ),
  'the discarded conversion remainder has no event column'
);

SELECT throws_ok(
  $$UPDATE public.inventory_precision_policies
       SET effective_to='2026-06-30'
     WHERE company_id='1a5f4000-0000-0000-0000-000000000101'$$,
  '23514',
  NULL,
  'an open-ended policy cannot be closed in place'
);
SELECT throws_ok(
  $$INSERT INTO public.inventory_precision_policies(
      company_id,policy_code,version_no,quantity_scale,
      transaction_currency_code,transaction_currency_scale,
      functional_currency_code,functional_currency_scale,gl_basis_scale,
      effective_from,effective_to,created_by
    ) VALUES(
      '1a5f4000-0000-0000-0000-000000000101',
      'IA5_PRECISION_SUCCESSOR',2,6,'PHP',2,'PHP',2,2,
      '2027-01-01',NULL,
      '1a5f4000-0000-0000-0000-000000000001'
    )$$,
  NULL,
  'a successor to an immutable open-ended precision policy overlaps and rejects'
);
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name IN(
        'inventory_precision_policies','inventory_accounting_profiles',
        'inventory_cost_formula_policies','inventory_valuation_scopes'
      )
      AND column_name IN(
        'superseded_by_id','closed_by_transition_id','resolution_precedence'
      )
  ),
  'no append-only policy/scope supersession authority currently exists'
);

-- H-07/M-01: prove the current tables are structural placeholders, not closed
-- allocation or replay authorities.
CREATE TEMP TABLE gate_value_id(id UUID PRIMARY KEY);
WITH inserted AS (
INSERT INTO public.inventory_event_values(
  company_id,inventory_event_id,value_role,
  transaction_currency_code,functional_currency_code,
  transaction_currency_scale,functional_currency_scale,
  valuation_amount_scale,unit_rate_scale,
  authoritative_transaction_amount,authoritative_functional_amount,
  gl_basis_amount,derived_unit_rate,exchange_rate_identity,residual_units,
  calculation_evidence,created_by
)
SELECT
  c.company_id,e.id,'inventory_value',
  'PHP','PHP',2,2,8,12,
  100.00000000,100.00000000,100.00000000,300.000003000000,
  NULL,0,jsonb_build_object('gate','allocation'),
  c.actor_id
FROM gate_uom_context c
JOIN public.inventory_events e ON e.company_id=c.company_id
RETURNING id
)
INSERT INTO gate_value_id SELECT id FROM inserted;

INSERT INTO public.inventory_event_allocations(
  company_id,inventory_event_value_id,allocation_sequence,allocation_key,
  authoritative_valuation_amount,gl_basis_amount,
  residual_rank,residual_units,is_final_allocation,
  allocation_evidence,created_by
)
SELECT c.company_id,v.id,x.seq,x.allocation_key,
       60.00000000,60.00000000,x.seq,0,true,
       jsonb_build_object('gate','deliberate over-allocation'),c.actor_id
FROM gate_uom_context c
CROSS JOIN gate_value_id v
CROSS JOIN (
  VALUES(1,'DESTINATION_A'),(2,'DESTINATION_B')
) AS x(seq,allocation_key);

SELECT is(
  (SELECT concat_ws('/',
      v.authoritative_functional_amount::text,
      sum(a.authoritative_valuation_amount)::text)
   FROM public.inventory_event_values v
   JOIN public.inventory_event_allocations a
     ON a.inventory_event_value_id=v.id
   JOIN gate_value_id g ON g.id=v.id
   GROUP BY v.authoritative_functional_amount),
  '100.00000000/120.00000000',
  'allocation rows can exceed their authoritative parent amount'
);
SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_event_allocations a
   JOIN gate_value_id g ON g.id=a.inventory_event_value_id
   WHERE a.is_final_allocation),
  2,
  'multiple allocations may simultaneously claim final allocation'
);
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='inventory_event_allocations'
      AND column_name IN(
        'allocated_quantity','destination_type','destination_id',
        'parent_allocation_id'
      )
  ),
  'allocation structure has no quantity or relational destination authority'
);
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='inventory_projection_versions'
      AND column_name IN(
        'replay_version_id','predecessor_projection_version_id',
        'algorithm_version','first_event_sequence','last_event_sequence',
        'became_current_at'
      )
  ),
  'projection version lacks replay lineage, algorithm, and exact event boundary'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.prosrc ~* '\\minsert\\s+into\\s+(public\\.)?inventory_projection_versions\\M'),
  0,
  'no projection-version writer or rebuild authority exists'
);

CREATE TEMP TABLE gate_ia6_dependency_matrix(
  ia6_object TEXT,
  ia5_authority_consumed TEXT,
  current_authority_sufficient BOOLEAN,
  required_correction TEXT,
  before_table_creation BOOLEAN,
  before_data_admission BOOLEAN,
  before_certification BOOLEAN
);
INSERT INTO gate_ia6_dependency_matrix VALUES
  ('FIFO layer identity','event/scope/policy FK',true,
   'tenant-safe immutable FK identity; policy resolution before admission',
   false,true,true),
  ('FIFO layer quantity','event base_quantity/UOM evidence',false,
   'item/UOM scale, governed conversion version, indivisible residual',
   false,true,true),
  ('WAC pool identity','valuation scope and formula policy',false,
   'append-only policy/scope succession and exact active resolver',
   false,true,true),
  ('WAC pool quantity/history','ordered event base_quantity',false,
   'governed UOM quantity plus approved economic order',
   false,true,true),
  ('Specific-ID value state','event/item/scope plus identity authority',false,
   'physical identity registry and tenant-safe ancestry',
   false,true,true),
  ('Replay run/version','event order, policy, precision and watermark',false,
   'approved order, policy lifecycle, algorithm version and exact boundary',
   false,true,true),
  ('Dormant empty method-state table','stable UUID identity only',true,
   'must prohibit data admission until all dependent authority gates pass',
   false,false,true);

TABLE gate_ia6_dependency_matrix;

SELECT * FROM finish();
ROLLBACK;
