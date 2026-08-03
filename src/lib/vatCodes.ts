import { supabase } from './supabase'

/**
 * The one place the UI asks which VAT codes a document may use.
 *
 * A VAT code is not simply "active": it is a version with an effective window,
 * a deprecation state, a tax side, and a company tax profile it must suit. The
 * database decides all of that in `fn_resolve_vat_code` and refuses anything
 * that fails, so a picker built from `vat_codes.is_active` alone would offer
 * codes the save will reject the moment a rate succession exists.
 *
 * `fn_vat_codes_asof` returns exactly the versions the database will accept for
 * this company on this document date — including the superseded version when
 * the document is dated inside its window, which is what keeps an older draft
 * editable after a rate change.
 */
export type VatCodeOption = {
  id: string
  vat_code: string
  description: string
  vat_classification: string
  transaction_type: string
  rate: number
}

export async function loadVatCodesAsOf(
  companyId: string,
  asOf: string | null | undefined,
  transactionType?: 'input_vat' | 'output_vat',
): Promise<VatCodeOption[]> {
  const { data } = await supabase.rpc('fn_vat_codes_asof', {
    p_company_id: companyId,
    // An empty date field means "today"; the database applies the same default.
    p_as_of: asOf || undefined,
    p_transaction_type: transactionType,
  })
  return (data || []).map(row => ({
    id: row.id,
    vat_code: row.vat_code,
    description: row.description,
    vat_classification: row.vat_classification,
    transaction_type: row.transaction_type,
    rate: Number(row.rate) || 0,
  }))
}
