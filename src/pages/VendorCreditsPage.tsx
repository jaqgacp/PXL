import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

type VCStatus = 'draft' | 'open' | 'applied' | 'cancelled'

type VC = {
  id: string; company_id: string; vc_number: string; credit_date: string
  supplier_id: string; supplier_name_snapshot: string; supplier_tin_snapshot: string | null
  supplier_cm_no: string | null; reference_bill_id: string | null
  remarks: string | null; total_taxable_amount: number; total_input_vat_amount: number
  total_amount: number; remaining_balance: number; status: VCStatus; created_at: string
}

type VCLine = {
  _key: string; id?: string; item_id: string; description: string
  quantity: number; uom_id: string; unit_price: number; net_amount: number
  vat_code_id: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'
  vat_rate: number; input_vat_amount: number; total_amount: number
  expense_account_id: string
}

type SupplierRef = { id: string; registered_name: string; tin: string }

type VATRef = { id: string; vat_code: string; description: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; rate: number }
type COARef = { id: string; account_code: string; account_name: string }
type VBRef = { id: string; bill_number: string; total_amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

const newLine = (): VCLine => ({
  _key: crypto.randomUUID(), item_id: '', description: '', quantity: 1, uom_id: '',
  unit_price: 0, net_amount: 0, vat_code_id: '', vat_classification: 'regular', vat_rate: 12,
  input_vat_amount: 0, total_amount: 0, expense_account_id: '',
})

const computeLine = (l: VCLine): VCLine => {
  const net = Math.max(Math.round(l.quantity * l.unit_price * 100) / 100, 0)
  const vat = l.vat_classification === 'regular' ? Math.round(net * l.vat_rate / 100 * 100) / 100 : 0
  return { ...l, net_amount: net, input_vat_amount: vat, total_amount: net + vat }
}

export default function VendorCreditsPage() {
  const { companyId, branchId } = useAppCtx()
  const [credits, setCredits] = useState<VC[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editVC, setEditVC] = useState<Partial<VC> | null>(null)
  const [lines, setLines] = useState<VCLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [vatCodes, setVatCodes] = useState<VATRef[]>([])
  const [expenseAccounts, setExpenseAccounts] = useState<COARef[]>([])
  const [vendorBills, setVendorBills] = useState<VBRef[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const listRef = useRef<HTMLDivElement>(null)
  const readOnly = mode === 'view'

  const loadCredits = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('vendor_credits').select('*').eq('company_id', companyId).order('credit_date', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`vc_number.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%`)
    const { data } = await q
    setCredits(data as VC[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadCredits() }, [loadCredits, companyId])

  useEffect(() => {
    if (!companyId) return
    supabase.from('suppliers').select('id,registered_name,tin').eq('company_id', companyId).eq('is_active', true).order('registered_name').then(({ data }) => setSuppliers(data as SupplierRef[] || []))
    supabase.from('vat_codes').select('id,vat_code,description,vat_classification,tax_codes(rate)').eq('transaction_type', 'input_vat').eq('is_active', true).then(({ data }) => setVatCodes((data || []).map((v: any) => ({ ...v, rate: v.tax_codes?.rate || 0 }))))
    supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).in('account_type', ['expense','cost_of_goods']).eq('is_active', true).order('account_code').then(({ data }) => setExpenseAccounts(data as COARef[] || []))
    supabase.from('vendor_bills').select('id,bill_number,total_amount').eq('company_id', companyId).eq('status', 'posted').order('bill_date', { ascending: false }).then(({ data }) => setVendorBills(data as VBRef[] || []))
  }, [companyId])

  const selectSupplier = (id: string) => {
    const s = suppliers.find(x => x.id === id)
    if (!s) return
    setEditVC(p => ({ ...p, supplier_id: s.id, supplier_name_snapshot: s.registered_name, supplier_tin_snapshot: s.tin }))
  }

  const updateLine = (idx: number, patch: Partial<VCLine>) => {
    setLines(prev => prev.map((l, i) => i !== idx ? l : computeLine({ ...l, ...patch })))
  }

  const totals = lines.reduce((acc, l) => ({ vat: acc.vat + l.input_vat_amount, total: acc.total + l.total_amount }), { vat: 0, total: 0 })

  const save = async () => {
    if (!companyId || !editVC?.supplier_id) { setError('Supplier is required'); return }
    setSaving(true); setError('')
    try {
      const result = await supabase.rpc('fn_save_vendor_credit', {
        p_vc_id: editVC.id || null,
        p_header: {
          company_id: companyId, branch_id: branchId || null,
          supplier_id: editVC.supplier_id, supplier_name_snapshot: editVC.supplier_name_snapshot,
          supplier_tin_snapshot: editVC.supplier_tin_snapshot || '',
          credit_date: editVC.credit_date, supplier_cm_no: editVC.supplier_cm_no || '',
          reference_bill_id: editVC.reference_bill_id || '',
          remarks: editVC.remarks || '',
        },
        p_lines: lines.filter(l => l.description.trim()).map(l => ({
          item_id: l.item_id || null, description: l.description, quantity: l.quantity,
          uom_id: l.uom_id || null, unit_price: l.unit_price,
          vat_code_id: l.vat_code_id || null, expense_account_id: l.expense_account_id || null,
        })),
      })
      if (result.error) throw new Error(result.error.message)
      setMode('list'); loadCredits()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const post = async (vc: VC) => {
    const { error: e } = await supabase.rpc('fn_post_vendor_credit', { p_vc_id: vc.id })
    if (e) { alert(e.message); return }
    loadCredits()
  }

  const STATUS_COLORS: Record<string, string> = { draft: 'draft', open: 'approved', applied: 'posted', cancelled: 'error' }
  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50'

  if (mode !== 'list') return (
    <div className="space-y-4" ref={listRef}>
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-semibold text-gray-900">{editVC?.id ? (readOnly ? 'Vendor Credit' : 'Edit Vendor Credit') : 'New Vendor Credit'}</h2>
          {editVC?.vc_number && <p className="text-xs text-gray-500 mt-0.5">{editVC.vc_number} · <StatusBadge status={STATUS_COLORS[editVC.status as string] || 'draft'} label={editVC.status as string} /></p>}
        </div>
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-700">← Back</button>
      </div>
      {error && <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">{error}</div>}
      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
        <div className="grid grid-cols-3 gap-3">
          <div><label className="block text-xs font-medium text-gray-700 mb-1">Credit Date *</label><input type="date" value={editVC?.credit_date || ''} disabled={readOnly} onChange={e => setEditVC(p => ({ ...p, credit_date: e.target.value }))} className={inp} /></div>
          <div className="col-span-2"><label className="block text-xs font-medium text-gray-700 mb-1">Supplier *</label><select value={editVC?.supplier_id || ''} disabled={readOnly} onChange={e => selectSupplier(e.target.value)} className={inp + ' w-full'}><option value="">— Select supplier —</option>{suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}</select></div>
          <div><label className="block text-xs font-medium text-gray-700 mb-1">Supplier CM No.</label><input type="text" value={editVC?.supplier_cm_no || ''} disabled={readOnly} onChange={e => setEditVC(p => ({ ...p, supplier_cm_no: e.target.value }))} className={inp + ' w-full'} /></div>
          <div><label className="block text-xs font-medium text-gray-700 mb-1">Reference Bill</label><select value={editVC?.reference_bill_id || ''} disabled={readOnly} onChange={e => setEditVC(p => ({ ...p, reference_bill_id: e.target.value }))} className={inp + ' w-full'}><option value="">— Optional —</option>{vendorBills.map(b => <option key={b.id} value={b.id}>{b.bill_number}</option>)}</select></div>
          <div><label className="block text-xs font-medium text-gray-700 mb-1">Remarks</label><input type="text" value={editVC?.remarks || ''} disabled={readOnly} onChange={e => setEditVC(p => ({ ...p, remarks: e.target.value }))} className={inp + ' w-full'} /></div>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Line Items</h3>
          {!readOnly && <button onClick={() => setLines(l => [...l, newLine()])} className="text-xs text-blue-600 hover:text-blue-800 font-medium">+ Add Line</button>}
        </div>
        <table className="w-full text-xs">
          <thead><tr className="border-b border-gray-200 text-gray-500">{['Description','Qty','Unit Price','VAT','Expense Acct','Net','VAT Amt','Total',!readOnly ? '' : undefined].filter(Boolean).map(h => <th key={h as string} className={`pb-2 font-medium ${h === 'Net' || h === 'VAT Amt' || h === 'Total' ? 'text-right' : 'text-left'} pr-2`}>{h}</th>)}</tr></thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={l._key} className="border-b border-gray-100">
                <td className="py-1.5 pr-1"><input value={l.description} disabled={readOnly} onChange={e => updateLine(i, { description: e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-40 focus:outline-none focus:ring-1 focus:ring-gray-900" /></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.quantity} disabled={readOnly} onChange={e => updateLine(i, { quantity: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-16 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.unit_price} disabled={readOnly} onChange={e => updateLine(i, { unit_price: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-24 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 pr-1"><select value={l.vat_code_id} disabled={readOnly} onChange={e => { const v = vatCodes.find(x => x.id === e.target.value); updateLine(i, { vat_code_id: e.target.value, vat_classification: v?.vat_classification || 'regular', vat_rate: v?.rate || 12 }) }} className="border border-gray-300 rounded px-1 py-1 text-xs w-28 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{vatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code}</option>)}</select></td>
                <td className="py-1.5 pr-1"><select value={l.expense_account_id} disabled={readOnly} onChange={e => updateLine(i, { expense_account_id: e.target.value })} className="border border-gray-300 rounded px-1 py-1 text-xs w-32 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{expenseAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code}</option>)}</select></td>
                <td className="py-1.5 pr-1 text-right font-mono">{fmt(l.net_amount)}</td>
                <td className="py-1.5 pr-1 text-right font-mono text-blue-600">{fmt(l.input_vat_amount)}</td>
                <td className="py-1.5 text-right font-mono font-medium">{fmt(l.total_amount)}</td>
                {!readOnly && <td className="py-1.5 pl-1"><button onClick={() => setLines(p => p.filter((_, j) => j !== i))} className="text-gray-300 hover:text-red-500 text-sm">×</button></td>}
              </tr>
            ))}
          </tbody>
          <tfoot><tr className="border-t-2 border-gray-300 font-semibold text-xs"><td colSpan={5} className="pt-2 text-right pr-2 text-gray-600">Totals</td><td className="pt-2 text-right font-mono">{fmt(totals.total - totals.vat)}</td><td className="pt-2 text-right font-mono text-blue-600">{fmt(totals.vat)}</td><td className="pt-2 text-right font-mono text-sm">{fmt(totals.total)}</td></tr></tfoot>
        </table>
      </div>
      {!readOnly && (
        <div className="flex justify-end gap-2">
          <button onClick={() => setMode('list')} className="px-4 py-2 text-sm border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
          <button onClick={save} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">{saving ? 'Saving…' : 'Save'}</button>
        </div>
      )}
    </div>
  )

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Vendor Credits</h2>
        <button onClick={() => { setEditVC({ credit_date: today() }); setLines([newLine()]); setError(''); setMode('edit') }} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New Vendor Credit</button>
      </div>
      <div className="flex gap-2">
        <input placeholder="Search…" value={fSearch} onChange={e => setFSearch(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-60" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option><option value="draft">Draft</option><option value="open">Open</option><option value="applied">Applied</option><option value="cancelled">Cancelled</option>
        </select>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : credits.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No vendor credits found.</div> : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200"><tr>{['Date','VC Number','Supplier','Supplier CM No.','Total','Balance','Status',''].map(h => <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>)}</tr></thead>
            <tbody className="divide-y divide-gray-100">
              {credits.map(vc => (
                <tr key={vc.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={vc.credit_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{vc.vc_number}</td>
                  <td className="px-3 py-2 text-gray-700">{vc.supplier_name_snapshot}</td>
                  <td className="px-3 py-2 text-gray-500">{vc.supplier_cm_no || '—'}</td>
                  <td className="px-3 py-2 text-right"><AmountCell amount={vc.total_amount} /></td>
                  <td className="px-3 py-2 text-right"><AmountCell amount={vc.remaining_balance} /></td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[vc.status]} label={vc.status} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => { setEditVC({ ...vc }); supabase.from('vendor_credit_lines').select('*').eq('vc_id', vc.id).order('line_number').then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id, vat_classification: 'regular', vat_rate: 12 })) as VCLine[] || [])); setMode('view') }} className="text-blue-600 hover:text-blue-800">View</button>
                      {vc.status === 'draft' && <><button onClick={() => { setEditVC({ ...vc }); supabase.from('vendor_credit_lines').select('*').eq('vc_id', vc.id).order('line_number').then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id, vat_classification: 'regular', vat_rate: 12 })) as VCLine[] || [])); setError(''); setMode('edit') }} className="text-gray-600 hover:text-gray-800">Edit</button><button onClick={() => post(vc)} className="text-green-600 hover:text-green-800">Post</button></>}
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
