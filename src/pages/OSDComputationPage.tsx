import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Status = 'draft' | 'final' | 'filed'
type PeriodType = 'quarterly' | 'annual'

type Row = {
  id: string
  period_type: PeriodType
  period_year: number
  period_quarter: number | null
  gross_income: number
  allowable_deductions: number
  taxable_income: number
  tax_rate: number
  tax_due: number
  status: Status
}

type FormData = Omit<Row, 'id'>

const OSD_RATE = 0.40
const now = new Date()
const EMPTY_FORM: FormData = { period_type: 'quarterly', period_year: now.getFullYear(), period_quarter: Math.floor(now.getMonth() / 3) + 1, gross_income: 0, allowable_deductions: 0, taxable_income: 0, tax_rate: 25, tax_due: 0, status: 'draft' }
const STATUS_LABELS: Record<Status, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700 font-mono tabular-nums'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const fmtPeriod = (r: Row | FormData) => r.period_type === 'annual' ? `FY ${r.period_year}` : `Q${r.period_quarter} ${r.period_year}`

function StatusBadge({ status }: { status: Status }) {
  const cls: Record<Status, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
}

export default function OSDComputationPage() {
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
    const { data } = await supabase.from('income_tax_computations').select('*').eq('company_id', companyId).eq('deduction_method', 'osd')
      .order('period_year', { ascending: false }).order('period_quarter', { ascending: false })
    setRows((data as Row[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => {
    const next = { ...f, [k]: v }
    if (k === 'gross_income' || k === 'tax_rate') {
      next.allowable_deductions = next.gross_income * OSD_RATE
      next.taxable_income = next.gross_income - next.allowable_deductions
      next.tax_due = next.taxable_income * (next.tax_rate / 100)
    }
    return next
  })

  const openNew = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new') }
  const openEdit = (r: Row) => { setForm({ ...r }); setEditId(r.id); setMode('edit') }
  const openView = (r: Row) => { openEdit(r); setMode('view') }

  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    setSaving(true)
    const payload = { company_id: companyId, deduction_method: 'osd', ...form, period_quarter: form.period_type === 'annual' ? null : form.period_quarter }
    if (!editId) {
      const { error } = await supabase.from('income_tax_computations').insert([payload])
      if (error) { alert('Cannot save.\nReason: ' + (error.code === '23505' ? `A computation for ${fmtPeriod(form)} already exists.` : error.message)); setSaving(false); return }
    } else {
      const { error } = await supabase.from('income_tax_computations').update(payload).eq('id', editId)
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
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← OSD Computation</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? 'OSD Computation' : editId ? 'Edit Computation' : 'New Computation'}</h1>
            <p className="text-sm text-gray-500 mt-0.5">{fmtPeriod(form)} — Optional Standard Deduction (40% of Gross Income)</p>
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
            <div><label className={lbl}>Period Type</label>{isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{form.period_type === 'annual' ? 'Annual' : 'Quarterly'}</div> : <select value={form.period_type} onChange={e => set('period_type', e.target.value)} className={inp}><option value="quarterly">Quarterly</option><option value="annual">Annual</option></select>}</div>
            <div><label className={lbl}>Year</label>{isView ? <div className={ro}>{form.period_year}</div> : <select value={form.period_year} onChange={e => set('period_year', Number(e.target.value))} className={inp}>{years.map(y => <option key={y} value={y}>{y}</option>)}</select>}</div>
            {form.period_type === 'quarterly' && <div><label className={lbl}>Quarter</label>{isView ? <div className={ro}>Q{form.period_quarter}</div> : <select value={form.period_quarter || 1} onChange={e => set('period_quarter', Number(e.target.value))} className={inp}>{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>}</div>}
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Computation</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Gross Income</label>{isView ? <div className={ro}>{fmtNum(form.gross_income)}</div> : <input type="number" step="0.01" value={form.gross_income} onChange={e => set('gross_income', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>OSD (40% of Gross Income)</label><div className={ro}>{fmtNum(form.allowable_deductions)}</div></div>
            <div><label className={lbl}>Taxable Income</label><div className={ro}>{fmtNum(form.taxable_income)}</div></div>
            <div><label className={lbl}>Tax Rate (%)</label>{isView ? <div className={ro}>{form.tax_rate}%</div> : <input type="number" step="0.01" value={form.tax_rate} onChange={e => set('tax_rate', Number(e.target.value))} className={inp} />}</div>
            <div className="col-span-2 pt-2 border-t border-gray-100"><label className={lbl}>Tax Due</label><div className="text-2xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.tax_due)}</div></div>
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
        <div><h1 className="text-xl font-semibold text-gray-900">OSD Computation</h1><p className="text-sm text-gray-500 mt-0.5">Optional Standard Deduction — 40% of Gross Income</p></div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New Computation</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(4)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Period</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross Income</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">OSD (40%)</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Income</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Due</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={7} className="text-center py-16 text-gray-400"><p className="text-base font-medium text-gray-500">No Computations Found</p><p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New Computation" to begin.'}</p></td></tr>
              ) : rows.map((r, i) => (
                <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtPeriod(r)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.gross_income)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.allowable_deductions)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.taxable_income)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(r.tax_due)}</td>
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
