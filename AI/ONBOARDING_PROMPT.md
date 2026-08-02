# Onboarding prompt for a new AI coder

Copy everything in the fenced block below into a fresh session as your first
message. It is deliberately short: the repository already answers the questions,
so the prompt's job is only to point at the right five files and set the rules
that are easy to get wrong.

---

```text
You are joining the PXL project — an accounting-first, Philippine-compliance-first
ERP for multi-company SMEs. React 19 + TypeScript + Vite over Supabase/PostgreSQL,
where essentially all business logic lives in the database (420+ functions, 990+
triggers, 500+ RLS policies, 200+ tables).

Read these five files, in this order, and nothing else yet:

  1. AI/AGENT_SYSTEM_PROMPT.md                       — how to work here
  2. AI/AI_STATE.md                                  — THE ONLY STATUS AUTHORITY:
                                                       where we are, what is next
  3. docs/PXL/00. Governance/PXL_HOW_WE_WORK.md      — the build loop, the five
                                                       non-negotiables, the two
                                                       quality bars
  4. docs/PXL/01. Architecture/PXL_DELIVERY_PLAN.md  — the complete end-to-end
                                                       plan and current phase
  5. docs/PXL/01. Architecture/PXL_PRODUCT_ARCHITECTURE.md — what PXL is
                                                       (skim; it is long)

Then run the gates and believe their output over any prose:

  npm run docs:check
  npm run test:frontend
  npm run test:db:fresh
  npm run test:canonical
  npm run test:db:regression

Then do the task named in AI/AI_STATE.md under "## Recommended Next Task".

Rules that are easy to get wrong here:

- DO NOT verify anything using the existing canonical/demo seed data. It was
  produced during early development by logic that was not always correct and can
  encode the very defect you are testing for. Provision your own company, chart of
  accounts, masters and documents through the CURRENT production RPCs and prove
  the flow end to end. Reference example:
  supabase/tests/112_purchase_to_gl_fresh_data_e2e_test.sql

- DO NOT start with an audit. The audit ceremony was deliberately retired on
  2026-08-02 because it consumed the capacity that should have shipped product —
  eleven days once produced 12,614 lines of documentation and zero lines of code.
  Read the state, run the gates, fix what fails, build the next thing.

- DO NOT write status facts anywhere except AI/AI_STATE.md. A second copy always
  drifts and becomes a trap for the next session. Two former status files were
  deleted for exactly this.

- DO NOT create a governance document in a commit that contains no application or
  SQL change.

- DO NOT resume the IA-5 / ECC inventory chronology programme. It is frozen,
  dormant, and has no consumers. Inventory reconciles without it.

- When you would write an audit finding, write a guard test instead. A human
  audit is a claim about a moment; a test is a claim about every moment after.

Five things must stay true no matter what you build. A change that weakens any of
them is rejected regardless of what it delivers:

  1. One doorway to the ledger — the Accounting Kernel makes any other write
     impossible, not merely discouraged.
  2. Posted records are immutable — corrections are reversals and memos.
  3. Tenant isolation — RLS on every base table, default deny.
  4. Everything reconciles — each subledger ties to its control account, proven
     by a guard test in the regression lane.
  5. Philippine tax is correct — VAT, percentage tax and withholding reconcile to
     the General Ledger at zero variance.

Be blunt about what is broken. PXL is internal QA and demo only — not pilot-ready,
not production-ready — and saying so accurately is more useful than optimism.
```

---

## For a short session

When you only need a quick fix and not a full onboarding:

```text
Read AI/AI_STATE.md and docs/PXL/00. Governance/PXL_HOW_WE_WORK.md, then do the
task under "## Recommended Next Task".

Never verify using the canonical/demo seed — provision fresh data through the
current RPCs (see supabase/tests/112_purchase_to_gl_fresh_data_e2e_test.sql).
Do not start with an audit. Do not put status facts anywhere but AI/AI_STATE.md.
```

## Keeping this prompt true

The prompt names five files and five invariants. If any of them is renamed,
merged or retired, update this file in the same commit. It is the front door — a
stale front door costs every future session the time it was written to save.
