import { useNavigate } from 'react-router-dom'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

// ─────────────────────────────────────────────────────────────
// RelatedDocumentsTab — reusable bidirectional document-chain view
// (Standard Transaction Workspace §12 / spec §14). Renders the FULL
// expected chain whether or not each stage exists: existing docs are
// clickable; missing stages show "None / Not created" (+ an allowed
// create action when valid). The owning page supplies `rows` from
// the links it can resolve, so the same component serves sales,
// purchasing, and accounting chains without hardcoding any of them.
// ─────────────────────────────────────────────────────────────

export type RelatedDirection = 'upstream' | 'current' | 'downstream'

export type RelatedDocRow = {
  key: string
  relationship: string
  docType: string
  direction: RelatedDirection
  number?: string | null
  date?: string | null
  status?: string | null
  amount?: number | null
  /** Route to open the existing document; makes the number a link. */
  href?: string | null
  /** Allowed create action when the stage is missing but valid (e.g. "Create Receipt"). */
  action?: { label: string; href: string } | null
  /** Explains a structurally-absent stage (e.g. "Not modeled on this document"). */
  note?: string
}

const DIRECTION_LABEL: Record<RelatedDirection, string> = {
  upstream: '↑ Upstream',
  current: '● This document',
  downstream: '↓ Downstream',
}

export function RelatedDocumentsTab({ rows, emptyLabel = 'No related documents.' }: {
  rows: RelatedDocRow[]
  emptyLabel?: string
}) {
  const navigate = useNavigate()
  if (rows.length === 0) return <div className="text-sm text-gray-500">{emptyLabel}</div>

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="bg-gray-50 border-b border-gray-200">
          <tr>
            {['Relationship', 'Type', 'Document No.', 'Date', 'Status', 'Amount', 'Direction', 'Action'].map((h, i) => (
              <th key={h} className={`px-3 py-2 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${i === 5 ? 'text-right' : 'text-left'}`}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {rows.map(r => {
            const exists = !!r.number
            return (
              <tr key={r.key} className={r.direction === 'current' ? 'bg-blue-50/40' : 'hover:bg-gray-50/60'}>
                <td className="px-3 py-2 text-xs text-gray-700 whitespace-nowrap">{r.relationship}</td>
                <td className="px-3 py-2 text-xs text-gray-500 whitespace-nowrap">{r.docType}</td>
                <td className="px-3 py-2 text-xs whitespace-nowrap">
                  {exists ? (
                    r.href ? (
                      <button onClick={() => navigate(r.href!)} className="font-mono font-semibold text-blue-600 hover:text-blue-800 hover:underline">{r.number}</button>
                    ) : (
                      <span className="font-mono font-semibold text-gray-900">{r.number}</span>
                    )
                  ) : (
                    <span className="text-gray-400 italic">{r.note ? r.note : 'None / Not created'}</span>
                  )}
                </td>
                <td className="px-3 py-2 text-xs text-gray-600 whitespace-nowrap">{r.date ? <DateCell date={r.date} /> : '—'}</td>
                <td className="px-3 py-2 text-xs">{r.status ? <StatusBadge status={r.status} /> : <span className="text-gray-300">—</span>}</td>
                <td className="px-3 py-2 text-xs text-right">{r.amount != null ? <AmountCell amount={r.amount} /> : <span className="text-gray-300">—</span>}</td>
                <td className="px-3 py-2 text-[11px] text-gray-400 whitespace-nowrap">{DIRECTION_LABEL[r.direction]}</td>
                <td className="px-3 py-2 text-xs whitespace-nowrap">
                  {exists && r.href ? (
                    <button onClick={() => navigate(r.href!)} className="text-blue-600 hover:text-blue-800 hover:underline">Open</button>
                  ) : r.action ? (
                    <button onClick={() => navigate(r.action!.href)} className="text-gray-700 hover:text-gray-900 hover:underline">{r.action.label}</button>
                  ) : (
                    <span className="text-gray-300">—</span>
                  )}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

export default RelatedDocumentsTab
