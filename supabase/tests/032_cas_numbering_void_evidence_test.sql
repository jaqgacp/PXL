-- CAS-NUMBERING-VOID-EVIDENCE-001 (PXL-DA-019)
--
-- Focused regression coverage for accountable SI numbering and immutable void
-- evidence.  The fixture deliberately combines a tiny ATP-authorized SI range
-- with an ordinary (non-ATP) JE range so both allocation modes are exercised.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(25);

-- ---------------------------------------------------------------------------
-- Owner, VAT company, branch, open periods, and accounting configuration
-- ---------------------------------------------------------------------------

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111132',
  'authenticated', 'authenticated', 'cas-evidence@test.local', '',
  NOW(), NOW(), NOW(),
  '{"provider":"email","providers":["email"]}', '{}'
);

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111132","role":"authenticated"}',
  true
);

INSERT INTO companies (
  id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period, cas_permit_no, cas_date_issued,
  address_line_1, address_line_2, city, province, zip_code,
  email, signatory_name, signatory_position, created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222232', 'corporation',
  'CAS Evidence Test Corp', 'Professional Services', '111-222-333-032',
  'vat', 'calendar', 'CAS-PERMIT-032', '2026-01-02',
  '32 Evidence Street', '', 'Makati', 'Metro Manila', '1232',
  'cas-evidence@test.local', 'Evidence Owner', 'President',
  auth.uid(), auth.uid()
);

UPDATE user_company_memberships
SET role = 'owner'
WHERE user_id = '11111111-1111-1111-1111-111111111132'
  AND company_id = '22222222-2222-2222-2222-222222222232';

SELECT is(
  (SELECT role FROM user_company_memberships
   WHERE user_id = auth.uid()
     AND company_id = '22222222-2222-2222-2222-222222222232'),
  'owner',
  'the fixture user is the company owner'
);

INSERT INTO branches (
  id, company_id, branch_code, branch_name, cas_permit_no, cas_date_issued,
  address_line_1, address_line_2, city, province, zip_code,
  created_by, updated_by
) VALUES (
  '33333333-3333-3333-3333-333333333232',
  '22222222-2222-2222-2222-222222222232',
  'HO', 'Head Office', 'CAS-PERMIT-032-HO', '2026-01-02',
  '32 Evidence Street', '', 'Makati', 'Metro Manila', '1232',
  auth.uid(), auth.uid()
);

INSERT INTO fiscal_years (
  id, company_id, year_name, start_date, end_date, is_calendar
) VALUES (
  '44444444-4444-4444-4444-444444444432',
  '22222222-2222-2222-2222-222222222232',
  'FY2026', '2026-01-01', '2026-12-31', true
);

INSERT INTO fiscal_periods (
  company_id, fiscal_year_id, period_number, period_name,
  start_date, end_date, is_locked
)
SELECT
  '22222222-2222-2222-2222-222222222232',
  '44444444-4444-4444-4444-444444444432',
  month_no,
  TO_CHAR(MAKE_DATE(2026, month_no, 1), 'Mon YYYY'),
  MAKE_DATE(2026, month_no, 1),
  (MAKE_DATE(2026, month_no, 1) + INTERVAL '1 month - 1 day')::DATE,
  false
FROM generate_series(1, 12) AS month_no;

INSERT INTO chart_of_accounts (
  id, company_id, account_code, account_name,
  account_type, normal_balance, is_postable, is_active,
  created_by, updated_by
) VALUES
  (
    'aaaaaaaa-0000-0000-0000-000000000132',
    '22222222-2222-2222-2222-222222222232',
    '1200', 'Accounts Receivable', 'asset', 'debit', true, true,
    auth.uid(), auth.uid()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000232',
    '22222222-2222-2222-2222-222222222232',
    '2100', 'Output VAT', 'liability', 'credit', true, true,
    auth.uid(), auth.uid()
  ),
  (
    'aaaaaaaa-0000-0000-0000-000000000332',
    '22222222-2222-2222-2222-222222222232',
    '4010', 'Service Revenue', 'revenue', 'credit', true, true,
    auth.uid(), auth.uid()
  );

INSERT INTO company_accounting_config (
  company_id, ar_account_id, vat_payable_account_id,
  created_by, updated_by
) VALUES (
  '22222222-2222-2222-2222-222222222232',
  'aaaaaaaa-0000-0000-0000-000000000132',
  'aaaaaaaa-0000-0000-0000-000000000232',
  auth.uid(), auth.uid()
);

-- SI is restricted to ATP 100-101.  JE is deliberately an ordinary series:
-- no ATP bounds, starting at one.
INSERT INTO number_series (
  company_id, branch_id, document_type_id, document_code, prefix, suffix,
  number_length, padding, starting_number, next_number, current_sequence,
  atp_series_start, atp_series_end, atp_alert_threshold,
  is_active, created_by, updated_by
)
SELECT
  '22222222-2222-2222-2222-222222222232',
  '33333333-3333-3333-3333-333333333232',
  dt.id,
  dt.document_code,
  CASE dt.document_code WHEN 'SI' THEN 'SI-' ELSE 'JE-' END,
  NULL,
  6, 6,
  CASE dt.document_code WHEN 'SI' THEN 100 ELSE 1 END,
  CASE dt.document_code WHEN 'SI' THEN 100 ELSE 1 END,
  CASE dt.document_code WHEN 'SI' THEN 99 ELSE 0 END,
  CASE dt.document_code WHEN 'SI' THEN 100 ELSE NULL END,
  CASE dt.document_code WHEN 'SI' THEN 101 ELSE NULL END,
  CASE dt.document_code WHEN 'SI' THEN 1 ELSE NULL END,
  true, auth.uid(), auth.uid()
FROM ref_document_types dt
WHERE dt.document_code IN ('SI', 'JE');

INSERT INTO customers (
  id, company_id, customer_code, registered_name, tin,
  registered_address, delivery_address, created_by, updated_by
) VALUES (
  '55555555-5555-5555-5555-555555555532',
  '22222222-2222-2222-2222-222222222232',
  'C-CAS-032', 'CAS Evidence Customer', '444-555-666-032',
  'Taguig City', 'Taguig City', auth.uid(), auth.uid()
);

CREATE TEMP TABLE t_cas_ctx (key TEXT PRIMARY KEY, id UUID NOT NULL);
GRANT SELECT ON TABLE t_cas_ctx TO authenticated;

-- ---------------------------------------------------------------------------
-- Ordinary direct reservations remain sequential; an unresolved reservation
-- is evidence, not a session-wide lock that prevents the next allocation.
-- ---------------------------------------------------------------------------

SELECT is(
  fn_next_document_number(
    '22222222-2222-2222-2222-222222222232',
    '33333333-3333-3333-3333-333333333232',
    'JE'
  ),
  'JE-000001',
  'an ordinary JE series allocates its first governed number'
);

SELECT is(
  fn_next_document_number(
    '22222222-2222-2222-2222-222222222232',
    '33333333-3333-3333-3333-333333333232',
    'JE'
  ),
  'JE-000002',
  'a second direct allocation succeeds despite the first unresolved reservation'
);

SELECT is(
  (SELECT COUNT(*)::INTEGER
   FROM cas_document_number_issuances
   WHERE company_id = '22222222-2222-2222-2222-222222222232'
     AND document_code = 'JE'
     AND status = 'reserved'),
  2,
  'both unresolved JE reservations remain visible as accountable evidence'
);

-- ---------------------------------------------------------------------------
-- First SI: allocate 100, bind it to the source, post, and void it.
-- ---------------------------------------------------------------------------

INSERT INTO t_cas_ctx (key, id)
SELECT 'si1', fn_save_sales_invoice(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222232',
    'branch_id', '33333333-3333-3333-3333-333333333232',
    'date', '2026-07-12',
    'customer_id', '55555555-5555-5555-5555-555555555532',
    'customer_name_snapshot', 'CAS Evidence Customer',
    'customer_tin_snapshot', '444-555-666-032',
    'customer_address_snapshot', 'Taguig City'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Exempt professional service',
    'quantity', 1,
    'unit_price', 1000,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000332'
  ))
);

SELECT is(
  (SELECT si_number FROM sales_invoices
   WHERE id = (SELECT id FROM t_cas_ctx WHERE key = 'si1')),
  'SI-000100',
  'the first ATP-controlled invoice receives sequence 100 with frozen formatting'
);

SELECT results_eq(
  $query$
    SELECT sequence_number, document_number, status, source_table, source_id
    FROM cas_document_number_issuances
    WHERE number_series_id = (
      SELECT id FROM number_series
      WHERE company_id = '22222222-2222-2222-2222-222222222232'
        AND branch_id = '33333333-3333-3333-3333-333333333232'
        AND document_code = 'SI'
    )
      AND sequence_number = 100
  $query$,
  $expected$
    VALUES (
      100::BIGINT,
      'SI-000100'::TEXT,
      'issued'::TEXT,
      'sales_invoices'::TEXT,
      (SELECT id FROM t_cas_ctx WHERE key = 'si1')
    )
  $expected$,
  'the reservation is atomically bound to the saved SI source'
);

SELECT lives_ok(
  FORMAT(
    'SELECT fn_approve_sales_invoice(%L); SELECT fn_post_sales_invoice(%L)',
    (SELECT id FROM t_cas_ctx WHERE key = 'si1'),
    (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  ),
  'the governed invoice approves and posts through the real RPCs'
);

SELECT results_eq(
  $query$
    SELECT si.status, je.status, (si.journal_entry_id IS NOT NULL)
    FROM sales_invoices si
    JOIN journal_entries je ON je.id = si.journal_entry_id
    WHERE si.id = (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  $query$,
  $$VALUES ('posted'::TEXT, 'posted'::TEXT, true)$$,
  'posting leaves a source-linked posted journal entry'
);

SELECT lives_ok(
  FORMAT(
    'SELECT fn_void_sales_invoice(%L, NULL, %L)',
    (SELECT id FROM t_cas_ctx WHERE key = 'si1'),
    'Customer billing correction'
  ),
  'the posted invoice voids through the real RPC with an explicit reason'
);

SELECT is(
  (SELECT status FROM sales_invoices
   WHERE id = (SELECT id FROM t_cas_ctx WHERE key = 'si1')),
  'cancelled',
  'the source invoice reaches its terminal cancelled status'
);

SELECT is(
  (SELECT status FROM cas_document_number_issuances
   WHERE source_table = 'sales_invoices'
     AND source_id = (SELECT id FROM t_cas_ctx WHERE key = 'si1')),
  'voided',
  'the same immutable issuance is marked voided rather than deleted or reusable'
);

SELECT results_eq(
  $query$
    SELECT
      reason_text,
      event_actor_id,
      original_journal_entry_id,
      reversal_journal_entry_id,
      (occurred_at IS NOT NULL)
    FROM cas_document_void_events v
    WHERE source_table = 'sales_invoices'
      AND source_id = (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  $query$,
  $expected$
    SELECT
      'Customer billing correction'::TEXT,
      '11111111-1111-1111-1111-111111111132'::UUID,
      si.journal_entry_id,
      je.reversed_by_je_id,
      true
    FROM sales_invoices si
    JOIN journal_entries je ON je.id = si.journal_entry_id
    WHERE si.id = (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  $expected$,
  'void evidence freezes the reason, actor, and original/reversal JE links'
);

SELECT results_eq(
  $query$
    SELECT
      source_snapshot->>'si_number',
      source_snapshot->>'status',
      source_snapshot->>'customer_name_snapshot',
      (source_snapshot->>'total_amount')::NUMERIC
    FROM cas_document_void_events
    WHERE source_table = 'sales_invoices'
      AND source_id = (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  $query$,
  $$VALUES (
    'SI-000100'::TEXT,
    'posted'::TEXT,
    'CAS Evidence Customer'::TEXT,
    1000.00::NUMERIC
  )$$,
  'void evidence retains the pre-void source snapshot'
);

SELECT results_eq(
  $query$
    SELECT original.status, reversal.status
    FROM sales_invoices si
    JOIN journal_entries original ON original.id = si.journal_entry_id
    JOIN journal_entries reversal ON reversal.id = original.reversed_by_je_id
    WHERE si.id = (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  $query$,
  $$VALUES ('reversed'::TEXT, 'posted'::TEXT)$$,
  'the frozen void links resolve to the reversed original and posted reversal JEs'
);

SELECT throws_ok(
  FORMAT(
    'UPDATE cas_document_void_events SET reason_text = %L WHERE source_id = %L',
    'tampered reason',
    (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  ),
  'P0001', NULL,
  'void evidence is immutable even to a direct table owner statement'
);

-- ---------------------------------------------------------------------------
-- Second SI consumes 101; a third attempt fails without drifting the counter.
-- ---------------------------------------------------------------------------

INSERT INTO t_cas_ctx (key, id)
SELECT 'si2', fn_save_sales_invoice(
  NULL,
  jsonb_build_object(
    'company_id', '22222222-2222-2222-2222-222222222232',
    'branch_id', '33333333-3333-3333-3333-333333333232',
    'date', '2026-07-12',
    'customer_id', '55555555-5555-5555-5555-555555555532',
    'customer_name_snapshot', 'CAS Evidence Customer',
    'customer_tin_snapshot', '444-555-666-032',
    'customer_address_snapshot', 'Taguig City'
  ),
  jsonb_build_array(jsonb_build_object(
    'description', 'Replacement exempt professional service',
    'quantity', 1,
    'unit_price', 500,
    'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
    'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000332'
  ))
);

SELECT is(
  (SELECT si_number FROM sales_invoices
   WHERE id = (SELECT id FROM t_cas_ctx WHERE key = 'si2')),
  'SI-000101',
  'the next invoice consumes 101 and never reuses voided number 100'
);

SELECT is(
  (SELECT status FROM cas_document_number_issuances
   WHERE source_table = 'sales_invoices'
     AND source_id = (SELECT id FROM t_cas_ctx WHERE key = 'si2')),
  'issued',
  'the second SI is bound to a distinct issued-number evidence row'
);

SELECT throws_like(
  $statement$
    SELECT fn_save_sales_invoice(
      NULL,
      jsonb_build_object(
        'company_id', '22222222-2222-2222-2222-222222222232',
        'branch_id', '33333333-3333-3333-3333-333333333232',
        'date', '2026-07-12',
        'customer_id', '55555555-5555-5555-5555-555555555532',
        'customer_name_snapshot', 'CAS Evidence Customer'
      ),
      jsonb_build_array(jsonb_build_object(
        'description', 'Unauthorized number beyond ATP',
        'quantity', 1,
        'unit_price', 1,
        'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT'),
        'revenue_account_id', 'aaaaaaaa-0000-0000-0000-000000000332'
      ))
    )
  $statement$,
  '%ATP range exhausted%',
  'the third SI allocation is rejected when ATP 100-101 is exhausted'
);

SELECT results_eq(
  $query$
    SELECT current_sequence, next_number
    FROM number_series
    WHERE company_id = '22222222-2222-2222-2222-222222222232'
      AND branch_id = '33333333-3333-3333-3333-333333333232'
      AND document_code = 'SI'
  $query$,
  $$VALUES (101::BIGINT, 102::INTEGER)$$,
  'failed exhaustion does not drift the governed series counter'
);

SELECT is(
  (SELECT COUNT(*)::INTEGER
   FROM cas_document_number_issuances
   WHERE company_id = '22222222-2222-2222-2222-222222222232'
     AND document_code = 'SI'
     AND sequence_number > 101),
  0,
  'no issuance evidence is created outside the ATP-authorized range'
);

SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $statement$
    UPDATE number_series
    SET current_sequence = 100
    WHERE company_id = '22222222-2222-2222-2222-222222222232'
      AND branch_id = '33333333-3333-3333-3333-333333333232'
      AND document_code = 'SI'
  $statement$,
  'P0001', NULL,
  'an application caller cannot roll an issued counter backwards'
);

SELECT throws_ok(
  $statement$
    UPDATE number_series
    SET prefix = 'REPRINT-'
    WHERE company_id = '22222222-2222-2222-2222-222222222232'
      AND branch_id = '33333333-3333-3333-3333-333333333232'
      AND document_code = 'SI'
  $statement$,
  'P0001', NULL,
  'an application caller cannot rewrite issued number identity formatting'
);

RESET ROLE;

SELECT results_eq(
  $query$
    SELECT
      atp_series_start,
      atp_series_end,
      current_sequence,
      reserved_count::BIGINT,
      issued_count::BIGINT,
      voided_count::BIGINT,
      total_allocated_count::BIGINT,
      numbers_remaining,
      usage_percent,
      is_exhausted,
      at_or_below_alert_threshold
    FROM vw_cas_atp_usage
    WHERE company_id = '22222222-2222-2222-2222-222222222232'
      AND branch_id = '33333333-3333-3333-3333-333333333232'
      AND document_code = 'SI'
  $query$,
  $$VALUES (
    100::INTEGER, 101::INTEGER, 101::BIGINT,
    0::BIGINT, 1::BIGINT, 1::BIGINT, 2::BIGINT,
    0::BIGINT, 100.00::NUMERIC, true, true
  )$$,
  'the ATP usage view reports issued/voided counts and exhausted status from evidence'
);

SET LOCAL ROLE authenticated;

SELECT throws_ok(
  FORMAT(
    'UPDATE cas_document_number_issuances SET status = %L WHERE source_id = %L',
    'issued',
    (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  ),
  '42501', NULL,
  'authenticated callers cannot directly mutate issuance evidence'
);

SELECT throws_ok(
  FORMAT(
    'DELETE FROM cas_document_void_events WHERE source_id = %L',
    (SELECT id FROM t_cas_ctx WHERE key = 'si1')
  ),
  '42501', NULL,
  'authenticated callers cannot directly delete void evidence'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
