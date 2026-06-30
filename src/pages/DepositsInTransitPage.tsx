import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type BankRef = { id: string; bank_name: string; account_number: string }
type DIT = {
  id: string; reconciliation_id: string; company_id: string
  description: string; document_date: string | null; amount: number; reference_doc_type: string | null
  recon_month: number; recon_year: number; bank_account_id: string
  bank_name: string; account_number: string
}

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function DepositsInTransitPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<DIT[]>([])
  const [banks, setBanks] = useState<BankRef[]>([])
  const [loading, setLoading] = useState(false)
  const [fBank, setFBank] = useState('')
  const [fMonth, setFMonth] = useState('')
  const [fYear, setFYear] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('vw_deposits_in_transit').select('*').eq('company_id', companyId).order('document_date')
    if (fBank) q = q.eq('bank_account_id', fBank)
    if (fMonth) q = q.eq('recon_month', Number(fMonth))
    if (fYear) q = q.eq('recon_year', Number(fYear))
    const { data } = await q
    setRows((data as DIT[]) || [])
    setLoading(false)
  }, [companyId, fBank, fMonth, fYear])

  const loadBanks = useCallback(async () => {
    if (!companyId) return
    const { data } = await supabase.from('bank_accounts').select('id,bank_name,account_number').eq('company_id', companyId).order('bank_name')
    setBanks((data as BankRef[]) || [])
  }, [companyId])

  useEffect(() => { if (companyId) { load(); loadBanks() } }, [load, loadBanks, companyId])

  const total = rows.reduce((s, r) => s + Number(r.amount), 0)
  const years = Array.from({ length: 6 }, (_, i) => new Date().getFullYear() - i)

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Deposits in Transit</span>
        <select value={fBank} onChange={e => setFBank(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm">
          <option value="">All banks</option>{banks.map(b => <option key={b.id} value={b.id}>{b.bank_name} — {b.account_number}</option>)}
        </select>
        <select value={fMonth} onChange={e => setFMonth(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm">
          <option value="">All months</option>{Array.from({ length: 12 }, (_, i) => i + 1).map(m => <option key={m} value={m}>{String(m).padStart(2, '0')}</option>)}
        </select>
        <select value={fYear} onChange={e => setFYear(e.target.value)} className="border border-gray-300 rounded px-2.5 py-1.5 text-sm">
          <option value="">All years</option>{years.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>
      {loading ? <div className="py-20 text-center text-sm text-gray-400">Loading...</div>
        : rows.length === 0 ? <div className="py-20 text-center"><p className="text-sm font-medium text-gray-500">No deposits in transit</p></div> : (
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200"><tr>
            {['Bank Account','Recon Period','Description','Document Date','Amount','Reference'].map(h =>
              <th key={h} className={`px-3 py-2.5 text-[10px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${h === 'Amount' ? 'text-right' : 'text-left'}`}>{h}</th>)}
          </tr></thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map(r => (
              <tr key={r.id} className="hover:bg-gray-50/60">
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.bank_name} {r.account_number}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{String(r.recon_month).padStart(2, '0')}/{r.recon_year}</td>
                <td className="px-3 py-2.5 text-xs text-gray-700">{r.description}</td>
                <td className="px-3 py-2.5 font-mono text-xs text-gray-500">{r.document_date || '—'}</td>
                <td className="px-3 py-2.5 text-right font-mono text-xs font-semibold text-gray-900">{fmt(r.amount)}</td>
                <td className="px-3 py-2.5 text-xs text-gray-500">{r.reference_doc_type || '—'}</td>
              </tr>
            ))}
          </tbody>
          <tfoot className="bg-gray-50 border-t border-gray-200"><tr>
            <td colSpan={4} className="px-3 py-2.5 text-xs font-semibold text-gray-600 text-right">Total ({rows.length})</td>
            <td className="px-3 py-2.5 text-right font-mono text-xs font-bold text-gray-900">{fmt(total)}</td>
            <td></td>
          </tr></tfoot>
        </table>
      )}
    </div>
  )
}
