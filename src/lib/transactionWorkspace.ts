export type TransactionWorkspaceFamily =
  | 'sales'
  | 'purchase'
  | 'journal'
  | 'inventory'
  | 'banking'
  | 'neutral'

type WorkspaceTone = {
  accent: string
  className: string
}

export const TRANSACTION_WORKSPACE_TONES: Record<TransactionWorkspaceFamily, WorkspaceTone> = {
  sales: {
    accent: '#1d4ed8',
    className: 'pxl-transaction-workspace--sales',
  },
  purchase: {
    accent: '#15803d',
    className: 'pxl-transaction-workspace--purchase',
  },
  journal: {
    accent: '#b45309',
    className: 'pxl-transaction-workspace--journal',
  },
  inventory: {
    accent: '#6d28d9',
    className: 'pxl-transaction-workspace--inventory',
  },
  banking: {
    accent: '#0f766e',
    className: 'pxl-transaction-workspace--banking',
  },
  neutral: {
    accent: '#374151',
    className: 'pxl-transaction-workspace--neutral',
  },
}

export type TransactionButtonVariant = 'primary' | 'secondary' | 'neutral' | 'text' | 'danger'

export function transactionWorkspaceClass(family: TransactionWorkspaceFamily) {
  return `pxl-transaction-workspace ${TRANSACTION_WORKSPACE_TONES[family].className}`
}

export function transactionHeaderClass(family: TransactionWorkspaceFamily) {
  return `${transactionWorkspaceClass(family)} pxl-transaction-header px-5 py-3 flex items-center gap-4 flex-wrap`
}

export function transactionStickyHeaderClass(family: TransactionWorkspaceFamily) {
  return `${transactionWorkspaceClass(family)} pxl-transaction-header sticky top-0 z-30 rounded-b-lg border-b`
}

export function transactionTabBarClass(family: TransactionWorkspaceFamily) {
  return `${TRANSACTION_WORKSPACE_TONES[family].className} pxl-transaction-tabs min-w-0 overflow-hidden`
}

export function transactionTabButtonClass(family: TransactionWorkspaceFamily, active: boolean) {
  return `${TRANSACTION_WORKSPACE_TONES[family].className} pxl-transaction-tab border-b-2 px-4 py-2 transition-colors ${
    active ? 'pxl-transaction-tab--active' : 'pxl-transaction-tab--inactive'
  }`
}

export function transactionSegmentButtonClass(family: TransactionWorkspaceFamily, active: boolean) {
  return `${TRANSACTION_WORKSPACE_TONES[family].className} pxl-button ${
    active ? 'pxl-button--secondary' : 'pxl-button--neutral'
  }`
}

export function transactionCardClass(raised = false) {
  return `pxl-transaction-card ${raised ? 'pxl-transaction-card--raised' : ''}`
}

export function transactionSectionTitleClass() {
  return 'pxl-section-title'
}

export function transactionTableClass() {
  return 'pxl-data-grid'
}

export function transactionButtonClass(variant: TransactionButtonVariant) {
  return `pxl-button pxl-button--${variant}`
}

export function transactionFieldLabelClass() {
  return 'pxl-field-label'
}

export function transactionInputClass() {
  return 'pxl-input'
}

export function transactionReadonlyFieldClass() {
  return 'pxl-readonly-field'
}
