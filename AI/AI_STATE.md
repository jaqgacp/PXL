# AI State

Last updated: 2026-07-10

## Project Status

PXL is a React + TypeScript + Vite frontend backed by Supabase/PostgreSQL. The repository contains extensive PXL documentation, migrations, pgTAP tests, and module pages.

Current documented build status in `docs/PXL/STATUS.md` says 206/206 pages are built, with production-hardening and audit work continuing through `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`, `docs/PXL/PXL_TRANSACTION_MATRIX.md`, and `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md`.

## Completed AI Operating Files

All files listed in `AI/AI_DOCUMENTATION_RULES.md` exist under `AI/`. The AI Operating System is at version 1.3.0 (`AI/AIOS_VERSION.md`) and is finalized as the permanent operating system for AI sessions. Per DEC-012, enhancements live in `docs/PXL/PXL_PRODUCT_BACKLOG.md` and every touched module gets a lightweight architectural review; audit findings hold defects only.

## Current Active Task

AIQ-008 (P0): work through open audit findings in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`. Session 43 (2026-07-04) closed PXL-DA-011 and PXL-AUD-005: `20260704000002_status_immutability.sql` adds generic status-aware guards — `fn_guard_doc_lines` (18 line tables) and `fn_guard_doc_header` (34 header tables, diff-based: business columns freeze once a document leaves its editable statuses; only status/updated stamps/per-table lifecycle metadata may change; DELETE blocked per DEC-002; posted schedule entries fully frozen). The same-transaction construction exception (`fn_row_written_by_current_txn`: visible row + xmin in progress ⇒ ours; works under subtransactions) keeps every posting writer and the CM/DM apply RPCs working while PostgREST single-transaction clients can never satisfy it. IMMUT-001 (`supabase/tests/020_status_immutability_test.sql`, 25 assertions, COMMITs fixtures to tamper cross-transaction) executed passing; `npm test` 324/324 across 20 files. Session 42 delivered generated DB types + typed client (PXL-AUD-029/030). Session 44 closed PXL-AUD-017; session 46 closed PXL-AUD-018 with a zero-warning lint baseline. Session 47 was the definitive EWT audit (PXL-AUD-031..049); session 48 added the transaction experience standard and PXL-AUD-050. Session 49 FIXED PXL-AUD-031 (receipt CWT explicit VAT-exclusive base, `20260704000003`, CWT-NET-BASE-001 executed). Session 50 partially fixed PXL-AUD-045: PV `ewt_tax_base` now defaults from proportional VAT-exclusive bill outstanding. Sessions 51-56 partially fixed PXL-AUD-050: Sales Invoice, Receipt, Credit Memo, Vendor Bill, Payment Voucher, and Journal Entry now show lifecycle facts and the shared `AuditTrailSection`. Session 57 (2026-07-05) CLOSED PXL-AUD-032 and PXL-AUD-033: `20260705000001_cv_ewt_supplier_validation.sql` adds `check_vouchers.supplier_id`/`ewt_tax_base`/`ewt_variance_reason` (supplier REQUIRED when EWT > 0; PV-parity validation via `trg_cv_ewt_validation` + post-time recheck reusing `fn_validate_payment_voucher_line_ewt`); `fn_post_check_voucher` writes supplier-linked tax detail with the explicit base and ATC master rate; `fn_cancel_check_voucher` switched to `fn_reverse_tax_detail_entries` counter-rows (legacy bare CV counter-rows backfilled + re-dated onto their reversal JE); `fn_generate_form_2307_issued` skips supplier-unlinked rows with `skipped_unlinked_count`/`skipped_unlinked_ewt` instead of aborting the quarter. `CheckVouchersPage` gained supplier select, auto-tracking EWT base, variance-reason select, and the PXL-AUD-050 Audit Evidence block; `Form2307IssuedPage` surfaces the skip warning. CV-EWT-2307-001 executed (`supabase/tests/022_cv_ewt_2307_test.sql`, 17 assertions). Session 58 (2026-07-10) CLOSED PXL-AUD-034 (the last session-47 EWT Critical): `20260710000001_ewt_return_reconciliation_gate.sql` adds `fn_compute_ewt_return` (server-side quarterly totals from the `ewt_payable` tax ledger, reversals included so cancels net out) and `trg_ewt_returns_status_reconciled` (BEFORE INSERT OR UPDATE, fires before the DA-011 guard): final/filed blocked unless figures match the ledger within 0.01, `still_due = withheld - remitted_prior` with non-negative prior, and `fn_wht_gl_reconciliation` reconciles the quarter to the EWT Payable control account; metadata-only updates of a validated return pass (mirrors `trg_vat_returns_status_reconciled`). `EWT1601EQReturnPage`: Generate calls the RPC, tax base/EWT withheld are read-only server-computed, gate hint added. EWT-RETURN-GATE-001 executed (`supabase/tests/023_ewt_return_gate_test.sql`, 12 assertions); `npm test` 373/373 across 23 files. Findings standing is 31 Retested Passed / 15 In Progress / 24 Open (70 findings); 8 Criticals remain.

## Current Broken / Missing AI Operating Areas

- Concise stable summary docs still missing (`PXL_ARCHITECTURE_SUMMARY.md`, `PXL_ACCOUNTING_RULES.md`, and generated `PXL_SCHEMA_SUMMARY.md` now exist):
  - `docs/PXL/PXL_TAX_RULES_PH.md` (AIQ-007)
- No Claude/Anthropic API integration exists yet; do not implement `cache_control` code until an integration exists or is explicitly requested.
- Remote grant posture vs Supabase's legacy auto-expose defaults has not been diffed (PXL-AUD-026 residue).
- Remote is in sync through migration 20260710000001 (pushed and verified 2026-07-10 via `supabase migration list --linked`). Note: `db push` emits harmless pg-delta CA-cert errors from the drift-check feature; migrations apply anyway — verify with `migration list --linked`, not the push output.
- Dev note: the CSP in `index.html` restricts `connect-src` to `*.supabase.co`, so running the frontend against the local Supabase stack (`127.0.0.1:54321`) requires a CSP bypass (Playwright `bypassCSP` was used for verification). Consider a dev-mode CSP if local frontend testing becomes routine.

## Last Files Changed

1601EQ reconciliation gate session (session 58, 2026-07-10, PXL-AUD-034):

- `supabase/migrations/20260710000001_ewt_return_reconciliation_gate.sql` (new: `fn_compute_ewt_return` + `fn_require_ewt_return_reconciled` / `trg_ewt_returns_status_reconciled`)
- `supabase/tests/023_ewt_return_gate_test.sql` (new: EWT-RETURN-GATE-001, 12 assertions)
- `src/pages/EWT1601EQReturnPage.tsx` (Generate calls `fn_compute_ewt_return`; tax base/EWT withheld read-only server-computed; gate hint; unused `quarterMonths` removed)
- `src/lib/database.types.ts` + `docs/PXL/PXL_SCHEMA_SUMMARY.md` (regenerated)
- `docs/PXL/PXL_ACCOUNTING_TEST_BOOK.md` (EWT-RETURN-GATE-001 Executed Passing, step 4 added for the remittance-JE variance leg)
- `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` (AUD-034 Retested Passed with Fix Applied/Remaining Risk; standing 31/15/24; session 58 log row)
- `docs/PXL/PXL_TRANSACTION_MATRIX.md` (EWT Return 1601EQ/QAP row updated to gated state; Quick Orientation lane moved to the EWT High tier; AUD-034 addendum row closed)
- `AI/AI_STATE.md`, `AI/AI_HANDOFF.md`, `AI/AI_WORK_QUEUE.md` (session close-out)

## Last Known Errors

None. `npm test` 373/373 across 23 files on a fresh `supabase db reset --local` (replay through `20260710000001`); `npm run build` passed; `npm run lint` is a zero-warning baseline (exit 0); `scripts/check_docs_consistency.sh` green.

IMPORTANT for future migrations: the PXL-DA-011 guards fire for superuser too — data backfills that rewrite non-draft documents or their lines need `SET session_replication_role = replica` (or targeted `ALTER TABLE ... DISABLE TRIGGER`) around the backfill. New lifecycle columns on guarded tables must be added to that table's allowlist in the guard trigger definition.

Note: `npm test` against a non-fresh local DB can fail with `users_pkey` duplicate-key collisions from earlier seeded runs — always `supabase db reset --local` first.

Session 38 landed as `0f9ab83` (CI 28648390569 green). Session 39 landed as `c575c8b` (CI 28649086159 green). Session 40 landed as `7cfa494` (CI 28699881597 green). Session 41 landed as `cb1fc3e` (2026-07-04); CI run 28701028419 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000001` pushed to hosted and verified via `supabase migration list --linked`. Session 42 landed as `bb6d96c` (2026-07-04); CI run 28706337718 completed successfully, verified via `gh run watch --exit-status`; no migrations in that session, hosted unchanged. Session 43 landed as `ba74c14` (2026-07-04); CI run 28707527259 completed successfully, verified via `gh run watch --exit-status`; migration `20260704000002` pushed to hosted and verified via `supabase migration list --linked`. Session 44 landed as `4274376` (2026-07-04); CI run 28707796428 completed successfully; no migration, hosted re-verified in sync through `20260704000002`. Session 45 landed as `5c3d159` (2026-07-04); CI run 28708225713 completed successfully; no migration, hosted unchanged. Session 46 landed as `b0d02b2` (2026-07-04); CI run 28708398509 completed successfully; no migration, hosted unchanged. Session 47 landed as `b6306f4` (2026-07-04); CI run 28714922044 completed successfully (verified via `gh run watch --exit-status`); documentation only, no migration, hosted unchanged (still synced through `20260704000002`). Session 48 landed as `fbc11db` (2026-07-04); CI run 28715522090 completed successfully (verified via `gh run watch --exit-status`); documentation only, no migration, hosted unchanged. Session 49 landed as `e30de22` (2026-07-04); migration `20260704000003` pushed to hosted and verified via `supabase migration list --linked`.

## Next Recommended Step

Continue AIQ-008. All four session-47 EWT Criticals (AUD-031, AUD-032/033, AUD-034) are closed — do not redo them. Next: either the EWT High pair PXL-AUD-035+036 (ATC as-of-document-date validation + rate versioning; scenarios ATC-ASOF-001 / ATC-RATE-VERSION-001) or resume the pre-existing Critical lane with PXL-DA-001 (server-side GL preview RPC, In Progress). The pre-existing Criticals (PXL-DA-001/002/004/008/009/019, AUD-002/006) remain. Run `npm run gen:types` after every migration. Do not redo PXL-DA-011, PXL-AUD-005, PXL-DA-015, PXL-DA-017, PXL-AUD-029, PXL-AUD-030, AIQ-006, or AIQ-010. Summary doc AIQ-007 follows when audit work pauses.

## Standing Autonomy Delegation

No user decisions are pending. On 2026-07-02 the user delegated all business-policy and prioritization decisions to the agent (DEC-008): decide with standard-accounting-practice, PH-compliance-conservative defaults, record a DEC entry, proceed. The former open questions are decided: role/action matrix DEC-009, approval segregation of duties DEC-010, branch as reporting dimension DEC-011, direct commits to `main` with CI as gate DEC-008. PXL-DA-003, PXL-AUD-004, PXL-DA-012, and PXL-DA-017 are now unblocked for implementation.

Hard stops that remain: weakening controls, destructive/irreversible operations on user data, spending money, external legal/compliance actions, and missing credentials (record PENDING). Claude API `cache_control` work stays parked until an API integration exists.
