import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Status = 'draft' | 'final' | 'filed'

type Row = {
  id: string
  period_year: number
  period_quarter: number
  gross_income: number
  taxable_income: number
  tax_due: number
  tax_credits: number
  tax_payable: number
  status: Status
  filed_date: string | null
  reference_no: string | null
}

type FormData = Omit<Row, 'id' | 'filed_date' | 'reference_no'> & { filed_date: string; reference_no: string; remarks: string }

const FORM_TYPE = '1701Q'
const now = new Date()
const EMPTY_FORM: FormData = { period_year: now.getFullYear(), period_quarter: Math.floor(now.getMonth() / 3) + 1, gross_income: 0, taxable_income: 0, tax_due: 0, tax_credits: 0, tax_payable: 0, status: 'draft', filed_date: '', reference_no: '', remarks: '' }
const STATUS_LABELS: Record<Status, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700 font-mono tabular-nums'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const fmtQuarter = (y: number, q: number) => `Q${q} ${y}`

function StatusBadge({ status }: { status: Status }) {
  const cls: Record<Status, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
}

export default function ITR1701QPage() {
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
    const { data } = await supabase.from('itr_filings').select('*').eq('company_id', companyId).eq('form_type', FORM_TYPE)
      .order('period_year', { ascending: false }).order('period_quarter', { ascending: false })
    setRows((data as Row[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => {
    const next = { ...f, [k]: v }
    if (k === 'tax_due' || k === 'tax_credits') next.tax_payable = Math.max(next.tax_due - next.tax_credits, 0)
    return next
  })

  const openNew = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new') }
  const openEdit = (r: Row) => { setForm({ ...r, filed_date: r.filed_date || '', reference_no: r.reference_no || '', remarks: '' }); setEditId(r.id); setMode('edit') }
  const openView = (r: Row) => { openEdit(r); setMode('view') }

  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    setSaving(true)
    const payload = { company_id: companyId, form_type: FORM_TYPE, ...form, filed_date: form.filed_date || null, reference_no: form.reference_no || null, remarks: form.remarks || null }
    if (!editId) {
      const { error } = await supabase.from('itr_filings').insert([payload])
      if (error) { alert('Cannot save.\nReason: ' + (error.code === '23505' ? `A 1701Q filing for ${fmtQuarter(form.period_year, form.period_quarter)} already exists.` : error.message)); setSaving(false); return }
    } else {
      const { error } = await supabase.from('itr_filings').update(payload).eq('id', editId)
      if (error) { alert('Cannot update.\nReason: ' + error.message); setSaving(false); return }
    }
    setSaving(false); load(); setMode('list')
  }

  const isView = mode === 'view'
  const years = Array.from({ length: 6 }, (_, i) => now.getFullYear() - 4 + i)

  if (mode === 'new' || mode === 'edit' || mode === 'view') {
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← 1701Q Quarterly ITR</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? 'Quarterly ITR — 1701Q' : editId ? 'Edit Filing' : 'New Filing'}</h1>
            <p className="text-sm text-gray-500 mt-0.5">{fmtQuarter(form.period_year, form.period_quarter)}</p>
          </div>
          <div className="flex gap-2">
            {isView ? (
              <>
                <button onClick={() => setMode('edit')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Edit</button>
                <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Print</button>
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
          <div className="grid grid-cols-3 gap-4">
            <div><label className={lbl}>Year</label>{isView ? <div className={ro}>{form.period_year}</div> : <select value={form.period_year} onChange={e => set('period_year', Number(e.target.value))} className={inp}>{years.map(y => <option key={y} value={y}>{y}</option>)}</select>}</div>
            <div><label className={lbl}>Quarter</label>{isView ? <div className={ro}>Q{form.period_quarter}</div> : <select value={form.period_quarter} onChange={e => set('period_quarter', Number(e.target.value))} className={inp}>{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>}</div>
            <div><label className={lbl}>Status</label>{isView ? <div className="mt-1.5"><StatusBadge status={form.status} /></div> : <select value={form.status} onChange={e => set('status', e.target.value)} className={inp}><option value="draft">Draft</option><option value="final">Final</option><option value="filed">Filed</option></select>}</div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Return Computation</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Gross Income</label>{isView ? <div className={ro}>{fmtNum(form.gross_income)}</div> : <input type="number" step="0.01" value={form.gross_income} onChange={e => set('gross_income', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Taxable Income</label>{isView ? <div className={ro}>{fmtNum(form.taxable_income)}</div> : <input type="number" step="0.01" value={form.taxable_income} onChange={e => set('taxable_income', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Tax Due</label>{isView ? <div className={ro}>{fmtNum(form.tax_due)}</div> : <input type="number" step="0.01" value={form.tax_due} onChange={e => set('tax_due', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Less: Tax Credits</label>{isView ? <div className={ro}>{fmtNum(form.tax_credits)}</div> : <input type="number" step="0.01" value={form.tax_credits} onChange={e => set('tax_credits', Number(e.target.value))} className={inp} />}</div>
            <div className="col-span-2 pt-2 border-t border-gray-100"><label className={lbl}>Tax Payable</label><div className="text-2xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.tax_payable)}</div></div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Filing</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Filed Date</label>{isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{form.filed_date || '—'}</div> : <input type="date" value={form.filed_date} onChange={e => set('filed_date', e.target.value)} className={inp} />}</div>
            <div><label className={lbl}>Reference No.</label>{isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{form.reference_no || '—'}</div> : <input value={form.reference_no} onChange={e => set('reference_no', e.target.value)} className={inp} />}</div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">1701Q Quarterly ITR</h1><p className="text-sm text-gray-500 mt-0.5">Quarterly Income Tax Return — Individual</p></div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New Filing</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(4)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Income</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Due</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Payable</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400"><p className="text-base font-medium text-gray-500">No Filings Found</p><p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New Filing" to begin.'}</p></td></tr>
              ) : rows.map((r, i) => (
                <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtQuarter(r.period_year, r.period_quarter)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.taxable_income)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.tax_due)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(r.tax_payable)}</td>
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
