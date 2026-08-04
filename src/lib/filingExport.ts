import { supabase } from '@/lib/supabase'

export type FilingExportFormat = 'csv' | 'dat'

type FilingExportResult = { ok: true; rows: number } | { ok: false; message: string }

/**
 * Downloads a BIR filing artifact export.
 *
 * The bytes that reach the user are the bytes that were evidenced. The RPC
 * writes a governed `report_snapshots` row holding the exact content and its
 * SHA-256, and this reads that row back — so the file an accountant keys into
 * eFPS is provably the file PXL recorded having produced.
 *
 * Nothing is assembled here. The Filing Artifact is the system of record for
 * compliance outputs; this module is a consumer of it, never a second
 * computation. It must not aggregate, re-sum, or reformat a figure.
 */
export async function downloadFilingArtifactExport(opts: {
  companyId: string
  formCode: string
  year: number
  period: number
  format?: FilingExportFormat
}): Promise<FilingExportResult> {
  const format: FilingExportFormat = opts.format ?? 'csv'

  const { data: snapshotId, error } = await supabase.rpc('fn_snapshot_filing_artifact_export', {
    p_company_id: opts.companyId,
    p_form_code: opts.formCode,
    p_year: opts.year,
    p_period: opts.period,
    p_format: format,
  })
  if (error) return { ok: false, message: error.message }

  const { data: snapshot, error: readError } = await supabase
    .from('report_snapshots')
    .select('source_payload,source_row_count')
    .eq('id', snapshotId as unknown as string)
    .single()
  if (readError) return { ok: false, message: readError.message }

  const content = (snapshot?.source_payload as { content?: string } | null)?.content ?? ''
  const blob = new Blob([content], { type: format === 'csv' ? 'text/csv' : 'text/plain' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${opts.formCode.toLowerCase()}-${opts.year}-q${opts.period}.${format}`
  a.click()
  URL.revokeObjectURL(url)

  return { ok: true, rows: Number(snapshot?.source_row_count ?? 0) }
}
