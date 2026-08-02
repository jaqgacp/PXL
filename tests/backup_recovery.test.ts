/**
 * Guards the backup and recovery capability.
 *
 * PXL had no backup tooling of any kind until 2026-08-02, and that single
 * absence blocked every module from production readiness. These assertions do
 * not re-run a drill — that is `npm run backup:drill`, which needs a live
 * database. They guard the things that would quietly make recovery impossible:
 * the scripts disappearing, the runnable entry points disappearing, backups
 * becoming committable, or the verifier degrading into something that cannot
 * fail.
 *
 * The last one matters most. A verifier that always passes is worse than no
 * verifier, because it manufactures confidence.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (p: string) => readFileSync(join(root, p), 'utf8')

test('backup and restore scripts exist', () => {
  for (const script of ['scripts/backup.sh', 'scripts/restore_verify.sh']) {
    assert.ok(existsSync(join(root, script)), `${script} is required for recoverability`)
  }
})

test('backup and drill entry points are runnable', () => {
  const pkg = JSON.parse(read('package.json'))
  for (const name of ['backup', 'backup:verify', 'backup:drill']) {
    assert.ok(pkg.scripts?.[name], `npm run ${name} must exist`)
  }
  assert.match(
    pkg.scripts['backup:drill'],
    /backup\.sh[\s\S]*restore_verify\.sh/,
    'the drill must take a backup AND verify it restores; a dump alone proves nothing',
  )
})

test('the backup captures a manifest, not just a dump file', () => {
  const backup = read('scripts/backup.sh')
  assert.match(backup, /manifest\.json/, 'a manifest is required to verify a restore against')
  assert.match(backup, /sha256sum/, 'archives must be checksummed so corruption is detectable')
  // Financial totals are what prove the books survived, as distinct from the schema.
  for (const measure of ['total_debit', 'total_credit', 'inventory_value', 'journal_entry_lines']) {
    assert.match(backup, new RegExp(measure), `manifest must record ${measure}`)
  }
  assert.match(backup, /row_counts/, 'manifest must record per-table row counts')
})

test('the verifier compares schema, rows, books and ledger integrity', () => {
  const verify = read('scripts/restore_verify.sh')
  assert.match(verify, /pg_restore/, 'verification must perform an actual restore')
  for (const measure of ['tables', 'functions', 'triggers', 'policies']) {
    assert.match(verify, new RegExp(`"${measure}"`), `verifier must compare ${measure}`)
  }
  assert.match(verify, /total_debit/, 'verifier must compare the ledger totals')
  assert.match(verify, /out_of_balance/, 'verifier must prove the restored ledger still balances')
  assert.match(
    verify,
    /COALESCE\(SUM\(debit_amount\)-SUM\(credit_amount\),0\)::numeric\(18,2\)/,
    'an empty ledger must normalize zero to the same scale as a populated ledger',
  )
  assert.match(verify, /MISMATCHES=0/, 'verifier must require zero row-count mismatches')
})

test('the verifier can actually fail', () => {
  const verify = read('scripts/restore_verify.sh')
  // A verifier with no failure path manufactures confidence. Require both a
  // non-zero exit and that mismatches set the failure flag.
  assert.match(verify, /exit 1/, 'verifier must be able to exit non-zero')
  assert.match(verify, /fail=1/, 'a mismatch must set the failure flag')
  assert.doesNotMatch(
    verify,
    /pg_restore[^\n]*--exit-on-error[^\n]*\|\|\s*true/,
    'do not suppress restore errors while also claiming exit-on-error',
  )
})

test('backups are never committable', () => {
  assert.match(read('.gitignore'), /^backups\/$/m, 'backups/ must be git-ignored — dumps contain client books')
})

test('the runbook records measured recovery objectives', () => {
  const runbook = read('docs/PXL/00. Governance/PXL_BACKUP_AND_RECOVERY_RUNBOOK.md')
  assert.match(runbook, /\*\*RPO\*\*/, 'runbook must state a recovery point objective')
  assert.match(runbook, /\*\*RTO\*\*/, 'runbook must state a recovery time objective')
  assert.match(runbook, /Retention/, 'runbook must state a retention policy')
  // Honesty requirement: the runbook must keep saying what is still unproven.
  assert.match(
    runbook,
    /Not yet proven/,
    'the runbook must continue to distinguish demonstrated recoverability from an operated backup service',
  )
})

test('the deploy rehearsal exists and matches real transaction boundaries', () => {
  const pkg = JSON.parse(read('package.json'))
  assert.ok(pkg.scripts?.['deploy:rehearse'], 'npm run deploy:rehearse must exist')

  const rehearsal = read('scripts/deploy_rehearsal.sh')
  // The rehearsal is only meaningful if it upgrades FROM the deployed version.
  // Replaying from empty is a different and weaker claim.
  assert.match(rehearsal, /DEPLOYED_THROUGH/, 'rehearsal must start from the deployed version, not from empty')
  assert.match(rehearsal, /--single-transaction/,
    'each migration must apply in one transaction, as `supabase db push` does; ' +
    'per-statement autocommit destroys CREATE TEMP TABLE … ON COMMIT DROP and reports false failures')
  assert.match(rehearsal, /BEGIN;/,
    'migrations that open their own transaction must not be wrapped twice')
  assert.match(rehearsal, /deptype='e'/,
    'extension member objects must be excluded from the object comparison')
})

test('the deploy runbook requires a backup and a rehearsal before deploying', () => {
  const runbook = read('docs/PXL/00. Governance/PXL_DEPLOY_RUNBOOK.md')
  // Assert the invariant, not a particular sentence: the runbook must make a
  // pre-deploy backup mandatory and must name the backup as the rollback plan,
  // because there is no supported "undo migration" path.
  assert.match(runbook, /backup/i, 'the runbook must cover backing up before a deploy')
  assert.match(
    runbook,
    /no supported "undo migration" path/i,
    'the runbook must state that the pre-deploy backup IS the rollback plan',
  )
  assert.match(runbook, /deploy:rehearse|deploy_rehearsal/, 'the runbook must require a rehearsal')
  assert.match(runbook, /Not proven/, 'the runbook must keep stating what has not been executed')
})

test('the hosted deploy cannot skip its safety steps', () => {
  const pkg = JSON.parse(read('package.json'))
  assert.ok(pkg.scripts?.['deploy:hosted'], 'npm run deploy:hosted must exist')

  const deploy = read('scripts/deploy_hosted.sh')
  // Default must be a dry run. A production schema change should require an
  // explicit second action, never happen as a side effect of running a script.
  assert.match(deploy, /--execute/, 'pushing must require an explicit --execute flag')
  assert.match(deploy, /db dump --linked/, 'the hosted database must be backed up before any push')
  assert.match(deploy, /deploy_rehearsal\.sh/, 'the upgrade must be rehearsed before it is pushed')
  assert.match(deploy, /--dry-run/, 'the plan must be shown before it is executed')
  assert.match(deploy, /refusing to deploy/, 'an empty backup must abort the deploy')
  // Credentials must be supplied by the operator, never baked into the script.
  // Match only values that could plausibly BE a secret — 16+ token characters —
  // so the '…' placeholders in the script's own help text are not flagged.
  const hardCodedSecret = /(SUPABASE_ACCESS_TOKEN|SUPABASE_DB_PASSWORD|PXL_BACKUP_PASSPHRASE)\s*=\s*["']?[A-Za-z0-9_.\-]{16,}/
  assert.doesNotMatch(deploy, hardCodedSecret, 'no credential may be hard-coded in the deploy script')
  assert.match(deploy, /SUPABASE_DB_PASSWORD:-/, 'the password must come from the environment, unset by default')
})
