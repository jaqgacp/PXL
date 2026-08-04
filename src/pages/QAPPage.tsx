import { useState, useEffect, useCallback } from 'react'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { downloadFilingArtifactExport } from '@/lib/filingExport'

type WorkingPaperRow = {
  counterparty_id: string | null
  counterparty_tin: string | null
  counterparty_name: string | null
  atc_code: string | null
  tax_rate: number | null
  tax_base: number
  tax_amount: number
  document_count: number
}

type Row = {
  key: string
  supplier_id: string | null
  supplier_name: string
  supplier_tin: string
  atc_code: string
  nature_of_payment: string
  tax_rate: number
  tax_base: number
  tax_withheld: number
}

type ArtifactStatus = 'draft' | 'final' | 'filed'
type Artifact = { id: string; status: ArtifactStatus; generated_at: string; total_tax_base: number; total_tax_amount: number }

type ReconRow = {
  supplier_name: string | null
  supplier_tin: string | null
  atc_code: string | null
  qap_tax_withheld: number
  form2307_tax_withheld: number
  withheld_variance: number
  form2307_status: string | null
  is_reconciled: boolean
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12] }
const quarterDates = (year: number, quarter: number) => {
  const months = QUARTERS[quarter]
  return {
    dateFrom: `${year}-${String(months[0]).padStart(2, '0')}-01`,
    dateTo: new Date(year, months[2], 0).toISOString().split('T')[0],
  }
}

const STATUS_LABELS: Record<ArtifactStatus, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }

function StatusBadge({ status }: { status: ArtifactStatus }) {
  const cls: Record<ArtifactStatus, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
}

export default function QAPPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<'generate' | 'final' | 'export' | null>(null)
  const [rows, setRows] = useState<Row[]>([])
  const [artifact, setArtifact] = useState<Artifact | null>(null)
  const [recon, setRecon] = useState<ReconRow[]>([])
  const { dateFrom, dateTo } = quarterDates(year, quarter)

  // The alphalist is the QAP filing artifact's working paper, grouped per payee
  // and ATC by the same reader every other BIR form uses. It used to be summed
  // here in the browser from `vw_ewt_summary_ap`, which silently dropped
  // reversal counter-rows — so a voided withholding left the QAP disagreeing
  // with the 1601EQ it is attached to, and with the General Ledger, invisibly.
  //
  // The nature of payment is the governed description of the ATC; it is looked
  // up for display, never computed.
  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: paper, error }, { data: atcs }, { data: artifactRow }, { data: reconRows }] = await Promise.all([
      supabase.rpc('fn_filing_working_paper', {
        p_company_id: companyId, p_form_code: 'QAP', p_year: year, p_period: quarter,
      }),
      supabase.from('atc_codes').select('code,description').eq('is_active', true),
      supabase.from('filing_artifacts').select('id,status,generated_at,total_tax_base,total_tax_amount')
        .eq('company_id', companyId).eq('form_code', 'QAP')
        .eq('period_year', year).eq('period_number', quarter).maybeSingle(),
      supabase.rpc('fn_qap_2307_reconciliation', {
        p_company_id: companyId, p_tax_year: year, p_tax_quarter: quarter,
      }),
    ])
    setLoading(false)
    if (error) { alert('Cannot load the QAP.\nReason: ' + error.message); return }

    const nature = new Map((atcs || []).map(a => [a.code as string, (a.description as string) || '']))
    setRows(((paper || []) as WorkingPaperRow[]).map((r, i) => ({
      key: `${r.counterparty_tin ?? 'unknown'}-${r.atc_code ?? 'none'}-${i}`,
      supplier_id: r.counterparty_id,
      supplier_name: r.counterparty_name || 'Unknown',
      supplier_tin: r.counterparty_tin || '',
      atc_code: r.atc_code || '',
      nature_of_payment: nature.get(r.atc_code || '') || '',
      tax_rate: Number(r.tax_rate || 0),
      tax_base: Number(r.tax_base),
      tax_withheld: Number(r.tax_amount),
    })))
    setArtifact((artifactRow as Artifact | null) ?? null)
    setRecon((reconRows || []) as ReconRow[])
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const totalBase = rows.reduce((s, r) => s + r.tax_base, 0)
  const totalWithheld = rows.reduce((s, r) => s + r.tax_withheld, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)
  const disagreements = recon.filter(r => !r.is_reconciled)
  const qapTraceFilters = (row: Row) => ({
    tax_kind: 'ewt_payable',
    counterparty_id: row.supplier_id || undefined,
    atc_code: row.atc_code || undefined,
    date_from: dateFrom,
    date_to: dateTo,
  })

  // Generating writes the artifact and its working paper from the posted ledger.
  // The screen states no figure of its own, so there is nothing here to save.
  const handleGenerate = async () => {
    if (!companyId) return
    setBusy('generate')
    const { data, error } = await supabase.rpc('fn_generate_filing_artifact', {
      p_company_id: companyId, p_form_code: 'QAP', p_year: year, p_period: quarter,
    })
    setBusy(null)
    if (error) { alert('Cannot generate the QAP.\nReason: ' + error.message); return }
    await load()
    const r = data as { line_count: number; total_tax_amount: number; is_reconciled: boolean }
    alert(
      `Generated from the posted withholding ledger.\n` +
      `Payees listed: ${r.line_count}\n` +
      `Tax withheld: ${fmt(Number(r.total_tax_amount))}` +
      (r.is_reconciled ? '' : '\n\nWARNING: the withholding ledger does not tie to the General Ledger for this quarter. This alphalist cannot be marked final until it does.')
    )
  }

  // Marking it final is the claim that this alphalist IS the ledger for the
  // quarter. The database refuses the claim while the two disagree.
  const handleMarkFinal = async () => {
    if (!artifact) return
    setBusy('final')
    const { error } = await supabase.from('filing_artifacts').update({ status: 'final' }).eq('id', artifact.id)
    setBusy(null)
    if (error) { alert('Cannot mark the QAP final.\nReason: ' + error.message); return }
    await load()
  }

  // The download is a consumer of the artifact: the RPC evidences the exact
  // bytes into report_snapshots and this hands back that same content.
  const handleExport = async () => {
    if (!companyId) return
    setBusy('export')
    const result = await downloadFilingArtifactExport({
      companyId, formCode: 'QAP', year, period: quarter,
    })
    setBusy(null)
    if (!result.ok) { alert('Cannot export the QAP.\nReason: ' + result.message); return }
    alert(`Exported ${result.rows} payee row${result.rows === 1 ? '' : 's'} for Q${quarter} ${year}.`)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">QAP — Quarterly Alphalist of Payees</h1>
          <p className="text-sm text-gray-500 mt-0.5">Per-supplier EWT summary — attachment to 1601EQ filing</p>
        </div>
        <div className="flex gap-2">
          <button onClick={handleGenerate} disabled={busy !== null || !companyId} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'generate' ? 'Generating...' : '⚡ Generate'}</button>
          <button onClick={handleMarkFinal} disabled={busy !== null || !artifact || artifact.status !== 'draft'} title={artifact ? undefined : 'Generate the alphalist first'} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'final' ? 'Marking...' : 'Mark Final'}</button>
          <button onClick={handleExport} disabled={busy !== null || !artifact || artifact.status === 'draft'} title={!artifact || artifact.status === 'draft' ? 'Mark the alphalist final before exporting it' : 'Download the filing artifact'} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'export' ? 'Exporting...' : '↓ Export CSV'}</button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <select value={quarter} onChange={e => setQuarter(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>
        <div className="flex items-center gap-2 text-xs text-gray-500 ml-auto">
          <span className="uppercase tracking-wide font-semibold text-gray-400">Filing artifact</span>
          {artifact ? (
            <>
              <StatusBadge status={artifact.status} />
              <span className="font-mono tabular-nums">{fmt(Number(artifact.total_tax_amount))} withheld</span>
              <span>· generated {new Date(artifact.generated_at).toLocaleString('en-PH')}</span>
            </>
          ) : (
            <span className="text-gray-400">Not generated for this quarter — the figures below are the working paper it would carry.</span>
          )}
        </div>
      </div>

      {/* The alphalist against the certificates actually issued. Both sides read
          governed sources: the QAP side is this artifact's working paper. */}
      {recon.length > 0 && (
        <div className={`border rounded-lg px-4 py-3 text-sm ${disagreements.length === 0 ? 'bg-green-50 border-green-200 text-green-800' : 'bg-amber-50 border-amber-200 text-amber-900'}`}>
          {disagreements.length === 0 ? (
            <span>All {recon.length} payee/ATC row{recon.length === 1 ? '' : 's'} agree with the Form 2307 certificates issued for this quarter.</span>
          ) : (
            <div className="space-y-1">
              <p className="font-medium">{disagreements.length} of {recon.length} payee/ATC rows do not agree with the Form 2307 certificates issued.</p>
              <ul className="text-xs space-y-0.5">
                {disagreements.slice(0, 8).map((d, i) => (
                  <li key={`${d.supplier_tin}-${d.atc_code}-${i}`} className="font-mono tabular-nums">
                    {d.supplier_name || 'Unknown'} · {d.atc_code || 'no ATC'} — alphalist {fmt(Number(d.qap_tax_withheld))}, certificates {fmt(Number(d.form2307_tax_withheld))} ({fmt(Number(d.withheld_variance))})
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Registered Name</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">ATC</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Nature</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rate</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Income Payments</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Withheld</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={7} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No EWT payees in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.key} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.supplier_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">
                    {r.supplier_id ? (
                      <ReportTraceLink
                        companyId={companyId || ''}
                        reportFamily="tax"
                        filters={qapTraceFilters(r)}
                        title="Open the accounting sources included for this QAP payee/ATC row"
                      >
                        {r.supplier_name}
                      </ReportTraceLink>
                    ) : r.supplier_name}
                  </td>
                  <td className="px-4 py-2.5 text-gray-500 font-mono">{r.atc_code || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-500">{r.nature_of_payment || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.tax_rate)}%</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.tax_base)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">
                    {r.supplier_id ? (
                      <ReportTraceLink
                        companyId={companyId || ''}
                        reportFamily="tax"
                        filters={qapTraceFilters(r)}
                        title="Open the tax-ledger sources for this QAP withholding amount"
                      >
                        {fmt(r.tax_withheld)}
                      </ReportTraceLink>
                    ) : fmt(r.tax_withheld)}
                  </td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={5} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} payee/ATC row{rows.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalBase)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalWithheld)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
