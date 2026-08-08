import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type TaxCode = {
  id: string; code: string; description: string; tax_type: string; rate: number; is_active: boolean
  effective_from: string; effective_to: string | null
  deprecated_at: string | null; supersedes_tax_code_id: string | null
}
type VatCode = {
  id: string; tax_code_id: string; vat_code: string; description: string; vat_classification: string
  transaction_type: string; relief_category: string | null; is_active: boolean
  effective_from: string; effective_to: string | null
  deprecated_at: string | null; supersedes_vat_code_id: string | null
  tax_codes?: { code: string; rate: number }
}
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
/**
 * `succeed` is the governed edit. A statutory rate change closes the current
 * version's window and starts a successor that points back at it; it never
 * rewrites the rate in place, because posted documents are stamped with the
 * version that priced them.
 */
type Mode = 'add' | 'edit' | 'succeed'

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const inpRO = `${inp} bg-gray-50 text-gray-500`
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'
const act = 'text-xs text-indigo-600 hover:underline disabled:text-gray-300 disabled:no-underline disabled:cursor-not-allowed'
const actMuted = 'text-xs text-gray-500 hover:underline disabled:text-gray-300 disabled:no-underline disabled:cursor-not-allowed'

const TAX_TYPES = ['vat','ewt','fwt','pt']
const ATC_CATEGORIES = ['ewt','fwt','pt','vat']
const VAT_CLASSIFICATIONS = ['regular','zero_rated','exempt']
const TX_TYPES = ['input_vat','output_vat']
const RELIEF_CATS = ['G','S','Z','E','']

const badge = (active: boolean) => (
  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-500'}`}>
    {active ? 'Active' : 'Inactive'}
  </span>
)

const fmtDate = (value?: string | null) => value ? new Date(value).toLocaleDateString() : '—'

/** An open-ended window reads as "current"; a closed one names the day it ended. */
const fmtWindow = (from?: string | null, to?: string | null) =>
  `${fmtDate(from)} → ${to ? fmtDate(to) : 'open'}`

const today = () => new Date().toISOString().slice(0, 10)

function emptyTC() { return { code: '', description: '', tax_type: 'vat', rate: '', effective_from: today(), effective_to: '' } }
function emptyVC() { return { tax_code_id: '', vat_code: '', description: '', vat_classification: 'regular', transaction_type: 'output_vat', relief_category: '', effective_from: today(), effective_to: '' } }
function emptyATC() { return { code: '', description: '', tax_category: 'ewt', rate: '', effective_from: today(), effective_to: '' } }
function emptyPT(cid: string) { return { company_id: cid, tax_code_id: '', pt_code: '', description: '', atc_id: '', rate: '', form_type: '2551Q' } }
/** The successor's own start date, its new rate, and — for VAT — the tax-code version that now holds the rate. */
function emptySuccession() { return { effective_from: today(), rate: '', tax_code_id: '', description: '' } }

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

  // Global statutory reference data is maintainer-only and closed by default
  // (MDP-01 Option A). `null` means the answer has not come back yet.
  const [canMaintain, setCanMaintain] = useState<boolean | null>(null)

  const [showForm, setShowForm] = useState(false)
  const [mode, setMode] = useState<Mode>('add')
  const [editId, setEditId] = useState<string | null>(null)
  /** A version that already priced a document has its code, rate and start frozen. */
  const [editUsed, setEditUsed] = useState(false)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [reason, setReason] = useState('')

  const [tcForm, setTcForm] = useState(emptyTC())
  const [vcForm, setVcForm] = useState(emptyVC())
  const [atcForm, setAtcForm] = useState(emptyATC())
  const [ptForm,  setPtForm]  = useState(emptyPT(''))
  const [succForm, setSuccForm] = useState(emptySuccession())
  /** The parent the VAT predecessor already points at — the one choice a successor may not repeat. */
  const [succPredecessorTaxCode, setSuccPredecessorTaxCode] = useState('')

  const cid = companyId || selectedCompany

  const fetchAll = async () => {
    supabase.from('tax_codes').select('*').order('code').order('effective_from').then(({ data }) => setTaxCodes((data || []) as unknown as TaxCode[]))
    supabase.from('vat_codes').select('*, tax_codes(code,rate)').order('vat_code').order('effective_from').then(({ data }) => setVatCodes((data as unknown as VatCode[]) || []))
    supabase.from('atc_codes').select('*').order('code').order('effective_from').then(({ data }) => setATCCodes((data || []) as unknown as ATCCode[]))
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
  }
  const fetchCompanyCodes = async (coid: string) => {
    if (!coid) return
    supabase.from('percentage_tax_codes').select('*, atc_codes(code), tax_codes(code)').eq('company_id', coid).order('pt_code').then(({ data }) => setPTCodes((data as unknown as PTCode[]) || []))
  }

  useEffect(() => { fetchAll() }, [])
  useEffect(() => { fetchCompanyCodes(cid) }, [cid])
  useEffect(() => {
    supabase.rpc('fn_is_bir_config_maintainer', {}).then(({ data, error }) =>
      setCanMaintain(error ? false : Boolean(data)))
  }, [])

  const resetForm = () => {
    setShowForm(false); setMode('add'); setEditId(null); setEditUsed(false)
    setSaved(false); setError(null); setReason('')
  }

  /**
   * Ask the database whether this version has priced anything before offering an
   * in-place edit. An unanswered question counts as used: a freeze is never
   * loosened on a guess.
   */
  const taxCodeUsed = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_tax_code_used', { p_tax_code_id: id })
    return error ? true : Boolean(data)
  }
  const vatCodeUsed = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_vat_code_used', { p_vat_code_id: id })
    return error ? true : Boolean(data)
  }
  const atcCodeUsed = async (id: string) => {
    const { data, error } = await supabase.rpc('fn_atc_code_used', { p_atc_id: id })
    return error ? true : Boolean(data)
  }

  const openAdd = () => {
    resetForm()
    setMode('add')
    if (tab === 'tax_codes') setTcForm(emptyTC())
    if (tab === 'vat_codes') setVcForm(emptyVC())
    if (tab === 'atc_codes') setAtcForm(emptyATC())
    if (tab === 'pt_codes')  setPtForm(emptyPT(cid))
    setShowForm(true)
  }

  const openSucceed = (id: string, current: { rate?: number; tax_code_id?: string; description: string }) => {
    resetForm()
    setMode('succeed')
    setEditId(id)
    setSuccPredecessorTaxCode(current.tax_code_id ?? '')
    setSuccForm({
      effective_from: today(),
      rate: current.rate === undefined ? '' : String(current.rate),
      tax_code_id: '',
      description: current.description,
    })
    setShowForm(true)
  }

  /**
   * Surface what the database actually said. The version guards and the RPCs
   * raise sentences meant to be read by the person maintaining the code, so they
   * are shown rather than replaced with a generic failure.
   */
  const fail = (message: string) => { setError(message); setSaving(false) }

  // ── Tax Codes ──────────────────────────────────────────────
  const openTC = async (r: TaxCode) => {
    resetForm()
    setMode('edit'); setEditId(r.id)
    setEditUsed(await taxCodeUsed(r.id))
    setTcForm({
      code: r.code, description: r.description, tax_type: r.tax_type, rate: String(r.rate),
      effective_from: r.effective_from?.slice(0, 10) ?? '', effective_to: r.effective_to?.slice(0, 10) ?? '',
    })
    setShowForm(true)
  }
  const saveTC = async () => {
    setSaving(true); setError(null)
    // Global tax reference is write-governed (MDP-01): mutate only through the RPC.
    const { error } = await supabase.rpc('fn_tax_code_upsert', {
      p_code: tcForm.code, p_description: tcForm.description, p_tax_type: tcForm.tax_type,
      p_rate: parseFloat(tcForm.rate), p_id: editId || undefined,
      p_effective_from: tcForm.effective_from || undefined,
      p_effective_to: tcForm.effective_to || undefined,
      p_reason: reason || 'tax setup: save tax code',
    })
    if (error) return fail(error.message)
    setSaved(true); fetchAll(); resetForm(); setSaving(false)
  }
  const succeedTC = async () => {
    setSaving(true); setError(null)
    const { error } = await supabase.rpc('fn_tax_code_succeed', {
      p_id: editId!, p_effective_from: succForm.effective_from, p_rate: parseFloat(succForm.rate),
      p_description: succForm.description || undefined,
      p_reason: reason || 'tax setup: new tax code version',
    })
    if (error) return fail(error.message)
    setSaved(true); fetchAll(); resetForm(); setSaving(false)
  }
  const toggleTC = async (r: TaxCode) => {
    const { error } = await supabase.rpc('fn_tax_code_set_active', {
      p_id: r.id, p_is_active: !r.is_active, p_reason: 'tax setup: toggle active',
    })
    if (error) setError(error.message)
    fetchAll()
  }

  // ── VAT Codes ─────────────────────────────────────────────
  const openVC = async (r: VatCode) => {
    resetForm()
    setMode('edit'); setEditId(r.id)
    setEditUsed(await vatCodeUsed(r.id))
    setVcForm({
      tax_code_id: r.tax_code_id, vat_code: r.vat_code, description: r.description,
      vat_classification: r.vat_classification, transaction_type: r.transaction_type,
      relief_category: r.relief_category || '',
      effective_from: r.effective_from?.slice(0, 10) ?? '', effective_to: r.effective_to?.slice(0, 10) ?? '',
    })
    setShowForm(true)
  }
  const saveVC = async () => {
    setSaving(true); setError(null)
    // Global VAT reference is write-governed (MDP-01): mutate only through the RPC.
    const { error } = await supabase.rpc('fn_vat_code_upsert', {
      p_tax_code_id: vcForm.tax_code_id, p_vat_code: vcForm.vat_code, p_description: vcForm.description,
      p_vat_classification: vcForm.vat_classification, p_transaction_type: vcForm.transaction_type,
      p_relief_category: vcForm.relief_category || undefined,
      p_id: editId || undefined,
      p_effective_from: vcForm.effective_from || undefined,
      p_effective_to: vcForm.effective_to || undefined,
      p_reason: reason || 'tax setup: save VAT code',
    })
    if (error) return fail(error.message)
    setSaved(true); fetchAll(); resetForm(); setSaving(false)
  }
  const succeedVC = async () => {
    setSaving(true); setError(null)
    const { error } = await supabase.rpc('fn_vat_code_succeed', {
      p_id: editId!, p_effective_from: succForm.effective_from,
      p_tax_code_id: succForm.tax_code_id,
      p_description: succForm.description || undefined,
      p_reason: reason || 'tax setup: new VAT code version',
    })
    if (error) return fail(error.message)
    setSaved(true); fetchAll(); resetForm(); setSaving(false)
  }
  const toggleVC = async (r: VatCode) => {
    const { error } = await supabase.rpc('fn_vat_code_set_active', {
      p_id: r.id, p_is_active: !r.is_active, p_reason: 'tax setup: toggle active',
    })
    if (error) setError(error.message)
    fetchAll()
  }

  // ── ATC Codes ─────────────────────────────────────────────
  const openATC = async (r: ATCCode) => {
    resetForm()
    setMode('edit'); setEditId(r.id)
    setEditUsed(await atcCodeUsed(r.id))
    setAtcForm({
      code: r.code, description: r.description, tax_category: r.tax_category, rate: String(r.rate),
      effective_from: r.effective_from?.slice(0, 10) ?? '', effective_to: r.effective_to?.slice(0, 10) ?? '',
    })
    setShowForm(true)
  }
  const saveATC = async () => {
    setSaving(true); setError(null)
    // Global ATC reference is write-governed (MDP-01): mutate only through the RPC.
    const { error } = await supabase.rpc('fn_atc_code_upsert', {
      p_code: atcForm.code, p_description: atcForm.description, p_tax_category: atcForm.tax_category,
      p_rate: parseFloat(atcForm.rate), p_id: editId || undefined,
      p_effective_from: atcForm.effective_from || undefined,
      p_effective_to: atcForm.effective_to || undefined,
      p_reason: reason || 'tax setup: save ATC code',
    })
    if (error) return fail(error.message)
    setSaved(true); fetchAll(); resetForm(); setSaving(false)
  }
  const succeedATC = async () => {
    setSaving(true); setError(null)
    const { error } = await supabase.rpc('fn_atc_code_succeed', {
      p_id: editId!, p_effective_from: succForm.effective_from, p_rate: parseFloat(succForm.rate),
      p_description: succForm.description || undefined,
      p_reason: reason || 'tax setup: new ATC version',
    })
    if (error) return fail(error.message)
    setSaved(true); fetchAll(); resetForm(); setSaving(false)
  }
  const toggleATC = async (r: ATCCode) => {
    const { error } = await supabase.rpc('fn_atc_code_set_active', {
      p_id: r.id, p_is_active: !r.is_active, p_reason: 'tax setup: toggle active',
    })
    if (error) setError(error.message)
    fetchAll()
  }

  // ── PT Codes ──────────────────────────────────────────────
  // Company-scoped, and outside MDP-01's global statutory surface: these are
  // written under the company's own admin policy, guarded by
  // trg_percentage_tax_code_version_rules and its history guard.
  const openPT = (r?: PTCode) => {
    resetForm()
    setMode(r ? 'edit' : 'add')
    setPtForm(r ? { company_id: r.company_id, tax_code_id: r.tax_code_id, pt_code: r.pt_code, description: r.description, atc_id: r.atc_id, rate: String(r.rate), form_type: r.form_type } : emptyPT(cid))
    setEditId(r?.id ?? null); setShowForm(true)
  }
  const savePT = async () => {
    setSaving(true); setError(null)
    const payload = { ...ptForm, rate: parseFloat(ptForm.rate) }
    const { error } = editId ? await supabase.from('percentage_tax_codes').update(payload).eq('id', editId) : await supabase.from('percentage_tax_codes').insert([payload])
    if (error) return fail(error.message)
    setSaved(true); fetchCompanyCodes(cid); resetForm(); setSaving(false)
  }
  const togglePT = async (r: PTCode) => {
    const { error } = await supabase.from('percentage_tax_codes').update({ is_active: !r.is_active }).eq('id', r.id)
    if (error) setError(error.message)
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
  // The three global families answer to the maintainer allowlist; PT codes answer
  // to the selected company.
  const mayWrite = needsCompany ? !!cid : canMaintain === true
  const versionMark = (superseded: string | null) => superseded
    ? <span title="This version supersedes an earlier one" className="ml-2 text-[10px] font-medium text-gray-400">v+</span>
    : null

  const successionNote = 'A statutory rate change is a succession, not an edit: the current version’s window closes and a successor starts the next day, so documents already posted keep the rate that priced them.'

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Tax Code Setup</h1>
        <p className="text-sm text-gray-500 mt-0.5">Configure Philippine tax codes, VAT, ATC, and percentage tax parameters</p>
      </div>

      {/* Authority notice: global statutory reference data is maintainer-only. */}
      {canMaintain === false && (
        <div className="bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 text-sm text-amber-900">
          <span className="font-medium">Read-only.</span> Tax, VAT and ATC codes are global statutory
          reference data, maintained only by a provisioned statutory-configuration maintainer. Your
          account is not on that list, so this page shows the codes but cannot change them.
        </div>
      )}

      {/* Tabs */}
      <div className="flex border-b border-gray-200 gap-0 overflow-x-auto">
        {TABS.map(t => (
          <button key={t.id} onClick={() => { setTab(t.id); resetForm(); setSearch(''); setFilterType('') }}
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
            {(tab === 'atc_codes' ? ATC_CATEGORIES : TAX_TYPES).map(t => <option key={t} value={t}>{t.toUpperCase()}</option>)}
          </select>
        )}
        {tab === 'vat_codes' && (
          <select value={filterType} onChange={e => setFilterType(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900">
            <option value="">All Classifications</option>
            {VAT_CLASSIFICATIONS.map(v => <option key={v} value={v}>{v.replace('_',' ')}</option>)}
          </select>
        )}
        <div className="flex-1" />
        <button onClick={openAdd} disabled={!mayWrite}
          className="px-4 py-1.5 bg-gray-900 text-white text-sm rounded-md hover:bg-gray-700 disabled:opacity-40 disabled:cursor-not-allowed">
          + Add {TABS.find(t => t.id === tab)?.label.replace(' Codes','').replace('Percentage Tax ','PT ')} Code
        </button>
      </div>

      {/* A failed toggle has no modal to report into. */}
      {error && !showForm && (
        <div className="bg-red-50 border border-red-200 rounded-lg px-4 py-3 text-sm text-red-800">{error}</div>
      )}

      {/* ── TAX CODES TABLE ── */}
      {tab === 'tax_codes' && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['Tax Code','Description','Type','Rate (%)','Effective','Status',''].map(h => <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtTax.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{r.code}{versionMark(r.supersedes_tax_code_id)}</td>
                  <td className="px-4 py-3 text-gray-700">{r.description}</td>
                  <td className="px-4 py-3"><span className="uppercase text-xs font-semibold text-indigo-700 bg-indigo-50 px-2 py-0.5 rounded">{r.tax_type}</span></td>
                  <td className="px-4 py-3 font-mono">{r.rate}%</td>
                  <td className="px-4 py-3 text-xs text-gray-600 whitespace-nowrap">{fmtWindow(r.effective_from, r.effective_to)}</td>
                  <td className="px-4 py-3">{badge(r.is_active)}</td>
                  <td className="px-4 py-3 text-right space-x-2 whitespace-nowrap">
                    <button onClick={() => openTC(r)} disabled={!mayWrite} className={act}>Edit</button>
                    <button onClick={() => openSucceed(r.id, { rate: r.rate, description: r.description })} disabled={!mayWrite} className={act} title={successionNote}>New version</button>
                    <button onClick={() => toggleTC(r)} disabled={!mayWrite} className={actMuted}>{r.is_active ? 'Deactivate' : 'Activate'}</button>
                  </td>
                </tr>
              ))}
              {!filtTax.length && <tr><td colSpan={7} className="px-4 py-8 text-center text-gray-400">No tax codes found</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {/* ── VAT CODES TABLE ── */}
      {tab === 'vat_codes' && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>{['VAT Code','Description','Classification','Rate','Transaction Type','RELIEF Cat','Effective','Status',''].map(h => <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtVAT.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{r.vat_code}{versionMark(r.supersedes_vat_code_id)}</td>
                  <td className="px-4 py-3 text-gray-700">{r.description}</td>
                  <td className="px-4 py-3">
                    <span className={`text-xs font-medium px-2 py-0.5 rounded ${r.vat_classification === 'regular' ? 'bg-blue-50 text-blue-700' : r.vat_classification === 'zero_rated' ? 'bg-yellow-50 text-yellow-700' : 'bg-gray-100 text-gray-600'}`}>
                      {r.vat_classification.replace('_',' ')}
                    </span>
                  </td>
                  <td className="px-4 py-3 font-mono">{r.tax_codes?.rate ?? '—'}%</td>
                  <td className="px-4 py-3 text-xs text-gray-600">{r.transaction_type.replace('_',' ')}</td>
                  <td className="px-4 py-3 font-mono text-xs">{r.relief_category || '—'}</td>
                  <td className="px-4 py-3 text-xs text-gray-600 whitespace-nowrap">{fmtWindow(r.effective_from, r.effective_to)}</td>
                  <td className="px-4 py-3">{badge(r.is_active)}</td>
                  <td className="px-4 py-3 text-right space-x-2 whitespace-nowrap">
                    <button onClick={() => openVC(r)} disabled={!mayWrite} className={act}>Edit</button>
                    <button onClick={() => openSucceed(r.id, { tax_code_id: r.tax_code_id, description: r.description })} disabled={!mayWrite} className={act} title={successionNote}>New version</button>
                    <button onClick={() => toggleVC(r)} disabled={!mayWrite} className={actMuted}>{r.is_active ? 'Deactivate' : 'Activate'}</button>
                  </td>
                </tr>
              ))}
              {!filtVAT.length && <tr><td colSpan={9} className="px-4 py-8 text-center text-gray-400">No VAT codes found</td></tr>}
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
                    <button onClick={() => openPT(r)} disabled={!mayWrite} className={act}>Edit</button>
                    <button onClick={() => togglePT(r)} disabled={!mayWrite} className={actMuted}>{r.is_active ? 'Deactivate' : 'Activate'}</button>
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
              <tr>{['ATC Code','Description','Tax Type','Rate (%)','Effective','Status','Deprecated',''].map(h => <th key={h} className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filtATC.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{r.code}{versionMark(r.supersedes_atc_code_id)}</td>
                  <td className="px-4 py-3 text-gray-700">{r.description}</td>
                  <td className="px-4 py-3"><span className="uppercase text-xs font-semibold text-indigo-700 bg-indigo-50 px-2 py-0.5 rounded">{r.tax_category}</span></td>
                  <td className="px-4 py-3 font-mono">{r.rate}%</td>
                  <td className="px-4 py-3 text-xs text-gray-600 whitespace-nowrap">{fmtWindow(r.effective_from, r.effective_to)}</td>
                  <td className="px-4 py-3">{badge(r.is_active)}</td>
                  <td className="px-4 py-3">
                    {r.deprecated_at ? (
                      <span title={r.deprecated_reason || undefined} className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-amber-100 text-amber-800">Deprecated</span>
                    ) : (
                      <span className="text-xs text-gray-400">—</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right space-x-2 whitespace-nowrap">
                    <button onClick={() => openATC(r)} disabled={!mayWrite} className={act}>Edit</button>
                    <button onClick={() => openSucceed(r.id, { rate: r.rate, description: r.description })} disabled={!mayWrite} className={act} title={successionNote}>New version</button>
                    <button onClick={() => toggleATC(r)} disabled={!mayWrite} className={actMuted}>{r.is_active ? 'Deactivate' : 'Activate'}</button>
                  </td>
                </tr>
              ))}
              {!filtATC.length && <tr><td colSpan={8} className="px-4 py-8 text-center text-gray-400">No ATC codes found</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {/* ── FORMS ── */}
      {showForm && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 space-y-4 max-h-[90vh] overflow-y-auto">

            {/* Succession — the governed edit, one transaction in the database */}
            {mode === 'succeed' && (
              <>
                <h2 className="text-base font-semibold text-gray-900">New version</h2>
                <p className="text-xs text-gray-500">{successionNote}</p>
                <div className={sec}>
                  <p className={hd}>Successor</p>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className={lbl}>Effective From *</label>
                      <input className={inp} type="date" value={succForm.effective_from} onChange={e => setSuccForm(f => ({ ...f, effective_from: e.target.value }))} />
                    </div>
                    {tab === 'vat_codes' ? (
                      <div><label className={lbl}>Tax Code Holding the New Rate *</label>
                        <select className={inp} value={succForm.tax_code_id} onChange={e => setSuccForm(f => ({ ...f, tax_code_id: e.target.value }))}>
                          <option value="">— select —</option>
                          {taxCodes.filter(t => t.tax_type === 'vat' && t.id !== succPredecessorTaxCode).map(t => <option key={t.id} value={t.id}>{t.code} — {t.rate}% (from {fmtDate(t.effective_from)})</option>)}
                        </select>
                        {/* A VAT code states no rate of its own; the tax code holds it, and one
                            VAT code may exist per tax-code version per direction. */}
                        <p className="mt-1 text-[11px] text-gray-500">Succeed the tax code first, then point this version at it.</p>
                      </div>
                    ) : (
                      <div><label className={lbl}>New Rate (%) *</label>
                        <input className={inp} type="number" step="0.01" value={succForm.rate} onChange={e => setSuccForm(f => ({ ...f, rate: e.target.value }))} />
                      </div>
                    )}
                  </div>
                  <div><label className={lbl}>Description</label><input className={inp} value={succForm.description} onChange={e => setSuccForm(f => ({ ...f, description: e.target.value }))} /></div>
                  <div><label className={lbl}>Reason *</label><input className={inp} value={reason} onChange={e => setReason(e.target.value)} placeholder="e.g. RR 3-2026 rate change" /></div>
                </div>
              </>
            )}

            {/* Tax code — add / in-place edit */}
            {mode !== 'succeed' && tab === 'tax_codes' && (
              <>
                <h2 className="text-base font-semibold text-gray-900">{mode === 'edit' ? 'Edit' : 'Add'} Tax Code</h2>
                {editUsed && <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-3 py-2">This version has already priced a posted document. Its code, type, rate and effective start are frozen — use <span className="font-medium">New version</span> to change the rate.</p>}
                <div className={sec}>
                  <p className={hd}>Tax Code Details</p>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className={lbl}>Tax Code *</label><input className={editUsed ? inpRO : inp} readOnly={editUsed} value={tcForm.code} onChange={e => setTcForm(f => ({ ...f, code: e.target.value }))} placeholder="e.g. VAT-12" /></div>
                    <div><label className={lbl}>Tax Type *</label>
                      <select className={editUsed ? inpRO : inp} disabled={editUsed} value={tcForm.tax_type} onChange={e => setTcForm(f => ({ ...f, tax_type: e.target.value }))}>
                        {TAX_TYPES.map(t => <option key={t} value={t}>{t.toUpperCase()}</option>)}
                      </select>
                    </div>
                  </div>
                  <div><label className={lbl}>Description *</label><input className={inp} value={tcForm.description} onChange={e => setTcForm(f => ({ ...f, description: e.target.value }))} /></div>
                  <div className="grid grid-cols-3 gap-4">
                    <div><label className={lbl}>Rate (%)*</label><input className={editUsed ? inpRO : inp} readOnly={editUsed} type="number" step="0.01" value={tcForm.rate} onChange={e => setTcForm(f => ({ ...f, rate: e.target.value }))} /></div>
                    <div><label className={lbl}>Effective From *</label><input className={editUsed ? inpRO : inp} readOnly={editUsed} type="date" value={tcForm.effective_from} onChange={e => setTcForm(f => ({ ...f, effective_from: e.target.value }))} /></div>
                    <div><label className={lbl}>Effective To</label><input className={inp} type="date" value={tcForm.effective_to} onChange={e => setTcForm(f => ({ ...f, effective_to: e.target.value }))} /></div>
                  </div>
                  <div><label className={lbl}>Reason</label><input className={inp} value={reason} onChange={e => setReason(e.target.value)} placeholder="recorded in the audit log" /></div>
                </div>
              </>
            )}

            {/* VAT code — add / in-place edit */}
            {mode !== 'succeed' && tab === 'vat_codes' && (
              <>
                <h2 className="text-base font-semibold text-gray-900">{mode === 'edit' ? 'Edit' : 'Add'} VAT Code</h2>
                {editUsed && <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-3 py-2">This version has already priced a posted document. Its code, tax code, classification, direction and effective start are frozen — use <span className="font-medium">New version</span> to change the rate.</p>}
                <div className={sec}>
                  <p className={hd}>VAT Code Details</p>
                  <div><label className={lbl}>Parent Tax Code *</label>
                    <select className={editUsed ? inpRO : inp} disabled={editUsed} value={vcForm.tax_code_id} onChange={e => setVcForm(f => ({ ...f, tax_code_id: e.target.value }))}>
                      <option value="">— select —</option>
                      {taxCodes.filter(t => t.tax_type === 'vat').map(t => <option key={t.id} value={t.id}>{t.code} — {t.description}</option>)}
                    </select>
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className={lbl}>VAT Code *</label><input className={editUsed ? inpRO : inp} readOnly={editUsed} value={vcForm.vat_code} onChange={e => setVcForm(f => ({ ...f, vat_code: e.target.value }))} placeholder="e.g. VAT-12" /></div>
                    <div><label className={lbl}>Transaction Type *</label>
                      <select className={editUsed ? inpRO : inp} disabled={editUsed} value={vcForm.transaction_type} onChange={e => setVcForm(f => ({ ...f, transaction_type: e.target.value }))}>
                        {TX_TYPES.map(t => <option key={t} value={t}>{t.replace('_',' ')}</option>)}
                      </select>
                    </div>
                  </div>
                  <div><label className={lbl}>Description *</label><input className={inp} value={vcForm.description} onChange={e => setVcForm(f => ({ ...f, description: e.target.value }))} /></div>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className={lbl}>VAT Classification *</label>
                      <select className={editUsed ? inpRO : inp} disabled={editUsed} value={vcForm.vat_classification} onChange={e => setVcForm(f => ({ ...f, vat_classification: e.target.value }))}>
                        {VAT_CLASSIFICATIONS.map(v => <option key={v} value={v}>{v.replace('_',' ')}</option>)}
                      </select>
                    </div>
                    <div><label className={lbl}>RELIEF Category</label>
                      <select className={inp} value={vcForm.relief_category} onChange={e => setVcForm(f => ({ ...f, relief_category: e.target.value }))}>
                        {RELIEF_CATS.map(c => <option key={c} value={c}>{c || '— none —'}</option>)}
                      </select>
                    </div>
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className={lbl}>Effective From *</label><input className={editUsed ? inpRO : inp} readOnly={editUsed} type="date" value={vcForm.effective_from} onChange={e => setVcForm(f => ({ ...f, effective_from: e.target.value }))} /></div>
                    <div><label className={lbl}>Effective To</label><input className={inp} type="date" value={vcForm.effective_to} onChange={e => setVcForm(f => ({ ...f, effective_to: e.target.value }))} /></div>
                  </div>
                  <div><label className={lbl}>Reason</label><input className={inp} value={reason} onChange={e => setReason(e.target.value)} placeholder="recorded in the audit log" /></div>
                </div>
              </>
            )}

            {/* ATC code — add / in-place edit */}
            {mode !== 'succeed' && tab === 'atc_codes' && (
              <>
                <h2 className="text-base font-semibold text-gray-900">{mode === 'edit' ? 'Edit' : 'Add'} ATC Code</h2>
                {editUsed && <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-3 py-2">This ATC has already been withheld against. Its code, tax category and rate are frozen — use <span className="font-medium">New version</span> to change the rate.</p>}
                <div className={sec}>
                  <p className={hd}>ATC Details</p>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className={lbl}>ATC Code *</label><input className={editUsed ? inpRO : inp} readOnly={editUsed} value={atcForm.code} onChange={e => setAtcForm(f => ({ ...f, code: e.target.value }))} placeholder="e.g. WC158" /></div>
                    <div><label className={lbl}>Tax Category *</label>
                      <select className={editUsed ? inpRO : inp} disabled={editUsed} value={atcForm.tax_category} onChange={e => setAtcForm(f => ({ ...f, tax_category: e.target.value }))}>
                        {ATC_CATEGORIES.map(t => <option key={t} value={t}>{t.toUpperCase()}</option>)}
                      </select>
                    </div>
                  </div>
                  <div><label className={lbl}>Description *</label><input className={inp} value={atcForm.description} onChange={e => setAtcForm(f => ({ ...f, description: e.target.value }))} /></div>
                  <div className="grid grid-cols-3 gap-4">
                    <div><label className={lbl}>Rate (%)*</label><input className={editUsed ? inpRO : inp} readOnly={editUsed} type="number" step="0.01" value={atcForm.rate} onChange={e => setAtcForm(f => ({ ...f, rate: e.target.value }))} /></div>
                    <div><label className={lbl}>Effective From *</label><input className={inp} type="date" value={atcForm.effective_from} onChange={e => setAtcForm(f => ({ ...f, effective_from: e.target.value }))} /></div>
                    <div><label className={lbl}>Effective To</label><input className={inp} type="date" value={atcForm.effective_to} onChange={e => setAtcForm(f => ({ ...f, effective_to: e.target.value }))} /></div>
                  </div>
                  <div><label className={lbl}>Reason</label><input className={inp} value={reason} onChange={e => setReason(e.target.value)} placeholder="recorded in the audit log" /></div>
                </div>
              </>
            )}

            {/* PT code — company-scoped */}
            {mode !== 'succeed' && tab === 'pt_codes' && (
              <>
                <h2 className="text-base font-semibold text-gray-900">{mode === 'edit' ? 'Edit' : 'Add'} Percentage Tax Code</h2>
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
                        {atcCodes.filter(a => a.tax_category === 'pt').map(a => <option key={a.id} value={a.id}>{a.code} — {a.description}</option>)}
                      </select>
                    </div>
                  </div>
                  <div><label className={lbl}>Description *</label><input className={inp} value={ptForm.description} onChange={e => setPtForm(f => ({ ...f, description: e.target.value }))} /></div>
                  <div className="grid grid-cols-2 gap-4">
                    <div><label className={lbl}>Rate (%) *</label><input className={inp} type="number" step="0.01" value={ptForm.rate} onChange={e => setPtForm(f => ({ ...f, rate: e.target.value }))} /></div>
                    <div><label className={lbl}>Form Type</label><input className={inp} value={ptForm.form_type} readOnly /></div>
                  </div>
                </div>
              </>
            )}

            {error && <p className="text-sm text-red-700 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</p>}

            <div className="flex justify-end gap-3">
              <button onClick={resetForm} className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button
                onClick={
                  mode === 'succeed'
                    ? (tab === 'tax_codes' ? succeedTC : tab === 'vat_codes' ? succeedVC : succeedATC)
                    : (tab === 'tax_codes' ? saveTC : tab === 'vat_codes' ? saveVC : tab === 'atc_codes' ? saveATC : savePT)
                }
                disabled={saving}
                className="px-4 py-2 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">
                {saving ? 'Saving…' : saved ? 'Saved!' : mode === 'succeed' ? 'Create version' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
