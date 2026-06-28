import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type COA = {
  id: string; company_id: string; account_code: string; account_name: string
  parent_id: string | null; account_type: string; normal_balance: string
  is_postable: boolean; currency_code: string | null; is_active: boolean; depth?: number
  companies?: { registered_name: string }; parent?: { account_name: string; account_code: string }
}

const ACCOUNT_TYPES = [
  { value: 'asset', label: 'Asset' },
  { value: 'liability', label: 'Liability' },
  { value: 'equity', label: 'Equity' },
  { value: 'revenue', label: 'Revenue' },
  { value: 'expense', label: 'Expense' },
]
const TYPE_COLORS: Record<string, string> = {
  asset: 'bg-blue-50 text-blue-700',
  liability: 'bg-red-50 text-red-700',
  equity: 'bg-purple-50 text-purple-700',
  revenue: 'bg-green-50 text-green-700',
  expense: 'bg-orange-50 text-orange-700',
}
const NORMAL_BALANCE: Record<string, string> = {
  asset: 'debit', expense: 'debit', liability: 'credit', equity: 'credit', revenue: 'credit',
}

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function ChartOfAccountsPage() {
  const [accounts, setAccounts] = useState<COA[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [filterCompany, setFilterCompany] = useState('')
  const [filterType, setFilterType] = useState('')
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState({ company_id: '', account_code: '', account_name: '', parent_id: '', account_type: 'asset', normal_balance: 'debit', is_postable: true, currency_code: '' })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const fetchAccounts = async () => {
    const { data } = await supabase.from('chart_of_accounts')
      .select('*, companies(registered_name), parent:parent_id(account_name, account_code)')
      .order('account_code')
    setAccounts((data as COA[]) || [])
  }
  useEffect(() => {
    fetchAccounts()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
  }, [])

  const set = (k: string, v: string | boolean) => {
    setSaved(false)
    setForm(f => {
      const next = { ...f, [k]: v }
      if (k === 'account_type') next.normal_balance = NORMAL_BALANCE[v as string] || 'debit'
      return next
    })
  }

  const openEdit = (a: COA) => {
    setForm({ company_id: a.company_id, account_code: a.account_code, account_name: a.account_name, parent_id: a.parent_id || '', account_type: a.account_type, normal_balance: a.normal_balance, is_postable: a.is_postable, currency_code: a.currency_code || '' })
    setEditId(a.id); setShowForm(true); setSaved(false)
  }

  const handleSave = async () => {
    setSaving(true)
    const payload = { company_id: form.company_id, account_code: form.account_code, account_name: form.account_name, parent_id: form.parent_id || null, account_type: form.account_type, normal_balance: form.normal_balance, is_postable: form.is_postable, currency_code: form.currency_code || null }
    const { error } = editId
      ? await supabase.from('chart_of_accounts').update(payload).eq('id', editId)
      : await supabase.from('chart_of_accounts').insert([payload])
    if (error) alert('Error: ' + error.message)
    else { setSaved(true); fetchAccounts() }
    setSaving(false)
  }

  const toggleActive = async (a: COA) => {
    await supabase.from('chart_of_accounts').update({ is_active: !a.is_active }).eq('id', a.id)
    fetchAccounts()
  }

  if (showForm) {
    const parentCandidates = accounts.filter(a => a.company_id === form.company_id && !a.is_postable && a.id !== editId)
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
            <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Account' : 'Create Account'}</h1>
          </div>
          <div className="flex gap-2">
            <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
            <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
              {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update Account' : 'Save Account'}
            </button>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Account Identity</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
              <select value={form.company_id} onChange={e => set('company_id', e.target.value)} className={inp}>
                <option value="">Select company...</option>
                {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select></div>
            <div><label className={lbl}>Account Type <span className="text-red-500">*</span></label>
              <select value={form.account_type} onChange={e => set('account_type', e.target.value)} className={inp}>
                {ACCOUNT_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
              </select></div>
            <div><label className={lbl}>Account Code <span className="text-red-500">*</span></label>
              <input value={form.account_code} onChange={e => set('account_code', e.target.value)} className={inp} placeholder="e.g., 1000, 1100, 1110" /></div>
            <div><label className={lbl}>Account Name <span className="text-red-500">*</span></label>
              <input value={form.account_name} onChange={e => set('account_name', e.target.value)} className={inp} placeholder="e.g., Cash and Cash Equivalents" /></div>
            <div><label className={lbl}>Parent Account</label>
              <select value={form.parent_id} onChange={e => set('parent_id', e.target.value)} className={inp}>
                <option value="">None (Header Account)</option>
                {parentCandidates.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select></div>
            <div><label className={lbl}>Normal Balance</label>
              <select value={form.normal_balance} onChange={e => set('normal_balance', e.target.value)} className={inp}>
                <option value="debit">Debit</option>
                <option value="credit">Credit</option>
              </select></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Posting & Currency</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Currency (blank = functional currency PHP)</label>
              <input value={form.currency_code} onChange={e => set('currency_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., USD — leave blank for PHP" maxLength={3} /></div>
            <div className="flex items-center gap-2 pt-6">
              <input type="checkbox" id="is_postable" checked={form.is_postable} onChange={e => set('is_postable', e.target.checked)} className="rounded border-gray-300" />
              <label htmlFor="is_postable" className="text-sm text-gray-700">Postable account (allow journal entries to post to this account)</label>
            </div>
          </div>
        </div>
      </div>
    )
  }

  const filtered = accounts.filter(a => {
    const m = !search || a.account_code.toLowerCase().includes(search.toLowerCase()) || a.account_name.toLowerCase().includes(search.toLowerCase())
    const c = !filterCompany || a.company_id === filterCompany
    const t = !filterType || a.account_type === filterType
    return m && c && t
  })
  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Chart of Accounts</h1>
        <p className="text-sm text-gray-500 mt-0.5">Double-entry account structure for general ledger</p></div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-56 focus:outline-none focus:ring-2 focus:ring-gray-900" placeholder="Search by code or name..." />
        <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        <select value={filterType} onChange={e => setFilterType(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Types</option>
          {ACCOUNT_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
        <div className="ml-auto">
          <button onClick={() => { setForm({ company_id: '', account_code: '', account_name: '', parent_id: '', account_type: 'asset', normal_balance: 'debit', is_postable: true, currency_code: '' }); setEditId(null); setShowForm(true); setSaved(false) }}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create Account
          </button>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Code</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Account Name</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Normal Balance</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Parent</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Postable</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.length === 0
              ? <tr><td colSpan={8} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Accounts Found</p><p className="text-sm mt-1">Create your chart of accounts structure.</p></td></tr>
              : filtered.map((a, i) => (
                <tr key={a.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{a.account_code}</td>
                  <td className="px-4 py-3 text-gray-900">{a.parent_id ? <span className="pl-4 text-gray-700">{a.account_name}</span> : <span className="font-medium">{a.account_name}</span>}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${TYPE_COLORS[a.account_type] || 'bg-gray-100 text-gray-600'}`}>{ACCOUNT_TYPES.find(t => t.value === a.account_type)?.label}</span></td>
                  <td className="px-4 py-3 text-gray-600 capitalize">{a.normal_balance}</td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{a.parent ? `${(a.parent as COA).account_code} ${(a.parent as COA).account_name}` : '—'}</td>
                  <td className="px-4 py-3 text-center">{a.is_postable ? <span className="text-green-600 text-xs font-medium">Yes</span> : <span className="text-gray-400 text-xs">No</span>}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${a.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{a.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openEdit(a)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleActive(a)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{a.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
          </tbody>
        </table>
        {filtered.length > 0 && <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">Showing {filtered.length} of {accounts.length} accounts</div>}
      </div>
    </div>
  )
}
