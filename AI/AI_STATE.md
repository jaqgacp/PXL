# AI State

Last updated: 2026-07-04

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 206/206 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 43 (2026-07-04) closed PXL-DA-011 and PXL-AUD-005: `20260704000002_status_immutability.sql` adds generic status-aware guards — `fn_guard_doc_lines` (18 line tables) and `fn_guard_doc_header` (34 header tables, diff-based: business columns freeze once a document leaves its editable statuses; only status/updated stamps/per-table lifecycle metadata may change; DELETE blocked per DEC-002; posted schedule entries fully frozen). The same-transaction construction exception (`fn_row_written_by_current_txn`: visible row + xmin in progress ⇒ ours; works under subtransactions) keeps every posting writer and the CM/DM apply RPCs working while PostgREST single-transaction clients can never satisfy it. IMMUT-001 (`supabase/tests/020_status_immutability_test.sql`, 25 assertions, COMMITs fixtures to tamper cross-transaction) executed passing; `npm test` 324/324 across 20 files. Session 42 delivered generated DB types + typed client (PXL-AUD-029/030). Session 44 closed PXL-AUD-017; session 46 closed PXL-AUD-018 with a zero-warning lint baseline. Session 47 was the definitive EWT audit (PXL-AUD-031..049); session 48 added the transaction experience standard and PXL-AUD-050. Session 49 FIXED PXL-AUD-031 (receipt CWT explicit VAT-exclusive base, `20260704000003`, CWT-NET-BASE-001 executed). Session 50 partially fixed PXL-AUD-045: PV `ewt_tax_base` now defaults from proportional VAT-exclusive bill outstanding. Sessions 51-56 partially fixed PXL-AUD-050: Sales Invoice, Receipt, Credit Memo, Vendor Bill, Payment Voucher, and Journal Entry now show lifecycle facts and the shared `AuditTrailSection`. Findings standing is 28 Retested Passed / 15 In Progress / 27 Open (70 findings); 11 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md`, `PXL_ACCOUNTING_RULES.md`, and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is fully in sync through migration 20260704000003 (pushed and verified 2026-07-04 via `supabase migration list --linked`). Note: `db push` emits harmless pg-delta CA-cert errors from the drift-check feature; migrations apply anyway — verify with `migration list --linked`, not the push output.
- Dev note: the CSP in `index.html` restricts `connect-src` to `*.supabase.co`, so running the frontend against the local Supabase stack (`127.0.0.1:54321`) requires a CSP bypass (Playwright `bypassCSP` was used for verification). Consider a dev-mode CSP if local frontend testing becomes routine.

## Last Files Changed

Receipt CWT explicit-base session (session 49, 2026-07-04):

- `supabase/migrations/20260704000003_receipt_cwt_explicit_base.sql` (new: `receipt_lines.cwt_tax_base`/`cwt_variance_reason`; rewritten `fn_validate_receipt_line_cwt` + trigger + ready check + `fn_save_receipt` + `fn_post_receipt` + `fn_save_cash_sale`)
- `supabase/tests/021_receipt_cwt_net_base_test.sql` (new: CWT-NET-BASE-001, 20 assertions)
- `src/pages/ReceiptsPage.tsx` (CWT Base column, net-base auto-default, variance-reason select, payload fields)
- `src/pages/CashSalesPage.tsx` (statutory net CWT hint)
- `src/lib/database.types.ts` + `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (CWT-NET-BASE-001 Executed Passing)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` + `docs/PXL/PXL_TRANSACTION_MATRIX.md` (PXL-AUD-031 Retested Passed; standing; session 49 log row; OR row updated)
- `README.md` (small cleanup: stack and migration summary now match React 19 and migration `20260704000003`; detailed object map delegated to generated schema summary)
- `docs/PXL/PXL_TRANSACTION_MATRIX.md` + `AI/AI_WORK_QUEUE.md` (small AIQ-010 context cleanup: Quick Orientation added to the top of the large matrix; AIQ-010 marked Done)
- `docs/PXL/PXL_ACCOUNTING_RULES.md` + `AI/AI_CONTEXT_INDEX.md` + `AI/AI_WORK_QUEUE.md` (small AIQ-006 context cleanup: concise accounting rules summary added and indexed; AIQ-006 marked Done)
- `src/pages/PaymentVouchersPage.tsx` (PXL-AUD-045 partial: PV EWT base defaults from proportional VAT-exclusive bill base)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` + `docs/PXL/PXL_TRANSACTION_MATRIX.md` (PXL-AUD-045 In Progress; standing now 28 Retested Passed / 14 In Progress / 28 Open)
- `src/pages/PaymentVouchersPage.tsx` (PXL-AUD-050 partial: saved PVs now show lifecycle audit facts and `AuditTrailSection`)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` + `docs/PXL/PXL_TRANSACTION_MATRIX.md` (PXL-AUD-050 In Progress; standing now 28 Retested Passed / 15 In Progress / 27 Open)
- `src/pages/VendorBillsPage.tsx` (PXL-AUD-050 partial: saved VBs now show lifecycle audit facts and `AuditTrailSection`)
- `src/pages/ReceiptsPage.tsx` (PXL-AUD-050 partial: saved ORs now show lifecycle audit facts and `AuditTrailSection`)
- `src/pages/SalesInvoicePage.tsx` (PXL-AUD-050 partial: saved SIs now show lifecycle audit facts and `AuditTrailSection`)
- `src/pages/JournalEntriesPage.tsx` (PXL-AUD-050 partial: saved JEs now show lifecycle audit facts and `AuditTrailSection`)
- `src/pages/CreditMemosPage.tsx` (PXL-AUD-050 partial: saved CMs now show lifecycle audit facts and `AuditTrailSection`)

## Last Known Errors

None. `npm test` 344/344 across 21 files on a fresh `supabase db reset --local` (replay through `20260704000003`); `npm run build` passed; `npm run lint` is a zero-warning baseline (exit 0); `scripts/check_docs_consistency.sh` green.

IMPORTANT for future migrations: the PXL-DA-011 guards fire for superuser too — data backfills that rewrite non-draft documents or their lines need `SET session_replication_role = replica` (or targeted `ALTER TABLE ... DISABLE TRIGGER`) around the backfill. New lifecycle columns on guarded tables must be added to that table's allowlist in the guard trigger definition.

Note: `npm test` against a non-fresh local DB can fail with `users_pkey` duplicate-key collisions from earlier seeded runs — always `supabase db reset --local` first.

Session 38 landed as `0f9ab83` (CI 28648390569 green). Session 39 landed as `c575c8b` (CI 28649086159 green). Session 40 landed as `7cfa494` (CI 28699881597 green). Session 41 landed as `cb1fc3e` (2026-07-04); CI run 28701028419 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000001` pushed to hosted and verified via `supabase migration list --linked`. Session 42 landed as `bb6d96c` (2026-07-04); CI run 28706337718 completed successfully, verified via `gh run watch --exit-status`; no migrations in that session, hosted unchanged. Session 43 landed as `ba74c14` (2026-07-04); CI run 28707527259 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000002` pushed to hosted and verified via `supabase migration list --linked`. Session 44 landed as `4274376` (2026-07-04); CI run 28707796428 completed successfully; no migration, hosted re-verified in sync through `20260704000002`. Session 45 landed as `5c3d159` (2026-07-04); CI run 28708225713 completed successfully; no migration, hosted unchanged. Session 46 landed as `b0d02b2` (2026-07-04); CI run 28708398509 completed successfully; no migration, hosted unchanged. Session 47 landed as `b6306f4` (2026-07-04); CI run 28714922044 completed successfully (verified via `gh run watch --exit-status`); documentation only, no migration, hosted unchanged (still synced through `20260704000002`). Session 48 landed as `fbc11db` (2026-07-04); CI run 28715522090 completed successfully (verified via `gh run watch --exit-status`); documentation only, no migration, hosted unchanged. Session 49 landed as `e30de22` (2026-07-04); migration `20260704000003` pushed to hosted and verified via `supabase migration list --linked`.

## Next Recommended Step

Continue AIQ-008 with the remaining EWT Criticals: PXL-AUD-032+033 together (check-voucher EWT validation/supplier linkage + counter-row cancel; scenario CV-EWT-2307-001), then PXL-AUD-034 (1601EQ reconciliation gate; pairs with PXL-AUD-041's remittance flow). Do not redo PXL-AUD-031. The pre-existing Criticals (PXL-DA-001/002/004/008/009/019, AUD-002/006) remain. Run `npm run gen:types` after every migration. Do not redo PXL-DA-011, PXL-AUD-005, PXL-DA-015, PXL-DA-017, PXL-AUD-029, PXL-AUD-030, AIQ-006, or AIQ-010. Summary doc AIQ-007 follows when audit work pauses.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
