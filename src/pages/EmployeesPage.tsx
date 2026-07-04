import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Department = { id: string; department_name: string }
type Branch = { id: string; branch_name: string }
type Employee = {
  id: string; employee_number: string; last_name: string; first_name: string; middle_name: string
  suffix: string; department_id: string; job_title: string; employment_type: string
  hire_date: string; regularization_date: string; separation_date: string; separation_reason: string
  birth_date: string; gender: string; civil_status: string
  tin: string; sss_no: string; philhealth_no: string; pagibig_no: string
  email: string; mobile: string; address_line: string; city_municipality: string; province: string
  branch_id: string; notes: string; is_active: boolean
  department_name?: string
}

const BLANK: Omit<Employee, 'id' | 'department_name'> = {
  employee_number: '', last_name: '', first_name: '', middle_name: '', suffix: '',
  department_id: '', job_title: '', employment_type: 'regular',
  hire_date: '', regularization_date: '', separation_date: '', separation_reason: '',
  birth_date: '', gender: '', civil_status: '',
  tin: '', sss_no: '', philhealth_no: '', pagibig_no: '',
  email: '', mobile: '', address_line: '', city_municipality: '', province: '',
  branch_id: '', notes: '', is_active: true,
}

const ET_COLOR: Record<string, string> = {
  regular: 'bg-green-50 text-green-700',
  probationary: 'bg-yellow-50 text-yellow-700',
  contractual: 'bg-blue-50 text-blue-700',
  part_time: 'bg-purple-50 text-purple-700',
  consultant: 'bg-gray-100 text-gray-600',
}

export default function EmployeesPage() {
  const { companyId, branchId } = useAppCtx()
  const [employees, setEmployees] = useState<Employee[]>([])
  const [departments, setDepartments] = useState<Department[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState('all')
  const [showInactive, setShowInactive] = useState(false)
  const [modal, setModal] = useState<'new' | 'edit' | null>(null)
  const [form, setForm] = useState<Omit<Employee, 'id' | 'department_name'>>(BLANK)
  const [editId, setEditId] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [activeTab, setActiveTab] = useState<'info' | 'gov' | 'contact'>('info')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: empData }, { data: deptData }, { data: brData }] = await Promise.all([
      supabase.from('employees').select(`id,employee_number,last_name,first_name,middle_name,suffix,
        department_id,job_title,employment_type,hire_date,regularization_date,separation_date,separation_reason,
        birth_date,gender,civil_status,tin,sss_no,philhealth_no,pagibig_no,email,mobile,
        address_line,city_municipality,province,branch_id,notes,is_active,
        departments(department_name)`
      ).eq('company_id', companyId).order('last_name').order('first_name'),
      supabase.from('departments').select('id,department_name').eq('company_id', companyId).order('department_name'),
      supabase.from('branches').select('id,branch_name').eq('company_id', companyId).order('branch_name'),
    ])
    setEmployees(((empData || []) as any[]).map(e => ({ ...e, department_name: e.departments?.department_name ?? '' })))
    setDepartments((deptData as Department[]) || [])
    setBranches((brData as Branch[]) || [])
  }, [companyId])

  useEffect(() => { load() }, [load])

  const openNew = () => {
    setForm({ ...BLANK, branch_id: branchId || '' })
    setEditId(null); setError(''); setActiveTab('info'); setModal('new')
  }

  const openEdit = (emp: Employee) => {
    const { department_name: _department_name, ...rest } = emp
    setForm(rest); setEditId(emp.id); setError(''); setActiveTab('info'); setModal('edit')
  }

  const set = (field: keyof typeof BLANK, value: string | boolean) =>
    setForm(p => ({ ...p, [field]: value }))

  const save = async () => {
    if (!companyId) return
    if (!form.last_name.trim() || !form.first_name.trim()) { setError('Last name and first name are required'); return }
    if (!form.hire_date) { setError('Hire date is required'); return }
    setSaving(true); setError('')

    const payload = {
      company_id: companyId,
      branch_id: form.branch_id || null,
      employee_number: form.employee_number.trim() || `EMP-${Date.now()}`,
      last_name: form.last_name.trim(),
      first_name: form.first_name.trim(),
      middle_name: form.middle_name.trim() || null,
      suffix: form.suffix.trim() || null,
      department_id: form.department_id || null,
      job_title: form.job_title.trim() || null,
      employment_type: form.employment_type,
      hire_date: form.hire_date,
      regularization_date: form.regularization_date || null,
      separation_date: form.separation_date || null,
      separation_reason: form.separation_reason.trim() || null,
      birth_date: form.birth_date || null,
      gender: form.gender || null,
      civil_status: form.civil_status || null,
      tin: form.tin.trim() || null,
      sss_no: form.sss_no.trim() || null,
      philhealth_no: form.philhealth_no.trim() || null,
      pagibig_no: form.pagibig_no.trim() || null,
      email: form.email.trim() || null,
      mobile: form.mobile.trim() || null,
      address_line: form.address_line.trim() || null,
      city_municipality: form.city_municipality.trim() || null,
      province: form.province.trim() || null,
      notes: form.notes.trim() || null,
      is_active: form.is_active,
    }

    const { error: e } = editId
      ? await supabase.from('employees').update(payload).eq('id', editId)
      : await supabase.from('employees').insert(payload)
    setSaving(false)
    if (e) { setError(e.message); return }
    setModal(null); load()
  }

  const toggleActive = async (emp: Employee) => {
    await supabase.from('employees').update({ is_active: !emp.is_active }).eq('id', emp.id)
    load()
  }

  const visible = employees.filter(e => {
    if (!showInactive && !e.is_active) return false
    if (typeFilter !== 'all' && e.employment_type !== typeFilter) return false
    const q = search.toLowerCase()
    return !q || e.last_name.toLowerCase().includes(q) || e.first_name.toLowerCase().includes(q) ||
      e.employee_number.toLowerCase().includes(q) || (e.department_name ?? '').toLowerCase().includes(q) ||
      (e.tin ?? '').includes(q)
  })

  const fullName = (e: Employee) => [e.last_name, e.first_name, e.middle_name].filter(Boolean).join(', ')

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Employees</span>
        <button onClick={openNew}
          className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-xs font-medium hover:bg-gray-800">
          + New Employee
        </button>
      </div>

      <div className="px-5 py-4 space-y-3">
        {/* Filters */}
        <div className="bg-white border border-gray-200 rounded-lg p-3 flex items-end gap-3 flex-wrap">
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Search</label>
            <input value={search} onChange={e => setSearch(e.target.value)}
              placeholder="Name, ID, TIN…"
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs w-48 focus:outline-none focus:ring-1 focus:ring-gray-900" />
          </div>
          <div>
            <label className="block text-[10px] text-gray-500 mb-1">Employment Type</label>
            <select value={typeFilter} onChange={e => setTypeFilter(e.target.value)}
              className="border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="all">All Types</option>
              <option value="regular">Regular</option>
              <option value="probationary">Probationary</option>
              <option value="contractual">Contractual</option>
              <option value="part_time">Part-time</option>
              <option value="consultant">Consultant</option>
            </select>
          </div>
          <label className="flex items-center gap-1.5 cursor-pointer select-none text-xs text-gray-600 mb-0.5">
            <input type="checkbox" checked={showInactive} onChange={e => setShowInactive(e.target.checked)} className="rounded" />
            Show inactive
          </label>
          <span className="text-xs text-gray-400 ml-auto">{visible.length} employee{visible.length !== 1 ? 's' : ''}</span>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['Employee #','Name','Department','Job Title','Type','Hire Date','TIN','Status',''].map(h => (
                <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
              ))}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {visible.length === 0 ? (
                <tr><td colSpan={9} className="py-12 text-center text-gray-400">No employees found</td></tr>
              ) : visible.map(e => (
                <tr key={e.id} className={`hover:bg-gray-50/60 ${!e.is_active ? 'opacity-50' : ''}`}>
                  <td className="px-3 py-2 font-mono text-gray-600">{e.employee_number}</td>
                  <td className="px-3 py-2 font-semibold text-gray-900">{fullName(e)}</td>
                  <td className="px-3 py-2 text-gray-600">{e.department_name || '—'}</td>
                  <td className="px-3 py-2 text-gray-600">{e.job_title || '—'}</td>
                  <td className="px-3 py-2">
                    <span className={`inline-flex px-2 py-0.5 rounded text-[10px] font-medium capitalize ${ET_COLOR[e.employment_type] || 'bg-gray-100 text-gray-600'}`}>
                      {e.employment_type.replace('_', ' ')}
                    </span>
                  </td>
                  <td className="px-3 py-2 font-mono text-gray-500">{e.hire_date}</td>
                  <td className="px-3 py-2 font-mono text-gray-500">{e.tin || '—'}</td>
                  <td className="px-3 py-2">
                    <span className={`inline-flex px-2 py-0.5 rounded text-[10px] font-medium ${e.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>
                      {e.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="px-3 py-2 flex gap-2">
                    <button onClick={() => openEdit(e)} className="text-xs text-gray-500 hover:text-gray-900 underline">Edit</button>
                    <button onClick={() => toggleActive(e)} className="text-xs text-gray-400 hover:text-gray-700 underline">
                      {e.is_active ? 'Deactivate' : 'Activate'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Modal */}
      {modal && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-start justify-center pt-12 px-4">
          <div className="bg-white rounded-xl shadow-2xl w-full max-w-2xl max-h-[85vh] flex flex-col">
            <div className="px-5 py-4 border-b border-gray-200 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-gray-900">{modal === 'new' ? 'New Employee' : 'Edit Employee'}</h2>
              <button onClick={() => setModal(null)} className="text-gray-400 hover:text-gray-600 text-lg leading-none">✕</button>
            </div>

            {/* Tabs */}
            <div className="border-b border-gray-200 px-5 flex gap-4">
              {(['info','gov','contact'] as const).map(t => (
                <button key={t} onClick={() => setActiveTab(t)}
                  className={`py-2.5 text-xs font-medium border-b-2 transition-colors ${activeTab === t ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-400 hover:text-gray-700'}`}>
                  {t === 'info' ? 'Employment Info' : t === 'gov' ? 'Gov\'t IDs' : 'Contact & Address'}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto px-5 py-4">
              {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2 mb-3">{error}</div>}

              {activeTab === 'info' && (
                <div className="space-y-3">
                  <div className="grid grid-cols-3 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Employee # *</label>
                      <input value={form.employee_number} onChange={e => set('employee_number', e.target.value)}
                        placeholder="Auto-generated if blank"
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Branch</label>
                      <select value={form.branch_id} onChange={e => set('branch_id', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                        <option value="">— Select —</option>
                        {branches.map(b => <option key={b.id} value={b.id}>{b.branch_name}</option>)}
                      </select>
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Department</label>
                      <select value={form.department_id} onChange={e => set('department_id', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                        <option value="">— Select —</option>
                        {departments.map(d => <option key={d.id} value={d.id}>{d.department_name}</option>)}
                      </select>
                    </div>
                  </div>
                  <div className="grid grid-cols-4 gap-3">
                    <div className="col-span-1">
                      <label className="block text-xs font-medium text-gray-600 mb-1">Last Name *</label>
                      <input value={form.last_name} onChange={e => set('last_name', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div className="col-span-1">
                      <label className="block text-xs font-medium text-gray-600 mb-1">First Name *</label>
                      <input value={form.first_name} onChange={e => set('first_name', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Middle Name</label>
                      <input value={form.middle_name} onChange={e => set('middle_name', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Suffix</label>
                      <input value={form.suffix} onChange={e => set('suffix', e.target.value)}
                        placeholder="Jr., Sr., III…"
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Job Title</label>
                      <input value={form.job_title} onChange={e => set('job_title', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Employment Type *</label>
                      <select value={form.employment_type} onChange={e => set('employment_type', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                        <option value="regular">Regular</option>
                        <option value="probationary">Probationary</option>
                        <option value="contractual">Contractual</option>
                        <option value="part_time">Part-time</option>
                        <option value="consultant">Consultant</option>
                      </select>
                    </div>
                  </div>
                  <div className="grid grid-cols-3 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Hire Date *</label>
                      <input type="date" value={form.hire_date} onChange={e => set('hire_date', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Regularization Date</label>
                      <input type="date" value={form.regularization_date} onChange={e => set('regularization_date', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Separation Date</label>
                      <input type="date" value={form.separation_date} onChange={e => set('separation_date', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                  </div>
                  <div className="grid grid-cols-3 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Birth Date</label>
                      <input type="date" value={form.birth_date} onChange={e => set('birth_date', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Gender</label>
                      <select value={form.gender} onChange={e => set('gender', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                        <option value="">— Select —</option>
                        <option value="male">Male</option>
                        <option value="female">Female</option>
                        <option value="other">Other</option>
                      </select>
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Civil Status</label>
                      <select value={form.civil_status} onChange={e => set('civil_status', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                        <option value="">— Select —</option>
                        <option value="single">Single</option>
                        <option value="married">Married</option>
                        <option value="widowed">Widowed</option>
                        <option value="separated">Separated</option>
                        <option value="others">Others</option>
                      </select>
                    </div>
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                    <textarea value={form.notes} onChange={e => set('notes', e.target.value)} rows={2}
                      className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 resize-none" />
                  </div>
                  <label className="flex items-center gap-2 text-xs text-gray-700">
                    <input type="checkbox" checked={form.is_active} onChange={e => set('is_active', e.target.checked)} />
                    Active
                  </label>
                </div>
              )}

              {activeTab === 'gov' && (
                <div className="space-y-3">
                  <div className="bg-blue-50 border border-blue-200 rounded px-3 py-2 text-xs text-blue-800">
                    Government IDs are required for BIR compliance — TIN is mandatory for withholding tax purposes.
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    {[
                      { field: 'tin', label: 'TIN (BIR)', placeholder: '000-000-000-000' },
                      { field: 'sss_no', label: 'SSS Number', placeholder: '00-0000000-0' },
                      { field: 'philhealth_no', label: 'PhilHealth Number', placeholder: '00-000000000-0' },
                      { field: 'pagibig_no', label: 'Pag-IBIG / HDMF', placeholder: '0000-0000-0000' },
                    ].map(({ field, label, placeholder }) => (
                      <div key={field}>
                        <label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>
                        <input value={(form as any)[field]} onChange={e => set(field as any, e.target.value)}
                          placeholder={placeholder}
                          className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm font-mono focus:outline-none focus:ring-1 focus:ring-gray-900" />
                      </div>
                    ))}
                  </div>
                  {form.separation_date && (
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Separation Reason</label>
                      <input value={form.separation_reason} onChange={e => set('separation_reason', e.target.value)}
                        placeholder="Resignation, end of contract, retirement…"
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                  )}
                </div>
              )}

              {activeTab === 'contact' && (
                <div className="space-y-3">
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Email</label>
                      <input type="email" value={form.email} onChange={e => set('email', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Mobile</label>
                      <input value={form.mobile} onChange={e => set('mobile', e.target.value)}
                        placeholder="+63 9XX XXX XXXX"
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">Address</label>
                    <input value={form.address_line} onChange={e => set('address_line', e.target.value)}
                      placeholder="House/Unit No., Street, Barangay"
                      className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">City / Municipality</label>
                      <input value={form.city_municipality} onChange={e => set('city_municipality', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-gray-600 mb-1">Province</label>
                      <input value={form.province} onChange={e => set('province', e.target.value)}
                        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
                    </div>
                  </div>
                </div>
              )}
            </div>

            <div className="px-5 py-3 border-t border-gray-200 flex justify-end gap-2">
              <button onClick={() => setModal(null)}
                className="px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-xs font-medium hover:bg-gray-50">
                Cancel
              </button>
              <button onClick={save} disabled={saving}
                className="px-4 py-1.5 bg-gray-900 text-white rounded text-xs font-medium hover:bg-gray-800 disabled:opacity-40">
                {saving ? 'Saving…' : modal === 'new' ? 'Create Employee' : 'Save Changes'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
