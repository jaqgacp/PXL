# PXL Sales Invoice GL Mapping

Status: Completeness Audit v1
Last updated: 2026-07-15
Canonical matrix: `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`

This file summarizes GL behavior. The field-level source, appearance, and validation gate is controlled by `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`.

## Current GL Mapping

| Business event | Debit account | Credit account | Source amount | Current status |
| --- | --- | --- | --- | --- |
| Customer receivable | Accounts Receivable control |  | Invoice total | Implemented |
| Sales revenue |  | Line revenue account | Net line amount | Implemented |
| Output VAT |  | VAT payable account | VAT amount | Implemented |
| Inventory item cost recognition | COGS account | Inventory account | Authoritative inventory cost | Implemented for inventory item lines |

## Current Account Sources

| Account | Business label | Technical source |
| --- | --- | --- |
| Accounts Receivable | Default Accounts Receivable Account | `company_accounting_config.ar_account_id` |
| VAT Payable | Default VAT Payable Account | `company_accounting_config.vat_payable_account_id` |
| Revenue | Revenue Account from Item / document line | `sales_invoice_lines.revenue_account_id` |
| Inventory | Inventory Account from Item / line snapshot | `sales_invoice_lines.inventory_account_id`, defaulted from `items.inventory_account_id` |
| COGS | COGS Account from Item / line snapshot | `sales_invoice_lines.cogs_account_id`, defaulted from `items.cogs_account_id` |

Technical source identifiers are row-detail/System metadata only. The default accountant view must use business labels.

## Current Dimension Sources

| Journal dimension | Source |
| --- | --- |
| Branch | Sales Invoice branch |
| Department | Sales Invoice line department, falling back to header department |
| Cost Center | Sales Invoice line cost center, falling back to header cost center |

## Inventory/COGS Mapping

| Business event | Debit account | Credit account | Required source |
| --- | --- | --- | --- |
| Inventory item cost recognition | COGS account | Inventory account | Item/line accounts plus authoritative inventory valuation |
| Zero-cost inventory sale | No COGS/Inventory entry when authoritative cost is zero | No COGS/Inventory entry when authoritative cost is zero | Approved zero-cost policy; current behavior records zero cost on the SI line |
| Void restoration | Reversal journal plus inventory restoration transaction | Original journal reversed | `fn_void_sales_invoice` and `inventory_transactions` with `SI_VOID` |
| Inventory reversal/return future | Inventory account | COGS account | Credit memo/return valuation reversal policy |

Do not use item standard cost as a posted COGS amount unless the approved costing method says standard cost is authoritative for the item/company. The current Sales Invoice posting uses the inventory valuation source (`stock_balances.wac_unit_cost` for weighted average or cost-layer consumption for non-WAC methods) rather than client-side UI calculations.

## Reconciliation Requirements

Sales Invoice GL Impact must reconcile to:

- invoice total,
- revenue net amount,
- output VAT,
- posted journal entry totals,
- AR subledger,
- VAT ledger,
- inventory subledger for inventory-item invoices.

Any future change to `fn_post_sales_invoice` must update this mapping, the transaction matrix, and pgTAP tests.

## Separated Commercial and Inventory Accounting Impact

Sales Invoice GL Impact must be presented in two visual sections while remaining one balanced accounting event unless a future approved architecture explicitly posts linked journals.

| Section | Included lines | Authoritative source |
| --- | --- | --- |
| Commercial / Revenue Accounting Impact | Accounts Receivable, Sales Revenue, Service Revenue, Output VAT, discounts, rounding, deferred revenue when supported | `fn_preview_gl_impact('SI', ...)`, posted `journal_entry_lines` |
| Inventory / Cost Accounting Impact | COGS, Inventory, inventory variance/clearing when supported | `fn_preview_gl_impact('SI', ...)`, posted `journal_entry_lines`, `inventory_transactions` |
| Expected Withholding - Informational | Expected CWT estimate, ATC, base, expected net collectible | SI expected CWT fields; not an authoritative SI journal line |

The response for Sales Invoice accounting impact classifies each line with `impact_group`, `accounting_effect`, `source_type`, and available source metadata such as item, warehouse, quantity, unit cost, total cost, valuation method, journal entry, and inventory movement. The UI must not classify lines by hardcoded account numbers.

Commercial and inventory section subtotals may balance independently, but the final control is the combined journal reconciliation: total debit, total credit, difference, and balanced status. No line may be duplicated between the sections.
