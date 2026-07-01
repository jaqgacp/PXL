import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type BankAccount = { id: string; bank_name: string; account_number: string; account_name: string; account_type: string; opening_balance: number; gl_account_id: string; is_active: boolean }
type GLAgg = { account_id: string; debit_amount: number; credit_amount: number }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

export default function BankPositionReportPage() {
  const { companyId } = useAppCtx()
  const [asOfDate, setAsOfDate] = useState(today())
  const [rows, setRows] = useState<{ account: BankAccount; balance: number }[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data: accounts } = await supabase.from('bank_accounts').select('id,bank_name,account_number,account_name,account_type,opening_balance,gl_account_id,is_active')
      .eq('company_id', companyId).eq('is_active', true).order('bank_name')

    const accList = (accounts as BankAccount[]) || []
    const glAccountIds = accList.map(a => a.gl_account_id).filter(Boolean)
    const { data: glData } = glAccountIds.length
      ? await supabase.from('vw_general_ledger').select('account_id,debit_amount,credit_amount').eq('company_id', companyId).in('account_id', glAccountIds).lte('je_date', asOfDate)
      : { data: [] }

    const movement: Record<string, number> = {}
    for (const r of (glData as GLAgg[]) || []) movement[r.account_id] = (movement[r.account_id] || 0) + Number(r.debit_amount) - Number(r.credit_amount)

    setRows(accList.map(a => ({ account: a, balance: Number(a.opening_balance) + (movement[a.gl_account_id] || 0) })))
    setLoading(false)
  }, [companyId, asOfDate])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const total = rows.reduce((s, r) => s + r.balance, 0)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">Bank Position Report</h1><p className="text-sm text-gray-500 mt-0.5">Book balance across all bank accounts as of a date</p></div>
        <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">Print</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <label className="text-xs text-gray-500">As of</label>
        <input type="date" value={asOfDate} onChange={e => setAsOfDate(e.target.value)} className="border border-gray-300 rounded-md px-3 py-1.5 text-sm" />
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <p className="text-xs text-gray-500 uppercase tracking-wide">Total Cash Position</p>
        <p className="text-2xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmt(total)}</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Bank</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Account No.</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Book Balance</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={4} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No active bank accounts.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.account.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{r.account.bank_name}</td>
                  <td className="px-4 py-2 text-gray-500 font-mono">{r.account.account_number}</td>
                  <td className="px-4 py-2 text-gray-500 capitalize">{r.account.account_type.replace('_', ' ')}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.balance)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
