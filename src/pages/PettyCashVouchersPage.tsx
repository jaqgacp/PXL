import { useState, useEffect, useCallback, useMemo } from 'react'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditEvidenceBlock, StatusBadge } from '@/components/ui/shared'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type COARef = { id: string; account_code: string; account_name: string }
type FundRef = { id: string; fund_name: string }
type PCV = {
  id: string; company_id: string; branch_id: string | null; fund_id: string
  pcv_number: string; voucher_date: string; payee: string; purpose: string
  expense_account_id: string; amount: number; receipt_number: string | null
  replenishment_id: string | null; status: string
  created_at?: string | null; updated_at?: string | null; posted_at?: string | null
  petty_cash_funds?: { fund_name: string } | null
  chart_of_accounts?: { account_code: string; account_name: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const formatDateTime = (value?: string | null) => value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'
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

  const requiredConfig = useMemo<ConfigField[]>(() => [], [])
  const readiness = useTransactionReadiness({
    companyId,
    branchId: form?.branch_id || branchId,
    documentCode: 'PCV',
    postingDate: form?.voucher_date || today(),
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
      if (fn === 'fn_approve_petty_cash_voucher') {
        const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'PCV', p_source_doc_id: id })
        if (previewError) throw new Error(`Petty Cash Voucher is not ready to approve: ${previewError.message}`)
      }
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
    <LegacyTransactionWorkspace title="Petty Cash Voucher" family="banking" pattern="C" posting
      documentNo={form?.pcv_number} status={form?.status} identity={form?.payee}
      financialFacts={[{ label: 'Voucher Amount', value: fmt(Number(form?.amount || 0)) }, { label: 'Fund', value: form?.petty_cash_funds?.fund_name || 'Not selected' }]}
      contextFacts={[{ label: 'Payee', value: form?.payee || 'Not selected' }, { label: 'Voucher Date', value: form?.voucher_date || 'Not assigned' }, { label: 'Purpose', value: form?.purpose || 'Not recorded' }, { label: 'Receipt Number', value: form?.receipt_number || 'Not assigned' }]}
      sourceDocType="PCV" sourceDocId={form?.id} auditTable="petty_cash_vouchers"
      actions={[
        { key: 'cancel-edit', label: 'Cancel', onClick: () => setMode('list'), hidden: ro },
        { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: save, disabled: saving || setupBlocked, hidden: ro, variant: 'primary' },
        { key: 'approve', label: 'Approve', onClick: () => runRpc('fn_approve_petty_cash_voucher', form?.id || ''), disabled: busy || setupBlocked, hidden: ro || !form?.id || form.status !== 'draft', variant: 'primary' },
        { key: 'cancel-doc', label: 'Cancel Voucher', onClick: () => runRpc('fn_cancel_petty_cash_voucher', form?.id || '', 'Cancel this PCV?'), disabled: busy, hidden: !ro || !form?.id || !['draft', 'approved'].includes(form.status || ''), group: 'more', variant: 'danger' },
      ]}
      headerFields={[
        { key: 'date', label: 'Voucher Date *', card: 0, content: <input type="date" disabled={ro} className={`${inputCls} pxl-input`} value={form?.voucher_date || today()} onChange={e => setForm(f => ({ ...f, voucher_date: e.target.value }))} /> },
        { key: 'number', label: 'Document Number', card: 0, content: <div className="pxl-readonly-field">{form?.pcv_number || 'Generated on save'}</div> },
        { key: 'payee', label: 'Payee *', card: 1, span: 2, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.payee || ''} onChange={e => setForm(f => ({ ...f, payee: e.target.value }))} /> },
        { key: 'fund', label: 'Fund *', card: 2, span: 2, content: <select disabled={ro} className={`${inputCls} pxl-input`} value={form?.fund_id || ''} onChange={e => setForm(f => ({ ...f, fund_id: e.target.value }))}><option value="">— select fund —</option>{funds.map(f => <option key={f.id} value={f.id}>{f.fund_name}</option>)}</select> },
        { key: 'receipt', label: 'Receipt Number', card: 2, span: 2, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.receipt_number || ''} onChange={e => setForm(f => ({ ...f, receipt_number: e.target.value }))} /> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{!ro && <SetupReadinessBanner readiness={readiness} />}</div>,
        gl: form?.id ? <GLImpactPanel companyId={companyId} sourceDocType="PCV" sourceDocId={form.id} previewRows={[]} /> : undefined,
        audit: form?.id ? <AuditEvidenceBlock tableName="petty_cash_vouchers" recordId={form.id} facts={auditFacts} /> : undefined,
      }}
      onBack={() => setMode('list')} backLabel="Petty Cash Vouchers">
    <div className="overflow-x-auto">
      <div className="mb-2 flex items-center justify-between"><h2 className="pxl-section-title">Expense Line</h2><span className="pxl-caption">Petty-cash disbursement detail</span></div>
      <table className="pxl-data-grid w-full min-w-[760px]" aria-label="Petty cash voucher line"><thead><tr><th className="text-left">Expense Account</th><th className="text-right">Amount</th><th className="text-left">Purpose</th></tr></thead><tbody><tr><td><select disabled={ro} className={`${inputCls} pxl-input`} value={form?.expense_account_id || ''} onChange={e => setForm(f => ({ ...f, expense_account_id: e.target.value }))}><option value="">— select account —</option>{coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}</select></td><td><input type="number" disabled={ro} className={`${inputCls} pxl-input text-right`} value={form?.amount ?? 0} onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) || 0 }))} /></td><td><input disabled={ro} className={`${inputCls} pxl-input`} value={form?.purpose || ''} onChange={e => setForm(f => ({ ...f, purpose: e.target.value }))} /></td></tr></tbody></table>
    </div>
    </LegacyTransactionWorkspace>
  )
}
