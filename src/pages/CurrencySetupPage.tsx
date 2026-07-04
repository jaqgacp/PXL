import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Currency = { id: string; currency_code: string; name: string; symbol: string; is_base: boolean; is_active: boolean }
type ExchangeRate = { id: string; company_id: string; currency_id: string; rate_date: string; rate: number; rate_type: string; source: string; companies?: { registered_name: string }; currencies?: { currency_code: string; name: string; symbol: string } }
type Company = { id: string; registered_name: string }

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function CurrencySetupPage() {
  const [tab, setTab] = useState<'currencies' | 'exchange_rates'>('currencies')
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [rates, setRates] = useState<ExchangeRate[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [filterCompany, setFilterCompany] = useState('')
  const [showRateForm, setShowRateForm] = useState(false)
  const [rateForm, setRateForm] = useState({ company_id: '', currency_id: '', rate_date: '', rate: '' })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    supabase.from('currencies').select('*').order('is_base', { ascending: false }).then(({ data }) => setCurrencies((data || []) as unknown as Currency[]))
    supabase.from('exchange_rates').select('*, companies(registered_name), currencies(currency_code,name,symbol)').order('rate_date', { ascending: false }).limit(200)
      .then(({ data }) => setRates((data as ExchangeRate[]) || []))
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
  }, [])

  const setR = (k: string, v: string) => { setSaved(false); setRateForm(f => ({ ...f, [k]: v })) }

  const toggleCurrency = async (c: Currency) => {
    if (c.is_base) return
    await supabase.from('currencies').update({ is_active: !c.is_active }).eq('id', c.id)
    supabase.from('currencies').select('*').order('is_base', { ascending: false }).then(({ data }) => setCurrencies((data || []) as unknown as Currency[]))
  }

  const handleSaveRate = async () => {
    setSaving(true)
    const { error } = await supabase.from('exchange_rates').upsert([{ company_id: rateForm.company_id, currency_id: rateForm.currency_id, rate_date: rateForm.rate_date, rate: parseFloat(rateForm.rate), rate_type: 'bsp_reference', source: 'manual' }], { onConflict: 'company_id,currency_id,rate_date,rate_type' })
    if (error) alert('Error: ' + error.message)
    else {
      setSaved(true)
      const { data } = await supabase.from('exchange_rates').select('*, companies(registered_name), currencies(currency_code,name,symbol)').order('rate_date', { ascending: false }).limit(200)
      setRates((data as ExchangeRate[]) || [])
    }
    setSaving(false)
  }

  const filteredRates = rates.filter(r => !filterCompany || r.company_id === filterCompany)
  const activeCurrencies = currencies.filter(c => !c.is_base && c.is_active)

  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Currency Setup</h1>
        <p className="text-sm text-gray-500 mt-0.5">Manage functional currencies and exchange rates</p></div>
      <div className="flex border-b border-gray-200">
        {(['currencies','exchange_rates'] as const).map(t => (
          <button key={t} onClick={() => { setTab(t); setShowRateForm(false) }}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${tab === t ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>
            {t === 'currencies' ? 'Currencies' : 'Exchange Rates'}
          </button>
        ))}
      </div>

      {tab === 'currencies' ? (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100 bg-blue-50">
            <p className="text-xs text-blue-700">Pre-loaded currency list. PHP is the base functional currency. Enable additional currencies to record foreign transactions.</p>
          </div>
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Code</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Name</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Symbol</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Base</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {currencies.map((c, i) => (
                <tr key={c.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{c.currency_code}</td>
                  <td className="px-4 py-3 text-gray-700">{c.name}</td>
                  <td className="px-4 py-3 text-gray-600 font-medium">{c.symbol}</td>
                  <td className="px-4 py-3">{c.is_base ? <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-purple-50 text-purple-700">Base Currency</span> : '—'}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${c.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{c.is_active ? 'Enabled' : 'Disabled'}</span></td>
                  <td className="px-4 py-3">{c.is_base ? <span className="text-xs text-gray-300">—</span> : (
                    <button onClick={() => toggleCurrency(c)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{c.is_active ? 'Disable' : 'Enable'}</button>
                  )}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <>
          {showRateForm ? (
            <div className={`max-w-2xl ${sec}`}><h2 className={hd}>Add Exchange Rate</h2>
              <div className="grid grid-cols-2 gap-4">
                <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
                  <select value={rateForm.company_id} onChange={e => setR('company_id', e.target.value)} className={inp}>
                    <option value="">Select company...</option>
                    {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
                  </select></div>
                <div><label className={lbl}>Foreign Currency <span className="text-red-500">*</span></label>
                  <select value={rateForm.currency_id} onChange={e => setR('currency_id', e.target.value)} className={inp}>
                    <option value="">Select currency...</option>
                    {activeCurrencies.map(c => <option key={c.id} value={c.id}>{c.currency_code} — {c.name}</option>)}
                  </select></div>
                <div><label className={lbl}>Rate Date <span className="text-red-500">*</span></label>
                  <input type="date" value={rateForm.rate_date} onChange={e => setR('rate_date', e.target.value)} className={inp} /></div>
                <div><label className={lbl}>Exchange Rate (1 Foreign = X PHP) <span className="text-red-500">*</span></label>
                  <input type="number" step="0.000001" min="0" value={rateForm.rate} onChange={e => setR('rate', e.target.value)} className={inp} placeholder="e.g., 57.500000" /></div>
              </div>
              <div className="flex gap-2 pt-2">
                <button onClick={() => setShowRateForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
                <button onClick={handleSaveRate} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
                  {saving ? 'Saving...' : saved ? '✓ Saved' : 'Save Rate'}
                </button>
              </div>
            </div>
          ) : (
            <>
              <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
                <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)}
                  className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
                  <option value="">All Companies</option>
                  {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
                </select>
                <div className="ml-auto">
                  <button onClick={() => { setRateForm({ company_id: '', currency_id: '', rate_date: '', rate: '' }); setSaved(false); setShowRateForm(true) }}
                    className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
                    + Add Exchange Rate
                  </button>
                </div>
              </div>
              <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
                <table className="w-full text-sm">
                  <thead><tr className="bg-gray-50 border-b border-gray-200">
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</th>
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Currency</th>
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Rate (to PHP)</th>
                    <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
                  </tr></thead>
                  <tbody>
                    {filteredRates.length === 0
                      ? <tr><td colSpan={4} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Exchange Rates</p><p className="text-sm mt-1">Add daily rates for foreign currency conversions.</p></td></tr>
                      : filteredRates.map((r, i) => (
                        <tr key={r.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                          <td className="px-4 py-3 text-gray-700">{r.rate_date}</td>
                          <td className="px-4 py-3">
                            <span className="font-mono font-medium text-gray-900 mr-2">{r.currencies?.currency_code}</span>
                            <span className="text-gray-500">{r.currencies?.name}</span>
                          </td>
                          <td className="px-4 py-3 font-mono tabular-nums text-gray-900">{Number(r.rate).toFixed(6)}</td>
                          <td className="px-4 py-3 text-gray-500">{r.companies?.registered_name || '—'}</td>
                        </tr>
                      ))}
                  </tbody>
                </table>
                {filteredRates.length > 0 && <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">Showing {filteredRates.length} rates</div>}
              </div>
            </>
          )}
        </>
      )}
    </div>
  )
}
