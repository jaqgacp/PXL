import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  id: string
  year_incurred: number
  nolco_amount: number
  applied_year1: number
  applied_year2: number
  applied_year3: number
  expiry_year: number
  remarks: string | null
}

type FormData = Omit<Row, 'id' | 'remarks'> & { remarks: string }

const now = new Date()
const EMPTY_FORM: FormData = { year_incurred: now.getFullYear(), nolco_amount: 0, applied_year1: 0, applied_year2: 0, applied_year3: 0, expiry_year: now.getFullYear() + 3, remarks: '' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700 font-mono tabular-nums'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const remaining = (r: Row | FormData) => r.nolco_amount - r.applied_year1 - r.applied_year2 - r.applied_year3

export default function NOLCOSchedulePage() {
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
    const { data } = await supabase.from('nolco_schedule').select('*').eq('company_id', companyId).order('year_incurred', { ascending: false })
    setRows((data as Row[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => {
    const next = { ...f, [k]: v }
    if (k === 'year_incurred') next.expiry_year = Number(v) + 3
    return next
  })

  const openNew = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new') }
  const openEdit = (r: Row) => { setForm({ ...r, remarks: r.remarks || '' }); setEditId(r.id); setMode('edit') }
  const openView = (r: Row) => { openEdit(r); setMode('view') }

  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    setSaving(true)
    const payload = { company_id: companyId, ...form, remarks: form.remarks || null }
    if (!editId) {
      const { error } = await supabase.from('nolco_schedule').insert([payload])
      if (error) { alert('Cannot save.\nReason: ' + (error.code === '23505' ? `NOLCO for year ${form.year_incurred} already exists.` : error.message)); setSaving(false); return }
    } else {
      const { error } = await supabase.from('nolco_schedule').update(payload).eq('id', editId)
      if (error) { alert('Cannot update.\nReason: ' + error.message); setSaving(false); return }
    }
    setSaving(false); load(); setMode('list')
  }

  const isView = mode === 'view'
  const years = Array.from({ length: 8 }, (_, i) => now.getFullYear() - 6 + i)
  const totalRemaining = rows.reduce((s, r) => s + remaining(r), 0)

  if (mode === 'new' || mode === 'edit' || mode === 'view') {
    return (
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← NOLCO Schedule</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? 'NOLCO Entry' : editId ? 'Edit NOLCO Entry' : 'New NOLCO Entry'}</h1>
            <p className="text-sm text-gray-500 mt-0.5">Year Incurred {form.year_incurred} — Expires {form.expiry_year}</p>
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
          <h2 className={hd}>NOLCO Details</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Year Incurred</label>{isView ? <div className={ro}>{form.year_incurred}</div> : <select value={form.year_incurred} onChange={e => set('year_incurred', Number(e.target.value))} className={inp}>{years.map(y => <option key={y} value={y}>{y}</option>)}</select>}</div>
            <div><label className={lbl}>Expiry Year (3 years)</label><div className={ro}>{form.expiry_year}</div></div>
            <div><label className={lbl}>NOLCO Amount</label>{isView ? <div className={ro}>{fmtNum(form.nolco_amount)}</div> : <input type="number" step="0.01" value={form.nolco_amount} onChange={e => set('nolco_amount', Number(e.target.value))} className={inp} />}</div>
            <div />
            <div><label className={lbl}>Applied — Year 1</label>{isView ? <div className={ro}>{fmtNum(form.applied_year1)}</div> : <input type="number" step="0.01" value={form.applied_year1} onChange={e => set('applied_year1', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Applied — Year 2</label>{isView ? <div className={ro}>{fmtNum(form.applied_year2)}</div> : <input type="number" step="0.01" value={form.applied_year2} onChange={e => set('applied_year2', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Applied — Year 3</label>{isView ? <div className={ro}>{fmtNum(form.applied_year3)}</div> : <input type="number" step="0.01" value={form.applied_year3} onChange={e => set('applied_year3', Number(e.target.value))} className={inp} />}</div>
            <div className="col-span-2 pt-2 border-t border-gray-100"><label className={lbl}>Remaining Balance</label><div className="text-2xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(remaining(form))}</div></div>
            <div className="col-span-2"><label className={lbl}>Remarks</label>{isView ? <textarea readOnly value={form.remarks || '—'} rows={2} className={ro.replace(' font-mono tabular-nums', '')} /> : <textarea value={form.remarks} onChange={e => set('remarks', e.target.value)} rows={2} className={inp} />}</div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">NOLCO Schedule</h1><p className="text-sm text-gray-500 mt-0.5">Net Operating Loss Carry-Over — 3-year application window</p></div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New NOLCO Entry</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <p className="text-xs text-gray-500 uppercase tracking-wide">Total Unapplied NOLCO</p>
        <p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(totalRemaining)}</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(4)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Year Incurred</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">NOLCO Amount</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Applied</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Remaining</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Expiry</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400"><p className="text-base font-medium text-gray-500">No NOLCO Entries Found</p><p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New NOLCO Entry" to begin.'}</p></td></tr>
              ) : rows.map((r, i) => {
                const rem = remaining(r)
                const isExpired = r.expiry_year < now.getFullYear()
                return (
                  <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                    <td className="px-4 py-3 font-medium text-gray-900">{r.year_incurred}</td>
                    <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.nolco_amount)}</td>
                    <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.applied_year1 + r.applied_year2 + r.applied_year3)}</td>
                    <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(rem)}</td>
                    <td className="px-4 py-3">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${isExpired ? 'bg-red-50 text-red-700' : 'bg-gray-100 text-gray-600'}`}>{r.expiry_year}{isExpired ? ' — Expired' : ''}</span>
                    </td>
                    <td className="px-4 py-3"><div className="flex items-center gap-2"><button onClick={() => openView(r)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button><button onClick={() => openEdit(r)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button></div></td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
