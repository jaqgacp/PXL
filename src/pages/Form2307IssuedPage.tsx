import { Fragment, useState, useEffect, useCallback } from 'react'
import { ReportTraceLink } from '@/components/AccountingTraceLink'
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
  requires_supersede: boolean; supersede_required_at: string | null; supersede_reason: string | null
  remarks: string | null; created_at: string
  suppliers?: { registered_name: string; tin: string }
  form_2307_issuance_lines?: IssuanceLine[]
}

type IssuanceLine = {
  atc_code: string; nature_of_income: string
  month_1_tax_base: number; month_1_tax_withheld: number
  month_2_tax_base: number; month_2_tax_withheld: number
  month_3_tax_base: number; month_3_tax_withheld: number
  tax_base: number; tax_rate: number | null; tax_withheld: number
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
      .select('*,suppliers(registered_name,tin),form_2307_issuance_lines(atc_code,nature_of_income,month_1_tax_base,month_1_tax_withheld,month_2_tax_base,month_2_tax_withheld,month_3_tax_base,month_3_tax_withheld,tax_base,tax_rate,tax_withheld)')
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
      const result = data as { generated_count?: number; skipped_locked_count?: number; skipped_unlinked_count?: number; skipped_unlinked_ewt?: number } | null
      if ((result?.generated_count || 0) === 0 && (result?.skipped_locked_count || 0) > 0) {
        alert('No certificates were regenerated because all matching certificates are already sent or acknowledged.')
      }
      if ((result?.skipped_unlinked_count || 0) > 0) {
        alert(`Warning: ${result?.skipped_unlinked_count} EWT row group(s) totaling ${Number(result?.skipped_unlinked_ewt || 0).toFixed(2)} withheld were SKIPPED because the source document has no supplier link. Those payees received no certificate — link the documents to suppliers and regenerate.`)
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
  const quarterMonthLabels = [0, 1, 2].map(offset =>
    new Date(year, (quarter - 1) * 3 + offset, 1).toLocaleString('en-PH', { month: 'short' })
  )
  const lineTraceFilters = (issuance: Issuance, line: IssuanceLine) => ({
    record_id: issuance.id,
    atc_code: line.atc_code || undefined,
    income_nature: line.nature_of_income || undefined,
    tax_rate: line.tax_rate == null ? undefined : String(line.tax_rate),
  })

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
                <Fragment key={iss.id}>
                  <tr className="hover:bg-gray-50">
                    <td className="px-3 py-2 text-gray-700">{(iss.suppliers as any)?.registered_name || '—'}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{(iss.suppliers as any)?.tin || '—'}</td>
                    <td className="px-3 py-2 text-gray-500">v{iss.version ?? 1}</td>
                    <td className="px-3 py-2 text-right font-mono">{fmt(iss.total_tax_base)}</td>
                    <td className="px-3 py-2 text-right font-mono font-medium text-red-700">{fmt(iss.total_ewt)}</td>
                    <td className="px-3 py-2">
                      <div className="flex flex-col gap-1">
                        <StatusBadge status={STATUS_COLORS[iss.status]} label={iss.status} />
                        {iss.requires_supersede && iss.status !== 'superseded' && (
                          <span className="inline-flex w-fit rounded bg-red-50 px-1.5 py-0.5 text-[10px] font-medium text-red-700" title={iss.supersede_reason || undefined}>
                            Supersede required
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="px-3 py-2 text-gray-500">{iss.date_generated ? <DateCell date={iss.date_generated.split('T')[0]} /> : '—'}</td>
                    <td className="px-3 py-2 text-gray-500">{iss.date_sent ? <DateCell date={iss.date_sent.split('T')[0]} /> : '—'}</td>
                    <td className="px-3 py-2 text-gray-500">{iss.date_acknowledged ? <DateCell date={iss.date_acknowledged.split('T')[0]} /> : '—'}</td>
                    <td className="px-3 py-2">
                      <div className="flex gap-2">
                        <ReportTraceLink
                          companyId={companyId || ''}
                          reportFamily="form_2307_issued"
                          filters={{ record_id: iss.id }}
                          className="text-blue-600 hover:text-blue-800"
                          title="Open the accounting sources for this certificate"
                        >
                          Trace
                        </ReportTraceLink>
                        {iss.status === 'generated' && <button onClick={() => { setActionModal({ issuance: iss, action: 'sent' }); setActionDate(new Date().toISOString().split('T')[0]) }} className="text-orange-600 hover:text-orange-800">Mark Sent</button>}
                        {iss.status === 'sent' && <button onClick={() => { setActionModal({ issuance: iss, action: 'acknowledged' }); setActionDate(new Date().toISOString().split('T')[0]) }} className="text-green-600 hover:text-green-800">Mark Acknowledged</button>}
                        {(iss.status === 'sent' || iss.status === 'acknowledged') && <button onClick={() => { setActionModal({ issuance: iss, action: 'supersede' }); setActionReason(iss.supersede_reason || '') }} className="text-red-600 hover:text-red-800">{iss.requires_supersede ? 'Supersede Now' : 'Supersede'}</button>}
                      </div>
                    </td>
                  </tr>
                  {(iss.form_2307_issuance_lines || []).length > 0 && (
                    <tr className="bg-gray-50/60">
                      <td colSpan={10} className="px-3 pb-3">
                        <div className="overflow-x-auto border border-gray-200 rounded-md bg-white">
                          <table className="w-full min-w-[980px] text-[11px]">
                            <thead className="bg-gray-50 border-b border-gray-200">
                              <tr>
                                {[
                                  'ATC', 'Nature', `${quarterMonthLabels[0]} Base`, `${quarterMonthLabels[0]} EWT`,
                                  `${quarterMonthLabels[1]} Base`, `${quarterMonthLabels[1]} EWT`,
                                  `${quarterMonthLabels[2]} Base`, `${quarterMonthLabels[2]} EWT`,
                                  'Total Base', 'Rate', 'Total EWT'
                                ].map(h => (
                                  <th key={h} className={`px-2 py-1.5 font-medium text-gray-500 ${h === 'ATC' || h === 'Nature' ? 'text-left' : 'text-right'}`}>{h}</th>
                                ))}
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100">
                              {(iss.form_2307_issuance_lines || []).map((line, index) => (
                                <tr key={`${line.atc_code}-${line.nature_of_income}-${index}`}>
                                  <td className="px-2 py-1.5 font-mono text-gray-700">{line.atc_code}</td>
                                  <td className="px-2 py-1.5 text-gray-700">{line.nature_of_income || '—'}</td>
                                  <td className="px-2 py-1.5 text-right font-mono">{fmt(line.month_1_tax_base)}</td>
                                  <td className="px-2 py-1.5 text-right font-mono">{fmt(line.month_1_tax_withheld)}</td>
                                  <td className="px-2 py-1.5 text-right font-mono">{fmt(line.month_2_tax_base)}</td>
                                  <td className="px-2 py-1.5 text-right font-mono">{fmt(line.month_2_tax_withheld)}</td>
                                  <td className="px-2 py-1.5 text-right font-mono">{fmt(line.month_3_tax_base)}</td>
                                  <td className="px-2 py-1.5 text-right font-mono">{fmt(line.month_3_tax_withheld)}</td>
                                  <td className="px-2 py-1.5 text-right font-mono font-medium">{fmt(line.tax_base)}</td>
                                  <td className="px-2 py-1.5 text-right font-mono">{line.tax_rate == null ? '—' : `${fmt(line.tax_rate)}%`}</td>
                                  <td className="px-2 py-1.5 text-right font-mono font-medium text-red-700">
                                    <ReportTraceLink
                                      companyId={companyId || ''}
                                      reportFamily="form_2307_issued"
                                      filters={lineTraceFilters(iss, line)}
                                      title="Open the source tax-ledger rows for this Form 2307 line"
                                    >
                                      {fmt(line.tax_withheld)}
                                    </ReportTraceLink>
                                  </td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
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
