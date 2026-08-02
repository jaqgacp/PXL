# IA-5 WP-4 — Detailed Order-Key Specification (Engineering Amendments EA-006, EA-007)

**Status:** COMPLETE — controlling WP-4 specification for M4 `inventory_event_order_keys`. **WP-4 is CERTIFIED 2026-07-31.** Its Brutal Audit failed on WP4-BA-001/WP4-BA-002, the bounded Brutal Fix closed both, the Brutal Audit Re-run passed, and the independent Certification Mission granted work-package certification. The amendment chronology below remains preserved as issued
**Amendment date:** 2026-07-31
**Owner / Domain:** Inventory Accounting — IA-5 Economic Costing Chronology Hardening
**Read when:** Reviewing the WP-4 contract, implementation, audit chronology, or certification
**Authority:** ADR-C01 (frozen), ECC-01 (accepted and owner approved), and the accepted IA-5 ECC Hardening Implementation Design
**Relationship:** Detailed engineering companion to `IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` §6.3, §15, §17 M4, §18, §21, §23, §24 row 4, and §25 — the exact parallel of `IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md` for WP-3. This document changes neither ADR-C01 nor ECC-01, redesigns no architecture, and authorises no work package.

---

## Engineering Amendment EA-006 — WP-4 Specification Completeness

**Reason.** The WP-4 Authorisation Gate (2026-07-31) returned **B — WP-4 AUTHORISATION REJECTED**. Architecture, dependencies, and prerequisites were found complete and satisfied; the rejection was for *specification* incompleteness. Nine implementation-affecting blockers were recorded: **B-1** (`resolution_state` required by §15/§18 but absent from §6.3), **B-2** (all-immutable contradicts V-35 supersession), **B-3** (no primary key), **B-4** (type *concepts*, no exact SQL contract), **B-5** (conditional nullability unenforced), **B-6** (1:1 `inventory_events` trigger unspecified and, if armed, breaks certified test `103`), **B-7** (no dormancy decision), **B-8** (no evidence allocation), **B-9** (§25 rollback premise false for WP-4).

**Correction.** EA-006 closes all nine: B-1 by §2.2, B-2 by §3, B-3 by §2.3, B-4 by §2.2 and §2.4, B-5 by §2.4, B-6 by §5, B-7 by §4, B-8 by §7, and B-9 by §6 together with the implementation-design reconciliation in §17 M4, §24 row 4, and §25.

---

## Engineering Amendment EA-007 — B-7 Dormancy Derivation Correction

**Amendment date:** 2026-07-31
**Reason:** The WP-4 Authorisation Re-run returned **B — REJECTED** on exactly one remaining blocker, **B-7**. EA-006 §4 reached its dormancy decision from a premise the catalog falsifies: it stated that `inventory_events` "carries **no** `activation_state`" and classified it as "dormancy is emptiness". Read from source, `inventory_events` carries `foundation_state text NOT NULL DEFAULT 'dormant'` with `inventory_events_foundation_state_check`, and `inventory_occurrences` carries the same. The derivation was wrong.

**Correction.** EA-007 rewrites **§4 only**. The four-class catalog pattern is read directly from source and the decision is re-grounded on the certified **per-event sidecar** precedent — `inventory_event_values`, `inventory_event_source_links`, and `inventory_event_allocations`, all created by the same certified IA-5 foundation migration `20260726000013`, all carrying guard, audit, and `ENABLE ALWAYS` immutability, and **none** carrying a dormancy column. EA-007 also corrects the derivation sentence in the EA-006 preamble and the §7.4 cross-reference.

**The decision is unchanged.** `inventory_event_order_keys` still carries no dormancy state column, because the catalog supports that outcome on the sidecar ground. **No column, constraint, index, trigger, count, or postcondition changes**, so §2.2 (31 columns), §2.4 (23 named constraints plus the primary key), §2.6, §5, §6.2, and §7.2 are untouched.

**Scope discipline.** EA-007 amends **one section**. It does not reopen B-1, B-2, B-3, B-4, B-5, B-6, B-8, or B-9 — all eight remain closed exactly as EA-006 left them. **No SQL, migration, schema, test, or database object was created or changed.** At EA-007 issuance, WP-4 remained unauthorised.

**No semantic change.** EA-006 changes no accounting policy, no ordering authority, no ADR-C01 rule, no ECC-01 rule, no component definition, no test-family definition, and no runtime behaviour. It assigns exact storage and governance representations to an object the accepted design already requires. **No SQL, migration, schema, test, or database object was created or changed.** At EA-006 issuance, WP-4 remained unauthorised.

**Derivation, not invention.** Every value below is read from a certified repository object — principally `public.inventory_events`, the per-event immutable evidence table M4 directly extends, and the certified WP-1/WP-2/WP-3 objects M4 references. Read from source, `inventory_events` carries `created_by uuid NOT NULL` and `created_at timestamptz NOT NULL DEFAULT clock_timestamp()`, carries the admission-root dormancy control `foundation_state text NOT NULL DEFAULT 'dormant'` with `inventory_events_foundation_state_check`, has RLS enabled with exactly one policy `inventory_events_read` (`SELECT` to `authenticated` `USING is_company_member(company_id)`), grants `SELECT` only to `authenticated`/`service_role`, and carries the `aa_`/`trg_`/`zz_` trigger triple with `zz_inventory_events_immutable` at `ENABLE ALWAYS`. The **per-event sidecars** `inventory_event_values`, `inventory_event_source_links`, and `inventory_event_allocations` carry that same control set but **no dormancy column** — the class M4 joins (§4).

---

## 1. Scope of WP-4

### 1.1 In scope (design §24 row 4 / §17 M4 — as reconciled by EA-006)

Exactly **one** new table, `public.inventory_event_order_keys`, plus its columns, keys, constraints, the five §18 indexes, RLS, its read policy, grants, the two governed triggers (§5.2), the single new WP-4 guard function (§5.3), and table-coverage registration (§7.5).

### 1.2 Out of scope for WP-4 (stop conditions carried forward)

No component resolver, no order-key writer, no comparator, no fingerprint, no boundary record, no replay path, no re-resolution procedure, no costing, no valuation, no projection, and **no trigger on `inventory_events`** (§5.4). No change to `inventory_events`, `inventory_valuation_scopes`, `inventory_valuation_scope_sequences`, `ref_inventory_event_source_types`, the WP-1 policy/version tables, the WP-3 stream objects, the Posting Engine, the Accounting Kernel, or the General Ledger. **A non-zero `inventory_events` count is a governance stop**, not a backfill exercise.

---

## 2. Governing Storage Contract — B-1, B-3, B-4, B-5

### 2.1 Object-level contract

| # | Attribute | Complete specification |
|---:|---|---|
| 1 | Name | `public.inventory_event_order_keys` |
| 2 | Purpose | The persisted **Economic Costing Chronology** sort key — the 14 ordering components, their canonical serialisation, and its digest — for one event under one resolution (design §6.3) |
| 3 | Accounting purpose | Derived ordering authority persisted as immutable evidence. It holds no cost, value, or journal effect |
| 4 | Ownership | Inventory Engine derives it; **the writer is M5/WP-5** (design §17 M5). WP-4 creates storage only |
| 5 | Chronology | ECC, distinct from the Accepted Event Chronology served by WP-3's allocator (design §5, §7) |
| 6 | ECC-01 traceability | §4.2 E1–E10, X1–X4; §4.3; §6.1; V-14/V-15; R-03 |
| 7 | ADR-C01 traceability | §3.2, §3.3, §6.2, §6.3 — no database-allocated value may order |
| 8 | Row population in WP-4 | **Zero.** M4 inserts no row |
| 9 | Consumers in WP-4 | **Zero** (design §21) |
| 10 | Cardinality | One **current** row per event, plus retained superseded resolutions (§3) |

### 2.2 Column contracts — exact SQL (closes B-1 and B-4)

All 31 columns. `Mut.` = mutability after insert.

| # | Column | Exact SQL type | Null | Default | Mut. | Component / contract |
|---:|---|---|---|---|---|---|
| 1 | `id` | `uuid` | `NOT NULL` | `gen_random_uuid()` | No | Surrogate PK (§2.3). Partition handle only; **never** an ordering input |
| 2 | `inventory_event_id` | `uuid` | `NOT NULL` | none | No | The event this key orders |
| 3 | `company_id` | `uuid` | `NOT NULL` | none | No | Tenant key; RLS predicate operand |
| 4 | `valuation_stream_id` | `uuid` | `NOT NULL` | none | No | ECC partition (design §6.2) |
| 5 | `economic_effective_at` | `timestamptz` | `NOT NULL` | none | No | **E1** economic instant, UTC µs |
| 6 | `source_precision_code` | `text` | `NOT NULL` | none | No | Declared source precision retained (N-01) |
| 7 | `economic_effect_class` | `text` | `NOT NULL` | none | No | **E3** class |
| 8 | `economic_effect_rank` | `smallint` | `NOT NULL` | none | No | **E3** rank resolved at admission |
| 9 | `source_type_rank` | `smallint` | `NOT NULL` | none | No | **E4** |
| 10 | `document_order_key` | `bytea` | `NOT NULL` | none | No | **E5**, length-prefixed, one registry algorithm |
| 11 | `source_line_ordinal` | `integer` | `NOT NULL` | none | No | **E6**, source-supplied |
| 12 | `transition_rank` | `smallint` | `NOT NULL` | none | No | **E7** |
| 13 | `occurrence_ordinal` | `bigint` | `NOT NULL` | none | No | **E8**, mirrors `source_occurrence_sequence` |
| 14 | `event_ordinal` | `integer` | `NOT NULL` | none | No | **E9**, mirrors `event_sequence` |
| 15 | `canonical_source_identity` | `bytea` | `NOT NULL` | none | No | **E10**, canonical encoding of `inventory_events_logical_event_uq`; **never DB-generated** |
| 16 | `correction_placement_class` | `text` | `NOT NULL` | none | No | `base`/`anchored`/`independent`/`counterfactual_only` |
| 17 | `correction_chain_depth` | `integer` | `NOT NULL` | none | No | **X1**, 0 = base fact |
| 18 | `correction_effective_at` | `timestamptz` | `NOT NULL` | none | No | **X2**, sentinel at depth 0 (N-08) |
| 19 | `correction_approved_at` | `timestamptz` | `NOT NULL` | none | No | **X3**, sentinel at depth 0 |
| 20 | `correction_identity` | `bytea` | `NOT NULL` | none | No | **X4**, sentinel at depth 0 |
| 21 | `correction_root_event_id` | `uuid` | **NULL allowed** | none | No | Root target; null **only** at depth 0 (§2.4 rule 9) |
| 22 | `order_policy_version_id` | `uuid` | `NOT NULL` | none | No | `V` element 1 |
| 23 | `registry_source_document_type` | `text` | `NOT NULL` | none | No | `V` element 2 — see §2.5 |
| 24 | `canonical_form_version_id` | `uuid` | `NOT NULL` | none | No | `V` element 3 |
| 25 | `scope_resolution_version_id` | `uuid` | `NOT NULL` | none | No | `V` element 4 |
| 26 | `correction_graph_version_id` | `uuid` | `NOT NULL` | none | No | `V` element 5 |
| 27 | `canonical_key_bytes` | `bytea` | `NOT NULL` | none | No | Length-prefixed injective serialisation of all 14 components (N-05) |
| 28 | `ecc_key_digest` | `bytea` | `NOT NULL` | none | No | `sha256(canonical_key_bytes)`, 32 bytes |
| 29 | `resolution_state` | `text` | `NOT NULL` | `'current'` | **Yes — §3** | `current`/`superseded`. **Closes B-1** |
| 30 | `created_by` | `uuid` | `NOT NULL` | none | No | Creating principal, exactly as on `inventory_events` |
| 31 | `created_at` | `timestamptz` | `NOT NULL` | `clock_timestamp()` | No | Creation evidence only. **Never** an ordering input |

No other column is authorised. In particular WP-4 adds **no** `activation_state` (§4) and **no** `updated_at`.

### 2.3 Primary key — closes B-3

| Kind | Exact identifier | Definition |
|---|---|---|
| Primary key | `inventory_event_order_keys_pkey` | `PRIMARY KEY (id)` |

`inventory_event_id` **cannot** be the primary key: §15's V-35 retains superseded resolutions, so an event may carry more than one row. 1:1 is enforced instead by the partial unique index `…_event_current_uq` (§2.6), exactly as design §18 specifies. The surrogate `id` follows the uniform repository convention (`inventory_events.id`, `inventory_valuation_scopes.id`, `inventory_valuation_streams.id`).

### 2.4 Constraints — exact identifiers and definitions (closes B-4, B-5)

| # | Kind | Exact identifier | Definition |
|---:|---|---|---|
| 1 | Unique | `inventory_event_order_keys_identity_uq` | `UNIQUE (valuation_stream_id, canonical_key_bytes)` — V-14/V-15 |
| 2 | Foreign key | `inventory_event_order_keys_inventory_event_id_fkey` | `FOREIGN KEY (inventory_event_id) REFERENCES inventory_events(id)` |
| 3 | Foreign key | `inventory_event_order_keys_company_id_fkey` | `FOREIGN KEY (company_id) REFERENCES companies(id)` |
| 4 | Foreign key | `inventory_event_order_keys_valuation_stream_id_fkey` | `FOREIGN KEY (valuation_stream_id) REFERENCES inventory_valuation_streams(id)` |
| 5 | Foreign key | `inventory_event_order_keys_correction_root_event_id_fkey` | `FOREIGN KEY (correction_root_event_id) REFERENCES inventory_events(id)` |
| 6 | Foreign key | `inventory_event_order_keys_order_policy_version_id_fkey` | `FOREIGN KEY (order_policy_version_id) REFERENCES inventory_event_order_policies(id)` |
| 7 | Foreign key | `inventory_event_order_keys_registry_source_document_type_fkey` | `FOREIGN KEY (registry_source_document_type) REFERENCES ref_inventory_event_source_types(source_document_type)` |
| 8 | Foreign key | `inventory_event_order_keys_canonical_form_version_id_fkey` | `FOREIGN KEY (canonical_form_version_id) REFERENCES inventory_canonical_form_versions(id)` |
| 9 | Foreign key | `inventory_event_order_keys_scope_resolution_version_id_fkey` | `FOREIGN KEY (scope_resolution_version_id) REFERENCES inventory_valuation_scopes(id)` |
| 10 | Foreign key | `inventory_event_order_keys_correction_graph_version_id_fkey` | `FOREIGN KEY (correction_graph_version_id) REFERENCES inventory_correction_graph_versions(id)` |
| 11 | Foreign key | `inventory_event_order_keys_created_by_fkey` | `FOREIGN KEY (created_by) REFERENCES auth.users(id)` |
| 12 | Check | `inventory_event_order_keys_economic_effect_class_check` | `CHECK (economic_effect_class = ANY (ARRAY['opening','increase','value_only','decrease','allowance']))` |
| 13 | Check | `inventory_event_order_keys_economic_effect_rank_check` | `CHECK (economic_effect_rank > 0)` |
| 14 | Check | `inventory_event_order_keys_source_type_rank_check` | `CHECK (source_type_rank > 0)` |
| 15 | Check | `inventory_event_order_keys_source_line_ordinal_check` | `CHECK (source_line_ordinal > 0)` |
| 16 | Check | `inventory_event_order_keys_transition_rank_check` | `CHECK (transition_rank > 0)` |
| 17 | Check | `inventory_event_order_keys_occurrence_ordinal_check` | `CHECK (occurrence_ordinal > 0)` |
| 18 | Check | `inventory_event_order_keys_event_ordinal_check` | `CHECK (event_ordinal > 0)` |
| 19 | Check | `inventory_event_order_keys_correction_placement_class_check` | `CHECK (correction_placement_class = ANY (ARRAY['base','anchored','independent','counterfactual_only']))` |
| 20 | Check | `inventory_event_order_keys_correction_chain_depth_check` | `CHECK (correction_chain_depth >= 0)` |
| 21 | Check | `inventory_event_order_keys_correction_root_check` | `CHECK ((correction_chain_depth = 0 AND correction_root_event_id IS NULL) OR (correction_chain_depth > 0 AND correction_root_event_id IS NOT NULL))` — **closes B-5** |
| 22 | Check | `inventory_event_order_keys_ecc_key_digest_check` | `CHECK (octet_length(ecc_key_digest) = 32)` |
| 23 | Check | `inventory_event_order_keys_resolution_state_check` | `CHECK (resolution_state = ANY (ARRAY['current','superseded']))` |

Twenty-three named constraints plus the primary key = **24 governed keys and constraints**. Every identifier is measured against PostgreSQL's 63-byte limit in §8; the longest is 61 bytes. `ecc_key_digest` is **not** given a generated expression: ADR-C01 §6.3 and design §2.2 bar database-derived ordering inputs, so the digest is supplied by the M5 resolver and only its length is constrained here.

### 2.5 `registry_source_document_type` — the one type concept that could not be honoured literally

Design §6.3 models the version vector as "UUID FK ×5". Read from source, the registry `ref_inventory_event_source_types` has **`PRIMARY KEY (source_document_type)` of type `text`** and carries no uuid version identifier; design §15 records registry versioning as "**per-type**". No uuid target therefore exists in the certified schema. The registry element of `V` is consequently stored as `registry_source_document_type text` with a foreign key to the registry's real key, exactly as the certified WP-1 tables `inventory_source_type_ranks` and `inventory_transition_ranks` already reference it. The vector still has five elements and still resolves registry authority; only the storage representation is corrected to a target that exists.

### 2.6 Indexes — design §18, verbatim

| Exact identifier | Definition | Role |
|---|---|---|
| `inventory_event_order_keys_ecc_idx` | `(valuation_stream_id, economic_effective_at, economic_effect_rank, source_type_rank, document_order_key, source_line_ordinal, transition_rank, occurrence_ordinal, event_ordinal, canonical_source_identity, correction_chain_depth, correction_effective_at, correction_approved_at, correction_identity)` | Performance. **E2 intentionally absent** — causal depth is population-derived |
| `inventory_event_order_keys_event_current_uq` | `UNIQUE INDEX (inventory_event_id) WHERE resolution_state = 'current'` | **Correctness** — 1:1 per current resolution; retains superseded rows |
| `inventory_event_order_keys_anchor_idx` | `(correction_root_event_id, correction_chain_depth)` | Performance — V-18/V-19 traversal |
| `inventory_event_order_keys_version_idx` | `(valuation_stream_id, order_policy_version_id, canonical_form_version_id)` | Performance — `V` resolution and F-11 detection |

`…_identity_uq` (§2.4 row 1) is the fifth §18 object and is declared as a `UNIQUE` **constraint**, so a duplicate raises `23505` rather than a silent tie.

---

## 3. Mutability Contract — closes B-2

**`inventory_event_order_keys` is immutable in every economic and identity column. Exactly one column may change after insert: `resolution_state`, and only in the direction `current` → `superseded`. `DELETE` is prohibited.**

| Field | May change after insert? |
|---|---|
| All columns except `resolution_state` (30 of 31) | **No** — immutable |
| `resolution_state` | **Yes**, and only `current` → `superseded` |

### 3.1 Why the blanket immutability rule is scoped, not universal

Design §6.3 marks every *component* immutable and §25 states "Never an in-place `UPDATE`". Both remain true and unweakened: **no ordering component, version reference, digest, or identity value may ever change.** §15's V-35 re-resolution does not edit a component — it writes *new* rows under the target version and demotes the prior rows to `superseded` evidence. Demotion is a governed lifecycle transition of a non-ordering state column, not a correction of an economic value.

This is the identical reasoning EA-003 §3.2 applied for WP-3: the design's immutability language is scoped to the object it governs, and a table whose sole governed lifecycle would otherwise be impossible receives a **dedicated `ENABLE ALWAYS` partial-mutability guard** instead of the blanket reject trigger. The certified `inventory_valuation_stream_sequences` is the standing precedent for that pattern.

### 3.2 The immutability trigger does **not** apply

`fn_ia5_reject_immutable_inventory_fact` — the `ENABLE ALWAYS` trigger that rejects every `UPDATE` and `DELETE` — **must not** be attached to `inventory_event_order_keys`. It would reject the V-35 demotion that §15 mandates. Its role is discharged instead by the §5.3 guard, which is stricter in every other respect: it rejects `DELETE` outright and rejects any `UPDATE` that touches any of the other 30 columns.

### 3.3 T-24 boundary for WP-4

Design §23 defines **T-24 — Immutability** as "`UPDATE`/`DELETE` rejection, both ops on every new table, `23514`". WP-4's contribution is bounded exactly as follows and must claim no more:

- `DELETE` on any row → **rejected**;
- `UPDATE` touching any column other than `resolution_state` → **rejected**;
- `UPDATE` setting `resolution_state` from `'superseded'` back to `'current'` → **rejected**;
- `UPDATE` setting `resolution_state` from `'current'` to `'superseded'` → **permitted**, and is the only permitted mutation.

---

## 4. Dormancy Contract — closes B-7 (corrected by EA-007, 2026-07-31)

**Decision: `inventory_event_order_keys` carries NO dormancy state column — neither `activation_state` nor `foundation_state` — and NO dormancy `CHECK`. It is a per-event sidecar, so its dormancy is *inherited* from `inventory_events`, exactly as for the certified sidecars `inventory_event_values` and `inventory_event_source_links`; it is additionally proven by emptiness, the absence of a writer, the absence of any grant, and zero consumers.**

> **EA-007 correction.** The WP-4 Authorisation Re-run found that EA-006 §4 justified this decision on a false premise — it asserted that `inventory_events` "carries **no** `activation_state`" and classified it as "dormancy is emptiness". Read from source, `inventory_events` **does** carry a dormancy control: `foundation_state text NOT NULL DEFAULT 'dormant'` with `inventory_events_foundation_state_check CHECK (foundation_state = 'dormant')`. EA-007 corrects the derivation. **The decision is unchanged**, because the catalog supports it on the correct ground — the per-event *sidecar* precedent — not on the ground EA-006 gave.

### 4.1 The governed pattern, read from the catalog

Design §21 requires an "`activation_state`/`foundation_state` `CHECK … = 'dormant'` on every new **policy and key** table, **matching the existing pattern**". The controlling words are *matching the existing pattern*. Read from source, the IA-5 catalog resolves into four classes, not three:

| Object class | Members | Dormancy mechanism | Where M4 sits |
|---|---|---|---|
| Governed **configuration / policy / version / identity** | `inventory_valuation_scopes`, `inventory_valuation_streams`, `inventory_precision_policies`, `inventory_accounting_profiles`, `inventory_cost_formula_policies`, and all six WP-1 tables (11 total) | **`activation_state`** `NOT NULL DEFAULT 'dormant'` + `CHECK` | Not M4 — M4 holds no policy, configuration, or identity |
| **Admission roots** | `inventory_occurrences`, `inventory_events` | **`foundation_state`** `NOT NULL DEFAULT 'dormant'` + `CHECK` | Not M4 — M4 admits nothing; it records a derivation about an already-admitted event |
| **Per-event sidecars** — rows that cannot exist without a parent `inventory_events` row | `inventory_event_values`, `inventory_event_source_links`, `inventory_event_allocations` | **None.** Full governed control set retained — guard, audit, and `ENABLE ALWAYS` immutability — but **no dormancy column** | **M4 sits here** |
| Mutable counters | `inventory_valuation_scope_sequences`, `inventory_valuation_stream_sequences` | None | Not M4 |

All three sidecars were created by the same certified IA-5 foundation migration `20260726000013` that created `inventory_events` and `inventory_occurrences`, and each carries three triggers with `fn_ia5_reject_immutable_inventory_fact` at `ENABLE ALWAYS` — the identical control set M4 adopts in §5.2. The sidecar class is therefore an **established, certified pattern**, not an exemption invented here.

`inventory_event_order_keys` is a per-event sidecar by construction: `inventory_event_id` is a `NOT NULL` foreign key to `inventory_events(id)` (§2.4 row 2), so **no order key can exist unless its parent event exists**. A dormancy flag would be unreachable rather than merely redundant: the parent's `foundation_state = 'dormant'` `CHECK` already gates every path by which a row could come into being, and a second flag on the child would also collide with the `resolution_state` lifecycle §3 governs.

### 4.2 The five dormancy facts WP-4 proves

1. **Inherited dormancy** — every row requires a parent `inventory_events` row, and `inventory_events.foundation_state` is `CHECK`-pinned to `'dormant'`;
2. `inventory_events` = 0;
3. `inventory_event_order_keys` contains **zero rows**;
4. **no writer exists** — the component resolver is M5/WP-5, so in WP-4 nothing can produce a key; and
5. **no grant and no consumer** exists (§5.5, design §21 "Consumers: **Zero**").

### 4.3 Activation rule

WP-4 performs no activation and creates no activation path. Activation of the ECC key follows activation of its parent admission root, which design §21 places behind a separate authorised migration and its four preconditions — recorded ECC-01 acceptance, a passed reopened evidence gate closing C-01, explicit IA-6 authorisation, and an enabling migration. Those preconditions apply unchanged and are not reopened here.

---

## 5. Triggers, Guard, Security — closes B-6

### 5.1 What WP-4 does **not** create

**WP-4 creates no trigger on `inventory_events`.** See §5.4.

### 5.2 Trigger strategy — exactly two triggers

| Trigger | Timing / events | Function | Enabled |
|---|---|---|---|
| `aa_inventory_event_order_keys_guard` | `BEFORE INSERT OR UPDATE OR DELETE FOR EACH ROW` | `fn_ia5_guard_inventory_order_key_foundation()` | **`ENABLE ALWAYS` (`A`)** |
| `trg_inventory_event_order_keys_audit` | `AFTER INSERT FOR EACH ROW` | `fn_audit_trigger()` | `ENABLE` (origin, `O`) |

Audit is `AFTER INSERT` only, per design §20. `ENABLE ALWAYS` on the guard is what makes the §3 mutability contract survive `session_replication_role = replica`, mirroring the certified WP-3 allocator guard.

### 5.3 The WP-4 guard function

WP-4 creates **one new** function: `public.fn_ia5_guard_inventory_order_key_foundation()` — `SECURITY DEFINER`, `SET search_path = public`, taking the same `pg_advisory_xact_lock(hashtextextended(TG_TABLE_NAME || ':' || company_id::text, 0))` serialisation the existing IA-5 guards take. It must be a **new** function, not an edit of an existing guard — the WP-1 and WP-3 precedent, preserving design §25 and risk **R-15**.

It enforces exactly:

1. `DELETE` is rejected — an issued order key is permanent evidence;
2. on `UPDATE`, any change to a column other than `resolution_state` is rejected;
3. on `UPDATE`, a `resolution_state` transition other than `'current'` → `'superseded'` is rejected;
4. `company_id` must equal the referenced event's `company_id`;
5. `company_id` must equal the referenced stream's `company_id`;
6. `correction_root_event_id`, when present, must reference an event in the same company.

Rules 4–6 are the P-02 company-isolation half design §19 requires. `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role` on the function (design §19).

### 5.4 Why no trigger is added to `inventory_events` — the B-6 resolution

Design §17 M4 and §24 row 4 assign a "1:1 deferrable enforcement" trigger on `inventory_events` to M4. **EA-006 moves that trigger to M5** for one decisive, verifiable reason:

> The trigger would enforce that every admitted event carries an order key. The only object that can produce an order key is the **M5/WP-5 component resolver**, which does not exist at M4. Arming it at M4 therefore makes every admission fail. Verified from source: `fn_ia5_record_dormant_inventory_occurrence` inserts into `inventory_events`, and **certified test `103` invokes it 19 times**. Arming this trigger at M4 would break certified test `103`, the certified IA-5 foundation, and the regression lane.

The 1:1 obligation itself is **not weakened or deferred** — it is enforced from the order-key side, at M4, by the partial unique index `…_event_current_uq` (§2.6), which is precisely what design §18 specifies for "1:1 per current resolution". What moves to M5 is only the *event-side totality* check, whose precondition is the M5 writer.

**Consequence — M4 becomes purely additive.** No existing object is altered, so risk **R-15** and design §25's rollback premise hold for WP-4 exactly as they held for WP-1, WP-2, and WP-3. This also closes **B-9** (§6).

### 5.5 RLS, grants, audit

| Control | Requirement |
|---|---|
| RLS | Enabled |
| Policy | Exactly one — `inventory_event_order_keys_read`, `SELECT` to `authenticated` `USING (is_company_member(company_id))`, matching `inventory_events_read` verbatim |
| Read grants | `GRANT SELECT` to `authenticated` and `service_role` |
| Write grants | `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, `service_role`. Design §19: "**No role can insert an order key**" |
| Writer path | Owner-mediated `SECURITY DEFINER` only. **No such writer exists in WP-4** |
| Audit | `fn_audit_trigger()` `AFTER INSERT` (design §20) |

---

## 6. Migration and Rollback Contract — closes B-9

### 6.1 Migration preconditions (fail-closed)

M4 executes in one transaction and stops before mutation unless every fact holds. A failed precondition is a **governance stop** — never authority to backfill, repair, or infer.

1. `public.inventory_events` exists and contains exactly **zero** rows.
2. `inventory_event_order_keys` does not already exist.
3. WP-1's six policy/version tables exist, remain **empty**, and retain their RLS, audit, immutability, and dormancy controls.
4. WP-2's six registry columns exist with the exact single `IA5_CERTIFICATION` authority row.
5. WP-3's `inventory_valuation_streams` and `inventory_valuation_stream_sequences` exist, remain **empty**, and retain their controls.
6. Every foreign-key target exists: `companies`, `auth.users`, `inventory_events`, `inventory_valuation_streams`, `inventory_event_order_policies`, `ref_inventory_event_source_types`, `inventory_canonical_form_versions`, `inventory_valuation_scopes`, `inventory_correction_graph_versions`.

### 6.2 Migration postconditions

Structural and registry-local only: exact 31-column shape; the 24 governed keys and constraints; the four indexes plus the unique constraint; RLS, policy, and grant state; both governed triggers present with the exact enablement of §5.2; the table created **empty**; `inventory_events` unchanged and still zero; no client/service write privilege; zero runtime consumers; and **no trigger added to `inventory_events`**.

### 6.3 Rollback — B-9 resolution

**WP-4 rollback, in order:**

1. `DROP TABLE public.inventory_event_order_keys` (drops its constraints, indexes, policy, and both triggers)
2. `DROP FUNCTION public.fn_ia5_guard_inventory_order_key_foundation()`

Because §5.4 removes the `inventory_events` trigger from M4, **WP-4 alters nothing existing**. Design §25 row 1 — "Drop the new tables in reverse dependency order; IA-5 is byte-identical to its certified state because nothing existing was altered" — therefore applies to WP-4 unmodified, and §25 row 3's constraint-trigger recovery moves to M5 with the trigger. There is no event, backfill, replay, journal, projection, or costing action to reverse, because WP-4 creates none.

---

## 7. Evidence Allocation — closes B-8

This section is the WP-4 analogue of EA-002 §23.1 for WP-2 and EA-003 §4 for WP-3.

### 7.1 Authoritative test-family contract

Design §23's family definitions remain the only authoritative T-number definitions and are **not renumbered**. WP-4 supplies the structural and fixture portion of exactly two existing families.

| Family | Authoritative purpose (§23) | WP-4 evidence boundary |
|---|---|---|
| **T-03 — Duplicate identity** (V-14/F-06) | Two facts, one canonical identity → `23505`, both rejected; failure = silent tie-break | **Structural:** `…_identity_uq` exists as a `UNIQUE` **constraint** on `(valuation_stream_id, canonical_key_bytes)`; `…_event_current_uq` exists as a partial unique index. **Fixture:** two rows sharing one `(valuation_stream_id, canonical_key_bytes)` are rejected `23505`; a second `current` row for one event is rejected `23505`; the same event may hold one `current` and one `superseded` row without collision. **Excluded:** WP-4 proves no comparator, no ordering outcome, and no tie-break behaviour — there is no comparator until WP-7 |
| **T-24 — Immutability** | `UPDATE`/`DELETE` rejection, `23514` | **Structural:** the guard exists at `ENABLE ALWAYS`; no `fn_ia5_reject_immutable_inventory_fact` trigger is attached (§3.2); zero client write grants. **Fixture:** `DELETE` rejected; `UPDATE` of any of the 30 non-state columns rejected; `'superseded'` → `'current'` rejected; `'current'` → `'superseded'` permitted (§3.3). **Excluded:** WP-4 claims no re-resolution procedure — V-35 execution is later work |

**"Order-key structural completeness"** is WP-4's combined completion evidence spanning those two families. It is **not** a third test family.

### 7.2 Evidence ownership

| Class | Owner | Content |
|---|---|---|
| **Structural (persistent)** | The M4 migration | Preconditions (§6.1); exact 31-column shape; 24 keys/constraints; four indexes; RLS, policy, grants; both triggers; table empty; zero consumers; `inventory_events` unchanged and trigger-free |
| **Fixture (rolled back)** | The WP-4 structural test | Certification-only company/user/item/scope/stream/event/order-key rows created **inside the test transaction** and removed by its final `ROLLBACK`, proving identity uniqueness, 1:1-per-current, the mutability asymmetry, and company isolation **non-vacuously** |
| **Implementation** | The WP-4 implementation record | Applied shape, assertions, validation lanes, and boundary review, recorded in a governed document |
| **Certification** | The isolated WP-4 rollback test | Against the M4-applied database: reassert preconditions **including exact total row counts**, drop the table then the guard function, verify the pre-M4 state and unchanged WP-1/WP-2/WP-3 controls, then `ROLLBACK` so M4 remains installed |

### 7.3 Fixture constructibility — verified

The T-03 fixture is constructible at WP-4 **without** WP-5's resolver. `inventory_event_order_keys` has no writer, so the test inserts rows directly as owner, supplying literal `bytea` values for `document_order_key`, `canonical_source_identity`, `canonical_key_bytes`, and a 32-byte `ecc_key_digest`. The required parent `inventory_events` rows are produced by the certified `fn_ia5_create_dormant_policy_bundle` / `fn_ia5_record_dormant_inventory_occurrence` path already exercised 19 times by test `103`, inside the same rolled-back transaction. No component derivation, comparator, or future object is required. This constructibility check is mandatory before authorisation — the exact failure **EA-005** corrected for WP-3.

### 7.4 Runtime exclusions — what WP-4 may **not** claim

WP-4 must not claim, in any test name, assertion message, report, or status line, that it proves: T-01 deterministic tuple; T-02 admission validation; T-05 line/occurrence order; T-15 replay repeatability; T-16 fingerprint; T-19 concurrency schedules; T-21 prohibited-input census; T-22 beyond the structural company-isolation controls; T-26 beyond fresh replay; T-27 dormancy beyond the five facts in §4.2; or **any** part of **C-01**. C-01 remains open pending WP-9's evidence package.

### 7.5 Coverage obligation

Guard `075` fails when a new `public` base table is unregistered, so WP-4 must add `inventory_event_order_keys` to `PXL_TABLE_COVERAGE_MATRIX.md` and the guard `075` registry in the same change set — the precedent WP-1, WP-2, and WP-3 all set.

---

## 8. Identifier Safety

Every WP-4 identifier is measured against PostgreSQL's 63-byte limit — the check **EA-001** established for WP-2.

| Identifier | Bytes |
|---|---:|
| `inventory_event_order_keys_registry_source_document_type_fkey` | **61** |
| `inventory_event_order_keys_correction_placement_class_check` | 59 |
| `inventory_event_order_keys_scope_resolution_version_id_fkey` | 59 |
| `inventory_event_order_keys_correction_graph_version_id_fkey` | 59 |
| `inventory_event_order_keys_canonical_form_version_id_fkey` | 57 |
| `inventory_event_order_keys_correction_chain_depth_check` | 55 |
| All other identifiers | ≤ 56 |

The longest is **61 bytes**, within the limit. Every implementation-chosen identifier must be re-measured before implementation.

---

## 9. Consistency Review

| Check | Result |
|---|---|
| All nine gate blockers closed | **Yes** — B-1 §2.2 · B-2 §3 · B-3 §2.3 · B-4 §2.2/§2.4 · B-5 §2.4 row 21 · B-6 §5.4 · **B-7 §4 (re-grounded by EA-007 on the certified per-event sidecar precedent)** · B-8 §7 · B-9 §6.3 |
| EA-007 changed only §4 and its two cross-references | **Yes** — no column, constraint, index, trigger, count, or postcondition moved; B-1…B-6, B-8, B-9 untouched |
| New blocker introduced? | **None identified** — every value is an exact figure derived from a certified object |
| Architecture unchanged | **Yes** — no tuple component, rank, partition rule, or ordering authority altered |
| ADR-C01 / ECC-01 changed | **No** — cited only |
| Accounting semantics unchanged | **Yes** — no cost, value, method, or journal effect |
| Posting Engine / Kernel preserved | **Yes** — no journal path, mutator, or totality trigger touched |
| Certified WP-1 / WP-2 / WP-3 preserved | **Yes** — referenced as foreign-key targets only; none altered |
| Scope expanded? | **No** — still exactly one new table (§17 M4); the `inventory_events` trigger is *moved to M5*, not added elsewhere |
| Implementation detail beyond the repaired specification | **None** — no SQL, migration, test, or database object created |

## Decision

**A.**

**EA-006 AND EA-007 COMPLETE — WP-4 SPECIFICATION AND EVIDENCE COMPLETE FOR M4**

**Historical EA-007 decision, preserved as issued: WP-4 REMAINS UNAUTHORISED.** EA-006 is documentation only and grants no implementation authority. A separate WP-4 Authorisation Re-run must independently verify that the nine blockers are resolved and issue that decision.

## Historical Subsequent Lifecycle Status — after Brutal Fix, 2026-07-31

The separate WP-4 Authorisation Re-run subsequently authorised WP-4. Migration
`20260731000019` and tests `109`/`110` then implemented the exact contract above.
The independent Brutal Audit verified the executable contract but returned
**FAILED** on only WP4-BA-001 (current authority-chain contradiction) and
WP4-BA-002 (stale generated schema summary). At that decision WP-4 was not
brutally fixed, not audit-re-run, and not certified. The bounded Brutal Fix
closed both blockers without changing SQL, migration logic, tests, runtime,
accounting, Posting, Kernel, ADR, or ECC. WP-4 is now **AUTHORISED, IMPLEMENTED,
BRUTALLY FIXED, NOT AUDIT RE-RUN, and NOT CERTIFIED**.

## Certification Outcome — 2026-07-31

The independent Brutal Audit Re-run subsequently passed and verified
WP4-BA-001 and WP4-BA-002 closed with no implementation regression. The
separate Lifecycle Step 7 Certification Mission re-executed fresh migration
replay, focused tests `109`/`110` (2 files / 101 assertions), the full pgTAP
regression (110 / 2,613), and canonical accounting (30 / 748). Direct catalog
inspection confirmed the exact §1–§7 M4 contract, zero rows, zero consumers,
SELECT-only grants, and no event-side trigger; canonical debit and credit both
remain `2,411,134.80` with `0.00` variance. Protected M4/test hashes remain
unchanged. No blocking finding remains.

**Certification decision: WP-4 CERTIFIED.** This certifies only the WP-4 work
package. It does not certify the IA-5 permanent foundation, Inventory module,
Inventory Engine, WP-5, IA-6, hosted deployment, or product readiness.
WP4-BA-003 and WP4-BA-004 remain unchanged non-blocking documentation findings.
