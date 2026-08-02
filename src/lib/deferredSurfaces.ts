/**
 * Routes that render a finished-looking screen over data that cannot exist yet.
 *
 * PXL defers by building the whole surface and leaving the data empty. That is
 * defensible engineering and completely invisible to a user, who sees a full
 * menu and concludes the product is broken rather than unfinished. This module
 * makes the deferral visible in the product itself instead of only in
 * governance documents.
 *
 * Membership is not a judgement call. A route belongs here only when, against a
 * fully seeded canonical dataset, it satisfies all of:
 *   - every business table it reads is empty;
 *   - it reads no reporting view (which would carry live posted data); and
 *   - it calls no generating RPC (which would let a user create the first row).
 *
 * A route with a working generator does NOT belong here: it is empty until used,
 * which is ordinary. Verified 2026-08-02 against the canonical lane.
 *
 * When a surface becomes real, delete its entry. `deferredSurfaces` is asserted
 * by tests/deferred_surfaces.test.ts so this list cannot silently rot.
 */
export const DEFERRED_ROUTES: readonly string[] = [
  // Fixed Assets — v2 scope. Eight screens, six tables, never exercised.
  'asset-register',
  'fixed-asset-dashboard',
  'reports-asset-disposal',
  'reports-book-vs-tax-depreciation',
  'reports-depreciation-schedule',

  // Banking & Treasury — v2 scope.
  'cash-count-sheet',
  'reports-check-register',

  // Income Tax — v2 scope. Ten screens, none has ever held a row.
  'inc-tax-1701',
  'inc-tax-1701q',
  'inc-tax-1702q',
  'inc-tax-1702rt',
  'inc-tax-book-to-tax-recon',
  'inc-tax-computation',
  'inc-tax-credits',
  'inc-tax-mcit',
  'inc-tax-nolco',
  'inc-tax-osd',

  // Statutory working papers and returns — the review surfaces they would be
  // built on already work and reconcile; only the filing artifacts are missing.
  'ewt-working-papers',
  'pt-summary-register',
  'pt-working-papers',
  'vat-working-papers',
  'wt-1601eq-working-papers',
  'wt-1601fq-return',
  'wt-1601fq-working-papers',
  'wt-2306-certificates',
  'wt-fwt-working-papers',
  'reports-fwt-summary',

  // CAS artifacts without a workflow behind them.
  'cas-attachment-register',
  'cas-export-history',
  'report-snapshots',
] as const

const DEFERRED = new Set(DEFERRED_ROUTES)

/** True when a route is a scaffold that cannot yet display or create data. */
export function isDeferredRoute(page: string | undefined): boolean {
  if (!page) return false
  return DEFERRED.has(page.replace(/^\//, ''))
}
