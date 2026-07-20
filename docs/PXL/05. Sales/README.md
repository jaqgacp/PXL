# PXL Sales Documentation Index

**Status:** Active domain index
**Authority:** Tier 2 Navigation; Sales Invoice specifications retain authority in their own files
**Last Reviewed:** 2026-07-18
**Applies To:** Sales transactions, receivables, sales tax review, sales registers, and Sales Invoice implementation specifications
**Read When:** A task changes Sales or Sales Invoice behavior
**Do Not Read For:** Universal transaction UI architecture; use `../12. UI and UX/README.md`

## Sales Invoice Authorities

Sales Invoice is an implementation of the transaction framework, not a universal UI standard. `PXL-AUD-053` remains the active completeness gate.

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
