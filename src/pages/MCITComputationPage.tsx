import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Status = 'draft' | 'final' | 'filed'

type Row = {
  id: string
  period_year: number
  gross_income: number
  mcit_rate: number
  mcit_due: number
  rcit_due: number
  tax_due_higher: number
  excess_mcit_carryforward: number
  status: Status
}

type FormData = Omit<Row, 'id'>

const now = new Date()
const EMPTY_FORM: FormData = { period_year: now.getFullYear(), gross_income: 0, mcit_rate: 2, mcit_due: 0, rcit_due: 0, tax_due_higher: 0, excess_mcit_carryforward: 0, status: 'draft' }
const STATUS_LABELS: Record<Status, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700 font-mono tabular-nums'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

function StatusBadge({ status }: { status: Status }) {
  const cls: Record<Status, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
}

export default function MCITComputationPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState<FormData>({ ...EMPTY_FORM })
  const [saving, setSaving] = useState(false)

  const load = async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('mcit_computations').select('*').eq('company_id', companyId).order('period_year', { ascending: false })
    setRows((data as Row[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => {
    const next = { ...f, [k]: v }
    if (k === 'gross_income' || k === 'mcit_rate' || k === 'rcit_due') {
      next.mcit_due = next.gross_income * (next.mcit_rate / 100)
      next.tax_due_higher = Math.max(next.mcit_due, next.rcit_due)
      next.excess_mcit_carryforward = next.mcit_due > next.rcit_due ? next.mcit_due - next.rcit_due : 0
    }
    return next
  })

  const openNew = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new') }
  const openEdit = (r: Row) => { setForm({ ...r }); setEditId(r.id); setMode('edit') }
  const openView = (r: Row) => { openEdit(r); setMode('view') }

  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    setSaving(true)
    const payload = { company_id: companyId, ...form }
    if (!editId) {
      const { error } = await supabase.from('mcit_computations').insert([payload])
      if (error) { alert('Cannot save.\nReason: ' + (error.code === '23505' ? `An MCIT computation for ${form.period_year} already exists.` : error.message)); setSaving(false); return }
    } else {
      const { error } = await supabase.from('mcit_computations').update(payload).eq('id', editId)
      if (error) { alert('Cannot update.\nReason: ' + error.message); setSaving(false); return }
    }
    setSaving(false); load(); setMode('list')
  }

  const isView = mode === 'view'
  const years = Array.from({ length: 6 }, (_, i) => now.getFullYear() - 4 + i)

  if (mode === 'new' || mode === 'edit' || mode === 'view') {
    return (
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← MCIT Computation</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? 'MCIT Computation' : editId ? 'Edit Computation' : 'New Computation'}</h1>
            <p className="text-sm text-gray-500 mt-0.5">FY {form.period_year} — Minimum Corporate Income Tax (2% of Gross Income)</p>
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
          <h2 className={hd}>Period</h2>
          <div><label className={lbl}>Year</label>{isView ? <div className={ro}>{form.period_year}</div> : <select value={form.period_year} onChange={e => set('period_year', Number(e.target.value))} className={inp}>{years.map(y => <option key={y} value={y}>{y}</option>)}</select>}</div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Computation</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Gross Income</label>{isView ? <div className={ro}>{fmtNum(form.gross_income)}</div> : <input type="number" step="0.01" value={form.gross_income} onChange={e => set('gross_income', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>MCIT Rate (%)</label>{isView ? <div className={ro}>{form.mcit_rate}%</div> : <input type="number" step="0.01" value={form.mcit_rate} onChange={e => set('mcit_rate', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>MCIT Due (2% of Gross Income)</label><div className={ro}>{fmtNum(form.mcit_due)}</div></div>
            <div><label className={lbl}>RCIT Due (Regular Rate)</label>{isView ? <div className={ro}>{fmtNum(form.rcit_due)}</div> : <input type="number" step="0.01" value={form.rcit_due} onChange={e => set('rcit_due', Number(e.target.value))} className={inp} />}</div>
            <div className="col-span-2 pt-2 border-t border-gray-100 grid grid-cols-2 gap-4">
              <div><label className={lbl}>Tax Due (Higher of MCIT/RCIT)</label><div className="text-xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.tax_due_higher)}</div></div>
              <div><label className={lbl}>Excess MCIT Carry-Forward</label><div className="text-xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.excess_mcit_carryforward)}</div></div>
            </div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Status</h2>
          {isView ? <StatusBadge status={form.status} /> : (
            <select value={form.status} onChange={e => set('status', e.target.value)} className={inp}><option value="draft">Draft</option><option value="final">Final</option><option value="filed">Filed</option></select>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">MCIT Computation</h1><p className="text-sm text-gray-500 mt-0.5">Minimum Corporate Income Tax — 2% of Gross Income vs. RCIT</p></div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New Computation</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(4)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Year</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">MCIT Due</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">RCIT Due</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Due (Higher)</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400"><p className="text-base font-medium text-gray-500">No MCIT Computations Found</p><p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New Computation" to begin.'}</p></td></tr>
              ) : rows.map((r, i) => (
                <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{r.period_year}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.mcit_due)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.rcit_due)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(r.tax_due_higher)}</td>
                  <td className="px-4 py-3"><StatusBadge status={r.status} /></td>
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
