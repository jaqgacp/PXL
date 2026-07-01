import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Status = 'draft' | 'final' | 'filed'

type ReturnRow = {
  id: string
  period_year: number
  period_quarter: number
  output_taxable_sales: number
  output_vat: number
  zero_rated_sales: number
  exempt_sales: number
  input_taxable_purchases: number
  input_vat: number
  input_vat_carried_over: number
  total_available_input_vat: number
  net_vat_payable: number
  vat_paid_prior_months: number
  vat_still_due: number
  status: Status
  filed_date: string | null
  reference_no: string | null
}

type FormData = Omit<ReturnRow, 'id' | 'filed_date' | 'reference_no'> & { filed_date: string; reference_no: string; remarks: string }

const now = new Date()
const EMPTY_FORM: FormData = {
  period_year: now.getFullYear(), period_quarter: Math.floor(now.getMonth() / 3) + 1,
  output_taxable_sales: 0, output_vat: 0, zero_rated_sales: 0, exempt_sales: 0,
  input_taxable_purchases: 0, input_vat: 0, input_vat_carried_over: 0, total_available_input_vat: 0,
  net_vat_payable: 0, vat_paid_prior_months: 0, vat_still_due: 0,
  status: 'draft', filed_date: '', reference_no: '', remarks: '',
}

const STATUS_LABELS: Record<Status, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700 font-mono tabular-nums'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const fmtQuarter = (y: number, q: number) => `Q${q} ${y}`
const quarterMonths = (q: number) => [(q - 1) * 3 + 1, (q - 1) * 3 + 2, (q - 1) * 3 + 3]

function StatusBadge({ status }: { status: Status }) {
  const cls: Record<Status, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
}

export default function VATReturn2550QPage() {
  const { companyId } = useAppCtx()
  const [returns, setReturns] = useState<ReturnRow[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState<FormData>({ ...EMPTY_FORM })
  const [saving, setSaving] = useState(false)
  const [generating, setGenerating] = useState(false)

  const load = async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('vat_returns').select('*').eq('company_id', companyId).eq('return_type', '2550Q')
      .order('period_year', { ascending: false }).order('period_quarter', { ascending: false })
    setReturns((data as ReturnRow[]) || [])
    setLoading(false)
  }

  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => ({ ...f, [k]: v }))

  const openNew = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new') }
  const openEdit = (r: ReturnRow) => { setForm({ ...r, filed_date: r.filed_date || '', reference_no: r.reference_no || '', remarks: '' }); setEditId(r.id); setMode('edit') }
  const openView = (r: ReturnRow) => { openEdit(r); setMode('view') }

  const handleGenerate = async () => {
    if (!companyId) return
    setGenerating(true)
    const months = quarterMonths(form.period_quarter)
    const startDate = `${form.period_year}-${String(months[0]).padStart(2, '0')}-01`
    const endDate = new Date(form.period_year, months[2], 0).toISOString().split('T')[0]

    const [{ data: outData }, { data: inData }, { data: monthlyReturns }] = await Promise.all([
      supabase.from('vw_output_vat_review').select('*').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate),
      supabase.from('vw_input_vat_review').select('*').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate),
      supabase.from('vat_returns').select('period_month,net_vat_payable').eq('company_id', companyId).eq('return_type', '2550M')
        .eq('period_year', form.period_year).in('period_month', months),
    ])

    const outRows = (outData || []) as { taxable_base: number; zero_rated_sales: number; exempt_sales: number; output_vat: number }[]
    const inRows = (inData || []) as { taxable_base: number; input_vat: number }[]

    const outputTaxable = outRows.reduce((s, r) => s + r.taxable_base, 0)
    const zeroRated = outRows.reduce((s, r) => s + r.zero_rated_sales, 0)
    const exempt = outRows.reduce((s, r) => s + r.exempt_sales, 0)
    const outputVat = outRows.reduce((s, r) => s + r.output_vat, 0)
    const inputTaxable = inRows.reduce((s, r) => s + r.taxable_base, 0)
    const inputVat = inRows.reduce((s, r) => s + r.input_vat, 0)

    // Monthly payments made in the first two months of the quarter (2550M filings)
    const paidPriorMonths = ((monthlyReturns || []) as { period_month: number; net_vat_payable: number }[])
      .filter(r => r.period_month !== months[2])
      .reduce((s, r) => s + Math.max(Number(r.net_vat_payable), 0), 0)

    const totalAvailableInputVat = inputVat + form.input_vat_carried_over
    const netPayable = outputVat - totalAvailableInputVat
    const stillDue = netPayable - paidPriorMonths

    setForm(f => ({
      ...f, output_taxable_sales: outputTaxable, output_vat: outputVat, zero_rated_sales: zeroRated, exempt_sales: exempt,
      input_taxable_purchases: inputTaxable, input_vat: inputVat, total_available_input_vat: totalAvailableInputVat,
      net_vat_payable: netPayable, vat_paid_prior_months: paidPriorMonths, vat_still_due: stillDue,
    }))
    setGenerating(false)
  }

  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    setSaving(true)
    const payload = {
      company_id: companyId, return_type: '2550Q',
      period_year: form.period_year, period_month: null, period_quarter: form.period_quarter,
      output_taxable_sales: form.output_taxable_sales, output_vat: form.output_vat,
      zero_rated_sales: form.zero_rated_sales, exempt_sales: form.exempt_sales,
      input_taxable_purchases: form.input_taxable_purchases, input_vat: form.input_vat,
      input_vat_carried_over: form.input_vat_carried_over, total_available_input_vat: form.total_available_input_vat,
      net_vat_payable: form.net_vat_payable, vat_paid_prior_months: form.vat_paid_prior_months,
      vat_still_due: form.vat_still_due,
      status: form.status, filed_date: form.filed_date || null, reference_no: form.reference_no || null, remarks: form.remarks || null,
    }
    if (!editId) {
      const { error } = await supabase.from('vat_returns').insert([payload])
      if (error) { alert('Cannot save VAT Return.\nReason: ' + (error.code === '23505' ? `A 2550Q return for ${fmtQuarter(form.period_year, form.period_quarter)} already exists.` : error.message)); setSaving(false); return }
    } else {
      const { error } = await supabase.from('vat_returns').update(payload).eq('id', editId)
      if (error) { alert('Cannot update VAT Return.\nReason: ' + error.message); setSaving(false); return }
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
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← VAT Return 2550Q</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? 'Quarterly VAT Return — 2550Q' : editId ? 'Edit VAT Return' : 'New VAT Return'}</h1>
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
                <button onClick={handleGenerate} disabled={generating} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50 disabled:opacity-50">{generating ? 'Generating...' : '⚡ Generate'}</button>
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
          <h2 className={hd}>Sales / Output VAT (Quarter Total)</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Taxable Sales</label>{isView ? <div className={ro}>{fmtNum(form.output_taxable_sales)}</div> : <input type="number" step="0.01" value={form.output_taxable_sales} onChange={e => set('output_taxable_sales', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Output VAT</label>{isView ? <div className={ro}>{fmtNum(form.output_vat)}</div> : <input type="number" step="0.01" value={form.output_vat} onChange={e => set('output_vat', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Zero-Rated Sales</label>{isView ? <div className={ro}>{fmtNum(form.zero_rated_sales)}</div> : <input type="number" step="0.01" value={form.zero_rated_sales} onChange={e => set('zero_rated_sales', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Exempt Sales</label>{isView ? <div className={ro}>{fmtNum(form.exempt_sales)}</div> : <input type="number" step="0.01" value={form.exempt_sales} onChange={e => set('exempt_sales', Number(e.target.value))} className={inp} />}</div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Purchases / Input VAT (Quarter Total)</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Taxable Purchases</label>{isView ? <div className={ro}>{fmtNum(form.input_taxable_purchases)}</div> : <input type="number" step="0.01" value={form.input_taxable_purchases} onChange={e => set('input_taxable_purchases', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Input VAT</label>{isView ? <div className={ro}>{fmtNum(form.input_vat)}</div> : <input type="number" step="0.01" value={form.input_vat} onChange={e => set('input_vat', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Input VAT Carried Over</label>{isView ? <div className={ro}>{fmtNum(form.input_vat_carried_over)}</div> : <input type="number" step="0.01" value={form.input_vat_carried_over} onChange={e => set('input_vat_carried_over', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Total Available Input VAT</label>{isView ? <div className={ro}>{fmtNum(form.total_available_input_vat)}</div> : <input type="number" step="0.01" value={form.total_available_input_vat} onChange={e => set('total_available_input_vat', Number(e.target.value))} className={inp} />}</div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Net VAT Payable</h2>
          <div className="grid grid-cols-3 gap-4">
            <div><label className={lbl}>Net VAT Payable (Quarter)</label><div className="text-xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.net_vat_payable)}</div></div>
            <div><label className={lbl}>Less: Paid — First 2 Months (2550M)</label>{isView ? <div className={ro}>{fmtNum(form.vat_paid_prior_months)}</div> : <input type="number" step="0.01" value={form.vat_paid_prior_months} onChange={e => set('vat_paid_prior_months', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>VAT Still Due</label><div className="text-xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.net_vat_payable - form.vat_paid_prior_months)}</div></div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Filing</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Filed Date</label>{isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{form.filed_date || '—'}</div> : <input type="date" value={form.filed_date} onChange={e => set('filed_date', e.target.value)} className={inp} />}</div>
            <div><label className={lbl}>Reference No. (eFPS/Bank)</label>{isView ? <div className={ro.replace(' font-mono tabular-nums', '')}>{form.reference_no || '—'}</div> : <input value={form.reference_no} onChange={e => set('reference_no', e.target.value)} className={inp} />}</div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">VAT Return — 2550Q</h1>
          <p className="text-sm text-gray-500 mt-0.5">Quarterly VAT Return</p>
        </div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New Return</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(4)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Output VAT</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Input VAT</th>
                <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Still Due</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
              </tr>
            </thead>
            <tbody>
              {returns.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">
                  <p className="text-base font-medium text-gray-500">No VAT Returns Found</p>
                  <p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New Return" to compute the first return.'}</p>
                </td></tr>
              ) : returns.map((r, i) => (
                <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtQuarter(r.period_year, r.period_quarter)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.output_vat)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.total_available_input_vat)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(r.vat_still_due)}</td>
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
