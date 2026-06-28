import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type Workflow = {
  id: string; company_id: string; workflow_name: string; module_type: string
  document_type: string; trigger_condition_type: string; threshold_value: number | null; is_active: boolean
  companies?: { registered_name: string }
  steps?: Step[]
}
type Step = {
  id: string; workflow_id: string; step_sequence: number; approver_type: string
  approver_user_id: string | null; action_required: string; escalation_hours: number | null
}

const MODULE_TYPES = [
  { value: 'sales', label: 'Sales' },
  { value: 'purchasing', label: 'Purchasing' },
  { value: 'payment', label: 'Payment' },
  { value: 'journal', label: 'Journal Entry' },
  { value: 'master_data', label: 'Master Data' },
  { value: 'asset', label: 'Fixed Asset' },
  { value: 'credit_memo', label: 'Credit Memo' },
]
const TRIGGER_CONDITIONS = [
  { value: 'always', label: 'Always (all documents)' },
  { value: 'amount_exceeds', label: 'Amount exceeds threshold' },
  { value: 'discount_pct_exceeds', label: 'Discount % exceeds threshold' },
  { value: 'credit_limit_exceeded', label: 'Credit limit exceeded' },
]
const APPROVER_TYPES = [
  { value: 'user', label: 'Specific User' },
  { value: 'role', label: 'Role (any user with role)' },
  { value: 'dept_head', label: 'Department Head' },
]
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function ApprovalWorkflowPage() {
  const [workflows, setWorkflows] = useState<Workflow[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [filterCompany, setFilterCompany] = useState('')
  const [filterModule, setFilterModule] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [showSteps, setShowSteps] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [selectedWorkflow, setSelectedWorkflow] = useState<Workflow | null>(null)
  const [steps, setSteps] = useState<Step[]>([])
  const [form, setForm] = useState({ company_id: '', workflow_name: '', module_type: 'sales', document_type: '', trigger_condition_type: 'always', threshold_value: '' })
  const [stepForm, setStepForm] = useState({ approver_type: 'user', approver_user_id: '', action_required: 'approve', escalation_hours: '' })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const fetchWorkflows = async () => {
    const { data } = await supabase.from('approval_workflows').select('*, companies(registered_name)').order('workflow_name')
    setWorkflows((data as Workflow[]) || [])
  }
  useEffect(() => {
    fetchWorkflows()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
  }, [])

  const set = (k: string, v: string) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }
  const setS = (k: string, v: string) => setStepForm(f => ({ ...f, [k]: v }))

  const openSteps = async (wf: Workflow) => {
    setSelectedWorkflow(wf)
    const { data } = await supabase.from('approval_workflow_steps').select('*').eq('workflow_id', wf.id).order('step_sequence')
    setSteps((data as Step[]) || [])
    setShowSteps(true)
  }

  const addStep = async () => {
    if (!selectedWorkflow) return
    const nextSeq = steps.length + 1
    const { error } = await supabase.from('approval_workflow_steps').insert([{
      company_id: selectedWorkflow.company_id,
      workflow_id: selectedWorkflow.id,
      step_sequence: nextSeq,
      approver_type: stepForm.approver_type,
      approver_user_id: stepForm.approver_user_id || null,
      action_required: stepForm.action_required,
      escalation_hours: stepForm.escalation_hours ? parseInt(stepForm.escalation_hours) : null,
    }])
    if (error) alert('Error: ' + error.message)
    else {
      setStepForm({ approver_type: 'user', approver_user_id: '', action_required: 'approve', escalation_hours: '' })
      openSteps(selectedWorkflow)
    }
  }

  const deleteStep = async (stepId: string) => {
    await supabase.from('approval_workflow_steps').delete().eq('id', stepId)
    if (selectedWorkflow) openSteps(selectedWorkflow)
  }

  const handleSave = async () => {
    setSaving(true)
    const payload = {
      company_id: form.company_id, workflow_name: form.workflow_name,
      module_type: form.module_type, document_type: form.document_type,
      trigger_condition_type: form.trigger_condition_type,
      threshold_value: form.threshold_value ? parseFloat(form.threshold_value) : null,
    }
    const { error } = editId
      ? await supabase.from('approval_workflows').update(payload).eq('id', editId)
      : await supabase.from('approval_workflows').insert([payload])
    if (error) alert('Error: ' + error.message)
    else { setSaved(true); fetchWorkflows() }
    setSaving(false)
  }

  const toggleActive = async (wf: Workflow) => {
    await supabase.from('approval_workflows').update({ is_active: !wf.is_active }).eq('id', wf.id)
    fetchWorkflows()
  }

  const needsThreshold = form.trigger_condition_type !== 'always' && form.trigger_condition_type !== 'credit_limit_exceeded'

  if (showSteps && selectedWorkflow) return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowSteps(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to Workflows</button>
          <h1 className="text-xl font-semibold text-gray-900">Approval Steps — {selectedWorkflow.workflow_name}</h1>
          <p className="text-sm text-gray-500">{selectedWorkflow.companies?.registered_name} · {MODULE_TYPES.find(m => m.value === selectedWorkflow.module_type)?.label} · {TRIGGER_CONDITIONS.find(t => t.value === selectedWorkflow.trigger_condition_type)?.label}</p>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Step</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Approver Type</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Action</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Escalation</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {steps.length === 0
              ? <tr><td colSpan={5} className="text-center py-8 text-gray-400 text-sm">No steps added yet. Add the first approver below.</td></tr>
              : steps.map((step, i) => (
                <tr key={step.id} className={`border-b border-gray-100 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-semibold text-gray-900">Step {step.step_sequence}</td>
                  <td className="px-4 py-3 text-gray-700">{APPROVER_TYPES.find(t => t.value === step.approver_type)?.label}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${step.action_required === 'approve' ? 'bg-green-50 text-green-700' : 'bg-blue-50 text-blue-700'}`}>{step.action_required === 'approve' ? 'Approve' : 'Review Only'}</span></td>
                  <td className="px-4 py-3 text-gray-500">{step.escalation_hours ? `${step.escalation_hours}h` : '—'}</td>
                  <td className="px-4 py-3"><button onClick={() => deleteStep(step.id)} className="text-xs text-red-600 hover:text-red-800 font-medium">Remove</button></td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>
      <div className={sec}><h2 className={hd}>Add Approval Step</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>Approver Type</label>
            <select value={stepForm.approver_type} onChange={e => setS('approver_type', e.target.value)} className={inp}>
              {APPROVER_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select></div>
          <div><label className={lbl}>Action Required</label>
            <select value={stepForm.action_required} onChange={e => setS('action_required', e.target.value)} className={inp}>
              <option value="approve">Approve</option>
              <option value="review">Review Only</option>
            </select></div>
          {stepForm.approver_type === 'user' && (
            <div><label className={lbl}>User ID (or email)</label>
              <input value={stepForm.approver_user_id} onChange={e => setS('approver_user_id', e.target.value)} className={inp} placeholder="User email or ID" /></div>
          )}
          <div><label className={lbl}>Escalation (hours, optional)</label>
            <input type="number" min="1" value={stepForm.escalation_hours} onChange={e => setS('escalation_hours', e.target.value)} className={inp} placeholder="e.g., 24" /></div>
        </div>
        <button onClick={addStep} className="bg-gray-900 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-gray-800 mt-2">
          + Add Step
        </button>
      </div>
    </div>
  )

  if (showForm) return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Workflow' : 'Create Approval Workflow'}</h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update Workflow' : 'Save Workflow'}
          </button>
        </div>
      </div>
      <div className={sec}><h2 className={hd}>Workflow Definition</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
            <select value={form.company_id} onChange={e => set('company_id', e.target.value)} className={inp}>
              <option value="">Select company...</option>
              {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
            </select></div>
          <div><label className={lbl}>Module Type <span className="text-red-500">*</span></label>
            <select value={form.module_type} onChange={e => set('module_type', e.target.value)} className={inp}>
              {MODULE_TYPES.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
            </select></div>
          <div className="col-span-2"><label className={lbl}>Workflow Name <span className="text-red-500">*</span></label>
            <input value={form.workflow_name} onChange={e => set('workflow_name', e.target.value)} className={inp} placeholder="e.g., Sales Invoice Approval — Amount > 50,000" /></div>
          <div><label className={lbl}>Document Type</label>
            <input value={form.document_type} onChange={e => set('document_type', e.target.value)} className={inp} placeholder="e.g., Sales Invoice (or leave blank for all)" /></div>
          <div><label className={lbl}>Trigger Condition <span className="text-red-500">*</span></label>
            <select value={form.trigger_condition_type} onChange={e => set('trigger_condition_type', e.target.value)} className={inp}>
              {TRIGGER_CONDITIONS.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select></div>
          {needsThreshold && (
            <div><label className={lbl}>Threshold Value <span className="text-red-500">*</span></label>
              <input type="number" min="0" step="0.01" value={form.threshold_value} onChange={e => set('threshold_value', e.target.value)} className={inp} placeholder="e.g., 50000.00" /></div>
          )}
        </div>
      </div>
    </div>
  )

  const filtered = workflows.filter(w => {
    const c = !filterCompany || w.company_id === filterCompany
    const m = !filterModule || w.module_type === filterModule
    return c && m
  })
  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Approval Workflows</h1>
        <p className="text-sm text-gray-500 mt-0.5">Configure multi-step approval routing for documents and transactions</p></div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        <select value={filterModule} onChange={e => setFilterModule(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Modules</option>
          {MODULE_TYPES.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
        </select>
        <div className="ml-auto">
          <button onClick={() => { setForm({ company_id: '', workflow_name: '', module_type: 'sales', document_type: '', trigger_condition_type: 'always', threshold_value: '' }); setEditId(null); setShowForm(true); setSaved(false) }}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create Workflow
          </button>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Workflow Name</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Module</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Trigger</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.length === 0
              ? <tr><td colSpan={6} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Approval Workflows</p><p className="text-sm mt-1">Create a workflow to enable document approval routing.</p></td></tr>
              : filtered.map((wf, i) => (
                <tr key={wf.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{wf.workflow_name}</td>
                  <td className="px-4 py-3"><span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-700">{MODULE_TYPES.find(m => m.value === wf.module_type)?.label}</span></td>
                  <td className="px-4 py-3 text-xs text-gray-600">{TRIGGER_CONDITIONS.find(t => t.value === wf.trigger_condition_type)?.label}{wf.threshold_value ? ` (${Number(wf.threshold_value).toLocaleString()})` : ''}</td>
                  <td className="px-4 py-3 text-gray-500">{wf.companies?.registered_name}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${wf.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{wf.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openSteps(wf)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">Steps</button>
                    <button onClick={() => { setForm({ company_id: wf.company_id, workflow_name: wf.workflow_name, module_type: wf.module_type, document_type: wf.document_type, trigger_condition_type: wf.trigger_condition_type, threshold_value: wf.threshold_value ? String(wf.threshold_value) : '' }); setEditId(wf.id); setShowForm(true); setSaved(false) }} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleActive(wf)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{wf.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
          </tbody>
        </table>
        {filtered.length > 0 && <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">Showing {filtered.length} workflows</div>}
      </div>
    </div>
  )
}
