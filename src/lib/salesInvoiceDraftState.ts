export type SalesInvoiceDraftLine = {
  _key: string
  item_id: string
  description: string
  quantity: number
  uom_id: string
  uom_label: string
  unit_price: number
  discount_percent: number
  discount_amount: number
  net_amount: number
  vat_code_id: string
  vat_classification: 'regular' | 'zero_rated' | 'exempt'
  vat_rate: number
  vat_amount: number
  total_amount: number
  revenue_account_id: string
  warehouse_id: string
  department_id: string
  cost_center_id: string
  salesperson_id: string
  inventory_account_id: string
  cogs_account_id: string
  unit_cost: number
  inventory_cost: number
  inventory_transaction_id: string
  remarks: string
  source_document_type: string
  source_line_id: string
}

export type SalesInvoiceVatPriceBasis = 'exclusive' | 'inclusive'

export type SalesInvoiceVatCodeRef = {
  id: string
  vat_classification: SalesInvoiceDraftLine['vat_classification']
  rate: number
}

export type SalesInvoiceItemRef = {
  id: string
  description: string
  uom_id: string
  uom_label: string
  standard_selling_price: number
  standard_cost: number
  default_sales_vat_id: string | null
  sales_account_id: string | null
  item_type: 'inventory_item' | 'service' | 'non_inventory'
  inventory_account_id: string | null
  cogs_account_id: string | null
}

export type SalesInvoiceCustomerDefaults = {
  id: string
  registered_name: string
  formatted_tin: string
  registered_address: string
  is_subject_to_cwt: boolean
  default_cwt_atc_code_id: string | null
  default_terms_id: string | null
}

export type SalesInvoiceDraftSnapshot = {
  customer: string
  customerName: string
  customerTin: string
  customerAddress: string
  terms: string
  isCwt: boolean
  cwtAtc: string
  cwtExpected: number
  cwtBase: number
  lines: SalesInvoiceDraftLine[]
}

const round2 = (n: number) => Math.round(n * 100) / 100

export const computeSalesInvoiceDraftLine = (
  line: SalesInvoiceDraftLine,
  vatPriceBasis: SalesInvoiceVatPriceBasis = 'exclusive',
): SalesInvoiceDraftLine => {
  const commercialGross = line.unit_price * line.quantity
  const disc = commercialGross * (line.discount_percent / 100)
  const commercialAmount = commercialGross - disc
  const rateFactor = line.vat_rate / 100
  const isInclusiveVat = vatPriceBasis === 'inclusive' && line.vat_classification === 'regular' && rateFactor > 0
  const net = isInclusiveVat ? commercialAmount / (1 + rateFactor) : commercialAmount
  const vat = line.vat_classification === 'regular'
    ? isInclusiveVat
      ? commercialAmount - net
      : net * rateFactor
    : 0

  return { ...line, discount_amount: disc, net_amount: net, vat_amount: vat, total_amount: net + vat }
}

export const updateSalesInvoiceDraftLineField = (
  lines: SalesInvoiceDraftLine[],
  key: string,
  field: keyof SalesInvoiceDraftLine,
  value: string | number,
  vatCodes: SalesInvoiceVatCodeRef[],
  vatPriceBasis: SalesInvoiceVatPriceBasis,
) => lines.map(line => {
  if (line._key !== key) return line
  if (field === 'vat_code_id') {
    const vatCode = vatCodes.find(v => v.id === value)
    return computeSalesInvoiceDraftLine({
      ...line,
      vat_code_id: String(value),
      vat_classification: vatCode?.vat_classification || 'exempt',
      vat_rate: vatCode?.rate ?? 0,
    }, vatPriceBasis)
  }
  return computeSalesInvoiceDraftLine({ ...line, [field]: value }, vatPriceBasis)
})

export const applySalesInvoiceItemSelection = (
  lines: SalesInvoiceDraftLine[],
  key: string,
  item: SalesInvoiceItemRef,
  vatCode: SalesInvoiceVatCodeRef | null,
  headerWarehouseId: string,
  vatPriceBasis: SalesInvoiceVatPriceBasis,
) => lines.map(line => {
  if (line._key !== key) return line
  const unitCost = item.item_type === 'inventory_item'
    ? Number(line.unit_cost || item.standard_cost || 0)
    : 0
  const updated: SalesInvoiceDraftLine = {
    ...line,
    item_id: item.id,
    description: item.description,
    uom_id: item.uom_id,
    uom_label: item.uom_label,
    unit_price: item.standard_selling_price,
    vat_code_id: vatCode?.id || '',
    vat_classification: vatCode?.vat_classification || 'exempt',
    vat_rate: vatCode?.rate ?? 0,
    revenue_account_id: item.sales_account_id || '',
    warehouse_id: item.item_type === 'inventory_item' ? (line.warehouse_id || headerWarehouseId) : '',
    inventory_account_id: item.item_type === 'inventory_item' ? (item.inventory_account_id || '') : '',
    cogs_account_id: item.item_type === 'inventory_item' ? (item.cogs_account_id || '') : '',
    unit_cost: unitCost,
    inventory_cost: item.item_type === 'inventory_item' ? round2(line.quantity * unitCost) : 0,
  }
  return computeSalesInvoiceDraftLine(updated, vatPriceBasis)
})

export const mergeSalesInvoiceCustomerDefaults = <T extends SalesInvoiceDraftSnapshot>(
  draft: T,
  customer: SalesInvoiceCustomerDefaults,
): T => ({
  ...draft,
  customer: customer.id,
  customerName: customer.registered_name,
  customerTin: customer.formatted_tin,
  customerAddress: customer.registered_address,
  isCwt: customer.is_subject_to_cwt,
  cwtAtc: customer.is_subject_to_cwt ? customer.default_cwt_atc_code_id || '' : '',
  cwtExpected: customer.is_subject_to_cwt ? draft.cwtExpected : 0,
  cwtBase: customer.is_subject_to_cwt ? draft.cwtBase : 0,
  terms: customer.default_terms_id || draft.terms,
  lines: draft.lines,
})
