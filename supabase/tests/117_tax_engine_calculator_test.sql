-- ══════════════════════════════════════════════════════════════════════════════
-- 117 — Tax Engine calculator (Delivery Plan Phase 4, PAD-001)
--
-- WHAT THIS GUARDS
--   `fn_calculate_tax` is the only function in PXL that turns a governed tax
--   rate into a tax amount. This file asserts the engine's own behaviour from
--   first principles, on a company it provisions itself through the current
--   production RPCs. It never reads the canonical/demo seed — that data was
--   produced by earlier logic and can encode the very defect under test
--   (`PXL_HOW_WE_WORK.md` §5a).
--
--   Test 090 asserts the STRUCTURAL claim (exactly one calculator exists, and
--   the posting layer is not it) and proves the eleven migrated callers still
--   produce identical output. This file asserts the ARITHMETIC claim: that the
--   one calculator is right, including the cases the seven duplicated
--   calculators disagreed about or never handled.
--
-- WHAT THIS DOES NOT CLAIM
--   Percentage tax. The engine does not calculate it and neither did anything
--   before it; no document reaches it. Asserting a PT branch here would be
--   asserting foundation with no consumer.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(31);

-- ── Fresh tenant, provisioned through the production path ────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11700000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'tax-engine-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"11700000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('11700000-0000-0000-0000-0000000000b1', 'corporation', 'Tax Engine Test Corp',
        'Professional Services', '397-000-001-00000', 'vat', 'calendar',
        'T St', 'T Bldg', 'Makati', 'Metro Manila', '1200',
        'tax-engine-owner@test.local', 'T Owner', 'President', auth.uid(), auth.uid());

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION A — VAT, exclusive pricing
-- ══════════════════════════════════════════════════════════════════════════════
CREATE TEMP VIEW v_ctx AS SELECT '11700000-0000-0000-0000-0000000000b1'::uuid AS company_id;

SELECT results_eq(
  $q$SELECT c.tax_kind, c.classification, c.net_amount, c.tax_rate, c.tax_amount, c.gross_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'sale', 'amount', 10000,
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-12'))) c$q$,
  $$VALUES ('output_vat'::text, 'regular'::text, 10000.00::numeric(15,2),
            12.0000::numeric(9,4), 1200.00::numeric(15,2), 11200.00::numeric(15,2))$$,
  'VAT-exclusive: 10,000 net grosses up to 11,200 with 1,200 output VAT');          -- 1

SELECT results_eq(
  $q$SELECT c.tax_kind, c.net_amount, c.tax_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'purchase', 'amount', 5000,
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='IVAT-12'))) c$q$,
  $$VALUES ('input_vat'::text, 5000.00::numeric(15,2), 600.00::numeric(15,2))$$,
  'the purchase side yields input VAT from the same one calculator');               -- 2

SELECT results_eq(
  $q$SELECT c.classification, c.net_amount, c.tax_amount, c.gross_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'sale', 'amount', 7500,
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-0-EXPORT'))) c$q$,
  $$VALUES ('zero_rated'::text, 7500.00::numeric(15,2), 0.00::numeric(15,2), 7500.00::numeric(15,2))$$,
  'zero-rated: the base is carried, the tax is zero, the gross does not move');     -- 3

SELECT results_eq(
  $q$SELECT c.classification, c.net_amount, c.tax_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'sale', 'amount', 3300,
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-EXEMPT'))) c$q$,
  $$VALUES ('exempt'::text, 3300.00::numeric(15,2), 0.00::numeric(15,2))$$,
  'exempt: the base is carried and no tax is computed');                            -- 4

-- An absent VAT code is exempt at zero, exactly as all seven calculators
-- behaved before PAD-001. This is the case a stricter engine would have broken.
SELECT results_eq(
  $q$SELECT c.classification, c.tax_rate, c.net_amount, c.tax_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'sale', 'amount', 999)) c$q$,
  $$VALUES ('exempt'::text, 0.0000::numeric(9,4), 999.00::numeric(15,2), 0.00::numeric(15,2))$$,
  'a line with no VAT code is exempt at 0% and keeps its full amount as net');      -- 5

SELECT is(
  (SELECT count(*)::int FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'sale', 'amount', 100)) c),
  1, 'with no ATC supplied the engine returns exactly one component');              -- 6

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION B — VAT, inclusive pricing
--
-- Before PAD-001 exactly ONE of the seven calculators implemented this, so six
-- document types could not price tax-inclusively at all. It is now one code
-- path reached by every caller.
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $q$SELECT c.net_amount, c.tax_amount, c.gross_amount, c.price_basis
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'sale', 'amount', 11200, 'price_basis', 'inclusive',
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-12'))) c$q$,
  $$VALUES (10000.00::numeric(15,2), 1200.00::numeric(15,2),
            11200.00::numeric(15,2), 'inclusive'::text)$$,
  'VAT-inclusive: 11,200 gross backs out to 10,000 net + 1,200 VAT');               -- 7

-- The residual rule: net + VAT must reconstitute the quoted price exactly, even
-- where the division does not land on a centavo. 1,000.00 / 1.12 = 892.857...
SELECT results_eq(
  $q$SELECT c.net_amount, c.tax_amount, (c.net_amount + c.tax_amount)
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'sale', 'amount', 1000, 'price_basis', 'inclusive',
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-12'))) c$q$,
  $$VALUES (892.86::numeric(15,2), 107.14::numeric(15,2), 1000.00::numeric)$$,
  'inclusive VAT is the residual, so net + VAT reconstitutes the quoted price');    -- 8

SELECT results_eq(
  $q$SELECT c.net_amount, c.tax_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'sale', 'amount', 5000, 'price_basis', 'inclusive',
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-EXEMPT'))) c$q$,
  $$VALUES (5000.00::numeric(15,2), 0.00::numeric(15,2))$$,
  'inclusive pricing on an exempt line backs nothing out — the price IS the net'); -- 9

SELECT results_eq(
  $q$SELECT c.net_amount, c.tax_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'sale', 'amount', 5000, 'price_basis', 'inclusive',
              'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-0-EXPORT'))) c$q$,
  $$VALUES (5000.00::numeric(15,2), 0.00::numeric(15,2))$$,
  'inclusive pricing on a zero-rated line backs nothing out either');               -- 10

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION C — Rounding
-- ══════════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT c.tax_amount FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'sale', 'amount', 100.05,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-12'))) c),
  12.01::numeric(15,2),
  '100.05 at 12% rounds to 12.01 — the figure every caller produced before');       -- 11

SELECT is(
  (SELECT c.tax_amount FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'sale', 'amount', 0.04,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-12'))) c),
  0.00::numeric(15,2), 'a base too small to produce a centavo of VAT yields 0.00'); -- 12

SELECT is(
  (SELECT c.net_amount FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'sale', 'amount', 100.005,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-12'))) c),
  100.01::numeric(15,2), 'a sub-centavo amount is rounded to 2dp before any tax');  -- 13

SELECT is(
  (SELECT c.tax_amount FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'sale', 'amount', 0,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='VAT-12'))) c),
  0.00::numeric(15,2), 'a zero line produces zero tax, not NULL');                  -- 14

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION D — Withholding by ATC, and the governed effective-date window
-- ══════════════════════════════════════════════════════════════════════════════
SELECT results_eq(
  $q$SELECT c.tax_kind, c.atc_code, c.tax_base, c.tax_rate, c.tax_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'purchase', 'amount', 5000,
              'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC140'))) c
      WHERE c.tax_kind = 'ewt'$q$,
  $$VALUES ('ewt'::text, 'WC140'::text, 5000.00::numeric(15,2),
            2.0000::numeric(9,4), 100.00::numeric(15,2))$$,
  'EWT by ATC: the base defaults to the VAT-exclusive net and the rate governs'); -- 15

SELECT is(
  (SELECT count(*)::int FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'purchase', 'amount', 5000,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
     'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC140'))) c),
  2, 'a VAT-and-withholding line returns exactly two components in one call');      -- 16

-- Withholding is computed on the VAT-EXCLUSIVE base, never the gross. This is
-- the single most consequential Philippine withholding rule in the engine.
SELECT is(
  (SELECT c.tax_base FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'purchase', 'amount', 5000,
     'vat_code_id', (SELECT id FROM vat_codes WHERE vat_code='IVAT-12'),
     'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC140'))) c
    WHERE c.tax_kind='ewt'),
  5000.00::numeric(15,2),
  'withholding defaults to the VAT-exclusive base, not the 5,600 gross');           -- 17

SELECT is(
  (SELECT c.tax_amount FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'purchase', 'amount', 5000,
     'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC140'),
     'withholding_base', 3000)) c
    WHERE c.tax_kind='ewt'),
  60.00::numeric(15,2), 'an explicit withholding base overrides the default');      -- 18

SELECT results_eq(
  $q$SELECT c.tax_kind, c.tax_rate, c.tax_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'purchase', 'amount', 10000,
              'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WI010'),
              'withholding_category', 'ewt')) c
      WHERE c.tax_kind='ewt'$q$,
  $$VALUES ('ewt'::text, 10.0000::numeric(9,4), 1000.00::numeric(15,2))$$,
  'a different ATC yields its own governed rate — professional fees at 10%');       -- 19

-- FWT travels the same code path, keyed by tax_category. It costs nothing extra
-- and it is what the ATC master already models.
SELECT results_eq(
  $q$SELECT c.tax_kind, c.atc_code, c.tax_rate, c.tax_amount
       FROM v_ctx, fn_calculate_tax(jsonb_build_object(
              'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
              'direction', 'purchase', 'amount', 20000,
              'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC001'),
              'withholding_category', 'fwt')) c
      WHERE c.tax_kind='fwt'$q$,
  $$VALUES ('fwt'::text, 'WC001'::text, 15.0000::numeric(9,4), 3000.00::numeric(15,2))$$,
  'FWT resolves through the same ATC mechanism at its own governed rate');          -- 20

-- An EWT code requested as FWT must not resolve. Categories are not aliases.
SELECT is(
  (SELECT c.tax_rate FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'purchase', 'amount', 5000,
     'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC140'),
     'withholding_category', 'fwt')) c
    WHERE c.tax_kind='fwt'),
  NULL::numeric(9,4), 'an EWT ATC asked for as FWT does not resolve');              -- 21

SELECT is(
  (SELECT c.tax_amount FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-01-15',
     'direction', 'purchase', 'amount', 5000,
     'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC140'),
     'withholding_category', 'fwt')) c
    WHERE c.tax_kind='fwt'),
  NULL::numeric(15,2),
  'an unresolved ATC yields a NULL amount so the caller can fail closed, not 0.00'); -- 22

-- ── The effective-date window, exercised through the governed succession ──────
UPDATE atc_codes SET effective_to = '2026-03-31', updated_by = auth.uid(), updated_at = NOW()
WHERE code = 'WC130' AND effective_to IS NULL;

INSERT INTO atc_codes (id, code, description, tax_category, rate, effective_from,
                       is_active, supersedes_atc_code_id, created_by, updated_by)
SELECT '11700000-0000-0000-0000-0000000000e1', a.code, a.description, a.tax_category,
       7.00, '2026-04-01', true, a.id, auth.uid(), auth.uid()
FROM atc_codes a WHERE a.code = 'WC130' AND a.effective_to = '2026-03-31';

SELECT is(
  (SELECT c.tax_amount FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-02-10',
     'direction', 'purchase', 'amount', 10000,
     'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC130' AND rate=2.00))) c
    WHERE c.tax_kind='ewt'),
  200.00::numeric(15,2), 'a document inside the old window withholds at the old 2% rate'); -- 23

SELECT is(
  (SELECT c.tax_amount FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-05-10',
     'direction', 'purchase', 'amount', 10000,
     'withholding_atc_code_id', '11700000-0000-0000-0000-0000000000e1')) c
    WHERE c.tax_kind='ewt'),
  700.00::numeric(15,2), 'a document inside the new window withholds at the new 7% rate'); -- 24

SELECT is(
  (SELECT c.tax_rate FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-05-10',
     'direction', 'purchase', 'amount', 10000,
     'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC130' AND rate=2.00))) c
    WHERE c.tax_kind='ewt'),
  NULL::numeric(9,4),
  'a superseded ATC version does not resolve after its window closes');             -- 25

SELECT is(
  (SELECT c.tax_rate FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-02-10',
     'direction', 'purchase', 'amount', 10000,
     'withholding_atc_code_id', '11700000-0000-0000-0000-0000000000e1')) c
    WHERE c.tax_kind='ewt'),
  NULL::numeric(9,4),
  'a not-yet-effective ATC version does not resolve before its window opens');      -- 26

UPDATE atc_codes SET is_active = false, updated_by = auth.uid(), updated_at = NOW()
WHERE code = 'WC150';

SELECT is(
  (SELECT c.tax_rate FROM v_ctx, fn_calculate_tax(jsonb_build_object(
     'company_id', v_ctx.company_id, 'document_date', '2026-02-10',
     'direction', 'purchase', 'amount', 10000,
     'withholding_atc_code_id', (SELECT id FROM atc_codes WHERE code='WC150'))) c
    WHERE c.tax_kind='ewt'),
  NULL::numeric(9,4), 'an inactive ATC does not resolve on any date');              -- 27

-- ══════════════════════════════════════════════════════════════════════════════
-- SECTION E — The engine fails closed on a malformed context
-- ══════════════════════════════════════════════════════════════════════════════
SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object('amount', 100))$$,
  '%requires company_id%',
  'a tax context with no company is refused, not silently computed');               -- 28

SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id','11700000-0000-0000-0000-0000000000b1',
      'direction','sideways','amount',100))$$,
  '%direction must be sale or purchase%',
  'an unrecognised direction is refused');                                          -- 29

SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id','11700000-0000-0000-0000-0000000000b1',
      'price_basis','net-ish','amount',100))$$,
  '%price_basis must be exclusive or inclusive%',
  'an unrecognised price basis is refused rather than defaulted');                  -- 30

SELECT throws_like(
  $$SELECT * FROM fn_calculate_tax(jsonb_build_object(
      'company_id','11700000-0000-0000-0000-0000000000b1',
      'amount',100,
      'withholding_atc_code_id',(SELECT id FROM atc_codes WHERE code='WC140'),
      'withholding_category','vat'))$$,
  '%withholding_category must be ewt or fwt%',
  'a withholding category that is not a withholding tax is refused');               -- 31

SELECT * FROM finish();
ROLLBACK;
