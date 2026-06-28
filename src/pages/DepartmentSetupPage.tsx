import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type Branch = { id: string; company_id: string; branch_name: string; branch_code: string }
type Department = {
  id: string; company_id: string; branch_id: string | null; department_code: string
  department_name: string; parent_department_id: string | null; department_head_name: string | null
  description: string | null; is_active: boolean
  companies?: { registered_name: string }; branches?: { branch_name: string }
  parent?: { department_name: string }
}
type CostCenter = {
  id: string; company_id: string; branch_id: string | null; department_id: string | null
  cost_center_code: string; cost_center_name: string; cost_center_type: string
  parent_cost_center_id: string | null; valid_from: string | null; valid_to: string | null
  description: string | null; is_active: boolean
  companies?: { registered_name: string }; departments?: { department_name: string }
}

const CC_TYPES = [
  { value: 'cost_center', label: 'Cost Center' },
  { value: 'revenue_center', label: 'Revenue Center' },
  { value: 'profit_center', label: 'Profit Center' },
  { value: 'investment_center', label: 'Investment Center' },
]
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function DepartmentSetupPage() {
  const [tab, setTab] = useState<'departments' | 'cost_centers'>('departments')
  const [departments, setDepartments] = useState<Department[]>([])
  const [costCenters, setCostCenters] = useState<CostCenter[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [search, setSearch] = useState('')
  const [filterCompany, setFilterCompany] = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'inactive'>('all')
  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [deptForm, setDeptForm] = useState({ company_id: '', branch_id: '', department_code: '', department_name: '', parent_department_id: '', department_head_name: '', description: '' })
  const [ccForm, setCcForm] = useState({ company_id: '', branch_id: '', department_id: '', cost_center_code: '', cost_center_name: '', cost_center_type: 'cost_center', parent_cost_center_id: '', valid_from: '', valid_to: '', description: '' })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const fetchAll = async () => {
    const [d, c] = await Promise.all([
      supabase.from('departments').select('*, companies(registered_name), branches(branch_name)').order('department_name'),
      supabase.from('cost_centers').select('*, companies(registered_name), departments(department_name)').order('cost_center_name'),
    ])
    setDepartments((d.data as Department[]) || [])
    setCostCenters((c.data as CostCenter[]) || [])
  }
  useEffect(() => {
    fetchAll()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
    supabase.from('branches').select('id,company_id,branch_name,branch_code').order('branch_name').then(({ data }) => setBranches(data || []))
  }, [])

  const setD = (k: string, v: string) => { setSaved(false); setDeptForm(f => ({ ...f, [k]: v })) }
  const setC = (k: string, v: string) => { setSaved(false); setCcForm(f => ({ ...f, [k]: v })) }

  const openCreate = () => {
    if (tab === 'departments') setDeptForm({ company_id: '', branch_id: '', department_code: '', department_name: '', parent_department_id: '', department_head_name: '', description: '' })
    else setCcForm({ company_id: '', branch_id: '', department_id: '', cost_center_code: '', cost_center_name: '', cost_center_type: 'cost_center', parent_cost_center_id: '', valid_from: '', valid_to: '', description: '' })
    setEditId(null); setShowForm(true); setSaved(false)
  }
  const openEditDept = (d: Department) => {
    setDeptForm({ company_id: d.company_id, branch_id: d.branch_id || '', department_code: d.department_code, department_name: d.department_name, parent_department_id: d.parent_department_id || '', department_head_name: d.department_head_name || '', description: d.description || '' })
    setEditId(d.id); setShowForm(true); setSaved(false)
  }
  const openEditCC = (c: CostCenter) => {
    setCcForm({ company_id: c.company_id, branch_id: c.branch_id || '', department_id: c.department_id || '', cost_center_code: c.cost_center_code, cost_center_name: c.cost_center_name, cost_center_type: c.cost_center_type, parent_cost_center_id: c.parent_cost_center_id || '', valid_from: c.valid_from || '', valid_to: c.valid_to || '', description: c.description || '' })
    setEditId(c.id); setShowForm(true); setSaved(false)
  }

  const handleSave = async () => {
    setSaving(true)
    let error: { message: string } | null = null
    if (tab === 'departments') {
      const payload = { ...deptForm, branch_id: deptForm.branch_id || null, parent_department_id: deptForm.parent_department_id || null }
      const res = editId ? await supabase.from('departments').update(payload).eq('id', editId) : await supabase.from('departments').insert([payload])
      error = res.error
    } else {
      const payload = { ...ccForm, branch_id: ccForm.branch_id || null, department_id: ccForm.department_id || null, parent_cost_center_id: ccForm.parent_cost_center_id || null, valid_from: ccForm.valid_from || null, valid_to: ccForm.valid_to || null }
      const res = editId ? await supabase.from('cost_centers').update(payload).eq('id', editId) : await supabase.from('cost_centers').insert([payload])
      error = res.error
    }
    if (error) alert('Error: ' + error.message)
    else { setSaved(true); fetchAll() }
    setSaving(false)
  }

  const toggleDept = async (d: Department) => { await supabase.from('departments').update({ is_active: !d.is_active }).eq('id', d.id); fetchAll() }
  const toggleCC = async (c: CostCenter) => { await supabase.from('cost_centers').update({ is_active: !c.is_active }).eq('id', c.id); fetchAll() }

  const formBranches = branches.filter(b => !deptForm.company_id || b.company_id === deptForm.company_id)
  const ccBranches = branches.filter(b => !ccForm.company_id || b.company_id === ccForm.company_id)
  const ccDepts = departments.filter(d => !ccForm.company_id || d.company_id === ccForm.company_id)

  if (showForm) return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit' : 'Create'} {tab === 'departments' ? 'Department' : 'Cost Center'}</h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update' : 'Save'}
          </button>
        </div>
      </div>
      {tab === 'departments' ? (
        <>
          <div className={sec}><h2 className={hd}>Section 1 — Department Identity</h2>
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
                <select value={deptForm.company_id} onChange={e => setD('company_id', e.target.value)} className={inp}>
                  <option value="">Select company...</option>
                  {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
                </select></div>
              <div><label className={lbl}>Branch (optional — leave blank for company-wide)</label>
                <select value={deptForm.branch_id} onChange={e => setD('branch_id', e.target.value)} className={inp}>
                  <option value="">All Branches (Company-wide)</option>
                  {formBranches.map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}
                </select></div>
              <div><label className={lbl}>Department Code <span className="text-red-500">*</span></label>
                <input value={deptForm.department_code} onChange={e => setD('department_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., ACCTG, HR, OPS" /></div>
              <div><label className={lbl}>Department Name <span className="text-red-500">*</span></label>
                <input value={deptForm.department_name} onChange={e => setD('department_name', e.target.value)} className={inp} placeholder="e.g., Accounting, Human Resources" /></div>
              <div><label className={lbl}>Parent Department</label>
                <select value={deptForm.parent_department_id} onChange={e => setD('parent_department_id', e.target.value)} className={inp}>
                  <option value="">None (Top-level)</option>
                  {departments.filter(d => d.company_id === deptForm.company_id && d.id !== editId).map(d => <option key={d.id} value={d.id}>{d.department_name}</option>)}
                </select></div>
            </div>
          </div>
          <div className={sec}><h2 className={hd}>Section 2 — Details</h2>
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>Department Head Name</label>
                <input value={deptForm.department_head_name} onChange={e => setD('department_head_name', e.target.value)} className={inp} /></div>
              <div className="col-span-2"><label className={lbl}>Description</label>
                <textarea value={deptForm.description} onChange={e => setD('description', e.target.value)} className={inp + ' h-20 resize-none'} /></div>
            </div>
          </div>
        </>
      ) : (
        <>
          <div className={sec}><h2 className={hd}>Section 1 — Cost Center Identity</h2>
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
                <select value={ccForm.company_id} onChange={e => setC('company_id', e.target.value)} className={inp}>
                  <option value="">Select company...</option>
                  {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
                </select></div>
              <div><label className={lbl}>Cost Center Type <span className="text-red-500">*</span></label>
                <select value={ccForm.cost_center_type} onChange={e => setC('cost_center_type', e.target.value)} className={inp}>
                  {CC_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
                </select></div>
              <div><label className={lbl}>Cost Center Code <span className="text-red-500">*</span></label>
                <input value={ccForm.cost_center_code} onChange={e => setC('cost_center_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., CC-001, PROJ-MNL" /></div>
              <div><label className={lbl}>Cost Center Name <span className="text-red-500">*</span></label>
                <input value={ccForm.cost_center_name} onChange={e => setC('cost_center_name', e.target.value)} className={inp} /></div>
              <div><label className={lbl}>Parent Cost Center</label>
                <select value={ccForm.parent_cost_center_id} onChange={e => setC('parent_cost_center_id', e.target.value)} className={inp}>
                  <option value="">None</option>
                  {costCenters.filter(c => c.company_id === ccForm.company_id && c.id !== editId).map(c => <option key={c.id} value={c.id}>{c.cost_center_name}</option>)}
                </select></div>
            </div>
          </div>
          <div className={sec}><h2 className={hd}>Section 2 — Organizational Links & Controls</h2>
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>Branch</label>
                <select value={ccForm.branch_id} onChange={e => setC('branch_id', e.target.value)} className={inp}>
                  <option value="">All Branches</option>
                  {ccBranches.map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}
                </select></div>
              <div><label className={lbl}>Department</label>
                <select value={ccForm.department_id} onChange={e => setC('department_id', e.target.value)} className={inp}>
                  <option value="">Not linked</option>
                  {ccDepts.map(d => <option key={d.id} value={d.id}>{d.department_name}</option>)}
                </select></div>
              <div><label className={lbl}>Valid From</label>
                <input type="date" value={ccForm.valid_from} onChange={e => setC('valid_from', e.target.value)} className={inp} /></div>
              <div><label className={lbl}>Valid To</label>
                <input type="date" value={ccForm.valid_to} onChange={e => setC('valid_to', e.target.value)} className={inp} /></div>
              <div className="col-span-2"><label className={lbl}>Description</label>
                <textarea value={ccForm.description} onChange={e => setC('description', e.target.value)} className={inp + ' h-20 resize-none'} /></div>
            </div>
          </div>
        </>
      )}
    </div>
  )

  const filteredDepts = departments.filter(d => {
    const m = !search || d.department_code.toLowerCase().includes(search.toLowerCase()) || d.department_name.toLowerCase().includes(search.toLowerCase())
    const c = !filterCompany || d.company_id === filterCompany
    const s = filterStatus === 'all' || (filterStatus === 'active' ? d.is_active : !d.is_active)
    return m && c && s
  })
  const filteredCC = costCenters.filter(c => {
    const m = !search || c.cost_center_code.toLowerCase().includes(search.toLowerCase()) || c.cost_center_name.toLowerCase().includes(search.toLowerCase())
    const co = !filterCompany || c.company_id === filterCompany
    const s = filterStatus === 'all' || (filterStatus === 'active' ? c.is_active : !c.is_active)
    return m && co && s
  })

  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Departments & Cost Centers</h1>
        <p className="text-sm text-gray-500 mt-0.5">Manage organizational structure and cost tracking segments</p></div>
      <div className="flex border-b border-gray-200">
        {(['departments','cost_centers'] as const).map(t => (
          <button key={t} onClick={() => { setTab(t); setSearch(''); setFilterCompany(''); setFilterStatus('all') }}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${tab === t ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>
            {t === 'departments' ? 'Departments' : 'Cost Centers'}
          </button>
        ))}
      </div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-56 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search..." />
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
          <button onClick={openCreate} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create New {tab === 'departments' ? 'Department' : 'Cost Center'}
          </button>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {tab === 'departments' ? (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Code</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Department Name</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Branch</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Head</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {filteredDepts.length === 0
                ? <tr><td colSpan={7} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Departments Found</p><p className="text-sm mt-1">Click "+ Create New Department" to get started.</p></td></tr>
                : filteredDepts.map((d, i) => (
                  <tr key={d.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                    <td className="px-4 py-3 font-mono font-medium text-gray-900">{d.department_code}</td>
                    <td className="px-4 py-3 text-gray-900">{d.department_name}</td>
                    <td className="px-4 py-3 text-gray-500">{d.companies?.registered_name || '—'}</td>
                    <td className="px-4 py-3 text-gray-500">{d.branches?.branch_name || 'All Branches'}</td>
                    <td className="px-4 py-3 text-gray-600">{d.department_head_name || '—'}</td>
                    <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${d.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{d.is_active ? 'Active' : 'Inactive'}</span></td>
                    <td className="px-4 py-3"><div className="flex items-center gap-2">
                      <button onClick={() => openEditDept(d)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                      <button onClick={() => toggleDept(d)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{d.is_active ? 'Deactivate' : 'Activate'}</button>
                    </div></td>
                  </tr>
                ))}
            </tbody>
          </table>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Code</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Name</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Department</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Valid To</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {filteredCC.length === 0
                ? <tr><td colSpan={8} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Cost Centers Found</p><p className="text-sm mt-1">Click "+ Create New Cost Center" to get started.</p></td></tr>
                : filteredCC.map((c, i) => (
                  <tr key={c.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                    <td className="px-4 py-3 font-mono font-medium text-gray-900">{c.cost_center_code}</td>
                    <td className="px-4 py-3 text-gray-900">{c.cost_center_name}</td>
                    <td className="px-4 py-3 text-gray-600">{CC_TYPES.find(t => t.value === c.cost_center_type)?.label || c.cost_center_type}</td>
                    <td className="px-4 py-3 text-gray-500">{c.companies?.registered_name || '—'}</td>
                    <td className="px-4 py-3 text-gray-500">{c.departments?.department_name || '—'}</td>
                    <td className="px-4 py-3 text-gray-500">{c.valid_to || '—'}</td>
                    <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${c.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{c.is_active ? 'Active' : 'Inactive'}</span></td>
                    <td className="px-4 py-3"><div className="flex items-center gap-2">
                      <button onClick={() => openEditCC(c)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                      <button onClick={() => toggleCC(c)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{c.is_active ? 'Deactivate' : 'Activate'}</button>
                    </div></td>
                  </tr>
                ))}
            </tbody>
          </table>
        )}
        {(tab === 'departments' ? filteredDepts : filteredCC).length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {(tab === 'departments' ? filteredDepts : filteredCC).length} records
          </div>
        )}
      </div>
    </div>
  )
}
