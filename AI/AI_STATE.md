# AI State

Last updated: 2026-07-04

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 206/206 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 42 (2026-07-04, bounded frontend-safety session, user-directed) introduced generated database types (`src/lib/database.types.ts`, `npm run gen:types`) and typed the shared Supabase client — column/RPC/embed drift is now a compile error across all 206 pages. This surfaced and closed PXL-AUD-030 (new, High: 8 pages had runtime-dead queries against non-existent columns — quotation/SO/DR/customer-return/cash-sale reference fetches, asset/warehouse supplier lists, SLP register tab; fixed via PostgREST aliases/embeds) and closed PXL-AUD-029 (AppShell feature gating resolves keys via the `ref_feature_definitions` embed). `PXL_ARCHITECTURE_SUMMARY.md` stack line corrected (TanStack Query/Zustand/react-hook-form/Zod installed but NOT adopted); Frontend Architecture backlog section added. Sessions 40/41 closed PXL-DA-015 (snapshot reader UI) and PXL-DA-017 (JE line dimensions per DEC-011). Findings standing is 23 Retested Passed / 14 In Progress / 13 Open (50 findings); 10 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is fully in sync through migration 20260704000001 (pushed and verified 2026-07-04 via `supabase migration list --linked`; user supplied the access token in-session, `link` + `db push --linked --yes`). Note: `db push` emits harmless pg-delta CA-cert errors from the drift-check feature; migrations apply anyway — verify with `migration list --linked`, not the push output.
- PXL-AUD-029 (Open, Medium): `AppShell` feature gating fails open — small query fix pending.
- Dev note: the CSP in `index.html` restricts `connect-src` to `*.supabase.co`, so running the frontend against the local Supabase stack (`127.0.0.1:54321`) requires a CSP bypass (Playwright `bypassCSP` was used for verification). Consider a dev-mode CSP if local frontend testing becomes routine.

## Last Files Changed

Frontend type-safety session (session 42, 2026-07-04):

- `src/lib/database.types.ts` (new, GENERATED — regenerate with `npm run gen:types` after EVERY migration)
- `src/lib/supabase.ts` (client typed `createClient<Database>`)
- `src/components/AppShell.tsx` (PXL-AUD-029 feature-gating fix)
- 8 pages with runtime-dead queries repaired via aliases/embeds (PXL-AUD-030): Quotations, SalesOrders, DeliveryReceipts, CustomerReturns, CashSales, AssetAcquisition, WarehouseStockSettings, PurchaseRegisters (SLP tab reworked)
- ~30 pages: behavior-neutral type fixes (optional RPC args omitted instead of null, non-null assertions on intentional null-for-new args, read-list casts, literal-union dynamic names, `TablesInsert`/`TablesUpdate` payload casts)
- `docs/PXL/PXL_ARCHITECTURE_SUMMARY.md` (stack line corrected — no overstated tech)
- `docs/PXL/PXL_PRODUCT_BACKLOG.md` (Frontend Architecture section)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-AUD-029/030 Retested Passed; standing; session 42 log row)
- `package.json` (`gen:types` script)

## Last Known Errors

None. `npm test` 299/299 across 19 files on a fresh `supabase db reset --local` (replay through `20260704000001`); `npm run build` passed; `npm run lint` passed with pre-existing warnings only (39); `scripts/check_docs_consistency.sh` green.

Note: `npm test` against a non-fresh local DB can fail with `users_pkey` duplicate-key collisions from earlier seeded runs — always `supabase db reset --local` first.

Session 38 landed as `0f9ab83` (CI 28648390569 green). Session 39 landed as `c575c8b` (CI 28649086159 green). Session 40 landed as `7cfa494` (CI 28699881597 green). Session 41 landed as `cb1fc3e` (2026-07-04); CI run 28701028419 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000001` pushed to hosted and verified via `supabase migration list --linked`.

## Next Recommended Step

Continue AIQ-008 with the next Critical: PXL-DA-011 (status-aware immutability on every transactional header/line table, Open) or PXL-DA-001 (server-side GL preview RPC, In Progress). IMPORTANT new discipline: run `npm run gen:types` after every migration so `src/lib/database.types.ts` stays in sync — a stale types file fails the frontend build on new columns/RPCs. Do not redo PXL-DA-015, PXL-DA-017, PXL-AUD-029, or PXL-AUD-030.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
