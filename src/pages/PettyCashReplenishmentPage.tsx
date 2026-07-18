import { useState, useEffect, useCallback, useMemo } from 'react'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { AuditEvidenceBlock, StatusBadge } from '@/components/ui/shared'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type FundRef = { id: string; fund_name: string }
type BankRef = { id: string; bank_name: string; account_number: string }
type PCVRow = { id: string; pcv_number: string; voucher_date: string; payee: string; purpose: string; amount: number }
type PCR = {
  id: string; company_id: string; branch_id: string | null; fund_id: string
  pcr_number: string; replenishment_date: string; bank_account_id: string | null
  check_number: string | null; total_amount: number; remarks: string | null; status: string
  created_at?: string | null; updated_at?: string | null; posted_at?: string | null
  petty_cash_funds?: { fund_name: string } | null
  bank_accounts?: { bank_name: string; account_number: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const formatDateTime = (value?: string | null) => value ? new Date(value).toLocaleString('en-PH') : 'Not recorded'
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

  const requiredConfig = useMemo<ConfigField[]>(() => [], [])
  const readiness = useTransactionReadiness({
    companyId,
    branchId: form?.branch_id || branchId,
    documentCode: 'PCR',
    postingDate: form?.replenishment_date || today(),
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
      const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'PCR', p_source_doc_id: id })
      if (previewError) throw new Error(`Petty Cash Replenishment is not ready to post: ${previewError.message}`)
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
    <LegacyTransactionWorkspace title="Petty Cash Replenishment" family="banking" pattern="C" posting
      documentNo={form?.pcr_number} status={form?.status} identity={form?.petty_cash_funds?.fund_name}
      financialFacts={[{ label: 'Replenishment Amount', value: fmt(Number(form?.total_amount || 0)) }, { label: 'Vouchers Available', value: pcvs.length }]}
      contextFacts={[{ label: 'Fund', value: form?.petty_cash_funds?.fund_name || 'Not selected' }, { label: 'Replenishment Date', value: form?.replenishment_date || 'Not assigned' }, { label: 'Bank Account', value: form?.bank_accounts ? `${form.bank_accounts.bank_name} ${form.bank_accounts.account_number}` : 'Not selected' }, { label: 'Check Number', value: form?.check_number || 'Not assigned' }]}
      relatedFacts={[{ label: 'Petty Cash Vouchers', value: pcvs.length, hint: 'Eligible vouchers loaded for replenishment', to: '/petty-cash-vouchers' }]}
      sourceDocType="PCR" sourceDocId={form?.id} auditTable="petty_cash_replenishments"
      actions={[
        { key: 'cancel', label: 'Cancel', onClick: () => setMode('list'), hidden: ro },
        { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: save, disabled: saving || setupBlocked, hidden: ro, variant: 'primary' },
        { key: 'post', label: 'Post', onClick: () => post(form?.id || ''), disabled: busy || setupBlocked, hidden: ro || !form?.id, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'date', label: 'Replenishment Date *', card: 0, content: <input type="date" disabled={ro} className={`${inputCls} pxl-input`} value={form?.replenishment_date || today()} onChange={e => setForm(f => ({ ...f, replenishment_date: e.target.value }))} /> },
        { key: 'number', label: 'Document Number', card: 0, content: <div className="pxl-readonly-field">{form?.pcr_number || 'Generated on save'}</div> },
        { key: 'fund', label: 'Fund *', card: 1, span: 2, content: <select disabled={ro} className={`${inputCls} pxl-input`} value={form?.fund_id || ''} onChange={e => pickFund(e.target.value)}><option value="">— select fund —</option>{funds.map(f => <option key={f.id} value={f.id}>{f.fund_name}</option>)}</select> },
        { key: 'bank', label: 'Bank Account *', card: 2, span: 2, content: <select disabled={ro} className={`${inputCls} pxl-input`} value={form?.bank_account_id || ''} onChange={e => setForm(f => ({ ...f, bank_account_id: e.target.value }))}><option value="">— select bank —</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select> },
        { key: 'check', label: 'Check Number', card: 2, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.check_number || ''} onChange={e => setForm(f => ({ ...f, check_number: e.target.value }))} /> },
        { key: 'remarks', label: 'Remarks', card: 2, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.remarks || ''} onChange={e => setForm(f => ({ ...f, remarks: e.target.value }))} /> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{!ro && <SetupReadinessBanner readiness={readiness} />}</div>,
        gl: form?.id ? <GLImpactPanel companyId={companyId} sourceDocType="PCR" sourceDocId={form.id} previewRows={[]} /> : undefined,
        audit: form?.id ? <AuditEvidenceBlock tableName="petty_cash_replenishments" recordId={form.id} facts={auditFacts} /> : undefined,
      }}
      onBack={() => setMode('list')} backLabel="Petty Cash Replenishments">
    <div className="overflow-hidden">
          <div className="mb-2 flex justify-between">
            <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Vouchers to Replenish</span>
            <span className="text-xs font-mono font-bold text-gray-900">Total: {fmt(total)}</span>
          </div>
          {pcvs.length === 0 ? <div className="px-4 py-6 text-xs text-gray-400">{form?.fund_id ? 'No approved unreplenished vouchers for this fund.' : 'Select a fund to load vouchers.'}</div> : (
            <table className="pxl-data-grid w-full text-xs">
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
    </LegacyTransactionWorkspace>
  )
}
