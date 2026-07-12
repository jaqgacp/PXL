// ─────────────────────────────────────────────────────────────
// PrimaryInformationPanel — the document's primary information
// section shown under the header/workflow, before the tabs
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
  fields: InfoField[]
}

function Field({ field }: { field: InfoField }) {
  return (
    <div className={field.wide ? 'sm:col-span-2' : ''} title={field.provenance}>
      <div className="text-[10px] uppercase tracking-wide text-gray-400">
        {field.label}
        {field.provenance && <span className="ml-1 text-gray-300" aria-hidden>·</span>}
      </div>
      <div className="text-xs font-medium text-gray-800 mt-0.5 break-words">{field.value ?? '—'}</div>
    </div>
  )
}

export function PrimaryInformationPanel({ groups }: { groups: InfoGroup[] }) {
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-5">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-x-8 gap-y-5">
        {groups.map(group => (
          <div key={group.key}>
            <div className="text-[10px] font-semibold uppercase tracking-widest text-gray-400 pb-2 mb-3 border-b border-gray-100">
              {group.title}
            </div>
            <div className="grid grid-cols-2 gap-x-4 gap-y-3">
              {group.fields.map((f, i) => <Field key={i} field={f} />)}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

export default PrimaryInformationPanel
