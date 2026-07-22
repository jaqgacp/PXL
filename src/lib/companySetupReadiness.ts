// Company setup readiness model (PXL-AUD-067).
//
// This module separates three distinct readiness concepts so a complete
// checklist can never be mistaken for a production-ready ERP:
//
//   Core Accounting Readiness  — the minimum configuration required to post a
//                                balanced, compliant journal (legal profile,
//                                branch, fiscal calendar, COA, number series,
//                                compliance/tax, GL mappings).
//   Operational Readiness      — the operational masters a company needs to
//                                actually run day-to-day workflows (customers,
//                                suppliers, products/services, inventory
//                                warehousing where applicable, banking).
//   Production Readiness        — validated live transactions, reconciliations,
//                                period close, and controls. This checklist
//                                does NOT assess it and never asserts it.
//
// The logic here is pure and deterministic so the readiness model can be tested
// without a browser or database (see tests/company_setup_readiness.test.ts).

export type ItemStatus = 'complete' | 'incomplete' | 'not_required' | 'error'

export type ReadinessGroup = 'core' | 'operational'

export type ChecklistItem = {
  id: string
  group: ReadinessGroup
  label: string
  detail: string
  status: ItemStatus
  path?: string
  actionLabel: string
}

export type ChecklistCompany = {
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

type BranchRow = { id: string; branch_code: string | null; branch_name: string | null }
type NamedRow = { period_name?: string; year_name?: string }
type AccountRow = { account_type: string }
type SeriesRow = { branch_id: string | null; document_code: string | null }
type ComplianceProfile = {
  vat_registered: boolean | null
  percentage_tax_registered: boolean | null
  ewt_registered: boolean | null
  fwt_registered: boolean | null
  is_active: boolean | null
} | null
type VatCodeRow = { transaction_type: string; vat_classification: string }
type AtcCodeRow = { id: string; tax_category: string }
type PtCodeRow = { atc_id: string }
type AccountingConfig = Record<string, string | null> | null

export type QueryResult<T> = { data: T | null; error: { message: string } | null }

export type ChecklistInput = {
  company: ChecklistCompany
  branches: QueryResult<BranchRow[]>
  fiscalYears: QueryResult<NamedRow[]>
  periods: QueryResult<NamedRow[]>
  accounts: QueryResult<AccountRow[]>
  series: QueryResult<SeriesRow[]>
  profile: QueryResult<ComplianceProfile>
  vatCodes: QueryResult<VatCodeRow[]>
  atcCodes: QueryResult<AtcCodeRow[]>
  ptCodes: QueryResult<PtCodeRow[]>
  config: QueryResult<AccountingConfig>
  // Operational master counts (active rows scoped to the company).
  customersCount: QueryResult<number>
  suppliersCount: QueryResult<number>
  itemsCount: QueryResult<number>
  inventoryItemsCount: QueryResult<number>
  warehousesCount: QueryResult<number>
  bankAccountsCount: QueryResult<number>
}

export const CORE_DOCUMENT_CODES = ['SI', 'OR', 'VB', 'PV'] as const
export const CORE_ACCOUNT_TYPES = ['asset', 'liability', 'equity', 'revenue', 'expense'] as const
export const GL_FIELDS = [
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

const errorDetail = (message: string) => `Could not verify this step: ${message}`

// ── Core Accounting Readiness ─────────────────────────────────────────────────

export function buildCoreAccountingItems(input: ChecklistInput): ChecklistItem[] {
  const { company } = input
  const items: ChecklistItem[] = []

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
  items.push({
    id: 'company',
    group: 'core',
    label: 'Company legal profile',
    status: companyReady ? 'complete' : 'incomplete',
    detail: !company.is_active
      ? 'The company is inactive.'
      : missingCompanyFields > 0
        ? `${missingCompanyFields} required legal, address, or signatory field${missingCompanyFields === 1 ? '' : 's'} remain incomplete.`
        : 'Legal identity, tax registration, address, and signatory details are complete.',
    actionLabel: 'Edit company',
  })

  const branches = input.branches.data || []
  items.push({
    id: 'branches',
    group: 'core',
    label: 'Active branch',
    status: input.branches.error ? 'error' : branches.length > 0 ? 'complete' : 'incomplete',
    detail: input.branches.error
      ? errorDetail(input.branches.error.message)
      : branches.length > 0
        ? `${branches.length} active branch${branches.length === 1 ? '' : 'es'} available.`
        : 'At least one active branch is required for transactions and document numbering.',
    path: '/branch-setup',
    actionLabel: 'Open branches',
  })

  const fiscalYears = input.fiscalYears.data || []
  items.push({
    id: 'fiscal-year',
    group: 'core',
    label: 'Current fiscal year',
    status: input.fiscalYears.error ? 'error' : fiscalYears.length > 0 ? 'complete' : 'incomplete',
    detail: input.fiscalYears.error
      ? errorDetail(input.fiscalYears.error.message)
      : fiscalYears.length > 0
        ? `${fiscalYears[0].year_name} is open and covers today.`
        : 'No open fiscal year covers today.',
    path: '/fiscal-years',
    actionLabel: 'Open fiscal years',
  })

  const periods = input.periods.data || []
  items.push({
    id: 'fiscal-period',
    group: 'core',
    label: 'Current open period',
    status: input.periods.error ? 'error' : periods.length > 0 ? 'complete' : 'incomplete',
    detail: input.periods.error
      ? errorDetail(input.periods.error.message)
      : periods.length > 0
        ? `${periods[0].period_name} is unlocked and covers today.`
        : 'No unlocked fiscal period covers today.',
    path: '/fiscal-years',
    actionLabel: 'Manage periods',
  })

  const accounts = input.accounts.data || []
  const configuredAccountTypes = new Set(accounts.map(account => account.account_type))
  const missingAccountTypes = CORE_ACCOUNT_TYPES.filter(type => !configuredAccountTypes.has(type))
  items.push({
    id: 'coa',
    group: 'core',
    label: 'Chart of accounts',
    status: input.accounts.error ? 'error' : missingAccountTypes.length === 0 ? 'complete' : 'incomplete',
    detail: input.accounts.error
      ? errorDetail(input.accounts.error.message)
      : missingAccountTypes.length === 0
        ? `${accounts.length} active postable accounts cover all five account types.`
        : `Missing active postable account types: ${missingAccountTypes.join(', ')}.`,
    path: '/chart-of-accounts',
    actionLabel: 'Open accounts',
  })

  const series = input.series.data || []
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
  const seriesError = input.branches.error || input.series.error
  items.push({
    id: 'number-series',
    group: 'core',
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

  const profile = input.profile.data
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
  items.push({
    id: 'compliance-profile',
    group: 'core',
    label: 'Compliance profile',
    status: input.profile.error ? 'error' : profileReady ? 'complete' : 'incomplete',
    detail: input.profile.error
      ? errorDetail(input.profile.error.message)
      : !profile
        ? 'No compliance profile exists for this company.'
        : !profile.is_active
          ? 'The compliance profile is inactive.'
          : profileMismatch || 'Tax registrations and filing applicability match the company profile.',
    path: '/compliance-profile',
    actionLabel: 'Open compliance profile',
  })

  const vatRequired = company.tax_registration === 'vat'
  const vatCodes = input.vatCodes.data || []
  const hasInputVat = vatCodes.some(code => code.transaction_type === 'input_vat' && code.vat_classification === 'regular')
  const hasOutputVat = vatCodes.some(code => code.transaction_type === 'output_vat' && code.vat_classification === 'regular')
  items.push({
    id: 'vat-codes',
    group: 'core',
    label: 'VAT codes',
    status: !vatRequired
      ? 'not_required'
      : input.vatCodes.error
        ? 'error'
        : hasInputVat && hasOutputVat
          ? 'complete'
          : 'incomplete',
    detail: !vatRequired
      ? 'VAT code setup is not required by this company registration.'
      : input.vatCodes.error
        ? errorDetail(input.vatCodes.error.message)
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
  const atcCodes = input.atcCodes.data || []
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
    pt: Boolean(input.ptCodes.data?.some(code => percentageTaxAtcs.has(code.atc_id))),
  }
  const missingAtcCategories = requiredAtcCategories.filter(category => !availableCategory[category])
  const atcQueryError = input.atcCodes.error?.message
    || (requiredAtcCategories.includes('pt') ? input.ptCodes.error?.message : '')
    || ''
  items.push({
    id: 'atc-codes',
    group: 'core',
    label: 'Withholding and ATC codes',
    status: input.profile.error
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
    detail: input.profile.error
      ? errorDetail(input.profile.error.message)
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

  const config = input.config.data
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
  items.push({
    id: 'gl-config',
    group: 'core',
    label: 'GL posting configuration',
    status: input.config.error ? 'error' : config && missingConfig.length === 0 ? 'complete' : 'incomplete',
    detail: input.config.error
      ? errorDetail(input.config.error.message)
      : config && missingConfig.length === 0
        ? `${requiredGlFields.length} applicable control, cash, VAT, and withholding account mappings are complete.`
        : `Missing account mappings: ${missingConfig.join(', ')}.`,
    path: '/gl-posting-config',
    actionLabel: 'Open GL configuration',
  })

  return items
}

// ── Operational Readiness ─────────────────────────────────────────────────────
//
// Operational masters are what a company needs to actually run workflows. They
// are surfaced explicitly (and separately from core accounting) so a company is
// never presented as "ready" when only accounting configuration exists.
// Operational gaps do NOT block core accounting readiness.

const countOf = (result: QueryResult<number>) => (typeof result.data === 'number' ? result.data : 0)

export function buildOperationalItems(input: ChecklistInput): ChecklistItem[] {
  const items: ChecklistItem[] = []

  const customers = countOf(input.customersCount)
  items.push({
    id: 'customers',
    group: 'operational',
    label: 'Customers',
    status: input.customersCount.error ? 'error' : customers > 0 ? 'complete' : 'incomplete',
    detail: input.customersCount.error
      ? errorDetail(input.customersCount.error.message)
      : customers > 0
        ? `${customers} active customer${customers === 1 ? '' : 's'} available for sales.`
        : 'No active customers exist yet. Sales invoicing needs at least one customer.',
    path: '/customers',
    actionLabel: 'Open customers',
  })

  const suppliers = countOf(input.suppliersCount)
  items.push({
    id: 'suppliers',
    group: 'operational',
    label: 'Suppliers',
    status: input.suppliersCount.error ? 'error' : suppliers > 0 ? 'complete' : 'incomplete',
    detail: input.suppliersCount.error
      ? errorDetail(input.suppliersCount.error.message)
      : suppliers > 0
        ? `${suppliers} active supplier${suppliers === 1 ? '' : 's'} available for purchasing.`
        : 'No active suppliers exist yet. Purchasing and vendor bills need at least one supplier.',
    path: '/suppliers',
    actionLabel: 'Open suppliers',
  })

  const itemsTotal = countOf(input.itemsCount)
  items.push({
    id: 'items',
    group: 'operational',
    label: 'Products or services',
    status: input.itemsCount.error ? 'error' : itemsTotal > 0 ? 'complete' : 'incomplete',
    detail: input.itemsCount.error
      ? errorDetail(input.itemsCount.error.message)
      : itemsTotal > 0
        ? `${itemsTotal} active item${itemsTotal === 1 ? '' : 's'} (products and/or services) available for transactions.`
        : 'No active products or services exist yet. Transactions need at least one item.',
    path: '/items',
    actionLabel: 'Open items',
  })

  // Warehousing only applies to companies that carry inventory items. A
  // service-only company (no active inventory items) does not need a warehouse.
  const inventoryItems = countOf(input.inventoryItemsCount)
  const warehouses = countOf(input.warehousesCount)
  const inventoryError = input.inventoryItemsCount.error || input.warehousesCount.error
  items.push({
    id: 'inventory-warehouse',
    group: 'operational',
    label: 'Inventory warehousing',
    status: inventoryError
      ? 'error'
      : inventoryItems === 0
        ? 'not_required'
        : warehouses > 0
          ? 'complete'
          : 'incomplete',
    detail: inventoryError
      ? errorDetail(inventoryError.message)
      : inventoryItems === 0
        ? 'No inventory items are configured; warehousing is not required for service-only operations.'
        : warehouses > 0
          ? `${inventoryItems} inventory item${inventoryItems === 1 ? '' : 's'} are stocked across ${warehouses} active warehouse${warehouses === 1 ? '' : 's'}.`
          : `${inventoryItems} inventory item${inventoryItems === 1 ? '' : 's'} exist but no active warehouse is configured for stock.`,
    path: '/warehouses',
    actionLabel: 'Open warehouses',
  })

  const banks = countOf(input.bankAccountsCount)
  items.push({
    id: 'bank-accounts',
    group: 'operational',
    label: 'Bank accounts',
    status: input.bankAccountsCount.error ? 'error' : banks > 0 ? 'complete' : 'incomplete',
    detail: input.bankAccountsCount.error
      ? errorDetail(input.bankAccountsCount.error.message)
      : banks > 0
        ? `${banks} active bank account${banks === 1 ? '' : 's'} available for receipts and payments.`
        : 'No active bank accounts exist yet. Receipts and payments need at least one bank account.',
    path: '/bank-accounts',
    actionLabel: 'Open bank accounts',
  })

  return items
}

export function buildChecklistItems(input: ChecklistInput): ChecklistItem[] {
  return [...buildCoreAccountingItems(input), ...buildOperationalItems(input)]
}

// ── Tiered readiness summary ──────────────────────────────────────────────────

export type GroupSummary = {
  ready: boolean
  requiredTotal: number
  completedCount: number
  remainingCount: number
  progress: number
  hasError: boolean
}

export type ReadinessSummary = {
  core: GroupSummary
  operational: ReadinessSummary['core']
}

function summarizeGroup(items: ChecklistItem[]): GroupSummary {
  const required = items.filter(item => item.status !== 'not_required')
  const completedCount = required.filter(item => item.status === 'complete').length
  const remainingCount = required.length - completedCount
  const hasError = items.some(item => item.status === 'error')
  return {
    ready: required.length > 0 && remainingCount === 0,
    requiredTotal: required.length,
    completedCount,
    remainingCount,
    progress: required.length > 0 ? Math.round((completedCount / required.length) * 100) : 0,
    hasError,
  }
}

export function summarizeReadiness(items: ChecklistItem[]): ReadinessSummary {
  return {
    core: summarizeGroup(items.filter(item => item.group === 'core')),
    operational: summarizeGroup(items.filter(item => item.group === 'operational')),
  }
}

// Production readiness is deliberately NOT computed here. A complete checklist
// proves configuration only; it never asserts that live transactions,
// reconciliations, period close, and controls have been validated.
export const PRODUCTION_READINESS_NOTE =
  'This checklist confirms setup configuration only. Production readiness — validated live transactions, reconciliations, period close, and internal controls — is assessed separately and is never implied by a complete checklist.'
