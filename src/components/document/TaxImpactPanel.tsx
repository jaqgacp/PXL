import { useEffect, useState, type ReactNode } from 'react'
import { supabase } from '@/lib/supabase'
import { AmountCell, DateCell } from '@/components/ui/shared'
import { ErpSectionHeader, ERP_EMPTY_CELL, ERP_TABLE, ERP_THEAD, ERP_TH, ERP_TD, ERP_TD_NUM } from '@/components/document/ErpSection'

// ─────────────────────────────────────────────────────────────
// TaxImpactPanel — per-document tax ledger view (Standard
// Transaction Workspace §10). SCOPE (DEC-015): VAT kinds only
// (output_vat / input_vat / percentage_tax), which are
// server-authoritative and correct today. Withholding rows
// (EWT/CWT) are intentionally DEFERRED because their correct
// VAT-exclusive base depends on the paused findings
// PXL-AUD-031/032/033 — rendering them now would show defective
// data confidently (§10 correctness gate). Reads tax_detail_entries.
// ─────────────────────────────────────────────────────────────

const VAT_KINDS = ['output_vat', 'input_vat', 'percentage_tax'] as const
const KIND_LABEL: Record<string, string> = {
  output_vat: 'Output VAT',
  input_vat: 'Input VAT',
  percentage_tax: 'Percentage Tax',
}

type TaxRow = {
  id: string
  tax_kind: string
  atc_code_id: string | null
  vat_code_id: string | null
  tax_base: number
  tax_rate: number | null
  tax_amount: number
  is_reversal: boolean
  filing_status: string
  atc_codes?: { code: string } | { code: string }[] | null
  vat_codes?: { vat_code: string } | { vat_code: string }[] | null
}

const relatedValue = <T,>(value: T | T[] | null | undefined): T | null =>
  Array.isArray(value) ? (value[0] ?? null) : (value ?? null)

export function TaxImpactPanel({
  sourceDocType,
  sourceDocId,
  fallbackLabel = 'Output VAT',
  fallbackBase,
  fallbackRate,
  fallbackAmount,
  expectedCwt = 0,
  actualCwt = 0,
  customerTin,
  customerBranch,
  documentNumber,
  documentDate,
  branchName,
  vatClassification,
}: {
  sourceDocType: string
  sourceDocId?: string | null
  /** Draft preview shown when no posted ledger rows exist yet. */
  fallbackLabel?: string
  fallbackBase?: number
  fallbackRate?: number
  fallbackAmount?: number
  expectedCwt?: number
  actualCwt?: number
  customerTin?: string | null
  customerBranch?: string | null
  documentNumber?: string | null
  documentDate?: string | null
  branchName?: string | null
  vatClassification?: string | null
}) {
  const [rows, setRows] = useState<TaxRow[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    const load = async () => {
      if (!sourceDocId) { setRows([]); setLoading(false); return }
      setLoading(true)
      const { data } = await supabase
        .from('tax_detail_entries')
        .select('id,tax_kind,atc_code_id,vat_code_id,tax_base,tax_rate,tax_amount,is_reversal,filing_status,atc_codes(code),vat_codes(vat_code)')
        .eq('source_doc_type', sourceDocType)
        .eq('source_doc_id', sourceDocId)
        .order('created_at')
      if (cancelled) return
      const vatRows = (data ?? []).filter(r => VAT_KINDS.includes(r.tax_kind as typeof VAT_KINDS[number]))
      setRows(vatRows as unknown as TaxRow[])
      setLoading(false)
    }
    load()
    return () => { cancelled = true }
  }, [sourceDocType, sourceDocId])

  const hasFallback = (fallbackAmount ?? 0) > 0 || (fallbackBase ?? 0) > 0
  const showFallback = !loading && rows.length === 0 && hasFallback
  const showExpectedCwt = Math.abs(expectedCwt) > 0.005
  const showActualCwt = Math.abs(actualCwt) > 0.005
  const taxContext: Array<{ label: string; value: ReactNode; title?: string }> = [
    { label: 'Customer TIN', value: customerTin, title: customerTin || undefined },
    { label: 'TIN Branch', value: customerBranch, title: customerBranch || undefined },
    { label: 'Document Number', value: documentNumber, title: documentNumber || undefined },
    { label: 'Document Date', value: documentDate ? <DateCell date={documentDate} /> : null, title: documentDate || undefined },
    { label: 'Branch', value: branchName, title: branchName || undefined },
    { label: 'VAT Classification', value: vatClassification, title: vatClassification || undefined },
  ].filter(field => field.value != null && field.value !== '')

  return (
    <div className="pxl-transaction-card pxl-transaction-card--raised p-3 space-y-2">
      <ErpSectionHeader
        title="Tax Impact"
        description="Transaction-specific tax effect and compliance linkage."
        className="pb-2 border-b border-gray-100"
      />
      {taxContext.length > 0 && (
        <div className="grid grid-cols-2 gap-x-3 gap-y-2 rounded border border-gray-200 bg-gray-50 px-3 py-2 lg:grid-cols-6">
          {taxContext.map(field => (
            <div key={field.label} className="min-w-0">
              <div className="text-[10px] font-medium uppercase tracking-wide text-gray-400">{field.label}</div>
              <div className="mt-0.5 truncate text-xs text-gray-700" title={field.title}>{field.value}</div>
            </div>
          ))}
        </div>
      )}
      {loading ? (
        <div className="px-3 py-4 text-center text-xs text-gray-400">Loading tax impact…</div>
      ) : rows.length === 0 && !hasFallback && !showExpectedCwt && !showActualCwt ? (
        <div className={ERP_EMPTY_CELL}>No VAT ledger rows for this document.</div>
      ) : (
        <>
        <div className="overflow-x-auto border border-gray-200 rounded">
          <table className={ERP_TABLE}>
            <thead className={ERP_THEAD}>
              <tr>
                {['Tax Type', 'Tax Code', 'ATC', 'Tax Base', 'Rate', 'Tax Amount', 'Tax Treatment', 'Ledger Status', 'Return or Report', 'Source Rule', 'Related Certificate'].map((h, i) => (
                  <th key={h} className={`${ERP_TH} ${i >= 3 && i <= 5 ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {!showFallback && rows.length === 0 && (
                <tr><td colSpan={11} className={ERP_EMPTY_CELL}>No authoritative VAT ledger rows for this document.</td></tr>
              )}
              {showFallback && (
                <tr>
                  <td className={`${ERP_TD} text-gray-800 whitespace-nowrap`}>{fallbackLabel}</td>
                  <td className={`${ERP_TD} text-gray-400`}>—</td>
                  <td className={`${ERP_TD} text-gray-400`}>—</td>
                  <td className={ERP_TD_NUM}><AmountCell amount={fallbackBase ?? 0} /></td>
                  <td className={`${ERP_TD_NUM} text-gray-500`}>{fallbackRate != null ? `${fallbackRate}%` : '—'}</td>
                  <td className={`${ERP_TD_NUM} font-semibold text-gray-900`}><AmountCell amount={fallbackAmount ?? 0} /></td>
                  <td className={`${ERP_TD} text-gray-600`}>Output VAT payable</td>
                  <td className={ERP_TD}><span className="pxl-status-badge bg-gray-100 px-1.5 py-0.5 text-gray-500">Posting Preview</span></td>
                  <td className={`${ERP_TD} text-gray-400`}>Not assigned</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>Draft tax calculation</td>
                  <td className={`${ERP_TD} text-gray-400`}>—</td>
                </tr>
              )}
              {rows.map(r => {
                const atc = relatedValue(r.atc_codes)?.code
                const vatCode = relatedValue(r.vat_codes)?.vat_code
                return (
                  <tr key={r.id}>
                    <td className={`${ERP_TD} text-gray-800 whitespace-nowrap`}>{KIND_LABEL[r.tax_kind] ?? r.tax_kind}</td>
                    <td className={`${ERP_TD} font-mono text-gray-600`}>{vatCode ?? '—'}</td>
                    <td className={`${ERP_TD} font-mono text-gray-600`}>{atc ?? '—'}</td>
                    <td className={ERP_TD_NUM}><AmountCell amount={Number(r.tax_base)} /></td>
                    <td className={`${ERP_TD_NUM} text-gray-500`}>{r.tax_rate != null ? `${Number(r.tax_rate)}%` : '—'}</td>
                    <td className={`${ERP_TD_NUM} font-semibold text-gray-900`}><AmountCell amount={Number(r.tax_amount)} /></td>
                    <td className={`${ERP_TD} text-gray-600 whitespace-nowrap`}>{r.tax_kind === 'input_vat' ? 'Recoverable' : 'Payable'}</td>
                    <td className={ERP_TD}>
                      {r.is_reversal
                        ? <span className="pxl-status-badge bg-red-50 px-1.5 py-0.5 text-red-700">Reversal</span>
                        : <details>
                            <summary className="cursor-pointer text-blue-700 hover:underline">{r.filing_status || 'Posted'}</summary>
                            <div className="mt-1 rounded bg-gray-50 p-2 text-[11px] text-gray-500">
                              Tax ledger entry: <span className="font-mono">{r.id}</span>
                            </div>
                          </details>}
                    </td>
                    <td className={`${ERP_TD} text-gray-400 whitespace-nowrap`}>Not assigned</td>
                    <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>Posting engine · {r.tax_kind}</td>
                    <td className={`${ERP_TD} text-gray-400`}>—</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        {(showExpectedCwt || showActualCwt) && (
          <div className="overflow-x-auto rounded border border-gray-200">
            <div className="border-b border-gray-100 bg-gray-50 px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500">
              Withholding Context
            </div>
            <table className={ERP_TABLE}>
              <thead className={ERP_THEAD}>
                <tr>
                  {['Withholding Type', 'Basis', 'Amount', 'Status', 'Recognition Source', 'Certificate'].map((h, i) => (
                    <th key={h} className={`${ERP_TH} ${i === 2 ? 'text-right' : 'text-left'}`}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {showExpectedCwt && (
                  <tr>
                    <td className={`${ERP_TD} text-gray-800 whitespace-nowrap`}>Expected CWT</td>
                    <td className={`${ERP_TD} text-gray-500`}>Customer withholding profile and invoice tax base</td>
                    <td className={`${ERP_TD_NUM} font-semibold text-gray-900`}><AmountCell amount={expectedCwt} /></td>
                    <td className={ERP_TD}><span className="pxl-status-badge bg-amber-50 px-1.5 py-0.5 text-amber-700">Informational</span></td>
                    <td className={`${ERP_TD} text-gray-500`}>Not recognized until governed receipt/application/certificate event</td>
                    <td className={`${ERP_TD} text-gray-400`}>Not received</td>
                  </tr>
                )}
                {showActualCwt && (
                  <tr>
                    <td className={`${ERP_TD} text-gray-800 whitespace-nowrap`}>Actual CWT Recognized</td>
                    <td className={`${ERP_TD} text-gray-500`}>Posted receipt application</td>
                    <td className={`${ERP_TD_NUM} font-semibold text-gray-900`}><AmountCell amount={actualCwt} /></td>
                    <td className={ERP_TD}><span className="pxl-status-badge bg-green-50 px-1.5 py-0.5 text-green-700">Recognized</span></td>
                    <td className={`${ERP_TD} text-gray-500`}>Receipt or payment application</td>
                    <td className={`${ERP_TD} text-gray-400`}>Not linked</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}
        </>
      )}
      <p className="text-xs text-gray-400 pt-1 border-t border-gray-100">
        Expected CWT is informational until receipt, payment application, or certificate recognition.
      </p>
    </div>
  )
}

export default TaxImpactPanel
