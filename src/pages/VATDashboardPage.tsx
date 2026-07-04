import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Profile = { vat_registered: boolean; vat_filing_frequency: string | null }
type Deadline = { effective_deadline: string; status: string }

const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December']

export default function VATDashboardPage() {
  const { companyId } = useAppCtx()
  const now = useMemo(() => new Date(), [])

  const [profile, setProfile] = useState<Profile | null>(null)
  const [outputVat, setOutputVat] = useState(0)
  const [inputVat, setInputVat] = useState(0)
  const [deadline, setDeadline] = useState<Deadline | null>(null)
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    const startDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`
    const endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split('T')[0]

    const [{ data: prof }, { data: outData }, { data: inData }, { data: dlData }] = await Promise.all([
      supabase.from('compliance_profiles').select('vat_registered,vat_filing_frequency').eq('company_id', companyId).maybeSingle(),
      supabase.from('vw_output_vat_review').select('output_vat').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate),
      supabase.from('vw_input_vat_review').select('input_vat').eq('company_id', companyId).gte('invoice_date', startDate).lte('invoice_date', endDate),
      supabase.from('tax_calendar_events').select('effective_deadline,status,ref_compliance_forms!inner(form_code)')
        .eq('company_id', companyId).in('ref_compliance_forms.form_code', ['2550M', '2550Q']).eq('status', 'pending')
        .order('effective_deadline').limit(1),
    ])

    setProfile(prof as Profile || null)
    setOutputVat(((outData || []) as { output_vat: number }[]).reduce((s, r) => s + Number(r.output_vat), 0))
    setInputVat(((inData || []) as { input_vat: number }[]).reduce((s, r) => s + Number(r.input_vat), 0))
    setDeadline((dlData?.[0] as unknown as Deadline) || null)
    setLoading(false)
  }, [companyId, now])

  useEffect(() => { load() }, [load])

  const netPayable = outputVat - inputVat
  const daysUntil = deadline ? Math.ceil((new Date(deadline.effective_deadline).getTime() - now.getTime()) / (1000 * 60 * 60 * 24)) : null

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">VAT Dashboard</h1>
        <p className="text-sm text-gray-500 mt-0.5">BIR Forms 2550M / 2550Q — Value-Added Tax overview, {MONTHS[now.getMonth()]} {now.getFullYear()}</p>
      </div>

      {!companyId ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Select a company from the context bar above.</div>
      ) : loading ? (
        <div className="bg-white border border-gray-200 rounded-lg p-16 text-center text-gray-400">Loading…</div>
      ) : (
        <div className="grid grid-cols-5 gap-4">
          <div className="bg-white border border-gray-200 rounded-lg p-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide">VAT Registration</p>
            <p className={`text-lg font-bold mt-1 ${profile?.vat_registered ? 'text-green-700' : 'text-gray-400'}`}>{profile?.vat_registered ? 'Registered' : 'Not Registered'}</p>
            <p className="text-xs text-gray-400 mt-0.5">Filing: {profile?.vat_filing_frequency ? profile.vat_filing_frequency[0].toUpperCase() + profile.vat_filing_frequency.slice(1) : '—'}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg p-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide">Output VAT — This Month</p>
            <p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(outputVat)}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg p-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide">Input VAT — This Month</p>
            <p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(inputVat)}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg p-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide">Net VAT</p>
            <p className="text-lg font-bold font-mono tabular-nums text-gray-900 mt-1">{fmtNum(netPayable)}</p>
            <p className="text-xs text-gray-400 mt-0.5">{netPayable < 0 ? 'Excess input VAT' : 'Payable'}</p>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg p-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide">Next Filing Deadline</p>
            {deadline ? (
              <>
                <p className={`text-lg font-bold mt-1 ${daysUntil !== null && daysUntil <= 7 ? 'text-red-600' : 'text-gray-900'}`}>{new Date(deadline.effective_deadline).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })}</p>
                <p className="text-xs text-gray-400 mt-0.5">{daysUntil !== null && daysUntil >= 0 ? `${daysUntil} day${daysUntil !== 1 ? 's' : ''} left` : 'Overdue'}</p>
              </>
            ) : <p className="text-sm text-gray-400 mt-1">No pending filing</p>}
          </div>
        </div>
      )}
    </div>
  )
}
