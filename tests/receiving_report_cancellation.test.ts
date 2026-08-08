/**
 * Receiving Report cancellation UI contract.
 *
 * The accounting and inventory reversal lives in fn_void_receiving_report.
 * This source test keeps the browser limited to reason capture, RPC invocation,
 * refusal display, and post-action refresh.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const page = readFileSync(join(root, 'src/pages/ReceivingReportsPage.tsx'), 'utf8')

test('Receiving Report cancellation calls the governed RPC and never writes cancelled status', () => {
  assert.ok(page.includes("supabase.rpc('fn_void_receiving_report'"))
  assert.doesNotMatch(
    page,
    /from\(['"]receiving_reports['"]\)[\s\S]{0,240}?(?:update|upsert)\([\s\S]{0,120}?status:\s*['"]cancelled['"]/,
    'a direct status write would bypass the journal reversal, stock removal, period guard, and dependency checks',
  )
})

test('the action captures a governed reason and forwards database refusals verbatim', () => {
  assert.ok(page.includes("from('void_reason_codes')"))
  assert.ok(page.includes('p_void_reason_id: voidReasonId'))
  assert.match(page, /disabled=\{!voidReasonId \|\| voiding\}/)
  assert.ok(page.includes('setError(cancelError.message)'))
})

test('successful cancellation refreshes both the open document and list state', () => {
  assert.ok(page.includes('loadReportDetail(editRR.id)'))
  assert.ok(page.includes('loadReports()'))
  assert.ok(page.includes("setVoidOpen(false)"))
})

test('the screen presents the actual RR journal and reversal behavior', () => {
  assert.ok(page.includes('DR Inventory / CR Goods Received Not Invoiced'))
  assert.ok(page.includes('Receipt journal reversed'))
  assert.ok(page.includes('accounting-trace?sourceType=RR'))
  assert.ok(!page.includes('No direct GL posting'))
})
