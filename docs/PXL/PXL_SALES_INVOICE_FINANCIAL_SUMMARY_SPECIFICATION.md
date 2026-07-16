# PXL Sales Invoice Financial Summary Specification

Status: Completeness Audit v1
Last updated: 2026-07-15
Authoritative field matrix: `PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`

## Purpose

The Sales Invoice Financial tab explains the invoice economics without duplicating the GL Impact tab. It must use the same authoritative accounting-impact payload as GL Impact so commercial, inventory, cost, and reconciliation values do not drift.

## Standard Structure

### Commercial Summary

Include the customer obligation and revenue-side measures:

- Gross Line Amount
- Line Discounts
- Net Sales
- VATable Sales
- Zero-Rated Sales
- VAT-Exempt Sales
- Output VAT
- Invoice Total
- Expected CWT, informational only
- Expected Net Collectible
- Amount Collected
- Balance Due

Expected CWT does not reduce invoice revenue or become an authoritative Sales Invoice journal line unless an approved policy changes the recognition event.

### Inventory and Cost Summary

Display this section only when the invoice contains inventory-impacting lines.

- Inventory Items Count
- Quantity Issued
- Inventory Cost
- Cost of Goods Sold
- Inventory Reduction
- Cost Adjustment, when supported
- Inventory Variance, when supported
- Gross Profit
- Gross Margin Percentage

Gross Profit = Net Sales minus authoritative COGS.
Gross Margin Percentage = Gross Profit divided by Net Sales.
When Net Sales is zero, display Not Applicable.

### Accounting Reconciliation

Use the same accounting-impact payload consumed by GL Impact.

- Commercial GL Debits
- Commercial GL Credits
- Inventory GL Debits
- Inventory GL Credits
- Combined Debits
- Combined Credits
- Difference
- Balanced Status

The combined totals are the control total. Section subtotals are presentation aids and must not create separate or conflicting journals.

## Data Authority

Draft and saved unposted invoices use server-side preview data where available. Unsaved draft previews may show local estimates, but they must be labeled as draft preview.

Posted invoices use immutable posted journal, tax, inventory, and collection records. Posted values must not be recomputed from current master data.

## Empty States

For service-only invoices, omit the Inventory and Cost Summary or show: `No inventory or cost-of-goods-sold impact applies to this invoice.`

If accounting impact cannot be loaded, show the actual reason and keep the tab from implying that the invoice has no impact.

## Validation Requirements

The Financial tab must reconcile with:

- GL Impact commercial section,
- GL Impact inventory/cost section,
- posted journal entry totals,
- Sales Invoice line totals,
- posted inventory movement evidence, when applicable,
- payment and credit applications for collected and balance due amounts.

Any mismatch is a validation blocker before the Sales Invoice reference implementation can be marked fully approved.
