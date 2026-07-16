import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const baseUrl = process.env.AUDIT_BASE_URL || 'http://127.0.0.1:5173';
const email = process.env.AUDIT_EMAIL || 'demo.admin@pxl.local';
const password = process.env.AUDIT_PASSWORD || 'PxlDemo123!';

const probes = [
  { area: 'Setup', route: '/company-setup', tokens: ['ABC Trading Corporation', 'Golden Retail Store'] },
  { area: 'Setup', route: '/branch-setup', tokens: ['ABC Head Office', 'ABC Cebu Branch'] },
  { area: 'Setup', route: '/department-setup', tokens: ['Finance', 'CC-FIN'] },
  { area: 'Setup', route: '/number-series', tokens: ['SI', 'OR', 'VB', 'PV'] },
  { area: 'Master Data', route: '/customers', tokens: ['CUST-VAT-CREDIT', 'CUST-CWT'] },
  { area: 'Master Data', route: '/suppliers', tokens: ['SUP-VAT-INVENTORY', 'SUP-EWT-SERVICE'] },
  { area: 'Master Data', route: '/item-catalog', tokens: ['ITEM-STOCK-001', 'Consulting Service'] },
  { area: 'Master Data', route: '/warehouses', tokens: ['WH-MAIN', 'WH-CEBU'] },
  { area: 'Sales', route: '/quotations', tokens: ['Quotations'] },
  { area: 'Sales', route: '/sales-orders', tokens: ['TEST-SO-OPEN-PARTIAL'] },
  { area: 'Sales', route: '/delivery-receipts', tokens: ['Delivery Receipts'] },
  { area: 'Sales', route: '/sales-invoices', tokens: ['TEST-SI-STANDALONE', 'TEST-SI-VAT-INCLUSIVE'] },
  { area: 'Sales', route: '/receipts', tokens: ['TEST-OR-SI-STANDALONE'] },
  { area: 'Sales', route: '/credit-memos', tokens: ['Credit Memos'] },
  { area: 'Purchasing', route: '/purchase-orders', tokens: ['TEST-PO-PARTIAL-RECEIPT'] },
  { area: 'Purchasing', route: '/receiving-reports', tokens: ['Receiving Reports'] },
  { area: 'Purchasing', route: '/vendor-bills', tokens: ['TEST-VB-PARTIAL-PAYMENT'] },
  { area: 'Purchasing', route: '/payment-vouchers', tokens: ['TEST-PV-PARTIAL'] },
  { area: 'Purchasing', route: '/vendor-credits', tokens: ['Vendor Credits'] },
  { area: 'Inventory', route: '/stock-balance', tokens: ['ITEM-STOCK-001', 'WH-MAIN'] },
  { area: 'Inventory', route: '/inventory-movements', tokens: ['transfer_out', 'TEST-INV-TRANSFER-OK'] },
  { area: 'Inventory', route: '/stock-transfer', tokens: ['TEST-INV-TRANSFER-OK'] },
  { area: 'Inventory', route: '/stock-adjustment', tokens: ['TEST-INV-ADJ-POS'] },
  { area: 'Inventory', route: '/physical-count', tokens: ['Physical Count'] },
  { area: 'Banking', route: '/bank-accounts', tokens: ['BPI Demo Operating', 'BDO Demo Payroll'] },
  { area: 'Accounting', route: '/journal-entries', tokens: ['DEMO-CORP-VAT opening balances'] },
  { area: 'Accounting', route: '/general-ledger', tokens: ['Cash on Hand', 'Sales Revenue'] },
  { area: 'Accounting', route: '/trial-balance', tokens: ['Cash on Hand', 'Owner Capital'] },
  { area: 'Accounting', route: '/ar-aging', tokens: ['TEST-SI-INVENTORY', 'TEST-SI-VAT-INCLUSIVE'] },
  { area: 'Accounting', route: '/ap-aging', tokens: ['TEST-VB-PARTIAL-PAYMENT'] },
  { area: 'Compliance', route: '/sales-tax-review', tokens: ['TEST-SI-STANDALONE', 'Output VAT'] },
  { area: 'Compliance', route: '/input-vat-review', tokens: ['TEST-VB-PARTIAL-PAYMENT', 'Input VAT'] },
  { area: 'Compliance', route: '/ewt-summary', tokens: ['SUP-VAT-INVENTORY', '24.00'] },
  { area: 'Compliance', route: '/vat-output-summary', tokens: ['Output VAT'] },
  { area: 'Reports', route: '/balance-sheet', tokens: ['Balance Sheet'] },
  { area: 'Reports', route: '/income-statement', tokens: ['Income Statement'] },
];

function classify(text, tokens) {
  if (/Error|error|Failed to load|relation .* does not exist|column .* does not exist/i.test(text)) {
    return 'broken';
  }
  const found = tokens.filter((token) => text.includes(token));
  if (found.length === tokens.length) return 'visible';
  if (found.length > 0) return 'partially visible';
  return 'missing';
}

async function selectOptionByText(locator, matcher) {
  const value = await locator.evaluate((select, source) => {
    const pattern = new RegExp(source);
    const option = Array.from(select.options).find((entry) => pattern.test(entry.textContent || ''));
    return option?.value || '';
  }, matcher.source);
  if (!value) throw new Error(`No select option matched ${matcher}`);
  await locator.selectOption(value);
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 950 } });

const result = {
  baseUrl,
  login: 'not attempted',
  context: {},
  probes: [],
};

await page.goto(baseUrl, { waitUntil: 'networkidle' });
if (await page.locator('input[type="email"]').count()) {
  await page.locator('input[type="email"]').fill(email);
  await page.locator('input[type="password"]').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForFunction(() => !document.body.innerText.includes('Signing in...'), null, { timeout: 15000 });

  if (await page.getByText('Sign in', { exact: true }).count()) {
    result.login = 'failed';
    result.loginText = (await page.locator('body').innerText()).slice(0, 1000);
    console.log(JSON.stringify(result, null, 2));
    await browser.close();
    process.exit(2);
  }
} else if (await page.locator('select[title="Company"]').count()) {
  result.login = 'already authenticated';
} else {
  result.login = 'failed';
  result.loginText = (await page.locator('body').innerText()).slice(0, 1000);
  console.log(JSON.stringify(result, null, 2));
  await browser.close();
  process.exit(2);
}

if (result.login === 'not attempted') result.login = 'passed';
await page.waitForSelector('select[title="Company"]', { timeout: 15000 });
await page.locator('select[title="Company"]').selectOption({ label: 'ABC Trading Corporation' });
await page.waitForTimeout(800);
await selectOptionByText(page.locator('select[title="Branch"]'), /HO/);
await page.waitForTimeout(500);

result.context.companyOptions = await page.locator('select[title="Company"] option').evaluateAll((opts) => opts.map((o) => o.textContent?.trim()).filter(Boolean));
result.context.branchOptions = await page.locator('select[title="Branch"] option').evaluateAll((opts) => opts.map((o) => o.textContent?.trim()).filter(Boolean));
result.context.periodOptions = await page.locator('select[title="Period"] option').evaluateAll((opts) => opts.map((o) => o.textContent?.trim()).filter(Boolean).slice(0, 5));

for (const probe of probes) {
  const url = `${baseUrl}${probe.route}`;
  const entry = { ...probe, status: 'not run', found: [], missing: [] };
  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 });
    await page.waitForTimeout(700);
    const text = await page.locator('body').innerText({ timeout: 5000 });
    entry.found = probe.tokens.filter((token) => text.includes(token));
    entry.missing = probe.tokens.filter((token) => !text.includes(token));
    entry.status = classify(text, probe.tokens);
    entry.title = text.split('\n').map((s) => s.trim()).find(Boolean) || '';
    entry.sample = text.replace(/\s+/g, ' ').slice(0, 500);
  } catch (error) {
    entry.status = 'broken';
    entry.error = error instanceof Error ? error.message : String(error);
  }
  result.probes.push(entry);
}

console.log(JSON.stringify(result, null, 2));
await browser.close();
