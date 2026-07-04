import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, DateCell } from '@/components/ui/shared'

type IssuanceStatus = 'pending' | 'generated' | 'sent' | 'acknowledged' | 'superseded'

type Issuance = {
  id: string; company_id: string; supplier_id: string
  tax_year: number; tax_quarter: number
  total_tax_base: number; total_ewt: number; status: IssuanceStatus
  version: number; supersedes_issuance_id: string | null; superseded_by_issuance_id: string | null
  date_generated: string | null; date_sent: string | null; date_acknowledged: string | null
  remarks: string | null; created_at: string
  suppliers?: { registered_name: string; tin: string }
  form_2307_issuance_lines?: IssuanceLine[]
}

type IssuanceLine = {
  atc_code: string; nature_of_income: string; tax_base: number; tax_rate: number | null; tax_withheld: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const STATUS_COLORS: Record<string, string> = { pending: 'draft', generated: 'approved', sent: 'warning', acknowledged: 'posted', superseded: 'inactive' }

export default function Form2307IssuedPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [quarter, setQuarter] = useState(Math.ceil((now.getMonth() + 1) / 3))
  const [issuances, setIssuances] = useState<Issuance[]>([])
  const [loading, setLoading] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [actionModal, setActionModal] = useState<{ issuance: Issuance; action: 'sent' | 'acknowledged' | 'supersede' } | null>(null)
  const [actionDate, setActionDate] = useState(now.toISOString().split('T')[0])
  const [actionReason, setActionReason] = useState('')

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
    try {
      const { data, error } = await supabase.rpc('fn_generate_form_2307_issued', {
        p_company_id: companyId,
        p_tax_year: year,
        p_tax_quarter: quarter,
      })
      if (error) throw error
      const result = data as { generated_count?: number; skipped_locked_count?: number } | null
      if ((result?.generated_count || 0) === 0 && (result?.skipped_locked_count || 0) > 0) {
        alert('No certificates were regenerated because all matching certificates are already sent or acknowledged.')
      }
      await load()
    } catch (err: any) {
      alert(err?.message || 'Unable to generate Form 2307 certificates.')
    } finally {
      setGenerating(false)
    }
  }

  const updateStatus = async (issuance: Issuance, status: 'sent' | 'acknowledged', date: string) => {
    const { error } = await supabase.rpc('fn_update_form_2307_issued_status', {
      p_issuance_id: issuance.id,
      p_status: status,
      p_action_date: date,
    })
    if (error) {
      alert(error.message)
      return
    }
    setActionModal(null)
    load()
  }

  const supersede = async (issuance: Issuance, reason: string) => {
    const { error } = await supabase.rpc('fn_supersede_form_2307_issued', {
      p_issuance_id: issuance.id,
      p_reason: reason || undefined,
    })
    if (error) {
      alert(error.message)
      return
    }
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
                {['Supplier','TIN','Ver','Tax Base','EWT Withheld','Status','Generated','Sent','Acknowledged','Actions'].map(h => (
                  <th key={h} className={`px-3 py-2 font-medium text-gray-500 ${['Tax Base','EWT Withheld'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {issuances.map(iss => (
                <tr key={iss.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2 text-gray-700">{(iss.suppliers as any)?.registered_name || '—'}</td>
                  <td className="px-3 py-2 font-mono text-gray-500">{(iss.suppliers as any)?.tin || '—'}</td>
                  <td className="px-3 py-2 text-gray-500">v{iss.version ?? 1}</td>
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
                      {(iss.status === 'sent' || iss.status === 'acknowledged') && <button onClick={() => { setActionModal({ issuance: iss, action: 'supersede' }); setActionReason('') }} className="text-red-600 hover:text-red-800">Supersede</button>}
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
            <h3 className="text-sm font-semibold text-gray-900 capitalize">{actionModal.action === 'supersede' ? 'Supersede Certificate' : `Mark as ${actionModal.action}`}</h3>
            <p className="text-xs text-gray-600">Supplier: {(actionModal.issuance.suppliers as any)?.registered_name}</p>
            {actionModal.action === 'supersede' ? (
              <>
                <p className="text-xs text-gray-600">A new version will be generated from the current EWT detail. This certificate (v{actionModal.issuance.version ?? 1}) is preserved as superseded evidence.</p>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Reason</label>
                  <input value={actionReason} onChange={e => setActionReason(e.target.value)} placeholder="e.g. late PV posted for the quarter" className={inp + ' w-full'} />
                </div>
              </>
            ) : (
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">{actionModal.action === 'sent' ? 'Date Sent' : 'Date Acknowledged'}</label>
                <input type="date" value={actionDate} onChange={e => setActionDate(e.target.value)} className={inp + ' w-full'} />
              </div>
            )}
            <div className="flex justify-end gap-2">
              <button onClick={() => setActionModal(null)} className="px-3 py-1.5 text-sm border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button onClick={() => actionModal.action === 'supersede' ? supersede(actionModal.issuance, actionReason) : updateStatus(actionModal.issuance, actionModal.action, actionDate)} className="px-3 py-1.5 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700">Confirm</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
