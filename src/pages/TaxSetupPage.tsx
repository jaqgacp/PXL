import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type TaxCode = { id: string; code: string; description: string; tax_type: string; rate: number; is_active: boolean }
type VatCode = { id: string; tax_code_id: string; vat_code: string; description: string; vat_classification: string; transaction_type: string; relief_category: string | null; is_active: boolean; tax_codes?: { code: string; rate: number } }
type ATCCode = {
  id: string
  code: string
  description: string
  tax_category: string
  rate: number
  is_active: boolean
  effective_from: string | null
  effective_to: string | null
  deprecated_at: string | null
  deprecated_reason: string | null
  supersedes_atc_code_id: string | null
}
type PTCode  = { id: string; company_id: string; tax_code_id: string; pt_code: string; description: string; atc_id: string; rate: number; form_type: string; is_active: boolean; atc_codes?: { code: string }; tax_codes?: { code: string } }
type Company = { id: string; registered_name: string }

type Tab = 'tax_codes' | 'vat_codes' | 'pt_codes' | 'atc_codes'

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

const TAX_TYPES = ['vat','ewt','fwt','pt']
const VAT_CLASSIFICATIONS = ['regular','zero_rated','exempt']
const TX_TYPES = ['input_vat','output_vat']
const RELIEF_CATS = ['G','S','Z','E','']

const badge = (active: boolean) => (
  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-500'}`}>
    {active ? 'Active' : 'Inactive'}
  </span>
)

const fmtDate = (value?: string | null) => value ? new Date(value).toLocaleDateString() : '—'

function emptyTC() { return { code: '', description: '', tax_type: 'vat', rate: '' } }
function emptyVC() { return { tax_code_id: '', vat_code: '', description: '', vat_classification: 'regular', transaction_type: 'output_vat', relief_category: '' } }
function emptyPT(cid: string) { return { company_id: cid, tax_code_id: '', pt_code: '', description: '', atc_id: '', rate: '', form_type: '2551Q' } }

export default function TaxSetupPage() {
  const { companyId } = useAppCtx()
  const [tab, setTab] = useState<Tab>('tax_codes')
  const [search, setSearch] = useState('')
  const [filterType, setFilterType] = useState('')

  const [taxCodes, setTaxCodes] = useState<TaxCode[]>([])
  const [vatCodes, setVatCodes] = useState<VatCode[]>([])
  const [atcCodes, setATCCodes] = useState<ATCCode[]>([])
  const [ptCodes, setPTCodes]   = useState<PTCode[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [selectedCompany, setSelectedCompany] = useState('')

  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const [tcForm, setTcForm] = useState(emptyTC())
  const [vcForm, setVcForm] = useState(emptyVC())
  const [ptForm,  setPtForm]  = useState(emptyPT(''))

  const cid = companyId || selectedCompany

  const fetchAll = async () => {
    supabase.from('tax_codes').select('*').order('tax_type').then(({ data }) => setTaxCodes((data || []) as unknown as TaxCode[]))
    supabase.from('vat_codes').select('*, tax_codes(code,rate)').order('vat_code').then(({ data }) => setVatCodes((data as VatCode[]) || []))
    supabase.from('atc_codes').select('*').order('code').then(({ data }) => setATCCodes((data || []) as unknown as ATCCode[]))
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
  }
  const fetchCompanyCodes = async (coid: string) => {
    if (!coid) return
    supabase.from('percentage_tax_codes').select('*, atc_codes(code), tax_codes(code)').eq('company_id', coid).order('pt_code').then(({ data }) => setPTCodes((data as PTCode[]) || []))
  }

  useEffect(() => { fetchAll() }, [])
  useEffect(() => { fetchCompanyCodes(cid) }, [cid])

  const resetForm = () => { setShowForm(false); setEditId(null); setSaved(false) }

  // ── Tax Codes ──────────────────────────────────────────────
  const openTC = (r?: TaxCode) => {
    setTcForm(r ? { code: r.code, description: r.description, tax_type: r.tax_type, rate: String(r.rate) } : emptyTC())
    setEditId(r?.id ?? null); setShowForm(true); setSaved(false)
  }
  const saveTC = async () => {
    setSaving(true)
    // Global tax reference is write-governed (MDP-01): mutate only through the RPC.
    const { error } = await supabase.rpc('fn_tax_code_upsert', {
      p_code: tcForm.code, p_description: tcForm.description, p_tax_type: tcForm.tax_type,
      p_rate: parseFloat(tcForm.rate), p_id: editId || undefined, p_reason: 'tax setup: save tax code',
    })
    if (error) alert(error.message)
    else { setSaved(true); fetchAll(); resetForm() }
    setSaving(false)
  }
  const toggleTC = async (r: TaxCode) => {
    const { error } = await supabase.rpc('fn_tax_code_set_active', {
      p_id: r.id, p_is_active: !r.is_active, p_reason: 'tax setup: toggle active',
    })
    if (error) alert(error.message)
    fetchAll()
  }

  // ── VAT Codes ─────────────────────────────────────────────
  const openVC = (r?: VatCode) => {
    setVcForm(r ? { tax_code_id: r.tax_code_id, vat_code: r.vat_code, description: r.description, vat_classification: r.vat_classification, transaction_type: r.transaction_type, relief_category: r.relief_category || '' } : emptyVC())
    setEditId(r?.id ?? null); setShowForm(true); setSaved(false)
  }
  const saveVC = async () => {
    setSaving(true)
    // Global VAT reference is write-governed (MDP-01): mutate only through the RPC.
    const { error } = await supabase.rpc('fn_vat_code_upsert', {
      p_tax_code_id: vcForm.tax_code_id, p_vat_code: vcForm.vat_code, p_description: vcForm.description,
      p_vat_classification: vcForm.vat_classification, p_transaction_type: vcForm.transaction_type,
      p_relief_category: vcForm.relief_category || undefined,
      p_id: editId || undefined, p_reason: 'tax setup: save VAT code',
    })
    if (error) alert(error.message)
    else { setSaved(true); fetchAll(); resetForm() }
    setSaving(false)
  }
  const toggleVC = async (r: VatCode) => {
    const { error } = await supabase.rpc('fn_vat_code_set_active', {
      p_id: r.id, p_is_active: !r.is_active, p_reason: 'tax setup: toggle active',
    })
    if (error) alert(error.message)
    fetchAll()
  }

  // ── PT Codes ──────────────────────────────────────────────
  const openPT = (r?: PTCode) => {
    setPtForm(r ? { company_id: r.company_id, tax_code_id: r.tax_code_id, pt_code: r.pt_code, description: r.description, atc_id: r.atc_id, rate: String(r.rate), form_type: r.form_type } : emptyPT(cid))
    setEditId(r?.id ?? null); setShowForm(true); setSaved(false)
  }
  const savePT = async () => {
    setSaving(true)
    const payload = { ...ptForm, rate: parseFloat(ptForm.rate) }
    const { error } = editId ? await supabase.from('percentage_tax_codes').update(payload).eq('id', editId) : await supabase.from('percentage_tax_codes').insert([payload])
    if (error) alert(error.message)
    else { setSaved(true); fetchCompanyCodes(cid); resetForm() }
    setSaving(false)
  }
  const togglePT = async (r: PTCode) => {
    await supabase.from('percentage_tax_codes').update({ is_active: !r.is_active }).eq('id', r.id)
    fetchCompanyCodes(cid)
  }

  const q = search.toLowerCase()
  const filtTax = taxCodes.filter(r => (!filterType || r.tax_type === filterType) && (!q || r.code.toLowerCase().includes(q) || r.description.toLowerCase().includes(q)))
  const filtVAT = vatCodes.filter(r => (!filterType || r.vat_classification === filterType) && (!q || r.vat_code.toLowerCase().includes(q) || r.description.toLowerCase().includes(q)))
  const filtATC = atcCodes.filter(r => (!filterType || r.tax_category === filterType) && (!q || r.code.toLowerCase().includes(q) || r.description.toLowerCase().includes(q)))
  const filtPT  = ptCodes.filter(r => (!q || r.pt_code.toLowerCase().includes(q) || r.description.toLowerCase().includes(q)))

  const TABS: { id: Tab; label: string }[] = [
    { id: 'tax_codes',  label: 'Tax Codes' },
    { id: 'vat_codes',  label: 'VAT Codes' },
    { id: 'pt_codes',   label: 'Percentage Tax Codes' },
    { id: 'atc_codes',  label: 'ATC Codes' },
  ]

  const needsCompany = tab === 'pt_codes'
  const canAdd = !needsCompany || !!cid

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Tax Code Setup</h1>
        <p className="text-sm text-gray-500 mt-0.5">Configure Philippine tax codes, VAT, ATC, and percentage tax parameters</p>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-gray-200 gap-0 overflow-x-auto">
        {TABS.map(t => (
          <button key={t.id} onClick={() => { setTab(t.id); setShowForm(false); setSearch(''); setFilterType('') }}
            className={`px-4 py-2 text-sm font-medium whitespace-nowrap border-b-2 transition-colors ${tab === t.id ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>
            {t.label}
          </button>
        ))}
      </div>

      {/* Company selector for per-company tabs */}
      {needsCompany && (
        <div className="flex items-center gap-3">
          <label className="text-sm text-gray-600 font-medium">Company:</label>
          <select value={cid || selectedCompany} onChange={e => setSelectedCompany(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900">
            <option value="">— select company —</option>
            {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
          </select>
        </div>
      )}

      {/* Action bar */}
      <div className="flex items-center gap-3">
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search code or description…" className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-64 focus:outline-none focus:ring-2 focus:ring-gray-900" />
        {(tab === 'tax_codes' || tab === 'atc_codes') && (
          <select value={filterType} onChange={e => setFilterType(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900">
            <option value="">All Types</option>
            {TAX_TYPES.map(t => <option key={t} value={t}>{t.toUpperCase()}</option>)}
          </select>
        )}
        {tab === 'vat_codes' && (
          <select value={filterType} onChange={e => setFilterType(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900">
            <option value="">All Classifications</option>
            {VAT_CLASSIFICATIONS.map(v => <option key={v} value={v}>{v.replace('_',' ')}</option>)}
          </select>
        )}
        <div className="flex-1" />
        {tab !== 'atc_codes' && (
          <button onClick={() => { resetForm(); setShowForm(true) }} disabled={!canAdd}
            className="px-4 py-1.5 bg-gray-900 text-white text-sm rounded-md hover:bg-gray-700 disabled:opacity-40">
            + Add {TABS.find(t => t.id === tab)?.label.replace(' Codes','').replace('Percentage Tax ','PT ')} Code
          </button>
        )}
      </div>

      {/* ── TAX CODES TABLE ── */}
      {tab === 'tax_codes' && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['Tax Code','Description','Type','Rate (%)','Status',''].map(h => <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtTax.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{r.code}</td>
                  <td className="px-4 py-3 text-gray-700">{r.description}</td>
                  <td className="px-4 py-3"><span className="uppercase text-xs font-semibold text-indigo-700 bg-indigo-50 px-2 py-0.5 rounded">{r.tax_type}</span></td>
                  <td className="px-4 py-3 font-mono">{r.rate}%</td>
                  <td className="px-4 py-3">{badge(r.is_active)}</td>
                  <td className="px-4 py-3 text-right space-x-2">
                    <button onClick={() => openTC(r)} className="text-xs text-indigo-600 hover:underline">Edit</button>
                    <button onClick={() => toggleTC(r)} className="text-xs text-gray-500 hover:underline">{r.is_active ? 'Deactivate' : 'Activate'}</button>
                  </td>
                </tr>
              ))}
              {!filtTax.length && <tr><td colSpan={6} className="px-4 py-8 text-center text-gray-400">No tax codes found</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {/* ── VAT CODES TABLE ── */}
      {tab === 'vat_codes' && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['VAT Code','Description','Classification','Rate','Transaction Type','RELIEF Cat','Status',''].map(h => <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtVAT.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{r.vat_code}</td>
                  <td className="px-4 py-3 text-gray-700">{r.description}</td>
                  <td className="px-4 py-3">
                    <span className={`text-xs font-medium px-2 py-0.5 rounded ${r.vat_classification === 'regular' ? 'bg-blue-50 text-blue-700' : r.vat_classification === 'zero_rated' ? 'bg-yellow-50 text-yellow-700' : 'bg-gray-100 text-gray-600'}`}>
                      {r.vat_classification.replace('_',' ')}
                    </span>
                  </td>
                  <td className="px-4 py-3 font-mono">{r.tax_codes?.rate ?? '—'}%</td>
                  <td className="px-4 py-3 text-xs text-gray-600">{r.transaction_type.replace('_',' ')}</td>
                  <td className="px-4 py-3 font-mono text-xs">{r.relief_category || '—'}</td>
                  <td className="px-4 py-3">{badge(r.is_active)}</td>
                  <td className="px-4 py-3 text-right space-x-2">
                    <button onClick={() => openVC(r)} className="text-xs text-indigo-600 hover:underline">Edit</button>
                    <button onClick={() => toggleVC(r)} className="text-xs text-gray-500 hover:underline">{r.is_active ? 'Deactivate' : 'Activate'}</button>
                  </td>
                </tr>
              ))}
              {!filtVAT.length && <tr><td colSpan={8} className="px-4 py-8 text-center text-gray-400">No VAT codes found</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {/* ── PT CODES TABLE ── */}
      {tab === 'pt_codes' && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['PT Code','Description','ATC','Rate (%)','Form','Status',''].map(h => <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtPT.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{r.pt_code}</td>
                  <td className="px-4 py-3 text-gray-700">{r.description}</td>
                  <td className="px-4 py-3 font-mono text-xs text-indigo-700">{r.atc_codes?.code}</td>
                  <td className="px-4 py-3 font-mono">{r.rate}%</td>
                  <td className="px-4 py-3 text-xs">{r.form_type}</td>
                  <td className="px-4 py-3">{badge(r.is_active)}</td>
                  <td className="px-4 py-3 text-right space-x-2">
                    <button onClick={() => openPT(r)} className="text-xs text-indigo-600 hover:underline">Edit</button>
                    <button onClick={() => togglePT(r)} className="text-xs text-gray-500 hover:underline">{r.is_active ? 'Deactivate' : 'Activate'}</button>
                  </td>
                </tr>
              ))}
              {!filtPT.length && <tr><td colSpan={7} className="px-4 py-8 text-center text-gray-400">{cid ? 'No PT codes found' : 'Select a company to view PT codes'}</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {/* ── ATC CODES TABLE ── */}
      {tab === 'atc_codes' && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['ATC Code','Description','Tax Type','Rate (%)','Effective','Status','Deprecated'].map(h => <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtATC.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{r.code}</td>
                  <td className="px-4 py-3 text-gray-700">{r.description}</td>
                  <td className="px-4 py-3"><span className="uppercase text-xs font-semibold text-indigo-700 bg-indigo-50 px-2 py-0.5 rounded">{r.tax_category}</span></td>
                  <td className="px-4 py-3 font-mono">{r.rate}%</td>
                  <td className="px-4 py-3 text-xs text-gray-600">{fmtDate(r.effective_from)} - {fmtDate(r.effective_to)}</td>
                  <td className="px-4 py-3">{badge(r.is_active)}</td>
                  <td className="px-4 py-3">
                    {r.deprecated_at ? (
                      <span title={r.deprecated_reason || undefined} className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-amber-100 text-amber-800">Deprecated</span>
                    ) : (
                      <span className="text-xs text-gray-400">—</span>
                    )}
                  </td>
                </tr>
              ))}
              {!filtATC.length && <tr><td colSpan={7} className="px-4 py-8 text-center text-gray-400">No ATC codes found</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {/* ── FORMS ── */}
      {showForm && tab === 'tax_codes' && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 space-y-4">
            <h2 className="text-base font-semibold text-gray-900">{editId ? 'Edit' : 'Add'} Tax Code</h2>
            <div className={sec}>
              <p className={hd}>Tax Code Details</p>
              <div className="grid grid-cols-2 gap-4">
                <div><label className={lbl}>Tax Code *</label><input className={inp} value={tcForm.code} onChange={e => setTcForm(f => ({ ...f, code: e.target.value }))} placeholder="e.g. VAT-12" /></div>
                <div><label className={lbl}>Tax Type *</label>
                  <select className={inp} value={tcForm.tax_type} onChange={e => setTcForm(f => ({ ...f, tax_type: e.target.value }))}>
                    {TAX_TYPES.map(t => <option key={t} value={t}>{t.toUpperCase()}</option>)}
                  </select>
                </div>
              </div>
              <div><label className={lbl}>Description *</label><input className={inp} value={tcForm.description} onChange={e => setTcForm(f => ({ ...f, description: e.target.value }))} /></div>
              <div className="w-40"><label className={lbl}>Rate (%)*</label><input className={inp} type="number" step="0.01" value={tcForm.rate} onChange={e => setTcForm(f => ({ ...f, rate: e.target.value }))} /></div>
            </div>
            <div className="flex justify-end gap-3">
              <button onClick={resetForm} className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button onClick={saveTC} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">{saving ? 'Saving…' : saved ? 'Saved!' : 'Save'}</button>
            </div>
          </div>
        </div>
      )}

      {showForm && tab === 'vat_codes' && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 space-y-4">
            <h2 className="text-base font-semibold text-gray-900">{editId ? 'Edit' : 'Add'} VAT Code</h2>
            <div className={sec}>
              <p className={hd}>VAT Code Details</p>
              <div><label className={lbl}>Parent Tax Code *</label>
                <select className={inp} value={vcForm.tax_code_id} onChange={e => setVcForm(f => ({ ...f, tax_code_id: e.target.value }))}>
                  <option value="">— select —</option>
                  {taxCodes.filter(t => t.tax_type === 'vat').map(t => <option key={t.id} value={t.id}>{t.code} — {t.description}</option>)}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className={lbl}>VAT Code *</label><input className={inp} value={vcForm.vat_code} onChange={e => setVcForm(f => ({ ...f, vat_code: e.target.value }))} placeholder="e.g. VAT-12" /></div>
                <div><label className={lbl}>Transaction Type *</label>
                  <select className={inp} value={vcForm.transaction_type} onChange={e => setVcForm(f => ({ ...f, transaction_type: e.target.value }))}>
                    {TX_TYPES.map(t => <option key={t} value={t}>{t.replace('_',' ')}</option>)}
                  </select>
                </div>
              </div>
              <div><label className={lbl}>Description *</label><input className={inp} value={vcForm.description} onChange={e => setVcForm(f => ({ ...f, description: e.target.value }))} /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className={lbl}>VAT Classification *</label>
                  <select className={inp} value={vcForm.vat_classification} onChange={e => setVcForm(f => ({ ...f, vat_classification: e.target.value }))}>
                    {VAT_CLASSIFICATIONS.map(v => <option key={v} value={v}>{v.replace('_',' ')}</option>)}
                  </select>
                </div>
                <div><label className={lbl}>RELIEF Category</label>
                  <select className={inp} value={vcForm.relief_category} onChange={e => setVcForm(f => ({ ...f, relief_category: e.target.value }))}>
                    {RELIEF_CATS.map(c => <option key={c} value={c}>{c || '— none —'}</option>)}
                  </select>
                </div>
              </div>
            </div>
            <div className="flex justify-end gap-3">
              <button onClick={resetForm} className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button onClick={saveVC} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">{saving ? 'Saving…' : saved ? 'Saved!' : 'Save'}</button>
            </div>
          </div>
        </div>
      )}

      {showForm && tab === 'pt_codes' && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 space-y-4">
            <h2 className="text-base font-semibold text-gray-900">{editId ? 'Edit' : 'Add'} Percentage Tax Code</h2>
            <div className={sec}>
              <p className={hd}>PT Code Details</p>
              <div><label className={lbl}>Parent Tax Code *</label>
                <select className={inp} value={ptForm.tax_code_id} onChange={e => setPtForm(f => ({ ...f, tax_code_id: e.target.value }))}>
                  <option value="">— select —</option>
                  {taxCodes.filter(t => t.tax_type === 'pt').map(t => <option key={t.id} value={t.id}>{t.code} — {t.description}</option>)}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className={lbl}>PT Code *</label><input className={inp} value={ptForm.pt_code} onChange={e => setPtForm(f => ({ ...f, pt_code: e.target.value }))} placeholder="e.g. PT-3" /></div>
                <div><label className={lbl}>ATC *</label>
                  <select className={inp} value={ptForm.atc_id} onChange={e => setPtForm(f => ({ ...f, atc_id: e.target.value }))}>
                    <option value="">— select —</option>
                    {atcCodes.map(a => <option key={a.id} value={a.id}>{a.code} — {a.description}</option>)}
                  </select>
                </div>
              </div>
              <div><label className={lbl}>Description *</label><input className={inp} value={ptForm.description} onChange={e => setPtForm(f => ({ ...f, description: e.target.value }))} /></div>
              <div className="grid grid-cols-2 gap-4">
                <div><label className={lbl}>Rate (%) *</label><input className={inp} type="number" step="0.01" value={ptForm.rate} onChange={e => setPtForm(f => ({ ...f, rate: e.target.value }))} /></div>
                <div><label className={lbl}>Form Type</label><input className={inp} value={ptForm.form_type} readOnly /></div>
              </div>
            </div>
            <div className="flex justify-end gap-3">
              <button onClick={resetForm} className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button onClick={savePT} disabled={saving} className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">{saving ? 'Saving…' : saved ? 'Saved!' : 'Save'}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
