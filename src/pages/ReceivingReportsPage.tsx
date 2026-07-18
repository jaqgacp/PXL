import { useState, useEffect, useCallback, useRef } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection, StatusBadge, DateCell } from '@/components/ui/shared'
import { TransactionWorkspace } from '@/components/document/TransactionWorkspace'
import { useBranchLabel } from '@/hooks/useBranchLabel'
import { SystemMetadataPanel, TransactionEmptyState } from '@/components/document/TransactionPrimitives'

type RRStatus = 'draft' | 'received' | 'cancelled'

type RR = {
  id: string; company_id: string; rr_number: string; rr_date: string
  branch_id: string | null; warehouse_id?: string | null; department_id?: string | null; cost_center_id?: string | null
  po_id: string; supplier_id: string; supplier_name_snapshot: string
  supplier_dr_no: string | null; remarks: string | null
  status: RRStatus; created_at: string
}

type RRLine = {
  _key: string; id?: string
  po_line_id: string; item_id: string; description: string
  ordered_qty: number; received_qty: number; reject_qty: number
  uom_id: string; unit_price: number; item_type?: 'inventory_item' | 'service' | 'non_inventory'
}

type PORef = {
  id: string; po_number: string; supplier_id: string
  supplier_name_snapshot: string; supplier_tin_snapshot: string | null
  status: string; branch_id: string | null; warehouse_id?: string | null; department_id?: string | null; cost_center_id?: string | null
}
type DimensionRef = { id: string; branch_id: string | null; department_id?: string | null; code: string; name: string }

type POLine = {
  id: string; item_id: string; description: string; quantity: number
  uom_id: string; unit_price: number
  items?: { description: string; uom_id: string }
  units_of_measure?: { uom_name: string }
}

const today = () => new Date().toISOString().split('T')[0]

export default function ReceivingReportsPage() {
  const { companyId, branchId } = useAppCtx()
  const [reports, setReports] = useState<RR[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editRR, setEditRR] = useState<Partial<RR> | null>(null)
  const [lines, setLines] = useState<RRLine[]>([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [openPOs, setOpenPOs] = useState<PORef[]>([])
  const [warehouses, setWarehouses] = useState<DimensionRef[]>([])
  const [departments, setDepartments] = useState<DimensionRef[]>([])
  const [costCenters, setCostCenters] = useState<DimensionRef[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const listRef = useRef<HTMLDivElement>(null)
  const readOnly = mode === 'view'
  const branchLabel = useBranchLabel(branchId)

  const loadReports = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('receiving_reports').select('*').eq('company_id', companyId).order('rr_date', { ascending: false }).order('rr_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`rr_number.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%`)
    const { data } = await q
    setReports(data as RR[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadReports() }, [loadReports, companyId])

  useEffect(() => {
    if (!companyId) return
    supabase.from('purchase_orders' as any).select('id,po_number,supplier_id,supplier_name_snapshot,supplier_tin_snapshot,status,branch_id,warehouse_id,department_id,cost_center_id')
      .eq('company_id', companyId).in('status', ['approved', 'partially_received']).order('po_date', { ascending: false })
      .then(({ data }) => setOpenPOs((data as unknown as PORef[]) || []))
    Promise.all([
      supabase.from('warehouses').select('id,branch_id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('departments').select('id,branch_id,department_code,department_name').eq('company_id', companyId).eq('is_active', true).order('department_code'),
      supabase.from('cost_centers').select('id,branch_id,department_id,cost_center_code,cost_center_name').eq('company_id', companyId).eq('is_active', true).order('cost_center_code'),
    ]).then(([warehouseRes, departmentRes, costCenterRes]) => {
      setWarehouses((warehouseRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, code: row.warehouse_code, name: row.warehouse_name })))
      setDepartments((departmentRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, code: row.department_code, name: row.department_name })))
      setCostCenters((costCenterRes.data || []).map((row: any) => ({ id: row.id, branch_id: row.branch_id, department_id: row.department_id, code: row.cost_center_code, name: row.cost_center_name })))
    })
  }, [companyId])

  const loadPOLines = async (poId: string) => {
    const { data } = await supabase.from('purchase_order_lines')
      .select('id,item_id,description,quantity,uom_id,unit_price,item:items(item_type)')
      .eq('po_id', poId).order('line_number')
    return (data as POLine[] || []).map(l => ({
      _key: l.id, po_line_id: l.id, item_id: l.item_id || '',
      description: l.description, ordered_qty: l.quantity,
      received_qty: l.quantity, reject_qty: 0,
      uom_id: l.uom_id || '', unit_price: l.unit_price, item_type: (l as any).item?.item_type,
    }))
  }

  const openNew = () => {
    setEditRR({ rr_date: today(), branch_id: branchId || '', warehouse_id: warehouses[0]?.id || '', department_id: departments[0]?.id || '', cost_center_id: costCenters[0]?.id || '' })
    setLines([])
    setError('')
    setMode('edit')
  }

  const openView = (rr: RR) => {
    setEditRR({ ...rr })
    supabase.from('receiving_report_lines').select('*,item:items(item_type)').eq('rr_id', rr.id).order('line_number')
      .then(({ data }) => setLines(data?.map((line: any) => ({ ...line, _key: line.id, item_type: line.item?.item_type })) as RRLine[] || []))
    setMode('view')
  }

  const selectPO = async (poId: string) => {
    const po = openPOs.find(p => p.id === poId)
    if (!po) return
    setEditRR(prev => ({ ...prev, po_id: po.id, branch_id: po.branch_id, warehouse_id: po.warehouse_id, department_id: po.department_id, cost_center_id: po.cost_center_id }))
    const lns = await loadPOLines(po.id)
    setLines(lns)
  }

  const updateLine = (idx: number, patch: Partial<RRLine>) => {
    setLines(prev => prev.map((l, i) => i === idx ? { ...l, ...patch } : l))
  }

  const save = async () => {
    if (!companyId || !editRR?.po_id) { setError('Purchase Order is required'); return }
    if (lines.length === 0) { setError('At least one line is required'); return }
    setSaving(true); setError('')
    try {
      const result = await supabase.rpc('fn_save_receiving_report', {
        p_rr_id: (editRR.id || null)!,
        p_header: {
          company_id: companyId, branch_id: editRR.branch_id || branchId || null,
          warehouse_id: editRR.warehouse_id || null,
          department_id: editRR.department_id || null,
          cost_center_id: editRR.cost_center_id || null,
          po_id: editRR.po_id, rr_date: editRR.rr_date,
          supplier_dr_no: editRR.supplier_dr_no || '',
          remarks: editRR.remarks || '',
        },
        p_lines: lines.map(l => ({
          po_line_id: l.po_line_id || null, item_id: l.item_id || null,
          description: l.description, ordered_qty: l.ordered_qty,
          received_qty: l.received_qty, reject_qty: l.reject_qty || 0,
          uom_id: l.uom_id || null, unit_price: l.unit_price || 0,
        })),
      })
      if (result.error) throw new Error(result.error.message)
      setMode('list'); loadReports()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const confirm = async (rr: RR) => {
    const { error: e } = await supabase.rpc('fn_confirm_receiving_report', { p_rr_id: rr.id })
    if (e) { alert(e.message); return }
    loadReports()
  }

  const STATUS_COLORS: Record<string, string> = {
    draft: 'draft', received: 'posted', cancelled: 'error',
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50'
  const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 4, maximumFractionDigits: 4 }).format(n)

  if (mode !== 'list') {
    const selectedPO = openPOs.find(po => po.id === editRR?.po_id)
    const rrStatus = (editRR?.status || 'draft') as RRStatus
    const totalOrdered = lines.reduce((sum, line) => sum + Number(line.ordered_qty || 0), 0)
    const totalReceived = lines.reduce((sum, line) => sum + Number(line.received_qty || 0), 0)
    const totalRejected = lines.reduce((sum, line) => sum + Number(line.reject_qty || 0), 0)
    const receiptValue = lines.reduce((sum, line) => sum + Number(line.received_qty || 0) * Number(line.unit_price || 0), 0)
    const validationErrors = [
      !editRR?.po_id ? 'An approved Purchase Order is required.' : '',
      lines.length === 0 ? 'At least one receipt line is required.' : '',
      lines.some(line => line.received_qty < 0 || line.reject_qty < 0) ? 'Received and rejected quantities cannot be negative.' : '',
      lines.some(line => line.received_qty + line.reject_qty > line.ordered_qty) ? 'Received plus rejected quantity cannot exceed ordered quantity.' : '',
      lines.some(line => line.received_qty > 0 && line.item_type === 'inventory_item' && !editRR?.warehouse_id) ? 'Warehouse is required for inventory-item receipts.' : '',
    ].filter(Boolean)
    const workflowSteps = [{ key: 'draft', label: 'Draft' }, { key: 'received', label: 'Received' }, { key: 'cancelled', label: 'Cancelled' }]

    return (
      <div ref={listRef}>
        <TransactionWorkspace
          title="Goods Receipt"
          documentNo={editRR?.rr_number}
          status={rrStatus}
          statusLabel={rrStatus}
          family="purchase"
          identity={{ name: editRR?.supplier_name_snapshot || selectedPO?.supplier_name_snapshot || 'Supplier from Purchase Order', secondary: selectedPO?.po_number || editRR?.po_id || undefined }}
          metrics={[
            { label: 'Quantity Received', value: fmt(totalReceived), emphasis: true },
            { label: 'Quantity Rejected', value: fmt(totalRejected) },
            { label: 'Receipt Value', value: `₱${new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(receiptValue)}` },
          ]}
          meta={[{ label: 'GL Posting', value: 'No direct GL posting', tone: 'neutral' }]}
          actions={[
            ...(!readOnly ? [{ key: 'save', label: saving ? 'Saving…' : 'Save Receipt', onClick: save, disabled: saving, variant: 'primary' as const }] : []),
            ...(readOnly && rrStatus === 'draft' && editRR?.id ? [{ key: 'confirm', label: 'Confirm Receipt', onClick: () => confirm(editRR as RR), variant: 'primary' as const }] : []),
          ]}
          workflow={{ steps: workflowSteps, currentKey: rrStatus }}
          cards={[
            { title: 'Document Information', content: <div className="grid gap-3 sm:grid-cols-2"><label className="pxl-field-label">Receipt Date<input type="date" value={editRR?.rr_date || ''} disabled={readOnly} onChange={event => setEditRR(current => ({ ...current, rr_date: event.target.value }))} className={`${inp} mt-1 w-full`} /></label><label className="pxl-field-label">Supplier DR No.<input type="text" value={editRR?.supplier_dr_no || ''} disabled={readOnly} onChange={event => setEditRR(current => ({ ...current, supplier_dr_no: event.target.value }))} className={`${inp} mt-1 w-full`} /></label><div><div className="pxl-field-label">Branch</div><div className="pxl-body-text mt-1">{branchLabel}</div></div><div><div className="pxl-field-label">Receipt Status</div><div className="pxl-body-text mt-1">{rrStatus}</div></div></div> },
            { title: 'Supplier Information', content: <div className="grid gap-3"><div><div className="pxl-field-label">Supplier</div><div className="pxl-body-text mt-1">{editRR?.supplier_name_snapshot || selectedPO?.supplier_name_snapshot || 'Sourced from Purchase Order'}</div></div><label className="pxl-field-label">Purchase Order<select value={editRR?.po_id || ''} disabled={readOnly || !!editRR?.id} onChange={event => void selectPO(event.target.value)} className={`${inp} mt-1 w-full`}><option value="">— Select approved PO —</option>{openPOs.map(po => <option key={po.id} value={po.id}>{po.po_number} — {po.supplier_name_snapshot}</option>)}</select></label><div><div className="pxl-field-label">Source Status</div><div className="pxl-body-text mt-1">{selectedPO?.status || 'Saved source snapshot'}</div></div></div> },
            { title: 'Inventory Context', content: <div className="grid gap-3 sm:grid-cols-2"><label className="pxl-field-label">Warehouse<select value={editRR?.warehouse_id || ''} disabled={readOnly} onChange={event => setEditRR(current => ({ ...current, warehouse_id: event.target.value }))} className={`${inp} mt-1 w-full`}><option value="">— Select warehouse —</option>{warehouses.filter(w => !editRR?.branch_id || !w.branch_id || w.branch_id === editRR.branch_id).map(w => <option key={w.id} value={w.id}>{w.code} — {w.name}</option>)}</select></label><label className="pxl-field-label">Department<select value={editRR?.department_id || ''} disabled={readOnly} onChange={event => setEditRR(current => ({ ...current, department_id: event.target.value }))} className={`${inp} mt-1 w-full`}><option value="">— Select department —</option>{departments.filter(d => !editRR?.branch_id || !d.branch_id || d.branch_id === editRR.branch_id).map(d => <option key={d.id} value={d.id}>{d.code} — {d.name}</option>)}</select></label><label className="pxl-field-label">Cost Center<select value={editRR?.cost_center_id || ''} disabled={readOnly} onChange={event => setEditRR(current => ({ ...current, cost_center_id: event.target.value }))} className={`${inp} mt-1 w-full`}><option value="">— Select cost center —</option>{costCenters.filter(c => (!editRR?.branch_id || !c.branch_id || c.branch_id === editRR.branch_id) && (!editRR?.department_id || !c.department_id || c.department_id === editRR.department_id)).map(c => <option key={c.id} value={c.id}>{c.code} — {c.name}</option>)}</select></label><div><div className="pxl-field-label">Ordered Quantity</div><div className="pxl-body-text mt-1 font-mono">{fmt(totalOrdered)}</div></div><div><div className="pxl-field-label">Received Quantity</div><div className="pxl-body-text mt-1 font-mono">{fmt(totalReceived)}</div></div><div><div className="pxl-field-label">Rejected Quantity</div><div className="pxl-body-text mt-1 font-mono">{fmt(totalRejected)}</div></div><div><div className="pxl-field-label">Movement</div><div className="pxl-body-text mt-1">{rrStatus === 'received' ? 'Warehouse stock receipt recorded' : 'Inbound receipt pending confirmation'}</div></div></div> },
          ]}
          tabBadges={{ lines: lines.length }}
          tabContent={{
            lines: <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]"><table className="pxl-data-grid w-full text-xs">
            <thead>
              <tr className="border-b border-gray-200 text-gray-500">
                <th className="text-left pb-2 font-medium">Description</th>
                <th className="text-right pb-2 font-medium w-24">Ordered</th>
                <th className="text-right pb-2 font-medium w-24">Received</th>
                <th className="text-right pb-2 font-medium w-24">Rejected</th>
              </tr>
            </thead>
            <tbody>
              {lines.length === 0 ? (
                <tr><td colSpan={4} className="py-4 text-center text-gray-400">Select a PO to load lines</td></tr>
              ) : lines.map((l, i) => (
                <tr key={l._key} className="border-b border-gray-100">
                  <td className="py-1.5 pr-2 text-gray-700">{l.description}</td>
                  <td className="py-1.5 pr-2 text-right font-mono text-gray-500">{fmt(l.ordered_qty)}</td>
                  <td className="py-1.5 pr-2">
                    <input type="number" value={l.received_qty} disabled={readOnly} onChange={e => updateLine(i, { received_qty: +e.target.value })} className="border border-gray-300 rounded px-2 py-1 text-xs text-right w-24 focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} max={l.ordered_qty} step="any" />
                  </td>
                  <td className="py-1.5">
                    <input type="number" value={l.reject_qty} disabled={readOnly} onChange={e => updateLine(i, { reject_qty: +e.target.value })} className="border border-gray-300 rounded px-2 py-1 text-xs text-right w-24 focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" />
                  </td>
                </tr>
              ))}
            </tbody>
            </table></div>,
            financial: <div className="space-y-4"><div className="ml-auto grid max-w-lg grid-cols-2 gap-2"><span className="text-gray-600">Total Ordered</span><span className="text-right font-mono">{fmt(totalOrdered)}</span><span className="text-gray-600">Total Received</span><span className="text-right font-mono">{fmt(totalReceived)}</span><span className="text-gray-600">Total Rejected</span><span className="text-right font-mono">{fmt(totalRejected)}</span><span className="pxl-section-title border-t pt-2">Source-Cost Value</span><span className="border-t pt-2 text-right font-mono font-bold">₱{new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(receiptValue)}</span></div><p className="pxl-caption">Receipt value is calculated from Purchase Order unit prices; it is not presented as a posted GL amount.</p></div>,
            gl: <TransactionEmptyState>The current Goods Receipt confirmation process updates receipt and Purchase Order status but does not create a direct journal entry.</TransactionEmptyState>,
            tax: <TransactionEmptyState>Goods Receipt does not recognize input VAT or EWT. Tax recognition occurs on the supported Vendor Bill or cash-purchase posting document.</TransactionEmptyState>,
            validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{validationErrors.length > 0 ? validationErrors.map(message => <div key={message} className="pxl-validation-message border border-orange-200 bg-orange-50 text-orange-800">{message}</div>) : <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-800">Receipt quantities and source-document controls are ready.</div>}</div>,
            workflow: <ol className="grid gap-2 sm:grid-cols-3">{workflowSteps.map(step => <li key={step.key} className={`pxl-transaction-card p-3 text-xs font-semibold ${step.key === rrStatus ? 'ring-2 ring-[var(--pxl-transaction-accent)]' : ''}`}>{step.label}</li>)}</ol>,
            approval: <div className="grid gap-3 sm:grid-cols-3"><div><div className="pxl-field-label">Approval / Confirmation</div><div className="pxl-body-text mt-1">{rrStatus === 'received' ? 'Receipt confirmed' : rrStatus === 'draft' ? 'Awaiting confirmation' : 'Cancelled'}</div></div><div><div className="pxl-field-label">Control</div><div className="pxl-body-text mt-1">Confirmation permission and source PO status</div></div><div><div className="pxl-field-label">Next Action</div><div className="pxl-body-text mt-1">{rrStatus === 'draft' ? 'Confirm Receipt' : 'No approval action available'}</div></div></div>,
            audit: editRR?.id ? <AuditTrailSection tableName="receiving_reports" recordId={editRR.id} /> : <TransactionEmptyState>Audit history begins after the Goods Receipt is saved.</TransactionEmptyState>,
            related: editRR?.po_id ? <table className="pxl-data-grid w-full"><thead><tr><th className="text-left">Relationship</th><th className="text-left">Document</th><th className="text-left">Status</th><th className="text-left">Open</th></tr></thead><tbody><tr><td>Source Purchase Order</td><td className="font-mono font-semibold">{selectedPO?.po_number || editRR.po_id}</td><td>{selectedPO?.status || 'Source snapshot'}</td><td><Link to="/purchase-orders" className="text-blue-700 hover:underline">Purchase Orders</Link></td></tr></tbody></table> : <TransactionEmptyState>Select a Purchase Order to establish source-document traceability.</TransactionEmptyState>,
            party: <dl className="grid gap-3 sm:grid-cols-2"><div><dt className="pxl-field-label">Supplier</dt><dd className="pxl-body-text mt-1">{editRR?.supplier_name_snapshot || selectedPO?.supplier_name_snapshot || '—'}</dd></div><div><dt className="pxl-field-label">Supplier ID</dt><dd className="pxl-body-text mt-1 font-mono">{editRR?.supplier_id || selectedPO?.supplier_id || '—'}</dd></div></dl>,
            activity: <div className="grid gap-3 sm:grid-cols-3"><div><div className="pxl-field-label">Created</div><div className="pxl-body-text mt-1">{editRR?.created_at ? new Date(editRR.created_at).toLocaleString('en-PH') : 'Not saved'}</div></div><div><div className="pxl-field-label">Confirmed</div><div className="pxl-body-text mt-1">{rrStatus === 'received' ? 'Yes' : 'No'}</div></div><div><div className="pxl-field-label">Inventory Evidence</div><div className="pxl-body-text mt-1">{rrStatus === 'received' ? 'Receipt confirmed' : 'Pending confirmation'}</div></div></div>,
            notes: <label className="pxl-field-label">Receipt Remarks<textarea value={editRR?.remarks || ''} disabled={readOnly} rows={5} onChange={event => setEditRR(current => ({ ...current, remarks: event.target.value }))} className={`${inp} mt-1 w-full`} /></label>,
            system: <SystemMetadataPanel facts={[
              { label: 'Internal ID', value: editRR?.id || 'Assigned when saved', hint: 'Transaction identity' },
              { label: 'Document Number', value: editRR?.rr_number || 'Generated from number series', hint: 'Receiving Report number' },
              { label: 'Company ID', value: companyId || '—', hint: 'Tenant boundary' },
              { label: 'Branch ID', value: branchId || '—', hint: 'Operational context' },
              { label: 'Source Purchase Order', value: editRR?.po_id || 'Not selected', hint: 'Document lineage' },
              { label: 'Created', value: editRR?.created_at ? new Date(editRR.created_at).toLocaleString('en-PH') : 'Not saved', hint: 'Audit metadata' },
              { label: 'Posting Status', value: 'No direct GL posting', hint: 'Accounting behavior' },
            ]} />,
          }}
          emptyTabMessages={{ attachments: 'No attachments have been added to this Goods Receipt.' }}
          sidebarPanels={[
            { key: 'inventory', title: 'Inventory', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Received</span><span className="font-mono text-sm font-bold">{fmt(totalReceived)}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Rejected</span><span className="font-mono text-xs">{fmt(totalRejected)}</span></div></div> },
            { key: 'source', title: 'Source Document', content: <div><div className="font-mono text-xs font-semibold">{selectedPO?.po_number || editRR?.po_id || 'Not selected'}</div><div className="pxl-caption mt-1">Purchase Order</div></div> },
            { key: 'gl', title: 'GL', content: <p className="pxl-caption">No direct journal posting in the current confirmation process.</p> },
            { key: 'supplier', title: 'Supplier', content: <p className="text-xs font-semibold">{editRR?.supplier_name_snapshot || selectedPO?.supplier_name_snapshot || 'Not selected'}</p> },
          ]}
          footer={<span>{editRR?.id ? `Created ${editRR.created_at ? new Date(editRR.created_at).toLocaleString('en-PH') : '—'}` : 'Unsaved Goods Receipt'}</span>}
          onBack={() => setMode('list')}
          backLabel="Receiving Reports"
        />
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Receiving Reports</h2>
        <button onClick={openNew} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New RR</button>
      </div>

      <div className="flex gap-2">
        <input placeholder="Search RR # or supplier…" value={fSearch} onChange={e => setFSearch(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-60" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option>
          <option value="draft">Draft</option>
          <option value="received">Received</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : reports.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-400">No receiving reports found.</div>
        ) : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['RR Date','RR Number','Supplier','Supplier DR No.','Status',''].map(h => (
                  <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {reports.map(rr => (
                <tr key={rr.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={rr.rr_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{rr.rr_number}</td>
                  <td className="px-3 py-2 text-gray-700">{rr.supplier_name_snapshot}</td>
                  <td className="px-3 py-2 text-gray-500">{rr.supplier_dr_no || '—'}</td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[rr.status]} label={rr.status} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => openView(rr)} className="text-blue-600 hover:text-blue-800">View</button>
                      {rr.status === 'draft' && <button onClick={() => confirm(rr)} className="text-green-600 hover:text-green-800">Confirm</button>}
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
