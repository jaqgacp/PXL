import { useState, useEffect, useCallback } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Route } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection } from '@/components/ui/shared'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { TransactionWorkspace } from '@/components/document/TransactionWorkspace'
import { useBranchLabel } from '@/hooks/useBranchLabel'
import { SystemMetadataPanel, TransactionEmptyState } from '@/components/document/TransactionPrimitives'

// ── Types ─────────────────────────────────────────────────────
type JEStatus = 'draft' | 'posted' | 'reversed'

type JE = {
  id: string; company_id: string; branch_id: string | null
  je_number: string; je_date: string; fiscal_period_id: string | null
  description: string | null; reference_doc_type: string | null; reference_doc_id: string | null
  status: JEStatus; total_debit: number; total_credit: number
  entry_class: string | null
  auto_reverse: boolean; is_auto_reversal: boolean; reversed_by_je_id: string | null
  created_at: string; updated_at: string
}

type JELine = {
  _key: string; id?: string
  account_id: string; description: string
  debit_amount: number; credit_amount: number
}

type COARef = { id: string; account_code: string; account_name: string }
type PeriodRef = { id: string; period_name: string; start_date: string; end_date: string }

// ── Helpers ───────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const formatDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'
const newLine = (): JELine => ({ _key: crypto.randomUUID(), account_id: '', description: '', debit_amount: 0, credit_amount: 0 })

const refTypeStyle = (t: string | null): string => {
  switch (t) {
    case 'MANUAL': return 'bg-blue-50 text-blue-700'
    case 'REV': return 'bg-amber-50 text-amber-700'
    case 'RECURRING': return 'bg-purple-50 text-purple-700'
    default: return 'bg-gray-100 text-gray-600'
  }
}

// ── Component ─────────────────────────────────────────────────
export default function JournalEntriesPage() {
  const { companyId, branchId } = useAppCtx()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const requestedJeId = searchParams.get('jeId') || ''

  const [entries, setEntries] = useState<JE[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [tab, setTab] = useState<'all' | 'manual'>('all')

  const [editJE, setEditJE] = useState<Partial<JE> | null>(null)
  const [lines, setLines] = useState<JELine[]>([newLine(), newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [accounts, setAccounts] = useState<COARef[]>([])
  const [periods, setPeriods] = useState<PeriodRef[]>([])

  // filters
  const [fPeriod, setFPeriod] = useState('')
  const [fFrom, setFFrom] = useState('')
  const [fTo, setFTo] = useState('')
  const [fStatus, setFStatus] = useState('')
  const [fSearch, setFSearch] = useState('')

  // reversal modal
  const [reverseTarget, setReverseTarget] = useState<JE | null>(null)
  const [reverseDate, setReverseDate] = useState(today())
  const [reversing, setReversing] = useState(false)
  const [openedQueryKey, setOpenedQueryKey] = useState('')

  const readOnly = mode === 'view'
  const branchLabel = useBranchLabel(editJE?.branch_id || branchId)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('journal_entries').select('*')
      .eq('company_id', companyId)
      .order('je_date', { ascending: false }).order('je_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fPeriod) q = q.eq('fiscal_period_id', fPeriod)
    if (fFrom) q = q.gte('je_date', fFrom)
    if (fTo) q = q.lte('je_date', fTo)
    const { data } = await q
    setEntries((data as JE[]) || [])
    setLoading(false)
  }, [companyId, fStatus, fPeriod, fFrom, fTo])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [coaRes, perRes] = await Promise.all([
      supabase.from('chart_of_accounts').select('id,account_code,account_name')
        .eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code'),
      supabase.from('fiscal_periods').select('id,period_name,start_date,end_date')
        .eq('company_id', companyId).order('start_date', { ascending: false }),
    ])
    setAccounts((coaRes.data as COARef[]) || [])
    setPeriods((perRes.data as PeriodRef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const openNew = () => {
    setEditJE({ company_id: companyId!, branch_id: branchId || null, je_date: today(), description: '', auto_reverse: false, entry_class: 'regular' })
    setLines([newLine(), newLine()])
    setError('')
    setMode('edit')
  }

  const openView = useCallback(async (je: JE) => {
    setEditJE(je)
    const { data } = await supabase.from('journal_entry_lines')
      .select('id,account_id,description,debit_amount,credit_amount,line_number')
      .eq('je_id', je.id).order('line_number')
    setLines(((data as any[]) || []).map(l => ({
      _key: l.id, id: l.id, account_id: l.account_id, description: l.description || '',
      debit_amount: Number(l.debit_amount), credit_amount: Number(l.credit_amount),
    })))
    setError('')
    setMode('view')
  }, [])

  useEffect(() => {
    if (!companyId || !requestedJeId) return
    const queryKey = `${companyId}:${requestedJeId}`
    if (openedQueryKey === queryKey) return
    let alive = true
    const openRequestedEntry = async () => {
      const { data, error: queryError } = await supabase.from('journal_entries')
        .select('*')
        .eq('company_id', companyId)
        .eq('id', requestedJeId)
        .maybeSingle()
      if (!alive) return
      setOpenedQueryKey(queryKey)
      if (queryError || !data) {
        setError(queryError?.message || 'Journal entry not found in the selected company')
        return
      }
      await openView(data as JE)
    }
    void openRequestedEntry()
    return () => { alive = false }
  }, [companyId, openView, openedQueryKey, requestedJeId])

  useEffect(() => {
    if (!requestedJeId) setOpenedQueryKey('')
  }, [requestedJeId])

  const updateLine = (key: string, field: keyof JELine, raw: string) => {
    setLines(ls => ls.map(l => {
      if (l._key !== key) return l
      if (field === 'debit_amount') return { ...l, debit_amount: parseFloat(raw) || 0, credit_amount: 0 }
      if (field === 'credit_amount') return { ...l, credit_amount: parseFloat(raw) || 0, debit_amount: 0 }
      return { ...l, [field]: raw }
    }))
  }

  const totalDebit = lines.reduce((s, l) => s + l.debit_amount, 0)
  const totalCredit = lines.reduce((s, l) => s + l.credit_amount, 0)
  const balance = totalDebit - totalCredit
  const isBalanced = Math.abs(balance) <= 0.01
  const validLines = lines.filter(l => l.account_id && (l.debit_amount > 0 || l.credit_amount > 0))
  const canPost = isBalanced && totalDebit > 0 && validLines.length >= 2
  const glPreviewRows: GLImpactRow[] = validLines.map(line => ({
    accountId: line.account_id,
    description: line.description || editJE?.description || 'Manual journal line',
    debit: line.debit_amount,
    credit: line.credit_amount,
  }))
  const auditFacts = editJE?.id ? [
    { label: 'Created', value: formatDateTime(editJE.created_at) },
    { label: 'Last edited', value: formatDateTime(editJE.updated_at) },
    { label: 'Status', value: editJE.status || 'draft' },
    { label: 'Lock status', value: editJE.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ] : []

  const post = async () => {
    if (!companyId || !editJE) return
    if (!canPost) { setError('Entry must balance and have at least 2 valid lines'); return }
    setSaving(true); setError('')
    try {
      const payload = validLines.map(l => ({
        account_id: l.account_id, description: l.description || null,
        debit_amount: l.debit_amount, credit_amount: l.credit_amount,
      }))
      const { error: e } = await supabase.rpc('fn_post_manual_je', {
        p_company_id: companyId,
        p_branch_id: (editJE.branch_id || branchId || null)!,
        p_je_date: editJE.je_date || today(),
        p_description: editJE.description || 'Manual Journal Entry',
        p_reference_doc_type: 'MANUAL',
        p_auto_reverse: !!editJE.auto_reverse,
        p_lines: payload,
        p_entry_class: editJE.entry_class || 'regular',
      })
      if (e) throw e
      await load()
      setMode('list')
    } catch (e: any) {
      setError(e.message || 'Posting failed')
    } finally { setSaving(false) }
  }

  const doReverse = async () => {
    if (!reverseTarget) return
    setReversing(true); setError('')
    try {
      const { error: e } = await supabase.rpc('fn_reverse_je', {
        p_je_id: reverseTarget.id, p_reversal_date: reverseDate,
      })
      if (e) throw e
      setReverseTarget(null)
      await load()
      setMode('list')
    } catch (e: any) {
      setError(e.message || 'Reversal failed')
      setReverseTarget(null)
    } finally { setReversing(false) }
  }

  const filtered = entries
    .filter(e => tab === 'all' || e.reference_doc_type === 'MANUAL')
    .filter(e => !fSearch ||
      e.je_number.toLowerCase().includes(fSearch.toLowerCase()) ||
      (e.description || '').toLowerCase().includes(fSearch.toLowerCase()))

  // ── Reversal Modal ────────────────────────────────────────────
  const reversalModal = reverseTarget && (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/40" onClick={() => setReverseTarget(null)} />
      <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-md p-6 z-10">
        <h2 className="text-base font-semibold text-gray-900 mb-1">Reverse {reverseTarget.je_number}</h2>
        <p className="text-sm text-gray-600 mb-4">
          A reversing entry will be posted that swaps all debits and credits. The original entry will be marked reversed. This cannot be undone.
        </p>
        <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Reversal Date</label>
        <input type="date" value={reverseDate} onChange={e => setReverseDate(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-2 text-sm w-full mt-1 mb-4 focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <div className="flex justify-end gap-2">
          <button onClick={() => setReverseTarget(null)}
            className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={doReverse} disabled={reversing}
            className="px-4 py-2 rounded-md text-sm font-medium text-white bg-red-600 hover:bg-red-700 disabled:opacity-50">
            {reversing ? 'Reversing…' : 'Confirm Reversal'}
          </button>
        </div>
      </div>
    </div>
  )

  // ── List View ─────────────────────────────────────────────────
  if (mode === 'list') return (
    <div>
      {reversalModal}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Journal Entries</span>
        <div className="flex rounded border border-gray-300 overflow-hidden">
          <button onClick={() => setTab('all')} className={`px-3 py-1.5 text-xs font-medium ${tab === 'all' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>All Entries</button>
          <button onClick={() => setTab('manual')} className={`px-3 py-1.5 text-xs font-medium border-l border-gray-300 ${tab === 'manual' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>Manual Entries</button>
        </div>
        <select value={fPeriod} onChange={e => setFPeriod(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All periods</option>
          {periods.map(p => <option key={p.id} value={p.id}>{p.period_name}</option>)}
        </select>
        <input type="date" value={fFrom} onChange={e => setFFrom(e.target.value)} title="From"
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <input type="date" value={fTo} onChange={e => setFTo(e.target.value)} title="To"
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900">
          <option value="">All statuses</option>
          <option value="posted">Posted</option>
          <option value="reversed">Reversed</option>
        </select>
        <input value={fSearch} onChange={e => setFSearch(e.target.value)} placeholder="Search JE # / description…"
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-48 focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <button onClick={openNew} disabled={!companyId}
          className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
          + Create Manual JE
        </button>
      </div>

      {error && (
        <div className="mx-5 mt-4 border border-red-200 bg-red-50 rounded-md px-4 py-3 text-sm text-red-700">{error}</div>
      )}

      {loading ? (
        <div className="py-16 text-center text-sm text-gray-400">Loading…</div>
      ) : filtered.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">No journal entries</p>
          <p className="text-xs text-gray-400 mt-1">Posted documents and manual entries appear here.</p>
        </div>
      ) : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              {['JE Number', 'Date', 'Period', 'Description', 'Ref Type', 'Total Debit', 'Total Credit', 'Auto-Rev', 'Status', ''].map(hh => (
                <th key={hh} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Total Debit', 'Total Credit'].includes(hh) ? 'text-right' : 'text-left'}`}>{hh}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {filtered.map(je => {
              const per = periods.find(p => p.id === je.fiscal_period_id)
              return (
                <tr key={je.id} onClick={() => openView(je)}
                  className={`cursor-pointer hover:bg-gray-50/60 ${je.status === 'reversed' ? 'opacity-60' : ''}`}>
                  <td className="px-3 py-2.5 font-mono text-xs font-semibold" onClick={event => event.stopPropagation()}>
                    <Link to={`/accounting-trace?jeId=${je.id}`} className="inline-flex items-center gap-1 text-blue-700 hover:text-blue-900">
                      {je.je_number}
                      <Route className="h-3 w-3" aria-hidden="true" />
                    </Link>
                  </td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{je.je_date}</td>
                  <td className="px-3 py-2.5 text-xs text-gray-500">{per?.period_name || '—'}</td>
                  <td className="px-3 py-2.5 text-xs text-gray-900 max-w-[220px] truncate">{je.description || '—'}</td>
                  <td className="px-3 py-2.5">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${refTypeStyle(je.reference_doc_type)}`}>
                      {je.reference_doc_type || '—'}
                    </span>
                  </td>
                  <td className="px-3 py-2.5 text-right font-mono tabular-nums text-xs text-gray-700">{fmt(je.total_debit)}</td>
                  <td className="px-3 py-2.5 text-right font-mono tabular-nums text-xs text-gray-700">{fmt(je.total_credit)}</td>
                  <td className="px-3 py-2.5 text-center text-xs">{je.auto_reverse ? '↺' : ''}</td>
                  <td className="px-3 py-2.5">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${je.status === 'reversed' ? 'bg-red-50 text-red-700' : 'bg-green-50 text-green-700'}`}>
                      {je.status}
                    </span>
                  </td>
                  <td className="px-3 py-2.5 text-right whitespace-nowrap" onClick={e => e.stopPropagation()}>
                    {je.status === 'posted' && !je.reversed_by_je_id && (
                      <button onClick={() => { setReverseTarget(je); setReverseDate(today()) }}
                        className="text-xs text-red-600 hover:text-red-800 font-medium">Reverse</button>
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

  // ── Edit / View ───────────────────────────────────────────────
  const inputCls = `border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50 disabled:text-gray-500 w-full`

  const jeStatus = editJE?.status || 'draft'
  const selectedPeriod = periods.find(period => period.id === editJE?.fiscal_period_id)
  const workflowSteps = [
    { key: 'draft', label: 'Draft' },
    { key: 'posted', label: 'Posted' },
    { key: 'reversed', label: 'Reversed' },
  ]
  const validationErrors = [
    validLines.length < 2 ? 'At least two valid journal lines are required.' : '',
    totalDebit <= 0 ? 'Journal total must be greater than zero.' : '',
    !isBalanced ? `Journal is out of balance by ₱${fmt(balance)}.` : '',
    validLines.some(line => !accounts.some(account => account.id === line.account_id)) ? 'Every line requires an active postable account.' : '',
  ].filter(Boolean)

  return (
    <>
      {reversalModal}
      <TransactionWorkspace
        title="Journal Entry"
        documentNo={editJE?.je_number}
        status={jeStatus}
        statusLabel={jeStatus}
        family="journal"
        identity={{ name: editJE?.description || 'Manual Journal Entry', secondary: editJE?.reference_doc_type || 'MANUAL' }}
        metrics={[
          { label: 'Total Debit', value: `₱${fmt(totalDebit)}`, emphasis: true },
          { label: 'Total Credit', value: `₱${fmt(totalCredit)}`, emphasis: true },
          { label: 'Difference', value: `₱${fmt(balance)}`, emphasis: !isBalanced },
        ]}
        meta={[
          { label: 'Balance', value: isBalanced ? 'Balanced' : 'Out of balance', tone: isBalanced ? 'success' : 'error' },
          { label: 'Lock', value: jeStatus === 'draft' ? 'Editable' : 'Frozen', tone: jeStatus === 'draft' ? 'neutral' : 'warning' },
        ]}
        actions={[
          ...(!readOnly ? [
            { key: 'cancel', label: 'Cancel', onClick: () => setMode('list'), disabled: saving },
            { key: 'post', label: saving ? 'Posting…' : 'Post Entry', onClick: post, disabled: saving || !canPost, variant: 'primary' as const },
          ] : []),
          ...(editJE?.id ? [
            { key: 'trace', label: 'Trace', onClick: () => navigate(`/accounting-trace?jeId=${editJE.id}`) },
            { key: 'ledger', label: 'General Ledger', onClick: () => navigate(`/general-ledger?jeId=${editJE.id}`), group: 'more' as const },
            { key: 'review', label: 'Posting Review', onClick: () => navigate(`/posting-review?jeId=${editJE.id}`), group: 'more' as const },
          ] : []),
          ...(readOnly && jeStatus === 'posted' && !editJE?.reversed_by_je_id ? [{ key: 'reverse', label: 'Reverse', onClick: () => { setReverseTarget(editJE as JE); setReverseDate(today()) }, variant: 'danger' as const, group: 'more' as const }] : []),
        ]}
        workflow={{ steps: workflowSteps, currentKey: jeStatus }}
        cards={[
          {
            title: 'Document Information',
            content: <div className="grid gap-3 sm:grid-cols-2">
              <label className="pxl-field-label">JE Date<input type="date" value={editJE?.je_date || today()} disabled={readOnly} onChange={e => setEditJE(v => ({ ...v, je_date: e.target.value }))} className={`${inputCls} mt-1`} /></label>
              <div><div className="pxl-field-label">Fiscal Period</div><div className="pxl-body-text mt-1">{selectedPeriod?.period_name || 'Assigned during posting'}</div></div>
              <div><div className="pxl-field-label">Branch</div><div className="pxl-body-text mt-1">{branchLabel}</div></div>
              <div><div className="pxl-field-label">Reference Type</div><div className="pxl-body-text mt-1">{editJE?.reference_doc_type || 'MANUAL'}</div></div>
            </div>,
          },
          {
            title: 'Accounting Context',
            content: <div className="grid gap-3 sm:grid-cols-2">
              <label className="pxl-field-label">Classification{readOnly ? <div className={`${inputCls} mt-1`}>{(editJE?.entry_class || 'regular').replace(/^\w/, c => c.toUpperCase())}</div> : <select value={editJE?.entry_class || 'regular'} onChange={e => setEditJE(v => ({ ...v, entry_class: e.target.value }))} className={`${inputCls} mt-1`}><option value="regular">Regular</option><option value="adjusting">Adjusting</option><option value="opening">Opening balance</option></select>}</label>
              <div><div className="pxl-field-label">Line Count</div><div className="pxl-body-text mt-1">{validLines.length} posting lines</div></div>
              <div><div className="pxl-field-label">Debit / Credit Rule</div><div className="pxl-body-text mt-1">One-sided amount per line</div></div>
              <div><div className="pxl-field-label">Balance Status</div><div className={`mt-1 text-xs font-semibold ${isBalanced ? 'text-green-700' : 'text-red-700'}`}>{isBalanced ? 'Balanced' : 'Out of balance'}</div></div>
            </div>,
          },
          {
            title: 'Posting Context',
            content: <div className="grid gap-3 sm:grid-cols-2">
              <div><div className="pxl-field-label">Posting Status</div><div className="pxl-body-text mt-1">{jeStatus}</div></div>
              <div><div className="pxl-field-label">Auto Reversal</div><div className="pxl-body-text mt-1">{editJE?.auto_reverse ? 'Enabled' : 'Disabled'}</div></div>
              {!readOnly && <label className="flex items-center gap-2 text-xs text-gray-700 sm:col-span-2"><input type="checkbox" checked={!!editJE?.auto_reverse} onChange={e => setEditJE(v => ({ ...v, auto_reverse: e.target.checked }))} />Auto-reverse at next period start</label>}
              <div><div className="pxl-field-label">Source Document</div><div className="pxl-body-text mt-1 font-mono">{editJE?.reference_doc_id || 'Manual entry'}</div></div>
              <div><div className="pxl-field-label">Reversal Journal</div><div className="pxl-body-text mt-1 font-mono">{editJE?.reversed_by_je_id || 'Not reversed'}</div></div>
            </div>,
          },
        ]}
        tabBadges={{ lines: lines.length }}
        tabContent={{
          lines: <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]">
            <div className="border-b border-[var(--pxl-border-medium)] px-3 py-2"><h2 className="pxl-section-title">Debit & Credit Lines</h2></div>
            <table className="pxl-data-grid w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Account', 'Line Description', 'Debit', 'Credit', ''].map(hh => (
                  <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Debit', 'Credit'].includes(hh) ? 'text-right' : 'text-left'}`}>{hh}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {lines.map(l => (
                <tr key={l._key}>
                  <td className="px-3 py-2">
                    <select value={l.account_id} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'account_id', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-64 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50">
                      <option value="">— select account —</option>
                      {accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                    </select>
                  </td>
                  <td className="px-3 py-2">
                    <input value={l.description} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'description', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-full focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-3 py-2">
                    <input type="number" min={0} value={l.debit_amount || ''} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'debit_amount', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-28 text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-3 py-2">
                    <input type="number" min={0} value={l.credit_amount || ''} disabled={readOnly}
                      onChange={e => updateLine(l._key, 'credit_amount', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-28 text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
                  </td>
                  <td className="px-3 py-2">
                    {!readOnly && lines.length > 2 && (
                      <button onClick={() => setLines(ls => ls.filter(x => x._key !== l._key))}
                        className="text-gray-400 hover:text-red-500 text-xs px-1">✕</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot className="border-t border-gray-200 bg-gray-50">
              <tr>
                <td className="px-3 py-2 text-right text-[10px] font-semibold uppercase tracking-wide text-gray-500" colSpan={2}>Totals</td>
                <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(totalDebit)}</td>
                <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(totalCredit)}</td>
                <td />
              </tr>
            </tfoot>
            </table>
            {!readOnly && <div className="flex items-center justify-between border-t border-[var(--pxl-border-medium)] px-4 py-2"><button onClick={() => setLines(ls => [...ls, newLine()])} className="pxl-button pxl-button--text">+ Add Line</button><span className={`text-xs font-semibold ${isBalanced ? 'text-green-700' : 'text-red-700'}`}>{isBalanced ? 'BALANCED ✓' : `OUT OF BALANCE: ${fmt(balance)}`}</span></div>}
          </div>,
          financial: <div className="ml-auto grid max-w-lg grid-cols-2 gap-2"><span className="text-gray-600">Total Debit</span><span className="text-right font-mono">₱{fmt(totalDebit)}</span><span className="text-gray-600">Total Credit</span><span className="text-right font-mono">₱{fmt(totalCredit)}</span><span className="pxl-section-title border-t pt-2">Difference</span><span className={`border-t pt-2 text-right font-mono font-bold ${isBalanced ? 'text-green-700' : 'text-red-700'}`}>₱{fmt(balance)}</span></div>,
          gl: <GLImpactPanel companyId={companyId} sourceDocType="MANUAL" sourceDocId={editJE?.id || null} previewRows={glPreviewRows} title="GL Impact — Manual Journal" />,
          tax: <TransactionEmptyState>No tax code fields are present on this Journal Entry. Tax impact is not inferred from account selection.</TransactionEmptyState>,
          validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{validationErrors.length > 0 ? validationErrors.map(message => <div key={message} className="pxl-validation-message border border-orange-200 bg-orange-50 text-orange-800">{message}</div>) : <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-800">Journal is balanced and ready to post.</div>}</div>,
          workflow: <ol className="grid gap-2 sm:grid-cols-3">{workflowSteps.map(step => <li key={step.key} className={`pxl-transaction-card p-3 text-xs font-semibold ${step.key === jeStatus ? 'ring-2 ring-[var(--pxl-transaction-accent)]' : ''}`}>{step.label}</li>)}</ol>,
          approval: <div className="grid gap-3 sm:grid-cols-3"><div><div className="pxl-field-label">Approval Status</div><div className="pxl-body-text mt-1">{jeStatus === 'draft' ? 'Posting authorization required' : 'Posting completed'}</div></div><div><div className="pxl-field-label">Segregation Control</div><div className="pxl-body-text mt-1">Driven by posting permissions</div></div><div><div className="pxl-field-label">Next Action</div><div className="pxl-body-text mt-1">{jeStatus === 'draft' ? 'Post Entry' : jeStatus === 'posted' ? 'Reverse when correction is required' : 'No action available'}</div></div></div>,
          audit: editJE?.id ? <div className="space-y-4"><div className="grid gap-3 sm:grid-cols-4">{auditFacts.map(fact => <div key={fact.label}><div className="pxl-field-label">{fact.label}</div><div className="pxl-body-text mt-1">{fact.value}</div></div>)}</div><AuditTrailSection tableName="journal_entries" recordId={editJE.id} /></div> : <TransactionEmptyState>Audit history begins when the Journal Entry is posted.</TransactionEmptyState>,
          related: editJE?.reference_doc_id || editJE?.reversed_by_je_id ? <table className="pxl-data-grid w-full"><thead><tr><th className="text-left">Relationship</th><th className="text-left">Document Type</th><th className="text-left">Document ID</th></tr></thead><tbody>{editJE?.reference_doc_id && <tr><td>Source</td><td>{editJE.reference_doc_type || 'Source document'}</td><td className="font-mono">{editJE.reference_doc_id}</td></tr>}{editJE?.reversed_by_je_id && <tr><td>Reversed by</td><td>Journal Entry</td><td className="font-mono">{editJE.reversed_by_je_id}</td></tr>}</tbody></table> : <TransactionEmptyState>This manual Journal Entry has no source or reversal document.</TransactionEmptyState>,
          party: <TransactionEmptyState>No entity dimension is stored on the current Journal Entry line model.</TransactionEmptyState>,
          activity: <div className="grid gap-3 sm:grid-cols-4">{auditFacts.map(fact => <div key={fact.label}><div className="pxl-field-label">{fact.label}</div><div className="pxl-body-text mt-1">{fact.value}</div></div>)}</div>,
          notes: <label className="pxl-field-label">Journal Description<textarea value={editJE?.description || ''} disabled={readOnly} rows={5} onChange={e => setEditJE(v => ({ ...v, description: e.target.value }))} className={`${inputCls} mt-1`} /></label>,
          system: <SystemMetadataPanel facts={[
            { label: 'Internal ID', value: editJE?.id || 'Assigned during posting', hint: 'Transaction identity' },
            { label: 'Journal Number', value: editJE?.je_number || 'Generated from number series', hint: 'Journal identity' },
            { label: 'Company ID', value: companyId || '—', hint: 'Tenant boundary' },
            { label: 'Branch ID', value: editJE?.branch_id || branchId || '—', hint: 'Posting context' },
            { label: 'Fiscal Period', value: selectedPeriod?.period_name || editJE?.fiscal_period_id || 'Assigned during posting', hint: 'Period control' },
            { label: 'Created', value: formatDateTime(editJE?.created_at), hint: 'Audit metadata' },
            { label: 'Updated', value: formatDateTime(editJE?.updated_at), hint: 'Audit metadata' },
            { label: 'Lock Status', value: jeStatus === 'draft' ? 'Editable draft' : 'Immutable; reverse to correct', hint: 'Lifecycle control' },
          ]} />,
        }}
        emptyTabMessages={{ attachments: 'No attachments have been added to this Journal Entry.' }}
        sidebarPanels={[
          { key: 'balance', title: 'Balance', content: <div className="space-y-2"><div className="flex justify-between gap-3"><span className="pxl-field-label">Debit</span><span className="font-mono text-xs">₱{fmt(totalDebit)}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Credit</span><span className="font-mono text-xs">₱{fmt(totalCredit)}</span></div><div className="flex justify-between gap-3"><span className="pxl-field-label">Difference</span><span className={`font-mono text-xs font-bold ${isBalanced ? 'text-green-700' : 'text-red-700'}`}>₱{fmt(balance)}</span></div></div> },
          { key: 'posting', title: 'Posting', content: <div><div className="text-xs font-semibold">{jeStatus}</div><div className="pxl-caption mt-1">{jeStatus === 'draft' ? 'Requires balanced lines and posting permission.' : 'Posted entries are immutable.'}</div></div> },
          { key: 'audit', title: 'Audit', content: <div className="pxl-caption">{editJE?.updated_at ? `Updated ${formatDateTime(editJE.updated_at)}` : 'Unsaved journal'}</div> },
        ]}
        footer={<span>{jeStatus === 'draft' ? 'Editable draft' : 'Posted entries are immutable — reverse to correct'} · Updated {formatDateTime(editJE?.updated_at)}</span>}
        onBack={() => setMode('list')}
        backLabel="Journal Entries"
      />
    </>
  )
}
