import type { TransactionWorkspaceFamily } from './transactionWorkspace'

export type TransactionWorkspacePattern = 'A' | 'B' | 'C' | 'D' | 'E'
export type TransactionModeCoverage = 'dedicated-route' | 'in-page-mode' | 'single-surface' | 'not-applicable'

export type ImplementedTransactionWorkspace = {
  key: string
  transaction: string
  module: 'Sales' | 'Purchasing/AP' | 'Inventory' | 'Accounting' | 'Banking/Treasury' | 'Fixed Assets'
  route: string
  page: string
  family: TransactionWorkspaceFamily
  pattern: TransactionWorkspacePattern
  posting: 'posting' | 'non-posting' | 'mixed' | 'generated-posting'
  form: TransactionModeCoverage
  view: TransactionModeCoverage
  primaryAdaptation: string
  fieldSourceGate: 'sales-invoice-reviewed-slice' | 'transaction-matrix-only'
}

/**
 * Executable route/mode inventory for transaction workspace validation.
 *
 * It records implemented application surfaces, not future manifest routes and
 * not a claim that a transaction's Field Source Matrix is validated. Most PXL
 * transaction pages currently host create/edit/view modes on their list route;
 * Sales Invoice is the only dedicated routed pair.
 */
export const IMPLEMENTED_TRANSACTION_WORKSPACES = [
  { key: 'sales-invoice', transaction: 'Sales Invoice', module: 'Sales', route: '/sales-invoices', page: 'SalesInvoicePage.tsx', family: 'sales', pattern: 'A', posting: 'posting', form: 'dedicated-route', view: 'dedicated-route', primaryAdaptation: 'AR, output VAT, expected CWT, inventory/COGS when applicable', fieldSourceGate: 'sales-invoice-reviewed-slice' },
  { key: 'quotation', transaction: 'Quotation', module: 'Sales', route: '/quotations', page: 'QuotationsPage.tsx', family: 'sales', pattern: 'E', posting: 'non-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Customer offer and conversion status; no posted GL', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'sales-order', transaction: 'Sales Order', module: 'Sales', route: '/sales-orders', page: 'SalesOrdersPage.tsx', family: 'sales', pattern: 'E', posting: 'non-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Customer commitment, fulfillment and billing state', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'delivery-receipt', transaction: 'Delivery Receipt', module: 'Sales', route: '/delivery-receipts', page: 'DeliveryReceiptsPage.tsx', family: 'sales', pattern: 'B', posting: 'non-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Delivery quantities, source order and inventory movement; current confirmation has no direct JE', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'cash-sale', transaction: 'Cash Sale', module: 'Sales', route: '/cash-sales', page: 'CashSalesPage.tsx', family: 'sales', pattern: 'A', posting: 'posting', form: 'in-page-mode', view: 'not-applicable', primaryAdaptation: 'Immediate settlement creates a Sales Invoice; the resulting document uses the Sales Invoice view', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'receipt', transaction: 'Sales Receipt / Official Receipt', module: 'Sales', route: '/receipts', page: 'ReceiptsPage.tsx', family: 'sales', pattern: 'C', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Payment method, applications, CWT and unapplied balance', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'credit-memo', transaction: 'Credit Memo', module: 'Sales', route: '/credit-memos', page: 'CreditMemosPage.tsx', family: 'sales', pattern: 'A', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Customer credit, application and tax reversal evidence', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'debit-memo', transaction: 'Debit Memo', module: 'Sales', route: '/debit-memos', page: 'DebitMemosPage.tsx', family: 'sales', pattern: 'A', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Customer debit adjustment and related invoice evidence', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'customer-return', transaction: 'Customer Return', module: 'Sales', route: '/customer-returns', page: 'CustomerReturnsPage.tsx', family: 'sales', pattern: 'B', posting: 'non-posting', form: 'in-page-mode', view: 'not-applicable', primaryAdaptation: 'Conversion surface creates a draft Credit Memo; the resulting document uses the Credit Memo view', fieldSourceGate: 'transaction-matrix-only' },

  { key: 'purchase-order', transaction: 'Purchase Order', module: 'Purchasing/AP', route: '/purchase-orders', page: 'PurchaseOrdersPage.tsx', family: 'purchase', pattern: 'E', posting: 'non-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Supplier commitment, receipt and billing state', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'receiving-report', transaction: 'Receiving Report / Goods Receipt', module: 'Purchasing/AP', route: '/receiving-reports', page: 'ReceivingReportsPage.tsx', family: 'purchase', pattern: 'B', posting: 'non-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Received quantities, warehouse and source purchase order; current confirmation has no direct JE', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'vendor-bill', transaction: 'Vendor Bill', module: 'Purchasing/AP', route: '/vendor-bills', page: 'VendorBillsPage.tsx', family: 'purchase', pattern: 'A', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'AP, input VAT, EWT and payment balance', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'cash-purchase', transaction: 'Cash Purchase', module: 'Purchasing/AP', route: '/cash-purchases', page: 'CashPurchasesPage.tsx', family: 'purchase', pattern: 'A', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Immediate supplier settlement and input-tax effect', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'payment-voucher', transaction: 'Payment Voucher / Vendor Payment', module: 'Purchasing/AP', route: '/payment-vouchers', page: 'PaymentVouchersPage.tsx', family: 'purchase', pattern: 'C', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Bill applications, bank/cash, EWT and settlement GL', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'vendor-credit', transaction: 'Vendor Credit', module: 'Purchasing/AP', route: '/vendor-credits', page: 'VendorCreditsPage.tsx', family: 'purchase', pattern: 'A', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Supplier credit and bill application evidence', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'supplier-debit-memo', transaction: 'Supplier Debit Memo', module: 'Purchasing/AP', route: '/supplier-debit-memos', page: 'SupplierDebitMemosPage.tsx', family: 'purchase', pattern: 'E', posting: 'non-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Supplier claim, send/acknowledge lifecycle and related bill evidence; no direct JE', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'purchase-return', transaction: 'Purchase Return', module: 'Purchasing/AP', route: '/purchase-returns', page: 'PurchaseReturnsPage.tsx', family: 'purchase', pattern: 'B', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Returned quantities, source receipt/bill and inventory effect', fieldSourceGate: 'transaction-matrix-only' },

  { key: 'stock-adjustment', transaction: 'Inventory Adjustment', module: 'Inventory', route: '/stock-adjustment', page: 'StockAdjustmentPage.tsx', family: 'inventory', pattern: 'B', posting: 'posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Quantity/cost variance, reason and warehouse', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'stock-transfer', transaction: 'Stock Transfer', module: 'Inventory', route: '/stock-transfer', page: 'StockTransferPage.tsx', family: 'inventory', pattern: 'B', posting: 'posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Source/destination warehouse, quantity and in-transit movement', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'goods-issue', transaction: 'Goods Issue', module: 'Inventory', route: '/goods-issue', page: 'GoodsIssuePage.tsx', family: 'inventory', pattern: 'B', posting: 'posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Warehouse issue, quantity, cost and destination use', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'physical-count', transaction: 'Physical Count', module: 'Inventory', route: '/physical-count', page: 'PhysicalCountPage.tsx', family: 'inventory', pattern: 'B', posting: 'mixed', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Counted quantity, variance and generated adjustment', fieldSourceGate: 'transaction-matrix-only' },

  { key: 'journal-entry', transaction: 'Journal Entry', module: 'Accounting', route: '/journal-entries', page: 'JournalEntriesPage.tsx', family: 'journal', pattern: 'D', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Debit/credit lines, balancing, dimensions and reversal', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'recurring-journal', transaction: 'Recurring Journal Template', module: 'Accounting', route: '/recurring-journal-templates', page: 'RecurringJournalTemplatesPage.tsx', family: 'journal', pattern: 'D', posting: 'generated-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Template cadence and generated journal trace', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'amortization-schedule', transaction: 'Amortization Schedule', module: 'Accounting', route: '/amortization-schedules', page: 'AmortizationSchedulesPage.tsx', family: 'journal', pattern: 'D', posting: 'generated-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Schedule inputs and generated entry status', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'revenue-recognition-schedule', transaction: 'Revenue Recognition Schedule', module: 'Accounting', route: '/revenue-recognition-schedules', page: 'RevenueRecognitionSchedulesPage.tsx', family: 'journal', pattern: 'D', posting: 'generated-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Recognition schedule and generated journal status', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'amortization-run', transaction: 'Amortization Entry Run', module: 'Accounting', route: '/amortization-run', page: 'AmortizationRunPage.tsx', family: 'journal', pattern: 'D', posting: 'generated-posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Due entry selection, preview and generated journal', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'revenue-recognition-run', transaction: 'Revenue Recognition Run', module: 'Accounting', route: '/revenue-recognition-run', page: 'RevenueRecognitionRunPage.tsx', family: 'journal', pattern: 'D', posting: 'generated-posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Due recognition selection, preview and generated journal', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'auto-reversal-run', transaction: 'Auto Reversal Run', module: 'Accounting', route: '/auto-reversal-run', page: 'AutoReversalRunPage.tsx', family: 'journal', pattern: 'D', posting: 'generated-posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Eligible source journals and reversal trace', fieldSourceGate: 'transaction-matrix-only' },

  { key: 'petty-cash-voucher', transaction: 'Petty Cash Voucher', module: 'Banking/Treasury', route: '/petty-cash-vouchers', page: 'PettyCashVouchersPage.tsx', family: 'banking', pattern: 'C', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Fund, custodian/payee, expense lines and liquidation', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'petty-cash-replenishment', transaction: 'Petty Cash Replenishment', module: 'Banking/Treasury', route: '/petty-cash-replenishment', page: 'PettyCashReplenishmentPage.tsx', family: 'banking', pattern: 'C', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Fund replenishment, vouchers and bank/cash settlement', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'cash-count-sheet', transaction: 'Cash Count Sheet', module: 'Banking/Treasury', route: '/cash-count-sheet', page: 'CashCountSheetPage.tsx', family: 'banking', pattern: 'C', posting: 'non-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Counted total, book balance and custodian variance; no direct JE', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'fund-transfer', transaction: 'Fund Transfer', module: 'Banking/Treasury', route: '/fund-transfers', page: 'FundTransfersPage.tsx', family: 'banking', pattern: 'C', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Source/destination account, amount and clearing state', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'inter-branch-transfer', transaction: 'Inter-Branch Transfer', module: 'Banking/Treasury', route: '/inter-branch-transfers', page: 'InterBranchTransfersPage.tsx', family: 'banking', pattern: 'C', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Source/destination branch and due-to/due-from impact', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'bank-adjustment', transaction: 'Bank Adjustment', module: 'Banking/Treasury', route: '/bank-adjustments', page: 'BankAdjustmentsPage.tsx', family: 'banking', pattern: 'C', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Bank account, adjustment reason and reconciliation status', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'check-voucher', transaction: 'Check Voucher', module: 'Banking/Treasury', route: '/check-vouchers', page: 'CheckVouchersPage.tsx', family: 'banking', pattern: 'C', posting: 'posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Payee, check details, applications, EWT and cancellation', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'bank-reconciliation', transaction: 'Bank Reconciliation', module: 'Banking/Treasury', route: '/bank-reconciliation', page: 'BankReconciliationPage.tsx', family: 'banking', pattern: 'C', posting: 'non-posting', form: 'in-page-mode', view: 'in-page-mode', primaryAdaptation: 'Statement/book balance, matching, variance and lock state', fieldSourceGate: 'transaction-matrix-only' },

  { key: 'asset-acquisition', transaction: 'Asset Acquisition', module: 'Fixed Assets', route: '/asset-acquisition', page: 'AssetAcquisitionPage.tsx', family: 'neutral', pattern: 'D', posting: 'posting', form: 'single-surface', view: 'not-applicable', primaryAdaptation: 'Asset identity, capitalization cost and acquisition GL', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'depreciation-run', transaction: 'Depreciation Run', module: 'Fixed Assets', route: '/depreciation-run', page: 'DepreciationRunPage.tsx', family: 'neutral', pattern: 'D', posting: 'generated-posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Asset-period selection and authoritative generated entry', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'asset-disposal', transaction: 'Asset Disposal', module: 'Fixed Assets', route: '/asset-disposal', page: 'AssetDisposalPage.tsx', family: 'neutral', pattern: 'D', posting: 'posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Proceeds, carrying value, gain/loss and tax policy', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'asset-transfer', transaction: 'Asset Transfer', module: 'Fixed Assets', route: '/asset-transfer', page: 'AssetTransferPage.tsx', family: 'inventory', pattern: 'B', posting: 'non-posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Source/destination branch/department and asset custody; no direct JE', fieldSourceGate: 'transaction-matrix-only' },
  { key: 'asset-impairment', transaction: 'Asset Impairment', module: 'Fixed Assets', route: '/asset-impairment', page: 'AssetImpairmentPage.tsx', family: 'neutral', pattern: 'D', posting: 'posting', form: 'single-surface', view: 'single-surface', primaryAdaptation: 'Recoverable amount, impairment loss and approval evidence', fieldSourceGate: 'transaction-matrix-only' },
] as const satisfies readonly ImplementedTransactionWorkspace[]

export const REQUIRED_TRANSACTION_TABS = [
  'Lines', 'Financial', 'GL Impact', 'Tax Impact', 'Validation', 'Workflow', 'Approval',
  'Audit', 'Related Docs', 'Related Party', 'Attachments', 'Activity', 'Notes', 'System',
] as const

const dimensionSet = (pattern: TransactionWorkspacePattern) => pattern === 'B'
  ? ['branch', 'warehouse', 'location', 'department', 'project', 'cost center']
  : pattern === 'C'
    ? ['company', 'branch', 'bank/cash account', 'related party']
    : pattern === 'D'
      ? ['company', 'branch', 'department', 'location', 'project', 'cost center', 'functional entity']
      : ['company', 'branch', 'department', 'location', 'project', 'cost center', 'related party']

const sidebarSet = (row: ImplementedTransactionWorkspace) => row.pattern === 'B'
  ? ['Inventory', 'GL Preview', 'Warehouse', 'Audit', 'Quick Actions']
  : row.pattern === 'C'
    ? ['Balance', 'Tax when applicable', 'Payment / Bank', 'GL Preview', 'Audit', 'Quick Actions']
    : row.pattern === 'D'
      ? ['Balance', 'Posting', 'Audit', 'Quick Actions']
      : [row.family === 'purchase' ? 'Supplier' : 'Customer', 'Balance', 'Tax when applicable', 'GL Preview', 'Audit', 'Quick Actions']

/** Concise executable rollout matrix used by structural and browser validation. */
export const TRANSACTION_ROLLOUT_MATRIX = IMPLEMENTED_TRANSACTION_WORKSPACES.map(row => ({
  ...row,
  formRoute: row.key === 'sales-invoice' ? '/sales-invoices/new' : row.route,
  viewRoute: row.view === 'not-applicable' ? null : row.key === 'sales-invoice' ? '/sales-invoices/:id' : `${row.route} (view mode)`,
  requiredTabs: REQUIRED_TRANSACTION_TABS,
  requiredSidebarPanels: sidebarSet(row),
  applicableDimensions: dimensionSet(row.pattern),
  relatedDocuments: row.primaryAdaptation,
  migrationStatus: 'migrated' as const,
  validationStatus: 'typecheck + structural test + authenticated browser route sweep' as const,
}))
