/**
 * The screen half of Delivery Receipt cancellation (Backlog 18c).
 *
 * `supabase/tests/131_delivery_receipt_cancellation_test.sql` asserts the
 * database half, and `scripts/verify_delivery_receipt_lifecycle.mjs` proves the
 * lifecycle across separate committed transactions — the shape pgTAP cannot see.
 *
 * Asserted here, over the source, are the claims only a screen can break:
 *
 *   1. The cancellation goes through the governed RPC, never a direct status
 *      update. A direct write would skip the journal reversal and the restock and
 *      leave the stock permanently short.
 *   2. A reason is collected, because the database requires one and the CAS
 *      evidence record is built from it.
 *   3. The screen does not decide for itself whether a delivery may be
 *      cancelled — the billed-invoice rule lives in one place, the database.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const page = readFileSync(join(root, 'src/pages/DeliveryReceiptsPage.tsx'), 'utf8')

test('cancelling a delivery goes through the governed RPC', () => {
  assert.ok(
    page.includes('fn_void_delivery_receipt'),
    'DeliveryReceiptsPage never calls fn_void_delivery_receipt, so a mis-shipped ' +
      'delivery still has no correction path.',
  )
})

test('the screen never cancels a delivery by writing the status directly', () => {
  const directCancel = /from\(['"]delivery_receipts['"]\)[\s\S]{0,200}?status:\s*['"]cancelled['"]/
  assert.ok(
    !directCancel.test(page),
    'DeliveryReceiptsPage sets status to cancelled through a direct table write. That ' +
      'skips the journal reversal and the restock, leaving stock permanently short.',
  )
})

test('a cancellation reason is collected and sent', () => {
  assert.ok(
    page.includes('void_reason_codes'),
    'DeliveryReceiptsPage does not load the governed reason codes.',
  )
  assert.ok(
    page.includes('p_void_reason_id'),
    'DeliveryReceiptsPage does not send a reason. fn_void_delivery_receipt requires ' +
      'one, and the CAS void evidence record is built from it.',
  )
  assert.ok(
    /disabled=\{!voidReasonId/.test(page),
    'DeliveryReceiptsPage lets the cancel button fire without a reason chosen.',
  )
})

test('the billed-invoice rule is left to the database', () => {
  // The screen may show what is billed; it must not be the thing that decides
  // whether cancelling is allowed, or the rule would exist in two places.
  const guardsInBrowser = /hidden:\s*[^,]*billedLineIds|disabled:\s*[^,]*billedLineIds\.length/
  assert.ok(
    !guardsInBrowser.test(page),
    'DeliveryReceiptsPage decides in the browser whether a delivery may be cancelled. ' +
      'That rule belongs to fn_void_delivery_receipt alone — one implementation, and it ' +
      'is the one that can see a draft invoice raised in another session.',
  )
})

test('a refused cancellation is shown to the user', () => {
  const dialog = page.slice(page.indexOf('Cancel Delivery'))
  assert.ok(
    dialog.includes('setError(e.message)') || page.includes('setError(e.message)'),
    'DeliveryReceiptsPage discards the database message when a cancellation is refused. ' +
      'The refusal names the invoice that must be voided first, which is the whole answer.',
  )
})
