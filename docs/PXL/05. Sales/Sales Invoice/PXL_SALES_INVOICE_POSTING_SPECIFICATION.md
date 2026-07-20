# PXL Sales Invoice Posting Specification

Status: Completeness Audit v1
Last updated: 2026-07-15
Canonical matrix: `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`

Posting fields, preview fields, and authoritative ledger fields must match the Field Source Matrix before Sales Invoice can be marked validated.

## 1. Current Posting Engine Behavior

`fn_post_sales_invoice(p_invoice_id)` is the authoritative Sales Invoice posting function.

Current validations before posting include:

- source document lock/idempotence,
- approved status requirement,
- accounting readiness,
- VAT registration readiness,
- invoice total validation,
- open fiscal period requirement,
- AR control account configuration,
- VAT payable account configuration when output VAT exists.
- active company-owned Department, Cost Center, Warehouse, Employee, Inventory Account, and COGS Account references when provided,
- sufficient stock for inventory item lines.

## 2. Current Journal Entry

| Line | Account source | Debit | Credit | Dimension source |
| --- | --- | --- | --- | --- |
| AR | Company posting configuration AR account | Invoice total |  | Invoice branch |
| Revenue | Sales invoice line revenue account |  | Net line amount by revenue account/description/dimensions | Invoice branch, line/header Department and Cost Center |
| Output VAT | Company posting configuration VAT payable account |  | Invoice VAT amount | Invoice branch, header Department and Cost Center |
| COGS | Sales invoice line COGS account | Authoritative inventory cost |  | Invoice branch, line/header Department and Cost Center |
| Inventory | Sales invoice line Inventory account |  | Authoritative inventory cost | Invoice branch, line/header Department and Cost Center |

The posted journal entry is finalized and linked through `sales_invoices.journal_entry_id`.

## 3. Current Tax Detail

For VAT-registered companies, posting writes output VAT tax detail rows grouped by VAT code:

- source document type `SI`,
- source document ID,
- branch,
- VAT code,
- tax base,
- tax amount,
- tax period,
- customer ID,
- customer TIN snapshot,
- customer name snapshot.

Expected CWT is not posted as CWT receivable at invoice stage.

## 4. Inventory and COGS Policy

For inventory item lines, current Sales Invoice posting:

1. requires a source-backed warehouse,
2. requires active postable Inventory and COGS accounts from the line/item source,
3. validates stock availability,
4. consumes authoritative inventory cost from `stock_balances.wac_unit_cost` for weighted-average items or cost-layer consumption for non-WAC methods,
5. posts Debit COGS and Credit Inventory when authoritative cost is greater than zero,
6. writes an immutable `inventory_transactions` issue row with `reference_doc_type = 'SI'`,
7. stores `unit_cost`, `inventory_cost`, and `inventory_transaction_id` on the SI line as posting-generated evidence,
8. restores stock and writes `SI_VOID` inventory evidence when the posted invoice is voided.

Service and non-inventory lines do not create inventory movements or COGS/Inventory journal lines. Header default warehouse is inherited only by inventory item lines.

Sales Invoice line business fields remain locked after draft. The posting RPC uses a narrow internal context flag only to write posting-generated inventory evidence fields; it does not reopen quantity, price, tax, revenue account, dimension, or descriptive line fields.

## 5. Future Posting Requirements

Future inventory-enabled Sales Invoice posting must support:

| Scenario | Required accounting behavior |
| --- | --- |
| Inventory item with cost | DR COGS, CR Inventory using authoritative valuation |
| Inventory item with zero cost | No COGS/Inventory amount is posted; line cost evidence remains zero unless policy later requires a blocker |
| Service item | No inventory or COGS entry |
| Non-inventory item | No stock movement; COGS only if an approved non-inventory cost policy exists |
| Expense item sold | Requires explicit accounting policy before use on Sales Invoice |
| Sales return / credit | Use Credit Memo/return policy; do not mutate posted SI |
| Rounding | Use configured rounding account and documented materiality threshold |
| Deferred revenue future | Use explicit deferred revenue rules and recognition schedule |

## 6. Posting Integrity Rules

- Posted values are authoritative server results.
- Posted values must not be recalculated client-side.
- GL Impact view must display posted journal lines when available.
- Preview GL Impact must be clearly labeled as preview.
- Sales Invoice GL Impact is visually separated into Commercial / Revenue Accounting Impact and Inventory / Cost Accounting Impact, but both sections remain one posting result from `fn_preview_gl_impact('SI', ...)` or the posted journal.
- Expected CWT remains informational in the Sales Invoice workspace and is not inserted into the authoritative SI journal unless an approved accounting policy changes recognition timing.
- Technical rule identifiers may appear only in row detail/System/Audit surfaces.
- Posting changes require pgTAP coverage and transaction-matrix update.

## 7. Validation

`supabase/tests/054_sales_invoice_completeness_test.sql` validates VAT-inclusive save, supported dimension capture, commercial versus inventory GL impact classification, inventory-item COGS/Inventory posting, stock reduction, tax ledger output, service-line non-inventory behavior, and void stock restoration.
