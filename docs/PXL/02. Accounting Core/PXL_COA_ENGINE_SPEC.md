# PXL COA Engine Specification

**Status:** Frozen — Approved (authoritative implementation contract)
**Authority:** Tier 2 domain specification for the Chart-of-Accounts / account-resolution engine (COA Engine, certifiable engine #19)
**Owner / Domain:** Accounting Core
**Applies To:** Account identity, hierarchy, lifecycle, posting eligibility, posting controls, financial-statement classification, and account resolution
**Read When:** Implementing or certifying account resolution, posting-account selection, COA lifecycle, change policy, or FS mapping
**Do Not Read For:** Tax computation/interpretation, report presentation/layout, budgeting, or analytics — those belong to their own engines
**Last Reviewed:** 2026-07-24 (frozen after approved clarifications)
**Relationship:** Implements the resolution hierarchy stated in [PXL_ACCOUNTING_RULES.md](PXL_ACCOUNTING_RULES.md); consumes `chart_of_accounts` (as enriched by MDP-04) and `company_accounting_config`; certified under the engine half of the Production Certification Program, `docs/PXL/00. Governance/PXL_HOW_WE_WORK.md` §6 (quality bars); status in [PXL_CERTIFICATION_MATRIX.md](../13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md). Supersedes no existing document.

> **Provenance.** No prior "COA Engine Architecture Version 2" document existed in the repository; the primitives (`ref_mapping_key`, `account_mapping`, `fn_resolve_account`, `fs_structure`, `account_fs_map`) did not exist. This specification was authored, reviewed with clarifications, and frozen on 2026-07-24. It is now the authoritative contract; implementation follows it and does not reinterpret it.

---

## 1. Authority Boundaries (normative)

The COA Engine **is the sole authority** for: account identity; account hierarchy; account lifecycle; posting eligibility; posting controls; financial-statement classification; account resolution; historical account classification; effective-dated account metadata.

The COA Engine **is not the authority** for: taxpayer interpretation; tax computation; VAT logic; EWT/CWT logic; business-tax rules; reporting presentation; budgeting; analytics; financial-report layouts. Those belong to their respective engines.

The COA Engine defines **what an account is**. Other engines decide **how** that account is interpreted or presented. Consumers of the shared contract are the Posting Engine, Tax Engine, Reporting / Financial Statements, Migration / Import, Configuration, and future Analytics.

---

## 2. The Five Frozen Contracts

1. Resolver Contract (§4)
2. Posting Control Contract (§5)
3. COA Governance / Lifecycle (§6)
4. Change Policy Enforcement (§7)
5. Financial Statement Registry (§8)

These five are frozen. No redesign, scope expansion, or speculative functionality is permitted; only defects may reopen them.

---

## 3. Scope, Delivery Phases, and Authority Transition

### 3.1 Bounded, additive-first delivery
Phase A adds all five contracts as **new, non-breaking** structures beside the existing schema, with compatibility views, and **rewires no posting consumer**. Migration of consumers and removal of hardcoded literals are Phase B/C.

### 3.2 Authority transition (normative — never two writable authorities)
- **Phase A:** `company_accounting_config` **remains the operational authority**. `account_mapping` is additively seeded from it and kept in sync; `fn_resolve_account` is equivalence-tested to return exactly today's configured accounts; existing posting behavior is unchanged. `account_mapping` is **not independently user-writable** in Phase A — it is a derived projection of the config, so there is exactly one writable configuration source.
- **Phase B:** `account_mapping` + `fn_resolve_account` become authoritative for each migrated consumer.
- **After complete migration:** `company_accounting_config` becomes a compatibility **projection/view only** and is no longer a second writable source of truth.

### 3.3 Phase A deliverables
`ref_mapping_key`; `account_mapping`; `fn_resolve_account()`; compatibility view(s); current-config seed/backfill + sync; lifecycle framework; change-policy framework; FS-registry framework; the PXL Standard COA canonical fixture (test/certification fixture only); certification tests; equivalence tests.

### 3.4 Phase A explicit exclusions
Do not rewire the ~41 posting consumers; do not modify Posting Engine behavior; do not change MDP-05 provisioning; do not migrate hardcoded posting logic; no Tax, Reporting, Budgeting, or Analytics work.

---

## 4. Contract 1 — Resolver Contract

### 4.1 `ref_mapping_key` — semantic key catalog
Seed-governed vocabulary of the semantic account references the system resolves. A key is added only by migration (fixed vocabulary; not a runtime write). Columns: `key_code` (PK), `description`, `expected_account_type` (nullable invariant: `asset|liability|equity|revenue|expense`), `is_active`. Phase A seeds exactly the keys that have a current `company_accounting_config` source (§4.6); further keys are added by migration as consumers adopt them.

### 4.2 `account_mapping` — company-scoped, effective-dated bindings with coexisting qualifiers
Binds a `ref_mapping_key` to a `chart_of_accounts` account. **Qualifiers are independent optional columns that may coexist on one mapping** — a mapping is the logical AND of its non-null qualifiers; a null qualifier matches anything. Qualifier columns (each nullable): `branch_id`, `document_type`, `party_id`, `item_id`, `item_group_id`, `tax_profile_id`. Plus `company_id`, `key_code`, `account_id`, `effective_from`, `effective_to`, `reason_code`, `source` (`config_sync|manual|migration`), audit columns.

**Uniqueness:** at most one *current* (open, `effective_to IS NULL`) binding per `(company_id, key_code, branch_id, document_type, party_id, item_id, item_group_id, tax_profile_id)` treating nulls as equal (partial unique index `NULLS NOT DISTINCT`).

### 4.3 Deterministic specificity (normative)
Given a resolution context, a mapping **matches** iff every non-null qualifier equals the corresponding context value. Among matching mappings, specificity is the **lexicographic vector** over qualifier dimensions in this fixed priority order (most significant first):

`document_type > party > item > item_group > tax_profile > branch`

This encodes the governed hierarchy of [PXL_ACCOUNTING_RULES.md](PXL_ACCOUNTING_RULES.md) read most-specific-first (Override → Document Type → Customer/Supplier → Item → Item Group → Tax Profile → Company), with **branch-specific outranking the company default** as the lowest-priority tiebreaker. A binding that constrains no qualifier is the company default (all-zero vector).

### 4.4 Resolution algorithm (`fn_resolve_account(company, key_code, context, as_of)`)
1. **Key validity:** unknown or inactive `key_code` ⇒ raise (fail-closed).
2. **Authorized transaction-level override:** if `context.override_account_id` is present, it wins outright **only if** `context.override_authorized` is true; an unauthorized override ⇒ raise. (Overrides are role-gated, reason-coded, audited, GL-visible per the accounting rules; they are supplied at transaction time, not stored as bindings.)
3. **Candidate set:** all `account_mapping` rows for `(company, key_code)` that are effective at `as_of` and whose non-null qualifiers all match `context`.
4. **Winner:** the unique candidate with the greatest specificity vector.
5. **Ambiguity:** if two or more candidates tie at the greatest specificity, **raise** — the resolver never silently chooses between equally valid candidates.
6. **No match:** if the candidate set is empty, **raise** (fail-closed — posting cannot proceed without an explicit mapping).
7. **Account validation:** the resolved account must exist, be in the same company, satisfy `expected_account_type` (if set), be `is_postable`, and be lifecycle `active` — otherwise raise.

Every resolution is deterministic, reproducible, and independently testable. `SECURITY DEFINER`, `SET search_path = public`, membership-safe, side-effect-free (safe inside posting).

### 4.5 Effective-date selection
Only mappings with `effective_from <= as_of` and (`effective_to IS NULL` or `as_of <= effective_to`) are candidates. The partial unique index guarantees one open binding per exact scope; any residual overlap across effective windows is caught by the §4.4-5 ambiguity rule.

### 4.6 Compatibility view + config sync
- `vw_company_accounting_config` (`security_invoker`) reconstructs the legacy `company_accounting_config` shape from the current company-scope `account_mapping` rows.
- `fn_sync_account_mapping_from_config(company)` upserts the company-scope bindings from config; a trigger on `company_accounting_config` keeps `account_mapping` in sync, and a one-time backfill seeds existing companies. Key ↔ config-column map (1:1, reversible): `AR_TRADE↔ar_account_id`, `AP_TRADE↔ap_account_id`, `VAT_OUTPUT↔vat_payable_account_id`, `VAT_INPUT↔input_vat_account_id`, `EWT_WITHHELD↔ewt_withheld_account_id`, `EWT_PAYABLE↔ewt_payable_account_id`, `CASH_DEFAULT↔default_cash_account_id`, `CUSTOMER_ADVANCES↔customer_advances_account_id`, `SUPPLIER_DOWNPAYMENTS↔supplier_down_payments_account_id`.

---

## 5. Contract 2 — Posting Control Contract

Phase A adds callable, tested validators; **wiring into posting is Phase B**.
- **Leaf-post validation:** only `is_postable`, lifecycle-`active`, in-effective-window **leaf** accounts (no children) may receive journal lines. Parent/summary accounts reject direct posting.
- **Manual posting rules:** manual JEs may not target a control account (subledger-owned); target must be a postable leaf.
- **Control account / subledger enforcement:** `is_control_account` movement must originate from the owning subledger (`subledger_type`), not ad-hoc manual lines.
- **Dimension policy integration:** posting-control reuses the certified Dimension Engine guard rather than reimplementing dimension validation.
- **Hardcoded references:** the hardcoded `account_code` literals in posting are replaced by `fn_resolve_account` calls in **Phase C** with before/after GL-equality proof.

---

## 6. Contract 3 — COA Governance (Account Lifecycle)

Additive `lifecycle_status` on `chart_of_accounts`: **draft → active → deprecated → archived**, plus **locked** (reversible freeze). `is_active` is retained and kept in sync (`active` ⇔ `is_active=true`).

Allowed transitions: `draft→active`, `draft→archived`; `active→deprecated`, `active→locked`; `deprecated→active`, `deprecated→archived`, `deprecated→locked`; `locked→active`, `locked→deprecated`; `archived→deprecated` (audited administrative reactivation). Archiving requires a zero posted balance. Transitions are permission-gated (`fn_transition_account_lifecycle`, admin-only) and audited via the existing audit family. Any other edge is rejected.

---

## 7. Contract 4 — Change Policy Enforcement

A guard trigger on `chart_of_accounts` enforces:
- **Immutable-once-used identity attributes:** once an account has posted history, `account_type`, `normal_balance`, posting role (`is_postable`), and `is_control_account` cannot change. Invalid modification ⇒ raise.
- **Historical preservation:** an account with posted history cannot be hard-deleted (lifecycle instead).
- **Effective dating:** time-varying classification (FS mapping) is expressed as new effective-dated rows, never in-place rewrites of reported history.
- **Lifecycle validity:** transitions must follow §6.

Follows the authorization-gated immutability-guard house pattern (not GUC-bypassable).

---

## 8. Contract 5 — Financial Statement Registry

Layered over the retained inline `fs_*` columns (kept readable via a compatibility view).
- `fs_structure`: per-company, per-statement (`balance_sheet|income_statement|cash_flow`) ordered hierarchy — `parent_id`, `display_order`, `line_code`, `line_label`, `is_subtotal`.
- `account_fs_map`: maps an account to an `fs_structure` line, **effective-dated**, with **exactly one active mapping per account per statement** (partial unique index), enabling **historical reproduction** (a prior-period statement uses the mapping effective then, even after reclassification). A mapping that has been reported against is immutable (§7).

Phase A delivers the framework (tables, constraints, compat view, provisioning helper); live population is Phase B.

---

## 9. PXL Standard COA (canonical dataset)

A reusable DEFINER provisioning generator, `fn_provision_pxl_standard_coa(company)`, produces the realistic Philippine SME chart with complete metadata on every account (code, name, type, normal_balance, postability, control/subledger flags, FS registry mapping, cash-flow category, lifecycle `active`, effective_from). In Phase A it is the **canonical certification dataset and test fixture only** — it does not modify live provisioning or MDP-05. It becomes the permanent foundation for regression, certification, migration, templates, financial statements, tax fixtures, and future reporting. Repointing live provisioning to it is a separate, independently validated Phase B activity.

---

## 10. Certification

- Registered as certifiable engine **#19** in `docs/PXL/00. Governance/PXL_HOW_WE_WORK.md` §6 (quality bars) — a distinct shared engine, **not** merged into the Posting Engine.
- Gates per that standard: contract documented and matching behavior; invariants (deterministic resolution, fail-closed, ambiguity-rejection, leaf-post-only, valid lifecycle transitions, immutable-attribute rejection, one active FS mapping, historical reproduction) proven by regression test `081_coa_engine_certification_test.sql`; DB-level protections (constraints, triggers, unique indexes, RLS) enforce them server-side; success + failure + equivalence tests pass; full regression green on fresh `--no-seed` replay; canonical lane green.
- **Phase A certification decision is bounded:** the resolver is proven correct and equivalence-identical to current config, and the lifecycle / change-policy / FS-registry frameworks are proven, but because Phase A rewires no consumer, engine gates 2 and 4 ("every invariant holds / success tests pass across every applicable implemented transaction") are **not** yet satisfiable. The engine therefore remains **In Progress — Phase A foundation certified-green**; full COA Engine certification is gated on Phase B consumer migration. This is recorded honestly in the matrix; no premature "Certified" claim is made.

---

## 11. Validation Requirements (Phase A exit)

All four previously Certified engines remain green; existing posting behavior unchanged; resolver output identical to current configuration; canonical dataset validates; full regression passes; no production behavior changes; no undocumented architectural decisions.
