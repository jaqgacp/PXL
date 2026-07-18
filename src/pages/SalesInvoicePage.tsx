import { useState, useEffect, useCallback, useMemo, useRef, useLayoutEffect, type SetStateAction } from 'react'
import { createPortal } from 'react-dom'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection, StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import TaxImpactPanel from '@/components/document/TaxImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { composePhTin, formatPhTinInput, getPhTinBranch, phTinDigits } from '@/lib/philippines'
import {
  TransactionPageHeader,
  TransactionTabsBar,
  TransactionWorkflowBanner,
  type DocumentTab,
  type ToolbarAction,
} from '@/components/document/DocumentLayout'
import { TransactionInfoCard, TransactionInfoCards } from '@/components/document/TransactionPrimitives'
import {
  applySalesInvoiceItemSelection,
  computeSalesInvoiceDraftLine,
  mergeSalesInvoiceCustomerDefaults,
  updateSalesInvoiceDraftLineField,
} from '@/lib/salesInvoiceDraftState'
import {
  transactionButtonClass,
  transactionCardClass,
  transactionFieldLabelClass,
  transactionInputClass,
  transactionReadonlyFieldClass,
  transactionSectionTitleClass,
  transactionTableClass,
} from '@/lib/transactionWorkspace'

// ── Types ─────────────────────────────────────────────────────
type SIStatus = 'draft' | 'approved' | 'posted' | 'cancelled'

type SI = {
  id: string; company_id: string; branch_id: string
  si_number: string; date: string; customer_id: string
  customer_name_snapshot: string; customer_tin_snapshot: string
  customer_address_snapshot: string; payment_terms_id: string | null
  due_date: string | null; currency_code: string
  vat_price_basis: VatPriceBasis
  department_id: string | null; cost_center_id: string | null
  warehouse_id: string | null; salesperson_id: string | null
  account_owner_id: string | null
  reference: string | null; memo: string | null
  total_taxable_amount: number; total_zero_rated_amount: number
  total_exempt_amount: number; total_vat_amount: number
  total_amount: number; status: SIStatus
  cwt_amount_expected: number | null
  cwt_atc_code_id: string | null
  cwt_tax_base: number | null
  void_reason_id: string | null; approved_at?: string | null; posted_at: string | null
  created_at: string; updated_at: string
}

type SILine = {
  _key: string
  id?: string
  item_id: string
  description: string
  quantity: number
  uom_id: string; uom_label: string
  unit_price: number
  discount_percent: number
  discount_amount: number
  net_amount: number
  vat_code_id: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; vat_rate: number
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
type EditableSalesInvoiceLineField = keyof Omit<SILine, 'id'>

type SalesInvoiceDraft = {
  date: string
  branch: string
  customer: string
  customerName: string
  customerTin: string
  customerAddress: string
  terms: string
  dueDate: string
  currency: string
  vatPriceBasis: VatPriceBasis
  department: string
  costCenter: string
  warehouse: string
  salesperson: string
  accountOwner: string
  reference: string
  memo: string
  isCwt: boolean
  cwtExpected: number
  cwtAtc: string
  cwtBase: number
  lines: SILine[]
}

type CustomerRef = {
  id: string; customer_code: string; registered_name: string; trade_name: string | null
  business_style: string | null; customer_group: string | null
  tin: string; tin_branch_code: string
  registered_address: string; delivery_address: string | null
  contact_person: string | null; email: string | null; phone_number: string | null
  credit_limit: number | null; default_tax_type: string; is_subject_to_cwt: boolean
  default_terms_id: string | null; default_gl_account_id: string | null
  default_cwt_atc_code_id: string | null
  payment_terms?: { days_to_due: number; term_name: string } | null
}

type ItemRef = {
  id: string; item_code: string; description: string
  uom_id: string; uom_label: string; standard_selling_price: number
  standard_cost: number
  default_sales_vat_id: string | null; sales_account_id: string | null
  item_type: 'inventory_item' | 'service' | 'non_inventory'
  inventory_account_id: string | null
  cogs_account_id: string | null
  costing_method: string | null
}

type VATRef = {
  id: string; vat_code: string; description: string
  vat_classification: 'regular' | 'zero_rated' | 'exempt'; rate: number
}

type TaxRegistration = 'vat' | 'non_vat' | 'exempt'
type VatPriceBasis = 'exclusive' | 'inclusive'
type Branch = { id: string; branch_code: string; branch_name: string }
type DepartmentRef = { id: string; department_code: string; department_name: string }
type CostCenterRef = { id: string; cost_center_code: string; cost_center_name: string; department_id: string | null }
type WarehouseRef = { id: string; warehouse_code: string; warehouse_name: string; branch_id: string | null }
type EmployeeRef = { id: string; employee_number: string; first_name: string; last_name: string; department_id: string | null }
type VoidReason = { id: string; code: string; description: string }
type ATCCode = { id: string; code: string; description: string; rate: number }
type OpenSalesOrder = {
  id: string
  so_number: string
  so_date: string
  total_amount: number
  approval_status: string
  fulfillment_status: string
  currency_code: string
}
type SalesOrderLineRef = {
  item_id: string | null
  description: string
  quantity: number
  fulfilled_quantity: number
  uom_id: string | null
  unit_price: number
  discount_amount: number
}
type FormMode = 'list' | 'new' | 'edit' | 'view'
type FormTab = 'lines' | 'financial' | 'gl' | 'tax' | 'validation' | 'workflow' | 'approval' | 'audit' | 'related' | 'party' | 'attachments' | 'activity' | 'notes' | 'system'
type ValidationState = 'Passed' | 'Warning' | 'Blocked' | 'Informational' | 'Not Applicable'

type ValidationRow = {
  check: string
  status: ValidationState
  message: string
  resolution: string
  source: string
}

// ── Helpers ──────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const today = () => new Date().toISOString().split('T')[0]
const round2 = (n: number) => Math.round(n * 100) / 100
const formatDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'
const emptyText = (value?: string | number | null) =>
  value === null || value === undefined || value === '' ? 'Not recorded' : String(value)
const newLine = (): SILine => ({
  _key: crypto.randomUUID(),
  item_id: '', description: '', quantity: 1, uom_id: '', uom_label: '',
  unit_price: 0, discount_percent: 0, discount_amount: 0, net_amount: 0,
  vat_code_id: '', vat_classification: 'regular', vat_rate: 12, vat_amount: 0,
  total_amount: 0, revenue_account_id: '',
  warehouse_id: '', department_id: '', cost_center_id: '', salesperson_id: '',
  inventory_account_id: '', cogs_account_id: '', unit_cost: 0, inventory_cost: 0,
  inventory_transaction_id: '', remarks: '', source_document_type: '', source_line_id: '',
})

const blankDraft = (branchId: string): SalesInvoiceDraft => ({
  date: today(),
  branch: branchId,
  customer: '',
  customerName: '',
  customerTin: '',
  customerAddress: '',
  terms: '',
  dueDate: '',
  currency: 'PHP',
  vatPriceBasis: 'exclusive',
  department: '',
  costCenter: '',
  warehouse: '',
  salesperson: '',
  accountOwner: '',
  reference: '',
  memo: '',
  isCwt: false,
  cwtExpected: 0,
  cwtAtc: '',
  cwtBase: 0,
  lines: [newLine()],
})

const computeLine = (l: SILine, vatPriceBasis: VatPriceBasis = 'exclusive'): SILine => {
  return computeSalesInvoiceDraftLine(l, vatPriceBasis) as SILine
}

const computeTotals = (lines: SILine[]) => ({
  total_taxable_amount: lines.filter(l => l.vat_classification === 'regular').reduce((s, l) => s + l.net_amount, 0),
  total_zero_rated_amount: lines.filter(l => l.vat_classification === 'zero_rated').reduce((s, l) => s + l.net_amount, 0),
  total_exempt_amount: lines.filter(l => l.vat_classification === 'exempt').reduce((s, l) => s + l.net_amount, 0),
  total_vat_amount: lines.reduce((s, l) => s + l.vat_amount, 0),
  total_amount: lines.reduce((s, l) => s + l.total_amount, 0),
})

const buildDraftSignature = ({
  date,
  branch,
  customer,
  customerName,
  customerTin,
  customerAddress,
  terms,
  dueDate,
  currency,
  vatPriceBasis,
  department,
  costCenter,
  warehouse,
  salesperson,
  accountOwner,
  reference,
  memo,
  isCwt,
  cwtAtc,
  cwtExpected,
  cwtBase,
  lines,
}: {
  date: string
  branch: string
  customer: string
  customerName: string
  customerTin: string
  customerAddress: string
  terms: string
  dueDate: string
  currency: string
  vatPriceBasis: VatPriceBasis
  department: string
  costCenter: string
  warehouse: string
  salesperson: string
  accountOwner: string
  reference: string
  memo: string
  isCwt: boolean
  cwtAtc: string
  cwtExpected: number
  cwtBase: number
  lines: SILine[]
}) => JSON.stringify({
  date,
  branch,
  customer,
  customerName,
  customerTin,
  customerAddress,
  terms,
  dueDate,
  currency,
  vatPriceBasis,
  department,
  costCenter,
  warehouse,
  salesperson,
  accountOwner,
  reference,
  memo,
  isCwt,
  cwtAtc,
  cwtExpected: round2(cwtExpected),
  cwtBase: round2(cwtBase),
  lines: lines.map(line => ({
    item_id: line.item_id,
    description: line.description,
    quantity: line.quantity,
    uom_id: line.uom_id,
    uom_label: line.uom_label,
    unit_price: line.unit_price,
    discount_percent: line.discount_percent,
    vat_code_id: line.vat_code_id,
    vat_classification: line.vat_classification,
    vat_rate: line.vat_rate,
    revenue_account_id: line.revenue_account_id,
    warehouse_id: line.warehouse_id,
    department_id: line.department_id,
    cost_center_id: line.cost_center_id,
    salesperson_id: line.salesperson_id,
    inventory_account_id: line.inventory_account_id,
    cogs_account_id: line.cogs_account_id,
    remarks: line.remarks,
    source_document_type: line.source_document_type,
    source_line_id: line.source_line_id,
  })),
})

const buildSignatureFromDraft = (draft: SalesInvoiceDraft) => buildDraftSignature({
  date: draft.date,
  branch: draft.branch,
  customer: draft.customer,
  customerName: draft.customerName,
  customerTin: draft.customerTin,
  customerAddress: draft.customerAddress,
  terms: draft.terms,
  dueDate: draft.dueDate,
  currency: draft.currency,
  vatPriceBasis: draft.vatPriceBasis,
  department: draft.department,
  costCenter: draft.costCenter,
  warehouse: draft.warehouse,
  salesperson: draft.salesperson,
  accountOwner: draft.accountOwner,
  reference: draft.reference,
  memo: draft.memo,
  isCwt: draft.isCwt,
  cwtAtc: draft.cwtAtc,
  cwtExpected: draft.cwtExpected,
  cwtBase: draft.cwtBase,
  lines: draft.lines,
})

// ── Field style constants ────────────────────────────────────
const inp = `w-full ${transactionInputClass()}`
const ro  = `w-full cursor-default ${transactionReadonlyFieldClass()}`
const lbl = `mb-1 block ${transactionFieldLabelClass()}`
const celInp = 'pxl-body-text w-full border-0 bg-transparent px-0 py-0 tabular-nums focus:outline-none focus:ring-0'

// ── Status badge map ─────────────────────────────────────────
const statusToShared: Record<SIStatus, string> = {
  draft: 'draft', approved: 'approved', posted: 'posted', cancelled: 'error',
}

const validationBadgeClass = (status: ValidationState) => {
  if (status === 'Passed') return 'bg-green-50 text-green-700'
  if (status === 'Blocked') return 'bg-red-50 text-red-700'
  if (status === 'Warning') return 'bg-yellow-50 text-yellow-700'
  if (status === 'Informational') return 'bg-blue-50 text-blue-700'
  return 'bg-gray-100 text-gray-500'
}

type LookupPosition = { top: number; left: number; width: number }

const useLookupPosition = (
  open: boolean,
  anchorRef: React.RefObject<HTMLElement | null>,
  minWidth: number
) => {
  const [position, setPosition] = useState<LookupPosition | null>(null)

  const updatePosition = useCallback(() => {
    const anchor = anchorRef.current
    if (!anchor) return
    const rect = anchor.getBoundingClientRect()
    setPosition({
      top: rect.bottom + 4,
      left: Math.max(8, Math.min(rect.left, window.innerWidth - minWidth - 8)),
      width: Math.max(rect.width, minWidth),
    })
  }, [anchorRef, minWidth])

  useLayoutEffect(() => {
    if (!open) return
    updatePosition()
    window.addEventListener('resize', updatePosition)
    window.addEventListener('scroll', updatePosition, true)
    return () => {
      window.removeEventListener('resize', updatePosition)
      window.removeEventListener('scroll', updatePosition, true)
    }
  }, [open, updatePosition])

  return position
}

// ── Item search dropdown ──────────────────────────────────────
function ItemSearch({ items, value, onChange }: {
  items: ItemRef[]
  value: string
  onChange: (item: ItemRef) => void
}) {
  const [q, setQ] = useState('')
  const [open, setOpen] = useState(false)
  const [activeIndex, setActiveIndex] = useState(0)
  const ref = useRef<HTMLDivElement>(null)
  const dropdownRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const position = useLookupPosition(open, ref, 480)
  const selected = items.find(i => i.id === value)

  useEffect(() => {
    const h = (e: MouseEvent) => {
      const target = e.target as Node
      if (
        ref.current &&
        !ref.current.contains(target) &&
        dropdownRef.current &&
        !dropdownRef.current.contains(target)
      ) setOpen(false)
    }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [])

  const filtered = q ? items.filter(i =>
    i.item_code.toLowerCase().includes(q.toLowerCase()) ||
    i.description.toLowerCase().includes(q.toLowerCase())
  ).slice(0, 30) : items.slice(0, 30)

  useEffect(() => { setActiveIndex(0) }, [q])
  useEffect(() => {
    if (activeIndex >= filtered.length) setActiveIndex(Math.max(0, filtered.length - 1))
  }, [activeIndex, filtered.length])

  const choose = (item: ItemRef) => {
    onChange(item)
    setOpen(false)
    setQ('')
  }

  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (!open && ['ArrowDown', 'ArrowUp', 'Enter'].includes(event.key)) setOpen(true)
    if (event.key === 'ArrowDown') {
      event.preventDefault()
      setActiveIndex(i => Math.min(i + 1, Math.max(0, filtered.length - 1)))
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      setActiveIndex(i => Math.max(i - 1, 0))
    } else if (event.key === 'Enter') {
      if (open && filtered[activeIndex]) {
        event.preventDefault()
        choose(filtered[activeIndex])
      }
    } else if (event.key === 'Escape') {
      event.preventDefault()
      setOpen(false)
      setQ('')
    }
  }

  return (
    <div ref={ref} className="relative">
      <input
        ref={inputRef}
        className={celInp + ' border-b border-gray-200 pr-6'}
        value={open ? q : (selected ? `${selected.item_code} - ${selected.description}` : '')}
        placeholder="Search item..."
        onFocus={() => { setOpen(true); setQ('') }}
        onChange={e => { setQ(e.target.value); setOpen(true) }}
        onKeyDown={onKeyDown}
      />
      <button
        type="button"
        className="absolute right-0 top-1/2 -translate-y-1/2 px-1 text-gray-400 hover:text-gray-700"
        title="Open item lookup"
        onMouseDown={e => {
          e.preventDefault()
          setOpen(true)
          inputRef.current?.focus()
        }}
      >
        ▾
      </button>
      {open && position && createPortal(
        <div
          ref={dropdownRef}
          className="pxl-dialog z-[9999] max-h-72 overflow-y-auto"
          style={{ position: 'fixed', top: position.top, left: position.left, width: position.width }}
        >
          <div className="grid grid-cols-[9rem_1fr_5rem] gap-2 border-b border-[var(--pxl-border-medium)] bg-[var(--pxl-surface-table-header)] px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-gray-500">
            <span>Item Code</span>
            <span>Description</span>
            <span>UOM</span>
          </div>
          {filtered.length === 0 ? (
            <div className="px-3 py-4 text-center text-xs text-gray-400">No items found.</div>
          ) : filtered.map((i, index) => (
            <button
              key={i.id}
              type="button"
              className={`grid w-full grid-cols-[9rem_1fr_5rem] gap-2 border-b border-gray-100 px-3 py-2 text-left text-xs last:border-0 ${index === activeIndex ? 'bg-blue-50' : 'hover:bg-gray-50'}`}
              onMouseEnter={() => setActiveIndex(index)}
              onMouseDown={e => { e.preventDefault(); choose(i) }}
            >
              <span className="font-mono font-semibold text-gray-800">{i.item_code}</span>
              <span className="whitespace-normal text-gray-700">{i.description}</span>
              <span className="text-gray-500">{i.uom_label || 'Not set'}</span>
            </button>
          ))}
        </div>,
        document.body
      )}
    </div>
  )
}

function CustomerSearch({ customers, value, onChange }: {
  customers: CustomerRef[]
  value: string
  onChange: (customer: CustomerRef) => void
}) {
  const [q, setQ] = useState('')
  const [open, setOpen] = useState(false)
  const [activeIndex, setActiveIndex] = useState(0)
  const ref = useRef<HTMLDivElement>(null)
  const dropdownRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const position = useLookupPosition(open, ref, 680)
  const selected = customers.find(c => c.id === value)

  useEffect(() => {
    const h = (e: MouseEvent) => {
      const target = e.target as Node
      if (
        ref.current &&
        !ref.current.contains(target) &&
        dropdownRef.current &&
        !dropdownRef.current.contains(target)
      ) setOpen(false)
    }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [])

  const searchTerm = q.trim().toLowerCase()
  const searchDigits = phTinDigits(q)
  const filtered = searchTerm
    ? customers.filter(c => [
      c.customer_code,
      c.registered_name,
      c.trade_name || '',
      composePhTin(c.tin, c.tin_branch_code),
      phTinDigits(composePhTin(c.tin, c.tin_branch_code)),
      c.contact_person || '',
      c.registered_address,
    ].some(v => v.toLowerCase().includes(searchTerm) || Boolean(searchDigits && v.includes(searchDigits)))).slice(0, 10)
    : customers.slice(0, 30)

  useEffect(() => { setActiveIndex(0) }, [q])
  useEffect(() => {
    if (activeIndex >= filtered.length) setActiveIndex(Math.max(0, filtered.length - 1))
  }, [activeIndex, filtered.length])

  const choose = (customer: CustomerRef) => {
    onChange(customer)
    setOpen(false)
    setQ('')
  }

  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (!open && ['ArrowDown', 'ArrowUp', 'Enter'].includes(event.key)) setOpen(true)
    if (event.key === 'ArrowDown') {
      event.preventDefault()
      setActiveIndex(i => Math.min(i + 1, Math.max(0, filtered.length - 1)))
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      setActiveIndex(i => Math.max(i - 1, 0))
    } else if (event.key === 'Enter') {
      if (open && filtered[activeIndex]) {
        event.preventDefault()
        choose(filtered[activeIndex])
      }
    } else if (event.key === 'Escape') {
      event.preventDefault()
      setOpen(false)
      setQ('')
    }
  }

  return (
    <div ref={ref} className="relative">
      <input
        ref={inputRef}
        className={inp + ' pr-7'}
        value={open ? q : (selected ? `${selected.customer_code} - ${selected.registered_name}` : '')}
        placeholder="Search customer, code, TIN, contact, address..."
        onFocus={() => { setOpen(true); setQ('') }}
        onChange={e => { setQ(e.target.value); setOpen(true) }}
        onKeyDown={onKeyDown}
      />
      <button
        type="button"
        className="absolute right-1.5 top-1/2 -translate-y-1/2 rounded px-1 text-gray-400 hover:text-gray-700"
        title="Open customer lookup"
        onMouseDown={e => {
          e.preventDefault()
          setOpen(true)
          inputRef.current?.focus()
        }}
      >
        ▾
      </button>
      {open && position && createPortal(
        <div
          ref={dropdownRef}
          className="pxl-dialog z-[9999] max-h-80 max-w-[calc(100vw-1rem)] overflow-y-auto"
          style={{ position: 'fixed', top: position.top, left: position.left, width: position.width }}
        >
          <div className="grid grid-cols-[7rem_1fr_8rem_6rem_7rem] gap-2 border-b border-[var(--pxl-border-medium)] bg-[var(--pxl-surface-table-header)] px-3 py-1.5 text-xs font-semibold uppercase tracking-wide text-gray-500">
            <span>Code</span>
            <span>Customer</span>
            <span>TIN</span>
            <span>TIN Branch</span>
            <span>VAT Class</span>
          </div>
          {filtered.length === 0 ? (
            <div className="px-3 py-4 text-center text-xs text-gray-400">No customers match the search.</div>
          ) : filtered.map((c, index) => (
            <button
              key={c.id}
              type="button"
              className={`grid w-full grid-cols-[7rem_1fr_8rem_6rem_7rem] gap-2 border-b border-gray-100 px-3 py-2 text-left text-xs last:border-0 ${index === activeIndex ? 'bg-blue-50' : 'hover:bg-gray-50'}`}
              onMouseEnter={() => setActiveIndex(index)}
              onMouseDown={e => { e.preventDefault(); choose(c) }}
            >
              <span className="font-mono font-semibold text-gray-700">{c.customer_code}</span>
              <span className="min-w-0">
                <span className="block whitespace-normal font-medium text-gray-900">{c.registered_name}</span>
                <span className="block whitespace-normal text-[11px] text-gray-400">{c.trade_name || c.registered_address}</span>
              </span>
              <span className="font-mono text-gray-600">{composePhTin(c.tin, c.tin_branch_code)}</span>
              <span className="font-mono text-gray-600">{getPhTinBranch(c.tin, c.tin_branch_code)}</span>
              <span className="text-gray-500">{c.default_tax_type.replace(/_/g, ' ')}</span>
            </button>
          ))}
        </div>,
        document.body
      )}
    </div>
  )
}

// ── Main ──────────────────────────────────────────────────────
export default function SalesInvoicePage() {
  const { companyId, branchId } = useAppCtx()
  const navigate = useNavigate()
  const location = useLocation()
  const { id: routeInvoiceId } = useParams<{ id?: string }>()
  const routeMode = location.pathname.endsWith('/new')
    ? 'new'
    : location.pathname.endsWith('/edit')
      ? 'edit'
      : 'list'
  // Saved non-draft invoices open in the routed document workspace; drafts
  // open in the canonical draft-edit route.
  const openDocument = (si: SI) => {
    if (si.status === 'draft') navigate(`/sales-invoices/${si.id}/edit`)
    else navigate(`/sales-invoices/${si.id}`)
  }

  // Reference data
  const [customers, setCustomers] = useState<CustomerRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [vatCodes, setVatCodes] = useState<VATRef[]>([])
  const [cwtAtcCodes, setCwtAtcCodes] = useState<ATCCode[]>([])
  const [taxRegistration, setTaxRegistration] = useState<TaxRegistration>('vat')
  const [branches, setBranches] = useState<Branch[]>([])
  const [departments, setDepartments] = useState<DepartmentRef[]>([])
  const [costCenters, setCostCenters] = useState<CostCenterRef[]>([])
  const [warehouses, setWarehouses] = useState<WarehouseRef[]>([])
  const [employees, setEmployees] = useState<EmployeeRef[]>([])
  const [voidReasons, setVoidReasons] = useState<VoidReason[]>([])
  const [refsLoaded, setRefsLoaded] = useState(false)
  const [openSalesOrders, setOpenSalesOrders] = useState<OpenSalesOrder[]>([])
  const [salesOrderPromptDismissed, setSalesOrderPromptDismissed] = useState(false)

  // List state
  const [list, setList] = useState<SI[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<SIStatus | ''>('')
  const [totalCount, setTotalCount] = useState(0)
  const PAGE = 25
  const [page, setPage] = useState(0)

  // Form state
  const [mode, setMode] = useState<FormMode>(routeMode)
  const [activeTab, setActiveTab] = useState<FormTab>('lines')
  const [editSI, setEditSI] = useState<SI | null>(null)
  const [draft, setDraft] = useState<SalesInvoiceDraft>(() => blankDraft(branchId))
  const [persistedSignature, setPersistedSignature] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const initializedRouteKeyRef = useRef<string | null>(null)
  const draftInitializationTokenRef = useRef(0)
  const draftInitializationCountsRef = useRef<Record<string, number>>({})
  const recordDraftInitialization = useCallback((routeKey: string, reason: string) => {
    if (!import.meta.env.DEV && import.meta.env.MODE !== 'test') return
    const nextCount = (draftInitializationCountsRef.current[routeKey] || 0) + 1
    draftInitializationCountsRef.current[routeKey] = nextCount
    if (nextCount > 1) {
      console.warn('Sales Invoice draft initialization repeated for the same route.', {
        routeKey,
        reason,
        count: nextCount,
      })
    }
  }, [])

  const setDraftValue = useCallback(<K extends keyof SalesInvoiceDraft>(
    key: K,
    value: SetStateAction<SalesInvoiceDraft[K]>,
  ) => {
    setDraft(prev => ({
      ...prev,
      [key]: typeof value === 'function'
        ? (value as (current: SalesInvoiceDraft[K]) => SalesInvoiceDraft[K])(prev[key])
        : value,
    }))
  }, [])
  const setLines = useCallback((value: SetStateAction<SILine[]>) => setDraftValue('lines', value), [setDraftValue])
  const setFDate = useCallback((value: SetStateAction<string>) => setDraftValue('date', value), [setDraftValue])
  const setFBranch = useCallback((value: SetStateAction<string>) => setDraftValue('branch', value), [setDraftValue])
  const setFCustomer = useCallback((value: SetStateAction<string>) => setDraftValue('customer', value), [setDraftValue])
  const setFTerms = useCallback((value: SetStateAction<string>) => setDraftValue('terms', value), [setDraftValue])
  const setFDueDate = useCallback((value: SetStateAction<string>) => setDraftValue('dueDate', value), [setDraftValue])
  const setFVatPriceBasis = useCallback((value: SetStateAction<VatPriceBasis>) => setDraftValue('vatPriceBasis', value), [setDraftValue])
  const setFDepartment = useCallback((value: SetStateAction<string>) => setDraftValue('department', value), [setDraftValue])
  const setFCostCenter = useCallback((value: SetStateAction<string>) => setDraftValue('costCenter', value), [setDraftValue])
  const setFWarehouse = useCallback((value: SetStateAction<string>) => setDraftValue('warehouse', value), [setDraftValue])
  const setFSalesperson = useCallback((value: SetStateAction<string>) => setDraftValue('salesperson', value), [setDraftValue])
  const setFAccountOwner = useCallback((value: SetStateAction<string>) => setDraftValue('accountOwner', value), [setDraftValue])
  const setFRef = useCallback((value: SetStateAction<string>) => setDraftValue('reference', value), [setDraftValue])
  const setFMemo = useCallback((value: SetStateAction<string>) => setDraftValue('memo', value), [setDraftValue])
  const setFCwtExpected = useCallback((value: SetStateAction<number>) => setDraftValue('cwtExpected', value), [setDraftValue])
  const setFCwtBase = useCallback((value: SetStateAction<number>) => setDraftValue('cwtBase', value), [setDraftValue])
  const {
    date: fDate,
    branch: fBranch,
    customer: fCustomer,
    customerName: fCustomerName,
    customerTin: fCustomerTIN,
    customerAddress: fCustomerAddr,
    terms: fTerms,
    dueDate: fDueDate,
    currency: fCurrency,
    vatPriceBasis: fVatPriceBasis,
    department: fDepartment,
    costCenter: fCostCenter,
    warehouse: fWarehouse,
    salesperson: fSalesperson,
    accountOwner: fAccountOwner,
    reference: fRef,
    memo: fMemo,
    isCwt: fIsWithholdingAgent,
    cwtExpected: fCwtExpected,
    cwtAtc: fCwtAtc,
    cwtBase: fCwtBase,
    lines,
  } = draft

  // Void dialog
  const [showVoid, setShowVoid] = useState(false)
  const [voidReason, setVoidReason] = useState('')
  const [voidMemo, setVoidMemo] = useState('')
  const requiredConfig = useMemo<ConfigField[]>(
    () => taxRegistration === 'vat'
      ? ['ar_account_id', 'vat_payable_account_id']
      : ['ar_account_id'],
    [taxRegistration]
  )
  const readiness = useTransactionReadiness({
    companyId,
    branchId: mode === 'list' ? branchId : fBranch,
    documentCode: 'SI',
    postingDate: mode === 'list' ? today() : fDate,
    requiredConfig,
  })
  const allowsVatCode = useCallback((code: VATRef) => taxRegistration === 'vat' || code.rate === 0, [taxRegistration])
  const defaultVatCode = useCallback(() => vatCodes.find(allowsVatCode) || null, [allowsVatCode, vatCodes])
  const blankLineWithCurrentVat = useCallback((): SILine => {
    const vat = defaultVatCode()
    return {
      ...newLine(),
      vat_code_id: vat?.id || '',
      vat_classification: vat?.vat_classification || 'exempt',
      vat_rate: vat?.rate ?? 0,
    }
  }, [defaultVatCode])
  const emptyLine = useCallback((): SILine => ({
    ...blankLineWithCurrentVat(),
    department_id: fDepartment,
    cost_center_id: fCostCenter,
    salesperson_id: fSalesperson,
  }), [blankLineWithCurrentVat, fCostCenter, fDepartment, fSalesperson])

  // Load reference data
  useEffect(() => {
    if (!companyId) { setRefsLoaded(false); return }
    const load = async () => {
      setRefsLoaded(false)
      const [
        { data: company },
        { data: cos },
        { data: itms },
        { data: vcs },
        { data: atcs },
        { data: brs },
        { data: deps },
        { data: ccs },
        { data: whs },
        { data: emps },
        { data: vrs },
      ] =
        await Promise.all([
          supabase.from('companies').select('tax_registration').eq('id', companyId).single(),
          supabase.from('customers')
            .select('id,customer_code,customer_group,registered_name,trade_name,business_style,tin,tin_branch_code,registered_address,delivery_address,contact_person,email,phone_number,credit_limit,default_tax_type,is_subject_to_cwt,default_terms_id,default_gl_account_id,default_cwt_atc_code_id,payment_terms(days_to_due,term_name)')
            .eq('company_id', companyId).eq('is_active', true).order('registered_name'),
          supabase.from('items')
            .select('id,item_code,description,uom_id,units_of_measure(uom_code),standard_selling_price,standard_cost,default_sales_vat_id,sales_account_id,item_type,inventory_account_id,cogs_account_id,costing_method')
            .eq('company_id', companyId).eq('is_active', true).order('item_code'),
          supabase.from('vat_codes')
            .select('id,vat_code,description,vat_classification,tax_codes(rate)')
            .eq('transaction_type', 'output_vat').eq('is_active', true),
          supabase.from('atc_codes')
            .select('id,code,description,rate')
            .eq('is_active', true).eq('tax_category', 'ewt').order('code'),
          supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true),
          supabase.from('departments').select('id,department_code,department_name').eq('company_id', companyId).eq('is_active', true).order('department_code'),
          supabase.from('cost_centers').select('id,cost_center_code,cost_center_name,department_id').eq('company_id', companyId).eq('is_active', true).order('cost_center_code'),
          supabase.from('warehouses').select('id,warehouse_code,warehouse_name,branch_id').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
          supabase.from('employees').select('id,employee_number,first_name,last_name,department_id').eq('company_id', companyId).eq('is_active', true).order('last_name'),
          supabase.from('void_reason_codes').select('id,code,description').eq('is_active', true).order('code'),
        ])

      setCustomers((cos || []).map(c => ({
        ...c,
        payment_terms: Array.isArray(c.payment_terms) ? c.payment_terms[0] : c.payment_terms,
      })) as unknown as CustomerRef[])
      setTaxRegistration((company?.tax_registration as TaxRegistration) || 'vat')

      setItems((itms || []).map(i => ({
        ...i,
        uom_label: (Array.isArray(i.units_of_measure)
          ? i.units_of_measure[0]?.uom_code
          : (i.units_of_measure as { uom_code?: string } | null)?.uom_code) ?? '',
      })) as unknown as ItemRef[])

      const companyTaxRegistration = ((company?.tax_registration as TaxRegistration) || 'vat')
      setVatCodes((vcs || []).map(v => ({
        id: v.id, vat_code: v.vat_code, description: v.description,
        vat_classification: v.vat_classification,
        rate: (Array.isArray(v.tax_codes) ? v.tax_codes[0]?.rate : (v.tax_codes as { rate?: number } | null)?.rate) ?? 0,
      })).filter(v => companyTaxRegistration === 'vat' || v.rate === 0) as VATRef[])
      setCwtAtcCodes(atcs as ATCCode[] || [])

      setBranches(brs as Branch[] || [])
      setDepartments(deps as DepartmentRef[] || [])
      setCostCenters(ccs as CostCenterRef[] || [])
      setWarehouses(whs as WarehouseRef[] || [])
      setEmployees(emps as EmployeeRef[] || [])
      setVoidReasons(vrs as VoidReason[] || [])
      setRefsLoaded(true)
    }
    load()
  }, [companyId])

  // Load list
  const loadList = useCallback(async () => {
    if (!companyId) return
    setListLoading(true)
    let q = supabase.from('sales_invoices')
      .select('*', { count: 'exact' })
      .eq('company_id', companyId)
      .order('date', { ascending: false })
      .range(page * PAGE, page * PAGE + PAGE - 1)

    if (filterStatus) q = q.eq('status', filterStatus)
    if (search.trim()) {
      const s = `%${search.trim()}%`
      const tinSearch = formatPhTinInput(search)
      const tinClause = tinSearch && tinSearch !== search.trim()
        ? `,customer_tin_snapshot.ilike.%${tinSearch}%`
        : ''
      q = q.or(`si_number.ilike.${s},reference.ilike.${s},customer_name_snapshot.ilike.${s},customer_tin_snapshot.ilike.${s}${tinClause}`)
    }

    const { data, count } = await q
    setList((data || []) as unknown as SI[])
    setTotalCount(count || 0)
    setListLoading(false)
  }, [companyId, page, filterStatus, search])

  useEffect(() => { if (mode === 'list') loadList() }, [mode, loadList])

  const resetNewForm = useCallback(() => {
    draftInitializationTokenRef.current += 1
    const nextDraft = {
      ...blankDraft(branchId),
      lines: [blankLineWithCurrentVat()],
    }
    setEditSI(null)
    setDraft(nextDraft)
    setOpenSalesOrders([])
    setSalesOrderPromptDismissed(false)
    setPersistedSignature(buildSignatureFromDraft(nextDraft))
    setActiveTab('lines')
    setError('')
  }, [blankLineWithCurrentVat, branchId])

  const openNew = () => {
    if (readiness.blockers.length > 0) {
      setError('Complete company, branch, fiscal period, number series, and GL posting setup before creating a sales invoice.')
      return
    }
    navigate('/sales-invoices/new')
  }

  const openEdit = useCallback(async (si: SI) => {
    const initToken = ++draftInitializationTokenRef.current
    setEditSI(si)
    const cust = customers.find(c => c.id === si.customer_id)
    const nextIsCwt = cust?.is_subject_to_cwt ?? false
    const nextCwtExpected = si.cwt_amount_expected ? Number(si.cwt_amount_expected) : 0
    const nextCwtAtc = si.cwt_atc_code_id || cust?.default_cwt_atc_code_id || ''
    const nextCwtBase = si.cwt_tax_base ? Number(si.cwt_tax_base) : 0
    const baseDraft: SalesInvoiceDraft = {
      date: si.date,
      branch: si.branch_id,
      customer: si.customer_id,
      customerName: si.customer_name_snapshot,
      customerTin: si.customer_tin_snapshot,
      customerAddress: si.customer_address_snapshot,
      terms: si.payment_terms_id || '',
      dueDate: si.due_date || '',
      currency: si.currency_code,
      vatPriceBasis: si.vat_price_basis || 'exclusive',
      department: si.department_id || '',
      costCenter: si.cost_center_id || '',
      warehouse: si.warehouse_id || '',
      salesperson: si.salesperson_id || '',
      accountOwner: si.account_owner_id || '',
      reference: si.reference || '',
      memo: si.memo || '',
      isCwt: nextIsCwt,
      cwtExpected: nextCwtExpected,
      cwtAtc: nextCwtAtc,
      cwtBase: nextCwtBase,
      lines: [],
    }
    setError('')

    // Load existing lines
    const { data: dbLines } = await supabase
      .from('sales_invoice_lines')
      .select('*')
      .eq('sales_invoice_id', si.id)
      .order('line_number')
    if (initToken !== draftInitializationTokenRef.current) return

    if (dbLines && dbLines.length > 0) {
      const mapped: SILine[] = (dbLines as Array<Record<string, unknown>>).map(l => {
        const vc = vatCodes.find(v => v.id === String(l.vat_code_id || ''))
        return {
          _key: String(l.id), id: String(l.id),
          item_id: String(l.item_id || ''), description: String(l.description || ''),
          quantity: Number(l.quantity), uom_id: String(l.uom_id || ''), uom_label: '',
          unit_price: Number(l.unit_price), discount_percent: Number(l.discount_percent),
          discount_amount: Number(l.discount_amount), net_amount: Number(l.net_amount),
          vat_code_id: String(l.vat_code_id || ''),
          vat_classification: (vc?.vat_classification || 'regular') as SILine['vat_classification'],
          vat_rate: vc?.rate || 12,
          vat_amount: Number(l.vat_amount), total_amount: Number(l.total_amount),
          revenue_account_id: String(l.revenue_account_id || ''),
          warehouse_id: String(l.warehouse_id || ''),
          department_id: String(l.department_id || ''),
          cost_center_id: String(l.cost_center_id || ''),
          salesperson_id: String(l.salesperson_id || ''),
          inventory_account_id: String(l.inventory_account_id || ''),
          cogs_account_id: String(l.cogs_account_id || ''),
          unit_cost: Number(l.unit_cost || 0),
          inventory_cost: Number(l.inventory_cost || 0),
          inventory_transaction_id: String(l.inventory_transaction_id || ''),
          remarks: String(l.remarks || ''),
          source_document_type: String(l.source_document_type || ''),
          source_line_id: String(l.source_line_id || ''),
        }
      })
      const nextDraft = { ...baseDraft, lines: mapped }
      setDraft(nextDraft)
      setPersistedSignature(buildSignatureFromDraft(nextDraft))
    } else {
      const nextLines = [{
        ...blankLineWithCurrentVat(),
        department_id: si.department_id || '',
        cost_center_id: si.cost_center_id || '',
        salesperson_id: si.salesperson_id || '',
      }]
      const nextDraft = { ...baseDraft, lines: nextLines }
      setDraft(nextDraft)
      setPersistedSignature(buildSignatureFromDraft(nextDraft))
    }

    setActiveTab('lines')
    setMode(si.status === 'draft' ? 'edit' : 'view')
  }, [blankLineWithCurrentVat, customers, vatCodes])

  useEffect(() => {
    const routeKey = `${companyId || 'no-company'}:${routeMode}:${routeInvoiceId || 'new'}`
    if (routeMode === 'list') {
      initializedRouteKeyRef.current = routeKey
      setMode('list')
      setEditSI(null)
      setError('')
      return
    }
    if (!companyId || !refsLoaded) return
    if (initializedRouteKeyRef.current === routeKey) {
      setMode(routeMode)
      return
    }
    initializedRouteKeyRef.current = routeKey
    if (routeMode === 'new') {
      recordDraftInitialization(routeKey, 'new-document-route')
      resetNewForm()
      setMode('new')
      return
    }
    if (routeMode === 'edit' && routeInvoiceId) {
      let cancelled = false
      const loadInvoice = async () => {
        setError('')
        const { data, error: invoiceError } = await supabase
          .from('sales_invoices')
          .select('*')
          .eq('id', routeInvoiceId)
          .eq('company_id', companyId)
          .maybeSingle()
        if (cancelled) return
        if (invoiceError || !data) {
          setError(invoiceError?.message || 'Sales invoice not found.')
          setMode('edit')
          return
        }
        const invoice = data as unknown as SI
        if (invoice.status !== 'draft') {
          navigate(`/sales-invoices/${invoice.id}`, { replace: true })
          return
        }
        recordDraftInitialization(routeKey, 'edit-document-route')
        await openEdit(invoice)
      }
      void loadInvoice()
      return () => { cancelled = true }
    }
  }, [companyId, navigate, openEdit, recordDraftInitialization, refsLoaded, resetNewForm, routeInvoiceId, routeMode])

  // Customer auto-fill
  const updateDueDateFromTerms = useCallback((invoiceDate: string, customerId: string) => {
    const customer = customers.find(c => c.id === customerId)
    const pt = customer?.payment_terms
    if (!pt) return
    const due = new Date(invoiceDate)
    due.setDate(due.getDate() + pt.days_to_due)
    setFDueDate(due.toISOString().split('T')[0])
  }, [customers, setFDueDate])

  const onInvoiceDateChange = (value: string) => {
    setFDate(value)
    if (fCustomer) updateDueDateFromTerms(value, fCustomer)
  }

  const onCustomerChange = (id: string) => {
    const c = customers.find(x => x.id === id)
    if (!c) { setFCustomer(id); return }
    const hasEnteredLines = lines.some(l => l.item_id || l.description.trim() || l.unit_price > 0 || l.quantity !== 1)
    if (fCustomer && id !== fCustomer && hasEnteredLines) {
      const confirmed = window.confirm(
        'Changing the customer refreshes customer defaults and payment terms. Existing line prices, tax codes, accounts, and descriptions will be kept.'
      )
      if (!confirmed) return
    }
    setDraft(prev => {
      const merged = mergeSalesInvoiceCustomerDefaults(prev, {
        id,
        registered_name: c.registered_name,
        formatted_tin: composePhTin(c.tin, c.tin_branch_code),
        registered_address: c.registered_address,
        is_subject_to_cwt: c.is_subject_to_cwt,
        default_cwt_atc_code_id: c.default_cwt_atc_code_id,
        default_terms_id: c.payment_terms && c.default_terms_id ? c.default_terms_id : null,
      })
      if (c.payment_terms && c.default_terms_id) {
        const due = new Date(prev.date)
        due.setDate(due.getDate() + c.payment_terms.days_to_due)
        return { ...merged, dueDate: due.toISOString().split('T')[0] }
      }
      return merged
    })
    setSalesOrderPromptDismissed(false)
  }

  useEffect(() => {
    if (!companyId || !fCustomer || mode === 'list') {
      setOpenSalesOrders([])
      return
    }
    let alive = true
    const loadOpenSalesOrders = async () => {
      const { data } = await supabase
        .from('sales_orders')
        .select('id,so_number,so_date,total_amount,approval_status,fulfillment_status,currency_code')
        .eq('company_id', companyId)
        .eq('customer_id', fCustomer)
        .eq('approval_status', 'approved')
        .in('fulfillment_status', ['open', 'partial'])
        .order('so_date', { ascending: false })
        .limit(5)
      if (!alive) return
      setOpenSalesOrders((data || []) as OpenSalesOrder[])
    }
    void loadOpenSalesOrders()
    return () => { alive = false }
  }, [companyId, fCustomer, mode])

  // Item auto-fill per line
  const onItemChange = (key: string, item: ItemRef) => {
    const itemVat = vatCodes.find(v => v.id === item.default_sales_vat_id)
    const vc = itemVat && allowsVatCode(itemVat) ? itemVat : defaultVatCode()
    setLines(prev => applySalesInvoiceItemSelection(prev, key, item, vc, fWarehouse, fVatPriceBasis) as SILine[])
  }

  const onVatPriceBasisChange = (value: VatPriceBasis) => {
    setFVatPriceBasis(value)
    setLines(prev => prev.map(line => computeLine(line, value)))
  }

  // Line field change
  const setLineField = (key: string, field: EditableSalesInvoiceLineField, value: string | number) => {
    setLines(prev => updateSalesInvoiceDraftLineField(prev, key, field, value, vatCodes, fVatPriceBasis) as SILine[])
  }

  const convertFromSalesOrder = async (so: OpenSalesOrder) => {
    const { data, error: lineError } = await supabase
      .from('sales_order_lines')
      .select('item_id,description,quantity,fulfilled_quantity,uom_id,unit_price,discount_amount')
      .eq('sales_order_id', so.id)
      .order('line_number')
    if (lineError) {
      setError(lineError.message)
      return
    }
    const sourceLines = ((data || []) as SalesOrderLineRef[])
      .map(line => ({ ...line, quantity: Math.max(0, Number(line.quantity) - Number(line.fulfilled_quantity || 0)) }))
      .filter(line => line.quantity > 0)

    if (sourceLines.length === 0) {
      setError('No remaining Sales Order lines are available for conversion.')
      return
    }

    const converted = sourceLines.map(line => {
      const item = items.find(i => i.id === line.item_id)
      const itemVat = item ? vatCodes.find(v => v.id === item.default_sales_vat_id) : null
      const vc = itemVat && allowsVatCode(itemVat) ? itemVat : defaultVatCode()
      const gross = Number(line.quantity) * Number(line.unit_price)
      const discountPercent = gross > 0 ? (Number(line.discount_amount || 0) / gross) * 100 : 0
      return computeLine({
        _key: crypto.randomUUID(),
        item_id: line.item_id || '',
        description: line.description,
        quantity: Number(line.quantity),
        uom_id: line.uom_id || item?.uom_id || '',
        uom_label: item?.uom_label || '',
        unit_price: Number(line.unit_price),
        discount_percent: discountPercent,
        discount_amount: 0,
        net_amount: 0,
        vat_code_id: vc?.id || '',
        vat_classification: vc?.vat_classification || 'exempt',
        vat_rate: vc?.rate ?? 0,
        vat_amount: 0,
        total_amount: 0,
        revenue_account_id: item?.sales_account_id || '',
        warehouse_id: item?.item_type === 'inventory_item' ? fWarehouse : '',
        department_id: fDepartment,
        cost_center_id: fCostCenter,
        salesperson_id: fSalesperson,
        inventory_account_id: item?.inventory_account_id || '',
        cogs_account_id: item?.cogs_account_id || '',
        unit_cost: 0,
        inventory_cost: 0,
        inventory_transaction_id: '',
        remarks: '',
        source_document_type: 'sales_order',
        source_line_id: '',
      }, fVatPriceBasis)
    })

    setFRef(prev => prev || so.so_number)
    setLines(converted.length > 0 ? converted : [emptyLine()])
    setSalesOrderPromptDismissed(true)
    setActiveTab('lines')
    setError('')
  }

  const getAccountingReadinessErrors = () => {
    const activeLines = lines.filter(l => l.description.trim())
    const errors: string[] = []
    if (activeLines.length === 0) errors.push('At least one line item is required.')
    if (activeLines.some(l => !l.revenue_account_id)) {
      errors.push('Every line needs a revenue account. Set the item sales account before approval or posting.')
    }
    if (activeLines.some(l => !l.vat_code_id || !vatCodes.some(v => v.id === l.vat_code_id))) {
      errors.push('Every line needs an active output VAT code before approval or posting.')
    }
    const inventoryActiveLines = activeLines.filter(l => items.find(item => item.id === l.item_id)?.item_type === 'inventory_item')
    if (inventoryActiveLines.some(l => !(l.warehouse_id || fWarehouse))) {
      errors.push('Every inventory item line needs a warehouse before approval or posting.')
    }
    if (inventoryActiveLines.some(l => !l.inventory_account_id || !l.cogs_account_id)) {
      errors.push('Every inventory item line needs Inventory and COGS accounts from Item Master before approval or posting.')
    }
    return errors
  }

  // Save — atomic via RPC; status transitions are separate RPC calls
  const save = async (nextStatus?: SIStatus) => {
    if (!companyId || !fCustomer || !fBranch) {
      setError('Company, Branch, and Customer are required.')
      return
    }
    if (readiness.blockers.length > 0) {
      setError('Complete setup readiness blockers before saving or posting this sales invoice.')
      return
    }
    if (fIsWithholdingAgent && !fCwtAtc) {
      setError('Customer is subject to CWT but has no default active EWT ATC code.')
      return
    }
    if (lines.every(l => !l.description.trim())) {
      setError('At least one line item is required.')
      return
    }
    if (nextStatus === 'approved' || nextStatus === 'posted') {
      const accountingErrors = getAccountingReadinessErrors()
      if (accountingErrors.length > 0) {
        setError(accountingErrors[0])
        return
      }
    }
    setSaving(true)
    setError('')
    try {
      const totals = computeTotals(lines)
      const isNew = mode === 'new'
      const customerTin = composePhTin(fCustomerTIN, customers.find(c => c.id === fCustomer)?.tin_branch_code)

      const header = {
        company_id: companyId,
        branch_id: fBranch,
        date: fDate,
        customer_id: fCustomer,
        customer_name_snapshot: fCustomerName,
        customer_tin_snapshot: customerTin,
        customer_address_snapshot: fCustomerAddr,
        payment_terms_id: fTerms || null,
        due_date: fDueDate || null,
        currency_code: fCurrency,
        vat_price_basis: fVatPriceBasis,
        department_id: fDepartment || null,
        cost_center_id: fCostCenter || null,
        warehouse_id: fWarehouse || null,
        salesperson_id: fSalesperson || null,
        account_owner_id: fAccountOwner || null,
        reference: fRef || null,
        memo: fMemo || null,
        ...totals,
        cwt_amount_expected: fIsWithholdingAgent && fCwtExpected > 0 ? fCwtExpected : null,
        cwt_atc_code_id: fIsWithholdingAgent && fCwtExpected > 0 ? fCwtAtc || null : null,
        cwt_tax_base: fIsWithholdingAgent && fCwtExpected > 0 ? fCwtBase || null : null,
      }

      const linesPayload = lines
        .filter(l => l.description.trim())
        .map((l, i) => ({
          line_number: i + 1,
          item_id: l.item_id || null,
          description: l.description,
          quantity: l.quantity,
          uom_id: l.uom_id || null,
          unit_price: l.unit_price,
          discount_percent: l.discount_percent,
          discount_amount: l.discount_amount,
          net_amount: l.net_amount,
          vat_code_id: l.vat_code_id || null,
          vat_amount: l.vat_amount,
          total_amount: l.total_amount,
          revenue_account_id: l.revenue_account_id || null,
          warehouse_id: (items.find(item => item.id === l.item_id)?.item_type === 'inventory_item' ? (l.warehouse_id || fWarehouse) : l.warehouse_id) || null,
          department_id: l.department_id || fDepartment || null,
          cost_center_id: l.cost_center_id || fCostCenter || null,
          salesperson_id: l.salesperson_id || fSalesperson || null,
          inventory_account_id: l.inventory_account_id || null,
          cogs_account_id: l.cogs_account_id || null,
          remarks: l.remarks || null,
          source_document_type: l.source_document_type || null,
          source_line_id: l.source_line_id || null,
        }))

      const { data: siId, error: saveErr } = await supabase.rpc('fn_save_sales_invoice', {
        p_invoice_id: (isNew ? null : editSI!.id)!,
        p_header: header,
        p_lines: linesPayload,
      })
      if (saveErr) throw saveErr

      // Status transitions: approve first if going to approved or posted
      const currentStatus = isNew ? 'draft' : (editSI?.status || 'draft')
      if ((nextStatus === 'approved' || nextStatus === 'posted') && currentStatus === 'draft') {
        const { error: appErr } = await supabase.rpc('fn_approve_sales_invoice', { p_invoice_id: siId })
        if (appErr) throw appErr
      }
      if (nextStatus === 'posted') {
        const { error: postErr } = await supabase.rpc('fn_post_sales_invoice', { p_invoice_id: siId })
        if (postErr) throw postErr
      }

      navigate('/sales-invoices')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Save failed.')
    }
    setSaving(false)
  }

  // Void — SECURITY DEFINER RPC bypasses RLS for posted/approved rows
  const doVoid = async () => {
    if (!editSI || !voidReason) return
    setSaving(true)
    const { error: e } = await supabase.rpc('fn_void_sales_invoice', {
      p_invoice_id: editSI.id,
      p_void_reason_id: voidReason,
      p_memo: voidMemo || undefined,
    })
    if (e) { setError(e.message); setSaving(false); return }
    setShowVoid(false)
    navigate('/sales-invoices')
    setSaving(false)
  }

  const doRevertToDraft = async () => {
    if (!editSI) return
    setSaving(true)
    const { error: e } = await supabase.rpc('fn_revert_si_to_draft', { p_invoice_id: editSI.id })
    if (e) { setError(e.message); setSaving(false); return }
    await openEdit({ ...editSI, status: 'draft' } as SI)
    setSaving(false)
  }

  useEffect(() => {
    if (mode !== 'new' && mode !== 'edit') return
    if (!fIsWithholdingAgent) {
      setFCwtBase(prev => prev === 0 ? prev : 0)
      setFCwtExpected(prev => prev === 0 ? prev : 0)
      return
    }

    const atc = cwtAtcCodes.find(a => a.id === fCwtAtc)
    if (!atc) {
      setFCwtBase(prev => prev === 0 ? prev : 0)
      setFCwtExpected(prev => prev === 0 ? prev : 0)
      return
    }

    const currentTotals = computeTotals(lines)
    const base = round2(
      currentTotals.total_taxable_amount +
      currentTotals.total_zero_rated_amount +
      currentTotals.total_exempt_amount
    )
    const expected = round2(base * atc.rate / 100)
    setFCwtBase(prev => Math.abs(prev - base) > 0.005 ? base : prev)
    setFCwtExpected(prev => Math.abs(prev - expected) > 0.005 ? expected : prev)
  }, [cwtAtcCodes, fCwtAtc, fIsWithholdingAgent, lines, mode, setFCwtBase, setFCwtExpected])

  const totals = computeTotals(lines)
  const revenueImpactRows = useMemo<GLImpactRow[]>(() => Array.from(
    lines.reduce((map, line) => {
      const key = line.revenue_account_id || 'missing_revenue_account'
      const existing = map.get(key) || {
        accountId: line.revenue_account_id || null,
        accountLabel: line.revenue_account_id ? undefined : 'Missing revenue account',
        accountSourceLabel: line.revenue_account_id ? 'Revenue Account from Item' : 'Missing Revenue Account',
        technicalSource: line.revenue_account_id ? 'document_line_account' : 'missing_revenue_account',
        impactGroup: 'COMMERCIAL' as const,
        accountingEffect: 'REVENUE',
        sourceLabel: 'Invoice Line',
        description: 'Sales revenue',
        debit: 0,
        credit: 0,
      }
      existing.credit += line.net_amount
      map.set(key, existing)
      return map
    }, new Map<string, GLImpactRow>()).values()
  ), [lines])
  const inventoryImpactRows = useMemo<GLImpactRow[]>(() => {
    const rows: GLImpactRow[] = []
    for (const line of lines) {
      if (!line.item_id || !line.description.trim()) continue
      const item = items.find(candidate => candidate.id === line.item_id)
      if (item?.item_type !== 'inventory_item') continue

      const unitCost = Number(line.unit_cost || item.standard_cost || 0)
      const totalCost = round2(Number(line.quantity || 0) * unitCost)
      if (totalCost <= 0.005) continue

      const label = item.item_code || line.description || 'Inventory item'
      const cogsAccountId = line.cogs_account_id || item.cogs_account_id
      const inventoryAccountId = line.inventory_account_id || item.inventory_account_id

      rows.push({
        accountId: cogsAccountId || null,
        accountLabel: cogsAccountId ? undefined : 'Missing COGS account',
        accountSourceLabel: 'COGS Account from Item',
        technicalSource: cogsAccountId ? 'item_cogs_account_id' : 'missing_cogs_account',
        impactGroup: 'INVENTORY',
        accountingEffect: 'COGS',
        sourceLabel: 'Invoice Line',
        itemId: item.id,
        itemCode: item.item_code,
        warehouseId: line.warehouse_id || fWarehouse || null,
        warehouseCode: warehouses.find(warehouse => warehouse.id === (line.warehouse_id || fWarehouse))?.warehouse_code || null,
        quantity: line.quantity,
        unitCost,
        totalCost,
        valuationMethod: item.costing_method || 'weighted_average',
        description: `COGS - ${label}`,
        debit: totalCost,
        credit: 0,
      })
      rows.push({
        accountId: inventoryAccountId || null,
        accountLabel: inventoryAccountId ? undefined : 'Missing Inventory account',
        accountSourceLabel: 'Inventory Account from Item',
        technicalSource: inventoryAccountId ? 'item_inventory_account_id' : 'missing_inventory_account',
        impactGroup: 'INVENTORY',
        accountingEffect: 'INVENTORY',
        sourceLabel: 'Invoice Line',
        itemId: item.id,
        itemCode: item.item_code,
        warehouseId: line.warehouse_id || fWarehouse || null,
        warehouseCode: warehouses.find(warehouse => warehouse.id === (line.warehouse_id || fWarehouse))?.warehouse_code || null,
        quantity: line.quantity,
        unitCost,
        totalCost,
        valuationMethod: item.costing_method || 'weighted_average',
        description: `Inventory - ${label}`,
        debit: 0,
        credit: totalCost,
      })
    }
    return rows
  }, [fWarehouse, items, lines, warehouses])
  const glImpactRows = useMemo<GLImpactRow[]>(() => [
    {
      configKey: 'ar_account_id',
      impactGroup: 'COMMERCIAL',
      accountingEffect: 'RECEIVABLE',
      sourceLabel: 'Invoice Header',
      description: 'Accounts receivable',
      debit: totals.total_amount,
      credit: 0,
    },
    ...revenueImpactRows,
    ...(totals.total_vat_amount > 0
      ? [{
        configKey: 'vat_payable_account_id' as const,
        impactGroup: 'COMMERCIAL' as const,
        accountingEffect: 'TAX',
        sourceLabel: 'Tax Calculation',
        description: 'Output VAT payable',
        debit: 0,
        credit: totals.total_vat_amount,
      }]
      : []),
    ...inventoryImpactRows,
  ], [inventoryImpactRows, revenueImpactRows, totals.total_amount, totals.total_vat_amount])
  const commercialGlRows = glImpactRows.filter(row => row.impactGroup !== 'INVENTORY')
  const inventoryGlRows = glImpactRows.filter(row => row.impactGroup === 'INVENTORY')
  const commercialGlDebit = commercialGlRows.reduce((sum, row) => sum + row.debit, 0)
  const commercialGlCredit = commercialGlRows.reduce((sum, row) => sum + row.credit, 0)
  const inventoryGlDebit = inventoryGlRows.reduce((sum, row) => sum + row.debit, 0)
  const inventoryGlCredit = inventoryGlRows.reduce((sum, row) => sum + row.credit, 0)
  const combinedGlDebit = commercialGlDebit + inventoryGlDebit
  const combinedGlCredit = commercialGlCredit + inventoryGlCredit
  const combinedGlDifference = combinedGlDebit - combinedGlCredit
  const readOnly = mode === 'view'
  const canEdit = mode === 'edit' || mode === 'new'
  const siStatus = editSI?.status || 'draft'
  const currentDraftSignature = useMemo(() => buildSignatureFromDraft(draft), [draft])
  const hasUnsavedChanges = canEdit && currentDraftSignature !== persistedSignature
  useEffect(() => {
    if (!hasUnsavedChanges) return
    const handler = (event: BeforeUnloadEvent) => {
      event.preventDefault()
      event.returnValue = ''
    }
    window.addEventListener('beforeunload', handler)
    return () => window.removeEventListener('beforeunload', handler)
  }, [hasUnsavedChanges])
  const confirmDiscardAndNavigate = (to: string) => {
    if (!hasUnsavedChanges || window.confirm('Discard unsaved Sales Invoice changes?')) navigate(to)
  }
  const guardUnsavedLink = (event: React.MouseEvent<HTMLAnchorElement>) => {
    if (hasUnsavedChanges && !window.confirm('Discard unsaved Sales Invoice changes?')) event.preventDefault()
  }
  const auditFacts = editSI ? [
    { label: 'Created', value: formatDateTime(editSI.created_at) },
    { label: 'Last edited', value: formatDateTime(editSI.updated_at) },
    { label: 'Approved', value: formatDateTime(editSI.approved_at) },
    { label: 'Posted', value: formatDateTime(editSI.posted_at) },
    { label: 'Lock status', value: editSI.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ] : []
  const selectedCustomer = customers.find(c => c.id === fCustomer)
  const tinDisplay = {
    tin: composePhTin(fCustomerTIN, selectedCustomer?.tin_branch_code),
    branch: getPhTinBranch(fCustomerTIN, selectedCustomer?.tin_branch_code),
  }
  const selectedBranch = branches.find(b => b.id === fBranch)
  const selectedAtc = cwtAtcCodes.find(a => a.id === fCwtAtc)
  const selectedDepartment = departments.find(d => d.id === fDepartment)
  const selectedCostCenter = costCenters.find(c => c.id === fCostCenter)
  const selectedWarehouse = warehouses.find(w => w.id === fWarehouse)
  const employeeLabel = (employee: EmployeeRef) => `${employee.employee_number} - ${employee.first_name} ${employee.last_name}`
  const activeLines = lines.filter(l => l.description.trim() || l.item_id)
  const inventoryLines = activeLines.filter(l => items.find(item => item.id === l.item_id)?.item_type === 'inventory_item')
  const grossLineAmount = lines.reduce((sum, line) => sum + line.quantity * line.unit_price, 0)
  const discountAmount = lines.reduce((sum, line) => sum + line.discount_amount, 0)
  const netSales = totals.total_taxable_amount + totals.total_zero_rated_amount + totals.total_exempt_amount
  const draftInventoryCost = inventoryLines.reduce((sum, line) => {
    const item = items.find(candidate => candidate.id === line.item_id)
    return sum + round2(Number(line.quantity || 0) * Number(line.unit_cost || item?.standard_cost || 0))
  }, 0)
  const draftGrossProfit = netSales - draftInventoryCost
  const draftGrossMargin = netSales > 0 ? (draftGrossProfit / netSales) * 100 : null
  const quantityIssued = inventoryLines.reduce((sum, line) => sum + Number(line.quantity || 0), 0)
  const expectedNetCollectible = Math.max(0, totals.total_amount - (fIsWithholdingAgent ? fCwtExpected : 0))
  const missingLineRevenueAccount = activeLines.some(l => !l.revenue_account_id)
  const missingLineVatCode = activeLines.some(l => !l.vat_code_id || !vatCodes.some(v => v.id === l.vat_code_id))
  const missingInventoryWarehouse = inventoryLines.some(l => !(l.warehouse_id || fWarehouse))
  const missingInventoryPostingAccounts = inventoryLines.some(l => !l.inventory_account_id || !l.cogs_account_id)
  const unavailableInventoryCost = inventoryLines.some(l => {
    const item = items.find(candidate => candidate.id === l.item_id)
    return Number(l.unit_cost || item?.standard_cost || 0) <= 0
  })
  const invalidLineQuantity = activeLines.some(l => l.quantity <= 0)
  const invalidLinePrice = activeLines.some(l => l.unit_price < 0)
  const validationRows = useMemo<ValidationRow[]>(() => {
    const rows: ValidationRow[] = [
      {
        check: 'Customer selected',
        status: fCustomer ? 'Passed' : 'Blocked',
        message: fCustomer ? 'Customer snapshot is ready.' : 'Select a customer before saving.',
        resolution: fCustomer ? 'No action required.' : 'Use Customer Information to select an active customer.',
        source: 'Customer master',
      },
      {
        check: 'Invoice date',
        status: fDate ? 'Passed' : 'Blocked',
        message: fDate ? 'Invoice date is present.' : 'Invoice date is required.',
        resolution: fDate ? 'No action required.' : 'Enter an invoice date.',
        source: 'Document Information',
      },
      {
        check: 'Branch active',
        status: fBranch && selectedBranch ? 'Passed' : 'Blocked',
        message: fBranch && selectedBranch ? 'Selected branch is active.' : 'Select an active branch.',
        resolution: fBranch && selectedBranch ? 'No action required.' : 'Choose a branch available for this company.',
        source: 'Branch setup',
      },
      {
        check: 'Setup readiness',
        status: readiness.loading ? 'Informational' : readiness.blockers.length > 0 ? 'Blocked' : 'Passed',
        message: readiness.loading
          ? 'Checking fiscal period, number series, and GL setup.'
          : readiness.blockers.length > 0
            ? `${readiness.blockers.length} setup issue${readiness.blockers.length === 1 ? '' : 's'} block saving or posting.`
            : 'Fiscal period, number series, and required GL setup are available.',
        resolution: readiness.blockers.length > 0 ? readiness.blockers.join(' ') : 'No action required.',
        source: 'Setup readiness',
      },
      {
        check: 'VAT Price Basis',
        status: 'Passed',
        message: fVatPriceBasis === 'inclusive'
          ? 'VAT Inclusive pricing will be persisted and recomputed by the server on save.'
          : 'VAT Exclusive pricing will be persisted and recomputed by the server on save.',
        resolution: 'No action required.',
        source: 'Document Information',
      },
      {
        check: 'Line items',
        status: activeLines.length > 0 ? 'Passed' : 'Blocked',
        message: activeLines.length > 0 ? `${activeLines.length} line${activeLines.length === 1 ? '' : 's'} ready for save.` : 'At least one line is required.',
        resolution: activeLines.length > 0 ? 'No action required.' : 'Add an item or service line.',
        source: 'Invoice lines',
      },
      {
        check: 'Quantities',
        status: invalidLineQuantity ? 'Blocked' : activeLines.length > 0 ? 'Passed' : 'Not Applicable',
        message: invalidLineQuantity ? 'One or more lines have zero or negative quantity.' : 'Line quantities are valid.',
        resolution: invalidLineQuantity ? 'Enter a quantity greater than zero on every active line.' : 'No action required.',
        source: 'Invoice lines',
      },
      {
        check: 'Prices',
        status: invalidLinePrice ? 'Blocked' : activeLines.length > 0 ? 'Passed' : 'Not Applicable',
        message: invalidLinePrice ? 'One or more lines have a negative unit price.' : 'Line prices are valid.',
        resolution: invalidLinePrice ? 'Use zero or a positive unit price.' : 'No action required.',
        source: 'Invoice lines',
      },
      {
        check: 'Output VAT code',
        status: missingLineVatCode ? 'Blocked' : activeLines.length > 0 ? 'Passed' : 'Not Applicable',
        message: missingLineVatCode ? 'Every active line needs an active output VAT code.' : 'VAT codes are present on active lines.',
        resolution: missingLineVatCode ? 'Set item VAT defaults or select an allowed output VAT code.' : 'No action required.',
        source: 'Tax setup',
      },
      {
        check: 'Revenue account',
        status: missingLineRevenueAccount ? 'Blocked' : activeLines.length > 0 ? 'Passed' : 'Not Applicable',
        message: missingLineRevenueAccount ? 'Every active line needs a revenue account before approval or posting.' : 'Revenue accounts are determined.',
        resolution: missingLineRevenueAccount ? 'Set the item sales account in Item Catalog.' : 'No action required.',
        source: 'Account determination',
      },
      {
        check: 'Inventory warehouse',
        status: missingInventoryWarehouse ? 'Blocked' : inventoryLines.length > 0 ? 'Passed' : 'Not Applicable',
        message: missingInventoryWarehouse ? 'Every inventory item line needs a warehouse.' : 'Inventory item lines have warehouse context.',
        resolution: missingInventoryWarehouse ? 'Select a header warehouse or line warehouse before approval/posting.' : 'No action required.',
        source: 'Warehouse master',
      },
      {
        check: 'Inventory and COGS accounts',
        status: missingInventoryPostingAccounts ? 'Blocked' : inventoryLines.length > 0 ? 'Passed' : 'Not Applicable',
        message: missingInventoryPostingAccounts ? 'One or more inventory item lines lack Inventory or COGS account defaults.' : 'Inventory posting accounts are determined.',
        resolution: missingInventoryPostingAccounts ? 'Set Inventory Asset and COGS accounts on Item Master.' : 'No action required.',
        source: 'Item accounting profile',
      },
      {
        check: 'Inventory cost availability',
        status: unavailableInventoryCost ? 'Warning' : inventoryLines.length > 0 ? 'Passed' : 'Not Applicable',
        message: unavailableInventoryCost ? 'One or more inventory lines have zero or unavailable cost in the draft preview.' : 'Inventory cost is available for inventory lines.',
        resolution: unavailableInventoryCost ? 'Review item standard cost and warehouse stock cost before posting.' : 'No action required.',
        source: 'Inventory valuation',
      },
      {
        check: 'Commercial GL section balance',
        status: Math.abs(commercialGlDebit - commercialGlCredit) <= 0.01 ? 'Passed' : 'Blocked',
        message: 'Commercial receivable, revenue, and tax debits and credits are compared.',
        resolution: 'Review AR, revenue, VAT, discount, or rounding account determination.',
        source: 'GL preview',
      },
      {
        check: 'Inventory GL section balance',
        status: inventoryLines.length === 0 ? 'Not Applicable' : Math.abs(inventoryGlDebit - inventoryGlCredit) <= 0.01 ? 'Passed' : 'Blocked',
        message: inventoryLines.length === 0 ? 'No inventory-cost impact applies.' : 'Inventory and COGS debits and credits are compared.',
        resolution: 'Review warehouse, inventory account, COGS account, and inventory valuation.',
        source: 'Inventory posting preview',
      },
      {
        check: 'GL preview balance',
        status: Math.abs(combinedGlDifference) <= 0.01 ? 'Passed' : 'Blocked',
        message: 'Draft GL preview debit and credit totals are compared locally.',
        resolution: 'Review GL Impact for missing accounts or out-of-balance rows.',
        source: 'GL preview',
      },
      {
        check: 'Expected CWT',
        status: fIsWithholdingAgent && !fCwtAtc ? 'Blocked' : fIsWithholdingAgent ? 'Informational' : 'Not Applicable',
        message: fIsWithholdingAgent
          ? selectedAtc
            ? `Expected CWT uses ${selectedAtc.code} at ${fmt(selectedAtc.rate)}%.`
            : 'Customer is subject to CWT but no active ATC is selected.'
          : 'Customer is not marked as subject to CWT.',
        resolution: fIsWithholdingAgent && !fCwtAtc ? 'Set a default active EWT ATC on the customer master.' : 'No action required.',
        source: 'Customer tax profile',
      },
    ]
    return rows
  }, [
    activeLines.length,
    fBranch,
    fCustomer,
    fCwtAtc,
    fDate,
    fIsWithholdingAgent,
    fVatPriceBasis,
    inventoryLines.length,
    inventoryGlCredit,
    inventoryGlDebit,
    invalidLinePrice,
    invalidLineQuantity,
    commercialGlCredit,
    commercialGlDebit,
    combinedGlDifference,
    missingInventoryPostingAccounts,
    missingInventoryWarehouse,
    missingLineRevenueAccount,
    missingLineVatCode,
    readiness.blockers,
    readiness.loading,
    selectedAtc,
    selectedBranch,
    unavailableInventoryCost,
  ])
  const validationBlockers = validationRows.filter(row => row.status === 'Blocked').length
  const readinessLabel = readiness.loading
    ? 'Checking readiness'
    : validationBlockers > 0
      ? `${validationBlockers} blocker${validationBlockers === 1 ? '' : 's'}`
      : 'Ready to save'
  const readinessState = readiness.loading
    ? 'pending'
    : validationBlockers > 0
      ? 'error'
      : 'success'
  const saveDisabledReason = readiness.blockers[0] || ''
  const formTabs: Array<{ key: FormTab; label: string }> = [
    { key: 'lines', label: 'Lines' },
    { key: 'financial', label: 'Financial' },
    { key: 'gl', label: 'GL Impact' },
    { key: 'tax', label: 'Tax Impact' },
    { key: 'validation', label: 'Validation' },
    { key: 'workflow', label: 'Workflow' },
    { key: 'approval', label: 'Approval' },
    { key: 'audit', label: 'Audit' },
    { key: 'related', label: 'Related Docs' },
    { key: 'party', label: 'Related Party' },
    { key: 'attachments', label: 'Attachments' },
    { key: 'activity', label: 'Activity' },
    { key: 'notes', label: 'Notes' },
    { key: 'system', label: 'System' },
  ]
  const formDocumentTabs: DocumentTab[] = formTabs.map(tab => ({ ...tab, content: null }))
  const formActions: ToolbarAction[] = [
    ...((mode === 'new' || siStatus === 'draft') && !readOnly ? [
      { key: 'save-draft', label: saving ? 'Saving…' : 'Save Draft', onClick: () => { void save('draft') }, disabled: saving || Boolean(saveDisabledReason) },
      { key: 'submit', label: 'Submit', onClick: () => { void save('approved') }, disabled: saving || Boolean(saveDisabledReason) },
      { key: 'post', label: 'Post', onClick: () => { void save('posted') }, disabled: saving || Boolean(saveDisabledReason), variant: 'primary' as const },
    ] : []),
    ...(siStatus === 'approved' ? [
      { key: 'return-draft', label: saving ? 'Reverting…' : 'Return to Draft', onClick: () => { void doRevertToDraft() }, disabled: saving, group: 'more' as const },
      { key: 'post', label: 'Post', onClick: () => { void save('posted') }, disabled: saving || Boolean(saveDisabledReason), variant: 'primary' as const },
    ] : []),
    ...(siStatus === 'posted' ? [
      { key: 'void', label: 'Void', onClick: () => setShowVoid(true), variant: 'danger' as const, group: 'more' as const },
    ] : []),
    { key: 'cancel', label: 'Cancel', onClick: () => confirmDiscardAndNavigate('/sales-invoices'), group: 'more' },
  ]
  const financialGroups = [
    {
      title: 'Commercial Summary',
      rows: [
        ['Gross line amount', 'Sum of line quantity x unit price before line discount.', grossLineAmount],
        ['Line discounts', 'Discounts entered on invoice lines.', discountAmount],
        ['Net sales', 'Net after discounts.', netSales],
        ['VATable sales', 'VATable sales base.', totals.total_taxable_amount],
        ['Zero-rated sales', 'Zero-rated sales base.', totals.total_zero_rated_amount],
        ['VAT-exempt sales', 'Exempt sales base.', totals.total_exempt_amount],
        ['Output VAT', 'VAT on taxable sales.', totals.total_vat_amount],
        ['Invoice total', 'Gross invoice amount.', totals.total_amount],
        ...(fIsWithholdingAgent ? [
          ['Expected CWT', 'Informational until payment recognition.', fCwtExpected],
          ['Expected Net Collectible', 'Invoice total less expected CWT.', expectedNetCollectible],
        ] : []),
        ['Amount collected', 'No payment applications recorded for draft preview.', 0],
        ['Balance due', 'Computed from collection applications after posting.', totals.total_amount],
      ],
    },
    ...(inventoryLines.length > 0 ? [{
      title: 'Inventory and Cost Summary',
      rows: [
        ['Inventory items count', 'Inventory-impacting invoice lines.', inventoryLines.length],
        ['Quantity issued', 'Quantity on inventory-impacting lines.', quantityIssued],
        ['Inventory cost', 'Estimated from line cost or item standard cost until posting.', draftInventoryCost],
        ['Cost of goods sold', 'Estimated COGS for draft inventory lines.', draftInventoryCost],
        ['Inventory reduction', 'Estimated inventory asset credit for draft inventory lines.', draftInventoryCost],
        ['Cost adjustment', 'No cost adjustment recorded in draft preview.', 0],
        ['Inventory variance', 'No inventory variance recorded in draft preview.', 0],
        ['Gross profit', 'Net sales less estimated COGS.', draftGrossProfit],
        ['Gross margin percentage', 'Gross profit divided by net sales.', draftGrossMargin == null ? 'Not Applicable' : `${fmt(draftGrossMargin)}%`],
      ],
    }] : []),
    {
      title: 'Accounting Reconciliation',
      rows: [
        ['Commercial GL debits', 'Commercial / Revenue Accounting Impact section debit total.', commercialGlDebit],
        ['Commercial GL credits', 'Commercial / Revenue Accounting Impact section credit total.', commercialGlCredit],
        ['Inventory GL debits', 'Inventory / Cost Accounting Impact section debit total.', inventoryGlDebit],
        ['Inventory GL credits', 'Inventory / Cost Accounting Impact section credit total.', inventoryGlCredit],
        ['Combined debits', 'Combined commercial and inventory debit total.', combinedGlDebit],
        ['Combined credits', 'Combined commercial and inventory credit total.', combinedGlCredit],
        ['Difference', 'Combined debits less combined credits.', combinedGlDifference],
        ['Balanced status', 'Preview balance status.', Math.abs(combinedGlDifference) <= 0.01 ? 'Balanced' : 'Unbalanced'],
      ],
    },
  ] as Array<{ title: string; rows: Array<[string, string, number | string]> }>

  // ── List View ──────────────────────────────────────────────
  if (mode === 'list') {
    const filteredList = list
    const STATUS_OPTIONS: Array<SIStatus | ''> = ['', 'draft', 'approved', 'posted', 'cancelled']

    return (
      <div>
        {/* Toolbar */}
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search SI#, customer, TIN…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <select value={filterStatus} onChange={e => { setFilterStatus(e.target.value as SIStatus | ''); setPage(0) }}
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
            {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s ? s.charAt(0).toUpperCase() + s.slice(1) : 'All Statuses'}</option>)}
          </select>
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {!companyId ? (
            <span className="text-xs text-gray-400">Select a company first</span>
          ) : (
            <button onClick={openNew} disabled={readiness.loading || readiness.blockers.length > 0}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Sales Invoice
            </button>
          )}
        </div>

        {companyId && readiness.blockers.length > 0 && (
          <div className="px-5 py-3 border-b border-gray-100">
            <SetupReadinessBanner readiness={readiness} />
          </div>
        )}

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Sales Invoices.</div>
        ) : listLoading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(8)].map((_, i) => (
              <div key={i} className="px-5 py-3 flex gap-4 animate-pulse">
                <div className="h-3 bg-gray-100 rounded w-24" />
                <div className="h-3 bg-gray-100 rounded w-32" />
                <div className="h-3 bg-gray-100 rounded flex-1" />
                <div className="h-3 bg-gray-100 rounded w-20" />
              </div>
            ))}
          </div>
        ) : filteredList.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Sales Invoices found</p>
            <p className="text-xs text-gray-400 mt-1">
              {search || filterStatus ? 'No records match the current filters.' : 'Create your first Sales Invoice to get started.'}
            </p>
            {!search && !filterStatus && (
              <button onClick={openNew} disabled={readiness.loading || readiness.blockers.length > 0}
                className="mt-4 px-4 py-2 bg-gray-900 text-white rounded text-sm hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed">
                New Sales Invoice
              </button>
            )}
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className={`${transactionTableClass()} w-full`}>
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['SI Number','Reference','Date','Customer','TIN','Net of VAT','VAT','Total Amount','Status'].map(h => (
                      <th key={h} className="whitespace-nowrap px-4 py-2.5 text-left">{h}</th>
                    ))}
                    <th className="whitespace-nowrap px-4 py-2.5 text-right">Open</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {filteredList.map(si => {
                    const netOfVat = si.total_taxable_amount + si.total_zero_rated_amount + si.total_exempt_amount
                    return (
                      <tr key={si.id} onClick={() => openDocument(si)}
                        className="hover:bg-gray-50 cursor-pointer transition-colors">
                        <td className="px-4 py-2.5 font-mono font-semibold text-xs text-gray-900 whitespace-nowrap">{si.si_number}</td>
                        <td className="px-4 py-2.5 font-mono text-xs text-gray-500 whitespace-nowrap">{si.reference || '—'}</td>
                        <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap"><DateCell date={si.date} /></td>
                        <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[200px] truncate">{si.customer_name_snapshot}</td>
                        <td className="px-4 py-2.5 font-mono text-xs text-gray-500 whitespace-nowrap">{si.customer_tin_snapshot}</td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-700"><AmountCell amount={netOfVat} /></td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs text-gray-700"><AmountCell amount={si.total_vat_amount} /></td>
                        <td className="px-4 py-2.5 text-right font-mono text-xs font-semibold text-gray-900"><AmountCell amount={si.total_amount} /></td>
                        <td className="px-4 py-2.5">
                          <StatusBadge status={statusToShared[si.status]} label={si.status.charAt(0).toUpperCase() + si.status.slice(1)} />
                        </td>
                        <td className="px-4 py-2.5 text-right whitespace-nowrap">
                          <Link to={`/sales-invoices/${si.id}`} onClick={e => e.stopPropagation()}
                            className="text-xs font-medium text-blue-600 hover:text-blue-800 hover:underline">
                            Open ↗
                          </Link>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            {totalCount > PAGE && (
              <div className="px-5 py-2.5 border-t border-gray-200 flex items-center justify-between bg-white">
                <span className="text-xs text-gray-500">
                  Showing {page * PAGE + 1}–{Math.min((page + 1) * PAGE, totalCount)} of {totalCount}
                </span>
                <div className="flex gap-1.5">
                  <button disabled={page === 0} onClick={() => setPage(p => p - 1)}
                    className="px-2.5 py-1 border border-gray-300 rounded text-xs text-gray-600 hover:bg-gray-50 disabled:opacity-40">← Prev</button>
                  <button disabled={(page + 1) * PAGE >= totalCount} onClick={() => setPage(p => p + 1)}
                    className="px-2.5 py-1 border border-gray-300 rounded text-xs text-gray-600 hover:bg-gray-50 disabled:opacity-40">Next →</button>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    )
  }

  if (routeMode !== 'list' && (!companyId || !refsLoaded)) {
    return <div className="py-16 text-center text-sm text-gray-400">Loading Sales Invoice workspace...</div>
  }

  const salesOrderSourcePrompt = canEdit && openSalesOrders.length > 0 && !salesOrderPromptDismissed ? (
    <section className={`${transactionCardClass()} p-3`}>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <div><div className="text-sm font-semibold text-gray-900">Open Sales Orders</div><div className="text-xs text-gray-500">Select a valid source document or continue with an empty invoice.</div></div>
        <button type="button" onClick={() => setSalesOrderPromptDismissed(true)} className={transactionButtonClass('neutral')}>Create empty invoice</button>
      </div>
      <div className="overflow-x-auto rounded border border-[#c7d0db]">
        <table className={`${transactionTableClass()} w-full text-xs`}><thead className="border-b bg-gray-50"><tr>{['Sales Order Number', 'Date', 'Remaining Amount', 'Status', 'Action'].map((label, index) => <th key={label} className={`px-3 py-2 ${index === 2 ? 'text-right' : 'text-left'}`}>{label}</th>)}</tr></thead><tbody className="divide-y divide-gray-100">{openSalesOrders.map(order => <tr key={order.id}><td className="px-3 py-2 font-mono font-semibold">{order.so_number}</td><td className="px-3 py-2"><DateCell date={order.so_date} /></td><td className="px-3 py-2 text-right font-mono">{order.currency_code} {fmt(Number(order.total_amount))}</td><td className="px-3 py-2">{order.fulfillment_status}</td><td className="px-3 py-2"><button type="button" onClick={() => void convertFromSalesOrder(order)} className={transactionButtonClass('primary')}>Convert</button></td></tr>)}</tbody></table>
      </div>
    </section>
  ) : null

  // ── Form View ─────────────────────────────────────────────
  return (
    <div className="pxl-transaction-workspace pxl-transaction-workspace--sales space-y-2 rounded-md p-2" aria-label="Sales Invoice workspace">
      <TransactionPageHeader
        title="Sales Invoice"
        documentNo={editSI?.si_number}
        status={siStatus}
        statusLabel={siStatus.charAt(0).toUpperCase() + siStatus.slice(1)}
        identity={selectedCustomer ? {
          name: <Link to={`/customers?customerId=${selectedCustomer.id}`} onClick={guardUnsavedLink}>{selectedCustomer.registered_name}</Link>,
          secondary: tinDisplay.tin || undefined,
        } : { name: 'Customer not selected' }}
        metrics={[
          { label: 'Invoice Total', value: `${fCurrency} ${fmt(totals.total_amount)}`, emphasis: true },
          { label: 'Net Collectible', value: `${fCurrency} ${fmt(expectedNetCollectible)}` },
          { label: 'Readiness', value: readinessLabel },
        ]}
        meta={[{ label: 'Readiness', value: readinessLabel, tone: readinessState === 'success' ? 'success' : readinessState === 'error' ? 'error' : 'warning' }]}
        actions={formActions}
        onBack={() => confirmDiscardAndNavigate('/sales-invoices')}
        backLabel="Sales Invoices"
      />

      <TransactionWorkflowBanner
        steps={[
          { key: 'draft', label: 'Draft' },
          { key: 'approved', label: 'Approved' },
          { key: 'posted', label: 'Posted' },
          { key: 'paid', label: 'Paid' },
          { key: 'cancelled', label: 'Voided' },
        ]}
        currentKey={siStatus}
      />

      <div className="space-y-2">
        <TransactionInfoCards>
          <TransactionInfoCard title="Document Information">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className={lbl}>Invoice Date <span className="text-red-500">*</span></label>
                <input type="date" value={fDate} onChange={e => onInvoiceDateChange(e.target.value)}
                  disabled={readOnly} className={readOnly ? ro : inp} />
              </div>
              <div>
                <label className={lbl}>Due Date</label>
                <div className={ro}>{fDueDate || 'Not assigned'}</div>
              </div>
              <div>
                <label className={lbl}>Branch <span className="text-red-500">*</span></label>
                <select value={fBranch} onChange={e => setFBranch(e.target.value)}
                  disabled={readOnly} className={readOnly ? ro : inp}>
                  <option value="">Select branch...</option>
                  {branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} - {b.branch_name}</option>)}
                </select>
              </div>
              <div>
                <label className={lbl}>Currency</label>
                <div className={ro}>{fCurrency}</div>
              </div>
              <div>
                <label className={lbl}>Payment Terms</label>
                {readOnly ? (
                  <div className={ro}>{selectedCustomer?.payment_terms?.term_name || fTerms || 'Not assigned'}</div>
                ) : (
                  <select value={fTerms} onChange={e => setFTerms(e.target.value)} className={inp}>
                    <option value="">Select terms...</option>
                    {selectedCustomer?.payment_terms && (
                      <option value={selectedCustomer.default_terms_id || ''}>
                        {selectedCustomer.payment_terms.term_name}
                      </option>
                    )}
                  </select>
                )}
              </div>
              <div>
                <label className={lbl}>VAT Price Basis</label>
                {readOnly ? (
                  <div className={ro}>{fVatPriceBasis === 'inclusive' ? 'VAT Inclusive' : 'VAT Exclusive'}</div>
                ) : (
                  <select value={fVatPriceBasis} onChange={e => onVatPriceBasisChange(e.target.value as VatPriceBasis)} className={inp}>
                    <option value="exclusive">VAT Exclusive</option>
                    <option value="inclusive">VAT Inclusive</option>
                  </select>
                )}
              </div>
              <div className="col-span-2">
                <label className={lbl}>External Reference</label>
                {readOnly ? (
                  <div className={ro}>{fRef || 'Not linked'}</div>
                ) : (
                  <input value={fRef} onChange={e => setFRef(e.target.value)} placeholder="Customer PO, Supplier Invoice, Delivery Receipt, Contract, Other External Reference" className={inp} />
                )}
              </div>
            </div>
          </TransactionInfoCard>

          <TransactionInfoCard title="Customer Information">
            <div className="space-y-3">
              <div>
                <label className={lbl}>Customer <span className="text-red-500">*</span></label>
                {readOnly ? (
                  <div className={ro}>{fCustomerName || 'Not selected'}</div>
                ) : (
                  <CustomerSearch customers={customers} value={fCustomer} onChange={customer => onCustomerChange(customer.id)} />
                )}
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className={lbl}>Customer Code</label>
                  <div className={ro}>{selectedCustomer?.customer_code || 'Not selected'}</div>
                </div>
                <div>
                  <label className={lbl}>TIN</label>
                  <div className={ro}>{tinDisplay.tin || 'Not selected'}</div>
                </div>
                <div>
                  <label className={lbl}>TIN Branch</label>
                  <div className={ro}>{tinDisplay.branch || 'Not recorded'}</div>
                </div>
                <div>
                  <label className={lbl}>VAT Classification</label>
                  <div className={ro}>{selectedCustomer?.default_tax_type?.replace(/_/g, ' ') || 'Not selected'}</div>
                </div>
                <div className="col-span-2">
                  <label className={lbl}>Business Style</label>
                  <div className={ro}>{selectedCustomer?.business_style || 'Not recorded'}</div>
                </div>
              </div>
            </div>
          </TransactionInfoCard>

          <TransactionInfoCard title="Sales Context">
            {departments.length === 0 && costCenters.length === 0 && warehouses.length === 0 && employees.length === 0 ? (
              <div className="rounded border border-[#c7d0db] bg-[#f3f6f9] px-3 py-4 text-center">
                <div className="text-xs font-medium text-gray-600">No operational dimensions assigned.</div>
              </div>
            ) : (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                {employees.length > 0 && (
                  <div>
                    <label className={lbl}>Account Owner</label>
                    {readOnly ? (
                      <div className={ro}>{employees.find(e => e.id === fAccountOwner) ? employeeLabel(employees.find(e => e.id === fAccountOwner)!) : 'Not assigned'}</div>
                    ) : (
                      <select value={fAccountOwner} onChange={e => setFAccountOwner(e.target.value)} className={inp}>
                        <option value="">Not assigned</option>
                        {employees.map(e => <option key={e.id} value={e.id}>{employeeLabel(e)}</option>)}
                      </select>
                    )}
                  </div>
                )}
                {employees.length > 0 && (
                  <div>
                    <label className={lbl}>Salesperson</label>
                    {readOnly ? (
                      <div className={ro}>{employees.find(e => e.id === fSalesperson) ? employeeLabel(employees.find(e => e.id === fSalesperson)!) : 'Not assigned'}</div>
                    ) : (
                      <select value={fSalesperson} onChange={e => {
                        const value = e.target.value
                        setFSalesperson(value)
                      }} className={inp}>
                        <option value="">Not assigned</option>
                        {employees.map(e => <option key={e.id} value={e.id}>{employeeLabel(e)}</option>)}
                      </select>
                    )}
                  </div>
                )}
                {departments.length > 0 && (
                  <div>
                    <label className={lbl}>Department</label>
                    {readOnly ? (
                      <div className={ro}>{selectedDepartment ? `${selectedDepartment.department_code} - ${selectedDepartment.department_name}` : 'Not assigned'}</div>
                    ) : (
                      <select value={fDepartment} onChange={e => {
                        const value = e.target.value
                        setFDepartment(value)
                      }} className={inp}>
                        <option value="">Not assigned</option>
                        {departments.map(d => <option key={d.id} value={d.id}>{d.department_code} - {d.department_name}</option>)}
                      </select>
                    )}
                  </div>
                )}
                {costCenters.length > 0 && (
                  <div>
                    <label className={lbl}>Cost Center</label>
                    {readOnly ? (
                      <div className={ro}>{selectedCostCenter ? `${selectedCostCenter.cost_center_code} - ${selectedCostCenter.cost_center_name}` : 'Not assigned'}</div>
                    ) : (
                      <select value={fCostCenter} onChange={e => {
                        const value = e.target.value
                        setFCostCenter(value)
                      }} className={inp}>
                        <option value="">Not assigned</option>
                        {costCenters.map(c => <option key={c.id} value={c.id}>{c.cost_center_code} - {c.cost_center_name}</option>)}
                      </select>
                    )}
                  </div>
                )}
                {warehouses.length > 0 && (
                  <div>
                    <label className={lbl}>Default Warehouse</label>
                    {readOnly ? (
                      <div className={ro}>{selectedWarehouse ? `${selectedWarehouse.warehouse_code} - ${selectedWarehouse.warehouse_name}` : 'Not assigned'}</div>
                    ) : (
                      <select value={fWarehouse} onChange={e => {
                        const value = e.target.value
                        setFWarehouse(value)
                      }} className={inp}>
                        <option value="">Not assigned</option>
                        {warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_code} - {w.warehouse_name}</option>)}
                      </select>
                    )}
                  </div>
                )}
              </div>
            )}
          </TransactionInfoCard>
        </TransactionInfoCards>

        <div className="overflow-hidden rounded border border-[var(--pxl-border-strong)]">
          <TransactionTabsBar
            tabs={formDocumentTabs}
            activeKey={activeTab}
            onChange={key => setActiveTab(key as FormTab)}
          />
        </div>

        <div className="pxl-transaction-content-grid grid min-w-0 items-start gap-2 lg:grid-cols-[minmax(0,1fr)_15rem] xl:grid-cols-[minmax(0,1fr)_16rem]">
        <div className="pxl-transaction-tab-panel min-w-0 rounded border border-[var(--pxl-border-medium)] bg-white px-2.5 py-2 shadow-[var(--pxl-shadow-card)]" id={`transaction-panel-${activeTab}`} role="tabpanel" aria-labelledby={`transaction-tab-${activeTab}`}>
        {activeTab === 'lines' && (
          <section className={`${transactionCardClass(true)}`}>
            <div className="flex items-center justify-between border-b border-[#c7d0db] px-3 py-2">
              <div>
                <div className={transactionSectionTitleClass()}>Invoice Lines</div>
                <div className="text-[11px] text-[#6b7280]">Draft amounts are client-side previews; server recomputation remains authoritative on save.</div>
              </div>
              {canEdit && (
                <div className="flex items-center gap-1.5">
                  <button type="button" onClick={() => setLines(prev => [...prev, emptyLine()])}
                    className={`${transactionButtonClass('neutral')} h-8 px-2 text-xs`}>
                    <svg className="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
                    Add Line
                  </button>
                </div>
              )}
            </div>
            <div className="max-h-[58vh] overflow-auto">
              <table className={`${transactionTableClass()} w-full min-w-[1800px]`}>
                <thead className="sticky top-0 z-10 border-b bg-gray-50">
                  <tr>
                    <th className="sticky left-0 z-20 w-10 bg-[var(--pxl-surface-table-header)] px-3 py-2 text-left">#</th>
                    <th className="min-w-[190px] px-3 py-2 text-left">Item or Service</th>
                    <th className="min-w-[220px] px-3 py-2 text-left">Description</th>
                    <th className="w-20 px-3 py-2 text-right">Qty</th>
                    <th className="w-16 px-3 py-2 text-left">UOM</th>
                    {warehouses.length > 0 && <th className="w-36 px-3 py-2 text-left">Warehouse</th>}
                    {departments.length > 0 && <th className="w-36 px-3 py-2 text-left">Department</th>}
                    {costCenters.length > 0 && <th className="w-36 px-3 py-2 text-left">Cost Center</th>}
                    <th className="w-28 px-3 py-2 text-right">Unit Price</th>
                    <th className="w-16 px-3 py-2 text-right">Disc%</th>
                    <th className="w-28 px-3 py-2 text-left">VAT Code</th>
                    <th className="w-20 px-3 py-2 text-right">VAT Rate</th>
                    <th className="w-28 px-3 py-2 text-right">Net Amount</th>
                    <th className="w-24 px-3 py-2 text-right">VAT</th>
                    <th className="w-28 px-3 py-2 text-right">Gross</th>
                    {canEdit && <th className="w-20 px-2 py-2 text-right">Actions</th>}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {lines.map((l, idx) => (
                    <tr key={l._key} className="hover:bg-gray-50/50">
                      <td className="sticky left-0 bg-white px-3 py-2 text-right align-middle text-xs text-gray-400">{idx + 1}</td>
                      <td className="px-3 py-2 align-middle">
                        {canEdit ? (
                          <ItemSearch items={items} value={l.item_id}
                            onChange={item => onItemChange(l._key, item)} />
                        ) : (
                          <span className="text-xs text-gray-600">{items.find(i => i.id === l.item_id)?.item_code || 'Not assigned'}</span>
                        )}
                      </td>
                      <td className="px-3 py-2 align-middle">
                        {canEdit ? (
                          <input value={l.description} onChange={e => setLineField(l._key, 'description', e.target.value)}
                            className={celInp} placeholder="Description..." />
                        ) : (
                          <span className="text-xs text-gray-700">{l.description}</span>
                        )}
                      </td>
                      <td className="px-3 py-2 text-right align-middle">
                        {canEdit ? (
                          <input type="number" value={l.quantity} min={0.0001} step="any"
                            onChange={e => setLineField(l._key, 'quantity', parseFloat(e.target.value) || 0)}
                            className={celInp + ' text-right'} />
                        ) : (
                          <span className="font-mono text-xs tabular-nums text-gray-700">{l.quantity}</span>
                        )}
                      </td>
                      <td className="px-3 py-2 align-middle text-xs text-gray-500">{l.uom_label || 'Not assigned'}</td>
                      {warehouses.length > 0 && (
                        <td className="px-3 py-2 align-middle">
                          {canEdit ? (
                            <select value={l.warehouse_id} onChange={e => setLineField(l._key, 'warehouse_id', e.target.value)} className="w-full border-0 bg-transparent text-xs focus:outline-none">
                              <option value="">Header/default</option>
                              {warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_code}</option>)}
                            </select>
                          ) : (
                            <span className="text-xs text-gray-500">{warehouses.find(w => w.id === l.warehouse_id)?.warehouse_code || 'Not assigned'}</span>
                          )}
                        </td>
                      )}
                      {departments.length > 0 && (
                        <td className="px-3 py-2 align-middle">
                          {canEdit ? (
                            <select value={l.department_id} onChange={e => setLineField(l._key, 'department_id', e.target.value)} className="w-full border-0 bg-transparent text-xs focus:outline-none">
                              <option value="">Header/default</option>
                              {departments.map(d => <option key={d.id} value={d.id}>{d.department_code}</option>)}
                            </select>
                          ) : (
                            <span className="text-xs text-gray-500">{departments.find(d => d.id === l.department_id)?.department_code || 'Not assigned'}</span>
                          )}
                        </td>
                      )}
                      {costCenters.length > 0 && (
                        <td className="px-3 py-2 align-middle">
                          {canEdit ? (
                            <select value={l.cost_center_id} onChange={e => setLineField(l._key, 'cost_center_id', e.target.value)} className="w-full border-0 bg-transparent text-xs focus:outline-none">
                              <option value="">Header/default</option>
                              {costCenters.map(c => <option key={c.id} value={c.id}>{c.cost_center_code}</option>)}
                            </select>
                          ) : (
                            <span className="text-xs text-gray-500">{costCenters.find(c => c.id === l.cost_center_id)?.cost_center_code || 'Not assigned'}</span>
                          )}
                        </td>
                      )}
                      <td className="px-3 py-2 text-right align-middle">
                        {canEdit ? (
                          <input type="number" value={l.unit_price} min={0} step="any"
                            onChange={e => setLineField(l._key, 'unit_price', parseFloat(e.target.value) || 0)}
                            className={celInp + ' text-right'} />
                        ) : (
                          <span className="font-mono text-xs tabular-nums text-gray-700">{fmt(l.unit_price)}</span>
                        )}
                      </td>
                      <td className="px-3 py-2 text-right align-middle">
                        {canEdit ? (
                          <input type="number" value={l.discount_percent} min={0} max={100} step="any"
                            onChange={e => setLineField(l._key, 'discount_percent', parseFloat(e.target.value) || 0)}
                            className={celInp + ' text-right'} />
                        ) : (
                          <span className="font-mono text-xs text-gray-500">{l.discount_percent}%</span>
                        )}
                      </td>
                      <td className="px-3 py-2 align-middle">
                        {canEdit ? (
                          <select value={l.vat_code_id}
                            onChange={e => setLineField(l._key, 'vat_code_id', e.target.value)}
                            className="w-full border-0 bg-transparent text-xs focus:outline-none">
                            <option value="">Not assigned</option>
                            {vatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code}</option>)}
                          </select>
                        ) : (
                          <span className="text-xs text-gray-500">{vatCodes.find(v => v.id === l.vat_code_id)?.vat_code || 'Not assigned'}</span>
                        )}
                      </td>
                      <td className="px-3 py-2 text-right align-middle font-mono text-xs tabular-nums text-gray-600">{fmt(l.vat_rate)}%</td>
                      <td className="px-3 py-2 text-right align-middle font-mono text-xs tabular-nums text-gray-700">{fmt(l.net_amount)}</td>
                      <td className="px-3 py-2 text-right align-middle font-mono text-xs tabular-nums text-gray-700">{fmt(l.vat_amount)}</td>
                      <td className="px-3 py-2 text-right align-middle font-mono text-xs font-semibold tabular-nums text-gray-900">{fmt(l.total_amount)}</td>
                      {canEdit && (
                        <td className="px-2 py-2 text-right align-middle">
                          <button type="button" onClick={() => setLines(prev => [...prev.slice(0, idx + 1), { ...l, _key: crypto.randomUUID(), id: undefined, unit_cost: 0, inventory_cost: 0, inventory_transaction_id: '' }, ...prev.slice(idx + 1)])}
                            className="mr-2 text-xs text-gray-400 hover:text-gray-900" title="Duplicate line">Copy</button>
                          <button type="button" onClick={() => setLines(prev => prev.length > 1 ? prev.filter(x => x._key !== l._key) : [emptyLine()])}
                            className="text-xs text-gray-400 hover:text-red-600" title="Remove line">Remove</button>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
                <tfoot className="sticky bottom-0 border-t border-gray-200 bg-gray-50">
                  <tr>
                    <td colSpan={9 + (warehouses.length > 0 ? 1 : 0) + (departments.length > 0 ? 1 : 0) + (costCenters.length > 0 ? 1 : 0)} className="px-3 py-2 text-right text-xs font-semibold text-gray-700">Preview Totals</td>
                    <td className="px-3 py-2 text-right font-mono text-xs font-semibold tabular-nums text-gray-900">{fmt(totals.total_taxable_amount + totals.total_zero_rated_amount + totals.total_exempt_amount)}</td>
                    <td className="px-3 py-2 text-right font-mono text-xs font-semibold tabular-nums text-gray-900">{fmt(totals.total_vat_amount)}</td>
                    <td className="px-3 py-2 text-right font-mono text-xs font-semibold tabular-nums text-gray-900">{fmt(totals.total_amount)}</td>
                    {canEdit && <td />}
                  </tr>
                </tfoot>
              </table>
            </div>
            <div className="flex justify-end border-t border-gray-100 px-3 py-3">
              <div className="w-full max-w-sm divide-y divide-gray-100">
                {[
                  ['Subtotal', totals.total_taxable_amount + totals.total_zero_rated_amount + totals.total_exempt_amount],
                  ['VAT', totals.total_vat_amount],
                  ['Invoice Total', totals.total_amount],
                  ...(fIsWithholdingAgent ? [
                    ['Expected CWT', -fCwtExpected],
                    ['Expected Net Collectible', expectedNetCollectible],
                  ] : []),
                ].map(([label, amount]) => (
                  <div key={label} className="flex items-center justify-between py-1.5">
                    <span className={`text-xs ${label === 'Invoice Total' ? 'font-semibold text-gray-900' : 'text-gray-500'}`}>{label}</span>
                    <span className={`font-mono text-xs tabular-nums ${label === 'Invoice Total' ? 'font-semibold text-gray-900' : 'text-gray-700'}`}>{fmt(Number(amount))}</span>
                  </div>
                ))}
              </div>
            </div>
          </section>
        )}

        {activeTab === 'financial' && (
          <section className={`${transactionCardClass()} p-3`}>
            <div className={`${transactionSectionTitleClass()} mb-3`}>Financial Summary</div>
            <div className="grid grid-cols-1 gap-3 xl:grid-cols-2">
              {financialGroups.map(group => (
                <div key={group.title} className="overflow-hidden rounded border border-gray-200">
                  <div className="border-b border-[var(--pxl-border-medium)] bg-[var(--pxl-surface-table-header)] px-3 py-2 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    {group.title}
                  </div>
                  <table className={`${transactionTableClass()} w-full`}>
                    <tbody className="divide-y divide-gray-100">
                      {group.rows.map(([component, basis, amount]) => (
                        <tr key={component}>
                          <td className="px-3 py-2 font-medium text-gray-800">{component}</td>
                          <td className="px-3 py-2 text-gray-500">{basis}</td>
                          <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-900">{typeof amount === 'number' ? fmt(amount) : amount}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ))}
            </div>
          </section>
        )}

        {activeTab === 'gl' && (
          <GLImpactPanel
            companyId={companyId}
            sourceDocType="SI"
            sourceDocId={editSI?.id}
            postingDate={fDate}
            previewRows={glImpactRows}
            separatedSalesInvoiceImpact
            withholdingInfo={fIsWithholdingAgent && fCwtExpected > 0 ? {
              withholdingType: 'Expected CWT',
              atc: selectedAtc?.code || null,
              rate: selectedAtc?.rate ?? null,
              base: fCwtBase,
              amount: fCwtExpected,
              expectedNetCollectible,
              recognitionEvent: 'Receipt or payment application',
              status: 'Informational only',
            } : null}
          />
        )}

        {activeTab === 'tax' && (
          <div className="space-y-3">
            <TaxImpactPanel
              sourceDocType="SI"
              sourceDocId={editSI?.id}
              fallbackLabel="Output VAT"
              fallbackBase={totals.total_taxable_amount}
              fallbackRate={totals.total_taxable_amount ? round2((totals.total_vat_amount / totals.total_taxable_amount) * 100) : undefined}
              fallbackAmount={totals.total_vat_amount}
            />
            {fIsWithholdingAgent && (
              <section className={`${transactionCardClass()} p-3`}>
                <div className={`${transactionSectionTitleClass()} mb-2`}>Expected CWT</div>
                <div className="overflow-x-auto rounded border border-gray-200">
                  <table className={`${transactionTableClass()} w-full`}>
                    <thead className="border-b border-gray-200 bg-gray-50">
                      <tr>
                        {['Tax Type', 'ATC', 'Tax Base', 'Rate', 'Tax Amount', 'Tax Treatment', 'Ledger Status', 'Tax Source'].map((h, i) => (
                          <th key={h} className={`px-3 py-2 ${i >= 2 && i <= 4 ? 'text-right' : 'text-left'}`}>{h}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      <tr>
                        <td className="px-3 py-2 text-gray-800">Expected CWT</td>
                        <td className="px-3 py-2 font-mono text-gray-600">{selectedAtc?.code || 'Not configured'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(fCwtBase)}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{selectedAtc ? `${fmt(selectedAtc.rate)}%` : 'Not configured'}</td>
                        <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-900">{fmt(fCwtExpected)}</td>
                        <td className="px-3 py-2 text-gray-500">Informational estimate</td>
                        <td className="px-3 py-2 text-gray-500">Not recognized on invoice</td>
                        <td className="px-3 py-2 text-gray-500">Customer profile and invoice tax base</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <p className="mt-2 text-xs text-gray-500">Expected CWT is informational until payment recognition.</p>
              </section>
            )}
          </div>
        )}

        {activeTab === 'validation' && (
          <section className={`${transactionCardClass()} p-3`}>
            {readiness.blockers.length > 0 && <div className="mb-3"><SetupReadinessBanner readiness={readiness} /></div>}
            {error && <div className="pxl-validation-message mb-3 border border-red-200 bg-red-50 text-red-700" role="alert">{error}</div>}
            <div className="mb-3 flex items-center justify-between gap-3">
              <div>
                <div className={transactionSectionTitleClass()}>Validation</div>
                <div className="text-[11px] text-gray-500">UI checks mirror current server-side readiness and line validation rules.</div>
              </div>
              <StatusBadge status={readinessState} label={readinessLabel} />
            </div>
            <div className="overflow-x-auto rounded border border-gray-200">
              <table className={`${transactionTableClass()} w-full`}>
                <thead className="border-b border-gray-200 bg-gray-50">
                  <tr>
                    {['Validation', 'Status', 'Message', 'Resolution', 'Source'].map(h => (
                      <th key={h} className="px-3 py-2 text-left">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {validationRows.map(row => (
                    <tr key={row.check}>
                      <td className="px-3 py-2 font-medium text-gray-800">{row.check}</td>
                      <td className="px-3 py-2"><span className={`rounded px-2 py-0.5 text-[11px] font-medium ${validationBadgeClass(row.status)}`}>{row.status}</span></td>
                      <td className="px-3 py-2 text-gray-600">{row.message}</td>
                      <td className="px-3 py-2 text-gray-500">{row.resolution}</td>
                      <td className="px-3 py-2 text-gray-500">{row.source}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        )}

        {activeTab === 'workflow' && (
          <section className={`${transactionCardClass()} p-3`}>
            <div className={`${transactionSectionTitleClass()} mb-3`}>Workflow & Approval</div>
            <div className="overflow-x-auto rounded border border-gray-200">
              <table className={`${transactionTableClass()} w-full`}>
                <thead className="border-b border-gray-200 bg-gray-50">
                  <tr>
                    {['Step', 'State', 'Date', 'Source'].map(h => (
                      <th key={h} className="px-3 py-2 text-left">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {[
                    ['Draft', siStatus === 'draft' ? 'Current' : 'Completed', editSI?.created_at || 'Not saved', 'Document lifecycle'],
                    ['Approved', editSI?.approved_at ? 'Completed' : 'Not recorded', editSI?.approved_at || 'Not recorded', 'Approval process'],
                    ['Posted', editSI?.posted_at ? 'Completed' : 'Not recorded', editSI?.posted_at || 'Not recorded', 'Posting engine'],
                    ['Voided', siStatus === 'cancelled' ? 'Completed' : 'Not applicable', siStatus === 'cancelled' ? emptyText(editSI?.updated_at) : 'Not applicable', 'Void controls'],
                  ].map(([step, state, date, source]) => (
                    <tr key={step}>
                      <td className="px-3 py-2 font-medium text-gray-800">{step}</td>
                      <td className="px-3 py-2 text-gray-600">{state}</td>
                      <td className="px-3 py-2 text-gray-500">{date === 'Not saved' || date === 'Not recorded' || date === 'Not applicable' ? date : formatDateTime(date)}</td>
                      <td className="px-3 py-2 text-gray-500">{source}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="mt-3 rounded border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-500">
              No approval workflow configured.
            </div>
          </section>
        )}

        {activeTab === 'approval' && (
          <section className={`${transactionCardClass()} p-3`}>
            <div className={`${transactionSectionTitleClass()} mb-3`}>Approval</div>
            <div className="overflow-hidden rounded border border-gray-200">
              <table className={`${transactionTableClass()} w-full`}>
                <thead className="border-b border-gray-200 bg-gray-50">
                  <tr>{['Approval Status', 'Approver', 'Submitted', 'Decision', 'Comments'].map(h => <th key={h} className="px-3 py-2 text-left">{h}</th>)}</tr>
                </thead>
                <tbody>
                  <tr>
                    <td className="px-3 py-2 font-medium text-gray-800">{editSI?.approved_at ? 'Approved' : siStatus === 'draft' ? 'Not submitted' : 'No workflow configured'}</td>
                    <td className="px-3 py-2 text-gray-500">Not recorded</td>
                    <td className="px-3 py-2 text-gray-500">Not recorded</td>
                    <td className="px-3 py-2 text-gray-500">{editSI?.approved_at ? formatDateTime(editSI.approved_at) : 'Not recorded'}</td>
                    <td className="px-3 py-2 text-gray-500">No approval comments recorded.</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        )}

        {activeTab === 'related' && (
          <div className="space-y-3">
          {salesOrderSourcePrompt}
          <section className={`${transactionCardClass()} p-3`}>
            <div className={`${transactionSectionTitleClass()} mb-3`}>Related Documents</div>
            <div className="overflow-x-auto rounded border border-gray-200">
              <table className={`${transactionTableClass()} w-full`}>
                <thead className="border-b border-gray-200 bg-gray-50">
                  <tr>
                    {['Relationship', 'Document Type', 'Document Number', 'Date', 'Status', 'Amount', 'Direction', 'Action'].map((h, i) => (
                      <th key={h} className={`px-3 py-2 ${i === 5 ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  <tr>
                    <td className="px-3 py-2 text-gray-500">This document</td>
                    <td className="px-3 py-2 text-gray-800">Sales Invoice</td>
                    <td className="px-3 py-2 font-mono text-gray-700">{editSI?.si_number || 'Not saved'}</td>
                    <td className="px-3 py-2 text-gray-500">{fDate}</td>
                    <td className="px-3 py-2 text-gray-500">{siStatus}</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-900">{fmt(totals.total_amount)}</td>
                    <td className="px-3 py-2 text-gray-500">Current</td>
                    <td className="px-3 py-2">{editSI ? <Link to={`/sales-invoices/${editSI.id}`} onClick={guardUnsavedLink} className="text-blue-700 hover:underline">Open view</Link> : <span className="text-gray-400">Not saved</span>}</td>
                  </tr>
                  {[
                    ['Source reference', 'Customer PO / SO / DR', fRef || 'Not linked', 'Upstream'],
                    ['Receipt', 'Official Receipt', 'Not created', 'Downstream'],
                    ['Credit Memo', 'Credit Memo', 'Not created', 'Downstream'],
                    ['Journal Entry', 'General Ledger', editSI?.posted_at ? 'Open GL Impact' : 'Not yet posted', 'Downstream'],
                  ].map(([relationship, docType, number, direction]) => (
                    <tr key={`${relationship}-${docType}`}>
                      <td className="px-3 py-2 text-gray-500">{relationship}</td>
                      <td className="px-3 py-2 text-gray-800">{docType}</td>
                      <td className="px-3 py-2 text-gray-500">{number}</td>
                      <td className="px-3 py-2 text-gray-400">Not recorded</td>
                      <td className="px-3 py-2 text-gray-400">Not recorded</td>
                      <td className="px-3 py-2 text-right text-gray-400">Not recorded</td>
                      <td className="px-3 py-2 text-gray-500">{direction}</td>
                      <td className="px-3 py-2 text-gray-400">Not available</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
          </div>
        )}

        {activeTab === 'party' && (
          <section className={`${transactionCardClass()} p-3`}>
            <div className="mb-3 flex items-center justify-between">
              <div>
                <div className={transactionSectionTitleClass()}>Related Party</div>
                <div className="text-[11px] text-gray-500">Current Customer Master, separate from the invoice snapshot.</div>
              </div>
              {selectedCustomer && <Link to={`/customers?customerId=${selectedCustomer.id}`} onClick={guardUnsavedLink} className="text-xs text-blue-700 hover:underline">Open Customer</Link>}
            </div>
            {!selectedCustomer ? (
              <div className="rounded border border-gray-200 bg-gray-50 px-3 py-4 text-center text-xs text-gray-400">Select a customer to view current master data.</div>
            ) : (
              <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
                <div className="overflow-hidden rounded border border-gray-200">
                  <table className={`${transactionTableClass()} w-full`}>
                    <tbody className="divide-y divide-gray-100">
                      {[
                        ['Customer Code', selectedCustomer.customer_code],
                        ['Registered Name', selectedCustomer.registered_name],
                        ['Trade Name', selectedCustomer.trade_name || 'Not recorded'],
                        ['Customer Group', selectedCustomer.customer_group || 'Not recorded'],
                        ['Default Terms', selectedCustomer.payment_terms?.term_name || 'Not assigned'],
                        ['Credit Limit', fmt(Number(selectedCustomer.credit_limit || 0))],
                      ].map(([label, value]) => (
                        <tr key={label}>
                          <td className="w-44 bg-gray-50 px-3 py-2 font-medium text-gray-500">{label}</td>
                          <td className="px-3 py-2 text-gray-800">{value}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="overflow-hidden rounded border border-gray-200">
                  <table className={`${transactionTableClass()} w-full`}>
                    <tbody className="divide-y divide-gray-100">
                      {[
                        ['TIN', composePhTin(selectedCustomer.tin, selectedCustomer.tin_branch_code)],
                        ['TIN Branch', getPhTinBranch(selectedCustomer.tin, selectedCustomer.tin_branch_code)],
                        ['VAT Classification', selectedCustomer.default_tax_type.replace(/_/g, ' ')],
                        ['Withholding', selectedCustomer.is_subject_to_cwt ? 'Subject to CWT' : 'Not subject to CWT'],
                        ['Default ATC', selectedAtc?.code || 'Not configured'],
                        ['Registered Address', selectedCustomer.registered_address],
                        ['Contact', selectedCustomer.contact_person || 'Not recorded'],
                        ['Email', selectedCustomer.email || 'Not recorded'],
                      ].map(([label, value]) => (
                        <tr key={label}>
                          <td className="w-44 bg-gray-50 px-3 py-2 font-medium text-gray-500">{label}</td>
                          <td className="px-3 py-2 text-gray-800">{value}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </section>
        )}

        {activeTab === 'attachments' && (
          <section className={`${transactionCardClass()} p-3`}>
            <div className={`${transactionSectionTitleClass()} mb-3`}>Attachments</div>
            <div className="overflow-x-auto rounded border border-gray-200">
              <table className={`${transactionTableClass()} w-full`}>
                <thead className="border-b border-gray-200 bg-gray-50">
                  <tr>
                    {['File Name', 'Document Type', 'Description', 'Uploaded By', 'Upload Date', 'File Size', 'OCR Status', 'Action'].map(h => (
                      <th key={h} className="px-3 py-2 text-left">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td colSpan={8} className="px-3 py-4 text-center text-xs text-gray-400">
                      No attachments linked.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        )}

        {activeTab === 'activity' && (
          <section className={`${transactionCardClass()} p-3`}>
            <div className={`${transactionSectionTitleClass()} mb-3`}>Activity</div>
            <div className="overflow-x-auto rounded border border-gray-200">
              <table className={`${transactionTableClass()} w-full`}>
                <thead className="border-b border-gray-200 bg-gray-50">
                  <tr>
                    {['Date and Time', 'Event Type', 'User or System', 'Description', 'Related Record', 'Action'].map(h => (
                      <th key={h} className="px-3 py-2 text-left">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td colSpan={6} className="px-3 py-4 text-center text-xs text-gray-400">
                      No activity events available.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        )}

        {activeTab === 'notes' && (
          <section className={`${transactionCardClass()} p-3`}>
            <div className={`${transactionSectionTitleClass()} mb-3`}>Notes</div>
            <div className="overflow-x-auto rounded border border-gray-200">
              <table className={`${transactionTableClass()} w-full`}>
                <thead className="border-b border-gray-200 bg-gray-50">
                  <tr>
                    {['Category', 'Visibility', 'Note', 'Source'].map(h => (
                      <th key={h} className="px-3 py-2 text-left">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  <tr>
                    <td className="px-3 py-2 font-medium text-gray-800">Customer-Facing</td>
                    <td className="px-3 py-2 text-gray-500">Print/email memo</td>
                    <td className="px-3 py-2">
                      {readOnly ? (
                        <span className="text-gray-700">{fMemo || 'Not recorded'}</span>
                      ) : (
                        <textarea
                          value={fMemo}
                          onChange={e => setFMemo(e.target.value)}
                          rows={3}
                          className={inp + ' resize-none'}
                          placeholder="Optional invoice footer message"
                        />
                      )}
                    </td>
                    <td className="px-3 py-2 text-gray-500">Invoice memo</td>
                  </tr>
                  <tr>
                    <td className="px-3 py-2 font-medium text-gray-800">Internal</td>
                    <td className="px-3 py-2 text-gray-500">Internal only</td>
                    <td className="px-3 py-2 text-gray-400">No internal note storage is configured for this form.</td>
                    <td className="px-3 py-2 text-gray-500">Not configured</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        )}

        {activeTab === 'audit' && (
          <section className="space-y-3">
            <div className={`${transactionCardClass()} p-3`}>
              <div className={`${transactionSectionTitleClass()} mb-3`}>Audit Evidence</div>
              {editSI?.id ? (
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
                  {auditFacts.map(fact => (
                    <div key={fact.label}>
                      <div className="mb-1 text-[10px] uppercase tracking-wide text-gray-400">{fact.label}</div>
                      <div className="text-xs font-medium text-gray-700">{fact.value}</div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="rounded border border-gray-200 bg-gray-50 px-3 py-4 text-center text-xs text-gray-400">No audit events available.</div>
              )}
            </div>
            {editSI?.id && <AuditTrailSection tableName="sales_invoices" recordId={editSI.id} />}
          </section>
        )}

        {activeTab === 'system' && (
          <section className={`${transactionCardClass()} p-3`}>
            <div className={`${transactionSectionTitleClass()} mb-3`}>System</div>
            <div className="overflow-hidden rounded border border-gray-200">
              <table className={`${transactionTableClass()} w-full`}>
                <tbody className="divide-y divide-gray-100">
                  {[
                    ['Document UUID', editSI?.id || 'Assigned on save'],
                    ['Number Series Result', editSI?.si_number || 'Generated by number series on save'],
                    ['Created Timestamp', editSI?.created_at ? formatDateTime(editSI.created_at) : 'Not saved'],
                    ['Updated Timestamp', editSI?.updated_at ? formatDateTime(editSI.updated_at) : 'Not saved'],
                    ['Posted Timestamp', editSI?.posted_at ? formatDateTime(editSI.posted_at) : 'Not posted'],
                  ].map(([label, value]) => (
                    <tr key={label}>
                      <td className="w-56 bg-gray-50 px-3 py-2 font-medium text-gray-500">{label}</td>
                      <td className="px-3 py-2 font-mono text-gray-700">{value}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        )}
        </div>

        <aside className="pxl-side-panel min-w-0 p-2.5" aria-label="Sales Invoice summary">
          <div className="space-y-4">
            <section className="border-b border-[var(--pxl-border-medium)] pb-4">
              <h2 className="pxl-section-title mb-2">Balance</h2>
              <dl className="space-y-2 text-xs">
                <div className="flex justify-between gap-3"><dt>Invoice Total</dt><dd className="font-mono font-semibold">{fCurrency} {fmt(totals.total_amount)}</dd></div>
                <div className="flex justify-between gap-3"><dt>Expected CWT</dt><dd className="font-mono">{fCurrency} {fmt(fCwtExpected)}</dd></div>
                <div className="flex justify-between gap-3"><dt>Net Collectible</dt><dd className="font-mono font-semibold">{fCurrency} {fmt(expectedNetCollectible)}</dd></div>
              </dl>
            </section>
            <section className="border-b border-[var(--pxl-border-medium)] pb-4">
              <h2 className="pxl-section-title mb-2">Tax</h2>
              <div className="flex justify-between gap-3 text-xs"><span>Output VAT</span><span className="font-mono font-semibold">{fmt(totals.total_vat_amount)}</span></div>
            </section>
            <section className="border-b border-[var(--pxl-border-medium)] pb-4">
              <h2 className="pxl-section-title mb-2">GL Preview</h2>
              <div className="space-y-1 text-xs"><div className="flex justify-between"><span>Debits</span><span className="font-mono">{fmt(combinedGlDebit)}</span></div><div className="flex justify-between"><span>Credits</span><span className="font-mono">{fmt(combinedGlCredit)}</span></div><div className="flex justify-between font-semibold"><span>Difference</span><span className="font-mono">{fmt(combinedGlDifference)}</span></div></div>
            </section>
            <section className="border-b border-[var(--pxl-border-medium)] pb-4">
              <h2 className="pxl-section-title mb-2">Customer</h2>
              <div className="text-xs font-semibold text-gray-800">{fCustomerName || 'Not selected'}</div>
              <div className="pxl-caption mt-1 font-mono">{tinDisplay.tin || 'No TIN selected'}</div>
            </section>
            <section className="border-b border-[var(--pxl-border-medium)] pb-4">
              <h2 className="pxl-section-title mb-2">Audit</h2>
              <div className="pxl-caption">{editSI?.updated_at ? `Updated ${formatDateTime(editSI.updated_at)}` : 'Audit events begin after save.'}</div>
            </section>
            <section>
              <h2 className="pxl-section-title mb-2">Quick Actions</h2>
              <div className="grid gap-1.5">
                <button type="button" onClick={() => setActiveTab('validation')} className="pxl-button pxl-button--neutral justify-start">Review Validation</button>
                <button type="button" onClick={() => setActiveTab('gl')} className="pxl-button pxl-button--neutral justify-start">Review GL Impact</button>
                <button type="button" onClick={() => setActiveTab('related')} className="pxl-button pxl-button--neutral justify-start">Related Documents</button>
              </div>
            </section>
          </div>
        </aside>
        </div>
      </div>

      {/* Void Dialog */}
      {showVoid && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={() => setShowVoid(false)} />
          <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-md p-6 z-10">
            <h2 className="text-sm font-semibold text-gray-900 mb-1">Void Sales Invoice</h2>
            <p className="text-xs text-gray-500 mb-4">
              Voiding <span className="font-mono font-semibold">{editSI?.si_number}</span> is permanent. The SI number will not be reused per BIR regulations.
            </p>
            <div className="space-y-3">
              <div>
                <label className={lbl}>Void Reason <span className="text-red-500">*</span></label>
                <select value={voidReason} onChange={e => setVoidReason(e.target.value)} className={inp}>
                  <option value="">Select reason…</option>
                  {voidReasons.map(r => <option key={r.id} value={r.id}>{r.description}</option>)}
                </select>
              </div>
              <div>
                <label className={lbl}>Additional Notes</label>
                <textarea value={voidMemo} onChange={e => setVoidMemo(e.target.value)}
                  rows={2} className={inp + ' resize-none'} placeholder="Specify details if Other was selected…" />
              </div>
            </div>
            {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
            <div className="flex justify-end gap-2 mt-4">
              <button onClick={() => setShowVoid(false)} className="border border-gray-300 text-gray-700 px-4 py-1.5 rounded text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={doVoid} disabled={!voidReason || saving}
                className="bg-red-600 text-white px-4 py-1.5 rounded text-sm font-medium hover:bg-red-700 disabled:opacity-50">
                {saving ? 'Voiding…' : 'Void Invoice'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
