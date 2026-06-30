import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

type FundRef = { id: string; fund_name: string }
type BankRef = { id: string; bank_name: string; account_number: string }
type PCVRow = { id: string; pcv_number: string; voucher_date: string; payee: string; purpose: string; amount: number }
type PCR = {
  id: string; company_id: string; branch_id: string | null; fund_id: string
  pcr_number: string; replenishment_date: string; bank_account_id: string | null
  check_number: string | null; total_amount: number; remarks: string | null; status: string
  petty_cash_funds?: { fund_name: string } | null
  bank_accounts?: { bank_name: string; account_number: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full disabled:bg-gray-50'

export default function PettyCashReplenishmentPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<PCR[]>([])
  const [funds, setFunds] = useState<FundRef[]>([])
  const [banks, setBanks] = useState<BankRef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [form, setForm] = useState<Partial<PCR> | null>(null)
  const [pcvs, setPcvs] = useState<PCVRow[]>([])
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('petty_cash_replenishments')
      .select('*,petty_cash_funds(fund_name),bank_accounts(bank_name,account_number)')
      .eq('company_id', companyId).order('replenishment_date', { ascending: false }).order('pcr_number', { ascending: false })
    setRows((data as PCR[]) || [])
    setLoading(false)
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [fRes, bRes] = await Promise.all([
      supabase.from('petty_cash_funds').select('id,fund_name').eq('company_id', companyId).eq('is_active', true).order('fund_name'),
      supabase.from('bank_accounts').select('id,bank_name,account_number').eq('company_id', companyId).eq('is_active', true).order('bank_name'),
    ])
    setFunds((fRes.data as FundRef[]) || [])
    setBanks((bRes.data as BankRef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const loadUnreplenished = useCallback(async (fundId: string) => {
    if (!fundId) { setPcvs([]); return }
    const { data } = await supabase.from('petty_cash_vouchers')
      .select('id,pcv_number,voucher_date,payee,purpose,amount')
      .eq('fund_id', fundId).eq('status', 'approved').is('replenishment_id', null).order('voucher_date')
    setPcvs((data as PCVRow[]) || [])
  }, [])

  const total = pcvs.reduce((s, p) => s + Number(p.amount), 0)

  const openNew = () => { setForm({ company_id: companyId, branch_id: branchId || null, replenishment_date: today(), status: 'draft' }); setPcvs([]); setError(''); setMode('edit') }
  const openRow = async (r: PCR) => {
    setForm({ ...r }); setError(''); setMode(r.status === 'draft' ? 'edit' : 'view')
    if (r.status === 'draft') await loadUnreplenished(r.fund_id)
    else {
      const { data } = await supabase.from('petty_cash_vouchers').select('id,pcv_number,voucher_date,payee,purpose,amount').eq('replenishment_id', r.id).order('voucher_date')
      setPcvs((data as PCVRow[]) || [])
    }
  }

  const pickFund = async (fundId: string) => { setForm(f => ({ ...f, fund_id: fundId })); await loadUnreplenished(fundId) }

  const save = async () => {
    if (!companyId || !form) return
    if (!form.fund_id || !form.bank_account_id) { setError('Fund and bank account are required'); return }
    if (total <= 0) { setError('No approved unreplenished vouchers for this fund'); return }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const base = {
        company_id: companyId, branch_id: form.branch_id || branchId || null, fund_id: form.fund_id,
        replenishment_date: form.replenishment_date || today(), bank_account_id: form.bank_account_id,
        check_number: form.check_number || null, total_amount: total, remarks: form.remarks || null, updated_by: uid,
      }
      if (form.id) {
        const { error: e } = await supabase.from('petty_cash_replenishments').update(base).eq('id', form.id)
        if (e) throw e
      } else {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', { p_company_id: companyId, p_branch_id: branchId, p_document_code: 'PCR' })
        if (ne || !num) throw new Error(ne?.message || 'No number series for PCR. Configure in Number Series setup.')
        const { error: e } = await supabase.from('petty_cash_replenishments').insert([{ ...base, pcr_number: num as string, status: 'draft', created_by: uid }])
        if (e) throw e
      }
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false) }
  }

  const post = async (id: string) => {
    setBusy(true); setError('')
    try {
      const { error: e } = await supabase.rpc('fn_post_petty_cash_replenishment', { p_pcr_id: id })
      if (e) throw e
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Post failed') } finally { setBusy(false) }
  }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Petty Cash Replenishment</span>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Replenishment</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No replenishments</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['PCR #','Date','Fund','Bank Account','Check #','Total','Status',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${h === 'Total' ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className={`hover:bg-gray-50/60 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900 cursor-pointer" onClick={() => openRow(r)}>{r.pcr_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.replenishment_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.petty_cash_funds?.fund_name || '—'}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{r.bank_accounts ? `${r.bank_accounts.bank_name} ${r.bank_accounts.account_number}` : '—'}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{r.check_number || '—'}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-900">{fmt(r.total_amount)}</td>
                <td className="px-3 py-2.5"><StatusBadge status={r.status} /></td>
                <td className="px-3 py-2.5 text-right whitespace-nowrap">
                  {r.status === 'draft' && <>
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-2">Edit</button>
                    <button disabled={busy} onClick={() => post(r.id)} className="text-xs text-blue-600 hover:text-blue-800 disabled:opacity-50">Post</button>
                  </>}
                  {r.status !== 'draft' && <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900">View</button>}
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
        <span className="text-sm font-semibold text-gray-700">{form?.pcr_number || 'New Replenishment'}</span>
        {form?.status && <StatusBadge status={form.status} />}
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          {!ro && <button onClick={save} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving…' : 'Save Draft'}</button>}
          {!ro && form?.id && <button onClick={() => post(form.id!)} disabled={busy} className="px-3 py-1.5 border border-blue-300 text-blue-600 rounded text-sm hover:bg-blue-50 disabled:opacity-50">Post</button>}
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg p-5 grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-3xl mb-4">
          <Field label="Fund *"><select disabled={ro} className={inputCls} value={form?.fund_id || ''} onChange={e => pickFund(e.target.value)}>
            <option value="">— select fund —</option>{funds.map(f => <option key={f.id} value={f.id}>{f.fund_name}</option>)}</select></Field>
          <Field label="Replenishment Date *"><input type="date" disabled={ro} className={inputCls} value={form?.replenishment_date || today()} onChange={e => setForm(f => ({ ...f, replenishment_date: e.target.value }))} /></Field>
          <Field label="Bank Account *"><select disabled={ro} className={inputCls} value={form?.bank_account_id || ''} onChange={e => setForm(f => ({ ...f, bank_account_id: e.target.value }))}>
            <option value="">— select bank —</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select></Field>
          <Field label="Check Number"><input disabled={ro} className={inputCls} value={form?.check_number || ''} onChange={e => setForm(f => ({ ...f, check_number: e.target.value }))} /></Field>
          <Field label="Remarks" full><input disabled={ro} className={inputCls} value={form?.remarks || ''} onChange={e => setForm(f => ({ ...f, remarks: e.target.value }))} /></Field>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden max-w-3xl">
          <div className="px-4 py-2.5 border-b border-gray-100 flex justify-between">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Vouchers to Replenish</span>
            <span className="text-xs font-mono font-bold text-gray-900">Total: {fmt(total)}</span>
          </div>
          {pcvs.length === 0 ? <div className="px-4 py-6 text-xs text-gray-400">{form?.fund_id ? 'No approved unreplenished vouchers for this fund.' : 'Select a fund to load vouchers.'}</div> : (
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200"><tr>
                {['PCV #','Date','Payee','Purpose','Amount'].map(h => <th key={h} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
              </tr></thead>
              <tbody className="divide-y divide-gray-100">
                {pcvs.map(p => (
                  <tr key={p.id}>
                    <td className="px-3 py-2 font-mono text-gray-900">{p.pcv_number}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{p.voucher_date}</td>
                    <td className="px-3 py-2 text-gray-700">{p.payee}</td>
                    <td className="px-3 py-2 text-gray-500 max-w-[200px] truncate">{p.purpose}</td>
                    <td className="px-3 py-2 text-right font-mono text-gray-900">{fmt(p.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  )
}

function Field({ label, children, full }: { label: string; children: React.ReactNode; full?: boolean }) {
  return <div className={`flex flex-col gap-1 ${full ? 'sm:col-span-2' : ''}`}>
    <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>{children}</div>
}
