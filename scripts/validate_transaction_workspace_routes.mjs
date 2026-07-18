import { createRequire } from 'node:module'
import { readFile } from 'node:fs/promises'

const require = createRequire(import.meta.url)
const { chromium } = require('playwright')

const baseUrl = process.env.PXL_WORKSPACE_BASE_URL || 'http://127.0.0.1:5173'
const email = process.env.PXL_DEMO_EMAIL || 'demo.admin@pxl.local'
const password = process.env.PXL_DEMO_PASSWORD || 'PxlDemo123!'
const coverageSource = await readFile(new URL('../src/lib/transactionWorkspaceCoverage.ts', import.meta.url), 'utf8')
const cases = coverageSource.split('\n').flatMap(line => {
  const match = line.match(/\{ key: '([^']+)', transaction: '([^']+)', module: '[^']+', route: '([^']+)', page: '([^']+)'/)
  return match ? [{ key: match[1], title: match[2], route: match[3], page: match[4] }] : []
})

const expectedTabs = [
  'Lines', 'Financial', 'GL Impact', 'Tax Impact', 'Validation', 'Workflow', 'Approval',
  'Audit', 'Related Docs', 'Related Party', 'Attachments', 'Activity', 'Notes', 'System',
]

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
await page.waitForTimeout(500)
const branchSelector = page.locator('select[title="Branch"]')
if (await branchSelector.count()) {
  const firstBranch = await branchSelector.locator('option').evaluateAll(options => options.find(option => option.value)?.value || '')
  if (firstBranch) await branchSelector.selectOption(firstBranch)
}

const normalizeTabs = labels => labels.map(label => label.replace(/\s*\([^)]*\)\s*$/, '').trim())
const openWorkspaceFromList = async () => {
  const newButton = page.locator('button:not(:disabled)').filter({ hasText: /^(\+\s*)?(new|create|add|record|receive|start|run|transfer|replenish|reconcile|count)/i }).first()
  if (await newButton.count()) {
    await newButton.click()
    await page.waitForTimeout(350)
    if (await page.locator('[aria-label$=" workspace"]').count()) return
  }
  const viewButton = page.locator('tbody button:not(:disabled)').filter({ hasText: /^(view|edit|open)$/i }).first()
  if (await viewButton.count()) {
    await viewButton.click()
    await page.waitForTimeout(350)
    if (await page.locator('[aria-label$=" workspace"]').count()) return
  }
  const row = page.locator('tbody tr').first()
  if (await row.count()) {
    await row.click()
    await page.waitForTimeout(350)
  }
}
const results = []

for (const testCase of cases) {
  const errorsBefore = runtimeErrors.length
  const route = testCase.key === 'sales-invoice' ? '/sales-invoices/new' : testCase.route
  await page.goto(`${baseUrl}${route}`, { waitUntil: 'networkidle' })
  await page.waitForTimeout(300)

  let workspace = page.locator('[aria-label$=" workspace"]').first()
  if (!(await workspace.count())) {
    await openWorkspaceFromList()
    workspace = page.locator('[aria-label$=" workspace"]').first()
  }

  const found = await workspace.count() === 1
  const tabs = found ? normalizeTabs(await workspace.locator('[role="tab"]').allTextContents()) : []
  const geometry = found ? await workspace.evaluate(node => ({
    viewportOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    sidebarWidth: node.querySelector('aside')?.getBoundingClientRect().width || 0,
    tabRows: (() => {
      const tabs = [...node.querySelectorAll('[role="tab"]')]
      return new Set(tabs.map(tab => Math.round(tab.getBoundingClientRect().top))).size
    })(),
    headerCount: node.querySelectorAll('header').length,
    innerHeaderCount: [...node.querySelectorAll('[role="tabpanel"]')].filter(panel => getComputedStyle(panel).display !== 'none').reduce((count, panel) => count + panel.querySelectorAll('.pxl-transaction-header').length, 0),
    topActionCount: node.querySelectorAll('.pxl-transaction-header__actions button').length,
  })) : { viewportOverflow: 0, sidebarWidth: 0, tabRows: 0 }

  const checks = {
    workspace: found,
    workflow: found && await workspace.locator('[aria-label*="workflow status"]').count() === 1,
    informationCards: found && await workspace.locator('.pxl-transaction-info-card').count() === 3,
    fixedTabs: JSON.stringify(tabs) === JSON.stringify(expectedTabs),
    oneTabRow: geometry.tabRows === 1,
    sidebar: geometry.sidebarWidth > 0,
    oneHeader: geometry.headerCount === 1 && geometry.innerHeaderCount === 0,
    topActions: geometry.topActionCount > 0,
    noHorizontalViewportOverflow: geometry.viewportOverflow <= 1,
    noRuntimeErrors: runtimeErrors.length === errorsBefore,
  }
  results.push({ ...testCase, openedRoute: route, checks, result: Object.values(checks).every(Boolean) ? 'PASS' : 'FAIL' })
}

// Representative zoom and theme checks cover the canonical shell across each
// workspace family; all 41 routes above use the same responsive primitives.
const representativeRoutes = ['/sales-invoices/new', '/vendor-bills', '/stock-adjustment', '/journal-entries', '/payment-vouchers', '/asset-acquisition']
const responsive = []
for (const route of representativeRoutes) {
  for (const zoom of [0.9, 1, 1.1, 1.25]) {
    await page.goto(`${baseUrl}${route}`, { waitUntil: 'networkidle' })
    if (!(await page.locator('[aria-label$=" workspace"]').count())) {
      await openWorkspaceFromList()
    }
    await page.evaluate(value => { document.body.style.zoom = String(value) }, zoom)
    const workspace = page.locator('[aria-label$=" workspace"]').first()
    const measurement = await workspace.evaluate(node => ({
      tabsVisible: node.querySelectorAll('[role="tab"]').length,
      sidebarVisible: (node.querySelector('aside')?.getBoundingClientRect().width || 0) > 0,
      workspaceUsage: node.getBoundingClientRect().width / document.documentElement.clientWidth,
      viewportOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    }))
    responsive.push({ route, width: 1440, zoom, ...measurement, result: measurement.tabsVisible === 14 && measurement.sidebarVisible && measurement.workspaceUsage >= 0.94 && measurement.viewportOverflow <= 1 ? 'PASS' : 'FAIL' })
  }
}

const viewportCoverage = []
for (const width of [1366, 1440, 1600, 1920]) {
  await page.setViewportSize({ width, height: 950 })
  for (const route of representativeRoutes) {
    await page.goto(`${baseUrl}${route}`, { waitUntil: 'networkidle' })
    if (!(await page.locator('[aria-label$=" workspace"]').count())) await openWorkspaceFromList()
    const workspace = page.locator('[aria-label$=" workspace"]').first()
    const measurement = await workspace.evaluate(node => ({
      tabsVisible: node.querySelectorAll('[role="tab"]').length,
      sidebarWidth: node.querySelector('aside')?.getBoundingClientRect().width || 0,
      workspaceUsage: node.getBoundingClientRect().width / document.documentElement.clientWidth,
      viewportOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    }))
    viewportCoverage.push({ route, width, ...measurement, result: measurement.tabsVisible === 14 && measurement.sidebarWidth >= 238 && measurement.workspaceUsage >= 0.94 && measurement.viewportOverflow <= 1 ? 'PASS' : 'FAIL' })
  }
}

await page.setViewportSize({ width: 1440, height: 950 })
await page.goto(`${baseUrl}/sales-invoices/new`, { waitUntil: 'networkidle' })
await page.evaluate(() => document.documentElement.classList.add('dark'))
const darkMode = await page.locator('[aria-label="Sales Invoice workspace"]').evaluate(node => {
  const background = getComputedStyle(node).backgroundColor
  const text = getComputedStyle(node).color
  return { background, text, tabs: node.querySelectorAll('[role="tab"]').length, sidebar: Boolean(node.querySelector('aside')) }
})

await browser.close()
const report = { baseUrl, routeCount: cases.length, results, responsive, viewportCoverage, darkMode, runtimeErrors }
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`)
if (results.some(result => result.result !== 'PASS') || responsive.some(result => result.result !== 'PASS') || viewportCoverage.some(result => result.result !== 'PASS') || runtimeErrors.length > 0 || darkMode.tabs !== 14 || !darkMode.sidebar) process.exitCode = 1
