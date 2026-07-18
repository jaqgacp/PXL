import { createRequire } from 'node:module'
import { mkdir, readFile } from 'node:fs/promises'

const require = createRequire(import.meta.url)
const { chromium } = require('playwright')

const baseUrl = process.env.PXL_WORKSPACE_BASE_URL || 'http://127.0.0.1:5173'
const outputDir = process.env.PXL_WORKSPACE_SCREENSHOT_DIR || '/tmp/pxl-transaction-workspaces'
const email = process.env.PXL_DEMO_EMAIL || 'demo.admin@pxl.local'
const password = process.env.PXL_DEMO_PASSWORD || 'PxlDemo123!'

const cases = [
  { key: 'sales-invoice-create', title: 'Sales Invoice', route: '/sales-invoices/new', open: 'none' },
  { key: 'sales-invoice-view', title: 'Sales Invoice', route: '/sales-invoices', token: 'DEMO-CORP-VAT-HO-SI-000004', open: 'link' },
  { key: 'vendor-bill-create', title: 'Vendor Bill', route: '/vendor-bills', open: 'new-button' },
  { key: 'cash-sale', title: 'Cash Sale', route: '/cash-sales', open: 'new-button' },
  { key: 'cash-purchase', title: 'Cash Purchase', route: '/cash-purchases', open: 'new-button' },
  { key: 'payment-voucher', title: 'Payment Voucher', route: '/payment-vouchers', open: 'new-button' },
  { key: 'journal-entry', title: 'Journal Entry', route: '/journal-entries', open: 'new-button' },
  { key: 'inventory-adjustment', title: 'Inventory Adjustment', route: '/stock-adjustment', open: 'none' },
  { key: 'official-receipt', title: 'Official Receipt', route: '/receipts', open: 'new-button' },
  { key: 'credit-memo', title: 'Credit Memo', route: '/credit-memos', open: 'new-button' },
  { key: 'asset-acquisition', title: 'Asset Acquisition', route: '/asset-acquisition', open: 'none' },
]

const expectedTabs = [
  'Lines', 'Financial', 'GL Impact', 'Tax Impact', 'Validation', 'Workflow', 'Approval',
  'Audit', 'Related Docs', 'Related Party', 'Attachments', 'Activity', 'Notes', 'System',
]

await mkdir(outputDir, { recursive: true })
const browser = await chromium.launch({ headless: true })
const page = await browser.newPage({ viewport: { width: 1440, height: 950 }, deviceScaleFactor: 1 })
const runtimeErrors = []
page.on('pageerror', error => runtimeErrors.push(error.message))

await page.goto(baseUrl, { waitUntil: 'networkidle' })
if (await page.locator('input[type="email"]').count()) {
  await page.locator('input[type="email"]').fill(email)
  await page.locator('input[type="password"]').fill(password)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await page.waitForSelector('select[title="Company"]')
}
await page.locator('select[title="Company"]').selectOption({ label: 'ABC Trading Corporation' })
await page.waitForFunction(() => document.querySelectorAll('select[title="Branch"] option').length > 1)
await page.locator('select[title="Branch"]').selectOption({ index: 1 })
await page.waitForTimeout(700)

const results = []
for (const testCase of cases) {
  const errorsBefore = runtimeErrors.length
  await page.goto(`${baseUrl}${testCase.route}`, { waitUntil: 'networkidle' })
  await page.waitForTimeout(600)

  if (testCase.open === 'new-button') {
    const newButton = page.locator('button').filter({ hasText: /new|create|add|record|receive/i }).first()
    if (!(await newButton.count())) throw new Error(`${testCase.title}: create action was not found; buttons=${JSON.stringify(await page.locator('button').allTextContents())}`)
    if (await newButton.isDisabled()) await newButton.evaluate(element => { element.removeAttribute('disabled'); element.click() })
    else await newButton.click()
    await page.waitForTimeout(700)
  } else if (testCase.open !== 'none') {
    const row = page.locator('tr').filter({ hasText: testCase.token }).first()
    if (!(await row.count())) throw new Error(`${testCase.title}: row containing ${testCase.token} was not found`)
    if (testCase.open === 'link') {
      const link = row.getByRole('link', { name: /Open/ }).first()
      if (await link.count()) await link.click()
      else await row.click()
    } else if (testCase.open === 'view-button') {
      await row.getByRole('button', { name: 'View', exact: true }).click()
    } else {
      await row.click()
    }
    await page.waitForTimeout(700)
  }

  for (const zoom of [0.9, 1]) {
    await page.evaluate(value => { document.body.style.zoom = String(value) }, zoom)
    await page.waitForTimeout(150)
    const workspace = page.locator(`[aria-label="${testCase.title} workspace"]`)
    if (await workspace.count() !== 1) throw new Error(`${testCase.title}: canonical workspace was not found`)
    let cardStatePersistence = true
    if (testCase.key === 'cash-purchase') {
      const referenceInput = workspace.getByLabel('Reference No.', { exact: true })
      const sentinel = `DENSITY-${Math.round(zoom * 100)}`
      const ownedByCard = await referenceInput.evaluate(element => Boolean(element.closest('.pxl-transaction-info-card')))
      await referenceInput.fill(sentinel)
      await workspace.getByRole('tab', { name: 'Financial', exact: true }).click()
      await workspace.getByRole('tab', { name: 'Lines', exact: true }).click()
      cardStatePersistence = ownedByCard && await referenceInput.inputValue() === sentinel
    }
    const visiblePanel = workspace.locator('[role="tabpanel"]:visible').first()
    const tabs = await workspace.locator('[role="tab"]').allTextContents()
    const normalizedTabs = tabs.map(label => label.replace(/\s*\([^)]*\)\s*$/, '').trim())
    const cardCount = await workspace.locator('.pxl-transaction-info-card').count()
    const topActionCount = await workspace.locator('.pxl-transaction-header__actions button').count()
    const duplicateBackCount = await visiblePanel.locator('button').filter({ hasText: /back/i }).count()
    const glDetailInLines = await visiblePanel.getByText(/^GL Impact(?:\s|$)/i).count()
    const measurements = await workspace.evaluate(node => {
      const header = node.querySelector('header')?.getBoundingClientRect()
      const sidebar = node.querySelector('aside')?.getBoundingClientRect()
      const infoBand = node.querySelector('.pxl-transaction-info-cards')?.getBoundingClientRect()
      const firstCard = node.querySelector('.pxl-transaction-info-card')
      const cardStyle = firstCard ? getComputedStyle(firstCard) : null
      const tabs = [...node.querySelectorAll('[role="tab"]')]
      const panel = [...node.querySelectorAll('[role="tabpanel"]')].find(candidate => getComputedStyle(candidate).display !== 'none')
      const panelRect = panel?.getBoundingClientRect()
      const firstDetail = panel?.querySelector('table, .pxl-empty-state')?.getBoundingClientRect()
      const lastChild = panel?.lastElementChild?.getBoundingClientRect()
      return {
        headerHeight: header?.height || 0,
        sidebarWidth: sidebar?.width || 0,
        sidebarTopDelta: sidebar && panelRect ? Math.abs(sidebar.top - panelRect.top) : 999,
        informationBandHeight: infoBand?.height || 0,
        workspaceWidth: node.getBoundingClientRect().width,
        viewportWidth: document.documentElement.clientWidth,
        tabRows: new Set(tabs.map(tab => Math.round(tab.getBoundingClientRect().top))).size,
        cardRadius: cardStyle?.borderRadius || '',
        cardPadding: cardStyle?.padding || '',
        viewportOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        headerCount: node.querySelectorAll('header').length,
        innerHeaderCount: panel?.querySelectorAll('.pxl-transaction-header').length || 0,
        lineDetailOffset: firstDetail && panelRect ? firstDetail.top - panelRect.top : 999,
        panelBottomWhitespace: lastChild && panelRect ? panelRect.bottom - lastChild.bottom : 999,
      }
    })
    const checks = {
      workspace: true,
      workflow: await workspace.locator('[aria-label="Transaction workflow status"]').count() === 1,
      informationCards: cardCount === 3,
      tabs: JSON.stringify(normalizedTabs) === JSON.stringify(expectedTabs),
      sidebar: await workspace.locator('aside').count() === 1,
      oneTabRow: measurements.tabRows === 1,
      fluidViewportUsage: measurements.workspaceWidth / measurements.viewportWidth >= 0.94,
      compactNaturalCards: measurements.informationBandHeight < 340 && measurements.cardRadius === '8px' && ['12px', '12px 12px'].includes(measurements.cardPadding),
      oneHeader: measurements.headerCount === 1 && measurements.innerHeaderCount === 0,
      topActions: topActionCount > 0,
      cardStatePersistence,
      noDuplicateBack: duplicateBackCount === 0,
      linesBeginWithDetail: measurements.lineDetailOffset <= 120,
      noDetailedGlInLines: glDetailInLines === 0,
      alignedSidebar: measurements.sidebarTopDelta <= 2,
      noArtificialPanelWhitespace: measurements.panelBottomWhitespace <= 30,
      noHorizontalViewportOverflow: measurements.viewportOverflow <= 1,
      noRuntimeErrors: runtimeErrors.length === errorsBefore,
    }
    const screenshot = `${outputDir}/${testCase.key}-${Math.round(zoom * 100)}.png`
    await page.screenshot({ path: screenshot, fullPage: true })
    results.push({ ...testCase, zoom, screenshot, checks, measurements: { ...measurements, cardCount, topActionCount, tabLabels: normalizedTabs }, result: Object.values(checks).every(Boolean) ? 'YES' : 'NO' })
  }
}

const referenceResult = results.find(result => result.key === 'sales-invoice-create' && result.zoom === 1)
const comparisonResults = results.filter(result => result.zoom === 1 && result.key !== 'sales-invoice-create')
const referenceImage = (await readFile(referenceResult.screenshot)).toString('base64')
const comparisonPage = await browser.newPage({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1 })
for (const result of comparisonResults) {
  const candidateImage = (await readFile(result.screenshot)).toString('base64')
  await comparisonPage.setContent(`<!doctype html><html><head><style>
    *{box-sizing:border-box}body{margin:0;background:#e5e7eb;font-family:Inter,Arial,sans-serif}
    main{display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:8px;align-items:start}
    figure{margin:0;background:white;border:1px solid #94a3b8;overflow:hidden}
    figcaption{position:sticky;top:0;z-index:1;background:#0f172a;color:white;padding:10px 14px;font-size:15px;font-weight:700}
    img{display:block;width:100%;height:auto}
  </style></head><body><main>
    <figure><figcaption>Sales Invoice create — 100%</figcaption><img src="data:image/png;base64,${referenceImage}"></figure>
    <figure><figcaption>${result.title} — ${result.result}</figcaption><img src="data:image/png;base64,${candidateImage}"></figure>
  </main></body></html>`, { waitUntil: 'load' })
  const comparisonScreenshot = `${outputDir}/sales-invoice-vs-${result.key}.png`
  await comparisonPage.screenshot({ path: comparisonScreenshot, fullPage: true })
  result.comparisonScreenshot = comparisonScreenshot
}

await browser.close()
process.stdout.write(`${JSON.stringify({ baseUrl, outputDir, results, runtimeErrors }, null, 2)}\n`)

if (results.some(result => result.result !== 'YES') || runtimeErrors.length > 0) process.exitCode = 1
