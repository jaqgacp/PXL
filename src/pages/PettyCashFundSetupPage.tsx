import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

type COARef = { id: string; account_code: string; account_name: string }
type Fund = {
  id: string; company_id: string; branch_id: string | null
  fund_name: string; custodian_name: string
  authorized_amount: number; replenishment_threshold: number | null
  gl_account_id: string; is_active: boolean
  chart_of_accounts?: { account_code: string; account_name: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full'

export default function PettyCashFundSetupPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<Fund[]>([])
  const [coa, setCoa] = useState<COARef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'form'>('list')
  const [form, setForm] = useState<Partial<Fund> | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('petty_cash_funds')
      .select('*,chart_of_accounts(account_code,account_name)')
      .eq('company_id', companyId).order('fund_name')
    setRows((data as Fund[]) || [])
    setLoading(false)
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('chart_of_accounts').select('id,account_code,account_name')
      .eq('company_id', companyId).eq('is_active', true).eq('account_type', 'asset').order('account_code')
    setCoa((data as COARef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const openNew = () => { setForm({ company_id: companyId, branch_id: branchId || null, is_active: true, authorized_amount: 0 }); setError(''); setMode('form') }
  const openEdit = (r: Fund) => { setForm({ ...r }); setError(''); setMode('form') }

  const save = async () => {
    if (!companyId || !form) return
    if (!form.fund_name || !form.custodian_name || !form.gl_account_id || !form.authorized_amount) {
      setError('Fund name, custodian, authorized amount and GL account are required'); return
    }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const payload = {
        company_id: companyId, branch_id: form.branch_id || null,
        fund_name: form.fund_name, custodian_name: form.custodian_name,
        authorized_amount: Number(form.authorized_amount) || 0,
        replenishment_threshold: form.replenishment_threshold != null ? Number(form.replenishment_threshold) : null,
        gl_account_id: form.gl_account_id, is_active: form.is_active ?? true, updated_by: uid,
      }
      const res = form.id
        ? await supabase.from('petty_cash_funds').update(payload).eq('id', form.id)
        : await supabase.from('petty_cash_funds').insert([{ ...payload, created_by: uid }])
      if (res.error) throw res.error
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false) }
  }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Petty Cash Fund Setup</span>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Fund</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? (
        <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No petty cash funds</p>
          <p className="text-xs text-gray-400 mt-1">Set up an imprest fund to track petty cash.</p></div>
      ) : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['Fund Name','Custodian','Authorized','Threshold','GL Account','Active',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Authorized','Threshold'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className={`hover:bg-gray-50/60 ${!r.is_active ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 text-xs font-semibold text-gray-900">{r.fund_name}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.custodian_name}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(r.authorized_amount)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-500">{r.replenishment_threshold != null ? fmt(r.replenishment_threshold) : '—'}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.chart_of_accounts?.account_code || '—'}</td>
                <td className="px-3 py-2.5"><StatusBadge status={r.is_active ? 'active' : 'inactive'} /></td>
                <td className="px-3 py-2.5 text-right"><button onClick={() => openEdit(r)} className="text-xs text-gray-500 hover:text-gray-900">Edit</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )

  return (
    <div className="flex flex-col h-full">
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-2">
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-semibold text-gray-700">{form?.id ? 'Edit Fund' : 'New Fund'}</span>
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          <button onClick={save} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving…' : 'Save'}</button>
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg p-5 grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-3xl">
          <Field label="Fund Name *"><input className={inputCls} value={form?.fund_name || ''} onChange={e => setForm(f => ({ ...f, fund_name: e.target.value }))} /></Field>
          <Field label="Custodian *"><input className={inputCls} value={form?.custodian_name || ''} onChange={e => setForm(f => ({ ...f, custodian_name: e.target.value }))} /></Field>
          <Field label="Authorized Amount *"><input type="number" className={inputCls} value={form?.authorized_amount ?? 0} onChange={e => setForm(f => ({ ...f, authorized_amount: parseFloat(e.target.value) || 0 }))} /></Field>
          <Field label="Replenishment Threshold"><input type="number" className={inputCls} value={form?.replenishment_threshold ?? ''} onChange={e => setForm(f => ({ ...f, replenishment_threshold: e.target.value === '' ? null : parseFloat(e.target.value) }))} /></Field>
          <Field label="GL Account *">
            <select className={inputCls} value={form?.gl_account_id || ''} onChange={e => setForm(f => ({ ...f, gl_account_id: e.target.value }))}>
              <option value="">— select asset account —</option>
              {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
            </select>
          </Field>
          <div className="flex items-end">
            <label className="flex items-center gap-2 text-sm text-gray-700"><input type="checkbox" checked={form?.is_active ?? true} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} />Active</label>
          </div>
        </div>
      </div>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>
      {children}
    </div>
  )
}
