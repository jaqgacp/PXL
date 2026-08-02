# Deploy Runbook — bringing hosted up to date

**Status:** Active — the procedure for deploying schema changes to a hosted PXL database
**Authority:** Tier 1 Operations. Satisfies Delivery Plan Phase 2 item 6.
**Owner / Domain:** Operations
**Read When:** Deploying migrations to a hosted project, or assessing deploy risk
**Do Not Read For:** Recovery (`PXL_BACKUP_AND_RECOVERY_RUNBOOK.md`) or what to build next (`PXL_DELIVERY_PLAN.md`)
**Date:** 2026-08-02

---

## 1. Current position

| | |
| --- | --- |
| Hosted project | `bskjkogijpbhukjkagfj` |
| Hosted schema is at | `20260716000005` (121 migrations) |
| Local repository has | 173 migrations |
| **Pending deploy** | **52 migrations** |
| Deploy status | **Deliberately deferred** (see §2a). Also blocked on credentials. |

Every additional undeployed migration makes the eventual deploy larger and
harder to reason about. This gap should be closed as soon as credentials allow.

---

## 2. Why the deploy is blocked

`supabase projects list` returns:

```
LegacyPlatformAuthRequiredError: Access token not provided.
```

The project is linked (`supabase/.temp/linked-project.json`) but no access token
exists in the environment or CLI session. **This is deliberate.** Finding
`PXL-AUD-055` revoked previously exposed hosted credentials; nothing was left
behind for an agent to pick up.

**To unblock, the owner runs one of these themselves:**

```bash
supabase login                       # interactive, stores a CLI session
# or
export SUPABASE_ACCESS_TOKEN=…       # from Supabase dashboard → Account → Access Tokens
```

Never paste an access token into a chat transcript, a commit, or a file in this
repository. `scripts/check_frontend_secrets.mjs` guards the frontend bundle;
nothing guards a transcript.

---

## 2a. Decision: the deploy is deliberately deferred (2026-08-02)

**Nothing consumes the hosted database.** There is no pilot client, no user, and
no deployed frontend — CI runs gates only and deploys nothing. Local is the
source of truth for all development. Deploying now would buy parity for its own
sake and ship no capability to anyone.

**What deferring does not cost.** The deploy is de-risked and repeatable, not
postponed-and-forgotten: the change set is proven non-destructive, the upgrade is
rehearsed against a reproduction of the deployed schema, and
`npm run deploy:hosted` performs the whole guarded sequence whenever credentials
exist. None of that work expires.

**The one real risk of waiting.** A local rehearsal cannot detect
*hosted-specific* differences — extension availability, role definitions, grants,
or RLS behaving differently on the platform. Those surface only on a real deploy.
Discovering them with nothing at stake is cheap; discovering them during a pilot
cut-over is not.

**Trigger — deploy no later than the start of Delivery Plan Phase 6 (pilot
hardening).** Waiting past that point means the first hosted deploy in this
product's life happens while a real client is waiting, which is the one scenario
worth avoiding. A practice deploy at any earlier quiet moment is better still.

Until then, `npm run deploy:rehearse` should be re-run whenever migrations are
added, so the gap stays proven-safe rather than merely unexamined.

---

## 3. Deploy risk assessment — completed 2026-08-02

### 3.1 Destructive DDL scan

All 52 pending migrations were scanned. **The change set is purely additive:**

| Pattern | Occurrences | Assessment |
| --- | ---: | --- |
| `DROP TABLE` | 1 | `pg_temp.mdp15_pending_import` — a session-scoped temp table |
| `DROP COLUMN` | 0 | — |
| `ALTER COLUMN … TYPE` | 0 | — |
| `TRUNCATE` | 0 real | every hit is inside a `privilege_type IN (…)` grant census |
| `DELETE FROM` | 0 top-level | all occurrences are rollback paths inside function bodies |

**No pending migration destroys or rewrites existing data.**

### 3.2 Upgrade rehearsal

`npm run deploy:rehearse` reproduces the deploy exactly:

1. builds a database containing **only** the 121 migrations hosted already has;
2. applies all 52 pending migrations in order, timing each;
3. compares the upgraded database against a full fresh replay.

This matters because `npm run test:db:fresh` proves the chain replays *from
empty*, which is not the same claim. Production is not empty — it sits at an
older migration and must move forward without breaking.

**Result 2026-08-02 — PASS:**

```
baseline built: 148 public tables (at 20260716000005)
52 pending migrations applied, slowest 335 ms

upgraded-vs-fresh comparison
  tables 202 OK · views 23 OK · functions 422 OK
  triggers 610 OK · policies 509 OK · indexes 644 OK · columns 3490 OK

MEASURED UPGRADE WINDOW: 8s (schema only)
```

The upgraded database is structurally identical to a fresh replay across every
object class. **A migration that fails here would have failed in production.**

### 3.3 Two harness findings worth keeping

**Transaction semantics are not cosmetic.** The first rehearsal reported a
failure in `20260722000007_mdp03_master_data_access_sod.sql`. It was a false
alarm caused by the harness: that migration uses
`CREATE TEMP TABLE … ON COMMIT DROP`, and under `psql`'s default autocommit each
statement is its own transaction, so the temp table was destroyed the instant it
was created. `supabase db push` applies each migration in **one** transaction.
The rehearsal now does the same, except for the three migrations that open their
own `BEGIN`/`COMMIT` and must not be wrapped twice. **A deploy harness that does
not match the real transaction boundary produces both false alarms and false
confidence.**

**Extension objects distort object counts.** `CREATE EXTENSION IF NOT EXISTS
pgcrypto` without a schema places ~36 shim functions in `public` inside a
scratch database, while the real database keeps them in `extensions`. The
comparison excludes extension member objects, after confirming that the set of
functions present in the live database but missing from the rehearsal is
**empty**.

---

## 4. Deploy procedure

`scripts/deploy_hosted.sh` exists so the safety steps cannot be skipped under
time pressure. It refuses to push until it has read the remote migration
history, rehearsed the upgrade locally, taken a hosted backup, and shown you a
dry run.

```bash
# ONE-TIME: authenticate. Run these yourself; never send the values to anyone.
supabase login                          # stores a session in ~/.supabase
export SUPABASE_DB_PASSWORD='…'         # Dashboard -> Project Settings -> Database
export PXL_BACKUP_PASSPHRASE='…'        # optional, encrypts the hosted backup

# DRY RUN — takes a hosted backup, rehearses, shows the plan, pushes nothing
npm run deploy:hosted

# DEPLOY — same steps, then pushes
npm run deploy:hosted -- --execute
```

The script runs six stages: preflight credentials → remote migration list →
local rehearsal → **hosted backup (schema, data and roles, checksummed and
optionally encrypted)** → dry run → push → parity check. It aborts if the backup
is empty, because a deploy without a restorable backup is a gamble.

Backups land in `backups/hosted/`, which is git-ignored.

**Announce a maintenance window.** The measured schema upgrade is 8 seconds on an
empty database; on a populated one, index builds and constraint validation take
longer. Budget 15 minutes and take the application offline for it.

---

## 5. Rollback

The pending change set contains no destructive DDL, so the practical failure mode
is a migration that errors partway. `supabase db push` applies each migration in
a transaction, so a failing migration rolls itself back and leaves earlier ones
applied.

1. **Stop.** Do not re-run `db push` hoping it resolves itself.
2. Record which migration failed and the exact error.
3. If the schema is usable, fix forward: correct the migration, rehearse again,
   redeploy.
4. If the schema is not usable, restore from the pre-deploy backup taken in step 1
   using `PXL_BACKUP_AND_RECOVERY_RUNBOOK.md` §5.

**There is no supported "undo migration" path.** The pre-deploy backup is the
rollback plan, which is why step 1 is not optional.

---

## 6. What is proven and what is not

**Proven 2026-08-02:**
- The 52 pending migrations contain no destructive DDL.
- They apply cleanly to a reproduction of the currently deployed schema.
- The upgraded result is structurally identical to a fresh replay.
- The schema upgrade window is seconds, not minutes.

**Not proven:**
- Nothing has been executed against the hosted database. No credentials exist.
- The rehearsal covers **schema**, not data migration under production volume.
- No hosted backup has ever been taken or restored — §4 step 1 has never run.
- Hosted RLS, grants and roles have not been compared with local.

**The deploy is rehearsed, not performed.**
