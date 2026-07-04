# AI State

Last updated: 2026-07-04

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 206/206 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 43 (2026-07-04) closed PXL-DA-011 and PXL-AUD-005: `20260704000002_status_immutability.sql` adds generic status-aware guards — `fn_guard_doc_lines` (18 line tables) and `fn_guard_doc_header` (34 header tables, diff-based: business columns freeze once a document leaves its editable statuses; only status/updated stamps/per-table lifecycle metadata may change; DELETE blocked per DEC-002; posted schedule entries fully frozen). The same-transaction construction exception (`fn_row_written_by_current_txn`: visible row + xmin in progress ⇒ ours; works under subtransactions) keeps every posting writer and the CM/DM apply RPCs working while PostgREST single-transaction clients can never satisfy it. IMMUT-001 (`supabase/tests/020_status_immutability_test.sql`, 25 assertions, COMMITs fixtures to tamper cross-transaction) executed passing; `npm test` 324/324 across 20 files. Session 42 delivered generated DB types + typed client (PXL-AUD-029/030). Session 44 (2026-07-04, small bounded session) closed PXL-AUD-017: company/branch/period context persists in localStorage (`pxl.ctx.*`) and restored IDs are validated against the RLS-scoped selector lists on load (stale/foreign IDs cleared, company staleness cascade-clears branch/period); frontend-only, no migration. Session 45 (2026-07-04, small bounded session) took PXL-AUD-018 to In Progress: cleared the 10 mechanically safe lint warnings (39→29) and in doing so fixed a real defect — six compliance dashboards (Books/CAS/IncomeTax/PT/VAT/WT) recreated `now = new Date()` each render, so `useEffect([load])` refetched from Supabase in a continuous loop; `now`/`quarterMonths` are now `useMemo`-pinned. Session 46 (2026-07-04, small bounded session) closed PXL-AUD-018 entirely: lint is now a ZERO-warning baseline (exit 0). Session 47 (2026-07-04) was an AUDIT-ONLY session (user-directed): the definitive end-to-end EWT audit. No code changed. It added findings PXL-AUD-031..049 (4 Critical / 9 High / 6 Medium) to the findings doc, a session-47 EWT addendum + the previously missing Check Voucher row to the transaction matrix, and 9 Not-Yet-Implemented scenarios (CWT-NET-BASE-001, CV-EWT-2307-001, EWT-RETURN-GATE-001, ATC-ASOF-001, ATC-RATE-VERSION-001, WHT-REMIT-001, PV-OR-HEADER-TOTALS-001, CM-VC-OVERAPPLY-001, CASH-PURCHASE-EWT-001) to the test book. Headline defects: OR CWT base is forced VAT-inclusive and the statutory net-based CWT is hard-rejected (AUD-031); check-voucher EWT is unvalidated, supplier-unlinked (aborts quarterly 2307 generation), and its cancel leaves phantom QAP rows (AUD-032/033); 1601EQ (`ewt_returns`) has no reconciliation gate (AUD-034); ATC validity is checked as of CURRENT_DATE not document date (AUD-035); ATC rate changes cannot be represented under the official code (AUD-036); in-quarter remittance JEs deadlock SAWT/QAP exports (AUD-041). EWT maturity assessed ~55% (PV pipeline ~75%). Session 48 (2026-07-04) was a second AUDIT-ONLY session (user-directed): the transaction experience architecture audit. No code changed. It created `docs/PXL/PXL_TRANSACTION_EXPERIENCE_STANDARD.md` — the Phase 2 UI/UX blueprint every future transaction page follows (document anatomy + per-document routes, 13-tab standard + Compliance Evidence tab, line-grid column groups with role visibility, auto-population matrix, account-determination ladder, summary/GL/Tax panel contracts, drill contract, component inventory, gap analysis; maturity: core four ~60%, JE ~40%, secondary docs ~30%, overall ~45%). One genuine defect logged: PXL-AUD-050 (complete server-side audit trail — lifecycle stamps + `sys_audit_logs` + existing `AuditTrailSection` component — rendered on ZERO transaction pages). Backlog Target section now defers to the standard; `AI_CONTEXT_INDEX.md` UI Mode includes it. Findings standing is 27 Retested Passed / 13 In Progress / 30 Open (70 findings); 12 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md` and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_ACCOUNTING_RULES.md` (AIQ-006)
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- `README.md` stack table is stale (says React 18 / Vite 8, migrations 001–015); `package.json` shows React 19, react-router-dom v7, TanStack Query, Zustand, Zod, and 61 migrations exist. The architecture summary reflects actuals; consider refreshing README separately.
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is fully in sync through migration 20260704000002 (pushed and verified 2026-07-04 via `supabase migration list --linked`). Note: `db push` emits harmless pg-delta CA-cert errors from the drift-check feature; migrations apply anyway — verify with `migration list --linked`, not the push output.
- Dev note: the CSP in `index.html` restricts `connect-src` to `*.supabase.co`, so running the frontend against the local Supabase stack (`127.0.0.1:54321`) requires a CSP bypass (Playwright `bypassCSP` was used for verification). Consider a dev-mode CSP if local frontend testing becomes routine.

## Last Files Changed

Status-aware immutability session (session 43, 2026-07-04):

- `supabase/migrations/20260704000002_status_immutability.sql` (new: `fn_row_written_by_current_txn`, `fn_guard_doc_lines`, `fn_guard_doc_header`, 18 line-guard + 34 header-guard triggers)
- `supabase/tests/020_status_immutability_test.sql` (new: IMMUT-001, 25 assertions; intentionally COMMITs fixtures — always reset before `npm test`)
- `src/lib/database.types.ts` (regenerated)
- `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated: 149 functions, 202 triggers)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (IMMUT-001 scenario)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (PXL-DA-011 + PXL-AUD-005 Retested Passed; standing; session 43 log row)

## Last Known Errors

None. `npm test` 324/324 across 20 files on a fresh `supabase db reset --local` (replay through `20260704000002`); `npm run build` passed; `npm run lint` is a zero-warning baseline (exit 0) as of session 46; `scripts/check_docs_consistency.sh` green.

IMPORTANT for future migrations: the PXL-DA-011 guards fire for superuser too — data backfills that rewrite non-draft documents or their lines need `SET session_replication_role = replica` (or targeted `ALTER TABLE ... DISABLE TRIGGER`) around the backfill. New lifecycle columns on guarded tables must be added to that table's allowlist in the guard trigger definition.

Note: `npm test` against a non-fresh local DB can fail with `users_pkey` duplicate-key collisions from earlier seeded runs — always `supabase db reset --local` first.

Session 38 landed as `0f9ab83` (CI 28648390569 green). Session 39 landed as `c575c8b` (CI 28649086159 green). Session 40 landed as `7cfa494` (CI 28699881597 green). Session 41 landed as `cb1fc3e` (2026-07-04); CI run 28701028419 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000001` pushed to hosted and verified via `supabase migration list --linked`. Session 42 landed as `bb6d96c` (2026-07-04); CI run 28706337718 completed successfully, verified via `gh run watch --exit-status`; no migrations in that session, hosted unchanged. Session 43 landed as `ba74c14` (2026-07-04); CI run 28707527259 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000002` pushed to hosted and verified via `supabase migration list --linked`. Session 44 landed as `4274376` (2026-07-04); CI run 28707796428 completed successfully; no migration, hosted re-verified in sync through `20260704000002`. Session 45 landed as `5c3d159` (2026-07-04); CI run 28708225713 completed successfully; no migration, hosted unchanged. Session 46 landed as `b0d02b2` (2026-07-04); CI run 28708398509 completed successfully; no migration, hosted unchanged. Session 47 landed as `b6306f4` (2026-07-04); CI run 28714922044 completed successfully (verified via `gh run watch --exit-status`); documentation only, no migration, hosted unchanged (still synced through `20260704000002`). Session 48 landed as `fbc11db` (2026-07-04); CI run 28715522090 completed successfully (verified via `gh run watch --exit-status`); documentation only, no migration, hosted unchanged.

## Next Recommended Step

Continue AIQ-008 with the new EWT Criticals from session 47, in this order: PXL-AUD-031 (OR CWT explicit VAT-exclusive base — smallest Critical, widest tax impact), then PXL-AUD-032+033 together (check-voucher EWT validation/linkage + counter-row cancel), then PXL-AUD-034 (1601EQ reconciliation gate; pairs with PXL-AUD-041's remittance flow). The pre-existing Criticals (PXL-DA-001/002/004/008/009/019, AUD-002/006) remain. Run `npm run gen:types` after every migration. Do not redo PXL-DA-011, PXL-AUD-005, PXL-DA-015, PXL-DA-017, PXL-AUD-029, or PXL-AUD-030.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
