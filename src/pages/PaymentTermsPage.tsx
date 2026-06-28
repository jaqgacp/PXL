import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type PaymentTerm = {
  id: string; company_id: string; term_code: string; term_name: string
  days_to_due: number; require_downpayment: boolean; dp_percentage: number | null; is_active: boolean
  companies?: { registered_name: string }
}

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

const COMMON_TERMS = [
  { code: 'COD', name: 'Cash on Delivery', days: 0 },
  { code: 'NET7', name: 'Net 7 Days', days: 7 },
  { code: 'NET15', name: 'Net 15 Days', days: 15 },
  { code: 'NET30', name: 'Net 30 Days', days: 30 },
  { code: 'NET45', name: 'Net 45 Days', days: 45 },
  { code: 'NET60', name: 'Net 60 Days', days: 60 },
  { code: 'DP50', name: '50% Downpayment, Balance upon Delivery', days: 0 },
]

export default function PaymentTermsPage() {
  const [terms, setTerms] = useState<PaymentTerm[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [search, setSearch] = useState('')
  const [filterCompany, setFilterCompany] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState({ company_id: '', term_code: '', term_name: '', days_to_due: '0', require_downpayment: false, dp_percentage: '' })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const fetchTerms = async () => {
    const { data } = await supabase.from('payment_terms').select('*, companies(registered_name)').order('term_code')
    setTerms((data as PaymentTerm[]) || [])
  }
  useEffect(() => {
    fetchTerms()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
  }, [])

  const set = (k: string, v: string | boolean) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const openEdit = (t: PaymentTerm) => {
    setForm({ company_id: t.company_id, term_code: t.term_code, term_name: t.term_name, days_to_due: String(t.days_to_due), require_downpayment: t.require_downpayment, dp_percentage: t.dp_percentage ? String(t.dp_percentage) : '' })
    setEditId(t.id); setShowForm(true); setSaved(false)
  }

  const quickFill = (ct: typeof COMMON_TERMS[number]) => {
    set('term_code', ct.code)
    setForm(f => ({ ...f, term_code: ct.code, term_name: ct.name, days_to_due: String(ct.days), require_downpayment: ct.code === 'DP50', dp_percentage: ct.code === 'DP50' ? '50' : '' }))
    setSaved(false)
  }

  const handleSave = async () => {
    setSaving(true)
    const payload = {
      company_id: form.company_id, term_code: form.term_code.toUpperCase(),
      term_name: form.term_name, days_to_due: parseInt(form.days_to_due) || 0,
      require_downpayment: form.require_downpayment,
      dp_percentage: form.require_downpayment && form.dp_percentage ? parseFloat(form.dp_percentage) : null,
    }
    const { error } = editId
      ? await supabase.from('payment_terms').update(payload).eq('id', editId)
      : await supabase.from('payment_terms').insert([payload])
    if (error) alert('Error: ' + error.message)
    else { setSaved(true); fetchTerms() }
    setSaving(false)
  }

  const toggleActive = async (t: PaymentTerm) => {
    await supabase.from('payment_terms').update({ is_active: !t.is_active }).eq('id', t.id)
    fetchTerms()
  }

  if (showForm) return (
    <div className="max-w-2xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Payment Term' : 'Create Payment Term'}</h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={handleSave} disabled={saving}
            className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update' : 'Save'}
          </button>
        </div>
      </div>

      {!editId && (
        <div className={sec}><h2 className={hd}>Quick Fill — Common Terms</h2>
          <p className="text-xs text-gray-500 mb-3">Click a common term to pre-fill the form, then adjust as needed.</p>
          <div className="flex flex-wrap gap-2">
            {COMMON_TERMS.map(ct => (
              <button key={ct.code} onClick={() => quickFill(ct)}
                className="border border-gray-200 bg-gray-50 hover:bg-gray-100 rounded px-3 py-1.5 text-xs font-medium text-gray-700">
                {ct.code}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className={sec}><h2 className={hd}>Section 1 — Basic Information</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
            <select value={form.company_id} onChange={e => set('company_id', e.target.value)} className={inp}>
              <option value="">Select company...</option>
              {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
            </select></div>
          <div><label className={lbl}>Term Code <span className="text-red-500">*</span></label>
            <input value={form.term_code} onChange={e => set('term_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., NET30, COD, DP50" /></div>
          <div className="col-span-2"><label className={lbl}>Term Name / Description <span className="text-red-500">*</span></label>
            <input value={form.term_name} onChange={e => set('term_name', e.target.value)} className={inp} placeholder="e.g., Net 30 Days, Cash on Delivery" /></div>
        </div>
      </div>

      <div className={sec}><h2 className={hd}>Section 2 — Term Rules</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>Days to Due <span className="text-red-500">*</span></label>
            <input type="number" min="0" value={form.days_to_due} onChange={e => set('days_to_due', e.target.value)} className={inp} placeholder="0 = COD / Due on invoice date" /></div>
          <div className="flex items-center gap-3 pt-5">
            <input type="checkbox" id="require_dp" checked={form.require_downpayment} onChange={e => set('require_downpayment', e.target.checked)} className="rounded border-gray-300" />
            <label htmlFor="require_dp" className="text-sm text-gray-700">Requires Downpayment</label>
          </div>
          {form.require_downpayment && (
            <div><label className={lbl}>Downpayment Percentage (%) <span className="text-red-500">*</span></label>
              <input type="number" min="1" max="100" step="0.01" value={form.dp_percentage} onChange={e => set('dp_percentage', e.target.value)} className={inp} placeholder="e.g., 50.00" /></div>
          )}
        </div>
        {parseInt(form.days_to_due) === 0 && !form.require_downpayment && (
          <div className="bg-amber-50 border border-amber-100 rounded px-3 py-2 text-xs text-amber-700 mt-2">
            Days to due = 0 means payment is due on the invoice date (COD or immediate payment).
          </div>
        )}
      </div>
    </div>
  )

  const filtered = terms.filter(t => {
    const m = !search || t.term_code.toLowerCase().includes(search.toLowerCase()) || t.term_name.toLowerCase().includes(search.toLowerCase())
    const c = !filterCompany || t.company_id === filterCompany
    return m && c
  })
  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Payment Terms</h1>
        <p className="text-sm text-gray-500 mt-0.5">Standardized credit policies for customers and suppliers</p></div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-48 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search code or name..." />
        <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        <div className="ml-auto">
          <button onClick={() => { setForm({ company_id: '', term_code: '', term_name: '', days_to_due: '0', require_downpayment: false, dp_percentage: '' }); setEditId(null); setShowForm(true); setSaved(false) }}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create Payment Term
          </button>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Term Code</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Description</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Days to Due</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Downpayment</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.length === 0
              ? <tr><td colSpan={7} className="text-center py-16 text-gray-400">
                  <p className="font-medium text-gray-500">No Payment Terms Found</p>
                  <p className="text-sm mt-1">Create standard terms like Net 30, COD, or DP50.</p>
                </td></tr>
              : filtered.map((t, i) => (
                <tr key={t.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{t.term_code}</td>
                  <td className="px-4 py-3 text-gray-700">{t.term_name}</td>
                  <td className="px-4 py-3 text-gray-600">{t.days_to_due === 0 ? <span className="text-orange-600 font-medium">COD</span> : `${t.days_to_due} days`}</td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{t.require_downpayment ? `${t.dp_percentage}% DP required` : '—'}</td>
                  <td className="px-4 py-3 text-gray-500">{t.companies?.registered_name || '—'}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${t.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{t.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openEdit(t)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleActive(t)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{t.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
          </tbody>
        </table>
        {filtered.length > 0 && <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">Showing {filtered.length} of {terms.length} terms</div>}
      </div>
    </div>
  )
}
