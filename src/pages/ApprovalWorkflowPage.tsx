import { useCallback, useState, useEffect } from 'react'
import { ArrowLeft, Check, Plus, Trash2, X } from 'lucide-react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type Branch = { id: string; company_id: string; branch_code: string; branch_name: string }
type Currency = { currency_code: string; name: string }
type Workflow = {
  id: string; company_id: string; workflow_name: string; module_type: string
  document_type: string; trigger_condition_type: string; threshold_value: number | null; is_active: boolean
  action_type: string; branch_id: string | null; currency_code: string | null
  requester_role_code: string | null; priority: number; effective_from: string | null; effective_to: string | null
  enforce_requester_separation: boolean
  companies?: { registered_name: string }
  steps?: Step[]
}
type Step = {
  id: string; workflow_id: string; step_sequence: number; approver_type: string
  approver_user_id: string | null; approver_role_code: string | null
  action_required: string; escalation_hours: number | null
}
type InboxItem = {
  request_id: string; company_id: string; branch_id: string | null; workflow_name: string
  module_type: string; action_type: string; source_document_type: string
  source_document_id: string; source_document_no: string; source_document_amount: number | null
  currency_code: string | null; status: string; current_step_sequence: number
  requester_id: string; record_version: string; submitted_at: string
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
const ACTION_TYPES = ['create', 'edit', 'delete', 'activate', 'deactivate', 'import', 'approve']
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function ApprovalWorkflowPage() {
  const [workflows, setWorkflows] = useState<Workflow[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [manageableCompanies, setManageableCompanies] = useState<Set<string>>(new Set())
  const [view, setView] = useState<'rules' | 'inbox'>('rules')
  const [inbox, setInbox] = useState<InboxItem[]>([])
  const [filterCompany, setFilterCompany] = useState('')
  const [filterModule, setFilterModule] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [showSteps, setShowSteps] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [selectedWorkflow, setSelectedWorkflow] = useState<Workflow | null>(null)
  const [steps, setSteps] = useState<Step[]>([])
  const emptyForm = { company_id: '', workflow_name: '', module_type: 'master_data', document_type: '', action_type: 'edit', branch_id: '', currency_code: '', requester_role_code: '', priority: '0', effective_from: '', effective_to: '', enforce_requester_separation: true, trigger_condition_type: 'always', threshold_value: '' }
  const [form, setForm] = useState(emptyForm)
  const [stepForm, setStepForm] = useState({ approver_type: 'role', approver_user_id: '', approver_role_code: '', action_required: 'approve', escalation_hours: '' })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [message, setMessage] = useState<{ tone: 'error' | 'success'; text: string } | null>(null)

  const fetchWorkflows = async () => {
    const { data, error } = await supabase.from('approval_workflows').select('*, companies(registered_name)').order('workflow_name')
    if (error) setMessage({ tone: 'error', text: error.message })
    setWorkflows((data as Workflow[]) || [])
  }
  const fetchInbox = useCallback(async () => {
    const { data, error } = await supabase.rpc('fn_approval_inbox', { p_company_id: filterCompany || null })
    if (error) setMessage({ tone: 'error', text: error.message })
    else setInbox((data as InboxItem[]) || [])
  }, [filterCompany])
  useEffect(() => {
    fetchWorkflows()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
    supabase.from('branches').select('id,company_id,branch_code,branch_name').order('branch_code').then(({ data }) => setBranches(data || []))
    supabase.from('currencies').select('currency_code,name').eq('is_active', true).order('currency_code').then(({ data }) => setCurrencies(data || []))
    supabase.auth.getUser().then(({ data }) => {
      if (!data.user) return
      supabase.from('user_company_memberships').select('company_id,role').eq('user_id', data.user.id).then(({ data: memberships }) => {
        setManageableCompanies(new Set((memberships || []).filter(m => m.role === 'owner' || m.role === 'admin').map(m => m.company_id)))
      })
    })
  }, [])

  useEffect(() => {
    if (view === 'inbox') fetchInbox()
  }, [view, fetchInbox])

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
    setMessage(null)
    const nextSeq = steps.length + 1
    const { error } = await supabase.from('approval_workflow_steps').insert([{
      company_id: selectedWorkflow.company_id,
      workflow_id: selectedWorkflow.id,
      step_sequence: nextSeq,
      approver_type: stepForm.approver_type,
      approver_user_id: stepForm.approver_user_id || null,
      approver_role_code: stepForm.approver_type === 'role' ? stepForm.approver_role_code || null : null,
      action_required: stepForm.action_required,
      escalation_hours: stepForm.escalation_hours ? parseInt(stepForm.escalation_hours) : null,
    }])
    if (error) setMessage({ tone: 'error', text: error.message })
    else {
      setStepForm({ approver_type: 'role', approver_user_id: '', approver_role_code: '', action_required: 'approve', escalation_hours: '' })
      setMessage({ tone: 'success', text: 'Approval step added.' })
      openSteps(selectedWorkflow)
    }
  }

  const deleteStep = async (stepId: string) => {
    const { error } = await supabase.from('approval_workflow_steps').delete().eq('id', stepId)
    if (error) setMessage({ tone: 'error', text: error.message })
    else if (selectedWorkflow) openSteps(selectedWorkflow)
  }

  const handleSave = async () => {
    setSaving(true)
    setMessage(null)
    const payload = {
      company_id: form.company_id, workflow_name: form.workflow_name,
      module_type: form.module_type, document_type: form.document_type,
      action_type: form.action_type, branch_id: form.branch_id || null,
      currency_code: form.currency_code || null,
      requester_role_code: form.requester_role_code || null,
      priority: Number(form.priority) || 0,
      effective_from: form.effective_from || null,
      effective_to: form.effective_to || null,
      enforce_requester_separation: form.enforce_requester_separation,
      trigger_condition_type: form.trigger_condition_type,
      threshold_value: form.threshold_value ? parseFloat(form.threshold_value) : null,
    }
    const { error } = editId
      ? await supabase.from('approval_workflows').update(payload).eq('id', editId)
      : await supabase.from('approval_workflows').insert([payload])
    if (error) setMessage({ tone: 'error', text: error.message })
    else { setSaved(true); setMessage({ tone: 'success', text: 'Approval rule saved.' }); fetchWorkflows() }
    setSaving(false)
  }

  const toggleActive = async (wf: Workflow) => {
    const { error } = await supabase.from('approval_workflows').update({ is_active: !wf.is_active }).eq('id', wf.id)
    if (error) setMessage({ tone: 'error', text: error.message })
    else fetchWorkflows()
  }

  const decideRequest = async (item: InboxItem, decision: 'approve' | 'reject') => {
    setMessage(null)
    const reason = decision === 'reject' ? window.prompt('Rejection reason') : null
    if (decision === 'reject' && !reason?.trim()) return
    const result = decision === 'approve'
      ? await supabase.rpc('fn_approve_approval_request', { p_request_id: item.request_id, p_current_record_version: item.record_version, p_remarks: null })
      : await supabase.rpc('fn_reject_approval_request', { p_request_id: item.request_id, p_current_record_version: item.record_version, p_reason: reason! })
    if (result.error) setMessage({ tone: 'error', text: result.error.message })
    else {
      setMessage({ tone: 'success', text: decision === 'approve' ? 'Approval recorded.' : 'Request rejected.' })
      fetchInbox()
    }
  }

  const needsThreshold = form.trigger_condition_type !== 'always' && form.trigger_condition_type !== 'credit_limit_exceeded'
  const canManageSelected = !!selectedWorkflow && manageableCompanies.has(selectedWorkflow.company_id)

  if (showSteps && selectedWorkflow) return (
    <div className="max-w-4xl mx-auto space-y-5">
      {message && <div className={`border px-4 py-3 text-sm ${message.tone === 'error' ? 'border-red-200 bg-red-50 text-red-700' : 'border-green-200 bg-green-50 text-green-700'}`}>{message.text}</div>}
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowSteps(false)} className="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-900 mb-1"><ArrowLeft size={14} /> Back to Workflows</button>
          <h1 className="text-xl font-semibold text-gray-900">Approval Steps - {selectedWorkflow.workflow_name}</h1>
          <p className="text-sm text-gray-500">{selectedWorkflow.companies?.registered_name} / {MODULE_TYPES.find(m => m.value === selectedWorkflow.module_type)?.label} / {TRIGGER_CONDITIONS.find(t => t.value === selectedWorkflow.trigger_condition_type)?.label}</p>
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
                  <td className="px-4 py-3 text-gray-700">{APPROVER_TYPES.find(t => t.value === step.approver_type)?.label}{step.approver_role_code ? `: ${step.approver_role_code}` : ''}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${step.action_required === 'approve' ? 'bg-green-50 text-green-700' : 'bg-blue-50 text-blue-700'}`}>{step.action_required === 'approve' ? 'Approve' : 'Review Only'}</span></td>
                  <td className="px-4 py-3 text-gray-500">{step.escalation_hours ? `${step.escalation_hours}h` : '-'}</td>
                  <td className="px-4 py-3">{canManageSelected && <button onClick={() => deleteStep(step.id)} title="Remove step" className="text-red-600 hover:text-red-800"><Trash2 size={16} /></button>}</td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>
      {canManageSelected && <div className={sec}><h2 className={hd}>Add Approval Step</h2>
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
            <div><label className={lbl}>User ID</label>
              <input value={stepForm.approver_user_id} onChange={e => setS('approver_user_id', e.target.value)} className={inp} placeholder="User UUID" /></div>
          )}
          {stepForm.approver_type === 'role' && (
            <div><label className={lbl}>Role Code</label>
              <input value={stepForm.approver_role_code} onChange={e => setS('approver_role_code', e.target.value)} className={inp} placeholder="e.g., admin" /></div>
          )}
          <div><label className={lbl}>Escalation (hours, optional)</label>
            <input type="number" min="1" value={stepForm.escalation_hours} onChange={e => setS('escalation_hours', e.target.value)} className={inp} placeholder="e.g., 24" /></div>
        </div>
        <button onClick={addStep} className="inline-flex items-center gap-2 bg-gray-900 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-gray-800 mt-2">
          <Plus size={16} /> Add Step
        </button>
      </div>}
    </div>
  )

  if (showForm) return (
    <div className="max-w-4xl mx-auto space-y-5">
      {message && <div className={`border px-4 py-3 text-sm ${message.tone === 'error' ? 'border-red-200 bg-red-50 text-red-700' : 'border-green-200 bg-green-50 text-green-700'}`}>{message.text}</div>}
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowForm(false)} className="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-900 mb-1"><ArrowLeft size={14} /> Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Workflow' : 'Create Approval Workflow'}</h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? 'Saved' : editId ? 'Update Workflow' : 'Save Workflow'}
          </button>
        </div>
      </div>
      <div className={sec}><h2 className={hd}>Workflow Definition</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
            <select value={form.company_id} onChange={e => set('company_id', e.target.value)} className={inp}>
              <option value="">Select company...</option>
              {companies.filter(c => manageableCompanies.has(c.id)).map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
            </select></div>
          <div><label className={lbl}>Module Type <span className="text-red-500">*</span></label>
            <select value={form.module_type} onChange={e => set('module_type', e.target.value)} className={inp}>
              {MODULE_TYPES.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
            </select></div>
          <div><label className={lbl}>Action <span className="text-red-500">*</span></label>
            <select value={form.action_type} onChange={e => set('action_type', e.target.value)} className={inp}>
              {ACTION_TYPES.map(action => <option key={action} value={action}>{action.replace('_', ' ')}</option>)}
            </select></div>
          <div><label className={lbl}>Branch</label>
            <select value={form.branch_id} onChange={e => set('branch_id', e.target.value)} className={inp}>
              <option value="">All branches</option>
              {branches.filter(b => b.company_id === form.company_id).map(b => <option key={b.id} value={b.id}>{b.branch_code} - {b.branch_name}</option>)}
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
          <div><label className={lbl}>Currency Context</label>
            <select value={form.currency_code} onChange={e => set('currency_code', e.target.value)} className={inp}>
              <option value="">Any currency</option>
              {currencies.map(c => <option key={c.currency_code} value={c.currency_code}>{c.currency_code} - {c.name}</option>)}
            </select></div>
          <div><label className={lbl}>Requester Role</label>
            <input value={form.requester_role_code} onChange={e => set('requester_role_code', e.target.value)} className={inp} placeholder="Any role" /></div>
          <div><label className={lbl}>Effective From</label>
            <input type="date" value={form.effective_from} onChange={e => set('effective_from', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Effective To</label>
            <input type="date" value={form.effective_to} onChange={e => set('effective_to', e.target.value)} className={inp} /></div>
          <div><label className={lbl}>Priority</label>
            <input type="number" value={form.priority} onChange={e => set('priority', e.target.value)} className={inp} /></div>
          <label className="flex items-center gap-2 text-sm text-gray-700 self-end pb-2">
            <input type="checkbox" checked={form.enforce_requester_separation} onChange={e => setForm(f => ({ ...f, enforce_requester_separation: e.target.checked }))} />
            Require requester and approver separation
          </label>
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
        <p className="text-sm text-gray-500 mt-0.5">Configure and action server-routed approvals for supported records</p></div>
      {message && <div className={`border px-4 py-3 text-sm ${message.tone === 'error' ? 'border-red-200 bg-red-50 text-red-700' : 'border-green-200 bg-green-50 text-green-700'}`}>{message.text}</div>}
      <div className="border-b border-gray-200 flex gap-5">
        <button onClick={() => setView('rules')} className={`pb-2 text-sm font-medium border-b-2 ${view === 'rules' ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500'}`}>Rules</button>
        <button onClick={() => setView('inbox')} className={`pb-2 text-sm font-medium border-b-2 ${view === 'inbox' ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500'}`}>Inbox</button>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        {view === 'rules' && <select value={filterModule} onChange={e => setFilterModule(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Modules</option>
          {MODULE_TYPES.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
        </select>}
        <div className="ml-auto">
          {view === 'rules' && manageableCompanies.size > 0 && <button onClick={() => { setForm(emptyForm); setEditId(null); setShowForm(true); setSaved(false); setMessage(null) }}
            className="inline-flex items-center gap-2 bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            <Plus size={16} /> Create Workflow
          </button>
          }
        </div>
      </div>
      {view === 'rules' ? <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
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
                  <td className="px-4 py-3 text-xs text-gray-600">{wf.action_type} / {TRIGGER_CONDITIONS.find(t => t.value === wf.trigger_condition_type)?.label}{wf.threshold_value ? ` (${Number(wf.threshold_value).toLocaleString()})` : ''}</td>
                  <td className="px-4 py-3 text-gray-500">{wf.companies?.registered_name}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${wf.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{wf.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openSteps(wf)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">Steps</button>
                    {manageableCompanies.has(wf.company_id) && <button onClick={() => { setForm({ company_id: wf.company_id, workflow_name: wf.workflow_name, module_type: wf.module_type, document_type: wf.document_type, action_type: wf.action_type, branch_id: wf.branch_id || '', currency_code: wf.currency_code || '', requester_role_code: wf.requester_role_code || '', priority: String(wf.priority), effective_from: wf.effective_from?.slice(0, 10) || '', effective_to: wf.effective_to?.slice(0, 10) || '', enforce_requester_separation: wf.enforce_requester_separation, trigger_condition_type: wf.trigger_condition_type, threshold_value: wf.threshold_value ? String(wf.threshold_value) : '' }); setEditId(wf.id); setShowForm(true); setSaved(false); setMessage(null) }} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>}
                    {manageableCompanies.has(wf.company_id) && <button onClick={() => toggleActive(wf)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{wf.is_active ? 'Deactivate' : 'Activate'}</button>}
                  </div></td>
                </tr>
              ))}
          </tbody>
        </table>
        {filtered.length > 0 && <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">Showing {filtered.length} workflows</div>}
      </div> : <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Record</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Workflow</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Step</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Submitted</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {inbox.length === 0 ? <tr><td colSpan={5} className="text-center py-16 text-gray-400">No pending approvals</td></tr> : inbox.map(item => (
              <tr key={item.request_id} className="border-b border-gray-100">
                <td className="px-4 py-3"><div className="font-medium text-gray-900">{item.source_document_no}</div><div className="text-xs text-gray-500">{item.source_document_type} / {item.action_type}</div></td>
                <td className="px-4 py-3 text-gray-700">{item.workflow_name}</td>
                <td className="px-4 py-3 text-gray-700">{item.current_step_sequence}</td>
                <td className="px-4 py-3 text-gray-500">{new Date(item.submitted_at).toLocaleString()}</td>
                <td className="px-4 py-3"><div className="flex items-center gap-2">
                  <button onClick={() => decideRequest(item, 'approve')} title="Approve" className="text-green-700 hover:text-green-900"><Check size={17} /></button>
                  <button onClick={() => decideRequest(item, 'reject')} title="Reject" className="text-red-600 hover:text-red-800"><X size={17} /></button>
                </div></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>}
    </div>
  )
}
