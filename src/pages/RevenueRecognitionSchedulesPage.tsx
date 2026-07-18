import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

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
  const [previewEntryId, setPreviewEntryId] = useState<string | null>(null)

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
    setPreviewEntryId(null)
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
      const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', {
        p_source_doc_type: 'REVREC', p_source_doc_id: entryId,
      })
      if (previewError) throw previewError
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
      const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', {
        p_source_doc_type: 'REVREC', p_source_doc_id: entry.id,
      })
      if (previewError) { failed++; continue }
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
      <LegacyTransactionWorkspace title="Revenue Recognition Schedule" family="journal" pattern="D" posting
        documentNo={viewSchedule.schedule_name} status={viewSchedule.status} identity={viewSchedule.description}
        financialFacts={[{ label: 'Contract Amount', value: fmt(viewSchedule.total_amount) }, { label: 'Recognized Periods', value: `${viewSchedule.posted_periods} / ${viewSchedule.total_periods}` }, { label: 'Pending Periods', value: pendingCount }]}
        contextFacts={[{ label: 'Schedule', value: viewSchedule.schedule_name }, { label: 'Deferred Revenue Account', value: deferAcc ? `${deferAcc.account_code} — ${deferAcc.account_name}` : viewSchedule.deferred_revenue_account_id }, { label: 'Revenue Account', value: revAcc ? `${revAcc.account_code} — ${revAcc.account_name}` : viewSchedule.revenue_account_id }, { label: 'Progress', value: `${Math.round(progress)}%` }]}
        sourceDocType="REVREC" sourceDocId={previewEntryId || viewSchedule.id} auditTable="revenue_recognition_schedules"
        onBack={() => { setMode('list'); setViewSchedule(null); setEntries([]) }} backLabel="Revenue Recognition Schedules"
        actions={[
          { key: 'cancel', label: 'Cancel Schedule', onClick: () => cancelSchedule(viewSchedule.id), hidden: viewSchedule.status !== 'active', variant: 'danger' },
          { key: 'post', label: postingAll ? 'Posting…' : `Post All Pending (${pendingCount})`, onClick: postAllPending, disabled: postingAll || pendingCount === 0, hidden: viewSchedule.status !== 'active', variant: 'primary' },
        ]}
        headerFields={[
          { key: 'name', label: 'Schedule', card: 0, span: 2, content: <div className="pxl-readonly-field">{viewSchedule.schedule_name}</div> },
          { key: 'status', label: 'Status', card: 0, content: <div className="pxl-readonly-field capitalize">{viewSchedule.status}</div> },
          { key: 'deferred', label: 'Deferred Revenue Account (DR)', card: 1, span: 2, content: <div className="pxl-readonly-field">{deferAcc ? `${deferAcc.account_code} — ${deferAcc.account_name}` : viewSchedule.deferred_revenue_account_id}</div> },
          { key: 'revenue', label: 'Revenue Account (CR)', card: 2, span: 2, content: <div className="pxl-readonly-field">{revAcc ? `${revAcc.account_code} — ${revAcc.account_name}` : viewSchedule.revenue_account_id}</div> },
          { key: 'progress', label: 'Progress', card: 2, content: <div className="pxl-readonly-field">{Math.round(progress)}%</div> },
        ]}
        tabContent={{
          validation: error ? <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div> : <div className="pxl-validation-message border border-gray-200">{pendingCount} pending periods.</div>,
          gl: previewEntryId ? <GLImpactPanel companyId={companyId} sourceDocType="REVREC" sourceDocId={previewEntryId} previewRows={[]} /> : undefined,
        }}>
      <div>
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-2.5 border-b border-gray-100">
              <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Recognition Schedule</span>
            </div>
            {entriesLoading ? (
              <div className="py-10 text-center text-sm text-gray-400">Loading…</div>
            ) : (
              <table className="pxl-data-grid w-full">
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
                          <div className="flex items-center gap-3">
                            <button onClick={() => setPreviewEntryId(e.id)} className="text-xs font-medium text-gray-600 hover:text-gray-900">Preview</button>
                            <button onClick={() => postEntry(e.id)} disabled={posting === e.id}
                              className="text-xs font-medium text-purple-600 hover:text-purple-800 disabled:opacity-40">
                              {posting === e.id ? 'Posting…' : 'Recognize'}
                            </button>
                          </div>
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
      </LegacyTransactionWorkspace>
    )
  }

  // ── New Form ──────────────────────────────────────────────────────────────────
  if (mode === 'new') {
    const preview = periodAmount()
    return (
      <LegacyTransactionWorkspace title="Revenue Recognition Schedule" family="journal" pattern="D" posting
        status="draft" identity={form.schedule_name}
        financialFacts={[{ label: 'Contract Amount', value: fmt(Number(form.total_amount) || 0) }, { label: 'Periods', value: Number(form.total_periods) || 0 }, { label: 'Recognition per Period', value: preview == null ? 'Not calculated' : fmt(preview) }]}
        contextFacts={[{ label: 'Schedule', value: form.schedule_name || 'New schedule' }, { label: 'Start Date', value: form.start_date }, { label: 'Deferred Revenue Account', value: accounts.find(account => account.id === form.deferred_revenue_account_id)?.account_name || 'Not selected' }, { label: 'Revenue Account', value: accounts.find(account => account.id === form.revenue_account_id)?.account_name || 'Not selected' }]}
        onBack={() => { setMode('list'); setForm(EMPTY_FORM); setError('') }} backLabel="Revenue Recognition Schedules"
        actions={[{ key: 'cancel', label: 'Cancel', onClick: () => { setMode('list'); setForm(EMPTY_FORM); setError('') } }, { key: 'save', label: saving ? 'Creating…' : 'Create Schedule', onClick: save, disabled: saving, variant: 'primary' }]}
        headerFields={[
          { key: 'name', label: 'Schedule Name *', card: 0, span: 2, content: <input value={form.schedule_name} onChange={event => setForm(current => ({ ...current, schedule_name: event.target.value }))} className="pxl-input w-full" /> },
          { key: 'start', label: 'Recognition Start Date *', card: 0, content: <input type="date" value={form.start_date} onChange={event => setForm(current => ({ ...current, start_date: event.target.value }))} className="pxl-input w-full" /> },
          { key: 'deferred', label: 'Deferred Revenue Account (DR) *', card: 1, span: 2, content: <select value={form.deferred_revenue_account_id} onChange={event => setForm(current => ({ ...current, deferred_revenue_account_id: event.target.value }))} className="pxl-input w-full"><option value="">Select account…</option>{accounts.map(account => <option key={account.id} value={account.id}>{account.account_code} — {account.account_name}</option>)}</select> },
          { key: 'revenue', label: 'Revenue Account (CR) *', card: 2, span: 2, content: <select value={form.revenue_account_id} onChange={event => setForm(current => ({ ...current, revenue_account_id: event.target.value }))} className="pxl-input w-full"><option value="">Select account…</option>{accounts.map(account => <option key={account.id} value={account.id}>{account.account_code} — {account.account_name}</option>)}</select> },
          { key: 'description', label: 'Description', card: 2, span: 2, content: <input value={form.description} onChange={event => setForm(current => ({ ...current, description: event.target.value }))} className="pxl-input w-full" /> },
        ]}
        tabContent={{ validation: error ? <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div> : undefined }}>
        <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr><th>Total Contract Amount</th><th>Number of Periods</th><th>Recognition per Period</th></tr></thead><tbody><tr><td><input type="number" min={0} step={0.01} value={form.total_amount} onChange={event => setForm(current => ({ ...current, total_amount: event.target.value }))} className="pxl-input w-full text-right" /></td><td><input type="number" min={1} max={360} value={form.total_periods} onChange={event => setForm(current => ({ ...current, total_periods: event.target.value }))} className="pxl-input w-full text-right" /></td><td className="text-right">{preview == null ? '—' : fmt(preview)}</td></tr></tbody></table></div>
      </LegacyTransactionWorkspace>
    )
  }

  // ── List ──────────────────────────────────────────────────────────────────────
  return (
    <div>
      <div className="pxl-list-header flex items-center gap-2 border-b border-gray-200 px-4 py-2">
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
