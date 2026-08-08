/**
 * Sales Document Conversion browser contract.
 *
 * Database tests 138 and the committed lifecycle own quantity, cost,
 * concurrency, accounting, tax, and correction truth. These source checks keep
 * React limited to selecting quantities, invoking the one authority, rendering
 * backend progress, and navigating the unified trace.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const read = (path: string) => readFileSync(join(root, path), 'utf8')
const quotation = read('src/pages/QuotationsPage.tsx')
const order = read('src/pages/SalesOrdersPage.tsx')
const delivery = read('src/pages/DeliveryReceiptsPage.tsx')
const invoice = read('src/pages/SalesInvoicePage.tsx')
const invoiceDocument = read('src/pages/SalesInvoiceDocumentPage.tsx')
const trace = read('src/components/SalesDocumentTrace.tsx')
const salesPages = [quotation, order, delivery, invoice, invoiceDocument].join('\n')

test('Quotation to Order, Order to Delivery, and Delivery to Invoice use one conversion RPC', () => {
  assert.ok(order.includes("p_source_document_type: 'sales_quotation'"))
  assert.ok(delivery.includes("p_source_document_type: 'sales_order'"))
  assert.ok(delivery.includes("p_source_document_type: 'delivery_receipt'"))
  assert.ok(order.includes("supabase.rpc('fn_convert_sales_document'"))
  assert.ok(delivery.includes("supabase.rpc('fn_convert_sales_document'"))
})

test('remaining quantity comes from the backend progress view at every conversion stage', () => {
  for (const page of [order, delivery, invoice]) {
    assert.ok(page.includes("from('vw_sales_document_conversion_progress')"))
    assert.ok(page.includes('remaining_quantity'))
  }
  assert.ok(delivery.includes('original_quantity'))
  assert.ok(delivery.includes('converted_quantity'))
})

test('the browser never writes conversion lineage directly', () => {
  assert.doesNotMatch(salesPages, /from\(['"]document_relationships['"]\)[\s\S]{0,160}?\.(?:insert|update|upsert|delete)\(/)
  assert.doesNotMatch(salesPages, /fulfilled_quantity\s*[-+]=/)
})

test('partial billing is selected in the UI but admitted by the database', () => {
  assert.ok(delivery.includes('Quantity to bill for'))
  assert.ok(delivery.includes("p_target_document_type: 'sales_invoice'"))
  assert.ok(delivery.includes('Every line on this delivery has already been reserved for billing.'))
})

test('converted decisions and cancellations use governed lifecycle RPCs', () => {
  assert.ok(order.includes("supabase.rpc('fn_set_converted_sales_order_decision'"))
  assert.ok(order.includes("supabase.rpc('fn_cancel_sales_order'"))
  assert.ok(quotation.includes("supabase.rpc('fn_cancel_sales_quotation'"))
  assert.ok(delivery.includes("supabase.rpc('fn_update_converted_delivery_details'"))
})

test('converted commercial fields are locked while operational delivery identity stays editable', () => {
  assert.ok(order.includes('convertedDocument'))
  assert.ok(order.includes('Converted commercial fields are locked.'))
  assert.ok(invoice.includes('convertedInvoice'))
  assert.ok(invoice.includes('This draft is conversion-owned'))
  assert.ok(delivery.includes('Operational shipping and inventory identity fields remain editable'))
})

test('legitimate standalone Order, Delivery, and Sales Invoice paths remain available', () => {
  assert.ok(order.includes("from('sales_orders').insert"))
  assert.ok(delivery.includes("from('delivery_receipts').insert"))
  assert.ok(invoice.includes("supabase.rpc('fn_save_sales_invoice'"))
})

test('all sales documents expose one RLS-scoped forward and reverse trace', () => {
  assert.ok(trace.includes("from('vw_sales_document_trace')"))
  assert.ok(trace.includes('source_document_id.eq.'))
  assert.ok(trace.includes('target_document_id.eq.'))
  for (const page of [quotation, order, delivery, invoice, invoiceDocument]) {
    assert.ok(page.includes('SalesDocumentTrace'))
  }
})
