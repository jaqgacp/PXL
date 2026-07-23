# PXL AI State

**Current Date:** 2026-07-23
**Current Branch:** `main`
**Working Tree:** Dirty with preserved prior MDP/security/certification work plus the bounded PXL-AUD-070 immutability-bypass remediation (migration `20260723000001`, guard test `078`) and the Number Series Engine certification hardening (migration `20260723000002`, guard test `079`). No commit has been made; preserve unrelated user changes.
**Product Phase:** Production Certification Program. Framework setup is complete; engine certification is executing, with three engines now Certified.
**Environment:** Authorized non-production hosted project `bskjkogijpbhukjkagfj`; migration history synchronized through `20260716000005`. The local migrations `20260723000001` (immutability) and `20260723000002` (number-series contract guard) are NOT yet applied to the hosted project. Do not reset, seed, migrate, repair, link, or otherwise mutate the hosted project without explicit approval. Local reset/test work is permitted.
**Product Readiness:** Internal QA/demo only. PXL is not production-ready and not pilot-ready while module/engine certification evidence is incomplete. No module is Certified; three shared engines are Certified.

## Current Finding Standing

Generated from `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md`: **90 Retested Passed / 0 In Progress / 0 Open (90 total)**.

- Active Critical: none.
- Active High: none.
- Active Medium: none. Every audit finding is Retested Passed.

## Active Work Map

No audit findings remain open. A Critical posted-document immutability bypass discovered during the Audit & Immutability Engine certification review was remediated, permanently guarded, and closed this session (see Last Verified Commands). A closed findings register does not certify any module: Setup & Master Data remains **Blocked** on its own Partial/operational/shared-engine evidence. Coverage governance is maintained through `PXL_TABLE_COVERAGE_MATRIX.md` plus guard `075`; adding a `public` base table requires a matching registry entry in both. The next work is Production Certification execution, not defect remediation.

## Hosted and UX Status

The five canonical companies are present and owned by the hosted operator. ABC Trading carries the high-volume demo data; last hosted automation passed 48/48 company/master/document and 20/20 report probes. Table coverage is governed under PXL-AUD-059: 176 local tables classified in `PXL_TABLE_COVERAGE_MATRIX.md`; hosted last profiled 82/66 of 148.

`PXL_TRANSACTION_WORKSPACE_STANDARD.md` and `PXL_TRANSACTION_WORKSPACE_PATTERNS.md` remain the transaction UI authorities. Sales Invoice is one implementation; PXL-AUD-053 still governs its validated source-backed completeness, so business qualification remains source-gated. Do not call Form/View UX fully implemented from that business/source result. Non-SI rows remain `transaction-matrix-only`.

## Documentation Cleanup Status

Active docs are organized under `docs/PXL/00. Governance/` … `docs/PXL/13. Testing and Validation/`, leaving only the master index and central findings register in `docs/PXL` root. Superseded UI and legacy SI blueprints were archived; generated placeholders, obsolete AIOS files, scratch scripts, and the non-authoritative Master Pharmacy working paper are in trash-review for human deletion/reconciliation. No permanent deletion is intended unless validation later proves a file empty, generated, unreferenced, and reproducible.

## Production Certification Program

The current program certifies every supported module and shared engine toward controlled production use. The permanent framework is four documents under `docs/PXL/13. Testing and Validation/`: `PXL_MODULE_CERTIFICATION_STANDARD.md` (23 module gates), `PXL_ENGINE_CERTIFICATION_STANDARD.md` (engine contracts/invariants/concurrency), `PXL_PRODUCT_COMPLETENESS_CHECKLIST.md` (capability expectations feeding module gates 1 and 22), and `PXL_CERTIFICATION_MATRIX.md` (status dashboard only). Do not create per-module status files or duplicate findings registers.

Three engines are now Certified: **Permissions/RLS** (first), **Audit & Immutability** (second, 2026-07-23 after PXL-AUD-070 remediation), and **Number Series** (third, 2026-07-23). Setup & Master Data remains **Blocked on missing evidence, not defects** (Gate 23 backup/restore/RPO/RTO does not exist; not all dependent engines are Certified — Dimension is not; Gate 20 browser evidence recorded-only). No module is Certified.

Phase order: (1) Setup/Master Data, Permissions/RLS, Core Accounting, Posting, Period Lock, Audit/Immutability, Number Series, Dimensions; (2) Sales/AR; (3) Purchasing/AP; (4) Inventory; (5) Banking/Treasury and Payments; (6) Fixed Assets; (7) Compliance/Tax; (8) Reports/FS/Reconciliation; (9) Production Operations, Backup/Restore, Deployment, Pilot readiness. Backup and restore evidence (Phase 9) does not yet exist and must not be claimed.

## Known Blockers and Non-Assumptions

- The remediation migration `20260723000001` is applied locally only; it must be applied to the hosted project under explicit approval before any hosted immutability claim.
- Banking, fixed assets, returns, broad transaction approval rollout, schedules, statutory generators, and CAS artifacts are not proven complete.
- Do not assume green checklists mean operational readiness, a rendered route means source-backed correctness, or archived phase reports are current status.
- Do not read `docs/PXL/archive/`, `docs/PXL/trash-review/`, all Compliance files, all SI specifications, or the full findings body for the next task.

## Last Verified Commands

Audit & Immutability Engine certification — **CERTIFIED** 2026-07-23 (second Certified engine), after remediating the Critical bypass found during the review:

- PXL-AUD-070 remediation: the immutability guard family (`fn_guard_doc_header`, `fn_guard_doc_lines`, four `fn_block_*_line_mutation_after_draft`) previously short-circuited on the USERSET GUC `pxl.allow_demo_reset='on'`, letting any authenticated member UPDATE/DELETE posted documents. Migration `20260723000001` gates the bypass on `fn_demo_reset_bypass_authorized()` (GUC AND a privileged `session_user` via `fn_role_is_privileged_maintenance`, i.e. `rolsuper`/`rolbypassrls`). `session_user=authenticator` for every PostgREST call, so the GUC alone can no longer disable immutability.
- Evidence: a production-identical `authenticator` reproduction confirmed the block (payee/line unchanged) and the authorized `postgres`+GUC maintenance path still writes. Focused test `078_immutability_demo_reset_bypass_guard_test.sql` passes 16/16 and is a permanent static class guard wired into the regression and canonical lanes. Full local lane green: fresh `--no-seed` replay through `20260723000001`, `test:db:local`, `test:canonical`, docs, lint, build, secret guard, diff.
- Immutability strengths retained: `sys_audit_logs`/`transaction_events` tamper-proof to authenticated; 79 tables audited; posted-doc guards (42 header/18 line) with tests 020/041/061/009/010/012.

Number Series Engine certification — **CERTIFIED** 2026-07-23 (third Certified engine):

- Contract: `fn_next_document_number(company, branch, code)` allocates a continuous `prefix+LPAD(seq,padding)+suffix` number under a `FOR UPDATE` row lock, membership-checked, active-only, ATP-bounded, writing forward-only `cas_document_number_issuances` evidence bound to the source document by 24 `fn_bind_cas_document_number` triggers; `number_series` writes are MDP-03 permission-gated; issued counters are no-backward/no-identity guarded; void evidence is immutable (test 032). ~25 document codes consume the governed allocator (server-side RPC for SI/CS/OR/JE/CM/DM-S/VB/PV/CP/VC/SDM/RR/PRT/PO/FA; client RPC then insert for CV/QT/SO/DR/FT/IBT/BADJ/PCV/PCR/CCS).
- Concurrency proven empirically: 10 concurrent clients × 20 allocations → 200 distinct, contiguous, zero duplicates, counter == 200. Company/branch isolation, inactive-series rejection, same-transaction rollback (no drift), and manual-number duplicate rejection all proven.
- Certification hardening: migration `20260723000002` adds a contract guard rejecting `has_dynamic_year=true` and `reset_frequency<>'never'` (the continuous allocator honors neither; CAS numbering is non-resetting) — the UI could previously store these unhonored. Guard test `079` (17/17) plus tests 030/032 run in the regression and canonical lanes. Not a defect finding (0 of 264 series used the values; latent, non-mandatory). Limitation: default auto-provisioning (MDP-06) covers only BIR-registered SI/CS/OR; other codes require explicit setup and fail closed if absent.

Permissions/RLS Engine remains **CERTIFIED** 2026-07-22: RLS on 176/176 tables (473 policies); default-deny; 335/335 DEFINER functions pin `search_path`; all authenticated views `security_invoker`; guard `077`; prior Critical PXL-AUD-069 Retested Passed via `20260722000011`.

Setup & Master Data Phase 1 re-review 2026-07-22 — Blocked on missing evidence, not defects; all 35 master-data gaps resolved (MDP-01…15). PXL-AUD-053 Sales Invoice completeness Retested Passed (test 054 42/42; canonical 88/88).

## Recommended Next Task

The finding program is complete — no audit findings remain open (90/90 Retested Passed) — and three shared engines are Certified (Permissions/RLS, Audit & Immutability, Number Series). Immediate next task, with user authorization: execute the **Dimension Engine** certification review from scratch against its governing standard (governed Project/Location/Functional Entity masters and `fn_is_valid_dimension` exist from MDP-09; transaction propagation, journal/report integration, and non-double-counting remain unproven), then Gate 23 backup/restore. Do not assume any module or remaining engine is Certified; each requires an executed review. Before any hosted immutability or numbering claim, apply migrations `20260723000001` and `20260723000002` to the hosted project under explicit approval and re-verify.
