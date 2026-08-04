import { supabase } from './supabase'

/**
 * The one place the UI asks which business tax codes a document line may use.
 *
 * A sale carries one business tax, but which one depends on the seller: VAT if
 * the company is VAT-registered, percentage tax if it is a non-VAT Section 116
 * taxpayer. `fn_business_tax_codes_asof` answers for both families as of the
 * document date — the same versions `fn_resolve_business_tax_code` accepts — so
 * a percentage-tax code is offered to exactly the companies that owe it and
 * never to a VAT-registered one.
 *
 * VAT pickers keep reading `fn_vat_codes_asof` (see `vatCodes.ts`): that
 * function is still the VAT authority, and this one calls it for the VAT half.
 */
export type BusinessTaxFamily = 'vat' | 'percentage_tax'

export type BusinessTaxCodeOption = {
  tax_family: BusinessTaxFamily
  id: string
  code: string
  description: string
  classification: string | null
  rate: number
  atc_code: string | null
  form_type: string | null
}

export async function loadBusinessTaxCodesAsOf(
  companyId: string,
  asOf: string | null | undefined,
  transactionType?: 'input_vat' | 'output_vat',
): Promise<BusinessTaxCodeOption[]> {
  const { data } = await supabase.rpc('fn_business_tax_codes_asof', {
    p_company_id: companyId,
    // An empty date field means "today"; the database applies the same default.
    p_as_of: asOf || undefined,
    p_transaction_type: transactionType,
  })
  return (data || []).map(row => ({
    tax_family: row.tax_family as BusinessTaxFamily,
    id: row.id,
    code: row.code,
    description: row.description,
    classification: row.classification,
    rate: Number(row.rate) || 0,
    atc_code: row.atc_code,
    form_type: row.form_type,
  }))
}

/**
 * The percentage-tax half on its own, for a form that already resolves its VAT
 * codes through `loadVatCodesAsOf`. An empty result is the answer for every
 * VAT-registered company, and the column that shows it should stay hidden.
 */
export async function loadPercentageTaxCodesAsOf(
  companyId: string,
  asOf: string | null | undefined,
): Promise<BusinessTaxCodeOption[]> {
  const codes = await loadBusinessTaxCodesAsOf(companyId, asOf, 'output_vat')
  return codes.filter(c => c.tax_family === 'percentage_tax')
}
