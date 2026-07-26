# ECC-01 Final Architecture Acceptance Report

**Status:** Final — architecture acceptance gate complete
**Authority:** Architecture review under the PXL authority order (`AI/AGENT_SYSTEM_PROMPT.md` §"Authority and Product Truth") and `docs/PXL/00. Governance/PXL_PRINCIPLES.md` §21; subordinate to [ADR-C01](ADR-C01_ECONOMIC_EVENT_CHRONOLOGY_AND_COSTING_ORDER_AUTHORITY.md)
**Owner / Domain:** Inventory Accounting
**Gate date:** 2026-07-26
**Applies To:** [ECC-01](ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md) acceptance, governance reconciliation, and freeze readiness
**Read When:** Deciding whether ECC-01 may be frozen, or before beginning IA-5 economic-costing-chronology hardening
**Do Not Read For:** Implementation authority. This gate performed no implementation and authorizes none.
**Subsequent status (2026-07-26):** At the time of this report, formal owner acceptance of ECC-01 was outstanding and ECC-A-11 was open. ECC-01 was subsequently accepted under [`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`](ECC-01_FORMAL_OWNER_ACCEPTANCE.md) (`ACCEPTED — OWNER APPROVED`, not frozen), and ECC-A-11 was resolved as Outcome B by [`PG-01_GOVERNANCE_AUTHORITY_MAP.md`](../../00.%20Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md). This report's conclusions are preserved as issued.

---

## 1. Executive Conclusion

**Decision: B — ACCEPTED WITH NON-BLOCKING CLARIFICATIONS.** All listed
clarifications were applied during this gate under its documentation authority
(Amendment A1). ECC-01 is architecturally complete and conforms to ADR-C01.

ECC-01 is a genuine derivation specification, not a restatement of the ADR. It
supplies what ADR-C01 §6.3 left open: a comparator, a normalization contract, an
eight-stage algorithm, four proved properties, thirty-five validation rules,
fifteen failure rules, and twenty-four worked numeric demonstrations. Every
arithmetic example in §7–§11 was independently recomputed during this gate and
every one reconciles exactly (§20.2). The ordering tuple is total, schedule-
independent, and free of database-assigned accounting authority. The Posting and
Kernel boundary is untouched.

Ten defects were found. Nine were bounded and were resolved in-document by this
gate; one (ECC-A-11, the undefined PG-01 authority) requires an owner decision
and does not block the architecture. Four of the nine — ECC-A-02, ECC-A-03,
ECC-A-04, and ECC-A-01 — would have blocked implementation had they been left
open, because two conforming teams could have derived different populations,
different keys, or different orders from identical facts. They are now closed by
normative text, not by interpretation.

The one status change this gate makes against the prior coder's report: **ECC-01
was not entitled to declare itself Frozen.** No repository authority authorizes
an AI-authored specification to record its own freeze. Its status is now
`PROPOSED — RECOMMENDED FOR ACCEPTANCE`. Freeze is an owner act.

---

## 2. Repository State Reviewed

Branch `main`, HEAD `6148aa4`, working tree dirty with preserved prior work.

| Document | Lines | Status found | Verdict |
| --- | ---: | --- | --- |
| `ECC-01_ECONOMIC_COSTING_CHRONOLOGY_DERIVATION_SPEC.md` | 1,446 (pre-amendment) | Self-declared "Frozen" | Content verified in full; status corrected |
| `ADR-C01_..._COSTING_ORDER_AUTHORITY.md` | 842 | Frozen | Controlling authority; verified, unmodified |
| `IA5_IA6_FINAL_EVIDENCE_GATE_REPORT.md` | 548 | Outcome C, controlling | Verified; all 9 asset links resolve |
| `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` | 269 | "Certified Complete" | **Contradicted Outcome C** — corrected (ECC-A-12) |
| `PXL_INVENTORY_COSTING_SPEC.md` | 353 | Frozen | §1 ordering sentence lacked supersession pointer — corrected |
| `AI/AI_STATE.md` | 81 | Updated by prior coder | Accurate on IA-5/ADR-C01/ECC-01; next-phase text updated by this gate |
| `AI/AGENT_SYSTEM_PROMPT.md`, `00. Governance/PXL_PRINCIPLES.md` | 103 / 160 | Active | Effective governance authority (§3) |
| `PXL_DOCUMENTATION_INDEX.md` | — | Active | Did not register ADR-C01/ECC-01/gate — corrected |
| `ADR-IAA-001`, IA-3 register, IA-4 blueprints, Layer Lifecycle, Reconciliation, Reporting, Architecture Spec | — | Frozen | Read for boundary and consistency; unmodified |

**Verification of the prior coder's reports.** Independently checked, not
accepted on assertion:

| Claim | Verdict |
| --- | --- |
| ECC-01 exists at the stated path, 1,446 lines, all 15 sections | **True** |
| No SQL, schema, migration, or implementation was written | **True** — `git status` shows no new/modified SQL, migration, test, or source file attributable to ECC-01 |
| Fourteen-component ordering tuple | **True** — 10 primary (E1–E10) + 4 correction-anchor (X1–X4) |
| Covers replay, FIFO, WAC, Specific-ID, backdating, corrections, concurrency, validation, failure | **True**, at normative depth, with worked numerics |
| Distinguishes order policy from calculation policy | **True** — §3.2 policy families vs dependencies of record; the cleanest single idea in the document |
| Contains conformance gaps against IA-5 | **True** — §14.1, five rows, all consistent with the gate's executable evidence |
| Broken documentation links were corrected | **True** — all 19 relative links across the three chronology documents resolve on disk |
| `AI_STATE.md` was stale and was updated | **True** |
| ECC-01 self-identifies as Frozen although acceptance may not have occurred | **True, and correctly flagged** — see ECC-A-01 |

**Two of the artifacts named in the gate instruction do not exist.** No document
named `00_PXL_ARCHITECTURE_PRINCIPLES.md`, no `PG-01` document, and no
standalone "IA-5 post-ADR conformity review" exist in this repository. Their
authoritative equivalents are `docs/PXL/00. Governance/PXL_PRINCIPLES.md`, the
authority order in `AI/AGENT_SYSTEM_PROMPT.md` (§3 below), and the conformity
assessment embedded in ADR-C01 §15(1) and ECC-01 §14.1 respectively. The
conformity conclusion the instruction attributes to a review document is real
and is recorded in those two places: IA-5 does not conform, because the Economic
Costing Chronology derivation is not implemented.

---

## 3. Governing Authority

| Question | Evidence-based answer |
| --- | --- |
| Was ECC-01 authorized? | **Yes, conditionally.** ADR-C01 §17 authorizes determining "the minimum additive authority hardening required"; gate Required Correction 3 requires all frozen contracts to describe one tuple. A derivation specification is squarely inside that grant. It was not, however, named in `AI_STATE.md`'s next-task list, so its authorization is owner-instruction-based, not repository-recorded. |
| Is ADR-C01 the controlling policy authority? | **Yes.** ADR-C01 §5–§12 are frozen decisions; ECC-01's own header declares subordination, and §1 confines it to deriving what §6.3 froze. |
| Is ECC-01 subordinate to ADR-C01? | **Yes**, verified by conformity matrix §5 — ECC-01 adds no ordering component, changes no rank, and reverses no ADR decision. |
| May ECC-01 declare itself Frozen? | **No.** `PXL_PRINCIPLES.md` §21 reserves structural authority to the human architect; `AGENT_SYSTEM_PROMPT.md` requires explicit approval for new documentation with a defined authority. Neither authorizes self-certification. ADR-C01's own freeze is distinguishable: gate Required Correction 1 explicitly instructed "**Freeze one explicit economic-order ADR**", and `AI_STATE.md` records that freeze. No equivalent instruction exists for ECC-01. |
| Is formal acceptance still required? | **Yes** — by the owner, recorded in `AI_STATE.md` or a successor governance record. |
| Does the repository define freeze authority? | **Only indirectly**, via `PXL_PRINCIPLES.md` §21 and the `AGENT_SYSTEM_PROMPT.md` authority order. There is no freeze-authority register. See ECC-A-11. |
| Does any document improperly self-certify? | **Two did.** ECC-01 ("Frozen") and `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` ("Certified Complete", contradicting Outcome C). Both corrected. |
| Does `AI_STATE.md` reflect governed status? | **Yes after this gate.** It was already accurate on IA-5 suspension, ADR-C01 freeze, ECC-01 authorship, and IA-6 non-authorization; its next-phase statement has been updated to this gate's outcome. |

**On PG-01.** ADR-C01's header cites "Architecture Authority under PG-01", and
both ADR-C01 §16/§17 and ECC-01 §15(13) invoke "PG-01 precedence". No PG-01
document exists. This gate did **not** stop on that basis, because the effective
authority is determinable without it: the `AGENT_SYSTEM_PROMPT.md` authority
order plus `PXL_PRINCIPLES.md` §21 supply document precedence, phase authority,
and human-controlled freeze. PG-01 is best read as a label for that chain. The
conservative consequence — no AI-performed freeze — is the same under either
reading, so the ambiguity changes no action taken here. It is recorded as
ECC-A-11 for owner resolution and must be settled before any document cites
"PG-01 precedence" as a binding rule.

---

## 4. ECC-01 Status Decision

**B — ACCEPTED WITH NON-BLOCKING CLARIFICATIONS.**

| Criterion | Result |
| --- | --- |
| No blocking architecture gap remains | **Met** — the four implementation-blocking gaps were closed in-document by this gate |
| Conforms to ADR-C01 | **Met** — §5, 14 of 14 rows conform |
| Ordering tuple total and deterministic | **Met** — §7, §8 |
| Replay fully governed | **Met after ECC-A-02/04/06** — §10 |
| Major costing methods adequately covered | **Met** — §11, §12, §13 |
| Implementation can proceed without inventing policy | **Met after Amendment A1** — §9 |
| Governance authority permits this phase to freeze | **NOT met** — §3 |

The document's status is therefore `PROPOSED — RECOMMENDED FOR ACCEPTANCE`, not
`Frozen`. Outcome A is unavailable for the single reason stated in the last row:
freeze authority rests with the owner, not with this gate.

*Subsequent status: the owner recorded acceptance on 2026-07-26 —
`ACCEPTED — OWNER APPROVED`. Freeze was not exercised and ECC-01 remains not
formally frozen; see [`ECC-01_FORMAL_OWNER_ACCEPTANCE.md`](ECC-01_FORMAL_OWNER_ACCEPTANCE.md) §11.*

---

## 5. ADR-C01 Conformity Matrix

| # | ADR-C01 decision | ECC-01 treatment | Verdict |
| ---: | --- | --- | --- |
| 1 | Dual chronology; accepted ≠ economic (§3.1, §3.4, §5.3) | P-07, §4.1, §6.7(1), W3/W4 | Conforms |
| 2 | Economic chronology is costing authority (§3.4) | P-03, §5.7(2), §7–§9 | Conforms |
| 3 | Ten-component hierarchy in frozen order (§6.3) | E1–E10 in identical order and meaning; §4.4 justifies each position | Conforms — no reordering, no substitution |
| 4 | Same-time effect ranks 10/20/30/40/50 (§6.4) | E3, ranks reproduced verbatim | Conforms |
| 5 | Correction placement immediately after target (§6.5) | Anchoring rule §4.4 + X1–X4; achieved by key construction | Conforms — and is a stronger construction than a special-case insertion |
| 6 | Reversal is an independent event at its own instant (§6.5) | Placement class `independent`, C4 | Conforms |
| 7 | Correction fork fails closed (§6.5) | V-19, F-08, C3 | Conforms |
| 8 | Missing/duplicate key handling (§6.6) | V-14, V-16, F-01/F-03/F-06/F-07 | Conforms |
| 9 | Lock/commit/arrival order has no ECC authority (§7) | §2.2 prohibition list, V-02, F-04, Theorem 2 | Conforms — the prohibition list is broader than the ADR's, which is a permitted strengthening |
| 10 | Pending-costing is retriable, never a permanent rejection for losing a race (§7.8) | F-14 and its explicit second governing rule | Conforms |
| 11 | FIFO consequences (§8.1–§8.11) | §7 F1–F6; §10.5 derives ADR §8.5 from tuple shape | Conforms |
| 12 | Moving WAC consequences (§9.1–§9.10) | §8 W1–W4; §8.1 proves ADR §9.3's permutation claim | Conforms — proves what the ADR asserted |
| 13 | Specific-ID: identity precedes chronology (§10) | §9 S1–S4; ordering explicitly powerless over identity | Conforms |
| 14 | Replay boundary, population, determinism, late events (§11) | §3.4, §5.4, §6.2–§6.7, R-01…R-10 | Conforms after ECC-A-02/04/06 |
| 15 | Dual cut-off (§12.4) | §3.4 bounds + watermark; inclusivity now explicit | Conforms after ECC-A-02 |
| 16 | Posting boundary unchanged (§13) | §2.3, §5.7(2), §15(12) | Conforms |

**Policy added beyond ADR authorization:** none found. The three placement
classes (`anchored` / `independent` / `counterfactual_only`) look like new policy
but are derivations of ADR-C01 §6.5 (open-period correction, reversal) and §12.2
(closed-period counterfactual) respectively.

**ADR requirement left undefined by ECC-01:** none remaining. Before Amendment
A1, ADR-C01 §11.2's "at or before the declared economic cut-off" had no
corresponding inclusivity rule in ECC-01 (ECC-A-02).

**One deliberate narrowing, recorded:** ADR-C01 §11.2 permits population
exclusion "by a governed supersession/correction interpretation"; ECC-01 §5.4(2)
excludes nothing and handles supersession in the fold. The narrowing is
strictly safer (both facts stay visible) and consistent with ADR-C01 §11.2's own
final sentence. Not a defect.

---

## 6. ECC Input Completeness Review

All fourteen attributes required by the review scope are present for every
component; §4.2 and §4.3 use a fixed contract table (Purpose / Owner / Data
source / Authority / Nullable / Versioned / Immutable / Validation / Failure).
Nullability is eliminated by construction (P-04, N-08), which removes the null-
ordering argument entirely — a good decision, since a null convention is itself
a hidden ordering policy.

**Hidden-authority census.** Each prohibited source in the review scope was
traced against §2.2 and against every component's declared data source:

| Prohibited source | Prohibited by | Reachable through any component? |
| --- | --- | --- |
| Auto-increment / sequence / per-scope accepted sequence | §2.2 bullet 3 | No — and §14.1 names IA-5's as the defect to correct |
| UUID generation order / admission-default UUID | §2.2 bullet 6 | No |
| Insert, commit, transaction, snapshot order | §2.2 bullets 1, 5 | No |
| Lock acquisition / advisory-lock outcome | §2.2 bullet 2 | No — §6.9(4) confines locks to deadlock avoidance |
| Physical row order, page order, plan order | §2.2 bullet 5 | No |
| Worker/parallel execution order | Theorem 1 (no residual tie) | No |
| Clock resolution accidents | §2.2 bullet 4, N-01 | No — coarse source precision widens cohorts, it does not fabricate order |
| Unspecified source-document ordering | E5 + V-06 (exactly one registry algorithm) | No |
| Unspecified line ordering | E6 + V-07 | No — but the derived-allocation case was ambiguous (ECC-A-08, resolved) |
| Unspecified event-effect ordering | E9 + V-13 | No — but plan purity was unstated (ECC-A-03, resolved) |
| Locale/environment collation | N-04, V-04 | No — byte comparison is mandated |

Two components required scrutiny because they are not pure source evidence:

- **E2 (causal depth)** is derived, but from the declared edge set alone, by a
  longest-path definition that is traversal-independent. Verified as a function
  of the edge set, and Lemma 1's invariance argument is sound.
- **E9 (event ordinal)** is Inventory-assigned. This was the one genuine hole:
  nothing required the occurrence event plan to be a pure function of the
  payload. Closed by ECC-A-03.

---

## 7. ECC Ordering Tuple Review

Fourteen components confirmed by inspection: E1–E10 (ADR §6.3, unchanged order)
plus X1–X4 (ADR §6.5 anchoring). The count is correct, and more importantly the
*composition* is correct — the extension block is not a fifteenth-through-
eighteenth tie-break bolted onto the primary block; it is only ever reachable
between a target and its own correction chain (§4.4).

| Property | Result |
| --- | --- |
| Complete | Yes — every ADR §6.3 component present, none added |
| Comprehensible | Yes — §4.4's position-by-position justification is the strongest section of the document |
| Expressive | Yes — resolves instant, causality, convention, source class, document, line, transition, occurrence, effect, identity |
| Lexicographic and deterministic | Yes — §4.5 |
| Total within scope | Yes, conditional on V-14; correctly stated as conditional |
| Stable under replay | Yes — P-05, Theorem 3 |
| Stable under concurrency | Yes — Theorem 2 (after ECC-A-03 closes its E9 premise) |
| Versioned | Yes — per-component "Versioned?" row, aggregated into `V` |
| Free of circular dependency | Yes — anchoring resolves to a depth-0 root; V-22 forbids cycles |
| Free of DB-assigned authority | Yes — §6 census |
| Correct precedence | Yes — see below |

**Precedence spot-checks.** The two positions that could plausibly be wrong are
both right: E2 above E3 (genuine causality must outrank the increase-before-
decrease convention, or a real dependency could be inverted by a convention),
and E3 above E4/E5 (otherwise a receipt could be pushed behind a same-instant
issue merely by carrying a later document number — which would reintroduce the
C-01 divergence through the front door).

**Collision analysis — a finding the document should own.** Given V-05 (source-
type ranks unique per policy version), V-06 (document order key unique per
document), and V-07 (line/occurrence/event ordinals unique at their grain),
equality through E9 forces equality of the E10 composite as ECC-01 defines it
(source type, document identity, line identity, transition, occurrence ordinal,
event ordinal). **E10 can therefore never legitimately decide an order.** Any
comparison that reaches E10 with unequal values means the registry's E10
composite carries a discriminator absent from E1–E9; any comparison that reaches
E10 with equal values is F-06. E10 is a correct and cheap safety net, but it is
redundant by construction rather than load-bearing. Recorded as ECC-A-15
(Informational) with a registry design consequence, not as a defect.

---

## 8. Total-Order and Determinism Review

§4.5 defines the standard lexicographic comparator; §6.2 proves unique
enumeration. Each required property was checked rather than accepted:

| Property | Basis | Verdict |
| --- | --- | --- |
| Irreflexivity | No index `i` can satisfy `comp_i(a) < comp_i(a)` | Holds |
| Asymmetry | Follows from per-component total orders at the first differing index | Holds |
| Transitivity | Standard lexicographic argument over per-component total orders | Holds; each component's domain is declared totally ordered (N-04/N-06/N-07 supply byte and numeric orders) |
| Totality | Requires V-14; ECC-01 states the dependency explicitly rather than asserting uniqueness | Holds **conditionally and honestly** |
| Equality handling | V-15/F-06: equal keys are an error path, never a stable-sort fallback | Holds — and §14.2(4) names the exact failure mode a stable sort would hide |
| Collision prevention | V-14 at admission (stage 3) and population (stage 4) | Holds |
| Tie-break completeness | No component may be skipped; no fallback exists | Holds |
| Replay stability | Theorem 3 + P-05 | Holds |

Theorem 1's proof is valid (minimal-differing-index contradiction). Theorem 2's
proof is valid **given** its trichotomy premise — that every component is
pre-admission evidence, a policy-version rank, or cohort causal depth. E9 sat
outside that trichotomy until ECC-A-03; the premise is now enforced by V-32
rather than assumed. Lemma 1 and Theorems 3 and 4 are valid, and Theorem 4's
consequence paragraph is unusually disciplined: it states that the proof holds
only if the implementation's fold is genuinely pure, and keeps the ADR's
mandatory full-rebuild comparison as the test of that premise instead of
retiring it as redundant.

The document does not accept "the tuple is unique" without conditions. That is
the single most important thing this section had to check, and it passes.

---

## 9. Derivation Algorithm Review

Eight stages: partition resolution, component resolution and normalization,
admission validation, population selection, causal validation and cohort
ranking, total ordering, fold and fingerprint, certification and promotion. All
twelve elements the review scope requires are present, and stages 1–3 are
correctly separated from 4–8 (admission-time versus replay-time), which is what
makes P-06's "resolve at admission" enforceable.

**Two-independent-teams test.** Applied to each stage. Before Amendment A1,
three stages would have required architectural interpretation:

- Stage 4 — "lies within the declared economic start and end keys": inclusivity
  undefined, bound-key completeness undefined, and cohort truncation unaddressed
  (ECC-A-02, ECC-A-04).
- Stage 2 — E9 resolution: plan purity unstated (ECC-A-03).
- Stage 2/4 — mixed version vectors after a policy change: the re-resolution
  protocol was named in §3.2 but had no defined invariants and no stage
  (ECC-A-05).

After Amendment A1, each stage resolves to one behaviour. Remaining
implementation freedom is confined to encoding choices that N-05 makes
observationally equivalent, and to the registry's per-source-type rules, which
are themselves versioned, governed artifacts — correctly outside a derivation
specification.

The §5.9 worked trace (three events, deciding component recorded per adjacent
pair) is the right minimum audit form and satisfies ADR-C01 §3.4's drill-through
requirement.

---

## 10. Replay Review

All thirteen replay elements required by the review scope are defined: input
set, scope, cut-offs, order-policy version, method version, precision, UOM,
source identity, corrections, fingerprint authority, output identity, conflict
behaviour, failure behaviour.

**The required property** — identical accepted events, source identities, policy
versions, normalization versions, valuation scope, and both cut-offs ⟹ identical
ECC and costing sequence — **holds**, via Theorem 2 (key invariance) and Theorem
1 (unique enumeration), with the fold's purity carried by Theorem 4.

Three assumption gaps were found and closed:

1. **Bound semantics** (ECC-A-02): inclusivity and bound-key completeness were
   undefined. An anchored correction shares its target's entire primary block,
   so a bound expressed as a primary block alone cannot say which side of the
   boundary the correction falls on. Bounds are now complete fourteen-component
   keys, closed interval.
2. **Population truncation** (ECC-A-04): a start bound could exclude a cohort
   member, which would recompute E2 depth over a restricted edge set and could
   reorder *included* events. Now prohibited by §5.4(5)/V-31. The asymmetry is
   deliberate and justified: within a cohort a predecessor always has strictly
   lower causal depth and therefore always sorts before its dependent, so an
   *end* bound can never orphan a predecessor, while a *start* bound can.
3. **Watermark portability** (ECC-A-06): ADR-C01 §3.1 permits two environments to
   assign different accepted positions to the same facts, so "replay through
   watermark *n*" does not name the same population in two databases. Every
   cross-environment equality claim (V-29, F-15, the §6.3 corollary) is now
   stated over the complete admitted fact set.

Late-event handling (§6.7) is correct and includes the point most
implementations get wrong, stated plainly: *a late event is not necessarily a
later event*, and lateness is a fact about accepted chronology only (W4).

---

## 11. FIFO Review

Six worked cases (F1–F6). Coverage against the required matrix:

| Required case | Covered | Deciding component |
| --- | --- | --- |
| Same-day / same-timestamp receipts | F2 | E5 |
| Multiple source documents | F2 | E4 then E5 |
| Multiple lines in one document | F3 | E6 |
| Multiple effects from one line | F4, F5 | E8, E9 |
| Receipt before issue | F1 | E3 |
| Issue before later-entered backdated receipt | B1 | E1 |
| Corrections | C1, F4 | anchoring + X1 |
| Reversals | C4 | independent key |
| Transfers | F5 | cross-partition dependency, §6.9 |
| Concurrent admission | F1, F2 | Theorem 2 |
| Accepted-through cut-off | §6.7, B3 | watermark |
| Economic-as-of cut-off | §3.4, B4 | end bound |

Layer order derives from economic authority throughout; §7.1's table shows
identical results under both submission orders, which is precisely the
divergence the evidence gate demonstrated. F4 is the strongest case in the
document: it takes an example where aggregate quantity and value are equal under
either order — the situation a reviewer would wave through as immaterial — and
shows that a later landed-cost correction anchored to occurrence 1 makes the
whole 40.00 either expensed or capitalized depending on order.

**Normative-versus-illustrative check.** Every example names its deciding
component and derives it from the tuple, so each demonstrates the normative
result rather than one implementation path. The ranks used (200/220/300/400/
410/420) are explicitly labelled "illustrative policy version" and are not
mistakable for frozen values.

---

## 12. Moving WAC Review

Four cases (W1–W4) plus B1/W3 backdating. Sequence handling verified for
receipts, issues, cost adjustments, corrections, reversals, backdated events,
same-moment events, multiple effects, and version changes.

Independent recomputation of every W-series and C-series figure: exact (§20.2).

The most valuable passage is §8.1's two-part treatment. It proves that permuting
an equal-instant inbound group cannot change the following issue's cost — exact
fixed-point addition is commutative and associative with no intermediate
rounding — and then refuses to conclude that the order may therefore be
arbitrary, because the **pool version chain** is fingerprinted audit evidence and
would differ. That is the correct distinction: commutativity of an aggregate is
not permission for a nondeterministic certified history.

Precision and rounding: explicit (quantity scale 2, valuation 8 decimals,
derived rates 12, GL basis 2), with issues costed from the authoritative extended
pool value and never from a rounded unit rate (W1, ADR §9.4). Re-cost is
separated from re-order by §3.2's policy-family split, and after ECC-A-09 a
dependency-of-record change must produce a successor version with an *identical*
ordered-input fingerprint and a different method-state fingerprint — which makes
the separation testable rather than merely asserted. After ECC-A-05, an
order-policy change cannot silently reuse a stale calculation, because the mixed
version state fails closed under F-11 until an authorized re-resolution runs.

---

## 13. Specific-ID Review

Genuinely specified, not merely mentioned. The governing idea is stated three
times in different forms and never violated: **ordering is not permission, and
chronology cannot create identity.**

| Concern | Treatment | Class |
| --- | --- | --- |
| Physical identity / lot / serial | S1, S2; identity supplies cost, ECC does not | Allocation |
| Identity assignment | S2 — requires an eligible owned receipt in the population | Eligibility |
| Identity transfer | F5, ADR §10.4 — ancestry and carrying value preserved | Ordering + allocation |
| Identity correction | ADR §10.6 via anchored corrections | Ordering |
| Identity conflict / duplicate | S3 — first application consumes, second is rejected | Eligibility |
| Missing identity | S2 — reject economic application | Eligibility |
| Partial lot occurrences | S4 — E8 decides, residual destination follows | Ordering |
| Reversal, backdating, replay | C4, §10, §6 | Ordering |

S4 deserves note: three equal partial issues of a 3-unit lot total 100.00 under
any order, but the order decides which project absorbs the 33.33333334 residual
and which allocation is the closing one. "Same total" is correctly rejected as a
defence for nondeterministic order in a system whose reconciliation contract
treats residuals as evidence rather than tolerance.

The one gap — §13's failure table contained no row for physical-identity
conflict, leaving a reader to wonder whether F-06 was meant to cover it — was an
under-specified boundary rather than a wrong rule. Closed by ECC-A-10: identity
failures are eligibility failures evaluated in ECC order at stage 7, explicitly
not ordering failures, and F-06 concerns duplicate *logical order* identity only.

---

## 14. Backdating and Correction Review

**Time distinctions.** All eight required distinctions are present and kept
apart: business-effective (E1), acceptance (accepted chronology / watermark),
replay (version), correction business time (X2), correction approval time (X3),
document date (source evidence), accounting date and Posting watermark (§2.3
Period boundary — explicitly not ECC's), economic cut-off and accepted-through
cut-off (§3.4).

Backdated acceptance alters economic chronology without rewriting accepted
history (W3: accepted position 5, ECC position 2, both permanent). Stale
projections, affected replay range, version selection, and supersession of
published outputs are governed by §6.7 and §10.3; closed periods route to
`counterfactual_only` (§6.8, B4), where ECC measures and never selects the
accounting treatment. B5 is a good structural result: backdating cannot fabricate
FIFO eligibility because E1 dominates and V-05 rejects contradicting causal
edges — the consequence falls out of the tuple's shape instead of relying on a
separate rule someone could forget.

**The anchoring rule** was examined most carefully, since it is the one place
ECC-01 could have invented policy.

| Test | Result |
| --- | --- |
| Authorized by ADR-C01? | Yes — §6.5 "evaluated immediately after the corrected target fact" |
| Internally consistent? | Yes — inheriting the root target's E1–E10 and discriminating by X1–X4 achieves ADR §6.5 by construction |
| Non-circular? | Yes — chains resolve to a depth-0 root; V-22 forbids cycles |
| Deterministic? | Yes — X1 then X2/X3/X4, total via X4 |
| Replay-safe? | Yes — Theorem 3 |
| FIFO / WAC / Specific-ID compatible? | Yes — C1, C2, and ADR §10.6 |
| Multiple corrections, corrections of corrections? | Yes — C2, chain depth |
| Partial corrections? | Yes — anchored at target, delta computed by replay |
| Forks? | **Fails closed** — V-19, C3; ordering by X2/X3/X4 is permitted only where a registered commutativity proof exists |
| Reversals? | Correctly *not* anchored — C4 gives the reason: an anchored reversal would silently claim its target's instant and misstate the reversal's period |
| Late acceptance? | Yes — §6.7, W4 |

"Correction", "reversal", "replacement/supersession", and "new economic event"
are distinguished by placement class plus registry semantics, and each maps to a
different key construction. A correction that changes past economic meaning is
governed: it is confined to open periods, produces a successor version, retains
every prior version, and in closed periods is demoted to a non-certifying
counterfactual.

---

## 15. Concurrency Review

The claim that different PostgreSQL schedules produce the same ECC is
**substantiated, not asserted**. Theorem 2 is a construction argument over the
component set, not a claim about locking — which is the right shape, since
locking protects integrity without defining chronology.

Independence verified against every schedule-sensitive input in the review
scope: transaction start order, lock acquisition, commit order, sequence
allocation, worker order, statement interleaving, query plan, physical storage,
replication timing, retry timing. Each is either in §2.2's prohibition list or
unreachable from any component's declared data source.

**The admission-allocation question**, which the review scope singles out, was
the decisive check. Three candidates:

| Candidate | Allocated at admission? | Disposition |
| --- | --- | --- |
| IA-5 per-scope accepted sequence | Yes, by row lock | Excluded from ECC authority; retained as accepted-chronology evidence (§14.1, §15(2)) |
| E9 event ordinal | Yes, by Inventory | Now required to be a pure function of payload + registry version (ECC-A-03, V-32) — deterministically derived before schedule-sensitive execution |
| E10 source identity | No — pre-admission, and explicitly "**not** database-generated at admission" | Governed by valid pre-admission authority |

That is the full set, and each resolves into one of the three dispositions the
review scope permits. §14.1's honesty about IA-5 is notable: it states plainly
that the implemented index "is an Accepted Event Chronology index, not an ECC
index".

F-14 deserves credit for a subtlety the ADR insisted on and a weaker
specification would have dropped: an issue admitted before a receipt it may
depend on gets a **non-final retriable** result that consumes no logical
identity — it is never permanently rejected merely for losing a race.

---

## 16. Version and Policy Governance Review

| Version | Governed by | May reorder? |
| --- | --- | --- |
| Event-order policy | §3.2 family 1 | Yes |
| Event Source Registry (per source type) | §3.2 family 2 | Yes |
| Valuation-scope resolution | §3.2 family 3 | Repartitions only, never reorders within a partition |
| Correction-graph | §3.2 family 4 | Yes |
| Canonical form (incl. digest identity after ECC-A-07) | §3.3 | Yes, via encoding |
| Costing method / cost formula | Dependency of record | No |
| Precision, rounding | Dependency of record | No |
| UOM normalization | Dependency of record | No |
| Negative-inventory, period, accounting profile | Dependency of record | No |
| Replay algorithm | §3.4 boundary | No — implementation identity, distinct from the policy it executes |

The four-versus-six split between "can reorder" and "dependency of record" is
the document's central governance contribution and is correctly enforced: only
four families appear in `V`, and only `V` gates comparability.

Resolved gaps: fingerprint/digest algorithm identity was referenced as
"versioned" without an owning family (ECC-A-07 — now the canonical form
version); the re-resolution protocol was named without invariants (ECC-A-05 —
now four invariants, with implicit re-resolution prohibited); dependency-of-
record changes had no stated version consequence (ECC-A-09 — now a successor
version with an identical ordered-input fingerprint).

Versions are immutable once used (P-05, P-06, V-12) and every event retains its
resolving versions, so an unavailable historical version cannot silently degrade
into a current-version re-derivation — the failure is F-11, fail-closed.
Effective-dated versions cannot split a valuation stream: §5.1(4) and V-11 fix
the partition to the scope **key**, and §15(4) identifies IA-5's scope-*version*
keying as a conformance gap to correct.

---

## 17. Cut-Off Authority Review

The dual model is complete: economic-as-of (an ECC end key) and accepted-through
(an admission watermark) are separate authorities with separate owners and
separate failure behaviour.

| Required element | Status |
| --- | --- |
| Exact inclusion predicate | Defined after ECC-A-02 |
| Boundary inclusivity | **Both bounds inclusive**; closed interval `[start, end]` under `≺` |
| Bound expression | Complete fourteen-component keys; a date alone, or a primary block alone, is invalid |
| Time-zone treatment | N-01 — UTC, unambiguous offset required, ambiguous local time rejected |
| Date-only normalization | N-02 — no silent midnight; a date-only source needs a registry-declared instant construction |
| Timestamp precision | N-01 — microsecond internal, source precision retained |
| Event accepted exactly at the cut-off | Included (watermark inclusive) |
| Event economically effective exactly at the cut-off | Included (end bound inclusive, from ADR §11.2) |
| Corrections accepted after the cut-off | Excluded from that version; successor version; prior version citable with disclosed exception |
| Backdated events accepted after the cut-off | Same treatment; §6.7 |
| Policy selection at the cut-off | Boundary declares `V`; events resolved incompatibly fail closed (F-11) |
| Reproducibility under identical cut-offs | Theorem 1 + Theorem 2 |

**Final inclusion rule, unambiguous:** an event is in the population if and only
if it belongs to the declared company and valuation-scope key, was admitted at
or before the accepted-through watermark, has an ECC sort key `k` with
`start ⪯ k ⪯ end` under `≺`, and resolves to a version vector compatible with
the boundary's `V` — with the start bound additionally constrained by §5.4(5)
not to truncate a cohort, a declared predecessor, or an anchored correction's
root target.

---

## 18. Failure Behavior Review

Fifteen failure rules, each with trigger, decision, blast radius, retriability,
and retained evidence — a better structure than a flat error list, because blast
radius and retriability are exactly what an implementer would otherwise invent.

All twenty ambiguity classes in the review scope map to a defined behaviour:
missing/duplicate source order → F-03/F-06; missing/duplicate line ordinal →
F-03/F-06; missing transition rank → F-03; unknown source or event type →
F-02; missing policy version → F-11; invalid correction target → F-09;
correction cycle → F-05/V-22; invalid physical identity → eligibility rejection
in ECC order (ECC-A-10); duplicate canonical identity → F-06; fingerprint
mismatch → F-12; non-total collision → F-06 via V-15; unsupported historical
version → F-11; invalid cut-off → V-23/V-31; cross-scope contamination →
F-13/P-02; invalid UOM normalization → dependency of record, rejected at
resolution; arithmetic overflow and precision incompatibility → N-09 fixed-point
with the precision policy as a dependency of record.

Two governing rules close the section, and both are correct and load-bearing:
**no failure is ever resolved by choosing an order**, and **F-14 is not a
rejection**. There is no fallback tie-break anywhere in the specification. F-04
is the sharpest rule in the document — detecting a prohibited derivation input
rejects *the implementation as non-conformant*, with a blast radius of "the
engine, not one event", and is explicitly not retriable.

---

## 19. Posting and Kernel Boundary Review

| Prohibited action | Present in ECC-01? |
| --- | --- |
| Posts journals / mutates journal records | No — §2.3, §15(12) |
| Replaces the Posting Engine | No |
| Defines GL accounts | No — §2.3 defers to COA resolution |
| Defines tax behaviour | No — §2.3 "Tax determination is not an ECC input" |
| Redesigns the Kernel | No |
| Introduces a journal writer | No — §15(12) forbids touching the six sanctioned persistence functions or the totality guard |
| Authorizes IA-6 | No — §1, §14, §15(14) |
| Implements projections / allocation / costing persistence | No — §5.7(2) supplies order only; formulas remain the frozen Costing Specification's |
| Creates runtime behaviour in this phase | No — header Implementation Status; verified by `git status` |

§14 ("Implementation Notes — Non-binding") and §15 ("Future Migration
Implications") are correctly fenced: §14 opens with "Nothing in this section
authorizes work" and §15 with "This section states implications only." §15 does
use mandatory verbs about a future phase's obligations; that is prescription
about conformance, not authorization to act, and every item stays inside
Inventory's own boundary. Recorded as ECC-A-17 (Informational), no change made.

---

## 20. Adversarial Case Results

### 20.1 Required cases

Applicable authority, derived result, and controlling rule for each. "Order
changes" means relative economic order of already-ordered events changes.

| # | Case | Authority | Derived ECC result | Order changes | Replay | Expected failure | Controlling rule |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1 | Two equal-instant receipts, opposite schedules | E5 | `GR-0000007 ≺ GR-0000012` in both schedules | No | No | None | §4.5, Theorem 2, F2 |
| 2 | One document, DB insert order ≠ line order | E6 | line 1 ≺ line 2 regardless of submission | No | No | None | E6, V-07, F3 |
| 3 | One line, multiple inventory effects | E9 | Event plan sequence; occurrence atomic | No | No | Whole occurrence rejected if any event fails | E9, V-13, V-32, F5 |
| 4 | Backdated receipt accepted after an issue | E1 | Receipt inserted before the issue; successor version from `K` | No — inserts only | **Yes**, from `K` | None (open period); `counterfactual_only` if closed | Theorem 3, §6.7, B1/W3 |
| 5 | Correction accepted after the accepted-through cut-off | Watermark | Outside that version; prior version citable with disclosed late-event exception | No | **Yes**, successor at a later watermark | None; fail closed where current certification is required | §3.4, §6.7(3), B3 |
| 6 | Correction of a correction | X1 | `e1, k1, k2, e2`; depth 1 then 2 on one anchor | No | **Yes** | None — non-branching chain needs no commutativity proof | §4.4, V-22, C2 |
| 7 | Equal on all components except the final tie-break | E10 | **Unreachable.** Equality through E9 forces equal E10 composites under V-05/V-06/V-07 | n/a | No | **F-06** duplicate logical order identity — both applications rejected, stream certification blocked | V-14, V-15, F-06, ECC-A-15 |
| 8 | Duplicate canonical identity | V-14 | No order produced | n/a | Rejected | **F-06**; retriable only after a source-registry correction | §4.2 E10, F-06 |
| 9 | Ordering-policy version change | `V` | Mixed-version partition is not replayable; order may change only through governed re-resolution | **Yes**, by authorized re-resolution only | **Yes**, successor with uniform `V` | **F-11** until re-resolution is authorized | §3.2, §3.3, V-17, V-35 |
| 10 | Precision-policy change (re-cost, no reorder) | Dependency of record | Identical ECC; identical ordered-input fingerprint; different method-state fingerprint | No | **Yes**, re-cost successor | None; a changed ordered-input fingerprint here is **F-12** | §3.2, ECC-A-09 |
| 11 | FIFO under concurrent admission | E3, E5 | `R1, R2, I1`; COGS 1,260.00; ending 1,040.00 in every schedule | No | No | None | Theorem 2, F1/F2 |
| 12 | Moving WAC under concurrent admission | E3, E5 | Pool 10/1,000 → 20/2,300 → issue 1,380.00 → 8/920; identical version chain | No | No | None; no deficit path | Theorem 2, W1/W2 |
| 13 | Specific-ID, duplicate physical identity | Eligibility, not ECC | ECC still orders the claimants; first consumes the identity | No | No | Second claim **rejected at stage 7**; not an ECC failure row | P-09, V-30, S3, ECC-A-10 |
| 14 | Same economic cut-off, later accepted-through | Watermark | Population may gain events with keys ≤ end; any key `< ` certified max forces a successor from `K` | No — inserts only | **Yes** | None | §6.7, Theorem 3 |
| 15 | Same accepted-through, earlier economic cut-off | End bound | Strict prefix of the same order; ordinals `1..M` identical to the larger version's first `M` | No | Prefix reuse legitimate | None — an end bound cannot orphan a predecessor | Theorem 4, §5.4(5) |

### 20.2 Independent arithmetic reconciliation

Every numeric example was recomputed from its stated inputs. All exact:

| Case | Check | Result |
| --- | --- | --- |
| F2 | 10 @ 100 + 2 @ 130 = 1,260.00; ending 8 @ 130 = 1,040.00; total 2,300.00 both sides; lock-order alternative 1,500.00/800.00, difference 240.00 | Exact |
| F3 | 450 + 190 = 640.00; ending 285.00; total 925.00 under both orders; misstatement 15.00 | Exact |
| F4 | Corrected layer 4.00 / 440.00 @ 110.00; issue 4 @ 110 + 1 @ 100 = 540.00 vs 500.00 inverted | Exact |
| F6 | 6 @ 145 + 1 @ 100 = 970.00; ending 3.00 / 300.00 | Exact |
| W1 | 12 × 2,300 / 20 = 1,380.00; pool 8.00 / 920.00; average 115.000000000000 | Exact |
| W3 | Deltas +80.00, +60.00, ending +1,260.00; `1,400.00 = 1,260.00 + 80.00 + 60.00` | Exact |
| B1 | 6 @ 40 + 4 @ 50 = 440.00; `240.00 = 300.00 − 60.00` | Exact |
| C1 | `150.00 = 90.00 + 60.00`; layer 1,150.00 @ 115.00 | Exact |
| C2 | 1,100.00 / 10 = 110.00; issue 660.00; ending 440.00; net `+100.00 = +60.00 + 40.00` | Exact |
| S4 | 33.33333333 × 2 + 33.33333334 = 100.00000000; GL basis 33.33 + 33.33 + 33.34 = 100.00 | Exact |

No arithmetic error, no rounding drift, and no example that reconciles only
under a favourable reading was found.

---

## 21. Blocking Findings

**None remain open.** Four findings would have blocked implementation had this
gate not been authorized to resolve them; all four are resolved in-document and
are recorded here in full for audit.

---

**Finding ID:** ECC-A-01
**Severity:** High
**Classification:** Documentation Governance
**Status:** Resolved in this phase
**Authority:** `PXL_PRINCIPLES.md` §21; `AGENT_SYSTEM_PROMPT.md` §"Findings and Documentation Governance"; gate report §13 RC-1 (which authorized freezing an ADR, not a derivation spec)
**Evidence:** ECC-01 header, pre-amendment: "**Status:** Frozen derivation specification under ADR-C01". No repository record of acceptance exists; `AI_STATE.md` recorded ECC-01 only as "authored 2026-07-26".
**Architectural Impact:** A self-declared freeze would make an unaccepted document cite itself as frozen authority and would let a future phase treat it as unchallengeable. The architecture content was unaffected.
**Required Resolution:** Status set to `PROPOSED — RECOMMENDED FOR ACCEPTANCE`, with freeze conditioned on recorded owner acceptance. **Applied.**
**Blocks Acceptance?:** No (resolved)
**Blocks Implementation?:** Yes while open — an unaccepted specification cannot govern hardening

---

**Finding ID:** ECC-A-02
**Severity:** High
**Classification:** Cut-Off / Determinism
**Status:** Resolved in this phase
**Authority:** ADR-C01 §11.2 ("at or before the declared economic cut-off"), §3.6, §12.4
**Evidence:** §5.4(1) pre-amendment: "whose ECC key lies within the declared economic start and end keys". Inclusivity undefined at both ends; §3.4 required "ECC keys, not dates" but never required a *complete* key. Because an anchored correction shares its target's entire E1–E10 block, a bound stated as a primary block cannot determine whether the correction is inside the population.
**Architectural Impact:** Two conforming implementations could select different populations at a boundary — different valuations, different fingerprints, from identical facts and identical declared cut-offs. This defeats the specification's central purpose.
**Required Resolution:** Bounds are complete fourteen-component keys; population is the closed interval `[start, end]`; end-inclusivity derived from ADR-C01 §11.2 and start-inclusivity from §3.6. Added to §3.4 and §5.4(1); testable as V-31. **Applied.**
**Blocks Acceptance?:** No (resolved)
**Blocks Implementation?:** Yes while open

---

**Finding ID:** ECC-A-03
**Severity:** High
**Classification:** Determinism / Concurrency
**Status:** Resolved in this phase
**Authority:** ECC-01 P-01, §2.2, V-02, Theorem 2's own premise
**Evidence:** E9's owner is "Inventory Engine, from the occurrence's declared event plan", and E10 composes the event ordinal. Nothing required that plan — how many Inventory effects an occurrence emits and in what sequence — to be a pure function of the occurrence payload. An implementation whose plan consulted current method state, available quantity, or admission-time master data would produce schedule-dependent E9 and E10 values while passing every stated rule.
**Architectural Impact:** Theorem 2's trichotomy (pre-admission evidence / policy rank / causal depth) did not cover E9, so the schedule-independence proof rested on an unstated premise. This is the same class of defect as C-01, entering through a component nobody would audit.
**Required Resolution:** Normative paragraph under E9 requiring the event plan to be a deterministic function of the occurrence's immutable payload and the registry rule at its declared version, and of nothing else; violation is F-04, not a data error. Testable as V-32. **Applied.**
**Blocks Acceptance?:** No (resolved)
**Blocks Implementation?:** Yes while open

---

**Finding ID:** ECC-A-04
**Severity:** High
**Classification:** Replay / Determinism
**Status:** Resolved in this phase
**Authority:** ECC-01 §4.2 (E2 depth over the cohort), Theorem 4, V-20
**Evidence:** §5.4 selects the population by key bounds, and §5.5(4) computes causal depth over cohort members **in the population**. A start bound falling inside an E1 cohort therefore removes edges from the depth computation and can change the depth — and so the order — of events that remain inside. §6.6 endorsed incremental replay without stating whether the saving applies to the ordering population or only to the fold; C5's example implied bounds do truncate.
**Architectural Impact:** A bounded or incremental replay could produce a different order for the same events than a full replay of the same partition — silently, since every stated rule would pass. It would also make Theorem 4's guarantee inapplicable to the very operation the theorem exists to license.
**Required Resolution:** §5.4(5) prohibits a start bound that truncates an E1 cohort, a declared predecessor, or an anchored correction's root target — widen or fail closed (F-05, F-09). §6.6 clarifies that incremental replay reuses the fold, never a shortened ordering population. The asymmetry with end bounds is justified in §10 of this report. Testable as V-31. **Applied.**
**Blocks Acceptance?:** No (resolved)
**Blocks Implementation?:** Yes while open

---

## 22. Non-Blocking Clarifications

Findings ECC-A-05 through ECC-A-10 were applied in this phase; ECC-A-11 requires
owner action; ECC-A-12 through ECC-A-14 are documentation reconciliation;
ECC-A-15 through ECC-A-17 are informational and no document was changed for
them.

**ECC-A-05 — Order re-resolution protocol undefined.** Medium; Version
Governance; Resolved. §3.2 named the protocol ("new version + governed order
re-resolution replay") but gave it no invariants and no algorithm stage, while
P-06 requires admission-time resolution and §14.2(1) forbids replay-time
re-derivation. A partition containing events resolved under two versions is not
replayable (F-11), so ordinary policy evolution would deadlock a scope with no
defined way out. Four invariants added to §3.3 — new immutable evidence under
the target version, prior resolution retained, re-derivation only from retained
source evidence, uniform `V` in the successor — plus an explicit prohibition on
implicit re-resolution triggered by a newer-version admission. V-35. *Blocks
acceptance: no. Blocks implementation: no — blocks the first policy change.*

**ECC-A-06 — Accepted-through watermark treated as portable.** Medium; Replay;
Resolved. ADR-C01 §3.1 permits different environments to assign different
accepted positions to identical facts, so a watermark value does not name the
same population across databases — yet V-29 and F-15 require cross-environment
fingerprint equality. §3.4 now states that a watermark is local to one accepted
chronology and that every cross-environment, cross-reset, or cross-schedule
equality claim is stated over the complete admitted fact set. V-34. *Blocks
acceptance: no. Blocks implementation: no — blocks certification-asset design.*

**ECC-A-07 — Fingerprint digest identity ungoverned.** Medium; Version
Governance; Resolved. §3.4 called the fingerprint "a versioned digest" and §5.7
referenced "the declared digest and version", but no policy family owned it and
it did not appear in `V`. Digest algorithm and version are now declared by the
canonical form version — the same authority governing the serialization being
digested — and a fingerprint without its digest identity is not replay
authority. *Blocks acceptance: no. Blocks implementation: no.*

**ECC-A-08 — Derived-allocation line ordinal ambiguous.** Medium; Determinism;
Resolved. E6's validation row said "a derived allocation orders after its parent
line" while N-07 restricts ordinals to positive integers compared numerically —
which cannot express "after line 3 but before line 4" without a synthetic
encoding, and different encodings yield different orders. §4.2 now requires a
derived allocation to carry its parent's E6 and to be ordered after the parent by
E2, E7, or E9 under the registry rule, per ADR-C01 §6.2, which places
line-before-allocation in the causal graph rather than in the ordinal domain.
V-33. *Blocks acceptance: no. Blocks implementation: no.*

**ECC-A-09 — Dependency-of-record change had no version consequence.** Low;
Version Governance; Resolved. §3.2 stated that such a change "changes calculated
amounts, never sequence" but did not say a successor replay version is required
or how a re-cost is distinguished from a re-order in evidence. Now: a successor
version whose ordered-input fingerprint is identical and whose method-state
fingerprint differs; a changed ordered-input fingerprint under such a change is
F-12. *Blocks acceptance: no. Blocks implementation: no.*

**ECC-A-10 — Ordering-versus-eligibility failure boundary unstated.** Low;
Specific-ID / Failure Behavior; Resolved. §13's fifteen rules are all ordering
failures, with no row for invalid, missing, or duplicated physical identity,
inviting a reader to stretch F-06 to cover it. A note now states that eligibility
failures are evaluated in ECC order at stage 7 and are explicitly not ECC failure
rows, and that F-06 concerns duplicate *logical order* identity only. *Blocks
acceptance: no. Blocks implementation: no.*

**ECC-A-11 — PG-01 cited as authority but absent from the repository.** High;
Documentation Governance; **Open — owner action required.** ADR-C01's header
("Architecture Authority under PG-01"), ADR-C01 §16 and §17(7), and ECC-01
§15(13) all invoke PG-01 or "PG-01 precedence". No such document exists; the
string appears only in those two files. The effective authority is determinable
(§3), so no action taken by this gate depends on the resolution, and ADR-C01 was
not edited because it is frozen and only a successor ADR may change it. Required
resolution: the owner either creates the PG-01 governance document defining
document authority, phase authority, program state, stop authority, and freeze
authority, or authorizes replacing the references with the existing authority
chain. *Blocks acceptance: no. Blocks implementation: no — but it must be settled
before any document relies on "PG-01 precedence" to resolve a conflict.*
*Subsequent status (2026-07-26): resolved by owner decision as Outcome B — the
existing accepted documents collectively embody PG-01, mapped non-normatively in
[`PG-01_GOVERNANCE_AUTHORITY_MAP.md`](../../00.%20Governance/PG-01_GOVERNANCE_AUTHORITY_MAP.md).
ADR-C01 was not edited; its citations are interpreted through that map.*

**ECC-A-12 — IA-5 evidence document contradicted the gate outcome.** High;
Documentation Governance; Resolved. `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_
EVIDENCE.md` declared "**Status:** Certified Complete" while the evidence gate
had returned Outcome C with C-01 Critical, and its §5 presented the lock-derived
index as "Economic order is:" and described the allocator as "a transaction
advisory lock" — which the gate's executable evidence disproved (§4.3: an
`UPDATE ... RETURNING` row lock). Status corrected to landed/dormant with
certification suspended; §5 relabelled as Accepted Event Chronology with the
supersession, the true mechanism, and the missing ECC components stated. No
implementation claim was strengthened. *Blocks acceptance: no. Blocks
implementation: no.*

**ECC-A-13 — Costing Specification §1 lacked its supersession pointer.** Medium;
Documentation Governance; Resolved. Gate RC-3 requires all frozen contracts to
describe one tuple; §1's sentence named "effective timestamp, governed sequence,
immutable event ID, and source-line order", which ADR-C01 §14 partly supersedes.
A supersession pointer to ADR-C01 §6.3/§14 and ECC-01 was added; the FIFO/WAC/
Specific-ID calculations were not touched. *Blocks acceptance: no.*

**ECC-A-14 — Documentation index did not register the chronology documents.**
Low; Documentation Governance; Resolved. ADR-C01, ECC-01, and the evidence gate
were unreachable from `PXL_DOCUMENTATION_INDEX.md`, and its Inventory row still
described IA-5 as "certified". Three rows added, IA-5 description corrected.
*Blocks acceptance: no.*

**ECC-A-15 — E10 is unreachable as a deciding component.** Informational;
Determinism; No change made. Under V-05, V-06, and V-07, equality through E9
forces equality of the E10 composite as §4.2 defines it, so E10 can only be
reached in the F-06 error path (§7 of this report). E10 remains correct as a
totality guarantee and should be kept. The design consequence for the Event
Source Registry: an E10 composite must not introduce a discriminator absent from
E1–E9, because a genuine business distinction decided by a component that
"carries no claimed economic meaning" is a distinction placed in the wrong
component.

**ECC-A-16 — E5's identity fallback carries no economic meaning.** Informational;
FIFO; No change made. E5 permits "the registry-declared canonical ordering of the
immutable source identifier" where no governed business sequence exists — ADR-C01
§6.3 authorizes this explicitly. But §7.2 shows E5 deciding a 240.00 profit
difference while arguing that E5 "must therefore be a governed source sequence".
Where the fallback is used, that materiality is settled by an arbitrary (though
deterministic and pre-admission) identity. Recommendation for the registry
phase, not a defect: prefer a governed sequence for every production-enabled
source type, and disclose fallback use in the ordering audit as a convention
rather than as business evidence.

**ECC-A-17 — §15 uses mandatory language in a non-binding section.**
Informational; Boundary; No change made. §15's items are prescriptions about what
a future conforming implementation must satisfy, not authorizations to act, and
all stay inside Inventory's boundary. The section's opening sentence and the
header's Implementation Status are sufficient fencing.

---

## 23. Documentation Reconciliation Performed

Documentation only. No code, SQL, schema, migration, RPC, function, trigger,
test, or runtime file was created or modified.

| File | Change |
| --- | --- |
| `ECC-01_..._DERIVATION_SPEC.md` | Status → `PROPOSED — RECOMMENDED FOR ACCEPTANCE`; Amendment A1 note; determinism clarifications for ECC-A-02 … ECC-A-10 in §3.2, §3.3, §3.4, §4.2 (E6, E9), §5.4, §6.6, §12, §13; five new validation rules V-31 … V-35 |
| `ECC-01_FINAL_ARCHITECTURE_ACCEPTANCE_REPORT.md` | Created — this report |
| `PXL_IA5_IMPLEMENTATION_AND_CERTIFICATION_EVIDENCE.md` | Status corrected from "Certified Complete" to landed/dormant with certification suspended; §5 ordering contract relabelled as Accepted Event Chronology, advisory-lock description corrected to the proven row-lock mechanism, missing ECC components named (ECC-A-12) |
| `PXL_INVENTORY_COSTING_SPEC.md` | §1 ordering sentence given its ADR-C01 §6.3/§14 supersession pointer (ECC-A-13); calculations untouched |
| `PXL_DOCUMENTATION_INDEX.md` | Three rows added for ADR-C01, ECC-01 + this report, and the evidence gate; Inventory row corrected (ECC-A-14) |
| `AI/AI_STATE.md` | Chronology paragraph and Recommended Next Task updated to this gate's outcome |

Not modified, deliberately: `ADR-C01` (frozen; only a successor ADR may change
it — ECC-A-11 is recorded rather than edited in place), the evidence gate report
and plan (historical evidence of a completed gate), IA-4 blueprints, and all
Posting/Kernel documents.

---

## 24. Authorized Next Phase

Subject to the owner recording acceptance of ECC-01, the next phase is:

**IA-5 ECONOMIC COSTING CHRONOLOGY HARDENING — IMPLEMENTATION DESIGN AND CHANGE
PLAN**

executed inside ADR-C01 §17's reopened evidence gate. It is design and
classification work: compare IA-5 against ADR-C01 and ECC-01, run the stopped
H-01…H-09 and M-01 assets plus the ECC permutation, concurrency, backdate,
correction, and FIFO/WAC consequence lanes, and classify the minimum additive
conforming correction. ECC-01 §14.3 lists the certification assets that phase
must run; §14.1 and §15 list the conformance gaps it must close.

That phase has **not** begun. No migration, SQL, schema, or test was created for
it here.

*Subsequent status (2026-07-26): the owner recorded acceptance; that design phase
completed as
[`IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md`](../04.%20Implementation/IA-5_ECC_HARDENING_IMPLEMENTATION_DESIGN_AND_CHANGE_PLAN.md);
and the next authorised phase is now **IA-5 ECC hardening implementation — Work
Package 1**, per
[`ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md`](../04.%20Implementation/ECC-01_OWNER_ACCEPTANCE_AND_IA-5_WP1_AUTHORISATION_REPORT.md).
IA-6 remains unauthorized and the C-01 stop remains open.*

If the owner declines acceptance, the next phase is instead a narrowly scoped
ECC-01 remediation addressing the returned items, and no hardening design may
begin.

**IA-6 remains unauthorized** regardless of this review. **The C-01 program stop
remains open** — ADR-C01 §16 requires executable proof of implementation
conformity, and this gate produced none and claims none. IA-5 remains dormant
and unmodified; P5.3B, P6, and P7 remain paused; hosted migration continues to
require explicit approval.

---

## 25. Final Certification Statement

ECC-01 is architecturally complete, conforms to ADR-C01, and defines a
deterministic Economic Costing Chronology suitable to govern future IA-5
hardening. ECC-01 is recommended for formal acceptance and freeze by the
authorized owner. No implementation may begin until that acceptance is recorded.
No implementation was performed during this phase.
