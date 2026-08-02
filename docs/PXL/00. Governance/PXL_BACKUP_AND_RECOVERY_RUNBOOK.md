# Backup and Recovery Runbook

**Status:** Active — the operational recovery procedure for PXL
**Authority:** Tier 1 Operations. Satisfies Delivery Plan Phase 2 and Pilot Bar criterion P10.
**Owner / Domain:** Operations
**Read When:** Setting up backups, restoring after data loss, or evidencing recoverability
**Do Not Read For:** Product status (`AI/AI_STATE.md`) or what to build next (`PXL_DELIVERY_PLAN.md`)
**Date:** 2026-08-02

---

## 1. Why this exists

Losing the books ends the product. A client whose General Ledger cannot be
recovered does not get a bug report — they get a legal problem with the BIR, who
require books of account to be preserved and producible on demand.

Until 2026-08-02 PXL had **no backup tooling of any kind**: no schedule, no
restore procedure, no successful restore test, no recovery objectives. It was the
single most consequential gap in the product that was not about accounting, and
it blocked every module from production readiness.

**A dump file that has never been restored is not a backup. It is a hope.**
This runbook therefore treats the *restore* as the deliverable and the dump as an
intermediate artifact.

---

## 2. Recovery objectives

| Objective | Value | Basis |
| --- | --- | --- |
| **RPO** — maximum acceptable data loss | **24 hours** at pilot scale, **1 hour** before a production claim | Daily dump for pilot; hourly requires WAL archiving or provider PITR, which is a hosting decision (PAD-007) |
| **RTO** — time to restore the books | **≤ 15 minutes** | Measured restore is **7–8 seconds** on a 38 MB database; the budget covers provisioning a host, fetching the archive and decrypting |
| **Retention** | 30 daily, 12 monthly, 7 annual | BIR requires books preserved for 10 years; annual archives carry that obligation |
| **Verification frequency** | Every backup is checksummed; **a full restore drill runs at least weekly** and before any release | A backup verified once is not a verified backup |

**Measured on 2026-08-02:** dump 1 s, archive 3.9 MB (custom format, compression
level 6), restore 7–8 s, full verification of 92 populated tables with zero
mismatches.

---

## 3. Taking a backup

```bash
npm run backup                      # writes to backups/
PXL_BACKUP_PASSPHRASE=… npm run backup   # AES-256-CBC, PBKDF2, 200k iterations
```

Each run produces three artifacts:

| Artifact | Purpose |
| --- | --- |
| `pxl-<timestamp>.dump` (or `.dump.enc`) | custom-format `pg_dump` of the whole database |
| `pxl-<timestamp>.dump.sha256` | content hash — a corrupted archive is detectable before you rely on it |
| `pxl-<timestamp>.manifest.json` | **what the database contained at dump time** |

The manifest is the point. It records schema object counts, the row count of
every populated table, and the financial totals — journal line count, total
debit, total credit, inventory value, audit log rows. Object counts prove the
schema survived; the financial totals prove **the books** survived.

`backups/` is git-ignored. Never commit a dump: it contains client books.

---

## 4. Verifying a backup — the part that matters

```bash
npm run backup:verify               # verifies the newest backup
npm run backup:drill                # backup + verify in one go
```

The verifier restores the archive into a throwaway database in the same cluster
and compares it against the manifest:

1. **Archive integrity** — SHA-256 must match, or it stops immediately.
2. **Schema objects** — tables, views, functions, triggers, policies, indexes.
3. **Every populated table** — exact row counts, all 92 of them.
4. **The books** — journal entries and lines, total debit, total credit,
   inventory value, audit log rows.
5. **Ledger integrity** — the restored trial balance must still be 0.00.

Any mismatch fails the run and prints exactly which measure diverged. The
throwaway database is dropped afterwards (`PXL_KEEP_RESTORE_DB=1` keeps it for
inspection).

**The verifier is not a rubber stamp.** It was tested against a deliberately
corrupted restore on 2026-08-02: dropping one function and deleting five rows
from `tax_calendar_events` produced `functions expected=422 got=421` and
`tax_calendar_events expected=248 got=243`, and the run failed. A verifier that
cannot fail proves nothing.

**A finding worth keeping.** During that corruption test, deleting rows from
`journal_entry_lines` in the *restored* database was rejected by the Accounting
Kernel:

```
Posting Engine totality: DELETE on journal_entry_lines did not originate
from a sanctioned kernel (writer: (direct SQL))
```

The restore preserves not only the data but the enforcement. A recovered database
is as tamper-proof as the original.

---

## 5. Restoring for real

When the production database is lost or corrupted:

1. **Stop writes.** Take the application offline so nothing posts into a
   database you are about to replace.
2. **Choose the archive.** The newest backup whose `backup:verify` has passed.
   Never restore an unverified archive.
3. **Verify before you commit to it.**
   ```bash
   PXL_BACKUP_PASSPHRASE=… npm run backup:verify backups/pxl-<timestamp>
   ```
4. **Provision a clean database** and restore into it:
   ```bash
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
     -in backups/pxl-<ts>.dump.enc -out /tmp/pxl.dump -pass env:PXL_BACKUP_PASSPHRASE
   createdb -U postgres pxl_restored
   pg_restore -U postgres -d pxl_restored --no-owner --no-privileges /tmp/pxl.dump
   ```
5. **Confirm the books** before letting anyone in:
   ```sql
   SELECT SUM(debit_amount) - SUM(credit_amount) FROM journal_entry_lines;  -- must be 0.00
   SELECT count(*) FROM journal_entries;
   ```
   Then run the reconciliation guards `111` and `112` against the restored
   database.
6. **Point the application at it**, bring writes back up, and record what was
   lost between the archive timestamp and the incident.
7. **Shred the decrypted intermediate**: `shred -u /tmp/pxl.dump`.

---

## 6. Operating the service

A drill that runs when someone remembers is indistinguishable from no drill at
the moment it is needed. `npm run backup:operate` is the unattended cycle, and
it is the single unit of work a schedule invokes:

```bash
PXL_BACKUP_PASSPHRASE=… PXL_OFFSITE_URL=s3://bucket/pxl npm run backup:operate
```

| Stage | Script | Fails the cycle when |
| --- | --- | --- |
| 1. Back up | `backup.sh` | the dump or manifest is empty |
| 2. Prove it restores | `restore_verify.sh` | any object, row count, financial total or ledger balance diverges |
| 3. Copy offsite, read it back | `backup_offsite.sh` | no destination, no verification receipt, an unencrypted archive, or a checksum mismatch on the copy |
| 4. Enforce retention | `backup_prune.mjs --apply` | the policy selects nothing to keep |
| 5. Record the outcome | `backups/drill-history.jsonl` | — |

Every stage fails closed. A schedule that keeps reporting success while one
stage quietly stopped working is worse than no schedule, because the gap is
discovered during the incident.

**Two refusals worth knowing about.** Step 3 will not replicate an archive that
step 2 has not passed — otherwise a possibly-broken artifact gets multiplied
until the number of copies is mistaken for evidence. It also will not send an
unencrypted dump off the host; books leaving the machine without AES-256 is a
disclosure, not a backup.

**The read-back is the point.** An offsite copy nobody has ever read is subject
to exactly the criticism this runbook applies to an unrestored dump. Step 3
downloads what it just uploaded and compares the SHA-256 before claiming
success.

### The schedule

`.github/workflows/backup-drill.yml` runs the full cycle **weekly** (01:00
Monday Philippine time) and on any change to the recovery scripts. It loads the
canonical dataset first — a cycle proven only against an empty schema says
nothing about restoring books — then verifies the *replicated* copy restores,
not merely the archive it still holds.

**What that job proves and does not prove.** It proves the recovery tooling
works, on a schedule, against a populated database, including replication and a
restore of the replicated copy. It is **not** a backup of client books: no PXL
database holds real data yet.

### Retention

30 daily, 12 monthly, 7 annual — enforced by `scripts/backup_retention.mjs`,
which keeps the newest set in each bucket plus the newest set overall,
unconditionally. Unrecognised files are never touched; this is a retention
policy, not a directory cleaner. `npm run backup:prune` reports; `--apply`
deletes. A guard test asserts these numbers and the table in §2 agree, because
the code that deletes books and the document that describes it must not drift.

Object-storage destinations should use a bucket lifecycle policy matching the
same numbers rather than running the pruner against them.

### The destination — PAD-007, decided 2026-08-02

**S3-compatible object storage, self-managed.** Cloudflare R2, Backblaze B2 or
AWS S3. The backups then live in a different failure domain from the database
vendor, which is the property that matters: a provider's own backups do not
survive losing the provider account.

Provider-native PITR is **not** adopted for the pilot. The daily cycle meets the
24-hour pilot RPO; the 1-hour production RPO is an open commitment to revisit
before any production claim.

**Setting it up.** Create a bucket with versioning on and a lifecycle policy
matching the retention numbers above, then prove it before trusting it with
anything:

```bash
export PXL_OFFSITE_URL=s3://pxl-backups/prod
export AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=…
export AWS_ENDPOINT_URL=https://<account>.r2.cloudflarestorage.com   # R2/B2 only
npm run backup:offsite:check
```

That uploads a canary containing no client data, reads it back, compares bytes
and deletes it — proving credentials, write, read, fidelity and **delete
permission**, the last of which retention needs and which would otherwise be
discovered during the first prune. It is safe to run against the production
destination, and the scheduled workflow runs it weekly once the repository
variable `PXL_OFFSITE_URL` and the two access-key secrets exist.

**The passphrase must be escrowed off the host.** `PXL_BACKUP_PASSPHRASE`. An
archive whose passphrase died with the server is not a backup. Keep it where the
loss of the application host cannot reach it, and never in this repository.

**The offsite copy is not optional.** A backup on the same host as the database
does not survive the failure that destroys the host.

---

## 7. What is proven and what is not

**Proven on 2026-08-02:**
- Backup, encryption, decryption and restore all execute end to end.
- A restored database is identical across every populated table (93 under the
  canonical dataset), all schema object classes and every financial total.
- The restored ledger balances at 0.00 and remains kernel-protected.
- The verifier detects both missing objects and missing rows.
- RTO measured at 6–8 seconds for restore.
- The full service cycle runs unattended: backup → verify → replicate → prune →
  journal, and the **replicated** copy was restored independently (93 tables, 0
  mismatches, debits and credits both ₱2,441,164.80, out-of-balance 0.00, 6s).
- Every refusal was exercised and observed to refuse: no destination, no
  verification receipt, an unencrypted archive, and a checksum mismatch on the
  copy each fail the cycle with exit 1 and are recorded as a failure with the
  stage that broke.

**Not yet proven:**
- The schedule exists but has never fired: the weekly workflow was committed on
  2026-08-02 and its first run is still ahead.
- No durable offsite destination or escrowed passphrase is configured. The
  replication was proven against separate storage on the same machine, which is
  a proof of the mechanism and explicitly **not** a separate failure domain.
- Nothing has been exercised against a hosted PXL database, only local.
- Point-in-time recovery is untested; the 1-hour production RPO depends on it.
- No restore has been performed under incident conditions by someone other than
  the author.
- No PXL database holds real books, so nothing of consequence is being backed
  up yet.

The tooling and the schedule are now built and proven. What remains is
owner-supplied: a destination, an escrowed passphrase, and a hosted database
worth protecting. Recoverability is **demonstrated and mechanised, not yet
operated over anything real.**
