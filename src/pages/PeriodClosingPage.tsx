import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Period = {
  id: string; company_id: string; period_name: string; period_number: number
  start_date: string; end_date: string; is_locked: boolean; fiscal_year_id: string
}

type FiscalYear = {
  id: string; year_name: string; start_date: string; end_date: string
  status: string; retained_earnings_id: string | null
}

type Check = { code: string; label: string; severity: 'blocking' | 'advisory'; ok: boolean; detail: string }
type Readiness = { period_name: string; ready: boolean; blocking_failures: number; checks: Check[] }

type CloseRun = {
  id: string; close_type: string; action: string; effective_date: string
  reason: string | null; net_income: number | null; performed_at: string
  superseded_by_id: string | null; fiscal_period_id: string | null
}

const money = (n: number | null) =>
  n === null ? '—' : n.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

export default function PeriodClosingPage() {
  const { companyId } = useAppCtx()
  const [periods, setPeriods] = useState<Period[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [runs, setRuns] = useState<CloseRun[]>([])
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  // Close confirmation + governed readiness checklist
  const [target, setTarget] = useState<Period | null>(null)
  const [readiness, setReadiness] = useState<Readiness | null>(null)
  const [checking, setChecking] = useState(false)

  // Reopen requires a reason — for a period and for a fiscal year alike
  const [reopenPeriod, setReopenPeriod] = useState<Period | null>(null)
  const [reopenYear, setReopenYear] = useState<FiscalYear | null>(null)
  const [reason, setReason] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const [p, y, r] = await Promise.all([
      supabase.from('fiscal_periods').select('*').eq('company_id', companyId)
        .order('start_date', { ascending: false }),
      supabase.from('fiscal_years').select('id, year_name, start_date, end_date, status, retained_earnings_id')
        .eq('company_id', companyId).order('start_date', { ascending: false }),
      supabase.from('fiscal_close_runs')
        .select('id, close_type, action, effective_date, reason, net_income, performed_at, superseded_by_id, fiscal_period_id')
        .eq('company_id', companyId).order('performed_at', { ascending: false }).limit(40),
    ])
    setPeriods((p.data as Period[]) || [])
    setYears((y.data as FiscalYear[]) || [])
    setRuns((r.data as CloseRun[]) || [])
    setLoading(false)
  }, [companyId])

  useEffect(() => { if (companyId) load() }, [load, companyId])

  const yearOf = (p: Period) => years.find(y => y.id === p.fiscal_year_id)

  const run = async (label: string, fn: () => PromiseLike<{ error: { message: string } | null }>) => {
    setBusy(label); setError(''); setNotice('')
    const { error: e } = await fn()
    if (e) setError(e.message)
    setBusy('')
    await load()
    return !e
  }

  const openChecklist = async (p: Period) => {
    setTarget(p); setReadiness(null); setChecking(true); setError('')
    const { data, error: e } = await supabase.rpc('fn_period_close_readiness', {
      p_company_id: companyId!, p_fiscal_period_id: p.id,
    })
    if (e) setError(e.message)
    setReadiness((data as unknown as Readiness) ?? null)
    setChecking(false)
  }

  const confirmClose = async () => {
    if (!target) return
    const ok = await run(target.id, () =>
      supabase.rpc('fn_close_accounting_period', {
        p_company_id: companyId!, p_fiscal_period_id: target.id,
      }))
    if (ok) { setNotice(`${target.period_name} is closed.`); setTarget(null); setReadiness(null) }
  }

  const confirmReopenPeriod = async () => {
    if (!reopenPeriod) return
    const ok = await run(reopenPeriod.id, () =>
      supabase.rpc('fn_reopen_accounting_period', {
        p_company_id: companyId!, p_fiscal_period_id: reopenPeriod.id, p_reason: reason,
      }))
    if (ok) { setNotice(`${reopenPeriod.period_name} is open again.`); setReopenPeriod(null); setReason('') }
  }

  const closeQuarter = async (fy: FiscalYear, quarter: number) => {
    const ok = await run(`${fy.id}-q${quarter}`, () =>
      supabase.rpc('fn_close_accounting_quarter', {
        p_company_id: companyId!, p_fiscal_year_id: fy.id, p_quarter: quarter,
      }))
    if (ok) setNotice(`Q${quarter} of ${fy.year_name} is closed.`)
  }

  const closeYear = async (fy: FiscalYear) => {
    if (!confirm(
      `Close ${fy.year_name}?\n\nThis posts the year-end closing journal: every revenue and expense account is zeroed and the net result is carried to Retained Earnings. All periods are locked and the next fiscal year is opened.\n\nThe year can be reopened later with a reason.`
    )) return
    const ok = await run(fy.id, () =>
      supabase.rpc('fn_close_fiscal_year', { p_company_id: companyId!, p_fiscal_year_id: fy.id }))
    if (ok) setNotice(`${fy.year_name} is closed and the next fiscal year is open.`)
  }

  const confirmReopenYear = async () => {
    if (!reopenYear) return
    const ok = await run(reopenYear.id, () =>
      supabase.rpc('fn_reopen_fiscal_year', {
        p_company_id: companyId!, p_fiscal_year_id: reopenYear.id, p_reason: reason,
      }))
    if (ok) { setNotice(`${reopenYear.year_name} is open again; the closing journal has been counter-posted.`); setReopenYear(null); setReason('') }
  }

  const badge = (locked: boolean) => (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${locked ? 'bg-red-50 text-red-700' : 'bg-green-50 text-green-700'}`}>
      {locked ? 'Closed' : 'Open'}
    </span>
  )

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Period Close &amp; Year-End</span>
        {error && <span className="text-xs text-red-600">{error}</span>}
        {notice && !error && <span className="text-xs text-green-700">{notice}</span>}
      </div>

      <div className="px-5 py-4 space-y-4">
        {/* ── Fiscal years: quarterly close, year-end close, reopen ─────────── */}
        <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Fiscal Years</span>
          </div>
          {years.length === 0 ? (
            <div className="py-10 text-center text-sm text-gray-400">No fiscal years. Create one first.</div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Fiscal Year', 'Start', 'End', 'Retained Earnings', 'Status', 'Quarterly Close', ''].map(h => (
                    <th key={h} className="px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {years.map(fy => (
                  <tr key={fy.id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2.5 font-medium text-gray-900">{fy.year_name}</td>
                    <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{fy.start_date}</td>
                    <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{fy.end_date}</td>
                    <td className="px-3 py-2.5 text-xs">
                      {fy.retained_earnings_id
                        ? <span className="text-gray-500">Configured</span>
                        : <span className="text-amber-700 font-medium">Not set — the year cannot be closed</span>}
                    </td>
                    <td className="px-3 py-2.5">{badge(fy.status === 'closed')}</td>
                    <td className="px-3 py-2.5">
                      <div className="flex gap-1">
                        {[1, 2, 3, 4].map(q => (
                          <button key={q} onClick={() => closeQuarter(fy, q)}
                            disabled={fy.status === 'closed' || busy === `${fy.id}-q${q}`}
                            className="text-[11px] px-1.5 py-0.5 border border-gray-300 rounded text-gray-600 hover:bg-gray-50 disabled:opacity-40">
                            Q{q}
                          </button>
                        ))}
                      </div>
                    </td>
                    <td className="px-3 py-2.5 text-right whitespace-nowrap">
                      {fy.status === 'closed' ? (
                        <button onClick={() => { setReopenYear(fy); setReason('') }} disabled={busy === fy.id}
                          className="text-xs text-gray-600 hover:text-gray-900 font-medium disabled:opacity-50">Reopen Year</button>
                      ) : (
                        <button onClick={() => closeYear(fy)} disabled={busy === fy.id || !fy.retained_earnings_id}
                          className="text-xs text-red-600 hover:text-red-800 font-medium disabled:opacity-40">
                          {busy === fy.id ? 'Closing…' : 'Close Year'}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* ── Monthly periods ───────────────────────────────────────────────── */}
        <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Accounting Periods</span>
          </div>
          {loading ? (
            <div className="py-16 text-center text-sm text-gray-400">Loading…</div>
          ) : periods.length === 0 ? (
            <div className="py-16 text-center text-sm text-gray-400">No fiscal periods. Set up fiscal years first.</div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Period', 'Fiscal Year', 'Start Date', 'End Date', 'Status', ''].map(h => (
                    <th key={h} className="px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {periods.map(p => {
                  const fy = yearOf(p)
                  const yearClosed = fy?.status === 'closed'
                  return (
                    <tr key={p.id} className="hover:bg-gray-50/60">
                      <td className="px-3 py-2.5 font-medium text-gray-900">{p.period_name}</td>
                      <td className="px-3 py-2.5 text-gray-600">{fy?.year_name || '—'}</td>
                      <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{p.start_date}</td>
                      <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{p.end_date}</td>
                      <td className="px-3 py-2.5">{badge(p.is_locked)}</td>
                      <td className="px-3 py-2.5 text-right">
                        {yearClosed ? (
                          <span className="text-xs text-gray-400">Year closed</span>
                        ) : p.is_locked ? (
                          <button onClick={() => { setReopenPeriod(p); setReason('') }} disabled={busy === p.id}
                            className="text-xs text-gray-600 hover:text-gray-900 font-medium disabled:opacity-50">Reopen Period</button>
                        ) : (
                          <button onClick={() => openChecklist(p)} disabled={busy === p.id}
                            className="text-xs text-red-600 hover:text-red-800 font-medium disabled:opacity-50">Close Period</button>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
        </div>

        {/* ── The close register ────────────────────────────────────────────── */}
        <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Close Register</span>
          </div>
          {runs.length === 0 ? (
            <div className="py-10 text-center text-sm text-gray-400">Nothing has been closed yet.</div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['When', 'Scope', 'Action', 'Effective', 'Net Income', 'Reason', 'Standing'].map(h => (
                    <th key={h} className="px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {runs.map(r => (
                  <tr key={r.id}>
                    <td className="px-3 py-2 font-mono text-xs text-gray-500">{r.performed_at.slice(0, 16).replace('T', ' ')}</td>
                    <td className="px-3 py-2 text-gray-700 capitalize">{r.close_type}</td>
                    <td className="px-3 py-2 text-gray-700 capitalize">{r.action}</td>
                    <td className="px-3 py-2 font-mono text-xs text-gray-500">{r.effective_date}</td>
                    <td className="px-3 py-2 text-right font-mono text-xs text-gray-700">{money(r.net_income)}</td>
                    <td className="px-3 py-2 text-xs text-gray-500">{r.reason || '—'}</td>
                    <td className="px-3 py-2 text-xs">
                      {r.superseded_by_id
                        ? <span className="text-gray-400">Superseded</span>
                        : <span className="text-gray-700">Current</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Governed pre-close checklist */}
      {target && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={() => { setTarget(null); setReadiness(null) }} />
          <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-lg p-6 z-10">
            <h2 className="text-base font-semibold text-gray-900 mb-1">Close {target.period_name}</h2>
            <p className="text-sm text-gray-600 mb-4">
              Closing prevents any further posting to {target.period_name}. The checks below come from the
              database, and the blocking ones are enforced whether or not this screen shows them.
            </p>
            <div className="border border-gray-200 rounded-lg divide-y divide-gray-100 mb-4">
              {checking || !readiness ? (
                <div className="px-4 py-6 text-center text-sm text-gray-400">Running checks…</div>
              ) : readiness.checks.map(c => (
                <div key={c.code} className="px-4 py-2.5 flex items-center justify-between gap-3">
                  <div className="flex items-center gap-2 min-w-0">
                    <span className={c.ok ? 'text-green-600' : c.severity === 'blocking' ? 'text-red-600' : 'text-amber-600'}>
                      {c.ok ? '✓' : '✗'}
                    </span>
                    <span className="text-sm text-gray-700 truncate">{c.label}</span>
                    {!c.ok && (
                      <span className={`text-[10px] uppercase tracking-wide font-semibold ${c.severity === 'blocking' ? 'text-red-600' : 'text-amber-600'}`}>
                        {c.severity}
                      </span>
                    )}
                  </div>
                  <span className={`text-xs whitespace-nowrap ${c.ok ? 'text-gray-500' : 'text-gray-700 font-medium'}`}>{c.detail}</span>
                </div>
              ))}
            </div>
            {readiness && !readiness.ready && (
              <p className="text-xs text-red-700 mb-4">
                {readiness.blocking_failures} blocking check{readiness.blocking_failures === 1 ? '' : 's'} must be
                resolved before {target.period_name} can be closed.
              </p>
            )}
            {readiness?.ready && readiness.checks.some(c => !c.ok) && (
              <p className="text-xs text-amber-700 mb-4">
                Advisory items remain. The close is allowed and these are recorded with it.
              </p>
            )}
            <div className="flex justify-end gap-2">
              <button onClick={() => { setTarget(null); setReadiness(null) }}
                className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={confirmClose} disabled={checking || !readiness?.ready || busy === target.id}
                className="px-4 py-2 rounded-md text-sm font-medium text-white bg-red-600 hover:bg-red-700 disabled:opacity-50">
                {busy === target.id ? 'Closing…' : 'Confirm Close'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reopen — a reason is required and is kept in the register */}
      {(reopenPeriod || reopenYear) && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={() => { setReopenPeriod(null); setReopenYear(null) }} />
          <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-lg p-6 z-10">
            <h2 className="text-base font-semibold text-gray-900 mb-1">
              Reopen {reopenPeriod ? reopenPeriod.period_name : reopenYear!.year_name}
            </h2>
            <p className="text-sm text-gray-600 mb-4">
              {reopenYear
                ? 'Reopening the year counter-posts the closing journal, so the profit comes back out of Retained Earnings and into the income accounts. Nothing is deleted — the original closing entry stays in the ledger.'
                : 'Reopening allows posting into this period again. The close it undoes is kept and marked superseded.'}
            </p>
            <label className="block text-xs font-medium text-gray-500 mb-1">Reason <span className="text-red-500">*</span></label>
            <textarea value={reason} onChange={e => setReason(e.target.value)} rows={3}
              placeholder="Why is this being reopened?"
              className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 mb-4" />
            <div className="flex justify-end gap-2">
              <button onClick={() => { setReopenPeriod(null); setReopenYear(null) }}
                className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={reopenPeriod ? confirmReopenPeriod : confirmReopenYear}
                disabled={!reason.trim() || busy !== ''}
                className="px-4 py-2 rounded-md text-sm font-medium text-white bg-gray-900 hover:bg-gray-800 disabled:opacity-50">
                Confirm Reopen
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
