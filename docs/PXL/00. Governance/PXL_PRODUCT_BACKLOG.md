# PXL Product Backlog

**Status:** Active Operational Backlog
**Authority:** Tier 3; it does not override Tier 1 rules or the central findings register
**Last Verified:** 2026-07-17
**Applies To:** Approved implementation work, missing capabilities, UX rollout, future enhancements, and deferred work
**Read When:** Planning beyond the one task selected in `AI/AI_STATE.md`
**Do Not Read For:** Finding remediation detail or fresh-session startup

## Backlog Rules

- Official defects and release blockers belong only in `PXL_END_TO_END_AUDIT_FINDINGS.md`.
- This file refers to defects by ID and never duplicates their full evidence or remediation.
- Posting changes must first be defined in `docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES_MATRIX.md`.
- Transaction field/source changes must remain synchronized with `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md` and `docs/PXL/04. Transaction Framework/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md`.
- Nothing here is authorized merely because it is listed. Work must be selected in `AI/AI_STATE.md` or explicitly approved.
- The Accounting Core Ready gate remains active; broad UX/report/dashboard rollout waits behind its security, accounting, tax, CAS, source, and regression prerequisites.

## Active Defects

The authoritative status, severity, scope, and fix are in the central register.

| Finding | Backlog Relationship |
| --- | --- |
| `PXL-AUD-055` | Critical external key-rotation dependency; not a feature backlog item. |
| `PXL-AUD-063` | BIR configuration RLS hardening; recommended next executable finding. |
| `PXL-AUD-066` | CAS historical evidence correction; blocks full regression lane. |
| `PXL-AUD-061` | Deterministic lane governance after CAS correction. |
| `PXL-AUD-053` | Sales Invoice source-backed completeness before approved-reference status. |
| `PXL-AUD-059` | Supported/deferred/unexercised workflow and table coverage. |
| `PXL-AUD-067` | Core-accounting versus operational-readiness checklist scope. |
| `PXL-AUD-060` | Login form accessibility and automation reliability. |

## Approved Implementation Work

These are long-term capabilities under the accounting-core sequence, not substitutes for active findings.

| Work | Required Outcome | Primary Authority / Dependency | Priority |
| --- | --- | --- | --- |
| Account determination engine | Derive operational GL accounts from company, tax profile, item group/item, counterparty, and document type; any override is permission-gated, reason-coded, and audited. | Accounting Rules Matrix; master-data governance | High |
| Configuration-driven tax engine | Resolve VAT, PT, EWT, CWT, and FWT applicability/rates by company and document date using governed versions and profiles. | Accounting Rules Matrix; tax setup specs | High |
| Master-data governance | Model and permission every master required by claimed transactions; do not expose free-text substitutes for missing governed dimensions. | Principles; transaction field-source matrix | High |
| Reconciliation suite | Prove AR=AR control, AP=AP control, inventory=inventory GL, assets=asset GL, FS=TB, and tax ledgers=tax controls with drillable variances. | Existing VAT/WHT and as-of reconciliation patterns | High |
| CI schema-type drift gate | Regenerate Supabase types against a migrated DB and fail when `src/lib/database.types.ts` differs. | `npm run gen:types`; CI | High |
| Governed full regression lanes | Name fresh-schema, canonical-seeded, hosted-safe read-only, and hosted UI lanes with explicit prerequisites/results. | `PXL-AUD-061`; `PXL-AUD-066` | High |

## UX Rollout

The UI architecture rollout is complete for the 41 implemented transaction surfaces. `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md` is the sole layout/visual authority and `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_PATTERNS.md` is the sole content-variation authority. Sales Invoice is an implementation, not an architecture dependency.

Future transaction UI work must add the route to the executable coverage registry, preserve business controls, compose the shared workspace, and run the full route/screenshot/zoom/theme validation. Field-source and accounting qualification remains separate backlog work.

| Work | Required Outcome | Readiness |
| --- | --- | --- |
| Standard transaction layout | Maintain one fluid workspace architecture without erasing transaction-specific rules. | Implemented on 41 surfaces; future routes use the same gate |
| Shared financial summary | Server-authoritative totals and consistent commercial/inventory/accounting presentation per transaction type. | SI specification exists; shared contract not rolled out |
| Tax impact panel | Tax-detail rows, ATC/rates, certificate/export relationships, and reconciliation status with drillback. | Ledger sources exist; shared UX pending |
| Posting validation panel | Explain company, branch, period, series, approval, master, tax, and account blockers before action. | Readiness primitives exist; convergence pending |
| Universal drilldown/drillback | Report → GL → JE → source → line/supporting document and back with preserved filters/context. | Trace contracts exist; universal linked UX pending |
| Dimension summary | Show governed Branch/Department/Cost Center and later approved dimensions, including provenance/defaulting. | Existing SI slice partial; missing masters explicit |
| Transaction/audit timeline | Present governed lifecycle events and supporting row audit as one source story. | Core evidence UI exists; richer timeline future |
| Customer/supplier insights | Show balances, aging, open documents, tax profiles, and certificate history at capture time. | Data dispersed; aggregation endpoint/panel missing |

## Missing Features

Missing means absent or not proven as a complete supported workflow; it does not automatically mean a defect.

- Banking transactions and reconciliation canonical workflows.
- Fixed-asset acquisition through disposal/impairment/transfer with FA-to-GL reconciliation.
- Customer and purchase returns plus debit/supplier debit memo coverage.
- Approval-instance execution and separation-of-duties UI evidence.
- Amortization, recurring journal, and revenue-recognition schedule execution.
- Statutory return/working-paper generators and CAS export artifacts not covered by current canonical data.
- Project, Location, and Functional Entity masters and policies.
- Payroll engine, statutory deductions, confidentiality, approval, payment, correction, and tests.
- Payment-method settlement mappings and method-specific references such as cheque or e-wallet identifiers.

## Future Enhancements

| Enhancement | Scope / Guardrail | Priority |
| --- | --- | --- |
| VAT/PT rate-version admin UI | Guided close-current/start-successor flow; database effective-date rules remain authoritative. | Medium |
| Snapshot hash verification and exact re-download | Recompute SHA-256 over frozen evidence and regenerate the exact recorded file. | Medium |
| TanStack Query adoption | Only high-revisit dashboards/registers/reports and shared reference reads when next touched; no mass refactor. | Medium |
| React Hook Form + Zod | Complex line-item forms only; client validation mirrors but never replaces server authority. | Medium |
| Shared company reference-data hooks | Extract within a touched domain cluster with zero behavior change and typed queries. | Medium |
| Large-form performance work | Profile 50+ line scenarios before memoization or state architecture changes. | Low |
| Zustand decision | Remove while unused; re-add only if cross-page state outgrows existing context. | Low |

## Deferred Work

The following wait until the Accounting Core Ready gate is cleared or an explicit task authorizes a narrow prerequisite:

- additional transaction workspace rollout;
- report pilots and broad report-workspace conversion;
- dashboards and management visualization expansion;
- client portal;
- AI/automation features;
- campaign, opportunity, and industry masters; and
- application-wide frontend state/form rewrites.

## Graduation Rule

When work is scheduled, `AI/AI_STATE.md` names one bounded task and its governing documents/tests. If implementation reveals a verified defect, add it only to the central findings register. When an enhancement ships and is validated, update the relevant governing specification and remove or revise its backlog row rather than appending session history.
