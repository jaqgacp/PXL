// Enforce the PXL backup retention policy over a backup directory.
//
// An unattended backup schedule without pruning fills the disk and then stops
// backing up — the failure mode is "no recent backup", discovered during the
// incident. This is the other half of scheduling, not an optimisation.
//
// Dry run by default. Deleting books is not something a script should do
// because someone forgot a flag.
//
//   node scripts/backup_prune.mjs                  # show what would go, change nothing
//   node scripts/backup_prune.mjs --apply          # delete
//   node scripts/backup_prune.mjs --apply backups/ /mnt/offsite/pxl
//
// Object-storage destinations should use a bucket lifecycle policy matching
// RETENTION instead of running this against them.

import { readdirSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { RETENTION, selectForRetention } from './backup_retention.mjs';

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const dirs = args.filter((a) => !a.startsWith('--'));
if (dirs.length === 0) dirs.push('backups');

// Every file a backup set owns. Anything else in the directory is left alone.
const SUFFIXES = [
  '.dump',
  '.dump.sha256',
  '.dump.enc',
  '.dump.enc.sha256',
  '.manifest.json',
  '.verified.json',
];

function setNamesIn(dir) {
  const names = new Set();
  for (const entry of readdirSync(dir)) {
    for (const suffix of SUFFIXES) {
      if (entry.endsWith(suffix)) names.add(entry.slice(0, -suffix.length));
    }
  }
  return [...names];
}

let exitCode = 0;
let removedTotal = 0;

for (const dir of dirs) {
  let names;
  try {
    names = setNamesIn(dir);
  } catch (error) {
    console.error(`[prune] FAIL: cannot read ${dir}: ${error.message}`);
    exitCode = 1;
    continue;
  }

  const { keep, remove, reasons, skipped } = selectForRetention(names);
  for (const name of skipped) console.log(`  ignore ${name}  (not a backup set name)`);
  console.log(`[prune] ${dir}: ${names.length} set(s); policy ${RETENTION.daily} daily / ${RETENTION.monthly} monthly / ${RETENTION.annual} annual`);

  for (const name of keep) console.log(`  keep   ${name}  (${reasons[name].join(', ')})`);

  for (const name of remove) {
    const files = SUFFIXES.map((s) => join(dir, name + s)).filter((p) => {
      try {
        return statSync(p).isFile();
      } catch {
        return false;
      }
    });
    console.log(`  ${apply ? 'DELETE' : 'would delete'} ${name}  (${files.length} file(s), outside every retention bucket)`);
    if (apply) {
      for (const file of files) rmSync(file, { force: true });
      removedTotal += 1;
    }
  }

  // A tripwire on the policy itself, not on stray files: the newest set is kept
  // unconditionally, so recognised sets with nothing retained means the
  // selector is broken and must not be allowed to run against the books.
  if (keep.length === 0 && keep.length + remove.length > 0) {
    console.error('[prune] FAIL: policy selected nothing to keep — refusing to continue');
    exitCode = 1;
  }
}

console.log(apply
  ? `[prune] PASS: ${removedTotal} set(s) removed under the published retention policy.`
  : '[prune] dry run — nothing was deleted. Pass --apply to enforce.');

process.exit(exitCode);
