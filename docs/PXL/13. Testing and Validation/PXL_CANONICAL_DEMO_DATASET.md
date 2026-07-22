# PXL Canonical Demo Dataset

**Status:** Active Operational Reference — incomplete canonical coverage
**Authority:** Tier 3; governed accounting, tax, transaction, security, and findings sources prevail
**Last Verified:** 2026-07-22 deterministic local canonical lane; hosted evidence remains 2026-07-18
**Applies To:** Non-production canonical data, hosted/local validation, recovery, and coverage boundaries
**Read When:** The task changes or validates canonical data or the hosted demo environment
**Do Not Read For:** Routine finding implementation unrelated to canonical fixtures

## Purpose

The canonical demo dataset is the governed development and QA fixture for PXL. It replaces ad hoc demo rows with deterministic companies, setup data, master data, opening stock, posted transactions, and regression assertions that exercise Philippine accounting, tax, inventory, and document-lifecycle behavior.

Authoritative rules remain in:

- `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md`
- `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md`
- `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md`
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
(printf "BEGIN;\nSET pxl.allow_demo_reset = 'on';\n"; cat supabase/seeds/canonical_demo_reset.sql supabase/seeds/canonical_demo_seed.sql supabase/seeds/canonical_phase3_enrichment.sql supabase/seeds/canonical_demo_volume.sql; printf "COMMIT;\n") | docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

## Seed Command

For a seed-only run after the database has already been reset:

```bash
(printf "SET pxl.seed_summary = 'on';\n"; cat supabase/seeds/canonical_demo_seed.sql) | docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

The seed is deterministic and uses stable business codes. It is safest to rerun after the reset script.

Phase 3 uses the base seed as the stable baseline and applies an idempotent enrichment without resetting hosted data:

```bash
docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /dev/stdin < supabase/seeds/canonical_phase3_enrichment.sql
```

The optional high-volume layer adds 40 customers, 30 suppliers, 24 items, 60 draft sales invoices, 30 draft purchase orders, and 30 draft vendor bills to the primary VAT company:

```bash
docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /dev/stdin < supabase/seeds/canonical_demo_volume.sql
```

For a hosted operator, grant owner access without hard-coding the email in source:

```bash
(printf "SET pxl.demo_owner_email = 'operator@example.com';\n"; cat supabase/seeds/canonical_demo_owner_access.sql) | docker exec -i supabase_db_PXL psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

## Test Command

The governed local canonical lane performs a fresh no-seed migration replay, loads the reset/base/enrichment/volume layers in one transaction, and runs all three canonical tests:

```bash
npm run test:canonical
```

For a focused rerun after the canonical seed is already loaded:

```bash
supabase test db --local supabase/tests/055_canonical_demo_dataset_test.sql
supabase test db --local supabase/tests/057_phase3_canonical_implementation_test.sql
supabase test db --local supabase/tests/058_canonical_demo_volume_test.sql
```

If the canonical seed is not loaded, this pgTAP file reports 34 skipped tests instead of failing the general suite.

The complete canonical dataset gate is **88 assertions**: test 055 = 34, test 057 = 38, and test 058 = 16. The canonical lane additionally runs `075_table_coverage_governance_test.sql` (8 seeded assertions), so `npm run test:canonical` reports **4 files / 96 assertions**. Focused reruns do not replace the complete gate after a seed or fixture change.

## Website Audit Command

Start the application against local Supabase:

```bash
VITE_SUPABASE_URL='http://127.0.0.1:54321' VITE_SUPABASE_ANON_KEY="$(supabase status -o env | sed -n 's/^ANON_KEY=//p')" npm run dev -- --host 127.0.0.1 --port 5173
```

Run the current Phase 3 browser visibility and setup-checklist probes:

```bash
AUDIT_BASE_URL='http://127.0.0.1:5173' node scripts/audit_phase3_hosted_ui.mjs
AUDIT_BASE_URL='http://127.0.0.1:5173' node scripts/audit_phase3_checklists.mjs
```

These scripts log in, select each of the five companies, verify the named canonical records/routes, exercise the ABC report set, and capture the current ten-check setup checklist. Playwright must be available to Node; these scripts are hosted-safe UI reads and must not be treated as proof of unsupported workflows.

For a governed hosted UI release gate, use `npm run test:hosted:ui` with explicit approved environment variables as documented in this folder's `README.md`. That command rejects local/non-HTTPS targets and returns nonzero when a company/document probe, report probe, SI-detail contract, or browser page-error check fails.

## Hosted Deployment Status

Authorized non-production hosted project:

- Project ref: `bskjkogijpbhukjkagfj`
- Project name: `PXL`

Hosted status through 2026-07-18:

- Frontend, Supabase link, and database all target `bskjkogijpbhukjkagfj`.
- Hosted migration history is synchronized through `20260716000005`.
- The earlier guarded hosted reset/base seed remains the baseline; Phase 3 did not repeat it.
- `canonical_phase3_enrichment.sql` was applied twice successfully to prove idempotence.
- Hosted tests 055/056/057 passed 34/34, 11/11, and 38/38.
- Hosted UI validation passed 48/48 company/master/document probes and 20/20 ABC report probes.
- On 2026-07-18, a fresh data-only backup was captured, the legacy `PXL Demo Trading Corporation` tenant was removed, and the five canonical tenants were atomically rebuilt with Phase 3 plus the high-volume layer.
- The designated hosted operator has owner membership in all five companies. Local tests 055/057/058 passed 34/34, 38/38, and 16/16 after the rebuild; hosted SQL verification confirmed exact volume counts, all reset triggers restored, 12 open ABC periods, and zero current AR/AP reconciliation variance. The hosted pgTAP CLI connector was not counted because its temporary login role lacked direct table permissions.

## Setup Checklist Status

Under `PXL-AUD-067` (Retested Passed), the Company Setup Checklist now presents readiness in explicit stages. **Stage 1 — Core Accounting Readiness** validates the ten posting prerequisites: legal profile, branch, fiscal calendar/period, chart of accounts, number series, compliance/tax setup, and GL mappings. **Stage 2 — Operational Readiness** separately evaluates customers, suppliers, products/services, conditional inventory warehousing (Not Applicable for service-only companies), and bank accounts. A persistent note states **Production Readiness** — validated live transactions, reconciliations, period close, and controls — is assessed separately and is never implied by a complete checklist. Completing Stage 1 no longer presents a company as operationally or production ready. All five canonical companies are both core-accounting and operationally ready in the current seed; the service-only OPC and Prime companies correctly show VAT and inventory warehousing as Not Applicable.

## Company Profiles

| Code | Registered Name | Entity Type | Taxpayer Type | Purpose |
| --- | --- | --- | --- | --- |
| `DEMO-SP-NONVAT` | Golden Retail Store | Sole proprietor | Non-VAT | MSME retail, branch operations, simple inventory and cash/credit sales. |
| `DEMO-CORP-VAT` | ABC Trading Corporation | Corporation | VAT | Primary full-featured trading, accounting, tax, purchasing, and inventory QA company. |
| `DEMO-OPC-NONVAT` | Northstar Digital Solutions OPC | OPC | Non-VAT | Service-only corporate behavior, project-service style billing, non-inventory flow. |
| `DEMO-SVC-VAT` | Prime Business Advisory Inc. | Corporation | VAT | VAT service billing and withholding timing separate from inventory trading. |
| `DEMO-PARTNERSHIP-VAT` | Bayani Partners and Company | Partnership | VAT | Entity-type coverage where supported by schema. |

## Master Data Summary

Hosted canonical totals after Phase 3 and high-volume enrichment:

| Area | Count |
| --- | ---: |
| Demo companies | 5 |
| Branches | 8 |
| Departments | 13 |
| Cost centers | 10 |
| Chart-of-account rows | 215 |
| Payment terms | 25 |
| UOMs | 40 |
| Items and services | 91 |
| Warehouses | 6 |
| Customers | 66 |
| Suppliers | 56 |
| Employees | 26 |
| Bank accounts | 10 |
| Demo auth users | 5 |

Primary VAT trading company (`DEMO-CORP-VAT`) has 3 branches, 5 departments, 5 cost centers, 3 warehouses, 50 customers, 40 suppliers, 22 stock items, 18 service items, sales/purchasing approval fixtures, bank accounts, employees, and number series for core document types.

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
- Golden Phase 3: opening inventory/JE, retail credit SI and partial OR, PO/RR/VB/PV, branch transfer, shrinkage adjustment.
- ABC Phase 3: quotation -> SO -> DR -> SI -> partial OR, applied CM, vendor credit/application, cash purchase, physical count, and governed SI void/reversal.
- Northstar Phase 3: retainer and milestone SIs, full retainer OR, cloud-service VB/PV, and adjusting accrual JE.
- Prime Phase 3: VAT-exclusive and VAT-inclusive/CWT SIs, partial OR, professional-fee and rent VBs with EWT, and partial PV.
- Bayani Phase 3: opening inventory, partial PO/RR/VB/PV, SO/DR/SI/OR chain, open advisory CWT SI, positive adjustment, and partner drawing JE.
- ABC high-volume work queue: 60 editable draft sales invoices across all three branches, 30 editable draft purchase orders, and 30 editable draft vendor bills. These are intentionally unposted so an operator can continue their lifecycles in the application.

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

- Credit memo, vendor credit/application, physical count, cash purchase, and posted SI reversal are now covered. Customer/purchase returns, debit/supplier debit memos, serialized inventory, and reservation/commitment scenarios remain unimplemented or unexercised.
- Hosted route visibility is passed for the scripted canonical probes. The consolidated transaction workspace UI is implemented; report/source drilldown and transaction-specific business qualification are not exhaustively proven for every company.
- Table coverage is governed by the maintained matrix `PXL_TABLE_COVERAGE_MATRIX.md` and the deterministic guard `075_table_coverage_governance_test.sql` (PXL-AUD-059, Retested Passed). Locally all 176 public base tables are classified: 90 expected-populated and 86 explicitly deferred/empty. Banking transactions/reconciliation, fixed assets, approvals, schedules, returns, statutory-return generation, and CAS export artifacts remain intentionally deferred, not overstated. Hosted coverage was last profiled at 82 populated / 66 classified empty of 148 tables.
- Hosted company selector access is membership-scoped after `20260716000002`: canonical demo users and the designated hosted operator see exactly the five canonical companies. The superseded `PXL Demo Trading Corporation` tenant was removed during the 2026-07-18 rebuild; broad global BIR form configuration policies are tracked separately as `PXL-AUD-063`.
- Project, location, and functional-entity masters now exist in the local migration chain (MDP-09), but the canonical fixture does not yet populate or exercise them; PXL-AUD-053 governs Sales Invoice propagation/report coverage.
- Service-only project billing is represented by deterministic service invoices, not a full project subledger.
- Approval workflow definitions exist, but no `approval_instances` canonical execution was fabricated.
- `scripts/audit_phase3_hosted_ui.mjs` and `scripts/audit_phase3_checklists.mjs` are the current hosted UI probes.

## Finding References

Official status and remediation live only in `PXL_END_TO_END_AUDIT_FINDINGS.md`. Active canonical-environment work should normally consider `PXL-AUD-060` (the sole remaining open finding). `PXL-AUD-053`, `PXL-AUD-055`, `PXL-AUD-059`, and `PXL-AUD-067` are Retested Passed; `PXL-AUD-059` coverage governance is maintained through `PXL_TABLE_COVERAGE_MATRIX.md` and guard `075`. PXL-AUD-061 now governs the permanent release lanes as Retested Passed; PXL-AUD-063 and PXL-AUD-066 are also passed historical controls. Do not copy their full content here or infer that a passed canonical probe closes an unrelated finding.

## How To Rerun

1. Confirm non-production environment.
2. Start the isolated local stack with `supabase db start`; back it up first if its current data must be retained.
3. Run `npm run test:canonical` from the repository root.
4. Require tests 055/057/058 to pass 88/88; do not count skipped assertions as seeded canonical evidence.
5. Run `npm run test:db:local` and the remaining release gates defined in this folder's `README.md` before release use.

## How To Extend

Use stable codes and deterministic dates. Add new scenarios to:

- `supabase/seeds/canonical_demo_seed.sql`
- `supabase/seeds/canonical_demo_volume.sql` for additive list-scale fixtures
- `supabase/tests/055_canonical_demo_dataset_test.sql`
- `supabase/tests/058_canonical_demo_volume_test.sql` for high-volume fixtures
- `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md`
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
