export type AccountingTraceTarget = {
  sourceType?: string | null
  sourceId?: string | null
  journalEntryId?: string | null
}

export type ReportTraceTarget = {
  companyId: string
  reportFamily: 'financial' | 'subledger' | 'tax' | 'form_2307_issued' | 'form_2307_received' | 'report_snapshot'
  filters: Record<string, string | null | undefined>
}

export function accountingTracePath({ sourceType, sourceId, journalEntryId }: AccountingTraceTarget) {
  const params = new URLSearchParams()
  if (journalEntryId) {
    params.set('jeId', journalEntryId)
  } else if (sourceType && sourceId) {
    params.set('sourceType', sourceType.trim().toUpperCase())
    params.set('sourceId', sourceId)
  }
  return `/accounting-trace?${params.toString()}`
}

export function reportTracePath({ companyId, reportFamily, filters }: ReportTraceTarget) {
  const params = new URLSearchParams({ companyId, reportFamily })
  for (const [key, value] of Object.entries(filters)) {
    if (value) params.set(key, value)
  }
  return `/accounting-trace?${params.toString()}`
}
