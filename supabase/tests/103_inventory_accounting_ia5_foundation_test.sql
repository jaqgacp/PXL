-- =============================================================================
-- INVENTORY-IA5-001 — Dormant event/identity/precision/security foundation
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(99);

CREATE TEMP TABLE ia5_pre_counts AS
SELECT
  (SELECT count(*) FROM public.stock_balances) AS stock_rows,
  (SELECT count(*) FROM public.inventory_cost_layers) AS layer_rows,
  (SELECT count(*) FROM public.inventory_transactions) AS transaction_rows,
  (SELECT count(*) FROM public.journal_entries) AS journal_rows,
  (SELECT count(*) FROM public.sys_posting_guard_violations) AS guard_rows;

-- ---------------------------------------------------------------------------
-- A. Additive schema, constraints, and ownership
-- ---------------------------------------------------------------------------

SELECT set_eq(
  $$SELECT c.relname::text
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind = 'r'
       AND c.relname IN (
         'ref_inventory_event_source_types',
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
       )$$,
  $$VALUES
      ('ref_inventory_event_source_types'),
      ('inventory_precision_policies'),
      ('inventory_accounting_profiles'),
      ('inventory_cost_formula_policies'),
      ('inventory_valuation_scopes'),
      ('inventory_valuation_scope_sequences'),
      ('inventory_occurrences'),
      ('inventory_events'),
      ('inventory_event_source_links'),
      ('inventory_event_values'),
      ('inventory_event_allocations'),
      ('inventory_projection_versions')$$,
  'IA-5 installs exactly the planned dormant foundation tables');                     -- 1

SELECT is(
  (SELECT count(*)::int
     FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'inventory_events'
      AND column_name IN (
        'company_id','source_document_type','source_document_id','source_line_id',
        'source_transition','source_occurrence_sequence','item_id',
        'valuation_scope_id','accounting_profile_id','cost_formula_policy_id',
        'precision_policy_id','event_type','event_sequence','scope_sequence',
        'effective_at','accounting_date','source_quantity','base_quantity',
        'source_uom_id','base_uom_id','immutable_source_evidence',
        'id','created_by','created_at'
      )),
  24,
  'immutable event authority carries every mandatory IA-5 identity family');          -- 2

SELECT is(
  (SELECT string_agg(
            column_name::text || ':' || numeric_precision::text || ':' || numeric_scale::text,
            ',' ORDER BY column_name
          )
     FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_events'
      AND column_name IN ('source_quantity','base_quantity','uom_conversion_factor')),
  'base_quantity:38:6,source_quantity:38:6,uom_conversion_factor:38:12',
  'event quantity and conversion columns use the frozen fixed-point scales');         -- 3

SELECT is(
  (SELECT string_agg(
            column_name::text || ':' || numeric_precision::text || ':' || numeric_scale::text,
            ',' ORDER BY column_name
          )
     FROM information_schema.columns
    WHERE table_schema='public' AND table_name='inventory_event_values'
      AND column_name IN (
        'authoritative_transaction_amount',
        'authoritative_functional_amount',
        'gl_basis_amount',
        'derived_unit_rate'
      )),
  'authoritative_functional_amount:38:8,authoritative_transaction_amount:38:8,derived_unit_rate:38:12,gl_basis_amount:38:8',
  'authoritative amounts and derived rates use separate frozen scales');               -- 4

SELECT is(
  (SELECT count(*)::int
     FROM pg_constraint
    WHERE connamespace = 'public'::regnamespace
      AND conname IN (
        'inventory_occurrences_company_idempotency_uq',
        'inventory_occurrences_logical_source_uq',
        'inventory_events_occurrence_event_uq',
        'inventory_events_scope_sequence_uq',
        'inventory_events_logical_event_uq'
      )),
  5,
  'database constraints enforce idempotency, source occurrence, and order identity'); -- 5

SELECT is(
  (SELECT count(*)::int
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgname LIKE 'zz_%_immutable'
      AND t.tgenabled = 'A'
      AND t.tgrelid IN (
        'public.ref_inventory_event_source_types'::regclass,
        'public.inventory_precision_policies'::regclass,
        'public.inventory_accounting_profiles'::regclass,
        'public.inventory_cost_formula_policies'::regclass,
        'public.inventory_valuation_scopes'::regclass,
        'public.inventory_occurrences'::regclass,
        'public.inventory_events'::regclass,
        'public.inventory_event_source_links'::regclass,
        'public.inventory_event_values'::regclass,
        'public.inventory_event_allocations'::regclass,
        'public.inventory_projection_versions'::regclass
      )),
  11,
  'all eleven append-only IA-5 fact/version tables have ALWAYS immutability guards'); -- 6

SELECT is(
  (SELECT count(*)::int
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgname LIKE 'aa_inventory_%_guard'
      AND t.tgrelid IN (
        'public.inventory_precision_policies'::regclass,
        'public.inventory_accounting_profiles'::regclass,
        'public.inventory_cost_formula_policies'::regclass,
        'public.inventory_valuation_scopes'::regclass,
        'public.inventory_events'::regclass,
        'public.inventory_event_source_links'::regclass,
        'public.inventory_event_values'::regclass,
        'public.inventory_event_allocations'::regclass
      )),
  8,
  'policy, scope, event, link, value, and allocation consistency guards exist');       -- 7

SELECT is(
  (SELECT count(*)::int
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgname LIKE 'trg_inventory_%_audit'
      AND t.tgfoid = 'public.fn_audit_trigger()'::regprocedure),
  19,
  'IA-5 reuses the certified audit authority for every company-scoped fact table '
  || '(10 IA-5 foundation + 6 ECC WP-1 order-policy/version + 2 ECC WP-3 '
  || 'stream/allocator + 1 ECC WP-4 order-key table)');                                -- 8

SELECT is(
  (SELECT count(*)::int
     FROM pg_class c
    WHERE c.oid IN (
      'public.ref_inventory_event_source_types'::regclass,
      'public.inventory_precision_policies'::regclass,
      'public.inventory_accounting_profiles'::regclass,
      'public.inventory_cost_formula_policies'::regclass,
      'public.inventory_valuation_scopes'::regclass,
      'public.inventory_valuation_scope_sequences'::regclass,
      'public.inventory_occurrences'::regclass,
      'public.inventory_events'::regclass,
      'public.inventory_event_source_links'::regclass,
      'public.inventory_event_values'::regclass,
      'public.inventory_event_allocations'::regclass,
      'public.inventory_projection_versions'::regclass
    ) AND c.relrowsecurity),
  12,
  'RLS is enabled on every IA-5 table');                                               -- 9

SELECT is(
  (SELECT count(*)::int
     FROM (VALUES
       ('ref_inventory_event_source_types'),
       ('inventory_precision_policies'),
       ('inventory_accounting_profiles'),
       ('inventory_cost_formula_policies'),
       ('inventory_valuation_scopes'),
       ('inventory_valuation_scope_sequences'),
       ('inventory_occurrences'),
       ('inventory_events'),
       ('inventory_event_source_links'),
       ('inventory_event_values'),
       ('inventory_event_allocations'),
       ('inventory_projection_versions')
     ) t(name)
    WHERE has_table_privilege(
      'authenticated',
      'public.' || t.name,
      'INSERT,UPDATE,DELETE'
    )),
  0,
  'authenticated has no direct IA-5 table mutation privilege');                       -- 10

SELECT is(
  (SELECT count(*)::int
     FROM pg_policies p
    WHERE p.schemaname='public'
      AND p.tablename IN (
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
      )
      AND p.cmd = 'SELECT'),
  11,
  'each company-scoped IA-5 object has one membership read policy');                   -- 11

SELECT set_eq(
  $$SELECT column_name::text
      FROM information_schema.columns
     WHERE table_schema='public' AND table_name='stock_balances'
       AND column_name IN (
         'projection_authority','projection_version_id',
         'projection_watermark_sequence','projection_fingerprint'
       )$$,
  $$VALUES ('projection_authority'),('projection_version_id'),
           ('projection_watermark_sequence'),('projection_fingerprint')$$,
  'legacy stock projection carries explicit authority/version evidence fields');      -- 12

SELECT is(
  (SELECT count(*)::int
     FROM public.stock_balances
    WHERE projection_authority <> 'legacy_active'
       OR projection_version_id IS NOT NULL
       OR projection_watermark_sequence IS NOT NULL
       OR projection_fingerprint IS NOT NULL),
  0,
  'all pre-existing stock rows are explicitly legacy-active without inferred versions'); -- 13

SELECT is(
  (SELECT count(*)::int
     FROM public.ref_inventory_event_source_types
    WHERE source_document_type='IA5_CERTIFICATION'
      AND is_certification_only
      AND NOT is_production_enabled
      AND removal_phase='IA-6'),
  1,
  'the only IA-5 source type is dormant, certification-only, and removal-bound');     -- 14

SELECT is(
  (SELECT count(*)::int FROM public.inventory_events)
  + (SELECT count(*)::int FROM public.inventory_occurrences)
  + (SELECT count(*)::int FROM public.inventory_valuation_scopes),
  0,
  'the migration creates no inferred historical event, occurrence, or scope rows');  -- 15

-- ---------------------------------------------------------------------------
-- B. Writer, caller, grant, and Kernel census
-- ---------------------------------------------------------------------------

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.fn_receive_inventory(jsonb)',
    'EXECUTE'
  ),
  'authenticated cannot execute the legacy generic receipt helper');                  -- 16

SELECT ok(
  NOT has_function_privilege(
    'anon',
    'public.fn_receive_inventory(jsonb)',
    'EXECUTE'
  ),
  'anon cannot execute the legacy generic receipt helper');                           -- 17

SELECT ok(
  NOT has_function_privilege(
    'service_role',
    'public.fn_receive_inventory(jsonb)',
    'EXECUTE'
  ),
  'service_role cannot execute the legacy generic receipt helper directly');          -- 18

SELECT ok(
  has_function_privilege(
    'postgres',
    'public.fn_receive_inventory(jsonb)',
    'EXECUTE'
  ),
  'the owner-mediated RR/Cash Purchase compatibility path remains callable');          -- 19

SELECT set_eq(
  $$SELECT p.proname::text
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public'
       AND strpos(p.prosrc, 'fn_receive_inventory(') > 0$$,
-- fn_post_credit_memo_vat_lump_impl joined on 2026-08-03: a customer return puts
-- goods back on hand, and it uses the one shared inbound path rather than a
-- second implementation of weighted-average roll-forward and layer creation.
  $$VALUES ('fn_confirm_receiving_report'),('fn_post_cash_purchase'),
           ('fn_post_opening_balance'),('fn_post_credit_memo_vat_lump_impl')$$,
  'the live function graph has exactly the four approved generic-receipt callers');   -- 20

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN (
        'fn_ensure_stock_balance',
        'fn_consume_cost_layers',
        'fn_add_cost_layer',
        'fn_update_wac'
      )
      AND (
        has_function_privilege('anon',p.oid,'EXECUTE')
        OR has_function_privilege('authenticated',p.oid,'EXECUTE')
        OR has_function_privilege('service_role',p.oid,'EXECUTE')
      )),
  0,
  'all four lower-level legacy Inventory helpers remain internal-only');               -- 21

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname LIKE 'fn_ia5_%'
      AND (
        has_function_privilege('anon',p.oid,'EXECUTE')
        OR has_function_privilege('authenticated',p.oid,'EXECUTE')
        OR has_function_privilege('service_role',p.oid,'EXECUTE')
      )),
  0,
  'no IA-5 internal service or trigger function is externally executable');           -- 22

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN (
        'fn_ia5_reject_immutable_inventory_fact',
        'fn_ia5_guard_inventory_policy_foundation',
        'fn_ia5_guard_inventory_event_fact',
        'fn_ia5_create_dormant_policy_bundle',
        'fn_ia5_record_dormant_inventory_occurrence'
      )
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=public']),
  5,
  'all five IA-5 SECURITY DEFINER functions pin search_path to public');               -- 23

SELECT set_eq(
  $$SELECT p.proname::text
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public'
       AND p.prosrc ~*
         '(insert[[:space:]]+into|update|delete[[:space:]]+from)'
         '[[:space:]]+(public[.])?'
         '(inventory_occurrences|inventory_events|inventory_event_source_links|'
         'inventory_event_values|inventory_event_allocations)'$$,
  $$VALUES ('fn_ia5_record_dormant_inventory_occurrence')$$,
  'one internal IA-5 authority writes occurrence/event facts');                       -- 24

SELECT set_eq(
  $$SELECT p.proname::text
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public'
       AND p.prosrc ~*
         '(insert[[:space:]]+into|update|delete[[:space:]]+from)'
         '[[:space:]]+(public[.])?'
         '(stock_balances|inventory_cost_layers|inventory_transactions)'$$,
-- `fn_save_cash_sale` joined this census on 2026-08-03: Cash Sale now relieves
-- stock and writes its issue transaction, which is the outbound entry point it
-- was missing. It uses the same fn_ensure_stock_balance / fn_consume_cost_layers
-- path as every other writer here — no second costing implementation exists.
  $$VALUES ('fn_add_cost_layer'),
           ('fn_consume_cost_layers'),
           ('fn_ensure_stock_balance'),
           ('fn_post_goods_issue_source_locked_impl'),
           ('fn_post_opening_balance'),
           ('fn_post_physical_count_source_locked_impl'),
           ('fn_post_sales_invoice'),
           ('fn_post_stock_adjustment_source_locked_impl'),
           ('fn_post_stock_transfer_source_locked_impl'),
           ('fn_receive_inventory'),
           ('fn_post_credit_memo_vat_lump_impl'),
           ('fn_post_delivery_receipt'),
           ('fn_reverse_opening_balance'),
           ('fn_save_cash_sale'),
           ('fn_update_wac'),
           ('fn_void_sales_invoice'),
           ('fn_void_sales_invoice_aud053_core')$$,
  'the legacy-active derived-table writer census is exactly the seventeen named functions'); -- 25

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname LIKE 'fn_ia5_%'
      AND p.prosrc ~*
        '(insert[[:space:]]+into|update|delete[[:space:]]+from)'
        '[[:space:]]+(public[.])?(journal_entries|journal_entry_lines)'),
  0,
  'no IA-5 function contains journal-table DML');                                     -- 26

SELECT set_eq(
  $$SELECT p.proname::text
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public'
       AND p.prosrc ~*
         '(insert[[:space:]]+into|update|delete[[:space:]]+from)'
         '[[:space:]]+(public[.])?(journal_entries|journal_entry_lines)'$$,
  $$VALUES ('fn_create_posted_journal_entry'),
           ('fn_reverse_posted_journal_entry'),
           ('fn_finalize_journal_entry'),
           ('fn_add_posting_line'),
           ('fn_add_posting_line_push'),
           ('fn_add_sales_invoice_posting_line')$$,
  'the six sanctioned Kernel mutators remain the complete direct ledger census');     -- 27

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce[[:space:]]+CONSTANT[[:space:]]+BOOLEAN[[:space:]]*:=[[:space:]]*true'
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the P5.2 guard remains armed');                                                     -- 28

SELECT is(
  (SELECT count(*)::int FROM public.sys_posting_guard_violations),
  (SELECT guard_rows::int FROM ia5_pre_counts),
  'schema installation produced no Kernel guard violation');                          -- 29

-- ---------------------------------------------------------------------------
-- C. Fixture and policy/precision foundation
-- ---------------------------------------------------------------------------

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES
  ('00000000-0000-0000-0000-000000000000',
   '1a500000-0000-0000-0000-000000000001',
   'authenticated','authenticated','ia5-owner-1@test.local','',
   now(),now(),now(),'{"provider":"email","providers":["email"]}','{}'),
  ('00000000-0000-0000-0000-000000000000',
   '1a500000-0000-0000-0000-000000000002',
   'authenticated','authenticated','ia5-owner-2@test.local','',
   now(),now(),now(),'{"provider":"email","providers":["email"]}','{}');

INSERT INTO public.companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by,
  functional_currency_code, reporting_currency_code
) VALUES
  ('1a500000-0000-0000-0000-000000000101','corporation',
   'IA5 Foundation One','Software','500-000-001-00000',
   'vat','calendar','1 Test','Building','Makati','Metro Manila','1200',
   'ia5-one@test.local','Owner One','President',
   '1a500000-0000-0000-0000-000000000001',
   '1a500000-0000-0000-0000-000000000001','PHP','PHP'),
  ('1a500000-0000-0000-0000-000000000102','corporation',
   'IA5 Foundation Two','Software','500-000-002-00000',
   'vat','calendar','2 Test','Building','Makati','Metro Manila','1200',
   'ia5-two@test.local','Owner Two','President',
   '1a500000-0000-0000-0000-000000000002',
   '1a500000-0000-0000-0000-000000000002','PHP','PHP');

INSERT INTO public.user_company_memberships (
  user_id, company_id, role, granted_by
) VALUES
  ('1a500000-0000-0000-0000-000000000001',
   '1a500000-0000-0000-0000-000000000101','owner',
   '1a500000-0000-0000-0000-000000000001'),
  ('1a500000-0000-0000-0000-000000000002',
   '1a500000-0000-0000-0000-000000000102','owner',
   '1a500000-0000-0000-0000-000000000002')
ON CONFLICT (user_id, company_id) DO NOTHING;

INSERT INTO public.branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES
  ('1a500000-0000-0000-0000-000000000201',
   '1a500000-0000-0000-0000-000000000101','HO','Head Office',
   '1 Test','Building','Makati','Metro Manila','1200',
   '1a500000-0000-0000-0000-000000000001',
   '1a500000-0000-0000-0000-000000000001'),
  ('1a500000-0000-0000-0000-000000000202',
   '1a500000-0000-0000-0000-000000000102','HO','Head Office',
   '2 Test','Building','Makati','Metro Manila','1200',
   '1a500000-0000-0000-0000-000000000002',
   '1a500000-0000-0000-0000-000000000002');

INSERT INTO public.item_categories (
  id, company_id, category_code, category_name
) VALUES
  ('1a500000-0000-0000-0000-000000000301',
   '1a500000-0000-0000-0000-000000000101','IA5','IA5 Items'),
  ('1a500000-0000-0000-0000-000000000302',
   '1a500000-0000-0000-0000-000000000102','IA5','IA5 Items');

INSERT INTO public.units_of_measure (
  id, company_id, uom_code, description
) VALUES
  ('1a500000-0000-0000-0000-000000000401',
   '1a500000-0000-0000-0000-000000000101','EA','Each'),
  ('1a500000-0000-0000-0000-000000000402',
   '1a500000-0000-0000-0000-000000000102','EA','Each');

INSERT INTO public.warehouses (
  id, company_id, branch_id, warehouse_code, warehouse_name,
  created_by, updated_by
) VALUES
  ('1a500000-0000-0000-0000-000000000501',
   '1a500000-0000-0000-0000-000000000101',
   '1a500000-0000-0000-0000-000000000201','MAIN','Main',
   '1a500000-0000-0000-0000-000000000001',
   '1a500000-0000-0000-0000-000000000001'),
  ('1a500000-0000-0000-0000-000000000502',
   '1a500000-0000-0000-0000-000000000102',
   '1a500000-0000-0000-0000-000000000202','MAIN','Main',
   '1a500000-0000-0000-0000-000000000002',
   '1a500000-0000-0000-0000-000000000002');

INSERT INTO public.items (
  id, company_id, item_code, description, item_type, category_id, uom_id,
  costing_method, created_by, updated_by
) VALUES
  ('1a500000-0000-0000-0000-000000000601',
   '1a500000-0000-0000-0000-000000000101','IA5-ITEM-1','IA5 Item 1',
   'inventory_item','1a500000-0000-0000-0000-000000000301',
   '1a500000-0000-0000-0000-000000000401','weighted_average',
   '1a500000-0000-0000-0000-000000000001',
   '1a500000-0000-0000-0000-000000000001'),
  ('1a500000-0000-0000-0000-000000000602',
   '1a500000-0000-0000-0000-000000000102','IA5-ITEM-2','IA5 Item 2',
   'inventory_item','1a500000-0000-0000-0000-000000000302',
   '1a500000-0000-0000-0000-000000000402','weighted_average',
   '1a500000-0000-0000-0000-000000000002',
   '1a500000-0000-0000-0000-000000000002');

CREATE TEMP TABLE ia5_bundle (
  company_id UUID PRIMARY KEY,
  bundle JSONB NOT NULL
);

INSERT INTO ia5_bundle
SELECT
  '1a500000-0000-0000-0000-000000000101',
  public.fn_ia5_create_dormant_policy_bundle(
    '1a500000-0000-0000-0000-000000000101',
    '1a500000-0000-0000-0000-000000000601',
    'warehouse',
    NULL,
    '1a500000-0000-0000-0000-000000000501',
    'moving_weighted_average',
    6::smallint,
    'USD',
    2::smallint,
    '2026-01-01',
    '2026-12-31',
    '1a500000-0000-0000-0000-000000000001'
  );

INSERT INTO ia5_bundle
SELECT
  '1a500000-0000-0000-0000-000000000102',
  public.fn_ia5_create_dormant_policy_bundle(
    '1a500000-0000-0000-0000-000000000102',
    '1a500000-0000-0000-0000-000000000602',
    'warehouse',
    NULL,
    '1a500000-0000-0000-0000-000000000502',
    'moving_weighted_average',
    6::smallint,
    'USD',
    2::smallint,
    '2026-01-01',
    '2026-12-31',
    '1a500000-0000-0000-0000-000000000002'
  );

SELECT is(
  (SELECT bundle->>'activation_state'
     FROM ia5_bundle
    WHERE company_id='1a500000-0000-0000-0000-000000000101'),
  'dormant',
  'policy bundle is explicitly dormant');                                             -- 30

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_valuation_scopes s
     JOIN public.inventory_cost_formula_policies f
       ON f.id=s.cost_formula_policy_id AND f.company_id=s.company_id
     JOIN public.inventory_accounting_profiles a
       ON a.id=s.accounting_profile_id AND a.company_id=s.company_id
     JOIN public.inventory_precision_policies p
       ON p.id=a.precision_policy_id AND p.company_id=s.company_id
    WHERE s.company_id IN (
      '1a500000-0000-0000-0000-000000000101',
      '1a500000-0000-0000-0000-000000000102'
    )),
  2,
  'scope, formula, profile, and precision identities are company-consistent');         -- 31

SELECT is(
  (SELECT scope_type || '/' ||
          CASE WHEN branch_id IS NULL THEN 'no-branch' ELSE 'branch' END || '/' ||
          CASE WHEN warehouse_id IS NULL THEN 'no-warehouse' ELSE 'warehouse' END
     FROM public.inventory_valuation_scopes
    WHERE company_id='1a500000-0000-0000-0000-000000000101'),
  'warehouse/no-branch/warehouse',
  'valuation scope is explicit rather than inferred from optional dimensions');       -- 32

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_accounting_profiles
    WHERE company_id='1a500000-0000-0000-0000-000000000101'
      AND '2026-07-01' BETWEEN effective_from AND effective_to),
  1,
  'an effective date resolves to exactly one accounting profile');                    -- 33

SELECT throws_ok(
  $$INSERT INTO public.inventory_precision_policies (
      company_id,policy_code,version_no,quantity_scale,
      transaction_currency_code,transaction_currency_scale,
      functional_currency_code,functional_currency_scale,gl_basis_scale,
      effective_from,effective_to,created_by
    ) VALUES (
      '1a500000-0000-0000-0000-000000000101','OVERLAP',99,6,
      'USD',2,'PHP',2,2,'2026-06-01','2026-06-30',
      '1a500000-0000-0000-0000-000000000001'
    )$$,
  NULL,
  'overlapping precision policy is rejected by database authority');                  -- 34

SELECT throws_ok(
  $$SELECT public.fn_ia5_create_dormant_policy_bundle(
      '1a500000-0000-0000-0000-000000000101',
      '1a500000-0000-0000-0000-000000000602',
      'warehouse',NULL,'1a500000-0000-0000-0000-000000000501',
      'moving_weighted_average',6::smallint,'USD',2::smallint,
      '2027-01-01','2027-12-31',
      '1a500000-0000-0000-0000-000000000001'
    )$$,
  NULL,
  'cross-company item policy creation is rejected');                                 -- 35

SELECT lives_ok(
  $$SELECT public.fn_ia5_quantize_exact(123.456789,6::smallint,'quantity')$$,
  'divisible fixed-point quantity is accepted exactly');                              -- 36

SELECT throws_ok(
  $$SELECT public.fn_ia5_quantize_exact(123.4567891,6::smallint,'quantity')$$,
  NULL,
  'quantity above its governed scale is rejected rather than rounded');               -- 37

SELECT is(
  public.fn_ia5_quantize_exact(0.000001,6::smallint,'quantity'),
  0.000001::numeric,
  'the maximum governed UOM quantity precision is retained');                         -- 38

SELECT is(
  public.fn_ia5_derive_unit_rate(123.45678901,3.125000),
  39.506172483200::numeric,
  'unit rate is derived to twelve decimals from authoritative amount and quantity');  -- 39

SELECT throws_ok(
  $$SELECT public.fn_ia5_derive_unit_rate(1,0)$$,
  NULL,
  'zero quantity cannot derive an authoritative rate');                               -- 40

SELECT lives_ok(
  $$SELECT public.fn_ia5_quantize_exact(
      99999999999999999999999999999999.999999,6::smallint,'maximum quantity'
    )$$,
  'maximum supported NUMERIC(38,6) value is accepted');                               -- 41

SELECT throws_ok(
  $$SELECT public.fn_ia5_quantize_exact(
      100000000000000000000000000000000.000000,6::smallint,'overflow quantity'
    )$$,
  NULL,
  'scale overflow is rejected explicitly');                                           -- 42

SELECT is(
  (SELECT transaction_currency_code || '/' || functional_currency_code ||
          '/' || activation_state
     FROM public.inventory_precision_policies
    WHERE company_id='1a500000-0000-0000-0000-000000000101'),
  'USD/PHP/dormant',
  'cross-currency precision metadata is stored without activating Currency logic');   -- 43

SELECT is(
  (SELECT count(*)::int
     FROM pg_class c
     JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public'
      AND c.relname IN (
        'inventory_fifo_layers',
        'inventory_wac_pools',
        'inventory_wac_pool_versions',
        'inventory_specific_id_values',
        'purchase_match_lines'
      )),
  0,
  'IA-5 does not start method state or purchase matching');                            -- 44

-- ---------------------------------------------------------------------------
-- D. Occurrence, event, precision, idempotency, determinism, and atomicity
-- ---------------------------------------------------------------------------

CREATE TEMP TABLE ia5_request (
  request_name TEXT PRIMARY KEY,
  payload JSONB NOT NULL
);

INSERT INTO ia5_request VALUES (
  'base',
  jsonb_build_array(jsonb_build_object(
    'valuation_scope_id',
      (SELECT bundle->>'valuation_scope_id'
         FROM ia5_bundle
        WHERE company_id='1a500000-0000-0000-0000-000000000101'),
    'event_type','foundation_receipt',
    'event_effect','quantity_increase',
    'event_sequence',1,
    'effective_at','2026-06-30T10:00:00Z',
    'accounting_date','2026-06-30',
    'item_id','1a500000-0000-0000-0000-000000000601',
    'physical_warehouse_id','1a500000-0000-0000-0000-000000000501',
    'source_uom_id','1a500000-0000-0000-0000-000000000401',
    'base_uom_id','1a500000-0000-0000-0000-000000000401',
    'source_quantity','3.125000',
    'base_quantity','3.125000',
    'uom_conversion_factor','1.000000000000',
    'immutable_source_evidence',
      jsonb_build_object('certification_case','base'),
    'source_evidence_fingerprint',repeat('b',64),
    'reason_code','IA5_CERTIFICATION',
    'value',jsonb_build_object(
      'value_role','inventory_value',
      'authoritative_transaction_amount','123.45000000',
      'authoritative_functional_amount','123.45678901',
      'gl_basis_amount','123.46000000',
      'derived_unit_rate','39.506172483200',
      'exchange_rate_identity','IA5-METADATA-ONLY',
      'residual_units',0,
      'calculation_evidence',
        jsonb_build_object('authority','IA5 fixed-point test')
    )
  ))
);

CREATE TEMP TABLE ia5_result (
  result_name TEXT PRIMARY KEY,
  result JSONB NOT NULL
);

INSERT INTO ia5_result VALUES (
  'base',
  public.fn_ia5_record_dormant_inventory_occurrence(
    '1a500000-0000-0000-0000-000000000101',
    'IA5_CERTIFICATION',
    '1a500000-0000-0000-0000-000000000701',
    '1a500000-0000-0000-0000-000000000801',
    'ACCEPTED',
    1,
    'ia5-base-idempotency-0001',
    repeat('a',64),
    '2026-06-30T10:00:00Z',
    '1a500000-0000-0000-0000-000000000001',
    (SELECT payload FROM ia5_request WHERE request_name='base')
  )
);

SELECT is(
  (SELECT (result->>'occurrence_state') || '/' || (result->>'duplicate')
     FROM ia5_result WHERE result_name='base'),
  'accepted/false',
  'first valid request is accepted as a new occurrence');                             -- 45

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_occurrences
    WHERE id=(SELECT (result->>'occurrence_id')::uuid
                FROM ia5_result WHERE result_name='base')),
  1,
  'one occurrence authority row is created');                                         -- 46

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_events
    WHERE occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                           FROM ia5_result WHERE result_name='base')),
  1,
  'one immutable event is created');                                                   -- 47

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_event_source_links l
     JOIN public.inventory_events e ON e.id=l.inventory_event_id
    WHERE e.occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                             FROM ia5_result WHERE result_name='base')
      AND l.relationship_type='primary'),
  1,
  'one exact primary source-line link is created');                                    -- 48

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_event_values v
     JOIN public.inventory_events e ON e.id=v.inventory_event_id
    WHERE e.occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                             FROM ia5_result WHERE result_name='base')),
  1,
  'one authoritative value record is created');                                       -- 49

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_event_allocations a
     JOIN public.inventory_event_values v ON v.id=a.inventory_event_value_id
     JOIN public.inventory_events e ON e.id=v.inventory_event_id
    WHERE e.occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                             FROM ia5_result WHERE result_name='base')),
  0,
  'later-phase costing allocation remains dormant');                                  -- 50

SELECT is(
  (SELECT projection_effect_count || '/' ||
          COALESCE(posting_request_id::text,'none') || '/' ||
          COALESCE(posting_result_id::text,'none')
     FROM public.inventory_occurrences
    WHERE id=(SELECT (result->>'occurrence_id')::uuid
                FROM ia5_result WHERE result_name='base')),
  '0/none/none',
  'accepted IA-5 occurrence has zero projection and Posting effects');                 -- 51

SELECT is(
  (SELECT source_document_id::text || '/' || source_line_id::text || '/' ||
          source_transition || '/' || source_occurrence_sequence
     FROM public.inventory_events
    WHERE occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                           FROM ia5_result WHERE result_name='base')),
  '1a500000-0000-0000-0000-000000000701/' ||
  '1a500000-0000-0000-0000-000000000801/ACCEPTED/1',
  'event retains exact document, line, transition, and partial occurrence identity'); -- 52

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_events e
     JOIN public.inventory_valuation_scopes s ON s.id=e.valuation_scope_id
     JOIN public.inventory_cost_formula_policies f ON f.id=e.cost_formula_policy_id
     JOIN public.inventory_accounting_profiles a ON a.id=e.accounting_profile_id
     JOIN public.inventory_precision_policies p ON p.id=e.precision_policy_id
    WHERE e.occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                             FROM ia5_result WHERE result_name='base')
      AND e.company_id=s.company_id
      AND s.cost_formula_policy_id=f.id
      AND s.accounting_profile_id=a.id
      AND a.precision_policy_id=p.id),
  1,
  'event resolves to exactly one consistent scope and policy-version chain');          -- 53

SELECT is(
  (SELECT source_quantity::text || '/' || base_quantity::text || '/' ||
          uom_conversion_factor::text
     FROM public.inventory_events
    WHERE occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                           FROM ia5_result WHERE result_name='base')),
  '3.125000/3.125000/1.000000000000',
  'authoritative source/base quantities and UOM factor remain exact');                 -- 54

SELECT is(
  (SELECT authoritative_transaction_amount::text || '/' ||
          authoritative_functional_amount::text || '/' ||
          gl_basis_amount::text || '/' || derived_unit_rate::text
     FROM public.inventory_event_values v
     JOIN public.inventory_events e ON e.id=v.inventory_event_id
    WHERE e.occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                             FROM ia5_result WHERE result_name='base')),
  '123.45000000/123.45678901/123.46000000/39.506172483200',
  'transaction, functional, GL-basis, and derived-rate facts remain distinct');        -- 55

SELECT ok(
  (SELECT count(*) >= 4
     FROM public.sys_audit_logs
    WHERE company_id='1a500000-0000-0000-0000-000000000101'
      AND record_id IN (
        SELECT (result->>'occurrence_id')::uuid
        FROM ia5_result WHERE result_name='base'
        UNION
        SELECT e.id
        FROM public.inventory_events e
        WHERE e.occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                                 FROM ia5_result WHERE result_name='base')
        UNION
        SELECT l.id
        FROM public.inventory_event_source_links l
        JOIN public.inventory_events e ON e.id=l.inventory_event_id
        WHERE e.occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                                 FROM ia5_result WHERE result_name='base')
        UNION
        SELECT v.id
        FROM public.inventory_event_values v
        JOIN public.inventory_events e ON e.id=v.inventory_event_id
        WHERE e.occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                                 FROM ia5_result WHERE result_name='base')
      )),
  'accepted occurrence, event, source link, and value use certified audit authority'); -- 56

INSERT INTO ia5_result VALUES (
  'duplicate',
  public.fn_ia5_record_dormant_inventory_occurrence(
    '1a500000-0000-0000-0000-000000000101',
    'IA5_CERTIFICATION',
    '1a500000-0000-0000-0000-000000000701',
    '1a500000-0000-0000-0000-000000000801',
    'ACCEPTED',1,'ia5-base-idempotency-0001',repeat('a',64),
    '2026-06-30T10:00:00Z',
    '1a500000-0000-0000-0000-000000000001',
    (SELECT payload FROM ia5_request WHERE request_name='base')
  )
);

SELECT is(
  (SELECT result->>'occurrence_id' FROM ia5_result WHERE result_name='duplicate'),
  (SELECT result->>'occurrence_id' FROM ia5_result WHERE result_name='base'),
  'sequential duplicate resolves to the original accepted occurrence');                -- 57

SELECT is(
  (SELECT result->>'duplicate' FROM ia5_result WHERE result_name='duplicate'),
  'true',
  'duplicate response is explicitly classified');                                     -- 58

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_events
    WHERE occurrence_id=(SELECT (result->>'occurrence_id')::uuid
                           FROM ia5_result WHERE result_name='base')),
  1,
  'sequential duplicate creates no second event');                                    -- 59

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000701',
      '1a500000-0000-0000-0000-000000000801',
      'ACCEPTED',1,'ia5-base-idempotency-0001',repeat('c',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      (SELECT payload FROM ia5_request WHERE request_name='base')
    )$$,
  NULL,
  'idempotency key reuse with changed content fails closed');                         -- 60

SELECT lives_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000701',
      '1a500000-0000-0000-0000-000000000801',
      'ACCEPTED',2,'ia5-partial-idempotency-0002',repeat('d',64),
      '2026-06-30T10:01:00Z',
      '1a500000-0000-0000-0000-000000000001',
      (SELECT payload FROM ia5_request WHERE request_name='base')
    )$$,
  'a legitimate second partial occurrence does not collide');                         -- 61

SELECT lives_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000701',
      '1a500000-0000-0000-0000-000000000802',
      'ACCEPTED',1,'ia5-line-idempotency-000001',repeat('e',64),
      '2026-06-30T10:02:00Z',
      '1a500000-0000-0000-0000-000000000001',
      (SELECT payload FROM ia5_request WHERE request_name='base')
    )$$,
  'a distinct source line has independent occurrence identity');                      -- 62

SELECT lives_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000102','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000702',
      '1a500000-0000-0000-0000-000000000802',
      'ACCEPTED',1,'ia5-base-idempotency-0001',repeat('f',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000002',
      jsonb_build_array(jsonb_build_object(
        'valuation_scope_id',
          (SELECT bundle->>'valuation_scope_id' FROM ia5_bundle
            WHERE company_id='1a500000-0000-0000-0000-000000000102'),
        'event_type','foundation_receipt',
        'event_effect','quantity_increase',
        'event_sequence',1,
        'effective_at','2026-06-30T10:00:00Z',
        'accounting_date','2026-06-30',
        'item_id','1a500000-0000-0000-0000-000000000602',
        'physical_warehouse_id','1a500000-0000-0000-0000-000000000502',
        'source_uom_id','1a500000-0000-0000-0000-000000000402',
        'base_uom_id','1a500000-0000-0000-0000-000000000402',
        'source_quantity','1.000000','base_quantity','1.000000',
        'uom_conversion_factor','1.000000000000',
        'immutable_source_evidence',jsonb_build_object('case','company2'),
        'source_evidence_fingerprint',repeat('1',64),
        'reason_code','IA5_CERTIFICATION'
      ))
    )$$,
  'the same idempotency key is isolated by company');                                 -- 63

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000703',
      '1a500000-0000-0000-0000-000000000803',
      'ACCEPTED',1,'ia5-zero-idempotency-00001',repeat('2',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      jsonb_set(
        (SELECT payload FROM ia5_request WHERE request_name='base'),
        '{0,source_quantity}','"0.000000"'::jsonb
      )
    )$$,
  NULL,
  'zero quantity is rejected for a quantity-increase event');                         -- 64

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000704',
      '1a500000-0000-0000-0000-000000000804',
      'ACCEPTED',1,'ia5-sign-idempotency-00001',repeat('3',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      jsonb_set(
        jsonb_set(
          (SELECT payload FROM ia5_request WHERE request_name='base'),
          '{0,source_quantity}','"-3.125000"'::jsonb
        ),
        '{0,base_quantity}','"-3.125000"'::jsonb
      )
    )$$,
  NULL,
  'negative quantity is rejected for an increase event');                             -- 65

SELECT lives_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000705',
      '1a500000-0000-0000-0000-000000000805',
      'ACCEPTED',1,'ia5-decrease-idempotency-01',repeat('4',64),
      '2026-06-30T10:03:00Z',
      '1a500000-0000-0000-0000-000000000001',
      jsonb_set(
        jsonb_set(
          jsonb_set(
            (SELECT payload FROM ia5_request WHERE request_name='base'),
            '{0,event_effect}','"quantity_decrease"'::jsonb
          ),
          '{0,source_quantity}','"-3.125000"'::jsonb
        ),
        '{0,base_quantity}','"-3.125000"'::jsonb
      )
    )$$,
  'negative quantity is valid only when explicitly classified as a decrease');        -- 66

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000706',
      '1a500000-0000-0000-0000-000000000806',
      'ACCEPTED',1,'ia5-scale-idempotency-0001',repeat('5',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      jsonb_set(
        (SELECT payload FROM ia5_request WHERE request_name='base'),
        '{0,source_quantity}','"3.1250001"'::jsonb
      )
    )$$,
  NULL,
  'event service rejects quantity above policy scale before storage');                 -- 67

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','PRODUCTION',
      '1a500000-0000-0000-0000-000000000707',
      '1a500000-0000-0000-0000-000000000807',
      'ACCEPTED',1,'ia5-source-idempotency-001',repeat('6',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      (SELECT payload FROM ia5_request WHERE request_name='base')
    )$$,
  NULL,
  'deferred Production source remains unavailable');                                  -- 68

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000708',NULL,
      'ACCEPTED',1,'ia5-null-line-idempotency-1',repeat('7',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      (SELECT payload FROM ia5_request WHERE request_name='base')
    )$$,
  NULL,
  'source-line identity cannot be null');                                              -- 69

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000709',
      '1a500000-0000-0000-0000-000000000809',
      'ACCEPTED',1,'ia5-actor-idempotency-0001',repeat('8',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000002',
      (SELECT payload FROM ia5_request WHERE request_name='base')
    )$$,
  NULL,
  'actor without company membership is rejected');                                    -- 70

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000710',
      '1a500000-0000-0000-0000-000000000810',
      'ACCEPTED',1,'ia5-scope-idempotency-0001',repeat('9',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      jsonb_set(
        (SELECT payload FROM ia5_request WHERE request_name='base'),
        '{0,valuation_scope_id}',
        to_jsonb((SELECT bundle->>'valuation_scope_id' FROM ia5_bundle
                   WHERE company_id='1a500000-0000-0000-0000-000000000102'))
      )
    )$$,
  NULL,
  'cross-company valuation scope is rejected');                                       -- 71

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000711',
      '1a500000-0000-0000-0000-000000000811',
      'ACCEPTED',1,'ia5-rollback-idempotency-01',repeat('0',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      jsonb_set(
        (SELECT payload FROM ia5_request WHERE request_name='base'),
        '{0,value,calculation_evidence}','null'::jsonb
      )
    )$$,
  NULL,
  'failure after occurrence/event work aborts the whole call');                        -- 72

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_occurrences
    WHERE company_id='1a500000-0000-0000-0000-000000000101'
      AND idempotency_key='ia5-rollback-idempotency-01'),
  0,
  'failed occurrence leaves no occurrence residue');                                  -- 73

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_events
    WHERE source_document_id='1a500000-0000-0000-0000-000000000711'),
  0,
  'failed occurrence leaves no event residue');                                       -- 74

SELECT lives_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000711',
      '1a500000-0000-0000-0000-000000000811',
      'ACCEPTED',1,'ia5-rollback-idempotency-01',repeat('0',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      (SELECT payload FROM ia5_request WHERE request_name='base')
    )$$,
  'same idempotency key can retry after a rolled-back failure');                       -- 75

CREATE TEMP TABLE ia5_order_one AS
SELECT string_agg(
  id::text,
  ',' ORDER BY
    valuation_scope_id,
    effective_at,
    accounting_date,
    occurrence_date,
    scope_sequence,
    source_occurrence_sequence,
    event_sequence
) AS ordered_ids
FROM public.inventory_events
WHERE company_id='1a500000-0000-0000-0000-000000000101';

CREATE TEMP TABLE ia5_order_two AS
SELECT string_agg(
  id::text,
  ',' ORDER BY
    valuation_scope_id,
    effective_at,
    accounting_date,
    occurrence_date,
    scope_sequence,
    source_occurrence_sequence,
    event_sequence
) AS ordered_ids
FROM public.inventory_events
WHERE company_id='1a500000-0000-0000-0000-000000000101';

SELECT is(
  (SELECT ordered_ids FROM ia5_order_one),
  (SELECT ordered_ids FROM ia5_order_two),
  'two replays of the accepted event set produce identical order');                   -- 76

SELECT is(
  (SELECT count(*)::int
     FROM (
       SELECT valuation_scope_id, scope_sequence
       FROM public.inventory_events
       GROUP BY valuation_scope_id, scope_sequence
       HAVING count(*) > 1
     ) d),
  0,
  'same-date events retain unique governed scope sequences');                          -- 77

SELECT ok(
  (SELECT bool_and(scope_sequence > 0)
     FROM public.inventory_events
    WHERE company_id='1a500000-0000-0000-0000-000000000101'),
  'economic tie-breaking uses governed scope sequence rather than random UUID order'); -- 78

SELECT throws_ok(
  format(
    'UPDATE public.inventory_events SET reason_code=''MUTATED'' WHERE id=%L',
    (SELECT (result->'event_ids'->>0)::uuid
       FROM ia5_result WHERE result_name='base')
  ),
  '23514',
  NULL,
  'accepted event cannot be updated in place');                                       -- 79

SET LOCAL session_replication_role = replica;
SELECT throws_ok(
  format(
    'DELETE FROM public.inventory_events WHERE id=%L',
    (SELECT (result->'event_ids'->>0)::uuid
       FROM ia5_result WHERE result_name='base')
  ),
  '23514',
  NULL,
  'ALWAYS immutability guard rejects replica-mode event deletion');                   -- 80
SET LOCAL session_replication_role = origin;

SELECT throws_ok(
  format(
    'UPDATE public.inventory_occurrences SET event_count=2 WHERE id=%L',
    (SELECT (result->>'occurrence_id')::uuid
       FROM ia5_result WHERE result_name='base')
  ),
  '23514',
  NULL,
  'accepted occurrence evidence cannot be updated');                                  -- 81

SELECT throws_ok(
  $$UPDATE public.inventory_precision_policies
       SET quantity_scale=4
     WHERE company_id='1a500000-0000-0000-0000-000000000101'$$,
  '23514',
  NULL,
  'used precision version cannot be rewritten');                                      -- 82

SELECT throws_ok(
  $$SELECT public.fn_ia5_record_dormant_inventory_occurrence(
      '1a500000-0000-0000-0000-000000000101','IA5_CERTIFICATION',
      '1a500000-0000-0000-0000-000000000701',
      '1a500000-0000-0000-0000-000000000801',
      'ACCEPTED',1,'ia5-other-key-same-source-1',repeat('c',64),
      '2026-06-30T10:00:00Z',
      '1a500000-0000-0000-0000-000000000001',
      (SELECT payload FROM ia5_request WHERE request_name='base')
    )$$,
  '23505',
  NULL,
  'logical source occurrence cannot be duplicated under a different key');            -- 83

-- ---------------------------------------------------------------------------
-- E. RLS attacks, dormancy, and current-authority compatibility
-- ---------------------------------------------------------------------------

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"1a500000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$INSERT INTO public.inventory_events DEFAULT VALUES$$,
  '42501',
  NULL,
  'authenticated cannot insert the event authority directly');                        -- 84

SELECT throws_ok(
  $$UPDATE public.inventory_events SET reason_code='ATTACK'$$,
  '42501',
  NULL,
  'authenticated cannot update event facts directly');                               -- 85

SELECT throws_ok(
  $$DELETE FROM public.inventory_events$$,
  '42501',
  NULL,
  'authenticated cannot delete event facts directly');                               -- 86

SELECT throws_ok(
  $$INSERT INTO public.inventory_projection_versions DEFAULT VALUES$$,
  '42501',
  NULL,
  'authenticated cannot write a projection version directly');                       -- 87

SELECT throws_ok(
  $$SELECT public.fn_receive_inventory('{}'::jsonb)$$,
  '42501',
  NULL,
  'authenticated direct call to legacy generic receipt is denied');                  -- 88

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_events
    WHERE company_id='1a500000-0000-0000-0000-000000000101'),
  5,
  'member can read its own dormant event evidence');                                  -- 89

SELECT is(
  (SELECT count(*)::int
     FROM public.inventory_events
    WHERE company_id='1a500000-0000-0000-0000-000000000102'),
  0,
  'member cannot read another company event');                                        -- 90

RESET ROLE;

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname NOT LIKE 'fn_ia5_%'
      AND p.prosrc ~*
        '(inventory_events|inventory_occurrences|inventory_event_values|'
        'inventory_valuation_scopes)'),
  0,
  'no pre-IA5 production function reads the dormant foundation');                     -- 91

SELECT is(
  (SELECT count(*)::int FROM public.stock_balances),
  (SELECT stock_rows::int FROM ia5_pre_counts),
  'IA-5 event tests do not change current stock balances');                            -- 92

SELECT is(
  (SELECT count(*)::int FROM public.inventory_cost_layers),
  (SELECT layer_rows::int FROM ia5_pre_counts),
  'IA-5 event tests do not change current cost layers');                               -- 93

SELECT is(
  (SELECT count(*)::int FROM public.inventory_transactions),
  (SELECT transaction_rows::int FROM ia5_pre_counts),
  'IA-5 event tests do not change the legacy movement ledger');                       -- 94

SELECT is(
  (SELECT count(*)::int FROM public.journal_entries),
  (SELECT journal_rows::int FROM ia5_pre_counts),
  'IA-5 event tests create no journal');                                               -- 95

SELECT is(
  (SELECT count(*)::int FROM public.sys_posting_guard_violations),
  (SELECT guard_rows::int FROM ia5_pre_counts),
  'IA-5 event tests create no Kernel guard violation');                               -- 96

SELECT ok(
  (SELECT strpos(p.prosrc,'fn_receive_inventory(') > 0
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_confirm_receiving_report')
  AND
  (SELECT strpos(p.prosrc,'fn_receive_inventory(') > 0
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_post_cash_purchase'),
  'existing RR and Cash Purchase owner-mediated compatibility routes remain wired');  -- 97

SELECT is(
  (SELECT count(*)::int
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid='public.fn_guard_journal_kernel_origin()'::regprocedure
      AND t.tgenabled='A'),
  2,
  'both P5.2 Kernel Totality Guard triggers remain ALWAYS enabled');                   -- 98

SELECT is(
  (SELECT count(*)::int
     FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('journal_entries','journal_entry_lines')
      AND cmd <> 'SELECT'),
  0,
  'journal tables remain SELECT-only under RLS');                                     -- 99

SELECT * FROM finish();
ROLLBACK;
