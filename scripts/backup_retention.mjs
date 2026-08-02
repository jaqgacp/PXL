// PXL backup retention policy.
//
// Kept as a pure module on purpose. This code decides which backups get
// deleted, and a retention bug destroys books silently — nothing else in the
// product fails so quietly. Isolating the selection from the filesystem lets
// `tests/recoverability_operations.test.ts` drive it with synthetic clocks and
// prove the boundaries, which is not possible against real files.
//
// Published in the Backup and Recovery Runbook §2. The guard test asserts these
// numbers match the runbook table, so the two cannot drift apart.

export const RETENTION = Object.freeze({
  daily: 30,
  monthly: 12,
  annual: 7,
});

const SET_NAME = /^pxl-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/;

/** Parse a backup set base name into its UTC instant, or null if it is not one. */
export function parseSetName(name) {
  const m = SET_NAME.exec(name);
  if (!m) return null;
  const [, y, mo, d, h, mi, s] = m;
  const at = new Date(Date.UTC(+y, +mo - 1, +d, +h, +mi, +s));
  if (Number.isNaN(at.getTime())) return null;
  // Reject impossible dates that Date.UTC silently rolls over (2026-02-31).
  if (at.getUTCMonth() !== +mo - 1 || at.getUTCDate() !== +d) return null;
  return at;
}

const dayKey = (at) => at.toISOString().slice(0, 10);
const monthKey = (at) => at.toISOString().slice(0, 7);
const yearKey = (at) => at.toISOString().slice(0, 4);

/**
 * Decide which backup sets to keep and which to delete.
 *
 * Keeps the newest set within each of the most recent N days, months and years,
 * plus the newest set overall regardless of age. A set that matches no bucket
 * is deleted. A name that is not a recognised backup set is never deleted —
 * this script is not a general-purpose directory cleaner.
 *
 * @param {string[]} names base names, e.g. ["pxl-20260802T114338Z"]
 * @returns {{keep: string[], remove: string[], skipped: string[], reasons: Record<string,string[]>}}
 */
export function selectForRetention(names) {
  const parsed = [];
  const skipped = [];
  for (const name of names) {
    const at = parseSetName(name);
    if (at) parsed.push({ name, at });
    else skipped.push(name);
  }

  // Newest first: within any bucket the first entry seen is the one to keep.
  parsed.sort((a, b) => b.at - a.at || (a.name < b.name ? 1 : -1));

  const reasons = {};
  const note = (name, why) => {
    (reasons[name] ??= []).push(why);
  };

  if (parsed.length > 0) note(parsed[0].name, 'newest');

  for (const [label, keyOf, limit] of [
    ['daily', dayKey, RETENTION.daily],
    ['monthly', monthKey, RETENTION.monthly],
    ['annual', yearKey, RETENTION.annual],
  ]) {
    const newestPerBucket = new Map();
    for (const entry of parsed) {
      const key = keyOf(entry.at);
      if (!newestPerBucket.has(key)) newestPerBucket.set(key, entry.name);
    }
    // Map preserves insertion order, and insertion followed newest-first.
    for (const [key, name] of [...newestPerBucket].slice(0, limit)) {
      note(name, `${label}:${key}`);
    }
  }

  const keep = parsed.filter((e) => reasons[e.name]).map((e) => e.name);
  const remove = parsed.filter((e) => !reasons[e.name]).map((e) => e.name);
  return { keep, remove, skipped, reasons };
}
