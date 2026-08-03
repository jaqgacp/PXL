-- ═══════════════════════════════════════════════════════════════════════════
-- Tax Engine — effective-dated VAT resolution (Delivery Plan Phase 4 residue).
--
-- THE DEFECT
--   `fn_calculate_tax` resolved VAT with
--       SELECT ... FROM vat_codes vc JOIN tax_codes tc ON tc.id = vc.tax_code_id
--       WHERE vc.id = <vat_code_id>
--   and nothing else. Withholding was already governed by the document date
--   (is_active, deprecated_at, effective_from/effective_to); VAT was not. The
--   version machinery for VAT has existed since 20260713000012 — effective
--   windows, deprecation, succession, immutability-after-use, an overlap guard
--   — and the engine simply did not consult it. A superseded, deprecated,
--   deactivated or not-yet-effective VAT version therefore still computed tax,
--   and worse, an unresolvable code fell through to `exempt at 0%` silently.
--
-- WHAT THIS CHANGES
--   One resolver, `fn_resolve_vat_code`, now owns every rule that decides
--   whether a VAT code may be used on a document: the code exists, its version
--   and its tax-code version are both active, not deprecated, and in force ON
--   THE DOCUMENT DATE, the code is for the document's tax side, and the
--   company's tax profile permits a VAT-bearing rate. It fails closed with a
--   specific message; it never degrades to exempt.
--
--   Everything that decides a VAT code's validity now goes through it:
--     * fn_calculate_tax          — the engine, at computation time;
--     * fn_validate_company_vat_code — the line/header trigger backstop, which
--       becomes date-aware (the document date, not today);
--     * fn_vat_codes_asof         — the picker surface the UI reads, so the
--       frontend offers exactly what the database will accept.
--
--   The frontend may filter; the database enforces. Both now apply one rule.
--
-- WHAT THIS DOES NOT CHANGE
--   No posting function, no journal shape, no tax-ledger row, no account
--   resolution, no rate arithmetic. `fn_calculate_tax` remains the only
--   function in the schema that turns a rate into a tax amount — this file
--   contains no tax arithmetic at all. Historical VAT records are untouched:
--   every seeded version runs from 1900-01-01 with an open end, so every
--   existing document resolves exactly the version it resolved before.
--
-- THE COMPANY TAX PROFILE (a documented gap, deliberately not closed here)
--   `companies.tax_registration` is a single scalar with no history, so a
--   company that changes between VAT and non-VAT has no effective-dated
--   profile to resolve against. Every profile read in this file is funnelled
--   through `fn_company_tax_registration_asof(company, date)` — one seam that
--   today ignores its date argument and returns the current scalar. When the
--   profile becomes effective-dated, exactly that one function changes and
--   every caller becomes correct. The gap and its smallest fix are recorded in
--   the Product Backlog; closing it is not required to make VAT resolution
--   effective-date aware, so it is not attempted here.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── The company tax-profile seam ───────────────────────────────────────────
-- This is deliberately the ONLY place the product reads a company's tax
-- registration for the purpose of validating a tax code. It accepts a date it
-- cannot yet honour, because the honest shape of the question is "what was
-- this company registered as on the document date?" and the model can only
-- answer "what is it registered as now?". Naming the gap in the signature is
-- what makes the future fix a one-function change instead of a hunt.
CREATE OR REPLACE FUNCTION public.fn_company_tax_registration_asof(
  p_company_id UUID,
  p_as_of      DATE DEFAULT NULL
)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- p_as_of is accepted and currently ignored: companies.tax_registration
  -- carries no effective-dated history. See the header note.
  SELECT c.tax_registration FROM companies c WHERE c.id = p_company_id;
$$;

COMMENT ON FUNCTION public.fn_company_tax_registration_asof(UUID, DATE) IS
  'The single seam through which tax-code validation reads a company tax profile. p_as_of is accepted but not yet honoured: companies.tax_registration has no effective-dated history. Closing that gap changes this function only.';

REVOKE ALL ON FUNCTION public.fn_company_tax_registration_asof(UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_company_tax_registration_asof(UUID, DATE) TO authenticated;

-- ── The resolution contract ────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typname = 'vat_code_resolution'
  ) THEN
    CREATE TYPE public.vat_code_resolution AS (
      vat_code_id      UUID,
      vat_code         TEXT,
      tax_code_id      UUID,
      tax_code         TEXT,
      classification   TEXT,          -- regular | zero_rated | exempt
      transaction_type TEXT,          -- input_vat | output_vat
      vat_rate         NUMERIC(9,4),
      effective_from   DATE,
      effective_to     DATE
    );
  END IF;
END $$;

COMMENT ON TYPE public.vat_code_resolution IS
  'The exact VAT version resolved for one document date: code, tax-code version, classification, side, rate and the window that made it valid.';

-- ── The resolver ───────────────────────────────────────────────────────────
-- Returns NULL for a NULL code — a line with no VAT code is a legitimate,
-- untaxed line and always has been. A code that WAS supplied and does not
-- resolve is an error, never a silent zero.
CREATE OR REPLACE FUNCTION public.fn_resolve_vat_code(
  p_company_id       UUID,
  p_vat_code_id      UUID,
  p_as_of            DATE DEFAULT NULL,
  p_transaction_type TEXT DEFAULT NULL,
  p_context          TEXT DEFAULT 'VAT code'
)
RETURNS public.vat_code_resolution
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_as_of        DATE := COALESCE(p_as_of, CURRENT_DATE);
  v_registration TEXT;
  v_row          public.vat_code_resolution;
  v_vc           vat_codes%ROWTYPE;
  v_tc           tax_codes%ROWTYPE;
BEGIN
  IF p_vat_code_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_vc FROM vat_codes WHERE id = p_vat_code_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION '% is not a valid VAT code', p_context;
  END IF;

  SELECT * INTO v_tc FROM tax_codes WHERE id = v_vc.tax_code_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION '% is not a valid VAT code', p_context;
  END IF;

  -- The VAT code version.
  IF NOT COALESCE(v_vc.is_active, false) THEN
    RAISE EXCEPTION '% % is inactive', p_context, v_vc.vat_code;
  END IF;
  IF v_vc.deprecated_at IS NOT NULL THEN
    RAISE EXCEPTION '% % was deprecated on %. Select its successor version.',
      p_context, v_vc.vat_code, v_vc.deprecated_at::DATE;
  END IF;
  IF v_vc.effective_from > v_as_of
     OR (v_vc.effective_to IS NOT NULL AND v_vc.effective_to < v_as_of) THEN
    RAISE EXCEPTION '% % is not effective on % (that version runs % to %).',
      p_context, v_vc.vat_code, v_as_of, v_vc.effective_from,
      COALESCE(v_vc.effective_to::TEXT, 'open');
  END IF;

  -- The tax code version that carries the rate.
  IF NOT COALESCE(v_tc.is_active, false) THEN
    RAISE EXCEPTION '% % resolves to tax code %, which is inactive',
      p_context, v_vc.vat_code, v_tc.code;
  END IF;
  IF v_tc.deprecated_at IS NOT NULL THEN
    RAISE EXCEPTION '% % resolves to tax code %, which was deprecated on %. Select its successor version.',
      p_context, v_vc.vat_code, v_tc.code, v_tc.deprecated_at::DATE;
  END IF;
  IF v_tc.effective_from > v_as_of
     OR (v_tc.effective_to IS NOT NULL AND v_tc.effective_to < v_as_of) THEN
    RAISE EXCEPTION '% % resolves to tax code %, which is not effective on % (that version runs % to %).',
      p_context, v_vc.vat_code, v_tc.code, v_as_of, v_tc.effective_from,
      COALESCE(v_tc.effective_to::TEXT, 'open');
  END IF;

  -- The tax side. A sales document may not carry an input-VAT code and a
  -- purchase document may not carry an output-VAT code.
  IF p_transaction_type IS NOT NULL AND v_vc.transaction_type <> p_transaction_type THEN
    RAISE EXCEPTION '% % is for %, not %',
      p_context, v_vc.vat_code, v_vc.transaction_type, p_transaction_type;
  END IF;

  -- The company tax profile.
  v_registration := fn_company_tax_registration_asof(p_company_id, v_as_of);
  IF v_registration IS NULL THEN
    RAISE EXCEPTION 'Company not found';
  END IF;
  IF v_registration <> 'vat' AND v_tc.rate <> 0 THEN
    RAISE EXCEPTION 'Non-VAT or exempt companies cannot use VAT-bearing code % (% rate). Use a zero-rate/exempt code instead.',
      v_vc.vat_code, v_tc.rate;
  END IF;

  v_row := ROW(v_vc.id, v_vc.vat_code, v_tc.id, v_tc.code,
               v_vc.vat_classification, v_vc.transaction_type, v_tc.rate,
               GREATEST(v_vc.effective_from, v_tc.effective_from),
               LEAST(COALESCE(v_vc.effective_to, DATE 'infinity'),
                     COALESCE(v_tc.effective_to, DATE 'infinity')))::public.vat_code_resolution;
  IF v_row.effective_to = DATE 'infinity' THEN
    v_row.effective_to := NULL;
  END IF;
  RETURN v_row;
END;
$function$;

COMMENT ON FUNCTION public.fn_resolve_vat_code(UUID, UUID, DATE, TEXT, TEXT) IS
  'The only place PXL decides whether a VAT code may be used. Resolves the exact VAT and tax-code versions in force on the document date and validates them against the tax side and the company tax profile. Fails closed; never degrades an unresolvable code to exempt.';

REVOKE ALL ON FUNCTION public.fn_resolve_vat_code(UUID, UUID, DATE, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_resolve_vat_code(UUID, UUID, DATE, TEXT, TEXT) TO authenticated;

-- ── The picker surface ─────────────────────────────────────────────────────
-- Exactly the codes fn_resolve_vat_code would accept for this company on this
-- date. The UI reads this instead of filtering vat_codes on is_active alone,
-- so a deprecated or superseded version is never offered and then rejected.
CREATE OR REPLACE FUNCTION public.fn_vat_codes_asof(
  p_company_id       UUID,
  p_as_of            DATE DEFAULT NULL,
  p_transaction_type TEXT DEFAULT NULL
)
RETURNS TABLE (
  id                 UUID,
  vat_code           TEXT,
  description        TEXT,
  vat_classification TEXT,
  transaction_type   TEXT,
  tax_code_id        UUID,
  rate               NUMERIC(6,2),
  effective_from     DATE,
  effective_to       DATE
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_as_of        DATE := COALESCE(p_as_of, CURRENT_DATE);
  v_registration TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of this company';
  END IF;

  v_registration := fn_company_tax_registration_asof(p_company_id, v_as_of);
  IF v_registration IS NULL THEN
    RAISE EXCEPTION 'Company not found';
  END IF;

  RETURN QUERY
  SELECT vc.id, vc.vat_code, vc.description, vc.vat_classification,
         vc.transaction_type, tc.id, tc.rate,
         GREATEST(vc.effective_from, tc.effective_from),
         NULLIF(LEAST(COALESCE(vc.effective_to, DATE 'infinity'),
                      COALESCE(tc.effective_to, DATE 'infinity')), DATE 'infinity')
  FROM vat_codes vc
  JOIN tax_codes tc ON tc.id = vc.tax_code_id
  WHERE COALESCE(vc.is_active, false)
    AND vc.deprecated_at IS NULL
    AND vc.effective_from <= v_as_of
    AND (vc.effective_to IS NULL OR vc.effective_to >= v_as_of)
    AND COALESCE(tc.is_active, false)
    AND tc.deprecated_at IS NULL
    AND tc.effective_from <= v_as_of
    AND (tc.effective_to IS NULL OR tc.effective_to >= v_as_of)
    AND (p_transaction_type IS NULL OR vc.transaction_type = p_transaction_type)
    AND (v_registration = 'vat' OR tc.rate = 0)
  ORDER BY vc.vat_code;
END;
$function$;

COMMENT ON FUNCTION public.fn_vat_codes_asof(UUID, DATE, TEXT) IS
  'The governed VAT-code picker: exactly the versions fn_resolve_vat_code accepts for this company on this document date. The UI reads this so it cannot offer a code the database will refuse.';

REVOKE ALL ON FUNCTION public.fn_vat_codes_asof(UUID, DATE, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_vat_codes_asof(UUID, DATE, TEXT) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- The trigger backstop becomes date-aware.
--
-- RLS lets a company member write document lines directly, so the line and
-- header triggers — not the save RPCs — are the boundary that must hold. They
-- validated is_active and the tax side but knew nothing about the document
-- date. They now pass it.
-- ═══════════════════════════════════════════════════════════════════════════

-- The 4-argument form is replaced, not overloaded: two candidates would make
-- every existing 4-argument call site ambiguous.
DROP FUNCTION IF EXISTS public.fn_validate_company_vat_code(UUID, UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.fn_validate_company_vat_code(
  p_company_id       UUID,
  p_vat_code_id      UUID,
  p_transaction_type TEXT,
  p_context          TEXT DEFAULT 'VAT code',
  p_as_of            DATE DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Every rule lives in the resolver; this is the void-returning face of it
  -- that triggers and document validators call.
  PERFORM fn_resolve_vat_code(p_company_id, p_vat_code_id, p_as_of,
                              p_transaction_type, p_context);
END;
$$;

COMMENT ON FUNCTION public.fn_validate_company_vat_code(UUID, UUID, TEXT, TEXT, DATE) IS
  'Trigger-facing VAT code validation. Delegates every rule to fn_resolve_vat_code as of the document date; p_as_of defaults to today only when the caller genuinely has no document date.';

GRANT EXECUTE ON FUNCTION public.fn_validate_company_vat_code(UUID, UUID, TEXT, TEXT, DATE) TO authenticated;

DROP FUNCTION IF EXISTS public.fn_validate_document_vat_registration(
  UUID, UUID, REGCLASS, NAME, NAME, TEXT, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.fn_validate_document_vat_registration(
  p_company_id             UUID,
  p_document_id            UUID,
  p_line_table             REGCLASS,
  p_parent_column          NAME,
  p_line_vat_amount_column NAME,
  p_transaction_type       TEXT,
  p_header_vat_amount      NUMERIC,
  p_context                TEXT,
  p_as_of                  DATE DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
BEGIN
  PERFORM fn_validate_company_vat_amount(
    p_company_id,
    p_header_vat_amount,
    p_context || ' header VAT amount'
  );

  FOR v_line IN EXECUTE format(
    'SELECT company_id, vat_code_id, %I AS vat_amount FROM %s WHERE %I = $1',
    p_line_vat_amount_column,
    p_line_table,
    p_parent_column
  ) USING p_document_id
  LOOP
    IF v_line.company_id IS DISTINCT FROM p_company_id THEN
      RAISE EXCEPTION '% line company does not match its document company', p_context;
    END IF;

    PERFORM fn_validate_company_vat_code(
      p_company_id,
      v_line.vat_code_id,
      p_transaction_type,
      p_context || ' VAT code',
      p_as_of
    );
    PERFORM fn_validate_company_vat_amount(
      p_company_id,
      v_line.vat_amount,
      p_context || ' line VAT amount'
    );
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.fn_validate_document_vat_registration(
  UUID, UUID, REGCLASS, NAME, NAME, TEXT, NUMERIC, TEXT, DATE) IS
  'Whole-document VAT registration/direction/effective-date validation, evaluated as of the document date.';

-- Generic parent-aware line trigger. Trigger arguments:
-- transaction type, parent table, parent FK, VAT amount column, context,
-- parent document-date column.
CREATE OR REPLACE FUNCTION public.fn_require_document_line_vat_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row JSONB := to_jsonb(NEW);
  v_parent_id UUID;
  v_line_company_id UUID;
  v_parent_company_id UUID;
  v_parent_date DATE;
  v_vat_code_id UUID;
  v_vat_amount NUMERIC;
BEGIN
  IF TG_NARGS <> 6 THEN
    RAISE EXCEPTION 'VAT line trigger is misconfigured on %', TG_TABLE_NAME;
  END IF;

  v_parent_id := NULLIF(v_row ->> TG_ARGV[2], '')::UUID;
  v_line_company_id := NULLIF(v_row ->> 'company_id', '')::UUID;
  v_vat_code_id := NULLIF(v_row ->> 'vat_code_id', '')::UUID;
  v_vat_amount := COALESCE(NULLIF(v_row ->> TG_ARGV[3], '')::NUMERIC, 0);

  IF v_parent_id IS NULL THEN
    RAISE EXCEPTION '% parent document is required', TG_ARGV[4];
  END IF;

  -- The parent's document date is read with the parent's company: the VAT
  -- version in force on that date is what governs the line.
  EXECUTE format('SELECT company_id, %I FROM %I WHERE id = $1', TG_ARGV[5], TG_ARGV[1])
  INTO v_parent_company_id, v_parent_date
  USING v_parent_id;

  IF v_parent_company_id IS NULL THEN
    RAISE EXCEPTION '% parent document was not found', TG_ARGV[4];
  END IF;
  IF v_line_company_id IS DISTINCT FROM v_parent_company_id THEN
    RAISE EXCEPTION '% line company does not match its document company', TG_ARGV[4];
  END IF;

  PERFORM fn_validate_company_vat_code(
    v_parent_company_id,
    v_vat_code_id,
    TG_ARGV[0],
    TG_ARGV[4] || ' VAT code',
    v_parent_date
  );
  PERFORM fn_validate_company_vat_amount(
    v_parent_company_id,
    v_vat_amount,
    TG_ARGV[4] || ' line VAT amount'
  );

  RETURN NEW;
END;
$$;

-- Generic header trigger. Trigger arguments:
-- line table, parent FK, line VAT amount column, transaction type,
-- header VAT amount column, context, header document-date column.
CREATE OR REPLACE FUNCTION public.fn_require_document_header_vat_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row JSONB := to_jsonb(NEW);
  v_header_vat_amount NUMERIC;
  v_document_date DATE;
BEGIN
  IF TG_NARGS <> 7 THEN
    RAISE EXCEPTION 'VAT header trigger is misconfigured on %', TG_TABLE_NAME;
  END IF;

  v_header_vat_amount := COALESCE(NULLIF(v_row ->> TG_ARGV[4], '')::NUMERIC, 0);
  v_document_date := NULLIF(v_row ->> TG_ARGV[6], '')::DATE;

  PERFORM fn_validate_document_vat_registration(
    NEW.company_id,
    NEW.id,
    TG_ARGV[0]::REGCLASS,
    TG_ARGV[1]::NAME,
    TG_ARGV[2]::NAME,
    TG_ARGV[3],
    v_header_vat_amount,
    TG_ARGV[5],
    v_document_date
  );

  RETURN NEW;
END;
$$;

-- ── Line enforcement, re-pointed with each parent's document-date column ────
DROP TRIGGER IF EXISTS trg_si_line_vat_registration ON sales_invoice_lines;
CREATE TRIGGER trg_si_line_vat_registration
  BEFORE INSERT OR UPDATE OF sales_invoice_id, company_id, vat_code_id, vat_amount
  ON sales_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'output_vat', 'sales_invoices', 'sales_invoice_id', 'vat_amount', 'Sales invoice', 'date'
  );

DROP TRIGGER IF EXISTS trg_vb_line_vat_registration ON vendor_bill_lines;
CREATE TRIGGER trg_vb_line_vat_registration
  BEFORE INSERT OR UPDATE OF vendor_bill_id, company_id, vat_code_id, input_vat_amount
  ON vendor_bill_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'input_vat', 'vendor_bills', 'vendor_bill_id', 'input_vat_amount', 'Vendor bill', 'bill_date'
  );

DROP TRIGGER IF EXISTS trg_cm_line_vat_registration ON credit_memo_lines;
CREATE TRIGGER trg_cm_line_vat_registration
  BEFORE INSERT OR UPDATE OF credit_memo_id, company_id, vat_code_id, vat_amount
  ON credit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'output_vat', 'credit_memos', 'credit_memo_id', 'vat_amount', 'Credit memo', 'cm_date'
  );

DROP TRIGGER IF EXISTS trg_dm_line_vat_registration ON debit_memo_lines;
CREATE TRIGGER trg_dm_line_vat_registration
  BEFORE INSERT OR UPDATE OF debit_memo_id, company_id, vat_code_id, vat_amount
  ON debit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'output_vat', 'debit_memos', 'debit_memo_id', 'vat_amount', 'Debit memo', 'dm_date'
  );

DROP TRIGGER IF EXISTS trg_cp_line_vat_registration ON cash_purchase_lines;
CREATE TRIGGER trg_cp_line_vat_registration
  BEFORE INSERT OR UPDATE OF cp_id, company_id, vat_code_id, input_vat_amount
  ON cash_purchase_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'input_vat', 'cash_purchases', 'cp_id', 'input_vat_amount', 'Cash purchase', 'transaction_date'
  );

DROP TRIGGER IF EXISTS trg_vc_line_vat_registration ON vendor_credit_lines;
CREATE TRIGGER trg_vc_line_vat_registration
  BEFORE INSERT OR UPDATE OF vc_id, company_id, vat_code_id, input_vat_amount
  ON vendor_credit_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_line_vat_registration(
    'input_vat', 'vendor_credits', 'vc_id', 'input_vat_amount', 'Vendor credit', 'credit_date'
  );

-- ── Header enforcement, re-pointed with each document-date column ───────────
DROP TRIGGER IF EXISTS trg_si_vat_registration_status ON sales_invoices;
CREATE TRIGGER trg_si_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_vat_amount
  ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'sales_invoice_lines', 'sales_invoice_id', 'vat_amount', 'output_vat',
    'total_vat_amount', 'Sales invoice', 'date'
  );

DROP TRIGGER IF EXISTS trg_vb_vat_registration_status ON vendor_bills;
CREATE TRIGGER trg_vb_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_input_vat_amount
  ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'vendor_bill_lines', 'vendor_bill_id', 'input_vat_amount', 'input_vat',
    'total_input_vat_amount', 'Vendor bill', 'bill_date'
  );

DROP TRIGGER IF EXISTS trg_cm_vat_registration_status ON credit_memos;
CREATE TRIGGER trg_cm_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_vat_amount
  ON credit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'credit_memo_lines', 'credit_memo_id', 'vat_amount', 'output_vat',
    'total_vat_amount', 'Credit memo', 'cm_date'
  );

DROP TRIGGER IF EXISTS trg_dm_vat_registration_status ON debit_memos;
CREATE TRIGGER trg_dm_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_vat_amount
  ON debit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'debit_memo_lines', 'debit_memo_id', 'vat_amount', 'output_vat',
    'total_vat_amount', 'Debit memo', 'dm_date'
  );

DROP TRIGGER IF EXISTS trg_cp_vat_registration_status ON cash_purchases;
CREATE TRIGGER trg_cp_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_input_vat_amount
  ON cash_purchases
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'cash_purchase_lines', 'cp_id', 'input_vat_amount', 'input_vat',
    'total_input_vat_amount', 'Cash purchase', 'transaction_date'
  );

DROP TRIGGER IF EXISTS trg_vc_vat_registration_status ON vendor_credits;
CREATE TRIGGER trg_vc_vat_registration_status
  BEFORE INSERT OR UPDATE OF company_id, status, total_input_vat_amount
  ON vendor_credits
  FOR EACH ROW EXECUTE FUNCTION fn_require_document_header_vat_registration(
    'vendor_credit_lines', 'vc_id', 'input_vat_amount', 'input_vat',
    'total_input_vat_amount', 'Vendor credit', 'credit_date'
  );

-- ── The two per-document validators keep their own document date ────────────
CREATE OR REPLACE FUNCTION public.fn_validate_sales_invoice_vat_registration(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
BEGIN
  FOR v_line IN
    SELECT si.company_id, si.date AS document_date, sil.vat_code_id
    FROM sales_invoices si
    JOIN sales_invoice_lines sil ON sil.sales_invoice_id = si.id
    WHERE si.id = p_invoice_id
  LOOP
    PERFORM fn_validate_company_vat_code(v_line.company_id, v_line.vat_code_id,
                                         'output_vat', 'Sales invoice VAT code',
                                         v_line.document_date);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_vendor_bill_vat_registration(p_bill_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
BEGIN
  FOR v_line IN
    SELECT vb.company_id, vb.bill_date AS document_date, vbl.vat_code_id
    FROM vendor_bills vb
    JOIN vendor_bill_lines vbl ON vbl.vendor_bill_id = vb.id
    WHERE vb.id = p_bill_id
  LOOP
    PERFORM fn_validate_company_vat_code(v_line.company_id, v_line.vat_code_id,
                                         'input_vat', 'Vendor bill VAT code',
                                         v_line.document_date);
  END LOOP;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- The engine. Only the VAT resolution changed; the arithmetic, the withholding
-- branch, the contract and every message are exactly as Phase 4 shipped them.
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
  v_atc_id       UUID          := NULLIF(BTRIM(p_context->>'withholding_atc_code_id'), '')::UUID;
  v_atc_category TEXT          := LOWER(COALESCE(NULLIF(BTRIM(p_context->>'withholding_category'), ''), 'ewt'));
  v_wht_base     NUMERIC(15,2) := ROUND(NULLIF(BTRIM(p_context->>'withholding_base'), '')::NUMERIC, 2);
  v_side         TEXT;
  v_vat_code     public.vat_code_resolution;
  v_class        TEXT;
  v_tax_code_id  UUID;
  v_rate         NUMERIC(9,4);
  v_net          NUMERIC(15,2);
  v_vat          NUMERIC(15,2);
  v_gross        NUMERIC(15,2);
  v_kind         TEXT;
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

  -- ── VAT ──────────────────────────────────────────────────────────────────
  -- A VAT component is ALWAYS emitted, even when no VAT code was supplied, so
  -- that `net_amount` has exactly one definition in the product.  An ABSENT
  -- code is exempt at 0% — the behaviour every caller had before.  A code that
  -- WAS supplied must resolve on the document date, against the company tax
  -- profile and on the right tax side, or the whole computation is refused.
  v_vat_code := fn_resolve_vat_code(v_company_id, v_vat_code_id, v_date, v_side, 'VAT code');

  v_class       := COALESCE(v_vat_code.classification, 'exempt');
  v_rate        := COALESCE(v_vat_code.vat_rate, 0);
  v_tax_code_id := v_vat_code.tax_code_id;
  v_kind        := COALESCE(v_vat_code.transaction_type, v_side);

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
  'The Tax Engine. The only function in PXL that turns a governed tax rate into a tax amount (PAD-001, Delivery Plan Phase 4). VAT and withholding are both resolved from the version in force on the document date. Percentage tax is deliberately absent: no document reaches it yet, and foundation without a caller is what this repository has already paid for once.';

REVOKE ALL ON FUNCTION public.fn_calculate_tax(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_calculate_tax(JSONB) TO authenticated;
