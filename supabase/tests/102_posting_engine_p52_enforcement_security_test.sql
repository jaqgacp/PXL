-- ══════════════════════════════════════════════════════════════════════════════
-- POSTING-ENGINE-P52-001 — Kernel Totality Guard enforcement certification
--
-- The catalog census runs before the transaction-local attack helpers exist.
-- The negative matrix then attempts all six ledger mutations through eight
-- unauthorized paths. Every helper is rolled back with this test.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(78);

-- ──────────────────────────────────────────────────────────────────────────────
-- A. Armed configuration and complete permanent-catalog security census
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TEMP VIEW p52_app_functions AS
SELECT p.oid, p.proname, p.prosecdef, p.proacl, p.prosrc,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND NOT EXISTS (
    SELECT 1
    FROM pg_depend d
    WHERE d.classid = 'pg_proc'::regclass
      AND d.objid = p.oid
      AND d.deptype = 'e'
  );

CREATE TEMP VIEW p52_direct_mutators AS
SELECT *
FROM p52_app_functions
WHERE prosrc ~*
  '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?(journal_entries|journal_entry_lines)';

CREATE TEMP VIEW p52_reachable_mutators AS
WITH RECURSIVE reachable AS (
  SELECT oid, proname, prosecdef, proacl, prosrc, identity_arguments
  FROM p52_direct_mutators
  UNION
  SELECT f.oid, f.proname, f.prosecdef, f.proacl, f.prosrc,
         f.identity_arguments
  FROM p52_app_functions f
  JOIN reachable r ON strpos(f.prosrc, r.proname || '(') > 0
)
SELECT * FROM reachable;

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM p52_app_functions p
    WHERE p.proname = 'fn_guard_journal_kernel_origin'),
  'the Kernel Totality Guard is armed with a compile-time true constant');             -- 1

SELECT ok(
  (SELECT p.prosrc !~ 'c_enforce\s+AND\s+NOT\s+v_maint'
     FROM p52_app_functions p
    WHERE p.proname = 'fn_guard_journal_kernel_origin'),
  'maintenance and replay classification is not an enforcement bypass');              -- 2

SELECT ok(
  (SELECT p.prosrc ~ 'PG_CONTEXT' AND p.prosrc !~ 'current_setting'
     FROM p52_app_functions p
    WHERE p.proname = 'fn_guard_journal_kernel_origin'),
  'kernel origin remains structural and cannot be forged with session state');         -- 3

SELECT ok(
  fn_posting_kernel_origin(
    'PL/pgSQL function fn_create_posted_journal_entry(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_reverse_posted_journal_entry(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_finalize_journal_entry(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line_push(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_sales_invoice_posting_line(uuid) line 1')
  AND NOT fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line_extra(uuid) line 1')
  AND NOT fn_posting_kernel_origin(
    'PL/pgSQL function fn_finalize_journal_entry_bypass(uuid) line 1'),
  'the frozen exact-name classifier admits only sanctioned names, not lookalikes');    -- 4

SELECT set_eq(
  $$SELECT proname::text FROM p52_direct_mutators$$,
  $$VALUES ('fn_create_posted_journal_entry'),
           ('fn_reverse_posted_journal_entry'),
           ('fn_finalize_journal_entry'),
           ('fn_add_posting_line'),
           ('fn_add_posting_line_push'),
           ('fn_add_sales_invoice_posting_line')$$,
  'only the six sanctioned persistence functions contain permanent ledger DML');      -- 5

SELECT is((SELECT count(*)::int FROM p52_direct_mutators), 6,
  'the direct ledger-mutator census is exactly six');                                  -- 6

SELECT ok((SELECT bool_and(prosecdef) FROM p52_direct_mutators),
  'all six direct ledger mutators are SECURITY DEFINER');                              -- 7

SELECT is(
  (SELECT count(*)::int
     FROM p52_direct_mutators
    WHERE has_function_privilege('anon', oid, 'EXECUTE')
       OR has_function_privilege('authenticated', oid, 'EXECUTE')),
  0, 'no sanctioned persistence function is client executable');                      -- 8

SELECT set_eq(
  $$SELECT proname::text
      FROM p52_direct_mutators
     WHERE has_function_privilege('service_role', oid, 'EXECUTE')$$,
  $$VALUES ('fn_create_posted_journal_entry'),
           ('fn_add_posting_line'),
           ('fn_add_posting_line_push')$$,
  'service_role has only the three approved persistence entry points');                -- 9

-- PXL-AUD-073 added fn_post_receiving_report, its source-locked implementation,
-- and brought fn_confirm_receiving_report into the ledger-capable graph, because
-- confirming a goods receipt now posts a journal instead of moving stock silently.
-- PAD-002 adds the opening-balance post and reversal writers; both reach the
-- ledger exclusively through the sanctioned Accounting Kernel.
-- Its Receipt and Payment Voucher continuation layers retain two private,
-- non-client-executable native-document cores.
-- Delivery Plan Phase 6 adds exactly one entry point to the graph:
-- fn_reopen_fiscal_year, which counter-posts the year-end closing journal through
-- the Accounting Kernel. fn_close_fiscal_year was already in the graph, and the
-- period close posts nothing at all — an accounting-period close is a lock, not
-- an entry — so the close engine's other five functions stay outside it.
-- Backlog 18c adds one more: fn_void_delivery_receipt, which reverses a delivery's
-- journal through fn_reverse_posted_journal_entry and restocks the goods. It is a
-- correction path, not a second posting path — the reversal is the same one every
-- other void uses.
SELECT is((SELECT count(*)::int FROM p52_reachable_mutators), 99,
  'the complete static ledger-capable call graph contains 99 functions');              -- 10

SELECT ok((SELECT bool_and(prosecdef) FROM p52_reachable_mutators),
  'every function in the static ledger-capable call graph is SECURITY DEFINER');       -- 11

-- PAD-001 adds exactly one function to all three censuses: fn_calculate_tax,
-- the Tax Engine. It is SECURITY DEFINER (it reads governed reference masters),
-- authenticated-executable (a form can price a line before saving it), and it
-- is NOT ledger-capable — assertion 10 above is unchanged at 85, because the
-- calculator writes nothing.
--
-- Delivery Receipt posting adds exactly one more to all three censuses on
-- 2026-08-03: fn_post_delivery_receipt, which relieves stock into
-- goods-delivered-not-invoiced. It IS ledger-capable, so assertion 10 above
-- moves from 85 to 86 — the only entry point added to the graph.
--
-- Financial statement presentation adds four, none of them ledger-capable:
-- fn_seed_company_fs_structure and fn_map_company_fs_accounts (provisioning,
-- admin-gated) and fn_financial_statement_report / fn_fs_line_is_descendant
-- (reporting, STABLE, read-only). Assertion 10 stays at 86: reporting reads the
-- ledger and never writes it, which is the boundary this file exists to hold.
--
-- Effective-dated VAT resolution adds exactly three more, on the same terms:
-- fn_resolve_vat_code (the one place a VAT code's validity is decided),
-- fn_company_tax_registration_asof (the tax-profile seam it reads), and
-- fn_vat_codes_asof (the picker the UI reads so it cannot offer what the
-- database refuses). All three read reference masters and write nothing, so
-- assertion 10 stays at 85.
--
-- Period close and year-end roll-forward add nine, taking the census from 446 to
-- 455. Seven are SECURITY DEFINER (383 -> 390): the readiness reader, the four
-- close/reopen entry points, the internal roll-forward, and the lock-origin
-- trigger body. Two are not: the close-run immutability trigger body and
-- fn_fiscal_close_engine_origin, an IMMUTABLE SQL classifier that reads only its
-- argument. Six become client-executable (313 -> 319 minus the one below):
-- readiness plus the four close/reopen entry points reach `authenticated` and
-- `service_role`; the roll-forward, both trigger bodies and the classifier reach
-- no role at all, so anon stays exactly where it was. The classifier is closed to
-- PUBLIC on the same terms as fn_posting_kernel_origin.
--
-- Comparative statements and notes add five, 455 -> 460. Four are SECURITY
-- DEFINER (390 -> 394) because they read governed company data across RLS:
-- fn_resolve_comparative_period, fn_comparative_financial_statement_report,
-- fn_financial_statement_line_accounts and fn_financial_statement_notes. The
-- fifth, fn_fs_presentation_sign, is an IMMUTABLE SQL classifier that reads only
-- its arguments. All five reach `authenticated` and `service_role` and none
-- reaches anon. fn_financial_statement_report was REPLACED rather than added:
-- its five-argument form is dropped so the new re-presentation argument cannot
-- make an existing five-argument call ambiguous. Assertion 10 stays at 87 —
-- reporting reads the ledger and never writes it.
--
-- Percentage tax (Backlog 8) adds thirteen, 460 -> 473. Twelve are SECURITY
-- DEFINER (394 -> 406): the business-tax resolver and its picker, the
-- percentage-tax registration seam, the code-usage predicate, the one
-- percentage-tax ledger writer, the ledger-to-GL reconciliation, the 2551Q
-- computation and its generator, and four trigger bodies (version rules, history
-- guard, the sales-line business-tax backstop and the return reconciliation
-- gate). The thirteenth, fn_percentage_tax_return_period, is an IMMUTABLE
-- quarter-bounds helper that reads only its arguments. Nine become
-- client-executable (323 -> 332); the four trigger bodies reach no role at all.
-- **anon stays exactly at 197** and service_role at 318: nothing here is
-- reachable without a session. Assertion 10 stays at 87 — percentage tax reaches
-- the ledger through the same six sanctioned kernels as everything else, and
-- fn_add_percentage_tax_detail writes the tax ledger, never the General Ledger.
-- BIR filing artifacts (Delivery Plan Phase 5.8) add seven, 473 -> 480: the one
-- tax-ledger-to-GL reconciliation, the filing period-bounds helper, the one
-- working-paper reader, the per-artifact reconciliation face, the artifact
-- guard, the one artifact generator and the 2550Q projection. Six are SECURITY
-- DEFINER (406 -> 412) because they read governed company data across RLS; the
-- seventh, fn_filing_period_bounds, is an IMMUTABLE helper that reads only its
-- arguments. Six become client-executable (332 -> 338); fn_guard_filing_artifact
-- is a trigger body and reaches no role at all. **anon stays exactly at 197** —
-- no filing surface is reachable without a session. Assertion 10 stays at 87:
-- filing *reads* the tax ledger and the General Ledger and writes neither. The
-- six existing per-form faces (VAT, withholding and percentage-tax
-- reconciliation, the 2551Q and 1601EQ computations, the PT generator) were
-- REPLACED by delegations rather than added, so they do not move any count.
-- Filing Artifact Export (Backlog 8d) adds two, 480 -> 482: the one exporter and
-- its evidence snapshot. Both are SECURITY DEFINER (412 -> 414) because they read
-- governed company data across RLS, and both reach `authenticated` (338 -> 340).
-- **anon stays exactly at 197.** Assertion 10 stays at 87: an export is a
-- consumer of the filing artifact and writes no ledger — it writes only a
-- `report_snapshots` evidence row.
-- Backlog 8e (i)/(iii) adds exactly one, 482 -> 483: `fn_generate_ewt_return`,
-- the 1601EQ projection. It is SECURITY DEFINER (414 -> 415) and reaches
-- `authenticated` (340 -> 341). Registering the QAP added **no function at all**
-- — it is seed rows — and `fn_filing_artifact_export`,
-- `fn_require_wht_export_profile` and `fn_qap_2307_reconciliation` were REPLACED
-- in place, so they move no count. **anon stays exactly at 197.**
-- Backlog 8f stage 1 adds four, 483 -> 487: the reconciling-item writer, its
-- delete, its reader and the line guard. All four are SECURITY DEFINER
-- (415 -> 419); three reach `authenticated` (341 -> 344) and the **guard reaches
-- no role at all**, exactly as `fn_guard_filing_artifact` does — a trigger body
-- is not a client surface. `fn_guard_filing_artifact`, `fn_generate_filing_artifact`
-- and `fn_filing_artifact_export` were REPLACED in place and move no count.
-- **anon stays exactly at 197.** Assertion 10 stays at 87: a reconciling item
-- explains a difference and writes no ledger.
--
-- Backlog 8f stage 2 REMOVES one, 487 -> 486: `fn_snapshot_wht_export`, retired
-- with the legacy SAWT/QAP export path once both screens consumed the filing
-- artifact instead. It was SECURITY DEFINER (419 -> 418) and reached
-- `authenticated` (344 -> 343) and `service_role` (318 -> 317). It also reached
-- **`anon`**, so retiring it moved the one number this file has otherwise held
-- fixed since it was written: **197 -> 196**. A legacy compliance export was
-- callable without a session; the governed one never has been.
--
-- Backlog 10 adds four, 486 -> 490: the three governed succession RPCs
-- (`fn_tax_code_succeed`, `fn_vat_code_succeed`, `fn_atc_code_succeed`) and
-- `fn_enforce_vat_code_version_rules`, the version-rules trigger `vat_codes`
-- alone had been missing. All four are SECURITY DEFINER (418 -> 422). Only the
-- three RPCs reach `authenticated` (343 -> 346); the trigger body reaches **no
-- role**, following `fn_enforce_percentage_tax_code_version_rules` rather than
-- the two older version-rule functions that were left PUBLIC-executable. The
-- three upserts were REPLACED with a wider signature and move no count.
-- **anon stays exactly at 196**, and service_role at 317.
--
-- Backlog 18c adds one, 490 -> 491: `fn_void_delivery_receipt`, the cancellation
-- and reversal a mis-shipped delivery had no path to. It is SECURITY DEFINER
-- (422 -> 423) and reaches `authenticated` and `service_role` exactly as
-- `fn_post_delivery_receipt` does (346 -> 347, 317 -> 318). The three guard
-- functions it repairs — the delivery header guard, `fn_guard_doc_lines` and
-- `fn_capture_cas_document_void` — were all REPLACED in place and move no count.
-- **anon stays exactly at 196.**
--
-- PXL-AUD-076 adds three, 491 -> 494: `fn_void_cash_sale`, the named authority
-- for withdrawing a cash sale as one business event, plus the two private
-- helpers it and the ordinary invoice void now share — `fn_reverse_receipt_core`
-- (the one receipt-reversal implementation, extracted from `fn_bounce_receipt`)
-- and `fn_stamp_void_inventory_dimensions`. All three are SECURITY DEFINER
-- (423 -> 426). Only the orchestrator reaches `authenticated` (347 -> 348) and
-- `service_role` (318 -> 319); both helpers reach no role at all.
--
-- **`anon` FALLS, 196 -> 194.** `fn_bounce_receipt` and `fn_void_sales_invoice`
-- were both reachable by `anon`: every historical grant for them was a bare
-- `GRANT ... TO authenticated`, and PostgreSQL grants EXECUTE to PUBLIC by
-- default. Neither was exploitable — both fail closed on `is_company_member` —
-- but a destructive financial entry point should not be reachable without a
-- session at all. PXL-AUD-076 revokes PUBLIC and anon on both, the same posture
-- every function written since Backlog 8f already carries.
--
-- Backlog 18b adds one, 494 -> 495: `fn_assert_no_unlinked_delivered_stock`, the
-- guard that refuses an invoice whose stockable line would relieve stock a
-- delivery already relieved. SECURITY DEFINER (426 -> 427) and private: clients
-- reach it only through the existing readiness validator, which performs the
-- company-membership check. Authenticated/service counts therefore do not move.
-- The package also closes the validator's inherited PUBLIC grant, so **anon
-- falls 194 -> 193**. The helper is NOT ledger-capable — assertion 10 is
-- unchanged: a guard refuses, it never writes.
--
-- The Sales + Purchasing lifecycle hardening package adds three, 495 -> 498:
-- `fn_void_receiving_report` (the purchasing mirror of the delivery
-- cancellation — ledger-capable, so assertion 10 moves 90 -> 91) and the two
-- three-way-match assertions `fn_assert_receipt_within_po` and
-- `fn_assert_bill_within_receipt`, which refuse and never write. All three are
-- SECURITY DEFINER (427 -> 430). Only the void orchestrator reaches
-- `authenticated` and `service_role` (348 -> 349 and 319 -> 320); both
-- relationship assertions are private. Replacing the Vendor Bill readiness
-- validator closes its inherited PUBLIC grant, so **anon falls 193 -> 192**.
-- The production costing authority adds a net 18 SECURITY DEFINER functions
-- and seven ledger-reachable orchestration paths. Private bridge revokes reduce
-- anon by four; service-only authorities add a net two; authenticated is stable.
-- The Sales Document Conversion Engine adds twelve SECURITY DEFINER functions.
-- Five governed entry points reach authenticated and service_role, seven helpers
-- remain private, and the converted-delivery authority adds one ledger-reachable
-- path. The package grants nothing to anon.
SELECT is((SELECT count(*)::int FROM p52_app_functions), 528,
  'the complete application-owned public function census contains 528 functions');    -- 12

SELECT is((SELECT count(*)::int FROM p52_app_functions WHERE prosecdef), 460,
  'the complete application-owned SECURITY DEFINER census contains 460 functions');   -- 13

SELECT is(
  (SELECT count(*)::int FROM p52_app_functions
    WHERE has_function_privilege('authenticated', oid, 'EXECUTE')),
  354, 'authenticated EXECUTE coverage is completely counted');                       -- 14

SELECT is(
  (SELECT count(*)::int FROM p52_app_functions
    WHERE has_function_privilege('anon', oid, 'EXECUTE')),
  188, 'anon EXECUTE coverage is completely counted');                                -- 15

SELECT is(
  (SELECT count(*)::int FROM p52_app_functions
    WHERE has_function_privilege('service_role', oid, 'EXECUTE')),
  327, 'service_role EXECUTE coverage is completely counted');                        -- 16

SELECT is(
  (SELECT count(*)::int
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgrelid IN (
        'public.journal_entries'::regclass,
        'public.journal_entry_lines'::regclass)),
  21, 'the complete ledger persistence trigger census contains 21 triggers');         -- 17

SELECT ok(
  (SELECT count(*) = 2 AND bool_and(t.tgenabled = 'A')
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid = 'public.fn_guard_journal_kernel_origin()'::regprocedure
      AND t.tgrelid IN (
        'public.journal_entries'::regclass,
        'public.journal_entry_lines'::regclass)),
  'the armed guard is ALWAYS-enabled on both ledger tables');                         -- 18

SELECT is(
  (SELECT count(*)::int
     FROM pg_class c
    WHERE c.oid IN (
      'public.journal_entries'::regclass,
      'public.journal_entry_lines'::regclass)
      AND c.relrowsecurity),
  2, 'RLS remains enabled on both ledger tables');                                     -- 19

SELECT set_eq(
  $$SELECT tablename || ':' || policyname || ':' || cmd
      FROM pg_policies
     WHERE schemaname='public'
       AND tablename IN ('journal_entries','journal_entry_lines')$$,
  $$VALUES ('journal_entries:je_read:SELECT'),
           ('journal_entry_lines:jel_read:SELECT')$$,
  'the complete ledger RLS census is the two membership-scoped read policies');        -- 20

SELECT is(
  (SELECT count(*)::int
     FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('journal_entries','journal_entry_lines')
      AND cmd <> 'SELECT'),
  0, 'there is no ledger write policy');                                               -- 21

SELECT is(
  (SELECT count(*)::int
     FROM (VALUES ('journal_entries'), ('journal_entry_lines')) AS t(name)
    WHERE has_table_privilege('authenticated', 'public.' || t.name,
                              'INSERT,UPDATE,DELETE')),
  0, 'authenticated has no direct ledger write privilege');                           -- 22

SELECT is(
  (SELECT count(*)::int
     FROM (VALUES ('journal_entries'), ('journal_entry_lines')) AS t(name)
    WHERE has_table_privilege('anon', 'public.' || t.name,
                              'INSERT,UPDATE,DELETE')),
  0, 'anon has no direct ledger write privilege');                                    -- 23

SELECT is((SELECT count(*)::int FROM sys_posting_guard_violations), 0,
  'the pre-attack violation census is zero');                                          -- 24

-- ──────────────────────────────────────────────────────────────────────────────
-- B. Positive kernel fixture
-- ──────────────────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '0f520000-0000-0000-0000-000000000001',
        'authenticated', 'authenticated', 'p52-owner@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"0f520000-0000-0000-0000-000000000001","role":"authenticated"}',
  true);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period, address_line_1, address_line_2,
  city, province, zip_code, email, signatory_name, signatory_position,
  created_by, updated_by
) VALUES (
  '0f520000-0000-0000-0000-0000000000b1', 'corporation',
  'P52 Enforcement Corp', 'Trading', '391-000-001-00000',
  'vat', 'calendar', 'Kernel St', 'Guard Bldg', 'Makati',
  'Metro Manila', '1200', 'p52-owner@test.local', 'Kernel Owner',
  'President', auth.uid(), auth.uid()
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name, address_line_1, address_line_2,
  city, province, zip_code, created_by, updated_by
) VALUES (
  '0f520000-0000-0000-0000-0000000000b2',
  '0f520000-0000-0000-0000-0000000000b1',
  'HO', 'Head Office', 'Kernel St', 'Guard Bldg', 'Makati',
  'Metro Manila', '1200', auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (
  id, company_id, year_name, start_date, end_date, is_calendar
) VALUES (
  '0f520000-0000-0000-0000-0000000000f1',
  '0f520000-0000-0000-0000-0000000000b1',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  id, company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
) VALUES (
  '0f520000-0000-0000-0000-0000000000f2',
  '0f520000-0000-0000-0000-0000000000b1',
  '0f520000-0000-0000-0000-0000000000f1',
  6, 'Jun 2026', '2026-06-01', '2026-06-30', false
);

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name, account_type,
  normal_balance, is_postable, is_active, created_by, updated_by
) VALUES (
  '0f520000-0000-0000-0000-0000000000a1',
  '0f520000-0000-0000-0000-0000000000b1',
  '1000', 'P52 Probe Account', 'asset', 'debit', true, true,
  auth.uid(), auth.uid()
);

CREATE TEMP TABLE p52_fixture AS
SELECT fn_create_posted_journal_entry(
  '0f520000-0000-0000-0000-0000000000b1',
  '0f520000-0000-0000-0000-0000000000b2',
  'P52-GUARD-DRAFT', '2026-06-15', 'P52 authorized kernel fixture',
  'MANUAL', NULL, '0f520000-0000-0000-0000-0000000000f2',
  'draft', 0, 0, 'manual', 'regular', false, false, false
) AS header_id;

ALTER TABLE p52_fixture ADD COLUMN line_id uuid;

UPDATE p52_fixture
SET line_id = fn_add_posting_line_push(
  header_id, 1,
  '0f520000-0000-0000-0000-0000000000a1',
  'P52 authorized kernel fixture line',
  1, 0, 'base', NULL,
  '0f520000-0000-0000-0000-0000000000b2'
);

-- ──────────────────────────────────────────────────────────────────────────────
-- C. Transaction-local unauthorized helpers and six-operation matrix
-- ──────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.p52_probe_mutate(p_operation text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  CASE p_operation
    WHEN 'INSERT journal_entries' THEN
      INSERT INTO journal_entries (
        company_id, branch_id, je_number, je_date, fiscal_period_id,
        description, reference_doc_type, status, total_debit, total_credit,
        created_by, updated_by
      ) VALUES (
        '0f520000-0000-0000-0000-0000000000b1',
        '0f520000-0000-0000-0000-0000000000b2',
        'P52-UNAUTHORIZED', '2026-06-15',
        '0f520000-0000-0000-0000-0000000000f2',
        'unauthorized probe', 'MANUAL', 'draft', 0, 0,
        '0f520000-0000-0000-0000-000000000001',
        '0f520000-0000-0000-0000-000000000001'
      );
    WHEN 'UPDATE journal_entries' THEN
      UPDATE journal_entries
      SET description = 'unauthorized header update'
      WHERE je_number = 'P52-GUARD-DRAFT';
    WHEN 'DELETE journal_entries' THEN
      DELETE FROM journal_entries
      WHERE je_number = 'P52-GUARD-DRAFT';
    WHEN 'INSERT journal_entry_lines' THEN
      INSERT INTO journal_entry_lines (
        je_id, company_id, line_number, account_id, description,
        debit_amount, credit_amount, branch_id, created_by, updated_by
      ) VALUES (
        (SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'),
        '0f520000-0000-0000-0000-0000000000b1', 99,
        '0f520000-0000-0000-0000-0000000000a1',
        'unauthorized probe line', 1, 0,
        '0f520000-0000-0000-0000-0000000000b2',
        '0f520000-0000-0000-0000-000000000001',
        '0f520000-0000-0000-0000-000000000001'
      );
    WHEN 'UPDATE journal_entry_lines' THEN
      UPDATE journal_entry_lines
      SET description = 'unauthorized line update'
      WHERE je_id = (
        SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'
      ) AND line_number = 1;
    WHEN 'DELETE journal_entry_lines' THEN
      DELETE FROM journal_entry_lines
      WHERE je_id = (
        SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'
      ) AND line_number = 1;
    ELSE
      RAISE EXCEPTION 'Unknown P5.2 probe operation: %', p_operation;
  END CASE;
END;
$$;

CREATE FUNCTION public.p52_security_definer_probe(p_operation text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.p52_probe_mutate(p_operation) $$;

CREATE FUNCTION public.p52_sql_script_probe(p_operation text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.p52_probe_mutate(p_operation) $$;

CREATE FUNCTION public.p52_rpc_probe(p_operation text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.p52_probe_mutate(p_operation) $$;

CREATE FUNCTION public.p52_migration_helper_probe(p_operation text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM set_config('pxl.allow_demo_reset', 'on', true);
  PERFORM public.p52_probe_mutate(p_operation);
END;
$$;

CREATE FUNCTION public.p52_replay_helper_probe(p_operation text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  PERFORM set_config('pxl.allow_demo_reset', 'on', true);
  PERFORM public.p52_probe_mutate(p_operation);
END;
$$;

REVOKE ALL ON FUNCTION public.p52_probe_mutate(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_security_definer_probe(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_sql_script_probe(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_rpc_probe(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_migration_helper_probe(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.p52_replay_helper_probe(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.p52_rpc_probe(text) TO authenticated;

CREATE TEMP TABLE p52_operations (
  ordinal integer PRIMARY KEY,
  operation text NOT NULL,
  direct_statement text NOT NULL
);

INSERT INTO p52_operations VALUES
  (1, 'INSERT journal_entries', $sql$
    INSERT INTO journal_entries (
      company_id, branch_id, je_number, je_date, fiscal_period_id,
      description, reference_doc_type, status, total_debit, total_credit,
      created_by, updated_by
    ) VALUES (
      '0f520000-0000-0000-0000-0000000000b1',
      '0f520000-0000-0000-0000-0000000000b2',
      'P52-UNAUTHORIZED', '2026-06-15',
      '0f520000-0000-0000-0000-0000000000f2',
      'unauthorized probe', 'MANUAL', 'draft', 0, 0,
      '0f520000-0000-0000-0000-000000000001',
      '0f520000-0000-0000-0000-000000000001'
    )
  $sql$),
  (2, 'UPDATE journal_entries', $sql$
    UPDATE journal_entries
    SET description = 'unauthorized header update'
    WHERE je_number = 'P52-GUARD-DRAFT'
  $sql$),
  (3, 'DELETE journal_entries', $sql$
    DELETE FROM journal_entries
    WHERE je_number = 'P52-GUARD-DRAFT'
  $sql$),
  (4, 'INSERT journal_entry_lines', $sql$
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, branch_id, created_by, updated_by
    ) VALUES (
      (SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'),
      '0f520000-0000-0000-0000-0000000000b1', 99,
      '0f520000-0000-0000-0000-0000000000a1',
      'unauthorized probe line', 1, 0,
      '0f520000-0000-0000-0000-0000000000b2',
      '0f520000-0000-0000-0000-000000000001',
      '0f520000-0000-0000-0000-000000000001'
    )
  $sql$),
  (5, 'UPDATE journal_entry_lines', $sql$
    UPDATE journal_entry_lines
    SET description = 'unauthorized line update'
    WHERE je_id = (
      SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'
    ) AND line_number = 1
  $sql$),
  (6, 'DELETE journal_entry_lines', $sql$
    DELETE FROM journal_entry_lines
    WHERE je_id = (
      SELECT id FROM journal_entries WHERE je_number='P52-GUARD-DRAFT'
    ) AND line_number = 1
  $sql$);

GRANT SELECT ON p52_operations TO authenticated, anon;

-- Authenticated and anon are rejected by table privileges/RLS before a trigger
-- can run. The other six paths reach the armed trigger and must receive 23514.
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  direct_statement, '42501', NULL,
  'authenticated rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 25-30
RESET ROLE;

SET LOCAL ROLE anon;
SELECT throws_ok(
  direct_statement, '42501', NULL,
  'anon rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 31-36
RESET ROLE;

SELECT throws_ok(
  format('SELECT public.p52_security_definer_probe(%L)', operation),
  '23514', NULL,
  'non-kernel SECURITY DEFINER helper rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 37-42

SELECT throws_ok(
  format('SELECT public.p52_sql_script_probe(%L)', operation),
  '23514', NULL,
  'SQL script helper rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 43-48

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  format('SELECT public.p52_rpc_probe(%L)', operation),
  '23514', NULL,
  'authenticated RPC rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 49-54
RESET ROLE;

SELECT throws_ok(
  format('SELECT public.p52_migration_helper_probe(%L)', operation),
  '23514', NULL,
  'migration helper rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 55-60

SET LOCAL session_replication_role = replica;
SELECT throws_ok(
  format('SELECT public.p52_replay_helper_probe(%L)', operation),
  '23514', NULL,
  'replay helper rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 61-66
SET LOCAL session_replication_role = origin;

SELECT throws_ok(
  direct_statement, '23514', NULL,
  'direct owner SQL rejects ' || operation
) FROM p52_operations ORDER BY ordinal;                                                -- 67-72

-- ──────────────────────────────────────────────────────────────────────────────
-- D. Positive result and rollback proof
-- ──────────────────────────────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int
     FROM journal_entries
    WHERE id = (SELECT header_id FROM p52_fixture)),
  1, 'the sanctioned header kernel succeeds under enforcement');                      -- 73

SELECT is(
  (SELECT count(*)::int
     FROM journal_entry_lines
    WHERE id = (SELECT line_id FROM p52_fixture)),
  1, 'the sanctioned line kernel succeeds under enforcement');                        -- 74

SELECT results_eq(
  $q$SELECT status, posting_origin, entry_class, total_debit, total_credit
       FROM journal_entries
      WHERE id = (SELECT header_id FROM p52_fixture)$q$,
  $$VALUES ('draft'::text, 'manual'::text, 'regular'::text,
            0::numeric, 0::numeric)$$,
  'authorized header metadata is unchanged');                                         -- 75

SELECT results_eq(
  $q$SELECT line_number, line_role, debit_amount, credit_amount, branch_id
       FROM journal_entry_lines
      WHERE id = (SELECT line_id FROM p52_fixture)$q$,
  $$VALUES (1, 'base'::text, 1::numeric, 0::numeric,
            '0f520000-0000-0000-0000-0000000000b2'::uuid)$$,
  'authorized line content and ordering are unchanged');                              -- 76

SELECT is((SELECT count(*)::int FROM sys_posting_guard_violations), 0,
  'all rejected violation evidence rolls back and the census remains zero');           -- 77

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM journal_entries WHERE je_number='P52-UNAUTHORIZED'
  )
  AND (SELECT description='P52 authorized kernel fixture'
         FROM journal_entries
        WHERE id=(SELECT header_id FROM p52_fixture))
  AND (SELECT description='P52 authorized kernel fixture line'
         FROM journal_entry_lines
        WHERE id=(SELECT line_id FROM p52_fixture)),
  'no unauthorized insert, update, or delete has persisted');                         -- 78

SELECT * FROM finish();
ROLLBACK;
