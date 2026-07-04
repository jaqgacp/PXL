import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

type BranchRef = { id: string; branch_code: string; branch_name: string }
type BankRef = { id: string; bank_name: string; account_number: string; branch_id: string | null }
type COARef = { id: string; account_code: string; account_name: string }
type IBT = {
  id: string; company_id: string; ibt_number: string; transfer_date: string
  from_branch_id: string; to_branch_id: string
  from_account_id: string | null; to_account_id: string | null
  amount: number; intercompany_account_id: string | null
  reference_number: string | null; remarks: string | null; status: string
  from_branch?: { branch_code: string } | null
  to_branch?: { branch_code: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full disabled:bg-gray-50'

export default function InterBranchTransfersPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<IBT[]>([])
  const [branches, setBranches] = useState<BranchRef[]>([])
  const [banks, setBanks] = useState<BankRef[]>([])
  const [coa, setCoa] = useState<COARef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [form, setForm] = useState<Partial<IBT> | null>(null)
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('inter_branch_transfers')
      .select('*,from_branch:branches!from_branch_id(branch_code),to_branch:branches!to_branch_id(branch_code)')
      .eq('company_id', companyId).order('transfer_date', { ascending: false }).order('ibt_number', { ascending: false })
    setRows((data as IBT[]) || [])
    setLoading(false)
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [brRes, baRes, coaRes] = await Promise.all([
      supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true).order('branch_code'),
      supabase.from('bank_accounts').select('id,bank_name,account_number,branch_id').eq('company_id', companyId).eq('is_active', true).order('bank_name'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_active', true).order('account_code'),
    ])
    setBranches((brRes.data as BranchRef[]) || [])
    setBanks((baRes.data as BankRef[]) || [])
    setCoa((coaRes.data as COARef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const openNew = () => { setForm({ company_id: companyId, transfer_date: today(), status: 'draft', amount: 0 }); setError(''); setMode('edit') }
  const openRow = (r: IBT) => { setForm({ ...r }); setError(''); setMode(r.status === 'draft' ? 'edit' : 'view') }

  const save = async () => {
    if (!companyId || !form) return
    if (!form.from_branch_id || !form.to_branch_id || !form.amount) { setError('From branch, to branch and amount are required'); return }
    if (form.from_branch_id === form.to_branch_id) { setError('From and to branches must differ'); return }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const base = {
        company_id: companyId, transfer_date: form.transfer_date || today(),
        from_branch_id: form.from_branch_id, to_branch_id: form.to_branch_id,
        from_account_id: form.from_account_id || null, to_account_id: form.to_account_id || null,
        amount: Number(form.amount), intercompany_account_id: form.intercompany_account_id || null,
        reference_number: form.reference_number || null, remarks: form.remarks || null, updated_by: uid,
      }
      if (form.id) {
        const { error: e } = await supabase.from('inter_branch_transfers').update(base).eq('id', form.id)
        if (e) throw e
      } else {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', { p_company_id: companyId, p_branch_id: form.from_branch_id, p_document_code: 'IBT' })
        if (ne || !num) throw new Error(ne?.message || 'No number series for IBT. Configure in Number Series setup.')
        const { error: e } = await supabase.from('inter_branch_transfers').insert([{ ...base, ibt_number: num as string, status: 'draft', created_by: uid }])
        if (e) throw e
      }
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false) }
  }

  const post = async (id: string) => { setBusy(true); setError(''); try { const { error: e } = await supabase.rpc('fn_post_inter_branch_transfer', { p_ibt_id: id }); if (e) throw e; await load(); setMode('list') } catch (e) { setError((e as Error).message || 'Post failed') } finally { setBusy(false) } }
  const cancel = async (id: string) => { const memo = prompt('Reason for cancellation (optional):') ?? undefined; setBusy(true); setError(''); try { const { error: e } = await supabase.rpc('fn_cancel_inter_branch_transfer', { p_ibt_id: id, p_memo: memo || undefined }); if (e) throw e; await load(); setMode('list') } catch (e) { setError((e as Error).message || 'Cancel failed') } finally { setBusy(false) } }
  const del = async (id: string) => { if (!confirm('Delete this draft transfer?')) return; setBusy(true); try { const { error: e } = await supabase.from('inter_branch_transfers').delete().eq('id', id); if (e) throw e; await load() } catch (e) { setError((e as Error).message || 'Delete failed') } finally { setBusy(false) } }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Inter-Branch Transfers</span>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Transfer</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No inter-branch transfers</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['IBT #','Date','From Branch','To Branch','Amount','Reference','Status',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className={`hover:bg-gray-50/60 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900 cursor-pointer" onClick={() => openRow(r)}>{r.ibt_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.transfer_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.from_branch?.branch_code || '—'}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.to_branch?.branch_code || '—'}</td>
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
  const fromBanks = banks.filter(b => !form?.from_branch_id || b.branch_id === form.from_branch_id || b.branch_id == null)
  const toBanks = banks.filter(b => !form?.to_branch_id || b.branch_id === form.to_branch_id || b.branch_id == null)
  return (
    <div className="flex flex-col h-full">
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-2">
        <button onClick={() => setMode('list')} className="text-sm text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-semibold text-gray-700">{form?.ibt_number || 'New Inter-Branch Transfer'}</span>
        {form?.status && <StatusBadge status={form.status} />}
        <div className="ml-auto flex items-center gap-2">
          {error && <span className="text-xs text-red-600 max-w-xs truncate">{error}</span>}
          {!ro && <button onClick={save} disabled={saving} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving…' : 'Save Draft'}</button>}
          {!ro && form?.id && <button onClick={() => post(form.id!)} disabled={busy} className="px-3 py-1.5 border border-blue-300 text-blue-600 rounded text-sm hover:bg-blue-50 disabled:opacity-50">Post</button>}
        </div>
      </div>
      <div className="flex-1 overflow-auto bg-gray-50 px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg p-5 grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-3xl">
          <Field label="Transfer Date *"><input type="date" disabled={ro} className={inputCls} value={form?.transfer_date || today()} onChange={e => setForm(f => ({ ...f, transfer_date: e.target.value }))} /></Field>
          <Field label="Amount *"><input type="number" disabled={ro} className={inputCls} value={form?.amount ?? 0} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} /></Field>
          <Field label="From Branch *"><select disabled={ro} className={inputCls} value={form?.from_branch_id || ''} onChange={e => setForm(f => ({ ...f, from_branch_id: e.target.value }))}>
            <option value="">— select —</option>{branches.map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}</select></Field>
          <Field label="To Branch *"><select disabled={ro} className={inputCls} value={form?.to_branch_id || ''} onChange={e => setForm(f => ({ ...f, to_branch_id: e.target.value }))}>
            <option value="">— select —</option>{branches.filter(b => b.id !== form?.from_branch_id).map(b => <option key={b.id} value={b.id}>{b.branch_code} — {b.branch_name}</option>)}</select></Field>
          <Field label="From Account"><select disabled={ro} className={inputCls} value={form?.from_account_id || ''} onChange={e => setForm(f => ({ ...f, from_account_id: e.target.value }))}>
            <option value="">— optional —</option>{fromBanks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select></Field>
          <Field label="To Account"><select disabled={ro} className={inputCls} value={form?.to_account_id || ''} onChange={e => setForm(f => ({ ...f, to_account_id: e.target.value }))}>
            <option value="">— optional —</option>{toBanks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select></Field>
          <Field label="Intercompany Account"><select disabled={ro} className={inputCls} value={form?.intercompany_account_id || ''} onChange={e => setForm(f => ({ ...f, intercompany_account_id: e.target.value }))}>
            <option value="">— optional —</option>{coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}</select></Field>
          <Field label="Reference Number"><input disabled={ro} className={inputCls} value={form?.reference_number || ''} onChange={e => setForm(f => ({ ...f, reference_number: e.target.value }))} /></Field>
          <Field label="Remarks" full><input disabled={ro} className={inputCls} value={form?.remarks || ''} onChange={e => setForm(f => ({ ...f, remarks: e.target.value }))} /></Field>
        </div>
      </div>
    </div>
  )
}

function Field({ label, children, full }: { label: string; children: React.ReactNode; full?: boolean }) {
  return <div className={`flex flex-col gap-1 ${full ? 'sm:col-span-2' : ''}`}>
    <label className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">{label}</label>{children}</div>
}
