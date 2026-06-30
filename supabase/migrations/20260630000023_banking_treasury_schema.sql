-- ══════════════════════════════════════════════════════════════════════════════
-- Migration 023: Banking & Treasury — Schema
-- Bank accounts, petty cash (funds/vouchers/replenishments/count sheets),
-- fund transfers, inter-branch transfers, bank adjustments, check vouchers,
-- bank reconciliation. Full RLS (is_company_member), indexes, constraints.
-- ══════════════════════════════════════════════════════════════════════════════

-- New document type codes for number series (CV/PCV/PCF already seeded in S1)
INSERT INTO ref_document_types (category, document_code, document_name, is_bir_registered, sort_order) VALUES
  ('accounting','PCR','Petty Cash Replenishment',false,25),
  ('accounting','CCS','Cash Count Sheet',false,26),
  ('accounting','FT','Fund Transfer',false,27),
  ('accounting','IBT','Inter-Branch Transfer',false,28),
  ('accounting','BADJ','Bank Adjustment',false,29)
ON CONFLICT (document_code) DO NOTHING;

-- Allow banking document types as journal entry reference sources
ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entries_reference_doc_type_check;
ALTER TABLE journal_entries
  ADD CONSTRAINT journal_entries_reference_doc_type_check
    CHECK (reference_doc_type IN (
      'SI','OR','CM','DM','MANUAL','VB','PV','CP','VC','REV',
      'FT','IBT','BADJ','PCV','PCR','CV'
    ));

-- ── bank_accounts ─────────────────────────────────────────────────────────────
CREATE TABLE bank_accounts (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID          NOT NULL REFERENCES companies(id),
  branch_id       UUID          REFERENCES branches(id),
  bank_name       TEXT          NOT NULL,
  bank_branch     TEXT,
  account_number  TEXT          NOT NULL,
  account_name    TEXT          NOT NULL,
  account_type    TEXT          NOT NULL DEFAULT 'checking'
                                CHECK (account_type IN ('checking','savings','time_deposit','money_market')),
  currency_id     UUID          REFERENCES currencies(id),
  gl_account_id   UUID          NOT NULL REFERENCES chart_of_accounts(id),
  is_primary      BOOLEAN       NOT NULL DEFAULT false,
  is_active       BOOLEAN       NOT NULL DEFAULT true,
  opening_balance NUMERIC(15,2) NOT NULL DEFAULT 0,
  notes           TEXT,
  created_by      UUID,
  updated_by      UUID,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, bank_name, account_number)
);
CREATE INDEX idx_bank_accounts_company ON bank_accounts (company_id);
CREATE INDEX idx_bank_accounts_active  ON bank_accounts (company_id, is_active);

-- ── petty_cash_funds ──────────────────────────────────────────────────────────
CREATE TABLE petty_cash_funds (
  id                       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id               UUID          NOT NULL REFERENCES companies(id),
  branch_id                UUID          REFERENCES branches(id),
  fund_name                TEXT          NOT NULL,
  custodian_name           TEXT          NOT NULL,
  authorized_amount        NUMERIC(15,2) NOT NULL,
  replenishment_threshold  NUMERIC(15,2),
  gl_account_id            UUID          NOT NULL REFERENCES chart_of_accounts(id),
  is_active                BOOLEAN       NOT NULL DEFAULT true,
  created_by               UUID,
  updated_by               UUID,
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, fund_name)
);
CREATE INDEX idx_pcf_company ON petty_cash_funds (company_id);

-- ── petty_cash_replenishments (defined before vouchers; vouchers FK here) ──────
CREATE TABLE petty_cash_replenishments (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID          NOT NULL REFERENCES companies(id),
  branch_id         UUID          REFERENCES branches(id),
  fund_id           UUID          NOT NULL REFERENCES petty_cash_funds(id),
  pcr_number        TEXT          NOT NULL,
  replenishment_date DATE         NOT NULL,
  bank_account_id   UUID          REFERENCES bank_accounts(id),
  check_number      TEXT,
  total_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  remarks           TEXT,
  status            TEXT          NOT NULL DEFAULT 'draft'
                                  CHECK (status IN ('draft','posted','cancelled')),
  fiscal_period_id  UUID          REFERENCES fiscal_periods(id),
  journal_entry_id  UUID          REFERENCES journal_entries(id),
  posted_at         TIMESTAMPTZ,
  posted_by         UUID,
  created_by        UUID,
  updated_by        UUID,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, pcr_number)
);
CREATE INDEX idx_pcr_company ON petty_cash_replenishments (company_id);
CREATE INDEX idx_pcr_status  ON petty_cash_replenishments (company_id, status);
CREATE INDEX idx_pcr_fund    ON petty_cash_replenishments (fund_id);

-- ── petty_cash_vouchers ───────────────────────────────────────────────────────
CREATE TABLE petty_cash_vouchers (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID          NOT NULL REFERENCES companies(id),
  branch_id          UUID          REFERENCES branches(id),
  fund_id            UUID          NOT NULL REFERENCES petty_cash_funds(id),
  pcv_number         TEXT          NOT NULL,
  voucher_date       DATE          NOT NULL,
  payee              TEXT          NOT NULL,
  purpose            TEXT          NOT NULL,
  expense_account_id UUID          NOT NULL REFERENCES chart_of_accounts(id),
  amount             NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  receipt_number     TEXT,
  replenishment_id   UUID          REFERENCES petty_cash_replenishments(id),
  status             TEXT          NOT NULL DEFAULT 'draft'
                                   CHECK (status IN ('draft','approved','replenished','cancelled')),
  fiscal_period_id   UUID          REFERENCES fiscal_periods(id),
  journal_entry_id   UUID          REFERENCES journal_entries(id),
  posted_at          TIMESTAMPTZ,
  posted_by          UUID,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, pcv_number)
);
CREATE INDEX idx_pcv_company ON petty_cash_vouchers (company_id);
CREATE INDEX idx_pcv_status  ON petty_cash_vouchers (company_id, status);
CREATE INDEX idx_pcv_fund    ON petty_cash_vouchers (fund_id);

-- ── cash_count_sheets ─────────────────────────────────────────────────────────
CREATE TABLE cash_count_sheets (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID          NOT NULL REFERENCES companies(id),
  branch_id           UUID          REFERENCES branches(id),
  fund_id             UUID          NOT NULL REFERENCES petty_cash_funds(id),
  sheet_number        TEXT          NOT NULL,
  count_date          DATE          NOT NULL,
  counted_by          TEXT          NOT NULL,
  witnessed_by        TEXT,
  book_balance        NUMERIC(15,2) NOT NULL DEFAULT 0,
  coins_and_bills     NUMERIC(15,2) NOT NULL DEFAULT 0,
  unreplenished_pcvs  NUMERIC(15,2) NOT NULL DEFAULT 0,
  other_items         NUMERIC(15,2) NOT NULL DEFAULT 0,
  counted_amount      NUMERIC(15,2) NOT NULL DEFAULT 0,
  shortage_overage    NUMERIC(15,2) GENERATED ALWAYS AS (counted_amount - book_balance) STORED,
  remarks             TEXT,
  status              TEXT          NOT NULL DEFAULT 'draft'
                                    CHECK (status IN ('draft','finalized')),
  created_by          UUID,
  updated_by          UUID,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, sheet_number)
);
CREATE INDEX idx_ccs_company ON cash_count_sheets (company_id);
CREATE INDEX idx_ccs_fund    ON cash_count_sheets (fund_id);

-- ── fund_transfers ────────────────────────────────────────────────────────────
CREATE TABLE fund_transfers (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID          NOT NULL REFERENCES companies(id),
  branch_id        UUID          REFERENCES branches(id),
  ft_number        TEXT          NOT NULL,
  transfer_date    DATE          NOT NULL,
  from_account_id  UUID          NOT NULL REFERENCES bank_accounts(id),
  to_account_id    UUID          NOT NULL REFERENCES bank_accounts(id),
  amount           NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  reference_number TEXT,
  remarks          TEXT,
  status           TEXT          NOT NULL DEFAULT 'draft'
                                 CHECK (status IN ('draft','posted','cancelled')),
  fiscal_period_id UUID          REFERENCES fiscal_periods(id),
  journal_entry_id UUID          REFERENCES journal_entries(id),
  posted_at        TIMESTAMPTZ,
  posted_by        UUID,
  created_by       UUID,
  updated_by       UUID,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, ft_number),
  CHECK (from_account_id != to_account_id)
);
CREATE INDEX idx_ft_company ON fund_transfers (company_id);
CREATE INDEX idx_ft_status  ON fund_transfers (company_id, status);

-- ── inter_branch_transfers ────────────────────────────────────────────────────
CREATE TABLE inter_branch_transfers (
  id                     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             UUID          NOT NULL REFERENCES companies(id),
  ibt_number             TEXT          NOT NULL,
  transfer_date          DATE          NOT NULL,
  from_branch_id         UUID          NOT NULL REFERENCES branches(id),
  to_branch_id           UUID          NOT NULL REFERENCES branches(id),
  from_account_id        UUID          REFERENCES bank_accounts(id),
  to_account_id          UUID          REFERENCES bank_accounts(id),
  amount                 NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  intercompany_account_id UUID         REFERENCES chart_of_accounts(id),
  reference_number       TEXT,
  remarks                TEXT,
  status                 TEXT          NOT NULL DEFAULT 'draft'
                                       CHECK (status IN ('draft','posted','cancelled')),
  fiscal_period_id       UUID          REFERENCES fiscal_periods(id),
  journal_entry_id       UUID          REFERENCES journal_entries(id),
  posted_at              TIMESTAMPTZ,
  posted_by              UUID,
  created_by             UUID,
  updated_by             UUID,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, ibt_number),
  CHECK (from_branch_id != to_branch_id)
);
CREATE INDEX idx_ibt_company ON inter_branch_transfers (company_id);
CREATE INDEX idx_ibt_status  ON inter_branch_transfers (company_id, status);

-- ── bank_adjustments ──────────────────────────────────────────────────────────
CREATE TABLE bank_adjustments (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID          NOT NULL REFERENCES companies(id),
  branch_id        UUID          REFERENCES branches(id),
  ba_number        TEXT          NOT NULL,
  adjustment_date  DATE          NOT NULL,
  bank_account_id  UUID          NOT NULL REFERENCES bank_accounts(id),
  adjustment_type  TEXT          NOT NULL
                                 CHECK (adjustment_type IN ('bank_debit_memo','bank_credit_memo','interest_income','bank_charge','other_debit','other_credit')),
  amount           NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  gl_account_id    UUID          NOT NULL REFERENCES chart_of_accounts(id),
  reference_number TEXT,
  description      TEXT          NOT NULL,
  status           TEXT          NOT NULL DEFAULT 'draft'
                                 CHECK (status IN ('draft','posted','cancelled')),
  fiscal_period_id UUID          REFERENCES fiscal_periods(id),
  journal_entry_id UUID          REFERENCES journal_entries(id),
  posted_at        TIMESTAMPTZ,
  posted_by        UUID,
  created_by       UUID,
  updated_by       UUID,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, ba_number)
);
CREATE INDEX idx_ba_company ON bank_adjustments (company_id);
CREATE INDEX idx_ba_status  ON bank_adjustments (company_id, status);
CREATE INDEX idx_ba_account ON bank_adjustments (bank_account_id);

-- ── check_vouchers ────────────────────────────────────────────────────────────
CREATE TABLE check_vouchers (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID          NOT NULL REFERENCES companies(id),
  branch_id          UUID          REFERENCES branches(id),
  cv_number          TEXT          NOT NULL,
  voucher_date       DATE          NOT NULL,
  bank_account_id    UUID          NOT NULL REFERENCES bank_accounts(id),
  check_number       TEXT          NOT NULL,
  check_date         DATE          NOT NULL,
  payee              TEXT          NOT NULL,
  payee_tin          TEXT,
  total_gross_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
  total_ewt_amount   NUMERIC(15,2) NOT NULL DEFAULT 0,
  net_check_amount   NUMERIC(15,2) GENERATED ALWAYS AS (total_gross_amount - total_ewt_amount) STORED,
  atc_code_id        UUID          REFERENCES atc_codes(id),
  ewt_rate           NUMERIC(5,2),
  particulars        TEXT          NOT NULL,
  status             TEXT          NOT NULL DEFAULT 'draft'
                                   CHECK (status IN ('draft','posted','released','cleared','stale','cancelled')),
  cleared_date       DATE,
  stale_date         DATE,
  fiscal_period_id   UUID          REFERENCES fiscal_periods(id),
  journal_entry_id   UUID          REFERENCES journal_entries(id),
  posted_at          TIMESTAMPTZ,
  posted_by          UUID,
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, cv_number)
);
CREATE INDEX idx_cv_company ON check_vouchers (company_id);
CREATE INDEX idx_cv_status  ON check_vouchers (company_id, status);
CREATE INDEX idx_cv_account ON check_vouchers (bank_account_id);

-- ── check_voucher_lines ───────────────────────────────────────────────────────
CREATE TABLE check_voucher_lines (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  cv_id              UUID          NOT NULL REFERENCES check_vouchers(id) ON DELETE CASCADE,
  company_id         UUID          NOT NULL REFERENCES companies(id),
  line_number        INT           NOT NULL,
  expense_account_id UUID          NOT NULL REFERENCES chart_of_accounts(id),
  description        TEXT          NOT NULL,
  amount             NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  created_by         UUID,
  updated_by         UUID,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_cvl_cv ON check_voucher_lines (cv_id);

-- ── bank_reconciliations ──────────────────────────────────────────────────────
CREATE TABLE bank_reconciliations (
  id                      UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID          NOT NULL REFERENCES companies(id),
  branch_id               UUID          REFERENCES branches(id),
  bank_account_id         UUID          NOT NULL REFERENCES bank_accounts(id),
  recon_month             INT           NOT NULL CHECK (recon_month BETWEEN 1 AND 12),
  recon_year              INT           NOT NULL CHECK (recon_year BETWEEN 2000 AND 2099),
  reconciliation_date     DATE          NOT NULL,
  bank_statement_balance  NUMERIC(15,2) NOT NULL DEFAULT 0,
  deposits_in_transit     NUMERIC(15,2) NOT NULL DEFAULT 0,
  outstanding_checks      NUMERIC(15,2) NOT NULL DEFAULT 0,
  bank_errors             NUMERIC(15,2) NOT NULL DEFAULT 0,
  book_balance            NUMERIC(15,2) NOT NULL DEFAULT 0,
  book_adjustments_add    NUMERIC(15,2) NOT NULL DEFAULT 0,
  book_adjustments_less   NUMERIC(15,2) NOT NULL DEFAULT 0,
  book_errors             NUMERIC(15,2) NOT NULL DEFAULT 0,
  adjusted_bank_balance   NUMERIC(15,2) GENERATED ALWAYS AS (bank_statement_balance + deposits_in_transit - outstanding_checks + bank_errors) STORED,
  adjusted_book_balance   NUMERIC(15,2) GENERATED ALWAYS AS (book_balance + book_adjustments_add - book_adjustments_less + book_errors) STORED,
  difference              NUMERIC(15,2) GENERATED ALWAYS AS ((bank_statement_balance + deposits_in_transit - outstanding_checks + bank_errors) - (book_balance + book_adjustments_add - book_adjustments_less + book_errors)) STORED,
  remarks                 TEXT,
  status                  TEXT          NOT NULL DEFAULT 'draft'
                                        CHECK (status IN ('draft','finalized')),
  finalized_at            TIMESTAMPTZ,
  finalized_by            UUID,
  created_by              UUID,
  updated_by              UUID,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, bank_account_id, recon_year, recon_month)
);
CREATE INDEX idx_brec_company ON bank_reconciliations (company_id);
CREATE INDEX idx_brec_account ON bank_reconciliations (bank_account_id);

-- ── bank_recon_items ──────────────────────────────────────────────────────────
CREATE TABLE bank_recon_items (
  id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  reconciliation_id  UUID          NOT NULL REFERENCES bank_reconciliations(id) ON DELETE CASCADE,
  company_id         UUID          NOT NULL REFERENCES companies(id),
  item_type          TEXT          NOT NULL
                                   CHECK (item_type IN ('outstanding_check','deposit_in_transit','bank_adjustment','book_adjustment')),
  reference_doc_type TEXT,
  reference_doc_id   UUID,
  description        TEXT          NOT NULL,
  document_date      DATE,
  amount             NUMERIC(15,2) NOT NULL,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by         UUID
);
CREATE INDEX idx_bri_recon ON bank_recon_items (reconciliation_id);
CREATE INDEX idx_bri_type  ON bank_recon_items (item_type);

-- ── updated_at triggers ───────────────────────────────────────────────────────
CREATE TRIGGER trg_bank_accounts_updated_at             BEFORE UPDATE ON bank_accounts             FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_petty_cash_funds_updated_at          BEFORE UPDATE ON petty_cash_funds          FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_petty_cash_replenishments_updated_at BEFORE UPDATE ON petty_cash_replenishments FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_petty_cash_vouchers_updated_at       BEFORE UPDATE ON petty_cash_vouchers       FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_cash_count_sheets_updated_at         BEFORE UPDATE ON cash_count_sheets         FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_fund_transfers_updated_at            BEFORE UPDATE ON fund_transfers            FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_inter_branch_transfers_updated_at    BEFORE UPDATE ON inter_branch_transfers    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_bank_adjustments_updated_at          BEFORE UPDATE ON bank_adjustments          FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_check_vouchers_updated_at            BEFORE UPDATE ON check_vouchers            FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_bank_reconciliations_updated_at      BEFORE UPDATE ON bank_reconciliations      FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── RLS ───────────────────────────────────────────────────────────────────────
ALTER TABLE bank_accounts             ENABLE ROW LEVEL SECURITY;
ALTER TABLE petty_cash_funds          ENABLE ROW LEVEL SECURITY;
ALTER TABLE petty_cash_replenishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE petty_cash_vouchers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_count_sheets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE fund_transfers            ENABLE ROW LEVEL SECURITY;
ALTER TABLE inter_branch_transfers    ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_adjustments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE check_vouchers            ENABLE ROW LEVEL SECURITY;
ALTER TABLE check_voucher_lines       ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_reconciliations      ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_recon_items          ENABLE ROW LEVEL SECURITY;

-- Parent tables: SELECT / INSERT / UPDATE scoped to company membership
CREATE POLICY "bank_accounts_read"   ON bank_accounts   FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "bank_accounts_insert" ON bank_accounts   FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "bank_accounts_update" ON bank_accounts   FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "pcf_read"   ON petty_cash_funds FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pcf_insert" ON petty_cash_funds FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "pcf_update" ON petty_cash_funds FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "pcr_read"   ON petty_cash_replenishments FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pcr_insert" ON petty_cash_replenishments FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "pcr_update" ON petty_cash_replenishments FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "pcv_read"   ON petty_cash_vouchers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "pcv_insert" ON petty_cash_vouchers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "pcv_update" ON petty_cash_vouchers FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "ccs_read"   ON cash_count_sheets FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "ccs_insert" ON cash_count_sheets FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "ccs_update" ON cash_count_sheets FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "ft_read"   ON fund_transfers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "ft_insert" ON fund_transfers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "ft_update" ON fund_transfers FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "ibt_read"   ON inter_branch_transfers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "ibt_insert" ON inter_branch_transfers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "ibt_update" ON inter_branch_transfers FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "ba_read"   ON bank_adjustments FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "ba_insert" ON bank_adjustments FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "ba_update" ON bank_adjustments FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "cv_read"   ON check_vouchers FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cv_insert" ON check_vouchers FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "cv_update" ON check_vouchers FOR UPDATE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "brec_read"   ON bank_reconciliations FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "brec_insert" ON bank_reconciliations FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "brec_update" ON bank_reconciliations FOR UPDATE TO authenticated USING (is_company_member(company_id));

-- Cascade children: SELECT / INSERT / UPDATE / DELETE scoped to company membership
CREATE POLICY "cvl_read"   ON check_voucher_lines FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cvl_insert" ON check_voucher_lines FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "cvl_update" ON check_voucher_lines FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "cvl_delete" ON check_voucher_lines FOR DELETE TO authenticated USING (is_company_member(company_id));

CREATE POLICY "bri_read"   ON bank_recon_items FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY "bri_insert" ON bank_recon_items FOR INSERT TO authenticated WITH CHECK (is_company_member(company_id));
CREATE POLICY "bri_update" ON bank_recon_items FOR UPDATE TO authenticated USING (is_company_member(company_id));
CREATE POLICY "bri_delete" ON bank_recon_items FOR DELETE TO authenticated USING (is_company_member(company_id));

-- ── Audit triggers ────────────────────────────────────────────────────────────
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'bank_accounts','petty_cash_funds','petty_cash_replenishments','petty_cash_vouchers',
    'cash_count_sheets','fund_transfers','inter_branch_transfers','bank_adjustments',
    'check_vouchers','bank_reconciliations'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_audit_%1$s ON %1$s;
       CREATE TRIGGER trg_audit_%1$s AFTER INSERT OR UPDATE OR DELETE ON %1$s
       FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();', t);
  END LOOP;
END; $$;
