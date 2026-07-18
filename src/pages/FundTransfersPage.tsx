import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditEvidenceBlock, StatusBadge } from '@/components/ui/shared'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type BankRef = { id: string; bank_name: string; account_number: string }
type FT = {
  id: string; company_id: string; branch_id: string | null
  ft_number: string; transfer_date: string
  from_account_id: string; to_account_id: string; amount: number
  reference_number: string | null; remarks: string | null; status: string
  created_at?: string | null; updated_at?: string | null; posted_at?: string | null
  from_acct?: { bank_name: string; account_number: string } | null
  to_acct?: { bank_name: string; account_number: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const formatDateTime = (value?: string | null) => value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'
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
  const auditFacts = form?.id ? [
    { label: 'Created', value: formatDateTime(form.created_at) },
    { label: 'Last edited', value: formatDateTime(form.updated_at) },
    { label: 'Posted', value: formatDateTime(form.posted_at) },
    { label: 'Status', value: form.status || 'draft' },
    { label: 'Lock status', value: form.status === 'draft' ? 'Draft editable' : 'Frozen by lifecycle controls' },
  ] : []

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
    <LegacyTransactionWorkspace title="Fund Transfer" family="banking" pattern="C" posting
      documentNo={form?.ft_number} status={form?.status} identity={form?.from_acct?.bank_name}
      financialFacts={[{ label: 'Transfer Amount', value: fmt(Number(form?.amount || 0)) }]}
      contextFacts={[{ label: 'Source Account', value: form?.from_acct ? `${form.from_acct.bank_name} ${form.from_acct.account_number}` : 'Not selected' }, { label: 'Destination Account', value: form?.to_acct ? `${form.to_acct.bank_name} ${form.to_acct.account_number}` : 'Not selected' }, { label: 'Transfer Date', value: form?.transfer_date || 'Not assigned' }, { label: 'Reference', value: form?.reference_number || 'Not assigned' }]}
      sourceDocType="FT" sourceDocId={form?.id} auditTable="fund_transfers"
      actions={[
        { key: 'cancel', label: 'Cancel', onClick: () => setMode('list'), hidden: ro },
        { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: save, disabled: saving || setupBlocked, hidden: ro, variant: 'primary' },
        { key: 'post', label: 'Post', onClick: () => post(form?.id || ''), disabled: busy || setupBlocked, hidden: ro || !form?.id, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'date', label: 'Transfer Date *', card: 0, content: <input type="date" disabled={ro} className={`${inputCls} pxl-input`} value={form?.transfer_date || today()} onChange={e => setForm(f => ({ ...f, transfer_date: e.target.value }))} /> },
        { key: 'number', label: 'Document Number', card: 0, content: <div className="pxl-readonly-field">{form?.ft_number || 'Generated on save'}</div> },
        { key: 'from', label: 'From Account *', card: 1, span: 2, content: <select disabled={ro} className={`${inputCls} pxl-input`} value={form?.from_account_id || ''} onChange={e => setForm(f => ({ ...f, from_account_id: e.target.value }))}><option value="">— select —</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select> },
        { key: 'to', label: 'To Account *', card: 2, span: 2, content: <select disabled={ro} className={`${inputCls} pxl-input`} value={form?.to_account_id || ''} onChange={e => setForm(f => ({ ...f, to_account_id: e.target.value }))}><option value="">— select —</option>{banks.filter(b => b.id !== form?.from_account_id).map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select> },
        { key: 'reference', label: 'Reference Number', card: 2, span: 2, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.reference_number || ''} onChange={e => setForm(f => ({ ...f, reference_number: e.target.value }))} /> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{!ro && <SetupReadinessBanner readiness={readiness} />}</div>,
        gl: form?.id ? <GLImpactPanel companyId={companyId} sourceDocType="FT" sourceDocId={form.id} previewRows={[]} /> : undefined,
        audit: form?.id ? <AuditEvidenceBlock tableName="fund_transfers" recordId={form.id} facts={auditFacts} /> : undefined,
      }}
      onBack={() => setMode('list')} backLabel="Fund Transfers">
    <div className="overflow-x-auto">
      <div className="mb-2 flex items-center justify-between"><h2 className="pxl-section-title">Transfer Line</h2><span className="pxl-caption">Bank movement detail</span></div>
      <table className="pxl-data-grid w-full min-w-[560px]" aria-label="Fund transfer line"><thead><tr><th className="text-right">Amount</th><th className="text-left">Remarks</th></tr></thead><tbody><tr><td><input type="number" disabled={ro} className={`${inputCls} pxl-input text-right`} value={form?.amount ?? 0} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} /></td><td><input disabled={ro} className={`${inputCls} pxl-input`} value={form?.remarks || ''} onChange={e => setForm(f => ({ ...f, remarks: e.target.value }))} /></td></tr></tbody></table>
    </div>
    </LegacyTransactionWorkspace>
  )
}
