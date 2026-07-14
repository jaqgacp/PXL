-- F2307-MONTHLY-001 - Form 2307 issued month-of-quarter breakdown
--
-- PXL-AUD-040: certificate lines must retain the 1st/2nd/3rd month income
-- payment split required by the official Form 2307, while quarter totals,
-- snapshot evidence, and superseded-version history remain intact.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111244',
        'authenticated', 'authenticated', 'harness-2307-month@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111244","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222244', 'corporation',
        'Form 2307 Monthly Corp', 'Professional Services', '111-222-333-244',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-2307-month@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333244',
        '22222222-2222-2222-2222-222222222244', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444244',
        '22222222-2222-2222-2222-222222222244',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (id, company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
VALUES
  ('44444444-0000-0000-0000-000000000241',
   '22222222-2222-2222-2222-222222222244',
   '44444444-4444-4444-4444-444444444244',
   1, 'Jan 2026', '2026-01-01', '2026-01-31', false),
  ('44444444-0000-0000-0000-000000000242',
   '22222222-2222-2222-2222-222222222244',
   '44444444-4444-4444-4444-444444444244',
   2, 'Feb 2026', '2026-02-01', '2026-02-28', false),
  ('44444444-0000-0000-0000-000000000243',
   '22222222-2222-2222-2222-222222222244',
   '44444444-4444-4444-4444-444444444244',
   3, 'Mar 2026', '2026-03-01', '2026-03-31', false);

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666244',
        '22222222-2222-2222-2222-222222222244', 'SUPP-MONTH',
        'Monthly 2307 Supplier Corp', '777-888-999-244',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);

CREATE FUNCTION pg_temp.add_ewt(p_doc_date date, p_base numeric, p_withheld numeric)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name, income_nature
  )
  VALUES (
    '22222222-2222-2222-2222-222222222244',
    '33333333-3333-3333-3333-333333333244',
    'PV', gen_random_uuid(), 'ewt_payable',
    (SELECT id FROM atc_codes WHERE code = 'WC140'),
    p_base, 2.00, p_withheld,
    (SELECT id FROM fiscal_periods
     WHERE company_id = '22222222-2222-2222-2222-222222222244'
       AND p_doc_date BETWEEN start_date AND end_date),
    p_doc_date, p_doc_date,
    '66666666-6666-6666-6666-666666666244',
    '777-888-999-244',
    'Monthly 2307 Supplier Corp',
    'Professional fees'
  );
$$;

SELECT pg_temp.add_ewt('2026-01-15', 10000, 200);
SELECT pg_temp.add_ewt('2026-02-15', 15000, 300);
SELECT pg_temp.add_ewt('2026-03-15',  5000, 100);

SELECT lives_ok(
  $$SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222244', 2026, 1)$$,
  'Form 2307 generation succeeds for a supplier with EWT in all three months');

INSERT INTO t_ctx
SELECT 'v1', id FROM form_2307_issuances
WHERE company_id = '22222222-2222-2222-2222-222222222244'
  AND supplier_id = '66666666-6666-6666-6666-666666666244'
  AND tax_year = 2026
  AND tax_quarter = 1;

SELECT results_eq(
  $q$SELECT total_tax_base, total_ewt
     FROM form_2307_issuances
     WHERE id = (SELECT id FROM t_ctx WHERE key = 'v1')$q$,
  $$VALUES (30000.00::numeric(15,2), 600.00::numeric(15,2))$$,
  'certificate header keeps the quarter totals');

SELECT results_eq(
  $q$SELECT atc_code, nature_of_income,
            month_1_tax_base, month_1_tax_withheld,
            month_2_tax_base, month_2_tax_withheld,
            month_3_tax_base, month_3_tax_withheld,
            tax_base, tax_withheld
     FROM form_2307_issuance_lines
     WHERE issuance_id = (SELECT id FROM t_ctx WHERE key = 'v1')$q$,
  $$VALUES ('WC140'::text, 'Professional fees'::text,
            10000.00::numeric(15,2), 200.00::numeric(15,2),
            15000.00::numeric(15,2), 300.00::numeric(15,2),
             5000.00::numeric(15,2), 100.00::numeric(15,2),
            30000.00::numeric(15,2), 600.00::numeric(15,2))$$,
  'certificate line retains 1st/2nd/3rd month base and withheld columns');

SELECT lives_ok(
  $$SELECT fn_update_form_2307_issued_status((SELECT id FROM t_ctx WHERE key = 'v1'), 'sent', '2026-04-05')$$,
  'sent status creates immutable report snapshot evidence');

SELECT results_eq(
  $q$SELECT (line->>'month_1_tax_base')::numeric(15,2),
            (line->>'month_2_tax_base')::numeric(15,2),
            (line->>'month_3_tax_base')::numeric(15,2),
            (line->>'tax_base')::numeric(15,2)
     FROM report_snapshots rs
     CROSS JOIN LATERAL jsonb_array_elements(rs.source_payload -> 'certificate_lines') AS line
     WHERE rs.source_table = 'form_2307_issuances'
       AND rs.source_id = (SELECT id FROM t_ctx WHERE key = 'v1')
       AND rs.snapshot_status = 'sent'$q$,
  $$VALUES (10000.00::numeric(15,2), 15000.00::numeric(15,2),
             5000.00::numeric(15,2), 30000.00::numeric(15,2))$$,
  'sent snapshot payload freezes the monthly certificate columns');

SELECT pg_temp.add_ewt('2026-03-20', 2500, 50);

SELECT lives_ok(
  $$INSERT INTO t_ctx
    SELECT 'v2', fn_supersede_form_2307_issued((SELECT id FROM t_ctx WHERE key = 'v1'), 'late March payment')$$,
  'supersede regenerates a new version from current EWT detail');

SELECT results_eq(
  $q$SELECT version, total_tax_base, total_ewt
     FROM form_2307_issuances
     WHERE id = (SELECT id FROM t_ctx WHERE key = 'v2')$q$,
  $$VALUES (2, 32500.00::numeric(15,2), 650.00::numeric(15,2))$$,
  'superseded replacement header includes the late March withholding');

SELECT results_eq(
  $q$SELECT old_line.month_3_tax_base, old_line.month_3_tax_withheld,
            new_line.month_3_tax_base, new_line.month_3_tax_withheld
     FROM form_2307_issuance_lines old_line
     CROSS JOIN form_2307_issuance_lines new_line
     WHERE old_line.issuance_id = (SELECT id FROM t_ctx WHERE key = 'v1')
       AND new_line.issuance_id = (SELECT id FROM t_ctx WHERE key = 'v2')$q$,
  $$VALUES (5000.00::numeric(15,2), 100.00::numeric(15,2),
            7500.00::numeric(15,2), 150.00::numeric(15,2))$$,
  'superseded certificate preserves old monthly evidence while the new version refreshes month 3');

SELECT * FROM finish();
ROLLBACK;
