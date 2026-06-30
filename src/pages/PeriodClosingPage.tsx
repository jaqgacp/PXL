import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Period = {
  id: string; company_id: string; period_name: string; period_number: number
  start_date: string; end_date: string; is_locked: boolean; fiscal_year_id: string
  fiscal_years: { year_name: string; status: string } | null
}

type Check = { label: string; ok: boolean; detail: string }

export default function PeriodClosingPage() {
  const { companyId } = useAppCtx()
  const [periods, setPeriods] = useState<Period[]>([])
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')

  // lock confirmation + checklist
  const [target, setTarget] = useState<Period | null>(null)
  const [checks, setChecks] = useState<Check[] | null>(null)
  const [checking, setChecking] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('fiscal_periods')
      .select('*, fiscal_years(year_name, status)')
      .eq('company_id', companyId).order('start_date', { ascending: false })
    setPeriods((data as Period[]) || [])
    setLoading(false)
  }, [companyId])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const runChecks = async (p: Period) => {
    setTarget(p); setChecks(null); setChecking(true); setError('')
    const y = Number(p.start_date.slice(0, 4))
    const m = Number(p.start_date.slice(5, 7))
    const [draftRes, reconRes, recurRes] = await Promise.all([
      supabase.from('journal_entries').select('id', { count: 'exact', head: true })
        .eq('company_id', companyId).eq('fiscal_period_id', p.id).eq('status', 'draft'),
      supabase.from('bank_reconciliations').select('id', { count: 'exact', head: true })
        .eq('company_id', companyId).eq('recon_year', y).eq('recon_month', m).neq('status', 'finalized'),
      supabase.from('recurring_journal_templates').select('id', { count: 'exact', head: true })
        .eq('company_id', companyId).eq('is_active', true).lte('next_run_date', p.end_date),
    ])
    const draftCount = draftRes.count ?? 0
    const reconCount = reconRes.error ? null : (reconRes.count ?? 0)
    const recurCount = recurRes.count ?? 0
    setChecks([
      { label: 'Draft journal entries in period', ok: draftCount === 0, detail: draftCount === 0 ? 'None' : `${draftCount} draft entr${draftCount === 1 ? 'y' : 'ies'}` },
      { label: 'Unreconciled bank accounts', ok: reconCount === null ? true : reconCount === 0, detail: reconCount === null ? 'N/A' : (reconCount === 0 ? 'All reconciled' : `${reconCount} not finalized`) },
      { label: 'Recurring templates due this period', ok: recurCount === 0, detail: recurCount === 0 ? 'None pending' : `${recurCount} pending` },
    ])
    setChecking(false)
  }

  const confirmLock = async () => {
    if (!target) return
    setBusy(target.id); setError('')
    const { error: e } = await supabase.from('fiscal_periods').update({ is_locked: true }).eq('id', target.id)
    if (e) setError(e.message)
    setTarget(null); setChecks(null); setBusy('')
    await load()
  }

  const unlock = async (p: Period) => {
    if (!confirm(`Unlock ${p.period_name}? Posting to this period will be re-enabled.`)) return
    setBusy(p.id); setError('')
    const { error: e } = await supabase.from('fiscal_periods').update({ is_locked: false }).eq('id', p.id)
    if (e) setError(e.message)
    setBusy('')
    await load()
  }

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Period Closing & Fiscal Locks</span>
        {error && <span className="text-xs text-red-600">{error}</span>}
      </div>

      <div className="px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Fiscal Periods</span>
          </div>
          {loading ? (
            <div className="py-16 text-center text-sm text-gray-400">Loading…</div>
          ) : periods.length === 0 ? (
            <div className="py-16 text-center text-sm text-gray-400">No fiscal periods. Set up fiscal years first.</div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Period', 'Fiscal Year', 'Start Date', 'End Date', 'Status', ''].map(hh => (
                    <th key={hh} className="px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{hh}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {periods.map(p => {
                  const yearClosed = p.fiscal_years?.status === 'closed'
                  return (
                    <tr key={p.id} className="hover:bg-gray-50/60">
                      <td className="px-3 py-2.5 font-medium text-gray-900">{p.period_name}</td>
                      <td className="px-3 py-2.5 text-gray-600">{p.fiscal_years?.year_name || '—'}</td>
                      <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{p.start_date}</td>
                      <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{p.end_date}</td>
                      <td className="px-3 py-2.5">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${p.is_locked ? 'bg-red-50 text-red-700' : 'bg-green-50 text-green-700'}`}>
                          {p.is_locked ? 'Locked' : 'Open'}
                        </span>
                      </td>
                      <td className="px-3 py-2.5 text-right">
                        {yearClosed ? (
                          <span className="text-xs text-gray-400">Year closed</span>
                        ) : p.is_locked ? (
                          <button onClick={() => unlock(p)} disabled={busy === p.id}
                            className="text-xs text-gray-600 hover:text-gray-900 font-medium disabled:opacity-50">Unlock Period</button>
                        ) : (
                          <button onClick={() => runChecks(p)} disabled={busy === p.id}
                            className="text-xs text-red-600 hover:text-red-800 font-medium disabled:opacity-50">Lock Period</button>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Pre-closing checklist + confirm */}
      {target && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={() => { setTarget(null); setChecks(null) }} />
          <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-lg p-6 z-10">
            <h2 className="text-base font-semibold text-gray-900 mb-1">Lock {target.period_name}</h2>
            <p className="text-sm text-gray-600 mb-4">
              This will prevent any further posting to {target.period_name}. Review the pre-closing checklist below.
            </p>
            <div className="border border-gray-200 rounded-lg divide-y divide-gray-100 mb-4">
              {checking || !checks ? (
                <div className="px-4 py-6 text-center text-sm text-gray-400">Running checks…</div>
              ) : checks.map(c => (
                <div key={c.label} className="px-4 py-2.5 flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className={c.ok ? 'text-green-600' : 'text-amber-600'}>{c.ok ? '✓' : '✗'}</span>
                    <span className="text-sm text-gray-700">{c.label}</span>
                  </div>
                  <span className={`text-xs ${c.ok ? 'text-gray-500' : 'text-amber-700 font-medium'}`}>{c.detail}</span>
                </div>
              ))}
            </div>
            {checks && checks.some(c => !c.ok) && (
              <p className="text-xs text-amber-700 mb-4">Some checks have warnings. You may still lock the period, but these items are noted.</p>
            )}
            <div className="flex justify-end gap-2">
              <button onClick={() => { setTarget(null); setChecks(null) }}
                className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={confirmLock} disabled={checking || busy === target.id}
                className="px-4 py-2 rounded-md text-sm font-medium text-white bg-red-600 hover:bg-red-700 disabled:opacity-50">
                {busy === target.id ? 'Locking…' : 'Confirm Lock'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
