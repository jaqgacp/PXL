import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { downloadFilingArtifactExport } from '@/lib/filingExport'
import VATReconciliationPanel from '@/components/VATReconciliationPanel'

type Status = 'draft' | 'final' | 'filed'
type TaxRegistration = 'vat' | 'non_vat' | 'exempt'

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
  const [exporting, setExporting] = useState(false)
  const [taxRegistration, setTaxRegistration] = useState<TaxRegistration>('vat')
  const isVatRegistered = taxRegistration === 'vat'

  const load = async () => {
    if (!companyId) return
    setLoading(true)
    const [{ data: company }, { data }] = await Promise.all([
      supabase.from('companies').select('tax_registration').eq('id', companyId).single(),
      supabase.from('vat_returns').select('*').eq('company_id', companyId).eq('return_type', '2550Q')
        .order('period_year', { ascending: false }).order('period_quarter', { ascending: false }),
    ])
    setTaxRegistration((company?.tax_registration as TaxRegistration) || 'vat')
    setReturns((data as ReturnRow[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => ({ ...f, [k]: v }))

  const openNew = () => {
    if (!isVatRegistered) {
      alert('Cannot create VAT Return.\nReason: 2550Q is only available for VAT-registered companies.')
      return
    }
    setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new')
  }
  const openEdit = (r: ReturnRow) => { setForm({ ...r, filed_date: r.filed_date || '', reference_no: r.reference_no || '', remarks: '' }); setEditId(r.id); setMode('edit') }
  const openView = (r: ReturnRow) => { openEdit(r); setMode('view') }

  // The return is computed from the posted tax ledger, in the database, by
  // `fn_generate_vat_return`. It used to be summed here in the browser from two
  // review views, and a figure computed on the client is not a figure computed
  // from the books. The RPC generates the 2550Q filing artifact and its working
  // paper, then projects both into the `vat_returns` row this screen reads.
  //
  // Input VAT carried over and VAT already paid are the only figures the
  // accountant states; they are passed to the RPC rather than netted here, so
  // the net payable still has exactly one author.
  const handleGenerate = async () => {
    if (!companyId) return
    if (!isVatRegistered) {
      alert('Cannot generate VAT Return.\nReason: 2550Q is only available for VAT-registered companies.')
      return
    }
    setGenerating(true)
    const { data, error } = await supabase.rpc('fn_generate_vat_return', {
      p_company_id: companyId,
      p_year: form.period_year,
      p_quarter: form.period_quarter,
      p_input_vat_carried_over: form.input_vat_carried_over,
      p_vat_paid_prior_months: form.vat_paid_prior_months,
    })
    setGenerating(false)
    if (error) { alert('Cannot generate VAT Return.\nReason: ' + error.message); return }

    const r = data as {
      vat_return_id: string
      output_taxable_sales: number; output_vat: number
      zero_rated_sales: number; exempt_sales: number
      input_taxable_purchases: number; input_vat: number
      input_vat_carried_over: number; total_available_input_vat: number
      net_vat_payable: number; vat_paid_prior_months: number; vat_still_due: number
      line_count: number; is_reconciled: boolean
    }

    setForm(f => ({
      ...f,
      output_taxable_sales: Number(r.output_taxable_sales),
      output_vat: Number(r.output_vat),
      zero_rated_sales: Number(r.zero_rated_sales),
      exempt_sales: Number(r.exempt_sales),
      input_taxable_purchases: Number(r.input_taxable_purchases),
      input_vat: Number(r.input_vat),
      input_vat_carried_over: Number(r.input_vat_carried_over),
      total_available_input_vat: Number(r.total_available_input_vat),
      net_vat_payable: Number(r.net_vat_payable),
      vat_paid_prior_months: Number(r.vat_paid_prior_months),
      vat_still_due: Number(r.vat_still_due),
    }))
    // The RPC owns the row; from here the screen is editing it, not creating one.
    setEditId(r.vat_return_id)
    setMode('edit')
    await load()
    alert(
      `Generated from the posted VAT ledger.\n` +
      `Output VAT: ${fmtNum(Number(r.output_vat))}\n` +
      `Input VAT: ${fmtNum(Number(r.input_vat))}\n` +
      `Net VAT payable: ${fmtNum(Number(r.net_vat_payable))}\n` +
      `Working paper lines: ${r.line_count}` +
      (r.is_reconciled ? '' : '\n\nWARNING: the VAT ledger does not tie to the General Ledger for this quarter. This return cannot be marked final until it does.')
    )
  }

  // Saving records what the accountant decides — the filing status and its
  // reference. The tax figures are never written from here: they belong to the
  // posted ledger, and the database refuses a return that disagrees with it.
  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    if (!isVatRegistered) { alert('Cannot save VAT Return.\nReason: 2550Q is only available for VAT-registered companies.'); return }
    if (!editId) {
      alert('Cannot save VAT Return.\nReason: Generate the return from the posted ledger first — its figures are computed, not typed.')
      return
    }
    setSaving(true)
    const { error } = await supabase.from('vat_returns').update({
      status: form.status,
      filed_date: form.filed_date || null,
      reference_no: form.reference_no || null,
      remarks: form.remarks || null,
    }).eq('id', editId)
    setSaving(false)
    if (error) { alert('Cannot update VAT Return.\nReason: ' + error.message); return }
    load(); setMode('list')
  }

  // The download is a consumer of the filing artifact: the RPC evidences the
  // exact bytes into report_snapshots and this hands back that same content.
  // Nothing about the return is assembled here.
  const handleExport = async () => {
    if (!companyId || !editId) return
    setExporting(true)
    const result = await downloadFilingArtifactExport({
      companyId, formCode: '2550Q', year: form.period_year, period: form.period_quarter,
    })
    setExporting(false)
    if (!result.ok) { alert('Cannot export the return.\nReason: ' + result.message); return }
    alert(`Exported ${result.rows} working-paper line${result.rows === 1 ? '' : 's'} for ${fmtQuarter(form.period_year, form.period_quarter)}.`)
  }

  const isView = mode === 'view'
  const years = Array.from({ length: 6 }, (_, i) => now.getFullYear() - 4 + i)
  const qStartMonth = (form.period_quarter - 1) * 3 + 1
  const qEndMonth = form.period_quarter * 3
  const periodStart = `${form.period_year}-${String(qStartMonth).padStart(2, '0')}-01`
  const periodEnd = `${form.period_year}-${String(qEndMonth).padStart(2, '0')}-${String(new Date(form.period_year, qEndMonth, 0).getDate()).padStart(2, '0')}`

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
                <button onClick={handleExport} disabled={exporting || form.status === 'draft'} title={form.status === 'draft' ? 'Mark the return final before exporting it' : 'Download the filing artifact'} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{exporting ? 'Exporting...' : '↓ Export CSV'}</button>
                <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Print</button>
                <button onClick={() => setMode('list')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Close</button>
              </>
            ) : (
              <>
                <button onClick={handleGenerate} disabled={generating || !isVatRegistered} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50 disabled:opacity-50">{generating ? 'Generating...' : '⚡ Generate from posted ledger'}</button>
                <button onClick={() => setMode('list')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
                <button onClick={handleSave} disabled={saving || !isVatRegistered} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving...' : editId ? 'Update' : 'Save'}</button>
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

        {/* Every figure below the two stated ones is read from the posted VAT
            ledger by the RPC. None of them is typed, and none is recomputed
            here: a return the ledger does not support cannot be marked final. */}
        <div className={sec}>
          <h2 className={hd}>Sales / Output VAT (Quarter Total)</h2>
          <div className="col-span-2 text-xs text-gray-500 bg-gray-50 border border-gray-100 rounded px-3 py-2">
            Computed from the posted VAT ledger. Press Generate after changing the
            quarter, or after restating the two figures below.
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Taxable Sales</label><div className={ro}>{fmtNum(form.output_taxable_sales)}</div></div>
            <div><label className={lbl}>Output VAT</label><div className={ro}>{fmtNum(form.output_vat)}</div></div>
            <div><label className={lbl}>Zero-Rated Sales</label><div className={ro}>{fmtNum(form.zero_rated_sales)}</div></div>
            <div><label className={lbl}>Exempt Sales</label><div className={ro}>{fmtNum(form.exempt_sales)}</div></div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Purchases / Input VAT (Quarter Total)</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Taxable Purchases</label><div className={ro}>{fmtNum(form.input_taxable_purchases)}</div></div>
            <div><label className={lbl}>Input VAT</label><div className={ro}>{fmtNum(form.input_vat)}</div></div>
            {/* Stated, not derived: the prior quarter's excess credit. */}
            <div><label className={lbl}>Input VAT Carried Over <span className="text-gray-400 font-normal">— stated</span></label>{isView ? <div className={ro}>{fmtNum(form.input_vat_carried_over)}</div> : <input type="number" step="0.01" min="0" value={form.input_vat_carried_over} onChange={e => set('input_vat_carried_over', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>Total Available Input VAT</label><div className={ro}>{fmtNum(form.total_available_input_vat)}</div></div>
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Net VAT Payable</h2>
          <div className="grid grid-cols-3 gap-4">
            <div><label className={lbl}>Net VAT Payable (Quarter)</label><div className="text-xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.net_vat_payable)}</div></div>
            {/* Stated, not derived: VAT already remitted for this quarter. */}
            <div><label className={lbl}>Less: VAT Already Paid <span className="text-gray-400 font-normal">— stated</span></label>{isView ? <div className={ro}>{fmtNum(form.vat_paid_prior_months)}</div> : <input type="number" step="0.01" min="0" value={form.vat_paid_prior_months} onChange={e => set('vat_paid_prior_months', Number(e.target.value))} className={inp} />}</div>
            <div><label className={lbl}>VAT Still Due</label><div className="text-xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.vat_still_due)}</div></div>
          </div>
        </div>

        {companyId && (
          <VATReconciliationPanel companyId={companyId} dateFrom={periodStart} dateTo={periodEnd}
            returnOutputVat={form.output_vat} returnInputVat={form.input_vat} />
        )}

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
        <button onClick={openNew} disabled={!isVatRegistered} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Return</button>
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
