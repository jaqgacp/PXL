import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

type COARef = { id: string; account_code: string; account_name: string }
type Currency = { id: string; currency_code: string }
type BankAccount = {
  id: string; company_id: string; branch_id: string | null
  bank_name: string; bank_branch: string | null
  account_number: string; account_name: string; account_type: string
  currency_id: string | null; gl_account_id: string
  is_primary: boolean; is_active: boolean; opening_balance: number; notes: string | null
  currencies?: { currency_code: string } | null
  chart_of_accounts?: { account_code: string; account_name: string } | null
}

const ACCOUNT_TYPES = ['checking', 'savings', 'time_deposit', 'money_market']
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full'

export default function BankAccountsPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<BankAccount[]>([])
  const [coa, setCoa] = useState<COARef[]>([])
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'form'>('list')
  const [form, setForm] = useState<Partial<BankAccount> | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('bank_accounts')
      .select('*,currencies(currency_code),chart_of_accounts(account_code,account_name)')
      .eq('company_id', companyId).order('bank_name')
    setRows((data as BankAccount[]) || [])
    setLoading(false)
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [coaRes, curRes] = await Promise.all([
      supabase.from('chart_of_accounts').select('id,account_code,account_name')
        .eq('company_id', companyId).eq('is_active', true).eq('account_type', 'asset').order('account_code'),
      supabase.from('currencies').select('id,currency_code').eq('is_active', true).order('currency_code'),
    ])
    setCoa((coaRes.data as COARef[]) || [])
    setCurrencies((curRes.data as Currency[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const openNew = () => {
    setForm({ company_id: companyId, branch_id: branchId || null, account_type: 'checking', is_primary: false, is_active: true, opening_balance: 0 })
    setError(''); setMode('form')
  }
  const openEdit = (r: BankAccount) => { setForm({ ...r }); setError(''); setMode('form') }

  const toggleActive = async (r: BankAccount) => {
    await supabase.from('bank_accounts').update({ is_active: !r.is_active, updated_by: (await supabase.auth.getUser()).data.user?.id }).eq('id', r.id)
    await load()
  }

  const save = async () => {
    if (!companyId || !form) return
    if (!form.bank_name || !form.account_number || !form.account_name || !form.gl_account_id) {
      setError('Bank name, account number, account name and GL account are required'); return
    }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const payload = {
        company_id: companyId, branch_id: form.branch_id || null,
        bank_name: form.bank_name, bank_branch: form.bank_branch || null,
        account_number: form.account_number, account_name: form.account_name,
        account_type: form.account_type || 'checking',
        currency_id: form.currency_id || null, gl_account_id: form.gl_account_id,
        is_primary: !!form.is_primary, is_active: form.is_active ?? true,
        opening_balance: Number(form.opening_balance) || 0, notes: form.notes || null,
        updated_by: uid,
      }
      const res = form.id
        ? await supabase.from('bank_accounts').update(payload).eq('id', form.id)
        : await supabase.from('bank_accounts').insert([{ ...payload, created_by: uid }])
      if (res.error) throw res.error
      await load(); setMode('list')
    } catch (e) {
      setError((e as Error).message || 'Save failed')
    } finally { setSaving(false) }
  }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Bank Accounts</span>
        <button onClick={openNew} disabled={!companyId}
          className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Bank Account</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? (
        <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No bank accounts</p>
          <p className="text-xs text-gray-400 mt-1">Add a bank account to begin treasury operations.</p></div>
      ) : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['Bank Name','Branch','Account Number','Account Name','Type','Currency','GL Account','Primary','Active',''].map(h =>
              <th key={h} className="px-3 py-2.5 text-left text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className={`hover:bg-gray-50/60 ${!r.is_active ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 text-xs font-semibold text-gray-900">{r.bank_name}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{r.bank_branch || '—'}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-700">{r.account_number}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700 max-w-[160px] truncate">{r.account_name}</td>
                <td className="px-3 py-2.5 text-xs"><StatusBadge status={r.account_type} label={r.account_type.replace(/_/g, ' ')} /></td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{r.currencies?.currency_code || '—'}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.chart_of_accounts ? `${r.chart_of_accounts.account_code}` : '—'}</td>
                <td className="px-3 py-2.5 text-xs text-center">{r.is_primary ? '★' : ''}</td>
                <td className="px-3 py-2.5"><StatusBadge status={r.is_active ? 'active' : 'inactive'} /></td>
                <td className="px-3 py-2.5 text-right whitespace-nowrap">
                  <button onClick={() => openEdit(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-3">Edit</button>
                  <button onClick={() => toggleActive(r)} className="text-xs text-gray-400 hover:text-gray-700">{r.is_active ? 'Deactivate' : 'Activate'}</button>
                </td>
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
        <span className="text-sm font-semibold text-gray-700">{form?.id ? 'Edit Bank Account' : 'New Bank Account'}</span>
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          <button onClick={save} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving…' : 'Save'}</button>
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg p-5 grid grid-cols-1 sm:grid-cols-3 gap-4 max-w-4xl">
          <Field label="Bank Name *"><input className={inputCls} value={form?.bank_name || ''} onChange={e => setForm(f => ({ ...f, bank_name: e.target.value }))} /></Field>
          <Field label="Bank Branch"><input className={inputCls} value={form?.bank_branch || ''} onChange={e => setForm(f => ({ ...f, bank_branch: e.target.value }))} /></Field>
          <Field label="Account Number *"><input className={inputCls} value={form?.account_number || ''} onChange={e => setForm(f => ({ ...f, account_number: e.target.value }))} /></Field>
          <Field label="Account Name *"><input className={inputCls} value={form?.account_name || ''} onChange={e => setForm(f => ({ ...f, account_name: e.target.value }))} /></Field>
          <Field label="Account Type">
            <select className={inputCls} value={form?.account_type || 'checking'} onChange={e => setForm(f => ({ ...f, account_type: e.target.value }))}>
              {ACCOUNT_TYPES.map(t => <option key={t} value={t}>{t.replace(/_/g, ' ')}</option>)}
            </select>
          </Field>
          <Field label="Currency">
            <select className={inputCls} value={form?.currency_id || ''} onChange={e => setForm(f => ({ ...f, currency_id: e.target.value }))}>
              <option value="">—</option>
              {currencies.map(c => <option key={c.id} value={c.id}>{c.currency_code}</option>)}
            </select>
          </Field>
          <Field label="GL Account *">
            <select className={inputCls} value={form?.gl_account_id || ''} onChange={e => setForm(f => ({ ...f, gl_account_id: e.target.value }))}>
              <option value="">— select asset account —</option>
              {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
            </select>
          </Field>
          <Field label="Opening Balance"><input type="number" className={inputCls} value={form?.opening_balance ?? 0} onChange={e => setForm(f => ({ ...f, opening_balance: parseFloat(e.target.value) || 0 }))} /></Field>
          <div className="flex items-end gap-4">
            <label className="flex items-center gap-2 text-sm text-gray-700"><input type="checkbox" checked={!!form?.is_primary} onChange={e => setForm(f => ({ ...f, is_primary: e.target.checked }))} />Primary</label>
            <label className="flex items-center gap-2 text-sm text-gray-700"><input type="checkbox" checked={form?.is_active ?? true} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} />Active</label>
          </div>
          <Field label="Notes" full><textarea className={inputCls} rows={2} value={form?.notes || ''} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))} /></Field>
        </div>
        {form?.opening_balance ? <div className="mt-3 text-xs text-gray-400">Opening balance: {fmt(Number(form.opening_balance))}</div> : null}
      </div>
    </div>
  )
}

function Field({ label, children, full }: { label: string; children: React.ReactNode; full?: boolean }) {
  return (
    <div className={`flex flex-col gap-1 ${full ? 'sm:col-span-3' : ''}`}>
      <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>
      {children}
    </div>
  )
}
