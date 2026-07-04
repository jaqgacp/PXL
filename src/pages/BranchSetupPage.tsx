import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { TablesInsert, TablesUpdate } from '@/lib/database.types'

type RDO = { id: string; rdo_code: string; rdo_name: string }
type Company = { id: string; registered_name: string }
type Branch = {
  id: string; company_id: string; branch_code: string; branch_name: string
  branch_type: string; tin_branch_code: string; rdo_id: string | null
  tax_registration_override: string; address_line_1: string; address_line_2: string
  city: string; province: string; zip_code: string; email: string | null
  phone_number: string | null; mobile_number: string | null; branch_manager: string | null
  is_active: boolean; bir_reg_date: string | null; lgu_permit_number: string | null
  lgu_reg_date: string | null; cas_permit_no: string | null; cas_date_issued: string | null
  companies?: { registered_name: string }; ref_rdo_codes?: { rdo_code: string; rdo_name: string }
}

const BRANCH_TYPES = [
  { value: 'head_office', label: 'Head Office' },
  { value: 'branch', label: 'Branch' },
  { value: 'satellite_office', label: 'Satellite Office' },
  { value: 'warehouse', label: 'Warehouse' },
  { value: 'project_site', label: 'Project Site' },
]
const TAX_OVERRIDES = [
  { value: 'inherit', label: 'Inherit from Company' },
  { value: 'peza', label: 'PEZA (VAT-Exempt)' },
  { value: 'boi', label: 'BOI Registered' },
  { value: 'bmbe', label: 'BMBE Registered' },
]

const EMPTY: Record<string, string> = {
  company_id: '', branch_code: '', branch_name: '', branch_type: 'branch',
  tin_branch_code: '', rdo_id: '', tax_registration_override: 'inherit',
  bir_reg_date: '', lgu_permit_number: '', lgu_reg_date: '', cas_permit_no: '', cas_date_issued: '',
  address_line_1: '', address_line_2: '', city: '', province: '', zip_code: '',
  email: '', phone_number: '', mobile_number: '', branch_manager: '',
}

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function BranchSetupPage() {
  const [branches, setBranches] = useState<Branch[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [rdos, setRdos] = useState<RDO[]>([])
  const [search, setSearch] = useState('')
  const [filterCompany, setFilterCompany] = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'inactive'>('all')
  const [showForm, setShowForm] = useState(false)
  const [showView, setShowView] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [viewData, setViewData] = useState<Branch | null>(null)
  const [form, setForm] = useState({ ...EMPTY })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const fetch = async () => {
    const { data } = await supabase
      .from('branches')
      .select('*, companies(registered_name), ref_rdo_codes(rdo_code, rdo_name)')
      .order('branch_name')
    setBranches((data as Branch[]) || [])
  }

  useEffect(() => {
    fetch()
    supabase.from('companies').select('id, registered_name').order('registered_name')
      .then(({ data }) => setCompanies(data || []))
    supabase.from('ref_rdo_codes').select('id, rdo_code, rdo_name').order('rdo_code')
      .then(({ data }) => setRdos(data || []))
  }, [])

  const set = (k: string, v: string) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const openCreate = () => { setForm({ ...EMPTY }); setEditId(null); setShowForm(true); setSaved(false) }
  const openEdit = (b: Branch) => {
    setForm({
      company_id: b.company_id, branch_code: b.branch_code, branch_name: b.branch_name,
      branch_type: b.branch_type, tin_branch_code: b.tin_branch_code,
      rdo_id: b.rdo_id || '', tax_registration_override: b.tax_registration_override,
      bir_reg_date: b.bir_reg_date || '', lgu_permit_number: b.lgu_permit_number || '',
      lgu_reg_date: b.lgu_reg_date || '', cas_permit_no: b.cas_permit_no || '',
      cas_date_issued: b.cas_date_issued || '', address_line_1: b.address_line_1,
      address_line_2: b.address_line_2, city: b.city, province: b.province,
      zip_code: b.zip_code, email: b.email || '', phone_number: b.phone_number || '',
      mobile_number: b.mobile_number || '', branch_manager: b.branch_manager || '',
    })
    setEditId(b.id); setShowForm(true); setSaved(false)
  }
  const openView = (b: Branch) => { setViewData(b); setShowView(true) }

  const handleSave = async () => {
    setSaving(true)
    const payload = { ...form, rdo_id: form.rdo_id || null, bir_reg_date: form.bir_reg_date || null,
      lgu_reg_date: form.lgu_reg_date || null, cas_date_issued: form.cas_date_issued || null }
    const { error } = editId
      ? await supabase.from('branches').update(payload as TablesUpdate<'branches'>).eq('id', editId)
      : await supabase.from('branches').insert([payload as TablesInsert<'branches'>])
    if (error) alert('Error: ' + error.message)
    else { setSaved(true); fetch() }
    setSaving(false)
  }

  const toggleStatus = async (b: Branch) => {
    await supabase.from('branches').update({ is_active: !b.is_active }).eq('id', b.id)
    fetch()
  }

  // VIEW
  if (showView && viewData) {
    const ro = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700'
    const rdo = rdos.find(r => r.id === viewData.rdo_id)
    const co = companies.find(c => c.id === viewData.company_id)
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setShowView(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
            <h1 className="text-xl font-semibold text-gray-900">View Branch</h1>
            <p className="text-sm text-gray-500 mt-0.5">{viewData.branch_name}</p>
          </div>
          <button onClick={() => setShowView(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Close</button>
        </div>
        <div className={sec}><h2 className={hd}>Section 1 — Branch Identity</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Company</label><input readOnly value={co?.registered_name || '—'} className={ro} /></div>
            <div><label className={lbl}>Branch Code</label><input readOnly value={viewData.branch_code} className={ro} /></div>
            <div className="col-span-2"><label className={lbl}>Branch Name</label><input readOnly value={viewData.branch_name} className={ro} /></div>
            <div><label className={lbl}>Branch Type</label><input readOnly value={BRANCH_TYPES.find(t => t.value === viewData.branch_type)?.label || viewData.branch_type} className={ro} /></div>
            <div><label className={lbl}>TIN Branch Code</label><input readOnly value={viewData.tin_branch_code || '—'} className={ro} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 2 — BIR, Tax & LGU Registration</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>RDO Code</label><input readOnly value={rdo ? `${rdo.rdo_code} — ${rdo.rdo_name}` : '—'} className={ro} /></div>
            <div><label className={lbl}>Tax Registration Override</label><input readOnly value={TAX_OVERRIDES.find(t => t.value === viewData.tax_registration_override)?.label || '—'} className={ro} /></div>
            <div><label className={lbl}>BIR Registration Date</label><input readOnly value={viewData.bir_reg_date || '—'} className={ro} /></div>
            <div><label className={lbl}>LGU Permit Number</label><input readOnly value={viewData.lgu_permit_number || '—'} className={ro} /></div>
            <div><label className={lbl}>LGU Reg. Date</label><input readOnly value={viewData.lgu_reg_date || '—'} className={ro} /></div>
            <div><label className={lbl}>CAS/PTU Number</label><input readOnly value={viewData.cas_permit_no || '—'} className={ro} /></div>
            <div><label className={lbl}>CAS Date Issued</label><input readOnly value={viewData.cas_date_issued || '—'} className={ro} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 3 — Branch Address</h2>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2"><label className={lbl}>Address Line 1</label><input readOnly value={viewData.address_line_1} className={ro} /></div>
            <div className="col-span-2"><label className={lbl}>Address Line 2</label><input readOnly value={viewData.address_line_2} className={ro} /></div>
            <div><label className={lbl}>City / Municipality</label><input readOnly value={viewData.city} className={ro} /></div>
            <div><label className={lbl}>Province</label><input readOnly value={viewData.province} className={ro} /></div>
            <div><label className={lbl}>ZIP Code</label><input readOnly value={viewData.zip_code} className={ro} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 4 — Contact Details</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Branch Email</label><input readOnly value={viewData.email || '—'} className={ro} /></div>
            <div><label className={lbl}>Phone Number</label><input readOnly value={viewData.phone_number || '—'} className={ro} /></div>
            <div><label className={lbl}>Mobile Number</label><input readOnly value={viewData.mobile_number || '—'} className={ro} /></div>
            <div><label className={lbl}>Branch Manager</label><input readOnly value={viewData.branch_manager || '—'} className={ro} /></div>
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
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Branch' : 'Create New Branch'}</h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={handleSave} disabled={saving}
            className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update Branch' : 'Save Branch'}
          </button>
        </div>
      </div>
      <div className={sec}><h2 className={hd}>Section 1 — Branch Identity</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={lbl}>Company <span className="text-red-500">*</span></label>
            <select value={form.company_id} onChange={e => set('company_id', e.target.value)} className={inp}>
              <option value="">Select company...</option>
              {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
            </select>
          </div>
          <div>
            <label className={lbl}>Branch Code <span className="text-red-500">*</span></label>
            <input value={form.branch_code} onChange={e => set('branch_code', e.target.value.toUpperCase())}
              className={inp} placeholder="e.g., HO, BR-001, CEB" />
          </div>
          <div className="col-span-2">
            <label className={lbl}>Branch Name <span className="text-red-500">*</span></label>
            <input value={form.branch_name} onChange={e => set('branch_name', e.target.value)}
              className={inp} placeholder="e.g., Head Office, Cebu Branch" />
          </div>
          <div>
            <label className={lbl}>Branch Type <span className="text-red-500">*</span></label>
            <select value={form.branch_type} onChange={e => set('branch_type', e.target.value)} className={inp}>
              {BRANCH_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
          <div>
            <label className={lbl}>TIN Branch Code <span className="text-red-500">*</span></label>
            <input value={form.tin_branch_code} onChange={e => set('tin_branch_code', e.target.value)}
              className={inp} placeholder="e.g., 00000 (Head Office), 00001 (Branch 1)" maxLength={5} />
          </div>
        </div>
      </div>
      <div className={sec}><h2 className={hd}>Section 2 — BIR, Tax & LGU Registration</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={lbl}>RDO Code <span className="text-red-500">*</span></label>
            <select value={form.rdo_id} onChange={e => set('rdo_id', e.target.value)} className={inp}>
              <option value="">Select RDO...</option>
              {rdos.map(r => <option key={r.id} value={r.id}>{r.rdo_code} — {r.rdo_name}</option>)}
            </select>
          </div>
          <div>
            <label className={lbl}>Tax Registration Override</label>
            <select value={form.tax_registration_override} onChange={e => set('tax_registration_override', e.target.value)} className={inp}>
              {TAX_OVERRIDES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
          <div><label className={lbl}>BIR Registration Date</label>
            <input type="date" value={form.bir_reg_date} onChange={e => set('bir_reg_date', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>LGU Permit Number</label>
            <input value={form.lgu_permit_number} onChange={e => set('lgu_permit_number', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>LGU Reg. Date</label>
            <input type="date" value={form.lgu_reg_date} onChange={e => set('lgu_reg_date', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>CAS / PTU Number</label>
            <input value={form.cas_permit_no} onChange={e => set('cas_permit_no', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>CAS Date Issued</label>
            <input type="date" value={form.cas_date_issued} onChange={e => set('cas_date_issued', e.target.value)} className={inp} /></div>
        </div>
      </div>
      <div className={sec}><h2 className={hd}>Section 3 — Branch Address</h2>
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2"><label className={lbl}>Address Line 1 <span className="text-red-500">*</span></label>
            <input value={form.address_line_1} onChange={e => set('address_line_1', e.target.value)} className={inp} placeholder="Unit / Building / Lot / Block / Street" /></div>
          <div className="col-span-2"><label className={lbl}>Address Line 2 <span className="text-red-500">*</span></label>
            <input value={form.address_line_2} onChange={e => set('address_line_2', e.target.value)} className={inp} placeholder="Subdivision / Village / Barangay" /></div>
          <div><label className={lbl}>City / Municipality <span className="text-red-500">*</span></label>
            <input value={form.city} onChange={e => set('city', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Province <span className="text-red-500">*</span></label>
            <input value={form.province} onChange={e => set('province', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>ZIP Code <span className="text-red-500">*</span></label>
            <input value={form.zip_code} onChange={e => set('zip_code', e.target.value)} className={inp} maxLength={4} /></div>
        </div>
      </div>
      <div className={sec}><h2 className={hd}>Section 4 — Contact Details</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>Branch Email</label>
            <input type="email" value={form.email} onChange={e => set('email', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Phone Number</label>
            <input value={form.phone_number} onChange={e => set('phone_number', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Mobile Number</label>
            <input value={form.mobile_number} onChange={e => set('mobile_number', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Branch Manager</label>
            <input value={form.branch_manager} onChange={e => set('branch_manager', e.target.value)} className={inp} /></div>
        </div>
      </div>
    </div>
  )

  // LIST
  const filtered = branches.filter(b => {
    const m = !search || b.branch_code.toLowerCase().includes(search.toLowerCase()) || b.branch_name.toLowerCase().includes(search.toLowerCase())
    const c = !filterCompany || b.company_id === filterCompany
    const s = filterStatus === 'all' || (filterStatus === 'active' ? b.is_active : !b.is_active)
    return m && c && s
  })
  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Branch Setup</h1>
        <p className="text-sm text-gray-500 mt-0.5">Manage operational branches per company</p></div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-56 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search by code or name..." />
        <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
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
            + Create New Branch
          </button>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Branch Code</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Branch Name</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">City</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr><td colSpan={7} className="text-center py-16 text-gray-400">
                <p className="text-base font-medium text-gray-500">No Branches Found</p>
                <p className="text-sm mt-1">Click "+ Create New Branch" to add your first branch.</p>
              </td></tr>
            ) : filtered.map((b, i) => (
              <tr key={b.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                <td className="px-4 py-3 font-mono font-medium text-gray-900">{b.branch_code}</td>
                <td className="px-4 py-3 text-gray-900">{b.branch_name}</td>
                <td className="px-4 py-3 text-gray-500">{b.companies?.registered_name || '—'}</td>
                <td className="px-4 py-3 text-gray-600">{BRANCH_TYPES.find(t => t.value === b.branch_type)?.label || b.branch_type}</td>
                <td className="px-4 py-3 text-gray-600">{b.city}</td>
                <td className="px-4 py-3">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${b.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>
                    {b.is_active ? 'Active' : 'Inactive'}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <button onClick={() => openView(b)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button>
                    <button onClick={() => openEdit(b)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleStatus(b)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">
                      {b.is_active ? 'Deactivate' : 'Activate'}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {filtered.length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {filtered.length} of {branches.length} branches
          </div>
        )}
      </div>
    </div>
  )
}
