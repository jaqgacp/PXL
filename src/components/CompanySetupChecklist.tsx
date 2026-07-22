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
import {
  buildChecklistItems,
  summarizeReadiness,
  PRODUCTION_READINESS_NOTE,
  type ChecklistCompany,
  type ChecklistInput,
  type ChecklistItem,
  type ItemStatus,
  type QueryResult,
  type ReadinessGroup,
} from '@/lib/companySetupReadiness'

type Props = {
  company: ChecklistCompany
  onBack: () => void
  onEditCompany: () => void
}

const STATUS_BADGE: Record<ItemStatus, string> = {
  complete: 'bg-green-50 text-green-700',
  incomplete: 'bg-amber-50 text-amber-800',
  not_required: 'bg-gray-100 text-gray-600',
  error: 'bg-red-50 text-red-700',
}

// The badge label depends on the group: an incomplete core step is a hard
// requirement ("Required"); an incomplete operational step is an operational
// gap that does not block core accounting readiness.
const badgeLabel = (status: ItemStatus, group: ReadinessGroup): string => {
  if (status === 'complete') return 'Ready'
  if (status === 'not_required') return 'Not applicable'
  if (status === 'error') return 'Check failed'
  return group === 'core' ? 'Required' : 'Operational gap'
}

const asCount = (result: { count: number | null; error: { message: string } | null }): QueryResult<number> => ({
  data: result.error ? null : result.count ?? 0,
  error: result.error,
})

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
          branches,
          fiscalYears,
          periods,
          accounts,
          series,
          profile,
          vatCodes,
          atcCodes,
          ptCodes,
          config,
          customersCount,
          suppliersCount,
          itemsCount,
          inventoryItemsCount,
          warehousesCount,
          bankAccountsCount,
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
          supabase.from('customers')
            .select('id', { count: 'exact', head: true })
            .eq('company_id', company.id)
            .eq('is_active', true),
          supabase.from('suppliers')
            .select('id', { count: 'exact', head: true })
            .eq('company_id', company.id)
            .eq('is_active', true),
          supabase.from('items')
            .select('id', { count: 'exact', head: true })
            .eq('company_id', company.id)
            .eq('is_active', true),
          supabase.from('items')
            .select('id', { count: 'exact', head: true })
            .eq('company_id', company.id)
            .eq('is_active', true)
            .eq('item_type', 'inventory_item'),
          supabase.from('warehouses')
            .select('id', { count: 'exact', head: true })
            .eq('company_id', company.id)
            .eq('is_active', true),
          supabase.from('bank_accounts')
            .select('id', { count: 'exact', head: true })
            .eq('company_id', company.id)
            .eq('is_active', true),
        ])

        if (cancelled) return

        const input: ChecklistInput = {
          company,
          branches,
          fiscalYears,
          periods,
          accounts,
          series,
          profile,
          vatCodes,
          atcCodes,
          ptCodes,
          config,
          customersCount: asCount(customersCount),
          suppliersCount: asCount(suppliersCount),
          itemsCount: asCount(itemsCount),
          inventoryItemsCount: asCount(inventoryItemsCount),
          warehousesCount: asCount(warehousesCount),
          bankAccountsCount: asCount(bankAccountsCount),
        }

        setItems(buildChecklistItems(input))
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

  const summary = useMemo(() => summarizeReadiness(items), [items])
  const coreItems = useMemo(() => items.filter(item => item.group === 'core'), [items])
  const operationalItems = useMemo(() => items.filter(item => item.group === 'operational'), [items])

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

  const renderRows = (rows: ChecklistItem[]) => (
    <div className="divide-y divide-gray-100">
      {rows.map(item => (
        <div key={item.id} className="px-5 py-4 grid grid-cols-[auto_minmax(0,1fr)] sm:grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-x-4 gap-y-2">
          <div className={`h-8 w-8 rounded-full flex items-center justify-center shrink-0 ${STATUS_BADGE[item.status]}`}>
            {statusIcon(item.status)}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2 flex-wrap">
              <h3 className="text-sm font-medium text-gray-900">{item.label}</h3>
              <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${STATUS_BADGE[item.status]}`}>
                {badgeLabel(item.status, item.group)}
              </span>
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
      ))}
    </div>
  )

  const groupHeader = (
    title: string,
    description: string,
    group: typeof summary.core,
    tone: 'core' | 'operational',
  ) => {
    const statusText = group.hasError
      ? 'A check could not be verified'
      : group.ready
        ? tone === 'core' ? 'Core accounting setup is ready' : 'Operational setup is ready'
        : `${group.remainingCount} ${tone === 'core' ? 'required' : 'operational'} item${group.remainingCount === 1 ? '' : 's'} remain`
    return (
      <div className="px-5 py-4 border-b border-gray-100">
        <div className="flex items-center justify-between gap-4">
          <div>
            <p className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">{title}</p>
            <p className={`text-sm font-semibold mt-0.5 ${group.ready && !group.hasError ? 'text-green-700' : 'text-gray-900'}`}>{statusText}</p>
            <p className="text-xs text-gray-500 mt-0.5">{description}</p>
          </div>
          {group.requiredTotal > 0 && (
            <div className="text-right shrink-0">
              <span className="text-sm font-semibold text-gray-700 tabular-nums">{group.progress}%</span>
              <p className="text-xs text-gray-500 mt-0.5">{group.completedCount} of {group.requiredTotal}</p>
            </div>
          )}
        </div>
        <div className="h-1.5 bg-gray-100 mt-3 overflow-hidden rounded-full">
          <div className={`h-full transition-all ${group.ready && !group.hasError ? 'bg-green-600' : 'bg-gray-800'}`} style={{ width: `${group.progress}%` }} />
        </div>
      </div>
    )
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

      {!loading && !unexpectedError && (
        <div className="border border-gray-200 bg-gray-50 rounded-lg px-5 py-4">
          <p className="text-sm font-semibold text-gray-900">Readiness is measured in stages</p>
          <ul className="mt-2 space-y-1.5 text-xs text-gray-600">
            <li className="flex items-start gap-2">
              <span className={`mt-0.5 inline-flex px-1.5 py-0.5 rounded text-[11px] font-medium ${summary.core.ready ? 'bg-green-50 text-green-700' : 'bg-amber-50 text-amber-800'}`}>
                {summary.core.ready ? 'Ready' : 'In progress'}
              </span>
              <span><span className="font-medium text-gray-800">Core accounting readiness</span> — the minimum configuration to post balanced, compliant journals.</span>
            </li>
            <li className="flex items-start gap-2">
              <span className={`mt-0.5 inline-flex px-1.5 py-0.5 rounded text-[11px] font-medium ${summary.operational.ready ? 'bg-green-50 text-green-700' : 'bg-amber-50 text-amber-800'}`}>
                {summary.operational.ready ? 'Ready' : 'In progress'}
              </span>
              <span><span className="font-medium text-gray-800">Operational readiness</span> — the operational masters needed to run day-to-day workflows.</span>
            </li>
            <li className="flex items-start gap-2">
              <span className="mt-0.5 inline-flex px-1.5 py-0.5 rounded text-[11px] font-medium bg-gray-200 text-gray-600">Separate</span>
              <span><span className="font-medium text-gray-800">Production readiness</span> — validated live transactions, reconciliations, period close, and controls. Assessed separately and never implied by a complete checklist.</span>
            </li>
          </ul>
        </div>
      )}

      {unexpectedError && (
        <div className="border border-red-200 bg-red-50 rounded-md px-4 py-3 text-sm text-red-700">
          Setup checks could not be loaded: {unexpectedError}
        </div>
      )}

      {loading ? (
        <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-5 py-4 border-b border-gray-100">
            <p className="text-sm font-semibold text-gray-900">Checking company setup...</p>
          </div>
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
        </section>
      ) : !unexpectedError && (
        <>
          <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            {groupHeader(
              'Stage 1 — Core accounting readiness',
              'Required to post balanced, compliant journals. Does not imply the company is operationally ready.',
              summary.core,
              'core',
            )}
            {renderRows(coreItems)}
          </section>

          <section className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            {groupHeader(
              'Stage 2 — Operational readiness',
              'Operational masters needed to run workflows. Gaps here do not block accounting posting, but the company is not operationally ready until they are resolved.',
              summary.operational,
              'operational',
            )}
            {renderRows(operationalItems)}
          </section>

          <p className="text-xs text-gray-500 leading-5 px-1">{PRODUCTION_READINESS_NOTE}</p>
        </>
      )}
    </div>
  )
}
