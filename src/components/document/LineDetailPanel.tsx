// ─────────────────────────────────────────────────────────────
// LineDetailPanel — reveals the selected line's detail beneath the
// grid so the main grid stays uncluttered (Standard Transaction
// Workspace spec §9). Config-driven sections of read-only fields.
// Reusable across document types.
// ─────────────────────────────────────────────────────────────

export type DetailField = { label: string; value: React.ReactNode; wide?: boolean }
export type DetailSection = { key: string; title: string; fields: DetailField[] }

export function LineDetailPanel({
  title,
  sections,
  onClose,
}: {
  title: string
  sections: DetailSection[]
  onClose?: () => void
}) {
  return (
    <div className="mt-2 bg-gray-50 border border-gray-200 rounded p-3">
      <div className="flex items-center justify-between pb-2 mb-3 border-b border-gray-200">
        <span className="text-xs font-semibold text-gray-700">{title}</span>
        {onClose && <button onClick={onClose} className="text-gray-400 hover:text-gray-700 text-sm leading-none">×</button>}
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-x-6 gap-y-3">
        {sections.map(section => (
          <div key={section.key}>
            <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500 mb-1.5">{section.title}</div>
            <div className="space-y-1.5">
              {section.fields.map((f, i) => (
                <div key={i} className={f.wide ? '' : ''}>
                  <div className="text-[10px] uppercase tracking-wide text-gray-400">{f.label}</div>
                  <div className="text-xs text-gray-800 mt-0.5 break-words">{f.value ?? '—'}</div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

export default LineDetailPanel
