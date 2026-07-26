-- IA5-IA6-GATE-ROLLBACK-001
-- Verification only. All local fixtures and effects are rolled back.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(8);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES
  ('00000000-0000-0000-0000-000000000000',
   '1a5f2000-0000-0000-0000-000000000001',
   'authenticated','authenticated','ia5-final-rollback@test.local','',
   now(),now(),now(),'{"provider":"email","providers":["email"]}','{}'),
  ('00000000-0000-0000-0000-000000000000',
   '1a5f2000-0000-0000-0000-000000000002',
   'authenticated','authenticated','ia5-final-rollback-other@test.local','',
   now(),now(),now(),'{"provider":"email","providers":["email"]}','{}');

CREATE TEMP TABLE gate_rollback_context (
  company_id UUID,
  actor_id UUID,
  item_id UUID,
  warehouse_id UUID,
  uom_id UUID,
  foreign_uom_id UUID,
  valuation_scope_id UUID
);

DO $$
DECLARE
  v_company UUID := '1a5f2000-0000-0000-0000-000000000101';
  v_other_company UUID := '1a5f2000-0000-0000-0000-000000000102';
  v_branch UUID := '1a5f2000-0000-0000-0000-000000000201';
  v_other_branch UUID := '1a5f2000-0000-0000-0000-000000000202';
  v_category UUID := '1a5f2000-0000-0000-0000-000000000301';
  v_uom UUID := '1a5f2000-0000-0000-0000-000000000401';
  v_foreign_uom UUID := '1a5f2000-0000-0000-0000-000000000402';
  v_warehouse UUID := '1a5f2000-0000-0000-0000-000000000501';
  v_item UUID := '1a5f2000-0000-0000-0000-000000000601';
  v_bundle JSONB;
BEGIN
  INSERT INTO public.companies (
    id, entity_type, registered_name, line_of_business, tin,
    tax_registration, accounting_period,
    address_line_1, address_line_2, city, province, zip_code,
    email, signatory_name, signatory_position, created_by, updated_by,
    functional_currency_code, reporting_currency_code
  ) VALUES
    (v_company,'corporation','IA5 Final Rollback','Software',
     '950-200-001-00000','vat','calendar','1','B','Makati','MM','1200',
     'rollback@test.local','Owner','President',
     '1a5f2000-0000-0000-0000-000000000001',
     '1a5f2000-0000-0000-0000-000000000001','PHP','PHP'),
    (v_other_company,'corporation','IA5 Final Rollback Other','Software',
     '950-200-002-00000','vat','calendar','2','B','Makati','MM','1200',
     'rollback-other@test.local','Owner','President',
     '1a5f2000-0000-0000-0000-000000000002',
     '1a5f2000-0000-0000-0000-000000000002','PHP','PHP');

  INSERT INTO public.user_company_memberships(user_id,company_id,role,granted_by)
  VALUES
    ('1a5f2000-0000-0000-0000-000000000001',v_company,'owner',
     '1a5f2000-0000-0000-0000-000000000001'),
    ('1a5f2000-0000-0000-0000-000000000002',v_other_company,'owner',
     '1a5f2000-0000-0000-0000-000000000002');

  INSERT INTO public.branches(
    id,company_id,branch_code,branch_name,address_line_1,address_line_2,
    city,province,zip_code,created_by,updated_by
  ) VALUES
    (v_branch,v_company,'HO','Head','1','B','Makati','MM','1200',
     '1a5f2000-0000-0000-0000-000000000001',
     '1a5f2000-0000-0000-0000-000000000001'),
    (v_other_branch,v_other_company,'HO','Head','2','B','Makati','MM','1200',
     '1a5f2000-0000-0000-0000-000000000002',
     '1a5f2000-0000-0000-0000-000000000002');

  INSERT INTO public.item_categories(id,company_id,category_code,category_name)
  VALUES(v_category,v_company,'ROLL','Rollback');
  INSERT INTO public.units_of_measure(id,company_id,uom_code,description)
  VALUES
    (v_uom,v_company,'EA','Each'),
    (v_foreign_uom,v_other_company,'EA','Each');
  INSERT INTO public.warehouses(
    id,company_id,branch_id,warehouse_code,warehouse_name,created_by,updated_by
  ) VALUES(
    v_warehouse,v_company,v_branch,'MAIN','Main',
    '1a5f2000-0000-0000-0000-000000000001',
    '1a5f2000-0000-0000-0000-000000000001'
  );
  INSERT INTO public.items(
    id,company_id,item_code,description,item_type,category_id,uom_id,
    costing_method,created_by,updated_by
  ) VALUES(
    v_item,v_company,'ROLL-ITEM','Rollback Item','inventory_item',
    v_category,v_uom,'weighted_average',
    '1a5f2000-0000-0000-0000-000000000001',
    '1a5f2000-0000-0000-0000-000000000001'
  );

  v_bundle := public.fn_ia5_create_dormant_policy_bundle(
    v_company,v_item,'warehouse',NULL,v_warehouse,
    'moving_weighted_average',6::smallint,'PHP',2::smallint,
    '2026-01-01','2026-12-31',
    '1a5f2000-0000-0000-0000-000000000001'
  );

  INSERT INTO gate_rollback_context VALUES(
    v_company,'1a5f2000-0000-0000-0000-000000000001',
    v_item,v_warehouse,v_uom,v_foreign_uom,
    (v_bundle->>'valuation_scope_id')::uuid
  );
END
$$;

CREATE FUNCTION pg_temp.rollback_payload(p_uom UUID)
RETURNS JSONB
LANGUAGE sql
AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'event_type','rollback_receipt',
    'event_effect','quantity_increase',
    'event_sequence',1,
    'effective_at','2026-07-26T10:00:00Z',
    'accounting_date','2026-07-26',
    'item_id',item_id,
    'valuation_scope_id',valuation_scope_id,
    'physical_warehouse_id',warehouse_id,
    'source_uom_id',p_uom,
    'base_uom_id',uom_id,
    'source_quantity','1.000000',
    'base_quantity','1.000000',
    'uom_conversion_factor','1.000000000000',
    'immutable_source_evidence',jsonb_build_object('gate','rollback'),
    'source_evidence_fingerprint',repeat('e',64),
    'reason_code','FINAL_ROLLBACK_GATE'
  ))
  FROM gate_rollback_context
$$;

-- Failure occurs after occurrence insertion and scope-sequence update is attempted;
-- the event guard rejects the foreign-company source UOM.
DO $$
DECLARE
  c gate_rollback_context%ROWTYPE;
BEGIN
  SELECT * INTO c FROM gate_rollback_context;
  BEGIN
    PERFORM public.fn_ia5_record_dormant_inventory_occurrence(
      c.company_id,'IA5_CERTIFICATION',gen_random_uuid(),gen_random_uuid(),
      'ACCEPTED',1,'ia5-final-rollback-retry-0001',repeat('a',64),
      '2026-07-26T10:00:00Z',c.actor_id,
      pg_temp.rollback_payload(c.foreign_uom_id)
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%UOM/company mismatch%' THEN
      RAISE;
    END IF;
  END;
END
$$;

SELECT is(
  (SELECT count(*)::int FROM public.inventory_occurrences
   WHERE company_id=(SELECT company_id FROM gate_rollback_context)),
  0,
  'failed occurrence leaves no occurrence residue'
);
SELECT is(
  (SELECT count(*)::int FROM public.inventory_events
   WHERE company_id=(SELECT company_id FROM gate_rollback_context)),
  0,
  'failed occurrence leaves no event residue'
);
SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_valuation_scope_sequences
   WHERE valuation_scope_id=(
     SELECT valuation_scope_id FROM gate_rollback_context
   )),
  0,
  'failed occurrence leaves no scope-sequence residue'
);
SELECT is(
  (SELECT count(*)::int FROM public.sys_audit_logs
   WHERE company_id=(SELECT company_id FROM gate_rollback_context)
     AND table_name IN ('inventory_occurrences','inventory_events')),
  0,
  'failed occurrence leaves no IA-5 audit residue'
);

CREATE TEMP TABLE gate_retry_result AS
SELECT public.fn_ia5_record_dormant_inventory_occurrence(
  company_id,'IA5_CERTIFICATION',gen_random_uuid(),gen_random_uuid(),
  'ACCEPTED',1,'ia5-final-rollback-retry-0001',repeat('a',64),
  '2026-07-26T10:00:00Z',actor_id,
  pg_temp.rollback_payload(uom_id)
) AS result
FROM gate_rollback_context;

SELECT is(
  (SELECT min(scope_sequence)::bigint
   FROM public.inventory_events
   WHERE company_id=(SELECT company_id FROM gate_rollback_context)),
  1::bigint,
  'retry after rollback receives the first committed scope sequence'
);

CREATE TEMP TABLE gate_accepted_retry AS
SELECT public.fn_ia5_record_dormant_inventory_occurrence(
  c.company_id,'IA5_CERTIFICATION',
  o.source_document_id,o.source_line_id,o.source_transition,
  o.source_occurrence_sequence,o.idempotency_key,o.request_fingerprint,
  o.occurred_at,c.actor_id,pg_temp.rollback_payload(c.uom_id)
) AS result
FROM gate_rollback_context c
JOIN public.inventory_occurrences o ON o.company_id=c.company_id;

SELECT is(
  (SELECT result->>'duplicate' FROM gate_accepted_retry),
  'true',
  'retry after acceptance returns duplicate evidence'
);
SELECT is(
  (SELECT count(*)::int FROM public.inventory_events
   WHERE company_id=(SELECT company_id FROM gate_rollback_context)),
  1,
  'accepted retry does not duplicate the event'
);
SELECT is(
  (SELECT last_sequence
   FROM public.inventory_valuation_scope_sequences
   WHERE valuation_scope_id=(
     SELECT valuation_scope_id FROM gate_rollback_context
   )),
  1::bigint,
  'accepted retry does not advance the scope sequence'
);

SELECT * FROM finish();
ROLLBACK;
