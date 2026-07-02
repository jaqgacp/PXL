import type { SetupReadiness } from '@/lib/setupReadiness'

export function SetupReadinessBanner({ readiness }: { readiness: SetupReadiness }) {
  if (readiness.loading) {
    return (
      <div className="border border-gray-200 bg-gray-50 rounded-md px-4 py-3 text-sm text-gray-600">
        Checking setup readiness...
      </div>
    )
  }

  if (readiness.blockers.length === 0 && readiness.warnings.length === 0) return null

  return (
    <div className="border border-amber-200 bg-amber-50 rounded-md px-4 py-3 text-sm">
      {readiness.blockers.length > 0 && (
        <>
          <div className="font-semibold text-amber-900">Setup required before this transaction can be saved or posted</div>
          <ul className="mt-2 list-disc pl-5 text-amber-800 space-y-1">
            {readiness.blockers.map(item => <li key={item}>{item}</li>)}
          </ul>
        </>
      )}
      {readiness.warnings.length > 0 && (
        <ul className="mt-2 list-disc pl-5 text-amber-700 space-y-1">
          {readiness.warnings.map(item => <li key={item}>{item}</li>)}
        </ul>
      )}
    </div>
  )
}
