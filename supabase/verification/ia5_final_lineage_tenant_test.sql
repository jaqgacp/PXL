-- IA5-IA6-GATE-LINEAGE-001
-- Verification only. All fixtures and effects are rolled back.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);

INSERT INTO auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data
) VALUES(
  '00000000-0000-0000-0000-000000000000',
  '1a5f5000-0000-0000-0000-000000000001',
  'authenticated','authenticated','ia5-final-lineage@test.local','',
  now(),now(),now(),'{"provider":"email","providers":["email"]}','{}'
);

CREATE TEMP TABLE gate_lineage_context(
  company_label TEXT PRIMARY KEY,
  company_id UUID,
  branch_id UUID,
  warehouse_id UUID,
  location_id UUID,
  item_id UUID,
  uom_id UUID,
  valuation_scope_id UUID,
  base_event_id UUID
);

CREATE FUNCTION pg_temp.setup_lineage_company(p_label TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_company UUID := gen_random_uuid();
  v_branch UUID := gen_random_uuid();
  v_category UUID := gen_random_uuid();
  v_uom UUID := gen_random_uuid();
  v_warehouse UUID := gen_random_uuid();
  v_location UUID := gen_random_uuid();
  v_item UUID := gen_random_uuid();
  v_bundle JSONB;
  v_result JSONB;
BEGIN
  INSERT INTO public.companies(
    id,entity_type,registered_name,line_of_business,tin,tax_registration,
    accounting_period,address_line_1,address_line_2,city,province,zip_code,
    email,signatory_name,signatory_position,created_by,updated_by,
    functional_currency_code,reporting_currency_code
  ) VALUES(
    v_company,'corporation','IA5 Lineage '||p_label,'Software',
    '95'||substr(md5(p_label),1,13),'vat','calendar','1','B','Makati','MM',
    '1200',p_label||'@lineage.test','Owner','President',
    '1a5f5000-0000-0000-0000-000000000001',
    '1a5f5000-0000-0000-0000-000000000001','PHP','PHP'
  );
  INSERT INTO public.user_company_memberships(user_id,company_id,role,granted_by)
  VALUES(
    '1a5f5000-0000-0000-0000-000000000001',v_company,'owner',
    '1a5f5000-0000-0000-0000-000000000001'
  );
  INSERT INTO public.branches(
    id,company_id,branch_code,branch_name,address_line_1,address_line_2,
    city,province,zip_code,created_by,updated_by
  ) VALUES(
    v_branch,v_company,'HO','Head','1','B','Makati','MM','1200',
    '1a5f5000-0000-0000-0000-000000000001',
    '1a5f5000-0000-0000-0000-000000000001'
  );
  INSERT INTO public.item_categories(id,company_id,category_code,category_name)
  VALUES(v_category,v_company,'L'||substr(md5(p_label),1,7),'Lineage');
  INSERT INTO public.units_of_measure(id,company_id,uom_code,description)
  VALUES(v_uom,v_company,'EA','Each');
  INSERT INTO public.warehouses(
    id,company_id,branch_id,warehouse_code,warehouse_name,created_by,updated_by
  ) VALUES(
    v_warehouse,v_company,v_branch,'MAIN','Main',
    '1a5f5000-0000-0000-0000-000000000001',
    '1a5f5000-0000-0000-0000-000000000001'
  );
  INSERT INTO public.locations(
    id,company_id,branch_id,location_code,location_name,location_type,created_by
  ) VALUES(v_location,v_company,v_branch,'LOC','Location','warehouse',
    '1a5f5000-0000-0000-0000-000000000001');
  INSERT INTO public.items(
    id,company_id,item_code,description,item_type,category_id,uom_id,
    costing_method,created_by,updated_by
  ) VALUES(
    v_item,v_company,'LINE-'||substr(md5(p_label),1,8),'Lineage Item',
    'inventory_item',v_category,v_uom,'weighted_average',
    '1a5f5000-0000-0000-0000-000000000001',
    '1a5f5000-0000-0000-0000-000000000001'
  );
  v_bundle := public.fn_ia5_create_dormant_policy_bundle(
    v_company,v_item,'warehouse',NULL,v_warehouse,
    'moving_weighted_average',6::smallint,'PHP',2::smallint,
    '2026-01-01','2026-12-31',
    '1a5f5000-0000-0000-0000-000000000001'
  );
  v_result := public.fn_ia5_record_dormant_inventory_occurrence(
    v_company,'IA5_CERTIFICATION',gen_random_uuid(),gen_random_uuid(),
    'ACCEPTED',1,'ia5-final-lineage-'||lower(p_label)||'-base',
    md5(p_label)||md5(p_label||':request'),
    '2026-07-26T10:00:00Z',
    '1a5f5000-0000-0000-0000-000000000001',
    jsonb_build_array(jsonb_build_object(
      'event_type','lineage_base_'||lower(p_label),
      'event_effect','quantity_increase','event_sequence',1,
      'effective_at','2026-07-26T10:00:00Z',
      'accounting_date','2026-07-26',
      'item_id',v_item,'valuation_scope_id',v_bundle->>'valuation_scope_id',
      'physical_warehouse_id',v_warehouse,'physical_location_id',v_location,
      'source_uom_id',v_uom,'base_uom_id',v_uom,
      'source_quantity','1.000000','base_quantity','1.000000',
      'uom_conversion_factor','1.000000000000',
      'lot_number','SHARED-LOT','serial_number','SHARED-SERIAL',
      'immutable_source_evidence',jsonb_build_object('company',p_label),
      'source_evidence_fingerprint',
        md5(p_label||':event')||md5(p_label||':event:2'),
      'reason_code','FINAL_LINEAGE_GATE'
    ))
  );
  INSERT INTO gate_lineage_context VALUES(
    p_label,v_company,v_branch,v_warehouse,v_location,v_item,v_uom,
    (v_bundle->>'valuation_scope_id')::uuid,
    (v_result->'event_ids'->>0)::uuid
  );
END
$$;

SELECT pg_temp.setup_lineage_company('COMPANY_A');
SELECT pg_temp.setup_lineage_company('COMPANY_B');

-- Company A event points to Company B location and predecessor.
CREATE TEMP TABLE gate_cross_tenant_result AS
SELECT public.fn_ia5_record_dormant_inventory_occurrence(
  a.company_id,'IA5_CERTIFICATION',gen_random_uuid(),gen_random_uuid(),
  'ACCEPTED',1,'ia5-final-cross-tenant-event-0001',
  repeat('a',64),'2026-07-26T10:00:00Z',
  '1a5f5000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'event_type','cross_tenant_lineage',
    'event_effect','quantity_increase','event_sequence',1,
    'effective_at','2026-07-26T10:00:00Z',
    'accounting_date','2026-07-26',
    'item_id',a.item_id,'valuation_scope_id',a.valuation_scope_id,
    'physical_warehouse_id',a.warehouse_id,
    'physical_location_id',b.location_id,
    'source_uom_id',a.uom_id,'base_uom_id',a.uom_id,
    'source_quantity','1.000000','base_quantity','1.000000',
    'uom_conversion_factor','1.000000000000',
    'predecessor_event_id',b.base_event_id,
    'lot_number','SHARED-LOT','serial_number','SHARED-SERIAL',
    'immutable_source_evidence',jsonb_build_object('cross_company',true),
    'source_evidence_fingerprint',repeat('b',64),
    'reason_code','FINAL_LINEAGE_GATE'
  ))
) AS result
FROM gate_lineage_context a
CROSS JOIN gate_lineage_context b
WHERE a.company_label='COMPANY_A' AND b.company_label='COMPANY_B';

SELECT is(
  (SELECT result->>'occurrence_state' FROM gate_cross_tenant_result),
  'accepted',
  'sanctioned dormant writer accepts cross-company location and predecessor'
);
SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_events e
   JOIN gate_lineage_context a ON a.company_id=e.company_id
   JOIN gate_lineage_context b
     ON b.location_id=e.physical_location_id
    AND b.company_id<>e.company_id
   WHERE a.company_label='COMPANY_A'),
  1,
  'physical_location_id can reference another company'
);
SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_events e
   JOIN public.inventory_events p ON p.id=e.predecessor_event_id
   WHERE e.company_id<>p.company_id),
  1,
  'predecessor event can reference another company'
);

-- Related source link also permits a cross-company event target.
INSERT INTO public.inventory_event_source_links(
  company_id,inventory_event_id,relationship_type,
  source_document_type,source_document_id,source_line_id,
  source_transition,source_occurrence_sequence,
  related_inventory_event_id,immutable_relationship_evidence,created_by
)
SELECT
  a.company_id,a.base_event_id,'predecessor',
  'IA5_CERTIFICATION',gen_random_uuid(),gen_random_uuid(),
  'ACCEPTED',1,b.base_event_id,
  jsonb_build_object('cross_company',true),
  '1a5f5000-0000-0000-0000-000000000001'
FROM gate_lineage_context a
CROSS JOIN gate_lineage_context b
WHERE a.company_label='COMPANY_A' AND b.company_label='COMPANY_B';

SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_event_source_links l
   JOIN public.inventory_events e ON e.id=l.inventory_event_id
   JOIN public.inventory_events r ON r.id=l.related_inventory_event_id
   WHERE e.company_id<>r.company_id),
  1,
  'related event source-link can point across companies'
);

SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_events'
      AND column_name IN(
        'event_schema_version','evidence_schema_version',
        'physical_identity_id','lot_identity_id','serial_identity_id'
      )
  ),
  'event schema and lot/serial physical identity are not versioned authorities'
);
SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_events
   WHERE lot_number='SHARED-LOT' AND serial_number='SHARED-SERIAL'),
  3,
  'duplicate lot/serial text is accepted without identity uniqueness'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_constraint
   WHERE conrelid='public.inventory_events'::regclass
     AND contype='f'
     AND pg_get_constraintdef(oid) ILIKE '%company_id%'),
  0,
  'event ancestry foreign keys are ID-only rather than tenant-composite'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_trigger
   WHERE tgrelid='public.inventory_events'::regclass
     AND NOT tgisinternal
     AND pg_get_triggerdef(oid) ILIKE '%physical_location%company%'),
  0,
  'no event trigger definition explicitly protects location tenancy'
);
SELECT ok(
  (SELECT prosrc NOT ILIKE '%physical_location_id%company%'
   FROM pg_proc
   WHERE oid='public.fn_ia5_guard_inventory_event_fact()'::regprocedure),
  'event consistency guard has no physical-location company check'
);

SELECT
  e.id,e.company_id,e.physical_location_id,e.predecessor_event_id,
  e.lot_number,e.serial_number,e.immutable_source_evidence
FROM public.inventory_events e
WHERE e.company_id IN(
  SELECT company_id FROM gate_lineage_context
)
ORDER BY e.company_id,e.scope_sequence;

SELECT * FROM finish();
ROLLBACK;
