import test from 'node:test'
import assert from 'node:assert/strict'
import {
  applySalesInvoiceItemSelection,
  mergeSalesInvoiceCustomerDefaults,
  updateSalesInvoiceDraftLineField,
  type SalesInvoiceDraftLine,
} from '../src/lib/salesInvoiceDraftState.ts'

const line = (key: string): SalesInvoiceDraftLine => ({
  _key: key,
  item_id: '',
  description: '',
  quantity: 2,
  uom_id: '',
  uom_label: '',
  unit_price: 0,
  discount_percent: 0,
  discount_amount: 0,
  net_amount: 0,
  vat_code_id: '',
  vat_classification: 'regular',
  vat_rate: 12,
  vat_amount: 0,
  total_amount: 0,
  revenue_account_id: '',
  warehouse_id: '',
  department_id: 'dept-header',
  cost_center_id: 'cc-header',
  salesperson_id: 'sales-header',
  inventory_account_id: '',
  cogs_account_id: '',
  unit_cost: 0,
  inventory_cost: 0,
  inventory_transaction_id: '',
  remarks: '',
  source_document_type: '',
  source_line_id: '',
})

const vatCode = { id: 'vat-12', vat_classification: 'regular' as const, rate: 12 }
const itemA = {
  id: 'item-a',
  description: 'Inventory item A',
  uom_id: 'uom-ea',
  uom_label: 'EA',
  standard_selling_price: 100,
  standard_cost: 40,
  default_sales_vat_id: 'vat-12',
  sales_account_id: 'sales-a',
  item_type: 'inventory_item' as const,
  inventory_account_id: 'inventory-a',
  cogs_account_id: 'cogs-a',
}
const itemB = {
  ...itemA,
  id: 'item-b',
  description: 'Inventory item B',
  standard_selling_price: 150,
  sales_account_id: 'sales-b',
}

test('item selection updates only the selected line and documented item-derived fields', () => {
  const lines = [line('line-1'), line('line-2')]
  const updated = applySalesInvoiceItemSelection(lines, 'line-2', itemA, vatCode, 'warehouse-header', 'exclusive')

  assert.deepEqual(updated[0], lines[0])
  assert.equal(updated[1].item_id, 'item-a')
  assert.equal(updated[1].description, 'Inventory item A')
  assert.equal(updated[1].warehouse_id, 'warehouse-header')
  assert.equal(updated[1].quantity, 2)
  assert.equal(updated[1].department_id, 'dept-header')
  assert.equal(updated[1].cost_center_id, 'cc-header')
  assert.equal(updated[1].inventory_cost, 80)
})

test('line dimension change preserves all other lines and fields', () => {
  const lines = [line('line-1'), line('line-2')]
  const updated = updateSalesInvoiceDraftLineField(lines, 'line-2', 'warehouse_id', 'warehouse-2', [vatCode], 'exclusive')

  assert.deepEqual(updated[0], lines[0])
  assert.equal(updated[1].warehouse_id, 'warehouse-2')
  assert.equal(updated[1].department_id, 'dept-header')
  assert.equal(updated[1].cost_center_id, 'cc-header')
  assert.equal(updated[1].quantity, 2)
})

test('customer default merge preserves lines and unrelated draft fields', () => {
  const draft = {
    customer: 'old-customer',
    customerName: 'Old Customer',
    customerTin: '111-222-333-00000',
    customerAddress: 'Old Address',
    terms: 'terms-old',
    isCwt: false,
    cwtAtc: '',
    cwtExpected: 0,
    cwtBase: 0,
    reference: 'PO-1001',
    department: 'dept-1',
    lines: [line('line-1')],
  }

  const merged = mergeSalesInvoiceCustomerDefaults(draft, {
    id: 'new-customer',
    registered_name: 'New Customer',
    formatted_tin: '123-456-789-00000',
    registered_address: 'New Address',
    is_subject_to_cwt: true,
    default_cwt_atc_code_id: 'atc-1',
    default_terms_id: 'terms-new',
  })

  assert.equal(merged.customer, 'new-customer')
  assert.equal(merged.customerName, 'New Customer')
  assert.equal(merged.reference, 'PO-1001')
  assert.equal(merged.department, 'dept-1')
  assert.strictEqual(merged.lines, draft.lines)
})

test('rapid repeated item selection keeps the final selection', () => {
  let lines = [line('line-1')]
  lines = applySalesInvoiceItemSelection(lines, 'line-1', itemA, vatCode, 'warehouse-header', 'exclusive')
  lines = applySalesInvoiceItemSelection(lines, 'line-1', itemB, vatCode, 'warehouse-header', 'exclusive')

  assert.equal(lines[0].item_id, 'item-b')
  assert.equal(lines[0].description, 'Inventory item B')
  assert.equal(lines[0].revenue_account_id, 'sales-b')
})
