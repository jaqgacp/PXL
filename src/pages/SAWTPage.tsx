import { useState, useEffect, useCallback } from 'react'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { downloadFilingArtifactExport } from '@/lib/filingExport'

type Agg = { customer_key: string; customer_id: string | null; customer_name: string; customer_tin: string; atc_code: string; payments: number; cwt: number }

type ArtifactStatus = 'draft' | 'final' | 'filed'
type Artifact = { id: string; status: ArtifactStatus; generated_at: string; total_tax_base: number; total_tax_amount: number }

const STATUS_LABELS: Record<ArtifactStatus, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }

function StatusBadge({ status }: { status: ArtifactStatus }) {
  const cls: Record<ArtifactStatus, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
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

export default function SAWTPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<'generate' | 'final' | 'export' | null>(null)
  const [rows, setRows] = useState<Agg[]>([])
  const [artifact, setArtifact] = useState<Artifact | null>(null)
  const { dateFrom, dateTo } = quarterDates(year, quarter)

  // The alphalist is the SAWT filing artifact's working paper, grouped per payor
  // and ATC by the same reader every other BIR form uses. It used to be summed
  // here in the browser from a review view; an alphalist computed on the client
  // is not an alphalist computed from the books.
  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data, error }, { data: artifactRow }] = await Promise.all([
      supabase.rpc('fn_filing_working_paper', {
        p_company_id: companyId,
        p_form_code: 'SAWT',
        p_year: year,
        p_period: quarter,
      }),
      supabase.from('filing_artifacts').select('id,status,generated_at,total_tax_base,total_tax_amount')
        .eq('company_id', companyId).eq('form_code', 'SAWT')
        .eq('period_year', year).eq('period_number', quarter).maybeSingle(),
    ])
    setLoading(false)
    if (error) { alert('Cannot load the SAWT.\nReason: ' + error.message); return }
    setArtifact((artifactRow as Artifact | null) ?? null)

    const lines = (data || []) as {
      counterparty_id: string | null; counterparty_tin: string | null
      counterparty_name: string | null; atc_code: string | null
      tax_base: number; tax_amount: number
    }[]

    setRows(lines.map((r, i) => ({
      customer_key: `${r.counterparty_tin ?? 'unknown'}-${r.atc_code ?? 'none'}-${i}`,
      customer_id: r.counterparty_id,
      customer_name: r.counterparty_name || 'Unknown',
      customer_tin: r.counterparty_tin || '',
      atc_code: r.atc_code || '',
      payments: Number(r.tax_base),
      cwt: Number(r.tax_amount),
    })))
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const totalPayments = rows.reduce((s, r) => s + r.payments, 0)
  const totalCwt = rows.reduce((s, r) => s + r.cwt, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  // Generating writes the artifact and its working paper from the posted
  // ledger. The screen states no figure of its own, so there is nothing to save.
  const handleGenerate = async () => {
    if (!companyId) return
    setBusy('generate')
    const { data, error } = await supabase.rpc('fn_generate_filing_artifact', {
      p_company_id: companyId, p_form_code: 'SAWT', p_year: year, p_period: quarter,
    })
    setBusy(null)
    if (error) { alert('Cannot generate the SAWT.\nReason: ' + error.message); return }
    await load()
    const r = data as { line_count: number; total_tax_amount: number; is_reconciled: boolean }
    alert(
      `Generated from the posted withholding ledger.\n` +
      `Payors listed: ${r.line_count}\n` +
      `CWT withheld: ${fmt(Number(r.total_tax_amount))}` +
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
    if (error) { alert('Cannot mark the SAWT final.\nReason: ' + error.message); return }
    await load()
  }

  // The download is a consumer of the filing artifact: the RPC evidences the
  // exact bytes into report_snapshots and this hands back that same content.
  // It used to call the legacy withholding snapshot, which rebuilt the alphalist
  // from a source view and then reformatted it here.
  const handleExport = async () => {
    if (!companyId) return
    setBusy('export')
    const result = await downloadFilingArtifactExport({
      companyId, formCode: 'SAWT', year, period: quarter,
    })
    setBusy(null)
    if (!result.ok) { alert('Cannot export the SAWT.\nReason: ' + result.message); return }
    alert(`Exported ${result.rows} payor row${result.rows === 1 ? '' : 's'} for Q${quarter} ${year}.`)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">SAWT — Summary Alphalist of Withholding Tax</h1>
          <p className="text-sm text-gray-500 mt-0.5">Per-customer CWT withheld on collections — attachment to quarterly/annual ITR</p>
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

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer TIN</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Customer Name</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">ATC</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Income Payments</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">CWT Withheld</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No CWT-bearing collections in this period.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.customer_key} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.customer_tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">
                    {r.customer_id ? (
                      <ReportTraceLink
                        companyId={companyId}
                        reportFamily="tax"
                        filters={{ tax_kind: 'cwt_receivable', counterparty_id: r.customer_id, date_from: dateFrom, date_to: dateTo }}
                        title="Open the accounting sources included for this payer"
                      >
                        {r.customer_name}
                      </ReportTraceLink>
                    ) : r.customer_name}
                  </td>
                  <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{r.atc_code || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.payments)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.cwt)}</td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={3} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {rows.length} line{rows.length !== 1 ? 's' : ''}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalPayments)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalCwt)}</td></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
