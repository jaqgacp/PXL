# PXL — Last Session Handoff

## 1. Date

2026-08-01 (UTC)

## 2. Mission

IA-5 ECC Hardening — WP-5 Engineering Amendment EA-008, documentation only,
strictly limited to WP5-AG-001, WP5-AG-002 and WP5-AG-003.

## 3. Status

**WP-5 ENGINEERING AMENDMENT COMPLETE — READY FOR AUTHORISATION GATE
RE-RUN.** This is specification readiness only. WP-5 is not authorised,
implemented, audited or certified.

## 4. Product Architecture Standing

The canonical Product Architecture remains
`docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`. It was read and left
unchanged. EA-008 changes no product scope, module/engine ownership or product
maturity.

## 5. Product Roadmap Standing

The subordinate roadmap remains
`docs/PXL/01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md`. It was read and
left unchanged. Its Phase B sequence still requires a WP-5 specification repair,
a separate gate and a product-value checkpoint before further dormant work.

## 6. Repository Standing

The worktree was already dirty and uncommitted. Unrelated changes were
preserved. EA-008 changed documentation only. No SQL, migration, test, source,
runtime, route, navigation, database object, business data or hosted environment
was changed or executed.

## 7. Files Created

- `docs/PXL/07. Inventory/04. Implementation/IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`

## 8. Files Modified

- `docs/PXL/07. Inventory/04. Implementation/IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md`
- `docs/PXL/13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md`
- `docs/PXL/PXL_DOCUMENTATION_INDEX.md`
- `AI/AI_STATE.md`
- `AI_PROGRESS.md`
- `AI_LAST_SESSION.md` (overwritten completely)

Product Architecture, Product Execution Roadmap, ADR-C01, ECC-01 and certified
WP-1…WP-4 specifications were not modified.

## 9. WP5-AG-001 Resolution

**Closed at specification level.** EA-008 fixes the current 11-argument writer
frontier; the exact 14-argument DROP-and-CREATE replacement; exact payload and
return schemas; writer transaction, writes, locks, idempotency and atomicity;
the exact 8-argument/25-column resolver; canonical bytes/digest; SQLSTATEs;
security; and pre/postconditions.

It corrects one prospective M5 contradiction: E2 is population-derived and
cannot be serialized at admission. `canonical_key_bytes` therefore encodes the
version vector plus 13 persisted admission components; the later comparator remains the frozen
14-component E1,E2,E3…X4 order. WP-4 storage certification remains bounded and
valid because it certified no resolver/encoding implementation.

## 10. WP5-AG-002 Resolution

**Closed at specification level.** Production is the default context and
remains ECC-01 V-10 fail-closed. The current repository has no enabled source,
activated version/stream or production source adapter, so no production call
can succeed.

The certification path is one explicit writer context, exact
`IA5_CERTIFICATION` source, `postgres` only, local/fresh only, explicit
BEGIN/assertions/ROLLBACK, no runtime grant and no hosted claim. The deferred
trigger rejects certification fixture constraint execution/commit after first
checking one current key, making accidental persistence impossible.

## 11. WP5-AG-003 Resolution

**Closed at specification level.** M5 owns four database objects: one replaced
writer, one new resolver, one new trigger function and one new deferred
constraint trigger. Trigger name, table, timing, event, level, deferrability,
ALWAYS enablement, SQLSTATE, totality, current/superseded behavior, test `103`/
`109` consequences, rollback and evidence ownership are exact.

## 12. Exact WP-5 Object Contract

1. Replace
   `public.fn_ia5_record_dormant_inventory_occurrence(uuid,text,uuid,uuid,text,bigint,text,text,timestamptz,uuid,jsonb)`
   with the exact 14-argument signature in EA-008 §3.
2. Create
   `public.fn_ia5_ecc_resolve_components(uuid,integer,text,text,uuid,timestamptz,timestamptz,text)`.
3. Create trigger function
   `public.fn_ia5_enforce_event_order_key_totality()`.
4. Create constraint trigger
   `inventory_events_ecc_order_key_totality_ct` on `public.inventory_events`.

No helper, overload, type, table, column, constraint, index, policy, grant,
wrapper, GUC, feature flag or runtime consumer is authorised.

## 13. Writer Contract Summary

The replacement remains owner-only `SECURITY DEFINER`, `search_path=public`,
with no client/service execute grant. It validates exact request/payload
fingerprints, membership, context, registry, company, plan, scope and versions;
resolves/creates one stream; advances only the stream-keyed accepted allocator;
inserts occurrence/event/link/optional authoritative value/current order key;
and returns exact occurrence/event/key/stream identities. Any event failure
rolls back the whole occurrence.

## 14. Resolver Contract Summary

The resolver is owner-only, writer-consumed, read-only DML-wise and returns
exactly one 25-column row. It resolves E1, E3…E10, X1…X4 and five version
references, serializes the version vector plus 13 admission-resolved components and returns their
32-byte SHA-256 digest. It cannot read accepted counters as chronology and
cannot calculate cost, valuation, FIFO, WAC, COGS, posting, tax or journals.

## 15. Canonical Encoding Summary

Encoding marker: `PXL_ECC_ADMISSION_K1`. The five-element version vector is
tagged before component records. Framing is one-byte tag + four-byte
unsigned big-endian length + payload. Text is NFC UTF-8; UUID is 16 bytes;
integers are fixed-width big-endian; timestamps are UTC microsecond text;
base X2/X3 use a distinct sentinel encoding; E10 is its own exact six-field
composite; JSON and amounts are excluded. Digest is the exact pgcrypto call
`extensions.digest(canonical_key_bytes,'sha256')`, yielding 32-byte `bytea`.

## 16. Certification-Fixture Boundary

The only fixture mode is the exact writer argument
`p_admission_context='certification_fixture'`. It accepts only the existing
disabled certification row, is callable only by `postgres`, has no normal-role
grant, is prohibited from commit and hosted claims, must rollback every
Inventory/version/audit/counter row, and cannot prove production activation or
Inventory readiness.

## 17. Trigger and Totality Contract

`inventory_events_ecc_order_key_totality_ct` is an `AFTER INSERT FOR EACH ROW`
constraint trigger, `DEFERRABLE INITIALLY DEFERRED`, `ENABLE ALWAYS`. At the
governed boundary every inserted event must have exactly one same-company
current key. Intermediate incompleteness is allowed only inside the writer
transaction. The trigger writes/repairs nothing and rejects fixture commit.

WP-5 performs no re-resolution or supersession. WP-4's only permitted state
transition remains current to superseded, but no current runtime procedure can
invoke it. A future re-resolution package needs separate authority and key-side
totality before use.

## 18. Security Boundary

All three functions are `postgres`-owned `SECURITY DEFINER` with
`search_path=public`; execution is revoked from PUBLIC, anon, authenticated and
service_role. Existing membership/RLS/guard/immutability controls remain.
Company must match across actor, source, occurrence, event, scope, stream,
allocator, version/rank, key and correction target. Direct chronology DML is
prohibited.

## 19. Rollback Contract

After zero-row/dependency/control preconditions and appropriate locks: drop the
constraint trigger; drop its function; drop resolver; drop the 14-argument
writer; recreate the exact 11-argument migration-13 writer; restore its owner,
security, search path, ACL and comment; prove the old three-trigger event set,
WP-1…WP-4 catalog state and zero row/audit/counter residue. Future test `113`
executes that proof transactionally and rolls it back.

## 20. Future Test and Evidence Allocation

- `111_inventory_accounting_ia5_ecc_wp5_admission_contract_test.sql` —
  structural, fixture, golden canonical bytes/digest.
- `112_inventory_accounting_ia5_ecc_wp5_totality_failure_security_test.sql` —
  totality, complete failures, idempotency/concurrency and tenant/role attacks.
- `113_inventory_accounting_ia5_ecc_wp5_rollback_test.sql` — exact restoration
  and certification residue.

Future implementation must semantically reconcile tests `103` and `109`, then
rerun `103`…`110`. No test changed in EA-008.

## 21. Validation Summary

- `npm run docs:check` — **PASS**.
- `git diff --check` — **PASS**.
- Internal links and documentation-index registration — **PASS**; all changed-
  document targets resolve and the WP-5 specification is registered once.
- WP5-AG-001/002/003, authority/status and chronology-preservation checks —
  **PASS**.
- Object/rollback census — **PASS**: three governed functions (one replaced,
  two created), one constraint trigger, exact reverse restoration.
- Failure/evidence census — **PASS**: 25 unique failure IDs and seven exact test
  families allocated across future tests `111`…`113`.
- Identifier check — **PASS**: governed names are 29, 39, 42 and 42 bytes,
  each below PostgreSQL's 63-byte maximum.
- Product Architecture, Product Roadmap, ADR-C01 and ECC-01 hashes —
  **unchanged**. The aggregate mission-start/end hash for every file under
  `src`, `supabase` and `scripts` is identical.
- No SQL, migration, test, runtime, route/navigation, database or hosted change
  occurred. No database or pgTAP lane and no hosted command was run.

## 22. Remaining Blocking Findings

None within WP5-AG-001…003 at specification level. The separate Authorisation
Gate is still mandatory and may independently reject EA-008. WP-5 remains
unauthorised.

## 23. Remaining Non-blocking Findings

The `governed_business_sequence` representation remains intentionally
fail-closed `0A000` because no current or enabled registry row uses it. A future
production source needs a separately governed registry/source-adapter amendment.
This does not affect the exact certification-only M5 contract.

## 24. Current Product Value Boundary

WP-5 proves what permanent evidence fixes later Inventory accounting sequence.
It does not calculate cost, layers, COGS, journals, accounts, tax or product
readiness. After any later WP-5 certification, the roadmap product-value
checkpoint still decides whether dormant WP-6+ work is more valuable than
canonical Sales/Purchasing proof, Receiving accounting, Tax authority, opening
balances and backup/restore.

## 25. Recommended Next Mission

**WP-5 AUTHORISATION GATE RE-RUN — Lifecycle Step 2.** Documentation and
governance only. Independently verify EA-008; do not implement WP-5 during the
gate.

## 26. NEXT AGENT START HERE

Read in order:

1. `AI/AI_STATE.md`
2. this file
3. `AI_PROGRESS.md`
4. `docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`
5. `docs/PXL/01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md`
6. `docs/PXL/07. Inventory/04. Implementation/IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` §§31–32
7. `docs/PXL/07. Inventory/04. Implementation/IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`
8. ADR-C01, ECC-01 and certified WP-1…WP-4 only where the gate must verify a
   cited dependency.

Gate question: does EA-008 close WP5-AG-001…003 without new
implementation-affecting ambiguity? Do not use this handoff as authority to
implement. WP-5 is not authorised; no runtime behavior, database object, test
or hosted environment changed.
