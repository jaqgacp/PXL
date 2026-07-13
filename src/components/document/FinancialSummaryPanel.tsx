import { AmountCell } from '@/components/ui/shared'
import { ErpSectionHeader } from '@/components/document/ErpSection'

// ─────────────────────────────────────────────────────────────
// FinancialSummaryPanel — shared, per-document-type summary card
// (Standard Transaction Workspace §8). Display only: the server
// computes the figures; this component never does its own
// arithmetic beyond rendering. Each document type builds its own
// `groups` contract (SI, VB, OR, PV, …).
// ─────────────────────────────────────────────────────────────

export type SummaryRow = {
  key: string
  label: string
  value: React.ReactNode
  /** Visual weight. `total` and `strong` are bold; `muted` is secondary. */
  variant?: 'default' | 'muted' | 'total' | 'strong'
  /** Render the value in parentheses (deductions, e.g. "(1,234.00)"). */
  paren?: boolean
  /** Draw a top divider above this row (section break, e.g. before a total). */
  divider?: boolean
}

export type SummaryGroup = {
  key: string
  /** `info` renders on a tinted panel (progressive disclosure, e.g. CWT block). */
  tone?: 'default' | 'info'
  rows: SummaryRow[]
  note?: string
}

function Row({ row }: { row: SummaryRow }) {
  const weight =
    row.variant === 'total' || row.variant === 'strong' ? 'font-semibold text-gray-900' :
    row.variant === 'muted' ? 'text-gray-500' : 'text-gray-700'
  return (
    <div className={`flex items-center justify-between ${row.divider ? 'pt-2 mt-1 border-t border-gray-100' : ''}`}>
      <span className={`text-xs ${weight}`}>{row.label}</span>
      <span className={`text-xs font-mono tabular-nums ${weight}`}>
        {row.paren && row.value ? '(' : ''}
        {typeof row.value === 'number' ? <AmountCell amount={row.value} /> : row.value}
        {row.paren && row.value ? ')' : ''}
      </span>
    </div>
  )
}

export function FinancialSummaryPanel({
  title = 'Financial Summary',
  groups,
  description = 'Computed financial totals used during posting.',
}: {
  title?: string
  description?: string
  groups: SummaryGroup[]
}) {
  return (
    <div className="bg-white border border-gray-200 rounded p-3 space-y-2">
      <ErpSectionHeader title={title} description={description} className="pb-2 border-b border-gray-100" />
      {groups.map(group => (
        group.tone === 'info' ? (
          <div key={group.key} className="mt-1 bg-gray-50 rounded px-2.5 py-2 space-y-1">
            {group.rows.map(r => <Row key={r.key} row={r} />)}
            {group.note && <p className="text-[10px] text-gray-500 leading-snug">{group.note}</p>}
          </div>
        ) : (
          <div key={group.key} className="space-y-1.5">
            {group.rows.map(r => <Row key={r.key} row={r} />)}
            {group.note && <p className="text-[10px] text-gray-400 leading-snug">{group.note}</p>}
          </div>
        )
      ))}
    </div>
  )
}

export default FinancialSummaryPanel
