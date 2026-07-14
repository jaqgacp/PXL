import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

// ── Types ─────────────────────────────────────────────────────────────────────
type Customer = { id: string; registered_name: string }

type OpenInvoice = {
  id: string; si_number: string; date: string; due_date: string | null
  customer_id: string; customer_name_snapshot: string; customer_tin_snapshot: string | null
  total_amount: number; paid: number; balance: number; days_overdue: number
}

type GroupRow = {
  customer_id: string; customer_name: string
  invoice_count: number; total_ar: number; overdue_amount: number
  oldest_due: string | null
  invoices: OpenInvoice[]
}

// ── Helpers ───────────────────────────────────────────────────────────────────
const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

function ageBucket(days: number) {
  if (days <= 0) return { label: 'Current', color: 'text-green-700' }
  if (days <= 30) return { label: '1–30 days', color: 'text-amber-600' }
  if (days <= 60) return { label: '31–60 days', color: 'text-orange-600' }
  if (days <= 90) return { label: '61–90 days', color: 'text-red-500' }
  return { label: '90+ days', color: 'text-red-700 font-bold' }
}

// ── Component ─────────────────────────────────────────────────────────────────
export default function CollectionMonitoringPage() {
  const { companyId } = useAppCtx()
  const [asOfDate, setAsOfDate] = useState(today())
  const [filterCustomer, setFilterCustomer] = useState('')
  const [filterOverdue, setFilterOverdue] = useState(false)
  const [loading, setLoading] = useState(false)
  const [groups, setGroups] = useState<GroupRow[]>([])
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [customers, setCustomers] = useState<Customer[]>([])

  useEffect(() => {
    if (!companyId) return
    supabase.from('customers').select('id,registered_name')
      .eq('company_id', companyId).eq('is_active', true).order('registered_name')
      .then(({ data }) => setCustomers(data as Customer[] || []))
  }, [companyId])

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true); setGroups([]); setExpanded(new Set())
    const asOf = new Date(asOfDate)

    let q = supabase.from('sales_invoices')
      .select('id,si_number,date,due_date,customer_id,customer_name_snapshot,customer_tin_snapshot,total_amount')
      .eq('company_id', companyId).eq('status', 'posted')
    if (filterCustomer) q = q.eq('customer_id', filterCustomer)

    const { data: invoices } = await q
    if (!invoices || invoices.length === 0) { setLoading(false); return }

    const ids = invoices.map(i => i.id)
    const { data: rlines } = await supabase.from('receipt_lines')
      .select('invoice_id,payment_amount,cwt_amount,receipts(status)')
      .in('invoice_id', ids)

    // Compute paid amounts (exclude bounced receipts)
    const paidMap: Record<string, number> = {}
    for (const rl of rlines || []) {
      if (!rl.invoice_id) continue
      const rec = Array.isArray(rl.receipts) ? rl.receipts[0] : rl.receipts
      if ((rec as { status?: string })?.status === 'bounced') continue
      paidMap[rl.invoice_id] = (paidMap[rl.invoice_id] || 0) + Number(rl.payment_amount) + Number(rl.cwt_amount)
    }

    const openInvoices: OpenInvoice[] = invoices
      .map(inv => {
        const total = Number(inv.total_amount)
        const paid  = paidMap[inv.id] || 0
        const balance = Math.max(total - paid, 0)
        const dueDate = inv.due_date ? new Date(inv.due_date) : null
        const days_overdue = dueDate ? Math.floor((asOf.getTime() - dueDate.getTime()) / 86400000) : 0
        return { ...inv, total_amount: total, paid, balance, days_overdue }
      })
      .filter(inv => inv.balance > 0.005) // filter fully paid
      .filter(inv => !filterOverdue || inv.days_overdue > 0)

    // Group by customer
    const byCustomer: Record<string, OpenInvoice[]> = {}
    for (const inv of openInvoices) {
      if (!byCustomer[inv.customer_id]) byCustomer[inv.customer_id] = []
      byCustomer[inv.customer_id].push(inv)
    }

    const grouped: GroupRow[] = Object.entries(byCustomer).map(([cid, invs]) => {
      invs.sort((a, b) => (a.due_date || '') < (b.due_date || '') ? -1 : 1)
      return {
        customer_id: cid,
        customer_name: invs[0].customer_name_snapshot,
        invoice_count: invs.length,
        total_ar: invs.reduce((s, i) => s + i.balance, 0),
        overdue_amount: invs.filter(i => i.days_overdue > 0).reduce((s, i) => s + i.balance, 0),
        oldest_due: invs[0]?.due_date || null,
        invoices: invs,
      }
    })
    grouped.sort((a, b) => b.overdue_amount - a.overdue_amount || b.total_ar - a.total_ar)

    setGroups(grouped)
    setLoading(false)
  }, [companyId, asOfDate, filterCustomer, filterOverdue])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  const toggleExpand = (cid: string) => {
    setExpanded(prev => {
      const next = new Set(prev)
      if (next.has(cid)) next.delete(cid)
      else next.add(cid)
      return next
    })
  }

  const grandTotal   = groups.reduce((s, g) => s + g.total_ar, 0)
  const overdueTotal = groups.reduce((s, g) => s + g.overdue_amount, 0)

  return (
    <div>
      {/* Toolbar */}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
        <label className="text-xs text-gray-500 whitespace-nowrap">As of</label>
        <input type="date" value={asOfDate} onChange={e => setAsOfDate(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
        <select value={filterCustomer} onChange={e => setFilterCustomer(e.target.value)}
          className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 max-w-[200px]">
          <option value="">All Customers</option>
          {customers.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        <label className="flex items-center gap-1.5 text-xs text-gray-600 cursor-pointer">
          <input type="checkbox" checked={filterOverdue} onChange={e => setFilterOverdue(e.target.checked)} className="h-3.5 w-3.5" />
          Overdue only
        </label>
        <button onClick={run} className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">Run</button>
        {!companyId && <span className="text-xs text-gray-400">Select a company first</span>}
      </div>

      {/* KPI Strip */}
      <div className="bg-white border-b border-gray-200 grid grid-cols-2 md:grid-cols-4 divide-x divide-gray-200">
        {[
          { label: 'Total Open AR', value: grandTotal, accent: false },
          { label: 'Total Overdue', value: overdueTotal, accent: true },
          { label: 'Customers with Balance', value: groups.length, money: false },
          { label: 'Open Invoices', value: groups.reduce((s, g) => s + g.invoice_count, 0), money: false },
        ].map(kpi => (
          <div key={kpi.label} className="px-5 py-3">
            <div className="text-[11px] font-medium text-gray-400 uppercase tracking-wide">{kpi.label}</div>
            <div className={`text-xl font-mono tabular-nums font-bold mt-0.5 ${kpi.accent ? 'text-red-700' : 'text-gray-900'}`}>
              {kpi.money === false ? kpi.value.toLocaleString() : fmt(kpi.value as number)}
            </div>
          </div>
        ))}
      </div>

      {loading ? (
        <div className="divide-y divide-gray-100">{[...Array(5)].map((_, i) => <div key={i} className="px-5 py-4 animate-pulse"><div className="h-4 bg-gray-100 rounded w-48 mb-2" /><div className="h-3 bg-gray-50 rounded w-32" /></div>)}</div>
      ) : groups.length === 0 ? (
        <div className="py-20 text-center">
          <p className="text-sm font-medium text-gray-500">No open balances</p>
          <p className="text-xs text-gray-400 mt-1">All invoices are fully paid as of {asOfDate}.</p>
        </div>
      ) : (
        <div className="divide-y divide-gray-100">
          {groups.map(g => {
            const isOpen = expanded.has(g.customer_id)
            return (
              <div key={g.customer_id}>
                {/* Customer summary row */}
                <button
                  onClick={() => toggleExpand(g.customer_id)}
                  className="w-full px-5 py-3 flex items-center gap-4 text-left hover:bg-gray-50/60 transition-colors">
                  <svg className={`h-3.5 w-3.5 text-gray-400 flex-shrink-0 transition-transform ${isOpen ? 'rotate-90' : ''}`}
                    viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M9 18l6-6-6-6" /></svg>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-semibold text-gray-900 truncate">{g.customer_name}</div>
                    <div className="text-xs text-gray-400 mt-0.5">
                      {g.invoice_count} invoice{g.invoice_count !== 1 ? 's' : ''}
                      {g.oldest_due && ` · oldest due ${g.oldest_due}`}
                    </div>
                  </div>
                  {g.overdue_amount > 0 && (
                    <span className="text-xs font-semibold text-red-600 bg-red-50 px-2 py-0.5 rounded">
                      {fmt(g.overdue_amount)} overdue
                    </span>
                  )}
                  <div className="text-right">
                    <div className="font-mono text-sm font-bold tabular-nums text-gray-900">{fmt(g.total_ar)}</div>
                    <div className="text-[10px] text-gray-400">outstanding</div>
                  </div>
                </button>

                {/* Invoice detail rows */}
                {isOpen && (
                  <div className="overflow-x-auto border-t border-gray-100 bg-gray-50/30">
                    <table className="w-full text-xs">
                      <thead className="border-b border-gray-200">
                        <tr>
                          {['SI Number','Date','Due Date','Age','Invoice Total','Paid','Balance Due'].map(h => (
                            <th key={h} className={`px-4 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-400 ${['Invoice Total','Paid','Balance Due'].includes(h) ? 'text-right' : 'text-left'}`}>{h}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-gray-100">
                        {g.invoices.map(inv => {
                          const bucket = ageBucket(inv.days_overdue)
                          return (
                            <tr key={inv.id} className="hover:bg-white/80">
                              <td className="px-4 py-2 font-mono font-semibold text-gray-900">{inv.si_number}</td>
                              <td className="px-4 py-2 text-gray-600">{inv.date}</td>
                              <td className="px-4 py-2 text-gray-600">{inv.due_date || '—'}</td>
                              <td className={`px-4 py-2 ${bucket.color}`}>{bucket.label}</td>
                              <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-700">{fmt(inv.total_amount)}</td>
                              <td className="px-4 py-2 text-right font-mono tabular-nums text-green-700">{inv.paid > 0 ? fmt(inv.paid) : '—'}</td>
                              <td className="px-4 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(inv.balance)}</td>
                            </tr>
                          )
                        })}
                      </tbody>
                      <tfoot className="border-t border-gray-200">
                        <tr>
                          <td colSpan={4} className="px-4 py-2 text-[10px] font-semibold text-gray-400 uppercase">Customer Total</td>
                          <td className="px-4 py-2 text-right font-mono tabular-nums font-bold text-gray-700 text-xs">{fmt(g.invoices.reduce((s, i) => s + i.total_amount, 0))}</td>
                          <td className="px-4 py-2 text-right font-mono tabular-nums text-green-700 text-xs">{fmt(g.invoices.reduce((s, i) => s + i.paid, 0))}</td>
                          <td className="px-4 py-2 text-right font-mono tabular-nums font-bold text-gray-900 text-xs">{fmt(g.total_ar)}</td>
                        </tr>
                      </tfoot>
                    </table>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}

      {/* Grand total footer */}
      {groups.length > 0 && (
        <div className="sticky bottom-0 bg-white border-t-2 border-gray-300 px-5 py-3 flex justify-between text-sm font-bold text-gray-900">
          <span>{groups.length} customer{groups.length !== 1 ? 's' : ''} · {groups.reduce((s, g) => s + g.invoice_count, 0)} open invoices</span>
          <span className="font-mono tabular-nums">{fmt(grandTotal)}</span>
        </div>
      )}
    </div>
  )
}
