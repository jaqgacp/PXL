-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-15 — Master-Data Import / Export Foundation
--
-- Proves the reusable backend contract: registry/templates, export hash/logging,
-- preview without mutation, deterministic row-level validation, duplicate/source
-- handling, idempotent commit, rollback-safe database-error handling, company
-- isolation, hierarchy preservation, and statutory-reference governance.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(38);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000',
   '11111111-1111-1111-1111-111111111715',
   'authenticated', 'authenticated', 'mdp15-admin@test.local', '',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000',
   '11111111-1111-1111-1111-111111111716',
   'authenticated', 'authenticated', 'mdp15-other@test.local', '',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}');

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-222222222715', 'corporation',
   'MDP15 Alpha Corp', 'Wholesale', '915-000-001-00000',
   'vat', 'calendar', 'Alpha St', 'Alpha Bldg', 'Makati',
   'Metro Manila', '1200', 'mdp15-alpha@test.local',
   'Alpha Owner', 'President',
   '11111111-1111-1111-1111-111111111715', '11111111-1111-1111-1111-111111111715'),
  ('22222222-2222-2222-2222-222222222716', 'corporation',
   'MDP15 Beta Corp', 'Services', '915-000-002-00000',
   'vat', 'calendar', 'Beta St', 'Beta Bldg', 'Pasig',
   'Metro Manila', '1600', 'mdp15-beta@test.local',
   'Beta Owner', 'President',
   '11111111-1111-1111-1111-111111111716', '11111111-1111-1111-1111-111111111716');

INSERT INTO user_company_memberships (user_id, company_id, role)
VALUES
  ('11111111-1111-1111-1111-111111111715','22222222-2222-2222-2222-222222222715','admin'),
  ('11111111-1111-1111-1111-111111111716','22222222-2222-2222-2222-222222222716','admin');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-111111111715');

CREATE TEMP TABLE mdp15_results (
  result_key TEXT PRIMARY KEY,
  payload    JSONB NOT NULL
) ON COMMIT DROP;

-- ── Registry / templates / governed statutory references ─────────────────────
SELECT ok(
  EXISTS (
    SELECT 1 FROM master_data_import_registry
    WHERE master_key='branches' AND import_mode='upsert' AND scope='company'
  ),
  'registry exposes branches as an importable company-scoped master');
SELECT is(
  (SELECT import_mode FROM master_data_import_registry WHERE master_key='tax_codes'),
  'governed_elsewhere',
  'global statutory tax_codes stay governed by the existing MDP-01 path');
SELECT ok(
  (fn_master_data_import_template('chart_of_accounts') -> 'business_key_columns') ? 'account_code',
  'COA template declares account_code as the business key');
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(fn_master_data_import_template('chart_of_accounts') -> 'columns') c
    WHERE c ->> 'column_name' = 'fs_statement'
  ),
  'templates exclude generated columns so exports remain import-ready');

INSERT INTO mdp15_results
SELECT 'tax_import_validation',
       fn_validate_master_data_import(
         NULL,
         'tax_codes',
         jsonb_build_array(jsonb_build_object('code','MDP15-TAX','description','Nope','tax_type','vat','rate',12)),
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'valid' FROM mdp15_results WHERE result_key='tax_import_validation'),
  'false',
  'tax_codes generic import validation is invalid because the master is governed elsewhere');
SELECT is(
  (SELECT payload #>> '{errors,0,code}' FROM mdp15_results WHERE result_key='tax_import_validation'),
  'master_not_importable',
  'tax_codes import reports the deterministic master_not_importable error');

-- ── Preview, validation, duplicate handling ──────────────────────────────────
INSERT INTO mdp15_results
SELECT 'branch_preview',
       fn_import_master_data(
         '22222222-2222-2222-2222-222222222715',
         'branches',
         jsonb_build_array(jsonb_build_object(
           'branch_code','HO',
           'branch_name','Head Office',
           'address_line_1','Alpha St',
           'address_line_2','Alpha Bldg',
           'city','Makati',
           'province','Metro Manila',
           'zip_code','1200'
         )),
         true,
         NULL,
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'status' FROM mdp15_results WHERE result_key='branch_preview'),
  'validated',
  'preview returns validated status for a good branch payload');
SELECT is(
  (SELECT payload ->> 'valid_row_count' FROM mdp15_results WHERE result_key='branch_preview'),
  '1',
  'preview reports one valid row');
SELECT is(
  (SELECT count(*)::int FROM branches WHERE company_id='22222222-2222-2222-2222-222222222715' AND branch_code='HO'),
  0,
  'preview mode does not mutate the branch master');
SELECT is(
  (SELECT status FROM master_data_import_batches
   WHERE id=(SELECT (payload ->> 'batch_id')::uuid FROM mdp15_results WHERE result_key='branch_preview')),
  'validated',
  'preview writes a validated import batch audit record');

INSERT INTO mdp15_results
SELECT 'branch_duplicate',
       fn_validate_master_data_import(
         '22222222-2222-2222-2222-222222222715',
         'branches',
         jsonb_build_array(
           jsonb_build_object('branch_code','DUP','branch_name','Dup 1','address_line_1','A','address_line_2','B','city','Makati','province','Metro Manila','zip_code','1200'),
           jsonb_build_object('branch_code','DUP','branch_name','Dup 2','address_line_1','A','address_line_2','B','city','Makati','province','Metro Manila','zip_code','1200')
         ),
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'valid' FROM mdp15_results WHERE result_key='branch_duplicate'),
  'false',
  'duplicate source business keys invalidate the import');
SELECT ok(
  EXISTS (
    SELECT 1
    FROM jsonb_array_elements((SELECT payload -> 'rows' FROM mdp15_results WHERE result_key='branch_duplicate')) r,
         jsonb_array_elements(r -> 'errors') e
    WHERE e ->> 'code' = 'duplicate_source_key'
  ),
  'duplicate handling reports duplicate_source_key at row level');

INSERT INTO mdp15_results
SELECT 'branch_required_missing',
       fn_validate_master_data_import(
         '22222222-2222-2222-2222-222222222715',
         'branches',
         jsonb_build_array(jsonb_build_object(
           'branch_code','MISS',
           'address_line_1','A',
           'address_line_2','B',
           'city','Makati',
           'province','Metro Manila',
           'zip_code','1200'
         )),
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'valid' FROM mdp15_results WHERE result_key='branch_required_missing'),
  'false',
  'missing required insert fields invalidate the import');
SELECT ok(
  EXISTS (
    SELECT 1
    FROM jsonb_array_elements((SELECT payload -> 'rows' FROM mdp15_results WHERE result_key='branch_required_missing')) r,
         jsonb_array_elements(r -> 'errors') e
    WHERE e ->> 'code' = 'required_column_missing' AND e ->> 'column' = 'branch_name'
  ),
  'required-column validation identifies branch_name');

INSERT INTO mdp15_results
SELECT 'department_missing_ref',
       fn_validate_master_data_import(
         '22222222-2222-2222-2222-222222222715',
         'departments',
         jsonb_build_array(jsonb_build_object(
           'branch_id','99999999-9999-9999-9999-999999999999',
           'department_code','OPS',
           'department_name','Operations'
         )),
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'valid' FROM mdp15_results WHERE result_key='department_missing_ref'),
  'false',
  'missing foreign keys invalidate the import during preview');
SELECT ok(
  EXISTS (
    SELECT 1
    FROM jsonb_array_elements((SELECT payload -> 'rows' FROM mdp15_results WHERE result_key='department_missing_ref')) r,
         jsonb_array_elements(r -> 'errors') e
    WHERE e ->> 'code' = 'missing_reference' AND e ->> 'column' = 'branch_id'
  ),
  'foreign-key validation reports missing_reference for branch_id');

INSERT INTO mdp15_results
SELECT 'branch_scope_mismatch',
       fn_validate_master_data_import(
         '22222222-2222-2222-2222-222222222715',
         'branches',
         jsonb_build_array(jsonb_build_object(
           'company_id','22222222-2222-2222-2222-222222222716',
           'branch_code','BETA',
           'branch_name','Wrong Scope',
           'address_line_1','A',
           'address_line_2','B',
           'city','Makati',
           'province','Metro Manila',
           'zip_code','1200'
         )),
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload #>> '{rows,0,errors,0,code}' FROM mdp15_results WHERE result_key='branch_scope_mismatch'),
  'company_scope_mismatch',
  'company isolation rejects rows scoped to another company');

-- ── Commit, idempotency, update, audit ────────────────────────────────────────
INSERT INTO mdp15_results
SELECT 'branch_commit',
       fn_import_master_data(
         '22222222-2222-2222-2222-222222222715',
         'branches',
         jsonb_build_array(jsonb_build_object(
           'branch_code','HO',
           'branch_name','Head Office',
           'address_line_1','Alpha St',
           'address_line_2','Alpha Bldg',
           'city','Makati',
           'province','Metro Manila',
           'zip_code','1200'
         )),
         false,
         'mdp15-branch-ho',
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'status' FROM mdp15_results WHERE result_key='branch_commit'),
  'imported',
  'commit imports a valid branch payload');
SELECT is(
  (SELECT branch_name FROM branches WHERE company_id='22222222-2222-2222-2222-222222222715' AND branch_code='HO'),
  'Head Office',
  'branch row exists after commit');
SELECT is(
  (SELECT inserted_count FROM master_data_import_batches
   WHERE id=(SELECT (payload ->> 'batch_id')::uuid FROM mdp15_results WHERE result_key='branch_commit')),
  1,
  'commit batch records one inserted row');
SELECT ok(
  (SELECT record_id IS NOT NULL FROM master_data_import_rows
   WHERE batch_id=(SELECT (payload ->> 'batch_id')::uuid FROM mdp15_results WHERE result_key='branch_commit')
     AND row_number=1),
  'import row audit record stores the inserted master record id');
SELECT ok(
  EXISTS (
    SELECT 1
    FROM sys_audit_logs
    WHERE table_name='master_data_import_batches'
      AND record_id=(SELECT (payload ->> 'batch_id')::uuid FROM mdp15_results WHERE result_key='branch_commit')
  ),
  'import batch creation/update is captured in sys_audit_logs');

INSERT INTO mdp15_results
SELECT 'branch_idempotent_replay',
       fn_import_master_data(
         '22222222-2222-2222-2222-222222222715',
         'branches',
         jsonb_build_array(jsonb_build_object(
           'branch_code','HO',
           'branch_name','Head Office',
           'address_line_1','Alpha St',
           'address_line_2','Alpha Bldg',
           'city','Makati',
           'province','Metro Manila',
           'zip_code','1200'
         )),
         false,
         'mdp15-branch-ho',
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'idempotent_replay' FROM mdp15_results WHERE result_key='branch_idempotent_replay'),
  'true',
  'reusing the same idempotency key and payload returns the prior batch');
SELECT is(
  (SELECT count(*)::int FROM branches WHERE company_id='22222222-2222-2222-2222-222222222715' AND branch_code='HO'),
  1,
  'idempotent replay does not duplicate the branch');
SELECT throws_ok(
  $q$SELECT fn_import_master_data(
       '22222222-2222-2222-2222-222222222715',
       'branches',
       jsonb_build_array(jsonb_build_object(
         'branch_code','HO',
         'branch_name','Different Name',
         'address_line_1','Alpha St',
         'address_line_2','Alpha Bldg',
         'city','Makati',
         'province','Metro Manila',
         'zip_code','1200'
       )),
       false,
       'mdp15-branch-ho',
       '{}'::jsonb
     )$q$,
  '23505',
  NULL,
  'reusing an idempotency key with a different payload is rejected');

INSERT INTO mdp15_results
SELECT 'branch_update',
       fn_import_master_data(
         '22222222-2222-2222-2222-222222222715',
         'branches',
         jsonb_build_array(jsonb_build_object(
           'branch_code','HO',
           'branch_name','Head Office Updated',
           'address_line_1','Alpha St',
           'address_line_2','Alpha Bldg',
           'city','Makati',
           'province','Metro Manila',
           'zip_code','1200'
         )),
         false,
         'mdp15-branch-ho-update',
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'updated_count' FROM mdp15_results WHERE result_key='branch_update'),
  '1',
  'import updates an existing row matched by business key');
SELECT is(
  (SELECT branch_name FROM branches WHERE company_id='22222222-2222-2222-2222-222222222715' AND branch_code='HO'),
  'Head Office Updated',
  'business-key update changes the branch deterministically');

-- ── Rollback safety: DB CHECK failure returns failed batch and no partial row ─
INSERT INTO mdp15_results
SELECT 'branch_bad_check',
       fn_import_master_data(
         '22222222-2222-2222-2222-222222222715',
         'branches',
         jsonb_build_array(jsonb_build_object(
           'branch_code','BADCHK',
           'branch_name','Bad Check',
           'branch_type','not_a_type',
           'address_line_1','Alpha St',
           'address_line_2','Alpha Bldg',
           'city','Makati',
           'province','Metro Manila',
           'zip_code','1200'
         )),
         false,
         'mdp15-bad-check',
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'status' FROM mdp15_results WHERE result_key='branch_bad_check'),
  'failed',
  'commit-time database constraint failure is reported as a failed import batch');
SELECT is(
  (SELECT count(*)::int FROM branches WHERE company_id='22222222-2222-2222-2222-222222222715' AND branch_code='BADCHK'),
  0,
  'failed commit rolls back the attempted master row');

SELECT throws_ok(
  $q$SELECT fn_export_master_data(
       '22222222-2222-2222-2222-222222222716',
       'branches',
       true
     )$q$,
  '42501',
  NULL,
  'company export enforces membership isolation');

-- ── Hierarchy preservation and export completeness ───────────────────────────
INSERT INTO mdp15_results
SELECT 'coa_hierarchy',
       fn_import_master_data(
         '22222222-2222-2222-2222-222222222715',
         'chart_of_accounts',
         jsonb_build_array(
           jsonb_build_object(
             'id','33333333-3333-3333-3333-333333333716',
             'account_code','1010-01',
             'account_name','Cash in Bank - Main',
             'parent_id','33333333-3333-3333-3333-333333333715',
             'account_type','asset',
             'normal_balance','debit',
             'is_postable',true
           ),
           jsonb_build_object(
             'id','33333333-3333-3333-3333-333333333715',
             'account_code','1010',
             'account_name','Cash in Bank',
             'account_type','asset',
             'normal_balance','debit',
             'is_postable',false
           )
         ),
         false,
         'mdp15-coa-hierarchy',
         '{}'::jsonb
       );
SELECT is(
  (SELECT payload ->> 'status' FROM mdp15_results WHERE result_key='coa_hierarchy'),
  'imported',
  'hierarchical COA import succeeds even when child appears before parent');
SELECT is(
  (SELECT count(*)::int FROM chart_of_accounts WHERE company_id='22222222-2222-2222-2222-222222222715'),
  2,
  'hierarchical import inserts both COA rows');
SELECT is(
  (SELECT parent_id FROM chart_of_accounts
   WHERE id='33333333-3333-3333-3333-333333333716'),
  '33333333-3333-3333-3333-333333333715'::uuid,
  'COA parent reference is preserved');

INSERT INTO mdp15_results
SELECT 'branch_export',
       fn_export_master_data('22222222-2222-2222-2222-222222222715', 'branches', true);
SELECT is(
  (SELECT payload ->> 'row_count' FROM mdp15_results WHERE result_key='branch_export'),
  '1',
  'branch export returns the deterministic company-scoped row count');
SELECT is(
  (SELECT content_hash FROM master_data_export_logs
   WHERE id=(SELECT (payload ->> 'export_log_id')::uuid FROM mdp15_results WHERE result_key='branch_export')),
  (SELECT payload ->> 'content_sha256' FROM mdp15_results WHERE result_key='branch_export'),
  'export log stores the same SHA-256 returned to the caller');

INSERT INTO mdp15_results
SELECT 'package_export',
       fn_export_master_data_package('22222222-2222-2222-2222-222222222715', false, true);
SELECT ok(
  EXISTS (
    SELECT 1
    FROM jsonb_array_elements((SELECT payload -> 'exports' FROM mdp15_results WHERE result_key='package_export')) e
    WHERE e ->> 'master_key' = 'branches'
  ),
  'package export includes company-scoped masters in registry order');

INSERT INTO mdp15_results
SELECT 'tax_catalog_export',
       fn_export_master_data(NULL, 'tax_reference_catalog', true);
SELECT ok(
  (SELECT (payload ->> 'row_count')::int > 0 FROM mdp15_results WHERE result_key='tax_catalog_export'),
  'read-only tax reference catalog export remains available');

SELECT ok(
  EXISTS (
    SELECT 1 FROM sys_audit_logs
    WHERE table_name='branches'
      AND record_id=(SELECT id FROM branches WHERE company_id='22222222-2222-2222-2222-222222222715' AND branch_code='HO')
  ),
  'underlying master-table audit trigger captures imported branch mutation');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
