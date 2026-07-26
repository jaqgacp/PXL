# PXL Posting Engine — Phase P3 Specification (Dimension Push, Fiscal Close, Preview Convergence, Manual-JE Control; COA Phase C design-only)

**Status:** Frozen — Approved, **Amendment A1 applied 2026-07-25** (documentation-only; §4 fiscal-close design retracted and replaced with the certified architecture — see §4 and §4.8). Implementation progress: **P3a landed 2026-07-25** (migration `20260725000001`, test 087); **P3b completed by existing architecture 2026-07-25, no implementation required**; **P3c landed 2026-07-25** (migration `20260725000002`, test 088); **P3d landed 2026-07-25** (migration `20260725000003`, test 089 — resolver convergence only; full Preview ≡ Actual remains P8). **Phase P3 is complete.** §8 COA Phase C remains design-only and deferred.
**Authority:** Tier 3 phase specification under the frozen Tier 2 [PXL_POSTING_ENGINE_SPEC.md](PXL_POSTING_ENGINE_SPEC.md). Elaborates roadmap phase **P3**; does not reopen or redesign any frozen decision.
**Owner / Domain:** Accounting Core
**Applies To:** The account/dimension resolution and preview seams of every forward posting writer, the year-end close writer, the manual-JE writer, and the preview path
**Read When:** Scoping, implementing, or certifying Posting Engine Phase P3
**Do Not Read For:** Tax computation (P4), totality enforcement (P5), subledger reconciliation (P6), reversal consolidation (P7), final certification (P8) — those are their own phases
**Last Reviewed:** 2026-07-25 (authored after COA Engine certification PASS-WITH-OBSERVATIONS; grounded in the live `pg_proc` state)
**Relationship:** Consumes the **Certified** COA Engine ([PXL_COA_ENGINE_SPEC.md](PXL_COA_ENGINE_SPEC.md)) resolver and the **Certified** Dimension, Number Series, Audit & Immutability, and Permissions/RLS engines. Implements the frozen roadmap line "P3 — Dimension push + hardcode removal (COA Phase C)" (`PXL_POSTING_ENGINE_SPEC.md` §7) and the frozen contracts §2.3 (push-not-pull), §3.1 (single Posting Plan / preview≡actual), §4.5 (Option-B numbering), §5.2 (Dimension Engine consumption), and COA §5 (Posting Control Contract). **Supersedes no document.**

> **Nature.** This is a **consolidation and hardening** specification, not a redesign and not a feature expansion. Every P3 change is additive-first and must leave posted accounting output **byte-for-byte identical**. Freezing this spec does **not** authorize implementation; a separate implementation scope must be approved per phase. The one forward-looking section — **§8 COA Phase C** — is **design-only**: it requires a governed amendment to the frozen COA contract and is explicitly **not** implemented by P3.

---

## 1. Objectives

P3 removes the last two "pull/hardcode" seams that survived P1–P2D and formalizes preview and manual-JE control, so that **account resolution and dimension propagation are both push-based, single-sourced, and provably identical to today's output**.

| # | Objective | Frozen basis | P3 disposition |
|---|---|---|---|
| O-A | Replace the pull-based dimension dispatch (`fn_add_posting_line`, hardcoded `VB`/`CP`) with explicit push of all six dimensions | §2.3, §5.2 | **Implement** |
| O-B | Ensure no forward posting writer resolves accounts by hardcoded `account_code` literal | §7 (P3 hardcode removal), COA §4.1, §5 | **SATISFIED by existing architecture (Amendment A1, 2026-07-25)** — census proves zero literals in all 25 forward writers; fiscal close uses validated per-year master data. No resolver keys are added. See §4 |
| O-C | Converge Preview and Posting on one Posting Plan; eliminate preview's direct `company_accounting_config` reads (certification observation O2) | §3.1 | **Implement (config-duplication removal); full preview≡actual gate remains P8** |
| O-D | Wire the delivered-but-dormant manual-postable control (`fn_assert_manual_postable`) into manual-JE posting (observation O3) | COA §5 | **Implement** |
| O-E | Design the future inventory/COGS/variance resolver + warehouse qualifier (observation O4) | COA §4.1–§4.3 | **Design only — deferred; needs governed COA amendment** |

**Non-goals (P3):** no tax contract (P4), no totality guard (P5), no subledger tables (P6), no reversal changes (P7), no multi-currency, no new business behavior, **no schema change in what P3 implements** (the two new close keys are seed rows in the existing `ref_mapping_key`/`account_mapping`, not schema changes).

---

## 2. Relationship to the frozen architecture (non-redesign)

P3 changes **seams**, never the frozen pipeline (§3), the Posting Plan (§3.1), the engine boundaries (§2), the numbering model (§4.5), or the COA resolver contract. Specifically:

- The frozen pipeline stage **[3] Dimension validation** and **[5] Account resolution** are unchanged in *ordering*; P3 only changes *how inputs reach them* (push instead of pull).
- The COA resolver contract is consumed unchanged. **Amended A1 (2026-07-25):** P3 adds **no** mapping keys. The originally proposed `RETAINED_EARNINGS` / `INCOME_SUMMARY` keys are withdrawn — the first is not expressible under the frozen qualifier set (RE is per-fiscal-year) and the second has no referent in the implemented accounting model. See §4.2.
- The Dimension Engine guard `fn_je_line_dimensions_guard` remains the sole validator; posting still **passes, never validates** dimensions (§5.2).

**Design challenge (answered):** *Does bundling preview convergence (§3.1, a P8 gate) and manual control (COA §5 Phase B/C) into P3 reopen the roadmap?* No. P3 implements only the **consolidation subset** — removing preview's config duplication and enforcing an already-delivered validator — leaving the **full preview≡actual and manual-control certification** to P8. This is elaboration, not reordering. Confirmed as Open Question Q1 for the reviewer.

---

## 3. Dimension Push Architecture (O-A)

### 3.1 Current state (the defect)
`fn_add_posting_line(p_je_id, p_line_number, p_account_id, p_description, p_debit, p_credit, p_branch_id, p_department_id, p_cost_center_id)` accepts **only three** of the six governed dimensions. Internally it **pulls** the remaining dimensions for two hardcoded document types:

```
fn_add_posting_line(...)                       ← PULL model (to be retired)
  ├─ SELECT reference_doc_type,id FROM journal_entries WHERE id = je
  ├─ IF type = 'VB' → SELECT dept,cc,project,location,fe FROM vendor_bills
  ├─ ELSIF type = 'CP' → SELECT dept,cc,project,location,fe FROM cash_purchases
  ├─ core insert with COALESCE(param_dept, pulled_dept), COALESCE(param_cc, pulled_cc)
  └─ IF pulled project/location/fe present → UPDATE the just-inserted line
```

Three structural problems: (1) **project/location/functional_entity cannot be pushed at all** through this helper — they arrive *only* via the pull; (2) only `VB`/`CP` are recognized — every other document type silently loses the pulled trio; (3) it violates the frozen **push-not-pull** principle (§2.3): the kernel reaches back into source tables *by document type*.

### 3.2 The push model — ownership
The **document writer owns dimension resolution.** It resolves the document's six header dimensions once into the in-memory **Posting Context**, then supplies each line's dimensions explicitly. The line helper becomes a pure sink: it writes exactly the six dimensions handed to it and reaches into no source table.

```
Posting Context (per posting invocation)
  header_dims := { branch, department, cost_center, project, location, functional_entity }   ← resolved ONCE
        │
        ▼   for each planned line:
  line_dims := COALESCE(line_override_dim, header_dim)   ← per dimension, explicit
        │
        ▼
  fn_add_posting_line(je, line_no, account, desc, dr, cr,
                      branch, department, cost_center, project, location, functional_entity)  ← PUSH: all six, no pull
```

### 3.3 Inheritance & override rules (normative)
- **Per-dimension resolution.** Each of the six dimensions resolves independently as `COALESCE(line_level_value, header_level_value)`. A line may override any subset; unoverridden dimensions inherit the header.
- **Branch is special.** `branch_id` is the company/branch isolation dimension and is always the document's branch (already passed explicitly today); it is never inherited from a line override in current writers, and P3 preserves that.
- **No implicit source lookup.** A dimension that is null after `COALESCE(line, header)` is written as null — never back-filled from a source table by the helper.
- **Determinism.** Resolution is a pure function of the Posting Context; identical inputs ⇒ identical line dimensions.

### 3.4 Line behavior & the helper contract
`fn_add_posting_line` gains three parameters (`p_project_id`, `p_location_id`, `p_functional_entity_id`), all `DEFAULT NULL`, and **drops the internal pull dispatch entirely**. Because the new parameters default to null and today's callers pass the same first-nine arguments, the signature change is **additive and backward compatible** at the call site. The follow-up `UPDATE` on `journal_entry_lines` is eliminated (the six dimensions are written in the single insert), which also removes a redundant write.

### 3.5 Validation order (unchanged ordering, corrected inputs)
```
[builder] resolve header dims → per-line dims (push)          ← NEW: explicit, in the writer / Posting Plan
   ▼
[3] Dimension validation — fn_je_line_dimensions_guard         ← UNCHANGED trigger; now sees pushed values
   ▼  (rejects cross-company / invalid dimension, fail-closed)
[8] Persistence (single insert carries all six dimensions)
```
The Dimension Engine guard fires on insert exactly as today. P3 does not add, weaken, or reorder validation; it only guarantees the guard sees **pushed** values instead of **pulled** ones.

### 3.6 Audit behavior
Unchanged. `fn_audit_trigger` records the line insert as today. Because the follow-up `UPDATE` is removed, the audit trail becomes *cleaner* (one insert row instead of insert+update for VB/CP lines) — an audit-neutral improvement that must be noted as a **non-GL** trail difference (see §3.8 and Risk R2).

### 3.7 Data-flow diagram (VB example — before vs after)
```
BEFORE (pull):  VB writer → fn_add_posting_line(…, branch, NULL, NULL)
                                   └─ pulls dept/cc/project/location/fe from vendor_bills → line

AFTER (push):   VB writer resolves header dims once → fn_add_posting_line(…, branch, dept, cc, project, location, fe)
                                   └─ writes exactly those six → line   (no source read, no UPDATE)
```
Resulting line dimensions are **identical** for every VB/CP line, because the pushed values come from the same `vendor_bills`/`cash_purchases` header columns the pull used.

### 3.8 Backward compatibility & byte-for-byte guarantee
- **GL identity:** debit, credit, account, and all six dimensions per line are unchanged for every document type. VB/CP lines receive the same header dimensions (now pushed); all other writers already pass their dimensions explicitly and are untouched.
- **Trail difference (non-GL):** VB/CP lines are now written in one insert rather than insert-then-update. This changes the *audit event shape* (fewer rows), not any GL value. Certification asserts GL equality on `journal_entry_lines` dimension columns and treats the trail-shape change as an approved, documented consequence.
- **Migration is per-writer**, each with a before/after dimension-equality proof (§11).

**Design challenge (answered):** *Why not keep the pull and just extend it to all document types?* Rejected — it entrenches the push-not-pull violation, couples the kernel to every source schema, and cannot express line-level overrides. Push is the frozen §2.3 principle and the model the migrated Sales writers already use.

---

## 4. Fiscal Close Architecture (O-B) — **AMENDED A1 (2026-07-25): objective satisfied by existing architecture; original design retracted**

> **Amendment A1 notice.** Everything §4 originally specified rested on an assumed fiscal-close design that has never existed in this codebase. A board-approved architecture review (2026-07-25), run against the live `pg_proc` catalog, falsified every mechanism claim in the original §4.1–§4.7. Spec Risk **R8** pre-authorized this outcome — *"the census is authoritative over the prose figure"* — and the census has now been run and discharged. The obsolete design is retracted below and replaced with the certified architecture. **The O-B objective itself is satisfied: no forward posting writer resolves accounts by `account_code` literal.** The retraction record is §4.8. **No implementation was performed or is required.**

### 4.1 Certified state (verified against live `pg_proc`, 2026-07-25)
`fn_close_fiscal_year` resolves Retained Earnings from **`fiscal_years.retained_earnings_id`** — a per-fiscal-year, FK-constrained master-data column — and validates it inline before any insert: the account must exist, belong to the closing company, be `account_type = 'equity'`, be `is_postable`, and be `is_active`. It contains **zero `account_code` literals** and reads **zero `company_accounting_config`**.

This is **master-data ownership**, the same sanctioned resolution mechanism P2C certified for the four Inventory writers. It is **not** a resolver bypass. Certification observation O1, which named fiscal close "the last resolver bypass among forward writers", is **withdrawn as factually incorrect**.

Because the COA guard `fn_coa_change_policy_guard` keeps `is_active` synchronised with `lifecycle_status` on every lifecycle change (`NEW.is_active := (NEW.lifecycle_status = 'active')`), the writer's `is_active` test is **equivalent to** a `lifecycle_status = 'active'` test. No validation gap exists relative to `fn_resolve_account`.

### 4.2 Resolver keys — **not required; not to be added**
`RETAINED_EARNINGS` and `INCOME_SUMMARY` are **withdrawn**. Neither may be added under P3.

- **`INCOME_SUMMARY` has no referent.** No income-summary account, table column, or function reference exists anywhere in the schema. Introducing one is a **redesign of accounting behavior**, not a migration (see §4.3).
- **`RETAINED_EARNINGS` is not expressible.** RE is selected **per fiscal year**. The frozen `account_mapping` qualifier set is `branch_id, document_type, party_id, item_id, item_group_id, tax_profile_id` — there is **no `fiscal_year_id` qualifier**. A company-scoped key resolves identically for the canonical set today (all five companies use `3200`) but silently removes per-year RE selection; making it faithful would require amending frozen COA §4.2–§4.3. Routing RE through a company-scoped key would therefore **move authority away from an already-validated master-data field and downgrade it**.

### 4.3 Year-end close journal design (certified — one-step, direct to Retained Earnings)
The implemented close is **one step**, not two:
1. **Close each revenue and expense account directly.** One line per P&L account with a non-zero net balance, posted on the side that zeroes it, ordered deterministically by `account_code`.
2. **One balancing line to Retained Earnings** — credit for net income, debit for a net loss.
3. Nominal accounts start the next year at zero; RE carries forward. All periods of the year are locked and the year is marked `closed`.

There is **no Income-Summary sweep and no clearing account**. Converting this to a two-step close would change the closing journal's line count, line order, and structure — changing posted accounting output. That is a redesign requiring its own approved scope, and it collides with the existing `fn_post_manual_je` guard reserving `closing` entries for the year-end close.

### 4.4 Numbering (certified — writer-local `CLOSE-YYYY-NNNN`)
Close journals are numbered by a **writer-local sequence**: `'CLOSE-' || YYYY || '-' || LPAD(seq,4,'0')`, seeded by `SELECT COUNT(*)+1` over the company's existing `CLOSE-YYYY-%` journals and advanced by a probe loop until unused. Uniqueness is backstopped by `journal_entries_company_id_je_number_key`. The close writer does **not** call `fn_next_document_number`; the earlier claim that it used Option-B Number Series allocation is retracted.

### 4.5 Idempotency & re-close safety (certified)
Re-close is prevented by **`fiscal_years.status = 'closed'`**, which raises on a second attempt. There is **no `CLOSE` occurrence key and no partial unique index**; `ux_journal_entries_live_source` excludes `CLOSE`, and close journals carry `reference_doc_id = NULL`. The earlier claim of a frozen `(company_id, fiscal_year)` occurrence key is retracted.

### 4.6 Future multi-book compatibility (design reservation only — premise corrected)
Reserve — do **not** implement — the seam for parallel books (e.g., statutory vs. management, or IFRS vs. tax). The correct extension point is **`fiscal_years`**, which already scopes RE per company *and* per year, not `account_mapping`. P3 neither adds `book_id` nor changes any table.

### 4.7 Sequence (year-end close — certified)
```
Operator → fn_close_fiscal_year(company_id, fiscal_year_id, close_date DEFAULT NULL)
   ├─ [admission] can_admin_company · fiscal year exists · status <> 'closed'
   ├─ [resolve]   RE := fiscal_years.retained_earnings_id
   │                 └─ assert: in company · equity · postable · active   (fail-closed)
   ├─ [period]    close_date within the year · covering fiscal_period resolved
   ├─ [aggregate] net P&L movement over entry_class regular/adjusting/opening
   ├─ [number]    je_number := 'CLOSE-YYYY-NNNN'  (writer-local sequence)
   ├─ [assert]    balanced (total_debit == total_credit)
   ├─ [persist]   header (entry_class='closing', reference_doc_type='CLOSE',
   │              reference_doc_id NULL, branch NULL) + one line per P&L account
   │              (direct INSERT, ordered by account_code) + one RE balancing line
   └─ [finalize]  lock every period of the year · mark the year closed
```

Close journals post at **company level**: `branch_id` is NULL and all six governed dimensions are NULL on every line. This is the confirmed answer to §9 Q4.

**Design challenge (re-answered):** *Add close keys to `company_accounting_config`, or resolve straight from the chart?* Neither. A third option shipped and is stronger than both: **per-fiscal-year master data on `fiscal_years`**, validated at post time and FK-constrained. It carries no well-known-code coupling and, unlike a company-scoped mapping key, expresses per-year RE selection.

### 4.8 Amendment A1 — retraction record (document history)
Retracted from §4 on 2026-07-25 as falsified by the live catalog:

| Retracted claim | Live evidence |
|---|---|
| §4.1 close resolves RE/IS via `WHERE account_code = '<literal>'`; "the last resolver bypass" | Zero `account_code` literals in any of the 25 forward posting writers |
| §4.2 add `RETAINED_EARNINGS` + `INCOME_SUMMARY` company-scoped keys | RE is per-fiscal-year; no `fiscal_year_id` qualifier exists; `INCOME_SUMMARY` has no referent |
| §4.3 two-step close (nominal → Income Summary → RE) | One-step close; zero income-summary lines across all five canonical closes |
| §4.4 numbering via `fn_next_document_number` (Option B) | Writer-local `CLOSE-YYYY-NNNN` sequence |
| §4.4 / §4.5 `CLOSE` occurrence key + partial unique index | No such index; idempotency is `fiscal_years.status='closed'` |
| §4.7 sequence steps `resolve(RETAINED_EARNINGS)` / `resolve(INCOME_SUMMARY)` / `fn_next_document_number` | None of these calls exist |

**R8 census, discharged (whole `public` schema).** Total quoted `account_code = '…'` literals: **9**, all in `fn_provision_company_accounting_config` (provisioning; writes no journal). `fn_seed_company_coa` and `fn_provision_pxl_standard_coa` compare `account_code` to columns/variables, not literals. Views and matviews: zero. **Forward posting writers: zero.** The frozen Tier 2 §7 figure of "16 hardcoded literals" reconciles to 9, none in any posting path.

**Forward-writer resolution mechanism (25 writers, exhaustive):** 11 use the certified COA resolver; 14 use master-data column ownership (4 inventory, 3 fixed-asset/amortization/revenue-recognition, 3 banking, petty cash, manual JE, fiscal close); **0** use `account_code` literals; **0** read `company_accounting_config`.

---

## 5. Preview Convergence (O-C)

### 5.1 Current state
Actual posting resolves accounts through the certified resolver (P2A–P2D). **Preview does not** — `fn_gl_impact_payload` and `fn_preview_sales_invoice_gl_impact_aud053_core` still read `company_accounting_config` directly (certification observation O2). Preview accuracy currently rests entirely on the config≡`account_mapping` equivalence sync; if the two ever diverge (e.g., an effective-dated mapping change), preview could silently drift from actual.

### 5.2 Target — one Posting Plan, two consumers (frozen §3.1)
The frozen artifact is the **Posting Plan** (§3.1): a deterministic, serializable value of header attributes + ordered lines (resolved account, amounts, six dimensions, `line_role`, provenance). **Preview and actual consume the same Plan builder; preview never duplicates posting logic.**

```
                 ┌─────────────── shared builder (stages 0-authorize … 7-assert) ───────────────┐
Source doc ─────▶│  admission → validation → period → dimensions(push) → tax assembly →           │
                 │  ACCOUNT RESOLUTION (fn_resolve_posting_account) → Posting Plan → invariants    │
                 └───────┬───────────────────────────────────────────────────────────┬───────────┘
                         │ preview: return Plan (no persistence, no lock)              │ actual: persist Plan (stage 8+)
                         ▼                                                             ▼
                 GL-Impact preview                                             posted journal
```

### 5.3 P3 scope vs P8 gate (phasing — normative)
- **P3 implements (the O2 fix):** the preview functions **stop reading `company_accounting_config`** and resolve accounts through `fn_resolve_posting_account`, so preview and actual draw every account from the **same resolver**. This removes the duplication and the drift risk with a bounded, low-risk change.
- **P8 certifies (the full gate):** a single shared Plan builder used verbatim by both paths, proven by the **preview ≡ actual** equality test and `source_fingerprint` equivalence across the whole census. Extracting one physical builder function for every writer is a larger refactor and is **not** required to close O2; P3 delivers resolver-sourced preview, P8 delivers builder-identity.

### 5.4 Determinism, fingerprint, failure
- **Determinism:** preview and actual resolve with the **same `as_of`** and the same context → the same account (COA §4.5 effective dating). A later-dated re-resolve is a different operation, not a preview mismatch.
- **`source_fingerprint`:** the P1 column continues to hash the resolved Plan inputs; any preview/actual input divergence is flagged (frozen §3.1). P3 changes no fingerprint semantics.
- **Fail-closed:** preview resolves through the same fail-closed resolver, so a missing mapping surfaces at **preview time** as a configuration defect (the intended behavior) rather than only at posting.

**Design challenge (answered):** *Fully unify the builder in P3?* Deferred to P8. The O2 risk is the **config/resolver duplication**, which resolver-sourcing eliminates now; builder-identity is a certification concern best proven once, at P8, over the full census.

---

## 6. Manual Journal Control (O-D)

### 6.1 Current state
`fn_assert_manual_postable` was delivered in COA Phase A but has **zero callers** (certification observation O3). Manual JE posting (`fn_post_manual_je`) validates user-supplied `account_id`s against `chart_of_accounts` but does **not** enforce the manual-posting rule that **a manual JE may not target a control (subledger-owned) account** (COA §5).

### 6.2 Control-account protection rules (COA §5, normative)
A manual JE line's target account must be a **postable, active, effective, leaf** account that is **not** a control account (`is_control_account = false`) — control-account movement must originate from the owning subledger, never an ad-hoc manual line. `fn_assert_manual_postable` already encodes this; P3 **wires it in**.

### 6.3 Validation order & wiring point
```
fn_post_manual_je(...)
   ├─ authorize (Permissions) · period open (Period)
   ├─ for each line:  fn_assert_manual_postable(company, account_id)      ← NEW wiring (fail-closed)
   │                     ├─ postable leaf? active? effective?  else RAISE
   │                     └─ is_control_account? → RAISE (subledger-owned)
   ├─ balance assertion (existing)
   └─ persist + audit (existing)
```
Wiring is a **pure tightening at the validation seam** — it adds a fail-closed guard before persistence and changes no amount, account (for valid input), dimension, or number.

### 6.4 Failure handling & compatibility
- **Fail-closed:** a manual line targeting a control/non-leaf/inactive account now raises with a precise, centrally-generated message naming the account.
- **Backward-compatibility caveat (must be surfaced):** unlike O-A/O-B/O-C, this guard is **intentionally behavior-changing for previously-invalid input** — a manual JE that illegitimately posted to a control account **will now be rejected**. This is a correctness improvement, not a byte-for-byte-preserving change. Certification must (a) prove no *canonical/valid* manual JE is affected (GL identical for legitimate input), and (b) record the rejection of illegitimate input as the intended new guard behavior. Flagged as Open Question Q2 (grandfathering of any existing non-conforming data) and Risk R4.

**Design challenge (answered):** *Is this "no feature expansion"?* Yes — it enforces an already-specified COA §5 rule using an already-delivered validator; it adds no capability, only closes a known control gap.

---

## 7. Cross-cutting: unified validation order, failure, determinism

P3 keeps the frozen pipeline (§3) ordering intact. The unified per-writer order after P3:

```
[0] admission (authorize, source lock, status, idempotency)      ← frozen
[1] module validation                                            ← frozen
[2] period open (fail fast)                                      ← frozen
[3] dimension validation (guard sees PUSHED dims)                ← O-A changes inputs, not order
[4] tax component assembly (unchanged in P3; P4 owns tax)         ← frozen
[5] account resolution (resolver; incl. RE/IS for close)         ← O-B extends key set
[6] Posting Plan construction (preview & actual share)           ← O-C
[7] invariant assertions (balance, sign, company, rounding;
      + manual-postable for MANUAL)                              ← O-D wires one guard
[8..] persist → subledger(derived) → audit → commit              ← frozen
```

- **Deterministic:** every P3 change is a pure function of the Posting Context / resolver inputs.
- **Fail-closed:** unresolved account (incl. RE/IS), invalid dimension, or non-postable manual target aborts the whole posting.
- **Auditable:** existing `fn_audit_trigger` coverage is retained; the only trail-shape change is the removed VB/CP follow-up `UPDATE` (§3.8).

---

## 8. COA Phase C — Future Inventory Resolver (DESIGN ONLY — deferred)

> **This section is design-only. P3 implements none of it. It requires a governed amendment to the frozen COA contract and MUST NOT be built under the P3 implementation scope.** Inventory writers remain exactly as **P2C-certified**.

### 8.1 The gap (certification observation O4)
Inventory/COGS/variance accounts are owned **per item** (`items.inventory_account_id`, `items.cogs_account_id`) and **per warehouse** (`warehouses.gl_inventory_account_id`, `gl_variance_account_id`). The resolver cannot express these today because (a) there are **no inventory keys** in `ref_mapping_key`, and (b) `account_mapping` has **no `warehouse_id` qualifier** (its qualifiers are branch/document_type/party/item/item_group/tax_profile — COA §4.2). Item-scoped resolution is *partially* expressible (an `item_id` qualifier exists); warehouse-scoped resolution is **not** expressible without a contract change.

### 8.2 Proposed keys (future)
`INVENTORY`, `COGS`, `INVENTORY_VARIANCE` (and possibly `INVENTORY_IN_TRANSIT`), each `expected_account_type = asset` (variance = expense/asset per policy), resolved with an `item_id` and/or `warehouse_id` context.

### 8.3 Proposed contract amendment — warehouse qualifier (governed)
Add `warehouse_id` (nullable) to `account_mapping`'s qualifier set and to the §4.3 specificity vector. Proposed specificity insertion (most-significant-first), to be ratified by COA governance:

```
document_type > party > item > item_group > warehouse > tax_profile > branch
```

This is a **change to a frozen contract** (§4.2/§4.3 uniqueness index and specificity ordering) and therefore a **governed COA architectural amendment**, not an implementation choice.

### 8.4 Governance — why this is not P3
The frozen COA spec permits *adding keys* by migration (§4.1) but **not** silently changing the qualifier set or specificity order; those are frozen (§4.2–§4.3). Item/warehouse routing needs the latter → it must pass a governed COA review that proves it does not weaken determinism, ambiguity rejection, or the partial-unique-index guarantee. P3 deliberately excludes it.

### 8.5 Migration strategy (future, sketch)
Additive-first, mirroring P2: (1) add keys + `warehouse_id` qualifier + specificity update behind an equivalence proof; (2) project existing `items.*`/`warehouses.*` account ownership into `account_mapping` (item- and warehouse-scoped bindings) via a one-time backfill + sync; (3) migrate inventory writers to the resolver **module-by-module with per-writer byte-for-byte GL proof**; (4) retain the master-data columns as the writable authority during transition (COA §3.2 pattern). Each step independently valuable and revertible.

### 8.6 Backward compatibility (future)
Until fully migrated, inventory writers keep reading item/warehouse master columns (P2C-certified). The projection is equivalence-tested (resolver result == master column) before any writer is switched — exactly the P2A–P2D method. No accounting output changes at any step.

**Design challenge (answered):** *Should P3 add just an `item_id`-scoped inventory key and defer only the warehouse part?* Rejected for P3 — a partial adoption that resolves item-scoped inventory but not warehouse-scoped transfers would create **two ownership models for one domain**, worse than the clean, uniform master-data ownership P2C certified. Inventory should migrate as a whole, under one governed COA amendment, or not at all.

---

## 9. Open Questions

- **Q1 — P3/P8 boundary for preview & manual control.** This spec scopes preview convergence to *resolver-sourcing* (O2 fix) and manual control to *validator wiring*, leaving builder-identity and full manual-control certification to P8. Does the architecture board accept this split, or should preview builder-identity move into P3?
- **Q2 — Manual-control grandfathering.** **ANSWERED by data audit 2026-07-25: no grandfathering required.** Across the whole database, accounts flagged `is_control_account` = **0** and journal lines on any control account = **0**; `is_control_account` defaults to `false` and is never set. No non-conforming data exists. **Consequential caveat for P3c:** because no account is flagged, wiring the guard would be **vacuous** against the canonical set — P3c must include a fixture that flags a control account and proves rejection, and the board should separately decide whether canonical/production charts ought to flag control accounts at all.
- **Q3 — Close-key seeding source.** **MOOT (Amendment A1).** No close keys are added; RE is owned by `fiscal_years.retained_earnings_id`. See §4.2.
- **Q4 — Dimension override policy for close/manual/system journals.** **ANSWERED 2026-07-25:** the year-end close posts at **company level** — `branch_id` NULL and all six governed dimensions NULL on every closing line (verified across all five canonical closes). P3 preserves this. Whether that is the intended long-term target remains a board decision.
- **Q5 — COA Phase C sequencing.** Does Phase C (governed amendment, §8) precede or follow P4–P8? It is independent of the Posting Engine phases and could be scheduled separately.

---

## 10. Risk Assessment

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Dimension push changes a VB/CP line dimension (silent GL drift) | High | Per-writer before/after dimension-equality proof over `journal_entry_lines`; canonical + regression must stay byte-for-byte green |
| R2 | Removing the VB/CP follow-up `UPDATE` alters the audit trail shape | Low | Documented as an approved non-GL trail change; assert GL identity, not row-event identity |
| R3 | New signature for `fn_add_posting_line` breaks a caller | Medium | New params default null; keep the old 9-arg call valid; add overload-safe deployment; grep all callers as an exit gate |
| R4 | Manual-control wiring rejects previously-accepted (illegitimate) input | Medium | Intended tightening; prove no *valid* manual JE affected; resolve Q2 grandfathering before enabling |
| R5 | Preview resolver-sourcing changes a previewed account vs the old config read | Low | Config≡mapping equivalence already certified (P2); assert preview account == actual account per document |
| R6 | ~~Close-key equivalence gap (resolved RE/IS ≠ old literal account)~~ | **RETIRED (A1)** | No close keys are added and no literal exists; there is nothing to equivalence-test. See §4.2/§4.8 |
| R7 | Scope creep from §8 into P3 implementation | High | §8 is design-only and gated behind a governed COA amendment; P3 acceptance explicitly excludes any inventory-writer or `account_mapping`-schema change |
| R8 | "~16 literals" (frozen §7) vs live finding (concentrated in fiscal close) | **DISCHARGED (A1)** | Census run 2026-07-25: **9** quoted literals schema-wide, all in `fn_provision_company_accounting_config` (writes no journal); **0** in any of the 25 forward posting writers; 0 in views. The risk fired as written — the prose figure and its location were both wrong, and the census governed. See §4.8 |

---

## 11. Implementation Phases (proposed sub-phases; each additive, revertible, separately certifiable)

| Sub-phase | Content | Exit gate | Risk |
|---|---|---|---|
| **P3a — Dimension push** ✅ **LANDED 2026-07-25** | Extend `fn_add_posting_line` to six explicit dimensions; delete the VB/CP pull + follow-up UPDATE; push header/line dims from VB/CP writers | All writers' line dimensions byte-for-byte identical; guard non-vacuous; zero pull dispatch remains | High (R1–R3) |
| **P3b — Fiscal-close hardcode removal** ✅ **COMPLETED BY EXISTING ARCHITECTURE 2026-07-25 (no implementation required)** | ~~Seed `RETAINED_EARNINGS`/`INCOME_SUMMARY`; migrate `fn_close_fiscal_year` to the resolver~~; **re-inventory literals** | Exit gate met on inspection: **zero `account_code` literals in forward writers** (census, §4.8). Fiscal close already uses validated per-year master-data ownership. No migration, seed, or test was written | — |
| **P3c — Manual-JE control** ✅ **LANDED 2026-07-25** | Wire `fn_assert_manual_postable` into `fn_post_manual_je` | Valid manual JEs unchanged (byte-for-byte, all pre-existing messages preserved); control targets fail-closed; guard proven non-vacuous; Q2 resolved — no grandfathering needed. Migration `20260725000002`, test 088 (30 assertions) | Medium (R4) |
| **P3d — Preview convergence (O2 subset)** ✅ **LANDED 2026-07-25** | Preview functions resolve via `fn_resolve_posting_account`; stop reading `company_accounting_config` for account resolution | Met: the one projecting preview path resolves AR_TRADE/VAT_OUTPUT through the adapter on the invoice date; preview account == actual posted account; payload byte-for-byte identical; preview side-effect-free; drift detection proven by controlled reversion. The rollback-preview paths and the posted-journal renderer were certified unchanged (documented ownership models). Migration `20260725000003`, test 089 (38 assertions) | Low (R5) |
| *(deferred)* **COA Phase C** | §8 — governed COA amendment; **not P3** | Separate governed review | — |

Each sub-phase lands independently with its own certification test (mirroring the 083–086 pattern) and its own before/after GL/dimension proof.

**P3a implementation record (2026-07-25).** Landed as migration `20260725000001_posting_engine_p3a_dimension_push.sql` with certification test `supabase/tests/087_posting_engine_p3a_dimension_push_test.sql` (28 assertions). Caller census (live `pg_proc`): six direct callers of `fn_add_posting_line` — `fn_post_vendor_bill`, `fn_post_cash_purchase_source_locked_impl`, `fn_post_payment_voucher`, `fn_post_receipt`, `fn_post_withholding_remittance`, and the wrapper `fn_add_sales_invoice_posting_line`. Only the first two posted journals typed `'VB'`/`'CP'`, so only they were affected by the retired pull; the rest post `'PV'`/`'OR'`/`'WHTREM'`/`'SI'`/`'REV'` and are unchanged. §3.4's "additive and backward compatible" signature note required one correction in execution: PostgreSQL treats the 9- and 12-argument forms as distinct functions and rejects a 9-argument call against both at CALL time with `function ... is not unique`, so the 9-argument function is dropped and re-created with twelve parameters (prior `REVOKE`/`GRANT` re-applied verbatim) rather than added as an overload. `fn_add_posting_line_core_20260718` (the pre-P3A 3-dimension inner insert) is left in place, now unreferenced and grantable only to `postgres`; retiring it is cleanup outside the P3a scope and is offered for review.

---

## 12. Certification Plan

**Method (unchanged from P2):** additive change → full regression + canonical must stay green with **byte-for-byte** GL/dimension equality; a per-sub-phase structural certification test proves the invariant and is non-vacuous.

| Gate | Proof |
|---|---|
| Dimension equality | Per document type, every posted line's six dimensions equal the pre-P3 output (canonical 055/057/058 + regression); guard rejects a cross-company dimension (non-vacuous) |
| Zero pull dispatch | No function contains the `VB`/`CP` source-dimension pull; `fn_add_posting_line` reads no source table |
| Close hardcode removal | **MET ON INSPECTION (A1, 2026-07-25).** `fn_close_fiscal_year` contains no `account_code` literal and reads no `company_accounting_config`; the schema-wide census finds zero literals in all 25 forward posting writers. ~~resolves RE/IS via the adapter; RE/IS equivalence (R6)~~ — withdrawn; no keys are added. Close journal output is unchanged because nothing was changed |
| Manual control | `fn_post_manual_je` calls `fn_assert_manual_postable`; valid JE unchanged; control/non-leaf target raises |
| Preview convergence | Preview functions call the resolver and read no `company_accounting_config`; previewed account == posted account per document |
| Invariants preserved | Frozen §6 invariants 1–20 remain green across the census; four foundational engines + COA remain Certified-green |
| Regression/canonical | Full regression and canonical lanes green; no skipped tests |

**Certification artifacts:** new pgTAP tests, one per *implemented* sub-phase, added to the regression and canonical lanes and the Accounting Test Book, exactly as `083`–`086` were. Landed: **`087`** (P3a). **P3b produces no test artifact** — it required no implementation (A1). P3c and P3d take the next sequential numbers when they are approved and implemented.

---

## 13. Recommendation

# ✅ READY FOR P3 IMPLEMENTATION

The P3 design is **backward compatible, deterministic, fail-closed, auditable, and byte-for-byte accounting-compatible** for O-A/O-C, with the one intentional, well-bounded tightening in O-D (manual-control, non-GL-affecting for valid input). It consumes the Certified COA and Dimension engines without redesigning any frozen contract, and it quarantines the sole contract-changing idea (§8 inventory/warehouse resolver) as **design-only, deferred, and governed**. **Amended A1 (2026-07-25):** O-B adds no resolver keys — it is satisfied by the existing architecture.

**Conditions on the approval (must be satisfied before or during implementation):**
1. **Q2 (manual-JE grandfathering) — SATISFIED** by the 2026-07-25 data audit: zero control-flagged accounts and zero journal lines on control accounts. P3c must instead prove its guard **non-vacuous** with a fixture that flags a control account (§9 Q2).
2. Treat **§8 (COA Phase C)** as out of P3 scope; it proceeds only under a separate governed COA amendment (R7).
3. Enforce the **byte-for-byte** exit gates in §11–§12 per sub-phase; any GL/dimension drift is a stop-the-line failure.

Order **P3a → P3b → P3c → P3d** is retained and **not renumbered**. Current standing: **P3a landed**; **P3b completed by existing architecture (no implementation)**; **P3c is the next implementation phase**, pending approval; P3d follows.

**Amendment A1 (2026-07-25) is documentation-only.** No production code, migration, seed, schema, SQL, or test was written or changed. Await approval before beginning P3c.
