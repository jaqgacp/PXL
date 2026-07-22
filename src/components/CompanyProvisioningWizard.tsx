import { useEffect, useMemo, useRef, useState } from 'react'
import {
  ArrowLeft,
  ArrowRight,
  Building2,
  Check,
  Loader2,
  ShieldCheck,
} from 'lucide-react'
import { supabase } from '@/lib/supabase'
import type { Json, Tables } from '@/lib/database.types'
import { formatPhTinInput, isValidPhTin, PH_TIN_PLACEHOLDER } from '@/lib/philippines'

type RDO = { id: string; rdo_code: string; rdo_name: string }
type CompanyOption = { id: string; registered_name: string }
type ProvisioningTemplate = Pick<
  Tables<'company_provisioning_templates'>,
  | 'template_code'
  | 'template_version'
  | 'template_name'
  | 'country_code'
  | 'localization_code'
  | 'default_functional_currency_code'
  | 'default_reporting_currency_code'
>
type Currency = Pick<Tables<'currencies'>, 'currency_code' | 'name'>
type ValidationError = {
  error_order?: number
  check_code?: string
  field_name?: string
  order?: number
  code?: string
  field?: string
  detail: string
}
type ProvisioningResult = {
  status?: 'succeeded' | 'failed'
  company_id?: string
  errors?: ValidationError[]
}

type Props = {
  companies: CompanyOption[]
  rdos: RDO[]
  onCancel: () => void
  onComplete: (companyId: string) => void | Promise<void>
}

const ENTITY_TYPES = [
  ['sole_proprietor', 'Sole Proprietor'],
  ['opc', 'One Person Corporation'],
  ['corporation', 'Regular Corporation'],
  ['partnership', 'Partnership'],
  ['cooperative', 'Cooperative'],
] as const

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]

const STEPS = [
  'Template & Company',
  'Tax Registration',
  'Fiscal Settings',
  'Operating Defaults',
  'Address & Signatory',
]

const currentYear = new Date().getUTCFullYear()

const INITIAL_FORM = {
  template_code: '',
  template_version: '',
  company_code: '',
  parent_company_id: '',
  entity_type: '',
  registered_name: '',
  trade_name: '',
  line_of_business: '',
  psic_code: '',
  tin: '',
  tax_registration: '',
  rdo_id: '',
  registration_number: '',
  bir_reg_date: '',
  sec_dti_reg_date: '',
  lgu_reg_date: '',
  cas_permit_no: '',
  cas_date_issued: '',
  accounting_period: 'calendar',
  fiscal_start_month: '1',
  fiscal_year_start_date: `${currentYear}-01-01`,
  fiscal_year_name: `FY${currentYear}`,
  functional_currency_code: '',
  reporting_currency_code: '',
  branch_code: 'HO',
  branch_name: 'Head Office',
  branch_type: 'head_office',
  tin_branch_code: '00000',
  warehouse_code: 'MAIN',
  warehouse_name: 'Main Warehouse',
  warehouse_type: 'main',
  address_line_1: '',
  address_line_2: '',
  city: '',
  province: '',
  zip_code: '',
  email: '',
  phone_number: '',
  mobile_number: '',
  signatory_name: '',
  signatory_position: '',
  signatory_tin: '',
  workspace_accent_color: '#14532D',
}

type WizardForm = typeof INITIAL_FORM

const inputClass = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-gray-900'
const labelClass = 'block text-xs font-medium text-gray-600 mb-1'

export function CompanyProvisioningWizard({ companies, rdos, onCancel, onComplete }: Props) {
  const [step, setStep] = useState(0)
  const [form, setForm] = useState<WizardForm>(INITIAL_FORM)
  const [templates, setTemplates] = useState<ProvisioningTemplate[]>([])
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [loadingReference, setLoadingReference] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [errors, setErrors] = useState<ValidationError[]>([])
  const [message, setMessage] = useState('')
  const idempotencyKey = useRef(crypto.randomUUID())

  useEffect(() => {
    let cancelled = false
    Promise.all([
      supabase.from('company_provisioning_templates')
        .select('template_code,template_version,template_name,country_code,localization_code,default_functional_currency_code,default_reporting_currency_code')
        .eq('is_current', true)
        .eq('is_active', true)
        .order('template_name'),
      supabase.from('currencies')
        .select('currency_code,name')
        .eq('is_active', true)
        .order('currency_code'),
    ]).then(([templateResult, currencyResult]) => {
      if (cancelled) return
      const nextTemplates = templateResult.data || []
      setTemplates(nextTemplates)
      setCurrencies(currencyResult.data || [])
      if (templateResult.error || currencyResult.error) {
        setMessage(templateResult.error?.message || currencyResult.error?.message || 'Cannot load provisioning references.')
      } else if (nextTemplates[0]) {
        const selected = nextTemplates[0]
        setForm(current => ({
          ...current,
          template_code: selected.template_code,
          template_version: String(selected.template_version),
          functional_currency_code: selected.default_functional_currency_code,
          reporting_currency_code: selected.default_reporting_currency_code,
        }))
      }
      setLoadingReference(false)
    })
    return () => { cancelled = true }
  }, [])

  const selectedTemplate = useMemo(
    () => templates.find(template =>
      template.template_code === form.template_code
      && String(template.template_version) === form.template_version),
    [form.template_code, form.template_version, templates],
  )

  const set = (field: keyof WizardForm, value: string) => {
    setForm(current => ({ ...current, [field]: value }))
    setErrors([])
    setMessage('')
  }

  const selectTemplate = (value: string) => {
    const template = templates.find(item => `${item.template_code}:${item.template_version}` === value)
    if (!template) return
    setForm(current => ({
      ...current,
      template_code: template.template_code,
      template_version: String(template.template_version),
      functional_currency_code: template.default_functional_currency_code,
      reporting_currency_code: template.default_reporting_currency_code,
    }))
    setErrors([])
    setMessage('')
  }

  const currentStepMissing = () => {
    const requiredByStep: Array<Array<keyof WizardForm>> = [
      ['template_code', 'company_code', 'entity_type', 'registered_name', 'line_of_business'],
      ['tin', 'tax_registration'],
      ['accounting_period', 'fiscal_year_start_date', 'functional_currency_code', 'reporting_currency_code'],
      ['branch_code', 'branch_name', 'branch_type', 'tin_branch_code', 'warehouse_code', 'warehouse_name', 'warehouse_type'],
      ['address_line_1', 'address_line_2', 'city', 'province', 'zip_code', 'email', 'signatory_name', 'signatory_position'],
    ]
    const missing = requiredByStep[step].filter(field => !form[field].trim())
    if (step === 2 && form.accounting_period === 'fiscal' && !form.fiscal_start_month) {
      missing.push('fiscal_start_month')
    }
    return missing
  }

  const next = () => {
    const missing = currentStepMissing()
    if (missing.length > 0) {
      setMessage(`Complete the required fields: ${missing.join(', ')}.`)
      return
    }
    if (step === 1 && !isValidPhTin(form.tin)) {
      setMessage(`TIN must use ${PH_TIN_PLACEHOLDER}.`)
      return
    }
    setMessage('')
    setStep(current => Math.min(current + 1, STEPS.length - 1))
  }

  const buildRequest = (): Json => ({
    template_code: form.template_code,
    template_version: Number(form.template_version),
    company: {
      company_code: form.company_code,
      parent_company_id: form.parent_company_id || null,
      entity_type: form.entity_type,
      registered_name: form.registered_name,
      trade_name: form.trade_name,
      line_of_business: form.line_of_business,
      psic_code: form.psic_code,
      tin: form.tin,
      tax_registration: form.tax_registration,
      rdo_id: form.rdo_id || null,
      registration_number: form.registration_number,
      bir_reg_date: form.bir_reg_date || null,
      sec_dti_reg_date: form.sec_dti_reg_date || null,
      lgu_reg_date: form.lgu_reg_date || null,
      cas_permit_no: form.cas_permit_no,
      cas_date_issued: form.cas_date_issued || null,
      accounting_period: form.accounting_period,
      fiscal_start_month: form.accounting_period === 'fiscal' ? Number(form.fiscal_start_month) : null,
      functional_currency_code: form.functional_currency_code,
      reporting_currency_code: form.reporting_currency_code,
      address_line_1: form.address_line_1,
      address_line_2: form.address_line_2,
      city: form.city,
      province: form.province,
      zip_code: form.zip_code,
      email: form.email,
      phone_number: form.phone_number,
      mobile_number: form.mobile_number,
      signatory_name: form.signatory_name,
      signatory_position: form.signatory_position,
      signatory_tin: form.signatory_tin,
      workspace_accent_color: form.workspace_accent_color,
    },
    fiscal_year: {
      start_date: form.fiscal_year_start_date,
      year_name: form.fiscal_year_name,
    },
    default_branch: {
      branch_code: form.branch_code,
      branch_name: form.branch_name,
      branch_type: form.branch_type,
      tin_branch_code: form.tin_branch_code,
      rdo_id: form.rdo_id || null,
    },
    default_warehouse: {
      warehouse_code: form.warehouse_code,
      warehouse_name: form.warehouse_name,
      warehouse_type: form.warehouse_type,
    },
  })

  const provision = async () => {
    const missing = currentStepMissing()
    if (missing.length > 0) {
      setMessage(`Complete the required fields: ${missing.join(', ')}.`)
      return
    }
    if (!isValidPhTin(form.tin) || (form.signatory_tin && !isValidPhTin(form.signatory_tin))) {
      setMessage(`TIN values must use ${PH_TIN_PLACEHOLDER}.`)
      return
    }

    setSubmitting(true)
    setErrors([])
    setMessage('')
    const request = buildRequest()
    const validation = await supabase.rpc('fn_validate_company_provisioning', { p_request: request })
    if (validation.error) {
      setMessage(validation.error.message)
      setSubmitting(false)
      return
    }
    if (validation.data.length > 0) {
      setErrors(validation.data)
      setMessage('Provisioning validation failed. Review the fields below.')
      setSubmitting(false)
      return
    }

    const response = await supabase.rpc('fn_provision_company', {
      p_request: request,
      p_idempotency_key: idempotencyKey.current,
    })
    if (response.error) {
      setMessage(response.error.message)
      setSubmitting(false)
      return
    }

    const result = response.data as ProvisioningResult
    if (result.status !== 'succeeded' || !result.company_id) {
      setErrors(result.errors || [])
      setMessage('Company provisioning did not complete. No partial company setup was retained.')
      setSubmitting(false)
      return
    }

    await onComplete(result.company_id)
  }

  const fieldError = (field: string) => errors.find(error =>
    (error.field_name || error.field) === field)?.detail

  const input = (
    field: keyof WizardForm,
    label: string,
    options: { type?: string; required?: boolean; placeholder?: string; maxLength?: number } = {},
  ) => (
    <div>
      <label className={labelClass} htmlFor={`provision-${field}`}>
        {label}{options.required && <span className="text-red-600"> *</span>}
      </label>
      <input
        id={`provision-${field}`}
        type={options.type || 'text'}
        value={form[field]}
        onChange={event => set(field, event.target.value)}
        className={inputClass}
        placeholder={options.placeholder}
        maxLength={options.maxLength}
      />
      {fieldError(`company.${field}`) && (
        <p className="mt-1 text-xs text-red-700">{fieldError(`company.${field}`)}</p>
      )}
    </div>
  )

  if (loadingReference) {
    return (
      <div className="min-h-[24rem] flex items-center justify-center text-sm text-gray-500">
        <Loader2 className="h-4 w-4 animate-spin mr-2" /> Loading provisioning references
      </div>
    )
  }

  return (
    <div className="max-w-5xl mx-auto space-y-5">
      <div className="flex items-start justify-between gap-4">
        <div>
          <button onClick={onCancel} className="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-900 mb-1">
            <ArrowLeft className="h-3.5 w-3.5" /> Back to companies
          </button>
          <h1 className="text-xl font-semibold text-gray-900">Provision Company</h1>
          <p className="text-sm text-gray-500 mt-0.5">{STEPS[step]}</p>
        </div>
        <div className="text-xs text-gray-500 tabular-nums">{step + 1} / {STEPS.length}</div>
      </div>

      <div className="grid grid-cols-5 gap-2" aria-label="Provisioning progress">
        {STEPS.map((name, index) => (
          <div key={name} className="min-w-0">
            <div className={`h-1 rounded ${index <= step ? 'bg-emerald-700' : 'bg-gray-200'}`} />
            <div className={`mt-2 text-[11px] leading-tight ${index === step ? 'font-semibold text-gray-900' : 'text-gray-400'}`}>
              {name}
            </div>
          </div>
        ))}
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-5 md:p-6 min-h-[25rem]">
        {step === 0 && (
          <div className="space-y-5">
            <div className="flex items-center gap-2 text-sm font-semibold text-gray-900">
              <Building2 className="h-4 w-4" /> Template and company identity
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">
                <label className={labelClass} htmlFor="provision-template">Company Template <span className="text-red-600">*</span></label>
                <select
                  id="provision-template"
                  value={selectedTemplate ? `${selectedTemplate.template_code}:${selectedTemplate.template_version}` : ''}
                  onChange={event => selectTemplate(event.target.value)}
                  className={inputClass}
                >
                  <option value="">Select template</option>
                  {templates.map(template => (
                    <option key={`${template.template_code}:${template.template_version}`} value={`${template.template_code}:${template.template_version}`}>
                      {template.template_name} ({template.country_code}, v{template.template_version})
                    </option>
                  ))}
                </select>
              </div>
              {input('company_code', 'Company Code', { required: true, placeholder: 'ACME_PH', maxLength: 20 })}
              <div>
                <label className={labelClass} htmlFor="provision-parent">Parent Company</label>
                <select id="provision-parent" value={form.parent_company_id} onChange={event => set('parent_company_id', event.target.value)} className={inputClass}>
                  <option value="">None</option>
                  {companies.map(company => <option key={company.id} value={company.id}>{company.registered_name}</option>)}
                </select>
              </div>
              <div>
                <label className={labelClass} htmlFor="provision-entity">Entity Type <span className="text-red-600">*</span></label>
                <select id="provision-entity" value={form.entity_type} onChange={event => set('entity_type', event.target.value)} className={inputClass}>
                  <option value="">Select entity type</option>
                  {ENTITY_TYPES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </div>
              {input('registered_name', 'Registered Name', { required: true })}
              {input('trade_name', 'Trade Name')}
              {input('line_of_business', 'Line of Business', { required: true })}
              {input('psic_code', 'PSIC Code')}
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="space-y-5">
            <div className="flex items-center gap-2 text-sm font-semibold text-gray-900">
              <ShieldCheck className="h-4 w-4" /> Tax and registration
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className={labelClass} htmlFor="provision-tin">TIN <span className="text-red-600">*</span></label>
                <input id="provision-tin" value={form.tin} onChange={event => set('tin', formatPhTinInput(event.target.value))} className={inputClass} placeholder={PH_TIN_PLACEHOLDER} />
              </div>
              <div>
                <label className={labelClass} htmlFor="provision-tax">Taxpayer Classification <span className="text-red-600">*</span></label>
                <select id="provision-tax" value={form.tax_registration} onChange={event => set('tax_registration', event.target.value)} className={inputClass}>
                  <option value="">Select classification</option>
                  <option value="vat">VAT Registered</option>
                  <option value="non_vat">Non-VAT / Percentage Tax</option>
                  <option value="exempt">Tax Exempt</option>
                </select>
              </div>
              <div>
                <label className={labelClass} htmlFor="provision-rdo">RDO</label>
                <select id="provision-rdo" value={form.rdo_id} onChange={event => set('rdo_id', event.target.value)} className={inputClass}>
                  <option value="">Select RDO</option>
                  {rdos.map(rdo => <option key={rdo.id} value={rdo.id}>{rdo.rdo_code} - {rdo.rdo_name}</option>)}
                </select>
              </div>
              {input('registration_number', 'SEC / DTI / CDA Number')}
              {input('bir_reg_date', 'BIR Registration Date', { type: 'date' })}
              {input('sec_dti_reg_date', 'SEC / DTI Registration Date', { type: 'date' })}
              {input('lgu_reg_date', 'LGU Registration Date', { type: 'date' })}
              {input('cas_permit_no', 'CAS / PTU Number')}
              {input('cas_date_issued', 'CAS / PTU Date Issued', { type: 'date' })}
            </div>
          </div>
        )}

        {step === 2 && (
          <div className="space-y-5">
            <div className="text-sm font-semibold text-gray-900">Fiscal calendar and currencies</div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className={labelClass} htmlFor="provision-period">Accounting Period <span className="text-red-600">*</span></label>
                <select id="provision-period" value={form.accounting_period} onChange={event => set('accounting_period', event.target.value)} className={inputClass}>
                  <option value="calendar">Calendar Year</option>
                  <option value="fiscal">Fiscal Year</option>
                </select>
              </div>
              {form.accounting_period === 'fiscal' && (
                <div>
                  <label className={labelClass} htmlFor="provision-month">Fiscal Start Month <span className="text-red-600">*</span></label>
                  <select id="provision-month" value={form.fiscal_start_month} onChange={event => set('fiscal_start_month', event.target.value)} className={inputClass}>
                    {MONTHS.map((month, index) => <option key={month} value={index + 1}>{month}</option>)}
                  </select>
                </div>
              )}
              {input('fiscal_year_start_date', 'First Fiscal Year Start', { type: 'date', required: true })}
              {input('fiscal_year_name', 'Fiscal Year Name', { required: true })}
              {(['functional_currency_code', 'reporting_currency_code'] as const).map((field, index) => (
                <div key={field}>
                  <label className={labelClass} htmlFor={`provision-${field}`}>{index === 0 ? 'Functional Currency' : 'Reporting Currency'} <span className="text-red-600">*</span></label>
                  <select id={`provision-${field}`} value={form[field]} onChange={event => set(field, event.target.value)} className={inputClass}>
                    <option value="">Select currency</option>
                    {currencies.map(currency => <option key={currency.currency_code} value={currency.currency_code}>{currency.currency_code} - {currency.name}</option>)}
                  </select>
                </div>
              ))}
            </div>
          </div>
        )}

        {step === 3 && (
          <div className="space-y-6">
            <div>
              <div className="text-sm font-semibold text-gray-900 mb-4">Default branch</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {input('branch_code', 'Branch Code', { required: true, maxLength: 20 })}
                {input('branch_name', 'Branch Name', { required: true })}
                <div>
                  <label className={labelClass} htmlFor="provision-branch-type">Branch Type <span className="text-red-600">*</span></label>
                  <select id="provision-branch-type" value={form.branch_type} onChange={event => set('branch_type', event.target.value)} className={inputClass}>
                    <option value="head_office">Head Office</option>
                    <option value="branch">Branch</option>
                    <option value="satellite_office">Satellite Office</option>
                    <option value="warehouse">Warehouse</option>
                    <option value="project_site">Project Site</option>
                  </select>
                </div>
                {input('tin_branch_code', 'TIN Branch Code', { required: true, maxLength: 5 })}
              </div>
            </div>
            <div className="border-t border-gray-100 pt-5">
              <div className="text-sm font-semibold text-gray-900 mb-4">Default warehouse</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {input('warehouse_code', 'Warehouse Code', { required: true, maxLength: 20 })}
                {input('warehouse_name', 'Warehouse Name', { required: true })}
                <div>
                  <label className={labelClass} htmlFor="provision-warehouse-type">Warehouse Type <span className="text-red-600">*</span></label>
                  <select id="provision-warehouse-type" value={form.warehouse_type} onChange={event => set('warehouse_type', event.target.value)} className={inputClass}>
                    <option value="main">Main</option>
                    <option value="transit">Transit</option>
                    <option value="consignment">Consignment</option>
                    <option value="damaged">Damaged</option>
                  </select>
                </div>
              </div>
            </div>
          </div>
        )}

        {step === 4 && (
          <div className="space-y-5">
            <div className="text-sm font-semibold text-gray-900">Registered address and signatory</div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">{input('address_line_1', 'Address Line 1', { required: true })}</div>
              <div className="md:col-span-2">{input('address_line_2', 'Address Line 2', { required: true })}</div>
              {input('city', 'City / Municipality', { required: true })}
              {input('province', 'Province', { required: true })}
              {input('zip_code', 'ZIP Code', { required: true, maxLength: 4 })}
              {input('email', 'Official Email', { type: 'email', required: true })}
              {input('phone_number', 'Phone Number')}
              {input('mobile_number', 'Mobile Number')}
              {input('signatory_name', 'Signatory Name', { required: true })}
              {input('signatory_position', 'Signatory Position', { required: true })}
              <div>
                <label className={labelClass} htmlFor="provision-signatory-tin">Signatory TIN</label>
                <input id="provision-signatory-tin" value={form.signatory_tin} onChange={event => set('signatory_tin', formatPhTinInput(event.target.value))} className={inputClass} placeholder={PH_TIN_PLACEHOLDER} />
              </div>
              <div>
                <label className={labelClass} htmlFor="provision-accent">Workspace Accent</label>
                <div className="grid grid-cols-[3rem_1fr] gap-2">
                  <input id="provision-accent" type="color" value={form.workspace_accent_color} onChange={event => set('workspace_accent_color', event.target.value.toUpperCase())} className="h-10 w-12 border border-gray-300 rounded-md bg-white p-1" />
                  <input value={form.workspace_accent_color} onChange={event => set('workspace_accent_color', event.target.value.toUpperCase())} className={`${inputClass} font-mono uppercase`} maxLength={7} />
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {(message || errors.length > 0) && (
        <div role="alert" className="border border-red-200 bg-red-50 rounded-lg px-4 py-3 text-sm text-red-800">
          {message && <p className="font-medium">{message}</p>}
          {errors.length > 0 && (
            <ul className="mt-2 space-y-1 text-xs">
              {errors.map((error, index) => <li key={`${error.code || error.check_code}-${index}`}>{error.field || error.field_name}: {error.detail}</li>)}
            </ul>
          )}
        </div>
      )}

      <div className="flex items-center justify-between gap-3">
        <button
          onClick={() => step === 0 ? onCancel() : setStep(current => current - 1)}
          disabled={submitting}
          className="inline-flex items-center gap-2 border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50 disabled:opacity-50"
        >
          <ArrowLeft className="h-4 w-4" /> {step === 0 ? 'Cancel' : 'Back'}
        </button>
        {step < STEPS.length - 1 ? (
          <button onClick={next} className="inline-flex items-center gap-2 bg-gray-900 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-gray-800">
            Continue <ArrowRight className="h-4 w-4" />
          </button>
        ) : (
          <button onClick={provision} disabled={submitting} className="inline-flex items-center gap-2 bg-emerald-800 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-emerald-700 disabled:opacity-50">
            {submitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
            {submitting ? 'Provisioning' : 'Validate & Provision'}
          </button>
        )}
      </div>
    </div>
  )
}
