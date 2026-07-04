import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type CreditType = 'cwt_2307' | 'prior_year_excess' | 'foreign_tax_credit' | 'other'

type Row = {
  id: string
  period_year: number
  period_quarter: number | null
  credit_type: CreditType
  description: string | null
  amount: number
  applied_amount: number
  remarks: string | null
}

type FormData = Omit<Row, 'id' | 'description' | 'remarks'> & { description: string; remarks: string }

const now = new Date()
const EMPTY_FORM: FormData = { period_year: now.getFullYear(), period_quarter: Math.floor(now.getMonth() / 3) + 1, credit_type: 'cwt_2307', description: '', amount: 0, applied_amount: 0, remarks: '' }
const CREDIT_LABELS: Record<CreditType, string> = { cwt_2307: 'CWT (Form 2307)', prior_year_excess: 'Prior Year Excess Credit', foreign_tax_credit: 'Foreign Tax Credit', other: 'Other' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700 font-mono tabular-nums'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const fmtPeriod = (r: { period_year: number; period_quarter: number | null }) => r.period_quarter ? `Q${r.period_quarter} ${r.period_year}` : `FY ${r.period_year}`

export default function TaxCreditsSchedulePage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState<FormData>({ ...EMPTY_FORM })
  const [saving, setSaving] = useState(false)
  const [filterYear, setFilterYear] = useState<number | ''>('')

  const load = async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('tax_credits_schedule').select('*').eq('company_id', companyId).order('period_year', { ascending: false }).order('period_quarter', { ascending: false })
    setRows((data as Row[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => ({ ...f, [k]: v }))
  const openNew = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new') }
  const openEdit = (r: Row) => { setForm({ ...r, description: r.description || '', remarks: r.remarks || '' }); setEditId(r.id); setMode('edit') }
  const openView = (r: Row) => { openEdit(r); setMode('view') }

  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    setSaving(true)
    const payload = { company_id: companyId, ...form, description: form.description || null, remarks: form.remarks || null }
    if (!editId) {
      const { error } = await supabase.from('tax_credits_schedule').insert([payload])
      if (error) { alert('Cannot save.\nReason: ' + error.message); setSaving(false); return }
    } else {
      const { error } = await supabase.from('tax_credits_schedule').update(payload).eq('id', editId)
      if (error) { alert('Cannot update.\nReason: ' + error.message); setSaving(false); return }
    }
    setSaving(false); load(); setMode('list')
  }

  const filtered = rows.filter(r => !filterYear || r.period_year === filterYear)
  const totalAmount = filtered.reduce((s, r) => s + r.amount, 0)
  const totalApplied = filtered.reduce((s, r) => s + r.applied_amount, 0)
  const isView = mode === 'view'
  const years = Array.from({ length: 6 }, (_, i) => now.getFullYear() - 4 + i)

  if (mode === 'new' || mode === 'edit' || mode === 'view') {
    return (
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Tax Credits Schedule</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? 'Tax Credit Entry' : editId ? 'Edit Tax Credit' : 'New Tax Credit'}</h1>
            <p className="text-sm text-gray-500 mt-0.5">{fmtPeriod(form)}</p>
          </div>
          <div className="flex gap-2">
            {isView ? (
              <>
                <button onClick={() => setMode('edit')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Edit</button>
                <button onClick={() => setMode('list')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Close</button>
              </>
            ) : (
              <>
                <button onClick={() => setMode('list')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
                <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving...' : editId ? 'Update' : 'Save'}</button>
              </>
            )}
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Credit Details</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Year</label>{isView ? <div className={ro}>{form.period_year}</div> : <select value={form.period_year} onChange={e => set('period_year', Number(e.target.value))} className={inp}>{years.map(y => <option key={y} value={y}>{y}</option>)}</select>}</div>
            <div><label className={lbl}>Quarter (optional)</label>{isView ? <div className={ro}>{form.period_quarter ? `Q${form.period_quarter}` : '—'}</div> : (
              <select value={form.period_quarter ?? ''} onChange={e => set('period_quarter', e.target.value ? Number(e.target.value) : '')} className={inp}>
                <option value="">Annual</option>{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}
              </select>
            )}</div>
            <div><label className={lbl}>Credit Type</label>{isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{CREDIT_LABELS[form.credit_type]}</div> : (
              <select value={form.credit_type} onChange={e => set('credit_type', e.target.value)} className={inp}>{Object.entries(CREDIT_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>
            )}</div>
            <div><label className={lbl}>Amount</label>{isView ? <div className={ro}>{fmtNum(form.amount)}</div> : <input type="number" step="0.01" value={form.amount} onChange={e => set('amount', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Applied Amount</label>{isView ? <div className={ro}>{fmtNum(form.applied_amount)}</div> : <input type="number" step="0.01" value={form.applied_amount} onChange={e => set('applied_amount', Number(e.target.value))} className={inp} />}</div>
            <div className="col-span-2"><label className={lbl}>Description</label>{isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{form.description || '—'}</div> : <input value={form.description} onChange={e => set('description', e.target.value)} className={inp} />}</div>
            <div className="col-span-2"><label className={lbl}>Remarks</label>{isView ? <textarea readOnly value={form.remarks || '—'} rows={2} className={ro.replace(' font-mono tabular-nums', '')} /> : <textarea value={form.remarks} onChange={e => set('remarks', e.target.value)} rows={2} className={inp} />}</div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Tax Credits Schedule</h1><p className="text-sm text-gray-500 mt-0.5">CWT, prior-year excess, foreign tax credits applied against income tax due</p></div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New Credit</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={filterYear} onChange={e => setFilterYear(e.target.value ? Number(e.target.value) : '')} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">
          <option value="">All Years</option>{years.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Total Credits</p><p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(totalAmount)}</p></div>
        <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Total Applied</p><p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(totalApplied)}</p></div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(4)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Period</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Credit Type</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Description</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Amount</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Applied</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400"><p className="text-base font-medium text-gray-500">No Tax Credits Found</p><p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New Credit" to begin.'}</p></td></tr>
              ) : filtered.map((r, i) => (
                <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtPeriod(r)}</td>
                  <td className="px-4 py-3 text-gray-700">{CREDIT_LABELS[r.credit_type]}</td>
                  <td className="px-4 py-3 text-gray-600 max-w-xs truncate">{r.description || '—'}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.amount)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(r.applied_amount)}</td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2"><button onClick={() => openView(r)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button><button onClick={() => openEdit(r)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button></div></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
