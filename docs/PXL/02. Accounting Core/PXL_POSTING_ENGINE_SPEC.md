# PXL Posting Engine Specification (Architecture)

**Status:** Frozen — Approved (authoritative Posting Engine architecture)
**Authority:** Tier 2 domain architecture for the central accounting processor (Posting Engine, certifiable engine #1)
**Owner / Domain:** Accounting Core
**Applies To:** Every accounting transaction that produces General Ledger effect, present and future
**Read When:** Implementing, extending, or certifying any posting, reversal, void, or correction path
**Do Not Read For:** Tax computation, inventory costing, depreciation math, FS presentation, reporting, budgeting, analytics — those belong to their own engines
**Last Reviewed:** 2026-07-26 (**Amendment A8** — P6 reconciliation investigation stopped at the frozen Inventory boundary: canonical stock/movement valuation does not equal the configured Inventory control account, and inventory cost-layer quantity/value does not equal stock. P6 is Blocked; no reconciliation heuristic, adjustment, posting change, inventory change, or P7 work was introduced. Amendments A1–A7 remain authoritative.)
**Relationship:** Satisfies the 20 mandatory Posting Engine invariants in [PXL_ENGINE_CERTIFICATION_STANDARD.md](../13. Testing and Validation/PXL_ENGINE_CERTIFICATION_STANDARD.md) §5 and the concurrency requirements §10; consumes the COA Engine contract [PXL_COA_ENGINE_SPEC.md](PXL_COA_ENGINE_SPEC.md) and the certified Permissions/RLS, Audit & Immutability, Number Series, and Dimension engines. Supersedes no existing document.

> **Provenance & nature.** This is a **consolidation architecture, not a greenfield rewrite.** A posting kernel already exists in the codebase and is sound; the certification blocker is inconsistent adoption across the authoritative General Ledger writer census (§4.7), not bad design. This document was authored, reviewed, and **frozen with all decisions approved on 2026-07-24**. Implementation must conform to it and must not redesign it; only a governed architectural review that proves a correctness defect may reopen it. Freezing this architecture does **not** authorize implementation — a separate implementation scope must be approved before any phase begins.

---

## 1. Frozen Decisions (approved 2026-07-24)

These are settled and no longer open:

1. **Journal numbering — Option B (centralized derivation).** One kernel function owns all journal-number derivation. Source documents with certified numbering keep **source-derived** journal numbers (`JE-<TYPE>-<source#>`); all scattered string concatenation is eliminated; every journal number is produced through one governed implementation. The certified Number Series Engine is used **only where no natural source number exists** — Manual Journal Entries, Auto Reversals, system-generated journals, and future engine-generated postings. **Historical journals are never renumbered**; historical continuity and auditor traceability are preserved.
2. **Kernel Totality Guard — approved.** The Posting Engine becomes the **only authorized writer of the General Ledger**. No future module, function, migration, or developer shortcut may create journal entries outside the engine. This is **structural enforcement**, not a coding convention (§4.6).
3. **Phase order — frozen** as P1 → P2 (COA Phase B) → P3 → P4 → P5 → P6 → P7 → P8 (Certification). No reordering without explicit approval (§7).
4. **Currency — PHP-only throughout P1–P8.** The model reserves multi-currency semantics only. Exchange rates, FX revaluation, dual currency, and foreign-currency journals are **not** implemented here; they belong to a future Currency Engine (§4.3).

The **corrected posting pipeline** (§3), the **Posting Plan** (§3.1), and the **engine boundaries** (§2) are frozen exactly as specified below.

---

## 2. Engine Boundaries (normative)

### 2.1 The Posting Engine OWNS
Admission control; source locking and idempotency; posting orchestration; journal construction (header/line assembly, line numbering, sign discipline, rounding placement); balancing; the posting status lifecycle (draft → posted → reversed); atomicity and failure semantics; rollback; reversal, void, and correction orchestration; idempotency; posting evidence; source-to-journal traceability; and the posting-source registry contract.

### 2.2 The Posting Engine SHALL NOT own — it consumes certified engines
Permissions; audit logic; numbering logic; dimension validation; account resolution; tax computation; inventory costing; depreciation calculation; financial-statement presentation; reporting; budgeting; analytics. **Never duplicate certified logic.**

| Concern | Owner | Consumption contract |
|---|---|---|
| Authorization, company/branch isolation | Permissions & RLS Engine *(Certified)* | `is_company_member`, `can_admin_company`, `can_perform`; RLS on every table the engine writes |
| Immutability, audit trail | Audit & Immutability Engine *(Certified)* | posted-doc guards; `fn_audit_trigger`; never bypass via GUC |
| Document numbering | Number Series Engine *(Certified)* | `fn_next_document_number(company, branch, code)` — only where no source number exists |
| Dimension validity + propagation | Dimension Engine *(Certified)* | `fn_is_valid_dimension`, `fn_je_line_dimensions_guard`; engine **passes** dimensions, never re-validates |
| Account identity, eligibility, resolution | COA Engine *(#19, Phase A landed)* | `fn_resolve_account`, `fn_assert_postable_leaf`, `fn_assert_manual_postable` |
| Period open/closed | Period Lock & Closing Engine | `fn_require_open_fiscal_period` |
| Approval gating | Approval & Workflow Engine | approval state is an **input precondition**, not a posting decision |
| Tax computation | Tax Engine *(future — does not exist)* | posting **receives** already-persisted tax values from the source document and never calculates. The `TaxComponent` shape (§5.3) is the target, not the current input; the boundary as actually implemented is certified in **§5.3.1** |
| Inventory costing/quantity | Inventory Engine *(future)* | posting receives valuation; never computes cost |
| Fixed-asset schedules | Fixed Asset Engine *(future)* | posting receives depreciation amounts |
| FS presentation, reporting, budgeting, analytics | Reporting / FS / Budget / Analytics | posting emits events; owns no presentation |

### 2.3 Design principles
- **Total, not optional.** Every GL effect flows through one kernel; a registry entry is the only way to become postable. Enforced structurally (§4.6).
- **Push, not pull.** Callers supply a fully-resolved *Posting Context*; the kernel never reaches back into source tables by document type.
- **Declarative source types.** Behavioral differences live in `ref_posting_source_types` data, not in engine branches.
- **Fail-closed.** Any unresolved account, invalid dimension, closed period, or missing tax component aborts the whole posting.
- **Database is the last line of defence.** Every invariant that can be a constraint/trigger is one, so a future bypass still cannot corrupt the ledger.

---

## 3. Posting Pipeline (frozen ordering)

Freeze this ordering exactly. It must not change unless a governed architectural review proves a correctness issue.

```
                 ┌─────────────────────────── PREVIEW MODE (no persistence) ──┐
 Source Document │                                                             │
      ▼          ▼                                                             │
 [0] ADMISSION                                                                 │
      ├─ Authorize (Permissions Engine)                                        │
      ├─ Resolve + ROW-LOCK source (registry)   ← lock BEFORE any read         │
      ├─ Status gate (ready statuses)                                          │
      └─ Duplicate / idempotency gate → may no-op                              │
      ▼                                                                        │
 [1] VALIDATION (module validators, pure)                                      │
      ▼                                                                        │
 [2] PERIOD VALIDATION (Period Engine, fail fast)                             │
      ▼                                                                        │
 [3] DIMENSION VALIDATION (Dimension Engine — call, don't reimplement)         │
      ▼                                                                        │
 [4] TAX COMPONENT ASSEMBLY (Tax Engine supplies; posting never computes)      │
      ▼                                                                        │
 [5] ACCOUNT RESOLUTION (COA resolver: base lines + every tax component)       │
      ▼                                                                        │
 [6] POSTING PLAN CONSTRUCTION (in-memory: header + lines)                     │
      ▼                                                                        │
 [7] INVARIANT ASSERTIONS (balance, sign, company, rounding) ──────────────────┘
      ▼                                          (preview returns the Plan here)
 [8] PERSISTENCE — header (centralized numbering) + lines
      │           DB triggers enforce: balance, dimensions, immutability, totality
      ▼
 [9] SUBLEDGER UPDATE (same transaction)
      ▼
[10] AUDIT + POSTING EVIDENCE (same transaction)
      ▼
[11] TRANSACTIONAL OUTBOX WRITE (same transaction)
      ▼
[12] COMMIT  ← the only durability boundary
      ▼
[13] POST-COMMIT DISPATCH (reporting / async consumers read the outbox)
```

**Why this ordering is correct (frozen rationale):**
1. **Admission first (lock + idempotency).** Validating before locking is a check-then-act race; two concurrent callers both validate and both post. Locking the source first is what makes invariants 11 and 12 hold under concurrency. The existing kernel already does this; implementation must not regress it.
2. **Tax assembly before account resolution.** Tax components determine *which* accounts are needed (input/output VAT, EWT, CWT). Resolving first would force a second resolution pass or hardcoded tax accounts.
3. **Commit explicit and singular; reporting events after commit.** Emitting events inside posting risks a dirty read (event for an uncommitted journal) or a non-transactional side effect. Events are written to a transactional **outbox** inside the transaction and dispatched after commit — the only design that is both atomic and observable. **Clarification:** the transactional outbox (stage 11) and post-commit dispatch (stage 13) are **dormant until the asynchronous infrastructure exists (P9, deferred).** P1–P8 are synchronous: the outbox table may be created but unwired and dispatch is a no-op. Their presence in the frozen ordering reserves the correct seam; it does **not** require async infrastructure in P1–P8.
4. **Preview is a first-class path.** Stages 0(authorize)–7 run with no persistence and return the Posting Plan (GL Impact preview, pre-flight configuration check).
5. **Invariant assertion is broader than balance.** The engine asserts balance, company consistency, sign discipline, rounding placement, and line completeness in one gate, with DB triggers as backstop.

### 3.1 The Posting Plan (frozen canonical artifact)
Stages 4–7 produce a **Posting Plan** — the single canonical accounting artifact before persistence: a pure value of header attributes + ordered lines, each with resolved account, amounts, dimensions, `line_role`, and provenance. It must be **deterministic, serializable, previewable, replayable, and independently testable.** **Preview and actual posting consume the exact same Posting Plan; preview never duplicates posting logic.** Persistence consumes the Plan unchanged.

**Preview ≡ actual holds only when the Posting Plan inputs are unchanged.** Preview is read-only and takes **no durable lock**, so a concurrent mutation between a preview and the subsequent post can change the inputs; the authoritative result is always the posted journal, and `source_fingerprint` flags any preview/actual input divergence. **Deterministic replay depends on the original effective-dated Posting Plan inputs** — the same `as_of`, resolving against mappings that are immutable-once-posted-against under the COA change policy. Re-resolving with a later date is a different operation, not a replay.

### 3.2 Idempotency contract (occurrence identity per source type)

Idempotency is keyed by **occurrence identity**, defined per source type by the posting-source registry (`ref_posting_source_types`):

- **Single-journal source types** (`allows_multiple_journal_entries = false`, the default): occurrence identity is `(company_id, reference_doc_type, reference_doc_id)`. The admission duplicate gate rejects a second live journal for the same source (`status IN ('posted','reversed')`, excluding reversal/void journals); re-invocation is a **no-op success** returning the existing journal id.
- **Multi-journal source types** (`allows_multiple_journal_entries = true`): the source-id gate does not apply, so each such type MUST declare a **deterministic occurrence key**, enforced by a **partial unique index** on the produced journals — not by an application check-then-act:
  - `RECURRING` → `(company_id, template_id, accounting_period)` — one journal per template per period.
  - `CLOSE` (year-end) → `(company_id, fiscal_year)` — one closing run per fiscal year.
  - `MANUAL` → **intentionally unrestricted.** Each manual journal is a distinct authored document; uniqueness is the human-entered `je_number` (`UNIQUE(company_id, je_number)`) only.
  - `REV` (reversal) → **intentionally unrestricted.** A document may be legitimately reversed and re-posted; the `reversal_of_je_id` link provides traceability, not a uniqueness constraint.

**Uniqueness rules:** occurrence identity is enforced **structurally** (a unique index on the occurrence key), never by read-then-write. **Duplicate prevention:** a re-run matching an existing occurrence returns the existing journal (no-op success) and never creates a second journal. **Retry behavior:** any retry after rollback re-runs the whole pipeline and is safe — a completed occurrence no-ops; an incomplete one (rolled back, so no journal exists) proceeds. This closes the silent-duplicate risk for the period-driven types (`RECURRING`, `CLOSE`) that the single-source-id gate alone does not cover.

**Status-less source types.** Three registered types carry no status column and therefore skip the admission *status* gate by design: `REV` (a reversal has no source status to check), `FA_DISP` (fixed-asset disposal), and `FA_IMP` (fixed-asset impairment). Their admission relies on source-lock + occurrence identity + the source document's own lifecycle guard. This is intentional and must be preserved.

---

## 4. Journal Architecture

### 4.1 Journal Header
Existing `journal_entries` is structurally adequate: `id`, `company_id`, `branch_id`, `je_number` (unique per company), `je_date`, `fiscal_period_id`, `description`, source binding (`reference_doc_type`, `reference_doc_id`), `status` (`draft|posted|reversed`), `total_debit`, `total_credit`, audit columns.

**Additive columns (Phase-gated, nullable first):**
- `posting_origin` — `system | manual` (invariant 13).
- `reversal_of_je_id` — explicit link (invariant 15), replacing the `je_number LIKE '%-REV-%'` string convention.
- `posting_run_id` — correlates every journal from one posting invocation/batch.
- `source_fingerprint` — hash of the resolved Posting Plan inputs; enables deterministic-replay proof and tamper evidence.

The current reliance on `je_number NOT LIKE '%-REV-%'` / `NOT LIKE 'JE-VOID-%'` in the duplicate gate is a string-convention dependency on a semantic fact and must be replaced by these structural columns (in P1, before numbering changes).

### 4.2 Journal Lines
Existing `journal_entry_lines` is adequate: `je_id`, `company_id`, `line_number`, `account_id`, `description`, `debit_amount`, `credit_amount`, the six dimensions, with `CHECK (debit>=0 AND credit>=0)` and `CHECK (debit=0 OR credit=0)`.

**Additive columns:** `line_role` (`base | tax | withholding | rounding | control | offset`) and `source_line_id`. `line_role` makes control-account/subledger reconciliation and tax-ledger tie-out provable rather than inferred.

### 4.3 Reference integrity, dimensions, currency
- Source binding `(reference_doc_type, reference_doc_id)` validated against the registry via `fn_assert_posting_source`.
- Dimensions live on the **line**, guarded by the certified Dimension Engine. Posting supplies; it does not validate.
- **Currency (frozen PHP-only):** reserve `currency_code`, `fx_rate`, `base_amount` semantics in the model. Do **not** implement exchange rates, FX revaluation, dual currency, or foreign-currency journals in P1–P8. Supported scope is stated explicitly; multi-currency is a future Currency Engine.

### 4.4 Posting, audit, and reversal metadata
Posting metadata (`posting_run_id`, `posting_origin`, `source_fingerprint`, posted_by/at); audit metadata (existing `fn_audit_trigger` coverage); reversal metadata (`reversal_of_je_id`, reason, reversal date).

### 4.5 Journal numbering — Option B (frozen)
A **single kernel function** owns all journal-number derivation.
- Source documents with certified numbering: journal number is **derived from the source number** (`JE-<TYPE>-<source#>`); uniqueness rests on `UNIQUE(company_id, je_number)` plus the source's own certified numbering; a guard test proves no path constructs a number outside the kernel.
- No natural source number (Manual JE, Auto Reversals, system/engine-generated): allocate through the **certified Number Series Engine** (`fn_next_document_number`).
- **All scattered string concatenation is eliminated.** Historical journals are never renumbered.
- **Ownership separation (clarified).** The **Number Series Engine owns sequence allocation** (issuing the next number in a governed series). The **Posting Engine owns journal-identity assembly** (composing the `je_number` — for source-numbered types by binding the source's already-certified number, for source-less types by consuming a sequence the Number Series Engine allocated). Posting never re-implements sequence allocation. A reversal's journal number is assembled by the reversal kernel from the original (label form `<original>-REV-<n>`); the authoritative relationship is the `reversal_of_je_id` link, and the string suffix is a display label, not a semantic dependency (§4.1).

### 4.6 Kernel Totality Guard (frozen — approved; **FULLY ENFORCED**)
The Posting Engine is the **only authorized writer of the GL**. The structural guard on `journal_entries` and `journal_entry_lines` distinguishes the six exact sanctioned persistence functions from every other call stack and rejects every non-kernel INSERT, UPDATE, or DELETE with SQLSTATE `23514`. This converts "everyone should use the engine" into "nothing else *can* write the ledger."

**Status (2026-07-26, after P5.2): ARMED and FULLY ENFORCED — see §4.6.3.** Enforcement is the compile-time constant `true`. All 24 authoritative forward writers and the four additional header-UPDATE paths remain kernel-routed. Canonical replay produces zero guard violations and zero accounting drift.

**Structural layers.**
1. **Table privileges and RLS for external callers.** `PUBLIC`, `anon`, and `authenticated` have no ledger-table INSERT, UPDATE, or DELETE privilege; both ledger tables retain RLS with SELECT-only policies. Direct client mutations therefore fail before they can become an RLS no-op.
2. **Kernel-origin trigger for every database caller.** The two totality triggers are `ENABLE ALWAYS`, so owner SQL, migration/seed/replay helpers, SECURITY DEFINER functions, RPCs, and `session_replication_role = replica` all remain guarded. No maintenance exception exists.
3. **Accounting invariants for every sanctioned write.** The other 19 triggers on the two ledger tables enforce balance, dimensions, source integrity, period, immutability, and audit. Together with the two totality triggers, the persistence surface has 21 triggers.

Only the six sanctioned persistence functions contain ledger mutation SQL. The classifier is exact-name and call-stack based; it has no runtime flag, role exception, whitelist prefix, maintenance bypass, or historical-origin inference.

#### 4.6.1 P5.0 Surface Closure (completed 2026-07-26 — the external surface only)

Migration `20260726000001`, test `091` (45 assertions), **no accounting behaviour change** (canonical GL/tax/inventory/stock/number-series fingerprints identical with and without the migration). Three closures:

- **Internal persistence helper.** `fn_add_posting_line` — reduced by P3A to one INSERT behind a membership check, with no admission control and no client caller — is no longer executable by `authenticated`. Posting writers are SECURITY DEFINER and call it as the owner, so the posting path is untouched.
- **PUBLIC / `anon` EXECUTE.** No GL-writing function retains a PUBLIC grant. Ten client entry points keep `authenticated` and `service_role` (status quo preserved); three journal-linking **trigger** functions are now unreachable by every caller role while their seven triggers keep firing.
- **Accounting-owned derived tables.** `stock_balances`, `inventory_cost_layers`, `inventory_transactions`, `asset_depreciation_entries`, `amortization_entries`, and `revenue_recognition_entries` deny every `authenticated` write, applying the pattern already certified on `tax_detail_entries`. All 28 functions writing them are SECURITY DEFINER; the frontend reads all six and writes none.

**The bypass this closed was real, not theoretical.** Before P5.0 a genuine company member could run `UPDATE stock_balances SET wac_unit_cost = wac_unit_cost * 10` (1 row) and forge an `inventory_transactions` row (1 row) straight through PostgREST. Because `fn_post_sales_invoice` reads `stock_balances.wac_unit_cost` to compute COGS, that is accounting impact created outside the engine, with no journal and no accounting audit. The same statements now yield `UPDATE 0` and an RLS violation; the controlled reversion is recorded as the non-vacuity proof in the test book.

**Deliberately excluded (correction to the review).** `bank_recon_items` and `book_tax_reconciliation` were candidates on the premise that their writers were all SECURITY DEFINER. That premise is false — `BankReconciliationPage` and `BookToTaxReconciliationPage` write them directly — so closing them would break working features. They remain member-writable by recorded decision and are pinned by assertion in test `091`.

#### 4.6.2 P5.1 Stage 1 — the guard, observe-only (landed 2026-07-26)

Migration `20260726000002`, test `092` (40 assertions), **no accounting behaviour change** (canonical fingerprints identical to the pre-P5.0 baseline).

**Origin is proven by call stack, not by a flag — a deliberate departure from the wording above.** §4.6 suggests "a transaction-scoped posting-context flag set only by the kernel". A settable flag is exactly the shape that produced Critical `PXL-AUD-070`. The guard instead reads `GET DIAGNOSTICS … PG_CONTEXT`: a write is kernel-origin **iff** a sanctioned kernel is genuinely on the plpgsql stack, which a caller cannot fabricate. It reads no session setting, and enforcement is a **compile-time constant** — there is no runtime knob to arm or disarm it, so arming is necessarily a governed migration. This satisfies the frozen intent structurally while removing the bypass class; the frozen decision is honoured, its suggested mechanism is not.

**Honest scope:** a *discipline* control, not an authorization control. Authorization is RLS (P5.0). The threat model is in-database code — a future function, migration, or developer shortcut.

**Material finding — the 7-argument kernel could not absorb the writers.** 23 of the 24 direct-insert writers resolve their own period and raise their **own** user-visible "No open fiscal period …" message (23 distinct wordings; three asserted by existing tests); all write computed header totals where the kernel writes 0/0 and relies on a finalizer none of them calls; four set `posting_origin`, three set `entry_class`/`auto_reverse`. Routing them through the kernel unchanged would have altered 23 user-visible behaviours and every migrated header's totals — a STOP condition. The kernel is therefore **extended additively** (`p_fiscal_period_id`, `p_status`, `p_total_debit`, `p_total_credit`, `p_posting_origin`, `p_entry_class`, `p_auto_reverse`, all defaulted) so a writer hands it what it already writes and keeps its own validation verbatim. Per P3A an additive overload is not deployment-safe, so the function was dropped and re-created with defaults; all seven existing 7-argument callers are unaffected.

**Material finding — the runtime census is larger than the static one.** Observe-only mode surfaced what `pg_proc` could not: `fn_post_sales_invoice`, `fn_post_vendor_bill`, `fn_post_receipt`, and `fn_post_cash_purchase_source_locked_impl` are "already kernel-routed" for the header INSERT yet each mutates the header afterwards with a direct `UPDATE journal_entries`. **The remaining P5.1 surface is header INSERTs + header UPDATEs + line INSERTs**, not header INSERTs alone. The §4.7 static census remains authoritative for *which functions exist*; the violation table is authoritative for *which paths actually run*.

**Module 1 migrated:** `fn_post_credit_memo_vat_lump_impl`, `fn_post_debit_memo_vat_lump_impl`, `fn_post_vendor_credit_vat_lump_impl`. Each keeps its own status gate, period resolution, and verbatim messages; only the header INSERT moved to the kernel, verified by line-level diff.

**Stage 2, Module 2 (landed 2026-07-26)** — migration `20260726000003`, test `093` (28 assertions), fingerprints unchanged. The memo posters' nine direct `journal_entry_lines` INSERTs moved to `fn_add_posting_line_push`, which joins the sanctioned set. The three writers now touch **neither** ledger table directly.

*Helper choice was forced.* The lines carry `line_role`, which `fn_add_posting_line` cannot express; and that helper additionally imposes `fn_require_postable_account` plus a debit/credit-exclusivity check the replaced raw INSERTs never performed — two new rejection paths, i.e. a validation change the phase contract forbids. The push helper (built by P1/P3A for the §4.2 additive line columns, unreferenced until now) performs the same single INSERT.

*Two assumptions corrected against the live schema.* Journal lines are **not** dimension-free: `fn_je_line_dimensions_guard` defaults a NULL line `branch_id` from the header on INSERT and fires identically for helper and raw INSERT. And `journal_entry_lines` carries **no** `fn_audit_trigger` — line-level audit does not exist, so line audit coverage cannot change here.

**Approved continuation and readiness closure (landed 2026-07-26)** — migrations `20260726000004`–`20260726000011`, tests `094`–`101` (133 assertions):

- **Batch A:** Sales Invoice, Vendor Bill, Receipt, and Cash Purchase retain the historical post-create `posting_origin` UPDATE and its audit row through an explicit default-off kernel mode.
- **Batch B:** Manual Journal is independently certified with its validator position, seven rejection messages, period gate, `MJE-YYYYMM` numbering, NULL `posting_origin`, `entry_class`, auto-reverse, dimensions, and line order unchanged.
- **Inventory:** Goods Issue, Physical Count, Stock Adjustment, and Stock Transfer route only their GL persistence through the kernels. Inventory calculations, layers, WAC, balances, movements, and the `INV_COUNT` zero-line behavior are unchanged; no Inventory Engine redesign occurred.
- **Treasury:** Bank Adjustment, Fund Transfer, Inter-Branch Transfer, Petty Cash Voucher approval, Petty Cash Replenishment, and Check Voucher migrated without lifecycle, numbering, tax, dimension, or reversal drift.
- **Assets and schedules:** Depreciation, Amortization, Revenue Recognition, Fixed Asset registration/disposal/impairment, and their exact source-link UPDATEs migrated through an explicit default-off finalizer mode.
- **System generated:** Recurring Journal and Fiscal Close migrated; the exact auto-reversal marker UPDATE remains through the finalizer.
- **Commerce:** Purchase Return retains its exact provisional-journal discard sequence; Cash Sale retains two journals, six line sites, tax detail, roles, order, and lifecycle.
- **Readiness closure:** the unused `fn_add_posting_line_core_20260718` raw-mutation helper was removed after proving it had no live caller. Classifier members are anchored at `\(`, so lookalike names cannot inherit kernel status; the six-member sanctioned set did not grow.

**Arming gate: MET, but enforcement deliberately unchanged.** Remaining forward writers: **0**. Canonical violation census: **0 writers / 0 events**, including **0 non-maintenance events**. Only the six sanctioned persistence functions contain ledger DML. Canonical `posting_origin` coverage is 30/48 explicit `system`; the 18 NULL journals (Inventory, Manual, Payment Voucher, and one reversal) remain valid, with no historical inference or backfill. GL, journal header/lines/order/roles, audit, dimensions, tax, inventory, number series, document status, reversal, preview, and deterministic replay equality all pass. The guard is **READY TO ARM**; arming remains a separate, explicitly approved migration.

#### 4.6.3 P5.2 — arming and enforcement certification (completed 2026-07-26)

Migration `20260726000012`, test `102` (78 assertions), and the read-only census `supabase/verification/p52_kernel_security_census.sql` arm the guard without changing any Posting, Inventory, Tax, COA, Preview, or Journal Engine behavior.

**Enforcement.** The guard compile-time constant is `true`; its former maintenance classification remains evidence metadata only and cannot bypass rejection. Both guard triggers are `ENABLE ALWAYS`. Direct ledger DML is revoked from `PUBLIC`, `anon`, and `authenticated`, and the guard function itself is not executable by those roles. The exact six-member classifier did not change:

1. `fn_create_posted_journal_entry`
2. `fn_reverse_posted_journal_entry`
3. `fn_finalize_journal_entry`
4. `fn_add_posting_line`
5. `fn_add_posting_line_push`
6. `fn_add_sales_invoice_posting_line`

**Negative proof.** Test `102` executes 48 unauthorized attempts: three operations on each of the two ledger tables through authenticated, anon, non-kernel SECURITY DEFINER, SQL-script helper, authenticated RPC, migration helper, replay helper, and direct owner SQL paths. Authenticated and anon attempts fail at privilege enforcement (`42501`); all other attempts reach and fail the guard (`23514`). No attempted mutation persists. Guard-evidence rows raised within a rejected statement roll back with that statement, so the violation table correctly remains at zero rather than becoming an exception log.

**Security census.** There are 409 application functions, 349 SECURITY DEFINER functions, 950 explicit EXECUTE ACL rows covering all 409 functions, and 80 direct-or-transitive ledger-mutating functions; every one of those 80 is SECURITY DEFINER and reaches one of the exact six sanctioned kernels. The six are the only direct mutators. `service_role` has direct EXECUTE on three (`fn_create_posted_journal_entry`, `fn_add_posting_line`, and `fn_add_posting_line_push`); it receives no classifier exemption and can mutate only while genuinely executing a sanctioned kernel. The ledger has 21 persistence triggers, including two always-enabled totality triggers, and two SELECT-only RLS policies. The complete row-level catalog output is maintained by the census script.

**Positive and equality proof.** Sales, Vendor Bill, Receipt, Payment, Credit Memo, Debit Memo, Vendor Credit, Cash Purchase, Manual Journal, Inventory, Fixed Asset, Recurring, Fiscal Close, and Reversal paths all remain successful. The clean full regression passes 102 files / 2,254 assertions; the canonical lane passes 30 files / 748 assertions after fresh migration and seed replay. Canonical counts remain 48 journals / 138 lines / 24 tax rows / 26 inventory movements, debit and credit both `2,411,134.80`, `posting_origin` remains 30 explicit `system` / 18 valid NULL, and guard violations remain zero. Journal, line order/role, numbering, dimensions, audit, tax, inventory, document status, preview, reversal, and GL fingerprints are unchanged.

### 4.7 Authoritative General Ledger writer census
The migration list, the Kernel Totality Guard scope, and the certification coverage list are all defined by the **authoritative GL-writer census — the set of database functions that write `journal_entries` / `journal_entry_lines`, enumerated from the current `pg_proc` state, not from any prose count of "posting paths."** This census supersedes the earlier "23 posting paths" figure. It must be regenerated and reconciled as an explicit **P1 exit gate**, and re-checked whenever a GL-writing function is added.

Current-state census (verified 2026-07-24 against `pg_proc`):

| Class | Count | Members / notes |
|---|---:|---|
| **Sanctioned kernels** | 2 | `fn_create_posted_journal_entry` (forward header writer) and `fn_reverse_posted_journal_entry` (reversal writer) — the only functions permitted to remain direct `journal_entries` writers after P5 |
| **Forward posters already kernel-routed** | 6 | `fn_post_sales_invoice`, `fn_post_vendor_bill`, `fn_post_payment_voucher`, `fn_post_receipt`, `fn_post_cash_purchase_source_locked_impl`, `fn_post_withholding_remittance` — already call the header helper (no migration needed) |
| **Reversal / Void / Correction — already consolidated** | 7 | `fn_void_sales_invoice_aud053_core`, `fn_void_vendor_bill`, `fn_void_withholding_remittance`, `fn_bounce_receipt`, `fn_cancel_payment_voucher`, `fn_reverse_je`, `fn_bt_reverse_je` — already route through the reversal kernel (no migration needed) |
| **Direct-insert forward writers — the migration surface** | 24 | the `*_source_locked_impl` family (goods issue, physical count, stock adjustment/transfer, depreciation, amortization, revenue recognition, bank adjustment, fund transfer, inter-branch transfer, petty-cash replenishment), plus `fn_post_manual_je`, `fn_post_check_voucher`, `fn_post_credit_memo_vat_lump_impl`, `fn_post_debit_memo_vat_lump_impl`, `fn_post_vendor_credit_vat_lump_impl`, `fn_register_fixed_asset`, `fn_dispose_fixed_asset`, `fn_record_impairment`, `fn_close_fiscal_year`, `fn_execute_recurring_template_source_locked_impl`, `fn_complete_purchase_return_source_locked_impl`, `fn_approve_petty_cash_voucher_source_locked_impl`, `fn_save_cash_sale` |

Each writer is classified with this vocabulary: **Forward Posting, Reversal, Void, Correction, Lifecycle, Recurring, System Generated, Cash Sale on Save, Other.** Two lifecycle behaviors the census makes explicit and the admission model must accommodate (they are **not** draft→approve→post): **Cash Sale on Save** (`fn_save_cash_sale`) and **post-on-approve** (`fn_approve_petty_cash_voucher_source_locked_impl`) create their journal at save/approve time.

The **24 direct-insert forward writers are the exact P2/P3 migration surface and the exact P5 Totality-Guard scope.** The 6 already-routed forward posters and 7 already-consolidated correction functions need no migration but remain in the certification coverage list. This census — not "23 posting paths" — is authoritative for migration, the Totality Guard, and certification coverage.

---

## 5. Integration Contracts

### 5.1 COA Resolver (`fn_resolve_account`)
- **When:** stage 5 only, after tax assembly, during Plan construction. Never during persistence; never re-resolved per line in a loop.
- **How many times:** once per *distinct* `(key, resolution context)` per posting, into a per-posting map; lines are built from the map. An N-line invoice with one revenue key = **one** call.
- **Caching:** per-posting-invocation memoization only. **No cross-transaction cache** — mappings are effective-dated; a stale cache would silently post to a superseded account.
- **Failure:** fail-closed; any raise aborts the whole posting. Errors name `key_code`, company, and context, generated centrally (not hand-written per transaction).
- **Missing mappings:** never defaulted, guessed, or skipped; surfaced at preview time as a configuration defect.
- **Guarantees relied upon:** determinism, most-specific precedence, ambiguity rejection, account validation (postable, active, correct type, same company). Posting must not re-check these.

### 5.2 Dimension Engine
Posting **passes** the six dimensions onto each line from the Posting Context and relies on `fn_je_line_dimensions_guard`. Posting performs **no** dimension validation. The current pull-based dispatch in `fn_add_posting_line` (hardcoded `VB`/`CP`) is replaced by push: the caller resolves the document's dimensions once into the Posting Context; every line inherits or overrides explicitly.

### 5.3 Tax Engine (integration only — not implemented here)
Posting receives a **tax component set** and never computes it:

```
TaxComponent {
  component_type : vat_output | vat_input | percentage_tax | ewt | cwt | ...
  taxable_base   : numeric
  rate_ref       : identifier (effective-dated, owned by Tax Engine)
  tax_amount     : numeric          -- authoritative, computed by Tax Engine
  account_key    : ref_mapping_key  -- resolved by the COA resolver
  direction      : debit | credit
  ledger_target  : tax ledger identity for tie-out
}
```
Rules: multiple components supported; each maps to exactly one line with `line_role='tax'|'withholding'`; posting asserts `sum(components) + base = document total` and refuses on mismatch; posting never re-derives a rate; rounding differences are an explicit `line_role='rounding'` line, never absorbed silently. Until the Tax Engine exists, module code supplies the component set in this shape.

#### 5.3.1 P4 Amendment A2 — the boundary as it actually exists (certified 2026-07-26)

**No formal Tax Engine exists, and no `TaxComponent` object, type, or contract exists in the live system.** The shape above remains the *target*; it is aspirational and unimplemented. The P4 investigation established that the true architectural gap sits **above** the Posting Engine — in the document-save layer — not inside it. P4 was therefore re-scoped by the architecture board (2026-07-26) from "introduce the TaxComponent shape" to a formal certification of the boundary that already holds. Test `090` is the permanent evidence.

**Certified ownership matrix (evidence: live `pg_proc`, migration-free, test `090`):**

| Concern | Owner **today** | Future target owner |
|---|---|---|
| Tax policy + calculation — applicability, classification, rate lookup, taxable base, inclusive/exclusive, exempt/zero-rated, rounding, VAT, EWT/CWT | **document-save layer** (7 duplicated calculators) | governed Tax Engine |
| Tax account resolution — `VAT_OUTPUT`, `VAT_INPUT`, `EWT_PAYABLE`, `EWT_WITHHELD` | **Certified COA Resolver** (`fn_resolve_account` via `fn_resolve_posting_account`) | unchanged |
| Tax-line construction, ordering, line roles, dimension carriage, Plan persistence | **Posting Engine** | unchanged |
| Tax-detail persistence, reconciliation, provenance-preserving reversal | **Tax Ledger layer** (`tax_detail_entries`, `fn_add_tax_detail`, `fn_reverse_tax_detail_entries`) | unchanged |

**Tax-aware posting-writer census — 20** (corrected from the investigation's 19; `fn_cancel_check_voucher` reaches the GL through `fn_bt_reverse_je` and was missed by a census predicate keyed only on `fn_reverse_posted_journal_entry`). Of the 20:

- **0** read `company_accounting_config` for an account; every tax account key is resolved through the certified adapter.
- **19** perform no tax arithmetic of any kind and read no VAT rate source. They consume tax amounts already persisted on the source document.
- **6** read `atc_codes`; in **5** of them the rate is copied straight into `tax_detail_entries.tax_rate` as **provenance only** — it never feeds a multiplication, division, or policy comparison. This is the precise boundary claim: *the posting layer records the rate that applied; it does not select one.*
- **1** — `fn_save_cash_sale` — genuinely computes VAT, because it is a **document-save function that also posts** ("Cash Sale on Save", §4.7). Its calculation belongs to its save half; its posting half consumes what that save half persisted, proven byte-for-byte in test `090`. Separating the two requires a Tax Engine output that does not yet exist, so it is registered as a **Tax Engine migration candidate**, not remediated here.

**Schema-wide tax-arithmetic census — 11 functions**, of which exactly one writes the GL (`fn_save_cash_sale`): 7 document-save VAT calculators, 2 EWT-profile appliers, and 2 stored-amount validators. The **seven duplicated calculators** (`fn_save_sales_invoice_aud053_core`, `fn_save_vendor_bill_core_20260718`, `fn_save_cash_purchase_core_20260718`, `fn_save_credit_memo`, `fn_save_debit_memo`, `fn_save_vendor_credit`, `fn_save_cash_sale`) are **registered technical debt owned by the future Tax Engine program** — they are not consolidated by P4. All seven share one rounding idiom, `ROUND(base * rate / 100, 2)` per line; **VAT-inclusive treatment is implemented in only one of the seven** (Sales Invoice), a documented limitation carried into that program.

**What certification proved behaviourally** (test `090`, 49 assertions): for Sales Invoice, Vendor Bill (source EWT), Cash Purchase, Payment Voucher (payment-time EWT), Official Receipt (CWT), Credit Memo, Vendor Credit, and Cash Sale, the *stored* tax amount, the *posted* GL tax line, and the *tax-ledger* entry are one value; GL-to-tax-ledger reconciliation is **exactly zero**, not tolerance-satisfied; reversal copies the original ATC version, rate, base, code, and income nature and **does not recompute at the current rate** (proven against a governed successor ATC carrying a different rate); rounding agrees across every reachable calculator; and invalid stored tax still fails closed.

**This certification does not claim** that the Tax Engine is certified, that a Tax Component object exists, that Philippine tax function coverage is complete, or that save-layer duplication has been removed.

### 5.4 Subledger contract (derived-view reconciliation — no materialized subledger tables)
PXL has **no materialized AR/AP subledger tables**; AR/AP/inventory/FA balances are **derived** from `journal_entries` + source documents (verified 2026-07-24 against the schema). The frozen contract is therefore **derived-view reconciliation**, not a same-transaction subledger writer, and **no materialized subledger tables are introduced** by this engine.

Posting **orchestrates** the GL effect and tags control-account movement with `line_role='control'`. Reconciliation is an **independent recomputation** of the subledger balance from its own source documents, compared against the control-account GL balance:

| Subledger | Model | Posting's obligation | Reconciliation (invariant 8) |
|---|---|---|---|
| AR | derived | Post the AR control line (`line_role='control'`) | AR control GL balance == independently recomputed open-receivable balance from AR source documents |
| AP | derived | Post the AP control line | AP control GL balance == independently recomputed open-payable balance from AP source documents |
| Inventory | derived | Post inventory/COGS lines; receive valuation (never compute cost) | Inventory control GL balance == recomputed valuation from posted inventory movements |
| Fixed Assets | derived | Post lines; receive depreciation/disposal amounts | FA control GL balance == recomputed FA-register balance |
| Cash/Bank | derived | Post cash lines | Cash/bank control GL balance == recomputed bank ledger |
| Tax ledgers | derived | Write tax lines (`line_role='tax'|'withholding'`) | Tax-ledger totals == recomputed from tax lines / source tax rows |

**Ownership boundary:** posting decides *that* a control account moves, *by how much in GL terms*, and tags it (`line_role='control'`); each subledger domain owns the *independent recomputation* of its balance from its own source documents. The guaranteed invariant is that the two agree. Introducing materialized subledger tables would be a separate, governed architectural change and is explicitly **out of scope** here.

#### 5.4.1 P6 investigation result — Blocked at Inventory (2026-07-26)

P6 stopped before implementation because the canonical data disproves the Inventory row of the frozen contract. Quantity and stock value recomputed from `inventory_transactions` equal `stock_balances`, but neither the stock valuation nor `inventory_cost_layers` reconciles to the configured item Inventory control account:

| Canonical company | Movement/stock ending value | Inventory-control GL | Control variance | Cost-layer ending value | Layer-to-stock variance |
|---|---:|---:|---:|---:|---:|
| ABC Trading Corporation | 71,180.00 | 68,780.00 | 2,400.00 | 73,600.00 | 2,420.00 |
| Bayani Partners and Company | 60,900.00 | 39,900.00 | 21,000.00 | 73,500.00 | 12,600.00 |
| Golden Retail Store | 46,370.00 | 39,740.00 | 6,630.00 | 50,300.00 | 3,930.00 |

The cause is structural, not a reporting predicate:

- Receiving Reports increase inventory movements and stock by 2,400.00 / 21,000.00 / 6,000.00, but their Vendor Bills debit `Purchases / Inventory Clearing` rather than the item Inventory account; the Receiving Report itself has no journal.
- ABC's later 200.00 Vendor Credit reduces purchase clearing without reducing stock or a cost layer.
- Golden's opening inventory movements/stock begin at 44,300.00 while its opening Inventory-control journal is 43,670.00.
- Remaining cost layers exceed stock by 9 / 6 / 14 units respectively; layer values exceed stock by the amounts shown above.

Treating purchase clearing as an additional control account would still leave ABC 200.00 and Golden 630.00 unreconciled and would contradict the configured item Inventory account. Closing the differences would require Inventory/Posting behavior changes, certified inventory-data changes, heuristic account aggregation, or adjustment postings. Every option is a P6 stop condition. No reconciliation function or certification test was added, and AR/AP/Fixed Asset/Bank/Tax were not advanced to P6 certification after this mandatory stop.

### 5.5 Period, Approval, Permissions, Audit
- **Period:** `fn_require_open_fiscal_period` at stage 2 (fail fast) and again at header insert (authoritative). Reopen is a Period Engine operation posting never performs. **Reversal into a closed period follows the governed reversal policy:** a reversal never posts silently into a closed period — it posts to the **current open period** (or a designated adjusting period per the Period Engine), while the `reversal_of_je_id` link preserves the tie to the original regardless of the original's period.
- **Approval:** approval status is a precondition read at admission; posting never approves; SOD stays in the Approval Engine.
- **Permissions:** authorization at admission via `can_perform`; RLS on every written table; no service credential in the frontend.
- **Audit:** existing trigger coverage plus explicit posting evidence; reversal and void write their own audit records.

---

## 6. Certification Matrix

Mapped to the 20 governed invariants (`PXL_ENGINE_CERTIFICATION_STANDARD.md` §5); each proven **across every implemented posting transaction**.

| # | Invariant | Proof mechanism | Structural enforcement |
|---|---|---|---|
| 1 | Debit = credit | Per-type balance assertion | `fn_enforce_journal_entry_balanced` trigger *(exists)* |
| 2 | One company per journal | Header FK + assertion | Constraint |
| 3 | Lines cannot cross companies | Cross-company line rejection test | Dimension/line guard |
| 4 | Branch values valid | Dimension Engine guard *(certified)* | Trigger |
| 5 | Posted documents not directly editable | Immutability guards *(certified)* | Trigger |
| 6 | Posted lines not mutable/deletable | Immutability guards *(certified)* | Trigger |
| 7 | Source→journal traceability complete | Registry + source binding assertion | FK + `fn_assert_posting_source` |
| 8 | Control accounts reconcile to derived subledger balances | Independent recomputation vs GL (derived-view model, §5.4) | `line_role='control'` + reconciliation query (no materialized subledger) |
| 9 | Closed periods block posting | Closed-period rejection per type | `fn_require_open_fiscal_period` |
| 10 | Unauthorized users cannot post | Permission rejection per type | `can_perform` + RLS |
| 11 | Duplicate posting prevented | Concurrent double-post test | Source row lock + duplicate gate |
| 12 | Reposting creates no second journal | Idempotent replay returns existing id | Duplicate gate |
| 13 | System vs manual journals distinguishable | Assertion on `posting_origin` | Column + check |
| 14 | Journal numbers unique | Uniqueness + single-derivation guard | `UNIQUE(company_id, je_number)` |
| 15 | Reversal is linked, equal and opposite | Reversal equality test | `reversal_of_je_id` FK |
| 16 | Reversal cannot silently alter source | Source-unchanged assertion | Immutability guards |
| 17 | Errors leave no partial journals | Injected-failure test | Single transaction |
| 18 | Posting transactional and atomic | Injected-failure test | Single transaction |
| 19 | Failed posting doesn't corrupt source | Post-failure source-state assertion | Rollback |
| 20 | Audit written for posting and reversal | Audit-row assertion | `fn_audit_trigger` |

**Additional gates:** the §10 concurrency scenarios (two users posting the same document; duplicate number generation; simultaneous approval and edit; retry after network failure; failed RPC midway); plus **preview ≡ actual** and **deterministic replay** (same inputs ⇒ same `source_fingerprint`).

**Coverage grid:** invariants × the **authoritative GL-writer census (§4.7)** — *not* the earlier "23 posting transactions" — built table-driven over `ref_posting_source_types` so a newly registered source type is automatically covered. Because not every invariant applies to every type, the grid uses an **applicability matrix**: each `(invariant, source type)` cell is marked **Applicable** (must be proven) or **N/A** (with a recorded reason — e.g., invariant 8 is N/A for a `MANUAL` JE with no control account; tax invariants are N/A for a fund transfer; occurrence-key duplicate prevention is proven for `RECURRING`/`CLOSE` and marked N/A for `MANUAL`/`REV`). Certification proves every Applicable cell and records every N/A with its reason; the fully-resolved grid is the P8 deliverable.

---

## 7. Implementation Roadmap (frozen order — P1 → P8)

Additive-first, modeled on the COA Engine pattern. **No phase begins without its own approved scope.**

| Phase | Content | Exit gate | Risk |
|---|---|---|---|
| **P1 — Kernel formalization (additive)** | Define Posting Context + Posting Plan; add the additive header/line columns (nullable); add the central numbering derivation; push-based line builder alongside the existing one. **Zero behavior change.** | Full regression green; no posting output differs; **the authoritative GL-writer census (§4.7) is regenerated and reconciled, and the per-type idempotency occurrence keys (§3.2) are finalized** — both part of P1's definition of done | Very low |
| **P2 — Resolver adoption (COA Phase B)** | Migrate the ~41 `company_accounting_config` reads to `fn_resolve_account`, module by module, each with before/after GL-equality proof. Completes COA Engine certification. | Per-module GL equality; COA Engine certifiable | Medium |
| **P3 — Dimension push + hardcode removal** | Replace pull-based dispatch with the Posting Context; ~~remove the 16 hardcoded `account_code` literals~~ **(corrected 2026-07-25 by P3 Amendment A1: the schema-wide census finds 9 quoted literals, all in `fn_provision_company_accounting_config`, which writes no journal; zero exist in any of the 25 forward posting writers — the hardcode-removal exit gate is met on inspection).** COA Phase C remains deferred and design-only. | GL identical; zero literals in forward writers — **met** | Medium |
| **P4 — Tax boundary certification** *(re-scoped by Amendment A2; **Completed / Certified 2026-07-26**)* | ~~Introduce the TaxComponent shape; module code supplies it~~ **— retracted: no Tax Engine and no TaxComponent object exists, so the contract cannot be introduced without inventing one.** Replaced by a formal certification of the existing ownership boundary (§5.3.1): tax-aware writer census, non-computation proof, COA tax-account ownership, Posting Engine tax-line ownership, Tax Ledger persistence/reversal ownership, zero-variance GL↔ledger reconciliation, reversal provenance, and rounding consistency. **No migration; zero behaviour change.** | **Met** — test `090` (49 assertions); posting computes no tax; tax lines unchanged | Medium |
| **P5 — Totality enforcement** *(split by the P5 architecture review, 2026-07-26)* | **P5.0 Surface Closure — Completed. P5.1 migration — Completed. P5.2 enforcement — Completed / FULLY ENFORCED.** Migrations `20260726000002`–`20260726000012` and tests `092`–`102` route all writers through the frozen kernels, reject every non-kernel mutation, and preserve validation, messages, periods, numbering, lifecycle, header/line/tax/dimension/audit/inventory/status/reversal/preview output. Remaining writer census: 0. Canonical violation census: 0. Only the six exact sanctioned persistence functions contain ledger DML; no classifier member or maintenance exception was added. | P5.0, P5.1, and P5.2 **met**; guard **FULLY ENFORCED** | Low once P1–P4 land |
| **P6 — Subledger reconciliation (derived-view) — Blocked** | Investigation proves canonical Inventory cannot meet §5.4: stock/movement value differs from the configured Inventory control account and cost layers differ from stock (§5.4.1). No heuristic aggregation, adjustment, or engine change is permitted in P6. | **Not met** — governed Inventory acquisition/layer remediation and fresh approval are required before P6 can resume | Medium |
| **P7 — Reversal/correction consolidation** | One reversal kernel; structural `reversal_of_je_id`; retire string-convention detection. | Reversal equality across all types | Medium |
| **P8 — Certification** | Full invariant × transaction grid; concurrency suite; preview ≡ actual; deterministic replay. | **Posting Engine Certified** | — |
| **P9 — Performance/async (optional, deferred)** | Batch/background posting, queue/outbox dispatch. | Throughput; isolation preserved | Deferred |

Each phase is independently valuable, certifiable, and revertible.

---

## 8. Risks (carry into implementation)

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Blast radius — the §4.7 census (24 direct-insert forward writers to migrate) feeds every module and 4 Certified engines | High | Additive-first phases; per-module GL-equality proof; no big-bang cutover |
| R2 | JE numbering change breaks historical continuity | High | Frozen Option B: centralize derivation, never renumber history |
| R3 | Silent GL drift during resolver migration | High | COA equivalence method; per-module before/after GL comparison as the gate |
| R4 | String-convention dependencies (`LIKE '%-REV-%'`) break when numbering changes | Medium | Replace with structural columns in P1 *before* touching numbering |
| R5 | Tax boundary aspirational until the Tax Engine exists | Medium | **Resolved in part 2026-07-26 (P4, §5.3.1):** the *boundary* is no longer aspirational — it is certified by test `090`, and 19 of the 20 tax-aware posting writers compute nothing. The *contract* (`TaxComponent`) remains aspirational and is now explicitly deferred to the governed Tax Engine program, together with the seven duplicated save-layer calculators and the `fn_save_cash_sale` co-location |
| R6 | Preview/actual divergence | Medium | Single Posting Plan builder shared by both; equality is a certification gate |
| R7 | Concurrency regressions if the source lock is weakened | High | Lock-first admission frozen; concurrency suite is a gate |
| R8 | Multi-currency half-build | Medium | Reserve semantics only; implement nothing until the Currency Engine is scoped |
| R9 | Scope creep into subledger/tax ownership | Medium | Boundaries (§2) are normative and testable |
| R10 | Certification grid is large (20 × census) | Medium | Table-driven harness over `ref_posting_source_types` with the §6 applicability matrix (Applicable / N/A) |
| R11 | Silent duplicate period-driven journals for multi-JE types | High | Resolved in-spec: §3.2 occurrence keys (`RECURRING`, `CLOSE`) enforced by partial unique index |
| R12 | Certification blind spots / totality gaps from an incomplete writer list | High | Resolved in-spec: §4.7 authoritative census supersedes "23 paths"; regenerated as a P1 exit gate |

### Review Board findings — resolution status (all incorporated 2026-07-24)
- **HIGH-1 idempotency:** resolved — §3.2 occurrence-key contract.
- **HIGH-2 subledger reality:** resolved — §5.4 derived-view model; invariant 8 reworded (§6); no materialized subledger tables.
- **HIGH-3 writer census:** resolved — §4.7 authoritative census; P1 exit gate.
- **Clarifications (MED/LOW):** outbox dormancy (§3 rationale), preview≡actual + replay inputs (§3.1), reversal-in-closed-period (§5.5), applicability matrix (§6), numbering ownership separation (§4.5), status-less types (§3.2) — all incorporated.

### Remaining architectural risks requiring explicit approval before their phase
- **R2/R4 sequencing:** structural reversal/origin columns (P1) must land and be adopted before numbering derivation is centralized (still P1 internally) — confirm at P1 scoping.
- **R7:** any future proposal to move or weaken the source lock is a governed architectural review, not an implementation choice.
- **Totality guard interaction (P5):** the guard must whitelist legitimate maintenance/seed paths (canonical seed, demo reset) or those lanes break — to be designed at P5 scoping.

---

## 9. Consolidation philosophy (frozen)
Do not replace good existing infrastructure simply because it predates this architecture. **Consolidate, standardize, centralize, remove duplication, increase provability, minimize migration risk.** The objective is that every posting path consumes one mandatory kernel.
