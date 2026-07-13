import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditTrailSection, StatusBadge } from '@/components/ui/shared'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'

type BankRef = { id: string; bank_name: string; account_number: string }
type COARef = { id: string; account_code: string; account_name: string }
type ATCCode = { id: string; code: string; description: string; rate: number }
type SupplierRef = { id: string; supplier_code: string; registered_name: string; tin: string }
type CV = {
  id: string; company_id: string; branch_id: string | null
  cv_number: string; voucher_date: string; bank_account_id: string
  check_number: string; check_date: string; payee: string; payee_tin: string | null
  supplier_id: string | null; ewt_tax_base: number | null; ewt_variance_reason: string | null
  total_gross_amount: number; total_ewt_amount: number; net_check_amount: number
  atc_code_id: string | null; ewt_rate: number | null; particulars: string
  status: string; cleared_date: string | null; stale_date: string | null
  created_at?: string; updated_at?: string; posted_at?: string | null
  bank_accounts?: { bank_name: string; account_number: string } | null
}

const EWT_VARIANCE_REASONS = [
  { value: 'rounding', label: 'Rounding' },
  { value: 'partial_non_taxable', label: 'Partially non-taxable payment' },
  { value: 'bir_ruling', label: 'BIR ruling' },
  { value: 'supplier_exempt', label: 'Supplier exemption' },
  { value: 'other_authorized', label: 'Other authorized basis' },
]
type CVLine = { _key: string; id?: string; expense_account_id: string; description: string; amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full disabled:bg-gray-50'
const newLine = (): CVLine => ({ _key: crypto.randomUUID(), expense_account_id: '', description: '', amount: 0 })

export default function CheckVouchersPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<CV[]>([])
  const [banks, setBanks] = useState<BankRef[]>([])
  const [coa, setCoa] = useState<COARef[]>([])
  const [atcCodes, setAtcCodes] = useState<ATCCode[]>([])
  const [suppliers, setSuppliers] = useState<SupplierRef[]>([])
  const [baseTouched, setBaseTouched] = useState(false)
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [form, setForm] = useState<Partial<CV> | null>(null)
  const [lines, setLines] = useState<CVLine[]>([newLine()])
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [fStatus, setFStatus] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('check_vouchers')
      .select('*,bank_accounts(bank_name,account_number)')
      .eq('company_id', companyId).order('voucher_date', { ascending: false }).order('cv_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    const { data } = await q
    setRows((data as CV[]) || [])
    setLoading(false)
  }, [companyId, fStatus])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [baRes, coaRes, atcRes, supRes] = await Promise.all([
      supabase.from('bank_accounts').select('id,bank_name,account_number').eq('company_id', companyId).eq('is_active', true).order('bank_name'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code'),
      supabase.from('atc_codes').select('id,code,description,rate').eq('is_active', true).order('code'),
      supabase.from('suppliers').select('id,supplier_code,registered_name,tin').eq('company_id', companyId).eq('is_active', true).order('registered_name'),
    ])
    setBanks((baRes.data as BankRef[]) || [])
    setCoa((coaRes.data as COARef[]) || [])
    setAtcCodes((atcRes.data as ATCCode[]) || [])
    setSuppliers((supRes.data as SupplierRef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const openNew = () => { setForm({ company_id: companyId, branch_id: branchId || null, voucher_date: today(), check_date: today(), status: 'draft', total_ewt_amount: 0 }); setLines([newLine()]); setBaseTouched(false); setError(''); setMode('edit') }
  const openRow = async (r: CV) => {
    setForm({ ...r }); setBaseTouched(r.ewt_tax_base != null); setError('')
    const { data } = await supabase.from('check_voucher_lines').select('*').eq('cv_id', r.id).order('line_number')
    const mapped: CVLine[] = (data || []).map((l) => {
      const row = l as { id: string; expense_account_id: string; description: string; amount: number }
      return { _key: row.id, id: row.id, expense_account_id: row.expense_account_id, description: row.description, amount: Number(row.amount) }
    })
    setLines(mapped.length ? mapped : [newLine()])
    setMode(r.status === 'draft' ? 'edit' : 'view')
  }

  const totalGross = lines.reduce((s, l) => s + (Number(l.amount) || 0), 0)
  const ewt = Number(form?.total_ewt_amount) || 0
  const netCheck = totalGross - ewt
  // Explicit EWT base auto-tracks the gross voucher total until manually overridden
  const ewtBase = ewt > 0 ? (baseTouched && form?.ewt_tax_base != null ? Number(form.ewt_tax_base) : totalGross) : null
  const atcRate = form?.ewt_rate != null ? Number(form.ewt_rate) : null
  const expectedEwt = ewtBase != null && atcRate ? Math.round(ewtBase * atcRate) / 100 : null
  const varianceNeeded = ewt > 0 && expectedEwt != null && Math.abs(expectedEwt - ewt) > 0.02

  const pickAtc = (id: string) => {
    const a = atcCodes.find(x => x.id === id)
    setForm(f => ({ ...f, atc_code_id: id || null, ewt_rate: a ? Number(a.rate) : null }))
  }
  const pickSupplier = (id: string) => {
    const s = suppliers.find(x => x.id === id)
    setForm(f => ({ ...f, supplier_id: id || null, ...(s ? { payee: s.registered_name, payee_tin: s.tin } : {}) }))
  }

  const requiredConfig = useMemo<ConfigField[]>(() => [], [])
  const readiness = useTransactionReadiness({
    companyId,
    branchId: form?.branch_id || branchId,
    documentCode: 'CV',
    postingDate: form?.voucher_date || today(),
    requiredConfig,
  })
  const setupBlocked = readiness.loading || readiness.blockers.length > 0

  const save = async () => {
    if (!companyId || !form) return
    if (setupBlocked) { setError(readiness.loading ? 'Setup readiness is still being checked.' : readiness.blockers[0]); return }
    if (!form.bank_account_id || !form.check_number || !form.payee || !form.particulars) { setError('Bank account, check number, payee and particulars are required'); return }
    const valid = lines.filter(l => l.expense_account_id && Number(l.amount) > 0)
    if (valid.length === 0) { setError('At least one expense line with an account and amount is required'); return }
    if (netCheck <= 0) { setError('Net check amount must be greater than zero'); return }
    if (ewt > 0 && !form.atc_code_id) { setError('An ATC code is required when EWT is withheld'); return }
    if (ewt > 0 && !form.supplier_id) { setError('A supplier is required when EWT is withheld (Form 2307 traceability)'); return }
    if (varianceNeeded && !form.ewt_variance_reason) { setError(`EWT ${fmt(ewt)} does not match the ATC rate on base ${fmt(ewtBase ?? 0)} (expected ${fmt(expectedEwt ?? 0)}). Select a variance reason.`); return }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const base = {
        company_id: companyId, branch_id: form.branch_id || branchId || null,
        voucher_date: form.voucher_date || today(), bank_account_id: form.bank_account_id,
        check_number: form.check_number, check_date: form.check_date || today(),
        payee: form.payee, payee_tin: form.payee_tin || null,
        supplier_id: form.supplier_id || null,
        total_gross_amount: totalGross, total_ewt_amount: ewt,
        atc_code_id: form.atc_code_id || null, ewt_rate: form.ewt_rate ?? null,
        ewt_tax_base: ewtBase, ewt_variance_reason: varianceNeeded ? form.ewt_variance_reason || null : null,
        particulars: form.particulars, updated_by: uid,
      }
      let cvId = form.id
      if (cvId) {
        const { error: e } = await supabase.from('check_vouchers').update(base).eq('id', cvId)
        if (e) throw e
      } else {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', { p_company_id: companyId, p_branch_id: branchId, p_document_code: 'CV' })
        if (ne || !num) throw new Error(ne?.message || 'No number series for CV. Configure in Number Series setup.')
        const { data: ins, error: e } = await supabase.from('check_vouchers').insert([{ ...base, cv_number: num as string, status: 'draft', created_by: uid }]).select('id').single()
        if (e) throw e
        cvId = (ins as { id: string }).id
      }
      await supabase.from('check_voucher_lines').delete().eq('cv_id', cvId)
      const linePayload = valid.map((l, i) => ({
        cv_id: cvId, company_id: companyId, line_number: i + 1,
        expense_account_id: l.expense_account_id, description: l.description, amount: Number(l.amount),
        created_by: uid, updated_by: uid,
      }))
      const { error: le } = await supabase.from('check_voucher_lines').insert(linePayload)
      if (le) throw le
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false) }
  }

  const doRpc = async (fn: 'fn_post_check_voucher' | 'fn_cancel_check_voucher', id: string, confirmMsg?: string) => {
    if (confirmMsg && !confirm(confirmMsg)) return
    setBusy(true); setError('')
    try {
      if (fn === 'fn_post_check_voucher') {
        const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'CV', p_source_doc_id: id })
        if (previewError) throw new Error(`Check Voucher is not ready to post: ${previewError.message}`)
      }
      const { error: e } = await supabase.rpc(fn, { p_cv_id: id })
      if (e) throw e
      await load(); setMode('list')
    }
    catch (e) { setError((e as Error).message || 'Action failed') } finally { setBusy(false) }
  }
  const setStatus = async (id: string, status: string, extra: Record<string, unknown> = {}) => {
    setBusy(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const { error: e } = await supabase.from('check_vouchers').update({ status, updated_by: uid, ...extra }).eq('id', id)
      if (e) throw e; await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Action failed') } finally { setBusy(false) }
  }
  const markCleared = (id: string) => { const d = prompt('Cleared date (YYYY-MM-DD):', today()); if (!d) return; setStatus(id, 'cleared', { cleared_date: d }) }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Check Vouchers</span>
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm">
          <option value="">All statuses</option>{['draft','posted','released','cleared','stale','cancelled'].map(s => <option key={s} value={s}>{s}</option>)}
        </select>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Check Voucher</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No check vouchers</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['CV #','Date','Bank','Check #','Check Date','Payee','Gross','EWT','Net','Status',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Gross','EWT','Net'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className={`hover:bg-gray-50/60 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900 cursor-pointer" onClick={() => openRow(r)}>{r.cv_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.voucher_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.bank_accounts ? `${r.bank_accounts.bank_name}` : '—'}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-700">{r.check_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.check_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700 max-w-[140px] truncate">{r.payee}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(r.total_gross_amount)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-blue-600">{fmt(r.total_ewt_amount)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(r.net_check_amount)}</td>
                <td className="px-3 py-2.5"><StatusBadge status={r.status} /></td>
                <td className="px-3 py-2.5 text-right whitespace-nowrap">
                  {r.status === 'draft' && <>
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-2">Edit</button>
                    <button disabled={busy} onClick={() => doRpc('fn_post_check_voucher', r.id)} className="text-xs text-blue-600 hover:text-blue-800 disabled:opacity-50">Post</button>
                  </>}
                  {r.status === 'posted' && <>
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-2">View</button>
                    <button disabled={busy} onClick={() => setStatus(r.id, 'released')} className="text-xs text-blue-600 hover:text-blue-800 mr-2 disabled:opacity-50">Release</button>
                    <button disabled={busy} onClick={() => doRpc('fn_cancel_check_voucher', r.id, 'Cancel and reverse this check voucher?')} className="text-xs text-red-600 hover:text-red-800 disabled:opacity-50">Cancel</button>
                  </>}
                  {r.status === 'released' && <>
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-2">View</button>
                    <button disabled={busy} onClick={() => markCleared(r.id)} className="text-xs text-green-600 hover:text-green-800 mr-2 disabled:opacity-50">Cleared</button>
                    <button disabled={busy} onClick={() => setStatus(r.id, 'stale', { stale_date: today() })} className="text-xs text-amber-600 hover:text-amber-800 mr-2 disabled:opacity-50">Stale</button>
                    <button disabled={busy} onClick={() => doRpc('fn_cancel_check_voucher', r.id, 'Cancel and reverse this check voucher?')} className="text-xs text-red-600 hover:text-red-800 disabled:opacity-50">Cancel</button>
                  </>}
                  {['cleared','stale','cancelled'].includes(r.status) && <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900">View</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )

  const ro = mode === 'view'
  return (
    <div className="flex flex-col h-full">
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-2">
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-semibold text-gray-700">{form?.cv_number || 'New Check Voucher'}</span>
        {form?.status && <StatusBadge status={form.status} />}
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          {!ro && <button onClick={save} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving…' : 'Save Draft'}</button>}
          {!ro && form?.id && <button onClick={() => doRpc('fn_post_check_voucher', form.id!)} disabled={busy} className="px-3 py-1.5 border border-blue-300 text-blue-600 rounded text-sm hover:bg-blue-50 disabled:opacity-50">Post</button>}
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        {!ro && <SetupReadinessBanner readiness={readiness} />}
        <div className="bg-white border border-gray-200 rounded-lg p-5 grid grid-cols-1 sm:grid-cols-3 gap-4 mb-4">
          <Field label="Voucher Date *"><input type="date" disabled={ro} className={inputCls} value={form?.voucher_date || today()} onChange={e => setForm(f => ({ ...f, voucher_date: e.target.value }))} /></Field>
          <Field label="Bank Account *"><select disabled={ro} className={inputCls} value={form?.bank_account_id || ''} onChange={e => setForm(f => ({ ...f, bank_account_id: e.target.value }))}>
            <option value="">— select —</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select></Field>
          <Field label="Check Number *"><input disabled={ro} className={inputCls} value={form?.check_number || ''} onChange={e => setForm(f => ({ ...f, check_number: e.target.value }))} /></Field>
          <Field label="Check Date *"><input type="date" disabled={ro} className={inputCls} value={form?.check_date || today()} onChange={e => setForm(f => ({ ...f, check_date: e.target.value }))} /></Field>
          <Field label="Supplier (required if EWT)"><select disabled={ro} className={inputCls} value={form?.supplier_id || ''} onChange={e => pickSupplier(e.target.value)}>
            <option value="">—</option>{suppliers.map(s => <option key={s.id} value={s.id}>{s.supplier_code} — {s.registered_name}</option>)}</select></Field>
          <Field label="Payee *"><input disabled={ro} className={inputCls} value={form?.payee || ''} onChange={e => setForm(f => ({ ...f, payee: e.target.value }))} /></Field>
          <Field label="Payee TIN"><input disabled={ro} className={inputCls} value={form?.payee_tin || ''} onChange={e => setForm(f => ({ ...f, payee_tin: e.target.value }))} /></Field>
          <Field label="ATC Code (if EWT)"><select disabled={ro} className={inputCls} value={form?.atc_code_id || ''} onChange={e => pickAtc(e.target.value)}>
            <option value="">—</option>{atcCodes.map(a => <option key={a.id} value={a.id}>{a.code} — {a.description}</option>)}</select></Field>
          <Field label="EWT Rate (%)"><input type="number" disabled className={inputCls} value={form?.ewt_rate ?? ''} readOnly /></Field>
          <Field label="EWT Base (defaults to gross)"><input type="number" disabled={ro} className={inputCls} value={ewtBase ?? ''} placeholder="—"
            onChange={e => { setBaseTouched(true); setForm(f => ({ ...f, ewt_tax_base: e.target.value === '' ? null : parseFloat(e.target.value) || 0 })) }} /></Field>
          <Field label="EWT Amount"><input type="number" disabled={ro} className={inputCls} value={form?.total_ewt_amount ?? 0} onChange={e => setForm(f => ({ ...f, total_ewt_amount: parseFloat(e.target.value) || 0 }))} /></Field>
          {varianceNeeded && (
            <Field label={`Variance Reason * (expected EWT ${fmt(expectedEwt ?? 0)})`}>
              <select disabled={ro} className={inputCls} value={form?.ewt_variance_reason || ''} onChange={e => setForm(f => ({ ...f, ewt_variance_reason: e.target.value || null }))}>
                <option value="">— select —</option>{EWT_VARIANCE_REASONS.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}</select>
            </Field>
          )}
          <Field label="Particulars *" full3><textarea disabled={ro} rows={2} className={inputCls} value={form?.particulars || ''} onChange={e => setForm(f => ({ ...f, particulars: e.target.value }))} /></Field>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg mb-4 overflow-x-auto">
          <div className="px-4 py-2.5 border-b border-gray-100"><span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Expense Distribution</span></div>
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200"><tr>
              {['Expense Account','Description','Amount',''].map(h => <th key={h} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
            </tr></thead>
            <tbody className="divide-y divide-gray-100">
              {lines.map(l => (
                <tr key={l._key}>
                  <td className="px-3 py-2"><select disabled={ro} value={l.expense_account_id} onChange={e => setLines(ls => ls.map(x => x._key === l._key ? { ...x, expense_account_id: e.target.value } : x))}
                    className="border border-gray-300 rounded px-2 py-1 text-xs w-56 focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50">
                    <option value="">— select —</option>{coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}</select></td>
                  <td className="px-3 py-2"><input disabled={ro} value={l.description} onChange={e => setLines(ls => ls.map(x => x._key === l._key ? { ...x, description: e.target.value } : x))}
                    className="border border-gray-300 rounded px-2 py-1 text-xs w-full focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" /></td>
                  <td className="px-3 py-2"><input type="number" disabled={ro} value={l.amount} onChange={e => setLines(ls => ls.map(x => x._key === l._key ? { ...x, amount: parseFloat(e.target.value) || 0 } : x))}
                    className="border border-gray-300 rounded px-2 py-1 text-xs w-28 text-right focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" /></td>
                  <td className="px-3 py-2">{!ro && lines.length > 1 && <button onClick={() => setLines(ls => ls.filter(x => x._key !== l._key))} className="text-gray-400 hover:text-red-500 text-xs px-1">✕</button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {!ro && <div className="px-4 py-2 border-t border-gray-100"><button onClick={() => setLines(ls => [...ls, newLine()])} className="text-xs text-gray-500 hover:text-gray-900 font-medium">+ Add Line</button></div>}
        </div>

        <div className="bg-white border border-gray-200 rounded-lg p-5 flex justify-end">
          <div className="grid grid-cols-2 gap-x-8 gap-y-1 text-sm min-w-[280px]">
            <span className="text-gray-500 text-xs">Total Gross</span><span className="text-right font-mono text-xs text-gray-900">{fmt(totalGross)}</span>
            <span className="text-gray-500 text-xs">EWT Withheld</span><span className="text-right font-mono text-xs text-blue-700">{fmt(ewt)}</span>
            <span className="text-gray-900 font-semibold border-t border-gray-200 pt-1 mt-1">Net Check Amount</span>
            <span className={`text-right font-mono font-bold border-t border-gray-200 pt-1 mt-1 ${netCheck <= 0 ? 'text-red-600' : 'text-gray-900'}`}>{fmt(netCheck)}</span>
          </div>
        </div>

        {form?.id && (
          <div className="mt-4">
            <GLImpactPanel companyId={companyId} sourceDocType="CV" sourceDocId={form.id} previewRows={[]} />
          </div>
        )}

        {form?.id && (
          <div className="mt-4 space-y-3">
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Audit Evidence</div>
              <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
                {[
                  { label: 'Created', value: fmtTs(form.created_at) },
                  { label: 'Last edited', value: fmtTs(form.updated_at) },
                  { label: 'Posted', value: fmtTs(form.posted_at) },
                  { label: 'Lock status', value: form.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
                ].map(fact => (
                  <div key={fact.label}>
                    <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{fact.label}</div>
                    <div className="mt-1 text-xs text-gray-700">{fact.value}</div>
                  </div>
                ))}
              </div>
            </div>
            <AuditTrailSection tableName="check_vouchers" recordId={form.id} />
          </div>
        )}
      </div>
    </div>
  )
}

function fmtTs(ts: string | null | undefined) {
  return ts ? new Date(ts).toLocaleString('en-PH', { dateStyle: 'medium', timeStyle: 'short' }) : '—'
}

function Field({ label, children, full3 }: { label: string; children: React.ReactNode; full3?: boolean }) {
  return <div className={`flex flex-col gap-1 ${full3 ? 'sm:col-span-3' : ''}`}>
    <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>{children}</div>
}
