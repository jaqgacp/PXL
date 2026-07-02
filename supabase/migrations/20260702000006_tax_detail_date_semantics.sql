-- ══════════════════════════════════════════════════════════════════════════════
-- Tax detail date semantics (PXL-AUD-025)
--
-- Consumer audit (2026-07-02) found zero readers of
-- tax_detail_entries.posting_date: every period filter — vw_ewt_summary_ap
-- (exposes document_date AS invoice_date), fn_generate_form_2307_issued,
-- fn_vat_gl_reconciliation, and all compliance pages — uses document_date or
-- tax_period_id. The column name is nonetheless a trap: posting_date holds
-- the system date at posting time, not the accounting period. Document the
-- semantics in the schema so future consumers cannot pick it by mistake.
-- ══════════════════════════════════════════════════════════════════════════════

COMMENT ON COLUMN tax_detail_entries.posting_date IS
  'System date when this tax ledger row was written (NOW() at posting time). '
  'NOT the accounting date — never use for period filtering or tax reports. '
  'Use document_date or tax_period_id instead. See PXL-AUD-025.';

COMMENT ON COLUMN tax_detail_entries.document_date IS
  'Accounting date of the source document, aligned with journal_entries.je_date. '
  'Use this (or tax_period_id) for all period filtering, tax reports, and '
  'GL reconciliation.';
