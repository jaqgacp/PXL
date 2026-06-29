import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

type CPStatus = 'draft' | 'posted' | 'cancelled'

type CP = {
  id: string; company_id: string; cp_number: string; transaction_date: string
  supplier_id: string | null; supplier_name_snapshot: string | null
  payment_method: string; reference_number: string | null; remarks: string | null
  total_taxable_amount: number; total_input_vat_amount: number; total_amount: number
  status: CPStatus; created_at: string
}

type CPLine = {
  _key: string; id?: string
  item_id: string; description: string; quantity: number; uom_id: string
  unit_price: number; net_amount: number; vat_code_id: string
  vat_classification: 'regular' | 'zero_rated' | 'exempt'; vat_rate: number
  input_vat_amount: number; total_amount: number; expense_account_id: string
}

type SupplierRef = { id: string; registered_name: string; tin: string }
type ItemRef = { id: string; item_code: string; description: string; uom_id: string; uom_label: string; standard_cost: number; default_purchase_vat_id: string | null; purchase_account_id: string | null }
type VATRef = { id: string; vat_code: string; description: string; vat_classification: 'regular' | 'zero_rated' | 'exempt'; rate: number }
type COARef = { id: string; account_code: string; account_name: string }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

const newLine = (): CPLine => ({
  _key: crypto.randomUUID(), item_id: '', description: '', quantity: 1, uom_id: '',
  unit_price: 0, net_amount: 0, vat_code_id: '', vat_classification: 'regular', vat_rate: 12,
  input_vat_amount: 0, total_amount: 0, expense_account_id: '',
})

const computeLine = (l: CPLine): CPLine => {
  const net = Math.max(Math.round(l.quantity * l.unit_price * 100) / 100, 0)
  const vat = l.vat_classification === 'regular' ? Math.round(net * l.vat_rate / 100 * 100) / 100 : 0
  return { ...l, net_amount: net, input_vat_amount: vat, total_amount: net + vat }
}

export default function CashPurchasesPage() {
  const { companyId, branchId } = useAppCtx()
  const [records, setRecords] = useState<CP[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [editCP, setEditCP] = useState<Partial<CP> | null>(null)
  const [lines, setLines] = useState<CPLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [items, setItems] = useState<ItemRef[]>([])
  const [vatCodes, setVatCodes] = useState<VATRef[]>([])
  const [cashAccounts, setCashAccounts] = useState<COARef[]>([])
  const [expenseAccounts, setExpenseAccounts] = useState<COARef[]>([])
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')
  const listRef = useRef<HTMLDivElement>(null)
  const readOnly = mode === 'view'

  const loadRecords = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('cash_purchases').select('*').eq('company_id', companyId).order('transaction_date', { ascending: false }).order('cp_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`cp_number.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%`)
    const { data } = await q
    setRecords(data as CP[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadRecords() }, [loadRecords, companyId])

  useEffect(() => {
    if (!companyId) return
    supabase.from('suppliers').select('id,registered_name,tin').eq('company_id', companyId).eq('is_active', true).order('registered_name').then(({ data }) => setSuppliers(data as SupplierRef[] || []))
    supabase.from('items').select('id,item_code,description,uom_id,uom:units_of_measure(uom_name),standard_cost,default_purchase_vat_id,purchase_account_id').eq('company_id', companyId).eq('is_active', true).order('description').then(({ data }) => setItems((data || []).map((i: any) => ({ ...i, uom_label: i.uom?.uom_name || '' }))))
    supabase.from('vat_codes').select('id,vat_code,description,vat_classification,tax_codes(rate)').eq('transaction_type', 'input_vat').eq('is_active', true).then(({ data }) => setVatCodes((data || []).map((v: any) => ({ id: v.id, vat_code: v.vat_code, description: v.description, vat_classification: v.vat_classification, rate: v.tax_codes?.rate || 0 }))))
    supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).in('account_type', ['asset']).eq('is_active', true).ilike('account_name', '%cash%').order('account_code').then(({ data }) => setCashAccounts(data as COARef[] || []))
    supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).in('account_type', ['expense','cost_of_goods']).eq('is_active', true).order('account_code').then(({ data }) => setExpenseAccounts(data as COARef[] || []))
  }, [companyId])

  const openNew = () => {
    setEditCP({ transaction_date: today(), payment_method: 'cash' })
    setLines([newLine()])
    setError('')
    setMode('edit')
  }

  const openEdit = (cp: CP) => {
    setEditCP({ ...cp })
    supabase.from('cash_purchase_lines').select('*').eq('cp_id', cp.id).order('line_number').then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id, vat_classification: 'regular', vat_rate: 12 })) as CPLine[] || [newLine()]))
    setError('')
    setMode('edit')
  }

  const openView = (cp: CP) => {
    setEditCP({ ...cp })
    supabase.from('cash_purchase_lines').select('*').eq('cp_id', cp.id).order('line_number').then(({ data }) => setLines(data?.map(l => ({ ...l, _key: l.id, vat_classification: 'regular', vat_rate: 12 })) as CPLine[] || []))
    setMode('view')
  }

  const selectItem = (idx: number, id: string) => {
    const item = items.find(x => x.id === id)
    if (!item) return
    const vatRef = vatCodes.find(v => v.id === item.default_purchase_vat_id)
    updateLine(idx, {
      item_id: item.id, description: item.description, uom_id: item.uom_id,
      unit_price: item.standard_cost,
      vat_code_id: item.default_purchase_vat_id || '',
      vat_classification: vatRef?.vat_classification || 'regular',
      vat_rate: vatRef?.rate || 12,
      expense_account_id: item.purchase_account_id || '',
    })
  }

  const selectVAT = (idx: number, id: string) => {
    const v = vatCodes.find(x => x.id === id)
    if (!v) return
    updateLine(idx, { vat_code_id: v.id, vat_classification: v.vat_classification, vat_rate: v.rate })
  }

  const updateLine = (idx: number, patch: Partial<CPLine>) => {
    setLines(prev => prev.map((l, i) => i !== idx ? l : computeLine({ ...l, ...patch })))
  }

  const totals = lines.reduce((acc, l) => ({
    taxable: acc.taxable + (l.vat_classification === 'regular' ? l.net_amount : 0),
    vat: acc.vat + l.input_vat_amount,
    total: acc.total + l.total_amount,
  }), { taxable: 0, vat: 0, total: 0 })

  const save = async () => {
    if (!companyId) return
    setSaving(true); setError('')
    try {
      const result = await supabase.rpc('fn_save_cash_purchase', {
        p_cp_id: editCP?.id || null,
        p_header: {
          company_id: companyId, branch_id: branchId || null,
          transaction_date: editCP?.transaction_date, payment_method: editCP?.payment_method || 'cash',
          supplier_id: editCP?.supplier_id || null,
          supplier_name_snapshot: editCP?.supplier_name_snapshot || '',
          supplier_tin_snapshot: '',
          payment_account_id: (editCP as any)?.payment_account_id || null,
          reference_number: editCP?.reference_number || '',
          remarks: editCP?.remarks || '',
        },
        p_lines: lines.filter(l => l.description.trim()).map(l => ({
          item_id: l.item_id || null, description: l.description, quantity: l.quantity,
          uom_id: l.uom_id || null, unit_price: l.unit_price,
          vat_code_id: l.vat_code_id || null,
          expense_account_id: l.expense_account_id || null,
        })),
      })
      if (result.error) throw new Error(result.error.message)
      setMode('list'); loadRecords()
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const post = async (cp: CP) => {
    const { error: e } = await supabase.rpc('fn_post_cash_purchase', { p_cp_id: cp.id })
    if (e) { alert(e.message); return }
    loadRecords()
  }

  const STATUS_COLORS: Record<string, string> = { draft: 'draft', posted: 'posted', cancelled: 'error' }
  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white disabled:bg-gray-50'

  if (mode !== 'list') return (
    <div className="space-y-4" ref={listRef}>
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-semibold text-gray-900">{editCP?.id ? (readOnly ? 'Cash Purchase' : 'Edit Cash Purchase') : 'New Cash Purchase'}</h2>
          {editCP?.cp_number && <p className="text-xs text-gray-500 mt-0.5">{editCP.cp_number} · <StatusBadge status={STATUS_COLORS[editCP.status as string] || 'draft'} label={editCP.status as string} /></p>}
        </div>
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-700">← Back</button>
      </div>

      {error && <div className="bg-red-50 border border-red-200 rounded p-3 text-sm text-red-700">{error}</div>}

      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
        <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Header</h3>
        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Date *</label>
            <input type="date" value={editCP?.transaction_date || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, transaction_date: e.target.value }))} className={inp} />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Payment Method</label>
            <select value={editCP?.payment_method || 'cash'} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, payment_method: e.target.value }))} className={inp + ' w-full'}>
              <option value="cash">Cash</option>
              <option value="check">Check</option>
              <option value="transfer">Bank Transfer</option>
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Payment Account</label>
            <select value={(editCP as any)?.payment_account_id || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, payment_account_id: e.target.value } as any))} className={inp + ' w-full'}>
              <option value="">— Select account —</option>
              {cashAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Payee / Supplier</label>
            <select value={editCP?.supplier_id || ''} disabled={readOnly} onChange={e => { const s = suppliers.find(x => x.id === e.target.value); setEditCP(p => ({ ...p, supplier_id: e.target.value, supplier_name_snapshot: s?.registered_name || '' })) }} className={inp + ' w-full'}>
              <option value="">— Optional —</option>
              {suppliers.map(s => <option key={s.id} value={s.id}>{s.registered_name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Reference No.</label>
            <input type="text" value={editCP?.reference_number || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, reference_number: e.target.value }))} className={inp + ' w-full'} placeholder="OR/Check/Transfer #" />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Remarks</label>
            <input type="text" value={editCP?.remarks || ''} disabled={readOnly} onChange={e => setEditCP(p => ({ ...p, remarks: e.target.value }))} className={inp + ' w-full'} />
          </div>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Line Items</h3>
          {!readOnly && <button onClick={() => setLines(l => [...l, newLine()])} className="text-xs text-blue-600 hover:text-blue-800 font-medium">+ Add Line</button>}
        </div>
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-gray-200 text-gray-500">
              <th className="text-left pb-2 font-medium w-36">Item</th>
              <th className="text-left pb-2 font-medium">Description</th>
              <th className="text-right pb-2 font-medium w-20">Qty</th>
              <th className="text-right pb-2 font-medium w-28">Unit Price</th>
              <th className="text-left pb-2 font-medium w-32">VAT</th>
              <th className="text-left pb-2 font-medium w-36">Expense Account</th>
              <th className="text-right pb-2 font-medium w-24">Net</th>
              <th className="text-right pb-2 font-medium w-24">VAT Amt</th>
              <th className="text-right pb-2 font-medium w-24">Total</th>
              {!readOnly && <th className="w-8" />}
            </tr>
          </thead>
          <tbody>
            {lines.map((l, i) => (
              <tr key={l._key} className="border-b border-gray-100">
                <td className="py-1.5 pr-1"><select value={l.item_id} disabled={readOnly} onChange={e => selectItem(i, e.target.value)} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-36 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{items.map(it => <option key={it.id} value={it.id}>{it.item_code}</option>)}</select></td>
                <td className="py-1.5 pr-1"><input value={l.description} disabled={readOnly} onChange={e => updateLine(i, { description: e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-full focus:outline-none focus:ring-1 focus:ring-gray-900" /></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.quantity} disabled={readOnly} onChange={e => updateLine(i, { quantity: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-20 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 pr-1"><input type="number" value={l.unit_price} disabled={readOnly} onChange={e => updateLine(i, { unit_price: +e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-28 text-right focus:outline-none focus:ring-1 focus:ring-gray-900" min={0} step="any" /></td>
                <td className="py-1.5 pr-1"><select value={l.vat_code_id} disabled={readOnly} onChange={e => selectVAT(i, e.target.value)} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-32 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{vatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code}</option>)}</select></td>
                <td className="py-1.5 pr-1"><select value={l.expense_account_id} disabled={readOnly} onChange={e => updateLine(i, { expense_account_id: e.target.value })} className="border border-gray-300 rounded px-1.5 py-1 text-xs w-36 focus:outline-none focus:ring-1 focus:ring-gray-900"><option value="">—</option>{expenseAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code}</option>)}</select></td>
                <td className="py-1.5 pr-1 text-right font-mono">{fmt(l.net_amount)}</td>
                <td className="py-1.5 pr-1 text-right font-mono text-blue-600">{fmt(l.input_vat_amount)}</td>
                <td className="py-1.5 font-mono font-medium">{fmt(l.total_amount)}</td>
                {!readOnly && <td className="py-1.5 pl-1"><button onClick={() => setLines(p => p.filter((_, j) => j !== i))} className="text-gray-300 hover:text-red-500 text-sm">×</button></td>}
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t-2 border-gray-300 font-semibold text-xs">
              <td colSpan={6} className="pt-2 text-right text-gray-600 pr-2">Totals</td>
              <td className="pt-2 text-right font-mono">{fmt(totals.taxable)}</td>
              <td className="pt-2 text-right font-mono text-blue-600">{fmt(totals.vat)}</td>
              <td className="pt-2 text-right font-mono text-sm">{fmt(totals.total)}</td>
            </tr>
          </tfoot>
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
        <h2 className="text-base font-semibold text-gray-900">Cash Purchases</h2>
        <button onClick={openNew} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700">+ New Cash Purchase</button>
      </div>
      <div className="flex gap-2">
        <input placeholder="Search…" value={fSearch} onChange={e => setFSearch(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-60" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All Statuses</option><option value="draft">Draft</option><option value="posted">Posted</option><option value="cancelled">Cancelled</option>
        </select>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : records.length === 0 ? <div className="p-8 text-center text-sm text-gray-400">No cash purchases found.</div> : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['Date','CP Number','Payee','Method','Total Amount','Status',''].map(h => <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {records.map(cp => (
                <tr key={cp.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={cp.transaction_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{cp.cp_number}</td>
                  <td className="px-3 py-2 text-gray-700">{cp.supplier_name_snapshot || '—'}</td>
                  <td className="px-3 py-2 capitalize text-gray-500">{cp.payment_method}</td>
                  <td className="px-3 py-2 text-right"><AmountCell amount={cp.total_amount} /></td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[cp.status]} label={cp.status} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2 justify-end">
                      <button onClick={() => openView(cp)} className="text-blue-600 hover:text-blue-800">View</button>
                      {cp.status === 'draft' && <><button onClick={() => openEdit(cp)} className="text-gray-600 hover:text-gray-800">Edit</button><button onClick={() => post(cp)} className="text-green-600 hover:text-green-800">Post</button></>}
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
