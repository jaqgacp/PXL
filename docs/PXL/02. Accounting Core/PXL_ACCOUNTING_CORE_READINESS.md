# PXL Accounting Core Readiness

**Status:** Active Operational Gate
**Authority:** Tier 3 Operational Support; Tier 1 accounting rules and the central findings register prevail
**Last Verified:** 2026-08-04 product-scope and status reconciliation
**Applies To:** Sequencing work before broader transaction/report/UX rollout
**Read When:** Deciding whether a proposed implementation can proceed
**Do Not Read For:** Current finding counts or detailed remediation; use `AI/AI_STATE.md` and the referenced central finding

## Purpose

The current phase is accounting-core hardening and canonical-environment validation. PXL is not production-ready. This document controls sequencing; it does not maintain defect status, duplicate findings, or define posting behavior.

Authorities:

- `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md` defines governed accounting/posting behavior.
- `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md` defines transaction lifecycle and implementation maturity.
- `PXL_END_TO_END_AUDIT_FINDINGS.md` is the only official defect and remediation register.
- `AI/AI_STATE.md` selects one bounded next task.
- `docs/PXL/00. Governance/PXL_PRODUCT_BACKLOG.md` holds approved and future work outside the current finding.

## Current Gate

Do not clear **PXL Accounting Core Ready** merely because the findings programme
is complete. The central register currently has no active remediation row, but
no source-to-statements-to-tax workflow meets the Product Definition of Done,
recovery has not operated over real data, hosted parity is absent after the
recorded boundary and no browser lane exists. Current counts and the selected
next task live only in `AI/AI_STATE.md`.

**Product boundary (PAD-015):** FWT/1601FQ/2306, Payroll/2316, quarterly and
annual Income Tax, MCIT/RCIT, NOLCO, OSD, Fringe Benefits Tax, Transfer Pricing,
Consolidation Tax and specialized-industry tax features are excluded future
extensions. They are not conditions of this gate. After current compliance
work, Banking & Treasury and then Fixed Assets are the product priorities.

## Work Sequence

Unless an active Critical finding requires immediate escalation, work in this order:

1. Security and RLS blockers.
2. Accounting and posting correctness.
3. Tax and BIR/CAS correctness.
4. Deterministic regression and hosted-safe validation.
5. Governed master-data prerequisites.
6. Source-backed transaction business qualification.
7. Save, approval, posting, tax, GL, inventory, relationship, report, and export validation.
8. Report rollout, dashboards, portals, and automation.

The consolidated Transaction Workspace UI is implemented, but visual conformance is not proof of business completeness. Sales Invoice is not an architecture reference; its bounded source qualification is complete, while broader workflow Product-DoD evidence remains open.

## Allowed Work While the Gate Is Active

- Fix one approved active finding.
- Maintain accounting, tax, transaction, security, and audit rules required by verified behavior.
- Harden shared posting, lifecycle, period, reversal, numbering, trace, RLS, and immutability controls.
- Add focused accounting, tax, security, inventory, and regression evidence.
- Govern master data required by an approved transaction.
- Correct documentation drift and validation gates.

## Hard Stops

Without explicit approval, do not:

- create another UI or architecture standard;
- roll the transaction workspace to another document type;
- implement a new report pilot or dashboard;
- add a new transaction family;
- hardcode tax behavior in page code;
- invent missing Project, Location, Functional Entity, or other masters;
- treat visual read-only state as an accounting or security control;
- claim a route, table, report, export, or approved specification proves end-to-end implementation;
- reset/seed Supabase or mutate hosted state; or
- describe the product as production-ready.

## Minimum Definition of Accounting Core Ready

The gate may be reassessed only when all conditions hold:

1. No active Critical finding remains.
2. High findings affecting security, posting, tax, traceability, CAS, source completeness, or regression are fixed or explicitly accepted by authorized governance with documented rationale.
3. Every implemented posting source is registered and follows the shared posting protocol or a verified compatibility wrapper.
4. Every implemented posting source has a governed accounting-rules row and explicit lifecycle, reversal, void/cancel, immutability, and audit behavior.
5. Operational accounts resolve from governed configuration, with overrides role-gated and audited where supported.
6. Tax applicability, rates, ATCs, and withholding behavior resolve from governed, effective-dated configuration and company/counterparty profiles.
7. Settlement totals and posting-critical amounts are server-derived or server-recomputed.
8. Period close, numbering, and CAS evidence are consistent and tested.
9. Required master-data families exist or unsupported dimensions are explicitly excluded.
10. Source-to-JE-to-GL-to-report drillback is verified for each claimed implemented family.
11. Positive and negative tests cover balance, tax, inventory, permissions, cross-company denial, and locked-period denial where applicable.
12. The complete intended regression lane is green, with no product failure hidden in a “held-out” label.

## Current Known Boundaries

- The five-company hosted canonical dataset exercises a meaningful accounting slice, not the entire ERP.
- Banking operations/reconciliation and fixed assets have not started; broader returns, approvals and schedules remain incomplete or unexercised in canonical coverage.
- Six current-scope statutory artifacts use the Filing Artifact path, but the SLSP screen still bypasses it and no filing has been performed with the Bureau.
- Project, Location, and Functional Entity masters exist; broader transaction UX and workflow qualification remain separate from their governed storage and posting controls.
- The current Company Setup Checklist measures ten core-accounting prerequisites, not full operational readiness (`PXL-AUD-067`).
- Frontend validation is source-contract and build coverage only; no browser lane exists.

## Documentation Maintenance

For each meaningful accounting-core task:

1. Update the central finding only when evidence or status changes.
2. Update the accounting and transaction matrices only when their governed behavior changes.
3. Update the accounting test book when a required scenario is added or its executed evidence changes.
4. Refresh `AI/AI_STATE.md` with one next task and run `npm run docs:ai-state-check`.

Do not append session history here. Do not copy full findings here. Historical phase evidence belongs under `docs/PXL/archive/`.
