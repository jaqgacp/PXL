# PXL Sales Invoice Tax Mapping

Status: Completeness Audit v1
Last updated: 2026-07-15
Canonical matrix: `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`

This file summarizes tax behavior. The field-level source, BIR/reporting use, and validation gate is controlled by `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`.

## 1. VAT Mapping

| Tax fact | Current source | Status |
| --- | --- | --- |
| VAT code | `sales_invoice_lines.vat_code_id` | Implemented |
| VAT classification | `vat_codes.vat_classification` / customer tax context | Implemented |
| VAT rate | `vat_codes.rate` resolved by document save/posting path | Implemented |
| VAT base | Server recomputed line net amount | Implemented |
| VAT amount | Server recomputed line VAT amount | Implemented |
| VAT ledger row | `tax_detail_entries` on posting | Implemented |
| Customer TIN | Sales Invoice customer TIN snapshot, displayed as `XXX-XXX-XXX-XXXXX` | Implemented |
| Branch | Sales Invoice branch | Implemented |
| Document type/number/date | Sales Invoice header | Implemented |

## 2. Expected CWT Mapping

Expected CWT on Sales Invoice is informational.

| Tax fact | Current source | Status |
| --- | --- | --- |
| Expected CWT amount | `sales_invoices.cwt_amount_expected` | Implemented |
| Expected CWT base | `sales_invoices.cwt_tax_base` | Implemented |
| Expected CWT ATC | `sales_invoices.cwt_atc_code_id` | Implemented |
| Actual CWT recognition | Receipt/application/certificate workflow | Implemented outside SI posting |
| CWT receivable GL posting at SI stage | Not posted by SI | Not implemented by policy |

Do not mix expected CWT into authoritative VAT ledger rows. Actual CWT belongs to the governed receipt/application/certificate process.

## 3. VAT Price Basis

The create/edit workspace supports:

- VAT Exclusive
- VAT Inclusive

VAT Price Basis is persisted on `sales_invoices.vat_price_basis`. The save RPC treats entered unit price less discount as the commercial price. For VAT Inclusive regular VAT lines, the server derives net amount by dividing the commercial amount by `1 + VAT rate`, records VAT as the difference, and preserves the entered gross commercial amount as the line total. For VAT Exclusive lines, the server computes VAT on top of net amount.

This behavior is covered by `supabase/tests/054_sales_invoice_completeness_test.sql` and remains the reusable policy for future sales/purchase transactions that adopt VAT Price Basis.

## 4. BIR Readiness

Sales Invoice tax data must remain consumable by:

- VAT sales reports,
- SLS/SLSP,
- VAT 2550Q/2550M equivalents where supported,
- SAWT where actual CWT certificates/receipt evidence exists,
- CAS export source tracing,
- customer ledger and AR aging.

Future BIR modules must use the system-wide TIN standard automatically and must not parse display strings as tax identity source data.

## 5. Validation Requirements

Every Sales Invoice tax implementation change must validate:

- VAT code effective date,
- company VAT registration compatibility,
- customer VAT classification,
- VAT base,
- VAT amount,
- VAT Price Basis exclusive/inclusive behavior,
- customer TIN and branch code,
- output VAT GL account,
- tax-detail row creation on posting,
- reversal/cancellation tax behavior,
- expected versus actual CWT separation.
