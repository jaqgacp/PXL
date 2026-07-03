-- ══════════════════════════════════════════════════════════════════════════════
-- F2307-SUPERSEDE-001 - Certificate Version/Supersede Workflow (PXL-AUD-015)
--
-- A sent certificate is locked from regeneration, but withholding can change
-- after issuance. fn_supersede_form_2307_issued must generate a new version
-- from current EWT detail, preserve the old certificate (status 'superseded',
-- lines intact) as evidence, link both directions, and keep exactly one
-- active certificate per company/supplier/quarter.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

-- ── Identity ───────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-111111111121',
        'authenticated', 'authenticated', 'harness-2307ss@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111121","role":"authenticated"}', true);

-- ── VAT company + setup ────────────────────────────────────────────────────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222231', 'corporation',
        '2307 Supersede Test Corp', 'Software Services', '111-222-333-011',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-2307ss@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('33333333-3333-3333-3333-333333333341',
        '22222222-2222-2222-2222-222222222231', 'HO', 'Head Office',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('44444444-4444-4444-4444-444444444461',
        '22222222-2222-2222-2222-222222222231',
        'FY2026', '2026-01-01', '2026-12-31', true);

INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
                            start_date, end_date, is_locked)
SELECT '22222222-2222-2222-2222-222222222231',
       '44444444-4444-4444-4444-444444444461',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
       false
FROM generate_series(1, 12) AS m;

INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
                               account_type, normal_balance, is_postable, is_active,
                               created_by, updated_by)
VALUES
  ('aaaaaaaa-0000-0000-0000-000000000081', '22222222-2222-2222-2222-222222222231',
   '1010', 'Cash in Bank',              'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000082', '22222222-2222-2222-2222-222222222231',
   '2010', 'Accounts Payable',          'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000083', '22222222-2222-2222-2222-222222222231',
   '2150', 'EWT Payable',               'liability', 'credit', true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000084', '22222222-2222-2222-2222-222222222231',
   '1300', 'Input VAT',                 'asset',     'debit',  true, true, auth.uid(), auth.uid()),
  ('aaaaaaaa-0000-0000-0000-000000000085', '22222222-2222-2222-2222-222222222231',
   '5010', 'Professional Fees Expense', 'expense',   'debit',  true, true, auth.uid(), auth.uid());

INSERT INTO company_accounting_config (company_id, ap_account_id,
        default_cash_account_id, ewt_payable_account_id, input_vat_account_id,
        created_by, updated_by)
VALUES ('22222222-2222-2222-2222-222222222231',
        'aaaaaaaa-0000-0000-0000-000000000082',
        'aaaaaaaa-0000-0000-0000-000000000081',
        'aaaaaaaa-0000-0000-0000-000000000083',
        'aaaaaaaa-0000-0000-0000-000000000084',
        auth.uid(), auth.uid());

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
                           number_length, starting_number, next_number,
                           is_active, created_by, updated_by)
SELECT '22222222-2222-2222-2222-222222222231',
       '33333333-3333-3333-3333-333333333341',
       rdt.id, rdt.document_code || '-', 6, 1, 1, true, auth.uid(), auth.uid()
FROM ref_document_types rdt
WHERE rdt.document_code IN ('VB', 'PV');

INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
                       registered_address, created_by, updated_by)
VALUES ('66666666-6666-6666-6666-666666666672',
        '22222222-2222-2222-2222-222222222231', 'SUPP-001',
        'Supersede Supplier Corp', '777-888-999-011',
        'Supplier HQ, Pasig', auth.uid(), auth.uid());

-- ── VB 11,200 + PV helper (EWT 2% on explicit 5,000 base per PV) ───────────────
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
GRANT SELECT ON t_ctx TO authenticated;

INSERT INTO t_ctx
SELECT 'vb', fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id',              '22222222-2222-2222-2222-222222222231',
    'branch_id',               '33333333-3333-3333-3333-333333333341',
    'supplier_id',             '66666666-6666-6666-6666-666666666672',
    'supplier_name_snapshot',  'Supersede Supplier Corp',
    'supplier_tin_snapshot',   '777-888-999-011',
    'supplier_invoice_number', 'SUP-INV-0011',
    'bill_date',               '2026-01-10'
  ),
  jsonb_build_array(jsonb_build_object(
    'description',        'Contractor services',
    'quantity',           1,
    'unit_price',         10000,
    'vat_code_id',        (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12'),
    'expense_account_id', 'aaaaaaaa-0000-0000-0000-000000000085'
  )));

SELECT fn_approve_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));
SELECT fn_post_vendor_bill((SELECT id FROM t_ctx WHERE key='vb'));

CREATE FUNCTION pg_temp.mk_pv(p_key text, p_date date)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  v_id := fn_save_payment_voucher(NULL,
    jsonb_build_object(
      'company_id',             '22222222-2222-2222-2222-222222222231',
      'branch_id',              '33333333-3333-3333-3333-333333333341',
      'supplier_id',            '66666666-6666-6666-6666-666666666672',
      'supplier_name_snapshot', 'Supersede Supplier Corp',
      'supplier_tin_snapshot',  '777-888-999-011',
      'voucher_date',           p_date::text,
      'total_amount',           5500,
      'total_ewt',              100
    ),
    jsonb_build_array(jsonb_build_object(
      'vendor_bill_id',    (SELECT id FROM t_ctx WHERE key='vb'),
      'payment_amount',    5500,
      'ewt_amount',        100,
      'atc_code_id',       (SELECT id FROM atc_codes WHERE code = 'WC140'),
      'ewt_tax_base',      5000,
      'ewt_income_nature', 'Contractor services'
    )));
  PERFORM fn_post_payment_voucher(v_id);
  INSERT INTO t_ctx VALUES (p_key, v_id);
END;
$$;

-- ── Generate after first PV, send, then a late PV lands in the quarter ─────────
SELECT pg_temp.mk_pv('pv1', '2026-02-05');
SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222231', 2026, 1);

INSERT INTO t_ctx
SELECT 'v1', id FROM form_2307_issuances
WHERE company_id = '22222222-2222-2222-2222-222222222231'
  AND tax_year = 2026 AND tax_quarter = 1;

SELECT fn_update_form_2307_issued_status((SELECT id FROM t_ctx WHERE key='v1'), 'sent', '2026-04-05');

SELECT results_eq(
  format($q$SELECT report_type, snapshot_status, snapshot_version, period_start,
                 period_end, source_row_count, length(source_hash)
          FROM report_snapshots
          WHERE source_table = 'form_2307_issuances'
            AND source_id = %L$q$, (SELECT id FROM t_ctx WHERE key='v1')),
  $$VALUES ('FORM_2307_ISSUED'::text, 'sent'::text, 1, '2026-01-01'::date,
            '2026-03-31'::date, 1, 64)$$,
  'sent certificate creates an immutable report snapshot with source hash');

SELECT throws_like(
  format($q$UPDATE form_2307_issuances SET total_ewt = 999
          WHERE id = %L$q$, (SELECT id FROM t_ctx WHERE key='v1')),
  '%immutable report snapshot%',
  'sent certificate amounts cannot be mutated after snapshot');

SELECT pg_temp.mk_pv('pv2', '2026-03-05');

-- Regeneration still refuses to touch the sent certificate
SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222231', 2026, 1);
SELECT is(
  (SELECT status || '|' || total_ewt::text FROM form_2307_issuances
   WHERE id = (SELECT id FROM t_ctx WHERE key='v1')),
  'sent|100.00',
  'sent certificate remains locked from regeneration after the late PV');

-- ── Supersede: new version from current detail, old preserved ──────────────────
INSERT INTO t_ctx
SELECT 'v2', fn_supersede_form_2307_issued(
  (SELECT id FROM t_ctx WHERE key='v1'), 'Late PV posted for the quarter');

SELECT is(
  (SELECT status FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='v1')),
  'superseded', 'old certificate moves to superseded status');

SELECT ok(
  (SELECT superseded_at IS NOT NULL
      AND superseded_by_issuance_id = (SELECT id FROM t_ctx WHERE key='v2')
   FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='v1')),
  'old certificate records when it was superseded and by which version');

SELECT is(
  (SELECT version FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='v2')),
  2, 'replacement certificate is version 2');

SELECT is(
  (SELECT supersedes_issuance_id FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='v2')),
  (SELECT id FROM t_ctx WHERE key='v1'),
  'replacement certificate links back to the version it supersedes');

SELECT is(
  (SELECT status || '|' || total_ewt::text || '|' || total_tax_base::text
   FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='v2')),
  'generated|200.00|10000.00',
  'version 2 is generated from current EWT detail: 200.00 withheld on 10,000.00');

SELECT results_eq(
  format($q$SELECT atc_code, tax_base, tax_withheld FROM form_2307_issuance_lines
          WHERE issuance_id = %L$q$, (SELECT id FROM t_ctx WHERE key='v2')),
  $$VALUES ('WC140'::text, 10000.00::numeric, 200.00::numeric)$$,
  'version 2 carries one refreshed ATC line');

SELECT results_eq(
  format($q$SELECT atc_code, tax_base, tax_withheld FROM form_2307_issuance_lines
          WHERE issuance_id = %L$q$, (SELECT id FROM t_ctx WHERE key='v1')),
  $$VALUES ('WC140'::text, 5000.00::numeric, 100.00::numeric)$$,
  'superseded certificate keeps its original lines as evidence');

SELECT is(
  (SELECT count(*)::int FROM form_2307_issuances
   WHERE company_id = '22222222-2222-2222-2222-222222222231'
     AND tax_year = 2026 AND tax_quarter = 1 AND status <> 'superseded'),
  1, 'exactly one active certificate exists for the supplier/quarter');

-- ── Regeneration refreshes only the active version ─────────────────────────────
SELECT lives_ok(
  $$SELECT fn_generate_form_2307_issued('22222222-2222-2222-2222-222222222231', 2026, 1)$$,
  'quarter regeneration after supersede refreshes the active version');

SELECT is(
  (SELECT status || '|' || total_ewt::text FROM form_2307_issuances
   WHERE id = (SELECT id FROM t_ctx WHERE key='v1')),
  'superseded|100.00',
  'regeneration never resurrects or alters the superseded certificate');

-- ── Negatives ──────────────────────────────────────────────────────────────────
SELECT throws_like(
  format($q$SELECT fn_supersede_form_2307_issued(%L)$q$, (SELECT id FROM t_ctx WHERE key='v2')),
  '%Only sent or acknowledged%',
  'a generated certificate cannot be superseded (regenerate instead)');

SELECT throws_like(
  format($q$SELECT fn_supersede_form_2307_issued(%L)$q$, (SELECT id FROM t_ctx WHERE key='v1')),
  '%Only sent or acknowledged%',
  'an already-superseded certificate cannot be superseded again');

SELECT lives_ok(
  format($q$SELECT fn_update_form_2307_issued_status(%L, 'sent', '2026-04-10')$q$,
         (SELECT id FROM t_ctx WHERE key='v2')),
  'replacement certificate can be sent after generated-state negative checks');

SELECT results_eq(
  format($q$SELECT report_type, snapshot_status, snapshot_version, period_start,
                 period_end, source_row_count, length(source_hash)
          FROM report_snapshots
          WHERE source_table = 'form_2307_issuances'
            AND source_id = %L$q$, (SELECT id FROM t_ctx WHERE key='v2')),
  $$VALUES ('FORM_2307_ISSUED'::text, 'sent'::text, 2, '2026-01-01'::date,
            '2026-03-31'::date, 1, 64)$$,
  'sent replacement certificate creates a separate versioned snapshot');

SET LOCAL ROLE authenticated;
-- UPDATE policy USING (false) hides every row: the direct write silently
-- matches nothing instead of erroring.
UPDATE form_2307_issuances SET status = 'generated'
WHERE id = (SELECT id FROM t_ctx WHERE key='v1');
SELECT is(
  (SELECT status FROM form_2307_issuances WHERE id = (SELECT id FROM t_ctx WHERE key='v1')),
  'superseded',
  'direct un-superseding through the table has no effect (RLS hides the row)');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
