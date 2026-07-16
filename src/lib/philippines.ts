export const PH_TIN_PLACEHOLDER = '000-000-000-00000'
export const PH_TIN_PATTERN = /^\d{3}-\d{3}-\d{3}-\d{5}$/
export const PH_TIN_BRANCH_PATTERN = /^\d{5}$/

export const phTinDigits = (value: string | null | undefined) =>
  String(value || '').replace(/\D/g, '').slice(0, 14)

export function formatPhTinInput(value: string | null | undefined) {
  const digits = phTinDigits(value)
  const parts = [
    digits.slice(0, 3),
    digits.slice(3, 6),
    digits.slice(6, 9),
    digits.slice(9, 14),
  ].filter(Boolean)
  return parts.join('-')
}

export function formatPhTinBranchInput(value: string | null | undefined) {
  return String(value || '').replace(/\D/g, '').slice(0, 5)
}

export function normalizePhTinBranch(value: string | null | undefined, fallback = '00000') {
  const digits = String(value || '').replace(/\D/g, '')
  if (!digits) return fallback
  return digits.slice(0, 5).padStart(5, '0')
}

export function normalizePhTin(value: string | null | undefined, branchCode?: string | null) {
  const digits = String(value || '').replace(/\D/g, '')
  if (!digits) return ''

  if (digits.length === 14) return formatPhTinInput(digits)

  if (digits.length === 9) {
    return formatPhTinInput(`${digits}${normalizePhTinBranch(branchCode)}`)
  }

  if (digits.length > 9 && digits.length < 14) {
    const taxpayer = digits.slice(0, 9)
    const branch = digits.slice(9).padStart(5, '0')
    return formatPhTinInput(`${taxpayer}${branch}`)
  }

  return formatPhTinInput(digits)
}

export function composePhTin(tin: string | null | undefined, branchCode?: string | null) {
  return normalizePhTin(tin, branchCode)
}

export function getPhTinBranch(value: string | null | undefined, branchCode?: string | null) {
  const normalized = normalizePhTin(value, branchCode)
  const digits = phTinDigits(normalized)
  if (digits.length === 14) return digits.slice(9, 14)
  return normalizePhTinBranch(branchCode)
}

export function isValidPhTin(value: string | null | undefined) {
  return PH_TIN_PATTERN.test(normalizePhTin(value))
}

export function phTinMatches(value: string | null | undefined, query: string) {
  const haystack = normalizePhTin(value)
  const formattedQuery = normalizePhTin(query)
  const digitQuery = phTinDigits(query)
  if (!query.trim()) return true
  return (
    haystack.toLowerCase().includes(query.toLowerCase()) ||
    Boolean(formattedQuery && haystack.includes(formattedQuery)) ||
    Boolean(digitQuery && phTinDigits(haystack).includes(digitQuery))
  )
}
