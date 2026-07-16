import { useNavigate } from 'react-router-dom'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'
import { ErpSectionHeader, ERP_EMPTY_CELL, ERP_TABLE, ERP_THEAD, ERP_TH, ERP_TD, ERP_TD_NUM } from '@/components/document/ErpSection'

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
  appliedAmount?: number | null
  openBalance?: number | null
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
  const relationContext = (row: RelatedDocRow) => {
    if (row.direction === 'upstream') return row.relationship || 'Created from'
    if (row.direction === 'downstream') return row.relationship || 'Applied to'
    return 'Current document'
  }

  return (
    <div className="bg-white border border-gray-200 rounded p-3 space-y-2">
      <ErpSectionHeader
        title="Related Documents"
        description="Document chain linked to this transaction."
        className="pb-2 border-b border-gray-100"
      />
      {rows.length === 0 ? (
        <div className={ERP_EMPTY_CELL}>{emptyLabel}</div>
      ) : (
        <div className="overflow-x-auto border border-gray-200 rounded">
          <table className={ERP_TABLE}>
            <thead className={ERP_THEAD}>
              <tr>
                {['Relationship', 'Document Type', 'Document Number', 'Date', 'Status', 'Amount', 'Applied Amount', 'Open Balance', 'Created From / Applied To', 'Direction', 'Action'].map((h, i) => (
                  <th key={h} className={`${ERP_TH} ${i >= 5 && i <= 7 ? 'text-right' : 'text-left'}`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map(r => {
                const exists = !!r.number
                return (
                  <tr key={r.key} className={r.direction === 'current' ? 'bg-gray-50' : 'hover:bg-gray-50/60'}>
                    <td className={`${ERP_TD} whitespace-nowrap`}>{r.relationship}</td>
                    <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{r.docType}</td>
                    <td className={`${ERP_TD} whitespace-nowrap`}>
                      {exists ? (
                        r.href ? (
                          <button onClick={() => navigate(r.href!)} className="font-mono font-medium text-blue-700 hover:text-blue-900 hover:underline">{r.number}</button>
                        ) : (
                          <span className="font-mono text-gray-900">{r.number}</span>
                        )
                      ) : (
                        <span className="text-gray-400 italic">{r.note ? r.note : 'None / Not created'}</span>
                      )}
                    </td>
                    <td className={`${ERP_TD} text-gray-600 whitespace-nowrap`}>{r.date ? <DateCell date={r.date} /> : '—'}</td>
                    <td className={ERP_TD}>{r.status ? <StatusBadge status={r.status} /> : <span className="text-gray-300">—</span>}</td>
                    <td className={ERP_TD_NUM}>{r.amount != null ? <AmountCell amount={r.amount} /> : <span className="text-gray-300">—</span>}</td>
                    <td className={ERP_TD_NUM}>{r.appliedAmount != null ? <AmountCell amount={r.appliedAmount} /> : <span className="text-gray-300">—</span>}</td>
                    <td className={ERP_TD_NUM}>{r.openBalance != null ? <AmountCell amount={r.openBalance} /> : <span className="text-gray-300">—</span>}</td>
                    <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{relationContext(r)}</td>
                    <td className="px-2 py-1.5 text-[11px] text-gray-400 whitespace-nowrap">{DIRECTION_LABEL[r.direction]}</td>
                    <td className={`${ERP_TD} whitespace-nowrap`}>
                      {exists && r.href ? (
                        <button onClick={() => navigate(r.href!)} className="text-blue-700 hover:text-blue-900 hover:underline">Open</button>
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
      )}
    </div>
  )
}

export default RelatedDocumentsTab
