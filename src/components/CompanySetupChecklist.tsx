import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  ArrowLeft,
  ArrowRight,
  Check,
  CircleAlert,
  CircleX,
  ListChecks,
  Minus,
  RefreshCw,
} from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type ChecklistCompany = {
  id: string
  registered_name: string
  entity_type: string
  tin: string
  tax_registration: string
  accounting_period: string
  line_of_business: string
  address_line_1: string
  address_line_2: string
  city: string
  province: string
  zip_code: string
  email: string
  signatory_name: string
  signatory_position: string
  is_active: boolean
}

type ItemStatus = 'complete' | 'incomplete' | 'not_required' | 'error'

type ChecklistItem = {
  id: string
  label: string
  detail: string
  status: ItemStatus
  path?: string
  actionLabel: string
}

type Props = {
  company: ChecklistCompany
  onBack: () => void
  onEditCompany: () => void
}

const CORE_DOCUMENT_CODES = ['SI', 'OR', 'VB', 'PV'] as const
const CORE_ACCOUNT_TYPES = ['asset', 'liability', 'equity', 'revenue', 'expense'] as const
const GL_FIELDS = [
  ['ar_account_id', 'AR control'],
  ['ap_account_id', 'AP control'],
  ['default_cash_account_id', 'default cash/bank'],
  ['vat_payable_account_id', 'output VAT payable'],
  ['input_vat_account_id', 'input VAT receivable'],
  ['ewt_withheld_account_id', 'CWT receivable'],
  ['ewt_payable_account_id', 'EWT payable'],
  ['customer_advances_account_id', 'customer advances'],
  ['supplier_down_payments_account_id', 'supplier down-payments'],
] as const

const STATUS_STYLES: Record<ItemStatus, { badge: string; label: string }> = {
  complete: { badge: 'bg-green-50 text-green-700', label: 'Ready' },
  incomplete: { badge: 'bg-amber-50 text-amber-800', label: 'Required' },
  not_required: { badge: 'bg-gray-100 text-gray-600', label: 'Not applicable' },
  error: { badge: 'bg-red-50 text-red-700', label: 'Check failed' },
}

const errorDetail = (message: string) => `Could not verify this step: ${message}`

export function CompanySetupChecklist({ company, onBack, onEditCompany }: Props) {
  const navigate = useNavigate()
  const { companyId, setCompanyId, setBranchId, setPeriodId } = useAppCtx()
  const [items, setItems] = useState<ChecklistItem[]>([])
  const [loading, setLoading] = useState(true)
  const [unexpectedError, setUnexpectedError] = useState('')
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    let cancelled = false

    const load = async () => {
      setLoading(true)
      setUnexpectedError('')

      try {
        const today = new Date().toISOString().slice(0, 10)
        const [
          branchesRes,
          fiscalYearsRes,
          periodsRes,
          accountsRes,
          seriesRes,
          profileRes,
          vatCodesRes,
          atcCodesRes,
          ptCodesRes,
          configRes,
        ] = await Promise.all([
          supabase.from('branches')
            .select('id, branch_code, branch_name')
            .eq('company_id', company.id)
            .eq('is_active', true)
            .order('branch_code'),
          supabase.from('fiscal_years')
            .select('id, year_name')
            .eq('company_id', company.id)
            .eq('status', 'open')
            .lte('start_date', today)
            .gte('end_date', today),
          supabase.from('fiscal_periods')
            .select('id, period_name')
            .eq('company_id', company.id)
            .eq('is_locked', false)
            .lte('start_date', today)
            .gte('end_date', today),
          supabase.from('chart_of_accounts')
            .select('id, account_type')
            .eq('company_id', company.id)
            .eq('is_active', true)
            .eq('is_postable', true),
          supabase.from('number_series')
            .select('branch_id, document_code')
            .eq('company_id', company.id)
            .eq('is_active', true),
          supabase.from('compliance_profiles')
            .select('vat_registered, percentage_tax_registered, ewt_registered, fwt_registered, is_active')
            .eq('company_id', company.id)
            .maybeSingle(),
          supabase.from('vat_codes')
            .select('id, transaction_type, vat_classification, tax_codes!inner(is_active)')
            .eq('is_active', true)
            .eq('tax_codes.is_active', true),
          supabase.from('atc_codes')
            .select('id, tax_category')
            .eq('is_active', true)
            .is('deprecated_at', null)
            .lte('effective_from', today)
            .or(`effective_to.is.null,effective_to.gte.${today}`),
          supabase.from('percentage_tax_codes')
            .select('id, atc_id')
            .eq('company_id', company.id)
            .eq('is_active', true),
          supabase.from('company_accounting_config')
            .select('ar_account_id, ap_account_id, default_cash_account_id, vat_payable_account_id, input_vat_account_id, ewt_withheld_account_id, ewt_payable_account_id, customer_advances_account_id, supplier_down_payments_account_id')
            .eq('company_id', company.id)
            .maybeSingle(),
        ])

        if (cancelled) return

        const nextItems: ChecklistItem[] = []
        const missingCompanyFields = [
          company.registered_name,
          company.entity_type,
          company.tin,
          company.tax_registration,
          company.accounting_period,
          company.line_of_business,
          company.address_line_1,
          company.address_line_2,
          company.city,
          company.province,
          company.zip_code,
          company.email,
          company.signatory_name,
          company.signatory_position,
        ].filter(value => !value?.trim()).length
        const companyReady = company.is_active && missingCompanyFields === 0

        nextItems.push({
          id: 'company',
          label: 'Company legal profile',
          status: companyReady ? 'complete' : 'incomplete',
          detail: !company.is_active
            ? 'The company is inactive.'
            : missingCompanyFields > 0
              ? `${missingCompanyFields} required legal, address, or signatory field${missingCompanyFields === 1 ? '' : 's'} remain incomplete.`
              : 'Legal identity, tax registration, address, and signatory details are complete.',
          actionLabel: 'Edit company',
        })

        const branches = branchesRes.data || []
        nextItems.push({
          id: 'branches',
          label: 'Active branch',
          status: branchesRes.error ? 'error' : branches.length > 0 ? 'complete' : 'incomplete',
          detail: branchesRes.error
            ? errorDetail(branchesRes.error.message)
            : branches.length > 0
              ? `${branches.length} active branch${branches.length === 1 ? '' : 'es'} available.`
              : 'At least one active branch is required for transactions and document numbering.',
          path: '/branch-setup',
          actionLabel: 'Open branches',
        })

        const fiscalYears = fiscalYearsRes.data || []
        nextItems.push({
          id: 'fiscal-year',
          label: 'Current fiscal year',
          status: fiscalYearsRes.error ? 'error' : fiscalYears.length > 0 ? 'complete' : 'incomplete',
          detail: fiscalYearsRes.error
            ? errorDetail(fiscalYearsRes.error.message)
            : fiscalYears.length > 0
              ? `${fiscalYears[0].year_name} is open and covers today.`
              : 'No open fiscal year covers today.',
          path: '/fiscal-years',
          actionLabel: 'Open fiscal years',
        })

        const periods = periodsRes.data || []
        nextItems.push({
          id: 'fiscal-period',
          label: 'Current open period',
          status: periodsRes.error ? 'error' : periods.length > 0 ? 'complete' : 'incomplete',
          detail: periodsRes.error
            ? errorDetail(periodsRes.error.message)
            : periods.length > 0
              ? `${periods[0].period_name} is unlocked and covers today.`
              : 'No unlocked fiscal period covers today.',
          path: '/fiscal-years',
          actionLabel: 'Manage periods',
        })

        const accounts = accountsRes.data || []
        const configuredAccountTypes = new Set(accounts.map(account => account.account_type))
        const missingAccountTypes = CORE_ACCOUNT_TYPES.filter(type => !configuredAccountTypes.has(type))
        nextItems.push({
          id: 'coa',
          label: 'Chart of accounts',
          status: accountsRes.error ? 'error' : missingAccountTypes.length === 0 ? 'complete' : 'incomplete',
          detail: accountsRes.error
            ? errorDetail(accountsRes.error.message)
            : missingAccountTypes.length === 0
              ? `${accounts.length} active postable accounts cover all five account types.`
              : `Missing active postable account types: ${missingAccountTypes.join(', ')}.`,
          path: '/chart-of-accounts',
          actionLabel: 'Open accounts',
        })

        const series = seriesRes.data || []
        const missingSeries = branches.map(branch => {
          const codes = new Set(series
            .filter(row => row.branch_id === branch.id)
            .map(row => row.document_code)
            .filter(Boolean))
          return {
            branch: branch.branch_code || branch.branch_name,
            codes: CORE_DOCUMENT_CODES.filter(code => !codes.has(code)),
          }
        }).filter(entry => entry.codes.length > 0)
        const seriesError = branchesRes.error || seriesRes.error
        nextItems.push({
          id: 'number-series',
          label: 'Core number series',
          status: seriesError
            ? 'error'
            : branches.length > 0 && missingSeries.length === 0
              ? 'complete'
              : 'incomplete',
          detail: seriesError
            ? errorDetail(seriesError.message)
            : branches.length === 0
              ? 'Create an active branch before configuring document series.'
              : missingSeries.length === 0
                ? `SI, OR, VB, and PV series are active for ${branches.length} branch${branches.length === 1 ? '' : 'es'}.`
                : `Missing by branch: ${missingSeries.map(entry => `${entry.branch} (${entry.codes.join(', ')})`).join('; ')}.`,
          path: '/number-series',
          actionLabel: 'Open number series',
        })

        const profile = profileRes.data
        let profileMismatch = ''
        if (profile) {
          if (company.tax_registration === 'vat' && !profile.vat_registered) {
            profileMismatch = 'Company is VAT-registered but the compliance profile is not.'
          } else if (company.tax_registration === 'non_vat' && (!profile.percentage_tax_registered || profile.vat_registered)) {
            profileMismatch = 'Non-VAT registration must have percentage tax enabled and VAT disabled.'
          } else if (company.tax_registration === 'exempt' && (profile.vat_registered || profile.percentage_tax_registered)) {
            profileMismatch = 'Exempt registration must have VAT and percentage tax disabled.'
          }
        }
        const profileReady = Boolean(profile?.is_active) && !profileMismatch
        nextItems.push({
          id: 'compliance-profile',
          label: 'Compliance profile',
          status: profileRes.error ? 'error' : profileReady ? 'complete' : 'incomplete',
          detail: profileRes.error
            ? errorDetail(profileRes.error.message)
            : !profile
              ? 'No compliance profile exists for this company.'
              : !profile.is_active
                ? 'The compliance profile is inactive.'
                : profileMismatch || 'Tax registrations and filing applicability match the company profile.',
          path: '/compliance-profile',
          actionLabel: 'Open compliance profile',
        })

        const vatRequired = company.tax_registration === 'vat'
        const vatCodes = vatCodesRes.data || []
        const hasInputVat = vatCodes.some(code => code.transaction_type === 'input_vat' && code.vat_classification === 'regular')
        const hasOutputVat = vatCodes.some(code => code.transaction_type === 'output_vat' && code.vat_classification === 'regular')
        nextItems.push({
          id: 'vat-codes',
          label: 'VAT codes',
          status: !vatRequired
            ? 'not_required'
            : vatCodesRes.error
              ? 'error'
              : hasInputVat && hasOutputVat
                ? 'complete'
                : 'incomplete',
          detail: !vatRequired
            ? 'VAT code setup is not required by this company registration.'
            : vatCodesRes.error
              ? errorDetail(vatCodesRes.error.message)
              : hasInputVat && hasOutputVat
                ? 'Active regular input and output VAT codes are available.'
                : 'Active regular input and output VAT codes are both required.',
          path: '/tax-setup',
          actionLabel: 'Open tax codes',
        })

        const requiredAtcCategories = profile
          ? [
              profile.ewt_registered ? 'ewt' : '',
              profile.fwt_registered ? 'fwt' : '',
              profile.percentage_tax_registered ? 'pt' : '',
            ].filter(Boolean)
          : []
        const atcCodes = atcCodesRes.data || []
        const currentAtcIdsByCategory = new Map<string, Set<string>>()
        for (const code of atcCodes) {
          const current = currentAtcIdsByCategory.get(code.tax_category) || new Set<string>()
          current.add(code.id)
          currentAtcIdsByCategory.set(code.tax_category, current)
        }
        const percentageTaxAtcs = currentAtcIdsByCategory.get('pt') || new Set<string>()
        const availableCategory: Record<string, boolean> = {
          ewt: Boolean(currentAtcIdsByCategory.get('ewt')?.size),
          fwt: Boolean(currentAtcIdsByCategory.get('fwt')?.size),
          pt: Boolean(ptCodesRes.data?.some(code => percentageTaxAtcs.has(code.atc_id))),
        }
        const missingAtcCategories = requiredAtcCategories.filter(category =>
          !availableCategory[category]
        )
        const atcQueryError = atcCodesRes.error?.message
          || (requiredAtcCategories.includes('pt') ? ptCodesRes.error?.message : '')
          || ''
        nextItems.push({
          id: 'atc-codes',
          label: 'Withholding and ATC codes',
          status: profileRes.error
            ? 'error'
            : !profile
              ? 'incomplete'
              : requiredAtcCategories.length === 0
                ? 'not_required'
                : atcQueryError
                  ? 'error'
                  : missingAtcCategories.length === 0
                    ? 'complete'
                    : 'incomplete',
          detail: profileRes.error
            ? errorDetail(profileRes.error.message)
            : !profile
              ? 'Complete the compliance profile to determine applicable withholding codes.'
              : requiredAtcCategories.length === 0
                ? 'No EWT, FWT, or percentage tax category is enabled.'
                : atcQueryError
                  ? errorDetail(atcQueryError)
                  : missingAtcCategories.length === 0
                    ? `Current ATC masters cover: ${requiredAtcCategories.join(', ')}.`
                    : `Missing current ATC coverage: ${missingAtcCategories.join(', ')}.`,
          path: '/tax-setup',
          actionLabel: 'Open tax codes',
        })

        const config = configRes.data
        const requiredGlFields = GL_FIELDS.filter(([field]) => {
          if (field === 'vat_payable_account_id' || field === 'input_vat_account_id') {
            return company.tax_registration === 'vat'
          }
          if (field === 'ewt_payable_account_id') return Boolean(profile?.ewt_registered)
          if (field === 'ewt_withheld_account_id') return false
          if (field === 'customer_advances_account_id') return false
          if (field === 'supplier_down_payments_account_id') return false
          return true
        })
        const missingConfig = config
          ? requiredGlFields.filter(([field]) => !config[field]).map(([, label]) => label)
          : requiredGlFields.map(([, label]) => label)
        nextItems.push({
          id: 'gl-config',
          label: 'GL posting configuration',
          status: configRes.error ? 'error' : config && missingConfig.length === 0 ? 'complete' : 'incomplete',
          detail: configRes.error
            ? errorDetail(configRes.error.message)
            : config && missingConfig.length === 0
              ? `${requiredGlFields.length} applicable control, cash, VAT, and withholding account mappings are complete.`
              : `Missing account mappings: ${missingConfig.join(', ')}.`,
          path: '/gl-posting-config',
          actionLabel: 'Open GL configuration',
        })

        setItems(nextItems)
      } catch (error) {
        if (!cancelled) {
          setItems([])
          setUnexpectedError(error instanceof Error ? error.message : 'Unknown setup check error')
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    void load()
    return () => { cancelled = true }
  }, [company, reloadKey])

  const requiredItems = useMemo(() => items.filter(item => item.status !== 'not_required'), [items])
  const completedCount = requiredItems.filter(item => item.status === 'complete').length
  const remainingCount = requiredItems.filter(item => item.status !== 'complete').length
  const progress = requiredItems.length > 0 ? Math.round((completedCount / requiredItems.length) * 100) : 0
  const allReady = !loading && requiredItems.length > 0 && remainingCount === 0

  const openStep = (item: ChecklistItem) => {
    if (item.id === 'company') {
      onEditCompany()
      return
    }
    if (!item.path) return
    if (companyId !== company.id) {
      setCompanyId(company.id)
      setBranchId('')
      setPeriodId('')
    }
    navigate(item.path)
  }

  const statusIcon = (status: ItemStatus) => {
    if (status === 'complete') return <Check className="h-4 w-4" aria-hidden="true" />
    if (status === 'not_required') return <Minus className="h-4 w-4" aria-hidden="true" />
    if (status === 'error') return <CircleX className="h-4 w-4" aria-hidden="true" />
    return <CircleAlert className="h-4 w-4" aria-hidden="true" />
  }

  return (
    <div className="max-w-5xl mx-auto space-y-5">
      <div className="flex items-start justify-between gap-4">
        <div>
          <button onClick={onBack} className="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-900 mb-2">
            <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
            Back to companies
          </button>
          <div className="flex items-center gap-2">
            <ListChecks className="h-5 w-5 text-gray-500" aria-hidden="true" />
            <h1 className="text-xl font-semibold text-gray-900">Company Setup Checklist</h1>
          </div>
          <p className="text-sm text-gray-500 mt-1">{company.registered_name}</p>
        </div>
        <button
          onClick={() => setReloadKey(key => key + 1)}
          disabled={loading}
          className="inline-flex h-9 w-9 items-center justify-center border border-gray-300 rounded-md text-gray-600 hover:bg-gray-50 disabled:opacity-50"
          title="Refresh setup checks"
          aria-label="Refresh setup checks"
        >
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" />
        </button>
      </div>

      <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <div className="px-5 py-4 border-b border-gray-100">
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className={`text-sm font-semibold ${allReady ? 'text-green-700' : 'text-gray-900'}`}>
                {loading
                  ? 'Checking company setup...'
                  : allReady
                    ? 'Core accounting setup is ready'
                    : `${remainingCount} required setup step${remainingCount === 1 ? '' : 's'} remain`}
              </p>
              {!loading && requiredItems.length > 0 && (
                <p className="text-xs text-gray-500 mt-0.5">{completedCount} of {requiredItems.length} required checks complete</p>
              )}
            </div>
            {!loading && requiredItems.length > 0 && (
              <span className="text-sm font-semibold text-gray-700 tabular-nums">{progress}%</span>
            )}
          </div>
          <div className="h-1.5 bg-gray-100 mt-3 overflow-hidden rounded-full">
            <div className={`h-full transition-all ${allReady ? 'bg-green-600' : 'bg-gray-800'}`} style={{ width: `${progress}%` }} />
          </div>
        </div>

        {unexpectedError && (
          <div className="m-5 border border-red-200 bg-red-50 rounded-md px-4 py-3 text-sm text-red-700">
            Setup checks could not be loaded: {unexpectedError}
          </div>
        )}

        {loading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(6)].map((_, index) => (
              <div key={index} className="px-5 py-4 flex items-center gap-4 animate-pulse">
                <div className="h-8 w-8 rounded-full bg-gray-100 shrink-0" />
                <div className="flex-1 space-y-2">
                  <div className="h-3 bg-gray-100 rounded w-40" />
                  <div className="h-3 bg-gray-100 rounded w-2/3" />
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {items.map(item => {
              const style = STATUS_STYLES[item.status]
              return (
                <div key={item.id} className="px-5 py-4 grid grid-cols-[auto_minmax(0,1fr)] sm:grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-x-4 gap-y-2">
                  <div className={`h-8 w-8 rounded-full flex items-center justify-center shrink-0 ${style.badge}`}>
                    {statusIcon(item.status)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <h2 className="text-sm font-medium text-gray-900">{item.label}</h2>
                      <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${style.badge}`}>{style.label}</span>
                    </div>
                    <p className={`text-xs mt-1 leading-5 ${item.status === 'error' ? 'text-red-600' : 'text-gray-500'}`}>{item.detail}</p>
                  </div>
                  <button
                    onClick={() => openStep(item)}
                    className="col-start-2 sm:col-start-3 inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:text-blue-900 justify-self-start sm:justify-self-end"
                  >
                    {item.actionLabel}
                    <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
                  </button>
                </div>
              )
            })}
          </div>
        )}
      </section>
    </div>
  )
}
