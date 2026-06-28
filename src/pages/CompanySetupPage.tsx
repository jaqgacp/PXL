import { useState, useEffect, useRef } from 'react'
import { supabase } from '@/lib/supabase'

type RDO = { id: string; rdo_code: string; rdo_name: string }
type Company = {
  id: string
  registered_name: string
  trade_name: string
  tin: string
  tax_registration: string
  rdo_id: string
  is_active: boolean
  parent_company_id: string | null
  entity_type: string
  ref_rdo_codes?: { rdo_code: string; rdo_name: string }
}

const ENTITY_TYPES = [
  { value: 'sole_proprietor', label: 'Sole Proprietor' },
  { value: 'opc', label: 'OPC' },
  { value: 'corporation', label: 'Regular Corporation' },
  { value: 'partnership', label: 'Partnership' },
  { value: 'cooperative', label: 'Cooperative' },
]

const TAX_REG_LABELS: Record<string, string> = {
  vat: 'VAT', non_vat: 'Non-VAT', exempt: 'Exempt'
}

const REG_NUMBER_LABEL: Record<string, string> = {
  sole_proprietor: 'DTI No.', opc: 'SEC No.',
  corporation: 'SEC No.', partnership: 'SEC No.', cooperative: 'CDA No.',
}

const MONTHS = ['January','February','March','April','May','June',
  'July','August','September','October','November','December']

const EMPTY_FORM = {
  parent_company_id: '', entity_type: '', registered_name: '',
  trade_name: '', line_of_business: '', psic_code: '', tin: '',
  tax_registration: '', rdo_id: '', registration_number: '',
  bir_reg_date: '', sec_dti_reg_date: '', lgu_reg_date: '',
  accounting_period: '', fiscal_start_month: '', cas_permit_no: '',
  cas_date_issued: '', address_line_1: '', address_line_2: '',
  city: '', province: '', zip_code: '', email: '',
  phone_number: '', mobile_number: '', signatory_name: '',
  signatory_position: '', signatory_tin: '',
}

export default function CompanySetupPage() {
  const [companies, setCompanies] = useState<Company[]>([])
  const [rdos, setRdos] = useState<RDO[]>([])
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'inactive'>('all')
  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState({ ...EMPTY_FORM })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  const fetchCompanies = async () => {
    const { data } = await supabase
      .from('companies')
      .select('*, ref_rdo_codes(rdo_code, rdo_name)')
      .order('registered_name')
    setCompanies((data as Company[]) || [])
  }

  useEffect(() => {
    fetchCompanies()
    supabase.from('ref_rdo_codes').select('id, rdo_code, rdo_name').order('rdo_code')
      .then(({ data }) => setRdos(data || []))
  }, [])

  const set = (k: string, v: string) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const openCreate = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setShowForm(true); setSaved(false) }

  const openEdit = (c: Company) => {
    setForm({
      parent_company_id: c.parent_company_id || '',
      entity_type: c.entity_type || '',
      registered_name: c.registered_name || '',
      trade_name: c.trade_name || '',
      line_of_business: '', psic_code: '', tin: c.tin || '',
      tax_registration: c.tax_registration || '',
      rdo_id: c.rdo_id || '', registration_number: '',
      bir_reg_date: '', sec_dti_reg_date: '', lgu_reg_date: '',
      accounting_period: '', fiscal_start_month: '', cas_permit_no: '',
      cas_date_issued: '', address_line_1: '', address_line_2: '',
      city: '', province: '', zip_code: '', email: '',
      phone_number: '', mobile_number: '', signatory_name: '',
      signatory_position: '', signatory_tin: '',
    })
    setEditId(c.id)
    setShowForm(true)
    setSaved(false)
  }

  const handleSave = async () => {
    setSaving(true)
    const payload = {
      ...form,
      parent_company_id: form.parent_company_id || null,
      rdo_id: form.rdo_id || null,
      fiscal_start_month: form.fiscal_start_month ? parseInt(form.fiscal_start_month) : null,
      bir_reg_date: form.bir_reg_date || null,
      sec_dti_reg_date: form.sec_dti_reg_date || null,
      lgu_reg_date: form.lgu_reg_date || null,
      cas_date_issued: form.cas_date_issued || null,
    }
    const { error } = editId
      ? await supabase.from('companies').update(payload).eq('id', editId)
      : await supabase.from('companies').insert([payload])
    if (error) alert('Cannot save company.\nReason: ' + error.message)
    else { setSaved(true); fetchCompanies() }
    setSaving(false)
  }

  const handleToggleStatus = async (c: Company) => {
    await supabase.from('companies').update({ is_active: !c.is_active }).eq('id', c.id)
    fetchCompanies()
  }

  const handleImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const text = await file.text()
    const lines = text.split('\n').filter(Boolean)
    const headers = lines[0].split(',').map(h => h.trim().toLowerCase().replace(/ /g, '_'))
    const rows = lines.slice(1).map(line => {
      const vals = line.split(',')
      return Object.fromEntries(headers.map((h, i) => [h, vals[i]?.trim() || '']))
    })
    const { error } = await supabase.from('companies').insert(rows)
    if (error) alert('Import failed: ' + error.message)
    else { fetchCompanies(); alert(`Imported ${rows.length} companies.`) }
    e.target.value = ''
  }

  const filtered = companies.filter(c => {
    const matchSearch = !search ||
      c.registered_name?.toLowerCase().includes(search.toLowerCase()) ||
      c.tin?.includes(search)
    const matchStatus = filterStatus === 'all' ||
      (filterStatus === 'active' && c.is_active) ||
      (filterStatus === 'inactive' && !c.is_active)
    return matchSearch && matchStatus
  })

  const inputClass = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
  const labelClass = 'block text-xs font-medium text-gray-500 mb-1'
  const sectionClass = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
  const headingClass = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

  if (showForm) return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Company' : 'Create New Company'}</h1>
          <p className="text-sm text-gray-500 mt-0.5">Legal, tax, and registration details</p>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)}
            className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
            Cancel
          </button>
          <button onClick={handleSave} disabled={saving}
            className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update Company' : 'Save Company'}
          </button>
        </div>
      </div>

      {/* Section 1 */}
      <div className={sectionClass}>
        <h2 className={headingClass}>Section 1 — Basic Information</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={labelClass}>Parent Company</label>
            <select value={form.parent_company_id} onChange={e => set('parent_company_id', e.target.value)} className={inputClass}>
              <option value="">None (Independent / Holding)</option>
              {companies.filter(c => c.id !== editId).map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
            </select>
          </div>
          <div>
            <label className={labelClass}>Entity Type <span className="text-red-500">*</span></label>
            <select value={form.entity_type} onChange={e => set('entity_type', e.target.value)} className={inputClass}>
              <option value="">Select...</option>
              {ENTITY_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
          <div className="col-span-2">
            <label className={labelClass}>Registered Name <span className="text-red-500">*</span></label>
            <input value={form.registered_name} onChange={e => set('registered_name', e.target.value)}
              className={inputClass} placeholder="As it appears on BIR Form 2303" />
          </div>
          <div>
            <label className={labelClass}>Trade Name</label>
            <input value={form.trade_name} onChange={e => set('trade_name', e.target.value)}
              className={inputClass} placeholder="Doing Business As (DBA)" />
          </div>
          <div>
            <label className={labelClass}>Line of Business <span className="text-red-500">*</span></label>
            <input value={form.line_of_business} onChange={e => set('line_of_business', e.target.value)}
              className={inputClass} placeholder="Main business activity" />
          </div>
          <div>
            <label className={labelClass}>PSIC Code <span className="text-red-500">*</span></label>
            <input value={form.psic_code} onChange={e => set('psic_code', e.target.value)}
              className={inputClass} placeholder="Philippine Standard Industrial Classification" />
          </div>
        </div>
      </div>

      {/* Section 2 */}
      <div className={sectionClass}>
        <h2 className={headingClass}>Section 2 — Registration & Tax Compliance</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={labelClass}>TIN <span className="text-red-500">*</span></label>
            <input value={form.tin} onChange={e => set('tin', e.target.value)} className={inputClass} placeholder="000-000-000-00000" />
          </div>
          <div>
            <label className={labelClass}>Tax Registration <span className="text-red-500">*</span></label>
            <select value={form.tax_registration} onChange={e => set('tax_registration', e.target.value)} className={inputClass}>
              <option value="">Select...</option>
              <option value="vat">VAT</option>
              <option value="non_vat">Non-VAT (Percentage Tax)</option>
              <option value="exempt">Exempt</option>
            </select>
          </div>
          <div>
            <label className={labelClass}>RDO Code <span className="text-red-500">*</span></label>
            <select value={form.rdo_id} onChange={e => set('rdo_id', e.target.value)} className={inputClass}>
              <option value="">Select RDO...</option>
              {rdos.map(r => <option key={r.id} value={r.id}>{r.rdo_code} — {r.rdo_name}</option>)}
            </select>
          </div>
          <div>
            <label className={labelClass}>{form.entity_type ? REG_NUMBER_LABEL[form.entity_type] : 'Registration Number'}</label>
            <input value={form.registration_number} onChange={e => set('registration_number', e.target.value)}
              className={inputClass} placeholder="SEC / DTI / CDA number" />
          </div>
          <div>
            <label className={labelClass}>BIR Registration Date</label>
            <input type="date" value={form.bir_reg_date} onChange={e => set('bir_reg_date', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>SEC / DTI Registration Date</label>
            <input type="date" value={form.sec_dti_reg_date} onChange={e => set('sec_dti_reg_date', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>LGU / Mayor's Permit Date</label>
            <input type="date" value={form.lgu_reg_date} onChange={e => set('lgu_reg_date', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>Accounting Period <span className="text-red-500">*</span></label>
            <select value={form.accounting_period} onChange={e => set('accounting_period', e.target.value)} className={inputClass}>
              <option value="">Select...</option>
              <option value="calendar">Calendar Year (Jan–Dec)</option>
              <option value="fiscal">Fiscal Year</option>
            </select>
          </div>
          {form.accounting_period === 'fiscal' && (
            <div>
              <label className={labelClass}>Fiscal Start Month <span className="text-red-500">*</span></label>
              <select value={form.fiscal_start_month} onChange={e => set('fiscal_start_month', e.target.value)} className={inputClass}>
                <option value="">Select month...</option>
                {MONTHS.map((m, i) => <option key={i} value={i + 1}>{m}</option>)}
              </select>
            </div>
          )}
        </div>
      </div>

      {/* Section 3 */}
      <div className={sectionClass}>
        <h2 className={headingClass}>Section 3 — System Compliance (CAS / PTU)</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={labelClass}>CAS / PTU Number</label>
            <input value={form.cas_permit_no} onChange={e => set('cas_permit_no', e.target.value)}
              className={inputClass} placeholder="Acknowledgement Certificate or PTU number" />
          </div>
          <div>
            <label className={labelClass}>Date Issued</label>
            <input type="date" value={form.cas_date_issued} onChange={e => set('cas_date_issued', e.target.value)} className={inputClass} />
          </div>
        </div>
      </div>

      {/* Section 4 */}
      <div className={sectionClass}>
        <h2 className={headingClass}>Section 4 — Registered Address</h2>
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2">
            <label className={labelClass}>Address Line 1 <span className="text-red-500">*</span></label>
            <input value={form.address_line_1} onChange={e => set('address_line_1', e.target.value)}
              className={inputClass} placeholder="Unit / Building / Lot / Block / Street" />
          </div>
          <div className="col-span-2">
            <label className={labelClass}>Address Line 2 <span className="text-red-500">*</span></label>
            <input value={form.address_line_2} onChange={e => set('address_line_2', e.target.value)}
              className={inputClass} placeholder="Subdivision / Village / Barangay" />
          </div>
          <div>
            <label className={labelClass}>City / Municipality <span className="text-red-500">*</span></label>
            <input value={form.city} onChange={e => set('city', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>Province <span className="text-red-500">*</span></label>
            <input value={form.province} onChange={e => set('province', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>ZIP Code <span className="text-red-500">*</span></label>
            <input value={form.zip_code} onChange={e => set('zip_code', e.target.value)}
              className={inputClass} placeholder="4-digit postal code" maxLength={4} />
          </div>
        </div>
      </div>

      {/* Section 5 */}
      <div className={sectionClass}>
        <h2 className={headingClass}>Section 5 — Contact & Authorized Representative</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={labelClass}>Official Email <span className="text-red-500">*</span></label>
            <input type="email" value={form.email} onChange={e => set('email', e.target.value)}
              className={inputClass} placeholder="Registered company email" />
          </div>
          <div>
            <label className={labelClass}>Phone Number</label>
            <input value={form.phone_number} onChange={e => set('phone_number', e.target.value)} className={inputClass} placeholder="Landline" />
          </div>
          <div>
            <label className={labelClass}>Mobile Number</label>
            <input value={form.mobile_number} onChange={e => set('mobile_number', e.target.value)} className={inputClass} placeholder="Mobile" />
          </div>
          <div>
            <label className={labelClass}>Signatory Name <span className="text-red-500">*</span></label>
            <input value={form.signatory_name} onChange={e => set('signatory_name', e.target.value)}
              className={inputClass} placeholder="Authorized to sign tax returns and 2307s" />
          </div>
          <div>
            <label className={labelClass}>Signatory Position <span className="text-red-500">*</span></label>
            <input value={form.signatory_position} onChange={e => set('signatory_position', e.target.value)}
              className={inputClass} placeholder="e.g., President, Treasurer, Owner" />
          </div>
          <div>
            <label className={labelClass}>Signatory TIN</label>
            <input value={form.signatory_tin} onChange={e => set('signatory_tin', e.target.value)}
              className={inputClass} placeholder="Personal TIN of signatory" />
          </div>
        </div>
      </div>
    </div>
  )

  // LIST VIEW
  return (
    <div className="space-y-4">
      {/* Page header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Company Setup</h1>
          <p className="text-sm text-gray-500 mt-0.5">Manage all registered business entities</p>
        </div>
      </div>

      {/* Action bar */}
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-64 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search by name or TIN..." />
        <select value={filterStatus} onChange={e => setFilterStatus(e.target.value as typeof filterStatus)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900">
          <option value="all">All Status</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
        <div className="ml-auto flex items-center gap-2">
          <button onClick={() => fileRef.current?.click()}
            className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 transition-colors">
            ↑ Import
          </button>
          <input ref={fileRef} type="file" accept=".csv" className="hidden" onChange={handleImport} />
          <button className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 transition-colors">
            ↓ Export
          </button>
          <button className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50 transition-colors">
            🖨 Print
          </button>
          <button onClick={openCreate}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800 transition-colors">
            + Create New Company
          </button>
        </div>
      </div>

      {/* Table */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Registered Name</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Parent Company</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">TIN</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">RDO</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Type</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan={7} className="text-center py-16 text-gray-400">
                  <p className="text-base font-medium text-gray-500">No Companies Found</p>
                  <p className="text-sm mt-1">Click "Create New Company" to add your first company.</p>
                </td>
              </tr>
            ) : filtered.map((c, i) => (
              <tr key={c.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                <td className="px-4 py-3 font-medium text-gray-900">
                  {c.registered_name}
                  {c.trade_name && <span className="text-gray-400 text-xs ml-1">({c.trade_name})</span>}
                </td>
                <td className="px-4 py-3 text-gray-600">—</td>
                <td className="px-4 py-3 text-gray-600 font-mono">{c.tin}</td>
                <td className="px-4 py-3 text-gray-600">
                  {c.ref_rdo_codes ? `${c.ref_rdo_codes.rdo_code} — ${c.ref_rdo_codes.rdo_name}` : '—'}
                </td>
                <td className="px-4 py-3">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                    c.tax_registration === 'vat' ? 'bg-blue-50 text-blue-700' :
                    c.tax_registration === 'non_vat' ? 'bg-amber-50 text-amber-700' :
                    'bg-gray-100 text-gray-600'
                  }`}>
                    {TAX_REG_LABELS[c.tax_registration] || c.tax_registration}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                    c.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'
                  }`}>
                    {c.is_active ? 'Active' : 'Inactive'}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <button onClick={() => openEdit(c)}
                      className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => handleToggleStatus(c)}
                      className="text-xs text-gray-500 hover:text-gray-700 font-medium">
                      {c.is_active ? 'Deactivate' : 'Activate'}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {/* Footer */}
        {filtered.length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {filtered.length} of {companies.length} companies
          </div>
        )}
      </div>
    </div>
  )
}