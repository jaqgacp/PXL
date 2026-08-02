/**
 * Guards recoverability as an OPERATED service, not a demonstrated capability.
 *
 * `backup_recovery.test.ts` guards the tooling: that the scripts exist, capture
 * a manifest, and that the verifier can fail. These assertions guard the layer
 * above it — the things that make the difference between "we can restore" and
 * "we would still have the books tomorrow":
 *
 *   - something invokes the drill on a schedule
 *   - a copy leaves the host, and is read back rather than assumed
 *   - an unverified or unencrypted archive cannot be replicated
 *   - retention is enforced, so the disk does not silently end the schedule
 *   - the published retention policy and the code that deletes books agree
 *
 * The last one is the reason the policy lives in a module instead of a shell
 * script: a retention bug deletes books silently, and nothing else in PXL fails
 * that quietly.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { RETENTION, parseSetName, selectForRetention } from '../scripts/backup_retention.mjs'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p: string) => readFileSync(join(root, p), 'utf8')

const setsAcross = (days: number, from = Date.UTC(2025, 0, 1, 3, 0, 0)) =>
  Array.from({ length: days }, (_, i) =>
    'pxl-' + new Date(from + i * 86_400_000).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, ''))

test('the drill runs on a schedule, not when someone remembers', () => {
  const path = '.github/workflows/backup-drill.yml'
  assert.ok(existsSync(join(root, path)), 'a scheduled backup drill workflow must exist')
  const workflow = read(path)
  assert.match(workflow, /schedule:/, 'the drill must be scheduled')
  assert.match(workflow, /cron:/, 'the schedule must carry a cron expression')
  assert.match(workflow, /backup_operate\.sh/, 'the schedule must invoke the full service cycle, not just a dump')
  // Restoring the archive you still hold proves the dump. Restoring the copy
  // that travelled proves the replication — the claim that survives host loss.
  assert.match(
    workflow,
    /restore_verify\.sh[\s\S]*OFFSITE|OFFSITE[\s\S]*restore_verify\.sh/,
    'the drill must restore the replicated copy, not only the local archive',
  )
})

test('operated backup entry points are runnable', () => {
  const pkg = JSON.parse(read('package.json'))
  for (const name of ['backup:offsite', 'backup:offsite:check', 'backup:prune', 'backup:operate']) {
    assert.ok(pkg.scripts?.[name], `npm run ${name} must exist`)
  }
})

test('a destination can be proven without shipping books to it', () => {
  // PAD-007 selects S3-compatible storage. The first thing anyone does with a
  // new bucket is find out whether the credentials work — and that must not be
  // discovered by uploading client books, nor by uploading CI demo data into
  // the bucket that will later hold real ones.
  const offsite = read('scripts/backup_offsite.sh')
  assert.match(offsite, /--check/, 'a destination self-test must exist')
  assert.match(offsite, /contains no client data/, 'the canary must carry no client data')
  // Retention needs delete. Finding that out during the first prune is too late.
  assert.match(offsite, /rm_remote/, 'the check must prove delete permission, which retention depends on')
  assert.match(offsite, /does not permit delete/, 'a destination without delete must fail the check')
})

test('the scheduled destination check is skipped rather than faked', () => {
  const workflow = read('.github/workflows/backup-drill.yml')
  assert.match(workflow, /backup:offsite:check/, 'the schedule must re-prove the destination')
  // A job that "passes" against an unconfigured destination would report green
  // for a bucket that does not exist.
  assert.match(
    workflow,
    /vars\.PXL_OFFSITE_URL != ''/,
    'the destination job must be skipped while no destination is configured, never silently passed',
  )
  // Scope the next assertion to the drill job. CI holds only demo data, and the
  // bucket that will hold real books must never receive it.
  const drillJob = workflow.slice(workflow.indexOf('\n  drill:'))
  assert.ok(drillJob.includes('backup_operate.sh'), 'the drill job must run the service cycle')
  assert.match(drillJob, /runner\.temp/, 'the drill must replicate to runner-local storage')
  assert.doesNotMatch(
    drillJob,
    /vars\.PXL_OFFSITE_URL/,
    'the CI drill must not replicate demo data into the real destination',
  )
})

test('one cycle chains every stage and fails closed', () => {
  const operate = read('scripts/backup_operate.sh')
  for (const stage of ['backup.sh', 'restore_verify.sh', 'backup_offsite.sh', 'backup_prune.mjs']) {
    assert.match(operate, new RegExp(stage.replace('.', '\\.')), `the cycle must run ${stage}`)
  }
  assert.match(operate, /set -euo pipefail/, 'a stage failure must abort the cycle')
  assert.match(operate, /trap .* ERR/, 'a failed cycle must be recorded, not silently forgotten')
  assert.match(operate, /drill-history\.jsonl/, 'each cycle must leave evidence that the schedule ran')
  assert.match(operate, /--apply/, 'retention must actually be enforced, not only reported')
})

test('an archive cannot go offsite unverified or unencrypted', () => {
  const offsite = read('scripts/backup_offsite.sh')
  // Replicating an unproven dump multiplies a possibly-broken artifact until
  // the number of copies is mistaken for evidence.
  assert.match(offsite, /verified\.json/, 'replication must require a restore-verification receipt')
  assert.match(offsite, /dump\.enc/, 'replication must prefer the encrypted archive')
  assert.match(offsite, /PXL_OFFSITE_ALLOW_PLAINTEXT/, 'sending plaintext books off the host must take an explicit override')
  assert.match(offsite, /PXL_OFFSITE_URL/, 'the destination must be configured, never defaulted')
  // Fail closed: no destination means no silent success.
  assert.match(offsite, /FAIL: PXL_OFFSITE_URL is not set/, 'a missing destination must fail, not skip')
})

test('the offsite copy is read back and proven, not assumed', () => {
  const offsite = read('scripts/backup_offsite.sh')
  assert.match(offsite, /sha256sum/, 'the replicated copy must be checksummed')
  assert.match(offsite, /READBACK|read-back/, 'the copy must be downloaded again to prove it is readable')
  assert.match(offsite, /exit 1/, 'a checksum mismatch must fail the run')
  // The manifest and receipt must travel too, or the copy cannot be verified
  // later from the destination alone.
  assert.match(offsite, /\.manifest\.json/, 'the manifest must be replicated alongside the archive')
})

test('a verification receipt is issued on pass and withdrawn on failure', () => {
  const verify = read('scripts/restore_verify.sh')
  assert.match(verify, /verified\.json/, 'a passing verification must leave a receipt')
  assert.match(
    verify,
    /rm -f "\$RECEIPT"/,
    'a failing verification must delete any earlier receipt, or a broken set keeps a stale certificate',
  )
})

test('the retention policy and the code that deletes books agree', () => {
  const runbook = read('docs/PXL/00. Governance/PXL_BACKUP_AND_RECOVERY_RUNBOOK.md')
  const published = /(\d+)\s+daily,\s*(\d+)\s+monthly,\s*(\d+)\s+annual/.exec(runbook)
  assert.ok(published, 'the runbook must publish a retention policy in a readable form')
  assert.equal(Number(published[1]), RETENTION.daily, 'runbook and code disagree on daily retention')
  assert.equal(Number(published[2]), RETENTION.monthly, 'runbook and code disagree on monthly retention')
  assert.equal(Number(published[3]), RETENTION.annual, 'runbook and code disagree on annual retention')
})

test('retention keeps the newest backup unconditionally', () => {
  // Even a set far older than every bucket is the only thing standing between
  // the business and total loss. It is never the one pruning removes.
  const { keep, remove } = selectForRetention(['pxl-20200101T000000Z'])
  assert.deepEqual(keep, ['pxl-20200101T000000Z'])
  assert.deepEqual(remove, [])
})

test('retention keeps one backup per day for the daily window', () => {
  const names = setsAcross(400)
  const { keep, remove, reasons } = selectForRetention(names)
  assert.equal(keep.length + remove.length, names.length, 'every set is either kept or removed')

  const daily = keep.filter((n) => reasons[n].some((r) => r.startsWith('daily:')))
  assert.equal(daily.length, RETENTION.daily, `exactly ${RETENTION.daily} daily backups are retained`)

  const monthly = keep.filter((n) => reasons[n].some((r) => r.startsWith('monthly:')))
  assert.equal(monthly.length, RETENTION.monthly, `exactly ${RETENTION.monthly} monthly backups are retained`)

  // Nothing inside the daily window may be pruned, whatever the other buckets do.
  const newestKept = keep[0]
  assert.equal(newestKept, names[names.length - 1], 'the newest set is retained')
})

test('retention keeps the newest set of each day, not an arbitrary one', () => {
  const morning = 'pxl-20260201T010000Z'
  const evening = 'pxl-20260201T230000Z'
  const { keep, remove } = selectForRetention([morning, evening, 'pxl-20260202T010000Z'])
  assert.ok(keep.includes(evening), 'the last backup of a day is the one worth keeping')
  assert.ok(remove.includes(morning), 'earlier same-day sets are superseded')
})

test('pruning never touches files it does not recognise', () => {
  const { skipped, keep, remove } = selectForRetention([
    'pxl-20260101T000000Z', 'README.md', 'pxl-notatimestamp', 'drill-history',
  ])
  assert.deepEqual(skipped.sort(), ['README.md', 'drill-history', 'pxl-notatimestamp'])
  assert.ok(!remove.includes('README.md'), 'this is a retention policy, not a directory cleaner')
  assert.equal(keep.length, 1)
})

test('an impossible timestamp is never treated as a backup', () => {
  // Date.UTC rolls 2026-02-31 forward to March. Accepting it would file a set
  // under the wrong month and could retire the real one in its place.
  assert.equal(parseSetName('pxl-20260231T000000Z'), null)
  assert.equal(parseSetName('pxl-20261301T000000Z'), null)
  assert.ok(parseSetName('pxl-20260228T235959Z') instanceof Date)
})

test('the prune CLI does not delete unless told to', () => {
  const prune = read('scripts/backup_prune.mjs')
  assert.match(prune, /--apply/, 'deletion must require an explicit flag')
  assert.match(prune, /dry run/i, 'the default must report rather than delete')
  assert.match(
    prune,
    /refusing to continue/,
    'a policy that selected nothing to keep is a bug, and must not be executed against the books',
  )
})

test('the regression lane establishes its own database state', () => {
  // The published gate order is fresh → canonical → regression. Because the
  // canonical seed populates `companies`, it removes the zero-company bootstrap
  // branch of fn_provision_company that the fresh-data end-to-end tests use to
  // provision their own tenant — so the suite reported a red lane that said
  // nothing about the product, only about what had run before it.
  const lanes = read('scripts/run_validation_lane.mjs')
  const regression = /function regression\(\)\s*\{([\s\S]*?)\n\}/.exec(lanes)
  assert.ok(regression, 'the regression lane must be defined')
  assert.match(
    regression[1],
    /freshSchema\(\)/,
    'regression must reset to a known schema first; a gate whose verdict depends on execution order is not a gate',
  )
})
