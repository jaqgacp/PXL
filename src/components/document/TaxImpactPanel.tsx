import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { AmountCell } from '@/components/ui/shared'

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
}: {
  sourceDocType: string
  sourceDocId?: string | null
  /** Draft preview shown when no posted ledger rows exist yet. */
  fallbackLabel?: string
  fallbackBase?: number
  fallbackRate?: number
  fallbackAmount?: number
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

  return (
    <div className="space-y-3">
      {loading ? (
        <div className="text-sm text-gray-400">Loading tax impact…</div>
      ) : rows.length === 0 && !hasFallback ? (
        <div className="text-sm text-gray-500">No VAT ledger rows for this document.</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Tax Type', 'ATC', 'VAT Code', 'Tax Base', 'Rate', 'Amount', 'Recoverable', 'Payable', 'Tax Ledger Entry', 'BIR Return', 'Status', 'Source Rule'].map((h, i) => (
                  <th key={h} className={`px-2 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${i >= 3 && i <= 7 ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {showFallback ? (
                <tr>
                  <td className="px-2 py-2 text-xs text-gray-800 whitespace-nowrap">{fallbackLabel}</td>
                  <td className="px-2 py-2 text-xs text-gray-400">—</td>
                  <td className="px-2 py-2 text-xs text-gray-400">—</td>
                  <td className="px-2 py-2 text-xs text-right"><AmountCell amount={fallbackBase ?? 0} /></td>
                  <td className="px-2 py-2 text-xs text-right text-gray-500">{fallbackRate != null ? `${fallbackRate}%` : '—'}</td>
                  <td className="px-2 py-2 text-xs text-right font-semibold"><AmountCell amount={fallbackAmount ?? 0} /></td>
                  <td className="px-2 py-2 text-xs text-right text-gray-400">—</td>
                  <td className="px-2 py-2 text-xs text-right"><AmountCell amount={fallbackAmount ?? 0} /></td>
                  <td className="px-2 py-2 text-xs text-gray-400">Not posted</td>
                  <td className="px-2 py-2 text-xs text-gray-400">Not assigned</td>
                  <td className="px-2 py-2 text-xs"><span className="px-1.5 py-0.5 rounded bg-gray-100 text-gray-500 text-[11px]">Estimated</span></td>
                  <td className="px-2 py-2 text-xs text-gray-500 whitespace-nowrap">Draft tax calculation</td>
                </tr>
              ) : rows.map(r => {
                const atc = relatedValue(r.atc_codes)?.code
                const vatCode = relatedValue(r.vat_codes)?.vat_code
                const recoverable = r.tax_kind === 'input_vat' || r.tax_kind === 'cwt_receivable'
                const payable = r.tax_kind === 'output_vat' || r.tax_kind === 'percentage_tax' || r.tax_kind === 'ewt_payable'
                return (
                  <tr key={r.id}>
                    <td className="px-2 py-2 text-xs text-gray-800 whitespace-nowrap">{KIND_LABEL[r.tax_kind] ?? r.tax_kind}</td>
                    <td className="px-2 py-2 text-xs font-mono text-gray-600">{atc ?? '—'}</td>
                    <td className="px-2 py-2 text-xs font-mono text-gray-600">{vatCode ?? '—'}</td>
                    <td className="px-2 py-2 text-xs text-right"><AmountCell amount={Number(r.tax_base)} /></td>
                    <td className="px-2 py-2 text-xs text-right text-gray-500">{r.tax_rate != null ? `${Number(r.tax_rate)}%` : '—'}</td>
                    <td className="px-2 py-2 text-xs text-right font-semibold"><AmountCell amount={Number(r.tax_amount)} /></td>
                    <td className="px-2 py-2 text-xs text-right">{recoverable ? <AmountCell amount={Number(r.tax_amount)} /> : '—'}</td>
                    <td className="px-2 py-2 text-xs text-right">{payable ? <AmountCell amount={Number(r.tax_amount)} /> : '—'}</td>
                    <td className="px-2 py-2 text-[11px] font-mono text-gray-500" title={r.id}>{r.id.slice(0, 8)}…</td>
                    <td className="px-2 py-2 text-xs text-gray-400 whitespace-nowrap">Not assigned</td>
                    <td className="px-2 py-2 text-xs">
                      {r.is_reversal
                        ? <span className="px-1.5 py-0.5 rounded bg-red-50 text-red-700 text-[11px]">Reversal</span>
                        : <span className="px-1.5 py-0.5 rounded bg-blue-50 text-blue-700 text-[11px]">{r.filing_status}</span>}
                    </td>
                    <td className="px-2 py-2 text-xs text-gray-500 whitespace-nowrap">Posting engine · {r.tax_kind}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
      <p className="text-xs text-gray-400 pt-1 border-t border-gray-100">
        VAT rows only. Expected withholding (EWT/CWT with ATC) is deferred here until the VAT-exclusive
        withholding base is corrected (PXL-AUD-031/032/033) — see the Financial Summary for the informational CWT figure.
      </p>
    </div>
  )
}

export default TaxImpactPanel
