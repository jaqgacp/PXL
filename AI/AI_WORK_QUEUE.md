# AI Work Queue

Purpose: prioritized queue for useful continuation under `AI/AI_AUTONOMY_PLAYBOOK.md`.

Status: `Todo`, `In Progress`, `Blocked`, `Done`. Priority: P0 correctness/security/accounting/tax; P1 hardening/tests/context; P2 cleanup/docs.

## Queue

| ID | Priority | Status | Work Mode | Task | Source | Stop / Done Criteria |
| --- | --- | --- | --- | --- | --- | --- |
| AIQ-001 | P1 | Done | Autonomy | Create permanent agent system prompt. | AI cache/autonomy plans | Done 2026-07-02. |
| AIQ-002 | P1 | Done | Autonomy | Create volatile project state file. | AI cache plan, status docs | Done 2026-07-02; updated each meaningful session. |
| AIQ-003 | P1 | Done | Autonomy | Create concise handoff with exact next prompt. | AI cache/autonomy plans | Done 2026-07-02; updated each meaningful session. |
| AIQ-004 | P1 | Done | Context | Create `PXL_ARCHITECTURE_SUMMARY.md`. | Repository architecture docs | Done 2026-07-02. |
| AIQ-005 | P1 | Done | Context | Create generated `PXL_SCHEMA_SUMMARY.md`. | `supabase/migrations/` | Done 2026-07-02; regenerate after migrations. |
| AIQ-006 | P1 | Done | Accounting | Create `PXL_ACCOUNTING_RULES.md`. | Accounting docs/matrix | Done 2026-07-04. |
| AIQ-007 | P1 | Todo | VAT/EWT | Create `PXL_TAX_RULES_PH.md`. | Compliance docs/matrix/audit/test book | Concise PH tax summary exists and points to source docs. |
| AIQ-008 | P0 | In Progress | Audit | Continue highest-severity open audit findings until none remain. | Audit findings, test book, transaction matrix | Current finding fixed or genuinely blocked; tests/docs/hosted state updated. Session 63 closed DA-005 (normal-trigger orphan/cross-company JE rejection in test 026), DA-007 (genuine two-session posting race, new test 029 with dblink), and AUD-051 (document-code/numbering registry alignment + branch-scoped repair of eight callers, migration `20260712000002`, new test 030). Session 64 landed the first DA-019 CAS slice: `20260712000003_posting_runtime_repairs.sql` (test 031, 49 assertions) repaired three schema-lint-surfaced runtime defects, and `20260712000004_cas_numbering_void_evidence.sql` (test 032, 25 assertions) added immutable numbering/void evidence, ATP exhaustion, an owner-proof `P0001` void-evidence immutability trigger, and `vw_cas_atp_usage`; DA-019 stays Critical/Open (DAT layout, books reconciliation, exported-byte hashing remain). Fresh replay/full suite is **601/601 across 31 owned files**; clean schema lint (three prior errors gone), green build/oxlint/docs-gate; types + schema summary regenerated. Standing unchanged: 43 passed / 11 in progress / 18 open; two Criticals remain (DA-009; DA-019). Committed `ffe7782` (pushed to `origin/main`); hosted push complete — `20260712000003`/`20260712000004` applied to `bskjkogijpbhukjkagfj` with held-out `20260710000004`/`00005` moved aside during the push (still off hosted); local = remote through `20260712000004`. |
| AIQ-009 | P1 | Todo | Testing | Add or improve tests for the next open accounting/tax/reporting risk. | Accounting test book | Test exists, runs where practical, and expected scenario is documented. |
| AIQ-010 | P2 | Done | Context | Add high-risk quick orientation to large state docs. | Matrix/audit findings | Done 2026-07-04. |
| AIQ-011 | P1 | Done | Autonomy | Move AI operating files under `AI/` and repair references. | User request | Done 2026-07-02. |
| AIQ-012 | P1 | Done | Autonomy | Finalize/version AIOS and documentation governance. | User request | Done 2026-07-02. |
| AIQ-013 | P1 | Done | Autonomy | Add findings index/readiness gate/schema generator/docs consistency/delegation controls. | User request | Done 2026-07-02. |
| AIQ-014 | P2 | Done | Context | Create product backlog and enforce defect-vs-enhancement separation. | User request, DEC-012 | Done 2026-07-03. |
| AIQ-015 | P0 | In Progress | Product/UI | **ACTIVE SOLE PRIORITY (DEC-015):** Build the Standard Transaction Workspace (DEC-013) across all transaction pages, phased and monitored. DA-009/DA-019 paused. | User directive 2026-07-12; `docs/PXL/PXL_STANDARD_TRANSACTION_WORKSPACE.md`; blueprint §17 | Each phase below shipped: verified (build/lint/types green), committed. Initiative done when core four + secondary docs run under `DocumentLayout` with the standard tab set. Issues found → routed per DEC-015 (defects to audit findings in priority order; enhancements to vision/backlog). |

## AIQ-015 Phase Plan (Standard Transaction Workspace)

Pilot = Sales Invoice (blueprint §17). Adopt-on-touch, reuse components, never fork, never change posting/tax behavior.

| Phase | Scope | Status |
| --- | --- | --- |
| P0 Governance | DEC-015, this queue entry, issue-routing, state/handoff | Done (session 65) |
| P1 Shell | `DocumentLayout` + `WorkflowStrip` + `TransactionTabs` (build first; §15) | Done (session 65) — `src/components/document/DocumentLayout.tsx`, build+lint green |
| P2 Routes | Deep-linkable `/sales-invoices/:id` view route added; list links to it ("Open ↗"). `/new`+`/:id/edit` stay in the list modal for now (route-driven create/edit deferred to a later slice). | Done (session 65) |
| P3 SI view | Done (session 65) — `src/pages/SalesInvoiceDocumentPage.tsx`: read-only document-of-record via `DocumentLayout`; tabs Lines · GL Impact (`GLImpactPanel`) · Posting Validation (checklist) · Audit Trail (`AuditTrailSection`, PXL-AUD-050) · Related; right rail = Financial Summary (§8 SI contract) + Party. Workflow strip + fixed toolbar. build+lint green, HMR verified. | Done (session 65) |
| P4 Panels | Done (session 65) — `src/components/document/FinancialSummaryPanel.tsx` (generic group-based, §8) + `PostingValidationPanel.tsx` (`readinessToChecks` bridges the live `useTransactionReadiness` server preflight, §11). SI doc page now uses both: right-rail summary + live preflight on draft/approved, derived checks on posted/voided. build+lint(0 warn) green, HMR verified. | Done (session 65) |
| P5 Tax+Grid | Done (session 65, user-approved VAT-only scope) — `src/components/document/LineGrid.tsx` (column-group-aware, read-only now, totals footer, structured for later editing; SI Lines tab uses it with a Revenue-Acct provenance column, §5) + `TaxImpactPanel.tsx` (reads `tax_detail_entries`, **VAT kinds only** with draft fallback; EWT/CWT deferred pending PXL-AUD-031/032/033, §10 correctness gate). Tax Impact tab added next to GL Impact. build+lint(0 warn) green, HMR verified. Deferred: editable line entry + full §7 account-determination ladder (arrives with route-driven create/edit). | Done (session 65) |
| P5A Final SI dense template | Final 2026-07-13 brief plus UI polish refinement: company-accent compact header + subtle workspace/tab tint, Posting/Collection/Lock chips in the header, no separate status/workflow strip, no Quick Actions card, exactly three compact information cards, no right rail, portal-based More menu, no-overflow one-line tabs including Workflow and Related Party, expanded GL/Tax/Validation/Workflow/Approval/Audit/Related Party/Attachments/Notes/System tabs, shared ERP section/table/empty-state presentation primitives, standardized table rhythm, compact tab headers, sharper radii, lighter borders/shadows, company appearance master-data migration/UI. Build/lint/diff-check green. | Done (sessions 68-71) |
| P5A.1 Saved-view table framework | Upgrade the reusable transaction line table into the professional ERP table system: Default/Accounting/Tax/Audit/Inventory/Sales/Custom views, saved custom views, browser-local persisted view/columns/order/pins/widths/density/sort/filter state, grouped searchable column chooser with select/clear/reset, drag-and-drop ordering, pin/unpin, manual resizing, compact/comfortable/spacious density, sticky headers/totals/pinned identity columns, export, refresh. Sales Invoice adopts it first; future modules should reuse the same `LineGrid` framework. | Done (session 72) |
| P5B SI consolidation + schema gaps | Move draft create/edit and `/sales-invoices/new` into the canonical workspace; retire register form; expand register actions/columns; create/link missing governed Sales/Customer/Dimension master data and storage-backed attachment/activity/notes/system fields. Never use static selectors. | In Progress — next |
| P6 Rollout | Core four (OR, VB, PV) → secondary docs; `RelatedDocumentsTab` (§12); config layer (§14) | Todo |

## Agent Selection Rule

1. With no direct user task, pick the first unblocked task at the lowest priority number (P0 before P1 before P2).
2. For architecture/accounting/tax/posting/security/lifecycle/compliance, consult `AI/AI_DECISIONS.md` before editing.
3. Mark `Blocked` only under the playbook threshold; otherwise keep progressing safely.
4. End by updating this queue, `AI_STATE.md`, `AI_HANDOFF.md`, and the applicable project docs.

## Current Recommended Next Task

**AIQ-015 is the active sole priority (DEC-015; final SI brief 2026-07-13).** The final dense Sales Invoice viewing/lifecycle template is implemented. Next is **P5B**: relocate draft create/edit + new-document creation into the same route/shell, retire the register form, then add the missing schema-backed master-data links and register actions/columns. Only after the SI pilot is genuinely complete should P6 roll the template to Vendor Bill and the other transaction families. AIQ-008's remaining Criticals (**PXL-DA-009**, **PXL-DA-019**) remain paused.

Discovered issues during workspace work are routed per DEC-015: genuine defects → NEW rows in `docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md` in severity order (so they queue for fix); enhancements → vision/backlog. A defect is fixed mid-phase only if it blocks the phase.

Do not redo AUD-002, AUD-006, AUD-014, AUD-051, DA-001, DA-002, DA-004, DA-005, DA-006, DA-007, or DA-008. The unowned ATC/CAS work (`20260710000004/00005` + test 027) is confirmed broken (breaks test 021; own test fails 15/30), stays untracked and off hosted per the user's 2026-07-11 decision, and must be held out of resets/tests/pushes/docs-gate runs until explicitly owned and fixed.
