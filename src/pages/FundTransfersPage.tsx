import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'

type BankRef = { id: string; bank_name: string; account_number: string }
type FT = {
  id: string; company_id: string; branch_id: string | null
  ft_number: string; transfer_date: string
  from_account_id: string; to_account_id: string; amount: number
  reference_number: string | null; remarks: string | null; status: string
  from_acct?: { bank_name: string; account_number: string } | null
  to_acct?: { bank_name: string; account_number: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full disabled:bg-gray-50'

export default function FundTransfersPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<FT[]>([])
  const [banks, setBanks] = useState<BankRef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [form, setForm] = useState<Partial<FT> | null>(null)
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('fund_transfers')
      .select('*,from_acct:bank_accounts!from_account_id(bank_name,account_number),to_acct:bank_accounts!to_account_id(bank_name,account_number)')
      .eq('company_id', companyId).order('transfer_date', { ascending: false }).order('ft_number', { ascending: false })
    setRows((data as FT[]) || [])
    setLoading(false)
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('bank_accounts').select('id,bank_name,account_number').eq('company_id', companyId).eq('is_active', true).order('bank_name')
    setBanks((data as BankRef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const openNew = () => { setForm({ company_id: companyId, branch_id: branchId || null, transfer_date: today(), status: 'draft', amount: 0 }); setError(''); setMode('edit') }
  const openRow = (r: FT) => { setForm({ ...r }); setError(''); setMode(r.status === 'draft' ? 'edit' : 'view') }

  const requiredConfig = useMemo<ConfigField[]>(() => [], [])
  const readiness = useTransactionReadiness({
    companyId,
    branchId: form?.branch_id || branchId,
    documentCode: 'FT',
    postingDate: form?.transfer_date || today(),
    requiredConfig,
  })
  const setupBlocked = readiness.loading || readiness.blockers.length > 0

  const save = async () => {
    if (!companyId || !form) return
    if (setupBlocked) { setError(readiness.loading ? 'Setup readiness is still being checked.' : readiness.blockers[0]); return }
    if (!form.from_account_id || !form.to_account_id || !form.amount) { setError('From, to and amount are required'); return }
    if (form.from_account_id === form.to_account_id) { setError('From and to accounts must differ'); return }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const base = {
        company_id: companyId, branch_id: form.branch_id || branchId || null,
        transfer_date: form.transfer_date || today(), from_account_id: form.from_account_id,
        to_account_id: form.to_account_id, amount: Number(form.amount),
        reference_number: form.reference_number || null, remarks: form.remarks || null, updated_by: uid,
      }
      if (form.id) {
        const { error: e } = await supabase.from('fund_transfers').update(base).eq('id', form.id)
        if (e) throw e
      } else {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', { p_company_id: companyId, p_branch_id: branchId, p_document_code: 'FT' })
        if (ne || !num) throw new Error(ne?.message || 'No number series for FT. Configure in Number Series setup.')
        const { error: e } = await supabase.from('fund_transfers').insert([{ ...base, ft_number: num as string, status: 'draft', created_by: uid }])
        if (e) throw e
      }
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false) }
  }

  const post = async (id: string) => {
    setBusy(true); setError('')
    try {
      const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'FT', p_source_doc_id: id })
      if (previewError) throw new Error(`Fund Transfer is not ready to post: ${previewError.message}`)
      const { error: e } = await supabase.rpc('fn_post_fund_transfer', { p_ft_id: id })
      if (e) throw e
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Post failed') } finally { setBusy(false) }
  }
  const cancel = async (id: string) => { const memo = prompt('Reason for cancellation (optional):') ?? undefined; setBusy(true); setError(''); try { const { error: e } = await supabase.rpc('fn_cancel_fund_transfer', { p_ft_id: id, p_memo: memo || undefined }); if (e) throw e; await load(); setMode('list') } catch (e) { setError((e as Error).message || 'Cancel failed') } finally { setBusy(false) } }
  const del = async (id: string) => { if (!confirm('Delete this draft fund transfer?')) return; setBusy(true); try { const { error: e } = await supabase.from('fund_transfers').delete().eq('id', id); if (e) throw e; await load() } catch (e) { setError((e as Error).message || 'Delete failed') } finally { setBusy(false) } }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Fund Transfers</span>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Fund Transfer</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No fund transfers</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['FT #','Date','From','To','Amount','Reference','Status',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className={`hover:bg-gray-50/60 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900 cursor-pointer" onClick={() => openRow(r)}>{r.ft_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.transfer_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.from_acct ? `${r.from_acct.bank_name} ${r.from_acct.account_number}` : '—'}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.to_acct ? `${r.to_acct.bank_name} ${r.to_acct.account_number}` : '—'}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-900">{fmt(r.amount)}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{r.reference_number || '—'}</td>
                <td className="px-3 py-2.5"><StatusBadge status={r.status} /></td>
                <td className="px-3 py-2.5 text-right whitespace-nowrap">
                  {r.status === 'draft' && <>
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-2">Edit</button>
                    <button disabled={busy} onClick={() => post(r.id)} className="text-xs text-blue-600 hover:text-blue-800 mr-2 disabled:opacity-50">Post</button>
                    <button disabled={busy} onClick={() => del(r.id)} className="text-xs text-red-600 hover:text-red-800 disabled:opacity-50">Delete</button>
                  </>}
                  {r.status === 'posted' && <>
                    <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900 mr-2">View</button>
                    <button disabled={busy} onClick={() => cancel(r.id)} className="text-xs text-red-600 hover:text-red-800 disabled:opacity-50">Cancel</button>
                  </>}
                  {r.status === 'cancelled' && <button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900">View</button>}
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
        <span className="text-sm font-semibold text-gray-700">{form?.ft_number || 'New Fund Transfer'}</span>
        {form?.status && <StatusBadge status={form.status} />}
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          {!ro && <button onClick={save} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving…' : 'Save Draft'}</button>}
          {!ro && form?.id && <button onClick={() => post(form.id!)} disabled={busy} className="px-3 py-1.5 border border-blue-300 text-blue-600 rounded text-sm hover:bg-blue-50 disabled:opacity-50">Post</button>}
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        {!ro && <SetupReadinessBanner readiness={readiness} />}
        <div className="bg-white border border-gray-200 rounded-lg p-5 grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-3xl">
          <Field label="Transfer Date *"><input type="date" disabled={ro} className={inputCls} value={form?.transfer_date || today()} onChange={e => setForm(f => ({ ...f, transfer_date: e.target.value }))} /></Field>
          <Field label="Amount *"><input type="number" disabled={ro} className={inputCls} value={form?.amount ?? 0} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} /></Field>
          <Field label="From Account *"><select disabled={ro} className={inputCls} value={form?.from_account_id || ''} onChange={e => setForm(f => ({ ...f, from_account_id: e.target.value }))}>
            <option value="">— select —</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select></Field>
          <Field label="To Account *"><select disabled={ro} className={inputCls} value={form?.to_account_id || ''} onChange={e => setForm(f => ({ ...f, to_account_id: e.target.value }))}>
            <option value="">— select —</option>{banks.filter(b => b.id !== form?.from_account_id).map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select></Field>
          <Field label="Reference Number"><input disabled={ro} className={inputCls} value={form?.reference_number || ''} onChange={e => setForm(f => ({ ...f, reference_number: e.target.value }))} /></Field>
          <Field label="Remarks"><input disabled={ro} className={inputCls} value={form?.remarks || ''} onChange={e => setForm(f => ({ ...f, remarks: e.target.value }))} /></Field>
        </div>
        {form?.id && (
          <div className="mt-4 max-w-5xl">
            <GLImpactPanel companyId={companyId} sourceDocType="FT" sourceDocId={form.id} previewRows={[]} />
          </div>
        )}
      </div>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="flex flex-col gap-1"><label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>{children}</div>
}
