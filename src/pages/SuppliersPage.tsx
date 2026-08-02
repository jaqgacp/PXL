import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { formatPhTinInput, isValidPhTin, normalizePhTin, phTinMatches, PH_TIN_PLACEHOLDER } from '@/lib/philippines'

type Company = { id: string; registered_name: string }
type Currency = { id: string; currency_code: string; name: string }
type PaymentTerm = { id: string; term_code: string; term_name: string }
type COA = { id: string; account_code: string; account_name: string }
type ATCCode = { id: string; code: string; description: string; rate: number }
type BankRef = { id: string; bank_code: string; bank_name: string; swift_code: string | null }
type SupplierBankAccount = {
  id?: string; bank_id: string; account_name: string; account_number: string
  account_type: 'checking' | 'savings'; bank_branch: string; swift_code: string
  is_default: boolean; is_active: boolean
  verification_status: 'unverified' | 'verified' | 'rejected'
  ref_banks?: { bank_name: string }
}
type Supplier = {
  id: string; company_id: string; supplier_code: string; supplier_group: string | null
  registered_name: string; trade_name: string | null; business_style: string | null
  tin: string; default_tax_type: string
  is_subject_to_ewt: boolean; default_atc_code_id: string | null
  registered_address: string; contact_person: string | null
  email: string | null; phone_number: string | null
  default_terms_id: string | null; default_currency_id: string | null
  default_gl_account_id: string | null; is_active: boolean
  companies?: { registered_name: string }
  payment_terms?: { term_code: string; term_name: string }
  currencies?: { currency_code: string }
  atc_codes?: { code: string; description: string; rate: number }
}

const TAX_TYPES = [
  { value: 'vat_registered', label: 'VAT-Registered (12%)' },
  { value: 'non_vat', label: 'Non-VAT / Non-VAT Registered' },
  { value: 'vat_exempt', label: 'VAT-Exempt Entity' },
  { value: 'zero_rated', label: 'Zero-Rated (Export / PEZA)' },
]
const SUPPLIER_GROUPS = ['Inventory Supplier', 'Services', 'Utilities', 'Rent', 'Contractor', 'Government', 'Individual']

const EMPTY = {
  company_id: '', supplier_code: '', supplier_group: '', registered_name: '', trade_name: '',
  business_style: '', tin: '', default_tax_type: 'vat_registered',
  is_subject_to_ewt: false, default_atc_code_id: '',
  registered_address: '', contact_person: '', email: '', phone_number: '',
  default_terms_id: '', default_currency_id: '', default_gl_account_id: '',
}

const newBankAccount = (): SupplierBankAccount => ({
  bank_id: '', account_name: '', account_number: '', account_type: 'checking',
  bank_branch: '', swift_code: '', is_default: false, is_active: true,
  verification_status: 'unverified',
})

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const roInp = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function SuppliersPage() {
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [terms, setTerms] = useState<PaymentTerm[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [atcCodes, setAtcCodes] = useState<ATCCode[]>([])
  const [bankRefs, setBankRefs] = useState<BankRef[]>([])
  const [bankAccounts, setBankAccounts] = useState<SupplierBankAccount[]>([])
  const [removedBankIds, setRemovedBankIds] = useState<string[]>([])
  const [search, setSearch] = useState('')
  const [filterCompany, setFilterCompany] = useState('')
  const [filterTaxType, setFilterTaxType] = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'inactive'>('all')
  const [showForm, setShowForm] = useState(false)
  const [showView, setShowView] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [viewData, setViewData] = useState<Supplier | null>(null)
  const [form, setForm] = useState({ ...EMPTY })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const fetchSuppliers = async () => {
    const { data } = await supabase.from('suppliers')
      .select('*, companies(registered_name), payment_terms(term_code,term_name), currencies(currency_code), atc_codes(code,description,rate)')
      .order('registered_name')
    setSuppliers((data as Supplier[]) || [])
  }
  useEffect(() => {
    fetchSuppliers()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
    supabase.from('currencies').select('id,currency_code,name').eq('is_active', true).order('currency_code').then(({ data }) => setCurrencies(data || []))
    supabase.from('ref_banks').select('id,bank_code,bank_name,swift_code').eq('is_active', true).order('sort_order').then(({ data }) => setBankRefs(data || []))
  }, [])

  useEffect(() => {
    if (!form.company_id) { setTerms([]); setCoa([]); setAtcCodes([]); return }
    supabase.from('payment_terms').select('id,term_code,term_name').eq('company_id', form.company_id).eq('is_active', true).order('term_code').then(({ data }) => setTerms(data || []))
    supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', form.company_id).eq('is_active', true).eq('is_postable', true).order('account_code').then(({ data }) => setCoa(data || []))
    supabase.from('atc_codes').select('id,code,description,rate').eq('tax_category', 'ewt').eq('is_active', true).order('code').then(({ data }) => setAtcCodes(data || []))
  }, [form.company_id])

  const set = (k: string, v: string | boolean) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const loadSupplierBanks = async (supplierId: string) => {
    const { data } = await (supabase as any).from('supplier_bank_accounts')
      .select('id,bank_id,account_name,account_number,account_type,bank_branch,swift_code,is_default,is_active,verification_status,ref_banks(bank_name)')
      .eq('supplier_id', supplierId).order('is_default', { ascending: false }).order('created_at')
    setBankAccounts(((data as SupplierBankAccount[]) || []).map(account => ({
      ...account, bank_branch: account.bank_branch || '', swift_code: account.swift_code || '',
    })))
    setRemovedBankIds([])
  }

  const openEdit = (s: Supplier) => {
    setForm({
      company_id: s.company_id, supplier_code: s.supplier_code,
      supplier_group: s.supplier_group || '', registered_name: s.registered_name,
      trade_name: s.trade_name || '', business_style: s.business_style || '',
      tin: normalizePhTin(s.tin), default_tax_type: s.default_tax_type,
      is_subject_to_ewt: s.is_subject_to_ewt || false,
      default_atc_code_id: s.default_atc_code_id || '',
      registered_address: s.registered_address,
      contact_person: s.contact_person || '', email: s.email || '',
      phone_number: s.phone_number || '', default_terms_id: s.default_terms_id || '',
      default_currency_id: s.default_currency_id || '',
      default_gl_account_id: s.default_gl_account_id || '',
    })
    loadSupplierBanks(s.id)
    setEditId(s.id); setShowForm(true); setSaved(false)
  }

  const openView = (s: Supplier) => { setViewData(s); loadSupplierBanks(s.id); setShowView(true) }

  const handleSave = async () => {
    if (!isValidPhTin(form.tin)) {
      alert(`TIN must use ${PH_TIN_PLACEHOLDER}.`)
      return
    }
    setSaving(true)
    if (bankAccounts.some(account => !account.bank_id || !account.account_name.trim() || !account.account_number.trim())) {
      alert('Each supplier bank account needs a bank, account name, and account number.')
      setSaving(false)
      return
    }
    if (bankAccounts.filter(account => account.is_active && account.is_default).length > 1) {
      alert('Only one active supplier bank account can be the default.')
      setSaving(false)
      return
    }
    const payload = {
      company_id: form.company_id, supplier_code: form.supplier_code.toUpperCase(),
      supplier_group: form.supplier_group || null, registered_name: form.registered_name,
      trade_name: form.trade_name || null, business_style: form.business_style || null,
      tin: normalizePhTin(form.tin), default_tax_type: form.default_tax_type,
      is_subject_to_ewt: form.is_subject_to_ewt,
      default_atc_code_id: form.is_subject_to_ewt ? (form.default_atc_code_id || null) : null,
      registered_address: form.registered_address,
      contact_person: form.contact_person || null, email: form.email || null,
      phone_number: form.phone_number || null,
      default_terms_id: form.default_terms_id || null,
      default_currency_id: form.default_currency_id || null,
      default_gl_account_id: form.default_gl_account_id || null,
    }
    const supplierResult = editId
      ? await supabase.from('suppliers').update(payload).eq('id', editId).select('id').single()
      : await supabase.from('suppliers').insert([payload]).select('id').single()
    const savedSupplierId = supplierResult.data?.id
    if (supplierResult.error || !savedSupplierId) {
      alert('Error: ' + (supplierResult.error?.message || 'Supplier was not saved'))
    } else {
      try {
        if (bankAccounts.some(account => account.is_default)) {
          const { error } = await (supabase as any).from('supplier_bank_accounts')
            .update({ is_default: false }).eq('supplier_id', savedSupplierId).eq('is_default', true)
          if (error) throw error
        }
        for (const account of bankAccounts) {
          const bankPayload = {
            company_id: form.company_id, supplier_id: savedSupplierId, bank_id: account.bank_id,
            account_name: account.account_name, account_number: account.account_number,
            account_type: account.account_type, bank_branch: account.bank_branch || null,
            swift_code: account.swift_code || null, is_default: account.is_default,
            is_active: account.is_active, verification_status: account.verification_status,
          }
          const result = account.id
            ? await (supabase as any).from('supplier_bank_accounts').update(bankPayload).eq('id', account.id)
            : await (supabase as any).from('supplier_bank_accounts').insert([bankPayload])
          if (result.error) throw result.error
        }
        if (removedBankIds.length > 0) {
          const { error } = await (supabase as any).from('supplier_bank_accounts').delete().in('id', removedBankIds)
          if (error) throw error
        }
        setSaved(true)
        setEditId(savedSupplierId)
        setRemovedBankIds([])
        fetchSuppliers()
        await loadSupplierBanks(savedSupplierId)
      } catch (bankError: any) {
        alert('Supplier saved, but bank details failed: ' + (bankError.message || 'Unknown error'))
      }
    }
    setSaving(false)
  }

  const updateBankAccount = (index: number, patch: Partial<SupplierBankAccount>) => {
    setSaved(false)
    setBankAccounts(rows => rows.map((row, rowIndex) => {
      if (rowIndex !== index) return patch.is_default ? { ...row, is_default: false } : row
      const bank = patch.bank_id ? bankRefs.find(ref => ref.id === patch.bank_id) : undefined
      return { ...row, ...patch, swift_code: bank?.swift_code || row.swift_code }
    }))
  }

  const removeBankAccount = (index: number) => {
    setBankAccounts(rows => {
      const removed = rows[index]
      if (removed?.id) setRemovedBankIds(ids => [...ids, removed.id!])
      return rows.filter((_, rowIndex) => rowIndex !== index)
    })
  }

  const toggleStatus = async (s: Supplier) => {
    await supabase.from('suppliers').update({ is_active: !s.is_active }).eq('id', s.id)
    fetchSuppliers()
  }

  // VIEW
  if (showView && viewData) {
    const taxLabel = TAX_TYPES.find(t => t.value === viewData.default_tax_type)?.label || viewData.default_tax_type
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setShowView(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
            <h1 className="text-xl font-semibold text-gray-900">View Supplier</h1>
            <p className="text-sm text-gray-500 mt-0.5">{viewData.registered_name}</p>
          </div>
          <div className="flex gap-2">
            <button onClick={() => { setShowView(false); openEdit(viewData) }} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Edit</button>
            <button onClick={() => setShowView(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Close</button>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 1 — Basic Information</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Supplier Code</label><input readOnly value={viewData.supplier_code} className={roInp} /></div>
            <div><label className={lbl}>Supplier Group</label><input readOnly value={viewData.supplier_group || '—'} className={roInp} /></div>
            <div className="col-span-2"><label className={lbl}>Registered Name</label><input readOnly value={viewData.registered_name} className={roInp} /></div>
            <div><label className={lbl}>Trade Name</label><input readOnly value={viewData.trade_name || '—'} className={roInp} /></div>
            <div><label className={lbl}>Business Style</label><input readOnly value={viewData.business_style || '—'} className={roInp} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 2 — Tax & Compliance</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>TIN</label><input readOnly value={normalizePhTin(viewData.tin)} className={roInp} /></div>
            <div><label className={lbl}>Tax Type</label><input readOnly value={taxLabel} className={roInp} /></div>
            <div><label className={lbl}>AP Withholding</label><input readOnly value={viewData.is_subject_to_ewt ? 'Subject to EWT' : 'Not subject to EWT'} className={roInp} /></div>
            <div><label className={lbl}>Default AP ATC</label><input readOnly value={viewData.atc_codes ? `${viewData.atc_codes.code} — ${viewData.atc_codes.description} (${viewData.atc_codes.rate}%)` : '—'} className={roInp} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 3 — Contact & Address</h2>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2"><label className={lbl}>Registered Address</label><textarea readOnly value={viewData.registered_address} className={roInp + ' h-16 resize-none'} /></div>
            <div><label className={lbl}>Contact Person</label><input readOnly value={viewData.contact_person || '—'} className={roInp} /></div>
            <div><label className={lbl}>Email</label><input readOnly value={viewData.email || '—'} className={roInp} /></div>
            <div><label className={lbl}>Phone Number</label><input readOnly value={viewData.phone_number || '—'} className={roInp} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 4 — Commercial Terms</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Payment Terms</label><input readOnly value={viewData.payment_terms ? `${viewData.payment_terms.term_code} — ${viewData.payment_terms.term_name}` : '—'} className={roInp} /></div>
            <div><label className={lbl}>Default Currency</label><input readOnly value={viewData.currencies?.currency_code || '—'} className={roInp} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 5 — Payment Instructions</h2>
          {bankAccounts.length === 0 ? <p className="text-sm text-gray-500">No supplier bank account recorded.</p> : (
            <div className="space-y-3">{bankAccounts.map(account => (
              <div key={account.id || account.account_number} className="rounded-md border border-gray-200 p-3 text-sm">
                <div className="font-medium text-gray-900">{account.ref_banks?.bank_name || bankRefs.find(bank => bank.id === account.bank_id)?.bank_name || 'Bank'}</div>
                <div className="mt-1 text-gray-600">{account.account_name} · ••••{account.account_number.slice(-4)}</div>
                <div className="mt-1 text-xs text-gray-500">{account.account_type} · {account.bank_branch || 'branch not specified'} · {account.verification_status}{account.is_default ? ' · default' : ''}</div>
              </div>
            ))}</div>
          )}
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
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Supplier' : 'Create New Supplier'}</h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={handleSave} disabled={saving}
            className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update Supplier' : 'Save Supplier'}
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
          <div><label className={lbl}>Supplier Code <span className="text-red-500">*</span></label>
            <input value={form.supplier_code} onChange={e => set('supplier_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., VEN-001" /></div>
          <div className="col-span-2"><label className={lbl}>Registered Name <span className="text-red-500">*</span></label>
            <input value={form.registered_name} onChange={e => set('registered_name', e.target.value)} className={inp} placeholder="Exact legal name as on BIR Form 2303" /></div>
          <div><label className={lbl}>Trade Name</label>
            <input value={form.trade_name} onChange={e => set('trade_name', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Business Style</label>
            <input value={form.business_style} onChange={e => set('business_style', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Supplier Group</label>
            <select value={form.supplier_group} onChange={e => set('supplier_group', e.target.value)} className={inp}>
              <option value="">Select group...</option>
              {SUPPLIER_GROUPS.map(g => <option key={g} value={g}>{g}</option>)}
            </select></div>
        </div>
      </div>

      <div className={sec}><h2 className={hd}>Section 2 — Tax & Compliance Details</h2>
        <div className="bg-blue-50 border border-blue-100 rounded-md px-3 py-2 mb-2">
          <p className="text-xs text-blue-700">The AP withholding ATC is the default applied on purchases from this supplier. It can be overridden per transaction.</p>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>TIN <span className="text-red-500">*</span></label>
            <input value={form.tin} onChange={e => set('tin', formatPhTinInput(e.target.value))} className={inp} placeholder={PH_TIN_PLACEHOLDER} /></div>
          <div><label className={lbl}>Tax Type <span className="text-red-500">*</span></label>
            <select value={form.default_tax_type} onChange={e => set('default_tax_type', e.target.value)} className={inp}>
              {TAX_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select></div>
          <div className="flex items-center gap-2 pt-6">
            <input id="is_subject_to_ewt" type="checkbox" checked={form.is_subject_to_ewt}
              onChange={e => set('is_subject_to_ewt', e.target.checked)} />
            <label htmlFor="is_subject_to_ewt" className="text-sm text-gray-700">Subject to AP EWT by default</label>
          </div>
          <div><label className={lbl}>Default AP ATC</label>
            <select value={form.default_atc_code_id} disabled={!form.is_subject_to_ewt}
              onChange={e => set('default_atc_code_id', e.target.value)} className={inp}>
              <option value="">None</option>
              {atcCodes.map(a => <option key={a.id} value={a.id}>{a.code} — {a.description} ({a.rate}%)</option>)}
            </select></div>
        </div>
      </div>

      <div className={sec}><h2 className={hd}>Section 3 — Contact & Address Information</h2>
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2"><label className={lbl}>Registered Address <span className="text-red-500">*</span></label>
            <textarea value={form.registered_address} onChange={e => set('registered_address', e.target.value)} className={inp + ' h-16 resize-none'} placeholder="Full legal address — printed on BIR Form 2307" /></div>
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
          <div><label className={lbl}>Default AP GL Account <span className="text-red-500">*</span></label>
            <select value={form.default_gl_account_id} onChange={e => set('default_gl_account_id', e.target.value)} className={inp}>
              <option value="">Select account...</option>
              {coa.filter(a => a.account_code.startsWith('2')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
            </select></div>
        </div>
      </div>

      <div className={sec}>
        <div className="flex items-center justify-between">
          <h2 className={hd + ' flex-1'}>Section 5 — Payment Instructions</h2>
          <button type="button" onClick={() => setBankAccounts(rows => [...rows, newBankAccount()])} className="ml-3 text-xs font-medium text-blue-600 hover:text-blue-800">+ Add bank account</button>
        </div>
        <p className="text-xs text-gray-500">Bank-transfer vouchers can only post against a verified supplier account and retain a historical payee snapshot.</p>
        {bankAccounts.length === 0 ? <p className="text-sm text-gray-400">No payment instructions yet.</p> : (
          <div className="space-y-4">{bankAccounts.map((account, index) => (
            <div key={account.id || index} className="rounded-lg border border-gray-200 p-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="col-span-2"><label className={lbl}>Bank <span className="text-red-500">*</span></label>
                  <select value={account.bank_id} onChange={e => updateBankAccount(index, { bank_id: e.target.value })} className={inp}>
                    <option value="">Select bank...</option>
                    {bankRefs.map(bank => <option key={bank.id} value={bank.id}>{bank.bank_code} — {bank.bank_name}</option>)}
                  </select></div>
                <div><label className={lbl}>Account Name <span className="text-red-500">*</span></label><input value={account.account_name} onChange={e => updateBankAccount(index, { account_name: e.target.value })} className={inp} /></div>
                <div><label className={lbl}>Account Number <span className="text-red-500">*</span></label><input value={account.account_number} onChange={e => updateBankAccount(index, { account_number: e.target.value })} className={inp} autoComplete="off" /></div>
                <div><label className={lbl}>Account Type</label><select value={account.account_type} onChange={e => updateBankAccount(index, { account_type: e.target.value as 'checking' | 'savings' })} className={inp}><option value="checking">Checking</option><option value="savings">Savings</option></select></div>
                <div><label className={lbl}>Bank Branch</label><input value={account.bank_branch} onChange={e => updateBankAccount(index, { bank_branch: e.target.value })} className={inp} /></div>
                <div><label className={lbl}>SWIFT / BIC</label><input value={account.swift_code} onChange={e => updateBankAccount(index, { swift_code: e.target.value.toUpperCase() })} className={inp} /></div>
                <div><label className={lbl}>Verification</label><select value={account.verification_status} onChange={e => updateBankAccount(index, { verification_status: e.target.value as SupplierBankAccount['verification_status'] })} className={inp}><option value="unverified">Unverified</option><option value="verified">Verified</option><option value="rejected">Rejected</option></select></div>
              </div>
              <div className="mt-4 flex items-center justify-between">
                <div className="flex gap-4 text-sm text-gray-600">
                  <label className="flex items-center gap-2"><input type="checkbox" checked={account.is_default} onChange={e => updateBankAccount(index, { is_default: e.target.checked })} />Default</label>
                  <label className="flex items-center gap-2"><input type="checkbox" checked={account.is_active} onChange={e => updateBankAccount(index, { is_active: e.target.checked })} />Active</label>
                </div>
                <button type="button" onClick={() => removeBankAccount(index)} className="text-xs font-medium text-red-600 hover:text-red-800">Remove</button>
              </div>
            </div>
          ))}</div>
        )}
      </div>
    </div>
  )

  // LIST
  const filtered = suppliers.filter(s => {
    const m = !search || s.supplier_code.toLowerCase().includes(search.toLowerCase()) || s.registered_name.toLowerCase().includes(search.toLowerCase()) || phTinMatches(s.tin, search)
    const co = !filterCompany || s.company_id === filterCompany
    const t = !filterTaxType || s.default_tax_type === filterTaxType
    const st = filterStatus === 'all' || (filterStatus === 'active' ? s.is_active : !s.is_active)
    return m && co && t && st
  })
  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Suppliers</h1>
        <p className="text-sm text-gray-500 mt-0.5">Vendor master records for purchasing, AP, and BIR 2307 generation</p></div>
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
          <button onClick={() => { setForm({ ...EMPTY }); setBankAccounts([]); setRemovedBankIds([]); setEditId(null); setShowForm(true); setSaved(false) }}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create Supplier
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
                  <p className="font-medium text-gray-500">No Suppliers Found</p>
                  <p className="text-sm mt-1">Click "+ Create Supplier" to add your first vendor.</p>
                </td></tr>
              : filtered.map((s, i) => (
                <tr key={s.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{s.supplier_code}</td>
                  <td className="px-4 py-3">
                    <p className="text-gray-900 font-medium">{s.registered_name}</p>
                    {s.trade_name && <p className="text-xs text-gray-400">{s.trade_name}</p>}
                  </td>
                  <td className="px-4 py-3 font-mono text-gray-600">{normalizePhTin(s.tin)}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                    s.default_tax_type === 'vat_registered' ? 'bg-blue-50 text-blue-700' :
                    s.default_tax_type === 'zero_rated' ? 'bg-green-50 text-green-700' :
                    s.default_tax_type === 'vat_exempt' ? 'bg-orange-50 text-orange-700' :
                    'bg-gray-100 text-gray-600'}`}>
                    {TAX_TYPES.find(t => t.value === s.default_tax_type)?.label.split(' ')[0] || s.default_tax_type}
                  </span></td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{s.contact_person || '—'}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${s.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{s.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openView(s)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button>
                    <button onClick={() => openEdit(s)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleStatus(s)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{s.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
          </tbody>
        </table>
        {filtered.length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {filtered.length} of {suppliers.length} suppliers
          </div>
        )}
      </div>
    </div>
  )
}
