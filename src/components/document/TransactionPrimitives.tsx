import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'

export type TransactionFact = {
  label: string
  value: ReactNode
  hint?: string
  to?: string
}

export type TransactionImpactColumn<Row> = {
  key: string
  label: string
  align?: 'left' | 'right'
  render: (row: Row) => ReactNode
}

export function TransactionInfoCard({ title, facts, children }: {
  title: string
  facts?: TransactionFact[]
  children?: ReactNode
}) {
  return (
    <section className="pxl-transaction-info-card pxl-transaction-card min-w-0 p-3">
      <h2 className="pxl-section-title mb-2 border-b border-[var(--pxl-border-subtle)] pb-1.5">{title}</h2>
      {facts && (
        <dl className="grid min-w-0 grid-cols-1 gap-x-3 gap-y-2 sm:grid-cols-2">
          {facts.map(fact => (
            <div key={fact.label} className="min-w-0">
              <dt className="pxl-field-label">{fact.label}</dt>
              <dd className="pxl-body-text mt-1 break-words">{fact.value}</dd>
              {fact.hint && <div className="pxl-caption mt-0.5">{fact.hint}</div>}
            </div>
          ))}
        </dl>
      )}
      {children}
    </section>
  )
}

export function TransactionInfoCards({ children }: { children: ReactNode }) {
  return <div className="pxl-transaction-info-cards grid min-w-0 grid-cols-1 items-start gap-2 lg:grid-cols-3">{children}</div>
}

export function TransactionSidebar({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <aside className="pxl-side-panel min-w-0 p-3" aria-label={title || 'Transaction summary'}>
      {title && <h2 className="pxl-section-title mb-3">{title}</h2>}
      {children}
    </aside>
  )
}

export function MasterRecordLink({ to, children, ariaLabel }: {
  to: string
  children: ReactNode
  ariaLabel?: string
}) {
  return <Link to={to} aria-label={ariaLabel} className="pxl-customer-link text-sm hover:underline">{children}</Link>
}

export function TransactionImpactTable<Row>({
  label,
  columns,
  rows,
  getRowKey,
  emptyLabel,
}: {
  label: string
  columns: TransactionImpactColumn<Row>[]
  rows: Row[]
  getRowKey: (row: Row, index: number) => string
  emptyLabel: string
}) {
  if (rows.length === 0) return <TransactionEmptyState>{emptyLabel}</TransactionEmptyState>
  return (
    <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]">
      <table className="pxl-data-grid w-full" aria-label={label}>
        <thead>
          <tr>
            {columns.map(column => (
              <th key={column.key} scope="col" className={`px-3 py-2 ${column.align === 'right' ? 'text-right' : 'text-left'}`}>
                {column.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={getRowKey(row, index)}>
              {columns.map(column => (
                <td key={column.key} className={`px-3 py-2 ${column.align === 'right' ? 'text-right font-mono tabular-nums' : 'text-left'}`}>
                  {column.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function TransactionEmptyState({ children }: { children: ReactNode }) {
  return <div className="pxl-empty-state" role="status">{children}</div>
}

export function TransactionLoadingState({ label = 'Loading transaction…' }: { label?: string }) {
  return <div className="pxl-loading-state" role="status" aria-live="polite">{label}</div>
}

export function TransactionErrorState({ message }: { message: string }) {
  return <div className="pxl-validation-message border border-red-300 bg-red-50 text-red-800" role="alert">{message}</div>
}

export function SystemMetadataPanel({ facts }: { facts: TransactionFact[] }) {
  return (
    <TransactionImpactTable
      label="System metadata"
      columns={[
        { key: 'field', label: 'Field', render: fact => fact.label },
        { key: 'value', label: 'Value', render: fact => fact.value },
        { key: 'purpose', label: 'Purpose', render: fact => fact.hint || 'Operational metadata' },
      ]}
      rows={facts}
      getRowKey={fact => fact.label}
      emptyLabel="No system metadata is available for this transaction."
    />
  )
}

export const FinancialSummaryTable = TransactionImpactTable
export const InventoryImpactTable = TransactionImpactTable
export const ApprovalHistoryTable = TransactionImpactTable
export const AuditHistoryTable = TransactionImpactTable
