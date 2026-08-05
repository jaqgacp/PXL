import { useState, useEffect, useCallback, useMemo } from 'react'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { downloadFilingArtifactExport } from '@/lib/filingExport'

type TaxKind = 'output_vat' | 'input_vat'

type Row = {
  key: string
  taxKind: TaxKind
  counterpartyId: string | null
  tin: string
  name: string
  taxableBase: number
  vat: number
  documentCount: number
}

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

/**
 * SLSP — Summary List of Sales and Purchases.
 *
 * This screen is a **filing surface**: every figure on it comes from the SLSP
 * filing artifact's working paper, which reads the posted tax ledger and groups
 * by the dimensions the artifact declares (`tax_kind`, `counterparty`). It
 * computes nothing.
 *
 * It used to be the last compliance screen off the governed pipeline. It was
 * **monthly** while the artifact and the BIR attachment are **quarterly**, it
 * summed its sales side in the browser from `vw_output_vat_review` with
 * `reduce`, and it read `vw_slp_export` for purchases — so the attachment could
 * disagree with the 2550Q it is filed beside, and nothing would say so.
 *
 * The monthly review question — "what did we sell this month?" — has not been
 * removed; it belongs to the **review surfaces** that already answer it, the
 * SLS and SLP registers. Review reads source data by design. Filing reads the
 * artifact. They are different stages of one pipeline, not competing
 * implementations.
 */
export default function SLSPExportPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [tab, setTab] = useState<TaxKind>('output_vat')
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState<'generate' | 'final' | 'export' | null>(null)
  const [rows, setRows] = useState<Row[]>([])
  const [artifact, setArtifact] = useState<Artifact | null>(null)
  const { dateFrom, dateTo } = quarterDates(year, quarter)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data, error }, { data: artifactRow }] = await Promise.all([
      supabase.rpc('fn_filing_working_paper', {
        p_company_id: companyId,
        p_form_code: 'SLSP',
        p_year: year,
        p_period: quarter,
      }),
      supabase.from('filing_artifacts').select('id,status,generated_at,total_tax_base,total_tax_amount')
        .eq('company_id', companyId).eq('form_code', 'SLSP')
        .eq('period_year', year).eq('period_number', quarter).maybeSingle(),
    ])
    setLoading(false)
    if (error) { alert('Cannot load the SLSP.\nReason: ' + error.message); return }
    setArtifact((artifactRow as Artifact | null) ?? null)

    const lines = (data || []) as {
      tax_kind: string; counterparty_id: string | null; counterparty_tin: string | null
      counterparty_name: string | null; tax_base: number; tax_amount: number; document_count: number
    }[]

    setRows(lines.map((r, i) => ({
      key: `${r.tax_kind}-${r.counterparty_tin ?? 'unknown'}-${i}`,
      taxKind: r.tax_kind as TaxKind,
      counterpartyId: r.counterparty_id,
      tin: r.counterparty_tin || '',
      name: r.counterparty_name || 'Unknown',
      taxableBase: Number(r.tax_base),
      vat: Number(r.tax_amount),
      documentCount: Number(r.document_count),
    })))
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const visible = useMemo(() => rows.filter(r => r.taxKind === tab), [rows, tab])
  const totalBase = visible.reduce((s, r) => s + r.taxableBase, 0)
  const totalVat = visible.reduce((s, r) => s + r.vat, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)
  const isSales = tab === 'output_vat'

  // Generating writes the artifact and its working paper from the posted tax
  // ledger. The screen states no figure of its own, so there is nothing to save.
  const handleGenerate = async () => {
    if (!companyId) return
    setBusy('generate')
    const { data, error } = await supabase.rpc('fn_generate_filing_artifact', {
      p_company_id: companyId, p_form_code: 'SLSP', p_year: year, p_period: quarter,
    })
    setBusy(null)
    if (error) { alert('Cannot generate the SLSP.\nReason: ' + error.message); return }
    await load()
    const r = data as { line_count: number; total_tax_amount: number; is_reconciled: boolean }
    alert(
      `Generated from the posted VAT ledger.\n` +
      `Counterparty lines: ${r.line_count}\n` +
      `VAT listed: ${fmt(Number(r.total_tax_amount))}` +
      (r.is_reconciled ? '' : '\n\nWARNING: the VAT ledger does not tie to the General Ledger for this quarter. This list cannot be marked final until it does.')
    )
  }

  // Marking it final is the claim that this list IS the ledger for the quarter.
  // The database refuses the claim while the two disagree.
  const handleMarkFinal = async () => {
    if (!artifact) return
    setBusy('final')
    const { error } = await supabase.from('filing_artifacts').update({ status: 'final' }).eq('id', artifact.id)
    setBusy(null)
    if (error) { alert('Cannot mark the SLSP final.\nReason: ' + error.message); return }
    await load()
  }

  // One export for the whole attachment. SLSP is filed as a single combined
  // list carrying its `tax_kind` column, so exporting per tab would be a second
  // shape of the same artifact — the browser deciding what the BIR receives.
  const handleExport = async () => {
    if (!companyId) return
    setBusy('export')
    const result = await downloadFilingArtifactExport({
      companyId, formCode: 'SLSP', year, period: quarter,
    })
    setBusy(null)
    if (!result.ok) { alert('Cannot export the SLSP.\nReason: ' + result.message); return }
    alert(`Exported ${result.rows} counterparty row${result.rows === 1 ? '' : 's'} — sales and purchases — for Q${quarter} ${year}.`)
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">SLSP — Summary List of Sales and Purchases</h1>
          <p className="text-sm text-gray-500 mt-0.5">Quarterly BIR attachment, generated from the posted VAT ledger</p>
        </div>
        <div className="flex gap-2">
          <button onClick={handleGenerate} disabled={busy !== null || !companyId} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'generate' ? 'Generating...' : '⚡ Generate'}</button>
          <button onClick={handleMarkFinal} disabled={busy !== null || !artifact || artifact.status !== 'draft'} title={artifact ? undefined : 'Generate the list first'} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'final' ? 'Marking...' : 'Mark Final'}</button>
          <button onClick={handleExport} disabled={busy !== null || !artifact || artifact.status === 'draft'} title={!artifact || artifact.status === 'draft' ? 'Mark the list final before exporting it' : 'Download the filing artifact — sales and purchases in one file'} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-40">{busy === 'export' ? 'Exporting...' : '↓ Export CSV'}</button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <select value={quarter} onChange={e => setQuarter(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>
        <div className="flex border border-gray-200 rounded-md overflow-hidden">
          <button onClick={() => setTab('output_vat')} className={`px-4 py-1.5 text-sm font-medium ${isSales ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>SLS — Sales</button>
          <button onClick={() => setTab('input_vat')} className={`px-4 py-1.5 text-sm font-medium ${!isSales ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>SLP — Purchases</button>
        </div>
        <div className="flex items-center gap-2 text-xs text-gray-500 ml-auto">
          <span className="uppercase tracking-wide font-semibold text-gray-400">Filing artifact</span>
          {artifact ? (
            <>
              <StatusBadge status={artifact.status} />
              <span className="font-mono tabular-nums">{fmt(Number(artifact.total_tax_amount))} VAT</span>
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
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">{isSales ? 'Customer TIN' : 'Supplier TIN'}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Registered Name</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Documents</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">{isSales ? 'Output VAT' : 'Input VAT'}</th>
              </tr>
            </thead>
            <tbody>
              {visible.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : `No ${isSales ? 'sales' : 'purchases'} in the posted VAT ledger for Q${quarter} ${year}.`}</td></tr>
              ) : visible.map(r => (
                <tr key={r.key} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{r.tin || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-700">
                    {r.counterpartyId ? (
                      <ReportTraceLink
                        companyId={companyId}
                        reportFamily="tax"
                        filters={{ tax_kind: r.taxKind, counterparty_id: r.counterpartyId, date_from: dateFrom, date_to: dateTo }}
                        title="Open the accounting sources included for this counterparty"
                      >
                        {r.name}
                      </ReportTraceLink>
                    ) : r.name}
                  </td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-500">{r.documentCount}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.taxableBase)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.vat)}</td>
                </tr>
              ))}
            </tbody>
            {visible.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr>
                  <td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {visible.length} {isSales ? 'customer' : 'supplier'}{visible.length !== 1 ? 's' : ''}</td>
                  <td />
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalBase)}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalVat)}</td>
                </tr>
              </tfoot>
            )}
          </table>
        )}
      </div>
    </div>
  )
}
