# PXL Accounting Core Readiness

Status: Active production-readiness phase
Milestone: **PXL Accounting Core Ready**
Last updated: 2026-07-13
Authority: User directive 2026-07-13; DEC-017; DEC-018

This document is the active production-readiness control plan for PXL's accounting core. The Sales Invoice Workspace and Report Workspace standards are documented. Do not create additional UI standards, roll out additional transaction workspaces, implement report pilots, or build dashboards until this accounting core readiness phase is explicitly cleared.

The objective is not feature expansion. The objective is to make sure every future transaction family can rely on one unified accounting, posting, tax, master-data, audit, and traceability engine.

The official posting-behavior specification is `PXL_ACCOUNTING_RULES_MATRIX.md`. This readiness document controls sequencing and production-readiness gaps; the matrix controls the accounting rules each future implementation must follow.

## 1. Current priority order

Workstreams must be handled in this order:

1. Accounting Engine.
2. Posting Engine.
3. Account Determination Engine.
4. Configuration-driven Tax Engine.
5. Master Data Governance.
6. CAS/BIR Readiness.
7. Transaction Rollout.
8. Report Rollout.
9. Dashboards.
10. Client Portal.
11. AI / Automation.

If a UI, report, or transaction rollout task conflicts with this order, pause the rollout and finish the relevant core readiness item first.

## 2. Hard stop rules

Until `PXL Accounting Core Ready` is achieved:

- Do not create new UI standards.
- Do not implement report pilots.
- Do not roll out the Transaction Workspace to additional document types.
- Do not create dashboards.
- Do not build new transaction pages unless required to fix a core accounting/tax defect.
- Do not hardcode tax behavior into page code.
- Do not add transaction dropdowns backed by static arrays when governed master data is required.
- Do not rely on visual read-only states as accounting controls.

Allowed work:

- accounting rules matrix maintenance;
- posting engine hardening;
- account determination architecture;
- tax engine architecture and governed tax configuration;
- master-data governance;
- CAS/BIR readiness;
- lifecycle, period, reversal, numbering, audit, traceability, and immutability controls;
- accounting/tax tests;
- documentation required to keep behavior and readiness accurate.

## 3. Trusted baseline and excluded drafts

The trusted baseline includes the deployed/shared posting primitives delivered through:

- `20260710000003_posting_engine_preview_trace.sql`
- `20260711000001_posting_engine_completion.sql`
- `20260712000003_posting_runtime_repairs.sql`
- `20260712000004_cas_numbering_void_evidence.sql`

The following files are intentionally excluded from readiness conclusions until explicitly owned and fixed:

- `supabase/migrations/20260710000004_atc_document_date_versioning.sql`
- `supabase/migrations/20260710000005_cas_numbering_void_dat_controls.sql`
- `supabase/tests/027_cas_end_to_end_controls_test.sql`

Those held-out drafts are not the production baseline.

## 4. Accounting Engine review

### 4.1 Current engine strengths

The current accounting engine has a strong foundation:

- registry-backed source resolution through `ref_posting_source_types`;
- source locking before posting through `fn_begin_source_posting`;
- governed journal creation through `fn_create_posted_journal_entry`;
- shared line insertion through `fn_add_posting_line`;
- deferred balance enforcement on journal entries and lines;
- postable-account enforcement through `fn_require_postable_account`;
- open-period enforcement through `fn_require_open_fiscal_period`;
- source-to-journal integrity through `fn_assert_posting_source`, `fn_assert_source_journal_link`, and journal source triggers;
- exact GL preview through rollback-based `fn_preview_gl_impact`;
- exact reversal primitives through `fn_reverse_posted_journal_entry`, `fn_reverse_je`, and `fn_bt_reverse_je`;
- tax counter-row support through `fn_reverse_tax_detail_entries`;
- posting event capture through `fn_record_posting_event`;
- row-level immutability guards for posted/approved source documents;
- multi-company membership checks in SECURITY DEFINER posting paths;
- branch-scoped document numbering for governed document types.

Core SI/OR/VB/PV are the strongest current flows. Secondary posting flows have been wrapped or partially aligned but still need capability-by-capability confirmation before expansion.

### 4.2 Required universal accounting lifecycle

Every accounting document type must declare which lifecycle states it supports:

- `draft`
- `approved`
- `posted`
- `reversed`
- `void`
- `cancelled`

Not every document needs every state. Non-posting documents may not post. But every transaction type must explicitly document:

- allowed starting state;
- approval requirement;
- posting trigger;
- reversible or voidable states;
- cancellation semantics;
- whether reversal creates an exact opposite JE;
- whether tax detail gets counter-rows;
- whether numbering evidence is consumed;
- whether posted rows become immutable;
- what audit event is written.

### 4.3 Accounting engine capability matrix

| Capability | Current baseline | Gap | Severity | Required before expansion |
| --- | --- | --- | --- | --- |
| Source registry | `ref_posting_source_types` exists and governs many source types. | Every future transaction must be registered before posting is implemented. | Critical | Add registration checklist to every transaction implementation plan. |
| Source locking | `fn_begin_source_posting` locks saved sources. | Atomic create-and-post forms and secondary wrappers must be verified individually. | High | No posting RPC without source lock or controlled create/post transaction boundary. |
| Journal creation | `fn_create_posted_journal_entry` centralizes source assertion and open period check. | Some historical writers still use compatibility wrappers or direct patterns. | High | All new posting must use shared create/add/finalize primitives. |
| Journal balancing | Deferred balance guards and finalization exist. | Tolerance policy must be standardized across posting, tax, and reports. | High | Define one accounting tolerance policy and test it. |
| Period locking | Open-period function exists. | Period close process, adjusted/unadjusted/post-closing modes, and closing entries remain open. | High | Complete PXL-DA-014 before financial statement/report rollout. |
| Numbering | Branch-scoped numbering and CAS evidence exist for governed documents. | Preflight coverage still not universal; held-out CAS drafts remain excluded from trusted replay. | High | Complete PXL-AUD-016. |
| Source-to-JE trace | Source assertion/link functions and trace RPCs exist. | Every future document must supply route/drill metadata and source line trace. | High | Add trace checklist to transaction readiness. |
| JE-to-source trace | `fn_get_accounting_trace` and source pages exist. | Some secondary source pages need workspace-level drillback/audit UX later. | Medium | Core engine must expose data before UI rollout. |
| Reversal | Shared exact reversal exists. | Document-specific cancel/void paths are inconsistent and tax counter-row coverage must be verified. | High | Document each source type's reversal/void/cancel behavior. |
| Void evidence | CAS void evidence, exact exported-byte hashing, CRLF DAT artifacts, source/GL-reconciled books exports, and audit-package snapshots exist. | Operational/legal CAS certification validation remains outside the code-control finding. | Low | Keep future CAS surfaces on the same snapshot/hash/reconciliation model. |
| Approval | SI/VB approval readiness exists; SoD exists when workflow configured. | Universal approval semantics and approval invalidation policies need clear per-document contracts. | Medium | Document approval requirements per transaction type. |
| Immutable posting | Generic status immutability guards exist. | New tables must be added to guards at creation time. | Critical | No new transactional table without immutability classification. |
| GL account determination | Control accounts are in `company_accounting_config`; line accounts often come from item/user selection. | Full account determination engine is not complete. | High | Define configurable account rules before hiding manual GL choices. |
| Dimensions | Branch/department/cost center JE-line guards exist. | Header/line dimension capture and defaulting are incomplete. | Medium | Define dimension master/rules before broader transaction rollout. |
| Multi-company | RLS and membership checks exist. | Cross-company mismatch tests must accompany each new source type. | Critical | Every posting test must include wrong-company negative coverage. |
| Multi-branch | Branch is a reporting dimension; numbering is branch-scoped. | Inter-branch behavior and branch attribution need per-document policy. | High | Define branch posting policy for each transaction class. |
| Audit trail | Row audit and some posting events exist. | Semantic `transaction_events` lifecycle log is still open. | High | Complete PXL-DA-016 or equivalent before declaring core ready. |

### 4.4 Accounting engine gaps to resolve first

| Gap ID | Gap | Existing reference | Severity | Next action |
| --- | --- | --- | --- | --- |
| ACR-001 | Complete posting lifecycle contract for every accounting document. | PXL-AUD-050, PXL-DA-016 | High | Add source-type lifecycle checklist and semantic event requirements. |
| ACR-002 | Finish financial statement readiness: JE classifications, close, retained earnings, FS mappings. | PXL-AUD-013, PXL-DA-014 | High | Implement closing/TB/FS accounting model before report rollout. |
| ACR-003 | Standardize reversal, void, cancellation, and tax counter-row behavior across all source types. | PXL-DA-004, PXL-DA-019 | High | Review every posting/cancel/void RPC and document exact behavior. |
| ACR-004 | Finish universal numbering readiness; preserve CAS evidence model. | PXL-AUD-016, PXL-DA-019 | High | Complete preflight coverage; DA-019 CAS evidence package is closed. |
| ACR-005 | Finish semantic lifecycle event log. | PXL-DA-016 | High | Implement `transaction_events` or equivalent governed event stream. |
| ACR-006 | Define account determination engine. | Product backlog account-determination row | High | Replace page/manual account choice with governed posting rules where applicable. |
| ACR-007 | Finish server-side heavy report and reconciliation foundation. | PXL-DA-018, DEC-016 | Medium | Server-side report computation after core posting/tax rules stabilize. |

## 5. Posting Engine review

The Posting Engine is the executable layer that turns an approved business event into balanced, traceable accounting. It must consume the Accounting Rules Matrix and Account Determination Engine rather than embedding transaction-specific account choices inside modules.

Required Posting Engine capabilities:

- source registration for every posting transaction;
- source lock before posting reads or writes;
- lifecycle-state validation;
- approval-state validation;
- fiscal-period validation;
- branch/company ownership validation;
- number-series validation where applicable;
- account determination call before journal creation;
- tax engine call before tax ledger creation;
- balanced journal generation;
- tax detail creation where applicable;
- inventory/cost/fixed-asset side effects where applicable;
- source-to-journal and journal-to-source traceability;
- exact reversal or controlled counter-row behavior;
- semantic audit event creation;
- immutable posted source rows and journal lines.

Posting Engine gaps:

| Gap ID | Gap | Severity | Next action |
| --- | --- | --- | --- |
| POST-001 | Not every source type has a documented Accounting Rules Matrix row with lifecycle, accounts, taxes, reversal, void, cancel, and test requirements. | Critical | Maintain `PXL_ACCOUNTING_RULES_MATRIX.md` before rollout. |
| POST-002 | Compatibility-wrapped secondary posters need verification against the shared create/add/finalize protocol. | High | Review each wrapper before expanding UI. |
| POST-003 | Settlement totals can still be client/header-driven in some flows. | ~~High~~ PV/OR done (session 77) | DONE for PV/OR — `20260713000003` derives header `total_amount`/`total_ewt`/`total_cwt` from lines and rejects divergence at posting (AUD-038/048, test 034). Apply the same pattern to any future settlement flow. |
| POST-004 | Posting tolerance policy is not fully standardized across GL, tax, and reports. | High | Define one tolerance policy and test it. |

## 6. Account Determination Engine design

The Account Determination Engine resolves GL accounts from configuration. Normal users should not pick GL accounts on operational transactions unless the override is explicitly role-gated, reason-coded, and audited.

Default hierarchy:

1. Company.
2. Tax Profile.
3. Item Group.
4. Item.
5. Customer / Supplier.
6. Document Type.
7. Override.

Accounts to resolve include:

- customer receivable account;
- supplier payable account;
- revenue account;
- expense account;
- inventory account;
- COGS account;
- VAT accounts;
- EWT/CWT/FWT accounts;
- cash and bank accounts;
- foreign exchange accounts;
- rounding accounts;
- gain/loss accounts;
- fixed asset and depreciation accounts;
- payroll expense/liability accounts;
- retained earnings and closing accounts.

Account Determination gaps:

| Gap ID | Gap | Severity | Next action |
| --- | --- | --- | --- |
| ADE-001 | Operational lines can still rely on user-selected revenue/expense accounts. | High | Define configurable posting rules before hiding manual GL choice. |
| ADE-002 | Item group, item, party, tax profile, document type, and override precedence is not implemented as one engine. | High | Design and test account resolution service/RPC after matrix signoff. |
| ADE-003 | Override governance is incomplete. | Medium | Require permission, reason, audit event, and GL Impact disclosure. |

## 7. Configuration-driven Tax Engine design

### 7.1 Core rule

The PXL Tax Engine must be configuration-driven. Philippine tax rules may be seeded as configuration, but they must not be hardcoded as application behavior.

Tax computation must depend on:

- company tax profile;
- branch or registration context where applicable;
- customer/supplier tax profile;
- item/service tax profile;
- document type;
- transaction direction;
- transaction date;
- effective tax rule version;
- taxable base policy;
- posting policy;
- exemption/zero-rated/non-VAT classification;
- withholding agent status;
- ATC/rate version effective on the document date;
- controlled variance policy;
- filing/reporting status.

### 7.2 Required configurable tax model

The target model should include governed configuration for:

- tax regimes, such as VAT, Percentage Tax, EWT, CWT, FWT;
- tax components, such as output VAT, input VAT, EWT payable, CWT receivable, FWT payable;
- tax codes and rates with effective dates;
- ATC versions under the same official code;
- taxable base formulas;
- document-type tax applicability;
- counterparty tax profiles;
- item/service tax profiles;
- withholding profiles;
- tax posting accounts;
- tax report mappings;
- filing and snapshot rules;
- variance tolerances and allowed variance reasons.

### 7.3 Current tax baseline

Current strengths:

- `tax_detail_entries` acts as the posted tax ledger.
- VAT registration gates exist across major VAT-bearing document families.
- VAT amount authority is server-side for audited VAT flows.
- `fn_add_tax_detail` centralizes tax detail insertion in the shared posting engine.
- VAT and WHT reconciliation RPCs exist.
- VAT, WHT, 2307, and snapshot flows have significant hardening.
- PV EWT, OR CWT, and CV EWT now validate base/rate with controlled variance.

Current architectural gaps:

- ~~ATC validation still needs document-date effective versioning in the trusted baseline.~~ DONE (session 77, `20260713000002`): validators/callers evaluate the ATC window as of the document date.
- ~~ATC code uniqueness/versioning is not production-ready.~~ DONE (session 77, `20260713000002`): version-aware uniqueness, overlap/successor guard, and `fn_atc_version_asof` resolver.
- EWT/CWT/FWT/Percentage Tax are not yet one unified configurable tax engine.
- ~~Company withholding profile flags do not consistently gate transaction surfaces.~~ DONE (session 84, `20260713000011`): active non-EWT profiles gate VB/PV/CV EWT payable, EWT returns, and QAP exports.
- ~~TWA auto-EWT is not operationally governed.~~ DONE (session 84, `20260713000011`): supplier-subject source-basis VB lines default to WC158 1% goods or WC160 2% services when the TWA profile is active.
- ~~Withholding basis policy is not configurable for payment vs accrual.~~ DONE (session 83, `20260713000010`): company-level AP EWT recognition policy defaults to source/accrual at VB and keeps explicit payment-basis compatibility.
- Cash purchases, advances, and down-payments have incomplete withholding support.
- Percentage Tax exists as compliance/reporting structures but is not fully integrated as a generic posting tax engine.
- FWT return structures exist, but no broad posted FWT tax-detail flow is production-ready.
- Some tax behavior is still expressed through document-specific SQL/RPC logic rather than a reusable tax-rule evaluator.

### 7.4 Tax engine readiness matrix

| Tax area | Current state | Gap | Severity | Required before core ready |
| --- | --- | --- | --- | --- |
| VAT | Strongest tax lane; server-computed/gated for major flows. | Effective-date governance and report rollout still need core stability. | High | Keep VAT as reference implementation for tax engine contracts. |
| Percentage Tax | Compliance pages/tables exist. | Needs configurable applicability, posting/report source, reconciliation, and filing rules. | High | Define PT tax-rule model before expansion. |
| EWT | PV/CV validation, 2307 hardening, document-date ATC versioning, controlled remittance flow, QAP multi-ATC reconciliation, AP source-basis EWT policy, and withholding profile gates exist. | Cash purchases/advances, 2307 month layout, duplicate withholding masters, and received-2307 lifecycle remain incomplete. | High | Complete PXL-AUD-043/040/044/047. |
| CWT | OR CWT detail and customer defaults exist. | 2307 received lifecycle, over-claim guard, stale/reversal handling incomplete. | High | Complete PXL-AUD-047 and customer CWT default-flow tests. |
| FWT | Tables/returns exist. | No mature posted FWT tax-detail engine. | High | Define FWT tax engine path before enabling FWT filing readiness. |
| Future BIR changes | Existing tables are partly configurable. | Need versioned tax-rule/rate model, not code edits per rate change. | Critical | Add effective-dated rule resolution by document date. |

### 7.5 Tax gaps to resolve first

| Gap ID | Gap | Existing reference | Severity | Next action |
| --- | --- | --- | --- | --- |
| TAX-001 | ATC effective window must use document date, not current date. | PXL-AUD-035 | ~~High~~ Resolved (session 77) | DONE — `20260713000002` threads the document date through the PV/OR/CV EWT-CWT validators and all callers; validators evaluate the ATC window as of the document date. Test 033. |
| TAX-002 | ATC versions must support rate changes under one official code. | PXL-AUD-036 | ~~High~~ Resolved (session 77) | DONE — `20260713000002` adds version-aware uniqueness `(code, tax_category, effective_from)`, overlap/successor guard, `fn_atc_version_asof` resolver, and effective_from immutability once used. Test 033. |
| TAX-003 | SAWT/QAP reconciliation and multi-ATC supplier scenarios remain incomplete. | PXL-DA-009 | ~~Critical~~ Resolved (session 79) | DONE — `20260713000006` adds supplier+ATC+nature+rate QAP rows, Form 2307 tie-out evidence, immutable snapshot-backed downloads, and per-report reconciliation blocking. Test 016. |
| TAX-004 | Controlled remittance/application flow is missing. | PXL-AUD-041 | ~~High~~ Resolved (session 78) | DONE — `20260713000005` adds governed `withholding_remittances`/WHTREM posting, excludes remittance JEs from WHT reconciliation variance, and derives `remitted_prior`. Test 036. |
| TAX-005 | Withholding basis policy is not configurable. | PXL-AUD-037 | ~~High~~ Resolved (session 83) | DONE — `20260713000010` adds company-level AP EWT recognition policy, defaults to source/accrual at VB, preserves payment-basis compatibility, and blocks duplicate PV EWT for source-accrued bills. Test 037. |
| TAX-006 | PV/OR header totals must be server-recomputed from lines. | PXL-AUD-038, PXL-AUD-048 | ~~High~~ Resolved (session 77) | DONE — `20260713000003` derives OR/PV cash and withholding totals from persisted lines and blocks divergent header totals. Test 034. |
| TAX-007 | Over-apply guards must account for CM/VC applications. | PXL-AUD-039 | ~~High~~ Resolved (session 77) | DONE — `20260713000004` nets AR credit memos and AP vendor-credit applications in over-apply guards. Test 035. |
| TAX-008 | Withholding profile gating is incomplete. | PXL-AUD-042 | ~~High~~ Resolved (session 84) | DONE — `20260713000011` gates explicit non-EWT profiles across AP-side EWT payable, EWT returns, and QAP exports, and implements TWA goods/services auto-EWT defaults. Test 038. |
| TAX-009 | Cash purchases and advances/down-payments withholding are incomplete. | PXL-AUD-043 | High | Define document policies before implementation. |
| TAX-010 | 2307 received claim lifecycle is not governed. | PXL-AUD-047 | Medium | Add validation, over-claim guard, stale/reversal handling. |

## 8. Master Data Governance review

### 8.1 Rule

Every dropdown or selector used by transactions must come from governed master data. The transaction form consumes master data; it must not define it.

Required properties for governed master data:

- company scope where applicable;
- active/inactive state;
- effective dates where values affect accounting or tax;
- immutable or versioned behavior after use by posted transactions;
- RLS and role permissions;
- audit trail;
- setup UI;
- API/RPC validation where used in posting;
- foreign keys from transaction tables;
- report and drilldown semantics.

### 8.2 Existing governed master data

Current governed masters include:

- company;
- branch;
- fiscal year and fiscal period;
- chart of accounts;
- GL posting configuration;
- number series;
- customer;
- supplier;
- item/service;
- unit of measure;
- item category;
- VAT codes;
- ATC codes, with incomplete versioning;
- payment terms;
- department;
- cost center;
- warehouse;
- bank account and payment modes in banking contexts.

### 8.3 Missing or incomplete master data

| Master data | Current state | Required ownership | Severity | Notes |
| --- | --- | --- | --- | --- |
| Salesperson | Missing as governed transaction master. | Sales/AR master data. | Medium | Required for Sales Context; should not be static text. |
| Sales Territory | Missing/incomplete. | Sales/Customer master data. | Medium | Needed for customer segmentation/reporting. |
| Price Level / Price List | Missing/incomplete. | Sales pricing master data. | Medium | Must not be hardcoded into transactions. |
| Industry | Missing/incomplete. | Customer/vendor classification master. | Low | Useful for Related Party/reporting. |
| Campaign | Missing; future marketing module. | Marketing module. | Low | Do not add to transaction header until module exists. |
| Opportunity | Missing; future CRM/marketing module. | CRM/marketing module. | Low | Same as campaign. |
| Delivery Terms | Missing/incomplete. | Sales/Purchasing logistics master. | Medium | Should feed SO/PO/DR/SI/VB context. |
| Payment Terms | Exists. | Master Data. | Low | Needs consistent use across all transaction types. |
| Header Dimensions | Incomplete. | Accounting dimensions. | Medium | Must link to branch/department/cost center/project/location rules. |
| Line Dimensions | Partially governed for JE lines. | Accounting dimensions. | Medium | Transaction lines need consistent capture/defaulting. |
| Project | Missing/incomplete as accounting dimension. | Project/dimension master. | Medium | Required for workspace Sales Context and JE dimensions. |
| Location | Missing/incomplete as standard dimension. | Dimension/Inventory master. | Medium | Needs distinction from branch/warehouse. |
| Tax Profiles | Incomplete. | Tax master data. | High | Company/counterparty/item/document tax behavior should resolve through profiles. |
| Withholding Profiles | Incomplete. | Tax master data. | High | Must govern EWT/CWT/FWT applicability, ATC, basis, and variance rules. |
| Account Determination Rules | Incomplete. | Accounting setup. | High | Needed before normal users stop choosing GL accounts. |

## 9. Transaction readiness review

Do not build these transactions now. This section records accounting requirements and missing capabilities before rollout.

| Transaction family | Current readiness | Accounting requirements before rollout | Missing capabilities |
| --- | --- | --- | --- |
| Official Receipt | Strong core posting exists. | Lifecycle contract, CWT profile defaults, over-apply guard including CMs, cash total recomputation, reversal/bounce audit. | PXL-AUD-038, PXL-AUD-039, PXL-AUD-045, PXL-AUD-046. |
| Vendor Bill | Strong core posting exists, including source/accrual EWT policy and net AP posting when supplier EWT applies. | Supplier withholding profile breadth, RR linkage policy, expense account determination. | PXL-AUD-008, ACR-006. |
| Payment Voucher | Strong core posting exists, including line-derived totals, VC-aware over-apply, controlled remittance linkage, duplicate-withholding block for source-accrued VBs, and explicit non-EWT profile gates. | Non-VB/down-payment withholding policies. | PXL-AUD-043. |
| Credit Memo | Posting exists. | CM application trace, OR over-apply interaction, reversal/void semantics, VAT/tax counter-row confirmation. | PXL-AUD-039, ACR-003. |
| Debit Memo | Posting exists. | Consistent numbering/readiness, application semantics, reversal/void behavior, tax trace. | ACR-003, ACR-004. |
| Sales Order | Non-posting operational document. | Clear non-posting status lifecycle, downstream source trace to DR/SI, reserved inventory policy. | Source-chain readiness and master-data defaults. |
| Purchase Order | Non-posting operational document. | Approval/cancel lifecycle, downstream source trace to RR/VB, commitment policy if any. | Source-chain readiness and governance. |
| Delivery Receipt | Operational/inventory document. | Inventory issue policy, cost recognition timing, SI linkage, reversal/cancel. | Inventory-to-GL policy and source chain trace. |
| Journal Entry | Posting exists for manual/recurring. | JE classifications, adjusted/unadjusted/closing entries, retained earnings, SoD/manual gating. | PXL-DA-014 and manual/system discriminator residue. |
| Inventory Transactions | Posting exists for adjustments/transfers/issues/counts. | Costing policy, inventory-to-GL reconciliation, branch/warehouse/dimension policy, exact reversal. | PXL-DA-018, inventory reconciliation, ACR-003. |
| Banking | Treasury posting exists. | Bank reconciliation integration, cancelled/reversed payment semantics, check lifecycle, cash position consistency. | Bank reconciliation standard and lifecycle event coverage. |
| Fixed Assets | Posting exists for acquisition/depreciation/disposal/impairment. | FA-to-GL reconciliation, book/tax depreciation policy, asset lifecycle audit, transfer/dimension treatment. | FA reconciliation and report readiness. |
| Payroll | Planned. | Payroll calendar, employee master, payroll liabilities, statutory deductions, withholding tax, approval, payment, reversal/correction. | Payroll engine, tax profiles, payroll confidentiality/security, full test matrix. |

## 10. Production readiness matrix

| Priority | Gap | Area | Why it matters | Existing reference |
| --- | --- | --- | --- | --- |
| ~~Critical~~ Done (session 79) | SAWT/QAP and multi-ATC withholding reconciliation now preserve supplier+ATC+nature+rate rows and 2307 tie-out evidence. | Tax Engine | Compliance filings now have immutable reconciliation-backed export evidence. | PXL-DA-009 |
| ~~Critical~~ Done (session 82) | CAS evidence now covers exact bytes, DAT artifacts, source/GL-reconciled books exports, and audit-package snapshots. | Accounting/Compliance | BIR CAS evidence now has a server-attested package; legal/operational certification remains a rollout task. | PXL-DA-019 |
| ~~Critical~~ ATC lane done (session 77) | ATC rate changes now resolve by document date and version (`20260713000002`). A fully generic configurable rule engine across all regimes (PT/FWT) is still future work. | Tax Engine | Rates can be wrong for historical/future documents. | TAX-001, TAX-002 (done); generic engine under TAX-006-style work |
| Critical | New transaction tables can bypass core controls if not registered/classified. | Accounting Engine | Source trace, immutability, and audit may fail. | ACR-001, ACR-003 |
| Critical | New posting behavior can diverge without the Accounting Rules Matrix. | Accounting/Posting Engine | Future modules can invent inconsistent posting logic. | `PXL_ACCOUNTING_RULES_MATRIX.md` |
| High | Financial statement/close model incomplete. | Accounting Engine | TB/FS can be misleading. | PXL-AUD-013, PXL-DA-014 |
| High | Account determination engine incomplete. | Accounting Engine | Users may pick wrong GL accounts; rollout cannot scale. | ACR-006 |
| High | Withholding profile/configuration incomplete. | Tax/Master Data | Duplicate/legacy withholding master data still needs consolidation. | PXL-AUD-008, PXL-AUD-044 |
| High | Remittance/application flow missing. | Tax Engine | Filed EWT/CWT workflows and reconciliations remain blocked. | PXL-AUD-041 |
| ~~High~~ PV/OR done (session 77) | Settlement header totals are client-driven. | Accounting/Tax | GL can diverge from line/subledger/tax rows. | PXL-AUD-038, PXL-AUD-048 (done for PV/OR, `20260713000003`) |
| ~~High~~ Done (session 77) | CM/VC-aware over-apply guards incomplete. | Subledger | AR/AP balances and withholding can be overstated. | PXL-AUD-039 (done, `20260713000004`) |
| High | Universal number-series preflight incomplete. | Posting/Compliance | Users can reach late numbering errors; CAS evidence gaps possible. | PXL-AUD-016 |
| High | Semantic lifecycle event log incomplete. | Audit | Audit timeline is not a single governed lifecycle stream. | PXL-DA-016 |
| Medium | Heavy reports need server-side computation/pagination/materialization. | Reporting Core | Large reports may be slow or unsafe. | PXL-DA-018 |
| Medium | Dimension capture/defaulting incomplete. | Accounting/Master Data | Branch/department/cost-center/project reporting can be inconsistent. | PXL-DA-017 residue |
| Medium | 2307 received lifecycle incomplete. | Tax/Compliance | CWT claims can be overclaimed or stale. | PXL-AUD-047 |
| Low | Campaign/opportunity/industry masters are absent. | Master Data | Useful context, but not blocking accounting core unless required by a transaction. | Master data gap |

## 11. Minimum definition of PXL Accounting Core Ready

PXL Accounting Core is ready only when:

1. All Critical accounting/tax/compliance findings are `Retested Passed`.
2. High findings that affect posting, tax, traceability, period close, numbering, or report correctness are either fixed or explicitly accepted with rationale.
3. Every posting source type uses or is compatibility-wrapped by the shared posting protocol.
4. Every posting source type has a row in `PXL_ACCOUNTING_RULES_MATRIX.md`.
5. Every posting source type has documented lifecycle, reversal, void/cancel, audit, and immutability behavior.
6. Account determination resolves operational posting accounts through configuration.
7. The Tax Engine has a configuration-driven rule model for VAT, Percentage Tax, EWT, CWT, FWT, and future effective-date changes.
8. ATC/tax rates resolve by document date and version.
9. Withholding profiles and company tax profiles actively govern transaction behavior.
10. Settlement totals are server-derived from line/source data.
11. Period close and financial statement readiness are implemented and tested.
12. Numbering and CAS evidence are complete enough for production use.
13. Master-data gaps required by transaction posting are modeled with governed tables, relationships, permissions, and maintenance UI.
14. Core source-to-JE-to-GL-to-report trace and drillback contracts are verified for implemented posting families.
15. Tests cover positive and negative accounting/tax scenarios, including cross-company denial and locked-period denial.

## 12. Recommended implementation sequence

Follow this sequence unless a blocking defect requires escalation:

1. Accounting Engine.
2. Posting Engine.
3. Account Determination Engine.
4. Configuration-driven Tax Engine.
5. Master Data Governance.
6. CAS/BIR Readiness.
7. Transaction Rollout.
8. Report Rollout.
9. Dashboards.
10. Client Portal.
11. AI / Automation.

Current concrete lane inside this sequence:

1. Maintain `PXL_ACCOUNTING_RULES_MATRIX.md` as the accounting behavior source of truth.
2. Continue the remaining high-priority accounting/tax lane: AUD-042/043, then AUD-040, and AUD-044..047/049.
3. ~~Complete ATC document-date versioning safely, replacing the held-out draft rather than adopting it as-is.~~ DONE (session 77, `20260713000002`, test 033; held-out draft `20260710000004` stays excluded).
4. ~~Complete controlled EWT remittance/CWT application flow.~~ DONE (session 78, `20260713000005`, test 036).
5. ~~Decide and encode withholding basis policy.~~ DONE (session 83, `20260713000010`, test 037).
6. ~~Server-recompute OR/PV cash totals from lines.~~ DONE (session 77, `20260713000003`, test 034).
7. ~~Add CM/VC-aware over-apply guards.~~ DONE (session 77, `20260713000004`, test 035).
8. Complete financial statement/close readiness.
9. Complete semantic transaction event log.
10. Define and implement the configuration-driven tax-rule model.
11. Complete master-data governance for required transaction dependencies.
12. Reassess every transaction type against the readiness table.
13. Only then resume transaction workspace rollout and report pilot implementation.

## 13. Documentation maintenance

Every accounting-core session must update, when applicable:

- this document;
- `PXL_ACCOUNTING_RULES_MATRIX.md`;
- `PXL_END_TO_END_AUDIT_FINDINGS.md`;
- `PXL_TRANSACTION_MATRIX.md`;
- `PXL_ACCOUNTING_RULES.md`;
- `PXL_ACCOUNTING_TEST_BOOK.md`;
- `AI/AI_DECISIONS.md`;
- `AI/AI_STATE.md`;
- `AI/AI_HANDOFF.md`;
- `AI/AI_WORK_QUEUE.md`.

Do not add cosmetic audit findings. Record defects only for accounting, tax, posting, reconciliation, security, data-integrity, immutability, traceability, or production-readiness issues.
