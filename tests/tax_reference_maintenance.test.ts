/**
 * The screen half of governed tax-code maintenance (Backlog 10).
 *
 * `supabase/tests/130_tax_reference_succession_test.sql` asserts the database
 * half: succession is reachable through the governed path, the link is recorded,
 * the two writes are one transaction, and a non-maintainer gets none of it.
 *
 * pgTAP cannot see `src/`, so the claims that only a screen can break are
 * asserted here, over the source itself:
 *
 *   1. The screen never writes the three global statutory tables directly — RLS
 *      denies it anyway, but a direct write is a governance regression whether or
 *      not the database catches it.
 *   2. A rate change is offered as a succession, not only as an in-place edit.
 *   3. The screen asks whether the caller may maintain these codes, instead of
 *      offering every action and letting a raw 42501 come back.
 *   4. Failures are shown, not thrown away in an alert().
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const page = readFileSync(join(root, 'src/pages/TaxSetupPage.tsx'), 'utf8')

/** The three global statutory families governed by MDP-01. */
const GOVERNED_TABLES = ['tax_codes', 'vat_codes', 'atc_codes']

test('the screen never writes a global statutory table directly', () => {
  for (const table of GOVERNED_TABLES) {
    for (const verb of ['insert', 'update', 'upsert', 'delete']) {
      const direct = new RegExp(`from\\(['"]${table}['"]\\)[\\s\\S]{0,80}?\\.${verb}\\(`)
      assert.ok(
        !direct.test(page),
        `TaxSetupPage calls .${verb}() on ${table} directly. Global statutory reference ` +
          'data is written only through the governed MDP-01 RPCs, which check the ' +
          'maintainer allowlist and log the change with its reason.',
      )
    }
  }
})

test('every governed write goes through a maintainer-checked RPC', () => {
  for (const rpc of [
    'fn_tax_code_upsert', 'fn_tax_code_set_active', 'fn_tax_code_succeed',
    'fn_vat_code_upsert', 'fn_vat_code_set_active', 'fn_vat_code_succeed',
    'fn_atc_code_upsert', 'fn_atc_code_set_active', 'fn_atc_code_succeed',
  ]) {
    assert.ok(
      page.includes(rpc),
      `TaxSetupPage does not call ${rpc}. Backlog 10 requires add, ` +
        'edit-through-succession and activate/deactivate on all three global families.',
    )
  }
})

test('a rate change is offered as a succession, not only as an in-place edit', () => {
  assert.ok(
    page.includes('New version'),
    'TaxSetupPage offers no succession action. Editing a rate in place would rewrite ' +
      'the version that already priced posted documents.',
  )
  for (const succeed of ['fn_tax_code_succeed', 'fn_vat_code_succeed', 'fn_atc_code_succeed']) {
    assert.ok(
      page.includes(succeed),
      `TaxSetupPage never calls ${succeed}, so that family has no governed rate change.`,
    )
  }
})

test('the effective window is a field the maintainer can set, not a hidden default', () => {
  for (const field of ['effective_from', 'effective_to']) {
    assert.ok(
      page.includes(`p_${field}`),
      `TaxSetupPage never sends p_${field}. A version with no window it can state ` +
        'cannot be succeeded, only overwritten.',
    )
  }
})

test('the screen asks whether the caller may maintain these codes', () => {
  assert.ok(
    page.includes('fn_is_bir_config_maintainer'),
    'TaxSetupPage never checks the maintainer allowlist, so it offers actions to ' +
      'users the database will refuse. Tax-reference authority is maintainer-only ' +
      'and closed by default (MDP-01 Option A).',
  )
  assert.ok(
    /disabled=\{!mayWrite\}/.test(page),
    'TaxSetupPage does not gate its maintenance actions on the authority answer.',
  )
})

test('a refused write is shown to the maintainer, not swallowed', () => {
  assert.ok(
    !page.includes('alert('),
    'TaxSetupPage reports failures through alert(). The version guards raise sentences ' +
      'written to be read — surface them in the form instead.',
  )
  assert.ok(
    page.includes('setError(error.message)') || page.includes('fail(error.message)'),
    'TaxSetupPage discards the database message on failure.',
  )
})

test('the reason reaching the audit log is the one the maintainer typed', () => {
  assert.ok(
    /p_reason: reason \|\|/.test(page),
    'TaxSetupPage sends a hard-coded reason. fn_log_bir_config_change records it as ' +
      '_change_reason, which is the only free-text account of why a statutory rate changed.',
  )
})
