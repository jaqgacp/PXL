import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type RefForm = {
  id: string; form_code: string; form_name: string; compliance_type: string
  statutory_deadline_rule: string; efps_eligible: boolean; is_active: boolean
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

const FREQ_MAP: Record<string, string> = {
  '2550M': 'Monthly', '0619-E': 'Monthly', '0619-F': 'Monthly',
  '2550Q': 'Quarterly', '1601EQ': 'Quarterly', '1601FQ': 'Quarterly', '2551Q': 'Quarterly',
  'QAP': 'Quarterly', 'SLSP': 'Quarterly', 'RELIEF': 'Quarterly', 'SAWT': 'Quarterly',
  '1702Q': 'Quarterly', '1604-E': 'Annual', '1702': 'Annual', 'MAYOR_PERMIT': 'Annual',
}

export default function BIRFormConfigPage() {
  const [forms, setForms] = useState<RefForm[]>([])
  const [filterType, setFilterType] = useState('')
  const [search, setSearch] = useState('')

  useEffect(() => {
    supabase.from('ref_compliance_forms').select('*').order('compliance_type').then(({ data }) => setForms(data || []))
  }, [])

  const q = search.toLowerCase()
  const filtered = forms.filter(f =>
    (!filterType || f.compliance_type === filterType) &&
    (!q || f.form_code.toLowerCase().includes(q) || f.form_name.toLowerCase().includes(q))
  )

  const TYPES = ['vat','ewt','fwt','income_tax','alphalist','information','lgu']

  const grouped = TYPES.map(t => ({ type: t, items: filtered.filter(f => f.compliance_type === t) })).filter(g => g.items.length > 0)

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">BIR Form Configuration</h1>
        <p className="text-sm text-gray-500 mt-0.5">Reference list of supported BIR compliance forms and their filing parameters</p>
      </div>

      <div className="flex items-center gap-3">
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search form no. or name…" className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-64 focus:outline-none focus:ring-2 focus:ring-gray-900" />
        <select value={filterType} onChange={e => setFilterType(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900">
          <option value="">All Types</option>
          {TYPES.map(t => <option key={t} value={t}>{t.replace('_',' ').toUpperCase()}</option>)}
        </select>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-7 gap-2">
        {TYPES.map(t => {
          const count = forms.filter(f => f.compliance_type === t).length
          return (
            <button key={t} onClick={() => setFilterType(filterType === t ? '' : t)}
              className={`rounded-lg border p-3 text-center transition-colors ${filterType === t ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-200 bg-white hover:border-gray-400'}`}>
              <div className="text-lg font-bold">{count}</div>
              <div className="text-xs mt-0.5 opacity-70">{t.replace('_',' ')}</div>
            </button>
          )
        })}
      </div>

      {/* Grouped tables */}
      {grouped.map(g => (
        <div key={g.type} className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 bg-gray-50 border-b border-gray-200 flex items-center gap-2">
            <span className={`text-xs font-semibold px-2 py-0.5 rounded ${TYPE_COLOR[g.type] || 'bg-gray-100 text-gray-600'}`}>
              {g.type.replace('_',' ').toUpperCase()}
            </span>
            <span className="text-xs text-gray-400">{g.items.length} form{g.items.length > 1 ? 's' : ''}</span>
          </div>
          <table className="w-full text-sm">
            <thead className="border-b border-gray-100">
              <tr>{['Form No.','Form Name','Frequency','Statutory Deadline Rule','eFPS Eligible','Status'].map(h =>
                <th key={h} className="px-4 py-2.5 text-left text-xs font-medium text-gray-500">{h}</th>
              )}</tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {g.items.map(f => (
                <tr key={f.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono font-semibold text-gray-900">{f.form_code}</td>
                  <td className="px-4 py-3 text-gray-700">{f.form_name}</td>
                  <td className="px-4 py-3">
                    <span className="text-xs text-gray-500">{FREQ_MAP[f.form_code] || '—'}</span>
                  </td>
                  <td className="px-4 py-3 text-xs text-gray-600 max-w-xs">{f.statutory_deadline_rule}</td>
                  <td className="px-4 py-3">
                    {f.efps_eligible
                      ? <span className="text-xs text-green-700 font-medium">Yes</span>
                      : <span className="text-xs text-gray-400">No</span>}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${f.is_active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-500'}`}>
                      {f.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}

      {!filtered.length && (
        <div className="bg-white border border-gray-200 rounded-lg py-10 text-center text-gray-400">No forms found</div>
      )}
    </div>
  )
}
