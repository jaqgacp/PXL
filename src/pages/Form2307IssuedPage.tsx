import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, DateCell } from '@/components/ui/shared'

type IssuanceStatus = 'pending' | 'generated' | 'sent' | 'acknowledged'

type Issuance = {
  id: string; company_id: string; supplier_id: string
  tax_year: number; tax_quarter: number
  total_tax_base: number; total_ewt: number; status: IssuanceStatus
  date_generated: string | null; date_sent: string | null; date_acknowledged: string | null
  remarks: string | null; created_at: string
  suppliers?: { registered_name: string; tin: string }
  form_2307_issuance_lines?: IssuanceLine[]
}

type EWTAggregate = {
  supplier_id: string; supplier_name: string; supplier_tin: string | null
  tax_base: number; ewt_withheld: number
  lines: { atc_code_id: string | null; atc_code: string; nature_of_payment: string; tax_base: number; tax_rate: number | null; tax_withheld: number }[]
}

type IssuanceLine = {
  atc_code: string; nature_of_income: string; tax_base: number; tax_rate: number | null; tax_withheld: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const QUARTERS: Record<number, number[]> = { 1: [1,2,3], 2: [4,5,6], 3: [7,8,9], 4: [10,11,12] }
const STATUS_COLORS: Record<string, string> = { pending: 'draft', generated: 'approved', sent: 'warning', acknowledged: 'posted' }

export default function Form2307IssuedPage() {
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
    const { data } = await supabase.from('form_2307_issuances')
      .select('*,suppliers(registered_name,tin),form_2307_issuance_lines(atc_code,nature_of_income,tax_base,tax_rate,tax_withheld)')
      .eq('company_id', companyId).eq('tax_year', year).eq('tax_quarter', quarter)
      .order('created_at')
    setIssuances(data as Issuance[] || [])
    setLoading(false)
  }, [companyId, year, quarter])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const generateBatch = async () => {
    if (!companyId) return
    setGenerating(true)
    const months = QUARTERS[quarter]
    const startDate = `${year}-${String(months[0]).padStart(2, '0')}-01`
    const endDate = new Date(year, months[months.length - 1], 0).toISOString().split('T')[0]

    // Pull EWT per supplier+ATC from tax_detail_entries (via rebased vw_ewt_summary_ap)
    const { data: ewtData } = await supabase.from('vw_ewt_summary_ap')
      .select('supplier_id,supplier_name,supplier_tin,atc_code_id,atc_code,nature_of_payment,tax_base,tax_rate,tax_withheld')
      .eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate)

    if (!ewtData || ewtData.length === 0) { alert('No EWT data found for this period.'); setGenerating(false); return }

    const bySupplier: Record<string, EWTAggregate> = {}
    for (const row of ewtData as any[]) {
      const sid = row.supplier_id
      if (!bySupplier[sid]) bySupplier[sid] = { supplier_id: sid, supplier_name: row.supplier_name, supplier_tin: row.supplier_tin, tax_base: 0, ewt_withheld: 0, lines: [] }
      bySupplier[sid].tax_base += Number(row.tax_base) || 0
      bySupplier[sid].ewt_withheld += Number(row.tax_withheld) || 0
      // Group by ATC within the supplier
      const existing = bySupplier[sid].lines.find(l => l.atc_code === (row.atc_code || ''))
      if (existing) {
        existing.tax_base += Number(row.tax_base) || 0
        existing.tax_withheld += Number(row.tax_withheld) || 0
      } else {
        bySupplier[sid].lines.push({
          atc_code_id: row.atc_code_id, atc_code: row.atc_code || '',
          nature_of_payment: row.nature_of_payment || '',
          tax_base: Number(row.tax_base) || 0, tax_rate: row.tax_rate,
          tax_withheld: Number(row.tax_withheld) || 0,
        })
      }
    }

    for (const s of Object.values(bySupplier)) {
      const { data: upserted } = await supabase.from('form_2307_issuances').upsert({
        company_id: companyId, supplier_id: s.supplier_id,
        tax_year: year, tax_quarter: quarter,
        total_tax_base: s.tax_base, total_ewt: s.ewt_withheld,
        status: 'generated', date_generated: new Date().toISOString(),
      }, { onConflict: 'company_id,supplier_id,tax_year,tax_quarter' }).select('id').single()

      if (upserted?.id) {
        // Replace per-ATC lines
        await supabase.from('form_2307_issuance_lines').delete().eq('issuance_id', upserted.id)
        if (s.lines.length > 0) {
          await supabase.from('form_2307_issuance_lines').insert(s.lines.map(l => ({
            issuance_id: upserted.id, company_id: companyId,
            atc_code_id: l.atc_code_id, atc_code: l.atc_code,
            nature_of_income: l.nature_of_payment,
            tax_base: l.tax_base, tax_rate: l.tax_rate, tax_withheld: l.tax_withheld,
          })))
        }
      }
    }

    load()
    setGenerating(false)
  }

  const updateStatus = async (issuance: Issuance, status: 'sent' | 'acknowledged', date: string) => {
    const update: any = { status, updated_by: null }
    if (status === 'sent') update.date_sent = date
    if (status === 'acknowledged') update.date_acknowledged = date
    await supabase.from('form_2307_issuances').update(update).eq('id', issuance.id)
    setActionModal(null)
    load()
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900'

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">2307 Issued Review</h2>
        <button onClick={generateBatch} disabled={generating} className="px-3 py-1.5 text-xs bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">
          {generating ? 'Generating…' : 'Generate 2307s for Quarter'}
        </button>
      </div>

      <div className="flex gap-3">
        <div><label className="block text-xs font-medium text-gray-700 mb-1">Year</label><select value={year} onChange={e => setYear(+e.target.value)} className={inp}>{[now.getFullYear() - 1, now.getFullYear()].map(y => <option key={y} value={y}>{y}</option>)}</select></div>
        <div><label className="block text-xs font-medium text-gray-700 mb-1">Quarter</label><select value={quarter} onChange={e => setQuarter(+e.target.value)} className={inp}>{[1,2,3,4].map(q => <option key={q} value={q}>Q{q}</option>)}</select></div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : issuances.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-400">
            No 2307 records for Q{quarter} {year}. Click "Generate 2307s" to create from EWT data.
          </div>
        ) : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Supplier','TIN','Tax Base','EWT Withheld','Status','Generated','Sent','Acknowledged','Actions'].map(h => (
                  <th key={h} className={`px-3 py-2 font-medium text-gray-500 ${['Tax Base','EWT Withheld'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {issuances.map(iss => (
                <tr key={iss.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2 text-gray-700">{(iss.suppliers as any)?.registered_name || '—'}</td>
                  <td className="px-3 py-2 font-mono text-gray-500">{(iss.suppliers as any)?.tin || '—'}</td>
                  <td className="px-3 py-2 text-right font-mono">{fmt(iss.total_tax_base)}</td>
                  <td className="px-3 py-2 text-right font-mono font-medium text-red-700">{fmt(iss.total_ewt)}</td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[iss.status]} label={iss.status} /></td>
                  <td className="px-3 py-2 text-gray-500">{iss.date_generated ? <DateCell date={iss.date_generated.split('T')[0]} /> : '—'}</td>
                  <td className="px-3 py-2 text-gray-500">{iss.date_sent ? <DateCell date={iss.date_sent.split('T')[0]} /> : '—'}</td>
                  <td className="px-3 py-2 text-gray-500">{iss.date_acknowledged ? <DateCell date={iss.date_acknowledged.split('T')[0]} /> : '—'}</td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2">
                      {iss.status === 'generated' && <button onClick={() => { setActionModal({ issuance: iss, action: 'sent' }); setActionDate(new Date().toISOString().split('T')[0]) }} className="text-orange-600 hover:text-orange-800">Mark Sent</button>}
                      {iss.status === 'sent' && <button onClick={() => { setActionModal({ issuance: iss, action: 'acknowledged' }); setActionDate(new Date().toISOString().split('T')[0]) }} className="text-green-600 hover:text-green-800">Mark Acknowledged</button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {actionModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg border border-gray-200 shadow-xl p-6 w-80 space-y-4">
            <h3 className="text-sm font-semibold text-gray-900 capitalize">Mark as {actionModal.action}</h3>
            <p className="text-xs text-gray-600">Supplier: {(actionModal.issuance.suppliers as any)?.registered_name}</p>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">{actionModal.action === 'sent' ? 'Date Sent' : 'Date Acknowledged'}</label>
              <input type="date" value={actionDate} onChange={e => setActionDate(e.target.value)} className={inp + ' w-full'} />
            </div>
            <div className="flex justify-end gap-2">
              <button onClick={() => setActionModal(null)} className="px-3 py-1.5 text-sm border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button onClick={() => updateStatus(actionModal.issuance, actionModal.action, actionDate)} className="px-3 py-1.5 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700">Confirm</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
