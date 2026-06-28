import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string; accounting_period: string; fiscal_start_month: number | null }
type FiscalYear = {
  id: string; company_id: string; year_name: string; start_date: string; end_date: string
  is_calendar: boolean; status: string
  companies?: { registered_name: string }
}
type FiscalPeriod = {
  id: string; period_number: number; period_name: string; start_date: string; end_date: string; is_locked: boolean
}

const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

function generatePeriods(startDate: string, endDate: string): Array<{ period_number: number; period_name: string; start_date: string; end_date: string }> {
  const periods = []
  const start = new Date(startDate + 'T00:00:00')
  const end = new Date(endDate + 'T00:00:00')
  let current = new Date(start)
  let periodNum = 1
  while (current <= end && periodNum <= 12) {
    const pStart = new Date(current)
    const pEnd = new Date(current.getFullYear(), current.getMonth() + 1, 0)
    const actualEnd = pEnd > end ? end : pEnd
    periods.push({
      period_number: periodNum,
      period_name: `${MONTHS[current.getMonth()]} ${current.getFullYear()}`,
      start_date: pStart.toISOString().slice(0, 10),
      end_date: actualEnd.toISOString().slice(0, 10),
    })
    current = new Date(current.getFullYear(), current.getMonth() + 1, 1)
    periodNum++
  }
  return periods
}

export default function FiscalYearsPage() {
  const [fiscalYears, setFiscalYears] = useState<FiscalYear[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [periods, setPeriods] = useState<FiscalPeriod[]>([])
  const [filterCompany, setFilterCompany] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [showPeriods, setShowPeriods] = useState(false)
  const [selectedYear, setSelectedYear] = useState<FiscalYear | null>(null)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState({ company_id: '', year_name: '', start_date: '', end_date: '', is_calendar: false })
  const [generatedPeriods, setGeneratedPeriods] = useState<ReturnType<typeof generatePeriods>>([])
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const fetchYears = async () => {
    const { data } = await supabase.from('fiscal_years').select('*, companies(registered_name)').order('start_date', { ascending: false })
    setFiscalYears((data as FiscalYear[]) || [])
  }
  useEffect(() => {
    fetchYears()
    supabase.from('companies').select('id, registered_name, accounting_period, fiscal_start_month').order('registered_name')
      .then(({ data }) => setCompanies(data || []))
  }, [])

  const set = (k: string, v: string | boolean) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const autoFillDates = (companyId: string) => {
    const co = companies.find(c => c.id === companyId)
    if (!co) return
    const now = new Date()
    let startMonth = 0
    if (co.accounting_period === 'fiscal' && co.fiscal_start_month) {
      startMonth = co.fiscal_start_month - 1
    }
    const startYear = startMonth <= now.getMonth() ? now.getFullYear() : now.getFullYear() - 1
    const start = new Date(startYear, startMonth, 1)
    const end = new Date(startYear + 1, startMonth, 0)
    const sd = start.toISOString().slice(0, 10)
    const ed = end.toISOString().slice(0, 10)
    const isCalendar = co.accounting_period === 'calendar'
    const yearName = isCalendar ? `FY ${startYear}` : `FY ${startYear}/${String(startYear + 1).slice(2)}`
    setForm(f => ({ ...f, company_id: companyId, year_name: yearName, start_date: sd, end_date: ed, is_calendar: isCalendar }))
    setGeneratedPeriods(generatePeriods(sd, ed))
  }

  const recalcPeriods = (sd: string, ed: string) => {
    if (sd && ed) setGeneratedPeriods(generatePeriods(sd, ed))
  }

  const handleSave = async () => {
    setSaving(true)
    const payload = { company_id: form.company_id, year_name: form.year_name, start_date: form.start_date, end_date: form.end_date, is_calendar: form.is_calendar }
    const { data: yearData, error } = editId
      ? await supabase.from('fiscal_years').update(payload).eq('id', editId).select().single()
      : await supabase.from('fiscal_years').insert([{ ...payload, status: 'open' }]).select().single()
    if (error) { alert('Error: ' + error.message); setSaving(false); return }
    if (!editId && yearData && generatedPeriods.length > 0) {
      await supabase.from('fiscal_periods').insert(generatedPeriods.map(p => ({ ...p, company_id: form.company_id, fiscal_year_id: yearData.id })))
    }
    setSaved(true); fetchYears(); setSaving(false)
  }

  const openPeriods = async (fy: FiscalYear) => {
    setSelectedYear(fy)
    const { data } = await supabase.from('fiscal_periods').select('*').eq('fiscal_year_id', fy.id).order('period_number')
    setPeriods((data as FiscalPeriod[]) || [])
    setShowPeriods(true)
  }

  const togglePeriodLock = async (p: FiscalPeriod) => {
    await supabase.from('fiscal_periods').update({ is_locked: !p.is_locked }).eq('id', p.id)
    openPeriods(selectedYear!)
  }

  const closeYear = async (fy: FiscalYear) => {
    if (!confirm(`Close ${fy.year_name}? This cannot be undone.`)) return
    await supabase.from('fiscal_years').update({ status: 'closed' }).eq('id', fy.id)
    fetchYears()
  }

  if (showPeriods && selectedYear) return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowPeriods(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to Fiscal Years</button>
          <h1 className="text-xl font-semibold text-gray-900">Fiscal Periods — {selectedYear.year_name}</h1>
          <p className="text-sm text-gray-500">{selectedYear.companies?.registered_name}</p>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Period</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Name</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Start Date</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">End Date</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {periods.length === 0
              ? <tr><td colSpan={6} className="text-center py-12 text-gray-400">No periods found</td></tr>
              : periods.map((p, i) => (
                <tr key={p.id} className={`border-b border-gray-100 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">Period {p.period_number}</td>
                  <td className="px-4 py-3 text-gray-700">{p.period_name}</td>
                  <td className="px-4 py-3 text-gray-600">{p.start_date}</td>
                  <td className="px-4 py-3 text-gray-600">{p.end_date}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${p.is_locked ? 'bg-orange-50 text-orange-700' : 'bg-green-50 text-green-700'}`}>
                      {p.is_locked ? 'Locked' : 'Open'}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <button onClick={() => togglePeriodLock(p)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">
                      {p.is_locked ? 'Unlock' : 'Lock'}
                    </button>
                  </td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>
    </div>
  )

  if (showForm) {
    const previewPeriods = form.start_date && form.end_date ? generatePeriods(form.start_date, form.end_date) : []
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
            <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Fiscal Year' : 'Create Fiscal Year'}</h1>
          </div>
          <div className="flex gap-2">
            <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
            <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
              {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update' : 'Save & Generate Periods'}
            </button>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Fiscal Year Settings</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
              <select value={form.company_id} onChange={e => autoFillDates(e.target.value)} className={inp}>
                <option value="">Select company...</option>
                {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select></div>
            <div><label className={lbl}>Year Name <span className="text-red-500">*</span></label>
              <input value={form.year_name} onChange={e => set('year_name', e.target.value)} className={inp} placeholder="e.g., FY 2026, FY 2025/26" /></div>
            <div><label className={lbl}>Start Date <span className="text-red-500">*</span></label>
              <input type="date" value={form.start_date} onChange={e => { set('start_date', e.target.value); recalcPeriods(e.target.value, form.end_date) }} className={inp} /></div>
            <div><label className={lbl}>End Date <span className="text-red-500">*</span></label>
              <input type="date" value={form.end_date} onChange={e => { set('end_date', e.target.value); recalcPeriods(form.start_date, e.target.value) }} className={inp} /></div>
            <div className="col-span-2 flex items-center gap-2 pt-1">
              <input type="checkbox" id="is_calendar" checked={form.is_calendar} onChange={e => set('is_calendar', e.target.checked)} className="rounded border-gray-300" />
              <label htmlFor="is_calendar" className="text-sm text-gray-700">Calendar year (Jan – Dec)</label>
            </div>
          </div>
        </div>
        {previewPeriods.length > 0 && !editId && (
          <div className={sec}><h2 className={hd}>Generated Periods Preview</h2>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead><tr className="bg-gray-50 border-b border-gray-100">
                  <th className="text-left px-3 py-2 text-xs text-gray-500">#</th>
                  <th className="text-left px-3 py-2 text-xs text-gray-500">Period Name</th>
                  <th className="text-left px-3 py-2 text-xs text-gray-500">Start</th>
                  <th className="text-left px-3 py-2 text-xs text-gray-500">End</th>
                </tr></thead>
                <tbody>
                  {previewPeriods.map(p => (
                    <tr key={p.period_number} className="border-b border-gray-50">
                      <td className="px-3 py-1.5 text-gray-500">{p.period_number}</td>
                      <td className="px-3 py-1.5 text-gray-700">{p.period_name}</td>
                      <td className="px-3 py-1.5 text-gray-500">{p.start_date}</td>
                      <td className="px-3 py-1.5 text-gray-500">{p.end_date}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    )
  }

  const filtered = fiscalYears.filter(fy => !filterCompany || fy.company_id === filterCompany)
  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Fiscal Years</h1>
        <p className="text-sm text-gray-500 mt-0.5">Define accounting periods and fiscal calendars per company</p></div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        <div className="ml-auto">
          <button onClick={() => { setForm({ company_id: '', year_name: '', start_date: '', end_date: '', is_calendar: false }); setEditId(null); setGeneratedPeriods([]); setShowForm(true); setSaved(false) }}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create Fiscal Year
          </button>
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead><tr className="bg-gray-50 border-b border-gray-200">
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Year Name</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Start Date</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">End Date</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
            <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.length === 0
              ? <tr><td colSpan={7} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Fiscal Years Found</p><p className="text-sm mt-1">Create the first fiscal year to get started.</p></td></tr>
              : filtered.map((fy, i) => (
                <tr key={fy.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fy.year_name}</td>
                  <td className="px-4 py-3 text-gray-500">{fy.companies?.registered_name || '—'}</td>
                  <td className="px-4 py-3 text-gray-600">{fy.start_date}</td>
                  <td className="px-4 py-3 text-gray-600">{fy.end_date}</td>
                  <td className="px-4 py-3 text-gray-500">{fy.is_calendar ? 'Calendar' : 'Fiscal'}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${fy.status === 'open' ? 'bg-blue-50 text-blue-700' : 'bg-gray-100 text-gray-500'}`}>{fy.status === 'open' ? 'Open' : 'Closed'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openPeriods(fy)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">Periods</button>
                    {fy.status === 'open' && <>
                      <button onClick={() => { setForm({ company_id: fy.company_id, year_name: fy.year_name, start_date: fy.start_date, end_date: fy.end_date, is_calendar: fy.is_calendar }); setEditId(fy.id); setShowForm(true); setSaved(false) }} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                      <button onClick={() => closeYear(fy)} className="text-xs text-gray-500 hover:text-red-700 font-medium">Close Year</button>
                    </>}
                  </div></td>
                </tr>
              ))}
          </tbody>
        </table>
        {filtered.length > 0 && <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">Showing {filtered.length} fiscal years</div>}
      </div>
    </div>
  )
}
