/**
 * The screen half of the compliance-architecture verification (Backlog 8f).
 *
 * `supabase/tests/129_compliance_architecture_verification_test.sql` asserts the
 * database half: the retired tables and the retired export are gone, and every
 * export snapshot is keyed to a filing artifact. pgTAP cannot see `src/`, so the
 * claim that **no routed screen bypasses the governed pipeline** is asserted
 * here, over the source itself.
 *
 * The claim, stated exactly as it must be stated:
 *
 *   The governed compliance architecture is complete for every implemented
 *   compliance family. FWT remains the single documented exception because no
 *   governed FWT pipeline exists yet.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const pagesDir = join(root, 'src/pages')
const pages = readdirSync(pagesDir).filter((f) => f.endsWith('.tsx'))
const read = (f: string) => readFileSync(join(pagesDir, f), 'utf8')

/** The two families Backlog 22 still blocks, and the only ones permitted to be hand-keyed. */
const FWT_PAGES = ['FWTWorkingPapersPage.tsx', 'FWT1601FQWorkingPapersPage.tsx']

test('no screen reads a retired legacy working-paper table', () => {
  const retired = /compliance_(vat|ewt|1601eq|pt)_working_papers/
  for (const page of pages) {
    assert.ok(
      !retired.test(read(page)),
      `${page} reads a legacy working-paper table retired by Backlog 8f. ` +
        'Compliance figures come from the filing artifact, not from a hand-keyed table.',
    )
  }
})

test('no screen calls the retired withholding export snapshot', () => {
  for (const page of pages) {
    assert.ok(
      !read(page).includes('fn_snapshot_wht_export'),
      `${page} calls fn_snapshot_wht_export, which was retired with Backlog 8f. ` +
        'Exports consume the filing artifact through downloadFilingArtifactExport.',
    )
  }
})

test('the four governed working papers are one implementation, not four', () => {
  const app = readFileSync(join(root, 'src/App.tsx'), 'utf8')
  for (const route of [
    'vat-working-papers',
    'ewt-working-papers',
    'wt-1601eq-working-papers',
    'pt-working-papers',
  ]) {
    const line = app.split('\n').find((l) => l.includes(`path="/${route}"`))
    assert.ok(line, `src/App.tsx no longer routes /${route}`)
    assert.match(
      line,
      /FilingWorkingPapersPage/,
      `/${route} must render the governed FilingWorkingPapersPage, not a screen of its own`,
    )
  }
  assert.equal(
    pages.filter((p) => /^(VAT|EWT|EWT1601EQ|PT)WorkingPapersPage\.tsx$/.test(p)).length,
    0,
    'the four legacy working-paper pages must be deleted, not merely unrouted',
  )
})

test('only the FWT surfaces remain hand-keyed, and only because FWT has no pipeline', () => {
  const handKeyed = pages.filter((p) => /compliance_[a-z0-9_]*working_papers/.test(read(p)))
  assert.deepEqual(
    handKeyed.sort(),
    [...FWT_PAGES].sort(),
    'FWT is the single documented exception: it is not a tax kind, so no filing ' +
      'artifact can be generated for it (Backlog 22). Any other page writing a ' +
      'compliance working paper by hand is a second architecture.',
  )
})

test('the governed working paper reaches the filing artifact and nothing else', () => {
  const page = read('FilingWorkingPapersPage.tsx')
  for (const rpc of [
    'fn_filing_working_paper',
    'fn_generate_filing_artifact',
    'fn_filing_reconciling_items',
    'fn_add_filing_reconciling_item',
  ]) {
    assert.ok(page.includes(rpc), `FilingWorkingPapersPage must consume ${rpc}`)
  }
  assert.ok(
    !/vw_[a-z_]*(review|summary)/.test(page),
    'the working paper must not read a review view: it reads the governed reader',
  )
  assert.ok(
    !/\.reduce\(/.test(page.slice(page.indexOf('handleAddItem'))),
    'nothing below the data layer may aggregate a compliance figure in the browser',
  )
})

/**
 * The filing surfaces: every screen whose figures are keyed onto a BIR form.
 * A review surface (SLS, SLP, RELIEF, the tax dashboards) is deliberately not
 * here — it reads source data by design, because its job is to find the invoice
 * with the missing VAT code before anything is generated. The two are different
 * stages of one pipeline, and only this stage is bound to the artifact.
 */
const FILING_PAGES = [
  'VATReturn2550QPage.tsx',
  'PTReturnPage.tsx',
  'EWT1601EQReturnPage.tsx',
  'SAWTPage.tsx',
  'QAPPage.tsx',
  'SLSPExportPage.tsx',
  'FilingWorkingPapersPage.tsx',
]

test('no filing surface rebuilds its figures from a source view', () => {
  for (const page of FILING_PAGES) {
    const src = read(page)
    assert.ok(
      src.includes('fn_filing_working_paper') || src.includes('fn_generate_'),
      `${page} is a filing surface and must consume the governed generator or working paper`,
    )
    assert.ok(
      !/from\('vw_[a-z_]+'\)/.test(src),
      `${page} reads a source view. A filing figure comes from the Filing Artifact; ` +
        'reading a review view here is the second architecture Backlog 8f removed.',
    )
    assert.ok(
      !src.includes('fn_snapshot_vat_export'),
      `${page} calls the legacy VAT export snapshot. Filing exports go through ` +
        'downloadFilingArtifactExport, which evidences the artifact bytes.',
    )
  }
})

test('the SLSP attachment is quarterly, like the artifact and the BIR form', () => {
  const src = read('SLSPExportPage.tsx')
  assert.match(
    src,
    /p_form_code: 'SLSP'/,
    'the SLSP screen must read the SLSP filing artifact',
  )
  assert.ok(
    !/selMonth|taxable_month/.test(src),
    'the SLSP screen was monthly while its artifact and the BIR attachment are ' +
      'quarterly, so the list could disagree with the 2550Q filed beside it (Backlog 8c/8e ii)',
  )
})

test('every compliance export in the product goes through the artifact export', () => {
  const compliance = pages.filter((p) =>
    /(VATReturn|PTReturn|EWT1601EQ|SAWT|QAP|SLSPExport|FilingWorkingPapers)/.test(p),
  )
  assert.ok(compliance.length >= 6, 'expected the compliance export surfaces to be found')
  for (const page of compliance) {
    const src = read(page)
    if (!src.includes('Export')) continue
    assert.ok(
      src.includes('downloadFilingArtifactExport'),
      `${page} offers an export that does not consume the filing artifact`,
    )
  }
})
