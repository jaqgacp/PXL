import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge } from '@/components/ui/shared'

type BankRef = { id: string; bank_name: string; account_number: string }
type OutCheck = {
  id: string; company_id: string; cv_number: string; voucher_date: string
  check_number: string; check_date: string; payee: string; payee_tin: string | null
  net_check_amount: number; status: string; particulars: string
  bank_account_id: string; bank_name: string; account_number: string; account_name: string
  days_outstanding: number
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function OutstandingChecksPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<OutCheck[]>([])
  const [banks, setBanks] = useState<BankRef[]>([])
  const [loading, setLoading] = useState(false)
  const [fBank, setFBank] = useState('')
  const [fStatus, setFStatus] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('vw_outstanding_checks').select('*').eq('company_id', companyId).order('check_date')
    if (fBank) q = q.eq('bank_account_id', fBank)
    if (fStatus) q = q.eq('status', fStatus)
    const { data } = await q
    setRows((data as OutCheck[]) || [])
    setLoading(false)
  }, [companyId, fBank, fStatus])

  const loadBanks = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('bank_accounts').select('id,bank_name,account_number').eq('company_id', companyId).order('bank_name')
    setBanks((data as BankRef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadBanks() } }, [load, loadBanks, companyId])

  const total = rows.reduce((s, r) => s + Number(r.net_check_amount), 0)
  const ageCls = (d: number) => d > 60 ? 'text-red-600' : d >= 30 ? 'text-amber-600' : 'text-gray-500'

  const exportCsv = () => {
    const header = ['Bank','Account','CV Number','Voucher Date','Check No','Check Date','Payee','Net Amount','Days Outstanding','Status']
    const lines = rows.map(r => [r.bank_name, r.account_number, r.cv_number, r.voucher_date, r.check_number, r.check_date, r.payee, r.net_check_amount, r.days_outstanding, r.status])
    const csv = [header, ...lines].map(row => row.map(c => `"${String(c ?? '').replace(/"/g, '""')}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'outstanding_checks.csv'; a.click()
  }

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Outstanding Checks</span>
        <select value={fBank} onChange={e => setFBank(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm">
          <option value="">All banks</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}
        </select>
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm">
          <option value="">All (posted + released)</option><option value="posted">Posted</option><option value="released">Released</option>
        </select>
        <button onClick={exportCsv} disabled={rows.length === 0} className="ml-auto px-3 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50 disabled:opacity-50">Export CSV</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No outstanding checks</p></div> : (
        <>
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200"><tr>
              {['Bank Account','CV #','Voucher Date','Check #','Check Date','Payee','Net Amount','Days Out','Status'].map(h =>
                <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${['Net Amount','Days Out'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>)}
            </tr></thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map(r => (
                <tr key={r.id} className="hover:bg-gray-50/60">
                  <td className="px-3 py-2.5 text-xs text-gray-700">{r.bank_name} {r.account_number}</td>
                  <td className="px-3 py-2.5 font-mono text-xs font-semibold text-gray-900">{r.cv_number}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.voucher_date}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-700">{r.check_number}</td>
                  <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.check_date}</td>
                  <td className="px-3 py-2.5 text-xs text-gray-700 max-w-[160px] truncate">{r.payee}</td>
                  <td className="px-3 py-2.5 text-right font-mono text-xs font-semibold text-gray-900">{fmt(r.net_check_amount)}</td>
                  <td className={`px-3 py-2.5 text-right font-mono text-xs font-semibold ${ageCls(r.days_outstanding)}`}>{r.days_outstanding}</td>
                  <td className="px-3 py-2.5"><StatusBadge status={r.status} /></td>
                </tr>
              ))}
            </tbody>
            <tfoot className="bg-gray-50 border-t border-gray-200">
              <tr>
                <td colSpan={6} className="px-3 py-2.5 text-xs font-semibold text-gray-600 text-right">Total ({rows.length} checks)</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(total)}</td>
                <td colSpan={2}></td>
              </tr>
            </tfoot>
          </table>
        </>
      )}
    </div>
  )
}
