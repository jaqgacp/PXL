# PXL Accounting Core Index

**Status:** Active domain index
**Authority:** Tier 2 Navigation; accounting rules retain authority in their own files
**Last Reviewed:** 2026-07-18
**Applies To:** Accounting rules, posting matrix, accounting readiness, accounting tests, ledgers, period controls, and accounting setup
**Read When:** A task changes posting, reversal, reconciliation, accounting readiness, or accounting tests
**Do Not Read For:** Tax-form layout or transaction UI layout

## Current Authorities

| Need | Read |
| --- | --- |
| Concise standing accounting rules | `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES.md` |
| Canonical debit/credit, posting, reversal, tax, report, lock, and test rules | `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md` |
| Current accounting-core readiness gate | `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_CORE_READINESS.md` |
| Regression scenarios and Supabase test coverage map | `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md` |
| Fiscal years, COA, GL posting config, opening balances, currency, exchange rates | `Setup/` |
| Journal, ledger, schedule, and period-management page blueprints | `Module Blueprints/` |

When accounting rules, transaction behavior, or tests change, keep `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md`, `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md`, `../04. Transaction Framework/PXL_TRANSACTION_MATRIX.md`, and the central findings register synchronized.
