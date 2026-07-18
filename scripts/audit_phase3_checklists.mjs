import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const { chromium } = require('playwright')

const baseUrl = process.env.AUDIT_BASE_URL || 'http://127.0.0.1:5173'
const email = process.env.AUDIT_EMAIL || 'demo.admin@pxl.local'
const password = process.env.AUDIT_PASSWORD || 'PxlDemo123!'

const companyNames = [
  'Golden Retail Store',
  'ABC Trading Corporation',
  'Northstar Digital Solutions OPC',
  'Prime Business Advisory Inc.',
  'Bayani Partners and Company',
]

const browser = await chromium.launch({ headless: true })
const page = await browser.newPage({ viewport: { width: 1440, height: 950 } })
const result = { baseUrl, login: 'not attempted', companies: [] }

await page.goto(baseUrl, { waitUntil: 'networkidle' })
if (await page.locator('input[type="email"]').count()) {
  await page.locator('input[type="email"]').fill(email)
  await page.locator('input[type="password"]').fill(password)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await page.waitForSelector('select[title="Company"]', { timeout: 15000 })
  result.login = 'passed'
} else if (await page.locator('select[title="Company"]').count()) {
  result.login = 'already authenticated'
} else {
  result.login = 'failed'
  console.log(JSON.stringify(result, null, 2))
  await browser.close()
  process.exit(2)
}

for (const companyName of companyNames) {
  await page.goto(`${baseUrl}/company-setup`, { waitUntil: 'networkidle' })
  const row = page.locator('tbody tr').filter({ hasText: companyName })
  await row.getByRole('button', { name: 'Checklist' }).click()
  await page.getByRole('heading', { name: 'Company Setup Checklist' }).waitFor()
  await page.waitForFunction(() => !document.body.innerText.includes('Checking company setup...'))

  const summary = await page.locator('section').first().locator('p').first().innerText()
  const steps = await page.locator('section h2').evaluateAll((headings) => headings.map((heading) => {
    const rowElement = heading.closest('.grid')
    const badge = heading.parentElement?.querySelector('span')?.textContent?.trim() || ''
    const detail = heading.parentElement?.parentElement?.querySelector('p')?.textContent?.trim() || ''
    return {
      step: heading.textContent?.trim() || '',
      status: badge,
      detail,
      rowText: rowElement?.textContent?.replace(/\s+/g, ' ').trim() || '',
    }
  }))

  result.companies.push({ companyName, summary, steps })
}

console.log(JSON.stringify(result, null, 2))
await browser.close()
