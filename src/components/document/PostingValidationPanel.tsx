import type { SetupReadiness } from '@/lib/setupReadiness'
import { ErpSectionHeader } from '@/components/document/ErpSection'

// ─────────────────────────────────────────────────────────────
// PostingValidationPanel — uniform readiness checklist shown on
// every posting document (Standard Transaction Workspace §11).
// Each check mirrors a server-side trigger/RPC validation so the
// panel explains, in advance, exactly what the database will
// reject. Converges the SetupReadinessBanner presentation.
// ─────────────────────────────────────────────────────────────

export type CheckState = 'ok' | 'blocked' | 'pending' | 'info'

export type ValidationCheck = {
  key: string
  label: string
  state: CheckState
  detail?: string
}

const ICON: Record<CheckState, { glyph: string; cls: string }> = {
  ok:      { glyph: '✓', cls: 'text-green-600' },
  blocked: { glyph: '✕', cls: 'text-red-600' },
  pending: { glyph: '○', cls: 'text-gray-300' },
  info:    { glyph: 'ℹ', cls: 'text-blue-500' },
}

/** Convert the shared setup-readiness result into posting checks. */
// eslint-disable-next-line react/only-export-components -- small pure helper colocated with its panel; not a component
export function readinessToChecks(readiness: SetupReadiness): ValidationCheck[] {
  if (readiness.loading) {
    return [{ key: 'loading', label: 'Checking setup readiness…', state: 'pending' }]
  }
  const checks: ValidationCheck[] = readiness.blockers.map((b, i) => ({
    key: `blocker-${i}`, label: b, state: 'blocked',
  }))
  for (let i = 0; i < readiness.warnings.length; i++) {
    checks.push({ key: `warn-${i}`, label: readiness.warnings[i], state: 'info' })
  }
  if (checks.length === 0) {
    checks.push({ key: 'setup-ok', label: 'Company, branch, fiscal period, number series, and GL posting configuration are ready.', state: 'ok' })
  }
  return checks
}

export function PostingValidationPanel({
  checks,
  title = 'Posting Validation',
  footnote,
}: {
  checks: ValidationCheck[]
  title?: string
  footnote?: string
}) {
  const blocked = checks.filter(c => c.state === 'blocked').length
  const pending = checks.some(c => c.state === 'pending')
  const ready = !pending && blocked === 0
  const badge = !pending
    ? ready
      ? <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-green-50 text-green-700">Ready to post</span>
      : <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium bg-red-50 text-red-700">{blocked} blocker{blocked !== 1 ? 's' : ''}</span>
    : null

  return (
    <div className="border border-gray-200 rounded p-3 space-y-2 bg-white">
      <ErpSectionHeader
        title={title}
        description="Validation results checked before posting."
        badge={badge}
        className="pb-2 border-b border-gray-100"
      />
      <ul className="grid grid-cols-1 lg:grid-cols-2 gap-x-6 gap-y-1.5">
        {checks.map(c => {
          const icon = ICON[c.state]
          return (
            <li key={c.key} className="flex items-start gap-2 text-xs">
              <span className={`${icon.cls} leading-4`}>{icon.glyph}</span>
              <span className="min-w-0">
                <span className={c.state === 'blocked' ? 'text-gray-800' : c.state === 'ok' ? 'text-gray-700' : 'text-gray-500'}>{c.label}</span>
                {c.detail && <span className="block text-xs text-gray-400">{c.detail}</span>}
              </span>
            </li>
          )
        })}
      </ul>
      {footnote && <p className="text-xs text-gray-400 pt-1 border-t border-gray-100">{footnote}</p>}
    </div>
  )
}

export default PostingValidationPanel
