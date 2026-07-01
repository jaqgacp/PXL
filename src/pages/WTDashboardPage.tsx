import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Profile = { ewt_registered: boolean; fwt_registered: boolean; is_twa: boolean }
type Deadline = { effective_deadline: string; form_code: string }

const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function WTDashboardPage() {
  const { companyId } = useAppCtx()
  const now = new Date()
  const quarter = Math.ceil((now.getMonth() + 1) / 3)
  const quarterMonths = [(quarter - 1) * 3 + 1, (quarter - 1) * 3 + 2, (quarter - 1) * 3 + 3]

  const [profile, setProfile] = useState<Profile | null>(null)
  const [ewtWithheld, setEwtWithheld] = useState(0)
  const [cwtWithheld, setCwtWithheld] = useState(0)
  const [deadlines, setDeadlines] = useState<Deadline[]>([])
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const startDate = `${now.getFullYear()}-${String(quarterMonths[0]).padStart(2, '0')}-01`
    const endDate = new Date(now.getFullYear(), quarterMonths[2], 0).toISOString().split('T')[0]

    const [{ data: prof }, { data: ewtData }, { data: recData }, { data: dlData }] = await Promise.all([
      supabase.from('compliance_profiles').select('ewt_registered,fwt_registered,is_twa').eq('company_id', companyId).maybeSingle(),
      supabase.from('vw_ewt_summary_ap').select('tax_withheld').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate),
      supabase.from('receipt_lines').select('cwt_amount,receipts!inner(receipt_date,company_id,status)')
        .eq('receipts.company_id', companyId).eq('receipts.status', 'posted').gte('receipts.receipt_date', startDate).lte('receipts.receipt_date', endDate).gt('cwt_amount', 0),
      supabase.from('tax_calendar_events').select('effective_deadline,ref_compliance_forms!inner(form_code)')
        .eq('company_id', companyId).in('ref_compliance_forms.form_code', ['1601EQ', '1601FQ', '0619-E', '0619-F']).eq('status', 'pending')
        .order('effective_deadline').limit(4),
    ])

    setProfile(prof as Profile || null)
    setEwtWithheld(((ewtData || []) as { tax_withheld: number }[]).reduce((s, r) => s + Number(r.tax_withheld), 0))
    setCwtWithheld(((recData || []) as { cwt_amount: number }[]).reduce((s, r) => s + Number(r.cwt_amount), 0))
    setDeadlines(((dlData || []) as unknown as { effective_deadline: string; ref_compliance_forms: { form_code: string } }[]).map(d => ({ effective_deadline: d.effective_deadline, form_code: d.ref_compliance_forms.form_code })))
    setLoading(false)
  }, [companyId, now, quarterMonths])

  useEffect(() => { load() }, [load])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Withholding Tax Dashboard</h1>
        <p className="text-sm text-gray-500 mt-0.5">EWT (1601EQ) &amp; FWT (1601FQ) overview — Q{quarter} {now.getFullYear()}</p>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4">
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">EWT / FWT Registration</p>
              <p className="text-sm font-bold mt-1 text-gray-900">EWT: <span className={profile?.ewt_registered ? 'text-green-700' : 'text-gray-400'}>{profile?.ewt_registered ? 'Yes' : 'No'}</span></p>
              <p className="text-sm font-bold text-gray-900">FWT: <span className={profile?.fwt_registered ? 'text-green-700' : 'text-gray-400'}>{profile?.fwt_registered ? 'Yes' : 'No'}</span></p>
              {profile?.is_twa && <p className="text-xs text-blue-600 mt-1">Top Withholding Agent</p>}
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">EWT Withheld — This Quarter</p>
              <p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(ewtWithheld)}</p>
              <p className="text-xs text-gray-400 mt-0.5">Payable to BIR</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">CWT Withheld — This Quarter</p>
              <p className="text-xl font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(cwtWithheld)}</p>
              <p className="text-xs text-gray-400 mt-0.5">Receivable — tax credit</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg p-4">
              <p className="text-xs text-gray-500 uppercase tracking-wide">Next Deadline</p>
              {deadlines[0] ? (
                <>
                  <p className="text-lg font-bold text-gray-900 mt-1">{deadlines[0].form_code}</p>
                  <p className="text-xs text-gray-400 mt-0.5">{new Date(deadlines[0].effective_deadline).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })}</p>
                </>
              ) : <p className="text-sm text-gray-400 mt-1">No pending filing</p>}
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
