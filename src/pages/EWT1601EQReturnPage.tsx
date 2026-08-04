import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { downloadFilingArtifactExport } from '@/lib/filingExport'

type Status = 'draft' | 'final' | 'filed'

type ReturnRow = {
  id: string
  period_year: number
  period_quarter: number
  total_tax_base: number
  total_ewt_withheld: number
  remitted_prior: number
  still_due: number
  status: Status
  filed_date: string | null
  reference_no: string | null
}

type FormData = Omit<ReturnRow, 'id' | 'filed_date' | 'reference_no'> & { filed_date: string; reference_no: string; remarks: string }

const now = new Date()
const EMPTY_FORM: FormData = { period_year: now.getFullYear(), period_quarter: Math.floor(now.getMonth() / 3) + 1, total_tax_base: 0, total_ewt_withheld: 0, remitted_prior: 0, still_due: 0, status: 'draft', filed_date: '', reference_no: '', remarks: '' }
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

export default function EWT1601EQReturnPage() {
  const { companyId } = useAppCtx()
  const [returns, setReturns] = useState<ReturnRow[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState<FormData>({ ...EMPTY_FORM })
  const [saving, setSaving] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [exporting, setExporting] = useState(false)

  const load = async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('ewt_returns').select('*').eq('company_id', companyId).order('period_year', { ascending: false }).order('period_quarter', { ascending: false })
    setReturns((data as ReturnRow[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string | number) => setForm(f => ({ ...f, [k]: v }))
  const openNew = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setMode('new') }
  const openEdit = (r: ReturnRow) => { setForm({ ...r, filed_date: r.filed_date || '', reference_no: r.reference_no || '', remarks: '' }); setEditId(r.id); setMode('edit') }
  const openView = (r: ReturnRow) => { openEdit(r); setMode('view') }

  // The return is generated in the database by `fn_generate_ewt_return`: it
  // produces the 1601EQ filing artifact and its per-ATC working paper from the
  // posted tax ledger, then projects both into the `ewt_returns` row this screen
  // reads. The screen used to compute here and write the row by typed insert, so
  // a 1601EQ could be marked filed with no artifact behind it and nothing to
  // export.
  //
  // Nothing on this return is stated. What was already remitted comes from the
  // posted 0619-E remittances, which is the only figure the database will accept
  // when the return is marked final, so it is read from there rather than typed
  // here and rejected later.
  const handleGenerate = async () => {
    if (!companyId) return
    setGenerating(true)
    const { data, error } = await supabase.rpc('fn_generate_ewt_return', {
      p_company_id: companyId, p_year: form.period_year, p_quarter: form.period_quarter,
    })
    setGenerating(false)
    if (error) { alert('Cannot generate the 1601EQ.\nReason: ' + error.message); return }

    const r = data as {
      ewt_return_id: string
      total_tax_base: number; total_ewt_withheld: number
      remitted_prior: number; still_due: number
      line_count: number; is_reconciled: boolean
    }

    setForm(f => ({
      ...f,
      total_tax_base: Number(r.total_tax_base),
      total_ewt_withheld: Number(r.total_ewt_withheld),
      remitted_prior: Number(r.remitted_prior),
      still_due: Number(r.still_due),
    }))
    // The RPC owns the row; from here the screen is editing it, not creating one.
    setEditId(r.ewt_return_id)
    setMode('edit')
    await load()
    alert(
      `Generated from the posted withholding ledger.\n` +
      `Tax base: ${fmtNum(Number(r.total_tax_base))}\n` +
      `EWT withheld: ${fmtNum(Number(r.total_ewt_withheld))}\n` +
      `Still due: ${fmtNum(Number(r.still_due))}\n` +
      `Working paper lines: ${r.line_count}` +
      (r.is_reconciled ? '' : '\n\nWARNING: the withholding ledger does not tie to the General Ledger for this quarter. This return cannot be marked final until it does.')
    )
  }

  // Saving records what the accountant decides — the filing status and its
  // reference. The tax figures are never written from here: they belong to the
  // posted ledger, and the database refuses a return that disagrees with it.
  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    if (!editId) {
      alert('Cannot save the 1601EQ.\nReason: Generate the return from the posted ledger first — its figures are computed, not typed.')
      return
    }
    setSaving(true)
    const { error } = await supabase.from('ewt_returns').update({
      status: form.status,
      filed_date: form.filed_date || null,
      reference_no: form.reference_no || null,
      remarks: form.remarks || null,
    }).eq('id', editId)
    setSaving(false)
    if (error) { alert('Cannot update the 1601EQ.\nReason: ' + error.message); return }
    load(); setMode('list')
  }

  // The download is a consumer of the filing artifact: the RPC evidences the
  // exact bytes into report_snapshots and this hands back that same content.
  // Nothing about the return is assembled here.
  const handleExport = async () => {
    if (!companyId || !editId) return
    setExporting(true)
    const result = await downloadFilingArtifactExport({
      companyId, formCode: '1601EQ', year: form.period_year, period: form.period_quarter,
    })
    setExporting(false)
    if (!result.ok) { alert('Cannot export the return.\nReason: ' + result.message); return }
    alert(`Exported ${result.rows} working-paper line${result.rows === 1 ? '' : 's'} for ${fmtQuarter(form.period_year, form.period_quarter)}.`)
  }

  const isView = mode === 'view'
  const years = Array.from({ length: 6 }, (_, i) => now.getFullYear() - 4 + i)

  if (mode === 'new' || mode === 'edit' || mode === 'view') {
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← 1601EQ Quarterly Return</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? 'Quarterly EWT Return — 1601EQ' : editId ? 'Edit Return' : 'New Return'}</h1>
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
                <button onClick={handleGenerate} disabled={generating} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50 disabled:opacity-50">{generating ? 'Generating...' : '⚡ Generate from posted ledger'}</button>
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

        {/* Every figure below the one stated remittance is read from the posted
            withholding ledger by the RPC. None of them is typed, and none is
            recomputed here: a return the ledger does not support cannot be
            marked final. */}
        <div className={sec}>
          <h2 className={hd}>Return Computation</h2>
          <div className="col-span-2 text-xs text-gray-500 bg-gray-50 border border-gray-100 rounded px-3 py-2">
            Computed from the posted withholding ledger. Press Generate after
            changing the quarter, or after posting a 0619-E remittance.
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Total Tax Base</label><div className={ro}>{fmtNum(form.total_tax_base)}</div></div>
            <div><label className={lbl}>Total EWT Withheld</label><div className={ro}>{fmtNum(form.total_ewt_withheld)}</div></div>
            {/* Derived, not stated: the posted 0619-E remittances for months 1
                and 2 of the quarter. */}
            <div><label className={lbl}>Less: Remitted Prior (0619-E) <span className="text-gray-400 font-normal">— from posted remittances</span></label><div className={ro}>{fmtNum(form.remitted_prior)}</div></div>
            <div className="col-span-2 pt-2 border-t border-gray-100"><label className={lbl}>Still Due</label><div className="text-2xl font-bold font-mono tabular-nums text-gray-900">{fmtNum(form.still_due)}</div></div>
          </div>
          {!isView && <p className="text-xs text-gray-400">A return can only be marked Final or Filed when its figures match the tax ledger, the ledger reconciles to the EWT Payable GL account for the quarter, and what it nets off matches the 0619-E remittances actually posted.</p>}
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
        <div><h1 className="text-xl font-semibold text-gray-900">1601EQ Quarterly Return</h1><p className="text-sm text-gray-500 mt-0.5">Quarterly Expanded Withholding Tax Return</p></div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New Return</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(4)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Base</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">EWT Withheld</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Still Due</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {returns.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400"><p className="text-base font-medium text-gray-500">No Returns Found</p><p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New Return" to compute the first return.'}</p></td></tr>
              ) : returns.map((r, i) => (
                <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtQuarter(r.period_year, r.period_quarter)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.total_tax_base)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.total_ewt_withheld)}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmtNum(r.still_due)}</td>
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
