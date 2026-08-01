# IA-5 WP-5 — Detailed Event Admission and Component Resolution Specification

**Status:** ENGINEERING AMENDMENT EA-010 COMPLETE — ready for a separate comprehensive WP-5 Authorisation Gate re-run; WP-5 remains unauthorised and unimplemented
**Authority:** Tier 2 Engineering Specification subordinate to the Product Architecture, ADR-C01, ECC-01, and the accepted IA-5 ECC Hardening programme design
**Owner / Domain:** Inventory Accounting / IA-5 ECC Hardening
**Applies To:** WP-5/M5 event admission and admission-time ECC component resolution only
**Read When:** Re-running the WP-5 Authorisation Gate or, only after a successful gate, implementing/auditing/certifying WP-5
**Do Not Read For:** Costing, valuation, FIFO, Moving WAC, COGS, Posting, General Ledger, tax, UI, production activation, WP-6…WP-9, or IA-6
**Date:** 2026-08-01

---

## Engineering Amendments EA-008 through EA-010 — Findings and authority

EA-008 closes only the three findings recorded by the 2026-07-31 WP-5
Authorisation Gate:

| Finding | Resolution in this specification |
| --- | --- |
| `WP5-AG-001` | Exact current and replacement writer signatures, payload schema, resolver signature and output, canonical encoding, failures, security, transaction sequence, idempotency, locks and postconditions are fixed in §§2–8. |
| `WP5-AG-002` | Production admission and the owner-only, rolled-back, commit-rejecting `IA5_CERTIFICATION` fixture path are separated in §9 without weakening ECC-01 V-10 or enabling a source. |
| `WP5-AG-003` | The trigger function and trigger are counted separately, totality/current/superseded rules are fixed, test `103`/`109` consequences are explicit, and reverse-order rollback is complete in §§10–12. |

The independent Authorisation Gate re-run after EA-008 returned **REJECTED**
and reopened exactly three High findings. EA-009 supersedes only the defective
prospective portions of EA-008; the EA-008 chronology above remains historical
evidence.

| Finding | EA-009 resolution in this specification |
| --- | --- |
| `WP5-AGR-001` | §§5–6 make certified WP-4 authoritative for persisted `canonical_key_bytes`, `ecc_key_digest`, the fourteen-component census and immutability. WP-5 derives the exact component values, including E2 = 0 for the only eligible base fixture, and serializes exactly fourteen components—no version-vector or admission-input pseudo-components. |
| `WP5-AGR-002` | §3.5 is the sole controlling writer algorithm. It places tenant-safe normalization before the company-scoped idempotency lookup, resolves duplicates before any chronology write, and fixes the occurrence/stream/allocator lock order. The programme design now points to it instead of restating a conflicting sequence. |
| `WP5-AGR-003` | §17 defines and executes a fixed, filesystem-derived, independently reproducible SHA-256 manifest for the protected implementation and authority boundary. |

The next complete independent Authorisation Gate re-run returned **REJECTED**
on four High findings. The following mission ledger preserves that issued gate
result. EA-010 supersedes only the defective prospective WP-5 rules; EA-008,
EA-009, and both prior rejection decisions remain historical evidence.

### EA-010 four-finding mission ledger

#### WP5-AGR2-001 — High — Resolution identity and WP-4 uniqueness conflict

- **Exact evidence:** ECC-01 §3.3 requires new immutable evidence under the
  target version while retaining the prior resolution; certified WP-4 permits
  retained resolutions and `current` → `superseded`; executable migration
  `20260731000019` also enforces unconditional `UNIQUE
  (valuation_stream_id, canonical_key_bytes)`; and the EA-009 WP-5 contract
  excluded the version vector from those bytes while still describing a
  successor row. A version-only re-resolution with unchanged comparator values
  therefore collides with the retained row.
- **Root cause:** comparator-component bytes were treated as though they were
  also a resolution-version identity.
- **Unsafe consequence:** an implementer could build the documented successor
  lifecycle and encounter an unavoidable `23505`, or silently change certified
  WP-4 identity semantics to avoid it.
- **Minimum governed repair:** restrict WP-5 to initial resolution only; remove
  its successor/re-resolution claims; fail closed on any pre-existing event
  resolution; and record a mandatory separate WP-4 lifecycle decision before
  re-resolution or dependent activation.
- **Confidence:** High.

#### WP5-AGR2-002 — High — Replacement-writer persistence map incomplete

- **Exact evidence:** EA-009 governed the caller payload and high-level insert
  sequence but did not map every required column of
  `inventory_occurrences`, `inventory_events`,
  `inventory_event_source_links`, optional `inventory_event_values`, the WP-3
  stream/allocator objects, and `inventory_event_order_keys`. Executable
  migration `20260726000013` supplies specific occurrence dates, policy IDs,
  costing method, valuation currency, source-link evidence, currency metadata,
  atomic/audit identities, defaults, and creation fields that the replacement
  contract left implicit. Its text/NFC/trim storage behavior was also not
  governed.
- **Root cause:** the input contract was completed without completing the
  persisted row-construction contract.
- **Unsafe consequence:** an implementer still had to choose which current
  writer semantics to preserve and how to populate financially and audit-
  relevant columns.
- **Minimum governed repair:** an exhaustive per-column persistence map for all
  seven written tables, plus an explicit preserved/modified/removed matrix for
  the current 11-argument writer.
- **Confidence:** High.

#### WP5-AGR2-003 — High — Economic-date derivation depends on session timezone

- **Exact evidence:** EA-009 used `E1::date`; executable
  `fn_ia5_guard_inventory_event_fact` compares policy periods through
  `NEW.effective_at::date`; and the current writer stores
  `p_occurred_at::date`. PostgreSQL converts `timestamptz` to `date` in the
  effective session `TimeZone`, while the canonical timestamp contract is UTC.
- **Root cause:** the contract governed UTC timestamp bytes but not the date
  boundary used for scope/policy selection, guard validation, and
  `occurrence_date` persistence.
- **Unsafe consequence:** the same instant near UTC midnight can select a
  different policy/version or be accepted/rejected differently under two
  session timezones.
- **Minimum governed repair:** define one UTC economic-date and occurrence-date
  derivation, pin the writer/resolver function-local timezone to UTC so the
  preserved guard observes the same date, and allocate two-timezone evidence.
- **Confidence:** High.

#### WP5-AGR2-004 — High — Two-session certification evidence is unconstructible

- **Exact evidence:** EA-009 required all business/version/event/key fixtures
  to live in one transaction ending `ROLLBACK`, yet assigned concurrent
  idempotency to test `112`. Existing repository asset
  `supabase/verification/ia5_concurrent_idempotency.sql` correctly records that
  autonomous sessions cannot see an uncommitted fixture and therefore commits
  isolated local setup before its two-session proof and requires an immediate
  local reset.
- **Root cause:** the single-session rolled-back fixture convention was applied
  to a multi-session visibility test without a separate reset-bounded lane.
- **Unsafe consequence:** the future implementer would have to commit forbidden
  Inventory fixture rows, weaken the fixture boundary, or claim concurrency
  without executable evidence.
- **Minimum governed repair:** allocate one exact fresh-local, reset-bounded,
  two-session verification asset; permit only non-Inventory setup to commit;
  require both event-admission transactions to roll back or be commit-rejected;
  reset immediately; and prove no Inventory or setup residue.
- **Confidence:** High.

Authority order is:

1. [`PXL_PRODUCT_ARCHITECTURE.md`](../../01.%20Architecture/PXL_PRODUCT_ARCHITECTURE.md) — product scope and engine/module ownership;
2. [`ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md`](../03.%20Architecture/ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md) — frozen dual-chronology decision;
3. [`ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md`](../03.%20Architecture/ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md) — accepted derivation, validation, normalization and failure authority;
4. [`IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md`](IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md) — programme and work-package sequence, as amended by EA-008 through EA-010;
5. certified WP-1 through WP-4 specifications — storage and dormant-foundation contracts; and
6. this document — the exact M5 representation and executable boundary.

This specification does not amend product scope, ADR-C01, ECC-01, or any
certified WP-1…WP-4 contract. EA-008's statement that WP-5 could persist a
version vector plus only thirteen components conflicted with certified WP-4
§2.1–§2.2. EA-009 withdraws that prospective statement. WP-4 remains
authoritative: `canonical_key_bytes` is the immutable, injective serialization
of exactly `E1…E10,X1…X4`; `ecc_key_digest` is SHA-256 of those exact bytes; and
the key row is the persistence authority. WP-5 is the producer only: it derives
and validates the fourteen values and satisfies that storage contract. The only
currently eligible `IA5_CERTIFICATION` source is `base` and rejects every
causal, reversal and correction edge, so ECC-01 §4.2 resolves E2 exactly to
integer zero. Any later source requiring non-zero E2 remains fail-closed until a
separate governed source/resolver amendment. No WP-4 amendment is required and
its certification remains valid.

**Governance decision:** EA-008, EA-009, and EA-010 grant no implementation, audit,
certification, deployment, source activation, or hosted authority. Only a
separate successful WP-5 Authorisation Gate may permit implementation.

---

## 1. Complete WP-5 object inventory

PostgreSQL triggers and trigger functions are separate objects. The future M5
implementation owns exactly **four database objects: three functions and one
constraint trigger**.

| Class | Exact object | Action | Count |
| --- | --- | --- | ---: |
| Function | `public.fn_ia5_record_dormant_inventory_occurrence(uuid,text,uuid,uuid,text,bigint,text,text,timestamptz,uuid,jsonb,integer,text,text)` | **Replace** the current 11-argument function after dropping that old signature; never overload | 1 |
| Function | `public.fn_ia5_ecc_resolve_components(uuid,integer,text,text,uuid,timestamptz,timestamptz,text)` | Create | 1 |
| Trigger function | `public.fn_ia5_enforce_event_order_key_totality()` | Create; returns `trigger` | 1 |
| Constraint trigger | `inventory_events_ecc_order_key_totality_ct` on `public.inventory_events` | Create | 1 |

Object census:

- functions created: **2** (resolver and trigger function);
- functions replaced: **1** (writer); functions overloaded/renamed/wrapped: **0**;
- functions preserved: exactly these nine existing `fn_ia5_*` signatures —
  `fn_ia5_create_dormant_policy_bundle`, `fn_ia5_derive_unit_rate`,
  `fn_ia5_guard_inventory_event_fact`,
  `fn_ia5_guard_inventory_order_key_foundation`,
  `fn_ia5_guard_inventory_order_policy_foundation`,
  `fn_ia5_guard_inventory_policy_foundation`,
  `fn_ia5_guard_inventory_stream_foundation`, `fn_ia5_quantize_exact`, and
  `fn_ia5_reject_immutable_inventory_fact` — plus every non-IA-5 function,
  including `fn_audit_trigger()`;
- constraint triggers created: **1**; ordinary triggers created/replaced: **0**;
- tables altered: **one existing table, `public.inventory_events`, trigger
  metadata only**;
- table columns, table constraints, RLS policies, indexes and tables created or
  altered: **0**;
- grants added: **0**; revocations are applied to all three functions;
- comments: comments on the three functions and the constraint trigger;
- runtime consumers: **0**;
- application/UI/API/job/report/background-worker consumers: **0**;
- table-coverage entries: **0**, because WP-5 creates no table;
- rollback-owned database objects: the four rows above plus restoration of the
  prior 11-argument writer definition, ACL and comment;
- future pgTAP files: `111`, `112`, and `113`; future two-session verification
  asset: `supabase/verification/ia5_wp5_concurrent_idempotency.sql`, evidence ID
  `WP5-CONC-114`; no test or verification asset is created or changed by
  EA-008, EA-009, or EA-010.

No helper or encoding function is authorised. The resolver performs encoding
inside its body. Adding a helper, overload, view, type, domain, table, column,
policy, index, second trigger, custom GUC, feature flag, or wrapper is scope
expansion and requires a new amendment and gate.

The future object comments are exact (without the surrounding Markdown
backticks):

| Object | Exact comment text |
| --- | --- |
| 14-argument writer | `IA-5 ECC WP-5 owner-only dormant event admission writer. Production remains fail-closed until separate source activation; certification fixtures must roll back.` |
| resolver | `IA-5 ECC WP-5 read-only chronology-component resolver. It resolves and encodes admission evidence only; it performs no costing, Posting, tax or journal work.` |
| totality trigger function | `IA-5 ECC WP-5 deferred event-side order-key totality and certification-commit guard. Automatic trigger execution only.` |
| constraint trigger | `IA-5 ECC WP-5 deferred event-side order-key totality; certification fixture commits are rejected.` |

---

## 2. Existing executable writer frontier

Repository source
`supabase/migrations/20260726000013_inventory_accounting_ia5_foundation.sql`
defines the current executable contract exactly as follows.

| Attribute | Current contract |
| --- | --- |
| Schema/name | `public.fn_ia5_record_dormant_inventory_occurrence` |
| Arguments, exact order | `p_company_id uuid`; `p_source_document_type text`; `p_source_document_id uuid`; `p_source_line_id uuid`; `p_source_transition text`; `p_source_occurrence_sequence bigint`; `p_idempotency_key text`; `p_request_fingerprint text`; `p_occurred_at timestamptz`; `p_actor_id uuid`; `p_events jsonb` |
| Defaults | None |
| Return | `jsonb` |
| Language/security | `plpgsql`, `SECURITY DEFINER`, `SET search_path = public` |
| Owner | `postgres` in the certified local catalog; migration execution must preserve that owner |
| ACL | `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, `service_role`; owner retains execution |
| Stored callers | None in the database function graph |
| Repository callers | Test `103` has 17 call expressions plus 2 signature/census references; test `109` has 2 call expressions. Ten `supabase/verification/ia5_*` assets also reference the signature. There is no application/runtime caller. |
| Writes | `inventory_occurrences`, `inventory_events`, `inventory_event_source_links`, optional `inventory_event_values`; insert/update of legacy accepted allocator `inventory_valuation_scope_sequences` |
| Return fields | `occurrence_id` UUID JSON string; `occurrence_state` string; `duplicate` boolean; `event_ids` array of UUID JSON strings |
| Idempotency | Existing identical `(company_id,idempotency_key)` returns the existing occurrence; conflicting source identity or request fingerprint raises; concurrent insert uses `ON CONFLICT … DO NOTHING` then reads the winner |
| Postconditions | One accepted occurrence, one or more immutable events, one primary source link per event, optional event value; zero projection/Posting/journal effect |
| Current source rule | Accepts only a row that is certification-only and production-disabled |
| Failure behavior | Exceptions abort the statement; most current messages use PostgreSQL's default `P0001`; table constraints may raise their native SQLSTATE |

The current `p_events` element reads these top-level keys:
`valuation_scope_id`, `event_type`, `event_effect`, `event_sequence`,
`effective_at`, `accounting_date`, `item_id`, `physical_warehouse_id`,
`physical_location_id`, `lot_number`, `serial_number`, `source_uom_id`,
`base_uom_id`, `source_quantity`, `base_quantity`, `uom_conversion_factor`,
`reversal_of_event_id`, `correction_of_event_id`, `predecessor_event_id`,
`immutable_source_evidence`, `source_evidence_fingerprint`, `reason_code`, and
optional `value`. The current `value` object reads `value_role`,
`authoritative_transaction_amount`, `authoritative_functional_amount`,
`gl_basis_amount`, optional `derived_unit_rate`, `exchange_rate_identity`,
optional `residual_units`, and `calculation_evidence`. Unknown keys are
currently retained only where they are inside stored evidence JSON; unknown
event/value keys are otherwise silently unused because no exact census exists.
The current writer does not create a stream or order key and does not resolve
E3/E4/E5/E6/E7/E10/X/V. That permissive payload and missing chronology are why
the current function cannot remain the M5 contract.

**Replacement decision:** M5 must execute a `DROP FUNCTION … RESTRICT` for the
exact 11-argument signature, then create the exact 14-argument signature in
§3. It does not use `CREATE OR REPLACE` across a signature change, does not
retain the old signature, and does not create an overload, alias or wrapper.
The old body, ACL, owner and comment are the rollback source of truth.

---

## 3. Replacement admission writer contract

### 3.1 Exact signature

The governed function is:

`public.fn_ia5_record_dormant_inventory_occurrence(`
`p_company_id uuid, p_source_document_type text, p_source_document_id uuid,`
`p_source_line_id uuid, p_source_transition text,`
`p_source_occurrence_sequence bigint, p_idempotency_key text,`
`p_request_fingerprint text, p_occurred_at timestamptz, p_actor_id uuid,`
`p_events jsonb, p_source_line_ordinal integer,`
`p_document_order_key_input text,`
`p_admission_context text DEFAULT 'production') RETURNS jsonb`

Arguments 1–13 have no SQL default. Every one is SQL `NOT NULL` by function
validation even though PostgreSQL function parameters cannot carry a `NOT NULL`
declaration. Argument 14 is non-null after its default is applied.

| Argument | Meaning and source | Validation / chronology |
| --- | --- | --- |
| `p_company_id uuid` | Tenant owning the occurrence; caller supplies from the source workflow | Required; membership, source, event, scope, stream, policy and key companies must all equal it; partition input, not an ECC component |
| `p_source_document_type text` | Immutable registered source type | Required exact registry key; participates in E4/E10 and selects the separately retained registry/version authority; no trimming/case-folding |
| `p_source_document_id uuid` | Immutable pre-admission source document identity | Required; E5 input for current algorithm and E10; never generated by IA-5 |
| `p_source_line_id uuid` | Immutable source line identity | Required; E10; never generated by IA-5 |
| `p_source_transition text` | Governed lifecycle transition | Required uppercase token matching `^[A-Z][A-Z0-9_]{1,39}$`; E7/E10 |
| `p_source_occurrence_sequence bigint` | E8 source occurrence ordinal | Required and positive; source-supplied; no allocation or retry-derived value |
| `p_idempotency_key text` | Retry identity | Required length 16…200; not an ECC component; retained on occurrence |
| `p_request_fingerprint text` | Caller checksum of the exact request envelope in §3.4 | Required 64 lowercase hex and must equal the writer's recomputation; retained on occurrence |
| `p_occurred_at timestamptz` | Occurrence/audit time | Required; retained, but never an ECC component and never substituted for E1 |
| `p_actor_id uuid` | Creating principal | Required company member; retained as `created_by`; not an ECC component |
| `p_events jsonb` | Ordered, non-empty deterministic event plan | Required array; exact schema §4; array order and `event_sequence` must agree; E9 comes from each element |
| `p_source_line_ordinal integer` | E6 immutable source line ordinal | Required and positive; source-supplied; retained in the key and reserved audit evidence |
| `p_document_order_key_input text` | Raw source-owned E5 input | Required. For the only current algorithm it must equal lowercase `p_source_document_id::text`; NFC normalized; retained in reserved audit evidence |
| `p_admission_context text` | Separates production from rolled-back certification | Exact `production` or `certification_fixture`; default `production`; not an ECC component; retained in reserved audit evidence |

No caller argument participates in Accepted Event Chronology. The only accepted-
chronology value is the WP-3 allocator result written to
`inventory_events.scope_sequence`; it is derived after validation, is never
caller-supplied, and is excluded from canonical ECC serialization.

### 3.2 Function properties and privileges

- language: `plpgsql`;
- volatility: `VOLATILE` because it writes and must see earlier writes in its
  transaction;
- parallel safety: `PARALLEL UNSAFE`;
- security: `SECURITY DEFINER`;
- owner: `postgres`;
- function configuration: exactly `SET search_path = public` and
  `SET TimeZone = 'UTC'`; both settings are function-local and PostgreSQL
  restores the caller's settings when the call returns;
- direct `EXECUTE`: owner only;
- explicit `REVOKE ALL`: `PUBLIC`, `anon`, `authenticated`, `service_role`;
- prohibited callers: every direct client, browser, UI, API role, report, job,
  background worker and service role;
- current application caller: none;
- future production caller: only a separately authorised owner-mediated server
  function after source activation and caller certification. WP-5 creates none.

The writer uses the caller's transaction. Production semantics require
`READ COMMITTED` or stronger; the certification fixture requires
`SERIALIZABLE`. The function must not begin, commit or roll back a transaction
internally. Any exception rolls back every row and counter change made by that
function statement. The certification context has the additional commit
prohibition in §9.

The UTC function configuration is part of the executable contract, not an
environment assumption. Define `economic_date` exactly as
`(effective_at AT TIME ZONE 'UTC')::date` and `occurrence_date` exactly as
`(p_occurred_at AT TIME ZONE 'UTC')::date`. The preserved
`fn_ia5_guard_inventory_event_fact` uses `NEW.effective_at::date`; because that
trigger executes inside this UTC-configured writer call, its date comparison is
identical to `economic_date` without modifying the certified guard. A future
direct writer other than this function is prohibited and may not rely on the
session timezone.

### 3.3 Exact return object

The return is one JSON object with exactly these keys; unknown return keys are
not authorised:

| Key | JSON type | Logical type | New call | Exact duplicate |
| --- | --- | --- | --- | --- |
| `occurrence_id` | string | UUID | new occurrence id | existing id |
| `occurrence_state` | string | text | `accepted` | stored state, which must be `accepted` |
| `duplicate` | boolean | boolean | `false` | `true` |
| `event_ids` | array of strings | UUID[] | event ids ordered by `event_sequence` | stored event ids in the same order |
| `order_key_ids` | array of strings | UUID[] | current key ids in event order | current key ids in event order |
| `valuation_stream_ids` | array of strings | UUID[] | stream ids in event order; duplicates retained | same persisted stream ids |
| `admission_context` | string | text | input context | stored reserved-audit context; mismatch is an idempotency conflict |

Every array has exactly `event_count` elements. A missing current key on a
duplicate is not repaired: it is totality failure and aborts.

### 3.4 Request fingerprint

The writer recomputes the request fingerprint as
`encode(extensions.digest(convert_to(request_object::text,'UTF8'),'sha256'),'hex')`,
where `request_object` is PostgreSQL `jsonb` with these exact keys:
`company_id`, `source_document_type`, `source_document_id`,
`source_line_id`, `source_transition`, `source_occurrence_sequence`,
`source_line_ordinal`, `document_order_key_input`, `occurred_at` normalized to
UTC microsecond text, `admission_context`, and `events`. The object is built by the writer in that
shape; JSONB's deterministic object-key ordering is part of this **request
checksum only**, not an ECC component encoding. `p_idempotency_key`,
`p_request_fingerprint` and `p_actor_id` are excluded.

The `events` value is not the caller's unvalidated JSON text. It is a rebuilt
JSONB array in `event_sequence` order with every allowed §4.2 key present, every
optional default materialized, UUID/timestamp/text/fixed-point values in the
exact validated stored form, the augmented §4.3 evidence object, its verified
`source_evidence_fingerprint`, and either the complete normalized §4.4 value
object (all defaults materialized) or JSON null. Open inner evidence objects
retain their JSONB key/value content exactly after PostgreSQL JSONB
normalization. Unknown keys never reach this object. Consequently omitted
optional input and the same explicit default have one fingerprint, whereas any
governed semantic difference has another.

A supplied fingerprint that differs aborts before persistent insertion. This
prevents a caller from reusing one key while changing chronology inputs. The
stored fingerprint remains the existing 64-character text field.

### 3.5 Exact transaction sequence

This subsection is the **sole controlling writer algorithm**. The programme
design §8.2 points here and carries no alternative ordering. No step, lock or
placement of duplicate resolution is implementation discretion.

The idempotency identity is the exact pair `(p_company_id,
p_idempotency_key)`. The company UUID is validated without transformation; the
key is validated for length but is not trimmed, case-folded or Unicode-
normalized. Before that pair may be queried, the writer must authenticate the
actor, prove membership in that same company, validate the admission context,
strictly parse the complete request, normalize the fields governed by §§3.4 and
4, and recompute both request and source-evidence fingerprints. This is the
minimum safe pre-lookup work: less would expose cross-company key existence or
allow a malformed/contradictory retry to inherit an earlier success. Policy,
stream, allocator and key work waits until the duplicate decision.

| Step | Mandatory operation and required inputs | Reads / writes / lock | Failure, retry and context rule |
| ---: | --- | --- | --- |
| 1 | Enforce owner-only execution and validate `p_actor_id`, required scalar types, and the exact caller transaction requirement. | Reads function ACL/session identity only; no table write or lock. | `42501`/`22023`; retry only with an authorised caller/valid scalar. Both contexts. |
| 2 | Prove `p_company_id` exists and `p_actor_id` has the exact `user_company_memberships` row. Do not query occurrence or source evidence first. | Reads `companies` and `user_company_memberships`; no write or row lock. | `42501`; cross-company probing stops here. Both contexts. |
| 3 | Resolve the exact source-registry row and validate `p_admission_context`. Apply V-10 to `production`; apply only §9.3 to `certification_fixture`. | Reads `ref_inventory_event_source_types`; no write or lock. | `23514`/`42501`; production-disabled and certification-only production calls fail before idempotency lookup. |
| 4 | Strictly parse all event/value keys, normalize timestamps/text/UUID/fixed-point values, derive every event's `economic_date` as `(effective_at AT TIME ZONE 'UTC')::date` and the occurrence date as `(p_occurred_at AT TIME ZONE 'UTC')::date`, require the event plan to be contiguous, validate the five immutable source-evidence identity keys, augment §4.3 evidence, recompute every source-evidence fingerprint, build the exact §3.4 request object, and verify `p_request_fingerprint`. | Reads no chronology table; writes only local PL/pgSQL values; no lock. | `22023`/`22021`/`23514`; corrected retry is safe. Both contexts. No master/policy default or session-timezone date is inferred. |
| 5 | Query the company-scoped idempotency identity and, if present, acquire `FOR UPDATE` on that `inventory_occurrences` row. | Reads/locks at most one occurrence using both company and key; no write. This is always the first chronology row lock. | Lock waits for an uncommitted winner. Deadlock is avoided because no stream/allocator lock precedes it. Both contexts. |
| 6 | Classify the existing-row result: exact accepted success, contradictory reuse, or invalid stored result. Compare source identity, fingerprint, context, event count, event ids, and the §3.8 persisted map; require exactly one order-key row in total—and that row `current`—for every event, then reconstruct the stream/key arrays. | Reads occurrence, events, reserved audit context, streams and all key states while holding the occurrence lock; no write. | Exact prior success returns §3.3 immediately. Any request mismatch is `IA5-WP5-011`/`23505`; missing, extra, superseded or otherwise invalid stored result evidence is `IA5-WP5-017`/`23514` and is never repaired. A failed prior transaction has no row and therefore proceeds as new. Both contexts. |
| 7 | On the new path only, resolve every event's company/item/UOM/scope/profile/formula/precision authority against its exact UTC `economic_date`; resolve the exact applicable order policy, E3/E4/E7 ranks, canonical-form version and correction-graph version against that same date. Validate quantity direction and the current base/no-edge rule. | Reads only the §3.6 master/policy allowlist; no write or lock. | Missing, ambiguous, cross-company, out-of-date or incompatible authority aborts. Retry only after governed correction. Both contexts. |
| 8 | Generate one occurrence id and the ordered event-id array, then insert the accepted occurrence as the idempotency reservation with `ON CONFLICT (company_id,idempotency_key) DO NOTHING`. | Inserts `inventory_occurrences`; its unique index is the absent-row concurrency arbiter. | If another transaction won, PostgreSQL waits for its outcome: on commit, lock the winner and repeat step 6; on rollback, this insert succeeds and remains the winner. Contradictory payload never receives the winner's result. |
| 9 | Derive all distinct stream business keys `(company_id,item_id,scope_code)` and process them in exact `ORDER BY uuid_send(company_id), uuid_send(item_id), convert_to(normalize(scope_code, NFC),'UTF8')`. Resolve/create each immutable stream, resolve/create its allocator row, then lock every allocator row `FOR UPDATE` in that same order before allocating any sequence. | Reads/inserts `inventory_valuation_streams` and `inventory_valuation_stream_sequences`; locks allocators only after the occurrence row. | Unique conflicts resolve to the one certified stream and are identity-checked. The fixed occurrence→sorted-stream→allocator order applies to every writer and prevents opposite multi-stream deadlocks. Both contexts. |
| 10 | Build each event's candidate component plan in `event_sequence` order: E1, E3…E10, X1…X4 and, because the only eligible source forbids all edges, E2 = 0. Validate the exact fourteen-component census before any key call. | Reads retained request and resolved authority in local values; no additional write or lock. | Any causal/reversal/correction input is `0A000`; no fifteenth component, version reference or admission metadata may enter the plan. Both contexts. |
| 11 | For each event in `event_sequence` order, increment its already-locked stream allocator with one `UPDATE … RETURNING`; construct and insert the occurrence/event/link/value rows exactly as the exhaustive §3.8 map requires. | Updates only allocator `last_sequence`/`updated_at`; inserts `inventory_events`, `inventory_event_source_links`, optional `inventory_event_values`. | Allocator or required-column mismatch is `23514`. The returned `scope_sequence` is Accepted Event Chronology only. A later error rolls back every counter and row. Both contexts. |
| 12 | Call the §5 resolver exactly once for the newly inserted event with the four required and four correction arguments. Require exactly one 26-column row and compare it to the step-10 plan. | Resolver performs only §5.2 reads; no write or lock. | Zero/multiple rows, component mismatch or encoding failure aborts. Event insertion must precede this call because the certified event and source-link facts are the resolver's retained evidence; that evidence-driven dependency is why the conceptual list in the gate prompt cannot place the executable resolver before event insertion. |
| 13 | Recompute `extensions.digest(canonical_key_bytes,'sha256')`, compare the 32 bytes, prove no `inventory_event_order_keys` row of any state exists for the newly generated event id, and insert exactly one §3.8/WP-4 row with `resolution_state='current'`. | Reads resolver output and all key states for that event; inserts only `inventory_event_order_keys`; no update, demotion, supersession or successor. | Digest mismatch `23514`; pre-existing event resolution raises `IA5-WP5-026`/`23505`; duplicate canonical identity/current key remains `23505`; no repair or suffix. Both contexts. |
| 14 | After every event, query events/keys/streams in event order; require exact event-count cardinality, exactly one current key per event, matching companies/streams, and construct only the §3.3 return object. | Read-only verification; occurrence and allocator locks remain transaction-held. | Totality/cardinality failure `23514`; whole transaction remains abortable. Both contexts. |
| 15 | Permit the deferred `inventory_events_ecc_order_key_totality_ct` to enforce event-side totality at `SET CONSTRAINTS` or transaction end. | Trigger performs §10 reads; no writes. | Production may pass only when source authority is later enabled; certification fixture always receives `IA5-WP5-024` and must roll back. |
| 16 | Return the governed object to the caller. | No write or new lock. | A return is not a commit and does not weaken deferred constraints. Both contexts. |
| 17 | Preserve audit behavior: existing insert audit triggers execute within the same transaction; WP-5 adds no rejected-attempt log. | Audit inserts are existing trigger effects only and roll back with the occurrence. | No audit row may survive a failed or fixture transaction. Both contexts. |
| 18 | Complete the caller transaction. | All locks release at transaction end. | Any exception rolls back occurrence, event, link, value, stream/allocator creation or increment, key and audit effects atomically. Production may commit only after all constraints; certification must explicitly `ROLLBACK` and cannot commit. |

An exact retry never revalidates current policy/master rows as a substitute for
persisted evidence: after steps 1–4 establish the same tenant-safe request, step
6 returns the already governed result. This prevents later master changes from
changing an admitted chronology while still refusing malformed, unauthorised or
contradictory calls.

### 3.6 Writes, updates and exclusions

The writer's direct-read allowlist is exact:

- tenant/master authority: `public.user_company_memberships`,
  `public.companies`, `public.items`, `public.branches`, `public.warehouses`,
  `public.locations`, and `public.units_of_measure`;
- source and admission evidence: `public.ref_inventory_event_source_types`,
  `public.inventory_occurrences`, `public.inventory_events`,
  `public.inventory_event_source_links`, and
  `public.inventory_event_order_keys`;
- scope dependencies: `public.inventory_valuation_scopes`,
  `public.inventory_accounting_profiles`,
  `public.inventory_cost_formula_policies`, and
  `public.inventory_precision_policies`;
- WP-1 ECC authority: `public.inventory_event_order_policies`,
  `public.inventory_event_effect_ranks`,
  `public.inventory_source_type_ranks`, `public.inventory_transition_ranks`,
  `public.inventory_canonical_form_versions`, and
  `public.inventory_correction_graph_versions`; and
- WP-3 accepted chronology: `public.inventory_valuation_streams` and
  `public.inventory_valuation_stream_sequences`.

No other direct table read is authorised. Existing foreign keys and certified
`ENABLE ALWAYS` guards may independently read their already governed parent or
tenant tables; that does not expand the writer's query allowlist. The writer
may write only:

- insert: `inventory_valuation_streams`,
  `inventory_valuation_stream_sequences`, `inventory_occurrences`,
  `inventory_events`, `inventory_event_source_links`, optional
  `inventory_event_values`, and `inventory_event_order_keys`;
- update: only `inventory_valuation_stream_sequences.last_sequence` and
  `updated_at`, through the certified forward-only allocator contract.

It may never read or update
`public.inventory_valuation_scope_sequences`. It may never update an
occurrence, event, source link, value, stream, order key, policy, registry row
or legacy scope allocator. It may never delete or supersede anything. It may
not write `public.inventory_event_allocations`, projections, stock balances,
legacy inventory transactions, cost layers, replay state, Posting requests,
journals, tax, GL or reports.

### 3.7 Idempotency, locks, concurrency and atomicity

- same key + byte-identical governed request + same context: return the same
  occurrence/events/keys/streams with `duplicate=true`;
- same key + different fingerprint, source identity, chronology input, event
  count, payload or context: `23505`, no row from the failed statement;
- same logical source occurrence under a different idempotency key: native
  logical-source `23505`, no partial row;
- the occurrence/idempotency row is always the first chronology lock; all
  distinct stream identities and allocator rows are then acquired in the exact
  sorted business-key order in §3.5, before any allocation;
- a concurrent missing-row duplicate is serialized by the existing occurrence
  unique index, then follows the same locked-winner decision; WP-5 adds no
  advisory lock and no lock result enters ECC;
- stream identity uses its unique key, not insertion order;
- policy, registry, scope and source evidence are read under the caller's one
  transaction snapshot; immutable guards prevent concurrent rewrite;
- two distinct schedules for the same complete authoritative command set must
  produce identical fourteen-component bytes/digests, while accepted
  `scope_sequence` may differ;
- one event failure aborts the whole occurrence; no partial event plan,
  allocator advance, audit row, key or value may survive that statement;
- retry after a failed statement is safe after the governed cause is fixed;
- no exception handler may convert a component, totality, cross-company or
  digest failure into an accepted result.

### 3.8 Complete column-by-column persistence map

This subsection is the complete row-construction authority for the replacement
writer. It covers **139 columns across seven written tables**. No column is
left to inherited implementation choice. Unless a row says otherwise, the
writer inserts once, never updates it, and an unavailable required value aborts
the whole occurrence with `IA5-WP5-010`/`22023` for malformed caller input or
the closest §7 `23514` authority failure. Database-generated IDs and timestamps
are audit/identity evidence only; none enters ECC. “Preserved” means the current
11-argument writer already uses the stated business rule; “modified” means
WP-5 deliberately replaces it. Every omitted nullable value below is explicitly
SQL `NULL`, not an undocumented default.

#### 3.8.1 `inventory_valuation_streams` — 7 columns

The writer selects by exact `(company_id,item_id,scope_code)`. If absent, it
inserts with `ON CONFLICT` handling, reloads the one row, and validates all
identity and dormant fields. It never updates a stream.

| Column / SQL contract | Exact source and stored value | Validation / failure | Evolution and audit meaning |
| --- | --- | --- | --- |
| `id uuid NOT NULL` | Omit on insert; table default `gen_random_uuid()`; return the persisted id | Exactly one row after conflict handling or `IA5-WP5-009`/`23514` | **Modified/additive**; permanent stream identity, not ECC input |
| `company_id uuid NOT NULL` | `p_company_id` | Company/item/scope equality or `IA5-WP5-006` | **Modified/additive** tenant partition |
| `item_id uuid NOT NULL` | normalized `p_events[].item_id` | Existing same-company item and scope item equality or `IA5-WP5-006` | **Modified/additive** partition key |
| `scope_code text NOT NULL` | exact `inventory_valuation_scopes.scope_code`; no trim/case change | Source value must be non-empty and already NFC; otherwise `IA5-WP5-014`/`22021` | **Modified/additive** version-free partition key |
| `activation_state text NOT NULL` | Omit; certified default exact `'dormant'` | Reload must equal `dormant` or `IA5-WP5-009` | **Modified/additive** dormancy evidence |
| `created_by uuid NOT NULL` | `p_actor_id` | Same-company member or `IA5-WP5-005` | **Modified/additive** creator audit identity |
| `created_at timestamptz NOT NULL` | Omit; certified default `clock_timestamp()` | Non-null; never compared or serialized | **Modified/additive** audit clock only |

#### 3.8.2 `inventory_valuation_stream_sequences` — 4 columns

For each bytewise-sorted stream key, insert the allocator row if absent, reload
and company-check it, then lock it `FOR UPDATE`. For each event, execute exactly
`last_sequence = last_sequence + 1, updated_at = clock_timestamp()` with stream
and company predicates and `RETURNING last_sequence`.

| Column / SQL contract | Exact source and stored value | Validation / failure | Evolution and audit meaning |
| --- | --- | --- | --- |
| `valuation_stream_id uuid NOT NULL` | persisted stream id | Exact FK/identity or `IA5-WP5-019`/`23514` | **Modified** from scope-keyed to certified stream-keyed allocator; immutable PK |
| `company_id uuid NOT NULL` | `p_company_id` | Equals stream company or `IA5-WP5-006` | **Preserved concept, modified key**; tenant audit |
| `last_sequence bigint NOT NULL` | insert exact `0`; one locked `+ 1` per event | Must return a positive value; overflow/native check aborts; retry is atomic | **Preserved allocation behavior, modified authority**; Accepted Event Chronology only |
| `updated_at timestamptz NOT NULL` | insert default `clock_timestamp()`; set `clock_timestamp()` on each increment | Non-null; never chronology or ECC | **Preserved** operational allocator timestamp |

#### 3.8.3 `inventory_occurrences` — 24 columns

| Column / SQL contract | Exact source and stored value | Validation / failure | Evolution and audit meaning |
| --- | --- | --- | --- |
| `id uuid NOT NULL` | writer-local `gen_random_uuid()` generated before event IDs | New-path insert must win or follow §3.5 step 8 | **Preserved** occurrence identity; not chronology |
| `atomic_occurrence_id uuid NOT NULL` | exact same UUID as `id` | Certified equality check or transaction abort | **Preserved** atomicity identity |
| `company_id uuid NOT NULL` | `p_company_id` | Company and membership proven before lookup | **Preserved** tenant identity |
| `source_document_type text NOT NULL` | exact ASCII registry key `p_source_document_type`; no trim/case/NFC transform | Registry/context rules or `001`/`002`/`003` | **Preserved, tightened** source authority |
| `source_document_id uuid NOT NULL` | `p_source_document_id` | Required and matches retained evidence | **Preserved** source identity |
| `source_line_id uuid NOT NULL` | `p_source_line_id` | Required and matches retained evidence | **Preserved** source identity |
| `source_transition text NOT NULL` | exact `p_source_transition`; no transform | ASCII domain and rank authority or `010`/`007` | **Preserved, tightened** lifecycle identity |
| `source_occurrence_sequence bigint NOT NULL` | `p_source_occurrence_sequence` | Positive and evidence-equal or `010` | **Preserved** E8 source evidence |
| `idempotency_key text NOT NULL` | exact `p_idempotency_key`; no trim/case/NFC transform | 16…200 and company-scoped uniqueness or `011` | **Preserved, tightened** retry identity |
| `request_fingerprint text NOT NULL` | verified/recomputed §3.4 lowercase SHA-256 hex | Exact equality or `010`; contradictory reuse `011` | **Modified** to governed normalized envelope |
| `occurrence_state text NOT NULL` | fixed literal `'accepted'` | Any other state is outside WP-5 | **Preserved** accepted fact; rejected attempts leave no row |
| `occurred_at timestamptz NOT NULL` | exact `p_occurred_at` instant | Required; request text canonicalized to UTC microseconds | **Preserved, normalized** audit instant; not ECC |
| `event_ids uuid[] NOT NULL` | writer-generated UUID array in `event_sequence` order | Cardinality equals event count; no null/duplicate ids | **Preserved** atomic event membership |
| `event_count integer NOT NULL` | validated JSON array length | Positive and integer-domain safe | **Preserved** atomic cardinality |
| `projection_effect_count integer NOT NULL` | fixed literal `0` | Certified check requires zero | **Preserved** no-projection boundary |
| `posting_request_id uuid NULL` | explicit `NULL` | Non-null is prohibited | **Preserved** no-Posting boundary |
| `posting_result_id uuid NULL` | explicit `NULL` | Non-null is prohibited | **Preserved** no-Posting boundary |
| `audit_identity uuid NOT NULL` | exact same UUID as `id` | Certified equality check | **Preserved** immutable audit identity |
| `failure_code text NULL` | explicit `NULL` | Accepted row requires null | **Preserved** failed requests persist nothing |
| `failure_evidence jsonb NULL` | explicit `NULL` | Accepted row requires null | **Preserved** failed requests persist nothing |
| `retry_of_occurrence_id uuid NULL` | explicit `NULL`; exact retries return prior row instead of inserting | Any non-null retry chain is outside WP-5 | **Preserved** idempotent-return model |
| `foundation_state text NOT NULL` | omit; certified default exact `'dormant'` | Reload/default must equal dormant | **Preserved** dormant foundation |
| `created_by uuid NOT NULL` | `p_actor_id` | Membership already proven | **Preserved** creator audit identity |
| `created_at timestamptz NOT NULL` | omit; certified default `clock_timestamp()` | Non-null; never ECC | **Preserved** audit clock |

#### 3.8.4 `inventory_events` — 41 columns

Text normalization is exact: ASCII-regex domains are stored exactly as supplied;
`lot_number`, `serial_number`, and `reason_code` are stored as
`btrim(normalize(input,'NFC'))`, with empty results rejected. Open JSON evidence
is stored as PostgreSQL JSONB after the reserved augmentation in §4.3.

| Column / SQL contract | Exact source and stored value | Validation / failure | Evolution and audit meaning |
| --- | --- | --- | --- |
| `id uuid NOT NULL` | writer-generated member of occurrence `event_ids` | Unique and fixed before occurrence insert | **Preserved** event identity; prohibited from ECC |
| `company_id uuid NOT NULL` | `p_company_id` | Every dependency same company or `006` | **Preserved** tenant identity |
| `occurrence_id uuid NOT NULL` | new occurrence `id` | Exact FK/member relationship | **Preserved** atomic occurrence link |
| `source_document_type text NOT NULL` | exact `p_source_document_type` | Equals occurrence/primary link | **Preserved** source identity |
| `source_document_id uuid NOT NULL` | `p_source_document_id` | Equals occurrence/primary link | **Preserved** E5/E10 source identity |
| `source_line_id uuid NOT NULL` | `p_source_line_id` | Equals occurrence/primary link | **Preserved** E10 source identity |
| `source_transition text NOT NULL` | exact `p_source_transition` | Equals occurrence/primary link and ranked | **Preserved** E7/E10 source identity |
| `source_occurrence_sequence bigint NOT NULL` | `p_source_occurrence_sequence` | Positive/equal to occurrence | **Preserved** E8 evidence |
| `event_type text NOT NULL` | exact ASCII `p_events[].event_type` | Exact regex or `010` | **Preserved, tightened** event audit class |
| `event_effect text NOT NULL` | exact payload enum | Registry effect map and quantity direction or `013` | **Preserved, tightened** E3 classification input |
| `event_sequence integer NOT NULL` | normalized contiguous payload integer | Equals array position + 1 | **Preserved, tightened** E9 |
| `scope_sequence bigint NOT NULL` | locked WP-3 stream allocator return | Positive and returned once or `019` | **Modified** to stream-keyed Accepted Event Chronology; never ECC |
| `effective_at timestamptz NOT NULL` | exact parsed UTC-microsecond payload instant | RFC3339 `Z`; no timezone-dependent transformation | **Preserved, tightened** E1 |
| `accounting_date date NULL` | exact payload date or explicit `NULL` | `YYYY-MM-DD`; WP-5 does not derive it | **Preserved** Posting/reporting date evidence only |
| `occurrence_date date NOT NULL` | `(p_occurred_at AT TIME ZONE 'UTC')::date` | Same result under every caller timezone | **Modified** to explicit UTC audit date |
| `item_id uuid NOT NULL` | normalized payload UUID | Existing same-company item and scope equality | **Preserved** stream/partition input |
| `valuation_scope_id uuid NOT NULL` | exact payload scope-version UUID | Same company/item and effective on UTC `economic_date` | **Preserved, tightened** scope version |
| `accounting_profile_id uuid NOT NULL` | exact `inventory_valuation_scopes.accounting_profile_id` | Profile same company/effective on UTC date | **Preserved** dependency of record |
| `cost_formula_policy_id uuid NOT NULL` | exact `inventory_valuation_scopes.cost_formula_policy_id` | Formula same company/profile/effective on UTC date | **Preserved** dependency of record |
| `precision_policy_id uuid NOT NULL` | exact selected profile's `precision_policy_id` | Precision same company/effective on UTC date | **Preserved** dependency of record |
| `costing_method text NOT NULL` | exact selected formula's `costing_method` | Certified enum and profile relationship | **Preserved** future costing-policy evidence; no cost computed |
| `physical_warehouse_id uuid NULL` | normalized payload UUID or `NULL` | Same company; must match scope warehouse when scope type is warehouse | **Preserved, tightened** physical evidence |
| `physical_location_id uuid NULL` | normalized payload UUID or `NULL` | Same company; if both location and warehouse carry non-null branch identities, those branch ids must match. The current `locations` schema has no warehouse FK, so no direct location-to-warehouse relationship is invented | **Preserved, tightened** physical evidence |
| `lot_number text NULL` | `btrim(normalize(payload,'NFC'))` or `NULL` | Empty normalized value rejected as `010` | **Modified** deterministic stored text; not ECC |
| `serial_number text NULL` | `btrim(normalize(payload,'NFC'))` or `NULL` | Empty normalized value rejected as `010` | **Modified** deterministic stored text; not ECC |
| `source_uom_id uuid NOT NULL` | normalized payload UUID | Same-company UOM or `006` | **Preserved** quantity evidence |
| `base_uom_id uuid NOT NULL` | normalized payload UUID | Same-company UOM or `006` | **Preserved** quantity evidence |
| `source_quantity numeric(38,6) NOT NULL` | exact six-decimal normalized payload | Precision policy quantization/direction or `013` | **Preserved, tightened** method-neutral quantity |
| `base_quantity numeric(38,6) NOT NULL` | exact six-decimal normalized payload | Equals rounded source × factor under quantity scale | **Preserved, tightened** method-neutral quantity |
| `uom_conversion_factor numeric(38,12) NOT NULL` | exact positive twelve-decimal payload | Governed conversion equality or `013` | **Preserved, tightened** source conversion evidence |
| `valuation_currency_code text NOT NULL` | exact `inventory_valuation_scopes.valuation_currency_code` | Three uppercase ASCII and scope equality | **Preserved** valuation-currency evidence |
| `reversal_of_event_id uuid NULL` | explicit `NULL` | Any input is `020`/`0A000` | **Modified boundary:** current WP-5 base facts only |
| `correction_of_event_id uuid NULL` | explicit `NULL` | Any input is `020`/`0A000` | **Modified boundary:** no correction/re-resolution |
| `predecessor_event_id uuid NULL` | explicit `NULL` | Any input is `020`/`0A000` | **Modified boundary:** E2 fixed to zero |
| `immutable_source_evidence jsonb NOT NULL` | exact augmented §4.3 JSONB | Non-empty, source identities equal, reserved key caller-absent | **Modified** governed chronology/audit evidence |
| `source_evidence_fingerprint text NOT NULL` | exact recomputed augmented-evidence SHA-256 hex | Caller equality required or `010` | **Modified** verified audit checksum |
| `journal_entry_id uuid NULL` | explicit `NULL` | Certified dormant Posting check | **Preserved** no-journal boundary |
| `reason_code text NOT NULL` | `btrim(normalize(payload,'NFC'))` | Non-empty; fixture exact `IA5_CERTIFICATION` | **Modified** deterministic audit reason |
| `foundation_state text NOT NULL` | omit; certified default exact `'dormant'` | Must remain dormant | **Preserved** no-activation evidence |
| `created_by uuid NOT NULL` | `p_actor_id` | Membership proven | **Preserved** creator audit identity |
| `created_at timestamptz NOT NULL` | omit; certified default `clock_timestamp()` | Non-null; never ECC | **Preserved** audit clock |

#### 3.8.5 `inventory_event_source_links` — 13 columns

WP-5 inserts exactly one primary link per event. Split, partial, predecessor,
reversal, correction, transfer-pair, and additional links are prohibited.

| Column / SQL contract | Exact source and stored value | Validation / failure | Evolution and audit meaning |
| --- | --- | --- | --- |
| `id uuid NOT NULL` | omit; default `gen_random_uuid()` | Exact one primary link per event | **Preserved** relationship-row identity |
| `company_id uuid NOT NULL` | `p_company_id` | Equals event company | **Preserved** tenant identity |
| `inventory_event_id uuid NOT NULL` | generated event id | Exact event FK | **Preserved** event relationship |
| `relationship_type text NOT NULL` | fixed literal `'primary'` | Any other WP-5 link is `020`/`0A000` | **Preserved, narrowed** source relationship |
| `source_document_type text NOT NULL` | `p_source_document_type` | Exact event/occurrence identity | **Preserved** source evidence |
| `source_document_id uuid NOT NULL` | `p_source_document_id` | Exact event/occurrence identity | **Preserved** source evidence |
| `source_line_id uuid NOT NULL` | `p_source_line_id` | Exact event/occurrence identity | **Preserved** source evidence |
| `source_transition text NOT NULL` | `p_source_transition` | Exact event/occurrence identity | **Preserved** source evidence |
| `source_occurrence_sequence bigint NOT NULL` | `p_source_occurrence_sequence` | Exact event/occurrence identity | **Preserved** source evidence |
| `related_inventory_event_id uuid NULL` | explicit `NULL` | Non-null is outside initial/base WP-5 | **Preserved base-only** no-edge boundary |
| `immutable_relationship_evidence jsonb NOT NULL` | exact JSONB object with only `request_fingerprint` = verified §3.4 hex and `source_evidence_fingerprint` = verified event hex | Both keys required; no unknown key; mismatch `010` | **Preserved and made exact** immutable relationship proof |
| `created_by uuid NOT NULL` | `p_actor_id` | Membership proven | **Preserved** creator audit identity |
| `created_at timestamptz NOT NULL` | omit; default `clock_timestamp()` | Non-null; never ECC | **Preserved** audit clock |

#### 3.8.6 `inventory_event_values` — 19 columns

The row is omitted exactly when `value` is absent or JSON null. When present,
one row is inserted; all scale/currency metadata is policy-derived, not caller-
selectable. `value_role` and non-null `exchange_rate_identity` are stored as
`btrim(normalize(input,'NFC'))`.

| Column / SQL contract | Exact source and stored value | Validation / failure | Evolution and audit meaning |
| --- | --- | --- | --- |
| `id uuid NOT NULL` | omit; default `gen_random_uuid()` | One role row under existing unique constraint | **Preserved** value-evidence identity |
| `company_id uuid NOT NULL` | `p_company_id` | Equals event/policy company | **Preserved** tenant identity |
| `inventory_event_id uuid NOT NULL` | generated event id | Exact FK | **Preserved** event relationship |
| `value_role text NOT NULL` | trimmed NFC payload role | Lowercase domain regex; fixture exact `inventory_value` | **Modified** deterministic role storage |
| `transaction_currency_code text NOT NULL` | precision policy exact value | Three uppercase ASCII; guard equality | **Preserved** transaction-currency evidence |
| `functional_currency_code text NOT NULL` | precision policy exact value | Three uppercase ASCII; guard equality | **Preserved** functional-currency evidence |
| `transaction_currency_scale smallint NOT NULL` | precision policy exact value | 0…8; amount quantized accordingly | **Preserved** currency-scale evidence |
| `functional_currency_scale smallint NOT NULL` | precision policy exact value | 0…8; functional/GL amount rules | **Preserved** currency-scale evidence |
| `valuation_amount_scale smallint NOT NULL` | precision policy exact value, required `8` | Guard/check equality | **Preserved** amount-scale evidence |
| `unit_rate_scale smallint NOT NULL` | precision policy exact value, required `12` | Guard/check equality | **Preserved** rate-scale evidence |
| `authoritative_transaction_amount numeric(38,8) NOT NULL` | normalized eight-decimal payload | Exact valuation scale **and** value equals its round at `transaction_currency_scale`; otherwise `010` | **Preserved, tightened** caller-authoritative value |
| `authoritative_functional_amount numeric(38,8) NOT NULL` | normalized eight-decimal payload | Exact `valuation_amount_scale=8`; otherwise `010` | **Preserved, tightened** caller-authoritative value |
| `gl_basis_amount numeric(38,8) NOT NULL` | normalized eight-decimal payload | Exact `gl_basis_scale=functional_currency_scale`; otherwise `010` | **Preserved, tightened** future posting basis; no journal |
| `derived_unit_rate numeric(38,12) NULL` | normalized twelve-decimal payload or explicit `NULL` | Exact policy scale | **Preserved, tightened** evidence only; never authority for WAC |
| `exchange_rate_identity text NULL` | trimmed NFC payload or `NULL` | Must be null for same currency and non-empty/non-null for differing currencies | **Preserved, tightened** source FX evidence; no FX calculation |
| `residual_units bigint NOT NULL` | normalized payload integer; omitted input materializes exact `0` | Bigint range | **Preserved, explicit default** precision residue |
| `calculation_evidence jsonb NOT NULL` | exact non-empty payload JSONB | Object and non-empty; contents not interpreted by WP-5 | **Preserved** source calculation audit evidence |
| `created_by uuid NOT NULL` | `p_actor_id` | Membership proven | **Preserved** creator audit identity |
| `created_at timestamptz NOT NULL` | omit; default `clock_timestamp()` | Non-null; never ECC | **Preserved** audit clock |

#### 3.8.7 `inventory_event_order_keys` — 31 columns

Before insert the writer requires zero rows of **any** `resolution_state` for the
event. Every component and version value comes from the one resolver row; the
writer only recomputes/verifies the digest and supplies fixed audit/lifecycle
values. The row is never updated by WP-5.

| Column / SQL contract | Exact source and stored value | Validation / failure | Evolution and audit meaning |
| --- | --- | --- | --- |
| `id uuid NOT NULL` | omit; default `gen_random_uuid()`, captured by `RETURNING` | Exactly one persisted id | **Modified/additive** returned key identity; not ECC |
| `inventory_event_id uuid NOT NULL` | generated event id | Zero prior key rows or `026`/`23505` | **Modified/additive** initial-resolution ownership |
| `company_id uuid NOT NULL` | `p_company_id`; compare resolver/event/stream | Cross-company `006` | **Modified/additive** tenant evidence |
| `valuation_stream_id uuid NOT NULL` | resolver output 1 | Exact event stream | **Modified/additive** partition identity |
| `economic_effective_at timestamptz NOT NULL` | resolver output 2 / event `effective_at` | Exact instant equality | **Modified/additive** E1 |
| `source_precision_code text NOT NULL` | resolver output 3; fixed current value `microsecond` | Exact retained evidence | **Modified/additive** normalization evidence |
| `economic_effect_class text NOT NULL` | resolver output 5 | Exact registry map and domain | **Modified/additive** E3 class |
| `economic_effect_rank smallint NOT NULL` | resolver output 6 | Positive exact policy rank | **Modified/additive** E3 rank |
| `source_type_rank smallint NOT NULL` | resolver output 7 | Positive exact policy rank | **Modified/additive** E4 |
| `document_order_key bytea NOT NULL` | resolver output 8 | Exact §6.3 bytes | **Modified/additive** E5 |
| `source_line_ordinal integer NOT NULL` | resolver output 9 | Positive/equal reserved evidence | **Modified/additive** E6 |
| `transition_rank smallint NOT NULL` | resolver output 10 | Positive exact policy rank | **Modified/additive** E7 |
| `occurrence_ordinal bigint NOT NULL` | resolver output 11 | Positive/equal occurrence | **Modified/additive** E8 |
| `event_ordinal integer NOT NULL` | resolver output 12 | Positive/equal event sequence | **Modified/additive** E9 |
| `canonical_source_identity bytea NOT NULL` | resolver output 13 | Exact §6.3 bytes | **Modified/additive** E10 |
| `correction_placement_class text NOT NULL` | resolver output 14; fixed current `base` | Non-base `020` | **Modified/additive** correction class evidence |
| `correction_chain_depth integer NOT NULL` | resolver output 15; fixed `0` | Nonzero `020` | **Modified/additive** X1 |
| `correction_effective_at timestamptz NOT NULL` | resolver output 16; PostgreSQL `-infinity` base sentinel | Exact depth-zero sentinel | **Modified/additive** X2 |
| `correction_approved_at timestamptz NOT NULL` | resolver output 17; PostgreSQL `-infinity` base sentinel | Exact depth-zero sentinel | **Modified/additive** X3 |
| `correction_identity bytea NOT NULL` | resolver output 18; zero-length bytea | Exact depth-zero sentinel | **Modified/additive** X4 |
| `correction_root_event_id uuid NULL` | resolver output 19; exact `NULL` | Depth-zero/root check | **Modified/additive** root evidence |
| `order_policy_version_id uuid NOT NULL` | resolver output 20 | Exact applicable policy on UTC economic date | **Modified/additive** derivation version |
| `registry_source_document_type text NOT NULL` | resolver output 21 | Exact registry primary key | **Modified/additive** registry authority reference |
| `canonical_form_version_id uuid NOT NULL` | resolver output 22 | Exact applicable version on UTC economic date | **Modified/additive** serialization authority |
| `scope_resolution_version_id uuid NOT NULL` | resolver output 23; exact event scope id | Exact equality | **Modified/additive** scope version |
| `correction_graph_version_id uuid NOT NULL` | resolver output 24 | Exact applicable version on UTC economic date | **Modified/additive** correction-policy reference |
| `canonical_key_bytes bytea NOT NULL` | resolver output 25 | Exact fourteen-component §6 bytes | **Modified/additive** certified WP-4 canonical evidence |
| `ecc_key_digest bytea NOT NULL` | resolver output 26 | 32 bytes and writer recomputation equality | **Modified/additive** certified WP-4 digest |
| `resolution_state text NOT NULL` | fixed literal `'current'`, not table-default discretion | Existing/current row prohibited; never changed by WP-5 | **Modified/additive** initial resolution only |
| `created_by uuid NOT NULL` | `p_actor_id` | Membership proven | **Modified/additive** resolution creator |
| `created_at timestamptz NOT NULL` | omit; default `clock_timestamp()` | Non-null; never ECC | **Modified/additive** audit clock |

#### 3.8.8 Current 11-argument writer behavior disposition

| Current behavior | EA-010 disposition | Controlling rule |
| --- | --- | --- |
| Membership before source admission | **PRESERVED** and made tenant-probe safe | §3.5 steps 1–3 |
| Certification-only disabled source admission | **MODIFIED** into explicit production-versus-fixture contexts | §9 |
| Eleven-argument callable signature | **REMOVED** after exact `DROP … RESTRICT`; restored only by rollback | §§2, 11 |
| Company-scoped idempotency and logical-source uniqueness | **PRESERVED**, with normalized request recomputation and lock classification | §§3.4, 3.5, 3.7 |
| Caller-supplied request/source fingerprints accepted by shape only | **REMOVED**; both are recomputed and compared | §§3.4, 4.3 |
| Unknown event/value keys silently unused | **REMOVED**; rejected | §4.1 |
| Writer-generated occurrence/event UUIDs and atomic event array | **PRESERVED** | §3.8.3–§3.8.4 |
| Legacy scope-version accepted allocator | **REMOVED from writer use**; table itself is preserved | §§3.5, 3.6 |
| WP-3 version-free stream and stream allocator | **ADDED** | §3.8.1–§3.8.2 |
| Scope/profile/formula/precision/currency derivation | **PRESERVED** and fixed to the UTC economic date | §§3.2, 3.8.4 |
| `p_occurred_at::date` under caller timezone | **REMOVED**; UTC occurrence date is mandatory | §§3.2, 3.8.4 |
| Quantity/UOM quantization and direction guards | **PRESERVED** and input formatting tightened | §§4.2, 3.8.4 |
| Source link with two-fingerprint evidence | **PRESERVED** and exact keys/values governed | §3.8.5 |
| Optional caller-authoritative value row and policy currency/scales | **PRESERVED** and every column/default governed | §§4.4, 3.8.6 |
| Posting/journal/projection fields remain null/zero | **PRESERVED** | §§3.6, 3.8 |
| No ECC resolver/order-key/totality | **MODIFIED**: initial resolution, key insertion, and deferred totality added | §§5–6, 10 |
| Correction/reversal/predecessor payload accepted by base writer | **REMOVED for WP-5**; any non-null edge fails `0A000` | §§4.2, 5.3 |
| Free-form text stored without a normalization decision | **REMOVED**; exact trimmed-NFC rules apply where stated | §§3.8.4, 3.8.6 |
| Failed statement leaves no partial row/counter/audit effect | **PRESERVED** | §§3.5, 3.7 |

---

## 4. Exact `p_events` JSON contract

### 4.1 Array and unknown-key policy

`p_events` is a non-empty JSON array. WP-5 adds no arbitrary business maximum;
its count must fit the existing `inventory_occurrences.event_count integer`
domain. Every element is an object.
Element `i` (zero based) must carry `event_sequence = i + 1`; sequences must be
unique and contiguous. **Unknown event keys and unknown `value` keys are
rejected.** No key is ignored.

Two nested evidence objects are intentionally open:

- `immutable_source_evidence`: source-domain evidence. Unknown inner keys are
  retained byte-logically through JSONB, included in its checksum, never
  interpreted as chronology, and never ignored or promoted to authority;
- `calculation_evidence`: source calculation evidence for an optional value.
  Unknown inner keys are retained, not interpreted by WP-5, and cannot affect
  chronology.

This is an exact policy, not an undefined “metadata JSONB” escape hatch.

`immutable_source_evidence` must contain at least these exact keys before the
writer adds its reserved object: `source_company_id` (lowercase UUID string),
`source_document_id` (lowercase UUID string), `source_line_id` (lowercase UUID
string), `source_transition` (string), and `source_occurrence_sequence`
(positive JSON integer). Each must equal the corresponding scalar function
argument. This is the exact certification-fixture source-company proof. A
future production adapter must supply evidence under a separately accepted
source contract; because none exists, the production path remains unavailable
rather than guessing a source table.

### 4.2 Event fields

| Key | JSON type | Required/default | Validation and ownership | Chronology / audit |
| --- | --- | --- | --- | --- |
| `event_type` | string | Required | caller; `^[a-z][a-z0-9_]{2,49}$` | audit only |
| `event_effect` | string | Required | caller; exact `quantity_increase`, `quantity_decrease`, or `value_only` | registry maps to E3 |
| `event_sequence` | number | Required | positive JSON integer, equals array position + 1 | E9, retained |
| `effective_at` | string | Required | exact UTC RFC3339 `YYYY-MM-DDTHH:MM:SS.ffffffZ`; source workflow owns | E1, retained as `timestamptz` |
| `source_precision_code` | string | Required | exact `microsecond` in WP-5 | retained normalization metadata; not a comparator component and not serialized as one |
| `economic_effect_class` | string | Required | caller assertion; must equal exact registry mapping and quantity direction | E3 class; retained in key |
| `accounting_date` | string or null | Optional, default null | exact `YYYY-MM-DD` if present | retained event fact; not ECC |
| `item_id` | string | Required | lowercase UUID; same company and scope | partition/stream selection, not tuple |
| `valuation_scope_id` | string | Required | lowercase UUID; exact company/item/effective scope version | `V` scope version; not tuple |
| `physical_warehouse_id` | string or null | Optional, default null | lowercase UUID and same company when present | retained; not ECC |
| `physical_location_id` | string or null | Optional, default null | lowercase UUID and governed warehouse/company when present | retained; not ECC |
| `lot_number` | string or null | Optional, default null | store exact `btrim(normalize(value,'NFC'))`; reject empty result; WP-5 adds no length cap absent a current table constraint | retained; not ECC |
| `serial_number` | string or null | Optional, default null | store exact `btrim(normalize(value,'NFC'))`; reject empty result; WP-5 adds no length cap absent a current table constraint | retained; not ECC |
| `source_uom_id` | string | Required | lowercase UUID, same company | retained; not ECC |
| `base_uom_id` | string | Required | lowercase UUID, same company | retained; not ECC |
| `source_quantity` | string | Required | signed fixed-point with exactly 6 decimals; direction matches effect | classification only; magnitude prohibited from ECC |
| `base_quantity` | string | Required | signed fixed-point with exactly 6 decimals | not ECC |
| `uom_conversion_factor` | string | Required | positive fixed-point with exactly 12 decimals; governed equality holds | not ECC |
| `reversal_of_event_id` | string or null | Optional, default null | lowercase UUID, same company; current WP-5 rejects unsupported reversal chain | causal evidence only; E2 later |
| `correction_of_event_id` | string or null | Optional, default null | lowercase UUID, same company; must equal correction target when present | correction graph input |
| `predecessor_event_id` | string or null | Optional, default null | lowercase UUID, same company | causal evidence for later E2 |
| `correction_target_event_id` | string or null | Optional, default null | lowercase UUID; required only for a supported anchored source rule | X/root input |
| `correction_effective_at` | string or null | Optional, default null | exact UTC microsecond RFC3339; required for supported non-base correction | X2 |
| `correction_approved_at` | string or null | Optional, default null | exact UTC microsecond RFC3339; required for supported non-base correction | X3 |
| `correction_placement_class` | string or null | Optional, default null | if present, exact registry value; caller cannot override registry | X placement |
| `immutable_source_evidence` | object | Required | non-empty; exact five source-identity keys in §4.1; reserved key `ia5_ecc_admission` prohibited in input | retained, fingerprinted; never directly serialized into ECC |
| `source_evidence_fingerprint` | string | Required | 64 lowercase hex; exact checksum §4.3 | audit, not tuple |
| `reason_code` | string | Required | store exact `btrim(normalize(value,'NFC'))`; reject empty result; certification fixture uses exact `IA5_CERTIFICATION`; WP-5 adds no narrower table domain | audit, not tuple |
| `value` | object or null | Optional, default null | exact §4.4 object | existing value evidence only; no resolver use |

### 4.3 Reserved audit evidence and checksum

The writer rejects caller input already containing `ia5_ecc_admission`, then
adds that exact object to `immutable_source_evidence`:

| Reserved key | JSON type | Exact value source |
| --- | --- | --- |
| `source_line_ordinal` | number | `p_source_line_ordinal` |
| `document_order_key_input` | string | NFC-normalized `p_document_order_key_input` |
| `source_precision_code` | string | event value |
| `economic_effect_class` | string | validated registry result |
| `correction_target_event_id` | string or null | validated event value |
| `correction_effective_at` | string or null | normalized event value |
| `correction_approved_at` | string or null | normalized event value |
| `correction_placement_class` | string | resolved registry value |
| `admission_context` | string | validated function context |

`source_evidence_fingerprint` must equal
`encode(extensions.digest(convert_to(augmented_evidence::text,'UTF8'),'sha256'),'hex')`,
where `augmented_evidence` is the **augmented** PostgreSQL JSONB object. This
checksum is audit evidence; it is not `ecc_key_digest` and never replaces
canonical component bytes.

### 4.4 Optional `value` object

Allowed keys are exactly:

| Key | JSON type | Requirement |
| --- | --- | --- |
| `value_role` | string | Required; store exact `btrim(normalize(value,'NFC'))`, require the existing lowercase role regex; certification fixture uses exact `inventory_value`; no new table domain |
| `authoritative_transaction_amount` | string | Required; signed fixed-point, exactly 8 decimals |
| `authoritative_functional_amount` | string | Required; signed fixed-point, exactly 8 decimals |
| `gl_basis_amount` | string | Required; signed fixed-point, exactly 8 decimals |
| `derived_unit_rate` | string or null | Optional, default null; signed fixed-point, exactly 12 decimals |
| `exchange_rate_identity` | string or null | Optional, default null; when non-null store exact `btrim(normalize(value,'NFC'))` and reject empty; required by existing currency rule when currencies differ |
| `residual_units` | number | Optional, default `0`; signed JSON integer in bigint range |
| `calculation_evidence` | object | Required and non-empty |

These are caller-authoritative values preserved by the existing foundation.
WP-5 validates scale and stores them. It does not compute quantity valuation,
unit cost, layers, WAC, FIFO, COGS, tax or journals.

---

## 5. Component resolver contract

### 5.1 Exact signature and properties

`public.fn_ia5_ecc_resolve_components(`
`p_inventory_event_id uuid, p_source_line_ordinal integer,`
`p_document_order_key_input text, p_economic_effect_class text,`
`p_correction_target_event_id uuid DEFAULT NULL,`
`p_correction_effective_at timestamptz DEFAULT NULL,`
`p_correction_approved_at timestamptz DEFAULT NULL,`
`p_correction_placement_class text DEFAULT NULL)`

The first four inputs are semantically non-null and have no default. The four
correction inputs are nullable with the displayed SQL defaults; current
`IA5_CERTIFICATION` requires all four to resolve to null/base behavior. A null
in any first-four input is `22023`.

It returns a `TABLE` with exactly one row and these columns in this order. The
EA-009 addition of output 4 does not change the eight-argument function
signature; it closes the WP-4 all-fourteen contract instead of creating an
overload.

| # | Output | PostgreSQL type | Null? |
| ---: | --- | --- | --- |
| 1 | `valuation_stream_id` | `uuid` | No |
| 2 | `economic_effective_at` | `timestamptz` | No |
| 3 | `source_precision_code` | `text` | No |
| 4 | `causal_depth` | `integer` | No; exact `0` in current WP-5 |
| 5 | `economic_effect_class` | `text` | No |
| 6 | `economic_effect_rank` | `smallint` | No |
| 7 | `source_type_rank` | `smallint` | No |
| 8 | `document_order_key` | `bytea` | No |
| 9 | `source_line_ordinal` | `integer` | No |
| 10 | `transition_rank` | `smallint` | No |
| 11 | `occurrence_ordinal` | `bigint` | No |
| 12 | `event_ordinal` | `integer` | No |
| 13 | `canonical_source_identity` | `bytea` | No |
| 14 | `correction_placement_class` | `text` | No |
| 15 | `correction_chain_depth` | `integer` | No |
| 16 | `correction_effective_at` | `timestamptz` | No |
| 17 | `correction_approved_at` | `timestamptz` | No |
| 18 | `correction_identity` | `bytea` | No |
| 19 | `correction_root_event_id` | `uuid` | Yes only when depth is 0 |
| 20 | `order_policy_version_id` | `uuid` | No |
| 21 | `registry_source_document_type` | `text` | No |
| 22 | `canonical_form_version_id` | `uuid` | No |
| 23 | `scope_resolution_version_id` | `uuid` | No |
| 24 | `correction_graph_version_id` | `uuid` | No |
| 25 | `canonical_key_bytes` | `bytea` | No |
| 26 | `ecc_key_digest` | `bytea` | No; exactly 32 bytes |

Properties: `plpgsql`, `VOLATILE`, `PARALLEL UNSAFE`, `SECURITY DEFINER`, owner
`postgres`, exact function configuration `SET search_path = public` and
`SET TimeZone = 'UTC'`, and no direct execution grant to
`PUBLIC`, `anon`, `authenticated`, or `service_role`. `VOLATILE` is required so
the resolver can see the event and stream inserted by earlier statements in the
writer's transaction. It performs no DML and emits no audit row. Only the
writer may call it in governed runtime. Direct owner invocation is permitted
only by future tests inside a rolled-back transaction and may not be cited as a
runtime consumer.

### 5.2 Reads, writes, determinism and row count

The resolver's exact direct-read allowlist is:
`public.inventory_events`, `public.inventory_occurrences`,
`public.inventory_event_source_links`, `public.inventory_valuation_scopes`,
`public.inventory_accounting_profiles`,
`public.inventory_cost_formula_policies`,
`public.inventory_precision_policies`, `public.inventory_valuation_streams`,
`public.ref_inventory_event_source_types`,
`public.inventory_event_order_policies`,
`public.inventory_event_effect_ranks`,
`public.inventory_source_type_ranks`, `public.inventory_transition_ranks`,
`public.inventory_canonical_form_versions`,
`public.inventory_correction_graph_versions`, and
`public.inventory_event_order_keys`. The last table is read only for a
registered same-company correction target; the current certification rule
rejects that path. No other table read is authorised.

The resolver may not read either accepted allocator table,
`inventory_events.scope_sequence`, clocks, generated occurrence/event/key ids
as ordering input, stock, layers, method state, availability, projections,
Posting, journals, tax, GL, UI or reports.

It writes nothing. For valid input it returns exactly one row. Zero or more than
one qualifying policy/version/rank/stream/target is a failure, never a default.
The output is a deterministic pure function of immutable event/source evidence
and the resolved version vector. Repeated calls in one unchanged transaction
are byte-identical. Replay must read the persisted output; it must not call this
resolver against current master data.

### 5.3 Resolution rules

1. Load the exact event, occurrence and primary source link; all three company
   and logical identities must match.
2. Load the exact registry row. Map `event_effect` to E3 class and compare to
   `p_economic_effect_class`; resolve exactly one order policy where company
   matches, `policy_code = source_document_type`, and
   `effective_from <= E1::date <= COALESCE(effective_to,'infinity')`. Resolve
   exactly one positive E3 rank, E4 rank and E7 rank under that policy, each
   with the same company and exact class/type/transition. Every effective-date
   comparison uses `economic_date := (E1 AT TIME ZONE 'UTC')::date`; `E1::date`
   under an inherited session timezone is prohibited.
3. E1 is the event's normalized `effective_at`; source precision is the reserved
   audit value and must be `microsecond`.
4. E5: `canonical_source_document_id` requires
   `p_document_order_key_input = event.source_document_id::text` in lowercase
   and returns the exact `PXL-ECC-E5-K1` encoded document key in §6.3. The currently unrepresented
   `governed_business_sequence` encoding is `0A000` and cannot be used until a
   later registry amendment governs numeric/text sequence representation. No
   current source is production enabled, so this is fail-closed, not a product
   limitation claim.
5. E6 equals positive `p_source_line_ordinal`; E8 equals the occurrence's
   positive source occurrence sequence; E9 equals the positive, contiguous
   event sequence.
6. E10 is the exact inner canonical composite in §6.3, built from source type,
   source document UUID, source line UUID, transition, E8 and E9. Event id and
   occurrence id are prohibited.
7. Resolve exactly one version-free stream by company/item/scope code. Its
   company/item/scope must match the event's scope version. Resolve the exact
   scope version as `scope_resolution_version_id`.
8. Resolve exactly one canonical-form version where company matches,
   `version_code = source_document_type`, and its inclusive activation range
   contains E1. Resolve exactly one company correction-graph version whose
   inclusive effective range contains E1. The canonical form's
   `encoding_rules` must be exactly §6.1.
9. For current `IA5_CERTIFICATION`, registry placement is `base` and all
   `predecessor_event_id`, `reversal_of_event_id`, `correction_of_event_id`, and
   four correction arguments must be null. With no declared in-cohort edge,
   ECC-01 §4.2 resolves E2 `causal_depth = 0`; X1 = 0, X2/X3 = PostgreSQL
   `-infinity`, X4 = zero-length bytea, root = null. Any edge, correction,
   reversal or non-base placement is `0A000`. A future separately authorised
   source rule may permit another accepted ECC-01 case only after governing how
   its E2 and correction evidence are resolved; WP-5 adds no such row.
10. Build §6 bytes from exactly E1, E2, E3…E10 and X1…X4, compute the digest,
    and return. Do not insert the key. The five version values, source precision,
    economic-effect class, correction-placement class and all admission inputs
    remain separately retained evidence and are not extra serialized
    components.

The resolver does not calculate cost, quantity valuation, FIFO layers, WAC,
COGS, journal lines, posting instructions, tax or financial-statement effects.

---

## 6. Canonical encoding and digest

### 6.1 Canonical-form authority marker

The resolved `inventory_canonical_form_versions.encoding_rules` must equal this
JSON object exactly; unknown or missing keys fail:

`{"component_framing":"TAG_U8_LENGTH_U32_BE","digest":"sha256","ecc_key_encoding":"PXL_ECC_K1","integer_encoding":"TWOS_COMPLEMENT_BIG_ENDIAN","text_normalization":"NFC","timestamp_encoding":"UTC_MICROSECOND_TEXT","uuid_encoding":"RFC4122_16_BYTE"}`

The certification fixture inserts that object explicitly. The table default
`{}` is structural only and is not an executable encoding authority.

### 6.2 Framing rules

- byte order: network/big-endian for every integer and length;
- document header: UTF-8 ASCII bytes `PXL-ECC-K1`, followed by one zero byte;
- immediately after the header are exactly fourteen component records in the
  §6.4 order. Nothing may precede, follow or be interleaved with them;
- every component record: one unsigned tag byte, then a four-byte unsigned
  big-endian payload length, then exactly that many payload bytes;
- lengths use the non-negative range of PostgreSQL `int4send`; overflow fails;
- no delimiter, terminator, locale collation, implicit cast, JSON text, SQL
  `NULL`, or omitted component is allowed;
- text: Unicode NFC, UTF-8 bytes, exact case after domain validation;
- UUID: exactly `uuid_send(value)`, 16 bytes; UUID text is never serialized;
- `smallint`/`integer`/`bigint`: exactly `int2send`/`int4send`/`int8send`, signed
  two's-complement network order; governed ordinals/ranks are positive;
- normal timestamp: ASCII UTC microsecond text
  `YYYY-MM-DDTHH:MM:SS.ffffffZ`, exactly 27 bytes;
- base-sentinel timestamp: one byte `00`; normal timestamp payload is byte
  `01` followed by the 27 timestamp bytes, preventing sentinel collision;
- bytea: its raw bytes;
- JSON and numeric amounts: never serialized as ECC components;
- composites: nested tag/length/value records with their own domain header;
- digest: exact pgcrypto call
  `extensions.digest(canonical_key_bytes,'sha256')`, returned as 32-byte
  `bytea`; hex text is not stored in `ecc_key_digest`.

The five non-null version values are retained only in their certified WP-4
columns: `order_policy_version_id`, `registry_source_document_type`,
`canonical_form_version_id`, `scope_resolution_version_id`, and
`correction_graph_version_id`. They govern derivation and interpretation but
are not E/X comparator components and therefore are not framed into
`canonical_key_bytes`. Source precision and the economic-effect and
correction-placement class labels likewise remain separate evidence. No current
master-data lookup may replace a retained version during replay.

### 6.3 E5 document key and E10 composite

`document_order_key` begins with ASCII `PXL-ECC-E5-K1` plus zero byte, followed
by one inner tag/length/value record. Tag `01` means
`canonical_source_document_id` and its payload is the 16 UUID bytes. Tag `02`
is reserved for a future separately governed business-sequence representation
and is rejected by WP-5. No other tag is valid. This makes the stored E5 value
self-identifying and length-prefixed before it is framed again as component 5.

`canonical_source_identity` begins with ASCII `PXL-ECC-E10-K1` plus zero byte,
then these inner records:

| Tag | Input | Encoding |
| ---: | --- | --- |
| `01` | source document type | NFC UTF-8 text |
| `02` | source document id | 16 UUID bytes |
| `03` | source line id | 16 UUID bytes |
| `04` | source transition | NFC UTF-8 text |
| `05` | occurrence ordinal | 8-byte `int8send` |
| `06` | event ordinal | 4-byte `int4send` |

This exact composite is recomputable from retained event facts and contains no
database-generated identity. `company_id` is not duplicated in E10: it is the
mandatory stream partition and is constant within every comparison. The WP-4
shorthand referencing `inventory_events_logical_event_uq` means that unique
key's six business-identity fields after the separate company partition.

### 6.4 Complete ordered fourteen-component sequence

After the §6.2 header, `canonical_key_bytes` records exactly these fourteen
components. Component number is the ADR-C01/ECC-01 comparator position; tag is
one unsigned hexadecimal byte. The source and authority columns are exhaustive
for current WP-5:

| # / tag | Component / logical type | Exact source field/table | Derivation owner and authority | Exact payload representation |
| ---: | --- | --- | --- | --- |
| 1 / `01` | E1 economic instant / `timestamptz` | `inventory_events.effective_at`, supplied by `p_events[].effective_at` | source workflow assertion validated by WP-5 under the registry/canonical-form versions | normal timestamp payload |
| 2 / `02` | E2 causal depth / `integer` | resolver result `causal_depth` | source domain owns edge declarations; Inventory/WP-5 derives exact `0` because the eligible base source requires every predecessor/reversal/correction field null; ECC-01 §4.2 | `int4send(0)` |
| 3 / `03` | E3 effect rank / `smallint` | `inventory_event_effect_ranks.effect_rank`, selected after the registry map classifies event effect | WP-1 policy plus WP-2 registry; WP-5 resolves/validates | `int2send` bytes |
| 4 / `04` | E4 source-type rank / `smallint` | `inventory_source_type_ranks.source_type_rank` | WP-1 applicable event-order policy; WP-5 resolves | `int2send` bytes |
| 5 / `05` | E5 document order key / `bytea` | source document UUID plus registry algorithm; `p_document_order_key_input` is only a validation/derivation input | source identity + WP-2 registry; WP-5 validates and encodes | complete §6.3 E5 bytes |
| 6 / `06` | E6 line ordinal / `integer` | `p_source_line_ordinal`, retained at `inventory_events.immutable_source_evidence.ia5_ecc_admission.source_line_ordinal` | source workflow + WP-2 line-order authority; WP-5 validates | `int4send` bytes |
| 7 / `07` | E7 transition rank / `smallint` | `inventory_transition_ranks.transition_rank` for the retained transition | WP-1 policy; WP-5 resolves | `int2send` bytes |
| 8 / `08` | E8 occurrence ordinal / `bigint` | `inventory_occurrences.source_occurrence_sequence` | immutable source occurrence semantics under WP-2 registry | `int8send` bytes |
| 9 / `09` | E9 event ordinal / `integer` | `inventory_events.event_sequence` | deterministic source event plan validated by WP-5 | `int4send` bytes |
| 10 / `0A` | E10 source identity / `bytea` | retained source type, document UUID, line UUID, transition, E8 and E9 | immutable source identity under registry/canonical-form authority; WP-5 composes | complete §6.3 E10 bytes |
| 11 / `0B` | X1 correction depth / `integer` | resolver constant `0` | WP-2 `correction_placement_class='base'` plus null correction/ancestry evidence | `int4send(0)` |
| 12 / `0C` | X2 correction effective instant / sentinel | base sentinel; no source timestamp substituted | same base rule | one byte `00` |
| 13 / `0D` | X3 correction approval instant / sentinel | base sentinel; no source timestamp substituted | same base rule | one byte `00` |
| 14 / `0E` | X4 correction identity / `bytea` | base sentinel; no generated id used | same base rule | zero-length payload |

Certified WP-4 owns the meaning, persistence and immutability of the complete
byte string and its digest. WP-5 owns only the derivation/validation and
byte-producing implementation that satisfies it. `p_source_line_ordinal` and
`p_document_order_key_input` are derivation inputs for E6 and E5 respectively;
they are not extra components. `p_admission_context`, request/idempotency data,
actor, occurrence time, version vector, source precision and class labels do not
participate. A fifteenth/sixteenth component or any undocumented prefix/suffix
is prohibited.

### 6.5 Error and collision rules

Invalid UTF-8/NFC conversion, timestamp precision, length overflow or composite
construction is `22021` and aborts. Any null component, unknown version marker,
or sentinel outside depth zero is `23514`. Digest recomputation mismatch is
`23514`. Duplicate `(valuation_stream_id,canonical_key_bytes)` is native
`23505`; no suffix, stable sort, event id, row id, clock or lock result may break
the tie.

---

## 7. Failure contract

Every message begins with the stable failure id. Unless stated otherwise, the
function statement aborts, no row/counter/audit effect from it remains, and a
retry is safe only after the governed cause is corrected.

| Failure ID | Condition / responsible object | SQLSTATE | Retry / audit / future test owner |
| --- | --- | --- | --- |
| `IA5-WP5-001` | Unknown source type; writer | `22023` | Retry after registry authority; attempted type in error; `112` |
| `IA5-WP5-002` | Source is not exact certification-eligible in fixture context; writer | `23514` | Retry only with exact fixture; `112` |
| `IA5-WP5-003` | Source is not production-enabled/complete in production context; writer | `23514` | Retry after separate activation/certification; no bypass; `112` |
| `IA5-WP5-004` | Invalid fixture source/context/caller; writer | `42501` | Owner-only; `112` |
| `IA5-WP5-005` | Actor is not a company member; writer | `42501` | Retry with governed membership; `112` |
| `IA5-WP5-006` | Missing tenant master identity or cross-company source/item/UOM/warehouse/location/event/scope/policy/stream/key/target; writer/resolver/guards | `23514` | No row; offending identities in message, no secret payload; `112` |
| `IA5-WP5-007` | Missing or ambiguous order policy/effect/source/transition rank; resolver | `23514` | Retry after governed version fixture; `112` |
| `IA5-WP5-008` | Missing/invalid canonical-form or correction-graph version; resolver | `23514` | Retry after governed version; `112` |
| `IA5-WP5-009` | Missing/multiple/out-of-UTC-date/mismatched valuation scope, accounting profile, cost formula, precision policy or valuation stream; writer/resolver | `23514` | Retry only after governed authority/source correction; `112` |
| `IA5-WP5-010` | Malformed argument, event plan, key, decimal, UUID, timestamp or unknown JSON key; writer | `22023` | Idempotent after correcting input; `112` |
| `IA5-WP5-011` | Idempotency key reused with different governed request/context; writer | `23505` | Not retryable under same key; evidence is both fingerprints/identities; `112` |
| `IA5-WP5-012` | Logical source occurrence duplicated under another key; occurrence constraint/writer | `23505` | Not retryable as a new fact; `112` |
| `IA5-WP5-013` | Contradictory event plan/effect/direction/ancestry; writer/resolver | `23514` | Whole occurrence rejected; `112` |
| `IA5-WP5-014` | Malformed or non-NFC component / canonical encoding failure; resolver | `22021` | Retry after canonical input correction; `111`/`112` |
| `IA5-WP5-015` | Digest recomputation differs; writer | `23514` | Not accepted; implementation defect blocks gate/certification; `111` |
| `IA5-WP5-016` | E10 or fourteen-component canonical key bytes duplicate another fact; order-key constraint | `23505` | Both logical applications are unsafe; stream certification blocked; `112` |
| `IA5-WP5-017` | Persisted event has no current key or, during duplicate reconstruction, does not have exactly one total key row and that row current; writer/trigger | `23514` | Transaction aborts; no repair path; `112` |
| `IA5-WP5-018` | Duplicate current order key; WP-4 partial unique index | `23505` | Transaction aborts; `112` |
| `IA5-WP5-019` | Stream allocator row/company mismatch or no returned sequence; writer | `23514` | Transaction aborts including counter statement; `112` |
| `IA5-WP5-020` | Unsupported correction/reversal/fork/counterfactual chain under current source rule; resolver | `0A000` | Requires separate source/correction authority, not retry; `112` |
| `IA5-WP5-021` | Illegal key update, deletion or supersession; WP-4 guard | `23514` | Original remains; `112` regression |
| `IA5-WP5-022` | Resolver returns zero/multiple rows; writer | `23514` | Transaction aborts; `111`/`112` |
| `IA5-WP5-023` | Event-side totality fails at deferred boundary; trigger function | `23514` | Transaction aborts; no event/key residue; `112` |
| `IA5-WP5-024` | Certification fixture reaches constraint execution/commit; trigger function | `23514` | Mandatory rollback path; not production evidence; `112` |
| `IA5-WP5-025` | Rollback precondition/residue mismatch; rollback test/migration | `23514` | Rollback stops before destructive step; `113` |
| `IA5-WP5-026` | Any order-key row of any state already exists for a newly generated event at initial resolution; writer | `23505` | Whole occurrence aborts; WP-5 never repairs, demotes or adds a successor; `112` |

Native foreign-key `23503`, check `23514`, unique `23505` and privilege `42501`
remain authoritative where PostgreSQL raises before a wrapper can attach a
message. Tests assert SQLSTATE and the stable prefix where WP-5 raises itself.
Failures are visible through the failed statement and transactional audit
rollback; WP-5 adds no persistent rejected-occurrence log and must not leak
cross-company evidence into messages.

---

## 8. Security and tenant isolation

| Control | Exact rule |
| --- | --- |
| Owner/security | All three functions owned by `postgres`, `SECURITY DEFINER`, `search_path=public`; no dynamic schema names |
| ACL | `REVOKE ALL` from `PUBLIC`, `anon`, `authenticated`, `service_role`; no new grant |
| Anonymous/authenticated | Cannot execute functions or write chronology tables; authenticated retains existing membership-scoped `SELECT` only |
| Service role | No direct execute and no chronology DML grant; BYPASSRLS does not create authority |
| Direct client DML | Prohibited by existing table ACLs/RLS/guards; no client may create, supersede or delete order evidence |
| Membership | `p_actor_id` must have exact `user_company_memberships` row for `p_company_id` |
| Source company | Certification evidence must carry the exact fixture company; production requires a separately authorised source adapter. No such adapter exists, so production admission is currently fail-closed |
| Event/occurrence | Company and full logical source identity must match |
| Scope/profile/formula/precision | Every dependency company equals the event company and is effective on E1 |
| Stream/allocator | Stream and allocator company equal event company; key-side WP-4 guard rechecks stream company |
| Order policy/ranks/versions | Every row company equals event company; exactly one applicable version/rank |
| Correction target | Same company and stream; current source rejects correction paths |
| Certification execution | `postgres` owner only, local/fresh governed database, one explicit transaction ending `ROLLBACK`; commit-rejecting trigger armed |
| Audit | Existing insert audit triggers run in the same transaction; certification audit rows roll back with fixtures |

No direct role can create or alter economic chronology evidence. Owner access is
a migration/test authority, not an application entitlement.

---

## 9. Production versus certification admission

### 9.1 Context matrix

| Rule | Production economic admission | Certification-only rolled-back fixture admission |
| --- | --- | --- |
| Context token | `production` (default) | `certification_fixture` (must be explicit) |
| Caller | Future separately authorised owner-mediated server caller; none exists | `postgres` test/migration owner only |
| Environment | Governed local/hosted environment only after separate deployment authority | Local fresh/reset certification database only; never hosted evidence |
| Source eligibility | Registered, complete, not certification-only, production-enabled, source adapter certified | Exact `IA5_CERTIFICATION`, certification-only=true, production-enabled=false, removal phase IA-6 |
| Version/stream state | Activated under later migration; currently impossible | Exact dormant rolled-back WP-1/WP-3 fixtures |
| Transaction end | `READ COMMITTED` or stronger; commit only if every deferred invariant passes | Mandatory explicit `BEGIN ISOLATION LEVEL SERIALIZABLE`; assertions; explicit `ROLLBACK`; commit prohibited and DB-rejected |
| Persistence | Governed production rows only after future activation | Zero row/audit/counter residue |
| Runtime consumer | None in WP-5 | None; tests only |
| Claims | Only after source activation, integration and later certification | WP-5 contract evidence only |

### 9.2 Production path remains fail-closed

A production-disabled source cannot be economically admitted. A
certification-only source cannot be called by UI, API, report, job, worker,
posting or application runtime. Production additionally requires a governed
source-company adapter and activated versions/stream; none exists in WP-5.
Therefore every production-context call in the current repository must fail
before occurrence insertion. WP-5 enables no source type, Inventory runtime,
hosted deployment or production claim.

### 9.3 Exact certification fixture mechanism

The smallest mechanism is the writer's explicit
`p_admission_context='certification_fixture'`; no custom setting, broad feature
flag, wrapper, table or grant is created. It is compatible with WP-1…WP-4
precedent: certification authorities are owner-created inside a transaction and
removed by final rollback.

#### Single-session pgTAP fixture path

Tests `111` and `112` use this path:

1. runs only as `postgres` in a fresh local certification database;
2. begins `BEGIN ISOLATION LEVEL SERIALIZABLE` and records before-counts for every affected
   Inventory/WP-1/WP-3/WP-4/audit table;
3. creates exact company/user/master/policy/scope/version/rank fixtures,
   including §6.1 encoding rules and exact `IA5_CERTIFICATION` registry use;
4. calls the writer with the explicit fixture context;
5. proves event, stream, accepted allocator and key structure before rollback;
6. proves the production context still rejects the same disabled source;
7. proves `SET CONSTRAINTS inventory_events_ecc_order_key_totality_ct IMMEDIATE`
   or attempted commit raises `IA5-WP5-024`/`23514`;
8. ends with explicit `ROLLBACK`, never `COMMIT`; and
9. in a clean follow-up transaction, proves every before/after count and object
   state equal, including `sys_audit_logs` and allocator rows.

The deferred trigger makes accidental fixture commit impossible: after proving
one current key, it rejects a certification-only event at constraint execution.
The fixture path has no grant to normal roles and is excluded from application,
production, hosted and activation claims.

#### Two-session concurrency verification path

`WP5-CONC-114` is allocated to the future, non-runtime repository asset
`supabase/verification/ia5_wp5_concurrent_idempotency.sql`. It is separate from
test `112` because two autonomous PostgreSQL sessions cannot see an uncommitted
single-session fixture. The asset follows the existing
`supabase/verification/ia5_concurrent_idempotency.sql` precedent but must use the
EA-010 writer contract and these exact controls:

1. It aborts unless the target is the local Supabase database and a fresh
   `supabase db reset --local --no-seed` baseline has zero rows for its reserved
   fixture identities and every IA-5 occurrence/event/stream/allocator/key
   table.
2. Its controlling `psql` session may commit only the minimum non-Inventory
   setup visible to autonomous sessions: reserved test user, two companies and
   memberships, branches, items/UOM/warehouse masters, dormant policy bundles,
   WP-1 policy/rank/canonical/correction-version fixtures, and valuation scopes.
   It may not commit an `inventory_occurrences`, `inventory_events`, source-link,
   value, stream, allocator, or order-key row.
3. It opens two owner-only autonomous connections using the local connection
   parameters already supplied by the Supabase CLI environment. Each executes
   `BEGIN ISOLATION LEVEL SERIALIZABLE`; neither may run against hosted or a
   remote hostname.
4. Session A calls the exact fixture-context writer and retains the successful
   statement without committing. Session B asynchronously calls the byte-
   identical request. The controller proves B waits on the company/idempotency
   unique-index transaction dependency and that neither session holds a stream
   or allocator lock before the occurrence/idempotency decision.
5. Session A executes explicit `ROLLBACK`. It must never commit; an independent
   branch also proves `SET CONSTRAINTS
   inventory_events_ecc_order_key_totality_ct IMMEDIATE` raises
   `IA5-WP5-024`/`23514` before rollback.
6. After A rolls back, B must proceed as the new winner, return
   `duplicate=false`, create exactly one structurally complete event/key result
   visible inside B, and then execute explicit `ROLLBACK`. This proves an
   in-progress duplicate waits and a rolled-back failed attempt consumes no
   identity. It does **not** claim a committed production-winner path.
7. Exact accepted-success retry and contradictory-payload rejection remain
   single-transaction assertions in test `112`, where the first governed result
   is visible without committing certification data. The concurrency asset must
   not fabricate a committed certification success or weaken the trigger.
8. The controller disconnects both sessions, runs
   `supabase db reset --local --no-seed` immediately, then starts a fresh
   read-only proof transaction and asserts: all seven writer-target tables are
   empty; all reserved user/company/master/policy fixtures are absent; the
   `IA5_CERTIFICATION` registry row is still its persistent certified value;
   migration history and the WP-1…WP-5 object census match the pre-run baseline;
   and no audit row for either reserved actor/company remains.
9. Any setup, connection, wait-state, SQLSTATE, rollback, reset, or residue
   mismatch exits non-zero and invalidates all concurrency evidence. Cleanup DML
   is prohibited; the fresh local reset is the only cleanup authority.

The only permissible claim is rollback-winner idempotency serialization under
the owner-only certification contract. A committed-winner production claim is
deferred until a separately governed source is production-enabled and its own
integration evidence is authorised. No hosted evidence or source activation is
produced.

### 9.4 Evidence boundary

WP-5 tests may prove only: exact signature/security/object shape; writer and
resolver behavior; exact fourteen-component canonical encoding; digest; atomic stream/event/
key admission; current-key totality; idempotency; failure; tenant isolation; and
rollback/no residue. They may not claim production source activation,
Inventory readiness, module/engine certification, costing/FIFO/WAC/COGS,
Posting/GL/tax correctness, hosted parity or product readiness.

---

## 10. Trigger, totality and lifecycle contract

### 10.1 Exact trigger inventory

| Attribute | Governed value |
| --- | --- |
| Trigger | `inventory_events_ecc_order_key_totality_ct` |
| Trigger function | `public.fn_ia5_enforce_event_order_key_totality()` returning `trigger` |
| Target | `public.inventory_events` |
| Kind/timing | Constraint trigger, `AFTER INSERT`, row-level |
| Deferrability | `DEFERRABLE INITIALLY DEFERRED` |
| Enablement | `ENABLE ALWAYS` |
| Transition tables | None (not permitted/needed for this row constraint trigger) |
| `WHEN` | None |
| Function | `plpgsql`, `VOLATILE`, `PARALLEL UNSAFE`, `SECURITY DEFINER`, owner `postgres`, `search_path=public` |
| Direct execute | Revoked from `PUBLIC`, `anon`, `authenticated`, `service_role`; automatic trigger execution only |
| Writes | None |
| Failure | `23514`, `IA5-WP5-023` for totality/context; `IA5-WP5-024` for fixture constraint execution |
| Rollback owner | WP-5; trigger first, function second |

Every identifier is below 63 bytes (§15).

The trigger function's exact evaluation order is: (1) count same-company
`current` keys for `NEW.id` and require exactly one, otherwise
`IA5-WP5-023`; (2) load the exact registry row and reserved
`admission_context`; (3) for `certification_fixture`, require the exact disabled
certification row and then raise `IA5-WP5-024` so constraint execution/commit
cannot succeed; (4) for `production`, require a complete non-certification,
production-enabled row, otherwise `IA5-WP5-003`; (5) return `NEW`. It never
changes `NEW` or writes a table.

### 10.2 Totality invariant

Under the only contractually permitted future admission operation, at the
deferred transaction boundary:

- every inserted accepted `inventory_events` row has exactly one
  `inventory_event_order_keys` row with `resolution_state='current'`;
- that key has the same company and references the event and its resolved
  stream;
- no rejected occurrence, counterfactual-only event or otherwise prohibited
  event is inserted, therefore no such event may have a key;
- certification fixture events satisfy the same one-current-key structure
  before rollback, then are rejected from commit;
- duplicate current evidence remains independently rejected by WP-4's partial
  unique index; and
- only the admission writer may insert both the event and key. No other runtime
  writer, direct grant or bypass is authorised.

Intermediate state may be incomplete only between event insertion and key
insertion inside the same writer transaction. The trigger checks after all
statements at transaction end or explicit constraint execution. A production
commit with zero or more than one current key aborts. The trigger does not
create or repair a key.

All event effects admitted by WP-5 require chronology. There is no persisted
excluded event class. Rejected/counterfactual facts are excluded by not being
inserted, not by storing an unkeyed event.

### 10.3 Initial-resolution-only lifecycle

WP-5 owns **initial resolution only**:

- new admission generates a new event id and requires zero pre-existing
  `inventory_event_order_keys` rows of any state for that id;
- it inserts exactly one row with fixed `resolution_state='current'`;
- any pre-existing row is `IA5-WP5-026`/`23505` and aborts the whole occurrence;
- writer and resolver never update, delete, demote, supersede or replace a key;
- exact duplicate admission returns the same one current row and inserts
  nothing; a duplicate result containing any superseded/extra row is invalid
  stored evidence and fails `23514` rather than being repaired;
- policy-version, registry-version, scope-version, canonical-form-version,
  correction-graph-version and replay-driven re-resolution are unsupported;
- WP-5 creates no successor resolution row and exposes no supersession or
  re-resolution entry point; and
- transactional rollback removes only the new uncommitted admission effects.
  Persistent delete is never a rollback method.

Certified WP-4 continues to prove the 31-column storage shape, unconditional
canonical-identity uniqueness, partial one-current-per-event uniqueness, full
economic/version-column immutability, and the structural fact that its guard
permits only `current` → `superseded`. WP-5 initial-resolution evidence proves
only that a newly admitted event receives one immutable current row satisfying
that storage contract. It does **not** prove that the structural supersession
capability is executable as a valid successor lifecycle.

**Mandatory future stop:** before any version-only or other re-resolution,
successor-row procedure, automatic supersession, WP-7 capability that depends
on re-resolution, or Inventory production activation, a separately governed
WP-4 lifecycle amendment or later authorised work package must resolve
resolution-aware uniqueness. Executable WP-4 currently enforces unconditional
`UNIQUE (valuation_stream_id,canonical_key_bytes)`, so equal fourteen-component
bytes cannot coexist merely because their version vector differs. EA-010 does
not alter that constraint, any WP-4 migration, or WP-4 certification.

### 10.4 Existing-table and certified-test consequence

Only a future successful Authorisation Gate may authorise WP-5 to add this one
trigger to `inventory_events`. That is an existing-table metadata change and
takes a brief `ACCESS EXCLUSIVE` lock. The historical “nothing existing is
altered” premise remains true only for WP-1, WP-3 and WP-4; it is false for M5
and is replaced by this WP-5 boundary:

> Replace one owner-only writer and add one resolver, one trigger function and
> one deferred constraint trigger; alter no table column, stored row, policy,
> index, accounting behavior or runtime consumer.

Future implementation must update prior tests as follows:

- **test `103`: semantic fixture adaptation**, not a mechanical census only.
  Its 17 calls must use the new signature, exact payload/fingerprints and
  `certification_fixture`; its two signature/census references and named
  security-definer/function census must add resolver and trigger function; it
  must assert the fourth non-internal
  `inventory_events` trigger and exact deferred/ALWAYS metadata. Existing
  foundation assertions remain unchanged in meaning.
- **test `109`: semantic fixture adaptation.** Its two old-writer calls can no
  longer be followed by manual current-key insertion, because M5 supplies the
  key. The WP-4 structural/guard assertions must use direct owner-built parent
  events or consume the writer-created keys without attempting a duplicate.
- **tests `104`…`108` and `110`: no semantic change expected**, but rerun for
  bounded regression evidence.
- **tests `111`/`112`: UTC and initial-resolution evidence.** Run the same
  boundary instants under at least two distinct session timezones and require
  identical policy/version selection, stored `occurrence_date`, resolver bytes,
  digest, and guard result; prove `IA5-WP5-026` on any pre-existing key state.
- the ten `supabase/verification/ia5_*` assets that reference the old signature
  must be updated in their later authorised scope before they are executable;
  `ia5_rollback_boundary.sql` must name the new signature and exact restoration.
  Future `ia5_wp5_concurrent_idempotency.sql` owns only §9.3's reset-bounded
  two-session proof.

These future test edits do not occur in EA-008, EA-009, or EA-010. WP-1…WP-4 remain certified in
their bounded storage/control scopes, but WP-5 implementation cannot pass its
gate or certification without re-evidence of `103` and `104`…`110`.

---

## 11. Exact rollback contract

Rollback is owner-executed in one transaction and starts only when:

- no production source was activated;
- all WP-5-created occurrence/event/link/value/stream/allocator/key rows are
  absent (certification fixtures already rolled back);
- persistent counts of occurrences, events, streams, stream sequences and
  order keys are zero;
- no database runtime object depends on the new writer or resolver;
- all four WP-5 objects have the exact expected shape; and
- WP-1…WP-4 hashes/shapes/controls match their pre-M5 census.

If any condition fails, rollback stops before dropping anything. It is
structural-only; it never deletes business rows or backfills.

Before census or drop, rollback acquires
`LOCK TABLE public.inventory_events IN ACCESS EXCLUSIVE MODE`, then
`LOCK TABLE public.inventory_event_order_keys,
public.inventory_event_source_links, public.inventory_event_values,
public.inventory_occurrences, public.inventory_valuation_stream_sequences,
public.inventory_valuation_streams IN SHARE MODE`. This fixed order blocks every
writer insert/update while allowing read-only evidence. `DROP FUNCTION …
RESTRICT` then takes PostgreSQL's object lock on each exact signature; there is
no invented function-identity lock or advisory-lock protocol. Reverse order is:

1. drop trigger `inventory_events_ecc_order_key_totality_ct` from
   `public.inventory_events`;
2. drop `public.fn_ia5_enforce_event_order_key_totality()`;
3. drop `public.fn_ia5_ecc_resolve_components(uuid,integer,text,text,uuid,timestamptz,timestamptz,text)`;
4. drop the 14-argument
   `public.fn_ia5_record_dormant_inventory_occurrence(uuid,text,uuid,uuid,text,bigint,text,text,timestamptz,uuid,jsonb,integer,text,text)`;
5. recreate the exact 11-argument writer body from migration
   `20260726000013`, as `postgres`, `SECURITY DEFINER`,
   `search_path=public`, with no defaults and `RETURNS jsonb`;
6. restore its exact `REVOKE ALL` ACL for `PUBLIC`, `anon`, `authenticated`,
   `service_role` and its exact dormant-writer comment from migration `13`;
7. assert the new signatures, function/trigger comments and ACL rows are absent;
   assert the old signature/body/config/owner/ACL/comment are byte-/catalog-
   equivalent to the pre-M5 census;
8. assert `inventory_events` has exactly its three pre-M5 non-internal triggers
   (`aa_inventory_events_guard`, `trg_inventory_events_audit`,
   `zz_inventory_events_immutable`) with original enablement;
9. assert all WP-1…WP-4 objects, grants, policies, constraints, indexes, comments
   and row counts are unchanged; and
10. execute the proof inside test `113`, then final `ROLLBACK` so the M5-applied
    schema remains installed for later lifecycle steps.

No helper, policy, table, index, constraint, custom setting, coverage entry or
registry row exists to drop. Documentation-index and test registrations are
repository changes, not database rollback objects. Certification fixture
cleanup is transactional rollback, never cleanup DML. Local-only migration
status remains local; hosted rollback/deployment is outside WP-5.

---

## 12. Future test and evidence allocation

No test or verification asset is authored by EA-008, EA-009, or EA-010. Future
implementation owns exactly:

| Test ID/file | Families owned | Required fixture / persistence | Core assertions and SQLSTATE | Explicitly excluded |
| --- | --- | --- | --- | --- |
| `111_inventory_accounting_ia5_ecc_wp5_admission_contract_test.sql` | `WP5-ST-111` structural; `WP5-FX-111` fixture/encoding/date | Exact local owner fixture, one transaction, final rollback | 3 governed function signatures + 1 trigger; writer/resolver both pin UTC; 26-column resolver row; 139-column persistence map; exact payload rejection; fourteen-component golden bytes (including E2 = 0), no extra component/version frames, 32-byte digest; same instant under UTC and a non-UTC session yields identical selected versions, `occurrence_date`, bytes/digest and guard outcome; one event/one key/one stream; `22021`/`23514`; zero persistent rows | No production, costing, comparator, re-resolution, GL or engine claim |
| `112_inventory_accounting_ia5_ecc_wp5_totality_failure_security_test.sql` | `WP5-TOT-112`, `WP5-FAIL-112`, `WP5-SEC-112`, `WP5-IDEM-112` | Exact two-company **single-session** certification fixture; final rollback | success before rollback; exact retry returns prior result; contradictory same-key payload `23505`; zero/multiple key rejection `23514`/`23505`; pre-existing any-state key `IA5-WP5-026`/`23505`; production-disabled failure; fixture commit rejection; all §7 failures feasible in M5; direct-role `42501`; cross-company `23514`; UTC/non-UTC date-boundary attack equality | No multi-session claim, hosted, committed production winner, source activation or re-resolution claim |
| `113_inventory_accounting_ia5_ecc_wp5_rollback_test.sql` | `WP5-RB-113`, `WP5-RES-113` | M5-applied database; structural rollback inside transaction; final rollback | exact reverse object census; old writer restored; trigger set restored; WP-1…WP-4 unchanged; all fixture/audit/counter counts zero; no ACL/comment residue; failure precondition `23514` | Does not uninstall M5 persistently or certify it |
| `supabase/verification/ia5_wp5_concurrent_idempotency.sql` | `WP5-CONC-114` | Fresh local reset; only §9.3 non-Inventory setup committed; two serializable autonomous event transactions both roll back; immediate second reset and residue proof | B waits behind A on company/idempotency conflict; A rollback consumes no identity; B proceeds as new and rolls back; commit-reject branch `IA5-WP5-024`/`23514`; deterministic lock order; zero event/stream/key/audit/setup residue after reset | No committed certification event, exact-prior-success winner, production concurrency, hosted or source-activation claim |

Evidence classes:

- structural assertions are persistent M5 schema evidence;
- ordinary pgTAP business/version/event/key fixtures are certification-only and
  rolled back; only `WP5-CONC-114` may commit the exact non-Inventory setup in
  §9.3 and must erase it by immediate fresh local reset;
- totality failure uses deferred constraint execution inside a rolled-back
  transaction;
- security uses owner and `SET LOCAL ROLE` attacks, then rollback;
- rollback proof is structural inside a transaction and ends in rollback;
- residue proof occurs in a fresh follow-up transaction;
- regression census updates to `103` and `109` are part of the future WP-5
  implementation change; tests `104`…`110` all rerun;
- canonical accounting lane expectation: fresh DB plus focused `103`…`113`,
  then `WP5-CONC-114` in its isolated reset-bounded lane, another fresh reset,
  then the repository's canonical database lane only if the Authorisation Gate
  authorises implementation;
- documentation lane: `npm run docs:check` and `git diff --check`;
- all evidence is WP-5 bounded and cannot lift C-01, certify IA-5 permanent
  foundation, Inventory Engine or Inventory module.

---

## 13. Authoritative implementation-boundary table

| Object | Action / owner | Purpose | Reads / writes | Security and callable boundary | Rollback / test owner | Explicit exclusions |
| --- | --- | --- | --- | --- | --- | --- |
| 14-arg `fn_ia5_record_dormant_inventory_occurrence` | Replace / `postgres` | Atomic source admission and **initial** accepted occurrence/event/stream/key resolution | Reads §3.6; applies all 139 §3.8 column mappings; updates only stream allocator | Definer; owner only; no current runtime; fixture owner-callable | Drop, restore old 11-arg body / `111`,`112`,`113`,`WP5-CONC-114` | No re-resolution, successor, supersession, costing, projection, Posting, GL, tax, activation |
| `fn_ia5_ecc_resolve_components` | Create / `postgres` | Resolve and encode all fourteen current admission chronology values, with E2 fixed to governed base-source depth 0 | Exact §5.2 allowlist; no writes | Definer; writer-only runtime; owner fixture direct call only | Drop / `111`,`112`,`113` | No causal graph traversal, cost, quantity valuation, comparator, replay or journal |
| `fn_ia5_enforce_event_order_key_totality` | Create / `postgres` | Deferred event-side exactly-one-current and fixture commit rejection | Reads `public.inventory_event_order_keys` and `public.ref_inventory_event_source_types`; `NEW` supplies the event; no writes | Definer trigger execution only; direct execution revoked | Drop after trigger / `112`,`113` | No key repair, supersession or runtime activation |
| `inventory_events_ecc_order_key_totality_ct` | Create on existing table / managed by `public.inventory_events` owner `postgres`; PostgreSQL gives triggers no separate owner | Arm totality after insertion | Fires on event; no direct table read/write of its own | ALWAYS, deferred constraint trigger | Drop first / `103`,`112`,`113` | No column/constraint/index/policy change |
| Existing WP-1…WP-4 objects | Preserve | Dependencies and controls | Read only, except certified stream allocator/key inserts through writer | Existing ACL/RLS/guards unchanged | Census / `103`…`113`,`WP5-CONC-114` | No reopening of certified scope; WP-4 structural supersession is not a WP-5 lifecycle |

The complete explicit exclusions are: costing; valuation calculation; FIFO;
Moving WAC; Specific-ID method state; cost layers; COGS; Inventory journal
generation; Posting Engine change beyond future test census; General Ledger;
tax; Sales; Purchasing; UI; routes; reports; hosted deployment; source-type
production activation; WP-6…WP-9; and IA-6.

---

## 14. Future migration preconditions and postconditions

### 14.1 Fail-closed preconditions

The future migration first takes the same fixed table-lock sequence as §11 and
then checks, before mutation:

1. WP-1 six tables exist with certified columns/constraints/RLS/grants/triggers,
   remain empty, and the exact certification fixture authority is constructible.
2. WP-2 six registry columns/constraints exist; exactly one persistent row is
   `IA5_CERTIFICATION` with the exact WP-2 values, certification-only=true,
   production-enabled=false, removal phase IA-6.
3. WP-3 tables and guard exist with exact shapes/controls and zero rows.
4. WP-4 31-column table, 24 keys/constraints, four explicit indexes, two
   triggers, guard, RLS/policy/grants exist and the table is empty.
5. The exact current 11-argument writer exists as `postgres`, definer,
   `search_path=public`, no defaults, current ACL/comment/body; no stored database
   caller depends on it.
6. `inventory_events` exists, has zero rows, has exactly its three certified
   non-internal triggers, and no totality trigger.
7. `inventory_occurrences`, both stream tables, order keys and all six WP-1
   tables have zero rows; legacy scope allocator also has zero IA-5 fixture rows.
8. No resolver, trigger function, 14-argument writer or WP-5 trigger exists.
9. No `fn_ia5_ecc_population`, ordered-input-fingerprint function,
   replacement ECC index, replay/boundary object, future WP-6+ consumer, IA-6
   method-state object or runtime consumer exists.
10. Expected table RLS, policies, grants and guard enablement match the certified
    census; client/service write/execute count remains zero. The exact
    `extensions.digest(bytea,text)` pgcrypto signature is present and executable
    by the function owner; no unqualified digest function is accepted.
11. ADR-C01 is still frozen at repository SHA-256
    `81dfe547905626f3e45fb2b59245d6953fbe79bfb8b23ad99202656a562fc5bf`;
    ECC-01 owner acceptance is still current at SHA-256
    `af017823e70858343ccb6f70670899f51af5e8ffe848a47c27636213ebff158c`.
    The implementation boundary also records the gate-reviewed EA-010 spec and
    amended-design hashes. A migration cannot read documentation hashes, so the
    Authorisation Gate records them before implementation.
12. Hosted state is neither queried nor assumed.
13. The certified `fn_ia5_guard_inventory_event_fact()` definition still uses
    its existing `NEW.effective_at::date` checks and is otherwise byte-/catalog-
    equivalent to the pre-M5 census; no alternate event writer exists. This is
    required because the writer's function-local UTC setting is the bounded
    compatibility mechanism in §3.2.

Any failure raises `23514` with an M5 stop-condition message before the first
DDL statement. It authorises no repair, backfill, trigger disablement, object
drop, source enablement or inference.

### 14.2 Exact postconditions

After future M5 implementation:

- exactly 12 `public.fn_ia5_*` signatures exist (10 pre-M5, plus resolver and
  trigger function; the writer replacement does not increase the count);
- exactly 10 of them are `SECURITY DEFINER` (the two existing immutable numeric
  helpers remain invoker/immutable); all new/definer functions pin
  `search_path=public`, and the writer/resolver additionally pin
  `TimeZone=UTC`;
- old 11-argument writer count = 0; exact new 14-argument writer count = 1;
- resolver count = 1; trigger-function count = 1;
- `inventory_events` has exactly four non-internal triggers: its three certified
  triggers plus the one §10 constraint trigger with exact timing,
  deferrability and ALWAYS enablement;
- no new table, column, table constraint, index, RLS policy or grant exists;
- direct execute on all three WP-5 functions for
  `PUBLIC`/`anon`/`authenticated`/`service_role` = false;
- persistent occurrence/event/stream/allocator/order-key row counts remain zero
  immediately after migration; WP-1 tables remain empty;
- exact registry row remains certification-only and production-disabled;
- runtime consumer count remains zero;
- certification fixture context exists only as the owner-only function
  argument and commit-rejecting trigger behavior; no flag/GUC/wrapper/table;
- rollback test `113` can restore exact pre-M5 catalog state inside a transaction;
- tests `111`…`113` and verification asset `WP5-CONC-114` are registered;
  `103`/`109` are reconciled; no new table coverage entry exists;
- every newly admitted event has one and only one total order-key row, fixed
  `current`; no re-resolution/successor/supersession implementation exists;
- no WP-6+, IA-6, cost, valuation, Posting, journal, tax, route, UI, report,
  hosted or production-activation change exists.

---

## 15. Identifier safety

ASCII byte counts, rechecked for PostgreSQL's 63-byte limit:

| Identifier | Bytes |
| --- | ---: |
| `inventory_events_ecc_order_key_totality_ct` | 42 |
| `fn_ia5_enforce_event_order_key_totality` | 39 |
| `fn_ia5_record_dormant_inventory_occurrence` | 42 |
| `fn_ia5_ecc_resolve_components` | 29 |

No identifier truncation or collision is permitted. Future implementation must
recompute `octet_length` for every chosen label; it may not repeat the WP-2
64-byte specification defect or the WP-3 byte-count documentation error.

---

## 16. Accounting and product-value boundary

In accounting language, WP-5 answers one question:

> When a dormant Inventory event is accepted, what permanent evidence proves
> the exact economic sequence inputs that accounting must later use?

It records source identity, economic time, governed ranks, line/occurrence/event
ordinals, correction sentinels, version references, canonical bytes and digest.
It preserves accepted arrival sequence separately and proves that schedule-
dependent allocation is not economic order.

WP-5 does **not** answer what an item costs, which layer is consumed, what WAC
or COGS is, what journal entry posts, which account is debited or credited, what
tax applies, or whether Inventory is production-ready. No functional
Inventory-to-GL value exists until later authorised costing, Posting,
reconciliation and workflow work passes the Product Definition of Done.

After a successful separate WP-5 Authorisation Gate, implementation may begin
only inside this contract. After later WP-5 implementation/audit/certification,
the Product Execution Roadmap's value checkpoint still decides whether further
dormant Inventory packages should proceed ahead of the more urgent canonical
Sales/Purchasing, Receiving accounting, Tax ownership, opening-balance and
backup/restore gaps.

---

## 17. EA-009/EA-010 reproducible protected-boundary proof

### 17.1 Fixed protected set

EA-009 established, and EA-010 reuses unchanged, the protected executable and
authority set. The set is enumerated from the filesystem, never from
`git status`:

- every regular file under `supabase/migrations/`;
- every `*.sql` regular file under `supabase/tests/`;
- every regular file under `src/` and `scripts/`;
- Product Architecture and Product Execution Roadmap;
- ADR-C01 and ECC-01;
- the WP-1 authorisation record, all three WP-2 issued records, and the
  certified WP-2, WP-3 and WP-4 detailed specifications; and
- the Posting Engine, Posting P3 and Accounting Rules authorities.

The EA-009/EA-010 files legitimately amended—this specification, the IA-5 programme
design, certification dashboard, documentation index and current AI status/
handoff files—are intentionally excluded. `AI_LAST_SESSION.md` is explicitly
excluded. `supabase/.temp`, `node_modules`, `.git` and build output outside the
enumerated roots are excluded. An untracked or generated regular file **inside**
an enumerated protected root is included automatically; Git status cannot hide
it. A missing explicit file or root is a hard failure.

Canonical execution is the repository's Linux/GNU-coreutils environment.
Relative filenames are assumed to be valid UTF-8 and to contain no newline;
spaces are supported. `LC_ALL=C` supplies byte-order sorting. The path manifest
is newline-delimited, the content manifest is the exact GNU `sha256sum` output
`<64 lowercase hex><two spaces><relative path><LF>` for each sorted path, and
the aggregate is SHA-256 of that complete content-manifest byte stream. No
absolute path, temporary filename or timestamp enters either hash. Another OS
must run the documented Linux container/CI image; substituting BSD `shasum` is
not a canonical comparison unless it reproduces the exact manifest format.

### 17.2 Exact reproduction command

Run from repository root:

```bash
set -euo pipefail
proof_dir=$(mktemp -d)
paths_file="$proof_dir/protected-paths.txt"
manifest_file="$proof_dir/protected-manifest.sha256"

for protected_root in supabase/migrations supabase/tests src scripts; do
  test -d "$protected_root" || { printf 'MISSING ROOT %s\n' "$protected_root" >&2; exit 1; }
done

{
  find supabase/migrations -type f -print
  find supabase/tests -type f -name '*.sql' -print
  find src -type f -print
  find scripts -type f -print
  printf '%s\n' \
    'docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md' \
    'docs/PXL/01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md' \
    'docs/PXL/07. Inventory/03. Architecture/ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md' \
    'docs/PXL/07. Inventory/03. Architecture/ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md' \
    'docs/PXL/07. Inventory/04. Implementation/ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md' \
    'docs/PXL/07. Inventory/04. Implementation/IA-5_ECC_HARDENING_WP-2_AUTHORISATION_REPORT.md' \
    'docs/PXL/07. Inventory/04. Implementation/IA-5_ECC_HARDENING_WP-2_EVIDENCE_GATE_REPORT.md' \
    'docs/PXL/07. Inventory/04. Implementation/IA-5_ECC_HARDENING_WP-2_IMPLEMENTATION_AND_EVIDENCE_REPORT.md' \
    'docs/PXL/07. Inventory/04. Implementation/IA-5_WP-2_DETAILED_REGISTRY_AUTHORITY_SPECIFICATION.md' \
    'docs/PXL/07. Inventory/04. Implementation/IA-5_WP-3_DETAILED_STREAM_AND_ALLOCATOR_SPECIFICATION.md' \
    'docs/PXL/07. Inventory/04. Implementation/IA-5_WP-4_DETAILED_ORDER_KEY_SPECIFICATION.md' \
    'docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_SPEC.md' \
    'docs/PXL/02. Accounting Core/PXL_POSTING_ENGINE_P3_SPEC.md' \
    'docs/PXL/02. Accounting Core/PXL_ACCOUNTING_RULES.md'
} | LC_ALL=C sort -u > "$paths_file"

while IFS= read -r file; do
  test -f "$file" || { printf 'MISSING %s\n' "$file" >&2; exit 1; }
  sha256sum -- "$file"
done < "$paths_file" > "$manifest_file"

printf 'ENTRY_COUNT %s\n' "$(wc -l < "$paths_file" | tr -d ' ')"
printf 'PATH_MANIFEST_SHA256 %s\n' "$(sha256sum "$paths_file" | awk '{print $1}')"
printf 'PROTECTED_AGGREGATE_SHA256 %s\n' "$(sha256sum "$manifest_file" | awk '{print $1}')"
rm -r "$proof_dir"
```

EA-009 and EA-010 mission-start evidence is **527 entries**, path-manifest SHA-256
`168c3ef5391c26f8ee5472b09c72a96b1089cb9dd2930502b65188645b99f508`,
and protected aggregate SHA-256
`8ddf66f36c63606f8eb0bceaacfe3f3131337758b895fc557ec488ca383d7ba6`.
Each mission-end run must reproduce all three values exactly; the permanent
handoff records the independent rerun and equality result. Redefining the set
after an edit is prohibited.

## 18. Governance quality challenge and decision

EA-010 attempted a line-by-line implementation against the entire specification,
not only the four cited paragraphs. The following ambiguity register records
every candidate that could affect data, chronology, security, failure atomicity,
rollback or evidence.

| Candidate ambiguity | Disposition | Controlling rule |
| --- | --- | --- |
| Version-only successor collides with WP-4 canonical identity | **Resolved for WP-5** by initial-resolution-only scope; **future governed stop** before any re-resolution | §§3.5, 10.3, 19.1 |
| Which old writer columns/defaults/text rules survive | **Resolved** by 139-column census and disposition matrix | §3.8 |
| Caller session timezone changes policy date/guard result | **Resolved** by function-local UTC and explicit UTC dates | §§3.2, 5.1, 5.3, 19.3 |
| Autonomous sessions cannot see rolled-back setup | **Resolved** by isolated reset-bounded `WP5-CONC-114` | §§9.3, 12, 19.4 |
| Exact duplicate result with historical/superseded key | **Resolved**: invalid stored evidence, `23514`, no repair | §§3.5, 10.3 |
| Non-base E2/correction derivation | **Resolved fail-closed**, `0A000`; separate future source/resolver authority | §§5.3, 7 |
| `governed_business_sequence` representation | **Resolved fail-closed**, `0A000`; no eligible source uses it | §§5.3, 6.3 |
| Committed-winner concurrency under disabled certification source | **Not a WP-5 certification claim**; future production-source integration evidence | §§9.3, 12 |
| Existing event guard still casts `timestamptz::date` | **Resolved without guard amendment**: it executes inside writer's UTC function configuration; alternate writers prohibited | §§3.2, 14 |
| IDs and audit clocks could enter chronology | **False positive**: every occurrence is mapped and explicitly excluded from ECC | §§3.8, 6.4 |
| Trigger could repair missing keys | **False positive**: read-only and fail-closed | §10 |
| Certification setup can leak to hosted/production | **Resolved** by local-host check, owner-only calls, reset boundary and prohibited claims | §9 |
| Rollback might remove business rows | **Resolved**: zero-row precondition, structural reverse order only | §11 |
| WP-6+, IA-6, Posting, costing or source activation could be inferred | **Resolved** by object/write allowlists and explicit exclusions | §§1, 3.6, 13, 16 |

Object names/counts, signatures, argument/default/return contracts, 139 stored
columns, payload keys, fourteen-component encoding/byte order/digest, version
references, privileges, trigger metadata, 26 SQLSTATE failures, initial-only
lifecycle, fixture contexts, one writer sequence, locks, idempotency,
concurrency, rollback, future evidence, pre/postconditions and protected
boundaries are now fixed. No unresolved EA-010 decision requires the Product
Owner, ADR-C01 owner, ECC-01 owner or a current WP-4 amendment. The mandatory
future WP-4 lifecycle stop is an explicit exclusion, not hidden authority.

**Decision:** `EA-010 COMPLETE — READY FOR WP-5 AUTHORISATION GATE RE-RUN`.

This is a specification-readiness decision only. It is not the Authorisation
Gate. WP-5 remains unauthorised and unimplemented.

## 19. Engineering Amendment EA-010 closure

### 19.1 Resolution of WP5-AGR2-001

- **Confirmed defect and sources:** ECC-01 §3.3/V-35, design §§6.3/15,
  certified WP-4 §§2–3 and executable migration `20260731000019` collectively
  permit historical state but do not provide resolution-aware canonical
  uniqueness. EA-009's prospective successor paragraph was therefore
  unexecutable for unchanged comparator bytes.
- **Controlling corrected rule:** WP-5 inserts an order key only for a newly
  generated event with no prior key row. Existing resolution of any state is
  `IA5-WP5-026`/`23505`. No update, demotion, successor or re-resolution occurs.
- **Implementation/rollback boundary:** the same four WP-5 objects remain; no
  WP-4 object changes. Rollback removes only new WP-5 objects and restores the
  old writer.
- **Evidence owner:** `111` proves one initial current row; `112` proves `026`,
  duplicate return and no supersession; `113` proves WP-4 unchanged.
- **Higher-authority preservation:** WP-4 still proves its issued structural
  lifecycle; ECC-01 still requires a future governed re-resolution remedy. EA-010
  merely refuses to claim that future procedure in WP-5.
- **Objective closure:** repository-wide WP-5 statements must classify
  re-resolution as prohibited/future, and no WP-5 algorithm may write
  `superseded` or a successor row.

Repository-wide terminology census disposition:

| Match group | Classification |
| --- | --- |
| ECC-01 and its acceptance report | **Future governed work** — the required higher-authority semantics remain; no executable WP-5 procedure is implied |
| Certified WP-4 specification, migration `20260731000019`, and test `109` | **WP-4 structural capability** — state column/guard/retention evidence only; unconditional canonical uniqueness remains |
| WP-3 specification references | **Future governed work** — explicitly names re-resolution as a later forward path, outside WP-3/WP-5 authority |
| IA-5 programme design §§6.3/15/23/25/28 | **Future governed work** after EA-010's explicit uniqueness stop; its §§31–36 matches are **historical** chronology |
| This specification §§13–19 | **Prohibited in WP-5** or **future governed work** as explicitly labelled; its EA-008/EA-009 ledger matches are **historical** |
| Other Inventory architecture/blueprint documents and IA-5 evidence reports | **Future governed work** or **historical** evidence; none is the current M5 executable authority |
| Current AI/dashboard/index references | **Prohibited in WP-5 / future governed work**; they route to this specification |
| Non-Inventory Accounting, Approval, Sales, Reporting, Compliance migration/test matches using the generic word `superseded` | **Historical/domain-local lifecycle terminology**, unrelated to Inventory order-key resolution and not a conflicting WP-5 authority |
| Archive and trash-review matches | **Historical** and non-authoritative |

No conflicting current WP-5 authority remains. The census intentionally does
not rewrite ECC-01, certified WP-4, unrelated domain lifecycles, or archived
history merely because they use the same English word.

### 19.2 Resolution of WP5-AGR2-002

- **Confirmed defect and sources:** migration `20260726000013`, WP-3 migration
  `20260730000018`, and WP-4 migration `20260731000019` contain 139 written-table
  columns whose complete construction was absent from EA-009.
- **Controlling corrected rule:** §3.8 governs every column, exact source,
  default/null, normalization, validation/failure, mutability, audit meaning,
  and preserved/modified/removed behavior. §3.5 step 11 points only to that map.
- **Implementation/rollback boundary:** no new argument, table, column or object
  was added. The 14-argument signature and seven-table write allowlist remain.
- **Evidence owner:** `111` owns column/source/default and normalized storage
  assertions; `112` owns missing/invalid mapping failures and idempotent return;
  `113` owns restoration and residue.
- **Higher-authority preservation:** the map adopts executable certified table
  shapes without modifying them and explicitly identifies the few WP-5 writer
  behavior changes.
- **Objective closure:** a future writer can be implemented from §§3–6 without
  consulting the old function to choose business behavior.

### 19.3 Resolution of WP5-AGR2-003

- **Confirmed defect and sources:** EA-009 resolver rule `E1::date`, current
  writer `p_occurred_at::date`, and preserved guard
  `NEW.effective_at::date` inherited caller/session timezone.
- **Controlling corrected rule:** writer and resolver have exact function
  configuration `SET TimeZone='UTC'`; `economic_date` and `occurrence_date` use
  explicit `AT TIME ZONE 'UTC'` expressions; all policy/version range checks use
  the former. The guard sees UTC because it runs during the writer call.
- **Implementation boundary:** only the future replacement writer and new
  resolver definitions receive the UTC configuration. The certified guard,
  migrations, tables and policies remain unchanged. No other event writer is
  authorised.
- **Failure behavior:** missing/invalid timestamp remains `010`/`22023`;
  canonical conversion failure is `014`/`22021`; out-of-period/mismatched
  authority is `23514`; the whole occurrence rolls back.
- **Rollback consequence:** dropping those two WP-5 definitions removes the UTC
  configuration; restoring the exact old writer restores its original config.
- **Evidence owner:** `111` and `112` execute a UTC-midnight boundary instant
  under at least UTC and one non-UTC session and require identical stored date,
  policy versions, guard result, bytes and digest.
- **Higher-authority preservation:** UTC is ECC-01 N-01's existing authority;
  this amendment supplies its missing PostgreSQL representation and changes no
  accounting policy.
- **Objective closure:** catalog `proconfig` and two-timezone result equality
  must both pass.

### 19.4 Resolution of WP5-AGR2-004

- **Confirmed defect and sources:** an all-rollback pgTAP fixture cannot be
  observed by independent sessions; current
  `supabase/verification/ia5_concurrent_idempotency.sql` documents and implements
  the necessary local committed-setup/reset precedent.
- **Controlling corrected rule:** ordinary fixtures remain rolled back.
  Multi-session proof belongs only to future `WP5-CONC-114` under §9.3: commit
  the minimum non-Inventory local setup, roll back or commit-reject every event
  transaction, reset immediately, and prove full residue absence.
- **Implementation boundary:** the future asset is evidence-only and
  non-runtime; it creates no database object, grant, source enablement or hosted
  path. EA-010 creates no SQL/test asset.
- **Failure behavior:** wrong host/baseline, inability to observe the wait,
  unexpected commit, SQLSTATE mismatch, reset failure or any residue exits
  non-zero and invalidates the evidence.
- **Rollback consequence:** event transactions explicitly roll back; local reset
  is mandatory cleanup for the deliberately committed setup. Cleanup DML is
  prohibited.
- **Evidence owner:** `WP5-CONC-114`; test `112` retains exact retry and
  contradictory-payload semantics without a multi-session claim.
- **Higher-authority preservation:** ECC-01 V-10 and the certification-only,
  production-disabled registry row are unchanged. No hosted or production
  concurrency claim is made.
- **Objective closure:** the future asset must be independently executable from
  fresh reset through second reset and residue proof without relying on
  uncommitted cross-session fixture visibility.
