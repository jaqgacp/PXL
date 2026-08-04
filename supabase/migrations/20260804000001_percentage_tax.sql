-- ═══════════════════════════════════════════════════════════════════════════
-- Delivery Plan Phase 5 — Percentage tax (Product Backlog item 8).
--
-- THE GAP
--   Percentage tax was calculated nowhere in PXL and never had been. A non-VAT,
--   Section 116 company could be configured as PT-registered, could be given
--   `percentage_tax_codes`, and could sell all year — and produce no percentage
--   tax anywhere: no component, no journal line, no tax-ledger row, no working
--   paper, no 2551Q. The PT Return screen filled that void by summing
--   VAT-*exempt* sales lines in the browser, which is wrong twice over: VAT
--   exemption is not the percentage-tax base, and a return computed on the
--   client is not a return computed from the posted books.
--
--   The master data was not sound either. `fn_seed_company_percentage_tax_codes`
--   seeded a row labelled "3% general" whose `tax_code_id` pointed at PT12-OUT
--   (12%), because it picked the first `pt` tax code by code and 'PT12-OUT'
--   sorts before 'PT3-OUT'; and when a company had no percentage-tax ATC it
--   attached **any** ATC — an EWT one — so the 2551Q line would have carried a
--   withholding code. Both are repaired below.
--
-- WHAT THIS CHANGES — the whole chain, or none of it
--   line business tax code → tax component → liability posting → tax ledger →
--   GL reconciliation → working paper → 2551Q return. Every link ships here.
--   A dormant PT branch with no consumer is what this repository has already
--   paid for once (IA-5/ECC); this one is consumed by two real documents.
--
--   1. `percentage_tax_codes` becomes an effective-dated, version-governed
--      master with exactly the machinery `vat_codes` has: successive versions of
--      one official code, an overlap guard, immutability after use, and
--      deprecate-and-succeed as the only way to change a rate.
--   2. One business-tax route, not a parallel one. `fn_resolve_business_tax_code`
--      is the only place PXL decides whether a line's business tax code may be
--      used, for BOTH families; it delegates the VAT half verbatim to
--      `fn_resolve_vat_code`. `fn_business_tax_codes_asof` is the one picker,
--      and it offers percentage-tax codes to a non-VAT/PT-registered company and
--      never to a VAT-registered one.
--   3. `fn_calculate_tax` emits a `percentage_tax` component. It remains the
--      only function in the schema that turns a governed rate into an amount.
--   4. Sales Invoice and Cash Sale carry the code per line, stamp the resolved
--      version, base, rate and amount on the line, and post
--      DR Percentage Tax Expense / CR Percentage Tax Payable through two new
--      governed account keys.
--   5. The tax ledger gets one `percentage_tax` row per code per document, with
--      the tax-code version and rate stamped on it (Backlog item 17, done right
--      for this new writer rather than deferred).
--   6. `fn_percentage_tax_gl_reconciliation` ties the PT ledger to the PT
--      payable control account, and `fn_generate_pt_return` builds the 2551Q
--      and its working paper from that same posted ledger. A PT return cannot
--      be marked final or filed while it disagrees with the ledger.
--
-- THE TAX, STATED PLAINLY
--   Percentage tax under Section 116 is a tax on the SELLER's gross sales or
--   receipts. It is not charged to the customer, it is not added to the invoice
--   total, and it never sits inside the price. That is why the component leaves
--   `net_amount` and `gross_amount` untouched, why the journal adds an equal
--   debit and credit that do not disturb AR, and why the base is the line's net
--   amount after discount.
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--   * **Recognition is on the sales document (accrual).** Section 116 says
--     "gross sales or receipts"; for services the Bureau measures collections.
--     Cash Sale collects at the same instant, so the two agree there. A credit
--     Sales Invoice for services recognises PT earlier than a collection basis
--     would. The basis is stated here rather than assumed, and the receipts
--     variant is recorded in the backlog.
--   * **It does not force a PT code onto a line.** A PT-registered company
--     selects its percentage-tax code exactly as any company selects a VAT code.
--     Making it mandatory would retroactively invalidate every already posted
--     non-VAT document in the canonical dataset and change its books; that is a
--     data migration, not a calculator, and it is recorded as the follow-on.
--   * **No credit-memo reversal.** A return by a PT-registered customer should
--     reduce gross sales and therefore PT. Credit Memo carries no PT code yet;
--     recorded as the follow-on rather than half-built here.
--   * **The 8% income-tax election is not a line treatment** and does not appear
--     anywhere in this file. It belongs to the taxpayer compliance profile and
--     the income-tax computation.
--
-- WHAT THIS DOES NOT CHANGE
--   No VAT arithmetic, no VAT resolution rule, no withholding path, no Posting
--   Engine kernel, guard or totality rule, no inventory or costing behaviour,
--   and no existing journal shape. A document that carries no percentage-tax
--   code posts byte-for-byte what it posted before.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. THE PERCENTAGE-TAX MASTER BECOMES A GOVERNED VERSION
--
-- `vat_codes` has carried effective windows, deprecation, supersession, an
-- overlap guard and immutability-after-use since 20260713000012.
-- `percentage_tax_codes` carried none of it, so the only way to change a rate
-- was to edit the row — which would silently restate every prior period the
-- moment PT started posting. The same machinery, applied to the same shape.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE percentage_tax_codes
  ADD COLUMN IF NOT EXISTS effective_from DATE NOT NULL DEFAULT DATE '1900-01-01',
  ADD COLUMN IF NOT EXISTS effective_to DATE,
  ADD COLUMN IF NOT EXISTS deprecated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deprecated_reason TEXT,
  ADD COLUMN IF NOT EXISTS supersedes_percentage_tax_code_id UUID
    REFERENCES percentage_tax_codes(id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'percentage_tax_codes_effective_date_range_chk'
      AND conrelid = 'public.percentage_tax_codes'::regclass
  ) THEN
    ALTER TABLE percentage_tax_codes
      ADD CONSTRAINT percentage_tax_codes_effective_date_range_chk
      CHECK (effective_to IS NULL OR effective_to >= effective_from);
  END IF;
END $$;

-- Version-aware uniqueness: one official company code, successive versions.
ALTER TABLE percentage_tax_codes
  DROP CONSTRAINT IF EXISTS percentage_tax_codes_company_id_pt_code_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_percentage_tax_code_version
  ON percentage_tax_codes (company_id, pt_code, effective_from);
CREATE UNIQUE INDEX IF NOT EXISTS uq_percentage_tax_code_direct_successor
  ON percentage_tax_codes (supersedes_percentage_tax_code_id)
  WHERE supersedes_percentage_tax_code_id IS NOT NULL;

COMMENT ON COLUMN percentage_tax_codes.effective_from IS
  'Start of the window in which this version of the company percentage-tax code may be used. A rate change closes this version and starts a successor; it never edits the row.';
COMMENT ON COLUMN percentage_tax_codes.rate IS
  'The rate of the tax_codes version this row points at, kept as a readable projection. tax_codes is the governed rate holder; a guard refuses a row whose rate disagrees with it.';

-- ── Repair: rows the broken seed left inconsistent ─────────────────────────
-- Percentage tax has never posted anything, so no document depends on these
-- values and repairing them cannot restate any book. Left unrepaired they would
-- be traps: a row labelled 3% that computes 12%, and a 2551Q line carrying an
-- EWT alphanumeric code.
UPDATE percentage_tax_codes ptc
SET tax_code_id = fix.id,
    updated_at  = now()
FROM (
  SELECT DISTINCT ON (tc.rate) tc.rate, tc.id
  FROM tax_codes tc
  WHERE tc.tax_type = 'pt'
    AND COALESCE(tc.is_active, false)
    AND tc.deprecated_at IS NULL
  ORDER BY tc.rate, tc.code
) fix
WHERE fix.rate = ptc.rate
  AND EXISTS (
    SELECT 1 FROM tax_codes bad
    WHERE bad.id = ptc.tax_code_id
      AND bad.rate IS DISTINCT FROM ptc.rate
  );

UPDATE percentage_tax_codes ptc
SET atc_id     = fix.id,
    updated_at = now()
FROM (
  SELECT DISTINCT ON (ac.rate) ac.rate, ac.id
  FROM atc_codes ac
  WHERE ac.tax_category = 'pt'
    AND COALESCE(ac.is_active, false)
    AND ac.deprecated_at IS NULL
  ORDER BY ac.rate, ac.code
) fix
WHERE fix.rate = ptc.rate
  AND EXISTS (
    SELECT 1 FROM atc_codes bad
    WHERE bad.id = ptc.atc_id
      AND bad.tax_category IS DISTINCT FROM 'pt'
  );

-- ── Usage predicate ────────────────────────────────────────────────────────
-- A percentage-tax code is "used" once a document line or the posted tax ledger
-- references it. Company master defaults are not usage, exactly as they are not
-- for VAT. It reads two columns this migration adds further down, and is
-- plpgsql for the same reason `fn_vat_code_used` is: the body resolves when it
-- runs, not when it is defined, and nothing updates the master in between.
CREATE OR REPLACE FUNCTION public.fn_percentage_tax_code_used(p_percentage_tax_code_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM sales_invoice_lines
    WHERE percentage_tax_code_id = p_percentage_tax_code_id
  ) OR EXISTS (
    SELECT 1 FROM tax_detail_entries
    WHERE percentage_tax_code_id = p_percentage_tax_code_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_percentage_tax_code_used(UUID) TO authenticated;

-- ── Version integrity: no overlapping live windows, valid successor ────────
CREATE OR REPLACE FUNCTION public.fn_enforce_percentage_tax_code_version_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_predecessor percentage_tax_codes%ROWTYPE;
  v_tax         tax_codes%ROWTYPE;
BEGIN
  IF NEW.effective_to IS NOT NULL AND NEW.effective_to < NEW.effective_from THEN
    RAISE EXCEPTION 'Percentage tax code effective end cannot be before its effective start.';
  END IF;

  -- The rate is a projection of the governed holder. Two places may state a
  -- rate only while they cannot disagree.
  SELECT * INTO v_tax FROM tax_codes WHERE id = NEW.tax_code_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Percentage tax code % references a tax code that does not exist.', NEW.pt_code;
  END IF;
  IF v_tax.tax_type <> 'pt' THEN
    RAISE EXCEPTION 'Percentage tax code % must reference a percentage-tax (pt) tax code, not %.',
      NEW.pt_code, v_tax.tax_type;
  END IF;
  IF NEW.rate IS DISTINCT FROM v_tax.rate THEN
    RAISE EXCEPTION 'Percentage tax code % states %%%, but tax code % is %%%. The tax code holds the governed rate.',
      NEW.pt_code, NEW.rate, v_tax.code, v_tax.rate;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atc_codes ac
    WHERE ac.id = NEW.atc_id AND ac.tax_category = 'pt'
  ) THEN
    RAISE EXCEPTION 'Percentage tax code % must reference a percentage-tax (pt) alphanumeric tax code; the 2551Q is filed per ATC.',
      NEW.pt_code;
  END IF;

  IF NEW.supersedes_percentage_tax_code_id IS NOT NULL THEN
    IF NEW.supersedes_percentage_tax_code_id = NEW.id THEN
      RAISE EXCEPTION 'A percentage tax code version cannot supersede itself.';
    END IF;
    SELECT * INTO v_predecessor FROM percentage_tax_codes
    WHERE id = NEW.supersedes_percentage_tax_code_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Superseded percentage tax code version was not found.';
    END IF;
    IF v_predecessor.company_id <> NEW.company_id THEN
      RAISE EXCEPTION 'A percentage tax code version may only supersede one of its own company.';
    END IF;
    IF v_predecessor.pt_code <> NEW.pt_code THEN
      RAISE EXCEPTION 'Successor percentage tax code must keep the same code as its predecessor.';
    END IF;
    IF v_predecessor.effective_from >= NEW.effective_from THEN
      RAISE EXCEPTION 'Successor percentage tax code % must start after the version it supersedes.', NEW.pt_code;
    END IF;
  END IF;

  -- Two live versions of one code may not cover overlapping windows. A row with
  -- the SAME start is not an overlap to report here: it is the same version, and
  -- the unique index decides its fate — which is what lets an idempotent
  -- ON CONFLICT DO NOTHING re-seed work, since a BEFORE INSERT trigger fires
  -- before the conflict is arbitrated.
  IF COALESCE(NEW.is_active, false) AND NEW.deprecated_at IS NULL THEN
    IF EXISTS (
      SELECT 1 FROM percentage_tax_codes a
      WHERE a.id <> NEW.id
        AND a.company_id = NEW.company_id
        AND a.pt_code = NEW.pt_code
        AND a.effective_from <> NEW.effective_from
        AND COALESCE(a.is_active, false)
        AND a.deprecated_at IS NULL
        AND a.effective_from <= COALESCE(NEW.effective_to, DATE 'infinity')
        AND NEW.effective_from <= COALESCE(a.effective_to, DATE 'infinity')
    ) THEN
      RAISE EXCEPTION 'Percentage tax code % has an overlapping active effective window with an existing version. Close the previous version''s effective_to before starting a successor.',
        NEW.pt_code;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_percentage_tax_code_version_rules ON percentage_tax_codes;
CREATE TRIGGER trg_percentage_tax_code_version_rules
  BEFORE INSERT OR UPDATE OF pt_code, tax_code_id, atc_id, rate, effective_from,
    effective_to, is_active, deprecated_at, supersedes_percentage_tax_code_id
  ON percentage_tax_codes
  FOR EACH ROW EXECUTE FUNCTION fn_enforce_percentage_tax_code_version_rules();

-- ── History guard: frozen once used, undeletable once used ─────────────────
CREATE OR REPLACE FUNCTION public.fn_guard_percentage_tax_code_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF fn_percentage_tax_code_used(OLD.id) THEN
      RAISE EXCEPTION 'Percentage tax code % is already used and cannot be deleted. Deprecate it and create a successor version instead.', OLD.pt_code;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND fn_percentage_tax_code_used(OLD.id) THEN
    IF NEW.pt_code IS DISTINCT FROM OLD.pt_code
       OR NEW.tax_code_id IS DISTINCT FROM OLD.tax_code_id
       OR NEW.atc_id IS DISTINCT FROM OLD.atc_id
       OR NEW.rate IS DISTINCT FROM OLD.rate
       OR NEW.effective_from IS DISTINCT FROM OLD.effective_from THEN
      RAISE EXCEPTION 'Percentage tax code, its tax code, ATC, rate and effective start are immutable after use. Deprecate this code and create a successor version.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_percentage_tax_code_history_guard ON percentage_tax_codes;
CREATE TRIGGER trg_percentage_tax_code_history_guard
  BEFORE UPDATE OR DELETE ON percentage_tax_codes
  FOR EACH ROW EXECUTE FUNCTION fn_guard_percentage_tax_code_history();

-- The master-data importer resolves an existing row by business key. With
-- successive versions of one code, the key is the code AND its start date.
UPDATE master_data_import_registry
SET business_key_columns = ARRAY['pt_code','effective_from'],
    sort_columns         = ARRAY['pt_code','effective_from']
WHERE master_key = 'percentage_tax_codes';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. THE COMPANY PERCENTAGE-TAX PROFILE SEAM
--
-- The mirror of `fn_company_tax_registration_asof`, and honest in the same way:
-- it accepts the document date because the right question is "was this company
-- percentage-tax registered on that date?", while `compliance_profiles` can only
-- answer "is it now?". `pt_effective_date` is honoured where it exists, which is
-- as far as the model goes. Naming the gap in the signature keeps the future fix
-- to one function.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_company_percentage_tax_registered_asof(
  p_company_id UUID,
  p_as_of      DATE DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT cp.percentage_tax_registered
       AND (cp.pt_effective_date IS NULL
            OR cp.pt_effective_date <= COALESCE(p_as_of, CURRENT_DATE))
     FROM compliance_profiles cp
     WHERE cp.company_id = p_company_id
       AND COALESCE(cp.is_active, true)),
    false);
$$;

COMMENT ON FUNCTION public.fn_company_percentage_tax_registered_asof(UUID, DATE) IS
  'The single seam through which business-tax validation reads a company percentage-tax registration. Honours pt_effective_date; compliance_profiles carries no fuller history, so de-registration is not yet dated.';

REVOKE ALL ON FUNCTION public.fn_company_percentage_tax_registered_asof(UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_company_percentage_tax_registered_asof(UUID, DATE) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. ONE BUSINESS-TAX ROUTE
--
-- A sales line carries exactly one business tax: VAT if the company is
-- VAT-registered, percentage tax if it is a non-VAT Section 116 taxpayer. Two
-- families, one route. `fn_resolve_business_tax_code` owns every rule that
-- decides whether the code on a line may be used; the VAT half is delegated
-- verbatim to `fn_resolve_vat_code`, which remains the only place VAT validity
-- is decided. `fn_business_tax_codes_asof` offers exactly what this resolver
-- accepts, so the picker cannot offer a code the database will refuse.
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'business_tax_resolution'
  ) THEN
    CREATE TYPE public.business_tax_resolution AS (
      tax_family       TEXT,          -- vat | percentage_tax
      code_id          UUID,          -- vat_codes.id or percentage_tax_codes.id
      code             TEXT,
      description      TEXT,
      tax_code_id      UUID,
      tax_code         TEXT,
      classification   TEXT,          -- regular | zero_rated | exempt (VAT only)
      transaction_type TEXT,          -- input_vat | output_vat | percentage_tax
      tax_rate         NUMERIC(9,4),
      atc_code_id      UUID,          -- the 2551Q alphanumeric code (PT only)
      atc_code         TEXT,
      form_type        TEXT,          -- 2551Q (PT only)
      effective_from   DATE,
      effective_to     DATE
    );
  END IF;
END $$;

COMMENT ON TYPE public.business_tax_resolution IS
  'The exact business-tax version resolved for one document date, for either family: VAT or percentage tax.';

CREATE OR REPLACE FUNCTION public.fn_resolve_business_tax_code(
  p_company_id             UUID,
  p_vat_code_id            UUID,
  p_percentage_tax_code_id UUID,
  p_as_of                  DATE DEFAULT NULL,
  p_transaction_type       TEXT DEFAULT NULL,
  p_context                TEXT DEFAULT 'Business tax code'
)
RETURNS SETOF public.business_tax_resolution
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_as_of        DATE := COALESCE(p_as_of, CURRENT_DATE);
  v_registration TEXT;
  v_vat          public.vat_code_resolution;
  v_ptc          percentage_tax_codes%ROWTYPE;
  v_tc           tax_codes%ROWTYPE;
  v_atc          atc_codes%ROWTYPE;
  v_row          public.business_tax_resolution;
BEGIN
  -- ── The VAT family: delegated whole, so VAT has exactly one rule set ──────
  v_vat := fn_resolve_vat_code(p_company_id, p_vat_code_id, v_as_of,
                               p_transaction_type,
                               CASE WHEN p_percentage_tax_code_id IS NULL
                                    THEN p_context ELSE 'VAT code' END);
  -- Test the field, never the composite: `row IS NOT NULL` is true only when
  -- every field is non-null, and an open-ended version has a NULL effective_to.
  IF v_vat.vat_code_id IS NOT NULL THEN
    v_row := ROW('vat', v_vat.vat_code_id, v_vat.vat_code, NULL,
                 v_vat.tax_code_id, v_vat.tax_code, v_vat.classification,
                 v_vat.transaction_type, v_vat.vat_rate,
                 NULL, NULL, NULL,
                 v_vat.effective_from, v_vat.effective_to)::public.business_tax_resolution;
    RETURN NEXT v_row;
  END IF;

  IF p_percentage_tax_code_id IS NULL THEN
    RETURN;
  END IF;

  -- A Section 116 sale is legitimately VAT-exempt AND percentage-taxable, so
  -- the two codes coexist on one line. What may never coexist is a VAT-BEARING
  -- rate and a percentage tax: that would charge two business taxes on the same
  -- peso. The company tax profile already makes that unreachable; this is the
  -- guard that keeps it so.
  IF v_vat.vat_code_id IS NOT NULL AND COALESCE(v_vat.vat_rate, 0) <> 0 THEN
    RAISE EXCEPTION '% cannot carry a VAT-bearing code and a percentage-tax code on one line.', p_context;
  END IF;

  -- ── The percentage-tax family ────────────────────────────────────────────
  -- Percentage tax is a tax on the seller's own sales. A purchase line never
  -- carries it: what the supplier owes under Section 116 is the supplier's
  -- business tax, priced into what it charges, not a component of this document.
  IF p_transaction_type IS NOT NULL AND p_transaction_type <> 'output_vat' THEN
    RAISE EXCEPTION '% is a percentage-tax code, which only applies to a sales document.', p_context;
  END IF;

  SELECT * INTO v_ptc FROM percentage_tax_codes WHERE id = p_percentage_tax_code_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION '% is not a valid percentage-tax code', p_context;
  END IF;
  IF v_ptc.company_id <> p_company_id THEN
    RAISE EXCEPTION '% % belongs to another company', p_context, v_ptc.pt_code;
  END IF;

  IF NOT COALESCE(v_ptc.is_active, false) THEN
    RAISE EXCEPTION '% % is inactive', p_context, v_ptc.pt_code;
  END IF;
  IF v_ptc.deprecated_at IS NOT NULL THEN
    RAISE EXCEPTION '% % was deprecated on %. Select its successor version.',
      p_context, v_ptc.pt_code, v_ptc.deprecated_at::DATE;
  END IF;
  IF v_ptc.effective_from > v_as_of
     OR (v_ptc.effective_to IS NOT NULL AND v_ptc.effective_to < v_as_of) THEN
    RAISE EXCEPTION '% % is not effective on % (that version runs % to %).',
      p_context, v_ptc.pt_code, v_as_of, v_ptc.effective_from,
      COALESCE(v_ptc.effective_to::TEXT, 'open');
  END IF;

  -- The tax-code version that carries the governed rate.
  SELECT * INTO v_tc FROM tax_codes WHERE id = v_ptc.tax_code_id;
  IF NOT FOUND OR v_tc.tax_type <> 'pt' THEN
    RAISE EXCEPTION '% % does not resolve to a percentage-tax rate', p_context, v_ptc.pt_code;
  END IF;
  IF NOT COALESCE(v_tc.is_active, false) THEN
    RAISE EXCEPTION '% % resolves to tax code %, which is inactive',
      p_context, v_ptc.pt_code, v_tc.code;
  END IF;
  IF v_tc.deprecated_at IS NOT NULL THEN
    RAISE EXCEPTION '% % resolves to tax code %, which was deprecated on %. Select its successor version.',
      p_context, v_ptc.pt_code, v_tc.code, v_tc.deprecated_at::DATE;
  END IF;
  IF v_tc.effective_from > v_as_of
     OR (v_tc.effective_to IS NOT NULL AND v_tc.effective_to < v_as_of) THEN
    RAISE EXCEPTION '% % resolves to tax code %, which is not effective on % (that version runs % to %).',
      p_context, v_ptc.pt_code, v_tc.code, v_as_of, v_tc.effective_from,
      COALESCE(v_tc.effective_to::TEXT, 'open');
  END IF;

  -- The alphanumeric tax code the 2551Q is filed under.
  SELECT * INTO v_atc FROM atc_codes
  WHERE id = v_ptc.atc_id
    AND tax_category = 'pt'
    AND COALESCE(is_active, false)
    AND deprecated_at IS NULL
    AND effective_from <= v_as_of
    AND (effective_to IS NULL OR effective_to >= v_as_of);
  IF NOT FOUND THEN
    RAISE EXCEPTION '% % has no percentage-tax ATC in force on %. The 2551Q is filed per ATC.',
      p_context, v_ptc.pt_code, v_as_of;
  END IF;

  -- The company tax profile. A VAT-registered company does not pay percentage
  -- tax on the same sales it charges VAT on; offering it the code at all would
  -- be a double business tax.
  v_registration := fn_company_tax_registration_asof(p_company_id, v_as_of);
  IF v_registration IS NULL THEN
    RAISE EXCEPTION 'Company not found';
  END IF;
  IF v_registration = 'vat' THEN
    RAISE EXCEPTION 'A VAT-registered company cannot use percentage-tax code %. Percentage tax is the business tax of a non-VAT taxpayer.',
      v_ptc.pt_code;
  END IF;
  IF NOT fn_company_percentage_tax_registered_asof(p_company_id, v_as_of) THEN
    RAISE EXCEPTION 'This company is not percentage-tax registered as of %. Set it in the Compliance Profile before using code %.',
      v_as_of, v_ptc.pt_code;
  END IF;

  v_row := ROW('percentage_tax', v_ptc.id, v_ptc.pt_code, v_ptc.description,
               v_tc.id, v_tc.code, NULL, 'percentage_tax', v_tc.rate,
               v_atc.id, v_atc.code, v_ptc.form_type,
               GREATEST(v_ptc.effective_from, v_tc.effective_from),
               LEAST(COALESCE(v_ptc.effective_to, DATE 'infinity'),
                     COALESCE(v_tc.effective_to, DATE 'infinity')))::public.business_tax_resolution;
  IF v_row.effective_to = DATE 'infinity' THEN
    v_row.effective_to := NULL;
  END IF;
  RETURN NEXT v_row;
  RETURN;
END;
$function$;

COMMENT ON FUNCTION public.fn_resolve_business_tax_code(UUID, UUID, UUID, DATE, TEXT, TEXT) IS
  'The only place PXL decides whether a line business tax code may be used, for both families. Returns one row per business tax that applies to the line: VAT delegated verbatim to fn_resolve_vat_code, percentage tax resolved against its own version, its tax-code version, its 2551Q ATC and the company percentage-tax registration, all as of the document date. Fails closed.';

REVOKE ALL ON FUNCTION public.fn_resolve_business_tax_code(UUID, UUID, UUID, DATE, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_resolve_business_tax_code(UUID, UUID, UUID, DATE, TEXT, TEXT) TO authenticated;

-- ── The picker ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_business_tax_codes_asof(
  p_company_id       UUID,
  p_as_of            DATE DEFAULT NULL,
  p_transaction_type TEXT DEFAULT NULL
)
RETURNS TABLE (
  tax_family       TEXT,
  id               UUID,
  code             TEXT,
  description      TEXT,
  classification   TEXT,
  transaction_type TEXT,
  tax_code_id      UUID,
  rate             NUMERIC(9,4),
  atc_code         TEXT,
  form_type        TEXT,
  effective_from   DATE,
  effective_to     DATE
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_as_of DATE := COALESCE(p_as_of, CURRENT_DATE);
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  -- The VAT family, exactly as fn_vat_codes_asof offers it. That function stays
  -- the VAT authority; this one does not restate its rules.
  RETURN QUERY
  SELECT 'vat'::TEXT, v.id, v.vat_code, v.description, v.vat_classification,
         v.transaction_type, v.tax_code_id, v.rate::NUMERIC(9,4),
         NULL::TEXT, NULL::TEXT, v.effective_from, v.effective_to
  FROM fn_vat_codes_asof(p_company_id, v_as_of, p_transaction_type) v;

  -- The percentage-tax family, offered to exactly the companies that owe it and
  -- only on the sales side.
  IF (p_transaction_type IS NULL OR p_transaction_type = 'output_vat')
     AND fn_company_tax_registration_asof(p_company_id, v_as_of) <> 'vat'
     AND fn_company_percentage_tax_registered_asof(p_company_id, v_as_of) THEN
    RETURN QUERY
    SELECT 'percentage_tax'::TEXT, ptc.id, ptc.pt_code, ptc.description,
           NULL::TEXT, 'percentage_tax'::TEXT, tc.id, tc.rate::NUMERIC(9,4),
           ac.code, ptc.form_type,
           GREATEST(ptc.effective_from, tc.effective_from),
           NULLIF(LEAST(COALESCE(ptc.effective_to, DATE 'infinity'),
                        COALESCE(tc.effective_to, DATE 'infinity')), DATE 'infinity')
    FROM percentage_tax_codes ptc
    JOIN tax_codes tc ON tc.id = ptc.tax_code_id
    JOIN atc_codes ac ON ac.id = ptc.atc_id
    WHERE ptc.company_id = p_company_id
      AND COALESCE(ptc.is_active, false)
      AND ptc.deprecated_at IS NULL
      AND ptc.effective_from <= v_as_of
      AND (ptc.effective_to IS NULL OR ptc.effective_to >= v_as_of)
      AND COALESCE(tc.is_active, false)
      AND tc.deprecated_at IS NULL
      AND tc.effective_from <= v_as_of
      AND (tc.effective_to IS NULL OR tc.effective_to >= v_as_of)
      AND ac.tax_category = 'pt'
      AND COALESCE(ac.is_active, false)
      AND ac.deprecated_at IS NULL
      AND ac.effective_from <= v_as_of
      AND (ac.effective_to IS NULL OR ac.effective_to >= v_as_of)
    ORDER BY ptc.pt_code;
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.fn_business_tax_codes_asof(UUID, DATE, TEXT) IS
  'The governed business-tax picker: exactly the VAT and percentage-tax versions fn_resolve_business_tax_code accepts for this company on this document date. Percentage-tax codes are offered only to a non-VAT, percentage-tax-registered company, and only on a sales document.';

REVOKE ALL ON FUNCTION public.fn_business_tax_codes_asof(UUID, DATE, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_business_tax_codes_asof(UUID, DATE, TEXT) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. THE ENGINE LEARNS PERCENTAGE TAX
--
-- `fn_calculate_tax` remains the only function in the schema that turns a
-- governed rate into a tax amount. The VAT branch is unchanged in behaviour: it
-- now asks fn_resolve_business_tax_code, which delegates it straight back to
-- fn_resolve_vat_code with the same context and the same messages.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_calculate_tax(p_context JSONB)
RETURNS SETOF public.tax_component
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id   UUID          := NULLIF(BTRIM(p_context->>'company_id'), '')::UUID;
  v_date         DATE          := COALESCE(NULLIF(BTRIM(p_context->>'document_date'), '')::DATE, CURRENT_DATE);
  v_direction    TEXT          := LOWER(COALESCE(NULLIF(BTRIM(p_context->>'direction'), ''), 'sale'));
  v_basis        TEXT          := LOWER(COALESCE(NULLIF(BTRIM(p_context->>'price_basis'), ''), 'exclusive'));
  v_amount       NUMERIC(15,2) := ROUND(COALESCE(NULLIF(BTRIM(p_context->>'amount'), '')::NUMERIC, 0), 2);
  v_vat_code_id  UUID          := NULLIF(BTRIM(p_context->>'vat_code_id'), '')::UUID;
  v_pt_code_id   UUID          := NULLIF(BTRIM(p_context->>'percentage_tax_code_id'), '')::UUID;
  v_atc_id       UUID          := NULLIF(BTRIM(p_context->>'withholding_atc_code_id'), '')::UUID;
  v_atc_category TEXT          := LOWER(COALESCE(NULLIF(BTRIM(p_context->>'withholding_category'), ''), 'ewt'));
  v_wht_base     NUMERIC(15,2) := ROUND(NULLIF(BTRIM(p_context->>'withholding_base'), '')::NUMERIC, 2);
  v_side         TEXT;
  v_business     public.business_tax_resolution;
  v_vat_res      public.business_tax_resolution;
  v_pt_res       public.business_tax_resolution;
  v_class        TEXT;
  v_tax_code_id  UUID;
  v_rate         NUMERIC(9,4);
  v_net          NUMERIC(15,2);
  v_vat          NUMERIC(15,2);
  v_gross        NUMERIC(15,2);
  v_kind         TEXT;
  v_pt_amount    NUMERIC(15,2);
  v_atc_code     TEXT;
  v_atc_desc     TEXT;
  v_atc_rate     NUMERIC(9,4);
  v_wht_amount   NUMERIC(15,2);
  v_row          public.tax_component;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'fn_calculate_tax requires company_id in the tax context.';
  END IF;
  IF v_direction NOT IN ('sale', 'purchase') THEN
    RAISE EXCEPTION 'fn_calculate_tax direction must be sale or purchase, not %.', v_direction;
  END IF;
  IF v_basis NOT IN ('exclusive', 'inclusive') THEN
    RAISE EXCEPTION 'fn_calculate_tax price_basis must be exclusive or inclusive, not %.', v_basis;
  END IF;
  IF v_atc_category NOT IN ('ewt', 'fwt') THEN
    RAISE EXCEPTION 'fn_calculate_tax withholding_category must be ewt or fwt, not %.', v_atc_category;
  END IF;

  v_side := CASE v_direction WHEN 'sale' THEN 'output_vat' ELSE 'input_vat' END;

  -- ── The line's business tax ──────────────────────────────────────────────
  -- One route, two families. An ABSENT code is exempt at 0% — the behaviour
  -- every caller had before. A code that WAS supplied must resolve on the
  -- document date, against the company tax profile and on the right tax side,
  -- or the whole computation is refused.
  FOR v_business IN
    SELECT * FROM fn_resolve_business_tax_code(
      v_company_id, v_vat_code_id, v_pt_code_id, v_date, v_side, 'VAT code')
  LOOP
    IF v_business.tax_family = 'vat' THEN
      v_vat_res := v_business;
    ELSE
      v_pt_res := v_business;
    END IF;
  END LOOP;

  -- ── VAT ──────────────────────────────────────────────────────────────────
  -- A VAT component is ALWAYS emitted so that `net_amount` has exactly one
  -- definition in the product. On a Section 116 line it is exempt at 0%, which
  -- is precisely what a non-VAT taxpayer's sale is for VAT purposes.
  v_class       := COALESCE(v_vat_res.classification, 'exempt');
  v_rate        := COALESCE(v_vat_res.tax_rate, 0);
  v_tax_code_id := v_vat_res.tax_code_id;
  v_kind        := COALESCE(v_vat_res.transaction_type, v_side);

  IF v_basis = 'inclusive' AND v_class = 'regular' AND v_rate > 0 THEN
    -- Back the tax out of a tax-inclusive price. The VAT is the residual, so
    -- net + VAT always reconstitutes the quoted price to the centavo.
    v_net   := ROUND(v_amount / (1 + (v_rate / 100)), 2);
    v_vat   := v_amount - v_net;
    v_gross := v_amount;
  ELSE
    v_net   := v_amount;
    v_vat   := CASE WHEN v_class = 'regular' THEN ROUND(v_net * v_rate / 100, 2) ELSE 0 END;
    v_gross := v_net + v_vat;
  END IF;

  v_row := ROW(v_kind, v_vat_code_id, v_tax_code_id, NULL, NULL, NULL, v_class,
               v_net, v_rate, v_vat, v_net, v_gross, v_basis)::public.tax_component;
  RETURN NEXT v_row;

  -- ── Percentage tax (Section 116 and its relatives) ───────────────────────
  -- The seller's own business tax on its gross sales. It is not charged to the
  -- customer, so it changes neither `net_amount` nor `gross_amount`; the caller
  -- posts it as an expense and a liability, not as part of the receivable.
  IF v_pt_res.code_id IS NOT NULL THEN
    v_pt_amount := ROUND(v_net * v_pt_res.tax_rate / 100.0, 2);
    v_row := ROW('percentage_tax', NULL, v_pt_res.tax_code_id,
                 v_pt_res.atc_code_id, v_pt_res.atc_code, v_pt_res.description,
                 NULL, v_net, v_pt_res.tax_rate, v_pt_amount,
                 v_net, v_gross, v_basis)::public.tax_component;
    RETURN NEXT v_row;
  END IF;

  -- ── Withholding (EWT / CWT at source, or FWT) ────────────────────────────
  -- The ATC version in force ON THE DOCUMENT DATE governs.  A rate that is
  -- inactive, deprecated, superseded or not yet effective does not resolve;
  -- the component is returned with a NULL rate so the caller can raise its own
  -- domain-specific message rather than inherit a generic one.
  IF v_atc_id IS NOT NULL THEN
    SELECT ac.code, ac.description, ac.rate INTO v_atc_code, v_atc_desc, v_atc_rate
    FROM atc_codes ac
    WHERE ac.id = v_atc_id
      AND ac.is_active = true
      AND ac.deprecated_at IS NULL
      AND ac.tax_category = v_atc_category
      AND ac.effective_from <= v_date
      AND (ac.effective_to IS NULL OR ac.effective_to >= v_date);

    v_wht_base   := ROUND(COALESCE(v_wht_base, v_net), 2);
    v_wht_amount := CASE WHEN v_atc_rate IS NULL
                         THEN NULL
                         ELSE ROUND(v_wht_base * v_atc_rate / 100.0, 2) END;

    v_row := ROW(v_atc_category, NULL, NULL, v_atc_id, v_atc_code, v_atc_desc, NULL,
                 v_wht_base, v_atc_rate, v_wht_amount, v_net, v_gross, v_basis)::public.tax_component;
    RETURN NEXT v_row;
  END IF;

  RETURN;
END;
$function$;

COMMENT ON FUNCTION public.fn_calculate_tax(JSONB) IS
  'The Tax Engine. The only function in PXL that turns a governed tax rate into a tax amount (PAD-001, Delivery Plan Phase 4). VAT, percentage tax and withholding are all resolved from the version in force on the document date. Percentage tax is the seller''s tax on its own gross sales: it leaves net and gross untouched.';

REVOKE ALL ON FUNCTION public.fn_calculate_tax(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_tax(JSONB) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. THE LINE AND DOCUMENT MODEL
--
-- Percentage tax is a per-line fact for the same reason withholding is: one
-- document may mix treatments, and the 2551Q is filed per ATC. The resolved
-- version, base, rate and amount are stamped on the line so a posted line
-- explains itself without re-resolving configuration.
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE sales_invoice_lines
  ADD COLUMN IF NOT EXISTS percentage_tax_code_id UUID REFERENCES percentage_tax_codes(id),
  ADD COLUMN IF NOT EXISTS percentage_tax_base NUMERIC(15,2),
  ADD COLUMN IF NOT EXISTS percentage_tax_rate NUMERIC(9,4),
  ADD COLUMN IF NOT EXISTS percentage_tax_amount NUMERIC(15,2);

CREATE INDEX IF NOT EXISTS idx_sil_percentage_tax_code
  ON sales_invoice_lines (company_id, percentage_tax_code_id)
  WHERE percentage_tax_code_id IS NOT NULL;

COMMENT ON COLUMN sales_invoice_lines.percentage_tax_code_id IS
  'The percentage-tax code the user selected for THIS line. Mutually exclusive with a VAT-bearing code: a sale owes one business tax, not two.';
COMMENT ON COLUMN sales_invoice_lines.percentage_tax_base IS
  'System-derived: the gross sales amount the Tax Engine applied the percentage-tax rate to (the line net, after discount).';
COMMENT ON COLUMN sales_invoice_lines.percentage_tax_rate IS
  'System-derived: the rate of the exact tax-code version resolved on the document date.';
COMMENT ON COLUMN sales_invoice_lines.percentage_tax_amount IS
  'System-derived by fn_calculate_tax. The seller''s own business tax; it is not added to the customer''s total.';

ALTER TABLE sales_invoices
  ADD COLUMN IF NOT EXISTS total_percentage_tax_amount NUMERIC(15,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN sales_invoices.total_percentage_tax_amount IS
  'Percentage tax the seller owes on this document. Deliberately NOT part of total_amount: the customer is not charged it.';

ALTER TABLE tax_detail_entries
  ADD COLUMN IF NOT EXISTS percentage_tax_code_id UUID REFERENCES percentage_tax_codes(id);

COMMENT ON COLUMN tax_detail_entries.percentage_tax_code_id IS
  'The company percentage-tax code version this ledger row was computed from. tax_code_id and tax_rate carry the governed rate version, so the row explains itself without re-resolving configuration.';

CREATE INDEX IF NOT EXISTS idx_tde_percentage_tax
  ON tax_detail_entries (company_id, document_date)
  WHERE tax_kind = 'percentage_tax';

-- One writer, so both documents produce an identical ledger row and the 2551Q
-- never has to know which document it came from.
CREATE OR REPLACE FUNCTION public.fn_add_percentage_tax_detail(
  p_company_id             UUID,
  p_branch_id              UUID,
  p_source_doc_type        TEXT,
  p_source_doc_id          UUID,
  p_percentage_tax_code_id UUID,
  p_tax_code_id            UUID,
  p_atc_code_id            UUID,
  p_tax_base               NUMERIC,
  p_tax_rate               NUMERIC,
  p_tax_amount             NUMERIC,
  p_tax_period_id          UUID,
  p_document_date          DATE,
  p_counterparty_id        UUID,
  p_counterparty_tin       TEXT,
  p_counterparty_name      TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, percentage_tax_code_id, tax_code_id, atc_code_id,
    tax_base, tax_rate, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name
  ) VALUES (
    p_company_id, p_branch_id, p_source_doc_type, p_source_doc_id,
    'percentage_tax', p_percentage_tax_code_id, p_tax_code_id, p_atc_code_id,
    ROUND(COALESCE(p_tax_base, 0), 2), p_tax_rate, ROUND(COALESCE(p_tax_amount, 0), 2),
    p_tax_period_id, CURRENT_DATE, p_document_date,
    p_counterparty_id, p_counterparty_tin, p_counterparty_name
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.fn_add_percentage_tax_detail(UUID, UUID, TEXT, UUID, UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, UUID, DATE, UUID, TEXT, TEXT) IS
  'The one percentage-tax ledger writer. Stamps the company code version, the governed tax-code version, its rate and the 2551Q ATC on every row.';

REVOKE ALL ON FUNCTION public.fn_add_percentage_tax_detail(UUID, UUID, TEXT, UUID, UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, UUID, DATE, UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_add_percentage_tax_detail(UUID, UUID, TEXT, UUID, UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, UUID, DATE, UUID, TEXT, TEXT) TO authenticated;

-- ── The trigger backstop ───────────────────────────────────────────────────
-- RLS lets a company member write document lines directly, so the save RPC is
-- not the boundary — this is. The percentage-tax code on a line is validated
-- against the parent document's date through the one governed route.
CREATE OR REPLACE FUNCTION public.fn_require_sales_line_percentage_tax_valid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_date       DATE;
BEGIN
  IF NEW.percentage_tax_code_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT si.company_id, si.date INTO v_company_id, v_date
  FROM sales_invoices si WHERE si.id = NEW.sales_invoice_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Sales invoice parent document was not found';
  END IF;
  IF NEW.company_id IS DISTINCT FROM v_company_id THEN
    RAISE EXCEPTION 'Sales invoice line company does not match its document company';
  END IF;

  -- Both codes go to the one route together: it is what decides that a
  -- VAT-exempt Section 116 line is legitimate and a VAT-bearing one is not.
  PERFORM fn_resolve_business_tax_code(
    v_company_id, NEW.vat_code_id, NEW.percentage_tax_code_id, v_date, 'output_vat',
    'Sales invoice percentage tax code');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_si_line_percentage_tax ON sales_invoice_lines;
CREATE TRIGGER trg_si_line_percentage_tax
  BEFORE INSERT OR UPDATE OF sales_invoice_id, company_id, vat_code_id,
    percentage_tax_code_id
  ON sales_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_sales_line_percentage_tax_valid();

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. THE TWO GOVERNED ACCOUNTS
--
-- Percentage tax is an expense of doing business and a liability until remitted.
-- Both are resolved through the COA engine, like every other posting account, so
-- a company that has not configured them cannot post percentage tax and is told
-- exactly what to configure.
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO ref_mapping_key (key_code, description, expected_account_type, is_active)
VALUES
  ('PERCENTAGE_TAX_EXPENSE',
   'Percentage tax expense (business tax borne by the seller; conventionally Taxes and Licenses)',
   'expense', true),
  ('PERCENTAGE_TAX_PAYABLE',
   'Percentage tax payable to the BIR until remitted with the 2551Q',
   'liability', true)
ON CONFLICT (key_code) DO UPDATE
  SET description           = EXCLUDED.description,
      expected_account_type = EXCLUDED.expected_account_type,
      is_active             = true;

ALTER TABLE company_accounting_config
  ADD COLUMN IF NOT EXISTS percentage_tax_expense_account_id UUID REFERENCES chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS percentage_tax_payable_account_id UUID REFERENCES chart_of_accounts(id);

INSERT INTO coa_template_lines (
  template_id, account_code, account_name, account_type, normal_balance,
  is_postable, parent_account_code, fs_group, fs_subgroup,
  is_control_account, allow_subledger, sort_order
)
SELECT t.template_id, '2240', 'Percentage Tax Payable', 'liability', 'credit',
       true, '2000', 'liabilities', 'Current Liabilities', false, false,
       COALESCE(MAX(t.sort_order), 0) + 1
FROM coa_template_lines t
WHERE NOT EXISTS (
  SELECT 1 FROM coa_template_lines x
  WHERE x.template_id = t.template_id AND x.account_code = '2240'
)
GROUP BY t.template_id;

-- Existing companies: adopt an explicitly named account when the chart already
-- has one. Nothing is invented. A company without one simply cannot post
-- percentage tax until an administrator configures the key — the correct
-- fail-closed behaviour, and the message says so.
UPDATE company_accounting_config cfg
SET percentage_tax_payable_account_id = COALESCE(cfg.percentage_tax_payable_account_id, src.account_id)
FROM (
  SELECT DISTINCT ON (a.company_id) a.company_id, a.id AS account_id
  FROM chart_of_accounts a
  WHERE a.is_postable
    AND a.account_type = 'liability'
    AND (a.account_code IN ('2240') OR a.account_name ILIKE '%percentage tax%')
  ORDER BY a.company_id, a.account_code
) src
WHERE src.company_id = cfg.company_id
  AND cfg.percentage_tax_payable_account_id IS NULL;

UPDATE company_accounting_config cfg
SET percentage_tax_expense_account_id = COALESCE(cfg.percentage_tax_expense_account_id, src.account_id)
FROM (
  SELECT DISTINCT ON (a.company_id) a.company_id, a.id AS account_id
  FROM chart_of_accounts a
  WHERE a.is_postable
    AND a.account_type = 'expense'
    AND (a.account_code IN ('6600')
         OR a.account_name ILIKE '%taxes%licenses%'
         OR a.account_name ILIKE '%percentage tax%')
  ORDER BY a.company_id, a.account_code
) src
WHERE src.company_id = cfg.company_id
  AND cfg.percentage_tax_expense_account_id IS NULL;

CREATE OR REPLACE FUNCTION fn_sync_account_mapping_from_config(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cfg   company_accounting_config%ROWTYPE;
  r       RECORD;
  v_count INTEGER := 0;
BEGIN
  SELECT * INTO v_cfg FROM company_accounting_config WHERE company_id = p_company_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  FOR r IN
    SELECT * FROM (VALUES
      ('AR_TRADE',                v_cfg.ar_account_id),
      ('AP_TRADE',                v_cfg.ap_account_id),
      ('VAT_OUTPUT',              v_cfg.vat_payable_account_id),
      ('VAT_INPUT',               v_cfg.input_vat_account_id),
      ('EWT_WITHHELD',            v_cfg.ewt_withheld_account_id),
      ('EWT_PAYABLE',             v_cfg.ewt_payable_account_id),
      ('CASH_DEFAULT',            v_cfg.default_cash_account_id),
      ('CUSTOMER_ADVANCES',       v_cfg.customer_advances_account_id),
      ('SUPPLIER_DOWNPAYMENTS',   v_cfg.supplier_down_payments_account_id),
      ('INVENTORY_CONTROL',       v_cfg.inventory_account_id),
      ('PURCHASE_CLEARING',       v_cfg.purchase_clearing_account_id),
      ('SALES_DELIVERY_CLEARING', v_cfg.sales_delivery_clearing_account_id),
      ('PERCENTAGE_TAX_EXPENSE',  v_cfg.percentage_tax_expense_account_id),
      ('PERCENTAGE_TAX_PAYABLE',  v_cfg.percentage_tax_payable_account_id)
    ) AS t(key_code, account_id)
    WHERE t.account_id IS NOT NULL
  LOOP
    UPDATE account_mapping m
       SET account_id = r.account_id, source = 'config_sync', updated_at = now()
     WHERE m.company_id = p_company_id
       AND m.key_code = r.key_code
       AND m.branch_id IS NULL AND m.document_type IS NULL AND m.party_id IS NULL
       AND m.item_id IS NULL AND m.item_group_id IS NULL AND m.tax_profile_id IS NULL
       AND m.effective_to IS NULL;
    IF NOT FOUND THEN
      INSERT INTO account_mapping (company_id, key_code, account_id, source)
      VALUES (p_company_id, r.key_code, r.account_id, 'config_sync');
    END IF;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION fn_sync_account_mapping_from_config(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_sync_account_mapping_from_config(UUID) TO service_role;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT company_id FROM company_accounting_config LOOP
    PERFORM fn_sync_account_mapping_from_config(r.company_id);
  END LOOP;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. SALES INVOICE — the line carries the code, the document carries the total
--
-- Reproduced whole because a save routine is one act; only the business-tax
-- computation, the four stamped line columns and the document total changed.
-- Every commercial rule, validation, message and side effect is as it was.
-- ═══════════════════════════════════════════════════════════════════════════
-- ── fn_save_sales_invoice_aud053_core ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_save_sales_invoice_aud053_core(p_invoice_id uuid, p_header jsonb, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_si_id          UUID;
  v_company_id     UUID;
  v_branch_id      UUID;
  v_customer_id    UUID;
  v_invoice_date   DATE;
  v_vat_basis      TEXT;
  v_department_id  UUID;
  v_cost_center_id UUID;
  v_warehouse_id   UUID;
  v_salesperson_id UUID;
  v_account_owner_id UUID;
  v_si_number      TEXT;
  v_fiscal_period  UUID;
  v_current_status TEXT;
  v_line           JSONB;
  v_item           items%ROWTYPE;
  v_vat_class      TEXT;
  v_qty            NUMERIC(15,4);
  v_price          NUMERIC(15,4);
  v_disc           NUMERIC(15,2);
  v_commercial     NUMERIC(15,2);
  v_net            NUMERIC(15,2);
  v_vat_amt        NUMERIC(15,2);
  v_total_line     NUMERIC(15,2);
  v_line_no        INT;
  v_line_warehouse_id UUID;
  v_line_department_id UUID;
  v_line_cost_center_id UUID;
  v_line_salesperson_id UUID;
  v_line_revenue_account_id UUID;
  v_line_inventory_account_id UUID;
  v_line_cogs_account_id UUID;
  v_taxable        NUMERIC(15,2) := 0;
  v_zero_rated     NUMERIC(15,2) := 0;
  v_exempt         NUMERIC(15,2) := 0;
  v_total_vat      NUMERIC(15,2) := 0;
  v_pt_code_id     UUID;
  v_pt_base        NUMERIC(15,2);
  v_pt_rate        NUMERIC(9,4);
  v_pt_amt         NUMERIC(15,2);
  v_total_pt       NUMERIC(15,2) := 0;
  v_grand_total    NUMERIC(15,2) := 0;
  v_has_lines      BOOLEAN := false;
  v_customer_cwt   BOOLEAN;
  v_customer_atc   UUID;
  v_cwt_amount     NUMERIC(15,2);
  v_cwt_atc        UUID;
  v_cwt_base       NUMERIC(15,2);
  v_cwt_rate       NUMERIC(9,4);
  v_cwt_expected   NUMERIC(15,2);
BEGIN
  v_company_id := (p_header->>'company_id')::UUID;
  v_branch_id  := (p_header->>'branch_id')::UUID;
  v_customer_id := (p_header->>'customer_id')::UUID;
  v_invoice_date := (p_header->>'date')::DATE;
  v_vat_basis := COALESCE(NULLIF(p_header->>'vat_price_basis', ''), 'exclusive');
  v_department_id := NULLIF(p_header->>'department_id', '')::UUID;
  v_cost_center_id := NULLIF(p_header->>'cost_center_id', '')::UUID;
  v_warehouse_id := NULLIF(p_header->>'warehouse_id', '')::UUID;
  v_salesperson_id := NULLIF(p_header->>'salesperson_id', '')::UUID;
  v_account_owner_id := NULLIF(p_header->>'account_owner_id', '')::UUID;

  IF v_vat_basis NOT IN ('exclusive', 'inclusive') THEN
    RAISE EXCEPTION 'VAT Price Basis must be VAT Exclusive or VAT Inclusive.';
  END IF;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = v_branch_id AND company_id = v_company_id) THEN
    RAISE EXCEPTION 'Branch does not belong to this company';
  END IF;
  IF v_department_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM departments WHERE id = v_department_id AND company_id = v_company_id AND COALESCE(is_active, true) = true
  ) THEN
    RAISE EXCEPTION 'Department does not belong to this company or is inactive';
  END IF;
  IF v_cost_center_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM cost_centers WHERE id = v_cost_center_id AND company_id = v_company_id AND COALESCE(is_active, true) = true
  ) THEN
    RAISE EXCEPTION 'Cost Center does not belong to this company or is inactive';
  END IF;
  IF v_warehouse_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM warehouses WHERE id = v_warehouse_id AND company_id = v_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Warehouse does not belong to this company or is inactive';
  END IF;
  IF v_salesperson_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM employees WHERE id = v_salesperson_id AND company_id = v_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Salesperson does not belong to this company or is inactive';
  END IF;
  IF v_account_owner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM employees WHERE id = v_account_owner_id AND company_id = v_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Account Owner does not belong to this company or is inactive';
  END IF;

  SELECT is_subject_to_cwt, default_cwt_atc_code_id
    INTO v_customer_cwt, v_customer_atc
  FROM customers
  WHERE id = v_customer_id
    AND company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer does not belong to this company';
  END IF;

  SELECT id INTO v_fiscal_period
  FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= v_invoice_date
    AND end_date   >= v_invoice_date
    AND is_locked = false
  LIMIT 1;

  IF p_invoice_id IS NULL THEN
    v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'SI');

    INSERT INTO sales_invoices (
      company_id, branch_id, si_number, date, fiscal_period_id,
      customer_id, customer_name_snapshot, customer_tin_snapshot, customer_address_snapshot,
      payment_terms_id, due_date, currency_code, vat_price_basis, reference, memo,
      department_id, cost_center_id, warehouse_id, salesperson_id, account_owner_id,
      total_taxable_amount, total_zero_rated_amount, total_exempt_amount,
      total_vat_amount, total_percentage_tax_amount,
      total_amount, cwt_amount_expected, cwt_atc_code_id, cwt_tax_base,
      status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_si_number, v_invoice_date, v_fiscal_period,
      v_customer_id, p_header->>'customer_name_snapshot',
      NULLIF(p_header->>'customer_tin_snapshot', ''),
      NULLIF(p_header->>'customer_address_snapshot', ''),
      NULLIF(p_header->>'payment_terms_id', '')::UUID,
      NULLIF(p_header->>'due_date', '')::DATE,
      COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      v_vat_basis,
      NULLIF(p_header->>'reference', ''), NULLIF(p_header->>'memo', ''),
      v_department_id, v_cost_center_id, v_warehouse_id, v_salesperson_id, v_account_owner_id,
      0, 0, 0, 0, 0, 0, NULL, NULL, NULL,
      'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_si_id;

  ELSE
    SELECT id, status INTO v_si_id, v_current_status
    FROM sales_invoices WHERE id = p_invoice_id AND company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Sales invoice not found or access denied';
    END IF;
    IF v_current_status != 'draft' THEN
      RAISE EXCEPTION 'Cannot edit a % sales invoice. Revert to draft first.', v_current_status;
    END IF;

    UPDATE sales_invoices SET
      branch_id = v_branch_id, date = v_invoice_date, fiscal_period_id = v_fiscal_period,
      customer_id = v_customer_id,
      customer_name_snapshot = p_header->>'customer_name_snapshot',
      customer_tin_snapshot = NULLIF(p_header->>'customer_tin_snapshot', ''),
      customer_address_snapshot = NULLIF(p_header->>'customer_address_snapshot', ''),
      payment_terms_id = NULLIF(p_header->>'payment_terms_id', '')::UUID,
      due_date = NULLIF(p_header->>'due_date', '')::DATE,
      currency_code = COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP'),
      vat_price_basis = v_vat_basis,
      reference = NULLIF(p_header->>'reference', ''), memo = NULLIF(p_header->>'memo', ''),
      department_id = v_department_id,
      cost_center_id = v_cost_center_id,
      warehouse_id = v_warehouse_id,
      salesperson_id = v_salesperson_id,
      account_owner_id = v_account_owner_id,
      total_taxable_amount = 0, total_zero_rated_amount = 0, total_exempt_amount = 0,
      total_vat_amount = 0, total_percentage_tax_amount = 0, total_amount = 0,
      cwt_amount_expected = NULL, cwt_atc_code_id = NULL, cwt_tax_base = NULL,
      updated_at = NOW(), updated_by = auth.uid()
    WHERE id = v_si_id;
  END IF;

  DELETE FROM sales_invoice_lines WHERE sales_invoice_id = v_si_id;

  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    v_item := NULL;
    IF NULLIF(v_line->>'item_id', '') IS NOT NULL THEN
      SELECT * INTO v_item
      FROM items
      WHERE id = NULLIF(v_line->>'item_id', '')::UUID
        AND company_id = v_company_id
        AND COALESCE(is_active, true) = true;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Sales invoice item does not belong to this company or is inactive';
      END IF;
    END IF;

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := COALESCE(NULLIF(v_line->>'discount_amount', '')::NUMERIC, 0);
    IF v_disc = 0 AND COALESCE(NULLIF(v_line->>'discount_percent', '')::NUMERIC, 0) > 0 THEN
      v_disc := ROUND(v_qty * v_price * COALESCE((v_line->>'discount_percent')::NUMERIC, 0) / 100, 2);
    END IF;
    v_disc := GREATEST(v_disc, 0);
    v_commercial := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);

    -- The line's business tax comes from the Tax Engine, which owns both price
    -- bases (PAD-001) and both families. This routine previously held the
    -- product's ONLY VAT-inclusive implementation; it is now shared by every
    -- document type. Percentage tax, when the line carries a PT code, is the
    -- seller's own tax: it changes neither the net nor the line total.
    v_pt_code_id := NULLIF(v_line->>'percentage_tax_code_id', '')::UUID;

    SELECT
      MAX(c.classification) FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.net_amount)     FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.tax_amount)     FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.gross_amount)   FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.tax_base)       FILTER (WHERE c.tax_kind = 'percentage_tax'),
      MAX(c.tax_rate)       FILTER (WHERE c.tax_kind = 'percentage_tax'),
      MAX(c.tax_amount)     FILTER (WHERE c.tax_kind = 'percentage_tax')
      INTO v_vat_class, v_net, v_vat_amt, v_total_line, v_pt_base, v_pt_rate, v_pt_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',             v_company_id,
           'document_date',          v_invoice_date,
           'direction',              'sale',
           'amount',                 v_commercial,
           'price_basis',            v_vat_basis,
           'vat_code_id',            NULLIF(v_line->>'vat_code_id', ''),
           'percentage_tax_code_id', v_pt_code_id
         )) c;

    IF v_item.id IS NOT NULL AND v_item.item_type = 'inventory_item' THEN
      v_line_warehouse_id := COALESCE(NULLIF(v_line->>'warehouse_id', '')::UUID, v_warehouse_id);
    ELSE
      v_line_warehouse_id := NULLIF(v_line->>'warehouse_id', '')::UUID;
    END IF;
    v_line_department_id := COALESCE(NULLIF(v_line->>'department_id', '')::UUID, v_department_id);
    v_line_cost_center_id := COALESCE(NULLIF(v_line->>'cost_center_id', '')::UUID, v_cost_center_id);
    v_line_salesperson_id := COALESCE(NULLIF(v_line->>'salesperson_id', '')::UUID, v_salesperson_id);
    v_line_revenue_account_id := COALESCE(NULLIF(v_line->>'revenue_account_id', '')::UUID, v_item.sales_account_id);
    v_line_inventory_account_id := COALESCE(NULLIF(v_line->>'inventory_account_id', '')::UUID, v_item.inventory_account_id);
    v_line_cogs_account_id := COALESCE(NULLIF(v_line->>'cogs_account_id', '')::UUID, v_item.cogs_account_id);

    IF v_line_warehouse_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM warehouses WHERE id = v_line_warehouse_id AND company_id = v_company_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Line warehouse does not belong to this company or is inactive';
    END IF;
    IF v_line_department_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM departments WHERE id = v_line_department_id AND company_id = v_company_id AND COALESCE(is_active, true) = true
    ) THEN
      RAISE EXCEPTION 'Line department does not belong to this company or is inactive';
    END IF;
    IF v_line_cost_center_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM cost_centers WHERE id = v_line_cost_center_id AND company_id = v_company_id AND COALESCE(is_active, true) = true
    ) THEN
      RAISE EXCEPTION 'Line cost center does not belong to this company or is inactive';
    END IF;
    IF v_line_salesperson_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM employees WHERE id = v_line_salesperson_id AND company_id = v_company_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Line salesperson does not belong to this company or is inactive';
    END IF;

    CASE v_vat_class
      WHEN 'regular' THEN v_taxable := v_taxable + v_net;
      WHEN 'zero_rated' THEN v_zero_rated := v_zero_rated + v_net;
      ELSE v_exempt := v_exempt + v_net;
    END CASE;
    v_total_vat   := v_total_vat + v_vat_amt;
    v_total_pt    := v_total_pt + COALESCE(v_pt_amt, 0);
    v_grand_total := v_grand_total + v_total_line;
    v_has_lines   := true;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number,
      item_id, description, quantity, uom_id,
      unit_price, discount_percent, discount_amount,
      net_amount, vat_code_id, vat_amount, total_amount,
      percentage_tax_code_id, percentage_tax_base, percentage_tax_rate, percentage_tax_amount,
      revenue_account_id, warehouse_id, department_id, cost_center_id, salesperson_id,
      inventory_account_id, cogs_account_id, remarks, source_document_type, source_line_id,
      created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id', '')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id', '')::UUID,
      v_price,
      COALESCE((v_line->>'discount_percent')::NUMERIC, 0),
      v_disc,
      v_net, NULLIF(v_line->>'vat_code_id', '')::UUID, v_vat_amt, v_total_line,
      v_pt_code_id, v_pt_base, v_pt_rate, v_pt_amt,
      v_line_revenue_account_id, v_line_warehouse_id, v_line_department_id, v_line_cost_center_id, v_line_salesperson_id,
      v_line_inventory_account_id, v_line_cogs_account_id, NULLIF(v_line->>'remarks', ''),
      NULLIF(v_line->>'source_document_type', ''), NULLIF(v_line->>'source_line_id', '')::UUID,
      auth.uid(), auth.uid()
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'At least one non-empty line item is required';
  END IF;

  v_cwt_amount := NULLIF(p_header->>'cwt_amount_expected', '')::NUMERIC;
  IF COALESCE(v_cwt_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Expected CWT cannot be negative';
  END IF;

  IF COALESCE(v_cwt_amount, 0) > 0 THEN
    IF NOT COALESCE(v_customer_cwt, false) THEN
      RAISE EXCEPTION 'Expected CWT is only allowed when the customer is subject to CWT';
    END IF;
    IF v_customer_atc IS NULL THEN
      RAISE EXCEPTION 'Customer is subject to CWT but has no default CWT ATC';
    END IF;

    v_cwt_atc := COALESCE(NULLIF(p_header->>'cwt_atc_code_id', '')::UUID, v_customer_atc);
    IF v_cwt_atc <> v_customer_atc THEN
      RAISE EXCEPTION 'Sales invoice expected CWT ATC must match the customer default CWT ATC';
    END IF;
    IF NOT fn_atc_code_is_current(v_cwt_atc, 'ewt', v_invoice_date) THEN
      RAISE EXCEPTION 'Customer default CWT ATC is not active/current on the sales invoice date';
    END IF;

    v_cwt_base := COALESCE(
      NULLIF(p_header->>'cwt_tax_base', '')::NUMERIC,
      ROUND(v_taxable + v_zero_rated + v_exempt, 2)
    );
    IF COALESCE(v_cwt_base, 0) <= 0 THEN
      RAISE EXCEPTION 'Expected CWT taxable base must be positive when expected CWT is recorded';
    END IF;

    -- Expected creditable withholding also comes from the Tax Engine.
    SELECT c.tax_rate, c.tax_amount INTO v_cwt_rate, v_cwt_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           v_invoice_date,
           'direction',               'sale',
           'amount',                  0,
           'withholding_atc_code_id', v_cwt_atc,
           'withholding_base',        v_cwt_base
         )) c
    WHERE c.tax_kind = 'ewt';
    v_cwt_expected := COALESCE(v_cwt_expected, 0);
    IF ABS(v_cwt_expected - v_cwt_amount) > 0.02 THEN
      RAISE EXCEPTION 'Sales invoice expected CWT % does not match customer ATC expected % on base %',
        v_cwt_amount, v_cwt_expected, v_cwt_base;
    END IF;
  ELSE
    v_cwt_amount := NULL;
    v_cwt_atc := NULL;
    v_cwt_base := NULL;
  END IF;

  UPDATE sales_invoices SET
    total_taxable_amount    = v_taxable,
    total_zero_rated_amount = v_zero_rated,
    total_exempt_amount     = v_exempt,
    total_vat_amount        = v_total_vat,
    total_percentage_tax_amount = v_total_pt,
    total_amount            = v_grand_total,
    cwt_amount_expected     = v_cwt_amount,
    cwt_atc_code_id         = v_cwt_atc,
    cwt_tax_base            = v_cwt_base,
    updated_at              = NOW(),
    updated_by              = auth.uid()
  WHERE id = v_si_id;

  RETURN v_si_id;
END;
$function$

;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. SALES INVOICE POSTING — the liability reaches the ledger
-- ═══════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.fn_post_delivery_receipt(UUID) TO authenticated, service_role;

-- ── 4. Sales Invoice consumes the clearing instead of relieving twice ──────
CREATE OR REPLACE FUNCTION public.fn_post_sales_invoice(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_begin JSONB;
  v_rec sales_invoices%ROWTYPE;
  v_ar UUID;
  v_vat UUID;
  v_pt_expense UUID;
  v_pt_payable UUID;
  v_total_pt NUMERIC(15,2);
  v_pt RECORD;
  v_clearing UUID;
  v_je_id UUID;
  v_fp_id UUID;
  v_line RECORD;
  v_inv_line RECORD;
  v_tax RECORD;
  v_stock stock_balances%ROWTYPE;
  v_layer RECORD;
  v_line_no INTEGER := 1;
  v_total_debit NUMERIC(15,2) := 0;
  v_total_credit NUMERIC(15,2) := 0;
  v_total_cost NUMERIC(18,2);
  v_unit_cost NUMERIC(18,6);
  v_inventory_tx_id UUID;
  v_delivered_cost NUMERIC(18,2);
BEGIN
  v_begin := fn_begin_source_posting(
    'SI', p_invoice_id, ARRAY['approved'], ARRAY['posted']
  );
  IF NOT (v_begin->>'should_post')::BOOLEAN THEN
    RETURN;
  END IF;

  SELECT * INTO STRICT v_rec FROM sales_invoices WHERE id = p_invoice_id;
  PERFORM fn_validate_sales_invoice_accounting_ready(p_invoice_id);
  PERFORM fn_validate_sales_invoice_vat_registration(p_invoice_id);
  PERFORM fn_validate_invoice_posting_totals('SI', p_invoice_id);

  -- COA resolver adoption (P2A): AR control + Output VAT via fn_resolve_account.
  v_ar := fn_resolve_posting_account(v_rec.company_id, 'AR_TRADE', v_rec.date,
            'AR control account not configured. Set it up in GL Posting Configuration.');
  IF v_rec.total_vat_amount > 0 THEN
    v_vat := fn_resolve_posting_account(v_rec.company_id, 'VAT_OUTPUT', v_rec.date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  -- Percentage tax is read from the lines, not from the header total: the lines
  -- are where the engine stamped it, and RLS lets a member write a line directly.
  SELECT COALESCE(SUM(sil.percentage_tax_amount), 0)
    INTO v_total_pt
  FROM sales_invoice_lines sil
  WHERE sil.sales_invoice_id = p_invoice_id;

  IF v_total_pt > 0 THEN
    v_pt_expense := fn_resolve_posting_account(v_rec.company_id, 'PERCENTAGE_TAX_EXPENSE', v_rec.date,
                      'Percentage Tax Expense account not configured. Set it up in GL Posting Configuration.');
    v_pt_payable := fn_resolve_posting_account(v_rec.company_id, 'PERCENTAGE_TAX_PAYABLE', v_rec.date,
                      'Percentage Tax Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_rec.company_id, v_rec.branch_id,
    'JE-SI-' || v_rec.si_number, v_rec.date,
    'Sales Invoice ' || v_rec.si_number || ' - ' || v_rec.customer_name_snapshot,
    'SI', v_rec.id,
    NULL, 'posted', 0, 0, 'system', 'regular', false, true
  );
  SELECT fiscal_period_id INTO v_fp_id FROM journal_entries WHERE id = v_je_id;

  PERFORM fn_add_sales_invoice_posting_line(
    v_je_id, 1, v_ar,
    'AR - ' || v_rec.customer_name_snapshot,
    v_rec.total_amount, 0,
    v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
    v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
  );
  v_line_no := 2;
  v_total_debit := v_rec.total_amount;

  FOR v_line IN
    SELECT sil.revenue_account_id, SUM(sil.net_amount) AS net_sum,
           sil.description AS line_description,
           COALESCE(sil.department_id, v_rec.department_id) AS department_id,
           COALESCE(sil.cost_center_id, v_rec.cost_center_id) AS cost_center_id,
           COALESCE(sil.project_id, v_rec.project_id) AS project_id,
           COALESCE(sil.location_id, v_rec.location_id) AS location_id,
           COALESCE(
             sil.functional_entity_id, v_rec.functional_entity_id
           ) AS functional_entity_id
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.revenue_account_id IS NOT NULL
    GROUP BY sil.revenue_account_id, sil.description,
             COALESCE(sil.department_id, v_rec.department_id),
             COALESCE(sil.cost_center_id, v_rec.cost_center_id),
             COALESCE(sil.project_id, v_rec.project_id),
             COALESCE(sil.location_id, v_rec.location_id),
             COALESCE(sil.functional_entity_id, v_rec.functional_entity_id)
  LOOP
    PERFORM fn_add_sales_invoice_posting_line(
      v_je_id, v_line_no, v_line.revenue_account_id,
      'Revenue - ' || v_line.line_description,
      0, v_line.net_sum,
      v_rec.branch_id, v_line.department_id, v_line.cost_center_id,
      v_line.project_id, v_line.location_id, v_line.functional_entity_id
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_line.net_sum;
  END LOOP;

  IF v_rec.total_vat_amount > 0 THEN
    PERFORM fn_add_sales_invoice_posting_line(
      v_je_id, v_line_no, v_vat,
      'Output VAT - ' || v_rec.si_number,
      0, v_rec.total_vat_amount,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_rec.total_vat_amount;
  END IF;

  -- ── Percentage tax: the seller's own business tax ────────────────────────
  -- DR expense / CR payable. Equal and opposite, so the receivable and the
  -- revenue the customer sees are untouched: the customer was never charged it.
  IF v_total_pt > 0 THEN
    PERFORM fn_add_sales_invoice_posting_line(
      v_je_id, v_line_no, v_pt_expense,
      'Percentage tax - ' || v_rec.si_number,
      v_total_pt, 0,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_line_no := v_line_no + 1;
    v_total_debit := v_total_debit + v_total_pt;

    PERFORM fn_add_sales_invoice_posting_line(
      v_je_id, v_line_no, v_pt_payable,
      'Percentage tax payable - ' || v_rec.si_number,
      0, v_total_pt,
      v_rec.branch_id, v_rec.department_id, v_rec.cost_center_id,
      v_rec.project_id, v_rec.location_id, v_rec.functional_entity_id
    );
    v_line_no := v_line_no + 1;
    v_total_credit := v_total_credit + v_total_pt;
  END IF;

  FOR v_inv_line IN
    SELECT sil.*,
           i.item_code,
           i.description AS item_description,
           i.item_type,
           COALESCE(i.costing_method, 'weighted_average') AS costing_method,
           COALESCE(sil.inventory_account_id, i.inventory_account_id) AS resolved_inventory_account_id,
           COALESCE(sil.cogs_account_id, i.cogs_account_id) AS resolved_cogs_account_id,
           -- The cost already relieved by a delivery, if this line bills one.
           (SELECT drl.inventory_cost
              FROM delivery_receipt_lines drl
             WHERE drl.id = sil.source_line_id
               AND sil.source_document_type = 'DR') AS delivered_cost
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    WHERE sil.sales_invoice_id = v_rec.id
      AND i.item_type = 'inventory_item'
  LOOP
    IF v_inv_line.resolved_inventory_account_id IS NULL
       OR v_inv_line.resolved_cogs_account_id IS NULL THEN
      RAISE EXCEPTION 'Inventory and COGS accounts are required for inventory item line %', v_inv_line.line_number;
    END IF;

    v_delivered_cost := v_inv_line.delivered_cost;

    -- ── The line bills a delivery that already relieved the stock ──────────
    -- The cost is sitting in Goods Delivered Not Invoiced. Recognise it as COGS
    -- and clear it; do NOT touch stock, which left at delivery.
    IF v_delivered_cost IS NOT NULL THEN
      IF v_delivered_cost > 0 THEN
        v_clearing := fn_resolve_posting_account(
          v_rec.company_id, 'SALES_DELIVERY_CLEARING', v_rec.date,
          'Goods Delivered Not Invoiced account not configured. Set it up in GL Posting Configuration.');

        PERFORM fn_add_sales_invoice_posting_line(
          v_je_id, v_line_no, v_inv_line.resolved_cogs_account_id,
          'COGS - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
          v_delivered_cost, 0,
          v_rec.branch_id,
          COALESCE(v_inv_line.department_id, v_rec.department_id),
          COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
          COALESCE(v_inv_line.project_id, v_rec.project_id),
          COALESCE(v_inv_line.location_id, v_rec.location_id),
          COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
        );
        v_line_no := v_line_no + 1;
        PERFORM fn_add_sales_invoice_posting_line(
          v_je_id, v_line_no, v_clearing,
          'Goods delivered not invoiced cleared - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
          0, v_delivered_cost,
          v_rec.branch_id,
          COALESCE(v_inv_line.department_id, v_rec.department_id),
          COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
          COALESCE(v_inv_line.project_id, v_rec.project_id),
          COALESCE(v_inv_line.location_id, v_rec.location_id),
          COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
        );
        v_line_no := v_line_no + 1;
        v_total_debit := v_total_debit + v_delivered_cost;
        v_total_credit := v_total_credit + v_delivered_cost;
      END IF;

      PERFORM set_config('pxl.sales_invoice_posting_internal', 'on', true);
      UPDATE sales_invoice_lines
      SET inventory_account_id = v_inv_line.resolved_inventory_account_id,
          cogs_account_id = v_inv_line.resolved_cogs_account_id,
          unit_cost = (SELECT drl.unit_cost FROM delivery_receipt_lines drl
                        WHERE drl.id = v_inv_line.source_line_id),
          inventory_cost = v_delivered_cost,
          updated_by = auth.uid(),
          updated_at = NOW()
      WHERE id = v_inv_line.id;
      PERFORM set_config('pxl.sales_invoice_posting_internal', '', true);

      CONTINUE;
    END IF;

    IF v_inv_line.warehouse_id IS NULL THEN
      RAISE EXCEPTION 'Warehouse is required for inventory item line %', v_inv_line.line_number;
    END IF;

    PERFORM fn_ensure_stock_balance(
      v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id
    );
    SELECT * INTO v_stock
    FROM stock_balances
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id
    FOR UPDATE;

    IF COALESCE(v_stock.qty_on_hand, 0) < v_inv_line.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for item %. On hand: %, requested: %',
        v_inv_line.item_code, COALESCE(v_stock.qty_on_hand, 0), v_inv_line.quantity;
    END IF;

    v_total_cost := 0;
    v_unit_cost := 0;

    IF v_inv_line.costing_method = 'weighted_average' THEN
      v_unit_cost := COALESCE(v_stock.wac_unit_cost, 0);
      v_total_cost := ROUND(v_inv_line.quantity * v_unit_cost, 2);
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
          v_inv_line.quantity, NULL, NULL
        )
      LOOP
        v_total_cost := v_total_cost + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
        v_unit_cost := v_layer.unit_cost;
      END LOOP;
      IF v_inv_line.quantity > 0 THEN
        v_unit_cost := ROUND(v_total_cost / v_inv_line.quantity, 6);
      END IF;
    END IF;

    UPDATE stock_balances
    SET qty_on_hand = qty_on_hand - v_inv_line.quantity,
        total_cost = GREATEST(total_cost - v_total_cost, 0),
        last_issue_date = v_rec.date,
        updated_at = NOW()
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id;

    IF v_inv_line.costing_method = 'weighted_average' THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE
        WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_inv_line.warehouse_id
        AND item_id = v_inv_line.item_id;
    END IF;

    IF v_total_cost > 0 THEN
      PERFORM fn_add_sales_invoice_posting_line(
        v_je_id, v_line_no, v_inv_line.resolved_cogs_account_id,
        'COGS - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        v_total_cost, 0,
        v_rec.branch_id,
        COALESCE(v_inv_line.department_id, v_rec.department_id),
        COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
        COALESCE(v_inv_line.project_id, v_rec.project_id),
        COALESCE(v_inv_line.location_id, v_rec.location_id),
        COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
      );
      v_line_no := v_line_no + 1;
      PERFORM fn_add_sales_invoice_posting_line(
        v_je_id, v_line_no, v_inv_line.resolved_inventory_account_id,
        'Inventory - ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        0, v_total_cost,
        v_rec.branch_id,
        COALESCE(v_inv_line.department_id, v_rec.department_id),
        COALESCE(v_inv_line.cost_center_id, v_rec.cost_center_id),
        COALESCE(v_inv_line.project_id, v_rec.project_id),
        COALESCE(v_inv_line.location_id, v_rec.location_id),
        COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
      );
      v_line_no := v_line_no + 1;
      v_total_debit := v_total_debit + v_total_cost;
      v_total_credit := v_total_credit + v_total_cost;
    END IF;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by,
      project_id, location_id, functional_entity_id
    )
    SELECT v_rec.company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
      'issue', v_rec.date,
      -v_inv_line.quantity, v_unit_cost, -v_total_cost,
      qty_on_hand, v_inv_line.costing_method,
      'SI', v_rec.id, v_je_id,
      'Sales Invoice ' || v_rec.si_number || ' line ' || v_inv_line.line_number,
      auth.uid(),
      COALESCE(v_inv_line.project_id, v_rec.project_id),
      COALESCE(v_inv_line.location_id, v_rec.location_id),
      COALESCE(v_inv_line.functional_entity_id, v_rec.functional_entity_id)
    FROM stock_balances
    WHERE warehouse_id = v_inv_line.warehouse_id
      AND item_id = v_inv_line.item_id
    RETURNING id INTO v_inventory_tx_id;

    PERFORM set_config('pxl.sales_invoice_posting_internal', 'on', true);
    UPDATE sales_invoice_lines
    SET inventory_account_id = v_inv_line.resolved_inventory_account_id,
        cogs_account_id = v_inv_line.resolved_cogs_account_id,
        unit_cost = v_unit_cost,
        inventory_cost = v_total_cost,
        inventory_transaction_id = v_inventory_tx_id,
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE id = v_inv_line.id;
    PERFORM set_config('pxl.sales_invoice_posting_internal', '', true);
  END LOOP;

  IF ABS(v_total_debit - v_total_credit) > 0.02 THEN
    RAISE EXCEPTION 'Journal entry would be unbalanced: DR=% CR=%. Check line revenue, VAT, inventory, and COGS configuration.',
      v_total_debit, v_total_credit;
  END IF;

  PERFORM fn_finalize_journal_entry(v_je_id);

  UPDATE sales_invoices
  SET status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
      journal_entry_id = v_je_id, updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  FOR v_tax IN
    SELECT sil.vat_code_id,
           SUM(sil.net_amount) AS tax_base,
           COALESCE(SUM(sil.vat_amount), 0) AS tax_amount
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.vat_code_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM companies c
        WHERE c.id = v_rec.company_id AND c.tax_registration = 'vat'
      )
    GROUP BY sil.vat_code_id
    HAVING SUM(sil.net_amount) <> 0
       OR COALESCE(SUM(sil.vat_amount), 0) <> 0
  LOOP
    PERFORM fn_add_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'SI', v_rec.id, NULL,
      'output_vat', NULL, v_tax.vat_code_id, NULL,
      v_tax.tax_base, NULL, v_tax.tax_amount, v_fp_id,
      CURRENT_DATE, v_rec.date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;

  -- ── Percentage tax ledger: one row per code, the 2551Q is filed per ATC ──
  -- The tax-code version and its rate are stamped on the row, so the working
  -- paper reads the rate that applied without re-resolving configuration.
  FOR v_pt IN
    SELECT sil.percentage_tax_code_id,
           ptc.tax_code_id,
           ptc.atc_id,
           MAX(sil.percentage_tax_rate)               AS tax_rate,
           SUM(sil.percentage_tax_base)               AS tax_base,
           COALESCE(SUM(sil.percentage_tax_amount),0) AS tax_amount
    FROM sales_invoice_lines sil
    JOIN percentage_tax_codes ptc ON ptc.id = sil.percentage_tax_code_id
    WHERE sil.sales_invoice_id = v_rec.id
      AND sil.percentage_tax_code_id IS NOT NULL
    GROUP BY sil.percentage_tax_code_id, ptc.tax_code_id, ptc.atc_id
    HAVING COALESCE(SUM(sil.percentage_tax_amount), 0) <> 0
  LOOP
    PERFORM fn_add_percentage_tax_detail(
      v_rec.company_id, v_rec.branch_id, 'SI', v_rec.id,
      v_pt.percentage_tax_code_id, v_pt.tax_code_id, v_pt.atc_id,
      v_pt.tax_base, v_pt.tax_rate, v_pt.tax_amount, v_fp_id,
      v_rec.date,
      v_rec.customer_id, v_rec.customer_tin_snapshot, v_rec.customer_name_snapshot
    );
  END LOOP;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'SI', v_rec.id, 'POSTED', v_je_id,
    jsonb_build_object('posting_date', v_rec.date)
  );
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. CASH SALE — the counter sale a non-VAT retailer actually rings up
-- ═══════════════════════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_save_cash_sale(
  p_header jsonb, p_lines jsonb, p_cwt_amount numeric DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_company_id    UUID;
  v_branch_id     UUID;
  v_date          DATE;
  v_basis         TEXT;
  v_hdr_warehouse UUID;
  v_hdr_dept      UUID;
  v_hdr_cc        UUID;
  v_si_id         UUID;
  v_receipt_id    UUID;
  v_si_number     TEXT;
  v_or_number     TEXT;
  v_ar            UUID;
  v_vat           UUID;
  v_cwt           UUID;
  v_cash_acct     UUID;
  v_fp_id         UUID;
  v_je_si_id      UUID;
  v_je_or_id      UUID;
  v_grand_total   NUMERIC(15,2) := 0;
  v_total_vat     NUMERIC(15,2) := 0;
  v_total_taxable NUMERIC(15,2) := 0;
  v_total_zero    NUMERIC(15,2) := 0;
  v_total_exempt  NUMERIC(15,2) := 0;
  v_total_pt      NUMERIC(15,2) := 0;
  v_pt_expense    UUID;
  v_pt_payable    UUID;
  v_pt_code_id    UUID;
  v_pt_base       NUMERIC(15,2);
  v_pt_rate       NUMERIC(9,4);
  v_pt_amt        NUMERIC(15,2);
  v_pt            RECORD;
  v_total_cogs    NUMERIC(15,2) := 0;
  v_line_cwt      NUMERIC(15,2) := 0;
  v_line_cwt_base NUMERIC(15,2) := 0;
  v_cwt_total     NUMERIC(15,2) := 0;
  v_cwt_source    TEXT := 'atc';
  v_rev_line      RECORD;
  v_inv_line      RECORD;
  v_line_no       INT;
  v_line          JSONB;
  v_item          items%ROWTYPE;
  v_qty           NUMERIC(15,4);
  v_price         NUMERIC(15,4);
  v_disc          NUMERIC(15,2);
  v_commercial    NUMERIC(15,2);
  v_net           NUMERIC(15,2);
  v_vat_amt       NUMERIC(15,2);
  v_class         TEXT;
  v_wht_atc       UUID;
  v_wht_amt       NUMERIC(15,2);
  v_wht_base      NUMERIC(15,2);
  v_wht_rate      NUMERIC(9,4);
  v_has_lines     BOOLEAN := false;
  v_line_warehouse UUID;
  v_line_dept     UUID;
  v_line_cc       UUID;
  v_cwt_atc       UUID;
  v_cwt_rate      NUMERIC;
  v_cash_received NUMERIC(15,2);
  v_net_of_vat    NUMERIC(15,2);
  v_cwt_base      NUMERIC(15,2);
  v_cwt_exclusive_expected NUMERIC(15,2);
  v_cwt_gross_expected     NUMERIC(15,2);
  v_stock         stock_balances%ROWTYPE;
  v_layer         RECORD;
  v_total_cost    NUMERIC(18,2);
  v_unit_cost     NUMERIC(18,6);
  v_inventory_tx_id UUID;
BEGIN
  v_company_id    := (p_header->>'company_id')::UUID;
  v_branch_id     := NULLIF(p_header->>'branch_id','')::UUID;
  v_date          := (p_header->>'date')::DATE;
  v_basis         := LOWER(COALESCE(NULLIF(p_header->>'vat_price_basis',''), 'exclusive'));
  v_hdr_warehouse := NULLIF(p_header->>'warehouse_id','')::UUID;
  v_hdr_dept      := NULLIF(p_header->>'department_id','')::UUID;
  v_hdr_cc        := NULLIF(p_header->>'cost_center_id','')::UUID;

  IF NOT is_company_member(v_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;
  IF v_basis NOT IN ('exclusive', 'inclusive') THEN
    RAISE EXCEPTION 'VAT Price Basis must be VAT Exclusive or VAT Inclusive.';
  END IF;

  -- COA resolver adoption (P2A). AR is always required; cash/CWT/VAT are conditional.
  v_ar := fn_resolve_posting_account(v_company_id, 'AR_TRADE', v_date,
            'AR control account not configured. Set it up in GL Posting Configuration.');

  v_cash_acct := NULLIF(p_header->>'bank_account_id','')::UUID;
  IF v_cash_acct IS NULL THEN
    v_cash_acct := fn_resolve_posting_account(v_company_id, 'CASH_DEFAULT', v_date,
                     'No cash/bank account specified and no default cash account configured.');
  END IF;

  -- CWT requires an ATC (PXL-AUD-007 rules, enforced by the receipt-line
  -- validator); the document-level ATC travels in the header as cwt_atc_id.
  v_cwt_atc := NULLIF(p_header->>'cwt_atc_id','')::UUID;

  SELECT id INTO v_fp_id FROM fiscal_periods
  WHERE company_id = v_company_id
    AND start_date <= v_date
    AND end_date   >= v_date
    AND is_locked = false
  LIMIT 1;
  IF v_fp_id IS NULL THEN
    RAISE EXCEPTION 'No open fiscal period found for date %. Create or unlock a fiscal period.', v_date;
  END IF;

  -- Number series
  v_si_number := fn_next_document_number(v_company_id, v_branch_id, 'CS');
  v_or_number := fn_next_document_number(v_company_id, v_branch_id, 'OR');

  -- Draft header first: the lines are the source of every total, and the line
  -- guards require the invoice to be a draft while they are written.
  INSERT INTO sales_invoices (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    si_number, date, due_date, currency_code, memo, vat_price_basis,
    department_id, cost_center_id, warehouse_id,
    total_amount, total_vat_amount, total_taxable_amount,
    total_zero_rated_amount, total_exempt_amount,
    is_cash_sale, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id,
    (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot',
    NULLIF(p_header->>'customer_tin_snapshot',''),
    v_si_number, v_date, v_date,
    COALESCE(NULLIF(p_header->>'currency_code',''),'PHP'),
    NULLIF(p_header->>'memo',''), v_basis,
    v_hdr_dept, v_hdr_cc, v_hdr_warehouse,
    0, 0, 0, 0, 0,
    true, 'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_si_id;

  -- ── One pass: the Tax Engine prices each line, the line is written, the
  -- document totals accumulate. UI preview values are never trusted.
  v_line_no := 1;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN NULLIF(TRIM(v_line->>'description'), '') IS NULL;

    v_item := NULL;
    IF NULLIF(v_line->>'item_id','') IS NOT NULL THEN
      SELECT * INTO v_item FROM items
      WHERE id = NULLIF(v_line->>'item_id','')::UUID
        AND company_id = v_company_id
        AND COALESCE(is_active, true) = true;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cash sale item does not belong to this company or is inactive';
      END IF;
    END IF;

    v_qty   := GREATEST(COALESCE((v_line->>'quantity')::NUMERIC, 1), 0);
    v_price := GREATEST(COALESCE((v_line->>'unit_price')::NUMERIC, 0), 0);
    v_disc  := COALESCE(NULLIF(v_line->>'discount_amount','')::NUMERIC, 0);
    IF v_disc = 0 AND COALESCE(NULLIF(v_line->>'discount_percent','')::NUMERIC, 0) > 0 THEN
      v_disc := ROUND(v_qty * v_price * (v_line->>'discount_percent')::NUMERIC / 100, 2);
    END IF;
    v_disc := GREATEST(v_disc, 0);
    v_commercial := GREATEST(ROUND(v_qty * v_price - v_disc, 2), 0);

    v_wht_atc    := NULLIF(v_line->>'withholding_atc_code_id','')::UUID;
    v_pt_code_id := NULLIF(v_line->>'percentage_tax_code_id','')::UUID;

    -- Business tax and withholding tax for this line, from the one engine, on
    -- the document date, in the document's price basis. Business tax is either
    -- family: VAT for a VAT company, percentage tax for a Section 116 one.
    SELECT
      MAX(c.classification)  FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.net_amount)      FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.tax_amount)      FILTER (WHERE c.tax_kind IN ('input_vat','output_vat')),
      MAX(c.tax_base)        FILTER (WHERE c.tax_kind = 'percentage_tax'),
      MAX(c.tax_rate)        FILTER (WHERE c.tax_kind = 'percentage_tax'),
      MAX(c.tax_amount)      FILTER (WHERE c.tax_kind = 'percentage_tax'),
      MAX(c.tax_base)        FILTER (WHERE c.tax_kind = 'ewt'),
      MAX(c.tax_rate)        FILTER (WHERE c.tax_kind = 'ewt'),
      MAX(c.tax_amount)      FILTER (WHERE c.tax_kind = 'ewt')
      INTO v_class, v_net, v_vat_amt, v_pt_base, v_pt_rate, v_pt_amt,
           v_wht_base, v_wht_rate, v_wht_amt
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           v_date,
           'direction',               'sale',
           'amount',                  v_commercial,
           'price_basis',             v_basis,
           'vat_code_id',             NULLIF(v_line->>'vat_code_id',''),
           'percentage_tax_code_id',  v_pt_code_id,
           'withholding_atc_code_id', v_wht_atc
         )) c;

    IF v_wht_atc IS NOT NULL AND v_wht_amt IS NULL THEN
      RAISE EXCEPTION 'Line % withholding tax code is inactive, deprecated, or not effective on %.',
        v_line_no, v_date;
    END IF;

    v_line_warehouse := COALESCE(NULLIF(v_line->>'warehouse_id','')::UUID, v_hdr_warehouse);
    v_line_dept      := COALESCE(NULLIF(v_line->>'department_id','')::UUID, v_hdr_dept);
    v_line_cc        := COALESCE(NULLIF(v_line->>'cost_center_id','')::UUID, v_hdr_cc);

    IF v_line_warehouse IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM warehouses WHERE id = v_line_warehouse AND company_id = v_company_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Line warehouse does not belong to this company or is inactive';
    END IF;

    INSERT INTO sales_invoice_lines (
      sales_invoice_id, company_id, line_number, item_id, description,
      quantity, uom_id, unit_price, discount_percent, discount_amount, net_amount,
      vat_code_id, vat_amount, total_amount,
      percentage_tax_code_id, percentage_tax_base, percentage_tax_rate, percentage_tax_amount,
      withholding_atc_code_id, withholding_tax_base, withholding_tax_rate, withholding_tax_amount,
      revenue_account_id, inventory_account_id, cogs_account_id,
      warehouse_id, department_id, cost_center_id, salesperson_id, remarks,
      created_by, updated_by
    ) VALUES (
      v_si_id, v_company_id, v_line_no,
      NULLIF(v_line->>'item_id','')::UUID, v_line->>'description',
      v_qty, NULLIF(v_line->>'uom_id','')::UUID, v_price,
      COALESCE(NULLIF(v_line->>'discount_percent','')::NUMERIC, 0), v_disc, v_net,
      NULLIF(v_line->>'vat_code_id','')::UUID, v_vat_amt, v_net + v_vat_amt,
      v_pt_code_id, v_pt_base, v_pt_rate, v_pt_amt,
      v_wht_atc, v_wht_base, v_wht_rate, v_wht_amt,
      COALESCE(NULLIF(v_line->>'revenue_account_id','')::UUID, v_item.sales_account_id),
      COALESCE(NULLIF(v_line->>'inventory_account_id','')::UUID, v_item.inventory_account_id),
      COALESCE(NULLIF(v_line->>'cogs_account_id','')::UUID, v_item.cogs_account_id),
      v_line_warehouse, v_line_dept, v_line_cc,
      NULLIF(v_line->>'salesperson_id','')::UUID, NULLIF(v_line->>'remarks',''),
      auth.uid(), auth.uid()
    );

    v_grand_total := v_grand_total + v_net + v_vat_amt;
    v_total_vat   := v_total_vat + v_vat_amt;
    v_total_pt    := v_total_pt + COALESCE(v_pt_amt, 0);
    CASE v_class
      WHEN 'regular'    THEN v_total_taxable := v_total_taxable + v_net;
      WHEN 'zero_rated' THEN v_total_zero    := v_total_zero + v_net;
      ELSE                   v_total_exempt  := v_total_exempt + v_net;
    END CASE;
    IF v_wht_atc IS NOT NULL THEN
      v_line_cwt      := v_line_cwt + COALESCE(v_wht_amt, 0);
      v_line_cwt_base := v_line_cwt_base + COALESCE(v_wht_base, 0);
    END IF;
    v_has_lines := true;
    v_line_no   := v_line_no + 1;
  END LOOP;

  IF NOT v_has_lines THEN
    RAISE EXCEPTION 'Cash sale must have at least one line with a description.';
  END IF;

  -- ── Which withholding convention is this document using? ─────────────────
  IF v_line_cwt > 0 THEN
    v_cwt_source := 'invoice_lines';
    IF COALESCE(p_cwt_amount, 0) > 0
       AND ABS(COALESCE(p_cwt_amount, 0) - v_line_cwt) > 0.02 THEN
      RAISE EXCEPTION 'Cash sale CWT % does not match the line-level withholding total %.',
        p_cwt_amount, v_line_cwt;
    END IF;
    IF v_cwt_atc IS NOT NULL THEN
      RAISE EXCEPTION 'A cash sale whose lines carry withholding tax codes must not also carry a document-level ATC.';
    END IF;
    v_cwt_total := v_line_cwt;
    v_cwt_base  := v_line_cwt_base;
  ELSE
    v_cwt_total := COALESCE(p_cwt_amount, 0);
  END IF;

  -- Output VAT account is required once there is VAT to post.
  IF v_total_vat > 0 THEN
    v_vat := fn_resolve_posting_account(v_company_id, 'VAT_OUTPUT', v_date,
               'VAT Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;
  IF v_cwt_total > 0 THEN
    v_cwt := fn_resolve_posting_account(v_company_id, 'EWT_WITHHELD', v_date,
               'EWT Withheld (CWT Receivable) account not configured. Set it up in GL Posting Configuration.');
  END IF;
  IF v_total_pt > 0 THEN
    v_pt_expense := fn_resolve_posting_account(v_company_id, 'PERCENTAGE_TAX_EXPENSE', v_date,
                      'Percentage Tax Expense account not configured. Set it up in GL Posting Configuration.');
    v_pt_payable := fn_resolve_posting_account(v_company_id, 'PERCENTAGE_TAX_PAYABLE', v_date,
                      'Percentage Tax Payable account not configured. Set it up in GL Posting Configuration.');
  END IF;

  UPDATE sales_invoices SET
    total_amount            = v_grand_total,
    total_vat_amount        = v_total_vat,
    total_percentage_tax_amount = v_total_pt,
    total_taxable_amount    = v_total_taxable,
    total_zero_rated_amount = v_total_zero,
    total_exempt_amount     = v_total_exempt,
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_si_id;

  -- ── Inventory costing, while the invoice is still a draft ────────────────
  -- Same path as fn_post_sales_invoice: lock the balance, cost the issue by the
  -- item's costing method, relieve stock, and write the resolved cost back to
  -- the line. The journal needs the total before it is created, so the costing
  -- runs first and the GL lines follow.
  FOR v_inv_line IN
    SELECT sil.id, sil.line_number, sil.item_id, sil.quantity, sil.warehouse_id,
           sil.description, i.item_code,
           COALESCE(i.costing_method, 'weighted_average') AS costing_method,
           COALESCE(sil.inventory_account_id, i.inventory_account_id) AS inv_acct,
           COALESCE(sil.cogs_account_id, i.cogs_account_id) AS cogs_acct
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    WHERE sil.sales_invoice_id = v_si_id
      AND i.item_type = 'inventory_item'
    ORDER BY sil.line_number
  LOOP
    IF v_inv_line.warehouse_id IS NULL THEN
      RAISE EXCEPTION 'Warehouse is required for inventory item line %', v_inv_line.line_number;
    END IF;
    IF v_inv_line.inv_acct IS NULL OR v_inv_line.cogs_acct IS NULL THEN
      RAISE EXCEPTION 'Inventory and COGS accounts are required for inventory item line %', v_inv_line.line_number;
    END IF;

    PERFORM fn_ensure_stock_balance(v_company_id, v_inv_line.warehouse_id, v_inv_line.item_id);
    SELECT * INTO v_stock FROM stock_balances
    WHERE warehouse_id = v_inv_line.warehouse_id AND item_id = v_inv_line.item_id
    FOR UPDATE;

    IF COALESCE(v_stock.qty_on_hand, 0) < v_inv_line.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for item %. On hand: %, requested: %',
        v_inv_line.item_code, COALESCE(v_stock.qty_on_hand, 0), v_inv_line.quantity;
    END IF;

    v_total_cost := 0;
    v_unit_cost  := 0;
    IF v_inv_line.costing_method = 'weighted_average' THEN
      v_unit_cost  := COALESCE(v_stock.wac_unit_cost, 0);
      v_total_cost := ROUND(v_inv_line.quantity * v_unit_cost, 2);
    ELSE
      FOR v_layer IN
        SELECT * FROM fn_consume_cost_layers(
          v_company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
          v_inv_line.quantity, NULL, NULL)
      LOOP
        v_total_cost := v_total_cost + ROUND(v_layer.qty_consumed * v_layer.unit_cost, 2);
      END LOOP;
      IF v_inv_line.quantity > 0 THEN
        v_unit_cost := ROUND(v_total_cost / v_inv_line.quantity, 6);
      END IF;
    END IF;

    UPDATE stock_balances
    SET qty_on_hand    = qty_on_hand - v_inv_line.quantity,
        total_cost     = GREATEST(total_cost - v_total_cost, 0),
        last_issue_date = v_date,
        updated_at     = NOW()
    WHERE warehouse_id = v_inv_line.warehouse_id AND item_id = v_inv_line.item_id;

    IF v_inv_line.costing_method = 'weighted_average' THEN
      UPDATE stock_balances
      SET wac_unit_cost = CASE WHEN qty_on_hand > 0 THEN ROUND(total_cost / qty_on_hand, 6) ELSE 0 END
      WHERE warehouse_id = v_inv_line.warehouse_id AND item_id = v_inv_line.item_id;
    END IF;

    UPDATE sales_invoice_lines
    SET inventory_account_id = v_inv_line.inv_acct,
        cogs_account_id      = v_inv_line.cogs_acct,
        unit_cost            = v_unit_cost,
        inventory_cost       = v_total_cost,
        updated_by = auth.uid(), updated_at = NOW()
    WHERE id = v_inv_line.id;

    v_total_cogs := v_total_cogs + v_total_cost;
  END LOOP;

  -- ── Sales journal: DR AR / CR revenue / CR output VAT / DR COGS / CR inventory
  v_je_si_id := fn_create_posted_journal_entry(
    v_company_id, v_branch_id,
    'JE-SI-' || v_si_number, v_date,
    'Cash Sale ' || v_si_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'SI', v_si_id,
    v_fp_id, 'posted',
    v_grand_total + v_total_cogs + v_total_pt, v_grand_total + v_total_cogs + v_total_pt,
    'system', 'regular', false, false, false
  );

  PERFORM fn_add_posting_line_push(
    v_je_si_id, 1, v_ar,
    'AR — ' || (p_header->>'customer_name_snapshot'),
    v_grand_total, 0, 'control', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
  );

  v_line_no := 2;
  FOR v_rev_line IN
    SELECT revenue_account_id, SUM(net_amount) AS net_sum, description AS ln_desc,
           department_id, cost_center_id
    FROM sales_invoice_lines
    WHERE sales_invoice_id = v_si_id AND revenue_account_id IS NOT NULL
    GROUP BY revenue_account_id, description, department_id, cost_center_id
  LOOP
    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_line_no, v_rev_line.revenue_account_id,
      'Revenue — ' || v_rev_line.ln_desc,
      0, v_rev_line.net_sum, 'base', NULL, v_branch_id,
      COALESCE(v_rev_line.department_id, v_hdr_dept),
      COALESCE(v_rev_line.cost_center_id, v_hdr_cc)
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_total_vat > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_line_no, v_vat,
      'Output VAT — ' || v_si_number,
      0, v_total_vat, 'tax', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
    );
    v_line_no := v_line_no + 1;
  END IF;

  -- Percentage tax: DR expense / CR payable. The walk-in customer paid the
  -- shelf price; this is the seller's own Section 116 business tax.
  IF v_total_pt > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_line_no, v_pt_expense,
      'Percentage tax — ' || v_si_number,
      v_total_pt, 0, 'base', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
    );
    v_line_no := v_line_no + 1;
    PERFORM fn_add_posting_line_push(
      v_je_si_id, v_line_no, v_pt_payable,
      'Percentage tax payable — ' || v_si_number,
      0, v_total_pt, 'tax', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
    );
    v_line_no := v_line_no + 1;
  END IF;

  FOR v_inv_line IN
    SELECT sil.id, sil.line_number, sil.item_id, sil.quantity, sil.warehouse_id,
           sil.description, sil.inventory_cost, sil.unit_cost,
           sil.inventory_account_id, sil.cogs_account_id,
           sil.department_id, sil.cost_center_id,
           i.item_code, COALESCE(i.costing_method, 'weighted_average') AS costing_method
    FROM sales_invoice_lines sil
    JOIN items i ON i.id = sil.item_id
    WHERE sil.sales_invoice_id = v_si_id
      AND i.item_type = 'inventory_item'
    ORDER BY sil.line_number
  LOOP
    IF COALESCE(v_inv_line.inventory_cost, 0) > 0 THEN
      PERFORM fn_add_posting_line_push(
        v_je_si_id, v_line_no, v_inv_line.cogs_account_id,
        'COGS — ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        v_inv_line.inventory_cost, 0, 'base', NULL, v_branch_id,
        COALESCE(v_inv_line.department_id, v_hdr_dept),
        COALESCE(v_inv_line.cost_center_id, v_hdr_cc)
      );
      v_line_no := v_line_no + 1;
      PERFORM fn_add_posting_line_push(
        v_je_si_id, v_line_no, v_inv_line.inventory_account_id,
        'Inventory — ' || COALESCE(v_inv_line.item_code, v_inv_line.description),
        0, v_inv_line.inventory_cost, 'base', NULL, v_branch_id,
        COALESCE(v_inv_line.department_id, v_hdr_dept),
        COALESCE(v_inv_line.cost_center_id, v_hdr_cc)
      );
      v_line_no := v_line_no + 1;
    END IF;

    INSERT INTO inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, journal_entry_id, notes, created_by
    )
    SELECT v_company_id, v_inv_line.warehouse_id, v_inv_line.item_id,
      'issue', v_date,
      -v_inv_line.quantity, COALESCE(v_inv_line.unit_cost, 0), -COALESCE(v_inv_line.inventory_cost, 0),
      sb.qty_on_hand, v_inv_line.costing_method,
      'SI', v_si_id, v_je_si_id,
      'Cash Sale ' || v_si_number || ' line ' || v_inv_line.line_number,
      auth.uid()
    FROM stock_balances sb
    WHERE sb.warehouse_id = v_inv_line.warehouse_id AND sb.item_id = v_inv_line.item_id
    RETURNING id INTO v_inventory_tx_id;

    UPDATE sales_invoice_lines
    SET inventory_transaction_id = v_inventory_tx_id,
        updated_by = auth.uid(), updated_at = NOW()
    WHERE id = v_inv_line.id;
  END LOOP;

  UPDATE sales_invoices SET
    status = 'posted', posted_by = auth.uid(), posted_at = NOW(),
    journal_entry_id = v_je_si_id, approved_by = auth.uid(), approved_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_si_id;

  -- Output VAT tax ledger: one row per VAT code.
  INSERT INTO tax_detail_entries (
    company_id, branch_id, source_doc_type, source_doc_id,
    tax_kind, vat_code_id, tax_base, tax_amount, tax_period_id,
    posting_date, document_date,
    counterparty_id, counterparty_tin, counterparty_name
  )
  SELECT
    v_company_id, v_branch_id, 'SI', v_si_id,
    'output_vat', sil.vat_code_id,
    SUM(sil.net_amount), COALESCE(SUM(sil.vat_amount), 0), v_fp_id,
    NOW()::DATE, v_date,
    (p_header->>'customer_id')::UUID,
    NULLIF(p_header->>'customer_tin_snapshot',''),
    p_header->>'customer_name_snapshot'
  FROM sales_invoice_lines sil
  WHERE sil.sales_invoice_id = v_si_id
    AND sil.vat_code_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM companies c
                WHERE c.id = v_company_id AND c.tax_registration = 'vat')
  GROUP BY sil.vat_code_id
  HAVING SUM(sil.net_amount) <> 0 OR COALESCE(SUM(sil.vat_amount), 0) <> 0;

  -- Percentage tax ledger: one row per code, through the one PT ledger writer.
  FOR v_pt IN
    SELECT sil.percentage_tax_code_id,
           ptc.tax_code_id,
           ptc.atc_id,
           MAX(sil.percentage_tax_rate)               AS tax_rate,
           SUM(sil.percentage_tax_base)               AS tax_base,
           COALESCE(SUM(sil.percentage_tax_amount),0) AS tax_amount
    FROM sales_invoice_lines sil
    JOIN percentage_tax_codes ptc ON ptc.id = sil.percentage_tax_code_id
    WHERE sil.sales_invoice_id = v_si_id
      AND sil.percentage_tax_code_id IS NOT NULL
    GROUP BY sil.percentage_tax_code_id, ptc.tax_code_id, ptc.atc_id
    HAVING COALESCE(SUM(sil.percentage_tax_amount), 0) <> 0
  LOOP
    PERFORM fn_add_percentage_tax_detail(
      v_company_id, v_branch_id, 'SI', v_si_id,
      v_pt.percentage_tax_code_id, v_pt.tax_code_id, v_pt.atc_id,
      v_pt.tax_base, v_pt.tax_rate, v_pt.tax_amount, v_fp_id, v_date,
      (p_header->>'customer_id')::UUID,
      NULLIF(p_header->>'customer_tin_snapshot',''),
      p_header->>'customer_name_snapshot'
    );
  END LOOP;

  -- ── Receipt ──────────────────────────────────────────────────────────────
  v_cash_received := v_grand_total - v_cwt_total;

  IF v_cwt_total > 0 AND v_cwt_source = 'atc' THEN
    v_net_of_vat := v_grand_total - v_total_vat;

    -- The ATC version in force on the cash-sale date governs, exactly as it
    -- does on every other withholding path.
    SELECT c.tax_rate, c.tax_amount INTO v_cwt_rate, v_cwt_exclusive_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           v_date,
           'direction',               'sale',
           'amount',                  0,
           'withholding_atc_code_id', v_cwt_atc,
           'withholding_base',        v_net_of_vat
         )) c
    WHERE c.tax_kind = 'ewt';

    IF v_cwt_rate IS NULL OR v_cwt_rate <= 0 THEN
      RAISE EXCEPTION 'CWT ATC code is missing, inactive, or has no positive rate.';
    END IF;

    SELECT c.tax_amount INTO v_cwt_gross_expected
    FROM fn_calculate_tax(jsonb_build_object(
           'company_id',              v_company_id,
           'document_date',           v_date,
           'direction',               'sale',
           'amount',                  0,
           'withholding_atc_code_id', v_cwt_atc,
           'withholding_base',        v_grand_total
         )) c
    WHERE c.tax_kind = 'ewt';

    IF ABS(v_cwt_exclusive_expected - v_cwt_total) <= 0.02 THEN
      v_cwt_base := v_net_of_vat;
    ELSIF ABS(v_cwt_gross_expected - v_cwt_total) <= 0.02 THEN
      v_cwt_base := v_grand_total;
    ELSE
      RAISE EXCEPTION 'CWT % does not match ATC rate %%% on the VAT-exclusive base % (expected %) or on the gross % (expected %).',
        v_cwt_total, v_cwt_rate,
        v_net_of_vat, v_cwt_exclusive_expected,
        v_grand_total, v_cwt_gross_expected;
    END IF;
  END IF;

  INSERT INTO receipts (
    company_id, branch_id, customer_id, customer_name_snapshot, customer_tin_snapshot,
    receipt_number, receipt_date, payment_mode_id, bank_account_id,
    total_amount, total_cwt, remarks, status, created_by, updated_by
  ) VALUES (
    v_company_id, v_branch_id, (p_header->>'customer_id')::UUID,
    p_header->>'customer_name_snapshot', NULLIF(p_header->>'customer_tin_snapshot',''),
    v_or_number, v_date,
    COALESCE(NULLIF(p_header->>'payment_mode_id','')::UUID,
             (SELECT id FROM ref_payment_modes WHERE code = 'CASH')), v_cash_acct,
    v_grand_total, v_cwt_total, 'Cash Sale — ' || v_si_number,
    'draft', auth.uid(), auth.uid()
  ) RETURNING id INTO v_receipt_id;

  INSERT INTO receipt_lines (
    receipt_id, company_id, invoice_id, payment_amount, cwt_amount,
    atc_code_id, cwt_tax_base, cwt_source, created_by, updated_by
  ) VALUES (
    v_receipt_id, v_company_id, v_si_id, v_grand_total - v_cwt_total, v_cwt_total,
    CASE WHEN v_cwt_source = 'atc' THEN v_cwt_atc ELSE NULL END,
    CASE WHEN v_cwt_total > 0 THEN v_cwt_base ELSE NULL END,
    CASE WHEN v_cwt_total > 0 THEN v_cwt_source ELSE 'atc' END,
    auth.uid(), auth.uid()
  );

  -- Post receipt JE: DR Cash (net) + DR CWT Receivable = CR AR (gross)
  v_je_or_id := fn_create_posted_journal_entry(
    v_company_id, v_branch_id,
    'JE-OR-' || v_or_number, v_date,
    'Cash Receipt ' || v_or_number || ' — ' || (p_header->>'customer_name_snapshot'),
    'OR', v_receipt_id,
    v_fp_id, 'posted', v_grand_total, v_grand_total,
    'system', 'regular', false, false, false
  );

  PERFORM fn_add_posting_line_push(
    v_je_or_id, 1, v_cash_acct,
    'Cash received — ' || v_or_number,
    v_cash_received, 0, 'base', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
  );

  IF v_cwt_total > 0 THEN
    PERFORM fn_add_posting_line_push(
      v_je_or_id, 2, v_cwt,
      'CWT receivable — ' || v_or_number,
      v_cwt_total, 0, 'withholding', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
    );
  END IF;

  PERFORM fn_add_posting_line_push(
    v_je_or_id, CASE WHEN v_cwt_total > 0 THEN 3 ELSE 2 END,
    v_ar, 'AR cleared — ' || v_or_number,
    0, v_grand_total, 'control', NULL, v_branch_id, v_hdr_dept, v_hdr_cc
  );

  UPDATE receipts SET status = 'posted', journal_entry_id = v_je_or_id,
    posted_by = auth.uid(), posted_at = NOW(),
    updated_at = NOW(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  -- ── CWT receivable tax ledger ────────────────────────────────────────────
  -- One row per ATC when the lines are itemised, because a 2307 and a 1601-EQ
  -- are assembled per ATC, not per document.
  IF v_cwt_total > 0 AND v_cwt_source = 'invoice_lines' THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    )
    SELECT
      v_company_id, v_branch_id, 'OR', v_receipt_id,
      'cwt_receivable', sil.withholding_atc_code_id,
      SUM(sil.withholding_tax_base), MAX(sil.withholding_tax_rate), SUM(sil.withholding_tax_amount), v_fp_id,
      NOW()::DATE, v_date,
      (p_header->>'customer_id')::UUID,
      NULLIF(p_header->>'customer_tin_snapshot',''),
      p_header->>'customer_name_snapshot'
    FROM sales_invoice_lines sil
    WHERE sil.sales_invoice_id = v_si_id
      AND sil.withholding_atc_code_id IS NOT NULL
    GROUP BY sil.withholding_atc_code_id;
  ELSIF v_cwt_total > 0 THEN
    INSERT INTO tax_detail_entries (
      company_id, branch_id, source_doc_type, source_doc_id,
      tax_kind, atc_code_id, tax_base, tax_rate, tax_amount, tax_period_id,
      posting_date, document_date,
      counterparty_id, counterparty_tin, counterparty_name
    ) VALUES (
      v_company_id, v_branch_id, 'OR', v_receipt_id,
      'cwt_receivable', v_cwt_atc, v_cwt_base, v_cwt_rate, v_cwt_total, v_fp_id,
      NOW()::DATE, v_date,
      (p_header->>'customer_id')::UUID,
      NULLIF(p_header->>'customer_tin_snapshot',''),
      p_header->>'customer_name_snapshot'
    );
  END IF;

  RETURN jsonb_build_object(
    'si_id', v_si_id, 'receipt_id', v_receipt_id,
    'si_number', v_si_number, 'receipt_number', v_or_number,
    'total_amount', v_grand_total, 'total_cwt', v_cwt_total,
    'total_percentage_tax', v_total_pt,
    'total_cogs', v_total_cogs
  );
END;
$function$;

COMMENT ON FUNCTION public.fn_save_cash_sale(jsonb, jsonb, numeric) IS
  'Cash Sale: prices every line through the Tax Engine (business tax — VAT or percentage tax — and withholding tax, all per line, all as of the document date), relieves inventory and posts COGS through the same costing path as fn_post_sales_invoice, then settles the invoice with an Official Receipt.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. THE PERCENTAGE TAX LEDGER TIES TO THE GENERAL LEDGER
--
-- The same shape as `fn_vat_gl_reconciliation`, for the same reason: a tax
-- ledger nobody ties to the books is a spreadsheet with better storage. This is
-- the reconciliation a 2551Q is defended with.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_percentage_tax_gl_reconciliation(
  p_company_id UUID,
  p_date_from  DATE,
  p_date_to    DATE
)
RETURNS TABLE (
  ledger_tax_base   NUMERIC(15,2),
  ledger_tax_amount NUMERIC(15,2),
  gl_account_id     UUID,
  gl_account_code   TEXT,
  gl_account_name   TEXT,
  gl_amount         NUMERIC(15,2),
  variance          NUMERIC(15,2),
  is_reconciled     BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_account_id UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Invalid reconciliation date range % to %', p_date_from, p_date_to;
  END IF;

  SELECT cfg.percentage_tax_payable_account_id INTO v_account_id
  FROM company_accounting_config cfg WHERE cfg.company_id = p_company_id;

  RETURN QUERY
  WITH ledger AS (
    SELECT COALESCE(SUM(tde.tax_base), 0)::NUMERIC(15,2)   AS base_sum,
           COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS tax_sum
    FROM tax_detail_entries tde
    WHERE tde.company_id = p_company_id
      AND tde.tax_kind = 'percentage_tax'
      AND tde.document_date BETWEEN p_date_from AND p_date_to
  ),
  gl AS (
    SELECT CASE WHEN v_account_id IS NULL THEN NULL
                ELSE (
                  SELECT COALESCE(SUM(jel.credit_amount - jel.debit_amount), 0)
                  FROM journal_entry_lines jel
                  JOIN journal_entries je ON je.id = jel.je_id
                  WHERE jel.account_id = v_account_id
                    AND jel.company_id = p_company_id
                    AND je.status IN ('posted', 'reversed')
                    AND je.je_date BETWEEN p_date_from AND p_date_to
                )
           END::NUMERIC(15,2) AS gl_sum
  )
  SELECT l.base_sum, l.tax_sum,
         v_account_id, coa.account_code, coa.account_name,
         g.gl_sum,
         (l.tax_sum - COALESCE(g.gl_sum, 0))::NUMERIC(15,2),
         CASE WHEN v_account_id IS NULL
              THEN l.tax_sum = 0
              ELSE ABS(l.tax_sum - g.gl_sum) <= 0.01
         END
  FROM ledger l
  CROSS JOIN gl g
  LEFT JOIN chart_of_accounts coa ON coa.id = v_account_id;
END;
$function$;

COMMENT ON FUNCTION public.fn_percentage_tax_gl_reconciliation(UUID, DATE, DATE) IS
  'Ties the percentage-tax ledger to the Percentage Tax Payable control account for a date range. A company with no payable account configured reconciles only while it has recognised no percentage tax.';

REVOKE ALL ON FUNCTION public.fn_percentage_tax_gl_reconciliation(UUID, DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_percentage_tax_gl_reconciliation(UUID, DATE, DATE) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 11. THE 2551Q — COMPUTED FROM THE POSTED BOOKS, NOT FROM THE BROWSER
--
-- The PT Return screen used to sum VAT-*exempt* sales lines in JavaScript. VAT
-- exemption is not the percentage-tax base, and a return computed on the client
-- is not a return computed from the books. Both are replaced by these two
-- functions, and a return may not be marked final or filed while it disagrees
-- with the ledger it claims to summarise.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_percentage_tax_return_period(
  p_year    INTEGER,
  p_quarter INTEGER,
  OUT date_from DATE,
  OUT date_to   DATE
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_year IS NULL OR p_quarter IS NULL OR p_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid 2551Q period: year %, quarter %', p_year, p_quarter;
  END IF;
  date_from := make_date(p_year, (p_quarter - 1) * 3 + 1, 1);
  date_to   := (date_from + INTERVAL '3 months' - INTERVAL '1 day')::DATE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_percentage_tax_return_period(INTEGER, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_compute_percentage_tax_return(
  p_company_id UUID,
  p_year       INTEGER,
  p_quarter    INTEGER
)
RETURNS TABLE (
  atc_code       TEXT,
  tax_code       TEXT,
  pt_code        TEXT,
  tax_rate       NUMERIC(9,4),
  taxable_base   NUMERIC(15,2),
  tax_due        NUMERIC(15,2),
  document_count INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_from DATE;
  v_to   DATE;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  SELECT f.date_from, f.date_to INTO v_from, v_to
  FROM fn_percentage_tax_return_period(p_year, p_quarter) f;

  RETURN QUERY
  SELECT ac.code, tc.code, ptc.pt_code,
         MAX(tde.tax_rate)::NUMERIC(9,4),
         COALESCE(SUM(tde.tax_base), 0)::NUMERIC(15,2),
         COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2),
         COUNT(DISTINCT tde.source_doc_id)::INTEGER
  FROM tax_detail_entries tde
  LEFT JOIN atc_codes ac              ON ac.id  = tde.atc_code_id
  LEFT JOIN tax_codes tc              ON tc.id  = tde.tax_code_id
  LEFT JOIN percentage_tax_codes ptc  ON ptc.id = tde.percentage_tax_code_id
  WHERE tde.company_id = p_company_id
    AND tde.tax_kind = 'percentage_tax'
    AND tde.document_date BETWEEN v_from AND v_to
  GROUP BY ac.code, tc.code, ptc.pt_code
  ORDER BY ac.code, tc.code, ptc.pt_code;
END;
$function$;

COMMENT ON FUNCTION public.fn_compute_percentage_tax_return(UUID, INTEGER, INTEGER) IS
  'Server-computed 2551Q quarterly totals per ATC and rate, from the posted percentage-tax ledger. The return is filed per ATC, so this is the shape the form needs.';

REVOKE ALL ON FUNCTION public.fn_compute_percentage_tax_return(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_compute_percentage_tax_return(UUID, INTEGER, INTEGER) TO authenticated;

-- ── The return and its working paper, generated together ───────────────────
CREATE OR REPLACE FUNCTION public.fn_generate_pt_return(
  p_company_id UUID,
  p_year       INTEGER,
  p_quarter    INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_from       DATE;
  v_to         DATE;
  v_base       NUMERIC(15,2) := 0;
  v_due        NUMERIC(15,2) := 0;
  v_rate       NUMERIC(5,2);
  v_rate_count INTEGER := 0;
  v_return     pt_returns%ROWTYPE;
  v_paid_prior NUMERIC(15,2) := 0;
  v_header_id  UUID;
  v_lines      INTEGER := 0;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  SELECT f.date_from, f.date_to INTO v_from, v_to
  FROM fn_percentage_tax_return_period(p_year, p_quarter) f;

  SELECT COALESCE(SUM(tde.tax_base), 0), COALESCE(SUM(tde.tax_amount), 0),
         COUNT(DISTINCT tde.tax_rate)
    INTO v_base, v_due, v_rate_count
  FROM tax_detail_entries tde
  WHERE tde.company_id = p_company_id
    AND tde.tax_kind = 'percentage_tax'
    AND tde.document_date BETWEEN v_from AND v_to;

  -- One rate in the quarter reports that rate. A quarter that spans a statutory
  -- rate change, or mixes Section 116 with another percentage tax, reports the
  -- effective rate and the per-ATC detail carries the truth.
  IF v_rate_count = 1 THEN
    SELECT MAX(tde.tax_rate)::NUMERIC(5,2) INTO v_rate
    FROM tax_detail_entries tde
    WHERE tde.company_id = p_company_id
      AND tde.tax_kind = 'percentage_tax'
      AND tde.document_date BETWEEN v_from AND v_to;
  ELSIF v_base <> 0 THEN
    v_rate := ROUND(v_due / v_base * 100, 2);
  ELSE
    v_rate := 0;
  END IF;

  SELECT * INTO v_return FROM pt_returns
  WHERE company_id = p_company_id AND period_year = p_year AND period_quarter = p_quarter;

  IF FOUND AND v_return.status <> 'draft' THEN
    RAISE EXCEPTION 'The % Q% percentage tax return is % and cannot be regenerated. Reopen it to draft first.',
      p_year, p_quarter, v_return.status;
  END IF;

  v_paid_prior := COALESCE(v_return.pt_paid_prior_quarters, 0);

  IF FOUND THEN
    UPDATE pt_returns SET
      gross_sales_exempt     = 0,
      gross_sales_zero_rated = 0,
      taxable_base           = v_base,
      pt_rate                = v_rate,
      pt_due                 = v_due,
      pt_still_due           = v_due - v_paid_prior,
      updated_by             = auth.uid(),
      updated_at             = now()
    WHERE id = v_return.id;
  ELSE
    INSERT INTO pt_returns (
      company_id, period_year, period_quarter,
      gross_sales_exempt, gross_sales_zero_rated,
      taxable_base, pt_rate, pt_due, pt_paid_prior_quarters, pt_still_due,
      status, created_by, updated_by
    ) VALUES (
      p_company_id, p_year, p_quarter,
      0, 0, v_base, v_rate, v_due, 0, v_due,
      'draft', auth.uid(), auth.uid()
    ) RETURNING * INTO v_return;
  END IF;

  -- ── The working paper: the schedule behind the one number on the form ────
  INSERT INTO compliance_pt_working_papers_headers (
    company_id, period_year, period_quarter, description, status, created_by, updated_by
  ) VALUES (
    p_company_id, p_year, p_quarter,
    format('2551Q schedule — %s Q%s, generated from the percentage tax ledger', p_year, p_quarter),
    'draft', auth.uid(), auth.uid()
  )
  ON CONFLICT (company_id, period_year, period_quarter) DO UPDATE
    SET description = EXCLUDED.description,
        updated_by  = auth.uid(),
        updated_at  = now()
  RETURNING id INTO v_header_id;

  IF (SELECT status FROM compliance_pt_working_papers_headers WHERE id = v_header_id) <> 'draft' THEN
    RAISE EXCEPTION 'The % Q% percentage tax working paper is no longer a draft and cannot be regenerated.',
      p_year, p_quarter;
  END IF;

  DELETE FROM compliance_pt_working_papers_lines WHERE header_id = v_header_id;

  INSERT INTO compliance_pt_working_papers_lines (header_id, reference, amount, remarks)
  SELECT v_header_id,
         COALESCE(si.si_number, tde.source_doc_type || ' ' || LEFT(tde.source_doc_id::TEXT, 8)),
         tde.tax_amount,
         format('%s · %s · base %s · rate %s%% · %s',
                tde.document_date,
                COALESCE(ac.code, 'no ATC'),
                to_char(tde.tax_base, 'FM999,999,999,990.00'),
                to_char(tde.tax_rate, 'FM990.00'),
                COALESCE(tde.counterparty_name, 'walk-in'))
  FROM tax_detail_entries tde
  LEFT JOIN sales_invoices si ON si.id = tde.source_doc_id AND tde.source_doc_type = 'SI'
  LEFT JOIN atc_codes ac      ON ac.id = tde.atc_code_id
  WHERE tde.company_id = p_company_id
    AND tde.tax_kind = 'percentage_tax'
    AND tde.document_date BETWEEN v_from AND v_to
  ORDER BY tde.document_date, si.si_number;

  GET DIAGNOSTICS v_lines = ROW_COUNT;

  RETURN jsonb_build_object(
    'pt_return_id',       v_return.id,
    'working_paper_id',   v_header_id,
    'period_from',        v_from,
    'period_to',          v_to,
    'taxable_base',       v_base,
    'pt_rate',            v_rate,
    'pt_due',             v_due,
    'pt_still_due',       v_due - v_paid_prior,
    'working_paper_lines', v_lines
  );
END;
$function$;

COMMENT ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) IS
  'Builds the 2551Q and its working paper for one quarter from the posted percentage-tax ledger. Refuses to overwrite a return that is already final or filed.';

REVOKE ALL ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) TO authenticated;

COMMENT ON COLUMN pt_returns.gross_sales_exempt IS
  'Legacy VAT-shaped column. It is NOT part of the percentage-tax computation: VAT exemption is not the percentage-tax base. fn_generate_pt_return writes zero here.';
COMMENT ON COLUMN pt_returns.gross_sales_zero_rated IS
  'Legacy VAT-shaped column. It is NOT part of the percentage-tax computation. fn_generate_pt_return writes zero here.';
COMMENT ON COLUMN pt_returns.taxable_base IS
  'Gross sales subject to percentage tax in the quarter, from the posted percentage-tax ledger.';

-- ── The gate: a return may not claim a figure the ledger does not support ──
CREATE OR REPLACE FUNCTION public.fn_require_pt_return_reconciled()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from   DATE;
  v_to     DATE;
  v_base   NUMERIC(15,2);
  v_due    NUMERIC(15,2);
BEGIN
  IF NEW.status = 'draft' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status
     AND OLD.taxable_base = NEW.taxable_base AND OLD.pt_due = NEW.pt_due THEN
    RETURN NEW;
  END IF;

  SELECT f.date_from, f.date_to INTO v_from, v_to
  FROM fn_percentage_tax_return_period(NEW.period_year, NEW.period_quarter) f;

  SELECT COALESCE(SUM(tde.tax_base), 0), COALESCE(SUM(tde.tax_amount), 0)
    INTO v_base, v_due
  FROM tax_detail_entries tde
  WHERE tde.company_id = NEW.company_id
    AND tde.tax_kind = 'percentage_tax'
    AND tde.document_date BETWEEN v_from AND v_to;

  IF ABS(COALESCE(NEW.taxable_base, 0) - v_base) > 0.01
     OR ABS(COALESCE(NEW.pt_due, 0) - v_due) > 0.01 THEN
    RAISE EXCEPTION 'Percentage tax return % Q% does not reconcile to the posted ledger (return base %, due %; ledger base %, due %). Regenerate it before marking it % .',
      NEW.period_year, NEW.period_quarter,
      NEW.taxable_base, NEW.pt_due, v_base, v_due, NEW.status;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pt_return_reconciled ON pt_returns;
CREATE TRIGGER trg_pt_return_reconciled
  BEFORE INSERT OR UPDATE OF status, taxable_base, pt_due ON pt_returns
  FOR EACH ROW EXECUTE FUNCTION fn_require_pt_return_reconciled();

-- ═══════════════════════════════════════════════════════════════════════════
-- 12. COMPANY SETUP SEEDS A PERCENTAGE-TAX CODE THAT IS ACTUALLY CORRECT
--
-- The old routine took the first `pt` tax code by code — 'PT12-OUT' sorts before
-- 'PT3-OUT' — and labelled it 3%, and fell back to ANY alphanumeric tax code
-- when no percentage-tax ATC existed, which meant an EWT code on a 2551Q line.
-- It now seeds from the rate it names and refuses to invent a classification it
-- does not have.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_seed_company_percentage_tax_codes(p_company_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tax_code_id UUID;
  v_atc_id      UUID;
  v_rate        NUMERIC(6,2) := 3.00;   -- Section 116, the general non-VAT rate
  v_count       INTEGER := 0;
BEGIN
  IF NOT can_admin_company(p_company_id) THEN
    RAISE EXCEPTION 'not authorized to seed defaults for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  -- The governed rate holder, at the rate this code claims to be.
  SELECT id INTO v_tax_code_id
  FROM tax_codes
  WHERE tax_type = 'pt' AND rate = v_rate
    AND COALESCE(is_active, false) AND deprecated_at IS NULL
  ORDER BY effective_from DESC, code
  LIMIT 1;

  -- The 2551Q alphanumeric code. No fallback: a withholding ATC on a percentage
  -- tax line would be a wrong return, and no row is better than a wrong one.
  SELECT id INTO v_atc_id
  FROM atc_codes
  WHERE tax_category = 'pt' AND rate = v_rate
    AND COALESCE(is_active, false) AND deprecated_at IS NULL
  ORDER BY effective_from DESC, code
  LIMIT 1;

  IF v_tax_code_id IS NULL OR v_atc_id IS NULL THEN
    RETURN 0;  -- required global references not present; seed nothing
  END IF;

  INSERT INTO percentage_tax_codes (company_id, tax_code_id, pt_code, description,
                                    atc_id, rate, form_type, created_by, updated_by)
  SELECT p_company_id, v_tax_code_id, v.pt_code, v.description, v_atc_id, v_rate,
         v.form_type, auth.uid(), auth.uid()
  FROM (VALUES
    ('PT-3','Percentage Tax - 3% (Section 116, non-VAT)', '2551Q')
  ) AS v(pt_code, description, form_type)
  ON CONFLICT (company_id, pt_code, effective_from) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION fn_seed_company_percentage_tax_codes(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_seed_company_percentage_tax_codes(UUID) TO authenticated, service_role;

COMMENT ON FUNCTION fn_seed_company_percentage_tax_codes(UUID) IS
  'MDP-05: seeds the Section 116 percentage-tax code for a company from the governed 3% tax-code version and the 3% percentage-tax ATC. Seeds nothing rather than something wrong when either is absent. Idempotent; admin-gated.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 13. LEAST PRIVILEGE
--
-- The four trigger bodies are reachable only by the triggers that own them, and
-- the two readers a maintenance screen legitimately calls reach `authenticated`
-- and nothing else. Nothing this migration adds is executable by `anon`.
-- ═══════════════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION public.fn_percentage_tax_code_used(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_percentage_tax_code_used(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_percentage_tax_return_period(INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_percentage_tax_return_period(INTEGER, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_enforce_percentage_tax_code_version_rules() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_guard_percentage_tax_code_history() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_require_sales_line_percentage_tax_valid() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_require_pt_return_reconciled() FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 14. A REVERSAL CARRIES THE PERCENTAGE-TAX CODE IT REVERSES
--
-- `fn_reverse_tax_detail_entries` is generic and already reverses every tax kind
-- a voided document wrote, percentage tax included: the counter-row negates the
-- base and the amount and keeps the tax-code version and the ATC. It could not
-- keep `percentage_tax_code_id`, because that column did not exist when it was
-- written and `fn_add_tax_detail` has no parameter for it — so a voided quarter
-- would have reconciled correctly while its per-code breakdown lost track of
-- which company code version the reversal belonged to. The counter-row is
-- stamped after it is written; nothing else about the reversal changes, and no
-- ledger or journal behaviour moves.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_reverse_tax_detail_entries(
  p_source_doc_type TEXT,
  p_source_doc_id UUID,
  p_reversal_date DATE,
  p_fiscal_period_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_row tax_detail_entries%ROWTYPE;
  v_reversal_id UUID;
BEGIN
  FOR v_row IN
    SELECT t.*
    FROM tax_detail_entries t
    WHERE t.source_doc_type = UPPER(BTRIM(p_source_doc_type))
      AND t.source_doc_id = p_source_doc_id
      AND t.is_reversal = false
      AND NOT EXISTS (
        SELECT 1 FROM tax_detail_entries r
        WHERE r.reverses_tax_detail_id = t.id
      )
    ORDER BY t.id
    FOR UPDATE
  LOOP
    v_reversal_id := fn_add_tax_detail(
      v_row.company_id, v_row.branch_id,
      v_row.source_doc_type, v_row.source_doc_id, v_row.source_line_id,
      v_row.tax_kind, v_row.tax_code_id, v_row.vat_code_id, v_row.atc_code_id,
      -v_row.tax_base, v_row.tax_rate, -v_row.tax_amount,
      p_fiscal_period_id, CURRENT_DATE, p_reversal_date,
      v_row.counterparty_id, v_row.counterparty_tin, v_row.counterparty_name,
      v_row.income_nature, true, v_row.id, 'draft'
    );

    IF v_row.percentage_tax_code_id IS NOT NULL THEN
      UPDATE tax_detail_entries
      SET percentage_tax_code_id = v_row.percentage_tax_code_id
      WHERE id = v_reversal_id;
    END IF;
  END LOOP;
END;
$$;
