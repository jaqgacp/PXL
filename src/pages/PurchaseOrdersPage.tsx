import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { TransactionWorkspace } from '@/components/document/TransactionWorkspace'
import { SystemMetadataPanel, TransactionEmptyState } from '@/components/document/TransactionPrimitives'
import { normalizePhTin } from '@/lib/philippines'

type POStatus = 'draft' | 'approved' | 'partially_received' | 'fully_received' | 'cancelled'

type PO = {
  id: string; company_id: string; branch_id: string | null
  warehouse_id?: string | null; department_id?: string | null; cost_center_id?: string | null
  po_number: string; po_date: string; supplier_id: string
  supplier_name_snapshot: string; supplier_tin_snapshot: string | null
  delivery_address: string | null; expected_date: string | null
  payment_terms_id: string | null; currency_code: string
  notes: string | null; total_amount: number; status: POStatus
  created_at: string
}

type POLine = {
  _key: string; id?: string
  item_id: string; description: string
  quantity: number; uom_id: string; uom_label: string
  unit_price: number; total_amount: number
}

type SupplierRef = {
  id: string; registered_name: string; tin: string
  registered_address: string; default_terms_id: string | null
}
type ItemRef = { id: string; item_code: string; description: string; uom_id: string; uom_label: string; standard_cost: number }
type WarehouseRef = { id: string; branch_id: string | null; warehouse_code: string; warehouse_name: string }
type DepartmentRef = { id: string; branch_id: string | null; department_code: string; department_name: string }
type CostCenterRef = { id: string; branch_id: string | null; department_id: string | null; cost_center_code: string; cost_center_name: string }
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const newLine = (): POLine => ({
  _key: crypto.randomUUID(), item_id: '', description: '',
  quantity: 1, uom_id: '', uom_label: '', unit_price: 0, total_amount: 0,
})

export default function PurchaseOrdersPage() {
  const { companyId, branchId } = useAppCtx()
  const [orders, setOrders] = useState<PO[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editPO, setEditPO] = useState<Partial<PO> | null>(null)
  const [lines, setLines] = useState<POLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [warehouses, setWarehouses] = useState<WarehouseRef[]>([])
  const [departments, setDepartments] = useState<DepartmentRef[]>([])
  const [costCenters, setCostCenters] = useState<CostCenterRef[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const listRef = useRef<HTMLDivElement>(null)
  const readOnly = mode === 'view'

  const loadOrders = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('purchase_orders').select('*').eq('company_id', companyId).order('po_date', { ascending: false }).order('po_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`po_number.ilike.%${fSearch}%,notes.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%`)
    const { data } = await q
    setOrders(data as PO[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadOrders() }, [loadOrders, companyId])

  useEffect(() => {
    if (!companyId) return
    void Promise.all([
      supabase.from('suppliers').select('id,registered_name,tin,registered_address,default_terms_id').eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('items').select('id,item_code,description,uom_id,uom:units_of_measure(uom_code),standard_cost').eq('company_id', companyId).eq('is_active', true).order('description'),
      supabase.from('warehouses').select('id,branch_id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('departments').select('id,branch_id,department_code,department_name').eq('company_id', companyId).eq('is_active', true).order('department_code'),
      supabase.from('cost_centers').select('id,branch_id,department_id,cost_center_code,cost_center_name').eq('company_id', companyId).eq('is_active', true).order('cost_center_code'),
    ]).then(([supplierRes, itemRes, warehouseRes, departmentRes, costCenterRes]) => {
      setSuppliers(supplierRes.data as SupplierRef[] || [])
      setItems((itemRes.data || []).map((item: any) => ({ ...item, uom_label: item.uom?.uom_code || '' })))
      setWarehouses(warehouseRes.data as WarehouseRef[] || [])
      setDepartments(departmentRes.data as DepartmentRef[] || [])
      setCostCenters(costCenterRes.data as CostCenterRef[] || [])
      const referenceError = supplierRes.error || itemRes.error || warehouseRes.error || departmentRes.error || costCenterRes.error
      if (referenceError) setError(`Unable to load purchase selections: ${referenceError.message}`)
    })
  }, [companyId])

  const openNew = () => {
    const defaultWarehouse = warehouses.find(warehouse => !warehouse.branch_id || warehouse.branch_id === branchId) || warehouses[0]
    const defaultDepartment = departments.find(department => !department.branch_id || department.branch_id === branchId) || departments[0]
    const defaultCostCenter = costCenters.find(costCenter =>
      (!costCenter.branch_id || costCenter.branch_id === branchId)
      && (!defaultDepartment || !costCenter.department_id || costCenter.department_id === defaultDepartment.id)
    ) || costCenters[0]
    setEditPO({
      po_date: today(), currency_code: 'PHP', branch_id: branchId || '',
      warehouse_id: defaultWarehouse?.id || '', department_id: defaultDepartment?.id || '',
      cost_center_id: defaultCostCenter?.id || '',
    })
    setLines([newLine()])
    setError('')
    setMode('edit')
    setTimeout(() => listRef.current?.scrollTo(0, 0), 10)
  }

  const openEdit = (po: PO) => {
    setEditPO({ ...po })
    supabase.from('purchase_order_lines').select('*').eq('po_id', po.id).order('line_number')
      .then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id, uom_label: '' })) as POLine[] || [newLine()]))
    setError('')
    setMode('edit')
  }

  const openView = (po: PO) => {
    setEditPO({ ...po })
    supabase.from('purchase_order_lines').select('*').eq('po_id', po.id).order('line_number')
      .then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id, uom_label: '' })) as POLine[] || []))
    setMode('view')
  }

  const selectSupplier = (id: string) => {
    const s = suppliers.find(x => x.id === id)
    if (!s) return
    setEditPO(prev => ({ ...prev, supplier_id: s.id, supplier_name_snapshot: s.registered_name, supplier_tin_snapshot: normalizePhTin(s.tin), delivery_address: s.registered_address, payment_terms_id: s.default_terms_id || '' }))
  }

  const selectItem = (idx: number, id: string) => {
    const item = items.find(x => x.id === id)
    if (!item) return
    updateLine(idx, { item_id: item.id, description: item.description, uom_id: item.uom_id, uom_label: item.uom_label, unit_price: item.standard_cost })
  }

  const updateLine = (idx: number, patch: Partial<POLine>) => {
    setLines(prev => prev.map((l, i) => {
      if (i !== idx) return l
      const updated = { ...l, ...patch }
      updated.total_amount = Math.round(updated.quantity * updated.unit_price * 100) / 100
      return updated
    }))
  }

  const grandTotal = lines.reduce((s, l) => s + (l.total_amount || 0), 0)

  const save = async () => {
    if (!companyId || !editPO?.supplier_id) { setError('Supplier is required'); return }
    setSaving(true); setError('')
    try {
      const id = await supabase.rpc('fn_save_purchase_order', {
        p_po_id: (editPO.id || null)!,
        p_header: {
          company_id: companyId, branch_id: editPO.branch_id || branchId || null,
          warehouse_id: editPO.warehouse_id || null,
          department_id: editPO.department_id || null,
          cost_center_id: editPO.cost_center_id || null,
          supplier_id: editPO.supplier_id, supplier_name_snapshot: editPO.supplier_name_snapshot,
          supplier_tin_snapshot: editPO.supplier_tin_snapshot || '',
          po_date: editPO.po_date, delivery_address: editPO.delivery_address || '',
          expected_date: editPO.expected_date || '', payment_terms_id: editPO.payment_terms_id || '',
          currency_code: editPO.currency_code || 'PHP', notes: editPO.notes || '',
        },
        p_lines: lines.filter(l => l.description.trim()).map(l => ({
          item_id: l.item_id || null, description: l.description,
          quantity: l.quantity, uom_id: l.uom_id || null, unit_price: l.unit_price,
        })),
      })
      if (id.error) throw new Error(id.error.message)
      setMode('list'); loadOrders()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const approve = async (po: PO) => {
    const { error: e } = await supabase.rpc('fn_approve_purchase_order', { p_po_id: po.id })
    if (e) { alert(e.message); return }
    loadOrders()
  }

  const cancel = async (po: PO) => {
    if (!confirm(`Cancel PO ${po.po_number}?`)) return
    const { error: e } = await supabase.rpc('fn_cancel_purchase_order', { p_po_id: po.id })
    if (e) { alert(e.message); return }
    loadOrders()
  }

  const STATUS_COLORS: Record<string, string> = {
    draft: 'draft', approved: 'approved', partially_received: 'warning',
    fully_received: 'posted', cancelled: 'error',
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50 disabled:text-gray-500'

  if (mode !== 'list') {
    const selectedSupplier = suppliers.find(supplier => supplier.id === editPO?.supplier_id)
    const poStatus = (editPO?.status || 'draft') as POStatus
    const workflowSteps = [
      { key: 'draft', label: 'Draft' },
      { key: 'approved', label: 'Approved' },
      { key: 'partially_received', label: 'Partially Received' },
      { key: 'fully_received', label: 'Received' },
      { key: 'cancelled', label: 'Cancelled' },
    ]
    const lineErrors = [
      !editPO?.supplier_id ? 'Supplier is required.' : '',
      lines.filter(line => line.description.trim()).length === 0 ? 'At least one purchase-order line is required.' : '',
      lines.some(line => line.quantity <= 0) ? 'Line quantities must be greater than zero.' : '',
    ].filter(Boolean)

    return (
      <div ref={listRef}>
        <TransactionWorkspace
          title="Purchase Order"
          documentNo={editPO?.po_number}
          status={poStatus}
          statusLabel={poStatus.replace(/_/g, ' ')}
          family="purchase"
          identity={{ name: editPO?.supplier_name_snapshot || selectedSupplier?.registered_name || 'Supplier not selected', secondary: editPO?.supplier_tin_snapshot || selectedSupplier?.tin || undefined }}
          metrics={[
            { label: 'Order Total', value: `₱${fmt(grandTotal)}`, emphasis: true },
            { label: 'Line Count', value: lines.length },
            { label: 'Receipt Status', value: poStatus === 'fully_received' ? 'Received' : poStatus === 'partially_received' ? 'Partial' : 'Not received' },
          ]}
          meta={[{ label: 'Posting', value: 'No direct GL posting', tone: 'neutral' }]}
          actions={[
            ...(!readOnly ? [
              { key: 'save', label: saving ? 'Saving…' : 'Save PO', onClick: save, disabled: saving, variant: 'primary' as const },
              { key: 'cancel-edit', label: 'Cancel Edit', onClick: () => setMode('list'), group: 'more' as const },
            ] : []),
            ...(readOnly && poStatus === 'draft' && editPO?.id ? [
              { key: 'edit', label: 'Edit', onClick: () => setMode('edit') },
              { key: 'approve', label: 'Approve', onClick: () => approve(editPO as PO), variant: 'primary' as const },
            ] : []),
            ...(readOnly && ['draft', 'approved', 'partially_received'].includes(poStatus) && editPO?.id ? [
              { key: 'cancel', label: 'Cancel PO', onClick: () => cancel(editPO as PO), variant: 'danger' as const, group: 'more' as const },
            ] : []),
          ]}
          workflow={{ steps: workflowSteps, currentKey: poStatus }}
          cards={[
            {
              title: 'Document Information',
              content: <div className="grid gap-3 sm:grid-cols-2">
                <label className="pxl-field-label">PO Date *<input type="date" value={editPO?.po_date || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, po_date: e.target.value }))} className={`${inp} mt-1 w-full`} /></label>
                <label className="pxl-field-label">Expected Delivery<input type="date" value={editPO?.expected_date || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, expected_date: e.target.value }))} className={`${inp} mt-1 w-full`} /></label>
                <div><div className="pxl-field-label">Currency</div><div className="pxl-body-text mt-1">{editPO?.currency_code || 'PHP'}</div></div>
                <div><div className="pxl-field-label">Document Type</div><div className="pxl-body-text mt-1">Non-posting source document</div></div>
              </div>,
            },
            {
              title: 'Supplier Information',
              content: <div className="grid gap-3 sm:grid-cols-2">
                <label className="pxl-field-label sm:col-span-2">Supplier *<select value={editPO?.supplier_id || ''} disabled={readOnly} onChange={e => selectSupplier(e.target.value)} className={`${inp} mt-1 w-full`}><option value="">— Select supplier —</option>{suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}</select></label>
                <div><div className="pxl-field-label">Supplier TIN</div><div className="pxl-body-text mt-1 font-mono">{editPO?.supplier_tin_snapshot || selectedSupplier?.tin || '—'}</div></div>
                <div><div className="pxl-field-label">Payment Terms</div><div className="pxl-body-text mt-1">{editPO?.payment_terms_id ? 'Sourced from supplier' : 'Not configured'}</div></div>
              </div>,
            },
            {
              title: 'Purchase Context',
              content: <div className="grid gap-3">
                <label className="pxl-field-label">Delivery Address<input type="text" value={editPO?.delivery_address || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, delivery_address: e.target.value }))} className={`${inp} mt-1 w-full`} /></label>
                <div className="grid gap-3 sm:grid-cols-3">
                  <label className="pxl-field-label">Warehouse<select value={editPO?.warehouse_id || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, warehouse_id: e.target.value }))} className={`${inp} mt-1 w-full`}><option value="">— Select warehouse —</option>{warehouses.filter(warehouse => !editPO?.branch_id || !warehouse.branch_id || warehouse.branch_id === editPO.branch_id).map(warehouse => <option key={warehouse.id} value={warehouse.id}>{warehouse.warehouse_code} — {warehouse.warehouse_name}</option>)}</select></label>
                  <label className="pxl-field-label">Department<select value={editPO?.department_id || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, department_id: e.target.value, cost_center_id: costCenters.some(costCenter => costCenter.id === p?.cost_center_id && (!e.target.value || !costCenter.department_id || costCenter.department_id === e.target.value)) ? p?.cost_center_id : '' }))} className={`${inp} mt-1 w-full`}><option value="">— Select department —</option>{departments.filter(department => !editPO?.branch_id || !department.branch_id || department.branch_id === editPO.branch_id).map(department => <option key={department.id} value={department.id}>{department.department_code} — {department.department_name}</option>)}</select></label>
                  <label className="pxl-field-label">Cost Center<select value={editPO?.cost_center_id || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, cost_center_id: e.target.value }))} className={`${inp} mt-1 w-full`}><option value="">— Select cost center —</option>{costCenters.filter(costCenter => (!editPO?.branch_id || !costCenter.branch_id || costCenter.branch_id === editPO.branch_id) && (!editPO?.department_id || !costCenter.department_id || costCenter.department_id === editPO.department_id)).map(costCenter => <option key={costCenter.id} value={costCenter.id}>{costCenter.cost_center_code} — {costCenter.cost_center_name}</option>)}</select></label>
                </div>
                <div className="grid gap-3 sm:grid-cols-2"><div><div className="pxl-field-label">Conversion Status</div><div className="pxl-body-text mt-1">{poStatus === 'fully_received' ? 'Fully received' : poStatus === 'partially_received' ? 'Partially received' : 'Open for receipt'}</div></div><div><div className="pxl-field-label">Expected Impact</div><div className="pxl-body-text mt-1">Receipt and vendor billing downstream</div></div></div>
              </div>,
            },
          ]}
          tabBadges={{ lines: lines.length }}
          tabContent={{
            lines: <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]">
              <div className="flex items-center justify-between border-b border-[var(--pxl-border-medium)] px-3 py-2"><h2 className="pxl-section-title">Purchase Order Lines</h2>{!readOnly && <button onClick={() => setLines(current => [...current, newLine()])} className="pxl-button pxl-button--text">+ Add Line</button>}</div>
              <table className="pxl-data-grid w-full text-xs">
            <thead>
              <tr className="border-b border-gray-200 text-gray-500">
                <th className="text-left pb-2 font-medium w-48">Item</th>
                <th className="text-left pb-2 font-medium">Description</th>
                <th className="text-right pb-2 font-medium w-20">Qty</th>
                <th className="text-right pb-2 font-medium w-28">Unit Price</th>
                <th className="text-right pb-2 font-medium w-28">Total</th>
                {!readOnly && <th className="w-8" />}
              </tr>
            </thead>
            <tbody>
              {lines.map((l, i) => (
                <tr key={l._key} className="border-b border-gray-100">
                  <td className="py-1.5 pr-2">
                    <select value={l.item_id} disabled={readOnly} onChange={e => selectItem(i, e.target.value)} className={inp + ' w-full text-xs'}>
                      <option value="">— Item —</option>
                      {items.map(it => <option key={it.id} value={it.id}>{it.item_code} — {it.description}</option>)}
                    </select>
                  </td>
                  <td className="py-1.5 pr-2"><input value={l.description} disabled={readOnly} onChange={e => updateLine(i, { description: e.target.value })} className={inp + ' w-full text-xs'} placeholder="Description" /></td>
                  <td className="py-1.5 pr-2"><input type="number" value={l.quantity} disabled={readOnly} onChange={e => updateLine(i, { quantity: +e.target.value })} className={inp + ' w-20 text-right text-xs'} min={0} step="any" /></td>
                  <td className="py-1.5 pr-2"><input type="number" value={l.unit_price} disabled={readOnly} onChange={e => updateLine(i, { unit_price: +e.target.value })} className={inp + ' w-28 text-right text-xs'} min={0} step="any" /></td>
                  <td className="py-1.5 text-right font-mono text-xs">{fmt(l.total_amount)}</td>
                  {!readOnly && <td className="py-1.5 pl-2"><button onClick={() => setLines(p => p.filter((_, j) => j !== i))} className="text-gray-300 hover:text-red-500 text-sm">×</button></td>}
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="border-t-2 border-gray-300 font-semibold">
                <td colSpan={4} className="pt-2 text-right text-xs text-gray-600 pr-2">Total Amount</td>
                <td className="pt-2 text-right font-mono text-sm">{fmt(grandTotal)}</td>
              </tr>
            </tfoot>
              </table>
            </div>,
            financial: <div className="ml-auto grid max-w-md grid-cols-2 gap-2"><span className="text-gray-600">Committed Purchase</span><span className="text-right font-mono">₱{fmt(grandTotal)}</span><span className="pxl-section-title border-t pt-2">Order Total</span><span className="border-t pt-2 text-right font-mono font-bold">₱{fmt(grandTotal)}</span></div>,
            gl: <TransactionEmptyState>Purchase Orders do not post directly to the general ledger. Posting occurs through supported receipt and vendor-bill processes.</TransactionEmptyState>,
            tax: <TransactionEmptyState>Purchase Orders do not recognize input VAT or EWT. Tax treatment is determined by the downstream posting document.</TransactionEmptyState>,
            validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{lineErrors.length > 0 ? lineErrors.map(message => <div key={message} className="pxl-validation-message border border-orange-200 bg-orange-50 text-orange-800">{message}</div>) : <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-800">Purchase Order is ready for its current lifecycle action.</div>}</div>,
            workflow: <ol className="grid gap-2 sm:grid-cols-5">{workflowSteps.map(step => <li key={step.key} className={`pxl-transaction-card p-3 text-xs font-semibold ${step.key === poStatus ? 'ring-2 ring-[var(--pxl-transaction-accent)]' : ''}`}>{step.label}</li>)}</ol>,
            approval: <div className="grid gap-3 sm:grid-cols-3"><div><div className="pxl-field-label">Approval Status</div><div className="pxl-body-text mt-1">{poStatus === 'draft' ? 'Pending approval' : poStatus === 'cancelled' ? 'Cancelled' : 'Approved'}</div></div><div><div className="pxl-field-label">Control</div><div className="pxl-body-text mt-1">Status and permission controlled</div></div><div><div className="pxl-field-label">Next Action</div><div className="pxl-body-text mt-1">{poStatus === 'draft' ? 'Approve' : poStatus === 'approved' ? 'Receive' : 'No approval action available'}</div></div></div>,
            audit: <div className="grid gap-3 sm:grid-cols-3"><div><div className="pxl-field-label">Created</div><div className="pxl-body-text mt-1">{editPO?.created_at ? new Date(editPO.created_at).toLocaleString('en-PH') : 'Not saved'}</div></div><div><div className="pxl-field-label">Current Status</div><div className="pxl-body-text mt-1">{poStatus.replace(/_/g, ' ')}</div></div><div><div className="pxl-field-label">Edit State</div><div className="pxl-body-text mt-1">{poStatus === 'draft' ? 'Editable' : 'Lifecycle controlled'}</div></div></div>,
            related: <TransactionEmptyState>{poStatus === 'partially_received' || poStatus === 'fully_received' ? 'Receipt status is recorded, but related-document identifiers are not exposed by this page query.' : 'No receiving report or vendor bill has been linked to this Purchase Order.'}</TransactionEmptyState>,
            party: selectedSupplier ? <dl className="grid gap-3 sm:grid-cols-3"><div><dt className="pxl-field-label">Supplier</dt><dd className="pxl-body-text mt-1">{selectedSupplier.registered_name}</dd></div><div><dt className="pxl-field-label">TIN</dt><dd className="pxl-body-text mt-1 font-mono">{selectedSupplier.tin || '—'}</dd></div><div><dt className="pxl-field-label">Registered Address</dt><dd className="pxl-body-text mt-1">{selectedSupplier.registered_address || '—'}</dd></div></dl> : <TransactionEmptyState>Select a supplier to see related-party information.</TransactionEmptyState>,
            notes: <label className="pxl-field-label">Purchase Order Notes<textarea value={editPO?.notes || ''} disabled={readOnly} onChange={e => setEditPO(p => ({ ...p, notes: e.target.value }))} rows={5} className={`${inp} mt-1 w-full resize-none`} /></label>,
            system: <SystemMetadataPanel facts={[
              { label: 'Internal ID', value: editPO?.id || 'Assigned when saved', hint: 'Transaction identity' },
              { label: 'Document Number', value: editPO?.po_number || 'Generated from number series', hint: 'Purchase Order number' },
              { label: 'Company ID', value: companyId || '—', hint: 'Tenant boundary' },
              { label: 'Branch ID', value: editPO?.branch_id || branchId || '—', hint: 'Operational context' },
              { label: 'Created', value: editPO?.created_at ? new Date(editPO.created_at).toLocaleString('en-PH') : 'Not saved', hint: 'Audit metadata' },
              { label: 'Posting Status', value: 'Non-posting document', hint: 'Accounting behavior' },
            ]} />,
          }}
          emptyTabMessages={{ attachments: 'No attachments have been added to this Purchase Order.', activity: 'No additional Purchase Order activity is available.' }}
          sidebarPanels={[
            { key: 'commitment', title: 'Commitment', content: <div className="flex justify-between gap-3"><span className="pxl-field-label">Order Total</span><span className="font-mono text-sm font-bold">₱{fmt(grandTotal)}</span></div> },
            { key: 'receipt', title: 'Receipt Status', content: <p className="pxl-body-text">{poStatus === 'fully_received' ? 'Fully received' : poStatus === 'partially_received' ? 'Partially received' : 'Not received'}</p> },
            { key: 'supplier', title: 'Supplier', content: <div><div className="text-xs font-semibold">{editPO?.supplier_name_snapshot || selectedSupplier?.registered_name || 'Not selected'}</div><div className="pxl-caption mt-1 font-mono">{editPO?.supplier_tin_snapshot || selectedSupplier?.tin || 'No TIN'}</div></div> },
            { key: 'posting', title: 'GL', content: <p className="pxl-caption">No direct posting. Receipt and billing documents carry downstream impact.</p> },
          ]}
          footer={<span>{editPO?.id ? `Created ${editPO.created_at ? new Date(editPO.created_at).toLocaleString('en-PH') : '—'}` : 'Unsaved Purchase Order'}</span>}
          onBack={() => setMode('list')}
          backLabel="Purchase Orders"
        />
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Purchase Orders</h2>
        <button onClick={openNew} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New PO</button>
      </div>

      <div className="flex gap-2">
        <input placeholder="Search PO # or supplier…" value={fSearch} onChange={e => setFSearch(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-60" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option>
          <option value="draft">Draft</option>
          <option value="approved">Approved</option>
          <option value="partially_received">Partially Received</option>
          <option value="fully_received">Fully Received</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : orders.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-400">No purchase orders found.</div>
        ) : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['PO Date','PO Number','Reference / Note','Supplier','Expected Date','Total Amount','Status',''].map(h => (
                  <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {orders.map(po => (
                <tr key={po.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={po.po_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{po.po_number}</td>
                  <td className="px-3 py-2 font-mono text-gray-500">{po.notes || '—'}</td>
                  <td className="px-3 py-2 text-gray-700">{po.supplier_name_snapshot}</td>
                  <td className="px-3 py-2"><DateCell date={po.expected_date} /></td>
                  <td className="px-3 py-2 text-right"><AmountCell amount={po.total_amount} /></td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[po.status]} label={po.status.replace('_', ' ')} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => openView(po)} className="text-blue-600 hover:text-blue-800">View</button>
                      {po.status === 'draft' && <button onClick={() => openEdit(po)} className="text-gray-600 hover:text-gray-800">Edit</button>}
                      {po.status === 'draft' && <button onClick={() => approve(po)} className="text-green-600 hover:text-green-800">Approve</button>}
                      {['draft','approved','partially_received'].includes(po.status) && <button onClick={() => cancel(po)} className="text-red-600 hover:text-red-800">Cancel</button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
