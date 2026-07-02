import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type ReconRow = {
  tax_kind: 'output_vat' | 'input_vat'
  ledger_tax_base: number
  ledger_tax_amount: number
  gl_account_id: string | null
  gl_account_code: string | null
  gl_account_name: string | null
  gl_amount: number | null
  variance: number
  is_reconciled: boolean
}

const KIND_LABELS: Record<ReconRow['tax_kind'], string> = { output_vat: 'Output VAT', input_vat: 'Input VAT' }
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function VATReconciliationPanel({ companyId, dateFrom, dateTo, returnOutputVat, returnInputVat }: {
  companyId: string
  dateFrom: string
  dateTo: string
  returnOutputVat: number
  returnInputVat: number
}) {
  const [rows, setRows] = useState<ReconRow[]>([])
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (!companyId || !dateFrom || !dateTo) return
    let cancelled = false
    const load = async () => {
      setLoading(true)
      const { data, error: err } = await supabase.rpc('fn_vat_gl_reconciliation', {
        p_company_id: companyId, p_date_from: dateFrom, p_date_to: dateTo,
      })
      if (cancelled) return
      setError(err ? err.message : '')
      setRows(err ? [] : ((data as ReconRow[]) || []))
      setLoading(false)
    }
    load()
    return () => { cancelled = true }
  }, [companyId, dateFrom, dateTo])

  const returnFigure = (kind: ReconRow['tax_kind']) => (kind === 'output_vat' ? returnOutputVat : returnInputVat)

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6 space-y-4">
      <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100">
        Tax Ledger / GL Reconciliation — {dateFrom} to {dateTo}
      </h2>
      {error ? (
        <p className="text-sm text-red-600">Cannot load reconciliation: {error}</p>
      ) : loading ? (
        <div className="space-y-2 animate-pulse">{[0, 1].map(i => <div key={i} className="h-3 bg-gray-100 rounded" />)}</div>
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-200">
              <th className="text-left py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax</th>
              <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Ledger</th>
              <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">GL Control Account</th>
              <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">This Return</th>
              <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(r => {
              const figureMatches = Math.abs(returnFigure(r.tax_kind) - r.ledger_tax_amount) <= 0.01
              const ok = r.is_reconciled && figureMatches
              return (
                <tr key={r.tax_kind} className="border-b border-gray-100">
                  <td className="py-2 font-medium text-gray-900">{KIND_LABELS[r.tax_kind]}</td>
                  <td className="py-2 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.ledger_tax_amount)}</td>
                  <td className="py-2 text-right font-mono tabular-nums text-gray-700">
                    {r.gl_account_id ? `${fmtNum(r.gl_amount ?? 0)} (${r.gl_account_code})` : 'Not configured'}
                  </td>
                  <td className="py-2 text-right font-mono tabular-nums text-gray-700">{fmtNum(returnFigure(r.tax_kind))}</td>
                  <td className="py-2 text-right">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${ok ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
                      {ok ? 'Reconciled' : !r.is_reconciled ? `GL variance ${fmtNum(r.variance)}` : 'Return ≠ tax ledger'}
                    </span>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
      <p className="text-xs text-gray-400">
        A return cannot be marked Final or Filed until the tax ledger reconciles to the GL VAT control accounts
        and the return's output/input VAT figures match the tax ledger for the period.
      </p>
    </div>
  )
}
