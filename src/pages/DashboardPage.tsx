import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, DateCell } from '@/components/ui/shared'

// ── Types ─────────────────────────────────────────────────────
type Company = { id: string; registered_name: string }

type TaxEvent = {
  id: string
  effective_deadline: string
  statutory_deadline: string
  coverage_period_start: string
  coverage_period_end: string
  status: 'pending' | 'filed' | 'late'
  date_filed: string | null
  efps_reference_no: string | null
  ref_compliance_forms: { form_code: string; form_name: string; compliance_type: string } | null
}

type Counts = {
  companies: number
  branches: number
  customers: number
  suppliers: number
  items: number
  accounts: number
  workflows: number
}

type SetupItem = { label: string; done: boolean; page?: string }

// ── Helpers ──────────────────────────────────────────────────
const daysUntil = (d: string) =>
  Math.ceil((new Date(d).getTime() - Date.now()) / 86_400_000)

const fmtDeadline = (days: number) => {
  if (days < 0) return { label: `${Math.abs(days)}d overdue`, cls: 'text-red-700 bg-red-50' }
  if (days === 0) return { label: 'Due today', cls: 'text-red-700 bg-red-50' }
  if (days <= 7)  return { label: `${days}d left`, cls: 'text-amber-700 bg-amber-50' }
  return { label: `${days}d left`, cls: 'text-gray-600 bg-gray-100' }
}

const COMPLIANCE_TYPE_LABEL: Record<string, string> = {
  vat: 'VAT', ewt: 'EWT', fwt: 'FWT',
  income_tax: 'Income Tax', alphalist: 'Alphalist',
  information: 'Information Return', lgu: 'LGU',
}

// ── KPI Card ─────────────────────────────────────────────────
function KpiCard({ label, value, sub, danger }: {
  label: string; value: number | string; sub?: string; danger?: boolean
}) {
  return (
    <div className="bg-white border border-gray-200 px-4 py-3 flex flex-col gap-0.5">
      <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">{label}</span>
      <span className={`text-2xl font-semibold tabular-nums leading-tight ${danger && Number(value) > 0 ? 'text-red-700' : 'text-gray-900'}`}>
        {value}
      </span>
      {sub && <span className="text-xs text-gray-400">{sub}</span>}
    </div>
  )
}

// ── Empty state for widgets ───────────────────────────────────
function WidgetEmpty({ message }: { message: string }) {
  return (
    <div className="py-8 text-center text-sm text-gray-400">{message}</div>
  )
}

// ── Main ──────────────────────────────────────────────────────
export default function DashboardPage() {
  const { companyId, setCompanyId } = useAppCtx()
  const [companies, setCompanies] = useState<Company[]>([])
  const [events, setEvents] = useState<TaxEvent[]>([])
  const [counts, setCounts] = useState<Counts>({ companies: 0, branches: 0, customers: 0, suppliers: 0, items: 0, accounts: 0, workflows: 0 })
  const [setupItems, setSetupItems] = useState<SetupItem[]>([])
  const [loading, setLoading] = useState(true)
  const [lastRefreshed, setLastRefreshed] = useState<Date | null>(null)

  const load = useCallback(async () => {
    setLoading(true)

    // Companies always loaded
    const { data: cos } = await supabase
      .from('companies').select('id,registered_name').eq('is_active', true).order('registered_name')
    setCompanies(cos || [])

    const cid = companyId

    // Global counts
    const [{ count: coCount }, { count: brCount }] = await Promise.all([
      supabase.from('companies').select('*', { count: 'exact', head: true }).eq('is_active', true),
      cid ? supabase.from('branches').select('*', { count: 'exact', head: true }).eq('company_id', cid).eq('is_active', true)
           : Promise.resolve({ count: 0 }),
    ])

    // Company-scoped counts
    const [{ count: custCount }, { count: suppCount }, { count: itemCount },
      { count: acctCount }, { count: wfCount }] = await Promise.all([
      cid ? supabase.from('customers').select('*', { count: 'exact', head: true }).eq('company_id', cid).eq('is_active', true)
          : Promise.resolve({ count: 0 }),
      cid ? supabase.from('suppliers').select('*', { count: 'exact', head: true }).eq('company_id', cid).eq('is_active', true)
          : Promise.resolve({ count: 0 }),
      cid ? supabase.from('items').select('*', { count: 'exact', head: true }).eq('company_id', cid).eq('is_active', true)
          : Promise.resolve({ count: 0 }),
      cid ? supabase.from('chart_of_accounts').select('*', { count: 'exact', head: true }).eq('company_id', cid)
          : Promise.resolve({ count: 0 }),
      cid ? supabase.from('approval_workflows').select('*', { count: 'exact', head: true }).eq('company_id', cid).eq('is_active', true)
          : Promise.resolve({ count: 0 }),
    ])

    setCounts({
      companies: coCount || 0, branches: brCount || 0,
      customers: custCount || 0, suppliers: suppCount || 0,
      items: itemCount || 0, accounts: acctCount || 0, workflows: wfCount || 0,
    })

    // Tax calendar events (next 90 days + overdue)
    if (cid) {
      const ninetyDays = new Date(Date.now() + 90 * 86_400_000).toISOString().split('T')[0]
      const { data: evts } = await supabase
        .from('tax_calendar_events')
        .select('id,effective_deadline,statutory_deadline,coverage_period_start,coverage_period_end,status,date_filed,efps_reference_no,ref_compliance_forms(form_code,form_name,compliance_type)')
        .eq('company_id', cid)
        .neq('status', 'filed')
        .lte('effective_deadline', ninetyDays)
        .order('effective_deadline')
        .limit(25)
      setEvents((evts as unknown as TaxEvent[]) || [])
    } else {
      setEvents([])
    }

    // Setup checklist — real checks against actual data
    if (cid) {
      const [{ count: cpCount }, { count: fyCount }, { count: currCount },
        { count: tcCount }, { count: nsCount }] = await Promise.all([
        supabase.from('compliance_profiles').select('*', { count: 'exact', head: true }).eq('company_id', cid),
        supabase.from('fiscal_years').select('*', { count: 'exact', head: true }).eq('company_id', cid),
        supabase.from('currencies').select('*', { count: 'exact', head: true }).eq('is_active', true),
        supabase.from('tax_codes').select('*', { count: 'exact', head: true }),
        supabase.from('number_series').select('*', { count: 'exact', head: true }).eq('company_id', cid),
      ])
      setSetupItems([
        { label: 'Company configured', done: (coCount || 0) > 0, page: 'company-setup' },
        { label: 'Branch set up', done: (brCount || 0) > 0, page: 'branch-setup' },
        { label: 'Chart of Accounts', done: (acctCount || 0) > 0, page: 'chart-of-accounts' },
        { label: 'Fiscal Year defined', done: (fyCount || 0) > 0, page: 'fiscal-years' },
        { label: 'Currencies configured', done: (currCount || 0) > 0, page: 'currency-setup' },
        { label: 'Tax codes set up', done: (tcCount || 0) > 0, page: 'tax-setup' },
        { label: 'Compliance profile', done: (cpCount || 0) > 0, page: 'compliance-profile' },
        { label: 'Number series', done: (nsCount || 0) > 0, page: 'number-series' },
      ])
    } else {
      setSetupItems([])
    }

    setLastRefreshed(new Date())
    setLoading(false)
  }, [companyId])

  useEffect(() => { load() }, [load])

  // Derived metrics
  const overdue = events.filter(e => e.status === 'late' || (e.status === 'pending' && daysUntil(e.effective_deadline) < 0))
  const dueThisWeek = events.filter(e => { const d = daysUntil(e.effective_deadline); return e.status === 'pending' && d >= 0 && d <= 7 })
  const setupDone = setupItems.filter(s => s.done).length
  const setupTotal = setupItems.length

  const sel = 'border border-gray-300 rounded px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white'

  return (
    <div className="space-y-0 divide-y divide-gray-200">

      {/* Action bar */}
      <div className="bg-white px-5 py-2.5 flex items-center gap-4">
        <div className="flex items-center gap-2">
          <label className="text-xs text-gray-500 font-medium whitespace-nowrap">Company</label>
          <select value={companyId} onChange={e => setCompanyId(e.target.value)} className={sel}>
            <option value="">All Companies</option>
            {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
          </select>
        </div>
        <div className="flex-1" />
        {lastRefreshed && (
          <span className="text-xs text-gray-400">
            Updated {lastRefreshed.toLocaleTimeString('en-PH', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
          </span>
        )}
        <button onClick={load} disabled={loading}
          className="flex items-center gap-1.5 px-3 py-1.5 border border-gray-300 rounded text-xs text-gray-600 hover:bg-gray-50 disabled:opacity-50">
          <svg className={`h-3 w-3 ${loading ? 'animate-spin' : ''}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}>
            <path d="M3 12a9 9 0 019-9 9.75 9.75 0 016.74 2.74L21 8M21 3v5h-5M21 12a9 9 0 01-9 9 9.75 9.75 0 01-6.74-2.74L3 16M3 21v-5h5" />
          </svg>
          Refresh
        </button>
      </div>

      {/* KPI strip */}
      <div className="grid grid-cols-2 md:grid-cols-4 divide-x divide-gray-200">
        <KpiCard
          label="Overdue Filings"
          value={loading ? '—' : overdue.length}
          sub={overdue.length > 0 ? 'Penalties may apply' : 'All current'}
          danger
        />
        <KpiCard
          label="Due This Week"
          value={loading ? '—' : dueThisWeek.length}
          sub={dueThisWeek.length > 0 ? 'Action required' : 'No urgent deadlines'}
        />
        <KpiCard
          label="Active Companies"
          value={loading ? '—' : counts.companies}
          sub={counts.branches > 0 ? `${counts.branches} branch${counts.branches !== 1 ? 'es' : ''}` : 'No branches yet'}
        />
        <KpiCard
          label={companyId ? 'Master Records' : 'Select Company'}
          value={loading ? '—' : companyId ? counts.customers + counts.suppliers + counts.items : '—'}
          sub={companyId ? `${counts.customers} customers · ${counts.suppliers} suppliers · ${counts.items} items` : 'Select a company to view'}
        />
      </div>

      {/* Main body */}
      <div className="grid grid-cols-1 xl:grid-cols-3 divide-y xl:divide-y-0 xl:divide-x divide-gray-200">

        {/* Tax Compliance Schedule — left 2/3 */}
        <div className="xl:col-span-2">
          <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between bg-white">
            <div>
              <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-500">Tax Compliance Schedule</h2>
              <p className="text-xs text-gray-400 mt-0.5">Pending filings — next 90 days + overdue</p>
            </div>
            {events.length > 0 && (
              <div className="flex items-center gap-2">
                {overdue.length > 0 && (
                  <span className="text-xs font-medium text-red-700 bg-red-50 px-2 py-0.5 rounded">
                    {overdue.length} overdue
                  </span>
                )}
                {dueThisWeek.length > 0 && (
                  <span className="text-xs font-medium text-amber-700 bg-amber-50 px-2 py-0.5 rounded">
                    {dueThisWeek.length} this week
                  </span>
                )}
              </div>
            )}
          </div>

          {!companyId ? (
            <WidgetEmpty message="Select a company in the toolbar to view the tax compliance schedule." />
          ) : loading ? (
            <div className="divide-y divide-gray-100">
              {[...Array(5)].map((_, i) => (
                <div key={i} className="px-5 py-3 flex gap-4 animate-pulse">
                  <div className="h-3 bg-gray-100 rounded w-16" />
                  <div className="h-3 bg-gray-100 rounded flex-1" />
                  <div className="h-3 bg-gray-100 rounded w-20" />
                </div>
              ))}
            </div>
          ) : events.length === 0 ? (
            <WidgetEmpty message="No pending tax deadlines in the next 90 days. Set up a Compliance Profile to generate the Tax Calendar." />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm" aria-label="Tax compliance schedule">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Form', 'Type', 'Coverage Period', 'Effective Deadline', 'Status', 'Days'].map(h => (
                      <th key={h} className="px-4 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {events.map(e => {
                    const days = daysUntil(e.effective_deadline)
                    const urgency = fmtDeadline(days)
                    const isOverdue = e.status === 'late' || days < 0
                    return (
                      <tr key={e.id} className={`hover:bg-gray-50 transition-colors ${isOverdue ? 'bg-red-50/40' : ''}`}>
                        <td className="px-4 py-2.5 font-mono text-xs font-semibold text-gray-900 whitespace-nowrap">
                          {e.ref_compliance_forms?.form_code ?? '—'}
                        </td>
                        <td className="px-4 py-2.5">
                          <span className="text-[11px] font-medium text-gray-500">
                            {COMPLIANCE_TYPE_LABEL[e.ref_compliance_forms?.compliance_type ?? ''] ?? '—'}
                          </span>
                        </td>
                        <td className="px-4 py-2.5 text-xs text-gray-500 whitespace-nowrap">
                          {new Date(e.coverage_period_start).toLocaleDateString('en-PH', { month: 'short', year: 'numeric' })}
                          {' – '}
                          {new Date(e.coverage_period_end).toLocaleDateString('en-PH', { month: 'short', year: 'numeric' })}
                        </td>
                        <td className="px-4 py-2.5 text-xs font-mono text-gray-700 whitespace-nowrap">
                          {new Date(e.effective_deadline).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })}
                        </td>
                        <td className="px-4 py-2.5">
                          <StatusBadge status={isOverdue ? 'error' : e.status} label={isOverdue ? 'Overdue' : e.status.charAt(0).toUpperCase() + e.status.slice(1)} />
                        </td>
                        <td className="px-4 py-2.5">
                          <span className={`text-[11px] font-medium px-2 py-0.5 rounded ${urgency.cls}`}>
                            {urgency.label}
                          </span>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Right panel — Setup Status + Master Data counts */}
        <div className="divide-y divide-gray-200">

          {/* Master Data Counts */}
          <div>
            <div className="px-5 py-3 bg-white border-b border-gray-100">
              <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-500">Master Data</h2>
            </div>
            {!companyId ? (
              <WidgetEmpty message="Select a company." />
            ) : (
              <div className="divide-y divide-gray-100">
                {[
                  { label: 'Chart of Accounts', value: counts.accounts },
                  { label: 'Customers', value: counts.customers },
                  { label: 'Suppliers', value: counts.suppliers },
                  { label: 'Items', value: counts.items },
                  { label: 'Branches', value: counts.branches },
                  { label: 'Approval Workflows', value: counts.workflows },
                ].map(row => (
                  <div key={row.label} className="px-5 py-2.5 flex items-center justify-between hover:bg-gray-50">
                    <span className="text-sm text-gray-600">{row.label}</span>
                    <span className={`text-sm font-mono font-semibold tabular-nums ${loading ? 'text-gray-300' : 'text-gray-900'}`}>
                      {loading ? '—' : row.value.toLocaleString()}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Setup Checklist */}
          <div>
            <div className="px-5 py-3 bg-white border-b border-gray-100 flex items-center justify-between">
              <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-500">Setup Checklist</h2>
              {setupTotal > 0 && (
                <span className="text-xs text-gray-400">{setupDone}/{setupTotal} complete</span>
              )}
            </div>
            {!companyId ? (
              <WidgetEmpty message="Select a company." />
            ) : loading ? (
              <WidgetEmpty message="Loading…" />
            ) : setupItems.length === 0 ? (
              <WidgetEmpty message="No setup data available." />
            ) : (
              <div className="divide-y divide-gray-100">
                {setupItems.map(item => (
                  <div key={item.label} className="px-5 py-2.5 flex items-center gap-3">
                    <span className={`h-4 w-4 rounded-full flex items-center justify-center shrink-0 ${item.done ? 'bg-green-500' : 'bg-gray-200'}`}>
                      {item.done && (
                        <svg className="h-2.5 w-2.5 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3}>
                          <path d="M5 12l5 5L20 7" />
                        </svg>
                      )}
                    </span>
                    <span className={`text-sm ${item.done ? 'text-gray-700' : 'text-gray-400'}`}>{item.label}</span>
                    {!item.done && item.page && (
                      <span className="ml-auto text-[11px] text-gray-400 bg-gray-100 px-1.5 py-0.5 rounded">Setup required</span>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>

        </div>
      </div>

      {/* Recent Critical Activities */}
      <div>
        <div className="px-5 py-3 bg-white border-b border-gray-100">
          <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-500">Recent Critical Activities</h2>
          <p className="text-xs text-gray-400 mt-0.5">Overdue and urgent items requiring action</p>
        </div>
        {!companyId ? (
          <WidgetEmpty message="Select a company to view critical activities." />
        ) : loading ? (
          <WidgetEmpty message="Loading…" />
        ) : overdue.length === 0 && dueThisWeek.length === 0 ? (
          <WidgetEmpty message="No critical activities. All tax filings are current." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm" aria-label="Critical activities">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  {['Effective Deadline', 'Document Type', 'Reference', 'Coverage Period', 'Action Required'].map(h => (
                    <th key={h} className="px-5 py-2.5 text-left text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {[...overdue, ...dueThisWeek].slice(0, 15).map(e => {
                  const days = daysUntil(e.effective_deadline)
                  const isOv = days < 0
                  return (
                    <tr key={e.id} className={`hover:bg-gray-50 transition-colors ${isOv ? 'bg-red-50/30' : 'bg-amber-50/20'}`}>
                      <td className="px-5 py-2.5 text-xs font-mono text-gray-700 whitespace-nowrap">
                        <DateCell date={e.effective_deadline} />
                      </td>
                      <td className="px-5 py-2.5">
                        <span className="text-xs font-medium text-indigo-700 bg-indigo-50 px-2 py-0.5 rounded">
                          Tax Filing
                        </span>
                      </td>
                      <td className="px-5 py-2.5 font-mono text-xs font-semibold text-gray-900">
                        {e.ref_compliance_forms?.form_code ?? '—'}
                      </td>
                      <td className="px-5 py-2.5 text-xs text-gray-500 whitespace-nowrap">
                        {new Date(e.coverage_period_start).toLocaleDateString('en-PH', { month: 'short', year: 'numeric' })}
                        {' – '}
                        {new Date(e.coverage_period_end).toLocaleDateString('en-PH', { month: 'short', year: 'numeric' })}
                      </td>
                      <td className="px-5 py-2.5">
                        <span className={`inline-flex items-center gap-1.5 text-xs font-medium ${isOv ? 'text-red-700' : 'text-amber-700'}`}>
                          <span className={`h-1.5 w-1.5 rounded-full shrink-0 ${isOv ? 'bg-red-500' : 'bg-amber-500'}`} />
                          {isOv
                            ? `File immediately — ${Math.abs(days)} day${Math.abs(days) !== 1 ? 's' : ''} overdue`
                            : `File before ${new Date(e.effective_deadline).toLocaleDateString('en-PH', { month: 'short', day: 'numeric' })}`}
                        </span>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
        <div className="px-5 py-2 border-t border-gray-100 bg-gray-50">
          <span className="text-xs text-gray-400">
            {companyId && !loading
              ? `${overdue.length + dueThisWeek.length} item${overdue.length + dueThisWeek.length !== 1 ? 's' : ''} shown · Transaction modules (Sales, Purchasing, Accounting) will surface additional activities when built`
              : 'Select a company to load activities'}
          </span>
        </div>
      </div>

    </div>
  )
}
