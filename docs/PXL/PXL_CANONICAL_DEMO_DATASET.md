# PXL Canonical Demo Dataset

## Purpose

The canonical demo dataset is the governed development and QA fixture for PXL. It replaces ad hoc demo rows with deterministic companies, setup data, master data, opening stock, posted transactions, and regression assertions that exercise Philippine accounting, tax, inventory, and document-lifecycle behavior.

Authoritative rules remain in:

- `PXL_ACCOUNTING_RULES_MATRIX.md`
- `PXL_TRANSACTION_MATRIX.md`
- `PXL_ACCOUNTING_TEST_BOOK.md`
- `PXL_END_TO_END_AUDIT_FINDINGS.md`

## Safety Requirements

Only run the reset against a proven non-production database.

Before reset:

1. Confirm the active Supabase project and database host.
2. Confirm the database is local, test, preview, isolated demo, or otherwise non-production.
3. Check for user-owned or production-like data.
4. Take a backup/export when practical.
5. Print the reset plan.
6. Set `pxl.allow_demo_reset = 'on'` in the same database session as the reset script.

The reset preserves migrations, schema, functions, triggers, RLS policies, roles, BIR/RDO/global tax references, currencies, payment modes, and governed reference data. It deletes only rows owned by the canonical demo companies.

## Supported Environment

Primary target: local Supabase development database.

Validated non-production target shape:

- Database host: `127.0.0.1:54322`
- Database name: `postgres`
- Database user: `postgres`
- Container: `supabase_db_PXL`
- Git branch: `main`

Do not run the reset against hosted Supabase unless the target project has been separately proven to be an isolated demo/test project.

Demo UI login after seed:

| Role | Email | Password |
| --- | --- | --- |
| Administrator | `demo.admin@pxl.local` | `PxlDemo123!` |
| Accountant | `demo.accountant@pxl.local` | `PxlDemo123!` |
| Approver | `demo.approver@pxl.local` | `PxlDemo123!` |
| Sales | `demo.sales@pxl.local` | `PxlDemo123!` |
| Warehouse | `demo.warehouse@pxl.local` | `PxlDemo123!` |

## Reset Command

Create a practical local backup first:

```bash
mkdir -p supabase/.temp/backups
docker exec supabase_db_PXL pg_dump -U postgres -d postgres --clean --if-exists --no-owner --no-privileges > supabase/.temp/backups/canonical_demo_pre_reset_$(date +%Y%m%d%H%M%S).sql
```

Run reset and seed in one `psql` session so the reset GUC is active:

```bash
(printf "SET pxl.allow_demo_reset = 'on';\nSET pxl.seed_summary = 'on';\n"; cat supabase/seeds/canonical_demo_reset.sql supabase/seeds/canonical_demo_seed.sql) | docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

## Seed Command

For a seed-only run after the database has already been reset:

```bash
(printf "SET pxl.seed_summary = 'on';\n"; cat supabase/seeds/canonical_demo_seed.sql) | docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

The seed is deterministic and uses stable business codes. It is safest to rerun after the reset script.

## Test Command

After reset and seed:

```bash
supabase test db --local supabase/tests/055_canonical_demo_dataset_test.sql
```

If the canonical seed is not loaded, this pgTAP file reports 34 skipped tests instead of failing the general suite.

## Website Audit Command

Start the application against local Supabase:

```bash
VITE_SUPABASE_URL='http://127.0.0.1:54321' VITE_SUPABASE_ANON_KEY="$(supabase status -o env | sed -n 's/^ANON_KEY=//p')" npm run dev -- --host 127.0.0.1 --port 5173
```

Run the canonical browser visibility probe:

```bash
AUDIT_BASE_URL='http://127.0.0.1:5173' NODE_PATH='/home/codespace/.npm/_npx/e41f203b7505f1fb/node_modules' node scripts/audit_canonical_ui.mjs
```

The script logs in, selects `ABC Trading Corporation`, and classifies core setup, master-data, sales, purchasing, inventory, banking, accounting, compliance, and report routes as `visible`, `partially visible`, `missing`, or `broken`.

## Company Profiles

| Code | Registered Name | Entity Type | Taxpayer Type | Purpose |
| --- | --- | --- | --- | --- |
| `DEMO-SP-NONVAT` | Golden Retail Store | Sole proprietor | Non-VAT | MSME retail, branch operations, simple inventory and cash/credit sales. |
| `DEMO-CORP-VAT` | ABC Trading Corporation | Corporation | VAT | Primary full-featured trading, accounting, tax, purchasing, and inventory QA company. |
| `DEMO-OPC-NONVAT` | Northstar Digital Solutions OPC | OPC | Non-VAT | Service-only corporate behavior, project-service style billing, non-inventory flow. |
| `DEMO-SVC-VAT` | Prime Business Advisory Inc. | Corporation | VAT | VAT service billing and withholding timing separate from inventory trading. |
| `DEMO-PARTNERSHIP-VAT` | Bayani Partners and Company | Partnership | VAT | Entity-type coverage where supported by schema. |

## Master Data Summary

Seeded totals after a clean reset:

| Area | Count |
| --- | ---: |
| Demo companies | 5 |
| Branches | 8 |
| Departments | 13 |
| Cost centers | 10 |
| Chart-of-account rows | 210 |
| Payment terms | 25 |
| UOMs | 25 |
| Items and services | 53 |
| Warehouses | 5 |
| Customers | 13 |
| Suppliers | 13 |
| Demo auth users | 5 |

Primary VAT trading company (`DEMO-CORP-VAT`) has 3 branches, 5 departments, 5 cost centers, 3 warehouses, 10 customers, 10 suppliers, 9 stock items, 6 service items, sales/purchasing approval fixtures, bank accounts, employees, and number series for core document types.

## Opening Balances

Opening date: `2026-01-02`.

`DEMO-CORP-VAT` opening GL:

| Account | Debit | Credit |
| --- | ---: | ---: |
| Cash on Hand | 50,000.00 | 0.00 |
| Cash in Bank - Operating | 500,000.00 | 0.00 |
| Inventory | 71,200.00 | 0.00 |
| Owner Capital / Share Capital | 0.00 | 621,200.00 |

Opening inventory is created through `fn_receive_inventory`, not direct quantity edits.

## Transaction Scenario Summary

Seeded posted or active scenarios include:

- `TEST-SI-STANDALONE`: VAT-exclusive service SI with expected CWT and posted OR actual CWT.
- `TEST-SI-VAT-INCLUSIVE`: VAT-inclusive service SI, 1,120 gross = 1,000 net + 120 VAT.
- `TEST-SI-INVENTORY`: inventory SI that issues stock and posts COGS/Inventory.
- `TEST-SI-NONVAT`: non-VAT sole-proprietor inventory SI.
- `TEST-SI-OPC-SERVICE`: non-VAT service OPC SI.
- `TEST-SI-SVC-VAT`: VAT service corporation SI.
- `TEST-PO-PARTIAL-RECEIPT`: approved PO for 20 units, confirmed RR for 12 units.
- `TEST-VB-PARTIAL-PAYMENT`: posted vendor bill with input VAT and source EWT.
- `TEST-PV-PARTIAL-PAYMENT`: posted partial supplier payment.
- `TEST-INV-TRANSFER-OK`: valid stock transfer within source warehouse availability.
- `TEST-INV-ADJ-POS` / `TEST-INV-ADJ-NEG`: positive and negative stock adjustments within available quantity.
- `TEST-SO-OPEN-PARTIAL`: approved open sales order fixture, 10 ordered, 6 fulfilled, 4 remaining.

Regression-only invalid scenarios in `055_canonical_demo_dataset_test.sql`:

- `TEST-INV-TRANSFER-BLOCK`: source warehouse transfer greater than available stock, blocked server-side.
- `TEST-INV-OVERSELL-BLOCK`: SI with excess warehouse quantity, blocked by approval readiness before posting.

## Expected Balances

Selected `DEMO-CORP-VAT` stock balances after seed:

| Warehouse | Item | Quantity | Value | WAC |
| --- | --- | ---: | ---: | ---: |
| `WH-MAIN` | `ITEM-STOCK-001` | 107.0000 | 21,400.00 | 200.000000 |
| `WH-MAIN` | `ITEM-STOCK-003` | 53.0000 | 2,385.00 | 45.000000 |
| `WH-CEBU` | `ITEM-STOCK-001` | 30.0000 | 6,000.00 | 200.000000 |
| `WH-CEBU` | `ITEM-STOCK-003` | 10.0000 | 450.00 | 45.000000 |

Selected tax expectations:

- `TEST-SI-STANDALONE`: output VAT base 2,000.00, VAT 240.00; expected CWT 40.00 on SI only.
- `TEST-OR-SI-STANDALONE`: actual CWT tax detail 40.00 on base 2,000.00.
- `TEST-SI-VAT-INCLUSIVE`: output VAT base 1,000.00, VAT 120.00.
- `TEST-VB-PARTIAL-PAYMENT`: input VAT base 2,400.00, VAT 288.00; EWT payable base 2,400.00, EWT 24.00.

## Known Limitations

This seed is audit-ready for the scenarios it actually executes, but it does not yet claim full coverage of every desired workflow in the long-form QA brief.

Current limitations:

- Credit memo, customer return, vendor credit, purchase return, and posted document reversal fixtures are not yet part of this canonical seed.
- Physical count, serialized inventory, inventory commitments/reservations, and inactive item/warehouse negative cases remain future seed/test expansions.
- Route-level UI visibility is not yet complete: the Phase 2 browser audit finds several seeded transaction references present in the database but missing from their application routes.
- Table coverage is not yet complete: 69 of 148 public tables are populated after seed and 79 are empty; active empty modules must be classified as future, unsupported, or pending workflow fixtures.
- Project, location, and functional-entity dimensions are not invented because governed master tables do not yet exist.
- Service-only project billing is represented by deterministic service invoices, not a full project subledger.
- Approval workflows are seeded only for supported sales and purchasing modules.
- The canonical pgTAP test focuses on database truth; `scripts/audit_canonical_ui.mjs` is the current UI walkthrough probe.

## Known Findings

`PXL-AUD-054` was discovered during canonical inventory-control validation: stock transfer posting did not validate source warehouse availability before decrementing source stock. It is fixed by `20260716000001_stock_transfer_availability_guard.sql` and covered by `055_canonical_demo_dataset_test.sql`.

`PXL-AUD-053` remains In Progress for broader Sales Invoice gold-standard validation beyond the source-backed slice already implemented.

Phase 2 product-audit findings:

- `PXL-AUD-055`: service-role credential exposed through a `VITE_` client environment variable. Remove and rotate before any external demo.
- `PXL-AUD-056`: hosted Supabase migration push is blocked until the project is proven non-production, DB credentials are supplied, and held-out migration drift is reconciled.
- `PXL-AUD-057`: canonical database rows are not consistently visible from transaction/report routes.
- `PXL-AUD-058`: local canonical login/CSP issue fixed; browser audit now authenticates locally.
- `PXL-AUD-059`: complete table coverage classification is still required.
- `PXL-AUD-060`: login labels need accessible association for reliable UI regression.
- `PXL-AUD-061`: full pgTAP regression lanes are not yet deterministic against the canonical seeded state.

## How To Rerun

1. Confirm non-production environment.
2. Back up the local database.
3. Run the reset+seed command above.
4. Run `supabase test db --local supabase/tests/055_canonical_demo_dataset_test.sql`.
5. Run `git diff --check`, `npm run lint`, `npm run build`, and `scripts/check_docs_consistency.sh`.

## How To Extend

Use stable codes and deterministic dates. Add new scenarios to:

- `supabase/seeds/canonical_demo_seed.sql`
- `supabase/tests/055_canonical_demo_dataset_test.sql`
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` if a defect is found

Do not insert balances directly when a governed transaction process exists.

## Recovery

If reset fails:

1. Stop immediately.
2. Keep the error output.
3. Do not disable triggers globally.
4. Restore the backup if needed:

```bash
docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/.temp/backups/<backup-file>.sql
```

5. Fix the reset order or controlled reset path, then rerun from a confirmed safe state.
