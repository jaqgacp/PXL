import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { TablesInsert } from '@/lib/database.types'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type BankRef = { id: string; bank_name: string; account_number: string; account_name: string; gl_account_id: string; opening_balance: number }
type Recon = {
  id: string; company_id: string; branch_id: string | null; bank_account_id: string
  recon_month: number; recon_year: number; reconciliation_date: string
  bank_statement_balance: number; deposits_in_transit: number; outstanding_checks: number; bank_errors: number
  book_balance: number; book_adjustments_add: number; book_adjustments_less: number; book_errors: number
  adjusted_bank_balance: number; adjusted_book_balance: number; difference: number
  remarks: string | null; status: string
  bank_accounts?: { bank_name: string; account_number: string; account_name: string } | null
}
type OutCheck = { id: string; cv_number: string; check_number: string; check_date: string; payee: string; net_check_amount: number }
type DITItem = { _key: string; id?: string; description: string; document_date: string | null; amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]
const lastDay = (y: number, m: number) => new Date(y, m, 0).toISOString().split('T')[0]
const inputCls = 'border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full disabled:bg-gray-50'
const numCls = inputCls + ' text-right font-mono'
const newDIT = (): DITItem => ({ _key: crypto.randomUUID(), description: '', document_date: today(), amount: 0 })

export default function BankReconciliationPage() {
  const { companyId, branchId } = useAppCtx()
  const [rows, setRows] = useState<Recon[]>([])
  const [banks, setBanks] = useState<BankRef[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'edit' | 'view'>('list')
  const [form, setForm] = useState<Partial<Recon> | null>(null)
  const [outChecks, setOutChecks] = useState<OutCheck[]>([])
  const [dits, setDits] = useState<DITItem[]>([])
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('bank_reconciliations')
      .select('*,bank_accounts(bank_name,account_number,account_name)')
      .eq('company_id', companyId).order('recon_year', { ascending: false }).order('recon_month', { ascending: false })
    setRows((data as Recon[]) || [])
    setLoading(false)
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('bank_accounts').select('id,bank_name,account_number,account_name,gl_account_id,opening_balance').eq('company_id', companyId).eq('is_active', true).order('bank_name')
    setBanks((data as BankRef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadRefs() } }, [load, loadRefs, companyId])

  const computeBookAndChecks = useCallback(async (bankAccountId: string, reconDate: string) => {
    const bank = banks.find(b => b.id === bankAccountId)
    if (!bank) return
    // GL balance up to reconciliation date (posted only)
    const { data: jel } = await supabase.from('journal_entry_lines')
      .select('debit_amount,credit_amount,journal_entries!inner(je_date,status,company_id)')
      .eq('account_id', bank.gl_account_id)
      .eq('journal_entries.company_id', companyId)
      .eq('journal_entries.status', 'posted')
      .lte('journal_entries.je_date', reconDate)
    const glBalance = (jel || []).reduce((s, r) => {
      const row = r as { debit_amount: number; credit_amount: number }
      return s + Number(row.debit_amount) - Number(row.credit_amount)
    }, 0)
    const bookBalance = glBalance + Number(bank.opening_balance || 0)

    // Outstanding checks
    const { data: cvs } = await supabase.from('check_vouchers')
      .select('id,cv_number,check_number,check_date,payee,net_check_amount')
      .eq('company_id', companyId).eq('bank_account_id', bankAccountId).in('status', ['posted', 'released']).order('check_date')
    const checks = (cvs as OutCheck[]) || []
    setOutChecks(checks)
    const outTotal = checks.reduce((s, c) => s + Number(c.net_check_amount), 0)

    setForm(f => ({ ...f, book_balance: bookBalance, outstanding_checks: outTotal }))
  }, [banks, companyId])

  const openNew = () => {
    const y = new Date().getFullYear(), m = new Date().getMonth() + 1
    setForm({ company_id: companyId, branch_id: branchId || null, recon_month: m, recon_year: y, reconciliation_date: lastDay(y, m), status: 'draft',
      bank_statement_balance: 0, deposits_in_transit: 0, outstanding_checks: 0, bank_errors: 0,
      book_balance: 0, book_adjustments_add: 0, book_adjustments_less: 0, book_errors: 0 })
    setOutChecks([]); setDits([]); setError(''); setMode('edit')
  }

  const openRow = async (r: Recon) => {
    setForm({ ...r }); setError('')
    const { data: items } = await supabase.from('bank_recon_items').select('*').eq('reconciliation_id', r.id).eq('item_type', 'deposit_in_transit')
    setDits((items || []).map((it) => {
      const row = it as { id: string; description: string; document_date: string | null; amount: number }
      return { _key: row.id, id: row.id, description: row.description, document_date: row.document_date, amount: Number(row.amount) }
    }))
    const { data: cvs } = await supabase.from('check_vouchers').select('id,cv_number,check_number,check_date,payee,net_check_amount')
      .eq('company_id', r.company_id).eq('bank_account_id', r.bank_account_id).in('status', ['posted', 'released']).order('check_date')
    setOutChecks((cvs as OutCheck[]) || [])
    setMode(r.status === 'finalized' ? 'view' : 'edit')
  }

  const pickBank = async (bankId: string) => {
    setForm(f => ({ ...f, bank_account_id: bankId }))
    if (form?.reconciliation_date) await computeBookAndChecks(bankId, form.reconciliation_date)
  }
  const pickPeriod = async (year: number, month: number) => {
    const rd = lastDay(year, month)
    setForm(f => ({ ...f, recon_year: year, recon_month: month, reconciliation_date: rd }))
    if (form?.bank_account_id) await computeBookAndChecks(form.bank_account_id, rd)
  }

  const ditTotal = dits.reduce((s, d) => s + (Number(d.amount) || 0), 0)
  const bankStmt = Number(form?.bank_statement_balance) || 0
  const outChk = Number(form?.outstanding_checks) || 0
  const bankErr = Number(form?.bank_errors) || 0
  const bookBal = Number(form?.book_balance) || 0
  const addAdj = Number(form?.book_adjustments_add) || 0
  const lessAdj = Number(form?.book_adjustments_less) || 0
  const bookErr = Number(form?.book_errors) || 0
  const adjBank = bankStmt + ditTotal - outChk + bankErr
  const adjBook = bookBal + addAdj - lessAdj + bookErr
  const difference = adjBank - adjBook

  const persist = async (finalize: boolean) => {
    if (!companyId || !form) return
    if (!form.bank_account_id) { setError('Select a bank account'); return }
    if (finalize && Math.abs(difference) > 0.001) { setError('Cannot finalize: reconciliation is not balanced (difference must be zero)'); return }
    setSaving(true); setError('')
    try {
      const uid = (await supabase.auth.getUser()).data.user?.id
      const base = {
        company_id: companyId, branch_id: form.branch_id || branchId || null, bank_account_id: form.bank_account_id,
        recon_month: form.recon_month, recon_year: form.recon_year, reconciliation_date: form.reconciliation_date || today(),
        bank_statement_balance: bankStmt, deposits_in_transit: ditTotal, outstanding_checks: outChk, bank_errors: bankErr,
        book_balance: bookBal, book_adjustments_add: addAdj, book_adjustments_less: lessAdj, book_errors: bookErr,
        remarks: form.remarks || null, status: finalize ? 'finalized' : 'draft',
        finalized_at: finalize ? new Date().toISOString() : null, finalized_by: finalize ? uid : null, updated_by: uid,
      }
      let reconId = form.id
      if (reconId) {
        const { error: e } = await supabase.from('bank_reconciliations').update(base).eq('id', reconId)
        if (e) throw e
      } else {
        const { data: ins, error: e } = await supabase.from('bank_reconciliations').insert([{ ...base, created_by: uid } as TablesInsert<'bank_reconciliations'>]).select('id').single()
        if (e) throw e
        reconId = (ins as { id: string }).id
      }
      await supabase.from('bank_recon_items').delete().eq('reconciliation_id', reconId).eq('item_type', 'deposit_in_transit')
      const ditPayload = dits.filter(d => Number(d.amount) !== 0 || d.description).map(d => ({
        reconciliation_id: reconId, company_id: companyId, item_type: 'deposit_in_transit',
        description: d.description || 'Deposit in transit', document_date: d.document_date || null, amount: Number(d.amount), created_by: uid,
      }))
      if (ditPayload.length) { const { error: de } = await supabase.from('bank_recon_items').insert(ditPayload); if (de) throw de }
      await load(); setMode('list')
    } catch (e) { setError((e as Error).message || 'Save failed') } finally { setSaving(false); setBusy(false) }
  }

  if (mode === 'list') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Bank Reconciliation</span>
        <button onClick={openNew} disabled={!companyId} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">+ New Reconciliation</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No reconciliations</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['Bank Account','Period','Recon Date','Stmt Bal','Book Bal','Out Checks','DIT','Adj Bank','Adj Book','Difference','Status',''].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Bank Account','Period','Recon Date','Status',''].includes(h) ? 'text-left' : 'text-right'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className="hover:bg-gray-50/60">
                <td className="px-3 py-2.5 text-xs text-gray-700 cursor-pointer" onClick={() => openRow(r)}>{r.bank_accounts ? `${r.bank_accounts.bank_name} ${r.bank_accounts.account_number}` : '—'}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{String(r.recon_month).padStart(2, '0')}/{r.recon_year}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.reconciliation_date}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(r.bank_statement_balance)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(r.book_balance)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-500">{fmt(r.outstanding_checks)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-500">{fmt(r.deposits_in_transit)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(r.adjusted_bank_balance)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs text-gray-700">{fmt(r.adjusted_book_balance)}</td>
                <td className={`px-3 py-2.5 text-right font-mono text-xs font-bold ${Math.abs(r.difference) < 0.001 ? 'text-green-600' : 'text-red-600'}`}>{fmt(r.difference)}</td>
                <td className="px-3 py-2.5"><StatusBadge status={r.status} /></td>
                <td className="px-3 py-2.5 text-right"><button onClick={() => openRow(r)} className="text-xs text-gray-500 hover:text-gray-900">{r.status === 'finalized' ? 'View' : 'Edit'}</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )

  const ro = mode === 'view'
  const reconciled = Math.abs(difference) < 0.001
  const years = Array.from({ length: 6 }, (_, i) => new Date().getFullYear() - i)
  return (
    <LegacyTransactionWorkspace title="Bank Reconciliation" family="banking" pattern="C" posting={false}
      documentNo={form ? `${form.recon_year || ''}-${String(form.recon_month || '').padStart(2, '0')}` : undefined}
      status={form?.status} identity={form?.bank_accounts?.bank_name}
      financialFacts={[{ label: 'Adjusted Bank Balance', value: fmt(Number(form?.adjusted_bank_balance || 0)) }, { label: 'Adjusted Book Balance', value: fmt(Number(form?.adjusted_book_balance || 0)) }, { label: 'Difference', value: fmt(difference), hint: reconciled ? 'Reconciled' : 'Must equal zero before completion' }, { label: 'Outstanding Checks', value: fmt(Number(form?.outstanding_checks || 0)) }]}
      contextFacts={[{ label: 'Bank Account', value: form?.bank_accounts ? `${form.bank_accounts.bank_name} ${form.bank_accounts.account_number}` : 'Not selected' }, { label: 'Reconciliation Date', value: form?.reconciliation_date || 'Not assigned' }, { label: 'Period', value: form ? `${form.recon_month || ''}/${form.recon_year || ''}` : 'Not assigned' }, { label: 'Status', value: form?.status || 'draft' }]}
      sourceDocId={form?.id} auditTable="bank_reconciliations"
      actions={[
        { key: 'cancel', label: 'Cancel', onClick: () => setMode('list'), hidden: ro },
        { key: 'save', label: saving ? 'Saving…' : 'Save', onClick: () => persist(false), disabled: saving, hidden: ro },
        { key: 'finalize', label: 'Finalize', onClick: () => { setBusy(true); persist(true) }, disabled: saving || busy || !reconciled, hidden: ro, variant: 'primary', title: reconciled ? undefined : 'Difference must be zero to finalize' },
      ]}
      headerFields={[
        { key: 'date', label: 'Reconciliation Date *', card: 0, content: <input type="date" disabled={ro} className={`${inputCls} pxl-input`} value={form?.reconciliation_date || today()} onChange={e => setForm(f => ({ ...f, reconciliation_date: e.target.value }))} /> },
        { key: 'period', label: 'Period', card: 0, content: <div className="grid grid-cols-2 gap-2"><select disabled={ro} className={`${inputCls} pxl-input`} value={form?.recon_month || 1} onChange={e => pickPeriod(form?.recon_year || new Date().getFullYear(), Number(e.target.value))}>{Array.from({ length: 12 }, (_, i) => i + 1).map(m => <option key={m} value={m}>{String(m).padStart(2, '0')}</option>)}</select><select disabled={ro} className={`${inputCls} pxl-input`} value={form?.recon_year || new Date().getFullYear()} onChange={e => pickPeriod(Number(e.target.value), form?.recon_month || 1)}>{years.map(y => <option key={y} value={y}>{y}</option>)}</select></div> },
        { key: 'bank', label: 'Bank Account *', card: 1, span: 2, content: <select disabled={ro || !!form?.id} className={`${inputCls} pxl-input`} value={form?.bank_account_id || ''} onChange={e => pickBank(e.target.value)}><option value="">— select —</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}</select> },
        { key: 'status', label: 'Reconciliation Status', card: 1, content: <div className="pxl-readonly-field">{reconciled ? 'Reconciled' : 'Difference remains'}</div> },
        { key: 'remarks', label: 'Remarks', card: 2, span: 2, content: <input disabled={ro} className={`${inputCls} pxl-input`} value={form?.remarks || ''} onChange={e => setForm(f => ({ ...f, remarks: e.target.value }))} /> },
      ]}
      tabContent={{
        validation: error ? <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div> : undefined,
        financial: <div className="space-y-2"><div className="grid grid-cols-1 gap-2 lg:grid-cols-2"><section className="pxl-transaction-card p-3"><h3 className="pxl-section-title mb-2">Bank Side</h3><Row label="Bank Statement Balance"><input type="number" disabled={ro} className={numCls} value={form?.bank_statement_balance ?? 0} onChange={e => setForm(f => ({ ...f, bank_statement_balance: parseFloat(e.target.value) || 0 }))} /></Row><Row label="Add: Deposits in Transit"><div className={`${numCls} bg-gray-50 text-gray-600`}>{fmt(ditTotal)}</div></Row><Row label="Less: Outstanding Checks"><input type="number" disabled={ro} className={numCls} value={form?.outstanding_checks ?? 0} onChange={e => setForm(f => ({ ...f, outstanding_checks: parseFloat(e.target.value) || 0 }))} /></Row><Row label="Bank Errors (±)"><input type="number" disabled={ro} className={numCls} value={form?.bank_errors ?? 0} onChange={e => setForm(f => ({ ...f, bank_errors: parseFloat(e.target.value) || 0 }))} /></Row><div className="mt-2 flex justify-between border-t pt-2 font-semibold"><span>Adjusted Bank Balance</span><span className="font-mono">{fmt(adjBank)}</span></div></section><section className="pxl-transaction-card p-3"><h3 className="pxl-section-title mb-2">Book Side</h3><Row label="Book Balance (GL)"><div className={`${numCls} bg-gray-50 text-gray-600`}>{fmt(bookBal)}</div></Row><Row label="Add: Book Adjustments"><input type="number" disabled={ro} className={numCls} value={form?.book_adjustments_add ?? 0} onChange={e => setForm(f => ({ ...f, book_adjustments_add: parseFloat(e.target.value) || 0 }))} /></Row><Row label="Less: Book Adjustments"><input type="number" disabled={ro} className={numCls} value={form?.book_adjustments_less ?? 0} onChange={e => setForm(f => ({ ...f, book_adjustments_less: parseFloat(e.target.value) || 0 }))} /></Row><Row label="Book Errors (±)"><input type="number" disabled={ro} className={numCls} value={form?.book_errors ?? 0} onChange={e => setForm(f => ({ ...f, book_errors: parseFloat(e.target.value) || 0 }))} /></Row><div className="mt-2 flex justify-between border-t pt-2 font-semibold"><span>Adjusted Book Balance</span><span className="font-mono">{fmt(adjBook)}</span></div></section></div><div className={`pxl-validation-message text-center font-mono font-bold ${reconciled ? 'border border-green-200 bg-green-50 text-green-700' : 'border border-red-200 bg-red-50 text-red-700'}`}>Difference: {fmt(difference)} · {reconciled ? 'RECONCILED' : 'NOT RECONCILED'}</div></div>,
      }}
      onBack={() => setMode('list')} backLabel="Bank Reconciliations">
    <div className="grid grid-cols-1 gap-2 lg:grid-cols-2">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-2.5 border-b border-gray-100 flex justify-between">
              <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Outstanding Checks</span>
              <span className="text-xs font-mono text-gray-500">{fmt(outChecks.reduce((s, c) => s + Number(c.net_check_amount), 0))}</span>
            </div>
            {outChecks.length === 0 ? <div className="px-4 py-6 text-xs text-gray-400">No outstanding checks.</div> : (
              <table className="pxl-data-grid w-full text-xs"><thead className="bg-gray-50 border-b border-gray-200"><tr>
                {['CV #','Check #','Date','Payee','Amount'].map(h => <th key={h} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
              </tr></thead><tbody className="divide-y divide-gray-100">
                {outChecks.map(c => (<tr key={c.id}>
                  <td className="px-3 py-1.5 font-mono text-gray-900">{c.cv_number}</td>
                  <td className="px-3 py-1.5 font-mono text-gray-700">{c.check_number}</td>
                  <td className="px-3 py-1.5 font-mono text-gray-500">{c.check_date}</td>
                  <td className="px-3 py-1.5 text-gray-700 max-w-[120px] truncate">{c.payee}</td>
                  <td className="px-3 py-1.5 text-right font-mono text-gray-900">{fmt(c.net_check_amount)}</td>
                </tr>))}
              </tbody></table>
            )}
          </div>
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-2.5 border-b border-gray-100 flex justify-between items-center">
              <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Deposits in Transit</span>
              <span className="text-xs font-mono text-gray-500">{fmt(ditTotal)}</span>
            </div>
            <table className="pxl-data-grid w-full text-xs"><thead className="bg-gray-50 border-b border-gray-200"><tr>
              {['Description','Date','Amount',''].map(h => <th key={h} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
            </tr></thead><tbody className="divide-y divide-gray-100">
              {dits.map(d => (<tr key={d._key}>
                <td className="px-3 py-1.5"><input disabled={ro} value={d.description} onChange={e => setDits(ls => ls.map(x => x._key === d._key ? { ...x, description: e.target.value } : x))} className="border border-gray-300 rounded px-2 py-1 text-xs w-full focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" /></td>
                <td className="px-3 py-1.5"><input type="date" disabled={ro} value={d.document_date || ''} onChange={e => setDits(ls => ls.map(x => x._key === d._key ? { ...x, document_date: e.target.value } : x))} className="border border-gray-300 rounded px-2 py-1 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" /></td>
                <td className="px-3 py-1.5"><input type="number" disabled={ro} value={d.amount} onChange={e => setDits(ls => ls.map(x => x._key === d._key ? { ...x, amount: parseFloat(e.target.value) || 0 } : x))} className="border border-gray-300 rounded px-2 py-1 text-xs w-24 text-right focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" /></td>
                <td className="px-3 py-1.5">{!ro && <button onClick={() => setDits(ls => ls.filter(x => x._key !== d._key))} className="text-gray-400 hover:text-red-500 text-xs px-1">✕</button>}</td>
              </tr>))}
            </tbody></table>
            {!ro && <div className="px-4 py-2 border-t border-gray-100"><button onClick={() => setDits(ls => [...ls, newDIT()])} className="text-xs text-gray-500 hover:text-gray-900 font-medium">+ Add Deposit</button></div>}
          </div>
    </div>
    </LegacyTransactionWorkspace>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="flex justify-between items-center gap-3 py-1"><span className="text-xs text-gray-600 flex-1">{label}</span><div className="w-40">{children}</div></div>
}
