import { useState, useEffect, useCallback } from 'react'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { downloadFilingArtifactExport } from '@/lib/filingExport'

/**
 * The one working-paper surface, for every filing artifact.
 *
 * It replaces four hand-keyed screens — VAT, EWT, 1601EQ and PT working papers —
 * that let an accountant type a schedule no ledger backed. Those screens were
 * the second compliance architecture; this one is a face of the governed
 * pipeline and computes nothing:
 *
 *   posted transactions → tax ledger → fn_filing_working_paper → artifact
 *
 * The figures come from the one working-paper reader. The only thing an
 * accountant enters here is a **reconciling item**, which explains a difference
 * and never becomes one: it carries no tax figure, reaches no total, no
 * reconciliation and no journal entry, and it is frozen once the artifact leaves
 * draft.
 */

type WorkingPaperRow = {
  tax_kind: string | null
  classification: string | null
  tax_code: string | null
  vat_code: string | null
  atc_code: string | null
  counterparty_id: string | null
  counterparty_name: string | null
  counterparty_tin: string | null
  tax_rate: number | null
  tax_base: number
  tax_amount: number
  document_count: number
}

type ReconcilingItem = {
  id: string
  line_number: number
  reason: string
  reference: string
  amount: number
  remarks: string
  created_at: string
}

type ArtifactStatus = 'draft' | 'final' | 'filed'
type Artifact = {
  id: string
  status: ArtifactStatus
  generated_at: string
  total_tax_base: number
  total_tax_amount: number
  net_tax_payable: number | null
}

type Props = {
  formCode: string
  title: string
  subtitle: string
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const STATUS_LABELS: Record<ArtifactStatus, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'

function StatusBadge({ status }: { status: ArtifactStatus }) {
  const cls: Record<ArtifactStatus, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
}

const EMPTY_ITEM = { reason: '', reference: '', amount: '', remarks: '' }

export default function FilingWorkingPapersPage({ formCode, title, subtitle }: Props) {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<'generate' | 'final' | 'export' | 'item' | null>(null)
  const [rows, setRows] = useState<WorkingPaperRow[]>([])
  const [items, setItems] = useState<ReconcilingItem[]>([])
  const [artifact, setArtifact] = useState<Artifact | null>(null)
  const [form, setForm] = useState({ ...EMPTY_ITEM })

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const [{ data: paper, error }, { data: artifactRow }, { data: itemRows }] = await Promise.all([
      supabase.rpc('fn_filing_working_paper', {
        p_company_id: companyId, p_form_code: formCode, p_year: year, p_period: quarter,
      }),
      supabase.from('filing_artifacts')
        .select('id,status,generated_at,total_tax_base,total_tax_amount,net_tax_payable')
        .eq('company_id', companyId).eq('form_code', formCode)
        .eq('period_year', year).eq('period_number', quarter).maybeSingle(),
      supabase.rpc('fn_filing_reconciling_items', {
        p_company_id: companyId, p_form_code: formCode, p_year: year, p_period: quarter,
      }),
    ])
    setLoading(false)
    if (error) { alert(`Cannot load the ${formCode} working paper.\nReason: ` + error.message); return }
    setRows((paper || []) as WorkingPaperRow[])
    setArtifact((artifactRow as Artifact | null) ?? null)
    setItems((itemRows || []) as ReconcilingItem[])
  }, [companyId, formCode, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const isDraft = artifact?.status === 'draft'
  const totalBase = rows.reduce((s, r) => s + Number(r.tax_base), 0)
  const totalTax = rows.reduce((s, r) => s + Number(r.tax_amount), 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  // Only the columns this form actually carries. One table serves every artifact
  // because a dimension the form does not group by comes back empty.
  const has = (k: keyof WorkingPaperRow) => rows.some(r => r[k] !== null && r[k] !== '')

  // The legacy screens listed one row per document. The governed working paper
  // groups by the dimensions the form is filed on and counts the documents, so
  // the documents themselves stay reachable through the accounting trace.
  const period = {
    from: `${year}-${String((quarter - 1) * 3 + 1).padStart(2, '0')}-01`,
    to: new Date(year, quarter * 3, 0).toISOString().split('T')[0],
  }
  const traceFilters = (r: WorkingPaperRow) => ({
    tax_kind: r.tax_kind || undefined,
    atc_code: r.atc_code || undefined,
    counterparty_id: r.counterparty_id || undefined,
    date_from: period.from,
    date_to: period.to,
  })

  const handleGenerate = async () => {
    if (!companyId) return
    setBusy('generate')
    const { data, error } = await supabase.rpc('fn_generate_filing_artifact', {
      p_company_id: companyId, p_form_code: formCode, p_year: year, p_period: quarter,
    })
    setBusy(null)
    if (error) { alert(`Cannot generate the ${formCode} working paper.\nReason: ` + error.message); return }
    await load()
    const r = data as { line_count: number; total_tax_amount: number; is_reconciled: boolean }
    alert(
      `Generated from the posted tax ledger.\n` +
      `Schedule lines: ${r.line_count}\n` +
      `Tax: ${fmt(Number(r.total_tax_amount))}` +
      (r.is_reconciled ? '' : '\n\nWARNING: the tax ledger does not tie to the General Ledger for this period. This working paper cannot be marked final until it does.')
    )
  }

  const handleMarkFinal = async () => {
    if (!artifact) return
    setBusy('final')
    const { error } = await supabase.from('filing_artifacts').update({ status: 'final' }).eq('id', artifact.id)
    setBusy(null)
    if (error) { alert(`Cannot mark the ${formCode} working paper final.\nReason: ` + error.message); return }
    await load()
  }

  const handleExport = async () => {
    if (!companyId) return
    setBusy('export')
    const result = await downloadFilingArtifactExport({
      companyId, formCode, year, period: quarter,
    })
    setBusy(null)
    if (!result.ok) { alert('Cannot export the working paper.\nReason: ' + result.message); return }
    alert(`Exported ${result.rows} row${result.rows === 1 ? '' : 's'} for Q${quarter} ${year}.`)
  }

  // A reconciling item is the only thing entered on this screen, and the
  // database is what enforces that it stays an explanation.
  const handleAddItem = async () => {
    if (!companyId) return
    setBusy('item')
    const { error } = await supabase.rpc('fn_add_filing_reconciling_item', {
      p_company_id: companyId, p_form_code: formCode, p_year: year, p_period: quarter,
      p_reason: form.reason, p_reference: form.reference,
      p_amount: Number(form.amount || 0), p_remarks: form.remarks,
    })
    setBusy(null)
    if (error) { alert('Cannot record the reconciling item.\nReason: ' + error.message); return }
    setForm({ ...EMPTY_ITEM })
    await load()
  }

  const handleDeleteItem = async (id: string) => {
    setBusy('item')
    const { error } = await supabase.rpc('fn_delete_filing_reconciling_item', { p_item_id: id })
    setBusy(null)
    if (error) { alert('Cannot withdraw the reconciling item.\nReason: ' + error.message); return }
    await load()
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">{title}</h1>
          <p className="text-sm text-gray-500 mt-0.5">{subtitle}</p>
        </div>
        <div className="flex gap-2">
          <button onClick={handleGenerate} disabled={busy !== null || !companyId} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'generate' ? 'Generating...' : '⚡ Generate'}</button>
          <button onClick={handleMarkFinal} disabled={busy !== null || !isDraft} title={artifact ? undefined : 'Generate the working paper first'} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'final' ? 'Marking...' : 'Mark Final'}</button>
          <button onClick={handleExport} disabled={busy !== null || !artifact || artifact.status === 'draft'} title={!artifact || artifact.status === 'draft' ? 'Mark it final before exporting' : 'Download the filing artifact'} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'export' ? 'Exporting...' : '↓ Export CSV'}</button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <select value={quarter} onChange={e => setQuarter(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>
        <div className="flex items-center gap-2 text-xs text-gray-500 ml-auto">
          <span className="uppercase tracking-wide font-semibold text-gray-400">{formCode} artifact</span>
          {artifact ? (
            <>
              <StatusBadge status={artifact.status} />
              <span className="font-mono tabular-nums">{fmt(Number(artifact.total_tax_amount))}</span>
              <span>· generated {new Date(artifact.generated_at).toLocaleString('en-PH')}</span>
            </>
          ) : (
            <span className="text-gray-400">Not generated for this period — the schedule below is what it would carry.</span>
          )}
        </div>
      </div>

      {/* The schedule. Every figure is read from the posted tax ledger by the one
          working-paper reader; nothing here is typed, and nothing is summed in
          the browser beyond displaying the column totals of what it returned. */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <div className="px-4 py-2.5 border-b border-gray-100 flex items-baseline justify-between">
          <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Schedule — from the posted tax ledger</h2>
          <span className="text-xs text-gray-400">{rows.length} line{rows.length === 1 ? '' : 's'}</span>
        </div>
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                {has('tax_kind') && <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Kind</th>}
                {has('classification') && <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Class</th>}
                {has('vat_code') && <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">VAT Code</th>}
                {has('tax_code') && <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Code</th>}
                {has('atc_code') && <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">ATC</th>}
                {has('counterparty_name') && <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Counterparty</th>}
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rate</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Base</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Docs</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={10} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Nothing in the tax ledger for this period.'}</td></tr>
              ) : rows.map((r, i) => (
                <tr key={i} className="border-b border-gray-100 hover:bg-gray-50">
                  {has('tax_kind') && <td className="px-4 py-2.5 text-gray-700">{r.tax_kind || '—'}</td>}
                  {has('classification') && <td className="px-4 py-2.5 text-gray-500">{r.classification || '—'}</td>}
                  {has('vat_code') && <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{r.vat_code || '—'}</td>}
                  {has('tax_code') && <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{r.tax_code || '—'}</td>}
                  {has('atc_code') && <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{r.atc_code || '—'}</td>}
                  {has('counterparty_name') && <td className="px-4 py-2.5 text-gray-700">{r.counterparty_name || '—'}</td>}
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-500">{r.tax_rate === null ? '—' : `${fmt(Number(r.tax_rate))}%`}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(Number(r.tax_base))}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">
                    {companyId ? (
                      <ReportTraceLink
                        companyId={companyId}
                        reportFamily="tax"
                        filters={traceFilters(r)}
                        title="Open the posted documents behind this line"
                      >
                        {fmt(Number(r.tax_amount))}
                      </ReportTraceLink>
                    ) : fmt(Number(r.tax_amount))}
                  </td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-400">{r.document_count}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={[has('tax_kind'), has('classification'), has('vat_code'), has('tax_code'), has('atc_code'), has('counterparty_name')].filter(Boolean).length + 1}
                      className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalBase)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalTax)}</td>
                  <td />
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>

      {/* Reconciling items explain a difference and never create one: they carry
          no tax figure, reach no total and no reconciliation, and post nothing. */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <div className="px-4 py-2.5 border-b border-gray-100">
          <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Reconciling items — explanation only</h2>
          <p className="text-xs text-gray-400 mt-1">
            Recorded against the artifact, excluded from every total and from the
            General Ledger reconciliation, never posted, and frozen once the
            working paper is marked final.
          </p>
        </div>

        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">#</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Reason</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Reference</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Amount</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Remarks</th>
              <th className="px-4 py-2.5" />
            </tr>
          </thead>
          <tbody>
            {items.length === 0 ? (
              <tr><td colSpan={6} className="text-center py-8 text-gray-400">No reconciling items for this period.</td></tr>
            ) : items.map(it => (
              <tr key={it.id} className="border-b border-gray-100">
                <td className="px-4 py-2.5 text-gray-400 font-mono text-xs">{it.line_number}</td>
                <td className="px-4 py-2.5 text-gray-700">{it.reason}</td>
                <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{it.reference}</td>
                <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(Number(it.amount))}</td>
                <td className="px-4 py-2.5 text-gray-500">{it.remarks}</td>
                <td className="px-4 py-2.5 text-right">
                  {isDraft && <button onClick={() => handleDeleteItem(it.id)} disabled={busy !== null} className="text-xs text-red-600 hover:text-red-800 font-medium disabled:opacity-40">Withdraw</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {isDraft ? (
          <div className="border-t border-gray-100 p-4 grid grid-cols-12 gap-3 items-end bg-gray-50/50">
            <div className="col-span-3"><label className={lbl}>Reason</label><input value={form.reason} onChange={e => setForm(f => ({ ...f, reason: e.target.value }))} className={inp} placeholder="Timing difference" /></div>
            <div className="col-span-2"><label className={lbl}>Reference</label><input value={form.reference} onChange={e => setForm(f => ({ ...f, reference: e.target.value }))} className={inp} placeholder="MEMO-2026-001" /></div>
            <div className="col-span-2"><label className={lbl}>Amount</label><input type="number" step="0.01" value={form.amount} onChange={e => setForm(f => ({ ...f, amount: e.target.value }))} className={inp} /></div>
            <div className="col-span-4"><label className={lbl}>Remarks</label><input value={form.remarks} onChange={e => setForm(f => ({ ...f, remarks: e.target.value }))} className={inp} placeholder="Why the books and the form differ" /></div>
            <div className="col-span-1"><button onClick={handleAddItem} disabled={busy !== null} className="w-full bg-gray-900 text-white px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-40">Add</button></div>
          </div>
        ) : (
          <div className="border-t border-gray-100 px-4 py-3 text-xs text-gray-400">
            {artifact
              ? `The ${formCode} artifact for this period is ${STATUS_LABELS[artifact.status].toLowerCase()}; its working paper and reconciling items are frozen.`
              : `Generate the ${formCode} working paper before recording a reconciling item against it.`}
          </div>
        )}
      </div>
    </div>
  )
}
