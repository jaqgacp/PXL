-- ══════════════════════════════════════════════════════════════════════════════
-- COA-ENGINE-CERT-001 — COA Engine (Phase A) certification + equivalence regression
--
-- Permanent protection for the frozen COA Engine contract
--   docs/PXL/02. Accounting Core/PXL_COA_ENGINE_SPEC.md
-- Proves, self-contained and rolled back:
--   * Resolver Contract: deterministic most-specific resolution, branch vs
--     company-default precedence, fail-closed on no/unknown/inactive key,
--     rejection of ambiguous equal-specificity matches, authorized vs
--     unauthorized transaction overrides, expected-type / postable / active
--     account validation.
--   * Equivalence: fn_resolve_account and vw_company_accounting_config return
--     exactly today's company_accounting_config (config remains the authority).
--   * Lifecycle (Contract 3): valid/invalid transitions, is_active sync,
--     zero-balance archive rule.
--   * Change policy (Contract 4): immutable-once-used identity attributes, no
--     delete with posted history.
--   * Posting control (Contract 2): leaf/postable/manual validators.
--   * FS registry (Contract 5): one active mapping per account per statement,
--     effective-dated reclassification.
--   * Canonical PXL Standard COA fixture provisioning.
--   * account_mapping is not writable by authenticated (single writable authority).
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(45);

-- ── User + claims helper ─────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0c0a0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'coacert-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

SELECT pg_temp.as_user('0c0a0000-0000-0000-0000-000000000001');

-- ── Companies A + B (creator becomes owner via trg_company_creator_owner) ────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('0c0a0000-0000-0000-0000-0000000000a1', 'corporation', 'COACert Alpha Corp',
   'Trading', '341-000-001-00000', 'vat', 'calendar',
   'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'coacert-owner@test.local', 'A Owner', 'President',
   '0c0a0000-0000-0000-0000-000000000001', '0c0a0000-0000-0000-0000-000000000001'),
  ('0c0a0000-0000-0000-0000-0000000000b1', 'corporation', 'COACert Beta Corp',
   'Trading', '341-000-002-00000', 'vat', 'calendar',
   'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'coacert-owner@test.local', 'B Owner', 'President',
   '0c0a0000-0000-0000-0000-000000000001', '0c0a0000-0000-0000-0000-000000000001');

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES
  ('0c0a0000-0000-0000-0000-0000000000c1', '0c0a0000-0000-0000-0000-0000000000a1',
   'HO', 'Head Office', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   '0c0a0000-0000-0000-0000-000000000001', '0c0a0000-0000-0000-0000-000000000001');

-- Helper: account id by code within company A
CREATE FUNCTION pg_temp.accA(p_code text)
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM chart_of_accounts
   WHERE company_id = '0c0a0000-0000-0000-0000-0000000000a1' AND account_code = p_code;
$$;

-- ════════════════════════════════════════════════════════════════════════════════
-- Canonical PXL Standard COA fixture (Contract 9)
-- ════════════════════════════════════════════════════════════════════════════════
SELECT is(
  fn_provision_pxl_standard_coa('0c0a0000-0000-0000-0000-0000000000a1',
                                '0c0a0000-0000-0000-0000-000000000001'),
  33, 'canonical PXL Standard COA provisions 33 accounts');                            -- 1

SELECT is_empty(
  $$SELECT account_code FROM chart_of_accounts
     WHERE company_id = '0c0a0000-0000-0000-0000-0000000000a1'
       AND (account_type IS NULL OR normal_balance IS NULL OR fs_group IS NULL
            OR lifecycle_status <> 'active')$$,
  'every provisioned account carries complete metadata and is active');                -- 2

SELECT is(
  (SELECT count(*)::int FROM fs_structure WHERE company_id='0c0a0000-0000-0000-0000-0000000000a1'),
  8, 'FS structure has 8 statement lines');                                            -- 3

SELECT is(
  (SELECT count(*)::int FROM account_fs_map WHERE company_id='0c0a0000-0000-0000-0000-0000000000a1'),
  33, 'every provisioned account has exactly one active FS mapping');                  -- 4

-- ════════════════════════════════════════════════════════════════════════════════
-- Config → mapping sync + resolver equivalence (Contract 1)
-- ════════════════════════════════════════════════════════════════════════════════
INSERT INTO company_accounting_config (
  company_id, ar_account_id, ap_account_id, vat_payable_account_id, input_vat_account_id,
  ewt_withheld_account_id, ewt_payable_account_id, default_cash_account_id,
  customer_advances_account_id, supplier_down_payments_account_id, created_by, updated_by)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1',
  pg_temp.accA('1100'), pg_temp.accA('2000'), pg_temp.accA('2200'), pg_temp.accA('1400'),
  pg_temp.accA('1410'), pg_temp.accA('2210'), pg_temp.accA('1010'),
  pg_temp.accA('2100'), pg_temp.accA('1200'),
  '0c0a0000-0000-0000-0000-000000000001', '0c0a0000-0000-0000-0000-000000000001');

SELECT is(
  (SELECT count(*)::int FROM account_mapping
    WHERE company_id='0c0a0000-0000-0000-0000-0000000000a1' AND source='config_sync'),
  9, 'config→mapping trigger seeded all 9 company-scope bindings');                    -- 5

SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE'),
          pg_temp.accA('1100'), 'resolve AR_TRADE equals configured AR account');       -- 6
SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AP_TRADE'),
          pg_temp.accA('2000'), 'resolve AP_TRADE equals configured AP account');       -- 7
SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','CASH_DEFAULT'),
          pg_temp.accA('1010'), 'resolve CASH_DEFAULT equals configured cash account');-- 8
SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','VAT_OUTPUT'),
          pg_temp.accA('2200'), 'resolve VAT_OUTPUT equals configured output VAT');     -- 9
SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','VAT_INPUT'),
          pg_temp.accA('1400'), 'resolve VAT_INPUT equals configured input VAT');       -- 10
SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','EWT_WITHHELD'),
          pg_temp.accA('1410'), 'resolve EWT_WITHHELD equals configured CWT');          -- 11
SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','EWT_PAYABLE'),
          pg_temp.accA('2210'), 'resolve EWT_PAYABLE equals configured EWT payable');   -- 12
SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','CUSTOMER_ADVANCES'),
          pg_temp.accA('2100'), 'resolve CUSTOMER_ADVANCES equals config');             -- 13
SELECT is(fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','SUPPLIER_DOWNPAYMENTS'),
          pg_temp.accA('1200'), 'resolve SUPPLIER_DOWNPAYMENTS equals config');         -- 14

SELECT is_empty(
  $$SELECT v.company_id FROM vw_company_accounting_config v
      JOIN company_accounting_config c ON c.company_id = v.company_id
     WHERE c.company_id = '0c0a0000-0000-0000-0000-0000000000a1'
       AND (v.ar_account_id IS DISTINCT FROM c.ar_account_id
         OR v.ap_account_id IS DISTINCT FROM c.ap_account_id
         OR v.vat_payable_account_id IS DISTINCT FROM c.vat_payable_account_id
         OR v.input_vat_account_id IS DISTINCT FROM c.input_vat_account_id
         OR v.ewt_withheld_account_id IS DISTINCT FROM c.ewt_withheld_account_id
         OR v.ewt_payable_account_id IS DISTINCT FROM c.ewt_payable_account_id
         OR v.default_cash_account_id IS DISTINCT FROM c.default_cash_account_id
         OR v.customer_advances_account_id IS DISTINCT FROM c.customer_advances_account_id
         OR v.supplier_down_payments_account_id IS DISTINCT FROM c.supplier_down_payments_account_id)$$,
  'compat view reproduces company_accounting_config exactly');                          -- 15

-- ════════════════════════════════════════════════════════════════════════════════
-- Deterministic precedence + specificity (Contract 1)
-- ════════════════════════════════════════════════════════════════════════════════
-- More-specific bindings for AR_TRADE (all asset accounts so expected-type holds).
INSERT INTO account_mapping (company_id, key_code, document_type, account_id, source)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','SI', pg_temp.accA('1500'),'manual');
INSERT INTO account_mapping (company_id, key_code, branch_id, account_id, source)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','0c0a0000-0000-0000-0000-0000000000c1', pg_temp.accA('1200'),'manual');

SELECT is(
  fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE',
    '{"document_type":"SI"}'::jsonb),
  pg_temp.accA('1500'), 'document_type-scoped mapping outranks company default');        -- 16
SELECT is(
  fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE',
    '{"document_type":"OTHER"}'::jsonb),
  pg_temp.accA('1100'), 'non-matching document_type falls back to company default');     -- 17
SELECT is(
  fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE',
    '{"branch_id":"0c0a0000-0000-0000-0000-0000000000c1"}'::jsonb),
  pg_temp.accA('1200'), 'branch-specific mapping outranks company default');             -- 18
SELECT is(
  fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE',
    '{"document_type":"SI","branch_id":"0c0a0000-0000-0000-0000-0000000000c1"}'::jsonb),
  pg_temp.accA('1500'), 'document_type outranks branch (specificity order)');            -- 19

-- Ambiguity: two open-at-today document_type='TIE' bindings (one open, one future-dated).
INSERT INTO account_mapping (company_id, key_code, document_type, account_id, source, effective_to)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','TIE', pg_temp.accA('1500'),'manual', NULL),
       ('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','TIE', pg_temp.accA('1200'),'manual', DATE '2099-12-31');
SELECT throws_like(
  $$SELECT fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','{"document_type":"TIE"}'::jsonb)$$,
  '%ambiguous%', 'ambiguous equal-specificity mappings are rejected, never guessed');    -- 20

-- ════════════════════════════════════════════════════════════════════════════════
-- Fail-closed + account validation (Contract 1)
-- ════════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$SELECT fn_resolve_account('0c0a0000-0000-0000-0000-0000000000b1','AR_TRADE','{}'::jsonb)$$,
  '%no active mapping%', 'fail-closed when no mapping exists (company B)');               -- 21
SELECT throws_like(
  $$SELECT fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','NOPE','{}'::jsonb)$$,
  '%unknown ref_mapping_key%', 'unknown key is rejected');                               -- 22

INSERT INTO ref_mapping_key (key_code, description, is_active)
  VALUES ('TEST_INACTIVE','inactive test key', false);
INSERT INTO account_mapping (company_id, key_code, account_id, source)
  VALUES ('0c0a0000-0000-0000-0000-0000000000a1','TEST_INACTIVE', pg_temp.accA('1010'),'manual');
SELECT throws_like(
  $$SELECT fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','TEST_INACTIVE','{}'::jsonb)$$,
  '%inactive%', 'inactive key is rejected');                                             -- 23

SELECT is(
  fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE',
    format('{"override_account_id":"%s","override_authorized":true}', pg_temp.accA('1010'))::jsonb),
  pg_temp.accA('1010'), 'authorized transaction override wins outright');                -- 24
SELECT throws_like(
  format($$SELECT fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','{"override_account_id":"%s"}'::jsonb)$$, pg_temp.accA('1010')),
  '%without authorization%', 'unauthorized override is rejected');                       -- 25

-- Winning mappings that violate the account invariants.
INSERT INTO account_mapping (company_id, key_code, document_type, account_id, source)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','MISMATCH', pg_temp.accA('2000'),'manual'); -- liability
SELECT throws_like(
  $$SELECT fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','{"document_type":"MISMATCH"}'::jsonb)$$,
  '%does not match expected%', 'expected account-type mismatch is rejected');            -- 26

INSERT INTO chart_of_accounts (company_id, account_code, account_name, account_type,
       normal_balance, is_postable, lifecycle_status, is_active, created_by, updated_by)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','NP1','Nonpostable Asset','asset','debit',
        false,'active',true,'0c0a0000-0000-0000-0000-000000000001','0c0a0000-0000-0000-0000-000000000001');
INSERT INTO account_mapping (company_id, key_code, document_type, account_id, source)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','NONPOST', pg_temp.accA('NP1'),'manual');
SELECT throws_like(
  $$SELECT fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','{"document_type":"NONPOST"}'::jsonb)$$,
  '%not postable%', 'resolved non-postable account is rejected');                        -- 27

INSERT INTO chart_of_accounts (company_id, account_code, account_name, account_type,
       normal_balance, is_postable, lifecycle_status, is_active, created_by, updated_by)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','LCX','Deprecated Asset','asset','debit',
        true,'deprecated',false,'0c0a0000-0000-0000-0000-000000000001','0c0a0000-0000-0000-0000-000000000001');
INSERT INTO account_mapping (company_id, key_code, document_type, account_id, source)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','INACTIVELC', pg_temp.accA('LCX'),'manual');
SELECT throws_like(
  $$SELECT fn_resolve_account('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE','{"document_type":"INACTIVELC"}'::jsonb)$$,
  '%not active%', 'resolved non-active-lifecycle account is rejected');                  -- 28

-- ════════════════════════════════════════════════════════════════════════════════
-- Dedicated lifecycle / change-policy / posting-control accounts + posted history
-- ════════════════════════════════════════════════════════════════════════════════
INSERT INTO chart_of_accounts (company_id, account_code, account_name, account_type,
       normal_balance, is_postable, lifecycle_status, is_active, created_by, updated_by)
VALUES
 ('0c0a0000-0000-0000-0000-0000000000a1','CP1','Change-policy Asset','asset','debit',true,'active',true,'0c0a0000-0000-0000-0000-000000000001','0c0a0000-0000-0000-0000-000000000001'),
 ('0c0a0000-0000-0000-0000-0000000000a1','LCZ','Lifecycle Zero-bal','asset','debit',true,'active',true,'0c0a0000-0000-0000-0000-000000000001','0c0a0000-0000-0000-0000-000000000001'),
 ('0c0a0000-0000-0000-0000-0000000000a1','DRF','Draft Asset','asset','debit',true,'draft',false,'0c0a0000-0000-0000-0000-000000000001','0c0a0000-0000-0000-0000-000000000001'),
 ('0c0a0000-0000-0000-0000-0000000000a1','CH1','Nohistory Asset','asset','debit',true,'active',true,'0c0a0000-0000-0000-0000-000000000001','0c0a0000-0000-0000-0000-000000000001'),
 ('0c0a0000-0000-0000-0000-0000000000a1','PAR','Parent Summary','asset','debit',false,'active',true,'0c0a0000-0000-0000-0000-000000000001','0c0a0000-0000-0000-0000-000000000001');
INSERT INTO chart_of_accounts (company_id, account_code, account_name, account_type,
       normal_balance, is_postable, lifecycle_status, is_active, parent_id, created_by, updated_by)
VALUES ('0c0a0000-0000-0000-0000-0000000000a1','CHD','Child Leaf','asset','debit',true,'active',true, pg_temp.accA('PAR'),'0c0a0000-0000-0000-0000-000000000001','0c0a0000-0000-0000-0000-000000000001');

INSERT INTO fiscal_years (
  id, company_id, year_name, start_date, end_date, is_calendar
) VALUES (
  '0c0a0000-0000-0000-0000-0000000000f1',
  '0c0a0000-0000-0000-0000-0000000000a1',
  'FY2026', '2026-01-01', '2026-12-31', true
);
INSERT INTO fiscal_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
) VALUES (
  '0c0a0000-0000-0000-0000-0000000000f2',
  '0c0a0000-0000-0000-0000-0000000000a1',
  '0c0a0000-0000-0000-0000-0000000000f1',
  7, 'Jul 2026', '2026-07-01', '2026-07-31', false
);

-- Posted history for CP1 (+100), seeded with triggers off so we control the state.
SET session_replication_role = replica;
CREATE TEMP TABLE t_coa_history AS
SELECT fn_create_posted_journal_entry(
  '0c0a0000-0000-0000-0000-0000000000a1',
  NULL, 'JE-COACERT-1', '2026-07-26', 'COA lifecycle history',
  'MANUAL', NULL, '0c0a0000-0000-0000-0000-0000000000f2', 'posted', 100, 100,
  NULL, 'regular', false, false, false
) AS je_id;
SELECT fn_add_posting_line_push(
  (SELECT je_id FROM t_coa_history), 1, pg_temp.accA('CP1'),
  'COA lifecycle history', 100, 0
);
SELECT fn_add_posting_line_push(
  (SELECT je_id FROM t_coa_history), 2, pg_temp.accA('1010'),
  'COA lifecycle offset', 0, 100
);
SET session_replication_role = DEFAULT;

-- ── Lifecycle (Contract 3) ───────────────────────────────────────────────────────
SELECT fn_transition_account_lifecycle(pg_temp.accA('LCZ'), 'deprecated');
SELECT is(
  (SELECT lifecycle_status || ':' || is_active::text FROM chart_of_accounts WHERE id = pg_temp.accA('LCZ')),
  'deprecated:false', 'active→deprecated transition succeeds and syncs is_active');       -- 29
SELECT throws_like(
  format($$SELECT fn_transition_account_lifecycle('%s'::uuid,'locked')$$, pg_temp.accA('DRF')),
  '%illegal lifecycle transition%', 'illegal transition draft→locked is rejected');       -- 30
SELECT fn_transition_account_lifecycle(pg_temp.accA('CP1'), 'deprecated');
SELECT throws_like(
  format($$SELECT fn_transition_account_lifecycle('%s'::uuid,'archived')$$, pg_temp.accA('CP1')),
  '%non-zero posted balance%', 'archiving a non-zero-balance account is rejected');        -- 31
SELECT lives_ok(
  format($$SELECT fn_transition_account_lifecycle('%s'::uuid,'archived')$$, pg_temp.accA('LCZ')),
  'deprecated zero-balance account archives');                                            -- 32

-- ── Change policy (Contract 4) — CP1 has posted history ──────────────────────────
SELECT throws_like(
  format($$UPDATE chart_of_accounts SET account_type='expense' WHERE id='%s'$$, pg_temp.accA('CP1')),
  '%account_type is immutable%', 'account_type immutable once account has posted history');-- 33
SELECT throws_like(
  format($$UPDATE chart_of_accounts SET normal_balance='credit' WHERE id='%s'$$, pg_temp.accA('CP1')),
  '%normal_balance is immutable%', 'normal_balance immutable once account has posted history');-- 34
SELECT throws_like(
  format($$DELETE FROM chart_of_accounts WHERE id='%s'$$, pg_temp.accA('CP1')),
  '%cannot be deleted%', 'account with posted history cannot be deleted');                 -- 35
SELECT lives_ok(
  format($$UPDATE chart_of_accounts SET account_type='liability', normal_balance='credit' WHERE id='%s'$$, pg_temp.accA('CH1')),
  'identity attributes are editable while the account has no posted history');             -- 36
SELECT lives_ok(
  format($$DELETE FROM chart_of_accounts WHERE id='%s'$$, pg_temp.accA('DRF')),
  'an unused draft account can be deleted');                                               -- 37

-- ── Posting control validators (Contract 2) ──────────────────────────────────────
SELECT ok(NOT fn_account_is_leaf(pg_temp.accA('PAR')), 'parent/summary account is not a leaf');   -- 38
SELECT ok(fn_is_account_postable(pg_temp.accA('CHD')), 'active postable leaf is postable');        -- 39
SELECT ok(NOT fn_is_account_postable(pg_temp.accA('PAR')), 'non-leaf parent is not postable');     -- 40
SELECT throws_like(
  format($$SELECT fn_assert_manual_postable('%s'::uuid)$$, pg_temp.accA('1100')),
  '%control account%', 'control account is rejected for manual journal posting');          -- 41
SELECT throws_like(
  format($$SELECT fn_assert_postable_leaf('%s'::uuid)$$, pg_temp.accA('NP1')),
  '%not a postable%', 'non-postable account is rejected by the leaf-post validator');       -- 42

-- ── FS registry (Contract 5) ─────────────────────────────────────────────────────
SELECT throws_like(
  format($$INSERT INTO account_fs_map (company_id, account_id, fs_structure_id, statement, effective_from)
           SELECT '0c0a0000-0000-0000-0000-0000000000a1', '%s',
                  (SELECT id FROM fs_structure WHERE company_id='0c0a0000-0000-0000-0000-0000000000a1' AND statement='balance_sheet' AND line_code='assets'),
                  'balance_sheet', CURRENT_DATE$$, pg_temp.accA('1010')),
  '%uq_account_fs_map_active%',
  'a second active FS mapping for the same account+statement is blocked');                 -- 43
SELECT lives_ok(
  format($f$DO $do$
    BEGIN
      UPDATE account_fs_map SET effective_to = CURRENT_DATE
       WHERE company_id='0c0a0000-0000-0000-0000-0000000000a1' AND account_id='%s'
         AND statement='balance_sheet' AND effective_to IS NULL;
      INSERT INTO account_fs_map (company_id, account_id, fs_structure_id, statement, effective_from)
      VALUES ('0c0a0000-0000-0000-0000-0000000000a1','%s',
              (SELECT id FROM fs_structure WHERE company_id='0c0a0000-0000-0000-0000-0000000000a1' AND statement='balance_sheet' AND line_code='assets'),
              'balance_sheet', CURRENT_DATE + 1);
    END
  $do$;$f$, pg_temp.accA('1010'), pg_temp.accA('1010')),
  'effective-dated reclassification (close current, open new) is allowed');               -- 44

-- ── Single writable authority: authenticated cannot write account_mapping ─────────
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('0c0a0000-0000-0000-0000-000000000001');
SELECT throws_like(
  $$INSERT INTO account_mapping (company_id, key_code, account_id, source)
    VALUES ('0c0a0000-0000-0000-0000-0000000000a1','AR_TRADE',
            (SELECT id FROM chart_of_accounts WHERE company_id='0c0a0000-0000-0000-0000-0000000000a1' AND account_code='1010'),'manual')$$,
  '%row-level security%',
  'authenticated cannot write account_mapping (config remains the single authority)');     -- 45
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
