# PXL Last Session

## 1. Date

2026-08-01

## 2. Mission

WP-5 Engineering Amendment EA-010 — comprehensive documentation/governance
closure of WP5-AGR2-001 through WP5-AGR2-004, followed by validated `main`
handoff. This mission did not run the Authorisation Gate or implement WP-5.

## 3. Status

`EA-010 COMPLETE — READY FOR WP-5 AUTHORISATION GATE RE-RUN`.

WP-5 remains unauthorised, unimplemented, unaudited and uncertified. EA-010
cannot authorise itself.

## 4. Starting Branch

`main`

## 5. Starting Commit

`32b7f599718acdbf1e9c7a0245c14378d628f5e5`

## 6. Remote Synchronization

Mission start: local `main` and `origin/main` were synchronized at the starting
commit; ahead/behind was `0/0`; the worktree was clean. Final synchronization is
recorded in §34 after the governed commit/push procedure.

## 7. Product Architecture Standing

[`docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`](docs/PXL/01.%20Architecture/PXL_PRODUCT_ARCHITECTURE.md)
remains canonical and unchanged. EA-010 changes no product scope, module/engine
taxonomy, accounting policy or production-readiness claim.

## 8. Product Roadmap Standing

[`docs/PXL/01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md`](docs/PXL/01.%20Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md)
remains subordinate and unchanged. Its value checkpoint still applies after any
later WP-5 lifecycle.

## 9. Repository Standing

- WP-1 through WP-4 remain Certified bounded work packages.
- C-01 and the IA-5 permanent-foundation suspension remain open.
- No Inventory Accounting Engine or Inventory Module certification exists.
- WP-5 remains unauthorised and has no executable object or runtime consumer.
- WP-6…WP-9 and IA-6 remain unauthorised.
- No production Inventory source is enabled.
- No hosted operation occurred.

## 10. Complete Four-Finding Ledger

| Finding | Severity | Exact evidence / root cause | Unsafe consequence | Minimum governed repair | Confidence |
| --- | --- | --- | --- | --- | --- |
| `WP5-AGR2-001` | High | ECC-01 requires retained target-version evidence; WP-4 structurally permits superseded history; executable WP-4 also has unconditional `UNIQUE (valuation_stream_id,canonical_key_bytes)`; EA-009 excluded `V` from those bytes yet described a successor. Comparator identity was conflated with resolution identity. | Unchanged-component re-resolution fails `23505` or invites a silent WP-4 change. | Initial-resolution-only WP-5; fail on any prior resolution; separate future lifecycle governance. | High |
| `WP5-AGR2-002` | High | EA-009 lacked exact mapping for required/defaulted/derived columns across occurrences, events, links, values, streams, allocator and keys; old-writer date/policy/currency/evidence/audit semantics and stored text normalization were not governed. | Implementer chooses accounting/audit row semantics. | Exhaustive seven-table per-column map plus old-writer disposition matrix. | High |
| `WP5-AGR2-003` | High | EA-009 `E1::date`, preserved guard `NEW.effective_at::date`, and current writer `p_occurred_at::date` inherited session timezone despite UTC ECC timestamps. | Same instant may select different authority or pass/fail differently by session. | UTC function configuration/date expressions and two-timezone evidence. | High |
| `WP5-AGR2-004` | High | All-rollback test `112` was assigned two-session evidence, but autonomous sessions cannot see uncommitted setup; repository precedent requires committed local setup and immediate reset. | Evidence would require leakage, weakening or fabrication. | Dedicated local-only reset-bounded two-session asset with event rollback/commit reject and residue proof. | High |

The exact issued chronology is preserved in the WP-5 specification's EA-010
ledger and programme design §§35–36; prior rejection/amendment records were not
rewritten.

## 11. WP5-AGR2-001 Resolution

WP-5 owns initial resolution only. A new event must have zero prior order-key
rows of any state. It receives exactly one immutable `current` row. Any prior
row raises `IA5-WP5-026`/`23505`; no update, demotion, successor, supersession
or re-resolution is permitted. WP-4 certification remains unchanged.

## 12. Initial-Resolution-Only Boundary

Exact duplicate admission returns the one persisted current row. Missing,
extra, or superseded duplicate-result evidence fails `23514` and is never
repaired. Writer, resolver and trigger expose no re-resolution entry point.

## 13. Future Re-resolution Stop

Before version-only or other re-resolution, successor rows, automatic
supersession, any WP-7 capability depending on re-resolution, or Inventory
production activation, separate governance must resolve WP-4's unconditional
canonical-identity uniqueness. EA-010 does not choose that future repair.

## 14. WP5-AGR2-002 Resolution

The detailed specification now governs every one of the **139 columns** across
the seven writer-target tables, including exact source/default/null,
normalization, validation/failure, insert/update behavior, audit meaning and
whether the old writer rule is preserved or modified.

## 15. Complete Persistence Map Summary

| Table | Columns | Governing result |
| --- | ---: | --- |
| `inventory_valuation_streams` | 7 | Exact version-free identity/create-or-resolve contract |
| `inventory_valuation_stream_sequences` | 4 | Exact stream lock and forward allocation |
| `inventory_occurrences` | 24 | Complete atomic/idempotency/audit row |
| `inventory_events` | 41 | Complete source, date, policy, quantity, physical and audit row |
| `inventory_event_source_links` | 13 | Exactly one primary link and exact evidence object |
| `inventory_event_values` | 19 | Exact optional-row/currency/precision contract |
| `inventory_event_order_keys` | 31 | Exact resolver-to-WP-4 initial-resolution insert |

## 16. Preserved / Modified / Removed Old-Writer Behaviour

- **Preserved:** membership, atomic occurrence/event IDs, tenant/idempotency and
  logical-source uniqueness, scope/profile/formula/precision derivation,
  quantity/UOM validation, primary-link/value evidence, null Posting fields and
  all-or-nothing failure.
- **Modified:** 14-argument signature, strict normalized payload/fingerprints,
  stream allocator, UTC dates, exact stored text, resolver/key/totality, and
  production-versus-certification contexts.
- **Removed from WP-5:** old 11-argument callable, legacy scope allocator use,
  unknown-key tolerance, unchecked fingerprints, non-base ancestry inputs,
  timezone-dependent dates and any re-resolution/successor claim.

## 17. WP5-AGR2-003 Resolution

Writer and resolver must carry exact `SET TimeZone='UTC'`. `economic_date` is
`(effective_at AT TIME ZONE 'UTC')::date`; `occurrence_date` is
`(p_occurred_at AT TIME ZONE 'UTC')::date`. The preserved event guard executes
inside the writer's UTC setting, so its existing cast observes the same date.
The guard itself is not modified.

## 18. WP5-AGR2-004 Resolution

Single-session tests remain owner-only and rolled back. Future evidence
`WP5-CONC-114` is allocated to
`supabase/verification/ia5_wp5_concurrent_idempotency.sql`: fresh local reset,
minimum committed non-Inventory setup, two serializable owner sessions, waiting
proof, session-A rollback/commit-reject, session-B new-winner result then
rollback, immediate second reset and full residue proof. It makes no committed
production-winner or hosted claim.

## 19. Comprehensive Ambiguity Sweep

Resolved: object census, signatures/defaults, payload/return, 139-column map,
one writer sequence, lock order, idempotency, UTC dates, fourteen components,
26-column resolver, version references, initial lifecycle, source contexts,
trigger/totality, security, 26 failures, rollback, future evidence,
preconditions/postconditions and prohibited claims. Non-base E2/correction and
governed-business-sequence encoding remain exact fail-closed `0A000` future
scope. Committed production concurrency remains a future production-source
claim. No new implementation-affecting ambiguity was accepted by assumption.

## 20. Final WP-5 Object Contract

Future M5 still owns exactly four PostgreSQL objects: replacement 14-argument
writer; new eight-argument/26-column resolver; new deferred-totality trigger
function; and one `AFTER INSERT`, row-level, `DEFERRABLE INITIALLY DEFERRED`,
`ENABLE ALWAYS` constraint trigger on `inventory_events`. No helper, table,
column, index, policy, grant, wrapper, GUC or runtime consumer is authorised.

## 21. Security and Tenant Boundary

All three functions are `postgres`-owned `SECURITY DEFINER`, pin
`search_path=public`; writer/resolver also pin UTC. Execute remains revoked from
`PUBLIC`, `anon`, `authenticated` and `service_role`. Membership and company
identity are proven before idempotency lookup. Cross-company source, event,
scope, policy, stream or key evidence fails closed. No direct client chronology
DML or certification runtime path exists.

## 22. Rollback Boundary

Reverse order remains: drop constraint trigger; drop trigger function; drop
resolver; drop 14-argument writer; restore exact migration-13 11-argument body,
owner/config/ACL/comment; prove old trigger census, WP-1…WP-4 catalog, zero rows,
no comments/grants/policies/functions and no fixture residue. Rollback is
structural only and stops before mutation if any row/precondition differs.

## 23. Future Test and Evidence Allocation

- `111`: structure, 139-column map, resolver/encoding/digest, UTC equivalence.
- `112`: single-session totality/failures/security/idempotency, `026`, UTC
  attack, fixture commit reject.
- `113`: exact structural rollback and residue.
- `WP5-CONC-114`: isolated reset-bounded two-session rollback-winner proof.
- Regression: semantic updates to `103`/`109`; rerun `104`…`110`.

No test was created or modified by EA-010.

## 24. Files Created

None.

## 25. Files Modified

1. `docs/PXL/07. Inventory/04. Implementation/IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`
2. `docs/PXL/07. Inventory/04. Implementation/IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md`
3. `docs/PXL/13. Testing and Validation/PXL_CERTIFICATION_MATRIX.md`
4. `docs/PXL/PXL_DOCUMENTATION_INDEX.md`
5. `AI/AI_STATE.md`
6. `AI_PROGRESS.md`
7. `AI_LAST_SESSION.md`

## 26. Validation Summary

**PASS.** `npm run docs:check` reports 92 Retested Passed / 0 In Progress / 0
Open, AI startup budgets pass, the findings/index/matrix/test-book state is
consistent, and 110 test files remain registered. `git diff --check` passes.
Internal validation checked 381 tracked Markdown files / 154 internal links
with zero missing targets. The executable-schema census matches all 139 mapped
columns across seven tables; the controlling contract has 18 ordered writer
steps, 14 ECC components, 26 resolver outputs and 26 unique failures
(`001`…`026`). Four-object/trigger/reverse-rollback, future-test/evidence,
identifier-length, authority/chronology/status and initial-resolution censuses
pass. Product Architecture, Roadmap and every protected implementation/authority
asset are unchanged. No database mutation, pgTAP lane or hosted command ran.

## 27. Protected Manifest Entry Count

`527`; path-manifest SHA-256
`168c3ef5391c26f8ee5472b09c72a96b1089cb9dd2930502b65188645b99f508`.

## 28. Start and End Protected Hashes

- Start: `8ddf66f36c63606f8eb0bceaacfe3f3131337758b895fc557ec488ca383d7ba6`
- End: `8ddf66f36c63606f8eb0bceaacfe3f3131337758b895fc557ec488ca383d7ba6`
- Result: identical. No protected executable or authority artifact changed.

## 29. Secret / Privacy Scan

The complete seven-file change surface and frontend source guard found no
credential, token, private key, remote database URI, client record, TIN,
invoice/tax file, dump or backup. No sensitive-path file is tracked and there
is no untracked file. Existing `.env.local` and a Supabase temporary certificate
are ignored and were excluded from staging. The previously owner-approved exact
Supabase CLI localhost default remains a reviewed false positive only; no
blanket URI exemption exists.

## 30. Remaining Blockers

No EA-010 specification blocker remains. WP-5 is nevertheless blocked from
implementation until the separate Authorisation Gate passes. Future
re-resolution/production activation additionally requires separate lifecycle
governance; this is outside initial-resolution WP-5.

## 31. Remaining Non-blockers

No committed-production-winner concurrency claim is available under the
disabled certification source; it is correctly deferred. Non-base source,
correction, business-sequence, costing, replay, Posting, tax, hosted and product
readiness remain excluded future scope.

## 32. WP-5 Authority Standing

**Unauthorised, unimplemented, unaudited and uncertified.** No SQL, migration,
test, runtime/application source, database object, route, navigation, Product
Architecture, Roadmap or hosted environment changed.

## 33. Recommended Next Mission

`WP-5 AUTHORISATION GATE RE-RUN — COMPREHENSIVE FINAL GATE`

The next reviewer must independently attempt to reject the complete EA-010
contract. Do not implement or repair during that gate.

## 34. Commit and Push Result

Pending final validation. Governed commit message:
`governance: complete WP-5 EA-010 contract reconciliation`. The committed
repository state is identified by current `main` HEAD after commit; final push
and local/remote synchronization must be verified before mission completion.

## 35. NEXT AGENT START HERE

Read, in order:

1. `AI/AGENT_SYSTEM_PROMPT.md`
2. `AI/AI_STATE.md`
3. this file
4. `AI_PROGRESS.md`
5. `docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md`
6. `docs/PXL/01. Architecture/PXL_PRODUCT_EXECUTION_ROADMAP.md`
7. `docs/PXL/07. Inventory/04. Implementation/IA-5_WP-5_DETAILED_EVENT_ADMISSION_AND_COMPONENT_RESOLUTION_SPECIFICATION.md`
8. `docs/PXL/07. Inventory/04. Implementation/IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md` §§35–36
9. ADR-C01, ECC-01, and certified WP-1…WP-4 contracts

Run only the comprehensive WP-5 Authorisation Gate. EA-010 is not authority to
implement. No runtime or hosted claim exists.
