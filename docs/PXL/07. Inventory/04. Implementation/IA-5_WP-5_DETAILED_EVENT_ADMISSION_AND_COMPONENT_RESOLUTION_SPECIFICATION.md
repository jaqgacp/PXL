# IA-5 WP-5 — Detailed Event Admission and Component Resolution Specification

**Status:** ENGINEERING AMENDMENT EA-008 COMPLETE — ready for a separate WP-5 Authorisation Gate re-run; WP-5 remains unauthorised and unimplemented
**Authority:** Tier 2 Engineering Specification subordinate to the Product Architecture, ADR-C01, ECC-01, and the accepted IA-5 ECC Hardening programme design
**Owner / Domain:** Inventory Accounting / IA-5 ECC Hardening
**Applies To:** WP-5/M5 event admission and admission-time ECC component resolution only
**Read When:** Re-running the WP-5 Authorisation Gate or, only after a successful gate, implementing/auditing/certifying WP-5
**Do Not Read For:** Costing, valuation, FIFO, Moving WAC, COGS, Posting, General Ledger, tax, UI, production activation, WP-6…WP-9, or IA-6
**Date:** 2026-08-01

---

## Engineering Amendment EA-008 — Findings and authority

EA-008 closes only the three findings recorded by the 2026-07-31 WP-5
Authorisation Gate:

| Finding | Resolution in this specification |
| --- | --- |
| `WP5-AG-001` | Exact current and replacement writer signatures, payload schema, resolver signature and output, canonical encoding, failures, security, transaction sequence, idempotency, locks and postconditions are fixed in §§2–8. |
| `WP5-AG-002` | Production admission and the owner-only, rolled-back, commit-rejecting `IA5_CERTIFICATION` fixture path are separated in §9 without weakening ECC-01 V-10 or enabling a source. |
| `WP5-AG-003` | The trigger function and trigger are counted separately, totality/current/superseded rules are fixed, test `103`/`109` consequences are explicit, and reverse-order rollback is complete in §§10–12. |

Authority order is:

1. [`PXL_PRODUCT_ARCHITECTURE.md`](../../01.%20Architecture/PXL_PRODUCT_ARCHITECTURE.md) — product scope and engine/module ownership;
2. [`ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md`](../03.%20Architecture/ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md) — frozen dual-chronology decision;
3. [`ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md`](../03.%20Architecture/ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md) — accepted derivation, validation, normalization and failure authority;
4. [`IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md`](IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md) — programme and work-package sequence, as amended by EA-008;
5. certified WP-1 through WP-4 specifications — storage and dormant-foundation contracts; and
6. this document — the exact M5 representation and executable boundary.

This specification does not amend product scope, ADR-C01, or ECC-01. It does
not reopen a certified WP-1…WP-4 object. Where historical M4 prose called
`canonical_key_bytes` a serialization of all fourteen comparator components,
EA-008 corrects the prospective M5 production rule: E2 is population-derived at
ordering time and cannot exist at admission, so the persisted admission bytes
contain the version vector and thirteen admission-resolved components. The
later comparator still
uses all fourteen components in the exact ADR-C01/ECC-01 order. WP-4 certified
storage shape and structural evidence did not certify an absent resolver or an
encoding algorithm, so its bounded certification remains valid.

**Governance decision:** EA-008 grants no implementation, audit,
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
- future test files: `111`, `112`, and `113` allocated in §12; no test is
  created or changed by EA-008.

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
| `p_source_document_type text` | Immutable registered source type | Required exact registry key; participates in E4/E10 and version vector; no trimming/case-folding |
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
- search path: exactly `public`;
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

A supplied fingerprint that differs aborts before persistent insertion. This
prevents a caller from reusing one key while changing chronology inputs. The
stored fingerprint remains the existing 64-character text field.

### 3.5 Exact transaction sequence

No step is implementation discretion:

1. Validate all non-null scalar arguments, exact context token, JSON array
   shape, exact payload keys, event-plan contiguity, request fingerprint and
   actor membership.
2. Read and validate the exact registry row. For `production`, apply V-10 and
   the fail-closed source-adapter rule in §9.2. For `certification_fixture`,
   require the exact `IA5_CERTIFICATION` row in §9.3.
3. Resolve the existing occurrence by `(company_id,idempotency_key)`. If found,
   lock it `FOR UPDATE`, compare all immutable request identity/fingerprint and
   stored context, require exactly one current key per event, and return the
   duplicate result. Do not insert, allocate, supersede or repair.
4. Generate the occurrence id and event ids. These UUIDs are storage handles
   only and never E5/E10 inputs.
5. Insert the accepted `inventory_occurrences` row using the existing dormant,
   zero-projection, zero-Posting contract. If a concurrent insert wins the
   idempotency unique key, read that winner `FOR UPDATE`, perform step 3, and
   return or fail.
6. For each event in array order, resolve its existing valuation scope and its
   profile/formula/precision dependencies at E1. Reject company, item, effective
   period, UOM, quantity, direction, evidence or plan mismatch.
7. Resolve or create exactly one dormant `inventory_valuation_streams` row by
   `(company_id,item_id,scope_code)`. Insert uses `ON CONFLICT DO NOTHING`, then
   reads the one immutable row and verifies company/item/scope identity.
8. Insert the stream's allocator row if absent, then increment
   `inventory_valuation_stream_sequences.last_sequence` with one atomic
   `UPDATE … RETURNING`. That row lock linearizes **Accepted Event Chronology
   only**. Store the returned value in the existing
   `inventory_events.scope_sequence`. Do not read or update
   `inventory_valuation_scope_sequences`.
9. Construct reserved audit evidence (§4.3), validate its fingerprint, and
   insert one `inventory_events` row plus one primary
   `inventory_event_source_links` row. Insert the optional caller-authoritative
   `inventory_event_values` row under the existing fixed-point contract. No
   value is calculated by the resolver.
10. Call `fn_ia5_ecc_resolve_components` exactly once for that event. It must
    return exactly one row. Recompute and compare its digest, then insert one
    `inventory_event_order_keys` row with `resolution_state='current'`.
11. After all events, query the occurrence's events and current keys in
    `event_sequence` order. Require cardinalities equal the event count and
    return §3.3. The deferred trigger independently rechecks event-side
    totality at its governed boundary.
12. The caller may commit only production admission that passes every deferred
    constraint. Certification fixtures must execute assertions and `ROLLBACK`;
    any attempted commit fails closed.

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
- row locks are limited to the existing idempotency winner and the accepted
  stream allocator; no lock result enters ECC;
- stream identity uses its unique key, not insertion order;
- policy, registry, scope and source evidence are read under the caller's one
  transaction snapshot; immutable guards prevent concurrent rewrite;
- two distinct schedules for the same complete authoritative command set must
  produce identical component bytes/digests, while accepted `scope_sequence`
  may differ;
- one event failure aborts the whole occurrence; no partial event plan,
  allocator advance, audit row, key or value may survive that statement;
- retry after a failed statement is safe after the governed cause is fixed;
- no exception handler may convert a component, totality, cross-company or
  digest failure into an accepted result.

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
| `source_precision_code` | string | Required | exact `microsecond` in WP-5 | persisted with E1; canonical |
| `economic_effect_class` | string | Required | caller assertion; must equal exact registry mapping and quantity direction | E3 class; retained in key |
| `accounting_date` | string or null | Optional, default null | exact `YYYY-MM-DD` if present | retained event fact; not ECC |
| `item_id` | string | Required | lowercase UUID; same company and scope | partition/stream selection, not tuple |
| `valuation_scope_id` | string | Required | lowercase UUID; exact company/item/effective scope version | `V` scope version; not tuple |
| `physical_warehouse_id` | string or null | Optional, default null | lowercase UUID and same company when present | retained; not ECC |
| `physical_location_id` | string or null | Optional, default null | lowercase UUID and governed warehouse/company when present | retained; not ECC |
| `lot_number` | string or null | Optional, default null | NFC; non-empty after trim; WP-5 adds no length cap absent a current table constraint | retained; not ECC |
| `serial_number` | string or null | Optional, default null | NFC; non-empty after trim; WP-5 adds no length cap absent a current table constraint | retained; not ECC |
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
| `reason_code` | string | Required | NFC and non-empty; certification fixture uses exact `IA5_CERTIFICATION`; WP-5 adds no narrower table domain | audit, not tuple |
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
| `value_role` | string | Required, NFC and non-empty; certification fixture uses exact `inventory_value`; no new table domain |
| `authoritative_transaction_amount` | string | Required; signed fixed-point, exactly 8 decimals |
| `authoritative_functional_amount` | string | Required; signed fixed-point, exactly 8 decimals |
| `gl_basis_amount` | string | Required; signed fixed-point, exactly 8 decimals |
| `derived_unit_rate` | string or null | Optional, default null; signed fixed-point, exactly 12 decimals |
| `exchange_rate_identity` | string or null | Optional, default null; required by existing currency rule when currencies differ |
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

It returns a `TABLE` with exactly one row and these columns in this order:

| # | Output | PostgreSQL type | Null? |
| ---: | --- | --- | --- |
| 1 | `valuation_stream_id` | `uuid` | No |
| 2 | `economic_effective_at` | `timestamptz` | No |
| 3 | `source_precision_code` | `text` | No |
| 4 | `economic_effect_class` | `text` | No |
| 5 | `economic_effect_rank` | `smallint` | No |
| 6 | `source_type_rank` | `smallint` | No |
| 7 | `document_order_key` | `bytea` | No |
| 8 | `source_line_ordinal` | `integer` | No |
| 9 | `transition_rank` | `smallint` | No |
| 10 | `occurrence_ordinal` | `bigint` | No |
| 11 | `event_ordinal` | `integer` | No |
| 12 | `canonical_source_identity` | `bytea` | No |
| 13 | `correction_placement_class` | `text` | No |
| 14 | `correction_chain_depth` | `integer` | No |
| 15 | `correction_effective_at` | `timestamptz` | No |
| 16 | `correction_approved_at` | `timestamptz` | No |
| 17 | `correction_identity` | `bytea` | No |
| 18 | `correction_root_event_id` | `uuid` | Yes only when depth is 0 |
| 19 | `order_policy_version_id` | `uuid` | No |
| 20 | `registry_source_document_type` | `text` | No |
| 21 | `canonical_form_version_id` | `uuid` | No |
| 22 | `scope_resolution_version_id` | `uuid` | No |
| 23 | `correction_graph_version_id` | `uuid` | No |
| 24 | `canonical_key_bytes` | `bytea` | No |
| 25 | `ecc_key_digest` | `bytea` | No; exactly 32 bytes |

Properties: `plpgsql`, `VOLATILE`, `PARALLEL UNSAFE`, `SECURITY DEFINER`, owner
`postgres`, `SET search_path = public`, and no direct execution grant to
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
   with the same company and exact class/type/transition.
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
9. For current `IA5_CERTIFICATION`, registry placement is `base`: correction
   inputs and ancestry correction ids must be null; X1 = 0, X2/X3 = PostgreSQL
   `-infinity`, X4 = zero-length bytea, root = null. Any correction is
   `0A000` under the current row. A future separately authorised source rule may
   use the already accepted ECC-01 classes only after its source adapter and
   correction evidence are specified; WP-5 adds no such row.
10. Build §6 bytes, compute digest, return. Do not insert the key.

The resolver does not calculate cost, quantity valuation, FIFO layers, WAC,
COGS, journal lines, posting instructions, tax or financial-statement effects.

---

## 6. Canonical encoding and digest

### 6.1 Canonical-form authority marker

The resolved `inventory_canonical_form_versions.encoding_rules` must equal this
JSON object exactly; unknown or missing keys fail:

`{"component_framing":"TAG_U8_LENGTH_U32_BE","digest":"sha256","ecc_admission_encoding":"PXL_ECC_ADMISSION_K1","integer_encoding":"TWOS_COMPLEMENT_BIG_ENDIAN","text_normalization":"NFC","timestamp_encoding":"UTC_MICROSECOND_TEXT","uuid_encoding":"RFC4122_16_BYTE"}`

The certification fixture inserts that object explicitly. The table default
`{}` is structural only and is not an executable encoding authority.

### 6.2 Framing rules

- byte order: network/big-endian for every integer and length;
- document header: UTF-8 ASCII bytes `PXL-ECC-ADMISSION-K1`, followed by one
  zero byte;
- immediately after the header, the resolved version vector is serialized in
  this exact order using the same framing: tag byte `0xF1` order-policy UUID
  (16 bytes); `0xF2` registry source-document type (NFC UTF-8); `0xF3`
  canonical-form UUID (16 bytes); `0xF4` scope-resolution UUID (16 bytes);
  `0xF5` correction-graph UUID (16 bytes). These are version tags and are not
  comparator components. They make two resolutions under different `V`
  different evidence and allow retained superseded/current rows without a
  false canonical-byte collision;
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

The five version records in the header are exact:

| Tag | Logical value and exact source | Payload |
| ---: | --- | --- |
| `F1` | `inventory_event_order_policies.id` selected for E1/source type | `uuid_send` |
| `F2` | `ref_inventory_event_source_types.source_document_type` | NFC UTF-8 text |
| `F3` | `inventory_canonical_form_versions.id` selected for E1/source type | `uuid_send` |
| `F4` | `inventory_events.valuation_scope_id`, which references the exact `inventory_valuation_scopes.id` scope version | `uuid_send` |
| `F5` | `inventory_correction_graph_versions.id` selected for E1/company | `uuid_send` |

Every version value is non-null, is retained in its separate WP-4 order-key
column, and is also framed here. No current master-data lookup may replace a
retained version during replay.

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

### 6.4 Ordered admission-component sequence

After the §6.2 version vector, `canonical_key_bytes` records these thirteen
admission-resolved components. Tags below are single hexadecimal byte values;
the source and authority columns are exhaustive for current WP-5:

| Tag | Component / logical type | Exact source field/table | Source authority | Exact payload representation |
| ---: | --- | --- | --- | --- |
| `01` | E1 economic instant / `timestamptz` | `inventory_events.effective_at`, supplied by `p_events[].effective_at` | source workflow assertion under the current certification rule; future production adapter separately required | normal timestamp payload |
| `03` | E3 effect rank / `smallint` | `inventory_event_effect_ranks.effect_rank`, selected after `ref_inventory_event_source_types.event_effect_map` maps the event effect | immutable registry plus applicable event-order policy | `int2send` bytes |
| `04` | E4 source-type rank / `smallint` | `inventory_source_type_ranks.source_type_rank` for the occurrence source type | applicable event-order policy | `int2send` bytes |
| `05` | E5 document order key / `bytea` | `inventory_occurrences.source_document_id` plus `ref_inventory_event_source_types.document_order_key_algorithm`; input assertion `p_document_order_key_input` must match | immutable pre-admission source UUID and registry algorithm | complete §6.3 E5 bytes |
| `06` | E6 line ordinal / `integer` | `p_source_line_ordinal`, retained at `inventory_events.immutable_source_evidence.ia5_ecc_admission.source_line_ordinal` | source workflow under `ref_inventory_event_source_types.line_order_authority` | `int4send` bytes |
| `07` | E7 transition rank / `smallint` | `inventory_transition_ranks.transition_rank` for `inventory_occurrences.source_transition` | applicable event-order policy | `int2send` bytes |
| `08` | E8 occurrence ordinal / `bigint` | `inventory_occurrences.source_occurrence_sequence` | immutable source occurrence semantics from the registry | `int8send` bytes |
| `09` | E9 event ordinal / `integer` | `inventory_events.event_sequence` | deterministic caller event plan validated by the writer | `int4send` bytes |
| `10` | E10 source identity / `bytea` | the occurrence/event source type, document UUID, line UUID, transition, E8 and E9 fields | immutable pre-admission source identity under the registry | complete §6.3 E10 bytes |
| `11` | X1 correction depth / `integer` | current certification resolver constant `0`; no current production correction rule | `ref_inventory_event_source_types.correction_placement_class='base'` plus null ancestry | `int4send(0)` |
| `12` | X2 correction effective instant / `timestamptz` sentinel | current certification base sentinel; no stored source timestamp is substituted | same base rule | one byte `00` |
| `13` | X3 correction approval instant / `timestamptz` sentinel | current certification base sentinel; no stored source timestamp is substituted | same base rule | one byte `00` |
| `14` | X4 correction identity / `bytea` | current certification base sentinel; no generated id is used | same base rule | zero-length payload |

E2 deliberately has no tag in the admission byte stream. It is the
population-derived causal depth computed later by WP-7 and compared between E1
and E3. The full comparator remains
`E1,E2,E3,E4,E5,E6,E7,E8,E9,E10,X1,X2,X3,X4`.
WP-7 must serialize/fingerprint the already ordered population in that order;
it may not mutate this persisted evidence or invent an admission-time E2.

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
| `IA5-WP5-006` | Cross-company source/event/scope/policy/stream/key/target; writer/resolver/guards | `23514` | No row; offending identities in message, no secret payload; `112` |
| `IA5-WP5-007` | Missing or ambiguous order policy/effect/source/transition rank; resolver | `23514` | Retry after governed version fixture; `112` |
| `IA5-WP5-008` | Missing/invalid canonical-form or correction-graph version; resolver | `23514` | Retry after governed version; `112` |
| `IA5-WP5-009` | Missing/multiple/mismatched valuation stream; writer/resolver | `23514` | Retry after source correction; `112` |
| `IA5-WP5-010` | Malformed argument, event plan, key, decimal, UUID, timestamp or unknown JSON key; writer | `22023` | Idempotent after correcting input; `112` |
| `IA5-WP5-011` | Idempotency key reused with different governed request/context; writer | `23505` | Not retryable under same key; evidence is both fingerprints/identities; `112` |
| `IA5-WP5-012` | Logical source occurrence duplicated under another key; occurrence constraint/writer | `23505` | Not retryable as a new fact; `112` |
| `IA5-WP5-013` | Contradictory event plan/effect/direction/ancestry; writer/resolver | `23514` | Whole occurrence rejected; `112` |
| `IA5-WP5-014` | Malformed or non-NFC component / canonical encoding failure; resolver | `22021` | Retry after canonical input correction; `111`/`112` |
| `IA5-WP5-015` | Digest recomputation differs; writer | `23514` | Not accepted; implementation defect blocks gate/certification; `111` |
| `IA5-WP5-016` | E10 or canonical admission bytes duplicate another fact; order-key constraint | `23505` | Both logical applications are unsafe; stream certification blocked; `112` |
| `IA5-WP5-017` | Missing current order key for a persisted event; writer/trigger | `23514` | Transaction aborts; no repair path; `112` |
| `IA5-WP5-018` | Duplicate current order key; WP-4 partial unique index | `23505` | Transaction aborts; `112` |
| `IA5-WP5-019` | Stream allocator row/company mismatch or no returned sequence; writer | `23514` | Transaction aborts including counter statement; `112` |
| `IA5-WP5-020` | Unsupported correction/reversal/fork/counterfactual chain under current source rule; resolver | `0A000` | Requires separate source/correction authority, not retry; `112` |
| `IA5-WP5-021` | Illegal key update, deletion or supersession; WP-4 guard | `23514` | Original remains; `112` regression |
| `IA5-WP5-022` | Resolver returns zero/multiple rows; writer | `23514` | Transaction aborts; `111`/`112` |
| `IA5-WP5-023` | Event-side totality fails at deferred boundary; trigger function | `23514` | Transaction aborts; no event/key residue; `112` |
| `IA5-WP5-024` | Certification fixture reaches constraint execution/commit; trigger function | `23514` | Mandatory rollback path; not production evidence; `112` |
| `IA5-WP5-025` | Rollback precondition/residue mismatch; rollback test/migration | `23514` | Rollback stops before destructive step; `113` |

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

The fixture path:

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

### 9.4 Evidence boundary

WP-5 tests may prove only: exact signature/security/object shape; writer and
resolver behavior; version-tagged 13-component admission encoding; digest; atomic stream/event/
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

### 10.3 Current and superseded semantics

- initial admission inserts exactly one `current` row;
- writer/resolver never update or delete an order key;
- exact duplicate admission returns the same current row and inserts nothing;
- `resolution_state` is the only mutable WP-4 column and its only permitted
  transition remains `current` → `superseded`, enforced by the existing
  `ENABLE ALWAYS` guard;
- WP-5 exposes no correction, re-resolution, policy-version-change,
  source-version-change, canonical-version-change, replay or supersession
  procedure, so no WP-5 object performs that transition;
- old rows are never deleted and remain queryable by event/version/state;
- a future re-resolution must, in one separately authorised transaction,
  demote the old row, insert one successor current row under the target `V`,
  retain the old row, and add key-side deferred totality before runtime use;
- until that future contract exists, direct owner demotion is a prohibited
  governance act and cannot be cited as supported behavior;
- uniqueness applies to one current row per event and to
  `(valuation_stream_id,canonical_key_bytes)` across retained resolutions;
- rollback of a transaction removes its newly inserted event/key and allocator
  effects automatically; persistent delete is never a rollback method.

This resolves the present admission boundary without falsely claiming that
future re-resolution is implemented.

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
- the ten `supabase/verification/ia5_*` assets that reference the old signature
  must be updated in their later authorised scope before they are executable;
  `ia5_rollback_boundary.sql` must name the new signature and exact restoration.

These future test edits do not occur in EA-008. WP-1…WP-4 remain certified in
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

No test is authored by EA-008. Future implementation owns exactly:

| Test ID/file | Families owned | Required fixture / persistence | Core assertions and SQLSTATE | Explicitly excluded |
| --- | --- | --- | --- | --- |
| `111_inventory_accounting_ia5_ecc_wp5_admission_contract_test.sql` | `WP5-ST-111` structural; `WP5-FX-111` fixture/encoding | Exact local owner fixture, one transaction, final rollback | 3 governed function signatures + 1 trigger; 25-column resolver row; exact payload rejection; version-tagged 13-component golden bytes and 32-byte digest; one event/one key/one stream; `22021`/`23514`; zero persistent rows | No production, costing, comparator, GL or engine claim |
| `112_inventory_accounting_ia5_ecc_wp5_totality_failure_security_test.sql` | `WP5-TOT-112`, `WP5-FAIL-112`, `WP5-SEC-112` | Exact two-company certification fixture; rolled back | success before rollback; zero/multiple key rejection `23514`/`23505`; production-disabled failure; fixture commit rejection; all §7 failures feasible in M5; idempotent retry/concurrency; direct-role `42501`; cross-company `23514` | No hosted or source activation claim |
| `113_inventory_accounting_ia5_ecc_wp5_rollback_test.sql` | `WP5-RB-113`, `WP5-RES-113` | M5-applied database; structural rollback inside transaction; final rollback | exact reverse object census; old writer restored; trigger set restored; WP-1…WP-4 unchanged; all fixture/audit/counter counts zero; no ACL/comment residue; failure precondition `23514` | Does not uninstall M5 persistently or certify it |

Evidence classes:

- structural assertions are persistent M5 schema evidence;
- all business/version/event/key fixtures are certification-only and rolled
  back;
- totality failure uses deferred constraint execution inside a rolled-back
  transaction;
- security uses owner and `SET LOCAL ROLE` attacks, then rollback;
- rollback proof is structural inside a transaction and ends in rollback;
- residue proof occurs in a fresh follow-up transaction;
- regression census updates to `103` and `109` are part of the future WP-5
  implementation change; tests `104`…`110` all rerun;
- canonical accounting lane expectation: fresh DB plus focused `103`…`113`,
  then the repository's canonical database lane only if the Authorisation Gate
  authorises implementation;
- documentation lane: `npm run docs:check` and `git diff --check`;
- all evidence is WP-5 bounded and cannot lift C-01, certify IA-5 permanent
  foundation, Inventory Engine or Inventory module.

---

## 13. Authoritative implementation-boundary table

| Object | Action / owner | Purpose | Reads / writes | Security and callable boundary | Rollback / test owner | Explicit exclusions |
| --- | --- | --- | --- | --- | --- | --- |
| 14-arg `fn_ia5_record_dormant_inventory_occurrence` | Replace / `postgres` | Atomic source admission, accepted occurrence/event/stream/key evidence | Reads §3.6; inserts seven listed tables; updates only stream allocator | Definer; owner only; no current runtime; fixture owner-callable | Drop, restore old 11-arg body / `111`,`112`,`113` | No costing, projection, Posting, GL, tax, activation |
| `fn_ia5_ecc_resolve_components` | Create / `postgres` | Resolve and encode admission-time chronology components | Exact §5.2 allowlist; no writes | Definer; writer-only runtime; owner fixture direct call only | Drop / `111`,`112`,`113` | No E2, cost, quantity valuation, comparator, replay or journal |
| `fn_ia5_enforce_event_order_key_totality` | Create / `postgres` | Deferred event-side exactly-one-current and fixture commit rejection | Reads `public.inventory_event_order_keys` and `public.ref_inventory_event_source_types`; `NEW` supplies the event; no writes | Definer trigger execution only; direct execution revoked | Drop after trigger / `112`,`113` | No key repair, supersession or runtime activation |
| `inventory_events_ecc_order_key_totality_ct` | Create on existing table / managed by `public.inventory_events` owner `postgres`; PostgreSQL gives triggers no separate owner | Arm totality after insertion | Fires on event; no direct table read/write of its own | ALWAYS, deferred constraint trigger | Drop first / `103`,`112`,`113` | No column/constraint/index/policy change |
| Existing WP-1…WP-4 objects | Preserve | Dependencies and controls | Read only, except certified stream allocator/key inserts through writer | Existing ACL/RLS/guards unchanged | Census / `103`…`113` | No reopening of certified scope |

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
    The implementation boundary also records the gate-reviewed EA-008 spec and
    amended-design hashes. A migration cannot read documentation hashes, so the
    Authorisation Gate records them before implementation.
12. Hosted state is neither queried nor assumed.

Any failure raises `23514` with an M5 stop-condition message before the first
DDL statement. It authorises no repair, backfill, trigger disablement, object
drop, source enablement or inference.

### 14.2 Exact postconditions

After future M5 implementation:

- exactly 12 `public.fn_ia5_*` signatures exist (10 pre-M5, plus resolver and
  trigger function; the writer replacement does not increase the count);
- exactly 10 of them are `SECURITY DEFINER` (the two existing immutable numeric
  helpers remain invoker/immutable); all new/definer functions pin
  `search_path=public`;
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
- tests `111`…`113` are registered; `103`/`109` are reconciled; no new table
  coverage entry exists;
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

## 17. Governance quality challenge and decision

EA-008 attempted to reject itself against every item in the gate's invention
list. Object name/count, function signatures, arguments/types/defaults,
return fields, payload keys, encoding/byte order/digest, privileges, trigger
metadata, SQLSTATEs, state transitions, fixture behavior, source eligibility,
locks/idempotency/concurrency, rollback order, test/evidence boundaries,
runtime exclusions and postconditions are fixed above.

No unresolved decision within WP5-AG-001…003 requires the Product Owner,
ADR-C01 owner or ECC-01 owner. The only prospective rule not implemented is
`governed_business_sequence` representation; because no such source row exists
or is enabled, the exact WP-5 behavior is fail-closed `0A000`. Its future
representation requires a separately governed source-registry amendment and
does not make this certification-only M5 implementation ambiguous.

**Decision:** `WP-5 ENGINEERING AMENDMENT COMPLETE — READY FOR AUTHORISATION GATE RE-RUN`.

This is a specification-readiness decision only. WP-5 remains unauthorised and
unimplemented.
