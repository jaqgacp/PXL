import { useState, useEffect, useCallback, useMemo } from 'react'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditEvidenceBlock, StatusBadge } from '@/components/ui/shared'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type BankRef = { id: string; bank_name: string; account_number: string }
type COARef = { id: string; account_code: string; account_name: string }
type BA = {
  id: string; company_id: string; branch_id: string | null
  ba_number: string; adjustment_date: string; bank_account_id: string
  adjustment_type: string; amount: number; gl_account_id: string
  reference_number: string | null; description: string; status: string
  created_at?: string | null; updated_at?: string | null; posted_at?: string | null
  bank_accounts?: { bank_name: string; account_number: string } | null
}

const TYPE_LABELS: Record<string, string> = {
  bank_debit_memo: 'Bank Debit Memo', bank_credit_memo: 'Bank Credit Memo',
  interest_income: 'Interest Income', bank_charge: 'Bank Charge',
  other_debit: 'Other Debit', other_credit: 'Other Credit',
}
const TYPES = Object.keys(TYPE_LABELS)
const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const formatDateTime = (value?: string | null) => value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full disabled:bg-gray-50'

export default function BankAdjustmentsPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<BA[]>([])
  const [banks, setBanks] = useState<BankRef[]>([])
  const [coa, setCoa] = useState<COARef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [form, setForm] = useState<Partial<BA> | null>(null)
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('bank_adjustments')
      .select('*,bank_accounts(bank_name,account_number)')
      .eq('company_id', companyId).order('adjustment_date', { ascending: false }).order('ba_number', { ascending: false })
    setRows((data as BA[]) || [])
    setLoading(false)
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [baRes, coaRes] = await Promise.all([
      supabase.from('bank_accounts').select('id,bank_name,account_number').eq('company_id', companyId).eq('is_active', true).order('bank_name'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code'),
    ])
    setBanks((baRes.data as BankRef[]) || [])
    setCoa((coaRes.data as COARef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const openNew = () => { setForm({ company_id: companyId, branch_id: branchId || null, adjustment_date: today(), status: 'draft', adjustment_type: 'bank_charge', amount: 0 }); setError(''); setMode('edit') }
  const openRow = (r: BA) => { setForm({ ...r }); setError(''); setMode(r.status === 'draft' ? 'edit' : 'view') }

  const requiredConfig = useMemo<ConfigField[]>(() => [], [])
  const readiness = useTransactionReadiness({
    companyId,
    branchId: form?.branch_id || branchId,
    documentCode: 'BADJ',
    postingDate: form?.adjustment_date || today(),
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
    if (!form.bank_account_id || !form.adjustment_type || !form.amount || !form.gl_account_id || !form.description) {
      setError('Bank account, type, amount, GL account and description are required'); return
    }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const base = {
        company_id: companyId, branch_id: form.branch_id || branchId || null,
        adjustment_date: form.adjustment_date || today(), bank_account_id: form.bank_account_id,
        adjustment_type: form.adjustment_type, amount: Number(form.amount), gl_account_id: form.gl_account_id,
        reference_number: form.reference_number || null, description: form.description, updated_by: uid,
      }
      if (form.id) {
        const { error: e } = await supabase.from('bank_adjustments').update(base).eq('id', form.id)
        if (e) throw e
      } else {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', { p_company_id: companyId, p_branch_id: branchId, p_document_code: 'BADJ' })
        if (ne || !num) throw new Error(ne?.message || 'No number series for BADJ. Configure in Number Series setup.')
        const { error: e } = await supabase.from('bank_adjustments').insert([{ ...base, ba_number: num as string, status: 'draft', created_by: uid }])
        if (e) throw e
      }
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false) }
  }

  const post = async (id: string) => {
    setBusy(true); setError('')
    try {
      const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'BADJ', p_source_doc_id: id })
      if (previewError) throw new Error(`Bank Adjustment is not ready to post: ${previewError.message}`)
      const { error: e } = await supabase.rpc('fn_post_bank_adjustment', { p_ba_id: id })
      if (e) throw e
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Post failed') } finally { setBusy(false) }
  }
  const cancel = async (id: string) => { const memo = prompt('Reason for cancellation (optional):') ?? undefined; setBusy(true); setError(''); try { const { error: e } = await supabase.rpc('fn_cancel_bank_adjustment', { p_ba_id: id, p_memo: memo || undefined }); if (e) throw e; await load(); setMode('list') } catch (e) { setError((e as Error).message || 'Cancel failed') } finally { setBusy(false) } }
  const del = async (id: string) => { if (!confirm('Delete this draft adjustment?')) return; setBusy(true); try { const { error: e } = await supabase.from('bank_adjustments').delete().eq('id', id); if (e) throw e; await load() } catch (e) { setError((e as Error).message || 'Delete failed') } finally { setBusy(false) } }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Bank Adjustments</span>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Adjustment</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No bank adjustments</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['BA #','Date','Bank Account','Type','Amount','Description','Reference','Status',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className={`hover:bg-gray-50/60 ${r.status === 'cancelled' ? 'opacity-50' : ''}`}>
                <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900 cursor-pointer" onClick={() => openRow(r)}>{r.ba_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.adjustment_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.bank_accounts ? `${r.bank_accounts.bank_name} ${r.bank_accounts.account_number}` : '—'}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{TYPE_LABELS[r.adjustment_type] || r.adjustment_type}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-900">{fmt(r.amount)}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500 max-w-[180px] truncate">{r.description}</td>
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
    <LegacyTransactionWorkspace title="Bank Adjustment" family="banking" pattern="C" posting
      documentNo={form?.ba_number} status={form?.status} identity={form?.bank_accounts?.bank_name}
      financialFacts={[{ label: 'Adjustment Amount', value: fmt(Number(form?.amount || 0)) }, { label: 'Adjustment Type', value: form?.adjustment_type ? TYPE_LABELS[form.adjustment_type] || form.adjustment_type : 'Not selected' }]}
      contextFacts={[{ label: 'Bank Account', value: form?.bank_accounts ? `${form.bank_accounts.bank_name} ${form.bank_accounts.account_number}` : 'Not selected' }, { label: 'Adjustment Date', value: form?.adjustment_date || 'Not assigned' }, { label: 'Reference', value: form?.reference_number || 'Not assigned' }, { label: 'Description', value: form?.description || 'Not recorded' }]}
      sourceDocType="BADJ" sourceDocId={form?.id} auditTable="bank_adjustments"
      actions={[
        { key: 'cancel', label: 'Cancel', onClick: () => setMode('list'), hidden: ro },
        { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: save, disabled: saving || setupBlocked, hidden: ro, variant: 'primary' },
        { key: 'post', label: 'Post', onClick: () => post(form?.id || ''), disabled: busy || setupBlocked, hidden: ro || !form?.id, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'date', label: 'Adjustment Date *', card: 0, content: <input type="date" disabled={ro} className={`${inputCls} pxl-input`} value={form?.adjustment_date || today()} onChange={e => setForm(f => ({ ...f, adjustment_date: e.target.value }))} /> },
        { key: 'number', label: 'Document Number', card: 0, content: <div className="pxl-readonly-field">{form?.ba_number || 'Generated on save'}</div> },
        { key: 'bank', label: 'Bank Account *', card: 1, span: 2, content: <select disabled={ro} className={`${inputCls} pxl-input`} value={form?.bank_account_id || ''} onChange={e => setForm(f => ({ ...f, bank_account_id: e.target.value }))}><option value="">— select —</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select> },
        { key: 'type', label: 'Adjustment Type *', card: 2, content: <select disabled={ro} className={`${inputCls} pxl-input`} value={form?.adjustment_type || ''} onChange={e => setForm(f => ({ ...f, adjustment_type: e.target.value }))}>{TYPES.map(t => <option key={t} value={t}>{TYPE_LABELS[t]}</option>)}</select> },
        { key: 'reference', label: 'Reference Number', card: 2, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.reference_number || ''} onChange={e => setForm(f => ({ ...f, reference_number: e.target.value }))} /> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{!ro && <SetupReadinessBanner readiness={readiness} />}</div>,
        gl: form?.id ? <GLImpactPanel companyId={companyId} sourceDocType="BADJ" sourceDocId={form.id} previewRows={[]} /> : undefined,
        audit: form?.id ? <AuditEvidenceBlock tableName="bank_adjustments" recordId={form.id} facts={auditFacts} /> : undefined,
      }}
      onBack={() => setMode('list')} backLabel="Bank Adjustments">
    <div className="overflow-x-auto">
      <div className="mb-2 flex items-center justify-between"><h2 className="pxl-section-title">Adjustment Line</h2><span className="pxl-caption">One bank adjustment line</span></div>
      <table className="pxl-data-grid w-full min-w-[760px]" aria-label="Bank adjustment line"><thead><tr><th className="text-left">GL Account</th><th className="text-right">Amount</th><th className="text-left">Description</th></tr></thead><tbody><tr>
        <td><select disabled={ro} className={`${inputCls} pxl-input`} value={form?.gl_account_id || ''} onChange={e => setForm(f => ({ ...f, gl_account_id: e.target.value }))}><option value="">— select —</option>{coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}</select></td>
        <td><input type="number" disabled={ro} className={`${inputCls} pxl-input text-right`} value={form?.amount ?? 0} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} /></td>
        <td><input disabled={ro} className={`${inputCls} pxl-input`} value={form?.description || ''} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} /></td>
      </tr></tbody></table>
    </div>
    </LegacyTransactionWorkspace>
  )
}
