/**
 * Guards the honesty of the navigation.
 *
 * PXL defers by building the whole surface and leaving the data empty. Without
 * this, a user sees a full menu and concludes the product is broken rather than
 * unfinished, and a pilot dies on first impression. `DEFERRED_ROUTES` marks
 * those screens in the product itself.
 *
 * These assertions keep the list honest in both directions: every entry must
 * still be a real route, and the list must stay in the shape the audit found.
 * When a surface becomes real, delete its entry — that is the intended way for
 * this test to force a deliberate decision.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const appShell = readFileSync(join(root, 'src/components/AppShell.tsx'), 'utf8')
const appRouter = readFileSync(join(root, 'src/App.tsx'), 'utf8')
const deferredSource = readFileSync(join(root, 'src/lib/deferredSurfaces.ts'), 'utf8')

function deferredRoutes(): string[] {
  const block = deferredSource.slice(
    deferredSource.indexOf('DEFERRED_ROUTES'),
    deferredSource.indexOf('] as const'),
  )
  return [...block.matchAll(/^\s*'([a-z0-9-]+)',/gm)].map((m) => m[1])
}

test('every deferred route is declared exactly once', () => {
  const routes = deferredRoutes()
  assert.ok(routes.length > 0, 'expected a non-empty deferred route list')
  assert.equal(new Set(routes).size, routes.length, 'duplicate entry in DEFERRED_ROUTES')
})

test('every deferred route is a real application route', () => {
  for (const route of deferredRoutes()) {
    assert.ok(
      appRouter.includes(`path="/${route}"`) || appRouter.includes(`path="${route}"`),
      `DEFERRED_ROUTES lists "${route}" but src/App.tsx declares no such route. ` +
        'Remove the stale entry.',
    )
  }
})

test('every deferred route is reachable from the navigation', () => {
  for (const route of deferredRoutes()) {
    assert.ok(
      appShell.includes(`'${route}'`),
      `DEFERRED_ROUTES lists "${route}" but the navigation never links to it. ` +
        'An unreachable scaffold should be removed, not labelled.',
    )
  }
})

test('the navigation renders the deferred marker', () => {
  assert.ok(
    appShell.includes('isDeferredRoute'),
    'AppShell must consult isDeferredRoute so scaffolds are marked in the product, ' +
      'not only in governance documents.',
  )
  assert.ok(appShell.includes('Not built'), 'AppShell must render the deferred badge text')
})

test('surfaces proven to work are never marked deferred', () => {
  // Each of these reads a live reporting view over posted data or exposes a
  // working generator RPC. Marking them "Not built" would be a false claim in
  // the opposite direction, which is just as damaging as overclaiming.
  const working = [
    'wt-qap',
    'wt-sawt',
    'vat-reconciliation',
    '2307-issued-review',
    'general-ledger',
    'trial-balance',
    'sales-invoices',
    'vendor-bills',
  ]
  const routes = new Set(deferredRoutes())
  for (const route of working) {
    assert.ok(!routes.has(route), `"${route}" has a real data source and must not be marked deferred`)
  }
})

test('a root-relative Supabase URL resolves against the page origin', () => {
  // The dev server proxies Supabase at /supabase on its own origin so the app
  // works in a remote workspace, where the browser cannot reach the container's
  // 127.0.0.1:54321.
  const client = readFileSync(join(root, 'src/lib/supabase.ts'), 'utf8')
  assert.match(client, /startsWith\('\/'\)/, 'a root-relative VITE_SUPABASE_URL must be detected')
  assert.match(client, /window\.location\.origin/, 'it must be resolved against the page origin')

  const vite = readFileSync(join(root, 'vite.config.ts'), 'utf8')
  assert.match(vite, /'\/supabase':\s*\{/, 'the dev server must proxy /supabase')
  assert.match(
    vite,
    /target:\s*'http:\/\/127\.0\.0\.1:54321'/,
    'the proxy must target the local Supabase API',
  )
  assert.match(vite, /rewrite:\s*\(p\).*\^\\\/supabase/, 'the proxy must strip its URL prefix')
})
