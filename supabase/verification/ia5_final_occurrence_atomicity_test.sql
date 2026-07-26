-- IA5-IA6-GATE-OCCURRENCE-001
-- Verification only. All fixtures and effects are rolled back.

\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(11);

INSERT INTO auth.users (
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data
) VALUES(
  '00000000-0000-0000-0000-000000000000',
  '1a5f3000-0000-0000-0000-000000000001',
  'authenticated','authenticated','ia5-final-atomicity@test.local','',
  now(),now(),now(),'{"provider":"email","providers":["email"]}','{}'
);

INSERT INTO public.companies(
  id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,
  email,signatory_name,signatory_position,created_by,updated_by,
  functional_currency_code,reporting_currency_code
) VALUES(
  '1a5f3000-0000-0000-0000-000000000101','corporation',
  'IA5 Final Atomicity','Software','950-300-001-00000','vat','calendar',
  '1','B','Makati','MM','1200','atomicity@test.local','Owner','President',
  '1a5f3000-0000-0000-0000-000000000001',
  '1a5f3000-0000-0000-0000-000000000001','PHP','PHP'
);
INSERT INTO public.user_company_memberships(user_id,company_id,role,granted_by)
VALUES(
  '1a5f3000-0000-0000-0000-000000000001',
  '1a5f3000-0000-0000-0000-000000000101','owner',
  '1a5f3000-0000-0000-0000-000000000001'
);
INSERT INTO public.branches(
  id,company_id,branch_code,branch_name,address_line_1,address_line_2,
  city,province,zip_code,created_by,updated_by
) VALUES(
  '1a5f3000-0000-0000-0000-000000000201',
  '1a5f3000-0000-0000-0000-000000000101','HO','Head',
  '1','B','Makati','MM','1200',
  '1a5f3000-0000-0000-0000-000000000001',
  '1a5f3000-0000-0000-0000-000000000001'
);
INSERT INTO public.item_categories(id,company_id,category_code,category_name)
VALUES(
  '1a5f3000-0000-0000-0000-000000000301',
  '1a5f3000-0000-0000-0000-000000000101','ATOM','Atomicity'
);
INSERT INTO public.units_of_measure(id,company_id,uom_code,description)
VALUES(
  '1a5f3000-0000-0000-0000-000000000401',
  '1a5f3000-0000-0000-0000-000000000101','EA','Each'
);
INSERT INTO public.warehouses(
  id,company_id,branch_id,warehouse_code,warehouse_name,created_by,updated_by
) VALUES(
  '1a5f3000-0000-0000-0000-000000000501',
  '1a5f3000-0000-0000-0000-000000000101',
  '1a5f3000-0000-0000-0000-000000000201','MAIN','Main',
  '1a5f3000-0000-0000-0000-000000000001',
  '1a5f3000-0000-0000-0000-000000000001'
);
INSERT INTO public.items(
  id,company_id,item_code,description,item_type,category_id,uom_id,
  costing_method,created_by,updated_by
) VALUES(
  '1a5f3000-0000-0000-0000-000000000601',
  '1a5f3000-0000-0000-0000-000000000101','ATOM-ITEM','Atomicity Item',
  'inventory_item','1a5f3000-0000-0000-0000-000000000301',
  '1a5f3000-0000-0000-0000-000000000401','weighted_average',
  '1a5f3000-0000-0000-0000-000000000001',
  '1a5f3000-0000-0000-0000-000000000001'
);

CREATE TEMP TABLE gate_atomicity_context AS
SELECT
  '1a5f3000-0000-0000-0000-000000000101'::uuid AS company_id,
  '1a5f3000-0000-0000-0000-000000000001'::uuid AS actor_id,
  '1a5f3000-0000-0000-0000-000000000601'::uuid AS item_id,
  '1a5f3000-0000-0000-0000-000000000501'::uuid AS warehouse_id,
  '1a5f3000-0000-0000-0000-000000000401'::uuid AS uom_id,
  (
    public.fn_ia5_create_dormant_policy_bundle(
      '1a5f3000-0000-0000-0000-000000000101',
      '1a5f3000-0000-0000-0000-000000000601',
      'warehouse',NULL,'1a5f3000-0000-0000-0000-000000000501',
      'moving_weighted_average',6::smallint,'PHP',2::smallint,
      '2026-01-01','2026-12-31',
      '1a5f3000-0000-0000-0000-000000000001'
    )->>'valuation_scope_id'
  )::uuid AS valuation_scope_id,
  gen_random_uuid() AS document_id,
  gen_random_uuid() AS line_1_id,
  gen_random_uuid() AS line_2_id;

CREATE FUNCTION pg_temp.atomicity_payload(p_line_label TEXT, p_valid BOOLEAN)
RETURNS JSONB
LANGUAGE sql
AS $$
  SELECT jsonb_build_array(jsonb_build_object(
    'event_type','atomicity_' || lower(p_line_label),
    'event_effect','quantity_increase',
    'event_sequence',1,
    'effective_at','2026-07-26T10:00:00Z',
    'accounting_date','2026-07-26',
    'item_id',item_id,
    'valuation_scope_id',valuation_scope_id,
    'physical_warehouse_id',warehouse_id,
    'source_uom_id',uom_id,
    'base_uom_id',uom_id,
    'source_quantity',CASE WHEN p_valid THEN '1.000000' ELSE '1.0000001' END,
    'base_quantity',CASE WHEN p_valid THEN '1.000000' ELSE '1.0000001' END,
    'uom_conversion_factor','1.000000000000',
    'immutable_source_evidence',jsonb_build_object('line',p_line_label),
    'source_evidence_fingerprint',
      md5(p_line_label)||md5(p_line_label||':event'),
    'reason_code','FINAL_ATOMICITY_GATE'
  ))
  FROM gate_atomicity_context
$$;

-- One document transaction: line 1 succeeds internally, line 2 then fails.
-- The PL/pgSQL exception block is a subtransaction and must roll back both.
DO $$
DECLARE
  c gate_atomicity_context%ROWTYPE;
BEGIN
  SELECT * INTO c FROM gate_atomicity_context;
  BEGIN
    PERFORM public.fn_ia5_record_dormant_inventory_occurrence(
      c.company_id,'IA5_CERTIFICATION',c.document_id,c.line_1_id,
      'ACCEPTED',1,'ia5-final-doc-line-1-0001',
      md5('line1')||md5('line1:request'),
      '2026-07-26T10:00:00Z',c.actor_id,
      pg_temp.atomicity_payload('LINE_1',true)
    );
    PERFORM public.fn_ia5_record_dormant_inventory_occurrence(
      c.company_id,'IA5_CERTIFICATION',c.document_id,c.line_2_id,
      'ACCEPTED',1,'ia5-final-doc-line-2-0001',
      md5('line2')||md5('line2:request'),
      '2026-07-26T10:00:00Z',c.actor_id,
      pg_temp.atomicity_payload('LINE_2',false)
    );
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%scale%' THEN
      RAISE;
    END IF;
  END;
END
$$;

SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_occurrences o
   JOIN gate_atomicity_context c
     ON c.company_id=o.company_id AND c.document_id=o.source_document_id),
  0,
  'a later line failure rolls back the earlier line occurrence in one SQL transaction'
);
SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_events e
   JOIN gate_atomicity_context c
     ON c.company_id=e.company_id AND c.document_id=e.source_document_id),
  0,
  'a later line failure rolls back all document events'
);

-- Retry the complete document command.
CREATE TEMP TABLE gate_document_retry_result(line_label TEXT,result JSONB);
INSERT INTO gate_document_retry_result
SELECT 'LINE_1',public.fn_ia5_record_dormant_inventory_occurrence(
  c.company_id,'IA5_CERTIFICATION',c.document_id,c.line_1_id,
  'ACCEPTED',1,'ia5-final-doc-line-1-0001',
  md5('line1')||md5('line1:request'),
  '2026-07-26T10:00:00Z',c.actor_id,
  pg_temp.atomicity_payload('LINE_1',true)
) FROM gate_atomicity_context c;
INSERT INTO gate_document_retry_result
SELECT 'LINE_2',public.fn_ia5_record_dormant_inventory_occurrence(
  c.company_id,'IA5_CERTIFICATION',c.document_id,c.line_2_id,
  'ACCEPTED',1,'ia5-final-doc-line-2-0001',
  md5('line2')||md5('line2:request'),
  '2026-07-26T10:00:00Z',c.actor_id,
  pg_temp.atomicity_payload('LINE_2',true)
) FROM gate_atomicity_context c;

SELECT is(
  (SELECT count(*)::int FROM gate_document_retry_result
   WHERE result->>'duplicate'='false'),
  2,
  'complete document retry accepts both line occurrences'
);
SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_occurrences o
   JOIN gate_atomicity_context c
     ON c.company_id=o.company_id AND c.document_id=o.source_document_id),
  2,
  'one document is represented by two independent line occurrences'
);
SELECT is(
  (SELECT count(DISTINCT atomic_occurrence_id)::int
   FROM public.inventory_occurrences o
   JOIN gate_atomicity_context c
     ON c.company_id=o.company_id AND c.document_id=o.source_document_id),
  2,
  'line occurrences have no shared atomic occurrence identity'
);
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_occurrences'
      AND column_name IN(
        'parent_occurrence_id','correlation_id','document_idempotency_key'
      )
  ),
  'no parent, correlation, or document-idempotency column currently exists'
);

-- One line can retry independently; the other line is not part of its identity.
CREATE TEMP TABLE gate_single_line_retry AS
SELECT public.fn_ia5_record_dormant_inventory_occurrence(
  c.company_id,'IA5_CERTIFICATION',c.document_id,c.line_1_id,
  'ACCEPTED',1,'ia5-final-doc-line-1-0001',
  md5('line1')||md5('line1:request'),
  '2026-07-26T10:00:00Z',c.actor_id,
  pg_temp.atomicity_payload('LINE_1',true)
) AS result
FROM gate_atomicity_context c;

SELECT is(
  (SELECT result->>'duplicate' FROM gate_single_line_retry),
  'true',
  'line-level retry is idempotent independently of document completion'
);

-- Prove event_ids[] can contradict relational membership under owner SQL.
DO $$
DECLARE
  c gate_atomicity_context%ROWTYPE;
  v_occurrence UUID := gen_random_uuid();
BEGIN
  SELECT * INTO c FROM gate_atomicity_context;
  INSERT INTO public.inventory_occurrences(
    id,atomic_occurrence_id,company_id,
    source_document_type,source_document_id,source_line_id,
    source_transition,source_occurrence_sequence,
    idempotency_key,request_fingerprint,occurrence_state,occurred_at,
    event_ids,event_count,projection_effect_count,
    posting_request_id,posting_result_id,audit_identity,created_by
  ) VALUES(
    v_occurrence,v_occurrence,c.company_id,
    'IA5_CERTIFICATION',gen_random_uuid(),gen_random_uuid(),
    'ACCEPTED',1,
    'ia5-final-false-event-array-0001',repeat('f',64),
    'accepted','2026-07-26T10:00:00Z',
    ARRAY[gen_random_uuid()],1,0,NULL,NULL,v_occurrence,c.actor_id
  );
END
$$;

SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_occurrences o
   WHERE o.company_id=(
       SELECT company_id FROM gate_atomicity_context
     )
     AND o.event_count > 0
     AND NOT EXISTS(
       SELECT 1 FROM public.inventory_events e
       WHERE e.occurrence_id=o.id
     )),
  1,
  'event_ids UUID array can claim membership without a relational event'
);

SELECT is(
  (SELECT count(*)::int
   FROM pg_constraint
   WHERE conrelid='public.inventory_occurrences'::regclass
     AND contype='f'
     AND pg_get_constraintdef(oid) ILIKE '%event_ids%'),
  0,
  'event_ids UUID array has no foreign-key enforcement'
);

SELECT is(
  (SELECT count(*)::int
   FROM pg_constraint
   WHERE conrelid='public.inventory_occurrences'::regclass
     AND conname='inventory_occurrences_dormant_posting_ck'),
  1,
  'Posting identities are deliberately forced null during dormant IA-5'
);

SELECT is(
  (SELECT count(*)::int
   FROM public.inventory_occurrences o
   JOIN gate_atomicity_context c
     ON c.company_id=o.company_id AND c.document_id=o.source_document_id
   WHERE o.posting_request_id IS NOT NULL OR o.posting_result_id IS NOT NULL),
  0,
  'current line occurrences cannot yet prove one Posting result shared by a document'
);

SELECT * FROM finish();
ROLLBACK;
