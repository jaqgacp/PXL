// ─────────────────────────────────────────────────────────────
// SidebarCard — consistent right-rail card wrapper (Standard
// Transaction Workspace §19). Title + optional "view" link to the
// corresponding tab + body. Keeps every sidebar card visually
// identical across document types. A card summarizes and links;
// it must not fully duplicate its tab.
// ─────────────────────────────────────────────────────────────

export function SidebarCard({
  title,
  onView,
  viewLabel = 'View',
  children,
}: {
  title: string
  onView?: () => void
  viewLabel?: string
  children: React.ReactNode
}) {
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <div className="flex items-center justify-between pb-2 mb-2 border-b border-gray-100">
        <span className="text-[10px] font-semibold uppercase tracking-widest text-gray-400">{title}</span>
        {onView && (
          <button onClick={onView} className="text-[11px] font-medium text-blue-600 hover:text-blue-800 hover:underline">{viewLabel}</button>
        )}
      </div>
      {children}
    </div>
  )
}

/** Compact label/value row for sidebar cards. */
export function CardRow({ label, value, strong, muted, paren }: {
  label: string
  value: React.ReactNode
  strong?: boolean
  muted?: boolean
  paren?: boolean
}) {
  const cls = strong ? 'text-gray-900 font-semibold' : muted ? 'text-gray-500' : 'text-gray-700'
  return (
    <div className="flex items-center justify-between py-0.5">
      <span className={`text-xs ${cls}`}>{label}</span>
      <span className={`text-xs font-mono tabular-nums ${cls}`}>{paren ? '(' : ''}{value}{paren ? ')' : ''}</span>
    </div>
  )
}

export default SidebarCard
