import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Tab = 'ar' | 'ap'

type AccountingConfig = {
  ar_account_id: string | null
  ap_account_id: string | null
  ar_account_code: string
  ar_account_name: string
  ap_account_code: string
  ap_account_name: string
}

type GlLine = { debit_amount: number; credit_amount: number }
type ArSubRow = { id: string; si_number: string; customer_name_snapshot: string; balance_due: number }
type ApSubRow = { id: string; bill_number: string; supplier_name: string; balance_due: number }

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

export default function ControlAccountReconciliationPage() {
  const { companyId } = useAppCtx()
  const [tab, setTab] = useState<Tab>('ar')
  const [asOfDate, setAsOfDate] = useState(today())
  const [config, setConfig] = useState<AccountingConfig | null>(null)
  const [configLoading, setConfigLoading] = useState(false)
  const [loading, setLoading] = useState(false)

  const [arGlLines, setArGlLines] = useState<GlLine[]>([])
  const [arSubRows, setArSubRows] = useState<ArSubRow[]>([])
  const [apGlLines, setApGlLines] = useState<GlLine[]>([])
  const [apSubRows, setApSubRows] = useState<ApSubRow[]>([])

  useEffect(() => {
    if (!companyId) { setConfig(null); return }
    setConfigLoading(true)
    supabase.from('company_accounting_config')
      .select('ar_account_id,ap_account_id').eq('company_id', companyId).maybeSingle()
      .then(async ({ data }) => {
        if (!data) { setConfig(null); setConfigLoading(false); return }
        const ids = [data.ar_account_id, data.ap_account_id].filter(Boolean) as string[]
        const coaMap: Record<string, { code: string; name: string }> = {}
        if (ids.length) {
          const { data: coas } = await supabase.from('chart_of_accounts')
            .select('id,account_code,account_name').in('id', ids)
          for (const c of (coas || []) as any[]) coaMap[c.id] = { code: c.account_code, name: c.account_name }
        }
        setConfig({
          ar_account_id: data.ar_account_id,
          ap_account_id: data.ap_account_id,
          ar_account_code: data.ar_account_id ? (coaMap[data.ar_account_id]?.code || '') : '',
          ar_account_name: data.ar_account_id ? (coaMap[data.ar_account_id]?.name || '') : '',
          ap_account_code: data.ap_account_id ? (coaMap[data.ap_account_id]?.code || '') : '',
          ap_account_name: data.ap_account_id ? (coaMap[data.ap_account_id]?.name || '') : '',
        })
        setConfigLoading(false)
      })
  }, [companyId])

  const runAR = useCallback(async () => {
    if (!companyId || !config?.ar_account_id) return
    setLoading(true)
    const [glRes, invRes] = await Promise.all([
      supabase.from('vw_general_ledger')
        .select('debit_amount,credit_amount')
        .eq('company_id', companyId).eq('account_id', config.ar_account_id)
        .lte('je_date', asOfDate),
      supabase.from('sales_invoices')
        .select('id,si_number,customer_name_snapshot,total_amount')
        .eq('company_id', companyId).eq('status', 'posted').lte('date', asOfDate),
    ])
    setArGlLines((glRes.data as GlLine[]) || [])
    const invoices = (invRes.data as any[]) || []
    if (!invoices.length) { setArSubRows([]); setLoading(false); return }
    const ids = invoices.map(i => i.id)
    const [rlRes, clRes] = await Promise.all([
      supabase.from('receipt_lines').select('invoice_id,payment_amount,cwt_amount').in('invoice_id', ids),
      supabase.from('credit_memos').select('invoice_id,total_amount').in('invoice_id', ids).in('status', ['applied']),
    ])
    const applied: Record<string, number> = {}
    for (const r of (rlRes.data as any[]) || []) applied[r.invoice_id] = (applied[r.invoice_id] || 0) + Number(r.payment_amount) + Number(r.cwt_amount)
    for (const c of (clRes.data as any[]) || []) applied[c.invoice_id] = (applied[c.invoice_id] || 0) + Number(c.total_amount)
    const rows: ArSubRow[] = invoices.map(inv => ({
      id: inv.id, si_number: inv.si_number,
      customer_name_snapshot: inv.customer_name_snapshot,
      balance_due: Math.max(0, Number(inv.total_amount) - (applied[inv.id] || 0)),
    })).filter(r => r.balance_due > 0.005)
    setArSubRows(rows)
    setLoading(false)
  }, [companyId, config, asOfDate])

  const runAP = useCallback(async () => {
    if (!companyId || !config?.ap_account_id) return
    setLoading(true)
    const [glRes, billRes] = await Promise.all([
      supabase.from('vw_general_ledger')
        .select('debit_amount,credit_amount')
        .eq('company_id', companyId).eq('account_id', config.ap_account_id)
        .lte('je_date', asOfDate),
      supabase.from('vw_ap_aging')
        .select('id,bill_number,supplier_name,balance_due')
        .eq('company_id', companyId).gt('balance_due', 0),
    ])
    setApGlLines((glRes.data as GlLine[]) || [])
    setApSubRows((billRes.data as ApSubRow[]) || [])
    setLoading(false)
  }, [companyId, config, asOfDate])

  useEffect(() => { if (config && tab === 'ar') runAR() }, [tab, config, runAR])
  useEffect(() => { if (config && tab === 'ap') runAP() }, [tab, config, runAP])

  const refresh = () => tab === 'ar' ? runAR() : runAP()

  const glLines = tab === 'ar' ? arGlLines : apGlLines
  const subRows = tab === 'ar' ? arSubRows : apSubRows

  const totalDebit = glLines.reduce((s, l) => s + Number(l.debit_amount), 0)
  const totalCredit = glLines.reduce((s, l) => s + Number(l.credit_amount), 0)
  const glBal = tab === 'ar' ? totalDebit - totalCredit : totalCredit - totalDebit
  const subBal = tab === 'ar'
    ? arSubRows.reduce((s, r) => s + r.balance_due, 0)
    : apSubRows.reduce((s, r) => s + r.balance_due, 0)
  const diff = glBal - subBal
  const reconciled = Math.abs(diff) <= 0.01

  const acctLabel = tab === 'ar'
    ? (config?.ar_account_code ? `${config.ar_account_code} — ${config.ar_account_name}` : 'AR account not configured')
    : (config?.ap_account_code ? `${config.ap_account_code} — ${config.ap_account_name}` : 'AP account not configured')

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Control Account Reconciliation</span>
        <div className="flex rounded border border-gray-300 overflow-hidden">
          <button onClick={() => setTab('ar')} className={`px-3 py-1.5 text-xs font-medium ${tab === 'ar' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>AR Reconciliation</button>
          <button onClick={() => setTab('ap')} className={`px-3 py-1.5 text-xs font-medium border-l border-gray-300 ${tab === 'ap' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>AP Reconciliation</button>
        </div>
        <label className="text-xs text-gray-500">As of</label>
        <input type="date" value={asOfDate} onChange={e => setAsOfDate(e.target.value)}
          className="border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <button onClick={refresh} disabled={!config || loading}
          className="px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50 disabled:opacity-40">
          Refresh
        </button>
      </div>

      {configLoading && <div className="py-16 text-center text-sm text-gray-400">Loading configuration…</div>}

      {!configLoading && !config && (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">GL Posting Configuration not set</p>
          <p className="text-xs text-gray-400 mt-1">Set up AR and AP control accounts in Setup › Accounting Setup › GL Posting Configuration.</p>
        </div>
      )}

      {config && (
        <div className="px-5 py-4 space-y-4">
          {/* KPI Strip */}
          <div className="grid grid-cols-3 gap-3">
            <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">GL Control Balance</p>
              <p className="text-xs text-gray-400 mt-0.5 truncate">{acctLabel}</p>
              <p className="text-lg font-bold text-gray-900 tabular-nums font-mono mt-1">{fmt(glBal)}</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Subsidiary Balance</p>
              <p className="text-xs text-gray-400 mt-0.5">{tab === 'ar' ? 'Outstanding Sales Invoices' : 'Outstanding Vendor Bills'}</p>
              <p className="text-lg font-bold text-gray-900 tabular-nums font-mono mt-1">{fmt(subBal)}</p>
            </div>
            <div className={`border rounded-lg px-4 py-3 ${reconciled ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
              <p className={`text-[10px] font-semibold uppercase tracking-wide ${reconciled ? 'text-green-500' : 'text-red-500'}`}>Difference</p>
              <p className="text-xs text-gray-400 mt-0.5">{reconciled ? 'Reconciled ✓' : 'Discrepancy found'}</p>
              <p className={`text-lg font-bold tabular-nums font-mono mt-1 ${reconciled ? 'text-green-700' : 'text-red-700'}`}>{fmt(diff)}</p>
            </div>
          </div>

          {loading ? (
            <div className="py-12 text-center text-sm text-gray-400">Loading…</div>
          ) : (
            <div className="grid grid-cols-2 gap-4">
              {/* GL Side */}
              <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
                <div className="px-4 py-2.5 border-b border-gray-100">
                  <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">GL — Control Account Summary</span>
                </div>
                <div className="divide-y divide-gray-100 text-xs">
                  {[
                    ['Total GL Lines', glLines.length.toString()],
                    ['Total Debit Posted', fmt(totalDebit)],
                    ['Total Credit Posted', fmt(totalCredit)],
                    [`Net Balance (${tab === 'ar' ? 'Debit' : 'Credit'} Normal)`, fmt(glBal)],
                  ].map(([label, value]) => (
                    <div key={label} className="flex justify-between px-4 py-2.5">
                      <span className="text-gray-600">{label}</span>
                      <span className="font-mono tabular-nums font-medium text-gray-900">{value}</span>
                    </div>
                  ))}
                </div>
              </div>

              {/* Subsidiary Side */}
              <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
                <div className="px-4 py-2.5 border-b border-gray-100 flex items-center justify-between">
                  <span className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">
                    {tab === 'ar' ? 'Outstanding Invoices' : 'Outstanding Bills'}
                  </span>
                  <span className="text-[10px] text-gray-400">{subRows.length} items</span>
                </div>
                {subRows.length === 0 ? (
                  <div className="py-10 text-center text-xs text-gray-400">
                    No outstanding {tab === 'ar' ? 'AR' : 'AP'} balances
                  </div>
                ) : (
                  <div className="overflow-y-auto max-h-72">
                    <table className="w-full text-xs">
                      <thead className="bg-gray-50 border-b border-gray-200 sticky top-0">
                        <tr>
                          <th className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left">
                            {tab === 'ar' ? 'Invoice #' : 'Bill #'}
                          </th>
                          <th className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left">
                            {tab === 'ar' ? 'Customer' : 'Supplier'}
                          </th>
                          <th className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-right">Balance Due</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-gray-100">
                        {(subRows as any[]).slice(0, 100).map((r) => (
                          <tr key={r.id} className="hover:bg-gray-50/60">
                            <td className="px-3 py-1.5 font-mono text-gray-900">
                              {tab === 'ar' ? (r as ArSubRow).si_number : (r as ApSubRow).bill_number}
                            </td>
                            <td className="px-3 py-1.5 text-gray-600 max-w-[130px] truncate">
                              {tab === 'ar' ? (r as ArSubRow).customer_name_snapshot : (r as ApSubRow).supplier_name}
                            </td>
                            <td className="px-3 py-1.5 text-right font-mono tabular-nums text-gray-700">{fmt(r.balance_due)}</td>
                          </tr>
                        ))}
                      </tbody>
                      <tfoot className="border-t border-gray-200 bg-gray-50">
                        <tr>
                          <td colSpan={2} className="px-3 py-2 text-right font-semibold text-gray-700 text-xs">Total</td>
                          <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900 text-xs">{fmt(subBal)}</td>
                        </tr>
                      </tfoot>
                    </table>
                  </div>
                )}
              </div>
            </div>
          )}

          {!reconciled && !loading && (
            <div className="bg-amber-50 border border-amber-200 rounded-lg p-4">
              <p className="text-sm font-medium text-amber-800">Reconciling difference: {fmt(Math.abs(diff))}</p>
              <p className="text-xs text-amber-600 mt-1">
                Common causes: unposted transactions, incorrect GL posting configuration, or direct GL postings not reflected in the subsidiary ledger. Check that all {tab === 'ar' ? 'invoices, receipts, and credit memos' : 'vendor bills, payment vouchers, and vendor credits'} are posted.
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
