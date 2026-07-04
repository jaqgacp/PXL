import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

type COARef = { id: string; account_code: string; account_name: string }
type FundRef = { id: string; fund_name: string }
type PCV = {
  id: string; company_id: string; branch_id: string | null; fund_id: string
  pcv_number: string; voucher_date: string; payee: string; purpose: string
  expense_account_id: string; amount: number; receipt_number: string | null
  replenishment_id: string | null; status: string
  petty_cash_funds?: { fund_name: string } | null
  chart_of_accounts?: { account_code: string; account_name: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full disabled:bg-gray-50'

export default function PettyCashVouchersPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<PCV[]>([])
  const [funds, setFunds] = useState<FundRef[]>([])
  const [coa, setCoa] = useState<COARef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [form, setForm] = useState<Partial<PCV> | null>(null)
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [fStatus, setFStatus] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('petty_cash_vouchers')
      .select('*,petty_cash_funds(fund_name),chart_of_accounts(account_code,account_name)')
      .eq('company_id', companyId).order('voucher_date', { ascending: false }).order('pcv_number', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    const { data } = await q
    setRows((data as PCV[]) || [])
    setLoading(false)
  }, [companyId, fStatus])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [fRes, cRes] = await Promise.all([
      supabase.from('petty_cash_funds').select('id,fund_name').eq('company_id', companyId).eq('is_active', true).order('fund_name'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_active', true).in('account_type', ['expense', 'asset']).order('account_code'),
    ])
    setFunds((fRes.data as FundRef[]) || [])
    setCoa((cRes.data as COARef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const openNew = () => { setForm({ company_id: companyId, branch_id: branchId || null, voucher_date: today(), status: 'draft', amount: 0 }); setError(''); setMode('edit') }
  const openRow = (r: PCV) => { setForm({ ...r }); setError(''); setMode(r.status === 'draft' ? 'edit' : 'view') }

  const save = async () => {
    if (!companyId || !form) return
    if (!form.fund_id || !form.payee || !form.purpose || !form.expense_account_id || !form.amount) {
      setError('Fund, payee, purpose, expense account and amount are required'); return
    }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const base = {
        company_id: companyId, branch_id: form.branch_id || branchId || null, fund_id: form.fund_id,
        voucher_date: form.voucher_date || today(), payee: form.payee, purpose: form.purpose,
        expense_account_id: form.expense_account_id, amount: Number(form.amount),
        receipt_number: form.receipt_number || null, updated_by: uid,
      }
      if (form.id) {
        const { error: e } = await supabase.from('petty_cash_vouchers').update(base).eq('id', form.id)
        if (e) throw e
      } else {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', { p_company_id: companyId, p_branch_id: branchId, p_document_code: 'PCV' })
        if (ne || !num) throw new Error(ne?.message || 'No number series for PCV. Configure in Number Series setup.')
        const { error: e } = await supabase.from('petty_cash_vouchers').insert([{ ...base, pcv_number: num as string, status: 'draft', created_by: uid }])
        if (e) throw e
      }
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false) }
  }

  const runRpc = async (fn: 'fn_approve_petty_cash_voucher' | 'fn_cancel_petty_cash_voucher', id: string, confirmMsg?: string) => {
    if (confirmMsg && !confirm(confirmMsg)) return
    setBusy(true); setError('')
    try {
      const { error: e } = await supabase.rpc(fn, { p_pcv_id: id })
      if (e) throw e
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Action failed') } finally { setBusy(false) }
  }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Petty Cash Vouchers</span>
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm">
          <option value="">All statuses</option><option value="draft">Draft</option><option value="approved">Approved</option><option value="replenished">Replenished</option><option value="cancelled">Cancelled</option>
        </select>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New PCV</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No petty cash vouchers</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['PCV #','Date','Fund','Payee','Purpose','Expense Acct','Amount','Receipt','Status',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className={`hover:bg-gray-50/60 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900 cursor-pointer" onClick={() => openRow(r)}>{r.pcv_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.voucher_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.petty_cash_funds?.fund_name || '—'}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700 max-w-[140px] truncate">{r.payee}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500 max-w-[160px] truncate">{r.purpose}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.chart_of_accounts?.account_code || '—'}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-900">{fmt(r.amount)}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{r.receipt_number || '—'}</td>
                <td className="px-3 py-2.5"><StatusBadge status={r.status} /></td>
                <td className="px-3 py-2.5 text-right whitespace-nowrap">
                  {r.status === 'draft' && <>
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-2">Edit</button>
                    <button disabled={busy} onClick={() => runRpc('fn_approve_petty_cash_voucher', r.id)} className="text-xs text-blue-600 hover:text-blue-800 mr-2 disabled:opacity-50">Approve</button>
                    <button disabled={busy} onClick={() => runRpc('fn_cancel_petty_cash_voucher', r.id, 'Cancel this PCV?')} className="text-xs text-red-600 hover:text-red-800 disabled:opacity-50">Cancel</button>
                  </>}
                  {r.status === 'approved' && <>
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-2">View</button>
                    <button disabled={busy} onClick={() => runRpc('fn_cancel_petty_cash_voucher', r.id, 'Cancel this approved PCV? A reversing entry will be posted.')} className="text-xs text-red-600 hover:text-red-800 disabled:opacity-50">Cancel</button>
                  </>}
                  {(r.status === 'replenished' || r.status === 'cancelled') &&
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900">View</button>}
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
        <span className="text-sm font-semibold text-gray-700">{form?.pcv_number || 'New PCV'}</span>
        {form?.status && <StatusBadge status={form.status} />}
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          {!ro && <button onClick={save} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving…' : 'Save Draft'}</button>}
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg p-5 grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-3xl">
          <Field label="Fund *"><select disabled={ro} className={inputCls} value={form?.fund_id || ''} onChange={e => setForm(f => ({ ...f, fund_id: e.target.value }))}>
            <option value="">— select fund —</option>{funds.map(f => <option key={f.id} value={f.id}>{f.fund_name}</option>)}</select></Field>
          <Field label="Voucher Date *"><input type="date" disabled={ro} className={inputCls} value={form?.voucher_date || today()} onChange={e => setForm(f => ({ ...f, voucher_date: e.target.value }))} /></Field>
          <Field label="Payee *"><input disabled={ro} className={inputCls} value={form?.payee || ''} onChange={e => setForm(f => ({ ...f, payee: e.target.value }))} /></Field>
          <Field label="Receipt Number"><input disabled={ro} className={inputCls} value={form?.receipt_number || ''} onChange={e => setForm(f => ({ ...f, receipt_number: e.target.value }))} /></Field>
          <Field label="Expense Account *"><select disabled={ro} className={inputCls} value={form?.expense_account_id || ''} onChange={e => setForm(f => ({ ...f, expense_account_id: e.target.value }))}>
            <option value="">— select account —</option>{coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}</select></Field>
          <Field label="Amount *"><input type="number" disabled={ro} className={inputCls} value={form?.amount ?? 0} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} /></Field>
          <Field label="Purpose *" full><textarea disabled={ro} rows={2} className={inputCls} value={form?.purpose || ''} onChange={e => setForm(f => ({ ...f, purpose: e.target.value }))} /></Field>
        </div>
      </div>
    </div>
  )
}

function Field({ label, children, full }: { label: string; children: React.ReactNode; full?: boolean }) {
  return <div className={`flex flex-col gap-1 ${full ? 'sm:col-span-2' : ''}`}>
    <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>{children}</div>
}
