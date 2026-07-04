import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Profile = { income_tax_regime: string; corporate_tax_rate: number; mcit_applicable: boolean; nolco_applicable: boolean }
type Deadline = { effective_deadline: string; form_code: string }
type Computation = { taxable_income: number; tax_due: number }

const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function IncomeTaxDashboardPage() {
  const { companyId } = useAppCtx()
  const now = useMemo(() => new Date(), [])
  const quarter = Math.ceil((now.getMonth() + 1) / 3)

  const [profile, setProfile] = useState<Profile | null>(null)
  const [latestComputation, setLatestComputation] = useState<Computation | null>(null)
  const [nolcoBalance, setNolcoBalance] = useState(0)
  const [deadlines, setDeadlines] = useState<Deadline[]>([])
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const [{ data: prof }, { data: compData }, { data: nolcoData }, { data: dlData }] = await Promise.all([
      supabase.from('compliance_profiles').select('income_tax_regime,corporate_tax_rate,mcit_applicable,nolco_applicable').eq('company_id', companyId).maybeSingle(),
      supabase.from('income_tax_computations').select('taxable_income,tax_due').eq('company_id', companyId).eq('period_year', now.getFullYear())
        .order('period_quarter', { ascending: false }).limit(1),
      supabase.from('nolco_schedule').select('nolco_amount,applied_year1,applied_year2,applied_year3').eq('company_id', companyId),
      supabase.from('tax_calendar_events').select('effective_deadline,ref_compliance_forms!inner(form_code)')
        .eq('company_id', companyId).in('ref_compliance_forms.form_code', ['1702Q', '1702']).eq('status', 'pending')
        .order('effective_deadline').limit(3),
    ])

    setProfile(prof as Profile || null)
    setLatestComputation((compData?.[0] as Computation) || null)
    const nolcoRows = (nolcoData || []) as { nolco_amount: number; applied_year1: number; applied_year2: number; applied_year3: number }[]
    setNolcoBalance(nolcoRows.reduce((s, r) => s + (Number(r.nolco_amount) - Number(r.applied_year1) - Number(r.applied_year2) - Number(r.applied_year3)), 0))
    setDeadlines(((dlData || []) as unknown as { effective_deadline: string; ref_compliance_forms: { form_code: string } }[]).map(d => ({ effective_deadline: d.effective_deadline, form_code: d.ref_compliance_forms.form_code })))
    setLoading(false)
  }, [companyId, now])

  useEffect(() => { load() }, [load])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Income Tax Dashboard</h1>
        <p className="text-sm text-gray-500 mt-0.5">BIR Forms 1701/1701Q (Individual) &amp; 1702/1702Q (Corporate) — Q{quarter} {now.getFullYear()}</p>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4">
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Tax Regime</p>
              <p className="text-lg font-bold mt-1 text-gray-900">{profile?.income_tax_regime ? profile.income_tax_regime.toUpperCase() : '—'}</p>
              <p className="text-xs text-gray-400 mt-0.5">Rate: {profile?.corporate_tax_rate ?? 25}%</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Latest Taxable Income</p>
              <p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(latestComputation?.taxable_income || 0)}</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Latest Tax Due</p>
              <p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(latestComputation?.tax_due || 0)}</p>
              <p className="text-xs text-gray-400 mt-0.5">{profile?.mcit_applicable ? 'MCIT applicable' : 'RCIT only'}</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Unapplied NOLCO</p>
              <p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(nolcoBalance)}</p>
              <p className="text-xs text-gray-400 mt-0.5">{profile?.nolco_applicable ? 'NOLCO applicable' : 'Not applicable'}</p>
            </div>
          </div>

          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-gray-100"><h2 className="text-xs font-semibold text-gray-400 uppercase tracking-widest">Upcoming Filings</h2></div>
            <table className="w-full text-sm">
              <thead><tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Form</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Deadline</th>
              </tr></thead>
              <tbody>
                {deadlines.length === 0 ? (
                  <tr><td colSpan={2} className="text-center py-8 text-xs text-gray-400">No pending filings.</td></tr>
                ) : deadlines.map((d, i) => (
                  <tr key={i} className="border-b border-gray-100">
                    <td className="px-4 py-2.5 font-medium text-gray-900">{d.form_code}</td>
                    <td className="px-4 py-2.5 text-gray-600">{new Date(d.effective_deadline).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })}</td>
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
