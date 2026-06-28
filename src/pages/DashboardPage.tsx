import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Company = { id: string; registered_name: string }
type TaxEvent = {
  id: string; company_id: string; effective_deadline: string; status: string
  ref_compliance_forms?: { form_code: string; form_name: string; compliance_type: string } | null
}

type DateRange = 'today' | 'this_month' | 'this_quarter' | 'ytd'

const DATE_RANGE_LABELS: Record<DateRange, string> = {
  today: 'Today',
  this_month: 'This Month',
  this_quarter: 'This Quarter',
  ytd: 'Year-to-Date',
}

// ── Mock KPI data (clearly labelled) ────────────────────────────────────────
const MOCK_CASH: Record<DateRange, { balance: number; accounts: number; change: number }> = {
  today:       { balance: 4_820_150.00, accounts: 3, change: +12500 },
  this_month:  { balance: 5_245_000.00, accounts: 3, change: +185000 },
  this_quarter:{ balance: 4_980_500.00, accounts: 3, change: -62000 },
  ytd:         { balance: 5_245_000.00, accounts: 3, change: +920000 },
}
const MOCK_AGING = {
  receivables: { current: 1_250_000, d30: 480_000, d60: 195_000, d90: 87_500 },
  payables:    { current: 890_000,   d30: 320_000, d60: 148_000, d90: 42_000 },
}
const MOCK_REVENUE: Record<DateRange, { months: { label: string; amount: number }[]; total: number; growth: number }> = {
  today: {
    months: [{ label: 'Today', amount: 185_000 }],
    total: 185_000, growth: 8.2,
  },
  this_month: {
    months: [
      { label: 'Mar', amount: 1_820_000 }, { label: 'Apr', amount: 2_150_000 },
      { label: 'May', amount: 1_940_000 }, { label: 'Jun', amount: 2_380_000 },
    ],
    total: 2_380_000, growth: 22.7,
  },
  this_quarter: {
    months: [
      { label: 'Q3 2025', amount: 5_400_000 }, { label: 'Q4 2025', amount: 6_120_000 },
      { label: 'Q1 2026', amount: 5_850_000 }, { label: 'Q2 2026', amount: 6_500_000 },
    ],
    total: 6_500_000, growth: 11.1,
  },
  ytd: {
    months: [
      { label: 'Jan', amount: 1_950_000 }, { label: 'Feb', amount: 2_020_000 },
      { label: 'Mar', amount: 1_820_000 }, { label: 'Apr', amount: 2_150_000 },
      { label: 'May', amount: 1_940_000 }, { label: 'Jun', amount: 2_380_000 },
    ],
    total: 12_260_000, growth: 15.4,
  },
}
const MOCK_ACTIVITIES = [
  { date: '2026-06-28', type: 'Purchase Order', reference: 'PO-2026-0182', amount: 485_000, action: 'Pending Approval', severity: 'warning' },
  { date: '2026-06-27', type: 'Sales Invoice', reference: 'SI-2026-1045', amount: 128_500, action: 'Overdue — 15 days', severity: 'danger' },
  { date: '2026-06-25', type: 'Payment Voucher', reference: 'PV-2026-0390', amount: 220_000, action: 'Pending Release', severity: 'warning' },
  { date: '2026-06-24', type: 'Credit Memo', reference: 'CM-2026-0042', amount: 35_000, action: 'For Approval', severity: 'info' },
  { date: '2026-06-22', type: 'Journal Entry', reference: 'JE-2026-0501', amount: 0, action: 'Unposted', severity: 'info' },
]

// ── Helpers ──────────────────────────────────────────────────────────────────
const php = (n: number) =>
  '₱' + n.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

const phpCompact = (n: number) => {
  if (n >= 1_000_000) return '₱' + (n / 1_000_000).toFixed(2) + 'M'
  if (n >= 1_000)     return '₱' + (n / 1_000).toFixed(1) + 'K'
  return '₱' + n.toLocaleString()
}

const fmtDate = (d: string) =>
  new Date(d).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })

const daysUntil = (d: string) => {
  const diff = new Date(d).getTime() - Date.now()
  return Math.ceil(diff / 86400000)
}

// ── Sample data badge ────────────────────────────────────────────────────────
const SampleBadge = () => (
  <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-amber-100 text-amber-700 border border-amber-200 leading-none">
    Sample Data
  </span>
)

// ── Mini bar chart (pure CSS) ─────────────────────────────────────────────
function MiniBarChart({ data }: { data: { label: string; amount: number }[] }) {
  const max = Math.max(...data.map(d => d.amount))
  return (
    <div className="flex items-end gap-1.5 h-14 mt-2">
      {data.map((d, i) => (
        <div key={i} className="flex flex-col items-center gap-1 flex-1">
          <div className="w-full bg-gray-900 rounded-sm transition-all"
            style={{ height: `${Math.max(4, (d.amount / max) * 48)}px` }} />
          <span className="text-[10px] text-gray-400 leading-none">{d.label}</span>
        </div>
      ))}
    </div>
  )
}

// ── Aging bar ─────────────────────────────────────────────────────────────
function AgingRow({ label, data, color }: { label: string; data: { current: number; d30: number; d60: number; d90: number }; color: string }) {
  const total = data.current + data.d30 + data.d60 + data.d90
  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <span className={`text-xs font-semibold ${color}`}>{label}</span>
        <span className="text-xs font-mono text-gray-700">{phpCompact(total)}</span>
      </div>
      <div className="flex gap-0.5 h-2 rounded overflow-hidden">
        <div title={`Current: ${phpCompact(data.current)}`} className="bg-green-400" style={{ width: `${(data.current / total) * 100}%` }} />
        <div title={`30-60d: ${phpCompact(data.d30)}`} className="bg-yellow-400" style={{ width: `${(data.d30 / total) * 100}%` }} />
        <div title={`60-90d: ${phpCompact(data.d60)}`} className="bg-orange-400" style={{ width: `${(data.d60 / total) * 100}%` }} />
        <div title={`90d+: ${phpCompact(data.d90)}`} className="bg-red-400" style={{ width: `${(data.d90 / total) * 100}%` }} />
      </div>
      <div className="flex justify-between text-[10px] text-gray-400">
        <span>Current</span><span>30–60d</span><span>60–90d</span><span>90d+</span>
      </div>
      <div className="flex justify-between text-[10px] font-mono text-gray-600">
        <span>{phpCompact(data.current)}</span>
        <span>{phpCompact(data.d30)}</span>
        <span>{phpCompact(data.d60)}</span>
        <span className="text-red-600">{phpCompact(data.d90)}</span>
      </div>
    </div>
  )
}

// ── Main component ────────────────────────────────────────────────────────────
export default function DashboardPage() {
  const { companyId, setCompanyId } = useAppCtx()
  const [companies, setCompanies] = useState<Company[]>([])
  const [taxEvents, setTaxEvents] = useState<TaxEvent[]>([])
  const [customerCount, setCustomerCount] = useState(0)
  const [supplierCount, setSupplierCount] = useState(0)
  const [dateRange, setDateRange] = useState<DateRange>('this_month')
  const [refreshing, setRefreshing] = useState(false)
  const [lastRefreshed, setLastRefreshed] = useState(new Date())

  const loadData = useCallback(async () => {
    setRefreshing(true)
    await Promise.all([
      supabase.from('companies').select('id,registered_name').eq('is_active', true).order('registered_name')
        .then(({ data }) => setCompanies(data || [])),
      companyId
        ? supabase.from('tax_calendar_events')
            .select('id,company_id,effective_deadline,status,ref_compliance_forms(form_code,form_name,compliance_type)')
            .eq('company_id', companyId)
            .eq('status', 'pending')
            .lte('effective_deadline', new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0])
            .order('effective_deadline')
            .limit(10)
            .then(({ data }) => setTaxEvents((data as unknown as TaxEvent[]) || []))
        : Promise.resolve(setTaxEvents([])),
      companyId
        ? supabase.from('customers').select('id', { count: 'exact', head: true }).eq('company_id', companyId)
            .then(({ count }) => setCustomerCount(count || 0))
        : Promise.resolve(setCustomerCount(0)),
      companyId
        ? supabase.from('suppliers').select('id', { count: 'exact', head: true }).eq('company_id', companyId)
            .then(({ count }) => setSupplierCount(count || 0))
        : Promise.resolve(setSupplierCount(0)),
    ])
    setLastRefreshed(new Date())
    setRefreshing(false)
  }, [companyId])

  useEffect(() => { loadData() }, [loadData])

  const cash = MOCK_CASH[dateRange]
  const revenue = MOCK_REVENUE[dateRange]

  // Build tax deadline rows from real data
  const taxRows = taxEvents.map(e => {
    const days = daysUntil(e.effective_deadline)
    return {
      date: e.effective_deadline,
      type: 'Tax Filing',
      reference: e.ref_compliance_forms?.form_code ?? '—',
      amount: 0,
      action: days < 0 ? `Overdue — ${Math.abs(days)} days` : days === 0 ? 'Due Today' : `Due in ${days} day${days === 1 ? '' : 's'}`,
      severity: days < 0 ? 'danger' : days <= 7 ? 'danger' : 'warning',
    }
  })
  const allActivities = [...taxRows, ...MOCK_ACTIVITIES].slice(0, 10)

  const overdueTax = taxEvents.filter(e => daysUntil(e.effective_deadline) < 0).length
  const dueSoonTax = taxEvents.filter(e => { const d = daysUntil(e.effective_deadline); return d >= 0 && d <= 7 }).length

  const inp = 'border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 bg-white'

  return (
    <div className="space-y-5">
      {/* Page header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Executive Dashboard</h1>
          <p className="text-sm text-gray-500 mt-0.5">
            Financial overview — last refreshed {lastRefreshed.toLocaleTimeString('en-PH', { hour: '2-digit', minute: '2-digit' })}
          </p>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <SampleBadge />
          <span className="text-xs text-gray-400">KPI cards show placeholder data pending live transaction modules</span>
        </div>
      </div>

      {/* Action bar */}
      <div className="flex items-center gap-3 p-4 bg-white border border-gray-200 rounded-lg">
        <div className="flex items-center gap-2">
          <label className="text-xs font-medium text-gray-500 whitespace-nowrap">Date Range</label>
          <select value={dateRange} onChange={e => setDateRange(e.target.value as DateRange)} className={inp}>
            {(Object.entries(DATE_RANGE_LABELS) as [DateRange, string][]).map(([k, v]) => (
              <option key={k} value={k}>{v}</option>
            ))}
          </select>
        </div>
        <div className="flex items-center gap-2">
          <label className="text-xs font-medium text-gray-500 whitespace-nowrap">Entity</label>
          <select value={companyId} onChange={e => setCompanyId(e.target.value)} className={inp}>
            <option value="">All Companies</option>
            {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
          </select>
        </div>
        <div className="flex-1" />
        <button onClick={loadData} disabled={refreshing}
          className="flex items-center gap-2 px-3 py-1.5 border border-gray-300 rounded-md text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50 transition-colors">
          <svg className={`h-3.5 w-3.5 ${refreshing ? 'animate-spin' : ''}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
            <path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8" /><path d="M21 3v5h-5" />
            <path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16" /><path d="M3 21v-5h5" />
          </svg>
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {/* ── KPI Widget Grid ── */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">

        {/* 1. Cash Flow Overview */}
        <div className="bg-white border border-gray-200 rounded-lg p-5 space-y-3">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Cash Flow Overview</p>
              <p className="text-xs text-gray-400 mt-0.5">{cash.accounts} bank accounts</p>
            </div>
            <SampleBadge />
          </div>
          <div>
            <div className="text-2xl font-bold font-mono tabular-nums text-gray-900">{phpCompact(cash.balance)}</div>
            <div className="text-xs text-gray-400 font-mono">{php(cash.balance)}</div>
          </div>
          <div className={`flex items-center gap-1 text-xs font-medium ${cash.change >= 0 ? 'text-green-700' : 'text-red-700'}`}>
            <svg className="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}>
              {cash.change >= 0 ? <path d="m18 15-6-6-6 6" /> : <path d="m6 9 6 6 6-6" />}
            </svg>
            {cash.change >= 0 ? '+' : ''}{phpCompact(Math.abs(cash.change))} vs prior period
          </div>
          <div className="pt-1 border-t border-gray-100">
            <div className="flex justify-between text-xs text-gray-500">
              <span>Petty Cash</span><span className="font-mono">{phpCompact(48500)}</span>
            </div>
            <div className="flex justify-between text-xs text-gray-500 mt-1">
              <span>Bank — BPI Checking</span><span className="font-mono">{phpCompact(2_840_000)}</span>
            </div>
            <div className="flex justify-between text-xs text-gray-500 mt-1">
              <span>Bank — BDO Savings</span><span className="font-mono">{phpCompact(1_931_650)}</span>
            </div>
          </div>
        </div>

        {/* 2. Receivables & Payables Aging */}
        <div className="bg-white border border-gray-200 rounded-lg p-5 space-y-4">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Receivables & Payables</p>
              <p className="text-xs text-gray-400 mt-0.5">Aging summary</p>
            </div>
            <SampleBadge />
          </div>
          <AgingRow label="Receivables" data={MOCK_AGING.receivables} color="text-green-700" />
          <div className="border-t border-gray-100 pt-3">
            <AgingRow label="Payables" data={MOCK_AGING.payables} color="text-red-700" />
          </div>
          <div className="pt-1">
            <div className="flex items-center gap-3 text-[10px] text-gray-400">
              <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-sm bg-green-400 inline-block" />Current</span>
              <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-sm bg-yellow-400 inline-block" />30–60d</span>
              <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-sm bg-orange-400 inline-block" />60–90d</span>
              <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-sm bg-red-400 inline-block" />90d+</span>
            </div>
          </div>
        </div>

        {/* 3. Tax Compliance Snapshot */}
        <div className="bg-white border border-gray-200 rounded-lg p-5 space-y-3">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Tax Compliance</p>
              <p className="text-xs text-gray-400 mt-0.5">Next 30 days</p>
            </div>
            {taxEvents.length === 0 && <SampleBadge />}
          </div>

          {taxEvents.length > 0 ? (
            <div className="space-y-2">
              {overdueTax > 0 && (
                <div className="flex items-center gap-2 p-2 bg-red-50 border border-red-100 rounded-md">
                  <div className="h-2 w-2 rounded-full bg-red-500 shrink-0" />
                  <div className="flex-1">
                    <p className="text-xs font-semibold text-red-700">{overdueTax} Overdue Filing{overdueTax > 1 ? 's' : ''}</p>
                    <p className="text-[10px] text-red-600">Penalties may apply</p>
                  </div>
                </div>
              )}
              {dueSoonTax > 0 && (
                <div className="flex items-center gap-2 p-2 bg-amber-50 border border-amber-100 rounded-md">
                  <div className="h-2 w-2 rounded-full bg-amber-500 shrink-0" />
                  <div className="flex-1">
                    <p className="text-xs font-semibold text-amber-700">{dueSoonTax} Due This Week</p>
                    <p className="text-[10px] text-amber-600">File before deadline</p>
                  </div>
                </div>
              )}
              <div className="space-y-1.5 pt-1">
                {taxEvents.slice(0, 4).map(e => {
                  const days = daysUntil(e.effective_deadline)
                  return (
                    <div key={e.id} className="flex items-center justify-between">
                      <span className="text-xs text-gray-700 font-mono">{e.ref_compliance_forms?.form_code}</span>
                      <span className={`text-[10px] font-medium px-1.5 py-0.5 rounded ${days < 0 ? 'bg-red-100 text-red-700' : days <= 7 ? 'bg-amber-100 text-amber-700' : 'bg-gray-100 text-gray-600'}`}>
                        {days < 0 ? `${Math.abs(days)}d overdue` : days === 0 ? 'Today' : `${days}d left`}
                      </span>
                    </div>
                  )
                })}
              </div>
            </div>
          ) : (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-600">VAT Payable (est.)</span>
                <span className="text-xs font-mono font-semibold text-gray-900">{phpCompact(142_800)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-600">EWT Payable (est.)</span>
                <span className="text-xs font-mono font-semibold text-gray-900">{phpCompact(38_500)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-600">Next Deadline</span>
                <span className="text-xs font-medium text-amber-700">Jul 20, 2026</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-xs text-gray-600">Pending Filings</span>
                <span className="text-xs font-medium text-gray-700">3</span>
              </div>
              <p className="text-[10px] text-gray-400 pt-1">Select a company with a Compliance Profile to see real deadlines</p>
            </div>
          )}
        </div>

        {/* 4. Revenue Trends */}
        <div className="bg-white border border-gray-200 rounded-lg p-5 space-y-3">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Revenue Trends</p>
              <p className="text-xs text-gray-400 mt-0.5">Gross sales — {DATE_RANGE_LABELS[dateRange].toLowerCase()}</p>
            </div>
            <SampleBadge />
          </div>
          <div>
            <div className="text-2xl font-bold font-mono tabular-nums text-gray-900">{phpCompact(revenue.total)}</div>
            <div className={`flex items-center gap-1 text-xs font-medium mt-0.5 ${revenue.growth >= 0 ? 'text-green-700' : 'text-red-700'}`}>
              <svg className="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}>
                {revenue.growth >= 0 ? <path d="m18 15-6-6-6 6" /> : <path d="m6 9 6 6 6-6" />}
              </svg>
              {revenue.growth >= 0 ? '+' : ''}{revenue.growth}% vs prior period
            </div>
          </div>
          <MiniBarChart data={revenue.months} />
          <div className="pt-1 border-t border-gray-100 flex justify-between text-xs text-gray-500">
            <span>Customers: <span className="font-semibold text-gray-700">{customerCount}</span></span>
            <span>Suppliers: <span className="font-semibold text-gray-700">{supplierCount}</span></span>
          </div>
        </div>
      </div>

      {/* ── Recent Critical Activities ── */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <div>
            <h2 className="text-sm font-semibold text-gray-900">Recent Critical Activities</h2>
            <p className="text-xs text-gray-400 mt-0.5">Items requiring executive attention</p>
          </div>
          <div className="flex items-center gap-2">
            {taxRows.length > 0 && (
              <span className="text-xs text-gray-500">{taxRows.length} real tax deadline{taxRows.length > 1 ? 's' : ''} from compliance profile</span>
            )}
            {MOCK_ACTIVITIES.length > 0 && (
              <SampleBadge />
            )}
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm" aria-label="Critical activities list">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Date', 'Document Type', 'Reference', 'Amount', 'Action Required'].map(h => (
                  <th key={h} className="px-5 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wide whitespace-nowrap">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {allActivities.map((a, i) => (
                <tr key={i} className="hover:bg-gray-50 transition-colors group">
                  <td className="px-5 py-3 text-xs text-gray-500 whitespace-nowrap">{fmtDate(a.date)}</td>
                  <td className="px-5 py-3">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                      a.type === 'Tax Filing'      ? 'bg-indigo-50 text-indigo-700' :
                      a.type === 'Sales Invoice'   ? 'bg-blue-50 text-blue-700' :
                      a.type === 'Purchase Order'  ? 'bg-purple-50 text-purple-700' :
                      a.type === 'Payment Voucher' ? 'bg-orange-50 text-orange-700' :
                      a.type === 'Credit Memo'     ? 'bg-teal-50 text-teal-700' :
                                                     'bg-gray-100 text-gray-600'
                    }`}>{a.type}</span>
                  </td>
                  <td className="px-5 py-3 font-mono font-medium text-gray-900 text-xs">{a.reference}</td>
                  <td className="px-5 py-3 text-right font-mono text-sm tabular-nums text-gray-700">
                    {a.amount > 0 ? php(a.amount) : <span className="text-gray-300">—</span>}
                  </td>
                  <td className="px-5 py-3">
                    <span className={`inline-flex items-center gap-1.5 text-xs font-medium ${
                      a.severity === 'danger'  ? 'text-red-700' :
                      a.severity === 'warning' ? 'text-amber-700' :
                                                 'text-blue-700'
                    }`}>
                      <span className={`h-1.5 w-1.5 rounded-full shrink-0 ${
                        a.severity === 'danger'  ? 'bg-red-500' :
                        a.severity === 'warning' ? 'bg-amber-500' :
                                                   'bg-blue-500'
                      }`} />
                      {a.action}
                    </span>
                  </td>
                </tr>
              ))}
              {!allActivities.length && (
                <tr>
                  <td colSpan={5} className="px-5 py-10 text-center text-gray-400">
                    No critical activities to show
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="px-5 py-3 border-t border-gray-100 bg-gray-50 flex items-center justify-between">
          <span className="text-xs text-gray-400">
            Showing {allActivities.length} items
            {taxRows.length > 0 ? ` (${taxRows.length} live, ${MOCK_ACTIVITIES.length} sample)` : ' (sample data)'}
          </span>
          <span className="text-xs text-gray-400">Transaction modules required for full live data</span>
        </div>
      </div>
    </div>
  )
}
