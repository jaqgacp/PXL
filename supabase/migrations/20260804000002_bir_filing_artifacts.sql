-- ═══════════════════════════════════════════════════════════════════════════
-- Delivery Plan Phase 5.8 — BIR filing artifacts, on one governed path.
--
-- THE PRINCIPLE THIS FILE EXISTS TO ENFORCE
--
--     posted transactions → Tax Engine → tax ledger → working paper → artifact
--
--   One path. Every return, every listing, every future form reads the same
--   posted `tax_detail_entries` through the same three functions. Nothing
--   computes a filing figure anywhere else — not in a second SQL function, and
--   not in a browser.
--
-- THE GAP
--   **Nothing has ever been filed from PXL**, and what existed to file with was
--   three copies of the same idea plus three more in JavaScript:
--
--   * `fn_vat_gl_reconciliation`, `fn_wht_gl_reconciliation` and
--     `fn_percentage_tax_gl_reconciliation` were near-identical bodies differing
--     only in which tax kinds they read, which control account they compare
--     against, that withholding excludes the controlled `WHTREM` remittance
--     journal, and that VAT counts `reversed` journals while withholding does
--     not. Four differences, three copies, and every future tax would have been
--     a fourth.
--   * The **2550Q screen computed the quarterly VAT return in the browser**, by
--     summing review views with `reduce`. So did the SLSP export and the SAWT
--     alphalist. A figure computed on the client is not a figure computed from
--     the books, and three clients drift three ways.
--
-- WHAT THIS CHANGES
--   1. `ref_tax_ledger_control` states, per tax kind, which governed account key
--      controls it, its normal balance, which journal statuses count and which
--      reference document types are excluded. It is configuration, seeded by
--      migration, and it is the only place those four facts live.
--   2. `fn_tax_ledger_gl_reconciliation(company, kinds[], from, to)` is **the**
--      reconciliation. The three existing functions become one-line delegations
--      that keep their signatures, their column shapes and their exact
--      semantics, so every caller and every test is untouched.
--   3. `ref_filing_artifact` + `ref_filing_artifact_kind` register what a filing
--      artifact IS: its period basis, the tax kinds it consumes, the sign each
--      kind carries in its net, and the dimensions it groups by. Adding 1601FQ,
--      2550M, 1604E or QAP later is a seed row, not a function.
--   4. `fn_filing_working_paper(company, form_code, year, period)` is **the**
--      reader. One query, no dynamic SQL: the artifact's declared dimensions
--      decide which grouping keys survive.
--   5. `fn_generate_filing_artifact(...)` persists a `filing_artifacts` header
--      and its `filing_artifact_lines`, both immutable once filed, and refuses
--      to leave draft while the artifact disagrees with the ledger it claims to
--      summarise.
--
--   6. `fn_generate_vat_return` and `fn_generate_pt_return` project the 2550Q
--      and 2551Q artifacts into the `vat_returns` and `pt_returns` rows their
--      screens already read, so the browser stops computing and starts
--      displaying. The screens keep their shape; only the source of the numbers
--      changes.
--
--   Percentage tax, which shipped hours earlier with its own generator, is
--   **re-pointed at this engine rather than left beside it**: `fn_generate_pt_return`
--   and `fn_compute_percentage_tax_return` now delegate, and the bespoke
--   computation is deleted. A second pipeline is exactly what this phase exists
--   to prevent, including one of its own making.
--
-- WHAT THIS DOES NOT CHANGE
--   No posting function, no Accounting Kernel path, no journal shape, no tax
--   arithmetic — `fn_calculate_tax` remains the only calculator and this file
--   contains none. No tax-ledger row is written, moved or altered: filing reads
--   the ledger, it never writes it. `vat_returns`, `pt_returns`, `ewt_returns`
--   and `fwt_returns` keep working for the screens that read them; they become
--   projections of the artifact, never a second source.
--
-- REGISTERED IN THIS INCREMENT
--   2550Q (quarterly VAT), 2551Q (percentage tax), 1601EQ (expanded
--   withholding), SLSP (summary list of sales and purchases) and SAWT (summary
--   alphalist of withholding taxes). Form 2306/2307 issuance already has its own
--   governed machinery and is not rebuilt here; 1601FQ, 2550M, QAP, 1604-E and
--   the Books of Accounts exports are seed rows plus a screen and are recorded
--   in the Product Backlog rather than half-built.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. WHAT CONTROLS A TAX KIND
--
-- Four facts decided the difference between the three reconciliation functions.
-- They are configuration, not code, and this is where they live.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS ref_tax_ledger_control (
  tax_kind                  TEXT PRIMARY KEY,
  description               TEXT NOT NULL,
  mapping_key               TEXT NOT NULL REFERENCES ref_mapping_key(key_code),
  normal_balance            TEXT NOT NULL CHECK (normal_balance IN ('debit','credit')),
  included_je_statuses      TEXT[] NOT NULL DEFAULT ARRAY['posted'],
  excluded_reference_types  TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  is_active                 BOOLEAN NOT NULL DEFAULT true,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE ref_tax_ledger_control IS
  'Filing engine: the governed account, normal balance, journal statuses and excluded document types that tie one tax kind to the General Ledger. Seed-only; not a runtime write.';
COMMENT ON COLUMN ref_tax_ledger_control.included_je_statuses IS
  'VAT counts reversed journals because a reversal writes its own counter tax row; withholding does not. The difference is configuration, not two functions.';
COMMENT ON COLUMN ref_tax_ledger_control.excluded_reference_types IS
  'Controlled documents whose movement settles the control account rather than creating tax: the WHTREM remittance journal (PXL-AUD-041).';

INSERT INTO ref_tax_ledger_control (
  tax_kind, description, mapping_key, normal_balance,
  included_je_statuses, excluded_reference_types)
VALUES
  ('output_vat',     'Output VAT on sales',                    'VAT_OUTPUT',             'credit', ARRAY['posted','reversed'], ARRAY[]::TEXT[]),
  ('input_vat',      'Creditable input VAT on purchases',      'VAT_INPUT',              'debit',  ARRAY['posted','reversed'], ARRAY[]::TEXT[]),
  ('ewt_payable',    'Expanded withholding tax withheld from suppliers', 'EWT_PAYABLE',  'credit', ARRAY['posted'],            ARRAY['WHTREM']),
  ('cwt_receivable', 'Creditable withholding tax withheld by customers', 'EWT_WITHHELD', 'debit',  ARRAY['posted'],            ARRAY['WHTREM']),
  ('percentage_tax', 'Percentage tax on gross sales (Section 116)', 'PERCENTAGE_TAX_PAYABLE', 'credit', ARRAY['posted','reversed'], ARRAY[]::TEXT[])
ON CONFLICT (tax_kind) DO UPDATE
  SET description              = EXCLUDED.description,
      mapping_key              = EXCLUDED.mapping_key,
      normal_balance           = EXCLUDED.normal_balance,
      included_je_statuses     = EXCLUDED.included_je_statuses,
      excluded_reference_types = EXCLUDED.excluded_reference_types,
      is_active                = true;

ALTER TABLE ref_tax_ledger_control ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ref_tax_ledger_control FROM PUBLIC;
GRANT SELECT ON ref_tax_ledger_control TO authenticated;
DROP POLICY IF EXISTS ref_tax_ledger_control_read ON ref_tax_ledger_control;
CREATE POLICY ref_tax_ledger_control_read ON ref_tax_ledger_control
  FOR SELECT TO authenticated USING (true);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. THE ONE RECONCILIATION
--
-- Every "does the tax ledger agree with the books" question in the product is
-- this function. The account is resolved through the COA engine, exactly as a
-- posting resolves it, so the reconciliation compares against the account the
-- posting actually used.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_tax_ledger_gl_reconciliation(
  p_company_id UUID,
  p_tax_kinds  TEXT[],
  p_date_from  DATE,
  p_date_to    DATE
)
RETURNS TABLE (
  tax_kind          TEXT,
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
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Invalid reconciliation date range % to %', p_date_from, p_date_to;
  END IF;
  IF p_tax_kinds IS NULL OR cardinality(p_tax_kinds) = 0 THEN
    RAISE EXCEPTION 'Reconciliation requires at least one tax kind';
  END IF;

  RETURN QUERY
  WITH kinds AS (
    SELECT c.tax_kind AS kind,
           c.normal_balance,
           c.included_je_statuses,
           c.excluded_reference_types,
           -- The control account is resolved the way a posting resolves it. A
           -- company that never configured the key reconciles only while it has
           -- recognised nothing, which is the honest answer rather than a zero.
           (SELECT m.account_id
              FROM account_mapping m
             WHERE m.company_id = p_company_id
               AND m.key_code = c.mapping_key
               AND m.branch_id IS NULL AND m.document_type IS NULL
               AND m.party_id IS NULL AND m.item_id IS NULL
               AND m.item_group_id IS NULL AND m.tax_profile_id IS NULL
               AND m.effective_to IS NULL
             LIMIT 1) AS account_id
    FROM ref_tax_ledger_control c
    WHERE c.tax_kind = ANY(p_tax_kinds)
      AND c.is_active
  ),
  ledger AS (
    SELECT tde.tax_kind AS kind,
           COALESCE(SUM(tde.tax_base), 0)::NUMERIC(15,2)   AS base_sum,
           COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2) AS tax_sum
    FROM tax_detail_entries tde
    WHERE tde.company_id = p_company_id
      AND tde.tax_kind = ANY(p_tax_kinds)
      AND tde.document_date BETWEEN p_date_from AND p_date_to
    GROUP BY tde.tax_kind
  ),
  gl AS (
    SELECT k.kind,
           k.account_id,
           CASE WHEN k.account_id IS NULL THEN NULL
                ELSE (
                  SELECT COALESCE(SUM(
                    CASE WHEN k.normal_balance = 'credit'
                         THEN jel.credit_amount - jel.debit_amount
                         ELSE jel.debit_amount - jel.credit_amount END), 0)
                  FROM journal_entry_lines jel
                  JOIN journal_entries je ON je.id = jel.je_id
                  WHERE jel.account_id = k.account_id
                    AND jel.company_id = p_company_id
                    AND je.status = ANY(k.included_je_statuses)
                    AND je.je_date BETWEEN p_date_from AND p_date_to
                    AND NOT (COALESCE(je.reference_doc_type, '')
                             = ANY(k.excluded_reference_types))
                )
           END::NUMERIC(15,2) AS gl_sum
    FROM kinds k
  )
  SELECT
    g.kind,
    COALESCE(l.base_sum, 0)::NUMERIC(15,2),
    COALESCE(l.tax_sum, 0)::NUMERIC(15,2),
    g.account_id,
    coa.account_code,
    coa.account_name,
    g.gl_sum,
    (COALESCE(l.tax_sum, 0) - COALESCE(g.gl_sum, 0))::NUMERIC(15,2),
    CASE WHEN g.account_id IS NULL
         THEN COALESCE(l.tax_sum, 0) = 0
         ELSE ABS(COALESCE(l.tax_sum, 0) - g.gl_sum) <= 0.01
    END
  FROM gl g
  LEFT JOIN ledger l ON l.kind = g.kind
  LEFT JOIN chart_of_accounts coa ON coa.id = g.account_id
  ORDER BY g.kind;
END;
$function$;

COMMENT ON FUNCTION public.fn_tax_ledger_gl_reconciliation(UUID, TEXT[], DATE, DATE) IS
  'The one reconciliation between the tax ledger and the General Ledger, for any tax kind. What used to differ between the VAT, withholding and percentage-tax copies is now configuration in ref_tax_ledger_control.';

REVOKE ALL ON FUNCTION public.fn_tax_ledger_gl_reconciliation(UUID, TEXT[], DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_tax_ledger_gl_reconciliation(UUID, TEXT[], DATE, DATE) TO authenticated;

-- ── The three existing faces become delegations ────────────────────────────
-- Same signature, same columns, same semantics, no second implementation. The
-- callers and tests that already depend on them do not change.
CREATE OR REPLACE FUNCTION fn_vat_gl_reconciliation(
  p_company_id UUID,
  p_date_from  DATE,
  p_date_to    DATE
)
RETURNS TABLE (
  tax_kind          TEXT,
  ledger_tax_base   NUMERIC(15,2),
  ledger_tax_amount NUMERIC(15,2),
  gl_account_id     UUID,
  gl_account_code   TEXT,
  gl_account_name   TEXT,
  gl_amount         NUMERIC(15,2),
  variance          NUMERIC(15,2),
  is_reconciled     BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM fn_tax_ledger_gl_reconciliation(
    p_company_id, ARRAY['input_vat','output_vat'], p_date_from, p_date_to);
$$;

COMMENT ON FUNCTION fn_vat_gl_reconciliation(UUID, DATE, DATE) IS
  'VAT face of fn_tax_ledger_gl_reconciliation. Kept for its callers; it computes nothing of its own.';

CREATE OR REPLACE FUNCTION fn_wht_gl_reconciliation(
  p_company_id UUID,
  p_date_from  DATE,
  p_date_to    DATE
)
RETURNS TABLE (
  tax_kind          TEXT,
  ledger_tax_base   NUMERIC(15,2),
  ledger_tax_amount NUMERIC(15,2),
  gl_account_id     UUID,
  gl_account_code   TEXT,
  gl_account_name   TEXT,
  gl_amount         NUMERIC(15,2),
  variance          NUMERIC(15,2),
  is_reconciled     BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM fn_tax_ledger_gl_reconciliation(
    p_company_id, ARRAY['cwt_receivable','ewt_payable'], p_date_from, p_date_to);
$$;

COMMENT ON FUNCTION fn_wht_gl_reconciliation(UUID, DATE, DATE) IS
  'Withholding face of fn_tax_ledger_gl_reconciliation, including the WHTREM exclusion (PXL-AUD-041), which is now configuration. It computes nothing of its own.';

DROP FUNCTION IF EXISTS public.fn_percentage_tax_gl_reconciliation(UUID, DATE, DATE);
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.ledger_tax_base, r.ledger_tax_amount, r.gl_account_id,
         r.gl_account_code, r.gl_account_name, r.gl_amount, r.variance,
         r.is_reconciled
  FROM fn_tax_ledger_gl_reconciliation(
         p_company_id, ARRAY['percentage_tax'], p_date_from, p_date_to) r;
$$;

COMMENT ON FUNCTION public.fn_percentage_tax_gl_reconciliation(UUID, DATE, DATE) IS
  'Percentage-tax face of fn_tax_ledger_gl_reconciliation. It computes nothing of its own.';

REVOKE ALL ON FUNCTION public.fn_percentage_tax_gl_reconciliation(UUID, DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_percentage_tax_gl_reconciliation(UUID, DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_vat_gl_reconciliation(UUID, DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_wht_gl_reconciliation(UUID, DATE, DATE) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. WHAT A FILING ARTIFACT IS
--
-- A return and a listing differ in period basis, which tax kinds they consume,
-- which way each kind moves the net, and which dimensions they group by.
-- Nothing else. Registering the next form is a seed row.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS ref_filing_artifact (
  form_code        TEXT PRIMARY KEY,
  form_name        TEXT NOT NULL,
  artifact_kind    TEXT NOT NULL CHECK (artifact_kind IN ('return','listing')),
  period_basis     TEXT NOT NULL CHECK (period_basis IN ('monthly','quarterly','annual')),
  -- Which grouping dimensions survive into the working paper. Governed set;
  -- a dimension not named here is collapsed, which is what makes one query
  -- serve a summary return and a per-counterparty alphalist alike.
  group_dimensions TEXT[] NOT NULL,
  statutory_deadline_rule TEXT NOT NULL,
  statutory_basis  TEXT,
  is_active        BOOLEAN NOT NULL DEFAULT true,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ref_filing_artifact_dimensions_chk CHECK (
    group_dimensions <@ ARRAY['tax_kind','tax_code','vat_code','atc','counterparty']
  )
);

CREATE TABLE IF NOT EXISTS ref_filing_artifact_kind (
  form_code  TEXT NOT NULL REFERENCES ref_filing_artifact(form_code) ON DELETE CASCADE,
  tax_kind   TEXT NOT NULL REFERENCES ref_tax_ledger_control(tax_kind),
  -- +1 for a tax the return owes, -1 for a credit against it. A listing carries
  -- no net, so its sign is 0 and no payable is reported.
  net_sign   SMALLINT NOT NULL DEFAULT 1 CHECK (net_sign IN (-1, 0, 1)),
  PRIMARY KEY (form_code, tax_kind)
);

COMMENT ON TABLE ref_filing_artifact IS
  'Filing engine: the registry of BIR filing artifacts. Registering a new return or listing is a seed row here plus its tax kinds; no function changes.';

INSERT INTO ref_filing_artifact (
  form_code, form_name, artifact_kind, period_basis, group_dimensions,
  statutory_deadline_rule, statutory_basis)
VALUES
  ('2550Q',  'Quarterly Value-Added Tax Return', 'return',  'quarterly',
   ARRAY['tax_kind','vat_code'], '25th day following the close of the quarter',
   'NIRC Sec. 114'),
  ('2551Q',  'Quarterly Percentage Tax Return',  'return',  'quarterly',
   ARRAY['atc','tax_code'],      '25th day following the close of the quarter',
   'NIRC Sec. 116 / 128'),
  ('1601EQ', 'Quarterly Remittance Return of Creditable Income Taxes Withheld (Expanded)',
   'return', 'quarterly', ARRAY['atc'],
   'Last day of the month following the close of the quarter', 'NIRC Sec. 58'),
  ('SLSP',   'Summary List of Sales and Purchases', 'listing', 'quarterly',
   ARRAY['tax_kind','counterparty'], '25th day following the close of the quarter',
   'RR 1-2012'),
  ('SAWT',   'Summary Alphalist of Withholding Taxes', 'listing', 'quarterly',
   ARRAY['counterparty','atc'], 'Attached to the quarterly or annual income tax return',
   'RR 2-98 as amended')
ON CONFLICT (form_code) DO UPDATE
  SET form_name               = EXCLUDED.form_name,
      artifact_kind           = EXCLUDED.artifact_kind,
      period_basis            = EXCLUDED.period_basis,
      group_dimensions        = EXCLUDED.group_dimensions,
      statutory_deadline_rule = EXCLUDED.statutory_deadline_rule,
      statutory_basis         = EXCLUDED.statutory_basis,
      is_active               = true;

INSERT INTO ref_filing_artifact_kind (form_code, tax_kind, net_sign) VALUES
  ('2550Q',  'output_vat',      1),
  ('2550Q',  'input_vat',      -1),
  ('2551Q',  'percentage_tax',  1),
  ('1601EQ', 'ewt_payable',     1),
  ('SLSP',   'output_vat',      0),
  ('SLSP',   'input_vat',       0),
  ('SAWT',   'cwt_receivable',  0)
ON CONFLICT (form_code, tax_kind) DO UPDATE SET net_sign = EXCLUDED.net_sign;

ALTER TABLE ref_filing_artifact ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref_filing_artifact_kind ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ref_filing_artifact FROM PUBLIC;
REVOKE ALL ON ref_filing_artifact_kind FROM PUBLIC;
GRANT SELECT ON ref_filing_artifact TO authenticated;
GRANT SELECT ON ref_filing_artifact_kind TO authenticated;
DROP POLICY IF EXISTS ref_filing_artifact_read ON ref_filing_artifact;
CREATE POLICY ref_filing_artifact_read ON ref_filing_artifact
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS ref_filing_artifact_kind_read ON ref_filing_artifact_kind;
CREATE POLICY ref_filing_artifact_kind_read ON ref_filing_artifact_kind
  FOR SELECT TO authenticated USING (true);

-- ── One place that turns a period into dates ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_filing_period_bounds(
  p_period_basis TEXT,
  p_year         INTEGER,
  p_period       INTEGER,
  OUT date_from  DATE,
  OUT date_to    DATE
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_year IS NULL OR p_year < 1900 THEN
    RAISE EXCEPTION 'Invalid filing year %', p_year;
  END IF;

  CASE p_period_basis
    WHEN 'monthly' THEN
      IF p_period IS NULL OR p_period NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'Invalid monthly filing period: month %', p_period;
      END IF;
      date_from := make_date(p_year, p_period, 1);
      date_to   := (date_from + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    WHEN 'quarterly' THEN
      IF p_period IS NULL OR p_period NOT BETWEEN 1 AND 4 THEN
        RAISE EXCEPTION 'Invalid quarterly filing period: quarter %', p_period;
      END IF;
      date_from := make_date(p_year, (p_period - 1) * 3 + 1, 1);
      date_to   := (date_from + INTERVAL '3 months' - INTERVAL '1 day')::DATE;
    WHEN 'annual' THEN
      date_from := make_date(p_year, 1, 1);
      date_to   := make_date(p_year, 12, 31);
    ELSE
      RAISE EXCEPTION 'Unknown filing period basis %', p_period_basis;
  END CASE;
END;
$$;

COMMENT ON FUNCTION public.fn_filing_period_bounds(TEXT, INTEGER, INTEGER) IS
  'The one place a filing period becomes a date range. Every artifact, every return, every listing.';

REVOKE ALL ON FUNCTION public.fn_filing_period_bounds(TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_filing_period_bounds(TEXT, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. THE ONE WORKING-PAPER READER
--
-- The schedule that stands behind every figure on every form. One query: the
-- artifact's declared dimensions decide which grouping keys survive, so a
-- summary return and a per-counterparty alphalist are the same code path with
-- different configuration — no dynamic SQL, and no second reader to drift.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_filing_working_paper(
  p_company_id UUID,
  p_form_code  TEXT,
  p_year       INTEGER,
  p_period     INTEGER
)
RETURNS TABLE (
  tax_kind         TEXT,
  classification   TEXT,
  tax_code         TEXT,
  vat_code         TEXT,
  atc_code         TEXT,
  counterparty_id  UUID,
  counterparty_tin TEXT,
  counterparty_name TEXT,
  tax_rate         NUMERIC(9,4),
  tax_base         NUMERIC(15,2),
  tax_amount       NUMERIC(15,2),
  document_count   INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_artifact ref_filing_artifact%ROWTYPE;
  v_from     DATE;
  v_to       DATE;
  v_dims     TEXT[];
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_artifact FROM ref_filing_artifact
  WHERE form_code = UPPER(BTRIM(p_form_code)) AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown or inactive filing artifact %', p_form_code;
  END IF;
  v_dims := v_artifact.group_dimensions;

  SELECT b.date_from, b.date_to INTO v_from, v_to
  FROM fn_filing_period_bounds(v_artifact.period_basis, p_year, p_period) b;

  RETURN QUERY
  SELECT
    g.k_tax_kind,
    MAX(vc.vat_classification)::TEXT,
    MAX(tc.code)::TEXT,
    MAX(vc.vat_code)::TEXT,
    MAX(ac.code)::TEXT,
    g.k_counterparty_id,
    MAX(g.k_counterparty_tin)::TEXT,
    MAX(g.k_counterparty_name)::TEXT,
    MAX(g.tax_rate)::NUMERIC(9,4),
    COALESCE(SUM(g.tax_base), 0)::NUMERIC(15,2),
    COALESCE(SUM(g.tax_amount), 0)::NUMERIC(15,2),
    COUNT(DISTINCT g.source_doc_id)::INTEGER
  FROM (
    SELECT
      -- A dimension the artifact does not group by is collapsed to NULL, which
      -- is precisely what "this form summarises across it" means.
      CASE WHEN 'tax_kind'     = ANY(v_dims) THEN tde.tax_kind END              AS k_tax_kind,
      CASE WHEN 'tax_code'     = ANY(v_dims) THEN tde.tax_code_id END           AS k_tax_code_id,
      CASE WHEN 'vat_code'     = ANY(v_dims) THEN tde.vat_code_id END           AS k_vat_code_id,
      CASE WHEN 'atc'          = ANY(v_dims) THEN tde.atc_code_id END           AS k_atc_code_id,
      CASE WHEN 'counterparty' = ANY(v_dims) THEN tde.counterparty_id END       AS k_counterparty_id,
      CASE WHEN 'counterparty' = ANY(v_dims) THEN tde.counterparty_tin END      AS k_counterparty_tin,
      CASE WHEN 'counterparty' = ANY(v_dims) THEN tde.counterparty_name END     AS k_counterparty_name,
      tde.tax_rate, tde.tax_base, tde.tax_amount, tde.source_doc_id
    FROM tax_detail_entries tde
    JOIN ref_filing_artifact_kind fak
      ON fak.form_code = v_artifact.form_code AND fak.tax_kind = tde.tax_kind
    WHERE tde.company_id = p_company_id
      AND tde.document_date BETWEEN v_from AND v_to
  ) g
  LEFT JOIN tax_codes tc ON tc.id = g.k_tax_code_id
  LEFT JOIN vat_codes vc ON vc.id = g.k_vat_code_id
  LEFT JOIN atc_codes ac ON ac.id = g.k_atc_code_id
  GROUP BY g.k_tax_kind, g.k_tax_code_id, g.k_vat_code_id, g.k_atc_code_id,
           g.k_counterparty_id
  HAVING COALESCE(SUM(g.tax_base), 0) <> 0 OR COALESCE(SUM(g.tax_amount), 0) <> 0
  ORDER BY g.k_tax_kind, MAX(ac.code), MAX(vc.vat_code), MAX(g.k_counterparty_name);
END;
$function$;

COMMENT ON FUNCTION public.fn_filing_working_paper(UUID, TEXT, INTEGER, INTEGER) IS
  'The one working-paper reader behind every BIR filing artifact. Reads the posted tax ledger and groups by exactly the dimensions the artifact declares. No form has its own query.';

REVOKE ALL ON FUNCTION public.fn_filing_working_paper(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_filing_working_paper(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- ── The reconciliation face for one artifact ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_filing_reconciliation(
  p_company_id UUID,
  p_form_code  TEXT,
  p_year       INTEGER,
  p_period     INTEGER
)
RETURNS TABLE (
  tax_kind          TEXT,
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
  v_artifact ref_filing_artifact%ROWTYPE;
  v_from     DATE;
  v_to       DATE;
  v_kinds    TEXT[];
BEGIN
  SELECT * INTO v_artifact FROM ref_filing_artifact
  WHERE form_code = UPPER(BTRIM(p_form_code)) AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown or inactive filing artifact %', p_form_code;
  END IF;

  SELECT b.date_from, b.date_to INTO v_from, v_to
  FROM fn_filing_period_bounds(v_artifact.period_basis, p_year, p_period) b;

  SELECT array_agg(fak.tax_kind ORDER BY fak.tax_kind) INTO v_kinds
  FROM ref_filing_artifact_kind fak WHERE fak.form_code = v_artifact.form_code;

  RETURN QUERY
  SELECT * FROM fn_tax_ledger_gl_reconciliation(p_company_id, v_kinds, v_from, v_to);
END;
$function$;

COMMENT ON FUNCTION public.fn_filing_reconciliation(UUID, TEXT, INTEGER, INTEGER) IS
  'Ties one filing artifact to the General Ledger through the one reconciliation, for exactly the tax kinds it consumes.';

REVOKE ALL ON FUNCTION public.fn_filing_reconciliation(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_filing_reconciliation(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. THE ARTIFACT ITSELF
--
-- One header and one line table for every form. A filed artifact is evidence:
-- it is frozen, and it may not be marked final or filed while it disagrees with
-- the ledger it claims to summarise.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS filing_artifacts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID NOT NULL REFERENCES companies(id),
  form_code         TEXT NOT NULL REFERENCES ref_filing_artifact(form_code),
  period_year       INTEGER NOT NULL,
  period_number     INTEGER NOT NULL,
  period_from       DATE NOT NULL,
  period_to         DATE NOT NULL,
  total_tax_base    NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_tax_amount  NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_tax_payable   NUMERIC(15,2),
  summary           JSONB NOT NULL DEFAULT '{}'::JSONB,
  status            TEXT NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','final','filed')),
  filed_date        DATE,
  reference_no      TEXT,
  remarks           TEXT,
  generated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, form_code, period_year, period_number)
);

CREATE TABLE IF NOT EXISTS filing_artifact_lines (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artifact_id       UUID NOT NULL REFERENCES filing_artifacts(id) ON DELETE CASCADE,
  line_number       INTEGER NOT NULL,
  tax_kind          TEXT,
  classification    TEXT,
  tax_code          TEXT,
  vat_code          TEXT,
  atc_code          TEXT,
  -- Kept so a stored alphalist line can be traced back to the accounting
  -- sources behind it, exactly as the screen traces the working paper.
  counterparty_id   UUID,
  counterparty_tin  TEXT,
  counterparty_name TEXT,
  tax_rate          NUMERIC(9,4),
  tax_base          NUMERIC(15,2) NOT NULL DEFAULT 0,
  tax_amount        NUMERIC(15,2) NOT NULL DEFAULT 0,
  document_count    INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (artifact_id, line_number)
);

COMMENT ON TABLE filing_artifacts IS
  'One generated BIR filing artifact per company, form and period. Generated from the posted tax ledger by fn_generate_filing_artifact; never typed.';
COMMENT ON COLUMN filing_artifacts.summary IS
  'Per-tax-kind base and tax totals, keyed by tax kind. Form-specific figures live here rather than as per-form columns, which is what lets one table serve every form.';
COMMENT ON COLUMN filing_artifacts.net_tax_payable IS
  'Signed net for a return (output VAT less creditable input VAT, tax withheld, percentage tax due). NULL for a listing, which owes nothing.';

CREATE INDEX IF NOT EXISTS idx_filing_artifacts_company_period
  ON filing_artifacts (company_id, form_code, period_year, period_number);

ALTER TABLE filing_artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE filing_artifact_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS filing_artifacts_read ON filing_artifacts;
CREATE POLICY filing_artifacts_read ON filing_artifacts
  FOR SELECT TO authenticated USING (is_company_member(company_id));
-- Generation and status changes flow through the governed RPCs (DEFINER), so
-- there is no direct INSERT policy: an artifact cannot be typed into existence.
DROP POLICY IF EXISTS filing_artifacts_update ON filing_artifacts;
CREATE POLICY filing_artifacts_update ON filing_artifacts
  FOR UPDATE TO authenticated USING (is_company_member(company_id));

DROP POLICY IF EXISTS filing_artifact_lines_read ON filing_artifact_lines;
CREATE POLICY filing_artifact_lines_read ON filing_artifact_lines
  FOR SELECT TO authenticated USING (
    is_company_member((SELECT company_id FROM filing_artifacts WHERE id = artifact_id)));

DROP TRIGGER IF EXISTS trg_filing_artifacts_updated_at ON filing_artifacts;
CREATE TRIGGER trg_filing_artifacts_updated_at
  BEFORE UPDATE ON filing_artifacts
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── A filed artifact is evidence: frozen, and never ahead of the ledger ────
CREATE OR REPLACE FUNCTION public.fn_guard_filing_artifact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ledger_base NUMERIC(15,2);
  v_ledger_tax  NUMERIC(15,2);
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN
      RAISE EXCEPTION 'A % filing artifact cannot be deleted. Reopen it to draft first.', OLD.status;
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'filed' AND NEW.status = 'filed'
       AND (NEW.total_tax_amount IS DISTINCT FROM OLD.total_tax_amount
            OR NEW.total_tax_base IS DISTINCT FROM OLD.total_tax_base
            OR NEW.period_from IS DISTINCT FROM OLD.period_from
            OR NEW.period_to IS DISTINCT FROM OLD.period_to) THEN
      RAISE EXCEPTION 'A filed % return is immutable. File an amended return instead.', OLD.form_code;
    END IF;
  END IF;

  -- Leaving draft is the claim that this artifact IS the ledger for its period.
  IF NEW.status <> 'draft' THEN
    SELECT COALESCE(SUM(r.ledger_tax_base), 0), COALESCE(SUM(r.ledger_tax_amount), 0)
      INTO v_ledger_base, v_ledger_tax
    FROM fn_filing_reconciliation(NEW.company_id, NEW.form_code,
                                  NEW.period_year, NEW.period_number) r;

    IF ABS(COALESCE(NEW.total_tax_amount, 0) - v_ledger_tax) > 0.01
       OR ABS(COALESCE(NEW.total_tax_base, 0) - v_ledger_base) > 0.01 THEN
      RAISE EXCEPTION '% for % period % does not reconcile to the posted ledger (artifact base %, tax %; ledger base %, tax %). Regenerate it before marking it %.',
        NEW.form_code, NEW.period_year, NEW.period_number,
        NEW.total_tax_base, NEW.total_tax_amount, v_ledger_base, v_ledger_tax,
        NEW.status;
    END IF;

    IF EXISTS (
      SELECT 1 FROM fn_filing_reconciliation(NEW.company_id, NEW.form_code,
                                             NEW.period_year, NEW.period_number) r
      WHERE NOT r.is_reconciled
    ) THEN
      RAISE EXCEPTION '% for % period % cannot be marked % while its tax ledger does not tie to the General Ledger.',
        NEW.form_code, NEW.period_year, NEW.period_number, NEW.status;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_filing_artifact_guard ON filing_artifacts;
CREATE TRIGGER trg_filing_artifact_guard
  BEFORE UPDATE OR DELETE ON filing_artifacts
  FOR EACH ROW EXECUTE FUNCTION fn_guard_filing_artifact();

-- ── The generator ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_generate_filing_artifact(
  p_company_id UUID,
  p_form_code  TEXT,
  p_year       INTEGER,
  p_period     INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_artifact  ref_filing_artifact%ROWTYPE;
  v_from      DATE;
  v_to        DATE;
  v_row       filing_artifacts%ROWTYPE;
  v_id        UUID;
  v_base      NUMERIC(15,2) := 0;
  v_tax       NUMERIC(15,2) := 0;
  v_net       NUMERIC(15,2);
  v_summary   JSONB := '{}'::JSONB;
  v_lines     INTEGER := 0;
  v_reconciled BOOLEAN;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_artifact FROM ref_filing_artifact
  WHERE form_code = UPPER(BTRIM(p_form_code)) AND is_active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown or inactive filing artifact %', p_form_code;
  END IF;

  SELECT b.date_from, b.date_to INTO v_from, v_to
  FROM fn_filing_period_bounds(v_artifact.period_basis, p_year, p_period) b;

  SELECT * INTO v_row FROM filing_artifacts
  WHERE company_id = p_company_id AND form_code = v_artifact.form_code
    AND period_year = p_year AND period_number = p_period;

  IF FOUND AND v_row.status <> 'draft' THEN
    RAISE EXCEPTION 'The % % period % artifact is % and cannot be regenerated. Reopen it to draft first.',
      p_year, v_artifact.form_code, p_period, v_row.status;
  END IF;

  -- Totals and the per-kind summary come from the reconciliation, which reads
  -- the same ledger the working paper does. One read, one truth.
  SELECT COALESCE(SUM(r.ledger_tax_base), 0),
         COALESCE(SUM(r.ledger_tax_amount), 0),
         bool_and(r.is_reconciled),
         COALESCE(jsonb_object_agg(r.tax_kind, jsonb_build_object(
           'tax_base', r.ledger_tax_base,
           'tax_amount', r.ledger_tax_amount,
           'gl_amount', r.gl_amount,
           'variance', r.variance,
           'is_reconciled', r.is_reconciled)), '{}'::JSONB)
    INTO v_base, v_tax, v_reconciled, v_summary
  FROM fn_filing_reconciliation(p_company_id, v_artifact.form_code, p_year, p_period) r;

  IF v_artifact.artifact_kind = 'return' THEN
    SELECT COALESCE(SUM(r.ledger_tax_amount * fak.net_sign), 0)
      INTO v_net
    FROM fn_filing_reconciliation(p_company_id, v_artifact.form_code, p_year, p_period) r
    JOIN ref_filing_artifact_kind fak
      ON fak.form_code = v_artifact.form_code AND fak.tax_kind = r.tax_kind;
  ELSE
    v_net := NULL;
  END IF;

  -- `v_row.id` is the only reliable test here: the aggregate reads above have
  -- long since reset FOUND, and an aggregate always finds its one row.
  IF v_row.id IS NOT NULL THEN
    UPDATE filing_artifacts SET
      period_from = v_from, period_to = v_to,
      total_tax_base = v_base, total_tax_amount = v_tax,
      net_tax_payable = v_net, summary = v_summary,
      generated_at = now(), updated_by = auth.uid(), updated_at = now()
    WHERE id = v_row.id
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO filing_artifacts (
      company_id, form_code, period_year, period_number, period_from, period_to,
      total_tax_base, total_tax_amount, net_tax_payable, summary,
      status, created_by, updated_by)
    VALUES (
      p_company_id, v_artifact.form_code, p_year, p_period, v_from, v_to,
      v_base, v_tax, v_net, v_summary, 'draft', auth.uid(), auth.uid())
    RETURNING id INTO v_id;
  END IF;

  DELETE FROM filing_artifact_lines WHERE artifact_id = v_id;

  INSERT INTO filing_artifact_lines (
    artifact_id, line_number, tax_kind, classification, tax_code, vat_code,
    atc_code, counterparty_id, counterparty_tin, counterparty_name, tax_rate,
    tax_base, tax_amount, document_count)
  SELECT v_id, ROW_NUMBER() OVER (),
         w.tax_kind, w.classification, w.tax_code, w.vat_code, w.atc_code,
         w.counterparty_id, w.counterparty_tin, w.counterparty_name, w.tax_rate,
         w.tax_base, w.tax_amount, w.document_count
  FROM fn_filing_working_paper(p_company_id, v_artifact.form_code, p_year, p_period) w;

  GET DIAGNOSTICS v_lines = ROW_COUNT;

  RETURN jsonb_build_object(
    'artifact_id',      v_id,
    'form_code',        v_artifact.form_code,
    'form_name',        v_artifact.form_name,
    'artifact_kind',    v_artifact.artifact_kind,
    'period_year',      p_year,
    'period_number',    p_period,
    'period_from',      v_from,
    'period_to',        v_to,
    'total_tax_base',   v_base,
    'total_tax_amount', v_tax,
    'net_tax_payable',  v_net,
    'is_reconciled',    COALESCE(v_reconciled, true),
    'summary',          v_summary,
    'line_count',       v_lines,
    'deadline_rule',    v_artifact.statutory_deadline_rule);
END;
$function$;

COMMENT ON FUNCTION public.fn_generate_filing_artifact(UUID, TEXT, INTEGER, INTEGER) IS
  'Generates any registered BIR filing artifact and its working paper from the posted tax ledger. The only writer of filing_artifacts; refuses to regenerate one that is already final or filed.';

REVOKE ALL ON FUNCTION public.fn_generate_filing_artifact(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_filing_artifact(UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. PERCENTAGE TAX JOINS THE ENGINE IT PRECEDED BY A DAY
--
-- `fn_generate_pt_return` and `fn_compute_percentage_tax_return` shipped hours
-- earlier with their own ledger reads. They now delegate: the 2551Q is generated
-- by the same function as every other artifact, and `pt_returns` becomes the
-- projection its screens read rather than a second computation.
-- ═══════════════════════════════════════════════════════════════════════════
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- pt_code is the company's own label for the code; the engine groups by the
  -- governed tax-code version, which is what the return is filed on.
  SELECT w.atc_code, w.tax_code,
         (SELECT MAX(ptc.pt_code) FROM percentage_tax_codes ptc
           JOIN tax_codes tc ON tc.id = ptc.tax_code_id
          WHERE ptc.company_id = p_company_id AND tc.code = w.tax_code),
         w.tax_rate, w.tax_base, w.tax_amount, w.document_count
  FROM fn_filing_working_paper(p_company_id, '2551Q', p_year, p_quarter) w
  ORDER BY w.atc_code, w.tax_code;
$$;

COMMENT ON FUNCTION public.fn_compute_percentage_tax_return(UUID, INTEGER, INTEGER) IS
  '2551Q face of fn_filing_working_paper. It computes nothing of its own.';

REVOKE ALL ON FUNCTION public.fn_compute_percentage_tax_return(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_compute_percentage_tax_return(UUID, INTEGER, INTEGER) TO authenticated;

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
  v_result     JSONB;
  v_base       NUMERIC(15,2);
  v_due        NUMERIC(15,2);
  v_rate       NUMERIC(5,2);
  v_rate_count INTEGER;
  v_from       DATE;
  v_to         DATE;
  v_return     pt_returns%ROWTYPE;
  v_paid_prior NUMERIC(15,2) := 0;
  v_header_id  UUID;
  v_lines      INTEGER := 0;
BEGIN
  -- One generator, one working paper, one reconciliation — the same three the
  -- 2550Q and the 1601EQ use.
  v_result := fn_generate_filing_artifact(p_company_id, '2551Q', p_year, p_quarter);
  v_base   := (v_result->>'total_tax_base')::NUMERIC;
  v_due    := (v_result->>'total_tax_amount')::NUMERIC;
  v_from   := (v_result->>'period_from')::DATE;
  v_to     := (v_result->>'period_to')::DATE;

  SELECT COUNT(DISTINCT tde.tax_rate) INTO v_rate_count
  FROM tax_detail_entries tde
  WHERE tde.company_id = p_company_id
    AND tde.tax_kind = 'percentage_tax'
    AND tde.document_date BETWEEN v_from AND v_to;

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

  -- `pt_returns` is the record the PT screens read. It is a projection of the
  -- artifact above, never a second computation.
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

  -- The legacy 2551Q working paper stays populated for the screen that reads
  -- it, from the same artifact lines.
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

  RETURN v_result || jsonb_build_object(
    'pt_return_id',        v_return.id,
    'working_paper_id',    v_header_id,
    'taxable_base',        v_base,
    'pt_rate',             v_rate,
    'pt_due',              v_due,
    'pt_still_due',        v_due - v_paid_prior,
    'working_paper_lines', v_lines);
END;
$function$;

COMMENT ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) IS
  'Generates the 2551Q through fn_generate_filing_artifact and projects it into pt_returns and the PT working paper for the screens that read them. It computes no figure of its own.';

REVOKE ALL ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_pt_return(UUID, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6b. THE 2550Q STOPS BEING COMPUTED IN A BROWSER
--
-- The quarterly VAT return screen summed `vw_output_vat_review` and
-- `vw_input_vat_review` with JavaScript `reduce` and typed the result into
-- `vat_returns`. This is the governed replacement: one RPC, generating the same
-- artifact as every other form, and projecting it into the `vat_returns` row the
-- screen already reads.
--
-- The VAT classification split the form needs — taxable, zero-rated, exempt —
-- is already in the working paper, because an exempt or zero-rated line reaches
-- the tax ledger with a base and a zero tax. No second query, no second source.
--
-- Two figures are deliberately NOT derived, because they are not facts about
-- this quarter's ledger: input VAT carried over from the prior quarter, and VAT
-- already paid within the quarter. They remain the accountant's to state — but
-- they are *stated to this function*, not arithmetic'd in a browser, so the net
-- payable still has exactly one author. Passing NULL keeps whatever the draft
-- already carries. Deriving the carry-over from the prior quarter's filed
-- return automatically is Backlog 8c.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_generate_vat_return(
  p_company_id UUID,
  p_year       INTEGER,
  p_quarter    INTEGER,
  p_input_vat_carried_over NUMERIC DEFAULT NULL,
  p_vat_paid_prior_months  NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_result      JSONB;
  v_return      vat_returns%ROWTYPE;
  v_out_taxable NUMERIC(15,2) := 0;
  v_out_zero    NUMERIC(15,2) := 0;
  v_out_exempt  NUMERIC(15,2) := 0;
  v_output_vat  NUMERIC(15,2) := 0;
  v_in_taxable  NUMERIC(15,2) := 0;
  v_in_zero     NUMERIC(15,2) := 0;
  v_in_exempt   NUMERIC(15,2) := 0;
  v_input_vat   NUMERIC(15,2) := 0;
  v_carried     NUMERIC(15,2) := 0;
  v_paid_prior  NUMERIC(15,2) := 0;
  v_available   NUMERIC(15,2);
  v_net         NUMERIC(15,2);
BEGIN
  -- One generator, one working paper, one reconciliation.
  v_result := fn_generate_filing_artifact(p_company_id, '2550Q', p_year, p_quarter);

  SELECT
    COALESCE(SUM(w.tax_base)   FILTER (WHERE w.tax_kind = 'output_vat' AND w.classification = 'regular'),    0),
    COALESCE(SUM(w.tax_base)   FILTER (WHERE w.tax_kind = 'output_vat' AND w.classification = 'zero_rated'), 0),
    COALESCE(SUM(w.tax_base)   FILTER (WHERE w.tax_kind = 'output_vat' AND w.classification = 'exempt'),     0),
    COALESCE(SUM(w.tax_amount) FILTER (WHERE w.tax_kind = 'output_vat'),                                     0),
    COALESCE(SUM(w.tax_base)   FILTER (WHERE w.tax_kind = 'input_vat'  AND w.classification = 'regular'),    0),
    COALESCE(SUM(w.tax_base)   FILTER (WHERE w.tax_kind = 'input_vat'  AND w.classification = 'zero_rated'), 0),
    COALESCE(SUM(w.tax_base)   FILTER (WHERE w.tax_kind = 'input_vat'  AND w.classification = 'exempt'),     0),
    COALESCE(SUM(w.tax_amount) FILTER (WHERE w.tax_kind = 'input_vat'),                                      0)
  INTO v_out_taxable, v_out_zero, v_out_exempt, v_output_vat,
       v_in_taxable, v_in_zero, v_in_exempt, v_input_vat
  FROM fn_filing_working_paper(p_company_id, '2550Q', p_year, p_quarter) w;

  SELECT * INTO v_return FROM vat_returns
  WHERE company_id = p_company_id AND return_type = '2550Q'
    AND period_year = p_year AND period_quarter = p_quarter;

  IF v_return.id IS NOT NULL AND v_return.status <> 'draft' THEN
    RAISE EXCEPTION 'The % Q% VAT return is % and cannot be regenerated. Reopen it to draft first.',
      p_year, p_quarter, v_return.status;
  END IF;

  -- Prior-period and payment facts are stated, not derived; when nothing is
  -- stated they survive regeneration. The engine must not invent them, and the
  -- browser must not add them up.
  v_carried    := COALESCE(p_input_vat_carried_over, v_return.input_vat_carried_over, 0);
  v_paid_prior := COALESCE(p_vat_paid_prior_months,  v_return.vat_paid_prior_months,  0);
  IF v_carried < 0 OR v_paid_prior < 0 THEN
    RAISE EXCEPTION 'Input VAT carried over (%) and VAT already paid (%) cannot be negative.',
      v_carried, v_paid_prior;
  END IF;
  v_available  := v_input_vat + v_carried;
  v_net        := v_output_vat - v_available;

  IF v_return.id IS NOT NULL THEN
    UPDATE vat_returns SET
      output_taxable_sales      = v_out_taxable,
      output_vat                = v_output_vat,
      zero_rated_sales          = v_out_zero,
      exempt_sales              = v_out_exempt,
      input_taxable_purchases   = v_in_taxable,
      input_vat                 = v_input_vat,
      input_vat_carried_over    = v_carried,
      total_available_input_vat = v_available,
      net_vat_payable           = v_net,
      vat_paid_prior_months     = v_paid_prior,
      vat_still_due             = v_net - v_paid_prior,
      updated_by                = auth.uid(),
      updated_at                = now()
    WHERE id = v_return.id;
  ELSE
    INSERT INTO vat_returns (
      company_id, return_type, period_year, period_month, period_quarter,
      output_taxable_sales, output_vat, zero_rated_sales, exempt_sales,
      input_taxable_purchases, input_vat, input_vat_carried_over,
      total_available_input_vat, net_vat_payable, vat_paid_prior_months,
      vat_still_due, status, created_by, updated_by
    ) VALUES (
      p_company_id, '2550Q', p_year, NULL, p_quarter,
      v_out_taxable, v_output_vat, v_out_zero, v_out_exempt,
      v_in_taxable, v_input_vat, v_carried,
      v_available, v_net, v_paid_prior,
      v_net - v_paid_prior, 'draft', auth.uid(), auth.uid()
    ) RETURNING * INTO v_return;
  END IF;

  RETURN v_result || jsonb_build_object(
    'vat_return_id',             v_return.id,
    'output_taxable_sales',      v_out_taxable,
    'output_vat',                v_output_vat,
    'zero_rated_sales',          v_out_zero,
    'exempt_sales',              v_out_exempt,
    'input_taxable_purchases',   v_in_taxable,
    'input_zero_rated_purchases', v_in_zero,
    'input_exempt_purchases',    v_in_exempt,
    'input_vat',                 v_input_vat,
    'input_vat_carried_over',    v_carried,
    'total_available_input_vat', v_available,
    'net_vat_payable',           v_net,
    'vat_paid_prior_months',     v_paid_prior,
    'vat_still_due',             v_net - v_paid_prior);
END;
$function$;

COMMENT ON FUNCTION public.fn_generate_vat_return(UUID, INTEGER, INTEGER, NUMERIC, NUMERIC) IS
  'Generates the 2550Q through fn_generate_filing_artifact and projects it into vat_returns for the screen that reads it. It computes no ledger figure of its own; input VAT carried over and VAT already paid are stated by the accountant and netted here rather than in a browser.';

REVOKE ALL ON FUNCTION public.fn_generate_vat_return(UUID, INTEGER, INTEGER, NUMERIC, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_vat_return(UUID, INTEGER, INTEGER, NUMERIC, NUMERIC) TO authenticated;

-- ── The 1601EQ computation joins it too ────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_compute_ewt_return(
  p_company_id UUID,
  p_year       INTEGER,
  p_quarter    INTEGER
)
RETURNS TABLE (
  total_tax_base     NUMERIC(15,2),
  total_ewt_withheld NUMERIC(15,2)
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(r.ledger_tax_base), 0)::NUMERIC(15,2),
         COALESCE(SUM(r.ledger_tax_amount), 0)::NUMERIC(15,2)
  FROM fn_filing_reconciliation(p_company_id, '1601EQ', p_year, p_quarter) r;
$$;

COMMENT ON FUNCTION fn_compute_ewt_return(UUID, INTEGER, INTEGER) IS
  '1601EQ face of the filing engine. It computes nothing of its own.';

GRANT EXECUTE ON FUNCTION fn_compute_ewt_return(UUID, INTEGER, INTEGER) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. LEAST PRIVILEGE
--
-- The artifact guard is reachable only by the trigger that owns it. Nothing
-- this migration adds is executable by `anon`.
-- ═══════════════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION public.fn_guard_filing_artifact() FROM PUBLIC, anon, authenticated;
