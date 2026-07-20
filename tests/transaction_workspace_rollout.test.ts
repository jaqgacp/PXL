import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { IMPLEMENTED_TRANSACTION_WORKSPACES, REQUIRED_TRANSACTION_TABS, TRANSACTION_ROLLOUT_MATRIX } from '../src/lib/transactionWorkspaceCoverage.ts'

const root = process.cwd()
const appSource = readFileSync(join(root, 'src/App.tsx'), 'utf8')

test('implemented transaction inventory has unique keys and real application routes', () => {
  const keys = IMPLEMENTED_TRANSACTION_WORKSPACES.map(row => row.key)
  assert.equal(new Set(keys).size, keys.length, 'transaction coverage keys must be unique')
  assert.ok(IMPLEMENTED_TRANSACTION_WORKSPACES.length >= 40, 'coverage must include all implemented transaction families')

  for (const row of IMPLEMENTED_TRANSACTION_WORKSPACES) {
    assert.match(appSource, new RegExp(`<Route\\s+path=["']${row.route.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}["']`), `${row.transaction} route must remain registered`)
    assert.ok(['A', 'B', 'C', 'D', 'E'].includes(row.pattern), `${row.transaction} must be classified`)
    assert.ok(row.primaryAdaptation.length > 12, `${row.transaction} must record its transaction-specific adaptation`)
  }
})

test('rollout matrix records routes, tabs, sidebar, dimensions, relations, migration and validation', () => {
  assert.equal(TRANSACTION_ROLLOUT_MATRIX.length, IMPLEMENTED_TRANSACTION_WORKSPACES.length)
  for (const row of TRANSACTION_ROLLOUT_MATRIX) {
    assert.ok(row.formRoute.startsWith('/'), `${row.transaction} form route is missing`)
    if (row.view !== 'not-applicable') assert.ok(row.viewRoute, `${row.transaction} view route/mode is missing`)
    assert.deepEqual([...row.requiredTabs], [...REQUIRED_TRANSACTION_TABS])
    assert.ok(row.requiredSidebarPanels.length >= 4, `${row.transaction} sidebar adaptation is incomplete`)
    assert.ok(row.applicableDimensions.length >= 4, `${row.transaction} dimensions are not classified`)
    assert.ok(row.relatedDocuments.length > 12, `${row.transaction} related-document adaptation is missing`)
    assert.equal(row.migrationStatus, 'migrated')
    assert.match(row.validationStatus, /browser route sweep/)
  }
})

test('every implemented transaction form/view uses the permanent shared workspace architecture', () => {
  for (const row of IMPLEMENTED_TRANSACTION_WORKSPACES) {
    const source = readFileSync(join(root, 'src/pages', row.page), 'utf8')
    const usesCanonicalWorkspace = row.key === 'sales-invoice'
      ? /<TransactionPageHeader[\s\S]*<TransactionWorkflowBanner[\s\S]*<TransactionInfoCards[\s\S]*<TransactionTabsBar[\s\S]*pxl-side-panel/.test(source)
      : /<(TransactionWorkspace|LegacyTransactionWorkspace|DocumentLayout)\b/.test(source)
    assert.ok(usesCanonicalWorkspace, `${row.page} must render the permanent transaction workspace, not only shared CSS`)
  }

  const salesInvoiceView = readFileSync(join(root, 'src/pages/SalesInvoiceDocumentPage.tsx'), 'utf8')
  assert.match(salesInvoiceView, /<TransactionWorkspace/)
  assert.doesNotMatch(salesInvoiceView, /<DocumentLayout/)

  const salesInvoiceForm = readFileSync(join(root, 'src/pages/SalesInvoicePage.tsx'), 'utf8')
  assert.doesNotMatch(salesInvoiceForm, /transactionStickyHeaderClass|transactionTabBarClass|transactionTabButtonClass/)
})

test('the workspace exposes the fixed fourteen-tab navigation contract', () => {
  const workspace = readFileSync(join(root, 'src/components/document/TransactionWorkspace.tsx'), 'utf8')
  const expected = [
    'Lines', 'Financial', 'GL Impact', 'Tax Impact', 'Validation', 'Workflow', 'Approval',
    'Audit', 'Related Docs', 'Related Party', 'Attachments', 'Activity', 'Notes', 'System',
  ]
  for (const label of expected) assert.match(workspace, new RegExp(`'${label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}'`), `missing fixed tab ${label}`)
  assert.match(workspace, /STANDARD_TRANSACTION_TAB_ORDER/)
  assert.match(workspace, /sidebar=/)

  const salesInvoice = readFileSync(join(root, 'src/pages/SalesInvoicePage.tsx'), 'utf8')
  const labelsInFormOrder = [...salesInvoice.matchAll(/\{ key: '[^']+', label: '([^']+)' \}/g)].map(match => match[1])
  assert.deepEqual(labelsInFormOrder.slice(0, expected.length), expected, 'Sales Invoice form must use the same fixed tab order')
})

test('legacy workspace preserves page-owned form state in one mounted Lines boundary', () => {
  const legacy = readFileSync(join(root, 'src/components/document/LegacyTransactionWorkspace.tsx'), 'utf8')
  assert.equal((legacy.match(/\{children\}/g) || []).length, 1, 'the existing business form must be mounted exactly once')
  assert.match(legacy, /headerFields/)
  assert.match(legacy, /actions/)
  assert.match(legacy, /tabContent/)
  assert.match(legacy, /sourceDocType && sourceDocId/)
  assert.match(legacy, /No journal is inferred/)
  assert.match(legacy, /Tax is not inferred/)
})

test('legacy transaction surfaces own header fields and actions in the canonical top workspace', () => {
  for (const row of IMPLEMENTED_TRANSACTION_WORKSPACES) {
    const source = readFileSync(join(root, 'src/pages', row.page), 'utf8')
    const workspaceCount = (source.match(/<LegacyTransactionWorkspace\b/g) || []).length
    if (!workspaceCount) continue
    const cardOwnerCount = (source.match(/\b(?:headerFields|cards)=/g) || []).length
    const actionOwnerCount = (source.match(/\bactions=/g) || []).length
    assert.equal(cardOwnerCount, workspaceCount, `${row.transaction} must bind its real header fields in the three-card band`)
    assert.equal(actionOwnerCount, workspaceCount, `${row.transaction} must expose its real handlers in the top header`)
    assert.doesNotMatch(source, /transactionHeaderClass/, `${row.transaction} must not render a second transaction header inside Lines`)
    assert.doesNotMatch(source, /← Back/, `${row.transaction} must not render a duplicate Back action inside tab content`)
  }
})

test('density correction removes visual hiding and arbitrary transaction content heights', () => {
  const css = readFileSync(join(root, 'src/index.css'), 'utf8')
  assert.doesNotMatch(css, /pxl-legacy-transaction-content[\s\S]{0,120}pxl-transaction-header/)
  assert.doesNotMatch(css, /--pxl-transaction-content-min-height/)
  assert.match(css, /--pxl-transaction-control-height:\s*32px/)
  assert.match(css, /--pxl-transaction-row-height:\s*30px/)
  assert.match(css, /\.pxl-transaction-info-card[\s\S]*?min-height:\s*0/)
  assert.match(css, /\.pxl-transaction-tab-panel[\s\S]*?min-height:\s*0/)
})

test('shared tabs and overlays satisfy persistence and clipping contracts', () => {
  const layout = readFileSync(join(root, 'src/components/document/DocumentLayout.tsx'), 'utf8')
  const workspace = readFileSync(join(root, 'src/lib/transactionWorkspace.ts'), 'utf8')

  assert.match(layout, /createPortal\(/, 'More menu must render outside overflow containers')
  assert.match(layout, /role="tablist"/)
  assert.match(layout, /aria-selected=/)
  assert.match(layout, /ArrowRight/)
  assert.match(layout, /ArrowLeft/)
  assert.doesNotMatch(workspace, /pxl-transaction-tabs overflow-x-auto/, 'desktop transaction tab helper must not depend on horizontal scrolling')
})

test('workspace is fluid and module families vary only through accent tokens', () => {
  const css = readFileSync(join(root, 'src/index.css'), 'utf8')
  assert.match(css, /main > div:has\(\.pxl-transaction-workspace\)[\s\S]*max-width: none/)
  assert.match(css, /\.pxl-transaction-workspace[\s\S]*width: 100%/)
  assert.match(css, /\.pxl-transaction-info-card[\s\S]*min-height: 0/)
  assert.match(css, /--pxl-transaction-sidebar-width: 16rem/)
  const layout = readFileSync(join(root, 'src/components/document/DocumentLayout.tsx'), 'utf8')
  assert.match(layout, /lg:grid-cols-\[minmax\(0,1fr\)_15rem\]/)
  assert.match(layout, /xl:grid-cols-\[minmax\(0,1fr\)_16rem\]/)
  const shell = readFileSync(join(root, 'src/components/AppShell.tsx'), 'utf8')
  assert.match(shell, /TRANSACTION_ROUTE_ROOTS/)
  assert.match(shell, /isTransactionRoute \? 'w-full'/)
  for (const family of ['sales', 'purchase', 'journal', 'inventory', 'banking', 'neutral']) {
    const block = css.match(new RegExp(`\\.pxl-transaction-workspace--${family} \\{([\\s\\S]*?)\\}`))?.[1] || ''
    assert.match(block, /--pxl-transaction-accent/)
    assert.doesNotMatch(block, /header-bg|tabs-bg/, `${family} must not define a different header or tab surface`)
  }
})

test('transaction UI documentation has exactly two current authorities', () => {
  const standard = readFileSync(join(root, 'docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md'), 'utf8')
  const patterns = readFileSync(join(root, 'docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_PATTERNS.md'), 'utf8')
  assert.match(standard, /Sole authoritative transaction-workspace UI architecture/)
  assert.match(patterns, /Sole authoritative transaction-content variation standard/)

  const superseded = [
    'docs/PXL/archive/superseded-ui-standards/PXL_STANDARD_TRANSACTION_WORKSPACE.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_TRANSACTION_WORKSPACE_DESIGN_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_TRANSACTION_EXPERIENCE_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_SALES_INVOICE_UX_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_SALES_INVOICE_VIEW_UX_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_DESIGN_SYSTEM.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_COMPONENT_LIBRARY.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_BUTTON_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_CARD_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_COLOR_SYSTEM.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_FORM_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_TABLE_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_TAB_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/PXL_TYPOGRAPHY_STANDARD.md',
    'docs/PXL/archive/superseded-ui-standards/UI_UX_PRINCIPLES.md',
  ]
  for (const file of superseded) {
    const source = readFileSync(join(root, file), 'utf8')
    assert.match(source, /Status:\*\* SUPERSEDED|Status: SUPERSEDED/, `${file} must be explicitly non-authoritative`)
  }
})

test('field-source validation state stays explicit for non-reference transactions', () => {
  const reference = IMPLEMENTED_TRANSACTION_WORKSPACES.filter(row => row.fieldSourceGate === 'sales-invoice-reviewed-slice')
  assert.deepEqual(reference.map(row => row.key), ['sales-invoice'])
  assert.ok(
    IMPLEMENTED_TRANSACTION_WORKSPACES.every(row => row.key === 'sales-invoice' || row.fieldSourceGate === 'transaction-matrix-only'),
    'non-reference surfaces must not claim a validated Field Source Matrix',
  )
})
