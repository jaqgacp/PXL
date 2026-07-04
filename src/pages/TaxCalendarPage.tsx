import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type CalEvent = {
  id: string; company_id: string; compliance_form_id: string
  coverage_period_start: string; coverage_period_end: string
  statutory_deadline: string; efps_adjusted_deadline: string | null; effective_deadline: string
  status: 'pending' | 'filed' | 'late'; date_filed: string | null; efps_reference_no: string | null
  assigned_to_user_id: string | null
  ref_compliance_forms?: { form_code: string; form_name: string; compliance_type: string }
  companies?: { registered_name: string }
}
type Company = { id: string; registered_name: string }

const inp = 'border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'

const STATUS_COLOR: Record<string, string> = {
  filed: 'bg-green-100 text-green-800',
  late:  'bg-red-100 text-red-800',
  pending: 'bg-yellow-100 text-yellow-800',
}

const TYPE_COLOR: Record<string, string> = {
  vat: 'bg-blue-50 text-blue-700',
  ewt: 'bg-purple-50 text-purple-700',
  fwt: 'bg-red-50 text-red-700',
  income_tax: 'bg-orange-50 text-orange-700',
  alphalist: 'bg-indigo-50 text-indigo-700',
  information: 'bg-teal-50 text-teal-700',
  lgu: 'bg-gray-100 text-gray-700',
}

function rowClass(e: CalEvent): string {
  const now = new Date()
  const deadline = new Date(e.effective_deadline)
  const daysLeft = Math.ceil((deadline.getTime() - now.getTime()) / 86400000)
  if (e.status === 'filed') return 'bg-green-50'
  if (e.status === 'late' || (e.status === 'pending' && deadline < now)) return 'bg-red-50'
  if (e.status === 'pending' && daysLeft <= 7) return 'bg-yellow-50'
  return ''
}

export default function TaxCalendarPage() {
  const { companyId } = useAppCtx()
  const [events, setEvents] = useState<CalEvent[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [selectedCompany, setSelectedCompany] = useState('')
  const [filterStatus, setFilterStatus] = useState('')
  const [filterYear, setFilterYear] = useState(new Date().getFullYear().toString())
  const [editId, setEditId] = useState<string | null>(null)
  const [filedDate, setFiledDate] = useState('')
  const [efpsRef, setEfpsRef] = useState('')
  const [saving, setSaving] = useState(false)
  const [regenerating, setRegenerating] = useState(false)

  const cid = companyId || selectedCompany

  const fetchEvents = async (coid: string) => {
    if (!coid) return
    const { data } = await supabase.from('tax_calendar_events')
      .select('*, ref_compliance_forms(form_code,form_name,compliance_type), companies(registered_name)')
      .eq('company_id', coid)
      .gte('coverage_period_start', `${filterYear}-01-01`)
      .lte('coverage_period_start', `${filterYear}-12-31`)
      .order('effective_deadline')
    setEvents((data as CalEvent[]) || [])
  }

  useEffect(() => {
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
  }, [])
  useEffect(() => { if (cid) fetchEvents(cid) }, [cid, filterYear])

  const handleRegenerate = async () => {
    if (!cid) return
    setRegenerating(true)
    const { error } = await supabase.rpc('fn_generate_tax_calendar', { p_company_id: cid, p_fiscal_year: parseInt(filterYear) })
    if (error) alert('Error regenerating: ' + error.message)
    else await fetchEvents(cid)
    setRegenerating(false)
  }

  const openEdit = (e: CalEvent) => {
    setEditId(e.id)
    setFiledDate(e.date_filed || '')
    setEfpsRef(e.efps_reference_no || '')
  }

  const handleMarkFiled = async () => {
    if (!editId) return
    setSaving(true)
    const { error } = await supabase.rpc('fn_mark_tax_event_filed', {
      p_event_id: editId,
      p_date_filed: filedDate || new Date().toISOString().split('T')[0],
      p_efps_ref: efpsRef || undefined,
    })
    if (error) alert(error.message)
    else { setEditId(null); fetchEvents(cid) }
    setSaving(false)
  }

  const filtered = events.filter(e => !filterStatus || e.status === filterStatus)

  const fmt = (d: string) => new Date(d).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })
  const fmtPeriod = (s: string, e: string) => {
    const ms = new Date(s); const me = new Date(e)
    return ms.toLocaleDateString('en-PH', { month: 'short', year: 'numeric' }) + (ms.getMonth() !== me.getMonth() ? ' – ' + me.toLocaleDateString('en-PH', { month: 'short', year: 'numeric' }) : '')
  }

  const summary = {
    total: events.length,
    filed: events.filter(e => e.status === 'filed').length,
    pending: events.filter(e => e.status === 'pending').length,
    overdue: events.filter(e => e.status === 'late' || (e.status === 'pending' && new Date(e.effective_deadline) < new Date())).length,
  }

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Tax Calendar</h1>
        <p className="text-sm text-gray-500 mt-0.5">BIR filing deadlines auto-generated from your Compliance Profile</p>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3">
        {!companyId && (
          <select value={selectedCompany} onChange={e => setSelectedCompany(e.target.value)} className={inp}>
            <option value="">— select company —</option>
            {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
          </select>
        )}
        <select value={filterYear} onChange={e => setFilterYear(e.target.value)} className={inp}>
          {[2024,2025,2026,2027].map(y => <option key={y} value={String(y)}>{y}</option>)}
        </select>
        <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)} className={inp}>
          <option value="">All Status</option>
          <option value="pending">Pending</option>
          <option value="filed">Filed</option>
          <option value="late">Late</option>
        </select>
        <div className="flex-1" />
        <button onClick={handleRegenerate} disabled={!cid || regenerating}
          className="px-4 py-1.5 border border-gray-300 text-sm rounded-md hover:bg-gray-50 disabled:opacity-40">
          {regenerating ? 'Regenerating…' : 'Regenerate Calendar'}
        </button>
      </div>

      {/* Summary cards */}
      {cid && (
        <div className="grid grid-cols-4 gap-3">
          {[
            { label: 'Total', value: summary.total, color: 'text-gray-900' },
            { label: 'Filed', value: summary.filed, color: 'text-green-700' },
            { label: 'Pending', value: summary.pending, color: 'text-yellow-700' },
            { label: 'Overdue', value: summary.overdue, color: 'text-red-700' },
          ].map(s => (
            <div key={s.label} className="bg-white border border-gray-200 rounded-lg p-4 text-center">
              <div className={`text-2xl font-bold ${s.color}`}>{s.value}</div>
              <div className="text-xs text-gray-500 mt-1">{s.label}</div>
            </div>
          ))}
        </div>
      )}

      {/* Legend */}
      <div className="flex items-center gap-4 text-xs text-gray-500">
        <span className="flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-red-100 inline-block" /> Overdue</span>
        <span className="flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-yellow-100 inline-block" /> Due within 7 days</span>
        <span className="flex items-center gap-1.5"><span className="w-3 h-3 rounded bg-green-100 inline-block" /> Filed</span>
      </div>

      {/* Table */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>{['Form','Type','Coverage Period','Statutory Deadline','eFPS Deadline','Status','Date Filed','eFPS Ref',''].map(h =>
              <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide whitespace-nowrap">{h}</th>
            )}</tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {filtered.map(e => (
              <tr key={e.id} className={`hover:bg-opacity-80 ${rowClass(e)}`}>
                <td className="px-4 py-3">
                  <div className="font-mono font-medium text-gray-900">{e.ref_compliance_forms?.form_code}</div>
                  <div className="text-xs text-gray-500">{e.ref_compliance_forms?.form_name}</div>
                </td>
                <td className="px-4 py-3">
                  <span className={`text-xs font-medium px-2 py-0.5 rounded ${TYPE_COLOR[e.ref_compliance_forms?.compliance_type || ''] || 'bg-gray-100 text-gray-600'}`}>
                    {e.ref_compliance_forms?.compliance_type?.replace('_',' ').toUpperCase()}
                  </span>
                </td>
                <td className="px-4 py-3 text-xs text-gray-600 whitespace-nowrap">{fmtPeriod(e.coverage_period_start, e.coverage_period_end)}</td>
                <td className="px-4 py-3 text-xs whitespace-nowrap">{fmt(e.statutory_deadline)}</td>
                <td className="px-4 py-3 text-xs whitespace-nowrap">{e.efps_adjusted_deadline ? fmt(e.efps_adjusted_deadline) : <span className="text-gray-300">—</span>}</td>
                <td className="px-4 py-3">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${STATUS_COLOR[e.status]}`}>
                    {e.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-xs whitespace-nowrap">{e.date_filed ? fmt(e.date_filed) : <span className="text-gray-300">—</span>}</td>
                <td className="px-4 py-3 text-xs font-mono">{e.efps_reference_no || <span className="text-gray-300">—</span>}</td>
                <td className="px-4 py-3 text-right">
                  {e.status === 'pending' && (
                    <button onClick={() => openEdit(e)} className="text-xs text-indigo-600 hover:underline whitespace-nowrap">Mark Filed</button>
                  )}
                </td>
              </tr>
            ))}
            {!filtered.length && (
              <tr><td colSpan={9} className="px-4 py-10 text-center text-gray-400">
                {cid ? `No events for ${filterYear}. Click "Regenerate Calendar" to generate deadlines from the Compliance Profile.` : 'Select a company to view the tax calendar'}
              </td></tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Mark Filed Modal */}
      {editId && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-md p-6 space-y-4">
            <h2 className="text-base font-semibold text-gray-900">Mark as Filed</h2>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">Date Filed *</label>
              <input type="date" className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900" value={filedDate} onChange={e => setFiledDate(e.target.value)} />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-500 mb-1">eFPS / eBIR Reference No.</label>
              <input className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900" value={efpsRef} onChange={e => setEfpsRef(e.target.value)} placeholder="Optional" />
            </div>
            <div className="flex justify-end gap-3">
              <button onClick={() => setEditId(null)} className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button onClick={handleMarkFiled} disabled={saving || !filedDate} className="px-4 py-2 text-sm bg-green-700 text-white rounded-md hover:bg-green-800 disabled:opacity-50">{saving ? 'Saving…' : 'Confirm Filed'}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
