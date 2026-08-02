# Archive

Only two things live here, and both have a reason to exist. Everything else that
was once archived was **deleted on 2026-08-02** — retired process ceremony,
superseded specifications, stale status snapshots, and historical reports whose
only remaining job was to carry a disclaimer telling you not to read them.
Git history retains all of it; `git log --diff-filter=D --name-only` will find
anything you need.

## `ia5-ecc-frozen/`

Design authority for the **frozen** Inventory Accounting chronology programme.

Work packages WP-1…WP-4 were implemented and certified, and **their tables,
constraints and triggers are live in the database today** — dormant, with zero
consumers and zero rows. These documents are kept because a future contributor
who finds `inventory_events`, `inventory_event_order_keys` or the valuation
stream tables in the schema needs to know what they are and why they are empty.

Kept: the ADR that decided the chronology model, the derivation spec for the
order key, the accounting architecture and layer-lifecycle specs, and the
detailed WP-2…WP-5 specifications that describe the live objects.

Deleted: every authorisation report, evidence gate report, owner acceptance
report and engineering amendment. Those recorded permission to proceed, not what
was built.

**The programme is frozen.** Deterministic same-timestamp ordering is a scale and
audit-replay refinement, not a prerequisite for inventory correctness. Inventory
reconciles to its control account today under weighted-average valuation without
any of it. Do not resume WP-5…WP-9 or IA-6 without a demonstrated costing-replay
requirement.

## `v2-deferred/`

Module blueprints for scope deliberately cut from v1: Banking & Treasury, Fixed
Assets, Income Tax, Final Withholding Tax, and Accounting Schedules.

These are **build instructions, not history.** They are accurate, they were never
superseded, and they are where the work starts when v2 begins. The screens they
describe exist in the product and are marked **Not built** in the navigation by
`src/lib/deferredSurfaces.ts`.
