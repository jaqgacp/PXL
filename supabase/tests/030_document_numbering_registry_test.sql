-- DOCUMENT-NUMBERING-REGISTRY-001 (PXL-AUD-051)
--
-- Proves the document-code registry, the numbering RPCs, and the branch-scoped
-- fn_next_document_number contract are mutually consistent:
--   * every code a shipped function requests exists in ref_document_types;
--   * no deployed function still calls the nonexistent two-argument overload;
--   * a real fixed-asset registration produces governed FA and JE numbers,
--     posts a balanced acquisition JE, and links it back as an FA source;
--   * the exact branch-scoped JE numbering call the inventory posters now make
--     resolves against a registry-consistent setup.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(11);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111130',
  'authenticated', 'authenticated', 'numbering@test.local', '',
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111130","role":"authenticated"}',
  true
);

-- ── Mechanical registry coverage guards (do not need company fixtures) ────────
SELECT is(
  (SELECT COUNT(*)::INTEGER
   FROM (
     SELECT DISTINCT (regexp_matches(
       p.prosrc,
       'fn_next_document_number\([a-z_.]+,\s*[a-z_.]+,\s*''([A-Z-]+)''\)', 'g'))[1] AS code
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname <> 'fn_next_document_number'
   ) requested
   LEFT JOIN ref_document_types d ON d.document_code = requested.code
   WHERE d.document_code IS NULL),
  0,
  'every document code requested by a shipped function exists in ref_document_types'
);

SELECT is(
  (SELECT COUNT(*)::INTEGER
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname <> 'fn_next_document_number'
     AND p.prosrc ~ 'fn_next_document_number\([a-z_.]+,\s*''[A-Z-]+''\)'),
  0,
  'no deployed function still calls the two-argument (branch-less) numbering overload'
);

SELECT is(
  (SELECT COUNT(*)::INTEGER FROM ref_document_types
   WHERE document_code IN ('JE', 'FA', 'SDM', 'PRT')),
  4,
  'the four previously-missing requested codes (JE, FA, SDM, PRT) are governed'
);

SELECT ok(
  EXISTS (SELECT 1 FROM ref_document_types WHERE document_code = 'DM-S'),
  'DebitMemosPage readiness code DM-S (its fn_save_debit_memo numbering code) is governed'
);

-- ── Company fixtures for the real FA registration path ───────────────────────
INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222230', 'corporation',
  'Numbering Registry Test Corp', 'Trading', '111-222-333-030',
  'vat', 'calendar',
  'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
  'numbering@test.local', 'Juan Dela Cruz', 'President',
  '11111111-1111-1111-1111-111111111130',
  '11111111-1111-1111-1111-111111111130'
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '33333333-3333-3333-3333-333333333230',
  '22222222-2222-2222-2222-222222222230', 'HO', 'Head Office',
  'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
  '11111111-1111-1111-1111-111111111130',
  '11111111-1111-1111-1111-111111111130'
);

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES (
  '44444444-4444-4444-4444-444444444430',
  '22222222-2222-2222-2222-222222222230',
  'FY2026', '2026-01-01', '2026-12-31', true
);
INSERT INTO fiscal_periods (
  company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
SELECT
  '22222222-2222-2222-2222-222222222230',
  '44444444-4444-4444-4444-444444444430',
  m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
  make_date(2026, m, 1),
  (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
  false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name,
  account_type, normal_balance, is_postable, is_active, created_by, updated_by
) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000130', '22222222-2222-2222-2222-222222222230',
   '1600', 'Machinery & Equipment', 'asset', 'debit', true, true,
   '11111111-1111-1111-1111-111111111130', '11111111-1111-1111-1111-111111111130'),
  ('aaaaaaaa-0000-0000-0000-000000000230', '22222222-2222-2222-2222-222222222230',
   '1010', 'Cash', 'asset', 'debit', true, true,
   '11111111-1111-1111-1111-111111111130', '11111111-1111-1111-1111-111111111130'),
  ('aaaaaaaa-0000-0000-0000-000000000330', '22222222-2222-2222-2222-222222222230',
   '1650', 'Accumulated Depreciation', 'asset', 'credit', true, true,
   '11111111-1111-1111-1111-111111111130', '11111111-1111-1111-1111-111111111130'),
  ('aaaaaaaa-0000-0000-0000-000000000430', '22222222-2222-2222-2222-222222222230',
   '6200', 'Depreciation Expense', 'expense', 'debit', true, true,
   '11111111-1111-1111-1111-111111111130', '11111111-1111-1111-1111-111111111130');

INSERT INTO fixed_asset_categories (
  id, company_id, category_code, category_name,
  depreciation_method, useful_life_months, salvage_rate,
  gl_asset_account_id, gl_accum_depr_account_id, gl_depr_expense_account_id,
  created_by, updated_by
) VALUES (
  '66666666-6666-6666-6666-666666666630',
  '22222222-2222-2222-2222-222222222230',
  'MACH', 'Machinery', 'straight_line', 60, 0,
  'aaaaaaaa-0000-0000-0000-000000000130',
  'aaaaaaaa-0000-0000-0000-000000000330',
  'aaaaaaaa-0000-0000-0000-000000000430',
  '11111111-1111-1111-1111-111111111130',
  '11111111-1111-1111-1111-111111111130'
);

-- Branch-scoped FA and JE series, exactly what a registry-consistent setup makes.
INSERT INTO number_series (
  company_id, branch_id, document_type_id, document_code, prefix,
  number_length, padding, starting_number, next_number, current_sequence,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222230',
  '33333333-3333-3333-3333-333333333230',
  dt.id, dt.document_code, dt.document_code || '-2026-',
  6, 6, 1, 1, 0, true,
  '11111111-1111-1111-1111-111111111130',
  '11111111-1111-1111-1111-111111111130'
FROM ref_document_types dt
WHERE dt.document_code IN ('FA', 'JE');

-- ── Real fixed-asset registration through the RPC (was the broken 2-arg path) ─
CREATE TEMP TABLE t_fa (asset_id UUID);
INSERT INTO t_fa
SELECT fn_register_fixed_asset(jsonb_build_object(
  'company_id', '22222222-2222-2222-2222-222222222230',
  'branch_id', '33333333-3333-3333-3333-333333333230',
  'category_id', '66666666-6666-6666-6666-666666666630',
  'asset_name', 'CNC Lathe',
  'acquisition_date', '2026-07-10',
  'depreciation_start_date', '2026-07-31',
  'acquisition_cost', 60000,
  'salvage_value', 0,
  'useful_life_months', 60,
  'depreciation_method', 'straight_line',
  'credit_account_id', 'aaaaaaaa-0000-0000-0000-000000000230'
));

SELECT isnt(
  (SELECT asset_id FROM t_fa), NULL,
  'fn_register_fixed_asset succeeds end-to-end (FA + JE numbering no longer fail)'
);

SELECT ok(
  (SELECT asset_number FROM fixed_assets WHERE id = (SELECT asset_id FROM t_fa)) LIKE 'FA-2026-%',
  'the asset number is drawn from the governed branch-scoped FA series'
);

SELECT ok(
  (SELECT je.je_number
   FROM journal_entries je
   JOIN fixed_assets fa ON fa.acquisition_je_id = je.id
   WHERE fa.id = (SELECT asset_id FROM t_fa)) LIKE 'JE-2026-%',
  'the acquisition journal number is drawn from the governed branch-scoped JE series'
);

SELECT is(
  (SELECT je.status
   FROM journal_entries je
   JOIN fixed_assets fa ON fa.acquisition_je_id = je.id
   WHERE fa.id = (SELECT asset_id FROM t_fa)),
  'posted',
  'the acquisition journal posts (branch-scoped numbering did not abort the RPC)'
);

SELECT is(
  (SELECT je.reference_doc_id
   FROM journal_entries je
   JOIN fixed_assets fa ON fa.acquisition_je_id = je.id
   WHERE fa.id = (SELECT asset_id FROM t_fa)),
  (SELECT asset_id FROM t_fa),
  'the acquisition journal links back to its FA source and satisfies source integrity'
);

SELECT is(
  (SELECT COUNT(*)::INTEGER FROM journal_entry_lines jel
   JOIN fixed_assets fa ON fa.acquisition_je_id = jel.je_id
   WHERE fa.id = (SELECT asset_id FROM t_fa)),
  2,
  'the acquisition journal has both balanced posting lines'
);

-- ── The exact branch-scoped JE call the inventory posters now make resolves ──
SELECT ok(
  fn_next_document_number(
    '22222222-2222-2222-2222-222222222230',
    '33333333-3333-3333-3333-333333333230',
    'JE'
  ) LIKE 'JE-2026-%',
  'the branch-scoped JE numbering call used by inventory posters resolves and increments'
);

SELECT * FROM finish();
ROLLBACK;
