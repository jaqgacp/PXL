import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type Branch = { id: string; company_id: string; branch_code: string; branch_name: string }
type DocType = { id: string; category: string; document_code: string; document_name: string; is_bir_registered: boolean }
type NumberSeries = {
  id: string; company_id: string; branch_id: string; document_type_id: string
  prefix: string | null; has_dynamic_year: boolean; number_length: number
  starting_number: number; next_number: number; reset_frequency: string
  atp_series_start: number | null; atp_series_end: number | null; atp_alert_threshold: number | null
  allow_manual_override: boolean; is_active: boolean
  companies?: { registered_name: string }
  branches?: { branch_code: string; branch_name: string }
  ref_document_types?: { document_code: string; document_name: string; category: string; is_bir_registered: boolean }
}

const CATEGORIES = ['sales','purchasing','accounting','compliance']
const CATEGORY_LABELS: Record<string, string> = { sales: 'Sales', purchasing: 'Purchasing', accounting: 'Accounting', compliance: 'Compliance' }
const RESET_FREQS = [{ value: 'never', label: 'Never' }, { value: 'yearly', label: 'Yearly' }, { value: 'monthly', label: 'Monthly' }]
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

function sampleNumber(prefix: string, hasDynYear: boolean, numLength: number, startNum: number): string {
  const year = hasDynYear ? new Date().getFullYear().toString() : ''
  const num = String(startNum).padStart(numLength, '0')
  return [prefix, year, num].filter(Boolean).join('-')
}

export default function NumberSeriesPage() {
  const [tab, setTab] = useState<'sales' | 'purchasing' | 'accounting' | 'compliance'>('sales')
  const [series, setSeries] = useState<NumberSeries[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [docTypes, setDocTypes] = useState<DocType[]>([])
  const [filterCompany, setFilterCompany] = useState('')
  const [filterBranch, setFilterBranch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState({
    company_id: '', branch_id: '', document_type_id: '', prefix: '', has_dynamic_year: false,
    number_length: '6', starting_number: '1', reset_frequency: 'never',
    atp_series_start: '', atp_series_end: '', atp_alert_threshold: '', allow_manual_override: false,
  })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const fetchSeries = async () => {
    const { data } = await supabase.from('number_series')
      .select('*, companies(registered_name), branches(branch_code,branch_name), ref_document_types(document_code,document_name,category,is_bir_registered)')
      .order('created_at', { ascending: false })
    setSeries((data as NumberSeries[]) || [])
  }
  useEffect(() => {
    fetchSeries()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
    supabase.from('branches').select('id,company_id,branch_code,branch_name').order('branch_name').then(({ data }) => setBranches(data || []))
    supabase.from('ref_document_types').select('*').order('sort_order').then(({ data }) => setDocTypes(data || []))
  }, [])

  const set = (k: string, v: string | boolean) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const openEdit = (s: NumberSeries) => {
    setForm({
      company_id: s.company_id, branch_id: s.branch_id, document_type_id: s.document_type_id,
      prefix: s.prefix || '', has_dynamic_year: s.has_dynamic_year,
      number_length: String(s.number_length), starting_number: String(s.starting_number),
      reset_frequency: s.reset_frequency, atp_series_start: s.atp_series_start ? String(s.atp_series_start) : '',
      atp_series_end: s.atp_series_end ? String(s.atp_series_end) : '',
      atp_alert_threshold: s.atp_alert_threshold ? String(s.atp_alert_threshold) : '',
      allow_manual_override: s.allow_manual_override,
    })
    setEditId(s.id); setShowForm(true); setSaved(false)
  }

  const handleSave = async () => {
    setSaving(true)
    const startNum = parseInt(form.starting_number) || 1
    const payload = {
      company_id: form.company_id, branch_id: form.branch_id,
      document_type_id: form.document_type_id, prefix: form.prefix || null,
      has_dynamic_year: form.has_dynamic_year, number_length: parseInt(form.number_length) || 6,
      starting_number: startNum, next_number: startNum,
      reset_frequency: form.reset_frequency,
      atp_series_start: form.atp_series_start ? parseInt(form.atp_series_start) : null,
      atp_series_end: form.atp_series_end ? parseInt(form.atp_series_end) : null,
      atp_alert_threshold: form.atp_alert_threshold ? parseInt(form.atp_alert_threshold) : null,
      allow_manual_override: form.allow_manual_override,
    }
    const { error } = editId
      ? await supabase.from('number_series').update(payload).eq('id', editId)
      : await supabase.from('number_series').insert([payload])
    if (error) alert('Error: ' + error.message)
    else { setSaved(true); fetchSeries() }
    setSaving(false)
  }

  const toggleActive = async (s: NumberSeries) => {
    await supabase.from('number_series').update({ is_active: !s.is_active }).eq('id', s.id)
    fetchSeries()
  }

  const formBranches = branches.filter(b => !form.company_id || b.company_id === form.company_id)
  const filteredBranches = branches.filter(b => !filterCompany || b.company_id === filterCompany)
  const tabDocTypeIds = new Set(docTypes.filter(d => d.category === tab).map(d => d.id))
  const filtered = series.filter(s => {
    const inTab = tabDocTypeIds.has(s.document_type_id)
    const c = !filterCompany || s.company_id === filterCompany
    const b = !filterBranch || s.branch_id === filterBranch
    return inTab && c && b
  })

  if (showForm) {
    const docType = docTypes.find(d => d.id === form.document_type_id)
    const preview = form.document_type_id ? sampleNumber(form.prefix, form.has_dynamic_year, parseInt(form.number_length) || 6, parseInt(form.starting_number) || 1) : ''
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
            <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Number Series' : 'Create Number Series'}</h1>
          </div>
          <div className="flex gap-2">
            <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
            <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
              {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update Series' : 'Save Series'}
            </button>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 1 — Series Scope</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
              <select value={form.company_id} onChange={e => set('company_id', e.target.value)} className={inp}>
                <option value="">Select company...</option>
                {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select></div>
            <div><label className={lbl}>Branch <span className="text-red-500">*</span></label>
              <select value={form.branch_id} onChange={e => set('branch_id', e.target.value)} className={inp}>
                <option value="">Select branch...</option>
                {formBranches.map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}
              </select></div>
            <div className="col-span-2"><label className={lbl}>Document Type <span className="text-red-500">*</span></label>
              <select value={form.document_type_id} onChange={e => set('document_type_id', e.target.value)} className={inp}>
                <option value="">Select document type...</option>
                {docTypes.map(d => <option key={d.id} value={d.id}>[{d.category}] {d.document_code} — {d.document_name}{d.is_bir_registered ? ' (BIR Registered)' : ''}</option>)}
              </select></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 2 — Numbering Format</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Prefix (optional)</label>
              <input value={form.prefix} onChange={e => set('prefix', e.target.value.toUpperCase())} className={inp} placeholder="e.g., SI, OR, PO" /></div>
            <div><label className={lbl}>Number Length (digits)</label>
              <input type="number" min="1" max="10" value={form.number_length} onChange={e => set('number_length', e.target.value)} className={inp} /></div>
            <div><label className={lbl}>Starting Number</label>
              <input type="number" min="1" value={form.starting_number} onChange={e => set('starting_number', e.target.value)} className={inp} /></div>
            <div><label className={lbl}>Reset Frequency</label>
              <select value={form.reset_frequency} onChange={e => set('reset_frequency', e.target.value)} className={inp}>
                {RESET_FREQS.map(f => <option key={f.value} value={f.value}>{f.label}</option>)}
              </select></div>
            <div className="col-span-2 flex items-center gap-2">
              <input type="checkbox" id="has_dynamic_year" checked={form.has_dynamic_year} onChange={e => set('has_dynamic_year', e.target.checked)} className="rounded border-gray-300" />
              <label htmlFor="has_dynamic_year" className="text-sm text-gray-700">Include year in number (e.g., SI-2026-000001)</label>
            </div>
            <div className="col-span-2 flex items-center gap-2">
              <input type="checkbox" id="allow_manual_override" checked={form.allow_manual_override} onChange={e => set('allow_manual_override', e.target.checked)} className="rounded border-gray-300" />
              <label htmlFor="allow_manual_override" className="text-sm text-gray-700">Allow manual document number override</label>
            </div>
            {preview && (
              <div className="col-span-2 bg-gray-50 border border-gray-200 rounded-md px-4 py-3">
                <p className="text-xs text-gray-500 mb-1">Sample document number:</p>
                <p className="text-base font-mono font-semibold text-gray-900">{preview}</p>
              </div>
            )}
          </div>
        </div>
        {docType?.is_bir_registered && (
          <div className={sec}><h2 className={hd}>Section 3 — BIR ATP (Authority to Print)</h2>
            <div className="bg-amber-50 border border-amber-200 rounded-md px-3 py-2 mb-2">
              <p className="text-xs text-amber-800">This document type requires BIR Authority to Print (ATP). Enter the approved series range from your BIR ATP certificate.</p>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div><label className={lbl}>ATP Series Start</label>
                <input type="number" value={form.atp_series_start} onChange={e => set('atp_series_start', e.target.value)} className={inp} placeholder="e.g., 1" /></div>
              <div><label className={lbl}>ATP Series End</label>
                <input type="number" value={form.atp_series_end} onChange={e => set('atp_series_end', e.target.value)} className={inp} placeholder="e.g., 50000" /></div>
              <div><label className={lbl}>Alert Threshold</label>
                <input type="number" value={form.atp_alert_threshold} onChange={e => set('atp_alert_threshold', e.target.value)} className={inp} placeholder="e.g., 1000" /></div>
            </div>
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Number Series</h1>
        <p className="text-sm text-gray-500 mt-0.5">Configure auto-numbering format per document type, company, and branch</p></div>
      <div className="flex border-b border-gray-200">
        {CATEGORIES.map(cat => (
          <button key={cat} onClick={() => setTab(cat as typeof tab)}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${tab === cat ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>
            {CATEGORY_LABELS[cat]}
          </button>
        ))}
      </div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={filterCompany} onChange={e => { setFilterCompany(e.target.value); setFilterBranch('') }}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        <select value={filterBranch} onChange={e => setFilterBranch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Branches</option>
          {filteredBranches.map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}
        </select>
        <div className="ml-auto">
          <button onClick={() => { setForm({ company_id: '', branch_id: '', document_type_id: '', prefix: '', has_dynamic_year: false, number_length: '6', starting_number: '1', reset_frequency: 'never', atp_series_start: '', atp_series_end: '', atp_alert_threshold: '', allow_manual_override: false }); setEditId(null); setShowForm(true); setSaved(false) }}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create Number Series
          </button>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Document Type</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Branch</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Format</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Next #</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Reset</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.length === 0
              ? <tr><td colSpan={7} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Number Series in {CATEGORY_LABELS[tab]}</p><p className="text-sm mt-1">Create a series for each document type that needs auto-numbering.</p></td></tr>
              : filtered.map((s, i) => (
                <tr key={s.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3">
                    <p className="font-medium text-gray-900">{s.ref_document_types?.document_code} — {s.ref_document_types?.document_name}</p>
                    <p className="text-xs text-gray-400">{s.companies?.registered_name}</p>
                  </td>
                  <td className="px-4 py-3 text-gray-600">{s.branches?.branch_code} {s.branches?.branch_name}</td>
                  <td className="px-4 py-3 font-mono text-gray-700 text-xs">{sampleNumber(s.prefix || '', s.has_dynamic_year, s.number_length, s.next_number)}</td>
                  <td className="px-4 py-3 text-gray-900 font-mono">{s.next_number}</td>
                  <td className="px-4 py-3 text-gray-600 capitalize">{s.reset_frequency}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${s.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{s.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openEdit(s)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleActive(s)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{s.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
          </tbody>
        </table>
        {filtered.length > 0 && <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">Showing {filtered.length} series</div>}
      </div>
    </div>
  )
}
