-- ══════════════════════════════════════════════════════════════════════════════
-- 118 — Effective-dated VAT resolution
--
-- WHAT THIS GUARDS
--   Phase 4 gave PXL one calculator but only half a governed one: withholding
--   resolved the ATC version in force on the document date, while VAT resolved
--   `WHERE vc.id = <id>` and nothing else. A superseded, deprecated, deactivated
--   or not-yet-effective VAT version still computed tax, and a code that could
--   not be resolved fell through to `exempt at 0%` in silence.
--
--   This file asserts the closed behaviour: the VAT version in force ON THE
--   DOCUMENT DATE governs, a rate change is made by succession rather than by
--   editing history, the past does not move when the future changes, and the
--   refusal is an exception rather than a silent zero. It also asserts that the
--   rule is enforced by the DATABASE — the line and header triggers, which RLS
--   lets a company member reach without any save RPC — and that the picker the
--   UI reads offers exactly what those triggers accept.
--
--   The fixture is provisioned by this file on companies it creates itself. It
--   never reads the canonical/demo seed, which was produced by the very logic
--   under test (`PXL_HOW_WE_WORK.md` §5a).
--
-- WHAT THIS DOES NOT CLAIM
--   Master-side version governance (overlap guards, immutability-after-use,
--   successor integrity) is test 039's subject and is not repeated here.
--   Percentage tax is still calculated nowhere; there is nothing to assert.
--   The company tax profile is NOT effective-dated — assertion 25 pins that gap
--   deliberately, so that closing it must come back through this file.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(25);

-- ── Identity, companies, and two invoices either side of the rate change ─────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11800000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'vat-effective@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"11800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('11800000-0000-0000-0000-0000000000c1', 'corporation', 'VAT Effective Corp',
   'Professional Services', '398-000-001-00000', 'vat', 'calendar',
   'V St', 'V Bldg', 'Makati', 'Metro Manila', '1200',
   'vat-effective@test.local', 'V Owner', 'President', auth.uid(), auth.uid()),
  ('11800000-0000-0000-0000-0000000000c2', 'corporation', 'Non-VAT Effective Corp',
   'Professional Services', '398-000-002-00000', 'non_vat', 'calendar',
   'N St', 'N Bldg', 'Makati', 'Metro Manila', '1200',
   'nonvat-effective@test.local', 'N Owner', 'President', auth.uid(), auth.uid());

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code,
                      created_by, updated_by)
VALUES ('11800000-0000-0000-0000-0000000000d1', '11800000-0000-0000-0000-0000000000c1',
        'HO', 'Head Office', 'V St', '', 'Makati', 'Metro Manila', '1200',
        auth.uid(), auth.uid());

INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
                       registered_address, delivery_address, created_by, updated_by)
VALUES ('11800000-0000-0000-0000-0000000000e1', '11800000-0000-0000-0000-0000000000c1',
        'C-1', 'Effective Date Customer', '444-555-666-081', 'Makati', 'Makati',
        auth.uid(), auth.uid());

-- One invoice inside the current VAT window, one after the rate change.
INSERT INTO sales_invoices (id, company_id, branch_id, customer_id,
                            customer_name_snapshot, customer_tin_snapshot,
                            si_number, date, status, created_by, updated_by)
VALUES
  ('11800000-0000-0000-0000-0000000000f1', '11800000-0000-0000-0000-0000000000c1',
   '11800000-0000-0000-0000-0000000000d1', '11800000-0000-0000-0000-0000000000e1',
   'Effective Date Customer', '444-555-666-081', 'SI-EARLY-1', '2026-02-10',
   'draft', auth.uid(), auth.uid()),
  ('11800000-0000-0000-0000-0000000000f2', '11800000-0000-0000-0000-0000000000c1',
   '11800000-0000-0000-0000-0000000000d1', '11800000-0000-0000-0000-0000000000e1',
   'Effective Date Customer', '444-555-666-081', 'SI-LATE-1', '2026-05-10',
   'draft', auth.uid(), auth.uid());

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — One resolver decides whether a VAT code may be used
-- ══════════════════════════════════════════════════════════════════════════════
SELECT ok(
  (SELECT p.prosrc !~ '\mvat_codes\M' AND p.prosrc !~ '\mtax_codes\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_calculate_tax'),
  'the engine no longer reads the VAT master directly');                           -- 1

SELECT ok(
  (SELECT p.prosrc ~ '\mfn_resolve_vat_code\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_calculate_tax'),
  'the engine resolves VAT through the one resolver');                             -- 2

-- The company-tax-profile rule exists in exactly one place. Before this work it
-- lived in fn_validate_company_vat_code, which the engine never called, which is
-- why the engine could compute VAT the triggers would have refused.
SELECT set_eq(
  $$SELECT p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
       AND p.prosrc ~ 'cannot use VAT-bearing code'$$,
  $$VALUES ('fn_resolve_vat_code')$$,
  'the VAT-bearing/non-VAT rule is stated once, in the resolver');                 -- 3

SELECT ok(
  (SELECT p.prosrc ~ '\mfn_resolve_vat_code\M'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_validate_company_vat_code'),
  'the trigger backstop asks the same resolver as the engine');                    -- 4

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — The VAT version in force on the document date governs
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT c.tax_amount FROM fn_calculate_tax(jsonb_build_object(
     'company_id', '11800000-0000-0000-0000-0000000000c1',
     'document_date', '2026-02-10', 'direction', 'sale', 'amount', 10000,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'))) c
    WHERE c.tax_kind = 'output_vat'),
  1200.00::numeric(15,2),
  'before the rate change a 10,000 sale carries 1,200 of output VAT');             -- 5

-- A line booked on the later invoice while the current version is still in force.
-- It is what proves, after the change, that the past does not move.
INSERT INTO sales_invoice_lines (sales_invoice_id, company_id, line_number, description,
                                 quantity, unit_price, net_amount, vat_code_id,
                                 vat_amount, total_amount)
VALUES ('11800000-0000-0000-0000-0000000000f2', '11800000-0000-0000-0000-0000000000c1',
        1, 'Booked before the rate change', 1, 10000, 10000,
        (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'), 1200, 11200);

-- ── The governed succession: close the window, add a successor version ────────
-- No historical row is edited except to close its effective window, which is the
-- documented deprecate-and-succeed workflow (migration 20260713000012).
UPDATE tax_codes SET effective_to = '2026-03-31'
WHERE code = 'VAT12-OUT' AND effective_from = DATE '1900-01-01';

INSERT INTO tax_codes (id, code, description, tax_type, rate, effective_from,
                       is_active, supersedes_tax_code_id)
SELECT '11800000-0000-0000-0000-0000000000a2', t.code, 'Output VAT 14%', t.tax_type,
       14.00, '2026-04-01', true, t.id
FROM tax_codes t WHERE t.code = 'VAT12-OUT' AND t.effective_from = DATE '1900-01-01';

UPDATE vat_codes SET effective_to = '2026-03-31'
WHERE vat_code = 'VAT-12' AND effective_from = DATE '1900-01-01';

INSERT INTO vat_codes (id, tax_code_id, vat_code, description, vat_classification,
                       transaction_type, relief_category, is_active, effective_from,
                       supersedes_vat_code_id)
SELECT '11800000-0000-0000-0000-0000000000b2', '11800000-0000-0000-0000-0000000000a2',
       v.vat_code, 'Standard 14% Output VAT', v.vat_classification,
       v.transaction_type, v.relief_category, true, '2026-04-01', v.id
FROM vat_codes v WHERE v.vat_code = 'VAT-12' AND v.effective_from = DATE '1900-01-01';

SELECT is(
  (SELECT c.tax_amount FROM fn_calculate_tax(jsonb_build_object(
     'company_id', '11800000-0000-0000-0000-0000000000c1',
     'document_date', '2026-02-10', 'direction', 'sale', 'amount', 10000,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'
                       AND effective_from = DATE '1900-01-01'))) c
    WHERE c.tax_kind = 'output_vat'),
  1200.00::numeric(15,2),
  'the superseded version still computes 12% on a document inside its window');    -- 6

SELECT is(
  (SELECT c.tax_amount FROM fn_calculate_tax(jsonb_build_object(
     'company_id', '11800000-0000-0000-0000-0000000000c1',
     'document_date', '2026-05-10', 'direction', 'sale', 'amount', 10000,
     'vat_code_id', '11800000-0000-0000-0000-0000000000b2')) c
    WHERE c.tax_kind = 'output_vat'),
  1400.00::numeric(15,2),
  'the successor version computes 14% on a document inside its window');           -- 7

-- The engine reports which tax-code version it used, so the transaction can
-- carry the exact resolved version rather than a rate someone has to re-derive.
SELECT results_eq(
  $q$SELECT c.tax_code_id, c.tax_rate, c.classification
       FROM fn_calculate_tax(jsonb_build_object(
              'company_id', '11800000-0000-0000-0000-0000000000c1',
              'document_date', '2026-05-10', 'direction', 'sale', 'amount', 10000,
              'vat_code_id', '11800000-0000-0000-0000-0000000000b2')) c
      WHERE c.tax_kind = 'output_vat'$q$,
  $$VALUES ('11800000-0000-0000-0000-0000000000a2'::uuid, 14.0000::numeric(9,4),
            'regular'::text)$$,
  'the engine returns the exact tax-code version, rate and classification it resolved'); -- 8

SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id', '11800000-0000-0000-0000-0000000000c1',
      'document_date', '2026-05-10', 'direction', 'sale', 'amount', 10000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'
                        AND effective_from = DATE '1900-01-01')))$$,
  '%is not effective on 2026-05-10%',
  'a superseded VAT version is refused after its window closes, not silently exempted'); -- 9

SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id', '11800000-0000-0000-0000-0000000000c1',
      'document_date', '2026-02-10', 'direction', 'sale', 'amount', 10000,
      'vat_code_id', '11800000-0000-0000-0000-0000000000b2'))$$,
  '%is not effective on 2026-02-10%',
  'a not-yet-effective VAT version is refused before its window opens');           -- 10

-- Classification survives the change: only the rate-bearing version moved.
SELECT results_eq(
  $q$SELECT c.classification, c.tax_amount, c.net_amount
       FROM fn_calculate_tax(jsonb_build_object(
              'company_id', '11800000-0000-0000-0000-0000000000c1',
              'document_date', '2026-05-10', 'direction', 'sale', 'amount', 7500,
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-0-EXPORT'))) c
      WHERE c.tax_kind = 'output_vat'$q$,
  $$VALUES ('zero_rated'::text, 0.00::numeric(15,2), 7500.00::numeric(15,2))$$,
  'zero-rated codes are unaffected by a regular-rate succession');                 -- 11

UPDATE vat_codes SET is_active = false WHERE vat_code = 'VAT-EXEMPT';
SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id', '11800000-0000-0000-0000-0000000000c1',
      'document_date', '2026-05-10', 'direction', 'sale', 'amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-EXEMPT')))$$,
  '%VAT-EXEMPT is inactive%',
  'a deactivated VAT code is refused on every date');                              -- 12

UPDATE vat_codes SET deprecated_at = NOW(), deprecated_reason = 'test'
WHERE vat_code = 'VAT-0-EXPORT';
SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id', '11800000-0000-0000-0000-0000000000c1',
      'document_date', '2026-05-10', 'direction', 'sale', 'amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-0-EXPORT')))$$,
  '%was deprecated on%Select its successor version.%',
  'a deprecated VAT code is refused and the message names the remedy');            -- 13

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Tax side and company tax profile
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id', '11800000-0000-0000-0000-0000000000c1',
      'document_date', '2026-02-10', 'direction', 'sale', 'amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12')))$$,
  '%is for input_vat, not output_vat%',
  'a sale cannot compute VAT from an input-VAT code');                             -- 14

SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id', '11800000-0000-0000-0000-0000000000c1',
      'document_date', '2026-02-10', 'direction', 'purchase', 'amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'
                        AND effective_from = DATE '1900-01-01')))$$,
  '%is for output_vat, not input_vat%',
  'a purchase cannot compute VAT from an output-VAT code');                        -- 15

SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id', '11800000-0000-0000-0000-0000000000c2',
      'document_date', '2026-02-10', 'direction', 'sale', 'amount', 1000,
      'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'
                        AND effective_from = DATE '1900-01-01')))$$,
  '%cannot use VAT-bearing code%',
  'a non-VAT company cannot compute VAT at a VAT-bearing rate');                   -- 16

SELECT is(
  (SELECT c.tax_amount FROM fn_calculate_tax(jsonb_build_object(
     'company_id', '11800000-0000-0000-0000-0000000000c2',
     'document_date', '2026-02-10', 'direction', 'purchase', 'amount', 1000,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-0'))) c
    WHERE c.tax_kind = 'input_vat'),
  0.00::numeric(15,2),
  'a non-VAT company may still use a zero-rate code — the framework is one, not two'); -- 17

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — The DATABASE enforces the rule, not only the save RPC
--
-- RLS lets a company member write document lines directly. The line and header
-- triggers are therefore the boundary that has to hold, and they now evaluate
-- the VAT version against the PARENT DOCUMENT'S date rather than today.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$INSERT INTO sales_invoice_lines
      (sales_invoice_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('11800000-0000-0000-0000-0000000000f2',
              '11800000-0000-0000-0000-0000000000c1', 2, 'Superseded code', 1, 1000, 1000,
              (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'
                 AND effective_from = DATE '1900-01-01'), 120, 1120)$$,
  '%Sales invoice VAT code VAT-12 is not effective on 2026-05-10%',
  'the line trigger refuses a superseded code using the invoice date, not today'); -- 18

SELECT lives_ok(
  $$INSERT INTO sales_invoice_lines
      (sales_invoice_id, company_id, line_number, description, quantity, unit_price,
       net_amount, vat_code_id, vat_amount, total_amount)
      VALUES ('11800000-0000-0000-0000-0000000000f1',
              '11800000-0000-0000-0000-0000000000c1', 1, 'In-window code', 1, 1000, 1000,
              (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'
                 AND effective_from = DATE '1900-01-01'), 120, 1120)$$,
  'the same code is accepted on an invoice dated inside its window');              -- 19

SELECT throws_like(
  $$UPDATE sales_invoices SET total_vat_amount = 1200
      WHERE id = '11800000-0000-0000-0000-0000000000f2'$$,
  '%is not effective on 2026-05-10%',
  'the header trigger re-validates every line against the document date');         -- 20

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — The picker offers exactly what the enforcer accepts
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $q$SELECT p.id FROM fn_vat_codes_asof('11800000-0000-0000-0000-0000000000c1',
                                        DATE '2026-02-10', 'output_vat') p
      WHERE p.vat_code = 'VAT-12'$q$,
  $q$SELECT id FROM vat_codes WHERE vat_code = 'VAT-12'
       AND effective_from = DATE '1900-01-01'$q$,
  'on a February document the picker offers the superseded version and only it'); -- 21

SELECT results_eq(
  $q$SELECT p.id, p.rate FROM fn_vat_codes_asof('11800000-0000-0000-0000-0000000000c1',
                                                DATE '2026-05-10', 'output_vat') p
      WHERE p.vat_code = 'VAT-12'$q$,
  $$VALUES ('11800000-0000-0000-0000-0000000000b2'::uuid, 14.00::numeric(6,2))$$,
  'on a May document the picker offers the successor version and its new rate'); -- 22

-- The invariant that keeps the UI and the database from disagreeing: nothing the
-- picker offers can be refused by the resolver.
SELECT lives_ok(
  $$SELECT fn_resolve_vat_code('11800000-0000-0000-0000-0000000000c1', p.id,
                               DATE '2026-05-10', p.transaction_type)
      FROM fn_vat_codes_asof('11800000-0000-0000-0000-0000000000c1',
                             DATE '2026-05-10') p$$,
  'every code the picker offers resolves — the UI cannot offer what the database refuses'); -- 23

SELECT is(
  (SELECT count(*)::int FROM fn_vat_codes_asof('11800000-0000-0000-0000-0000000000c2',
                                               DATE '2026-05-10') p
    WHERE p.rate <> 0),
  0, 'a non-VAT company is offered no VAT-bearing code at all');                    -- 24

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION F — The recorded gap: the company tax profile is NOT effective-dated
--
-- `companies.tax_registration` is a single scalar with no history, so this seam
-- accepts a date it cannot honour. Every profile read in tax-code validation goes
-- through it, so closing the gap is a one-function change — and it must come back
-- through this assertion, which is why the assertion exists.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  fn_company_tax_registration_asof('11800000-0000-0000-0000-0000000000c1', DATE '2000-01-01'),
  fn_company_tax_registration_asof('11800000-0000-0000-0000-0000000000c1', DATE '2040-01-01'),
  'GAP: the company tax profile is date-blind — one scalar answers every date');   -- 25

SELECT * FROM finish();
ROLLBACK;
