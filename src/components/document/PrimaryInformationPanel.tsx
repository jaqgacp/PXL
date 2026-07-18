// ─────────────────────────────────────────────────────────────

import { TransactionInfoCard, TransactionInfoCards } from './TransactionPrimitives'
// PrimaryInformationPanel — the document's primary information
// section shown under the header, before the tabs
// (Standard Transaction Workspace spec §5). Config-driven groups
// of read-only, mostly auto-populated fields. Reusable across all
// document types; each supplies its own groups. Provenance hint
// (where a value came from) shows on hover (§6 smart master data).
// ─────────────────────────────────────────────────────────────

export type InfoField = {
  label: string
  value: React.ReactNode
  /** e.g. "from Customer master" — shown on hover, marks auto-populated data. */
  provenance?: string
  /** Span both columns for long values (addresses, memos). */
  wide?: boolean
}

export type InfoGroup = {
  key: string
  title: string
  fields?: InfoField[]
  content?: React.ReactNode
}

function Field({ field }: { field: InfoField }) {
  return (
    <div className={field.wide ? 'sm:col-span-2' : ''} title={field.provenance}>
      <div className="pxl-field-label leading-tight">
        {field.label}
        {field.provenance && <span className="ml-1 text-gray-300" aria-hidden>·</span>}
      </div>
      <div className="pxl-body-text mt-1 leading-snug break-words">{field.value ?? '—'}</div>
    </div>
  )
}

export function PrimaryInformationPanel({ groups }: { groups: InfoGroup[] }) {
  return (
    <TransactionInfoCards>
      {groups.map(group => (
        <TransactionInfoCard key={group.key} title={group.title}>
          {group.content ?? (
            <div className="grid grid-cols-2 gap-x-3 gap-y-1">
              {(group.fields ?? []).map((f, i) => <Field key={i} field={f} />)}
            </div>
          )}
        </TransactionInfoCard>
      ))}
    </TransactionInfoCards>
  )
}

export default PrimaryInformationPanel
