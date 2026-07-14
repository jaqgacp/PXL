import { useState, useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type Currency = { id: string; currency_code: string; name: string }
type PaymentTerm = { id: string; term_code: string; term_name: string }
type COA = { id: string; account_code: string; account_name: string }
type ATCCode = { id: string; code: string; description: string; rate: number }
type Customer = {
  id: string; company_id: string; customer_code: string; customer_group: string | null
  registered_name: string; trade_name: string | null; business_style: string | null
  tin: string; default_tax_type: string
  is_subject_to_cwt: boolean; default_cwt_atc_code_id: string | null
  registered_address: string; delivery_address: string; contact_person: string | null
  email: string | null; phone_number: string | null
  default_terms_id: string | null; default_currency_id: string | null
  default_gl_account_id: string | null; credit_limit: number; is_active: boolean
  companies?: { registered_name: string }
  payment_terms?: { term_code: string; term_name: string }
  currencies?: { currency_code: string }
  atc_codes?: { code: string; description: string; rate: number }
}

const TAX_TYPES = [
  { value: 'vat_registered', label: 'VAT-Registered (12%)' },
  { value: 'non_vat', label: 'Non-VAT / Non-VAT Registered' },
  { value: 'vat_exempt', label: 'VAT-Exempt Entity' },
  { value: 'zero_rated', label: 'Zero-Rated (PEZA / Export)' },
]
const CUSTOMER_GROUPS = ['Retail', 'Wholesale', 'Corporate', 'Government', 'Export', 'Individual']

const EMPTY = {
  company_id: '', customer_code: '', customer_group: '', registered_name: '', trade_name: '',
  business_style: '', tin: '', default_tax_type: 'vat_registered',
  is_subject_to_cwt: false, default_cwt_atc_code_id: '',
  registered_address: '', delivery_address: '', contact_person: '', email: '', phone_number: '',
  default_terms_id: '', default_currency_id: '', default_gl_account_id: '', credit_limit: '0',
}

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const roInp = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function CustomersPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [customers, setCustomers] = useState<Customer[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [terms, setTerms] = useState<PaymentTerm[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [atcCodes, setAtcCodes] = useState<ATCCode[]>([])
  const [search, setSearch] = useState('')
  const [filterCompany, setFilterCompany] = useState('')
  const [filterTaxType, setFilterTaxType] = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'inactive'>('all')
  const [showForm, setShowForm] = useState(false)
  const [showView, setShowView] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [viewData, setViewData] = useState<Customer | null>(null)
  const [form, setForm] = useState({ ...EMPTY })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const linkedCustomerId = searchParams.get('customerId')

  const fetchCustomers = async () => {
    const { data } = await supabase.from('customers')
      .select('*, companies(registered_name), payment_terms(term_code,term_name), currencies(currency_code), atc_codes(code,description,rate)')
      .order('registered_name')
    setCustomers((data as Customer[]) || [])
  }
  useEffect(() => {
    fetchCustomers()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
    supabase.from('currencies').select('id,currency_code,name').eq('is_active', true).order('currency_code').then(({ data }) => setCurrencies(data || []))
  }, [])

  useEffect(() => {
    if (!form.company_id) { setTerms([]); setCoa([]); setAtcCodes([]); return }
    supabase.from('payment_terms').select('id,term_code,term_name').eq('company_id', form.company_id).eq('is_active', true).order('term_code').then(({ data }) => setTerms(data || []))
    supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', form.company_id).eq('is_active', true).eq('is_postable', true).order('account_code').then(({ data }) => setCoa(data || []))
    supabase.from('atc_codes').select('id,code,description,rate').eq('is_active', true).eq('tax_category', 'ewt').order('code').then(({ data }) => setAtcCodes(data || []))
  }, [form.company_id])

  const set = (k: string, v: string | boolean) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const openCreate = () => {
    setForm({ ...EMPTY })
    setEditId(null); setShowForm(true); setSaved(false)
  }

  const openEdit = (c: Customer) => {
    setForm({
      company_id: c.company_id, customer_code: c.customer_code,
      customer_group: c.customer_group || '', registered_name: c.registered_name,
      trade_name: c.trade_name || '', business_style: c.business_style || '',
      tin: c.tin, default_tax_type: c.default_tax_type,
      is_subject_to_cwt: c.is_subject_to_cwt || false,
      default_cwt_atc_code_id: c.default_cwt_atc_code_id || '',
      registered_address: c.registered_address, delivery_address: c.delivery_address,
      contact_person: c.contact_person || '', email: c.email || '',
      phone_number: c.phone_number || '', default_terms_id: c.default_terms_id || '',
      default_currency_id: c.default_currency_id || '',
      default_gl_account_id: c.default_gl_account_id || '',
      credit_limit: String(c.credit_limit ?? 0),
    })
    setEditId(c.id); setShowForm(true); setSaved(false)
  }

  const openView = (c: Customer) => { setViewData(c); setShowView(true) }
  const clearLinkedCustomer = () => {
    if (!linkedCustomerId) return
    const next = new URLSearchParams(searchParams)
    next.delete('customerId')
    setSearchParams(next, { replace: true })
  }
  const closeView = () => { setShowView(false); clearLinkedCustomer() }

  useEffect(() => {
    if (!linkedCustomerId || customers.length === 0 || showForm) return
    const linked = customers.find(c => c.id === linkedCustomerId)
    if (linked && (!showView || viewData?.id !== linked.id)) {
      setViewData(linked)
      setShowView(true)
    }
  }, [linkedCustomerId, customers, showForm, showView, viewData?.id])

  const handleSave = async () => {
    setSaving(true)
    const payload = {
      company_id: form.company_id, customer_code: form.customer_code.toUpperCase(),
      customer_group: form.customer_group || null, registered_name: form.registered_name,
      trade_name: form.trade_name || null, business_style: form.business_style || null,
      tin: form.tin, default_tax_type: form.default_tax_type,
      is_subject_to_cwt: Boolean(form.is_subject_to_cwt),
      default_cwt_atc_code_id: form.is_subject_to_cwt ? form.default_cwt_atc_code_id || null : null,
      registered_address: form.registered_address, delivery_address: form.delivery_address,
      contact_person: form.contact_person || null, email: form.email || null,
      phone_number: form.phone_number || null,
      default_terms_id: form.default_terms_id || null,
      default_currency_id: form.default_currency_id || null,
      default_gl_account_id: form.default_gl_account_id || null,
      credit_limit: parseFloat(form.credit_limit) || 0,
    }
    const { error } = editId
      ? await supabase.from('customers').update(payload).eq('id', editId)
      : await supabase.from('customers').insert([payload])
    if (error) alert('Error: ' + error.message)
    else { setSaved(true); fetchCustomers() }
    setSaving(false)
  }

  const toggleStatus = async (c: Customer) => {
    await supabase.from('customers').update({ is_active: !c.is_active }).eq('id', c.id)
    fetchCustomers()
  }

  const syncDelivery = () => set('delivery_address', form.registered_address)

  // VIEW
  if (showView && viewData) {
    const taxLabel = TAX_TYPES.find(t => t.value === viewData.default_tax_type)?.label || viewData.default_tax_type
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={closeView} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
            <h1 className="text-xl font-semibold text-gray-900">View Customer</h1>
            <p className="text-sm text-gray-500 mt-0.5">{viewData.registered_name}</p>
          </div>
          <div className="flex gap-2">
            <button onClick={() => { clearLinkedCustomer(); setShowView(false); openEdit(viewData) }} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Edit</button>
            <button onClick={closeView} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Close</button>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 1 — Basic Information</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Customer Code</label><input readOnly value={viewData.customer_code} className={roInp} /></div>
            <div><label className={lbl}>Customer Group</label><input readOnly value={viewData.customer_group || '—'} className={roInp} /></div>
            <div className="col-span-2"><label className={lbl}>Registered Name</label><input readOnly value={viewData.registered_name} className={roInp} /></div>
            <div><label className={lbl}>Trade Name</label><input readOnly value={viewData.trade_name || '—'} className={roInp} /></div>
            <div><label className={lbl}>Business Style</label><input readOnly value={viewData.business_style || '—'} className={roInp} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 2 — Tax & Compliance</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>TIN</label><input readOnly value={viewData.tin} className={roInp} /></div>
          <div><label className={lbl}>Tax Type</label><input readOnly value={taxLabel} className={roInp} /></div>
          <div><label className={lbl}>Subject to CWT</label><input readOnly value={viewData.is_subject_to_cwt ? 'Yes' : 'No'} className={roInp} /></div>
          <div><label className={lbl}>Default CWT ATC</label><input readOnly value={(viewData as any).atc_codes?.code || viewData.default_cwt_atc_code_id || '—'} className={roInp} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 3 — Contact & Address</h2>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2"><label className={lbl}>Registered Address</label><textarea readOnly value={viewData.registered_address} className={roInp + ' h-16 resize-none'} /></div>
            <div className="col-span-2"><label className={lbl}>Delivery Address</label><textarea readOnly value={viewData.delivery_address} className={roInp + ' h-16 resize-none'} /></div>
            <div><label className={lbl}>Contact Person</label><input readOnly value={viewData.contact_person || '—'} className={roInp} /></div>
            <div><label className={lbl}>Email</label><input readOnly value={viewData.email || '—'} className={roInp} /></div>
            <div><label className={lbl}>Phone Number</label><input readOnly value={viewData.phone_number || '—'} className={roInp} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 4 — Commercial Terms</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Payment Terms</label><input readOnly value={viewData.payment_terms ? `${viewData.payment_terms.term_code} — ${viewData.payment_terms.term_name}` : '—'} className={roInp} /></div>
            <div><label className={lbl}>Default Currency</label><input readOnly value={viewData.currencies?.currency_code || '—'} className={roInp} /></div>
            <div><label className={lbl}>Credit Limit</label><input readOnly value={Number(viewData.credit_limit).toLocaleString('en-PH', { minimumFractionDigits: 2 })} className={roInp} /></div>
          </div>
        </div>
      </div>
    )
  }

  // FORM
  if (showForm) return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Customer' : 'Create New Customer'}</h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={handleSave} disabled={saving}
            className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update Customer' : 'Save Customer'}
          </button>
        </div>
      </div>

      <div className={sec}><h2 className={hd}>Section 1 — Basic Information</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
            <select value={form.company_id} onChange={e => set('company_id', e.target.value)} className={inp}>
              <option value="">Select company...</option>
              {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
            </select></div>
          <div><label className={lbl}>Customer Code <span className="text-red-500">*</span></label>
            <input value={form.customer_code} onChange={e => set('customer_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., CUST-001" /></div>
          <div className="col-span-2"><label className={lbl}>Registered Name <span className="text-red-500">*</span></label>
            <input value={form.registered_name} onChange={e => set('registered_name', e.target.value)} className={inp} placeholder="Exact legal name as on BIR Form 2303" /></div>
          <div><label className={lbl}>Trade Name</label>
            <input value={form.trade_name} onChange={e => set('trade_name', e.target.value)} className={inp} placeholder="DBA / Trade name" /></div>
          <div><label className={lbl}>Business Style</label>
            <input value={form.business_style} onChange={e => set('business_style', e.target.value)} className={inp} placeholder="As indicated in BIR registration" /></div>
          <div><label className={lbl}>Customer Group</label>
            <select value={form.customer_group} onChange={e => set('customer_group', e.target.value)} className={inp}>
              <option value="">Select group...</option>
              {CUSTOMER_GROUPS.map(g => <option key={g} value={g}>{g}</option>)}
            </select></div>
        </div>
      </div>

      <div className={sec}><h2 className={hd}>Section 2 — Tax & Compliance Details</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>TIN <span className="text-red-500">*</span></label>
            <input value={form.tin} onChange={e => set('tin', e.target.value)} className={inp} placeholder="000-000-000-00000" /></div>
          <div><label className={lbl}>Tax Type <span className="text-red-500">*</span></label>
            <select value={form.default_tax_type} onChange={e => set('default_tax_type', e.target.value)} className={inp}>
              {TAX_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select></div>
          <label className="flex items-center gap-2 mt-6 text-sm text-gray-700">
            <input type="checkbox" checked={Boolean(form.is_subject_to_cwt)}
              onChange={e => setForm(f => ({ ...f, is_subject_to_cwt: e.target.checked, default_cwt_atc_code_id: e.target.checked ? f.default_cwt_atc_code_id : '' }))}
              className="rounded border-gray-300" />
            Subject to CWT by default
          </label>
          <div><label className={lbl}>Default CWT ATC</label>
            <select value={form.default_cwt_atc_code_id} disabled={!form.is_subject_to_cwt}
              onChange={e => set('default_cwt_atc_code_id', e.target.value)} className={inp}>
              <option value="">None</option>
              {atcCodes.map(a => <option key={a.id} value={a.id}>{a.code} — {a.description} ({a.rate}%)</option>)}
            </select></div>
        </div>
      </div>

      <div className={sec}><h2 className={hd}>Section 3 — Contact & Address Information</h2>
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2">
            <label className={lbl}>Registered Address <span className="text-red-500">*</span></label>
            <textarea value={form.registered_address} onChange={e => set('registered_address', e.target.value)} className={inp + ' h-16 resize-none'} placeholder="Full legal address for BIR billing purposes" />
          </div>
          <div className="col-span-2">
            <div className="flex items-center justify-between mb-1">
              <label className={lbl}>Delivery Address <span className="text-red-500">*</span></label>
              <button onClick={syncDelivery} type="button" className="text-xs text-blue-600 hover:text-blue-800">Same as Registered</button>
            </div>
            <textarea value={form.delivery_address} onChange={e => set('delivery_address', e.target.value)} className={inp + ' h-16 resize-none'} />
          </div>
          <div><label className={lbl}>Contact Person</label>
            <input value={form.contact_person} onChange={e => set('contact_person', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Email</label>
            <input type="email" value={form.email} onChange={e => set('email', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Phone Number</label>
            <input value={form.phone_number} onChange={e => set('phone_number', e.target.value)} className={inp} /></div>
        </div>
      </div>

      <div className={sec}><h2 className={hd}>Section 4 — Commercial Terms</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>Default Payment Terms <span className="text-red-500">*</span></label>
            <select value={form.default_terms_id} onChange={e => set('default_terms_id', e.target.value)} className={inp}>
              <option value="">Select terms...</option>
              {terms.map(t => <option key={t.id} value={t.id}>{t.term_code} — {t.term_name}</option>)}
            </select></div>
          <div><label className={lbl}>Default Currency <span className="text-red-500">*</span></label>
            <select value={form.default_currency_id} onChange={e => set('default_currency_id', e.target.value)} className={inp}>
              <option value="">Select currency...</option>
              {currencies.map(c => <option key={c.id} value={c.id}>{c.currency_code} — {c.name}</option>)}
            </select></div>
          <div><label className={lbl}>Default AR GL Account <span className="text-red-500">*</span></label>
            <select value={form.default_gl_account_id} onChange={e => set('default_gl_account_id', e.target.value)} className={inp}>
              <option value="">Select account...</option>
              {coa.filter(a => a.account_code.startsWith('1')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
            </select></div>
          <div><label className={lbl}>Credit Limit (₱)</label>
            <input type="number" min="0" step="0.01" value={form.credit_limit} onChange={e => set('credit_limit', e.target.value)} className={inp} /></div>
        </div>
      </div>
    </div>
  )

  // LIST
  const filtered = customers.filter(c => {
    const m = !search || c.customer_code.toLowerCase().includes(search.toLowerCase()) || c.registered_name.toLowerCase().includes(search.toLowerCase()) || c.tin.includes(search)
    const co = !filterCompany || c.company_id === filterCompany
    const t = !filterTaxType || c.default_tax_type === filterTaxType
    const s = filterStatus === 'all' || (filterStatus === 'active' ? c.is_active : !c.is_active)
    return m && co && t && s
  })
  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Customers</h1>
        <p className="text-sm text-gray-500 mt-0.5">Client master records for sales, AR, and BIR compliance</p></div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-56 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search name, code, or TIN..." />
        <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        <select value={filterTaxType} onChange={e => setFilterTaxType(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Tax Types</option>
          {TAX_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
        <select value={filterStatus} onChange={e => setFilterStatus(e.target.value as typeof filterStatus)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="all">All Status</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
        <div className="ml-auto">
          <button onClick={openCreate}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create Customer
          </button>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Code</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Registered Name</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">TIN</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Type</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Contact Person</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.length === 0
              ? <tr><td colSpan={7} className="text-center py-16 text-gray-400">
                  <p className="font-medium text-gray-500">No Customers Found</p>
                  <p className="text-sm mt-1">Click "+ Create Customer" to add your first customer.</p>
                </td></tr>
              : filtered.map((c, i) => (
                <tr key={c.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{c.customer_code}</td>
                  <td className="px-4 py-3">
                    <p className="text-gray-900 font-medium">{c.registered_name}</p>
                    {c.trade_name && <p className="text-xs text-gray-400">{c.trade_name}</p>}
                  </td>
                  <td className="px-4 py-3 font-mono text-gray-600">{c.tin}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                    c.default_tax_type === 'vat_registered' ? 'bg-blue-50 text-blue-700' :
                    c.default_tax_type === 'zero_rated' ? 'bg-green-50 text-green-700' :
                    c.default_tax_type === 'vat_exempt' ? 'bg-orange-50 text-orange-700' :
                    'bg-gray-100 text-gray-600'}`}>
                    {TAX_TYPES.find(t => t.value === c.default_tax_type)?.label.split(' ')[0] || c.default_tax_type}
                  </span></td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{c.contact_person || '—'}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${c.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{c.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openView(c)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button>
                    <button onClick={() => openEdit(c)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleStatus(c)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{c.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
          </tbody>
        </table>
        {filtered.length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {filtered.length} of {customers.length} customers
          </div>
        )}
      </div>
    </div>
  )
}
