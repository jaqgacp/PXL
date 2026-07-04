import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Schedule = {
  id: string; company_id: string; branch_id: string | null
  schedule_name: string; description: string | null
  deferred_revenue_account_id: string; revenue_account_id: string
  total_amount: number; start_date: string
  total_periods: number; posted_periods: number
  status: 'active' | 'completed' | 'cancelled'
  created_at: string
}

type Entry = {
  id: string; period_number: number; entry_date: string
  amount: number; status: 'pending' | 'posted' | 'skipped'
  je_id: string | null
  journal_entries: { je_number: string } | null
}

type COARef = { id: string; account_code: string; account_name: string }

type FormState = {
  schedule_name: string; description: string
  deferred_revenue_account_id: string; revenue_account_id: string
  total_amount: string; start_date: string; total_periods: string
}

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

const EMPTY_FORM: FormState = {
  schedule_name: '', description: '', deferred_revenue_account_id: '', revenue_account_id: '',
  total_amount: '', start_date: today(), total_periods: '12',
}

function statusColor(s: Schedule['status']) {
  if (s === 'completed') return 'bg-green-50 text-green-700'
  if (s === 'cancelled') return 'bg-red-50 text-red-700'
  return 'bg-purple-50 text-purple-700'
}

export default function RevenueRecognitionSchedulesPage() {
  const { companyId, branchId } = useAppCtx()
  const [mode, setMode] = useState<'list' | 'new' | 'view'>('list')
  const [schedules, setSchedules] = useState<Schedule[]>([])
  const [accounts, setAccounts] = useState<COARef[]>([])
  const [loading, setLoading] = useState(false)
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [viewSchedule, setViewSchedule] = useState<Schedule | null>(null)
  const [entries, setEntries] = useState<Entry[]>([])
  const [entriesLoading, setEntriesLoading] = useState(false)
  const [posting, setPosting] = useState<string | null>(null)
  const [postingAll, setPostingAll] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('revenue_recognition_schedules').select('*')
      .eq('company_id', companyId).order('created_at', { ascending: false })
    setSchedules((data as Schedule[]) || [])
    setLoading(false)
  }, [companyId])

  const loadAccounts = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('chart_of_accounts')
      .select('id,account_code,account_name').eq('company_id', companyId)
      .eq('is_active', true).eq('is_postable', true).order('account_code')
    setAccounts((data as COARef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadAccounts() } }, [load, loadAccounts, companyId])

  const loadEntries = async (schedule: Schedule) => {
    setViewSchedule(schedule)
    setEntriesLoading(true)
    setMode('view')
    const { data } = await supabase.from('revenue_recognition_entries')
      .select('id,period_number,entry_date,amount,status,je_id,journal_entries(je_number)')
      .eq('schedule_id', schedule.id).order('period_number')
    setEntries((data as unknown as Entry[]) || [])
    setEntriesLoading(false)
  }

  const save = async () => {
    if (!companyId) return
    const amt = parseFloat(form.total_amount)
    const periods = parseInt(form.total_periods)
    if (!form.schedule_name || !form.deferred_revenue_account_id || !form.revenue_account_id) {
      setError('Schedule name, deferred revenue account, and revenue account are required'); return
    }
    if (isNaN(amt) || amt <= 0) { setError('Enter a valid total amount'); return }
    if (isNaN(periods) || periods < 1 || periods > 360) { setError('Periods must be 1–360'); return }
    setSaving(true); setError('')
    try {
      const { error: e } = await supabase.rpc('fn_create_revenue_recognition_schedule', {
        p_company_id: companyId,
        p_branch_id: (branchId || null)!,
        p_schedule_name: form.schedule_name,
        p_description: (form.description || null)!,
        p_deferred_revenue_account_id: form.deferred_revenue_account_id,
        p_revenue_account_id: form.revenue_account_id,
        p_total_amount: amt,
        p_start_date: form.start_date,
        p_total_periods: periods,
      })
      if (e) throw e
      await load()
      setMode('list')
      setForm(EMPTY_FORM)
    } catch (e: any) {
      setError(e.message || 'Failed to create schedule')
    } finally { setSaving(false) }
  }

  const postEntry = async (entryId: string) => {
    setPosting(entryId); setError('')
    try {
      const { error: e } = await supabase.rpc('fn_post_revenue_recognition_entry', { p_entry_id: entryId })
      if (e) throw e
      if (viewSchedule) { await loadEntries(viewSchedule); await load() }
    } catch (e: any) {
      setError(e.message || 'Posting failed')
    } finally { setPosting(null) }
  }

  const postAllPending = async () => {
    if (!viewSchedule) return
    const pending = entries.filter(e => e.status === 'pending')
    if (!pending.length) return
    setPostingAll(true); setError('')
    let failed = 0
    for (const entry of pending) {
      const { error: e } = await supabase.rpc('fn_post_revenue_recognition_entry', { p_entry_id: entry.id })
      if (e) failed++
    }
    if (failed) setError(`${failed} entry(ies) failed — check open periods`)
    await loadEntries(viewSchedule); await load()
    setPostingAll(false)
  }

  const cancelSchedule = async (id: string) => {
    if (!confirm('Cancel this schedule? Pending entries will be skipped.')) return
    const { error: e } = await supabase.rpc('fn_cancel_revenue_recognition_schedule', { p_schedule_id: id })
    if (e) { setError(e.message); return }
    await load()
  }

  const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full'

  const periodAmount = () => {
    const amt = parseFloat(form.total_amount)
    const p = parseInt(form.total_periods)
    if (isNaN(amt) || isNaN(p) || p < 1) return null
    return Math.round(amt / p * 100) / 100
  }

  // ── View Mode ────────────────────────────────────────────────────────────────
  if (mode === 'view' && viewSchedule) {
    const deferAcc = accounts.find(a => a.id === viewSchedule.deferred_revenue_account_id)
    const revAcc = accounts.find(a => a.id === viewSchedule.revenue_account_id)
    const pendingCount = entries.filter(e => e.status === 'pending').length
    const progress = viewSchedule.total_periods > 0 ? (viewSchedule.posted_periods / viewSchedule.total_periods) * 100 : 0

    return (
      <div className="flex flex-col h-full">
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-2 flex-wrap">
          <button onClick={() => { setMode('list'); setViewSchedule(null); setEntries([]) }}
            className="text-sm text-gray-500 hover:text-gray-900">← Back</button>
          <span className="text-gray-300">|</span>
          <span className="text-sm font-semibold text-gray-700">{viewSchedule.schedule_name}</span>
          <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${statusColor(viewSchedule.status)}`}>{viewSchedule.status}</span>
          <div className="ml-auto flex items-center gap-2">
            {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
            {viewSchedule.status === 'active' && pendingCount > 0 && (
              <button onClick={postAllPending} disabled={postingAll}
                className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
                {postingAll ? 'Posting…' : `Post All Pending (${pendingCount})`}
              </button>
            )}
            {viewSchedule.status === 'active' && (
              <button onClick={() => cancelSchedule(viewSchedule.id)}
                className="px-3 py-1.5 border border-red-300 text-red-600 rounded text-sm hover:bg-red-50">Cancel Schedule</button>
            )}
          </div>
        </div>

        <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg p-4 mb-4">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-xs">
              <div>
                <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Total Amount</p>
                <p className="font-mono tabular-nums font-semibold text-gray-900 mt-0.5">{fmt(viewSchedule.total_amount)}</p>
              </div>
              <div>
                <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Periods</p>
                <p className="font-medium text-gray-900 mt-0.5">{viewSchedule.posted_periods} / {viewSchedule.total_periods} posted</p>
              </div>
              <div>
                <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Deferred Revenue Account (DR)</p>
                <p className="text-gray-700 mt-0.5">{deferAcc ? `${deferAcc.account_code} — ${deferAcc.account_name}` : '—'}</p>
              </div>
              <div>
                <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Revenue Account (CR)</p>
                <p className="text-gray-700 mt-0.5">{revAcc ? `${revAcc.account_code} — ${revAcc.account_name}` : '—'}</p>
              </div>
            </div>
            <div className="mt-3">
              <div className="flex justify-between text-[10px] text-gray-400 mb-1">
                <span>Progress</span><span>{Math.round(progress)}%</span>
              </div>
              <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
                <div className="h-full bg-purple-500 rounded-full transition-all" style={{ width: `${progress}%` }} />
              </div>
            </div>
          </div>

          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-2.5 border-b border-gray-100">
              <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Recognition Schedule</span>
            </div>
            {entriesLoading ? (
              <div className="py-10 text-center text-sm text-gray-400">Loading…</div>
            ) : (
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Period', 'Entry Date', 'Amount', 'Status', 'JE Number', ''].map(hh => (
                      <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 ${hh === 'Amount' ? 'text-right' : 'text-left'}`}>{hh}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {entries.map(e => (
                    <tr key={e.id} className={e.status === 'skipped' ? 'opacity-40' : ''}>
                      <td className="px-3 py-2 font-mono text-gray-600">{e.period_number}</td>
                      <td className="px-3 py-2 font-mono text-gray-700">{e.entry_date}</td>
                      <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-900">{fmt(e.amount)}</td>
                      <td className="px-3 py-2">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${e.status === 'posted' ? 'bg-green-50 text-green-700' : e.status === 'skipped' ? 'bg-gray-100 text-gray-500' : 'bg-amber-50 text-amber-700'}`}>
                          {e.status}
                        </span>
                      </td>
                      <td className="px-3 py-2 font-mono text-xs text-gray-500">{e.journal_entries?.je_number || '—'}</td>
                      <td className="px-3 py-2">
                        {e.status === 'pending' && viewSchedule.status === 'active' && (
                          <button onClick={() => postEntry(e.id)} disabled={posting === e.id}
                            className="text-xs font-medium text-purple-600 hover:text-purple-800 disabled:opacity-40">
                            {posting === e.id ? 'Posting…' : 'Recognize'}
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t border-gray-200 bg-gray-50">
                  <tr>
                    <td colSpan={2} className="px-3 py-2 text-right font-semibold text-gray-700">Total</td>
                    <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(entries.reduce((s, e) => s + e.amount, 0))}</td>
                    <td colSpan={3} />
                  </tr>
                </tfoot>
              </table>
            )}
          </div>
        </div>
      </div>
    )
  }

  // ── New Form ──────────────────────────────────────────────────────────────────
  if (mode === 'new') {
    const preview = periodAmount()
    return (
      <div className="flex flex-col h-full">
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-2 flex-wrap">
          <button onClick={() => { setMode('list'); setForm(EMPTY_FORM); setError('') }}
            className="text-sm text-gray-500 hover:text-gray-900">← Back</button>
          <span className="text-gray-300">|</span>
          <span className="text-sm font-semibold text-gray-700">New Revenue Recognition Schedule</span>
          <div className="ml-auto flex items-center gap-2">
            {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
            <button onClick={save} disabled={saving}
              className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
              {saving ? 'Creating…' : 'Create Schedule'}
            </button>
          </div>
        </div>

        <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg p-5 max-w-2xl">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="sm:col-span-2 flex flex-col gap-1">
                <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Schedule Name *</label>
                <input value={form.schedule_name} onChange={e => setForm(f => ({ ...f, schedule_name: e.target.value }))} className={inputCls} placeholder="e.g. Subscription Revenue Q1 2026" />
              </div>
              <div className="sm:col-span-2 flex flex-col gap-1">
                <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Description</label>
                <input value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} className={inputCls} />
              </div>
              <div className="flex flex-col gap-1">
                <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Deferred Revenue Account (DR) *</label>
                <select value={form.deferred_revenue_account_id} onChange={e => setForm(f => ({ ...f, deferred_revenue_account_id: e.target.value }))} className={inputCls}>
                  <option value="">— select account —</option>
                  {accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                </select>
              </div>
              <div className="flex flex-col gap-1">
                <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Revenue Account (CR) *</label>
                <select value={form.revenue_account_id} onChange={e => setForm(f => ({ ...f, revenue_account_id: e.target.value }))} className={inputCls}>
                  <option value="">— select account —</option>
                  {accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                </select>
              </div>
              <div className="flex flex-col gap-1">
                <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Total Contract Amount *</label>
                <input type="number" min={0} step={0.01} value={form.total_amount}
                  onChange={e => setForm(f => ({ ...f, total_amount: e.target.value }))} className={inputCls} />
              </div>
              <div className="flex flex-col gap-1">
                <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Number of Periods (months) *</label>
                <input type="number" min={1} max={360} value={form.total_periods}
                  onChange={e => setForm(f => ({ ...f, total_periods: e.target.value }))} className={inputCls} />
              </div>
              <div className="flex flex-col gap-1">
                <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Recognition Start Date *</label>
                <input type="date" value={form.start_date} onChange={e => setForm(f => ({ ...f, start_date: e.target.value }))} className={inputCls} />
              </div>
              {preview !== null && (
                <div className="flex flex-col gap-1">
                  <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Monthly Recognition Preview</label>
                  <div className="border border-gray-200 rounded px-2.5 py-2 text-sm bg-gray-50 font-mono text-gray-700">
                    {fmt(preview)} / period
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    )
  }

  // ── List ──────────────────────────────────────────────────────────────────────
  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Revenue Recognition Schedules</span>
        {error && <span className="text-xs text-red-600">{error}</span>}
        <button onClick={() => { setMode('new'); setForm(EMPTY_FORM); setError('') }} disabled={!companyId}
          className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
          + New Schedule
        </button>
      </div>

      {loading ? (
        <div className="py-16 text-center text-sm text-gray-400">Loading…</div>
      ) : schedules.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">No revenue recognition schedules</p>
          <p className="text-xs text-gray-400 mt-1">Create a schedule to recognize deferred revenue over a contract period.</p>
        </div>
      ) : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              {['Schedule Name', 'Total Amount', 'Start Date', 'Periods', 'Progress', 'Status', ''].map(hh => (
                <th key={hh} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${hh === 'Total Amount' ? 'text-right' : 'text-left'}`}>{hh}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {schedules.map(s => {
              const pct = s.total_periods > 0 ? (s.posted_periods / s.total_periods) * 100 : 0
              return (
                <tr key={s.id} onClick={() => loadEntries(s)} className="cursor-pointer hover:bg-gray-50/60">
                  <td className="px-3 py-2.5 font-medium text-gray-900">{s.schedule_name}</td>
                  <td className="px-3 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmt(s.total_amount)}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{s.start_date}</td>
                  <td className="px-3 py-2.5 text-xs text-gray-600 tabular-nums">{s.posted_periods}/{s.total_periods}</td>
                  <td className="px-3 py-2.5 w-28">
                    <div className="flex items-center gap-2">
                      <div className="flex-1 h-1.5 bg-gray-100 rounded-full overflow-hidden">
                        <div className="h-full bg-purple-500 rounded-full" style={{ width: `${pct}%` }} />
                      </div>
                      <span className="text-[10px] text-gray-400 tabular-nums w-8">{Math.round(pct)}%</span>
                    </div>
                  </td>
                  <td className="px-3 py-2.5">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${statusColor(s.status)}`}>{s.status}</span>
                  </td>
                  <td className="px-3 py-2.5 text-right" onClick={e => e.stopPropagation()}>
                    {s.status === 'active' && (
                      <button onClick={() => cancelSchedule(s.id)}
                        className="text-xs text-red-500 hover:text-red-700 font-medium">Cancel</button>
                    )}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
    </div>
  )
}
