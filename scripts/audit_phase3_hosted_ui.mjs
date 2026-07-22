import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const baseUrl = process.env.AUDIT_BASE_URL || 'http://127.0.0.1:5173';
const email = process.env.AUDIT_EMAIL || 'demo.admin@pxl.local';
const password = process.env.AUDIT_PASSWORD || 'PxlDemo123!';

const companies = [
  {
    name: 'Golden Retail Store',
    probes: [
      ['/customers', ['CUST-GOLDEN-CREDIT']],
      ['/suppliers', ['SUP-GOLDEN-GOODS']],
      ['/item-catalog', ['GRS-RICE-5KG']],
      ['/warehouses', ['WH-GOLDEN-HO', 'WH-GOLDEN-EAST']],
      ['/sales-invoices', ['DEMO-SP-NONVAT-HO-SI-000002', 'P3-GRS-SI-CREDIT']],
      ['/receipts', ['DEMO-SP-NONVAT-HO-OR-000001', 'P3-GRS-OR-PARTIAL']],
      ['/purchase-orders', ['DEMO-SP-NONVAT-HO-PO-000001', 'P3-GRS-PO-INVENTORY']],
      ['/vendor-bills', ['DEMO-SP-NONVAT-HO-VB-000001', 'P3-GRS-VB-INVENTORY']],
      ['/payment-vouchers', ['DEMO-SP-NONVAT-HO-PV-000001', 'P3-GRS-PV-PARTIAL']],
    ],
  },
  {
    name: 'ABC Trading Corporation',
    probes: [
      ['/customers', ['CUST-VAT-CREDIT', 'CUST-CWT']],
      ['/suppliers', ['SUP-VAT-INVENTORY', 'SUP-EWT-SERVICE']],
      ['/item-catalog', ['ITEM-STOCK-001', 'ABC-BULK-PAPER']],
      ['/warehouses', ['WH-MAIN', 'WH-CEBU']],
      ['/quotations', ['DEMO-CORP-VAT-HO-QT-000001']],
      ['/sales-orders', ['DEMO-CORP-VAT-HO-SO-000002']],
      ['/delivery-receipts', ['DEMO-CORP-VAT-HO-DR-000001']],
      ['/sales-invoices', ['DEMO-CORP-VAT-HO-SI-000004', 'P3-ABC-SI-LIFECYCLE']],
      ['/receipts', ['DEMO-CORP-VAT-HO-OR-000002', 'P3-ABC-OR-LIFECYCLE-PARTIAL']],
      ['/credit-memos', ['DEMO-CORP-VAT-HO-CM-000001']],
      ['/vendor-credits', ['DEMO-CORP-VAT-HO-VC-000001']],
      ['/cash-purchases', ['DEMO-CORP-VAT-HO-CP-000001']],
      ['/physical-count', ['P3-ABC-COUNT-JUNE']],
    ],
  },
  {
    name: 'Northstar Digital Solutions OPC',
    probes: [
      ['/customers', ['CUST-NORTHSTAR-MILESTONE']],
      ['/suppliers', ['SUP-NORTHSTAR-CLOUD']],
      ['/item-catalog', ['NS-RETAINER', 'NS-MILESTONE']],
      ['/sales-invoices', ['DEMO-OPC-NONVAT-HO-SI-000002', 'P3-NS-SI-RETAINER']],
      ['/receipts', ['DEMO-OPC-NONVAT-HO-OR-000001', 'P3-NS-OR-RETAINER']],
      ['/vendor-bills', ['DEMO-OPC-NONVAT-HO-VB-000001', 'P3-NS-VB-CLOUD']],
      ['/payment-vouchers', ['DEMO-OPC-NONVAT-HO-PV-000001', 'P3-NS-PV-CLOUD']],
    ],
  },
  {
    name: 'Prime Business Advisory Inc.',
    probes: [
      ['/customers', ['CUST-PRIME-RETAINER']],
      ['/suppliers', ['SUP-PRIME-PROF', 'SUP-PRIME-RENT']],
      ['/item-catalog', ['PBA-TAX-ADVISORY', 'PBA-RETAINER']],
      ['/sales-invoices', ['DEMO-SVC-VAT-HO-SI-000003', 'P3-PBA-SI-CWT-PARTIAL']],
      ['/receipts', ['DEMO-SVC-VAT-HO-OR-000001', 'P3-PBA-OR-CWT-PARTIAL']],
      ['/vendor-bills', ['DEMO-SVC-VAT-HO-VB-000001', 'P3-PBA-VB-PROF']],
      ['/payment-vouchers', ['DEMO-SVC-VAT-HO-PV-000001', 'P3-PBA-PV-PROF-PARTIAL']],
    ],
  },
  {
    name: 'Bayani Partners and Company',
    probes: [
      ['/customers', ['CUST-BAYANI-TRADE', 'CUST-BAYANI-SERVICE']],
      ['/suppliers', ['SUP-BAYANI-GOODS']],
      ['/item-catalog', ['BPC-PAPER-CASE', 'BPC-ADVISORY']],
      ['/warehouses', ['WH-BAYANI']],
      ['/sales-orders', ['DEMO-PARTNERSHIP-VAT-HO-SO-000001']],
      ['/delivery-receipts', ['DEMO-PARTNERSHIP-VAT-HO-DR-000001']],
      ['/sales-invoices', ['DEMO-PARTNERSHIP-VAT-HO-SI-000001', 'P3-BPC-SI-TRADE']],
      ['/receipts', ['DEMO-PARTNERSHIP-VAT-HO-OR-000001', 'P3-BPC-OR-TRADE']],
      ['/purchase-orders', ['DEMO-PARTNERSHIP-VAT-HO-PO-000001', 'P3-BPC-PO-PARTIAL']],
      ['/receiving-reports', ['DEMO-PARTNERSHIP-VAT-HO-RR-000001']],
      ['/vendor-bills', ['DEMO-PARTNERSHIP-VAT-HO-VB-000001', 'P3-BPC-VB-INVENTORY']],
      ['/payment-vouchers', ['DEMO-PARTNERSHIP-VAT-HO-PV-000001', 'P3-BPC-PV-PARTIAL']],
    ],
  },
];

const reportProbes = [
  ['/stock-balance', ['ITEM-STOCK-001', 'WH-MAIN']],
  ['/inventory-movements', ['ITEM-STOCK-001', 'Receipt']],
  ['/inventory-valuation', ['ITEM-STOCK-001']],
  ['/journal-entries', ['DEMO-CORP-VAT opening balances']],
  ['/general-ledger', ['Cash on Hand']],
  ['/trial-balance', ['GRAND TOTAL', 'Cash on Hand']],
  ['/ar-aging', ['Luzon Retail Group Inc.']],
  ['/ap-aging', ['National Office Depot Inc.']],
  ['/sales-registers', ['Sales Register']],
  ['/purchase-registers', ['Purchase Register']],
  ['/sales-tax-review', ['Output VAT']],
  ['/input-vat-review', ['Input VAT']],
  ['/ewt-summary', ['EWT']],
  ['/vat-output-summary', ['Output VAT']],
  ['/balance-sheet', ['Balance Sheet']],
  ['/income-statement', ['Income Statement']],
  ['/statement-of-cash-flows', ['Statement of Cash Flows']],
  ['/reports-branch-pnl', ['Branch']],
  ['/reports-department', ['Department']],
  ['/reports-cost-center', ['Cost Center']],
];

function hasRuntimeError(text) {
  return /Failed to load|relation .* does not exist|column .* does not exist|invalid input syntax|Error loading/i.test(text);
}

async function selectCompany(page, name) {
  await page.goto(`${baseUrl}/dashboard`, { waitUntil: 'networkidle', timeout: 20000 });
  const company = page.locator('select[title="Company"]');
  await company.selectOption({ label: name });
  await page.waitForTimeout(700);
  const branch = page.locator('select[title="Branch"]');
  const ho = await branch.locator('option').evaluateAll((options) => {
    const match = options.find((option) => /(^|\s)HO\s|HO\s—/.test(option.textContent || ''));
    return match?.value || '';
  });
  if (ho) await branch.selectOption(ho);
  await page.waitForTimeout(400);
}

async function setDateRangeAndRun(page, route) {
  if (route === '/trial-balance') {
    const rangeButton = page.getByRole('button', { name: 'By Date Range', exact: true });
    if (await rangeButton.count()) await rangeButton.click();
  }

  const dates = page.locator('input[type="date"]');
  const count = await dates.count();
  if (count >= 2) {
    await dates.nth(0).fill('2026-01-01');
    await dates.nth(1).fill('2026-07-16');
  } else if (count === 1 && /aging/.test(route)) {
    await dates.nth(0).fill('2026-07-16');
  }

  for (const label of ['Apply', 'Run', 'Generate', 'Load']) {
    const button = page.getByRole('button', { name: label, exact: true });
    if (await button.count() && await button.first().isVisible()) {
      if (await button.first().isEnabled()) await button.first().click();
      break;
    }
  }
  await page.waitForTimeout(1000);
}

async function probeRoute(page, companyName, route, expected, prepare = false) {
  const result = { company: companyName, route, expected, found: [], missing: [], status: 'Blocked' };
  try {
    await page.goto(`${baseUrl}${route}`, { waitUntil: 'networkidle', timeout: 20000 });
    await page.waitForTimeout(700);
    if (route === '/physical-count') {
      const history = page.getByRole('button', { name: 'History', exact: true });
      if (await history.count()) await history.click();
      await page.waitForTimeout(500);
    }
    if (prepare) await setDateRangeAndRun(page, route);
    const text = await page.locator('body').innerText();
    result.found = expected.filter((token) => text.includes(token));
    result.missing = expected.filter((token) => !text.includes(token));
    if (hasRuntimeError(text)) result.status = 'Failed';
    else if (result.missing.length === 0) result.status = 'Passed';
    else if (result.found.length > 0) result.status = 'Partially Passed';
    else result.status = 'Failed';
    result.tail = text.replace(/\s+/g, ' ').slice(-500);
  } catch (error) {
    result.status = 'Blocked';
    result.error = error instanceof Error ? error.message : String(error);
  }
  return result;
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 950 } });
const pageErrors = [];
page.on('pageerror', (error) => pageErrors.push(error.message));

const output = {
  baseUrl,
  login: 'not attempted',
  companyOptions: [],
  companyProbes: [],
  salesInvoiceDetail: {},
  reports: [],
  pageErrors,
};

await page.goto(baseUrl, { waitUntil: 'networkidle' });
if (await page.getByLabel('Email').count()) {
  // PXL-AUD-060: login fields resolve by accessible label, not CSS selectors.
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForSelector('select[title="Company"]', { timeout: 15000 });
}
output.login = 'passed';
await page.waitForFunction(() => document.querySelectorAll('select[title="Company"] option').length > 1);
output.companyOptions = await page.locator('select[title="Company"] option').evaluateAll((options) =>
  options.map((option) => option.textContent?.trim()).filter((label) => label && label !== 'Company')
);

for (const company of companies) {
  await selectCompany(page, company.name);
  for (const [route, expected] of company.probes) {
    output.companyProbes.push(await probeRoute(page, company.name, route, expected));
  }
}

await selectCompany(page, 'ABC Trading Corporation');
await page.goto(`${baseUrl}/sales-invoices`, { waitUntil: 'networkidle' });
const search = page.locator('input[placeholder*="Search SI"]');
await search.fill('P3-ABC-SI-LIFECYCLE');
await page.waitForTimeout(800);
const targetRow = page.locator('tr').filter({ hasText: 'DEMO-CORP-VAT-HO-SI-000004' }).first();
if (await targetRow.count()) {
  const open = targetRow.getByRole('link', { name: /Open/ });
  await open.click();
  await page.waitForLoadState('networkidle');
  await page.getByText('Bond Paper A4', { exact: true }).first().waitFor({ timeout: 10000 });
  const detail = {
    route: page.url().replace(baseUrl, ''),
    externalReferenceVisible: false,
    readOnly: false,
    tabs: [],
  };
  let body = await page.locator('body').innerText();
  detail.externalReferenceVisible = body.includes('P3-ABC-SI-LIFECYCLE');
  detail.readOnly = !(body.includes('Save Draft') || body.includes('Submit') || body.includes('Post Invoice'));
  const tabExpectations = {
    Lines: ['Bond Paper A4'],
    Financial: ['FINANCIAL COMPONENT'],
    'GL Impact': ['Accounts Receivable'],
    'Tax Impact': ['Output VAT'],
    Validation: ['FROZEN BY LIFECYCLE CONTROLS'],
    Audit: ['Audit'],
    'Related Docs': ['DEMO-CORP-VAT-HO-OR-000002'],
    'Related Party': ['Luzon Retail Group Inc.'],
  };
  for (const [tab, tokens] of Object.entries(tabExpectations)) {
    const button = page.getByRole('tab', { name: new RegExp(`^${tab}`) }).first();
    if (await button.count()) await button.click();
    await page.waitForTimeout(250);
    body = await page.locator('body').innerText();
    const missing = tokens.filter((token) => !body.includes(token));
    detail.tabs.push({ tab, status: missing.length ? 'Failed' : 'Passed', missing });
  }
  output.salesInvoiceDetail = detail;
} else {
  output.salesInvoiceDetail = { status: 'Failed', reason: 'Reference search did not return the hosted invoice.' };
}

await selectCompany(page, 'ABC Trading Corporation');
for (const [route, expected] of reportProbes) {
  output.reports.push(await probeRoute(page, 'ABC Trading Corporation', route, expected, true));
}

const failedCompanyProbes = output.companyProbes.filter((probe) => probe.status !== 'Passed');
const failedReports = output.reports.filter((probe) => probe.status !== 'Passed');
const failedDetailTabs = output.salesInvoiceDetail.tabs?.filter((tab) => tab.status !== 'Passed') || [];
const detailFailed = output.salesInvoiceDetail.status === 'Failed'
  || output.salesInvoiceDetail.externalReferenceVisible === false
  || output.salesInvoiceDetail.readOnly === false
  || failedDetailTabs.length > 0;
output.summary = {
  companyProbes: `${output.companyProbes.length - failedCompanyProbes.length}/${output.companyProbes.length} passed`,
  reports: `${output.reports.length - failedReports.length}/${output.reports.length} passed`,
  salesInvoiceDetail: detailFailed ? 'Failed' : 'Passed',
  pageErrors: output.pageErrors.length,
};

console.log(JSON.stringify(output, null, 2));
await browser.close();

if (failedCompanyProbes.length > 0 || failedReports.length > 0 || detailFailed || output.pageErrors.length > 0) {
  process.exitCode = 1;
}
