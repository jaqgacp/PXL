import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Status = 'draft' | 'final' | 'filed'

type ReturnRow = {
  id: string
  company_id: string
  period_year: number
  period_quarter: number
  gross_sales_exempt: number
  gross_sales_zero_rated: number
  taxable_base: number
  pt_rate: number
  pt_due: number
  pt_paid_prior_quarters: number
  pt_still_due: number
  status: Status
  filed_date: string | null
  reference_no: string | null
  remarks: string | null
  updated_at: string
}

type FormData = {
  period_year: number
  period_quarter: number
  gross_sales_exempt: number
  gross_sales_zero_rated: number
  taxable_base: number
  pt_rate: number
  pt_due: number
  pt_paid_prior_quarters: number
  pt_still_due: number
  status: Status
  filed_date: string
  reference_no: string
  remarks: string
}

const now = new Date()
const EMPTY_FORM: FormData = {
  period_year: now.getFullYear(), period_quarter: Math.floor(now.getMonth() / 3) + 1,
  gross_sales_exempt: 0, gross_sales_zero_rated: 0, taxable_base: 0, pt_rate: 3,
  pt_due: 0, pt_paid_prior_quarters: 0, pt_still_due: 0,
  status: 'draft', filed_date: '', reference_no: '', remarks: '',
}

const STATUS_LABELS: Record<Status, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700 font-mono tabular-nums'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

const fmtQuarter = (y: number, q: number) => `Q${q} ${y}`
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const quarterMonths = (q: number) => [(q - 1) * 3 + 1, (q - 1) * 3 + 2, (q - 1) * 3 + 3]

function StatusBadge({ status }: { status: Status }) {
  const cls: Record<Status, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
}

export default function PTReturnPage() {
  const { companyId } = useAppCtx()

  const [returns, setReturns] = useState<ReturnRow[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode]       = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editId, setEditId]   = useState<string | null>(null)
  const [form, setForm]       = useState<FormData>({ ...EMPTY_FORM })
  const [saving, setSaving]   = useState(false)
  const [generating, setGenerating] = useState(false)

  const load = async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('pt_returns').select('*').eq('company_id', companyId)
      .order('period_year', { ascending: false }).order('period_quarter', { ascending: false })
    setReturns((data as ReturnRow[]) || [])
    setLoading(false)
  }

  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => ({ ...f, [k]: v }))

  const openNew = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new') }

  const openEdit = (r: ReturnRow) => {
    setForm({
      period_year: r.period_year, period_quarter: r.period_quarter,
      gross_sales_exempt: r.gross_sales_exempt, gross_sales_zero_rated: r.gross_sales_zero_rated,
      taxable_base: r.taxable_base, pt_rate: r.pt_rate, pt_due: r.pt_due,
      pt_paid_prior_quarters: r.pt_paid_prior_quarters, pt_still_due: r.pt_still_due,
      status: r.status, filed_date: r.filed_date || '', reference_no: r.reference_no || '', remarks: r.remarks || '',
    })
    setEditId(r.id); setMode('edit')
  }

  const openView = (r: ReturnRow) => { openEdit(r); setMode('view') }

  // Pull posted SI lines classified exempt/zero-rated for the selected quarter and recompute
  const handleGenerate = async () => {
    if (!companyId) return
    setGenerating(true)
    const months = quarterMonths(form.period_quarter)
    const startDate = `${form.period_year}-${String(months[0]).padStart(2, '0')}-01`
    const lastMonth = months[2]
    const endDate = new Date(form.period_year, lastMonth, 0).toISOString().split('T')[0]

    const { data } = await supabase
      .from('sales_invoice_lines')
      .select(`net_amount, vat_code_id, vat_codes!inner(vat_classification), sales_invoices!inner(date, status, company_id)`)
      .eq('sales_invoices.company_id', companyId)
      .eq('sales_invoices.status', 'posted')
      .gte('sales_invoices.date', startDate)
      .lte('sales_invoices.date', endDate)
      .in('vat_codes.vat_classification', ['exempt', 'zero_rated'])

    let exempt = 0, zeroRated = 0
    for (const r of (data || []) as Record<string, unknown>[]) {
      const vc = r.vat_codes as Record<string, unknown>
      const amt = Number(r.net_amount)
      if (vc.vat_classification === 'exempt') exempt += amt
      else zeroRated += amt
    }
    const taxableBase = exempt + zeroRated
    const ptDue = taxableBase * (form.pt_rate / 100)

    setForm(f => ({
      ...f,
      gross_sales_exempt: exempt,
      gross_sales_zero_rated: zeroRated,
      taxable_base: taxableBase,
      pt_due: ptDue,
      pt_still_due: ptDue - f.pt_paid_prior_quarters,
    }))
    setGenerating(false)
  }

  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    setSaving(true)
    const payload = {
      company_id: companyId,
      period_year: form.period_year, period_quarter: form.period_quarter,
      gross_sales_exempt: form.gross_sales_exempt, gross_sales_zero_rated: form.gross_sales_zero_rated,
      taxable_base: form.taxable_base, pt_rate: form.pt_rate, pt_due: form.pt_due,
      pt_paid_prior_quarters: form.pt_paid_prior_quarters, pt_still_due: form.pt_due - form.pt_paid_prior_quarters,
      status: form.status, filed_date: form.filed_date || null, reference_no: form.reference_no || null, remarks: form.remarks || null,
    }
    if (!editId) {
      const { error } = await supabase.from('pt_returns').insert([payload])
      if (error) {
        alert('Cannot save PT Return.\nReason: ' + (error.code === '23505' ? `A return for ${fmtQuarter(form.period_year, form.period_quarter)} already exists.` : error.message))
        setSaving(false); return
      }
    } else {
      const { error } = await supabase.from('pt_returns').update(payload).eq('id', editId)
      if (error) { alert('Cannot update PT Return.\nReason: ' + error.message); setSaving(false); return }
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
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← PT Quarterly Return</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? 'PT Quarterly Return — 2551Q' : editId ? 'Edit PT Return' : 'New PT Return'}</h1>
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
                <button onClick={handleGenerate} disabled={generating} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50 disabled:opacity-50">{generating ? 'Generating...' : '⚡ Generate from Sales'}</button>
                <button onClick={() => setMode('list')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
                <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving...' : editId ? 'Update' : 'Save'}</button>
              </>
            )}
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Period</h2>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <label className={lbl}>Year</label>
              {isView ? <div className={ro}>{form.period_year}</div> : (
                <select value={form.period_year} onChange={e => set('period_year', Number(e.target.value))} className={inp}>
                  {years.map(y => <option key={y} value={y}>{y}</option>)}
                </select>
              )}
            </div>
            <div>
              <label className={lbl}>Quarter</label>
              {isView ? <div className={ro}>Q{form.period_quarter}</div> : (
                <select value={form.period_quarter} onChange={e => set('period_quarter', Number(e.target.value))} className={inp}>
                  {[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}
                </select>
              )}
            </div>
            <div>
              <label className={lbl}>Status</label>
              {isView ? <div className="mt-1.5"><StatusBadge status={form.status} /></div> : (
                <select value={form.status} onChange={e => set('status', e.target.value)} className={inp}>
                  <option value="draft">Draft</option>
                  <option value="final">Final</option>
                  <option value="filed">Filed</option>
                </select>
              )}
            </div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Return Computation (BIR Form 2551Q)</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={lbl}>Gross Sales — Exempt</label>
              {isView ? <div className={ro}>{fmtNum(form.gross_sales_exempt)}</div> :
                <input type="number" step="0.01" value={form.gross_sales_exempt} onChange={e => set('gross_sales_exempt', Number(e.target.value))} className={inp} />}
            </div>
            <div>
              <label className={lbl}>Gross Sales — Zero-Rated</label>
              {isView ? <div className={ro}>{fmtNum(form.gross_sales_zero_rated)}</div> :
                <input type="number" step="0.01" value={form.gross_sales_zero_rated} onChange={e => set('gross_sales_zero_rated', Number(e.target.value))} className={inp} />}
            </div>
            <div>
              <label className={lbl}>Taxable Base</label>
              {isView ? <div className={ro}>{fmtNum(form.taxable_base)}</div> :
                <input type="number" step="0.01" value={form.taxable_base} onChange={e => set('taxable_base', Number(e.target.value))} className={inp} />}
            </div>
            <div>
              <label className={lbl}>PT Rate (%)</label>
              {isView ? <div className={ro}>{form.pt_rate}%</div> :
                <input type="number" step="0.01" value={form.pt_rate} onChange={e => set('pt_rate', Number(e.target.value))} className={inp} />}
            </div>
            <div>
              <label className={lbl}>PT Due</label>
              {isView ? <div className={ro}>{fmtNum(form.pt_due)}</div> :
                <input type="number" step="0.01" value={form.pt_due} onChange={e => set('pt_due', Number(e.target.value))} className={inp} />}
            </div>
            <div>
              <label className={lbl}>Less: Paid — Prior Quarters</label>
              {isView ? <div className={ro}>{fmtNum(form.pt_paid_prior_quarters)}</div> :
                <input type="number" step="0.01" value={form.pt_paid_prior_quarters} onChange={e => set('pt_paid_prior_quarters', Number(e.target.value))} className={inp} />}
            </div>
            <div className="col-span-2 pt-2 border-t border-gray-100">
              <label className={lbl}>PT Still Due</label>
              <div className="text-2xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.pt_due - form.pt_paid_prior_quarters)}</div>
            </div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Filing</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={lbl}>Filed Date</label>
              {isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{form.filed_date || '—'}</div> :
                <input type="date" value={form.filed_date} onChange={e => set('filed_date', e.target.value)} className={inp} />}
            </div>
            <div>
              <label className={lbl}>Reference No. (eFPS/Bank)</label>
              {isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{form.reference_no || '—'}</div> :
                <input value={form.reference_no} onChange={e => set('reference_no', e.target.value)} className={inp} />}
            </div>
            <div className="col-span-2">
              <label className={lbl}>Remarks</label>
              {isView ? <textarea readOnly value={form.remarks || '—'} rows={2} className={ro.replace(' font-mono tabular-nums', '')} /> :
                <textarea value={form.remarks} onChange={e => set('remarks', e.target.value)} rows={2} className={inp} />}
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">PT Quarterly Return — 2551Q</h1>
          <p className="text-sm text-gray-500 mt-0.5">Quarterly Percentage Tax Return</p>
        </div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New Return</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(4)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">PT Due</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Still Due</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
              </tr>
            </thead>
            <tbody>
              {returns.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">
                  <p className="text-base font-medium text-gray-500">No PT Returns Found</p>
                  <p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New Return" to compute the first return.'}</p>
                </td></tr>
              ) : returns.map((r, i) => (
                <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtQuarter(r.period_year, r.period_quarter)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.taxable_base)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.pt_due)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(r.pt_still_due)}</td>
                  <td className="px-4 py-3"><StatusBadge status={r.status} /></td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <button onClick={() => openView(r)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button>
                      <button onClick={() => openEdit(r)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
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
