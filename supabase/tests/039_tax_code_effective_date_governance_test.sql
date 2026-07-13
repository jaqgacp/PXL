-- ══════════════════════════════════════════════════════════════════════════════
-- TAX-CODE-VERSION-001 - VAT / percentage-tax rate governance: one official tax
-- code may carry successive effective-dated rate versions, a used version's rate
-- and identity are frozen, and historical rates survive a statutory rate change.
-- Finding coverage: PXL-DA-010 (extend effective-date/version governance from
-- ATC codes to VAT/tax codes).
--
-- Scenario: TESTVAT output VAT is 12% through 2026-06-30 and 14% from 2026-07-01
-- (a statutory rate change under the same official code). The version in force is
-- resolved by document date; overlapping active windows and mis-ordered
-- successors are rejected; once a version has driven a posted tax-ledger row its
-- code / type / rate / effective start are immutable and it cannot be deleted;
-- an unused version stays editable; a used VAT code cannot be re-pointed to a
-- different tax code; and the historical 12% version keeps its rate after the
-- 14% successor exists.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- ── Identity ────────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11111111-1111-1111-1111-1111111111d0',
        'authenticated', 'authenticated', 'harness-taxver@test.local', '',
        now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-1111111111d0","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('22222222-2222-2222-2222-2222222222d0', 'corporation',
        'Tax Version Test Corp', 'Trading', '111-222-333-D10',
        'vat', 'calendar',
        'Unit 1', 'Test Bldg', 'Makati', 'Metro Manila', '1200',
        'harness-taxver@test.local', 'Juan Dela Cruz', 'President',
        auth.uid(), auth.uid());

-- ── Governance columns present ───────────────────────────────────────────────────
SELECT has_column('tax_codes', 'effective_from',
  'tax_codes carries an effective_from governance column');
SELECT has_column('vat_codes', 'effective_from',
  'vat_codes carries an effective_from governance column');
SELECT hasnt_index('public', 'tax_codes', 'tax_codes_code_key',
  'the global unique key on tax_codes.code is replaced by version-aware uniqueness');

-- ── Version-aware uniqueness: successive effective-dated versions of one code ─────
INSERT INTO tax_codes (id, code, description, tax_type, rate, effective_from, effective_to)
VALUES ('aaaaaaaa-0000-0000-0000-0000000000a1', 'TESTVAT', 'Output VAT (v1 12%)',
        'vat', 12.00, DATE '1900-01-01', DATE '2026-06-30');

SELECT lives_ok($$
  INSERT INTO tax_codes (id, code, description, tax_type, rate,
                         effective_from, supersedes_tax_code_id)
  VALUES ('aaaaaaaa-0000-0000-0000-0000000000a2', 'TESTVAT', 'Output VAT (v2 14%)',
          'vat', 14.00, DATE '2026-07-01', 'aaaaaaaa-0000-0000-0000-0000000000a1')
$$, 'a successor version of the same official tax code is accepted');

SELECT throws_ok($$
  INSERT INTO tax_codes (code, description, tax_type, rate, effective_from)
  VALUES ('TESTVAT', 'dup start', 'vat', 15.00, DATE '2026-07-01')
$$, NULL, NULL, 'a duplicate (code, effective_from) version is rejected');

-- ── Overlap + successor-ordering integrity ───────────────────────────────────────
SELECT throws_ok($$
  INSERT INTO tax_codes (code, description, tax_type, rate, effective_from)
  VALUES ('TESTVAT', 'overlaps v1', 'vat', 16.00, DATE '2026-01-01')
$$, NULL, NULL, 'an active version overlapping an existing active window is rejected');

SELECT throws_ok($$
  INSERT INTO tax_codes (id, code, description, tax_type, rate,
                         effective_from, supersedes_tax_code_id)
  VALUES ('aaaaaaaa-0000-0000-0000-0000000000a3', 'TESTVAT', 'bad successor',
          'vat', 18.00, DATE '1899-01-01', 'aaaaaaaa-0000-0000-0000-0000000000a1')
$$, NULL, NULL, 'a successor that starts before its predecessor is rejected');

-- ── As-of resolution by document date ────────────────────────────────────────────
SELECT is(fn_tax_code_version_asof('TESTVAT', DATE '2026-03-01'),
          'aaaaaaaa-0000-0000-0000-0000000000a1'::uuid,
          'a March 2026 document resolves to the 12% version');
SELECT is(fn_tax_code_version_asof('TESTVAT', DATE '2026-08-01'),
          'aaaaaaaa-0000-0000-0000-0000000000a2'::uuid,
          'an August 2026 document resolves to the 14% successor');

-- ── Establish posted usage of v1 through the tax ledger ──────────────────────────
INSERT INTO tax_detail_entries (company_id, source_doc_type, source_doc_id, tax_kind,
                                tax_code_id, tax_base, tax_rate, tax_amount,
                                posting_date, document_date)
VALUES ('22222222-2222-2222-2222-2222222222d0', 'SI',
        '99999999-9999-9999-9999-9999999999d0', 'output_vat',
        'aaaaaaaa-0000-0000-0000-0000000000a1', 1000.00, 12.00, 120.00,
        DATE '2026-03-01', DATE '2026-03-01');

SELECT ok(fn_tax_code_used('aaaaaaaa-0000-0000-0000-0000000000a1'),
  'a tax code referenced by a posted tax-ledger row reads as used');

-- ── Immutability after use ───────────────────────────────────────────────────────
SELECT throws_ok($$
  UPDATE tax_codes SET rate = 13.00 WHERE id = 'aaaaaaaa-0000-0000-0000-0000000000a1'
$$, NULL, NULL, 'the rate of a used tax code is frozen');

SELECT throws_ok($$
  UPDATE tax_codes SET effective_from = DATE '1901-01-01'
  WHERE id = 'aaaaaaaa-0000-0000-0000-0000000000a1'
$$, NULL, NULL, 'the effective start of a used tax code is frozen');

SELECT throws_ok($$
  DELETE FROM tax_codes WHERE id = 'aaaaaaaa-0000-0000-0000-0000000000a1'
$$, NULL, NULL, 'a used tax code cannot be deleted');

-- ── Unused successor stays editable ──────────────────────────────────────────────
SELECT lives_ok($$
  UPDATE tax_codes SET description = 'Output VAT (v2 14% revised)'
  WHERE id = 'aaaaaaaa-0000-0000-0000-0000000000a2'
$$, 'an unused tax code version remains editable');

-- ── VAT code mapping is frozen once the VAT code is used ──────────────────────────
INSERT INTO tax_codes (id, code, description, tax_type, rate)
VALUES ('bbbbbbbb-0000-0000-0000-0000000000b1', 'TESTVATB', 'Input VAT B', 'vat', 12.00);
INSERT INTO vat_codes (id, tax_code_id, vat_code, description, vat_classification, transaction_type)
VALUES ('cccccccc-0000-0000-0000-0000000000c1',
        'bbbbbbbb-0000-0000-0000-0000000000b1', 'TESTVC-IN', 'Input VAT B code',
        'regular', 'input_vat');
INSERT INTO tax_detail_entries (company_id, source_doc_type, source_doc_id, tax_kind,
                                vat_code_id, tax_base, tax_rate, tax_amount,
                                posting_date, document_date)
VALUES ('22222222-2222-2222-2222-2222222222d0', 'VB',
        '99999999-9999-9999-9999-9999999999d1', 'input_vat',
        'cccccccc-0000-0000-0000-0000000000c1', 500.00, 12.00, 60.00,
        DATE '2026-03-01', DATE '2026-03-01');

SELECT ok(fn_tax_code_used('bbbbbbbb-0000-0000-0000-0000000000b1'),
  'a tax code used through one of its VAT codes reads as used');

SELECT throws_ok($$
  UPDATE vat_codes SET vat_classification = 'exempt'
  WHERE id = 'cccccccc-0000-0000-0000-0000000000c1'
$$, NULL, NULL, 'the classification of a used VAT code is frozen');

-- ── Historical rate survives a statutory rate change ─────────────────────────────
UPDATE tax_codes SET is_active = false,
       deprecated_at = now(), deprecated_reason = 'Superseded by 14% version'
WHERE id = 'aaaaaaaa-0000-0000-0000-0000000000a1';

SELECT is((SELECT rate FROM tax_codes WHERE id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
          12.00::numeric,
          'the historical 12% version keeps its rate after the 14% successor and deprecation');

SELECT * FROM finish();
ROLLBACK;
