import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type IssuanceStatus = 'pending' | 'generated' | 'sent' | 'acknowledged'

type Issuance = {
  id: string
  bank_account_id: string
  period_year: number
  period_quarter: number
  gross_interest_income: number
  fwt_rate: number
  fwt_withheld: number
  certificate_number: string | null
  status: IssuanceStatus
  date_generated: string | null
  date_sent: string | null
  date_acknowledged: string | null
  bank_accounts?: { bank_name: string; account_number: string }
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1, 2, 3], 2: [4, 5, 6], 3: [7, 8, 9], 4: [10, 11, 12] }
const STATUS_LABELS: Record<IssuanceStatus, string> = { pending: 'Pending', generated: 'Generated', sent: 'Sent', acknowledged: 'Acknowledged' }
const STATUS_CLS: Record<IssuanceStatus, string> = { pending: 'bg-gray-100 text-gray-600', generated: 'bg-blue-50 text-blue-700', sent: 'bg-amber-50 text-amber-700', acknowledged: 'bg-green-50 text-green-700' }

export default function Form2306Page() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [issuances, setIssuances] = useState<Issuance[]>([])
  const [loading, setLoading] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [actionModal, setActionModal] = useState<{ issuance: Issuance; action: 'sent' | 'acknowledged' } | null>(null)
  const [actionDate, setActionDate] = useState(now.toISOString().split('T')[0])

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('form_2306_issuances').select('*,bank_accounts(bank_name,account_number)')
      .eq('company_id', companyId).eq('period_year', year).eq('period_quarter', quarter).order('created_at')
    setIssuances((data as Issuance[]) || [])
    setLoading(false)
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const generateBatch = async () => {
    if (!companyId) return
    setGenerating(true)
    const months = QUARTERS[quarter]
    const startDate = `${year}-${String(months[0]).padStart(2, '0')}-01`
    const endDate = new Date(year, months[months.length - 1], 0).toISOString().split('T')[0]

    const { data: adjData } = await supabase.from('bank_adjustments')
      .select('bank_account_id,amount').eq('company_id', companyId).eq('adjustment_type', 'interest_income').eq('status', 'posted')
      .gte('adjustment_date', startDate).lte('adjustment_date', endDate)

    if (!adjData || adjData.length === 0) { alert('No interest income adjustments found for this period.'); setGenerating(false); return }

    const byBank: Record<string, number> = {}
    for (const row of adjData as { bank_account_id: string; amount: number }[]) {
      byBank[row.bank_account_id] = (byBank[row.bank_account_id] || 0) + Number(row.amount)
    }

    for (const [bankAccountId, gross] of Object.entries(byBank)) {
      const fwt = gross * 0.20
      await supabase.from('form_2306_issuances').upsert({
        company_id: companyId, bank_account_id: bankAccountId, period_year: year, period_quarter: quarter,
        gross_interest_income: gross, fwt_rate: 20, fwt_withheld: fwt,
        status: 'generated', date_generated: new Date().toISOString(),
      }, { onConflict: 'company_id,bank_account_id,period_year,period_quarter' })
    }

    setGenerating(false); load()
  }

  const applyAction = async () => {
    if (!actionModal) return
    await supabase.from('form_2306_issuances').update(
      actionModal.action === 'sent'
        ? { status: 'sent', date_sent: actionDate }
        : { status: 'acknowledged', date_acknowledged: actionDate }
    ).eq('id', actionModal.issuance.id)
    setActionModal(null); load()
  }

  const totalGross = issuances.reduce((s, i) => s + i.gross_interest_income, 0)
  const totalFwt = issuances.reduce((s, i) => s + i.fwt_withheld, 0)
  const years = Array.from({ length: 5 }, (_, i) => now.getFullYear() - 2 + i)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">2306 Certificates</h1>
          <p className="text-sm text-gray-500 mt-0.5">Final Withholding Tax certificates — bank interest income</p>
        </div>
        <button onClick={generateBatch} disabled={generating} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 disabled:opacity-50">{generating ? 'Generating...' : '⚡ Generate Batch'}</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={year} onChange={e => setYear(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{years.map(y => <option key={y} value={y}>{y}</option>)}</select>
        <select value={quarter} onChange={e => setQuarter(Number(e.target.value))} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm">{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Gross Interest Income</p><p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(totalGross)}</p></div>
        <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">FWT Withheld (20%)</p><p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(totalFwt)}</p></div>
        <div className="bg-white border border-gray-200 rounded-lg p-4"><p className="text-xs text-gray-500 uppercase tracking-wide">Certificates</p><p className="text-xl font-bold text-gray-900 mt-1">{issuances.length}</p></div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Bank</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Account No.</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Gross Interest</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">FWT Withheld</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
              </tr>
            </thead>
            <tbody>
              {issuances.length === 0 ? (
                <tr><td colSpan={6} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No certificates. Click "Generate Batch" to pull interest income for this quarter.'}</td></tr>
              ) : issuances.map(i => (
                <tr key={i.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-gray-700">{i.bank_accounts?.bank_name || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-500">{i.bank_accounts?.account_number || '—'}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(i.gross_interest_income)}</td>
                  <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(i.fwt_withheld)}</td>
                  <td className="px-4 py-2.5"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${STATUS_CLS[i.status]}`}>{STATUS_LABELS[i.status]}</span></td>
                  <td className="px-4 py-2.5">
                    <div className="flex items-center gap-2">
                      {i.status === 'generated' && <button onClick={() => setActionModal({ issuance: i, action: 'sent' })} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Mark Sent</button>}
                      {i.status === 'sent' && <button onClick={() => setActionModal({ issuance: i, action: 'acknowledged' })} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Mark Acknowledged</button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
            {issuances.length > 0 && (
              <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                <tr><td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalGross)}</td><td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(totalFwt)}</td><td colSpan={2} /></tr>
              </tfoot>
            )}
          </table>
        )}
      </div>

      {actionModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 w-96 space-y-4">
            <h3 className="text-sm font-semibold text-gray-900">Mark as {actionModal.action === 'sent' ? 'Sent' : 'Acknowledged'}</h3>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Date</label>
              <input type="date" value={actionDate} onChange={e => setActionDate(e.target.value)} className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm" />
            </div>
            <div className="flex justify-end gap-2">
              <button onClick={() => setActionModal(null)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={applyAction} className="bg-gray-900 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-gray-800">Confirm</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
