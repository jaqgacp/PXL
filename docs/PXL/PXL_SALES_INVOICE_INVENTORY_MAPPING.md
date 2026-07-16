# PXL Sales Invoice Inventory Mapping

Status: Completeness Audit v1
Last updated: 2026-07-15
Canonical matrix: `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`

## Purpose

This file documents how Sales Invoice inventory-impacting lines flow to inventory movement, COGS, Inventory, financial summary, and GL Impact presentation.

## Applicability

| Line type | Inventory movement | COGS / Inventory GL impact | Financial inventory/cost summary |
| --- | --- | --- | --- |
| Inventory Item | Yes, when posted | Yes, when authoritative cost is greater than zero | Yes |
| Service Item | No | No | No |
| Non-Inventory Item | No by default | Only if an approved future non-inventory cost policy exists | Only if supported by policy |
| Mixed invoice | Inventory lines only | Inventory lines only | Yes, limited to inventory-impacting lines |
| Zero-cost inventory item | Movement may post with zero cost; no COGS/Inventory amount when cost is zero | Disclosed as zero/unavailable cost; policy may warn or block | Yes, with zero cost disclosure |

## Source Flow

| Inventory fact | Source |
| --- | --- |
| Warehouse | Sales Invoice line warehouse; header warehouse inherited only by inventory item lines |
| Item | Sales Invoice line item |
| Quantity issued | Sales Invoice line quantity |
| Inventory account | Sales Invoice line snapshot from Item Master |
| COGS account | Sales Invoice line snapshot from Item Master |
| Unit cost | Posting engine valuation result |
| Total cost | Posting engine valuation result |
| Valuation method | Item costing method |
| Inventory movement | `inventory_transactions` with `reference_doc_type = 'SI'` |
| Void restoration | `inventory_transactions` with `reference_doc_type = 'SI_VOID'` |

## Presentation

Sales Invoice GL Impact displays inventory-related accounting in the Inventory / Cost Accounting Impact section. The section uses the same authoritative accounting-impact payload as the commercial section and must not create a second journal.

The inventory section shows available item, warehouse, quantity, unit cost, total cost, valuation method, posting status, inventory movement, and journal entry references. Missing source values are shown as blockers or warnings; values are not invented.

## Reconciliation

Inventory / Cost Accounting Impact must reconcile to:

- Debit COGS lines,
- Credit Inventory lines,
- Sales Invoice line `inventory_cost`,
- linked `inventory_transactions`,
- stock balance movement,
- the combined Sales Invoice journal entry.
