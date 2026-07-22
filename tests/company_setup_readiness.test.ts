import test from 'node:test'
import assert from 'node:assert/strict'
import {
  buildChecklistItems,
  summarizeReadiness,
  PRODUCTION_READINESS_NOTE,
  type ChecklistCompany,
  type ChecklistInput,
  type ItemStatus,
  type QueryResult,
} from '../src/lib/companySetupReadiness.ts'

const ok = <T>(data: T): QueryResult<T> => ({ data, error: null })
const okCount = (n: number): QueryResult<number> => ({ data: n, error: null })

const vatCompany: ChecklistCompany = {
  id: 'co-1',
  registered_name: 'ABC Trading Corporation',
  entity_type: 'corporation',
  tin: '000-000-000-000',
  tax_registration: 'vat',
  accounting_period: 'calendar',
  line_of_business: 'Trading',
  address_line_1: '1 Main St',
  address_line_2: 'Unit 2',
  city: 'Makati',
  province: 'NCR',
  zip_code: '1200',
  email: 'ap@abc.test',
  signatory_name: 'Jane Cruz',
  signatory_position: 'President',
  is_active: true,
}


// A fully core-ready + operationally-ready VAT trading company.
function readyInput(overrides: Partial<ChecklistInput> = {}): ChecklistInput {
  const base: ChecklistInput = {
    company: vatCompany,
    branches: ok([{ id: 'br-1', branch_code: 'MAIN', branch_name: 'Main' }]),
    fiscalYears: ok([{ year_name: 'FY2026' }]),
    periods: ok([{ period_name: 'Jul 2026' }]),
    accounts: ok([
      { account_type: 'asset' },
      { account_type: 'liability' },
      { account_type: 'equity' },
      { account_type: 'revenue' },
      { account_type: 'expense' },
    ]),
    series: ok([
      { branch_id: 'br-1', document_code: 'SI' },
      { branch_id: 'br-1', document_code: 'OR' },
      { branch_id: 'br-1', document_code: 'VB' },
      { branch_id: 'br-1', document_code: 'PV' },
    ]),
    profile: ok({
      vat_registered: true,
      percentage_tax_registered: false,
      ewt_registered: true,
      fwt_registered: false,
      is_active: true,
    }),
    vatCodes: ok([
      { transaction_type: 'input_vat', vat_classification: 'regular' },
      { transaction_type: 'output_vat', vat_classification: 'regular' },
    ]),
    atcCodes: ok([{ id: 'atc-ewt', tax_category: 'ewt' }]),
    ptCodes: ok([]),
    config: ok({
      ar_account_id: 'a', ap_account_id: 'b', default_cash_account_id: 'c',
      vat_payable_account_id: 'd', input_vat_account_id: 'e', ewt_withheld_account_id: null,
      ewt_payable_account_id: 'f', customer_advances_account_id: null, supplier_down_payments_account_id: null,
    }),
    customersCount: okCount(49),
    suppliersCount: okCount(39),
    itemsCount: okCount(42),
    inventoryItemsCount: okCount(22),
    warehousesCount: okCount(3),
    bankAccountsCount: okCount(2),
  }
  return { ...base, ...overrides }
}

const statusOf = (items: ReturnType<typeof buildChecklistItems>, id: string): ItemStatus =>
  items.find(item => item.id === id)!.status

test('fully-configured VAT trading company is both core and operationally ready', () => {
  const items = buildChecklistItems(readyInput())
  const summary = summarizeReadiness(items)
  assert.equal(summary.core.ready, true)
  assert.equal(summary.operational.ready, true)
  assert.equal(summary.core.remainingCount, 0)
  assert.equal(summary.operational.remainingCount, 0)
})

test('VAT codes are Not applicable for a non-VAT company', () => {
  const nonVat = readyInput({
    company: { ...vatCompany, tax_registration: 'non_vat' },
    profile: ok({
      vat_registered: false,
      percentage_tax_registered: true,
      ewt_registered: false,
      fwt_registered: false,
      is_active: true,
    }),
    vatCodes: ok([]),
    // percentage-tax registered requires a PT ATC
    atcCodes: ok([{ id: 'atc-pt', tax_category: 'pt' }]),
    ptCodes: ok([{ atc_id: 'atc-pt' }]),
    // no VAT GL fields required for non-VAT
    config: ok({
      ar_account_id: 'a', ap_account_id: 'b', default_cash_account_id: 'c',
      vat_payable_account_id: null, input_vat_account_id: null, ewt_withheld_account_id: null,
      ewt_payable_account_id: null, customer_advances_account_id: null, supplier_down_payments_account_id: null,
    }),
  })
  const items = buildChecklistItems(nonVat)
  assert.equal(statusOf(items, 'vat-codes'), 'not_required')
  // Not-applicable steps are excluded from the required core total.
  const summary = summarizeReadiness(items)
  assert.equal(summary.core.ready, true)
})

test('inventory warehousing is Not applicable for a service-only company', () => {
  const serviceOnly = readyInput({
    company: { ...vatCompany, tax_registration: 'non_vat', entity_type: 'opc' },
    profile: ok({
      vat_registered: false, percentage_tax_registered: true, ewt_registered: false,
      fwt_registered: false, is_active: true,
    }),
    vatCodes: ok([]),
    atcCodes: ok([{ id: 'atc-pt', tax_category: 'pt' }]),
    ptCodes: ok([{ atc_id: 'atc-pt' }]),
    config: ok({
      ar_account_id: 'a', ap_account_id: 'b', default_cash_account_id: 'c',
      vat_payable_account_id: null, input_vat_account_id: null, ewt_withheld_account_id: null,
      ewt_payable_account_id: null, customer_advances_account_id: null, supplier_down_payments_account_id: null,
    }),
    itemsCount: okCount(9),
    inventoryItemsCount: okCount(0),
    warehousesCount: okCount(0),
  })
  const items = buildChecklistItems(serviceOnly)
  assert.equal(statusOf(items, 'inventory-warehouse'), 'not_required')
  // Service-only company with customers/suppliers/items/bank is still operationally ready.
  const summary = summarizeReadiness(items)
  assert.equal(summary.operational.ready, true)
})

test('inventory warehousing is required when inventory items exist but no warehouse', () => {
  const items = buildChecklistItems(readyInput({
    inventoryItemsCount: okCount(10),
    warehousesCount: okCount(0),
  }))
  assert.equal(statusOf(items, 'inventory-warehouse'), 'incomplete')
  const summary = summarizeReadiness(items)
  assert.equal(summary.operational.ready, false)
})

test('operational false-positive is prevented: core ready but no operational masters', () => {
  const items = buildChecklistItems(readyInput({
    customersCount: okCount(0),
    suppliersCount: okCount(0),
    itemsCount: okCount(0),
    inventoryItemsCount: okCount(0),
    warehousesCount: okCount(0),
    bankAccountsCount: okCount(0),
  }))
  const summary = summarizeReadiness(items)
  // Core accounting is ready...
  assert.equal(summary.core.ready, true)
  // ...but the company is explicitly NOT operationally ready.
  assert.equal(summary.operational.ready, false)
  assert.equal(statusOf(items, 'customers'), 'incomplete')
  assert.equal(statusOf(items, 'suppliers'), 'incomplete')
  assert.equal(statusOf(items, 'items'), 'incomplete')
  assert.equal(statusOf(items, 'bank-accounts'), 'incomplete')
  // Service-only interpretation only when there are zero inventory items.
  assert.equal(statusOf(items, 'inventory-warehouse'), 'not_required')
})

test('core and operational readiness are computed independently', () => {
  // Core incomplete (no branch) but operational masters all present.
  const items = buildChecklistItems(readyInput({
    branches: ok([]),
    series: ok([]),
  }))
  const summary = summarizeReadiness(items)
  assert.equal(summary.core.ready, false)
  assert.equal(summary.operational.ready, true)
})

test('a verification error surfaces as an error status, not a false Ready', () => {
  const items = buildChecklistItems(readyInput({
    customersCount: { data: null, error: { message: 'permission denied' } },
  }))
  assert.equal(statusOf(items, 'customers'), 'error')
  const summary = summarizeReadiness(items)
  assert.equal(summary.operational.hasError, true)
  assert.equal(summary.operational.ready, false)
})

test('production readiness is never asserted by the checklist model', () => {
  const items = buildChecklistItems(readyInput())
  const summary = summarizeReadiness(items)
  // The model exposes only core and operational tiers; there is no production flag.
  assert.deepEqual(Object.keys(summary).sort(), ['core', 'operational'])
  assert.match(PRODUCTION_READINESS_NOTE, /never implied by a complete checklist/i)
})
