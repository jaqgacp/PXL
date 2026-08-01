# IA-5 WP-3 — Detailed Stream and Allocator Specification (Engineering Amendments EA-003, EA-004, EA-005)

**Status:** COMPLETE — controlling WP-3 specification for both M3 objects (EA-003 allocator, EA-004 stream, EA-005 T-22 evidence correction). **WP-3 was AUTHORISED and IMPLEMENTED on 2026-07-30** by migration `20260730000018` and tests `107`/`108`, **passed its independent Evidence Gate on 2026-07-31, and is CERTIFIED 2026-07-31** (work-package certification only)
**Amendment date:** 2026-07-30
**Owner / Domain:** Inventory Accounting — IA-5 Economic Costing Chronology Hardening
**Read when:** Reviewing WP-3 authorisation, or implementing WP-3 / migration M3 once separately authorised
**Authority:** ADR-C01 (frozen), ECC-01 (accepted and owner approved), ECC-01 Formal Owner Acceptance, and the accepted IA-5 ECC Hardening Implementation Design
**Relationship:** Detailed engineering companion to `IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` §6.2, §17 M3, §18, §23, and §24 WP-3 — the exact parallel of `IA-5_WP-2_DETAILED_REGISTRY_AUTHORITY_SPECIFICATION.md` for WP-2. This document changes neither ADR-C01 nor ECC-01, redesigns no architecture, and authorises no work package.

---

## Engineering Amendment EA-003 — WP-3 Specification Completeness

**Reason.** The WP-3 Authorisation Gate (2026-07-30) returned **B — WP-3
AUTHORISATION REJECTED**. Architecture and dependencies were found complete and
satisfied; the rejection was for *specification* incompleteness. Four documented
blockers were recorded:

| Blocker | Finding |
|---|---|
| **F-1** | The design's own table accounting (§17 M9: "9 new tables (6 from M1, 2 from M3, 1 from M4)") requires **two** new tables from M3, but §6 "Target Logical Data Model" models only one — `inventory_valuation_streams` (§6.2). The second object appears only as an unnamed phrase: "stream-keyed accepted allocator" (§17, §18, §24), "stream allocator" (§5), "re-key to stream" (§3.1). It had a purpose and a primary key (§18) but no name, columns, mutability, dormancy, validation, audit, or rollback contract. |
| **F-2** | The allocator is mutable by design (§3.1, §5), yet the design's blanket rules — §6.2's `ENABLE ALWAYS` reject trigger, §19's "`GRANT SELECT` only … immutability triggers make even the owner unable to `UPDATE`", and §21's dormancy `CHECK` on "every new policy and key table" — would, if applied literally, make allocation impossible. No rule stated which applied. |
| **F-3** | §24 row 3 assigns T-22 and T-26, but §23 defines T-22 as proving that cross-company **edges and orders** are rejected. WP-3 creates no edge, comparator, or order and so cannot discharge T-22 as written. No WP-3 evidence allocation existed — the exact defect **EA-002** was raised to fix for WP-2. |
| **F-4** | Design §29's subsequent-status note and §30 item 4 still described WP-2 as uncertified and named the WP-2 Certification Mission as the current phase, contradicting §24 row 2 within the same document. |

**Correction.** EA-003 closes F-1, F-2, and F-3 in this document and reconciles
F-4 in the implementation design. It is a **documentation-only** amendment.

**No semantic change.** EA-003 changes no accounting policy, no ordering
authority, no ADR-C01 rule, no ECC-01 rule, no work-package boundary, no
migration count, no table count, no test-family definition, no scope, and no
runtime behaviour. It assigns exact storage and governance representations to an
object the accepted design already requires, and allocates existing test
obligations to their authoritative families. **No SQL, migration, schema, test,
or database object was created or changed.** WP-3 remains unauthorised.

**Derivation, not invention.** Every contract below is derived from an existing
certified repository object or an existing governing rule. The primary template
is the certified `public.inventory_valuation_scope_sequences` — the scope-keyed
allocator this object re-keys to the stream per design §3.1 and ECC-01 §15(4).
Its read-from-source shape is:

| Column | Type | Null | Default |
|---|---|---|---|
| `valuation_scope_id` | `uuid` | NO | — |
| `company_id` | `uuid` | NO | — |
| `last_sequence` | `bigint` | NO | `0` |
| `updated_at` | `timestamptz` | NO | `clock_timestamp()` |

with `PRIMARY KEY (valuation_scope_id)`, `FOREIGN KEY (company_id) REFERENCES companies(id)`,
`FOREIGN KEY (valuation_scope_id) REFERENCES inventory_valuation_scopes(id)`,
`CHECK (last_sequence >= 0)`, RLS enabled, one policy
`inventory_valuation_scope_sequences_read` — `SELECT` to `authenticated` using
`is_company_member(company_id)` — grants limited to `authenticated`/`service_role`
`SELECT`, **no immutability trigger**, and **no `activation_state` column**.

---

## Engineering Amendment EA-004 — `inventory_valuation_streams` Specification Completeness

**Amendment date:** 2026-07-30
**Reason:** The WP-3 Final Authorisation Gate returned **B — REJECTED** for
exactly one remaining gap. EA-003 raised M3's *second* table to full governance
standard but left M3's *first* table, `inventory_valuation_streams`, at design
§6.2's twelve-row sketch, whose entire type specification is one cell: "UUID PK;
`company_id`, `item_id`, `scope_code` all NOT NULL". The gate recorded two
findings:

| Finding | Detail |
|---|---|
| **G-1** | Undefined for streams: primary-key column name and default; SQL types; whether `created_by`/`created_at` exist; foreign keys; the mechanism enforcing §6.2's own cross-table validation; immutability-trigger and RLS-policy identities |
| **G-2** | EA-003 §3.3 stated that streams "retains whatever dormancy treatment design §6.2 already specifies" — but §6.2 specifies none, so a live question was recorded as resolved. The repository pattern is genuinely split, so the answer cannot be inferred |

**Correction.** EA-004 specifies `inventory_valuation_streams` completely in
**§8** (governing specification), **§9** (dormancy contract, resolved outright —
no deferral, no forward reference), and **§10** (mutability contract). Both M3
tables now carry identical governance depth.

**Scope discipline.** EA-004 amends **one object**. It does not reopen the
allocator specification (§2–§3), redesign WP-3, change the two-table scope, or
touch architecture, ADR-C01, or ECC-01. §8.6 names the single guard function
that hosts both tables' validations; the allocator behaviours EA-003 §3.2 already
fixed are carried across **unchanged** — EA-004 adds a host, not a behaviour.

**No semantic change.** No accounting policy, ordering authority, table count,
migration count, test-family definition, work-package boundary, or runtime
behaviour changes. **No SQL, migration, schema, test, or database object was
created or changed.** WP-3 remains unauthorised.

**Derivation, not invention.** Every value below is read from the certified peer
`public.inventory_valuation_scopes` — the valuation-identity object streams
directly succeeds in partition role — or from the standing IA-5 pattern
confirmed across all fourteen guarded Inventory tables.

---

## Engineering Amendment EA-005 — T-22 Evidence Allocation Correction

**Amendment date:** 2026-07-30
**Reason:** The WP-3 Final Authorisation Decision returned **B — REJECTED** on
exactly one implementation-affecting contradiction, **B-1**. The repository
simultaneously required the streams guard to reject any stream whose item
belongs to another company (§8.4 rule 2, from design §6.2), *and* required the
T-22 fixture to prove that "two companies each hold a stream for the same
`(item_id, scope_code)`" (§4.1, repeated in design §23.2). Because
`public.items.company_id` is `NOT NULL` and no item spans companies, an item
belongs to exactly one company, so the second company's stream is rejected by
the guard before the unique key is ever reached. **The mandated fixture was
unconstructible**, forcing an implementation engineer either to weaken guard
rule 2 — defeating the P-02 company isolation that risk R-11 depends on — or to
invent replacement evidence.

**Correction.** EA-005 corrects the **evidence allocation only**, in the two
places that carried it (§4.1 and design §23.2). The corrected fixture proves the
same invariant by constructible means:

- two companies each hold a stream carrying the **same `scope_code` for their
  own item** — proving `scope_code` is not globally unique and that partition
  identity is company-scoped;
- a stream naming **another company's item is rejected**, which is the positive
  proof of guard rule 2 rather than a contradiction of it;
- a duplicate `(company_id, item_id, scope_code)` is rejected `23505`; and
- an allocator row whose `company_id` differs from its stream's is rejected.

Constructibility is verified against the live schema:
`inventory_valuation_scopes` is unique on
`(company_id, item_id, scope_code, effective_from)`, so two companies may each
hold a scope version with the same `scope_code` for their own item, satisfying
§8.4 rule 3 for both streams.

**No contract change.** EA-005 changes **no** validation rule, guard behaviour,
column, key, constraint, trigger, mutability, dormancy, grant, RLS expectation,
audit role, replay role, rollback order, implementation boundary, runtime
exclusion, table count, architecture, ADR-C01 rule, or ECC-01 rule. Company
isolation is strengthened in evidence and unchanged in behaviour. **No SQL,
migration, schema, test, or database object was created or changed.** WP-3
remains unauthorised.

---

## 1. Scope of WP-3

### 1.1 In scope (design §24 row 3 / §17 M3 — authoritative)

Exactly **two** new tables and their attached controls:

1. `public.inventory_valuation_streams` — the permanent partition identity.
   Sketched by design §6.2; **specified to full governance standard in §8–§10
   by Engineering Amendment EA-004.**
2. `public.inventory_valuation_stream_sequences` — the stream-keyed accepted
   allocator, specified in §2–§3 below.

Plus, for each: constraints, RLS, its read policy, grants, the governed triggers
named in §3 and §8.5, the single new WP-3 guard function (§8.6), and
table-coverage registration (§4.5). WP-3's evidence allocation is §4.

### 1.2 Out of scope for WP-3 (stop conditions carried forward)

No stream resolver function; no allocator function; no change to
`fn_ia5_record_dormant_inventory_occurrence` (that is M5/WP-5); no
`inventory_event_order_keys` (M4/WP-4); no comparator, order key, document key,
fingerprint, or replay path; no index on any ECC object; no change to
`inventory_events`, `inventory_valuation_scopes`,
`inventory_valuation_scope_sequences`, `ref_inventory_event_source_types`, the
WP-1 policy/version tables, the Posting Engine, the Accounting Kernel, or the
General Ledger; no method state, costing, valuation, or projection; no
production source-type enablement; no hosted application. **A non-zero
`inventory_events` count is a governance stop**, not a backfill exercise.

### 1.3 Legacy allocator disposition — F-2 resolution (8)

Design §3.1 classifies `inventory_valuation_scope_sequences` as
"**Supersede** (re-key to stream; old table retained read-only)". EA-003 fixes
the only reading compatible with design §25 and risk **R-15**
("Nothing existing is altered"):

> "Retained read-only" is **passive**. WP-3 makes **no** change to
> `inventory_valuation_scope_sequences` — no trigger, no revoke, no rename, no
> constraint, no data change. It becomes read-only *in practice* when M5
> replaces the admission writer and nothing writes it thereafter.

Adding any enforcement to the legacy table in WP-3 would be scope expansion and
would invalidate §25's rollback premise for every package before WP-5.

---

## 2. Second Table Specification — `inventory_valuation_stream_sequences`

### 2.1 Object-level contract

| # | Attribute | Complete specification |
|---:|---|---|
| 1 | Name | `public.inventory_valuation_stream_sequences` — the exact naming parallel of the certified `inventory_valuation_scope_sequences`, re-keyed from scope to stream |
| 2 | Purpose | Holds one continuous **Accepted Event Chronology** counter per valuation **stream**, so accepted numbering never restarts or splits when a valuation scope is re-versioned |
| 3 | Accounting purpose | None. It produces accepted-chronology evidence only. It contributes **no** ECC component, no cost, no value, and no journal |
| 4 | Ownership | Inventory Engine (design §5, "Accepted Event Chronology"); mutability recorded there as "Allocator mutable; positions immutable" |
| 5 | ECC-01 traceability | §15(2) accepted sequence preserved and demoted; §15(4) partition key moves from scope version to scope key; V-11; P-01 (exclusion, §3.5) |
| 6 | ADR-C01 traceability | §5(3) separation of accepted from economic authority; §6.3 prohibition on database-allocated ordering — satisfied by exclusion, not by participation |
| 7 | Design traceability | §3.1 (supersede/re-key), §5, §17 M3, §18 (`PRIMARY KEY (valuation_stream_id)`), §24 row 3 |
| 8 | Row population | Created **empty**. WP-3 inserts no row. Rows are created only by the future M5 stream-keyed writer, one per stream on first allocation |
| 9 | Expected cardinality | One row per stream ⇒ company × item × scope key |
| 10 | Consumers in WP-3 | **Zero.** No function, view, report, RPC, or UI reads or writes it |

### 2.2 Column contracts

| # | Column | Type | Null | Default | Mutability | Contract |
|---:|---|---|---|---|---|---|
| 1 | `valuation_stream_id` | `uuid` | `NOT NULL` | none | **Immutable** | The stream whose accepted counter this row holds. Primary key and foreign key. One row per stream, permanently |
| 2 | `company_id` | `uuid` | `NOT NULL` | none | **Immutable** | Denormalised tenant key, required by design §19 so the RLS policy can evaluate `is_company_member(company_id)` without a join. Must equal the referenced stream's `company_id` (§3.4) |
| 3 | `last_sequence` | `bigint` | `NOT NULL` | `0` | **Mutable, forward-only** | The highest accepted sequence issued for this stream. Advanced by the future allocator via `UPDATE … RETURNING`. Never decreases; never reused |
| 4 | `updated_at` | `timestamptz` | `NOT NULL` | `clock_timestamp()` | **Mutable** | Last allocation timestamp. Operational evidence only — **never** an ordering input, and prohibited as an ECC component by design §2.2 |

No other column is authorised. In particular WP-3 adds **no** `activation_state`
column (§3.3), **no** `created_by`, and **no** version reference: an accepted
counter is not a versioned authority.

### 2.3 Keys and constraints

| Kind | Definition | Rationale |
|---|---|---|
| Primary key | `PRIMARY KEY (valuation_stream_id)` | Mandated verbatim by design §18. The PK *is* the "one allocator row per stream" rule; no separate `UNIQUE` is needed or authorised |
| Unique | **None beyond the primary key** | Design §18: "any uniqueness rule keyed on a policy version that would split one economic stream across versions" is *explicitly not proposed*. Uniqueness is keyed on the stream, never on the scope version — the precise mistake ECC-01 §15(4) identifies |
| Foreign key | `valuation_stream_id` → `inventory_valuation_streams (id)` | Binds the counter to the permanent partition. No `ON DELETE` action — streams are immutable and never deleted while the allocator exists |
| Foreign key | `company_id` → `companies (id)` | Mirrors the certified template; supports tenant isolation |
| Check | `CHECK (last_sequence >= 0)` | Mirrors the certified `inventory_valuation_scope_sequences_last_sequence_check`. Accepted positions are strictly positive; `0` is the pre-allocation ground state |

Constraint identifiers follow the repository's descriptive convention and must
be verified against PostgreSQL's 63-byte identifier limit before implementation
— the exact failure **EA-001** corrected for WP-2. The longest name implied
above, `inventory_valuation_stream_sequences_valuation_stream_id_fkey`
(59 bytes), is within the limit; any implementation-chosen identifier must be
re-measured.

### 2.4 Rollback behaviour

WP-3's two tables drop in foreign-key order — child before parent:

1. `DROP TABLE public.inventory_valuation_stream_sequences`
2. `DROP TABLE public.inventory_valuation_streams`

This is design §25's "drop the new tables in reverse dependency order" and
preserves R-15's "nothing existing is altered". Design §6.2's clause
"Rollback | Drop after the order-key table" governs only once M4 exists; while
`inventory_event_order_keys` does not exist, WP-3's rollback order is exactly
the two steps above. There is no event, backfill, replay, journal, projection,
costing, or production action to reverse, because WP-3 creates none.

---

## 3. Allocator Governance Contract — F-2 resolution

This section removes every engineering interpretation about allocator
mutability.

### 3.1 Field-level mutability — normative

| Field | May change after insert? |
|---|---|
| `valuation_stream_id` | **No** — immutable identity and primary key |
| `company_id` | **No** — immutable tenant binding |
| `last_sequence` | **Yes**, and only upward (`NEW.last_sequence >= OLD.last_sequence`) |
| `updated_at` | **Yes** |

Row **deletion is prohibited**. A stream's accepted counter, once created, is
permanent: deleting it would permit reissuing consumed accepted positions.

### 3.2 The immutable trigger does **not** apply

`fn_ia5_reject_immutable_inventory_fact` — the `ENABLE ALWAYS` trigger that
rejects every `UPDATE` and `DELETE` — **must not** be attached to
`inventory_valuation_stream_sequences`.

Reason: it would reject the `UPDATE … RETURNING` that is this object's sole
function, making allocation impossible. The design's immutability language is
scoped, not universal:

- §6.2's `ENABLE ALWAYS` reject trigger governs `inventory_valuation_streams`,
  the immutable **partition identity** — and still does, unchanged.
- §19's "immutability triggers make even the owner unable to `UPDATE`" is stated
  in a row whose subject is "the entire **order-key** row", i.e. M4's
  `inventory_event_order_keys`.
- The certified template `inventory_valuation_scope_sequences` carries **no**
  immutability trigger, confirming that a counter is not an immutable fact.

**Instead, a dedicated `ENABLE ALWAYS` partial-mutability guard is required**,
enforcing exactly §3.1: reject every `DELETE`; reject any `UPDATE` that changes
`valuation_stream_id` or `company_id`; reject any `UPDATE` where
`NEW.last_sequence < OLD.last_sequence`; and reject any row whose `company_id`
differs from its stream's `company_id` (§3.4).

This is an existing certified repository pattern, not a new mechanism. The
**Certified** Number Series Engine's `fn_guard_cas_number_series` already
implements both halves — "Document sequence counters cannot move backward;
issued numbers are never reusable" and rejection of identity-column changes —
and IA-5 already uses guard triggers throughout. WP-3 reuses the pattern; it
introduces no new control class.

### 3.3 Dormancy checks do **not** apply

WP-3 must **not** add an `activation_state`/`foundation_state` column or a
`… = 'dormant'` `CHECK` to `inventory_valuation_stream_sequences`.

Reason: design §21's rule is scoped to "every new **policy and key** table". An
accepted counter is neither — it holds no policy and no ECC key. A dormancy
`CHECK` on a monotonic counter is also meaningless, because a counter has no
activation state to constrain. The repository already draws exactly this line:
the identity table `inventory_valuation_scopes` carries `activation_state NOT NULL`,
while its allocator `inventory_valuation_scope_sequences` carries none.

WP-3 dormancy is instead proven by four independently verifiable facts:

1. `inventory_events` = 0;
2. both new tables contain **zero rows**;
3. **no writer exists** — the stream-keyed allocator function is M5/WP-5, so in
   WP-3 nothing can advance a counter; and
4. **no grant and no consumer** exists (§3.6, §5).

`inventory_valuation_streams` retains whatever dormancy treatment design §6.2
already specifies; EA-003 does not alter §6.2.

### 3.4 Company-consistency validation

`inventory_valuation_stream_sequences.company_id` must equal
`inventory_valuation_streams.company_id` for the referenced stream. This is
enforced inside the §3.2 guard trigger, **not** by adding a composite unique key
to `inventory_valuation_streams` — that would modify an object design §6.2
already fixed and would be scope expansion. Design §19 requires "no
cross-company stream can resolve (P-02)"; this validation is its allocator-side
half.

### 3.5 Why allocator mutability violates neither ADR-C01 nor ECC-01

| Rule | Why it is satisfied |
|---|---|
| **ECC-01 P-01** — "No counter, sequence, serial, identity column, or lock-protected allocator may produce an **ECC position**" | The allocator produces an **Accepted Event Chronology** position only. It contributes no E1–E10 or X1–X4 component. Design §7 already classifies `scope_sequence` as "Persisted accepted evidence, **excluded from every ECC path**", and §2.2 lists it as a prohibited ECC input |
| **ECC-01 §15(2)** — accepted sequence "preserved, and demoted in meaning" | The allocator must therefore continue to exist. EA-003 preserves it and does not restore it as costing authority |
| **ECC-01 §15(4)** — partition key must move from scope version to scope key, for "accepted sequence uniqueness **and** stream identity" | Re-keying the allocator to the stream is **mandated** by this clause, not optional. WP-3 implements the accepted-sequence half; §6.2 implements the identity half |
| **ECC-01 V-11** | One scope key resolves to exactly one partition, permanently — enforced by the stream's `UNIQUE (company_id, item_id, scope_code)` and by this table's `PRIMARY KEY (valuation_stream_id)` |
| **ADR-C01 §6.3** — 10-component tuple; database allocation never orders | The tuple is untouched: no component is added, removed, or reordered. The prohibition is satisfied **by exclusion** — the allocator never enters the tuple — not by constraining the allocator's own behaviour |
| **ADR-C01 §5(3)** — accepted and economic authority are distinct | This table is the schema expression of that separation: mutable accepted counter here, immutable economic key in M4's sidecar |

**Enforcement of the exclusion is not left to prose.** Test family **T-21**
(Prohibited-input census, layer S, *blocks certification*) statically asserts
that no ECC component depends on `scope_sequence`, a clock, a UUID default, or a
lock outcome. That census is WP-9's obligation and is explicitly **not** claimed
by WP-3 (§4.4).

### 3.6 Grants and how they interact

| Control | Requirement |
|---|---|
| Client write surface | `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, `service_role`. **No client role may ever `INSERT`, `UPDATE`, `DELETE`, or `TRUNCATE`** |
| Client read surface | `GRANT SELECT` to `authenticated` and `service_role`, matching the certified template |
| RLS | Enabled, with exactly one policy — `SELECT` to `authenticated` using `is_company_member(company_id)`, named `inventory_valuation_stream_sequences_read` |
| Writer path | Owner-mediated `SECURITY DEFINER` only, with `SET search_path = public`. **No such writer exists in WP-3** |
| Interaction | The two controls are independent and neither is redundant: **grants** remove the client path entirely, while the **§3.2 guard trigger** constrains even the table owner to forward-only counter movement with frozen identity and no deletion. Revoking grants alone would still leave the owner able to rewrite history; the guard alone would still expose a client write path |

### 3.7 Audit role

`fn_audit_trigger()` **AFTER INSERT only**, per design §20 ("Admission audit …
via `fn_audit_trigger()` on every new table").

Deliberately **not** on `UPDATE`: counter churn is operational, not audit
evidence, and auditing every allocation would write one `sys_audit_logs` row per
admitted event with no evidentiary gain. The **accepted position itself** is
recorded immutably on `inventory_events`, which is already audit-covered and
`ENABLE ALWAYS` immutable. Design §5 states exactly this split — "Allocator
mutable; positions immutable".

### 3.8 Replay role

**None.** The allocator supplies no ECC component, no fingerprint input, and no
boundary field; design §20's ordering-run evidence (boundary, `V`, event count,
ordered-input fingerprint, duration, outcome) contains nothing from this table.
Replay never reads it. Accepted-chronology consumers — audit, idempotency, and
the accepted watermark (design §5) — may read it after WP-5 supplies a writer.

---

## 4. WP-3 Evidence Allocation — F-3 resolution

This section is the WP-3 analogue of **EA-002** §23.1 for WP-2.

### 4.1 Authoritative test-family contract

The implementation design §23 family definitions remain the only authoritative
T-number definitions and are **not renumbered**. WP-3 supplies the structural
and fixture portion of exactly two existing families.

| Family | Authoritative purpose (§23) | WP-3 evidence boundary |
|---|---|---|
| **T-22 — Multi-company isolation** (P-02) | Cross-company edges and streams are rejected; failure = any cross-company order | **Structural:** both tables carry `company_id`; RLS enabled on both; exactly one member-gated `SELECT` policy each; zero client write grants; the stream key `UNIQUE (company_id, item_id, scope_code)` is company-leading. **Fixture:** two companies each hold a stream carrying the **same `scope_code` for their own item**, without collision — proving `scope_code` is not globally unique and that partition identity is company-scoped; a stream naming **another company's item is rejected** by the §8.4 rule 2 guard; a duplicate `(company_id, item_id, scope_code)` is rejected `23505`; an allocator row whose `company_id` differs from its stream's is rejected. **Excluded:** WP-3 proves no cross-company *edge* and no cross-company *order* — no correction edges, order keys, or comparator exist |
| **T-26 — Migration / backfill** (empty-precondition) | Fresh `--no-seed` replay; count 0; all objects present | **Structural:** fresh replay through M3 succeeds; `inventory_events` = 0 asserted *before* mutation; both tables created empty; no backfill; no default affecting accounting order; exact shape, keys, constraints, RLS, policy, grants, guard and audit triggers present. **Excluded:** WP-3 asserts no admitted event and no allocated sequence |

**"Stream partition completeness"** is WP-3's combined completion evidence
spanning those two families — the exact counterpart of EA-002's "registry
completeness". It is **not** a third test family and not an alternative name for
T-22 or T-26.

### 4.2 Evidence ownership

| Class | Owner | Content |
|---|---|---|
| **Structural (persistent)** | The M3 migration | Preconditions (§4.3); exact two-table shape; PK/FK/CHECK; RLS, policy, and grant state; guard and audit triggers present; both tables empty; zero consumers; no change to any existing object |
| **Fixture (rolled back)** | The WP-3 structural test | Minimum certification-only company/item/scope/stream/allocator rows created **inside the test transaction** and removed by its final `ROLLBACK`, proving stream-key uniqueness, allocator PK uniqueness, company consistency, monotonic forward-only movement, identity immutability, and delete rejection **non-vacuously** |
| **Implementation** | The WP-3 implementation report | Applied shape, assertions, validation lanes, and boundary review |
| **Certification** | The isolated WP-3 rollback test | Against the M3-applied database: reassert preconditions **including exact total row counts**, drop both tables in foreign-key order, verify the pre-M3 state and unchanged controls, then `ROLLBACK` so M3 remains installed |

Fixture evidence is **required**, not optional: design §6.2 keeps both tables
permanently empty in WP-3, so a `UNIQUE`/`PRIMARY KEY` constraint and the §3.2
guard cannot otherwise be proven non-vacuous. This is the identical boundary
EA-002 established for WP-2, and the fixture is evidence only — never seed data,
a migration dependency, runtime configuration, or production authority.

**Carry-forward from the WP-2 certification review.** That review found test
`106` proved *one matching* registry row but not that *exactly one* row existed.
WP-3's certification rollback proof must therefore assert **total** row counts
for both tables immediately before the destructive drops, so it fails closed on
an unexpected extra row.

### 4.3 Migration preconditions (fail-closed)

M3 must execute in one transaction and stop before mutation unless every fact
holds. A failed precondition is a **governance stop** — never authority to
backfill, repair, delete, disable a trigger, or infer a value.

1. `public.inventory_events` exists and contains exactly **zero** rows.
2. Neither `inventory_valuation_streams` nor
   `inventory_valuation_stream_sequences` exists.
3. WP-1's six policy/version tables exist, remain **empty**, and retain their
   RLS, audit, immutability, and dormancy controls.
4. WP-2's six registry columns exist with the exact single `IA5_CERTIFICATION`
   authority row, `is_certification_only = true`,
   `is_production_enabled = false`.
5. `inventory_valuation_scopes` and `inventory_valuation_scope_sequences` exist
   **unchanged**, and the latter remains untouched by this migration (§1.3).
6. `public.companies` exists as the foreign-key target.

### 4.4 Runtime exclusions — what WP-3 may **not** claim

WP-3 must not claim, in any test name, assertion message, report, or status
line, that it proves: T-01 deterministic tuple; T-02 admission validation;
T-03 duplicate identity; T-05 line/occurrence order; T-15 replay repeatability;
T-16 fingerprint; T-19 concurrency schedules; T-21 prohibited-input census;
T-27 dormancy beyond the four facts in §3.3; or **any** part of **C-01**. It
creates no comparator, order key, document key, fingerprint, replay path, or
concurrency proof. C-01 remains open pending WP-9's evidence package.

### 4.5 Locking and coverage obligations

- **Locking.** Design §17 M3 records "New tables". Creating the two foreign keys
  additionally takes a brief lock on the referenced `companies` and
  `inventory_valuation_streams` relations while each constraint is validated;
  both are instant because the child table is empty. No existing table is
  rewritten.
- **Table coverage.** Guard `075` fails when a new `public` base table is
  unregistered, so WP-3 must add **both** tables to
  `PXL_TABLE_COVERAGE_MATRIX.md` and the guard `075` registry in the same change
  set — the precedent WP-1 set for its six tables. Design §17 M9 remains the
  consolidated bookkeeping row and is not a licence to defer registration.

---

## 5. Architectural Validation

| Question | Result |
|---|---|
| New accounting policy? | **No.** No costing method, valuation arithmetic, account mapping, posting, tax, or business chronology is chosen |
| New ordering authority? | **No.** The ADR-C01 tuple is untouched; the allocator is excluded from every ECC path (§3.5) |
| ADR-C01 / ECC-01 changed? | **No.** Both are unmodified; EA-003 cites them and adds nothing |
| Derived-not-allocated preserved? | **Yes.** ECC positions remain derived. The only allocated value here is the accepted counter, which ECC-01 §15(2) preserves and §2.2 excludes from ECC |
| Dormancy preserved? | **Yes.** Zero rows, zero streams, no writer, no grant, no consumer (§3.3) |
| Replay safety preserved? | **Yes.** No accepted event, replay function, or fingerprint input is created or changed |
| Posting / Kernel boundary preserved? | **Yes.** No journal path, sanctioned mutator, or totality trigger is touched (design §22) |
| Scope expanded? | **No.** Two tables — the count design §17 M3 and §17 M9 already require |

## 6. Remaining Open Questions

**None for the WP-3 specification.** Design §27's open-decision register gains no
new unresolved item. For the allocator, name, columns, keys, mutability, guard,
dormancy, grants, audit, replay role, and rollback are fixed in §2–§3; for the
stream, the same attribute set is fixed in §8–§10 by EA-004. ECC-01 §15(4)'s
permitted implementation choice was already closed in favour of a
stream-identity object by design §6.2 and §27 item 4.

Questions belonging to WP-4 through WP-9, IA-6, production source onboarding,
runtime version selection, event admission, key materialisation, correction
graphs, costing execution, concurrency proof, C-01 closure, and hosted
deployment remain outside this document and retain their existing authorisation
gates.

## 7. Readiness Assessment

Six documented blockers have been closed across two amendments. **EA-003:**
**F-1** by §2, **F-2** by §3, **F-3** by §4, and **F-4** by the
implementation-design reconciliation in §29/§30 of that document. **EA-004:**
**G-1** by §8 and §10, and **G-2** by §9, which resolves the streams dormancy
question outright rather than deferring it.

**EA-005:** **B-1** by correcting the T-22 fixture in §4.1 and design §23.2 so
it is constructible without weakening guard rule 2.

Both M3 objects now carry identical governance depth, so an implementation
engineer can execute M3 without making a repository design decision, and every
mandated item of evidence can actually be built.

**WP-3 is not authorised by this document.** EA-003, EA-004, and EA-005 are
documentation only and grant no implementation authority. A separate WP-3 Authorisation Gate
must independently re-verify the prerequisites and issue that decision.

---

## 8. `inventory_valuation_streams` — Governing Specification (EA-004)

### 8.1 Object-level contract

| # | Attribute | Complete specification |
|---:|---|---|
| 1 | Table name | `public.inventory_valuation_streams` |
| 2 | Purpose | One permanent partition per valuation-scope **key**, so an effective-dated scope re-version never splits or restarts a stream (design §6.2; ECC-01 §15(4), V-11) |
| 3 | Accounting purpose | None. It is a partition identity. It holds no cost, value, rank, order component, or journal effect |
| 4 | Authority | ECC partition identity — the only legitimate ECC grouping key (design §6.2) |
| 5 | Ownership | Inventory Master (design §6.2 "Owner / source"); derived from `(company_id, item_id, scope_code)` |
| 6 | ECC-01 traceability | §15(4) partition key moves from scope version to scope key; **V-11** one scope key ⇒ exactly one partition, permanently |
| 7 | ADR-C01 traceability | §5(3) separation of accepted from economic authority; the partition is not a tuple component and adds no ordering dimension |
| 8 | Lifecycle | Created **empty** by M3 → rows inserted only by the future M5 stream resolver, one per resolved scope key → immutable for life → activation only by a later authorised migration (§9.3) |
| 9 | Row population in WP-3 | **Zero.** M3 inserts no row |
| 10 | Consumers in WP-3 | **Zero.** No function, view, report, RPC, or UI reads or writes it |

### 8.2 Column contracts

Derived column-for-column from the certified peer `inventory_valuation_scopes`,
retaining only what a version-free partition identity requires.

| # | Column | Type | Null | Default | Mutability | Contract |
|---:|---|---|---|---|---|---|
| 1 | `id` | `uuid` | `NOT NULL` | `gen_random_uuid()` | **Immutable** | Surrogate primary key. Named `id` per the uniform repository convention (`inventory_valuation_scopes.id`). It is a partition handle only and **never** an ordering input — ADR-C01 §6.3 bars database-allocated identifiers from ordering, and design §2.2 lists them as prohibited ECC inputs |
| 2 | `company_id` | `uuid` | `NOT NULL` | none | **Immutable** | Tenant key; the RLS predicate operand |
| 3 | `item_id` | `uuid` | `NOT NULL` | none | **Immutable** | The item whose valuation this stream partitions |
| 4 | `scope_code` | `text` | `NOT NULL` | none | **Immutable** | The valuation-scope **key** — deliberately the code, never a scope-version row id. This is the whole point of ECC-01 §15(4). No format `CHECK` is authorised; the peer constrains `scope_type` and currency but never `scope_code` |
| 5 | `activation_state` | `text` | `NOT NULL` | `'dormant'` | **Immutable** (see §9) | Dormancy control, resolved in §9 |
| 6 | `created_by` | `uuid` | `NOT NULL` | none | **Immutable** | Creating principal. `NOT NULL` makes it a mandatory input for the future M5 writer, exactly as on the peer |
| 7 | `created_at` | `timestamptz` | `NOT NULL` | `clock_timestamp()` | **Immutable** | Creation evidence only. **Never** an ordering input (design §2.2 prohibits wall-clock and insertion-time ordering) |

No other column is authorised. In particular streams carries **no** version
column, **no** `effective_from`/`effective_to`, and **no** `updated_at`: design
§6.2 fixes "Versioning | None — a stream is version-free by construction", and an
immutable row is never updated.

### 8.3 Keys and constraints

| Kind | Exact identifier | Definition |
|---|---|---|
| Primary key | `inventory_valuation_streams_pkey` | `PRIMARY KEY (id)` |
| Unique | `inventory_valuation_streams_key_uq` | `UNIQUE (company_id, item_id, scope_code)` — named verbatim by design §18; the §15(4) fix and the enforcement of V-11 |
| Check | `inventory_valuation_streams_activation_state_check` | `CHECK (activation_state = 'dormant')` (§9) |
| Foreign key | `inventory_valuation_streams_company_id_fkey` | `FOREIGN KEY (company_id) REFERENCES companies(id)` |
| Foreign key | `inventory_valuation_streams_item_id_fkey` | `FOREIGN KEY (item_id) REFERENCES items(id)` |
| Foreign key | `inventory_valuation_streams_created_by_fkey` | `FOREIGN KEY (created_by) REFERENCES auth.users(id)` |

No `ON DELETE` action on any foreign key, matching the peer. The longest
identifier above is `inventory_valuation_streams_activation_state_check`
(**50 bytes**), and the longest WP-3 identifier of any kind is
`fn_ia5_guard_inventory_stream_foundation` / `inventory_valuation_streams_created_by_fkey`
(**43 bytes**) — all within PostgreSQL's 63-byte limit. Every identifier must be
re-measured at implementation; an overlength label is the exact failure **EA-001**
corrected for WP-2.

### 8.4 Validation rules — enforcement mechanism

Design §6.2 states the rules but not their mechanism. Both are cross-table, so
neither can be a `CHECK`; and `scope_code` is **not** unique in
`inventory_valuation_scopes` (versions share it), so neither can be a foreign
key. They are therefore enforced by the §8.6 guard trigger:

1. `company_id` must exist in `companies`.
2. **Company match with item** — `items.company_id` must equal
   `NEW.company_id`.
3. **`scope_code` must match at least one scope version** — at least one
   `inventory_valuation_scopes` row must exist with the same `company_id`,
   `item_id`, and `scope_code`.

**Failure behaviour:** reject (design §6.2 "Reject admission (F-02 class) if a
stream cannot be resolved"). Fail-closed is mandatory at every step per ECC-01
§15(11); no fallback stream may be manufactured.

**Ownership:** the guard is created by **WP-3**, with the table. Design §24
sequences "every schema addition before any writer change", so the constraint
exists armed before M5 can write through it. In WP-3 the table is empty, so the
guard is armed but never fires outside a rolled-back test fixture.

### 8.5 Trigger strategy

The uniform IA-5 three-trigger pattern, confirmed identical on the peer and on
all six certified WP-1 tables. The `aa_`/`trg_`/`zz_` prefixes are load-bearing:
PostgreSQL fires triggers in name order, so validation runs first and the
immutability reject runs last.

| Trigger | Timing / events | Function | Enabled |
|---|---|---|---|
| `aa_inventory_valuation_streams_guard` | `BEFORE INSERT OR UPDATE FOR EACH ROW` | `fn_ia5_guard_inventory_stream_foundation()` (§8.6) | `ENABLE` (origin, `O`) |
| `trg_inventory_valuation_streams_audit` | `AFTER INSERT FOR EACH ROW` | `fn_audit_trigger()` | `ENABLE` (origin, `O`) |
| `zz_inventory_valuation_streams_immutable` | `BEFORE UPDATE OR DELETE FOR EACH ROW` | `fn_ia5_reject_immutable_inventory_fact()` | **`ENABLE ALWAYS` (`A`)** |

`ENABLE ALWAYS` on the immutability trigger is required by design §6.2
("Immutable; `ENABLE ALWAYS` reject trigger") and is what makes the rejection
survive `session_replication_role = replica`.

### 8.6 The WP-3 guard function

WP-3 creates **one new** function:
`public.fn_ia5_guard_inventory_stream_foundation()` — `SECURITY DEFINER`,
`SET search_path = public`, dispatching on `TG_TABLE_NAME`, taking the same
`pg_advisory_xact_lock(hashtextextended(TG_TABLE_NAME || ':' || NEW.company_id::text, 0))`
serialisation the existing IA-5 guards take.

**It must be a new function, not an edit of an existing one.** This is the WP-1
precedent, verified in the catalog: WP-1 did **not** extend
`fn_ia5_guard_inventory_policy_foundation`; it created
`fn_ia5_guard_inventory_order_policy_foundation` for its six tables, preserving
design §25 and risk **R-15** ("Nothing existing is altered"). Editing a shared
certified guard would alter an existing object and invalidate WP-3's rollback
premise.

It hosts two branches:

- `inventory_valuation_streams` — the three §8.4 validations.
- `inventory_valuation_stream_sequences` — the allocator behaviours **already
  fixed by EA-003 §3.2 and carried across unchanged**: reject `DELETE`; reject
  changes to `valuation_stream_id`/`company_id`; reject
  `NEW.last_sequence < OLD.last_sequence`; reject a `company_id` that differs
  from its stream's. EA-004 names the host function only and alters no allocator
  behaviour.

`REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role` on the function
(design §19: "Every new `fn_ia5_*` revoked from all roles; owner-mediated only").

### 8.7 RLS, grants, and audit

| Control | Requirement |
|---|---|
| RLS | Enabled |
| Policy | Exactly one — `inventory_valuation_streams_read`, `SELECT` to `authenticated` `USING (is_company_member(company_id))`, matching the peer verbatim |
| Read grants | `GRANT SELECT` to `authenticated` and `service_role` |
| Write grants | `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, `service_role`. **No client role may ever `INSERT`, `UPDATE`, `DELETE`, or `TRUNCATE`** |
| Writer path | Owner-mediated `SECURITY DEFINER` only. **No such writer exists in WP-3** — the stream resolver is M5/WP-5 |
| Audit role | `fn_audit_trigger()` `AFTER INSERT` (design §20, "on every new table"). Not on `UPDATE`/`DELETE`, because §10 makes both impossible |

### 8.8 Replay and certification roles

- **Replay role.** Design §6.2: "Partition selector; recorded in every boundary
  and fingerprint." In WP-3 this is **latent** — no replay path, boundary
  record, comparator, or fingerprint exists, so the table participates in
  nothing. It becomes the partition selector only when WP-7 builds the ordering
  and fingerprint functions.
- **Certification role.** Structural assertions are persistent (shape, keys,
  constraints, controls, emptiness). Non-vacuity is proven by a **rolled-back**
  fixture per §4.2: duplicate `(company_id, item_id, scope_code)` rejected
  `23505`; cross-company item rejected; unresolvable `scope_code` rejected;
  `UPDATE`/`DELETE` rejected `23514`; a non-`'dormant'` `activation_state`
  rejected `23514`.

### 8.9 Rollback order and implementation boundary

**WP-3 rollback, in order:**

1. `DROP TABLE public.inventory_valuation_stream_sequences` (child)
2. `DROP TABLE public.inventory_valuation_streams` (parent)
3. `DROP FUNCTION public.fn_ia5_guard_inventory_stream_foundation()`

Step 3 completes the contract: the guard function is created by WP-3, so
rollback must remove it or the package is not fully reversible. Design §6.2's
clause "Drop after the order-key table" governs only once M4 exists; while
`inventory_event_order_keys` does not exist, the three steps above are the whole
rollback. Nothing existing is altered, so §25's premise and **R-15** hold.

**Implementation boundary — WP-3 creates exactly:** two tables; their keys,
constraints, RLS, read policies, and grants; three triggers per table as
specified; one new guard function; and both tables' entries in
`PXL_TABLE_COVERAGE_MATRIX.md` and guard `075` (§4.5).

**Runtime exclusions.** WP-3 creates **no** stream resolver, allocator function,
order key, document key, comparator, fingerprint, boundary record, replay path,
index on any ECC object, or consumer of either table; and changes **no** existing
table, function, trigger, grant, Posting object, or Kernel object.

---

## 9. Streams Dormancy Contract (EA-004) — resolved, not deferred

**Decision: `inventory_valuation_streams` carries `activation_state text NOT NULL DEFAULT 'dormant'` with `CHECK (activation_state = 'dormant')`, and it carries the `ENABLE ALWAYS` immutability trigger. Both apply. Neither is optional.**

### 9.1 The governing rule

Design §21 requires an `activation_state`/`foundation_state` `CHECK … = 'dormant'`
on "every new policy and key table, **matching the existing pattern**". Three
independent lines of repository evidence place streams inside that rule:

1. **The existing pattern for a valuation-identity table is the peer.**
   `inventory_valuation_scopes` — the object streams directly succeeds in
   partition role — carries `activation_state text NOT NULL DEFAULT 'dormant'`
   and `inventory_valuation_scopes_activation_state_check`
   `CHECK (activation_state = 'dormant')`, together with the `ENABLE ALWAYS`
   immutability trigger and the audit trigger.
2. **Design §6.2 itself calls streams a key** — "the only legitimate ECC
   grouping **key**" — bringing it within §21's "policy and key table" wording.
3. **All six certified WP-1 tables carry it**, establishing it as the standing
   rule for every new governed IA-5 configuration object.

### 9.2 Why the objects that omit it do not apply

The catalog splits cleanly, and neither exempt class fits streams:

| Object | Dormancy mechanism | Why streams differs |
|---|---|---|
| `inventory_events` | None — dormancy is emptiness | A transactional **fact** table with no activation lifecycle. Streams is governed configuration |
| `ref_inventory_event_source_types` | A **domain-specific pair** — `CHECK (NOT is_production_enabled)` + `CHECK (is_certification_only)` (design §21 row 1) | The registry is dormancy-guarded, just by different columns. Streams has no such alternative available |
| `inventory_valuation_scope_sequences` | None | A mutable **counter**, correctly exempt (§3.3) |

Omitting the check would make streams the **only** new governed IA-5
configuration object in the repository with no dormancy constraint whatsoever.

### 9.3 Activation rule

Because the `ENABLE ALWAYS` immutability trigger rejects every `UPDATE`,
`activation_state` **can never change by DML**. Activation is therefore by
**migration only** — a later authorised migration replacing the `CHECK`.

This is not a conflict; it is design §21's stated intent: "dormancy is enforced
by `CHECK` constraints and absent grants, which cannot be toggled at runtime.
This is deliberate: a flag can be flipped; a constraint requires a migration."
It is also exactly how `inventory_valuation_scopes` and all six WP-1 tables
operate today. Design §21's four activation preconditions — recorded ECC-01
acceptance, a passed reopened evidence gate closing C-01, explicit IA-6
authorisation, and a separate enabling migration — apply unchanged. **WP-3
performs no activation and creates no activation path.**

---

## 10. Streams Mutability Contract (EA-004)

**`inventory_valuation_streams` is fully immutable and append-only. Every column
is immutable after insert; there is no partial-mutability exception.**

| Field | May change after insert? |
|---|---|
| `id`, `company_id`, `item_id`, `scope_code`, `activation_state`, `created_by`, `created_at` | **No** — all immutable |

- `UPDATE` and `DELETE` are rejected by
  `zz_inventory_valuation_streams_immutable` (`ENABLE ALWAYS`) with SQLSTATE
  `23514`, the same class the certified registry and WP-1 tables already return.
- **This is the deliberate opposite of the allocator.** The two M3 tables have
  different mutability by design and the difference is load-bearing: the stream
  is a permanent identity (design §6.2 "Immutable"), while the allocator is a
  counter that must advance (design §5 "Allocator mutable; positions immutable").
  §3 governs the allocator and is unchanged by EA-004.
- A stream is never deleted while its allocator row exists; the foreign key and
  the immutability trigger both prevent it.
- **Correction path:** a stream whose key was wrong is not edited. Because one
  scope key is one partition permanently (V-11), a wrong key means the resolver
  input was wrong; the governed forward path is re-resolution under design §15,
  never an in-place `UPDATE` (design §25, "Never an in-place `UPDATE`").

---

## 11. EA-004 Consistency Review

| Check | Result |
|---|---|
| Both M3 tables at identical governance depth | **Yes** — object contract, column contracts, keys, constraints, triggers, guard, mutability, dormancy, grants, RLS, audit, replay, certification, rollback, boundary, exclusions for each |
| Implementation boundaries unchanged | **Yes** — still exactly two tables (§17 M3, §17 M9); EA-004 adds no object beyond the guard function WP-3's own validations already required |
| Architecture unchanged | **Yes** — no tuple component, rank, partition rule, or ordering authority altered |
| ADR-C01 unchanged | **Yes** — not opened |
| ECC-01 unchanged | **Yes** — not opened; §15(4)/V-11 cited only |
| Allocator specification reopened? | **No** — §2–§3 unedited. §8.6 names the host function and carries EA-003 §3.2's behaviours across verbatim |
| Engineering interpretation remaining | **None identified** — every G-1 and G-2 item is fixed by an exact value, and EA-005 makes every mandated T-22 assertion constructible |
| Validation rule / company isolation changed by EA-005 | **No** — §8.4 rule 2 is unedited; the corrected fixture proves it rather than contradicting it |

## Decision

**A.**

**EA-003, EA-004, AND EA-005 COMPLETE — WP-3 SPECIFICATION AND EVIDENCE COMPLETE FOR BOTH M3 OBJECTS**

**WP-3 AUTHORISED AND IMPLEMENTED 2026-07-30 — EVIDENCE GATE PASSED AND CERTIFIED 2026-07-31**

## 12. Implementation Record (2026-07-30)

The WP-3 Final Authorisation Verdict returned **A — WP-3 AUTHORISED**, and the
authorised implementation mission completed the bounded scope on 2026-07-30:

- migration `20260730000018` creates exactly the two authorised tables with the
  seven stream columns (§8.2), four allocator columns (§2.2), ten governed keys
  and constraints (§2.3, §8.3), five governed triggers (§3.2, §3.7, §8.5), the
  one new guard function (§8.6), RLS with one read policy each, and SELECT-only
  grants — behind six fail-closed preconditions (§4.3);
- test `107` proves the structure, the mutability asymmetry, and the
  structural/fixture portions of T-22 and T-26 with all fixture data rolled back
  (46 assertions);
- test `108` proves fixture cleanup and the isolated three-step rollback,
  reasserting exact total row counts before the destructive drops (22
  assertions); and
- fresh replay, focused `107`/`108` (68), full regression (108 files / 2,512
  assertions), and canonical accounting (30 files / 748 assertions) pass.

No accounting, runtime, Posting, Kernel, `inventory_events`, ADR-C01, or ECC-01
change was made. This record is neither an Evidence Gate nor certification.

## 13. Certification Record (2026-07-31)

The independent **WP-3 Evidence Gate passed** with zero blocking findings, and
the separate **Certification Mission granted certification**: **WP-3 is CERTIFIED
2026-07-31.** The gate re-verified the two-table shape, ten governed constraints,
five triggers with exact timing and enablement, the single guard function, RLS
with one read policy each, zero client/service write grants, zero consumers, and
the three-step rollback; and re-executed fresh replay, focused `107`/`108` (68),
full regression (108 / 2,512), canonical accounting (30 / 748, debit = credit =
`2,411,134.80`), `docs:check`, and the schema-summary generator.

Two Evidence Gate findings were certified **False Positives** — no governing rule
requires a standalone Final Authorisation Verdict or WP-3 Implementation Report —
and no repair was made for either. **This certifies the WP-3 work package only:**
C-01 remains open, the IA-5 permanent-foundation claim remains suspended, no
Inventory module or engine is certified, and WP-4…WP-9 and IA-6 remain
unauthorised.
