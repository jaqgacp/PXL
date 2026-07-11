import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'

type Warehouse = { id: string; warehouse_code: string; warehouse_name: string }
type Department = { id: string; department_name: string }
type Item = { id: string; item_code: string; description: string; costing_method: string; uom_code: string }
type COA = { id: string; account_code: string; account_name: string }
type IssueLine = { item_id: string; item_code: string; item_name: string; uom_code: string; costing_method: string; qty: string; lot_number: string; serial_number: string; gl_expense_account_id: string }
type IssueRecord = { id: string; issue_number: string; issue_date: string; warehouse_name: string; department_name: string | null; purpose: string | null; status: string }

export default function GoodsIssuePage() {
  const { companyId, branchId } = useAppCtx()
  const today = new Date().toISOString().slice(0, 10)
  const [tab, setTab] = useState<'new' | 'history'>('new')
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [departments, setDepartments] = useState<Department[]>([])
  const [items, setItems] = useState<Item[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [history, setHistory] = useState<IssueRecord[]>([])
  const [warehouseId, setWarehouseId] = useState('')
  const [deptId, setDeptId] = useState('')
  const [issueDate, setIssueDate] = useState(today)
  const [purpose, setPurpose] = useState('')
  const [notes, setNotes] = useState('')
  const [lines, setLines] = useState<IssueLine[]>([])
  const [saving, setSaving] = useState(false)
  const [posting, setPosting] = useState(false)
  const [pendingId, setPendingId] = useState<string | null>(null)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: whs }, { data: depts }, { data: itemData }, { data: coaData }, { data: issData }] = await Promise.all([
      supabase.from('warehouses').select('id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('departments').select('id,department_name').eq('company_id', companyId).order('department_name'),
      supabase.from('items').select('id,item_code,description,costing_method,units_of_measure!inner(uom_code)').eq('company_id', companyId).eq('is_active', true).eq('item_type', 'inventory_item').order('item_code'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_postable', true).order('account_code'),
      supabase.from('goods_issues').select(`id,issue_number,issue_date,purpose,status,notes,warehouses!inner(warehouse_name),departments(department_name)`).eq('company_id', companyId).order('issue_date', { ascending: false }).limit(50),
    ])
    setWarehouses((whs as Warehouse[]) || [])
    setDepartments((depts as Department[]) || [])
    setItems(((itemData || []) as any[]).map(i => ({ id: i.id, item_code: i.item_code, description: i.description, costing_method: i.costing_method || 'weighted_average', uom_code: i.units_of_measure?.uom_code || '' })))
    setCoa((coaData as COA[]) || [])
    setHistory(((issData || []) as any[]).map(g => ({ id: g.id, issue_number: g.issue_number, issue_date: g.issue_date, status: g.status, purpose: g.purpose, warehouse_name: g.warehouses?.warehouse_name ?? '', department_name: g.departments?.department_name ?? null })))
  }, [companyId])

  useEffect(() => { load() }, [load])

  const addLine = (itemId: string) => {
    const item = items.find(i => i.id === itemId)
    if (!item || lines.find(l => l.item_id === itemId)) return
    setLines(p => [...p, { item_id: itemId, item_code: item.item_code, item_name: item.description, uom_code: item.uom_code, costing_method: item.costing_method, qty: '', lot_number: '', serial_number: '', gl_expense_account_id: '' }])
  }

  const saveDraft = async () => {
    if (!companyId || !warehouseId) { setError('Select a warehouse'); return }
    if (lines.length === 0 || lines.some(l => !l.qty || Number(l.qty) <= 0)) { setError('Add items with positive quantities'); return }
    setSaving(true); setError(''); setSuccess('')

    const { data: giData, error: e1 } = await supabase.from('goods_issues').insert({
      company_id: companyId, branch_id: branchId || null, warehouse_id: warehouseId,
      issue_number: 'PENDING', issue_date: issueDate,
      department_id: deptId || null, purpose: purpose || null, notes: notes || null, status: 'draft',
    }).select().single()
    if (e1 || !giData) { setSaving(false); setError(e1?.message || 'Failed'); return }

    const { error: e2 } = await supabase.from('goods_issue_lines').insert(
      lines.map(l => ({
        issue_id: (giData as any).id, company_id: companyId, item_id: l.item_id,
        qty_issued: Number(l.qty),
        lot_number: l.lot_number || null, serial_number: l.serial_number || null,
        gl_expense_account_id: l.gl_expense_account_id || null,
      }))
    )
    setSaving(false)
    if (e2) { setError(e2.message); return }
    setPendingId((giData as any).id)
    setSuccess('Draft saved. Ready to post.')
  }

  const post = async () => {
    if (!pendingId) return
    setPosting(true); setError(''); setSuccess('')
    const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'INV_GI', p_source_doc_id: pendingId })
    if (previewError) {
      setPosting(false)
      setError(`Goods Issue is not ready to post: ${previewError.message}`)
      return
    }
    const { error: e } = await supabase.rpc('fn_post_goods_issue', { p_issue_id: pendingId })
    setPosting(false)
    if (e) { setError(e.message); return }
    setSuccess('Goods issue posted. Stock deducted and GL entry created.')
    setPendingId(null); setLines([]); setPurpose(''); setNotes(''); setDeptId('')
    load()
  }

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Goods Issue</span>
        <div className="ml-auto flex gap-1">
          {(['new','history'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-3 py-1 rounded text-xs font-medium ${tab === t ? 'bg-gray-900 text-white' : 'text-gray-500 hover:text-gray-900'}`}>
              {t === 'new' ? 'New Issue' : 'History'}
            </button>
          ))}
        </div>
      </div>

      {tab === 'new' ? (
        <div className="px-5 py-4 max-w-4xl space-y-4">
          {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
          {success && <div className="text-xs text-green-700 bg-green-50 border border-green-200 rounded px-3 py-2">{success}</div>}

          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Header</p>
            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Warehouse *</label>
                <select value={warehouseId} onChange={e => setWarehouseId(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">— Select —</option>
                  {warehouses.map(w => <option key={w.id} value={w.id}>{w.warehouse_code} — {w.warehouse_name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Issue Date</label>
                <input type="date" value={issueDate} onChange={e => setIssueDate(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Department</label>
                <select value={deptId} onChange={e => setDeptId(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">— None —</option>
                  {departments.map(d => <option key={d.id} value={d.id}>{d.department_name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Purpose</label>
                <input value={purpose} onChange={e => setPurpose(e.target.value)}
                  placeholder="e.g. Production Run, Maintenance, Office Use"
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
              </div>
              <div className="col-span-2">
                <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                <input value={notes} onChange={e => setNotes(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
              </div>
            </div>
          </div>

          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-2">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Items to Issue</p>
              <select onChange={e => { addLine(e.target.value); e.target.value = '' }}
                className="ml-auto border border-gray-200 rounded px-2.5 py-1 text-xs w-64 focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">+ Add Item…</option>
                {items.map(i => <option key={i.id} value={i.id}>{i.item_code} — {i.description}</option>)}
              </select>
            </div>
            {lines.length === 0 ? (
              <div className="py-10 text-center text-xs text-gray-400">Add items to issue</div>
            ) : (
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Item','Method','Qty Issued','Lot / Serial','Expense GL Account',''].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {lines.map((l, idx) => (
                    <tr key={l.item_id}>
                      <td className="px-3 py-2">
                        <p className="font-semibold text-gray-900">{l.item_code}</p>
                        <p className="text-[10px] text-gray-400">{l.item_name}</p>
                      </td>
                      <td className="px-3 py-2 text-gray-500 text-[10px]">{l.costing_method === 'weighted_average' ? 'WAC' : l.costing_method === 'fifo' ? 'FIFO' : 'Specific ID'}</td>
                      <td className="px-3 py-2">
                        <div className="flex items-center gap-1">
                          <input type="number" min={0.0001} step={0.0001} value={l.qty}
                            onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, qty: e.target.value } : x))}
                            className="border border-gray-300 rounded px-2 py-1 text-xs font-mono text-right w-24 focus:outline-none focus:ring-1 focus:ring-gray-900" />
                          <span className="text-gray-400">{l.uom_code}</span>
                        </div>
                      </td>
                      <td className="px-3 py-2">
                        {l.costing_method !== 'weighted_average' ? (
                          <div className="flex gap-1">
                            <input value={l.lot_number}
                              onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, lot_number: e.target.value } : x))}
                              placeholder="Lot" className="border border-gray-200 rounded px-1.5 py-0.5 text-xs w-20 focus:outline-none" />
                            <input value={l.serial_number}
                              onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, serial_number: e.target.value } : x))}
                              placeholder="Serial" className="border border-gray-200 rounded px-1.5 py-0.5 text-xs w-24 focus:outline-none" />
                          </div>
                        ) : <span className="text-gray-300">—</span>}
                      </td>
                      <td className="px-3 py-2">
                        <select value={l.gl_expense_account_id}
                          onChange={e => setLines(p => p.map((x, i) => i === idx ? { ...x, gl_expense_account_id: e.target.value } : x))}
                          className="border border-gray-200 rounded px-1.5 py-1 text-[10px] w-52 focus:outline-none focus:ring-1 focus:ring-gray-900">
                          <option value="">— Use item COGS account —</option>
                          {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                        </select>
                      </td>
                      <td className="px-3 py-2">
                        <button onClick={() => setLines(p => p.filter((_, i) => i !== idx))} className="text-red-400 hover:text-red-600 text-xs">✕</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          {pendingId && (
            <GLImpactPanel companyId={companyId} sourceDocType="INV_GI" sourceDocId={pendingId} previewRows={[]} />
          )}

          <div className="flex gap-2">
            {!pendingId ? (
              <button onClick={saveDraft} disabled={saving}
                className="px-4 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
                {saving ? 'Saving…' : 'Save Draft'}
              </button>
            ) : (
              <button onClick={post} disabled={posting}
                className="px-4 py-1.5 bg-green-700 text-white rounded text-sm font-medium hover:bg-green-800 disabled:opacity-40">
                {posting ? 'Posting…' : 'Post Issue'}
              </button>
            )}
          </div>
        </div>
      ) : (
        <div className="px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Issue #','Date','Warehouse','Department','Purpose','Status'].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {history.length === 0 ? (
                  <tr><td colSpan={6} className="py-12 text-center text-gray-400">No goods issues</td></tr>
                ) : history.map(g => (
                  <tr key={g.id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{g.issue_number}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{g.issue_date}</td>
                    <td className="px-3 py-2 text-gray-800">{g.warehouse_name}</td>
                    <td className="px-3 py-2 text-gray-600">{g.department_name || '—'}</td>
                    <td className="px-3 py-2 text-gray-600 max-w-[160px] truncate">{g.purpose || '—'}</td>
                    <td className="px-3 py-2">
                      <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${g.status === 'posted' ? 'bg-green-50 text-green-700' : 'bg-yellow-50 text-yellow-700'}`}>
                        {g.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
