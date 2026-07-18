import { useState, useEffect, useCallback, useMemo } from 'react'
import { useTransactionReadiness, type ConfigField } from '@/lib/setupReadiness'
import { SetupReadinessBanner } from '@/components/SetupReadiness'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type FundRef = { id: string; fund_name: string; authorized_amount: number }
type CCS = {
  id: string; company_id: string; branch_id: string | null; fund_id: string
  sheet_number: string; count_date: string; counted_by: string; witnessed_by: string | null
  book_balance: number; coins_and_bills: number; unreplenished_pcvs: number; other_items: number
  counted_amount: number; shortage_overage: number; remarks: string | null; status: string
  petty_cash_funds?: { fund_name: string } | null
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full disabled:bg-gray-50'

export default function CashCountSheetPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<CCS[]>([])
  const [funds, setFunds] = useState<FundRef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [form, setForm] = useState<Partial<CCS> | null>(null)
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('cash_count_sheets')
      .select('*,petty_cash_funds(fund_name)')
      .eq('company_id', companyId).order('count_date', { ascending: false }).order('sheet_number', { ascending: false })
    setRows((data as CCS[]) || [])
    setLoading(false)
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('petty_cash_funds').select('id,fund_name,authorized_amount').eq('company_id', companyId).eq('is_active', true).order('fund_name')
    setFunds((data as FundRef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const computeForFund = useCallback(async (fundId: string) => {
    const fund = funds.find(f => f.id === fundId)
    const authorized = fund ? Number(fund.authorized_amount) : 0
    const { data } = await supabase.from('petty_cash_vouchers').select('amount').eq('fund_id', fundId).eq('status', 'approved').is('replenishment_id', null)
    const unrepl = (data || []).reduce((s, r) => s + Number((r as { amount: number }).amount), 0)
    setForm(f => ({ ...f, fund_id: fundId, unreplenished_pcvs: unrepl, book_balance: authorized - unrepl }))
  }, [funds])

  const openNew = () => { setForm({ company_id: companyId, branch_id: branchId || null, count_date: today(), status: 'draft', coins_and_bills: 0, unreplenished_pcvs: 0, other_items: 0, book_balance: 0 }); setError(''); setMode('edit') }
  const openRow = (r: CCS) => { setForm({ ...r }); setError(''); setMode(r.status === 'finalized' ? 'view' : 'edit') }

  const counted = (Number(form?.coins_and_bills) || 0) + (Number(form?.unreplenished_pcvs) || 0) + (Number(form?.other_items) || 0)
  const shortageOverage = counted - (Number(form?.book_balance) || 0)

  const requiredConfig = useMemo<ConfigField[]>(() => [], [])
  // Cash count sheets allocate a number series but do not post to the GL, so no open-period gate.
  const readiness = useTransactionReadiness({
    companyId,
    branchId: form?.branch_id || branchId,
    documentCode: 'CCS',
    postingDate: form?.count_date || today(),
    requiredConfig,
    requireOpenPeriod: false,
  })
  const setupBlocked = readiness.loading || readiness.blockers.length > 0

  const save = async (finalize: boolean) => {
    if (!companyId || !form) return
    if (setupBlocked) { setError(readiness.loading ? 'Setup readiness is still being checked.' : readiness.blockers[0]); return }
    if (!form.fund_id || !form.counted_by) { setError('Fund and counted-by are required'); return }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const base = {
        company_id: companyId, branch_id: form.branch_id || branchId || null, fund_id: form.fund_id,
        count_date: form.count_date || today(), counted_by: form.counted_by, witnessed_by: form.witnessed_by || null,
        book_balance: Number(form.book_balance) || 0, coins_and_bills: Number(form.coins_and_bills) || 0,
        unreplenished_pcvs: Number(form.unreplenished_pcvs) || 0, other_items: Number(form.other_items) || 0,
        counted_amount: counted, remarks: form.remarks || null,
        status: finalize ? 'finalized' : 'draft', updated_by: uid,
      }
      if (form.id) {
        const { error: e } = await supabase.from('cash_count_sheets').update(base).eq('id', form.id)
        if (e) throw e
      } else {
        const { data: num, error: ne } = await supabase.rpc('fn_next_document_number', { p_company_id: companyId, p_branch_id: branchId, p_document_code: 'CCS' })
        if (ne || !num) throw new Error(ne?.message || 'No number series for CCS. Configure in Number Series setup.')
        const { error: e } = await supabase.from('cash_count_sheets').insert([{ ...base, sheet_number: num as string, created_by: uid }])
        if (e) throw e
      }
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false); setBusy(false) }
  }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Cash Count Sheet</span>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Count Sheet</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No cash count sheets</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['Sheet #','Date','Fund','Counted By','Witnessed By','Book Bal','Counted','Short/Over','Status',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Book Bal','Counted','Short/Over'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => {
              const so = Number(r.shortage_overage)
              return (
              <tr key={r.id} className="hover:bg-gray-50/60">
                <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900 cursor-pointer" onClick={() => openRow(r)}>{r.sheet_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.count_date}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.petty_cash_funds?.fund_name || '—'}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.counted_by}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{r.witnessed_by || '—'}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(r.book_balance)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-900">{fmt(r.counted_amount)}</td>
                <td className={`px-3 py-2.5 text-right font-mono text-xs font-semibold ${so < 0 ? 'text-red-600' : so > 0 ? 'text-green-600' : 'text-gray-400'}`}>{fmt(so)}</td>
                <td className="px-3 py-2.5"><StatusBadge status={r.status} /></td>
                <td className="px-3 py-2.5 text-right"><button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900">{r.status === 'finalized' ? 'View' : 'Edit'}</button></td>
              </tr>
            )})}
          </tbody>
        </table>
      )}
    </div>
  )

  const ro = mode === 'view'
  return (
    <LegacyTransactionWorkspace title="Cash Count Sheet" family="banking" pattern="C" posting={false}
      documentNo={form?.sheet_number} status={form?.status} identity={form?.petty_cash_funds?.fund_name}
      financialFacts={[{ label: 'Counted Amount', value: fmt(Number(form?.counted_amount || 0)) }, { label: 'Book Balance', value: fmt(Number(form?.book_balance || 0)) }, { label: 'Shortage / Overage', value: fmt(Number(form?.shortage_overage || 0)) }, { label: 'Unreplenished Vouchers', value: fmt(Number(form?.unreplenished_pcvs || 0)) }]}
      contextFacts={[{ label: 'Fund', value: form?.petty_cash_funds?.fund_name || 'Not selected' }, { label: 'Count Date', value: form?.count_date || 'Not assigned' }, { label: 'Counted By', value: form?.counted_by || 'Not recorded' }, { label: 'Witnessed By', value: form?.witnessed_by || 'Not recorded' }]}
      sourceDocId={form?.id} auditTable="cash_count_sheets"
      actions={[
        { key: 'cancel', label: 'Cancel', onClick: () => setMode('list'), hidden: ro },
        { key: 'save', label: saving ? 'Saving…' : 'Save Draft', onClick: () => save(false), disabled: saving, hidden: ro },
        { key: 'finalize', label: 'Finalize', onClick: () => { setBusy(true); save(true) }, disabled: saving || busy, hidden: ro, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'date', label: 'Count Date *', card: 0, content: <input type="date" disabled={ro} className={`${inputCls} pxl-input`} value={form?.count_date || today()} onChange={e => setForm(f => ({ ...f, count_date: e.target.value }))} /> },
        { key: 'number', label: 'Document Number', card: 0, content: <div className="pxl-readonly-field">{form?.sheet_number || 'Generated on save'}</div> },
        { key: 'fund', label: 'Fund *', card: 1, span: 2, content: <select disabled={ro} className={`${inputCls} pxl-input`} value={form?.fund_id || ''} onChange={e => computeForFund(e.target.value)}><option value="">— select fund —</option>{funds.map(f => <option key={f.id} value={f.id}>{f.fund_name}</option>)}</select> },
        { key: 'counted-by', label: 'Counted By *', card: 1, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.counted_by || ''} onChange={e => setForm(f => ({ ...f, counted_by: e.target.value }))} /> },
        { key: 'witness', label: 'Witnessed By', card: 1, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.witnessed_by || ''} onChange={e => setForm(f => ({ ...f, witnessed_by: e.target.value }))} /> },
        { key: 'remarks', label: 'Remarks', card: 2, span: 2, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.remarks || ''} onChange={e => setForm(f => ({ ...f, remarks: e.target.value }))} /> },
        { key: 'status', label: 'Count Status', card: 2, content: <div className="pxl-readonly-field capitalize">{form?.status || 'draft'}</div> },
      ]}
      tabContent={{ validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{!ro && <SetupReadinessBanner readiness={readiness} />}</div> }}
      onBack={() => setMode('list')} backLabel="Cash Count Sheets">
    <div className="overflow-x-auto"><div className="mb-2 flex items-center justify-between"><h2 className="pxl-section-title">Count Lines</h2><span className="pxl-caption">Counted amount {fmt(counted)}</span></div><table className="pxl-data-grid w-full min-w-[760px]" aria-label="Cash count lines"><thead><tr><th className="text-left">Count Component</th><th className="text-right">Amount</th><th className="text-left">Source</th></tr></thead><tbody>
      <tr><td>Coins &amp; Bills</td><td><input type="number" disabled={ro} className={`${inputCls} pxl-input text-right`} value={form?.coins_and_bills ?? 0} onChange={e => setForm(f => ({ ...f, coins_and_bills: parseFloat(e.target.value) || 0 }))} /></td><td>Physical count</td></tr>
      <tr><td>Unreplenished PCVs</td><td><input type="number" disabled className={`${inputCls} pxl-input text-right`} value={form?.unreplenished_pcvs ?? 0} readOnly /></td><td>System calculated</td></tr>
      <tr><td>Other Items</td><td><input type="number" disabled={ro} className={`${inputCls} pxl-input text-right`} value={form?.other_items ?? 0} onChange={e => setForm(f => ({ ...f, other_items: parseFloat(e.target.value) || 0 }))} /></td><td>Count adjustment</td></tr>
      <tr><td>Book Balance</td><td><input type="number" disabled className={`${inputCls} pxl-input text-right`} value={form?.book_balance ?? 0} readOnly /></td><td>System calculated</td></tr>
    </tbody><tfoot><tr><td>Shortage / (Overage)</td><td className="text-right font-mono">{fmt(shortageOverage)}</td><td>Counted less book</td></tr></tfoot></table></div>
    </LegacyTransactionWorkspace>
  )
}
