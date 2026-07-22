# PXL Sales Documentation Index

**Status:** Active domain index
**Authority:** Tier 2 Navigation; Sales Invoice specifications retain authority in their own files
**Last Reviewed:** 2026-07-22
**Applies To:** Sales transactions, receivables, sales tax review, sales registers, and Sales Invoice implementation specifications
**Read When:** A task changes Sales or Sales Invoice behavior
**Do Not Read For:** Universal transaction UI architecture; use `../12. UI and UX/README.md`

## Sales Invoice Authorities

Sales Invoice is an implementation of the transaction framework, not a universal UI standard. `PXL-AUD-053` is `Retested Passed`; the authoritative field-source matrix is `END_TO_END_VALIDATED` for the supported Sales Invoice scope.

The certified path covers create/edit, server validation, posting, AR/revenue/output VAT/COGS/inventory, expected-CWT timing, void/reversal, Credit Memo and Receipt relationships, Customer Ledger, AR Aging, GL, VAT, Trial Balance, Financial Statements through posted GL, the Sales Invoice register, search, API/view sources, exports, and audit evidence. Project, Location, and Functional Entity are supported at header and line-override level and propagate through preview, posting, inventory where applicable, reporting, API/export sources, audit, and reversal.

Explicit exclusions remain unsupported rather than partially implied: foreign-currency SI (the server accepts PHP only), Delivery Receipt conversion, price levels/default discount policies, deferred revenue, a distinct cancel/revision/posting-version model, SI integration/import metadata, attachments, and categorized internal notes. Live customer/item/workflow presentation enrichments remain classified partial in the field-source matrix and are not consumed as posting or reporting truth.

Certification evidence: focused test 054 passes 42/42; Sales Invoice draft-state tests pass 4/4; the full 74-file database suite passes 1,588 assertions; canonical tests 055/057/058 pass 88/88; documentation, lint, build/secret guard, and diff validation pass.

| Need | Read |
| --- | --- |
| Transaction identity, lifecycle, panels, tabs, and non-definitions | `Sales Invoice/PXL_SALES_INVOICE_TRANSACTION_DEFINITION.md` |
| Source-backed functional behavior and remaining completeness gaps | `Sales Invoice/PXL_SALES_INVOICE_FUNCTIONAL_SPECIFICATION.md` |
| Field mapping summary; the detailed authority is the field-source matrix | `Sales Invoice/PXL_SALES_INVOICE_FIELD_MAPPING.md` |
| Dimension capture, inheritance, and posting propagation | `Sales Invoice/PXL_SALES_INVOICE_DIMENSION_MAPPING.md` |
| Save/post/void behavior and posting integrity | `Sales Invoice/PXL_SALES_INVOICE_POSTING_SPECIFICATION.md` |
| Debit/credit and GL Impact behavior | `Sales Invoice/PXL_SALES_INVOICE_GL_MAPPING.md` |
| VAT, expected CWT, and VAT Price Basis behavior | `Sales Invoice/PXL_SALES_INVOICE_TAX_MAPPING.md` |
| Inventory movement, COGS, inventory account, and void restoration behavior | `Sales Invoice/PXL_SALES_INVOICE_INVENTORY_MAPPING.md` |
| Financial tab source and reconciliation contract | `Sales Invoice/PXL_SALES_INVOICE_FINANCIAL_SUMMARY_SPECIFICATION.md` |

## Other Sales Blueprints

`Module Blueprints/` contains retained planned/current module blueprints for quotations, sales orders, delivery receipts, cash sales, receipts, credit/debit memos, customer returns, receivables, tax review, and registers. Read only the exact blueprint named by the task, then verify against implementation evidence.

Historical Sales Invoice blueprints were moved to `../archive/superseded-sales-invoice-blueprints/` because the current source-backed specifications above now define the active Sales Invoice behavior.
