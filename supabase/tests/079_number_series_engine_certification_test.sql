-- ══════════════════════════════════════════════════════════════════════════════
-- NUMBER-SERIES-ENGINE-001 — Number Series Engine certification regression
--
-- Complements test 030 (registry code consistency) and test 032 (SI/JE
-- reservation, ATP exhaustion, immutable void evidence, no-backward / no-identity
-- guards). This file locks in the remaining engine gates proven during the
-- 2026-07-23 certification:
--   * company isolation (a non-member cannot allocate);
--   * branch isolation (per-branch independent counters);
--   * inactive series cannot allocate;
--   * same-transaction rollback leaves no counter drift (gap policy);
--   * manual document numbers cannot bypass duplicate controls;
--   * the contract guard rejects configuration the continuous allocator never
--     honors (dynamic-year injection, periodic reset) — proven non-vacuous;
--   * structural concurrency guarantees (row lock + registry uniqueness) exist.
--
-- Empirical concurrency (10 concurrent clients × 20 allocations → 200 distinct,
-- contiguous, zero duplicates, counter == 200) is recorded in the certification
-- evidence; the structural assertions below guard the mechanism that makes it hold.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES
 ('00000000-0000-0000-0000-000000000000','11111111-0000-0000-0000-000000000079',
  'authenticated','authenticated','ns-owner@test.local','',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}'),
 ('00000000-0000-0000-0000-000000000000','12222222-0000-0000-0000-000000000079',
  'authenticated','authenticated','ns-outsider@test.local','',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}');

SELECT set_config('request.jwt.claims',
  json_build_object('sub','11111111-0000-0000-0000-000000000079','role','authenticated')::text, true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-0000-0000-0000-000000000079', 'corporation',
        'Number Series Cert Corp', 'Trading', '111-079-079-00000',
        'vat', 'calendar', 'U', 'B', 'Makati', 'Metro Manila', '1200',
        'ns-owner@test.local', 'Owner', 'President', auth.uid(), auth.uid());

INSERT INTO user_company_memberships (user_id, company_id, role)
VALUES ('11111111-0000-0000-0000-000000000079','22222222-0000-0000-0000-000000000079','owner')
ON CONFLICT (user_id, company_id) DO UPDATE SET role='owner';

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES
 ('33333333-0000-0000-0000-000000000079','22222222-0000-0000-0000-000000000079',
  'HO','Head Office','U','B','Makati','Metro Manila','1200',auth.uid(),auth.uid()),
 ('33333333-0000-0000-0000-000000000179','22222222-0000-0000-0000-000000000079',
  'BR2','Branch 2','U','B','Makati','Metro Manila','1200',auth.uid(),auth.uid());

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES ('aaaa0000-0000-0000-0000-000000000079','22222222-0000-0000-0000-000000000079',
        '1010','Cash in Bank','asset','debit',true,true,auth.uid(),auth.uid());

INSERT INTO bank_accounts (id, company_id, bank_name, account_number, account_name,
                           account_type, gl_account_id, created_at, updated_at)
VALUES ('bbbb0000-0000-0000-0000-000000000079','22222222-0000-0000-0000-000000000079',
        'BDO','00790079','Operating','checking','aaaa0000-0000-0000-0000-000000000079',now(),now());

-- Ordinary JE series in both branches (no ATP).
INSERT INTO number_series (company_id, branch_id, document_type_id, document_code, prefix,
                           number_length, padding, starting_number, next_number, current_sequence,
                           is_active, created_by, updated_by)
SELECT '22222222-0000-0000-0000-000000000079', br.id,
       (SELECT id FROM ref_document_types WHERE document_code='JE'), 'JE', 'JE-',
       6, 6, 1, 1, 0, true, auth.uid(), auth.uid()
FROM (VALUES ('33333333-0000-0000-0000-000000000079'::uuid),
             ('33333333-0000-0000-0000-000000000179'::uuid)) AS br(id);

-- ── 1. Company isolation: a non-member cannot allocate ────────────────────────
SELECT set_config('request.jwt.claims',
  json_build_object('sub','12222222-0000-0000-0000-000000000079','role','authenticated')::text, true);
SELECT throws_like(
  $$SELECT fn_next_document_number('22222222-0000-0000-0000-000000000079',
      '33333333-0000-0000-0000-000000000079','JE')$$,
  '%Access denied%',
  'a non-member cannot allocate another company''s number series');
SELECT set_config('request.jwt.claims',
  json_build_object('sub','11111111-0000-0000-0000-000000000079','role','authenticated')::text, true);

-- ── 2-4. Branch isolation: independent per-branch counters ────────────────────
SELECT is(
  fn_next_document_number('22222222-0000-0000-0000-000000000079','33333333-0000-0000-0000-000000000079','JE'),
  'JE-000001', 'branch 1 allocates its first number');
SELECT is(
  fn_next_document_number('22222222-0000-0000-0000-000000000079','33333333-0000-0000-0000-000000000079','JE'),
  'JE-000002', 'branch 1 advances independently');

-- ── 5. Rollback / gap policy: same-transaction rollback leaves no drift ───────
SAVEPOINT sp_rollback;
SELECT fn_next_document_number('22222222-0000-0000-0000-000000000079','33333333-0000-0000-0000-000000000179','JE');
ROLLBACK TO SAVEPOINT sp_rollback;
SELECT is(
  (SELECT current_sequence FROM number_series
   WHERE company_id='22222222-0000-0000-0000-000000000079'
     AND branch_id='33333333-0000-0000-0000-000000000179' AND document_code='JE'),
  0::BIGINT,
  'a rolled-back allocation leaves the branch counter undrifted (no gap)');

SELECT is(
  fn_next_document_number('22222222-0000-0000-0000-000000000079','33333333-0000-0000-0000-000000000179','JE'),
  'JE-000001',
  'branch 2 reuses the rolled-back number and stays independent of branch 1');

-- ── 6. Inactive series cannot allocate ────────────────────────────────────────
UPDATE number_series SET is_active=false
WHERE company_id='22222222-0000-0000-0000-000000000079'
  AND branch_id='33333333-0000-0000-0000-000000000179' AND document_code='JE';
SELECT throws_like(
  $$SELECT fn_next_document_number('22222222-0000-0000-0000-000000000079',
      '33333333-0000-0000-0000-000000000179','JE')$$,
  '%No active number series%',
  'an inactive series cannot allocate a number');

-- ── 7-8. Manual document numbers cannot bypass duplicate controls ─────────────
INSERT INTO check_vouchers (id, company_id, branch_id, cv_number, voucher_date,
                            bank_account_id, check_number, check_date, payee,
                            total_gross_amount, particulars, status, created_by, updated_by)
VALUES ('cccc0000-0000-0000-0000-000000000079','22222222-0000-0000-0000-000000000079',
        '33333333-0000-0000-0000-000000000079','CV-MANUAL-1','2026-05-10',
        'bbbb0000-0000-0000-0000-000000000079','CHK-1','2026-05-10','Payee A',
        100,'Manual number','draft',auth.uid(),auth.uid());
SELECT ok(
  EXISTS (SELECT 1 FROM cas_document_number_issuances
          WHERE company_id='22222222-0000-0000-0000-000000000079'
            AND document_code='CV' AND document_number='CV-MANUAL-1' AND status='issued'),
  'a manually-numbered document is registered as issued evidence');
SELECT throws_ok(
  $$INSERT INTO check_vouchers (id, company_id, branch_id, cv_number, voucher_date,
        bank_account_id, check_number, check_date, payee,
        total_gross_amount, particulars, status, created_by, updated_by)
     VALUES ('cccc0000-0000-0000-0000-000000000179','22222222-0000-0000-0000-000000000079',
        '33333333-0000-0000-0000-000000000079','CV-MANUAL-1','2026-05-11',
        'bbbb0000-0000-0000-0000-000000000079','CHK-2','2026-05-11','Payee B',
        200,'Duplicate manual number','draft',
        '11111111-0000-0000-0000-000000000079','11111111-0000-0000-0000-000000000079')$$,
  NULL,
  'a duplicate manual document number is rejected (uniqueness cannot be bypassed)');

-- ── 9-11. Contract guard: unsupported configuration is rejected (non-vacuous) ─
SELECT lives_ok(
  $$INSERT INTO number_series (company_id, branch_id, document_type_id, document_code, prefix,
        number_length, padding, starting_number, next_number, current_sequence, is_active,
        created_by, updated_by)
     VALUES ('22222222-0000-0000-0000-000000000079','33333333-0000-0000-0000-000000000079',
        (SELECT id FROM ref_document_types WHERE document_code='PO'),'PO','PO-',
        6,6,1,1,0,true,
        '11111111-0000-0000-0000-000000000079','11111111-0000-0000-0000-000000000079')$$,
  'a default continuous series (no dynamic year, reset=never) is accepted');
SELECT throws_like(
  $$INSERT INTO number_series (company_id, branch_id, document_type_id, document_code, prefix,
        has_dynamic_year, number_length, padding, starting_number, next_number, current_sequence,
        is_active, created_by, updated_by)
     VALUES ('22222222-0000-0000-0000-000000000079','33333333-0000-0000-0000-000000000079',
        (SELECT id FROM ref_document_types WHERE document_code='RR'),'RR','RR-',
        true,6,6,1,1,0,true,
        '11111111-0000-0000-0000-000000000079','11111111-0000-0000-0000-000000000079')$$,
  '%dynamic-year%',
  'has_dynamic_year = true is rejected (allocator never injects a dynamic year)');
SELECT throws_like(
  $$INSERT INTO number_series (company_id, branch_id, document_type_id, document_code, prefix,
        reset_frequency, number_length, padding, starting_number, next_number, current_sequence,
        is_active, created_by, updated_by)
     VALUES ('22222222-0000-0000-0000-000000000079','33333333-0000-0000-0000-000000000079',
        (SELECT id FROM ref_document_types WHERE document_code='VB'),'VB','VB-',
        'yearly',6,6,1,1,0,true,
        '11111111-0000-0000-0000-000000000079','11111111-0000-0000-0000-000000000079')$$,
  '%periodic reset%',
  'reset_frequency <> never is rejected (governed CAS numbering is continuous)');

-- ── 12-13. Direct counter manipulation is authorization/guard controlled ──────
SELECT throws_like(
  $$UPDATE number_series SET current_sequence = 0
     WHERE company_id='22222222-0000-0000-0000-000000000079'
       AND branch_id='33333333-0000-0000-0000-000000000079' AND document_code='JE'$$,
  '%cannot move backward%',
  'an issued counter cannot be rolled backward');
SELECT throws_like(
  $$UPDATE number_series SET reset_frequency = 'monthly'
     WHERE company_id='22222222-0000-0000-0000-000000000079'
       AND branch_id='33333333-0000-0000-0000-000000000079' AND document_code='JE'$$,
  '%periodic reset%',
  'an existing series cannot be reconfigured to an unsupported reset frequency');

-- ── 14. Non-member allocation of a document code without a series still denied ─
SELECT throws_like(
  $$SELECT fn_next_document_number('22222222-0000-0000-0000-000000000079',
      '33333333-0000-0000-0000-000000000079','ZZZ')$$,
  '%No active number series%',
  'a request for an unconfigured document code fails closed');

-- ── 15-17. Structural concurrency + uniqueness guarantees (permanent guard) ───
SELECT ok(
  (SELECT p.prosrc LIKE '%FOR UPDATE%'
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='fn_next_document_number'),
  'the allocator serializes concurrent callers with a FOR UPDATE row lock');
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    WHERE t.relname='cas_document_number_issuances' AND c.contype='u'
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
           FROM unnest(c.conkey) k JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k)
          = ARRAY['number_series_id','sequence_number']),
  'a UNIQUE(number_series_id, sequence_number) constraint prevents two allocations sharing a sequence');
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    WHERE t.relname='cas_document_number_issuances' AND c.contype='u'
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname::text)
           FROM unnest(c.conkey) k JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k)
          = ARRAY['branch_id','company_id','document_code','document_number']),
  'a UNIQUE(company_id, branch_id, document_code, document_number) constraint prevents duplicate issued numbers');

SELECT * FROM finish();
ROLLBACK;
