import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'

export type ConfigField =
  | 'ar_account_id'
  | 'vat_payable_account_id'
  | 'ewt_withheld_account_id'
  | 'default_cash_account_id'
  | 'ap_account_id'
  | 'input_vat_account_id'
  | 'ewt_payable_account_id'

type ReadinessArgs = {
  companyId: string
  branchId: string
  documentCode: string
  postingDate: string
  requiredConfig: ConfigField[]
}

export type SetupReadiness = {
  loading: boolean
  blockers: string[]
  warnings: string[]
}

const CONFIG_LABELS: Record<ConfigField, string> = {
  ar_account_id: 'AR control account',
  vat_payable_account_id: 'VAT payable account',
  ewt_withheld_account_id: 'CWT receivable account',
  default_cash_account_id: 'default cash/bank account',
  ap_account_id: 'AP control account',
  input_vat_account_id: 'input VAT account',
  ewt_payable_account_id: 'EWT payable account',
}

async function hasNumberSeries(companyId: string, branchId: string, documentCode: string) {
  const direct = await supabase.from('number_series')
    .select('id')
    .eq('company_id', companyId)
    .eq('branch_id', branchId)
    .eq('document_code', documentCode)
    .eq('is_active', true)
    .limit(1)

  if (!direct.error) return { ok: Boolean(direct.data?.length), error: '' }

  const legacy = await supabase.from('number_series')
    .select('id, ref_document_types!inner(document_code)')
    .eq('company_id', companyId)
    .eq('branch_id', branchId)
    .eq('ref_document_types.document_code', documentCode)
    .eq('is_active', true)
    .limit(1)

  if (!legacy.error) return { ok: Boolean(legacy.data?.length), error: '' }
  return { ok: false, error: legacy.error.message || direct.error.message }
}

export function useTransactionReadiness({
  companyId,
  branchId,
  documentCode,
  postingDate,
  requiredConfig,
}: ReadinessArgs): SetupReadiness {
  const [state, setState] = useState<SetupReadiness>({ loading: false, blockers: [], warnings: [] })

  useEffect(() => {
    let cancelled = false

    const load = async () => {
      const blockers: string[] = []
      const warnings: string[] = []

      if (!companyId) blockers.push('Select a company.')
      if (!branchId) blockers.push('Select a branch.')
      if (!postingDate) blockers.push('Enter a transaction date.')

      if (!companyId || !branchId || !postingDate) {
        setState({ loading: false, blockers, warnings })
        return
      }

      setState(prev => ({ ...prev, loading: true }))

      const [branchRes, periodRes, configRes, seriesRes] = await Promise.all([
        supabase.from('branches')
          .select('id')
          .eq('company_id', companyId)
          .eq('id', branchId)
          .eq('is_active', true)
          .limit(1),
        supabase.from('fiscal_periods')
          .select('id')
          .eq('company_id', companyId)
          .lte('start_date', postingDate)
          .gte('end_date', postingDate)
          .eq('is_locked', false)
          .limit(1),
        supabase.from('company_accounting_config')
          .select('*')
          .eq('company_id', companyId)
          .maybeSingle(),
        hasNumberSeries(companyId, branchId, documentCode),
      ])

      if (!branchRes.data?.length) blockers.push('Selected branch is missing or inactive.')
      if (!periodRes.data?.length) blockers.push(`No open fiscal period covers ${postingDate}.`)
      if (!seriesRes.ok) {
        blockers.push(`No active number series for document code ${documentCode} in the selected branch.`)
        if (seriesRes.error) warnings.push(`Number series check detail: ${seriesRes.error}`)
      }

      const cfg = configRes.data as Partial<Record<ConfigField, string | null>> | null
      if (configRes.error) {
        blockers.push('Cannot read GL Posting Configuration.')
        warnings.push(configRes.error.message)
      } else if (!cfg) {
        blockers.push('GL Posting Configuration is missing.')
      } else {
        for (const field of requiredConfig) {
          if (!cfg[field]) blockers.push(`GL Posting Configuration is missing ${CONFIG_LABELS[field]}.`)
        }
      }

      if (!cancelled) setState({ loading: false, blockers, warnings })
    }

    load()
    return () => { cancelled = true }
  }, [companyId, branchId, documentCode, postingDate, requiredConfig])

  return state
}
