# How We Work

**Status:** Active — the only process authority in this repository
**Authority:** Tier 1 Process. Replaces the certification-ceremony process retired on 2026-08-02.
**Applies To:** Every contributor, human or AI
**Read When:** Starting any session, deciding whether something is "done", or wondering whether a task is worth doing
**Do Not Read For:** What PXL is (Product Architecture), where we are (`AI/AI_STATE.md`), or what is broken (findings register)

---

## 1. The goal, in one sentence

**A Philippine business runs its real books on PXL.**

A valid business transaction produces the correct subsidiary ledger, General
Ledger, trial balance, financial statements, BIR tax and books effect, and audit
trail — with no parallel bookkeeping and nothing that can be quietly altered.

Everything below exists to get there. A task that does not move a real business
closer to running its books on PXL is not work, however sophisticated it is.

---

## 2. The loop

Four steps. Repeat until the product is finished.

```text
   ┌──────────────────────────────────────────────────────────────┐
   │  1. KNOW WHAT WE ARE BUILDING                                │
   │     Product Architecture (what PXL is)                       │
   │     Execution Roadmap    (what order)                        │
   └──────────────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  2. REVIEW WHERE WE ARE                                      │
   │     AI/AI_STATE.md — the only status authority               │
   │     Run the gates. Believe the output, not the prose.        │
   └──────────────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  3. BRUTAL FIX                                               │
   │     Find the real defect. Fix the cause, not the symptom.    │
   │     Write the guard test that makes it impossible again.     │
   └──────────────────────────────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────────────┐
   │  4. BUILD AND FINISH                                         │
   │     Ship the next capability. Update AI_STATE. Move on.      │
   └──────────────────────────────────────────────────────────────┘
```

**Step 3 happens once per defect, not once per week.** A brutal review that
produces a document instead of a fix has failed.

---

## 3. What we deleted, and why

PXL previously ran a certification programme with Brutal Audits, Authorisation
Gates, Evidence Gates, Certification Missions, Owner Acceptance Reports and
Engineering Amendments. It was rigorous, it produced four certified engines, and
it found two genuine Critical defects. It was also **the reason the product
stopped moving**:

- 26 completion criteria × 11 modules = **286 gates**, with zero modules past
  gate 3 after months of work.
- Eleven consecutive days produced **12,614 lines of documentation and zero lines
  of application code.**
- The programme's own highest-priority defect — a goods receipt that moved stock
  without a journal — sat unfixed for weeks while amendments were written about a
  dormant foundation that had no consumers. It took roughly **40 lines of SQL** to
  fix.

Retired on 2026-08-02: the module certification standard, the engine
certification standard, the product completeness checklist, and every gate,
amendment and acceptance ceremony that went with them.

**What replaced it is not "less rigour". It is rigour that executes.**

---

## 4. Audit ceremony out, automated invariants in

The distinction that matters:

| Retired — a human writes a document saying it is correct | Kept — the machine proves it on every run |
| --- | --- |
| Brutal Audit report | pgTAP regression, 128 files / 3,079 assertions |
| Evidence Gate report | Reconciliation guard tests (e.g. `111`) |
| Authorisation Gate | Kernel totality guard — a ledger write outside the doorway is impossible |
| Certification Mission | Coverage governance guard (`075`) |
| Owner Acceptance Report | RLS + immutability triggers, always on |
| Engineering Amendment | A migration, plus the test that locks its behaviour |

A human audit is a claim about a moment. A guard test is a claim about every
moment from now on. **When you would have written an audit finding, write a test
instead.**

This is why "cut the audits" does **not** weaken the product. The things that
actually keep PXL solid — the sealed posting doorway, the kernel guard, row-level
security, posted-record immutability, the reconciliation guards — are code, run
automatically, and none of them were touched.

---

## 5. Solid means these five things

Cutting process never cuts these. They are what makes the product trustworthy,
and each is enforced by code rather than by review:

1. **One doorway to the ledger.** Every journal is written by the six sanctioned
   persistence functions. The Accounting Kernel makes any other route impossible,
   not merely discouraged.
2. **Immutability.** A posted document is never edited or deleted. Corrections
   are reversals, voids, credit and debit memos. Database triggers enforce it.
3. **Tenant isolation.** Row-level security on every base table, default deny.
   One company cannot see another's books at the data layer.
4. **Everything reconciles.** Each subledger ties to its control account, proven
   by a guard test that runs in the regression lane. Currently 3 of 9 evidenced,
   all at 0.00.
5. **Correct Philippine tax.** VAT, percentage tax and withholding reconcile to
   the General Ledger at zero variance, from the same posted data the financial
   statements use.

**A change that weakens any of the five is rejected regardless of what it
delivers.** That is the one veto that survived the cut.

---

## 5a. Never verify against the existing demo data

**Do not use the canonical/demo seed as evidence that a workflow is correct.**
That data was produced during early development by logic and engines that were
not always right, so it can encode the very defect you are testing for.

This is not theoretical. The canonical opening journal for one demo company was
₱630 short of opening stock, because the seed valued "opening" inventory from a
live `stock_balances` snapshot taken *after* later seed blocks had already issued
stock. Anything measured against it would have confirmed a wrong number.

**How to verify instead.** Write a self-contained test that provisions its own
company, chart of accounts, fiscal calendar, masters and documents, and drives
the flow through the **current production RPCs** — the same functions the
application calls. `supabase/tests/112_purchase_to_gl_fresh_data_e2e_test.sql` is
the reference example.

That test earned its keep on its first run: it failed because `PURCHASE_CLEARING`
had been declared an `expense` key, inferred from the legacy demo chart. Goods
received not invoiced is properly a **liability**, so a correctly configured
company could not receive stock at all — while the legacy chart worked fine. The
canonical lane could never have caught it, because it only ever exercises the
legacy chart.

Use the canonical seed for regression and coverage sweeps. Never as proof of
correctness.

---

## 6. When is something done?

Two bars, both defined in the Execution Roadmap §9.4.

- **Pilot Bar (10 criteria)** — the operative gate now. Lifecycle works, posting
  is correct, it reconciles with a guard test, tax is right, permissions hold,
  audit trail is complete, period controls enforce, one canonical workflow is
  proven with real data, tests run in the regression lane, backup and restore are
  proven. A module passing all ten may run in a controlled pilot alongside a
  manual process.
- **Production Bar (26 criteria)** — after a pilot survives a quarter. The words
  *Certified*, *Complete* and *Production Ready* are reserved for it.

Never claim a bar the evidence does not support. "The screen exists" is not "the
workflow works" is not "it reconciles".

---

## 7. Rules that keep this from rotting

1. **Status lives in one place.** `AI/AI_STATE.md`. A second copy always drifts
   and becomes a trap. Two former root status files reported inventory as
   unreconciled after it was fixed; both were deleted.
2. **No governance-only commit during ordinary engineering.** A prose-only
   commit is allowed only for an explicit owner-directed repository finalization
   or Product Architecture Amendment, and it must change no runtime behavior.
3. **A defect that is known is a defect that is filed.** For weeks the register
   read "0 open defects" while the worst accounting defect in the product went
   unrecorded because nobody classified it as a finding. If it is broken, file it.
4. **Depth requires a consumer.** No foundation work without a caller in the same
   phase. This one rule would have prevented the entire dormant-inventory detour.
5. **Measure exercised capability, not surface.** Exercised posting entry points
   and evidenced reconciliations are real. Menu entries and route counts are not.
6. **Believe the database, not the document.** Executed behaviour outranks
   everything written here. Where they disagree, the document is the defect.

---

## 8. Starting a session

```bash
npm run docs:check        # documentation gates
npm run test:frontend     # frontend assertions
npm run test:db:fresh     # replay every migration on a clean database
npm run test:canonical    # seed and verify the canonical dataset
npm run test:db:regression # full pgTAP suite
```

Then read `AI/AI_STATE.md` §"Recommended Next Task" and do that.

If the gates pass and `AI_STATE` names a task, **start building**. Do not open a
review of the repository first. The review is this document, and it has already
happened.
