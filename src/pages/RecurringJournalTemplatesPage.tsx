import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { TablesInsert } from '@/lib/database.types'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

type Recurrence = 'monthly' | 'quarterly' | 'semi_annual' | 'annual'

type Template = {
  id: string; company_id: string; branch_id: string | null
  template_name: string; description: string | null
  recurrence_type: Recurrence; day_of_month: number
  next_run_date: string | null; last_run_date: string | null
  start_date: string; end_date: string | null
  auto_reverse: boolean; is_active: boolean
}

type TLine = {
  _key: string; id?: string
  account_id: string; description: string; debit_amount: number; credit_amount: number
}

type COARef = { id: string; account_code: string; account_name: string }

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const newLine = (): TLine => ({ _key: crypto.randomUUID(), account_id: '', description: '', debit_amount: 0, credit_amount: 0 })

const RECURRENCE_LABEL: Record<Recurrence, string> = {
  monthly: 'Monthly', quarterly: 'Quarterly', semi_annual: 'Semi-Annual', annual: 'Annual',
}

export default function RecurringJournalTemplatesPage() {
  const { companyId, branchId } = useAppCtx()
  const [templates, setTemplates] = useState<Template[]>([])
  const [lineCounts, setLineCounts] = useState<Record<string, number>>({})
  const [accounts, setAccounts] = useState<COARef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit'>('list')

  const [edit, setEdit] = useState<Partial<Template> | null>(null)
  const [lines, setLines] = useState<TLine[]>([newLine(), newLine()])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  // execute modal
  const [execTarget, setExecTarget] = useState<Template | null>(null)
  const [execDate, setExecDate] = useState(today())
  const [executing, setExecuting] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('recurring_journal_templates').select('*')
      .eq('company_id', companyId).order('template_name')
    const tpls = (data as Template[]) || []
    setTemplates(tpls)
    if (tpls.length) {
      const { data: lc } = await supabase.from('recurring_journal_template_lines')
        .select('template_id').in('template_id', tpls.map(t => t.id))
      const counts: Record<string, number> = {}
      for (const r of (lc as any[]) || []) counts[r.template_id] = (counts[r.template_id] || 0) + 1
      setLineCounts(counts)
    } else {
      setLineCounts({})
    }
    setLoading(false)
  }, [companyId])

  const loadAccounts = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('chart_of_accounts').select('id,account_code,account_name')
      .eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code')
    setAccounts((data as COARef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadAccounts() } }, [load, loadAccounts, companyId])

  const openNew = () => {
    setEdit({ company_id: companyId!, branch_id: branchId || null, template_name: '', recurrence_type: 'monthly',
      day_of_month: 1, start_date: today(), auto_reverse: false, is_active: true })
    setLines([newLine(), newLine()])
    setError('')
    setMode('edit')
  }

  const openEdit = async (t: Template) => {
    setEdit(t)
    const { data } = await supabase.from('recurring_journal_template_lines')
      .select('id,account_id,description,debit_amount,credit_amount,line_number')
      .eq('template_id', t.id).order('line_number')
    setLines(((data as any[]) || []).map(l => ({
      _key: l.id, id: l.id, account_id: l.account_id, description: l.description || '',
      debit_amount: Number(l.debit_amount), credit_amount: Number(l.credit_amount),
    })))
    setError('')
    setMode('edit')
  }

  const updateLine = (key: string, field: keyof TLine, raw: string) => {
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
  const canSave = !!edit?.template_name && isBalanced && totalDebit > 0 && validLines.length >= 2

  const save = async () => {
    if (!companyId || !edit) return
    if (!canSave) { setError('Template must be named, balanced, and have at least 2 valid lines'); return }
    setSaving(true); setError('')
    try {
      const header = {
        company_id: companyId,
        branch_id: edit.branch_id || branchId || null,
        template_name: edit.template_name,
        description: edit.description || null,
        recurrence_type: edit.recurrence_type || 'monthly',
        day_of_month: edit.day_of_month || 1,
        start_date: edit.start_date || today(),
        end_date: edit.end_date || null,
        auto_reverse: !!edit.auto_reverse,
        is_active: edit.is_active ?? true,
        next_run_date: edit.next_run_date || edit.start_date || today(),
      }
      let templateId = edit.id
      if (templateId) {
        const { error: e } = await supabase.from('recurring_journal_templates').update(header).eq('id', templateId)
        if (e) throw e
        await supabase.from('recurring_journal_template_lines').delete().eq('template_id', templateId)
      } else {
        const { data, error: e } = await supabase.from('recurring_journal_templates').insert(header as TablesInsert<'recurring_journal_templates'>).select('id').single()
        if (e) throw e
        templateId = (data as any).id
      }
      const linePayload = validLines.map((l, i) => ({
        template_id: templateId, company_id: companyId, line_number: i + 1,
        account_id: l.account_id, description: l.description || null,
        debit_amount: l.debit_amount, credit_amount: l.credit_amount,
      }))
      const { error: le } = await supabase.from('recurring_journal_template_lines').insert(linePayload as TablesInsert<'recurring_journal_template_lines'>[])
      if (le) throw le
      await load()
      setMode('list')
    } catch (e: any) {
      setError(e.message || 'Save failed')
    } finally { setSaving(false) }
  }

  const toggleActive = async (t: Template) => {
    await supabase.from('recurring_journal_templates').update({ is_active: !t.is_active }).eq('id', t.id)
    await load()
  }

  const doExecute = async () => {
    if (!execTarget) return
    setExecuting(true); setError('')
    try {
      const { error: e } = await supabase.rpc('fn_execute_recurring_template', {
        p_template_id: execTarget.id, p_je_date: execDate,
      })
      if (e) throw e
      setExecTarget(null)
      await load()
    } catch (e: any) {
      setError(e.message || 'Execution failed')
      setExecTarget(null)
    } finally { setExecuting(false) }
  }

  const inputCls = `border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full`

  // execute modal
  const execModal = execTarget && (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/40" onClick={() => setExecTarget(null)} />
      <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-md p-6 z-10">
        <h2 className="text-base font-semibold text-gray-900 mb-1">Execute {execTarget.template_name}</h2>
        <p className="text-sm text-gray-600 mb-4">A balanced journal entry will be posted for the date below.</p>
        <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Posting Date</label>
        <input type="date" value={execDate} onChange={e => setExecDate(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-2 text-sm w-full mt-1 mb-4 focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <div className="flex justify-end gap-2">
          <button onClick={() => setExecTarget(null)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={doExecute} disabled={executing}
            className="px-4 py-2 rounded-md text-sm font-medium text-white bg-gray-900 hover:bg-gray-800 disabled:opacity-50">
            {executing ? 'Posting…' : 'Execute'}
          </button>
        </div>
      </div>
    </div>
  )

  // ── List ──────────────────────────────────────────────────────
  if (mode === 'list') return (
    <div>
      {execModal}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Recurring Journal Templates</span>
        {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
        <button onClick={openNew} disabled={!companyId}
          className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">+ New Template</button>
      </div>

      {loading ? (
        <div className="py-16 text-center text-sm text-gray-400">Loading…</div>
      ) : templates.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">No recurring templates</p>
          <p className="text-xs text-gray-400 mt-1">Create a template to automate periodic journal entries.</p>
        </div>
      ) : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              {['Template Name', 'Description', 'Recurrence', 'Next Run', 'Last Run', 'Lines', 'Active', ''].map(hh => (
                <th key={hh} className="px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{hh}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {templates.map(t => {
              const due = t.is_active && t.next_run_date && t.next_run_date <= today()
              return (
                <tr key={t.id} className="hover:bg-gray-50/60">
                  <td className="px-3 py-2.5 font-medium text-gray-900">{t.template_name}</td>
                  <td className="px-3 py-2.5 text-xs text-gray-500 max-w-[200px] truncate">{t.description || '—'}</td>
                  <td className="px-3 py-2.5 text-xs text-gray-600">{RECURRENCE_LABEL[t.recurrence_type]}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{t.next_run_date || '—'}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{t.last_run_date || '—'}</td>
                  <td className="px-3 py-2.5 text-xs text-gray-600 tabular-nums">{lineCounts[t.id] || 0}</td>
                  <td className="px-3 py-2.5"><StatusBadge status={t.is_active ? 'active' : 'inactive'} /></td>
                  <td className="px-3 py-2.5 text-right whitespace-nowrap">
                    <button onClick={() => openEdit(t)} className="text-xs text-gray-600 hover:text-gray-900 font-medium mr-3">Edit</button>
                    {t.is_active && (
                      <button onClick={() => { setExecTarget(t); setExecDate(t.next_run_date || today()) }}
                        className={`text-xs font-medium mr-3 ${due ? 'text-green-700 hover:text-green-900' : 'text-gray-500 hover:text-gray-800'}`}>Execute</button>
                    )}
                    <button onClick={() => toggleActive(t)} className="text-xs text-gray-500 hover:text-gray-800 font-medium">
                      {t.is_active ? 'Deactivate' : 'Activate'}
                    </button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
    </div>
  )

  // ── Edit ──────────────────────────────────────────────────────
  return (
    <div className="flex flex-col h-full">
      {execModal}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-2 flex-wrap">
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-semibold text-gray-700">{edit?.id ? edit.template_name : 'New Template'}</span>
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          <button onClick={save} disabled={saving || !canSave}
            className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {saving ? 'Saving…' : 'Save Template'}
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg p-5 mb-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="flex flex-col gap-1">
              <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Template Name *</label>
              <input value={edit?.template_name || ''} onChange={e => setEdit(v => ({ ...v, template_name: e.target.value }))} className={inputCls} />
            </div>
            <div className="flex flex-col gap-1 sm:col-span-2">
              <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Description</label>
              <input value={edit?.description || ''} onChange={e => setEdit(v => ({ ...v, description: e.target.value }))} className={inputCls} />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Recurrence *</label>
              <select value={edit?.recurrence_type || 'monthly'} onChange={e => setEdit(v => ({ ...v, recurrence_type: e.target.value as Recurrence }))} className={inputCls}>
                <option value="monthly">Monthly</option>
                <option value="quarterly">Quarterly</option>
                <option value="semi_annual">Semi-Annual</option>
                <option value="annual">Annual</option>
              </select>
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Day of Month * (1–28)</label>
              <input type="number" min={1} max={28} value={edit?.day_of_month || 1}
                onChange={e => setEdit(v => ({ ...v, day_of_month: Math.min(28, Math.max(1, parseInt(e.target.value) || 1)) }))} className={inputCls} />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Start Date *</label>
              <input type="date" value={edit?.start_date || today()} onChange={e => setEdit(v => ({ ...v, start_date: e.target.value }))} className={inputCls} />
            </div>
            <div className="flex flex-col gap-1">
              <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">End Date</label>
              <input type="date" value={edit?.end_date || ''} onChange={e => setEdit(v => ({ ...v, end_date: e.target.value || null }))} className={inputCls} />
            </div>
            <label className="flex items-center gap-2 text-sm text-gray-700 mt-5">
              <input type="checkbox" checked={!!edit?.auto_reverse} onChange={e => setEdit(v => ({ ...v, auto_reverse: e.target.checked }))} />
              Auto-reverse next period
            </label>
          </div>
        </div>

        {/* Lines */}
        <div className="bg-white border border-gray-200 rounded-lg mb-4 overflow-x-auto">
          <div className="px-4 py-2.5 border-b border-gray-100">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Template Lines</span>
          </div>
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Account', 'Description', 'Debit', 'Credit', ''].map(hh => (
                  <th key={hh} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Debit', 'Credit'].includes(hh) ? 'text-right' : 'text-left'}`}>{hh}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {lines.map(l => (
                <tr key={l._key}>
                  <td className="px-3 py-2">
                    <select value={l.account_id} onChange={e => updateLine(l._key, 'account_id', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-64 focus:outline-none focus:ring-1 focus:ring-gray-900">
                      <option value="">— select account —</option>
                      {accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                    </select>
                  </td>
                  <td className="px-3 py-2">
                    <input value={l.description} onChange={e => updateLine(l._key, 'description', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-full focus:outline-none focus:ring-1 focus:ring-gray-900" />
                  </td>
                  <td className="px-3 py-2">
                    <input type="number" min={0} value={l.debit_amount || ''} onChange={e => updateLine(l._key, 'debit_amount', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-28 text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-gray-900" />
                  </td>
                  <td className="px-3 py-2">
                    <input type="number" min={0} value={l.credit_amount || ''} onChange={e => updateLine(l._key, 'credit_amount', e.target.value)}
                      className="border border-gray-300 rounded px-2 py-1 text-xs w-28 text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-gray-900" />
                  </td>
                  <td className="px-3 py-2">
                    {lines.length > 2 && (
                      <button onClick={() => setLines(ls => ls.filter(x => x._key !== l._key))} className="text-gray-400 hover:text-red-500 text-xs px-1">✕</button>
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
          <div className="px-4 py-2 border-t border-gray-100 flex items-center justify-between">
            <button onClick={() => setLines(ls => [...ls, newLine()])} className="text-xs text-gray-500 hover:text-gray-900 font-medium">+ Add Line</button>
            <span className={`text-xs font-semibold ${isBalanced ? 'text-green-600' : 'text-red-600'}`}>
              {isBalanced ? 'BALANCED ✓' : `OUT OF BALANCE: ${fmt(balance)}`}
            </span>
          </div>
        </div>
      </div>
    </div>
  )
}
