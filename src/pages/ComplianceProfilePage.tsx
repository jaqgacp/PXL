import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type Profile = {
  id: string; company_id: string; efps_enrolled: boolean; efps_group: string | null
  vat_registered: boolean; vat_effective_date: string | null; vat_filing_frequency: string | null; vat_threshold_monitoring: boolean
  percentage_tax_registered: boolean; percentage_tax_rate: number | null; pt_effective_date: string | null; pt_filing_frequency: string | null
  ewt_registered: boolean; is_twa: boolean; twa_effective_date: string | null; twa_auto_ewt_enabled: boolean
  files_0619e: boolean; qap_required: boolean; requires_1604e: boolean
  fwt_registered: boolean; files_0619f: boolean
  income_tax_regime: string; corporate_tax_rate: number; mcit_applicable: boolean; nolco_applicable: boolean
  sawt_required: boolean; slsp_required: boolean; relief_required: boolean; dat_file_required: boolean
  is_active: boolean
  companies?: { registered_name: string }
}

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

const Toggle = ({ value, onChange, label }: { value: boolean; onChange: (v: boolean) => void; label: string }) => (
  <label className="flex items-center gap-3 cursor-pointer select-none">
    <button type="button" onClick={() => onChange(!value)}
      className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${value ? 'bg-gray-900' : 'bg-gray-300'}`}>
      <span className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${value ? 'translate-x-4' : 'translate-x-0.5'}`} />
    </button>
    <span className="text-sm text-gray-700">{label}</span>
  </label>
)

const EMPTY: Omit<Profile, 'id' | 'companies'> = {
  company_id: '', efps_enrolled: false, efps_group: null,
  vat_registered: false, vat_effective_date: null, vat_filing_frequency: 'quarterly', vat_threshold_monitoring: false,
  percentage_tax_registered: false, percentage_tax_rate: null, pt_effective_date: null, pt_filing_frequency: 'quarterly',
  ewt_registered: false, is_twa: false, twa_effective_date: null, twa_auto_ewt_enabled: false,
  files_0619e: false, qap_required: false, requires_1604e: false,
  fwt_registered: false, files_0619f: false,
  income_tax_regime: 'rcit', corporate_tax_rate: 25, mcit_applicable: false, nolco_applicable: false,
  sawt_required: false, slsp_required: false, relief_required: false, dat_file_required: false,
  is_active: true,
}

export default function ComplianceProfilePage() {
  const [profiles, setProfiles] = useState<Profile[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState({ ...EMPTY })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [search, setSearch] = useState('')

  const fetchAll = () => {
    supabase.from('compliance_profiles').select('*, companies(registered_name)').order('created_at', { ascending: false })
      .then(({ data }) => setProfiles((data as Profile[]) || []))
    supabase.from('companies').select('id,registered_name').order('registered_name')
      .then(({ data }) => setCompanies(data || []))
  }
  useEffect(() => { fetchAll() }, [])

  const set = <K extends keyof typeof EMPTY>(k: K, v: (typeof EMPTY)[K]) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const openNew = () => {
    setForm({ ...EMPTY }); setEditId(null); setShowForm(true); setSaved(false)
  }
  const openEdit = (p: Profile) => {
    setForm({
      company_id: p.company_id, efps_enrolled: p.efps_enrolled, efps_group: p.efps_group,
      vat_registered: p.vat_registered, vat_effective_date: p.vat_effective_date, vat_filing_frequency: p.vat_filing_frequency, vat_threshold_monitoring: p.vat_threshold_monitoring,
      percentage_tax_registered: p.percentage_tax_registered, percentage_tax_rate: p.percentage_tax_rate, pt_effective_date: p.pt_effective_date, pt_filing_frequency: p.pt_filing_frequency,
      ewt_registered: p.ewt_registered, is_twa: p.is_twa, twa_effective_date: p.twa_effective_date, twa_auto_ewt_enabled: p.twa_auto_ewt_enabled,
      files_0619e: p.files_0619e, qap_required: p.qap_required, requires_1604e: p.requires_1604e,
      fwt_registered: p.fwt_registered, files_0619f: p.files_0619f,
      income_tax_regime: p.income_tax_regime, corporate_tax_rate: p.corporate_tax_rate, mcit_applicable: p.mcit_applicable, nolco_applicable: p.nolco_applicable,
      sawt_required: p.sawt_required, slsp_required: p.slsp_required, relief_required: p.relief_required, dat_file_required: p.dat_file_required,
      is_active: p.is_active,
    })
    setEditId(p.id); setShowForm(true); setSaved(false)
  }

  const handleSave = async () => {
    if (!form.company_id) return alert('Please select a company')
    setSaving(true)
    const payload = {
      ...form,
      efps_group: form.efps_enrolled ? form.efps_group : null,
      vat_effective_date: form.vat_registered ? form.vat_effective_date : null,
      vat_filing_frequency: form.vat_registered ? form.vat_filing_frequency : null,
      percentage_tax_rate: form.percentage_tax_registered ? form.percentage_tax_rate : null,
      pt_effective_date: form.percentage_tax_registered ? form.pt_effective_date : null,
      pt_filing_frequency: form.percentage_tax_registered ? form.pt_filing_frequency : null,
      twa_effective_date: form.is_twa ? form.twa_effective_date : null,
    }
    const { error } = editId
      ? await supabase.from('compliance_profiles').update(payload).eq('id', editId)
      : await supabase.from('compliance_profiles').insert([payload])
    if (error) alert(error.message)
    else { setSaved(true); fetchAll(); setTimeout(() => { setShowForm(false); setSaved(false) }, 800) }
    setSaving(false)
  }

  const toggleActive = async (p: Profile) => {
    await supabase.from('compliance_profiles').update({ is_active: !p.is_active }).eq('id', p.id)
    fetchAll()
  }

  const filtered = profiles.filter(p => !search || p.companies?.registered_name.toLowerCase().includes(search.toLowerCase()))

  const badge = (active: boolean) => (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-500'}`}>
      {active ? 'Active' : 'Inactive'}
    </span>
  )

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Compliance Profile</h1>
        <p className="text-sm text-gray-500 mt-0.5">Configure BIR tax registrations and filing obligations per company</p>
      </div>

      <div className="flex items-center gap-3">
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search by company…" className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-64 focus:outline-none focus:ring-2 focus:ring-gray-900" />
        <div className="flex-1" />
        <button onClick={openNew} className="px-4 py-1.5 bg-gray-900 text-white text-sm rounded-md hover:bg-gray-700">+ New Profile</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>{['Company','Tax Registration','Income Tax Regime','TWA','eFPS','Status',''].map(h => <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">{h}</th>)}</tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {filtered.map(p => (
              <tr key={p.id} className="hover:bg-gray-50">
                <td className="px-4 py-3 font-medium text-gray-900">{p.companies?.registered_name}</td>
                <td className="px-4 py-3">
                  {p.vat_registered && <span className="text-xs bg-blue-50 text-blue-700 px-2 py-0.5 rounded mr-1">VAT</span>}
                  {p.percentage_tax_registered && <span className="text-xs bg-yellow-50 text-yellow-700 px-2 py-0.5 rounded mr-1">PT</span>}
                  {p.ewt_registered && <span className="text-xs bg-purple-50 text-purple-700 px-2 py-0.5 rounded mr-1">EWT</span>}
                  {p.fwt_registered && <span className="text-xs bg-red-50 text-red-700 px-2 py-0.5 rounded">FWT</span>}
                </td>
                <td className="px-4 py-3 text-xs text-gray-600 uppercase">{p.income_tax_regime}</td>
                <td className="px-4 py-3">
                  {p.is_twa ? <span className="text-xs bg-orange-50 text-orange-700 px-2 py-0.5 rounded font-semibold">TWA</span> : <span className="text-gray-300">—</span>}
                </td>
                <td className="px-4 py-3">{p.efps_enrolled ? <span className="text-xs text-green-700">Enrolled {p.efps_group ? `(Grp ${p.efps_group})` : ''}</span> : <span className="text-gray-400 text-xs">No</span>}</td>
                <td className="px-4 py-3">{badge(p.is_active)}</td>
                <td className="px-4 py-3 text-right space-x-2">
                  <button onClick={() => openEdit(p)} className="text-xs text-indigo-600 hover:underline">Edit</button>
                  <button onClick={() => toggleActive(p)} className="text-xs text-gray-500 hover:underline">{p.is_active ? 'Deactivate' : 'Activate'}</button>
                </td>
              </tr>
            ))}
            {!filtered.length && <tr><td colSpan={7} className="px-4 py-8 text-center text-gray-400">No compliance profiles yet</td></tr>}
          </tbody>
        </table>
      </div>

      {showForm && (
        <div className="fixed inset-0 bg-black/30 flex items-start justify-center z-50 overflow-y-auto py-8">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-2xl mx-4 p-6 space-y-5">
            <h2 className="text-base font-semibold text-gray-900">{editId ? 'Edit' : 'New'} Compliance Profile</h2>

            {/* Section 1: Company & eFPS */}
            <div className={sec}>
              <p className={hd}>Company & General Filing</p>
              <div><label className={lbl}>Company *</label>
                <select className={inp} value={form.company_id} onChange={e => set('company_id', e.target.value)} disabled={!!editId}>
                  <option value="">— select company —</option>
                  {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
                </select>
              </div>
              <Toggle value={form.efps_enrolled} onChange={v => set('efps_enrolled', v)} label="eFPS Enrolled" />
              {form.efps_enrolled && (
                <div className="w-40"><label className={lbl}>eFPS Group</label>
                  <select className={inp} value={form.efps_group || ''} onChange={e => set('efps_group', e.target.value || null)}>
                    <option value="">— select —</option>
                    {['A','B','C','D','E'].map(g => <option key={g} value={g}>Group {g}</option>)}
                  </select>
                </div>
              )}
            </div>

            {/* Section 2: VAT */}
            <div className={sec}>
              <p className={hd}>Value-Added Tax (VAT)</p>
              <Toggle value={form.vat_registered} onChange={v => set('vat_registered', v)} label="VAT Registered" />
              {form.vat_registered && (
                <div className="grid grid-cols-2 gap-4">
                  <div><label className={lbl}>VAT Effective Date</label><input type="date" className={inp} value={form.vat_effective_date || ''} onChange={e => set('vat_effective_date', e.target.value || null)} /></div>
                  <div><label className={lbl}>Filing Frequency</label>
                    <select className={inp} value={form.vat_filing_frequency || 'quarterly'} onChange={e => set('vat_filing_frequency', e.target.value)}>
                      <option value="monthly">Monthly (2550M + 2550Q)</option>
                      <option value="quarterly">Quarterly (2550Q only)</option>
                    </select>
                  </div>
                  <div className="col-span-2"><Toggle value={form.vat_threshold_monitoring} onChange={v => set('vat_threshold_monitoring', v)} label="Enable VAT Threshold Monitoring" /></div>
                </div>
              )}
            </div>

            {/* Section 3: Percentage Tax */}
            <div className={sec}>
              <p className={hd}>Percentage Tax</p>
              <Toggle value={form.percentage_tax_registered} onChange={v => set('percentage_tax_registered', v)} label="Percentage Tax Registered" />
              {form.percentage_tax_registered && (
                <div className="grid grid-cols-2 gap-4">
                  <div><label className={lbl}>Rate (%)</label><input type="number" step="0.01" className={inp} value={form.percentage_tax_rate ?? ''} onChange={e => set('percentage_tax_rate', e.target.value ? parseFloat(e.target.value) : null)} /></div>
                  <div><label className={lbl}>PT Effective Date</label><input type="date" className={inp} value={form.pt_effective_date || ''} onChange={e => set('pt_effective_date', e.target.value || null)} /></div>
                  <div><label className={lbl}>Filing Frequency</label><input className={inp} value="Quarterly (2551Q)" readOnly /></div>
                </div>
              )}
            </div>

            {/* Section 4: EWT */}
            <div className={sec}>
              <p className={hd}>Expanded Withholding Tax (EWT)</p>
              <Toggle value={form.ewt_registered} onChange={v => set('ewt_registered', v)} label="EWT Registered" />
              {form.ewt_registered && (
                <div className="space-y-3">
                  <Toggle value={form.is_twa} onChange={v => set('is_twa', v)} label="Top Withholding Agent (TWA)" />
                  {form.is_twa && (
                    <div className="grid grid-cols-2 gap-4 pl-4">
                      <div><label className={lbl}>TWA Effective Date</label><input type="date" className={inp} value={form.twa_effective_date || ''} onChange={e => set('twa_effective_date', e.target.value || null)} /></div>
                      <div className="flex items-end"><Toggle value={form.twa_auto_ewt_enabled} onChange={v => set('twa_auto_ewt_enabled', v)} label="Auto-compute EWT on Purchase Invoices" /></div>
                    </div>
                  )}
                  <Toggle value={form.files_0619e} onChange={v => set('files_0619e', v)} label="Files Monthly 0619-E Remittance" />
                  <Toggle value={form.qap_required} onChange={v => set('qap_required', v)} label="QAP Required (Quarterly Alphalist of Payees)" />
                  <Toggle value={form.requires_1604e} onChange={v => set('requires_1604e', v)} label="Annual Alphalist 1604-E Required" />
                </div>
              )}
            </div>

            {/* Section 5: FWT */}
            <div className={sec}>
              <p className={hd}>Final Withholding Tax (FWT)</p>
              <Toggle value={form.fwt_registered} onChange={v => set('fwt_registered', v)} label="FWT Registered" />
              {form.fwt_registered && (
                <div className="space-y-3 pl-1">
                  <Toggle value={form.files_0619f} onChange={v => set('files_0619f', v)} label="Files Monthly 0619-F Remittance" />
                  <p className="text-xs text-gray-400">Quarterly form: 1601FQ (auto-assigned)</p>
                </div>
              )}
            </div>

            {/* Section 6: Income Tax */}
            <div className={sec}>
              <p className={hd}>Income Tax</p>
              <div className="grid grid-cols-2 gap-4">
                <div><label className={lbl}>Income Tax Regime *</label>
                  <select className={inp} value={form.income_tax_regime} onChange={e => set('income_tax_regime', e.target.value)}>
                    <option value="rcit">RCIT — Regular Corporate Income Tax</option>
                    <option value="mcit">MCIT — Minimum Corporate Income Tax</option>
                    <option value="preferential">Preferential Rate (e.g., PEZA)</option>
                    <option value="osd">OSD — Optional Standard Deduction</option>
                    <option value="itemized">Itemized Deductions</option>
                  </select>
                </div>
                <div><label className={lbl}>Corporate Tax Rate (%)</label><input type="number" step="0.01" className={inp} value={form.corporate_tax_rate} onChange={e => set('corporate_tax_rate', parseFloat(e.target.value) || 25)} /></div>
              </div>
              <div className="flex gap-6">
                <Toggle value={form.mcit_applicable} onChange={v => set('mcit_applicable', v)} label="MCIT Applicable" />
                <Toggle value={form.nolco_applicable} onChange={v => set('nolco_applicable', v)} label="NOLCO Carryover Applicable" />
              </div>
            </div>

            {/* Section 7: System Compliance */}
            <div className={sec}>
              <p className={hd}>System Compliance & Attachments</p>
              <div className="grid grid-cols-2 gap-3">
                <Toggle value={form.sawt_required} onChange={v => set('sawt_required', v)} label="SAWT Required" />
                <Toggle value={form.slsp_required} onChange={v => set('slsp_required', v)} label="SLSP Required" />
                <Toggle value={form.relief_required} onChange={v => set('relief_required', v)} label="RELIEF Required" />
                <Toggle value={form.dat_file_required} onChange={v => set('dat_file_required', v)} label="DAT File Required (CAS)" />
              </div>
            </div>

            <div className="flex justify-end gap-3 pt-2">
              <button onClick={() => { setShowForm(false); setSaved(false) }} className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button onClick={handleSave} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">{saving ? 'Saving…' : saved ? 'Saved!' : 'Save Profile'}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
