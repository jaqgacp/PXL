import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Profile = { percentage_tax_registered: boolean; percentage_tax_rate: number | null; pt_filing_frequency: string | null }
type ReturnRow = { period_year: number; period_quarter: number; taxable_base: number; pt_due: number; status: string }
type Deadline = { effective_deadline: string; status: string; coverage_period_start: string; coverage_period_end: string }

const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const fmtQuarter = (y: number, q: number) => `Q${q} ${y}`

export default function PTDashboardPage() {
  const { companyId } = useAppCtx()
  const now = useMemo(() => new Date(), [])
  const currentQuarter = Math.floor(now.getMonth() / 3) + 1

  const [profile, setProfile] = useState<Profile | null>(null)
  const [current, setCurrent] = useState<ReturnRow | null>(null)
  const [trend, setTrend] = useState<ReturnRow[]>([])
  const [deadline, setDeadline] = useState<Deadline | null>(null)
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: prof }, { data: retData }, { data: dlData }] = await Promise.all([
      supabase.from('compliance_profiles').select('percentage_tax_registered,percentage_tax_rate,pt_filing_frequency').eq('company_id', companyId).maybeSingle(),
      supabase.from('pt_returns').select('period_year,period_quarter,taxable_base,pt_due,status').eq('company_id', companyId).order('period_year', { ascending: false }).order('period_quarter', { ascending: false }).limit(4),
      supabase.from('tax_calendar_events').select('effective_deadline,status,coverage_period_start,coverage_period_end,ref_compliance_forms!inner(form_code)')
        .eq('company_id', companyId).eq('ref_compliance_forms.form_code', '2551Q').eq('status', 'pending')
        .order('effective_deadline').limit(1),
    ])

    setProfile(prof as Profile || null)
    const returns = (retData as ReturnRow[]) || []
    setTrend(returns.slice().reverse())
    setCurrent(returns.find(r => r.period_year === now.getFullYear() && r.period_quarter === currentQuarter) || null)
    setDeadline((dlData?.[0] as unknown as Deadline) || null)
    setLoading(false)
  }, [companyId, now, currentQuarter])

  useEffect(() => { load() }, [load])

  const daysUntil = deadline ? Math.ceil((new Date(deadline.effective_deadline).getTime() - now.getTime()) / (1000 * 60 * 60 * 24)) : null

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Percentage Tax Dashboard</h1>
        <p className="text-sm text-gray-500 mt-0.5">BIR Form 2551Q — Quarterly Percentage Tax overview</p>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4">
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">PT Registration</p>
              <p className={`text-lg font-bold mt-1 ${profile?.percentage_tax_registered ? 'text-green-700' : 'text-gray-400'}`}>
                {profile?.percentage_tax_registered ? 'Registered' : 'Not Registered'}
              </p>
              <p className="text-xs text-gray-400 mt-0.5">Rate: {profile?.percentage_tax_rate ?? 3}%</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Current Quarter — {fmtQuarter(now.getFullYear(), currentQuarter)}</p>
              <p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(current?.taxable_base || 0)}</p>
              <p className="text-xs text-gray-400 mt-0.5">Taxable Base</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">PT Due — This Quarter</p>
              <p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(current?.pt_due || 0)}</p>
              <p className="text-xs text-gray-400 mt-0.5">{current ? current.status[0].toUpperCase() + current.status.slice(1) : 'Not yet computed'}</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Next Filing Deadline</p>
              {deadline ? (
                <>
                  <p className={`text-lg font-bold mt-1 ${daysUntil !== null && daysUntil <= 7 ? 'text-red-600' : 'text-gray-900'}`}>
                    {new Date(deadline.effective_deadline).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })}
                  </p>
                  <p className="text-xs text-gray-400 mt-0.5">{daysUntil !== null && daysUntil >= 0 ? `${daysUntil} day${daysUntil !== 1 ? 's' : ''} left` : 'Overdue'}</p>
                </>
              ) : <p className="text-sm text-gray-400 mt-1">No pending filing</p>}
            </div>
          </div>

          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100">
              <h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Last 4 Quarters — PT Trend</h2>
            </div>
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-200">
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
                  <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Taxable Base</th>
                  <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">PT Due</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                </tr>
              </thead>
              <tbody>
                {trend.length === 0 ? (
                  <tr><td colSpan={4} className="text-center py-8 text-xs text-gray-400">No PT returns computed yet.</td></tr>
                ) : trend.map(r => (
                  <tr key={`${r.period_year}-${r.period_quarter}`} className="border-b border-gray-100">
                    <td className="px-4 py-2.5 font-medium text-gray-900">{fmtQuarter(r.period_year, r.period_quarter)}</td>
                    <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.taxable_base)}</td>
                    <td className="px-4 py-2.5 text-right font-mono tabular-nums text-gray-700">{fmtNum(r.pt_due)}</td>
                    <td className="px-4 py-2.5 text-xs text-gray-600">{r.status[0].toUpperCase() + r.status.slice(1)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  )
}
