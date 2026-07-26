-- IA5-IA6-GATE-FINGERPRINT-001
-- Verification only. All fixtures and effects are rolled back.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(10);

INSERT INTO auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data
) VALUES(
  '00000000-0000-0000-0000-000000000000',
  '1a5f6000-0000-0000-0000-000000000001',
  'authenticated','authenticated','ia5-final-fingerprint@test.local','',
  now(),now(),now(),'{"provider":"email","providers":["email"]}','{}'
);
INSERT INTO public.companies(
  id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,
  email,signatory_name,signatory_position,created_by,updated_by,
  functional_currency_code,reporting_currency_code
) VALUES(
  '1a5f6000-0000-0000-0000-000000000101','corporation',
  'IA5 Final Fingerprint','Software','950-600-001-00000','vat','calendar',
  '1','B','Makati','MM','1200','fingerprint@test.local','Owner','President',
  '1a5f6000-0000-0000-0000-000000000001',
  '1a5f6000-0000-0000-0000-000000000001','PHP','PHP'
);
INSERT INTO public.user_company_memberships(user_id,company_id,role,granted_by)
VALUES(
  '1a5f6000-0000-0000-0000-000000000001',
  '1a5f6000-0000-0000-0000-000000000101','owner',
  '1a5f6000-0000-0000-0000-000000000001'
);
INSERT INTO public.branches(
  id,company_id,branch_code,branch_name,address_line_1,address_line_2,
  city,province,zip_code,created_by,updated_by
) VALUES(
  '1a5f6000-0000-0000-0000-000000000201',
  '1a5f6000-0000-0000-0000-000000000101','HO','Head',
  '1','B','Makati','MM','1200',
  '1a5f6000-0000-0000-0000-000000000001',
  '1a5f6000-0000-0000-0000-000000000001'
);
INSERT INTO public.item_categories(id,company_id,category_code,category_name)
VALUES(
  '1a5f6000-0000-0000-0000-000000000301',
  '1a5f6000-0000-0000-0000-000000000101','HASH','Fingerprint'
);
INSERT INTO public.units_of_measure(id,company_id,uom_code,description)
VALUES
  ('1a5f6000-0000-0000-0000-000000000401',
   '1a5f6000-0000-0000-0000-000000000101','EA','Each'),
  ('1a5f6000-0000-0000-0000-000000000402',
   '1a5f6000-0000-0000-0000-000000000101','BOX','Box');
INSERT INTO public.warehouses(
  id,company_id,branch_id,warehouse_code,warehouse_name,created_by,updated_by
) VALUES(
  '1a5f6000-0000-0000-0000-000000000501',
  '1a5f6000-0000-0000-0000-000000000101',
  '1a5f6000-0000-0000-0000-000000000201','MAIN','Main',
  '1a5f6000-0000-0000-0000-000000000001',
  '1a5f6000-0000-0000-0000-000000000001'
);
INSERT INTO public.items(
  id,company_id,item_code,description,item_type,category_id,uom_id,
  costing_method,created_by,updated_by
) VALUES(
  '1a5f6000-0000-0000-0000-000000000601',
  '1a5f6000-0000-0000-0000-000000000101','HASH-ITEM','Fingerprint Item',
  'inventory_item','1a5f6000-0000-0000-0000-000000000301',
  '1a5f6000-0000-0000-0000-000000000401','weighted_average',
  '1a5f6000-0000-0000-0000-000000000001',
  '1a5f6000-0000-0000-0000-000000000001'
);

CREATE TEMP TABLE gate_fingerprint_context AS
SELECT
  '1a5f6000-0000-0000-0000-000000000101'::uuid company_id,
  '1a5f6000-0000-0000-0000-000000000001'::uuid actor_id,
  '1a5f6000-0000-0000-0000-000000000601'::uuid item_id,
  '1a5f6000-0000-0000-0000-000000000501'::uuid warehouse_id,
  '1a5f6000-0000-0000-0000-000000000401'::uuid base_uom_id,
  '1a5f6000-0000-0000-0000-000000000402'::uuid alternate_uom_id,
  gen_random_uuid() document_id,
  gen_random_uuid() line_id,
  (
    public.fn_ia5_create_dormant_policy_bundle(
      '1a5f6000-0000-0000-0000-000000000101',
      '1a5f6000-0000-0000-0000-000000000601',
      'warehouse',NULL,'1a5f6000-0000-0000-0000-000000000501',
      'moving_weighted_average',6::smallint,'PHP',2::smallint,
      '2026-01-01','2026-12-31',
      '1a5f6000-0000-0000-0000-000000000001'
    )->>'valuation_scope_id'
  )::uuid valuation_scope_id;

CREATE FUNCTION pg_temp.fingerprint_payload(
  p_quantity NUMERIC,
  p_source_uom UUID,
  p_factor NUMERIC,
  p_effective_at TIMESTAMPTZ,
  p_policy_scope UUID,
  p_evidence TEXT
)
RETURNS JSONB
LANGUAGE sql
AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'event_type','fingerprint_receipt',
    'event_effect','quantity_increase','event_sequence',1,
    'effective_at',p_effective_at,'accounting_date',p_effective_at::date,
    'item_id',item_id,'valuation_scope_id',p_policy_scope,
    'physical_warehouse_id',warehouse_id,
    'source_uom_id',p_source_uom,'base_uom_id',base_uom_id,
    'source_quantity',p_quantity,
    'base_quantity',round(p_quantity*p_factor,6),
    'uom_conversion_factor',p_factor,
    'immutable_source_evidence',jsonb_build_object('material_evidence',p_evidence),
    'source_evidence_fingerprint',repeat('0',64),
    'reason_code','FINAL_FINGERPRINT_GATE'
  ))
  FROM gate_fingerprint_context
$$;

CREATE TEMP TABLE gate_fingerprint_first AS
SELECT public.fn_ia5_record_dormant_inventory_occurrence(
  c.company_id,'IA5_CERTIFICATION',c.document_id,c.line_id,
  'ACCEPTED',1,'ia5-final-fingerprint-key-0001',repeat('a',64),
  '2026-07-26T10:00:00Z',c.actor_id,
  pg_temp.fingerprint_payload(
    1,c.base_uom_id,1,'2026-07-26T10:00:00Z',
    c.valuation_scope_id,'ORIGINAL'
  )
) AS result
FROM gate_fingerprint_context c;

SELECT is(
  (SELECT result->>'duplicate' FROM gate_fingerprint_first),
  'false',
  'initial canonical-looking request is accepted'
);

-- Change quantity, UOM, factor, effective time, and evidence while preserving the
-- caller-supplied fingerprint and outer source identity.
CREATE TEMP TABLE gate_fingerprint_changed_retry AS
SELECT public.fn_ia5_record_dormant_inventory_occurrence(
  c.company_id,'IA5_CERTIFICATION',c.document_id,c.line_id,
  'ACCEPTED',1,'ia5-final-fingerprint-key-0001',repeat('a',64),
  '2026-07-26T10:00:00Z',c.actor_id,
  pg_temp.fingerprint_payload(
    999,c.alternate_uom_id,12,'2026-06-01T00:00:00Z',
    c.valuation_scope_id,'MATERIALLY CHANGED'
  )
) AS result
FROM gate_fingerprint_context c;

SELECT is(
  (SELECT result->>'duplicate' FROM gate_fingerprint_changed_retry),
  'true',
  'same supplied fingerprint returns the earlier occurrence despite changed payload'
);
SELECT is(
  (SELECT base_quantity::text
   FROM public.inventory_events
   WHERE company_id=(SELECT company_id FROM gate_fingerprint_context)),
  '1.000000',
  'changed retry is ignored and original event remains authoritative'
);
SELECT is(
  (SELECT count(*)::int FROM public.inventory_events
   WHERE company_id=(SELECT company_id FROM gate_fingerprint_context)),
  1,
  'changed retry does not duplicate the event'
);

SELECT throws_ok(
  format(
    $sql$
    SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      %L,%L,%L,%L,%L,1,%L,%L,%L,%L,
      pg_temp.fingerprint_payload(
        1,%L,1,%L,%L,%L
      )
    )
    $sql$,
    (SELECT company_id FROM gate_fingerprint_context),
    'IA5_CERTIFICATION',
    (SELECT document_id FROM gate_fingerprint_context),
    (SELECT line_id FROM gate_fingerprint_context),
    'ACCEPTED','ia5-final-fingerprint-key-0001',repeat('b',64),
    '2026-07-26T10:00:00Z',
    (SELECT actor_id FROM gate_fingerprint_context),
    (SELECT base_uom_id FROM gate_fingerprint_context),
    '2026-07-26T10:00:00Z',
    (SELECT valuation_scope_id FROM gate_fingerprint_context),
    'ORIGINAL'
  ),
  NULL,
  'changed supplied request fingerprint is rejected'
);

SELECT is(
  (SELECT source_evidence_fingerprint
   FROM public.inventory_events
   WHERE company_id=(SELECT company_id FROM gate_fingerprint_context)),
  repeat('0',64),
  'arbitrary well-formed source evidence fingerprint is stored without derivation'
);
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name IN('inventory_occurrences','inventory_events')
      AND column_name IN(
        'fingerprint_algorithm','fingerprint_version',
        'canonicalisation_version','canonical_payload'
      )
  ),
  'fingerprint algorithm and canonicalisation version are not persisted'
);
SELECT ok(
  (SELECT prosrc NOT ILIKE '%digest(%'
       AND prosrc NOT ILIKE '%sha256%'
       AND prosrc NOT ILIKE '%jsonb_strip_nulls%'
   FROM pg_proc
   WHERE oid='public.fn_ia5_record_dormant_inventory_occurrence(
     uuid,text,uuid,uuid,text,bigint,text,text,timestamptz,uuid,jsonb
   )'::regprocedure),
  'database admission does not calculate or canonicalise request fingerprint'
);
SELECT is(
  (SELECT count(*)::int
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname LIKE 'fn_ia5%'
     AND (
       p.prosrc ILIKE '%canonical%fingerprint%'
       OR p.prosrc ILIKE '%fingerprint%version%'
     )),
  0,
  'no separate IA-5 canonical fingerprint authority exists'
);
SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.fn_ia5_record_dormant_inventory_occurrence(
      uuid,text,uuid,uuid,text,bigint,text,text,timestamptz,uuid,jsonb
    )',
    'EXECUTE'
  ),
  'fingerprint trust is internal-only rather than an authenticated client boundary'
);

SELECT * FROM finish();
ROLLBACK;
