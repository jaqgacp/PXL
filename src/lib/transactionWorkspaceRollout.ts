export type TransactionWorkspaceRolloutStatus =
  | 'NOT_DEFINED'
  | 'DEFINED'
  | 'READY_FOR_IMPLEMENTATION'
  | 'IN_PROGRESS'
  | 'IMPLEMENTED'
  | 'VALIDATED'
  | 'APPROVED_REFERENCE'
  | 'BLOCKED'

export type TransactionWorkspaceModeStatus =
  | 'NOT_REQUIRED'
  | 'NOT_STARTED'
  | 'PARTIAL'
  | 'IMPLEMENTED'
  | 'VALIDATED'

export type TransactionWorkspaceModule =
  | 'Sales'
  | 'Purchasing'
  | 'Accounting'
  | 'Receivables'
  | 'Payables'
  | 'Inventory'
  | 'Banking'
  | 'Fixed Assets'
  | 'Compliance'

export type TransactionWorkspaceFamily =
  | 'sales'
  | 'purchasing'
  | 'accounting'
  | 'receivables'
  | 'payables'
  | 'inventory'
  | 'banking'
  | 'fixed-assets'
  | 'compliance'

export type TransactionImpactLevel =
  | 'none'
  | 'informational'
  | 'preview'
  | 'authoritative'
  | 'posting'
  | 'pending-definition'

export type TransactionWorkspaceTabKey =
  | 'lines'
  | 'financial'
  | 'gl'
  | 'tax'
  | 'inventory'
  | 'payment'
  | 'validation'
  | 'workflow'
  | 'approval'
  | 'audit'
  | 'related'
  | 'party'
  | 'attachments'
  | 'activity'
  | 'notes'
  | 'system'

export type TransactionInformationPanelKind =
  | 'document'
  | 'customer'
  | 'supplier'
  | 'salesContext'
  | 'purchaseContext'
  | 'accountingContext'
  | 'inventoryContext'
  | 'paymentContext'
  | 'bankingContext'
  | 'assetContext'
  | 'taxContext'
  | 'relatedParty'

export type TransactionPrimaryPartyType =
  | 'customer'
  | 'supplier'
  | 'employee'
  | 'bank'
  | 'asset'
  | 'internal'
  | 'none'

export type TransactionWorkspaceReferenceRole =
  | 'editable-reference'
  | 'readonly-reference'
  | 'rollout-test-candidate'

export type TransactionFieldSourceMatrixStatus =
  | 'NOT_STARTED'
  | 'DRAFT'
  | 'COMPLETE'
  | 'VALIDATED'
  | 'BLOCKED'

export type TransactionFieldSourceMatrixValidationStatus =
  | 'NOT_TESTED'
  | 'DOCUMENT_REVIEWED'
  | 'IMPLEMENTATION_REVIEWED'
  | 'END_TO_END_VALIDATED'
  | 'BLOCKED'

export type TransactionWorkspaceDefinition = {
  key: string
  name: string
  module: TransactionWorkspaceModule
  family: TransactionWorkspaceFamily
  documentPrefix: string | null
  routes: {
    list: string
    create?: string
    edit?: string
    view?: string
  }
  primaryParty: {
    type: TransactionPrimaryPartyType
    label: string
    masterRoute?: string
  }
  lifecycleStatuses: string[]
  headerKpis: string[]
  actionGroupsByStatus: Record<string, string[]>
  informationPanels: TransactionInformationPanelKind[]
  tabs: TransactionWorkspaceTabKey[]
  relatedDocuments: string[]
  impacts: {
    posting: TransactionImpactLevel
    gl: TransactionImpactLevel
    tax: TransactionImpactLevel
    inventory: TransactionImpactLevel
    payment: TransactionImpactLevel
  }
  behaviorReferences: {
    posting?: string
    tax?: string
    inventory?: string
    correction?: string
    reversal?: string
    voidOrCancel?: string
  }
  fieldSourceMatrix: {
    document: string
    status: TransactionFieldSourceMatrixStatus
    validationStatus: TransactionFieldSourceMatrixValidationStatus
    blockers: string[]
  }
  documentation: string[]
  rollout: {
    phase: number
    sequence: number
    status: TransactionWorkspaceRolloutStatus
    createEditStatus: TransactionWorkspaceModeStatus
    viewStatus: TransactionWorkspaceModeStatus
    definitionStatus: TransactionWorkspaceRolloutStatus
    recommendedNext?: boolean
    referenceRoles?: TransactionWorkspaceReferenceRole[]
    blockers: string[]
    notes: string
  }
}

export const STANDARD_TRANSACTION_TABS: TransactionWorkspaceTabKey[] = [
  'lines',
  'financial',
  'gl',
  'tax',
  'validation',
  'workflow',
  'approval',
  'audit',
  'related',
  'party',
  'attachments',
  'activity',
  'notes',
  'system',
]

export const STANDARD_TRANSACTION_COMPONENTS = [
  'DocumentLayout',
  'PrimaryInformationPanel',
  'LineGrid',
  'LineDetailPanel',
  'FinancialSummaryPanel',
  'GLImpactPanel',
  'TaxImpactPanel',
  'PostingValidationPanel',
  'WorkflowStrip',
  'RelatedDocumentsTab',
  'AuditTrailSection',
  'ErpSection',
] as const

const docs = {
  workspace: 'docs/PXL/PXL_STANDARD_TRANSACTION_WORKSPACE.md',
  experience: 'docs/PXL/PXL_TRANSACTION_EXPERIENCE_STANDARD.md',
  manifest: 'docs/PXL/PXL_TRANSACTION_WORKSPACE_MANIFEST.md',
  playbook: 'docs/PXL/PXL_TRANSACTION_WORKSPACE_ROLLOUT_PLAYBOOK.md',
  schema: 'docs/PXL/PXL_TRANSACTION_DEFINITION_SCHEMA.md',
  matrix: 'docs/PXL/PXL_TRANSACTION_MATRIX.md',
  accountingRules: 'docs/PXL/PXL_ACCOUNTING_RULES_MATRIX.md',
  fieldSourceMatrix: 'docs/PXL/PXL_TRANSACTION_FIELD_SOURCE_MATRIX.md',
  siForm: 'docs/PXL/PXL_SALES_INVOICE_UX_STANDARD.md',
  siView: 'docs/PXL/PXL_SALES_INVOICE_VIEW_UX_STANDARD.md',
  siFunctional: 'docs/PXL/PXL_SALES_INVOICE_FUNCTIONAL_SPECIFICATION.md',
  siFields: 'docs/PXL/PXL_SALES_INVOICE_FIELD_MAPPING.md',
  siDimensions: 'docs/PXL/PXL_SALES_INVOICE_DIMENSION_MAPPING.md',
  siPosting: 'docs/PXL/PXL_SALES_INVOICE_POSTING_SPECIFICATION.md',
  siGl: 'docs/PXL/PXL_SALES_INVOICE_GL_MAPPING.md',
  siTax: 'docs/PXL/PXL_SALES_INVOICE_TAX_MAPPING.md',
} as const

type TransactionSeed = Omit<TransactionWorkspaceDefinition, 'documentation' | 'rollout' | 'fieldSourceMatrix'> & {
  documentation?: string[]
  fieldSourceMatrix?: TransactionWorkspaceDefinition['fieldSourceMatrix']
  rollout: Omit<TransactionWorkspaceDefinition['rollout'], 'blockers'> & {
    blockers?: string[]
  }
}

function defineTransaction(seed: TransactionSeed): TransactionWorkspaceDefinition {
  return {
    ...seed,
    fieldSourceMatrix: seed.fieldSourceMatrix ?? {
      document: docs.fieldSourceMatrix,
      status: 'NOT_STARTED',
      validationStatus: 'NOT_TESTED',
      blockers: ['Field Source Matrix is mandatory before READY_FOR_IMPLEMENTATION.'],
    },
    documentation: seed.documentation ?? [docs.manifest, docs.playbook, docs.matrix, docs.accountingRules],
    rollout: {
      ...seed.rollout,
      blockers: seed.rollout.blockers ?? [],
    },
  }
}

const salesPanels: TransactionInformationPanelKind[] = ['document', 'customer', 'salesContext']
const purchasePanels: TransactionInformationPanelKind[] = ['document', 'supplier', 'purchaseContext']
const accountingPanels: TransactionInformationPanelKind[] = ['document', 'accountingContext', 'taxContext']
const inventoryPanels: TransactionInformationPanelKind[] = ['document', 'inventoryContext', 'relatedParty']
const bankingPanels: TransactionInformationPanelKind[] = ['document', 'bankingContext', 'paymentContext']
const assetPanels: TransactionInformationPanelKind[] = ['document', 'assetContext', 'accountingContext']

export const TRANSACTION_WORKSPACE_REGISTRY = [
  defineTransaction({
    key: 'sales-invoice',
    name: 'Sales Invoice',
    module: 'Sales',
    family: 'sales',
    documentPrefix: 'SI',
    routes: { list: '/sales-invoices', create: '/sales-invoices/new', edit: '/sales-invoices/:id/edit', view: '/sales-invoices/:id' },
    primaryParty: { type: 'customer', label: 'Customer', masterRoute: '/customers' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'partially_paid', 'paid', 'voided', 'cancelled'],
    headerKpis: ['Invoice Total', 'Collected', 'Balance Due'],
    actionGroupsByStatus: {
      draft: ['Submit', 'Edit', 'Print', 'Email'],
      approved: ['Post', 'Return to Draft', 'Print', 'Email'],
      posted: ['Create Receipt', 'Create Credit Memo', 'Void', 'Print', 'Email'],
    },
    informationPanels: salesPanels,
    tabs: STANDARD_TRANSACTION_TABS,
    relatedDocuments: ['Quotation', 'Sales Order', 'Delivery Receipt', 'Receipt', 'Credit Memo', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'authoritative', payment: 'authoritative' },
    behaviorReferences: {
      posting: docs.accountingRules,
      tax: docs.accountingRules,
      correction: 'Credit Memo or governed correction flow',
      reversal: 'Void/reversal flow through posting engine',
      voidOrCancel: 'Void Sales Invoice',
    },
    fieldSourceMatrix: {
      document: docs.fieldSourceMatrix,
      status: 'COMPLETE',
      validationStatus: 'IMPLEMENTATION_REVIEWED',
      blockers: [
        'PXL-AUD-053 remains open for Project/Location/Functional Entity master decisions plus full view-state/report/API/export/source-chain validation.',
      ],
    },
    documentation: [
      docs.fieldSourceMatrix,
      docs.siForm,
      docs.siView,
      docs.siFunctional,
      docs.siFields,
      docs.siDimensions,
      docs.siPosting,
      docs.siGl,
      docs.siTax,
      docs.workspace,
      docs.experience,
      docs.manifest,
      docs.playbook,
    ],
    rollout: {
      phase: 0,
      sequence: 1,
      status: 'IN_PROGRESS',
      createEditStatus: 'IMPLEMENTED',
      viewStatus: 'IMPLEMENTED',
      definitionStatus: 'DEFINED',
      referenceRoles: ['editable-reference', 'readonly-reference'],
      blockers: [
        'PXL-AUD-053 residual: Project/Location/Functional Entity masters are not implemented and must stay hidden.',
        'Full fixture validation across every listed view state, source chain, report/API/export, and costing-method scenario is still required before VALIDATED/APPROVED_REFERENCE status.',
      ],
      notes: 'Approved structural implementation reference pair with a tested Sales Invoice completeness slice; do not copy Sales Invoice-specific business fields or residual gaps into other transactions.',
    },
  }),
  defineTransaction({
    key: 'sales-order',
    name: 'Sales Order',
    module: 'Sales',
    family: 'sales',
    documentPrefix: 'SO',
    routes: { list: '/sales-orders', create: '/sales-orders/new', edit: '/sales-orders/:id/edit', view: '/sales-orders/:id' },
    primaryParty: { type: 'customer', label: 'Customer', masterRoute: '/customers' },
    lifecycleStatuses: ['draft', 'submitted', 'approved', 'partially_fulfilled', 'fulfilled', 'partially_invoiced', 'invoiced', 'on_hold', 'cancelled'],
    headerKpis: ['Order Total', 'Fulfilled', 'Remaining'],
    actionGroupsByStatus: {
      draft: ['Submit', 'Save Draft', 'Cancel'],
      approved: ['Create Delivery Receipt', 'Create Sales Invoice', 'Put on Hold', 'Cancel'],
    },
    informationPanels: salesPanels,
    tabs: ['lines', 'financial', 'validation', 'workflow', 'approval', 'audit', 'related', 'party', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Quotation', 'Delivery Receipt', 'Sales Invoice', 'Receipt', 'Credit Memo'],
    impacts: { posting: 'none', gl: 'none', tax: 'informational', inventory: 'informational', payment: 'none' },
    behaviorReferences: {
      correction: 'Cancel or revise while unfulfilled according to transaction matrix',
      voidOrCancel: 'Cancel Sales Order',
    },
    rollout: {
      phase: 1,
      sequence: 1,
      status: 'DEFINED',
      createEditStatus: 'PARTIAL',
      viewStatus: 'NOT_STARTED',
      definitionStatus: 'DEFINED',
      recommendedNext: true,
      referenceRoles: ['rollout-test-candidate'],
      blockers: [
        'Field Source Matrix must be completed before READY_FOR_IMPLEMENTATION.',
        'Must be implemented only after explicit rollout instruction and dependency review.',
      ],
      notes: 'First rollout test because it is non-posting and exercises fulfillment/invoicing relationships.',
    },
  }),
  defineTransaction({
    key: 'delivery-receipt',
    name: 'Delivery Receipt',
    module: 'Sales',
    family: 'sales',
    documentPrefix: 'DR',
    routes: { list: '/delivery-receipts', create: '/delivery-receipts/new', edit: '/delivery-receipts/:id/edit', view: '/delivery-receipts/:id' },
    primaryParty: { type: 'customer', label: 'Customer', masterRoute: '/customers' },
    lifecycleStatuses: ['draft', 'approved', 'delivered', 'partially_invoiced', 'invoiced', 'cancelled'],
    headerKpis: ['Delivered Quantity', 'Invoiced Quantity', 'Remaining Quantity'],
    actionGroupsByStatus: { approved: ['Post Delivery', 'Create Sales Invoice', 'Cancel'] },
    informationPanels: salesPanels,
    tabs: ['lines', 'inventory', 'validation', 'workflow', 'approval', 'audit', 'related', 'party', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Sales Order', 'Sales Invoice', 'Customer Return'],
    impacts: { posting: 'pending-definition', gl: 'pending-definition', tax: 'none', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { inventory: docs.matrix, correction: 'Customer Return or cancellation flow' },
    rollout: { phase: 1, sequence: 2, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Requires inventory policy review before implementation.' },
  }),
  defineTransaction({
    key: 'sales-quotation',
    name: 'Sales Quotation',
    module: 'Sales',
    family: 'sales',
    documentPrefix: 'SQ',
    routes: { list: '/quotations', create: '/quotations/new', edit: '/quotations/:id/edit', view: '/quotations/:id' },
    primaryParty: { type: 'customer', label: 'Customer', masterRoute: '/customers' },
    lifecycleStatuses: ['draft', 'sent', 'accepted', 'rejected', 'expired', 'cancelled'],
    headerKpis: ['Quote Total', 'Accepted Amount', 'Open Amount'],
    actionGroupsByStatus: { draft: ['Send', 'Submit', 'Cancel'], accepted: ['Create Sales Order', 'Create Sales Invoice'] },
    informationPanels: salesPanels,
    tabs: ['lines', 'financial', 'validation', 'workflow', 'approval', 'audit', 'related', 'party', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Sales Order', 'Sales Invoice'],
    impacts: { posting: 'none', gl: 'none', tax: 'informational', inventory: 'none', payment: 'none' },
    behaviorReferences: { correction: 'Revise or cancel quotation before conversion' },
    rollout: { phase: 1, sequence: 3, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Non-posting offer workflow; conversion trace must be verified.' },
  }),
  defineTransaction({
    key: 'sales-receipt',
    name: 'Sales Receipt / Official Receipt',
    module: 'Receivables',
    family: 'receivables',
    documentPrefix: 'OR',
    routes: { list: '/receipts', create: '/receipts/new', edit: '/receipts/:id/edit', view: '/receipts/:id' },
    primaryParty: { type: 'customer', label: 'Customer', masterRoute: '/customers' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'bounced', 'voided', 'cancelled'],
    headerKpis: ['Receipt Total', 'Applied', 'Unapplied'],
    actionGroupsByStatus: { draft: ['Submit', 'Post'], posted: ['Apply', 'Bounce', 'Void', 'Print'] },
    informationPanels: ['document', 'customer', 'paymentContext'],
    tabs: STANDARD_TRANSACTION_TABS,
    relatedDocuments: ['Sales Invoice', 'Credit Memo', 'Journal Entry', 'Form 2307 Received'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, tax: docs.accountingRules, reversal: 'Receipt bounce or void flow' },
    rollout: { phase: 1, sequence: 4, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Uses receipt/application and actual CWT recognition rules.' },
  }),
  defineTransaction({
    key: 'credit-memo',
    name: 'Credit Memo',
    module: 'Sales',
    family: 'sales',
    documentPrefix: 'CM',
    routes: { list: '/credit-memos', create: '/credit-memos/new', edit: '/credit-memos/:id/edit', view: '/credit-memos/:id' },
    primaryParty: { type: 'customer', label: 'Customer', masterRoute: '/customers' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'applied', 'voided'],
    headerKpis: ['Credit Total', 'Applied', 'Open Credit'],
    actionGroupsByStatus: { approved: ['Post'], posted: ['Apply Credit', 'Void'] },
    informationPanels: salesPanels,
    tabs: STANDARD_TRANSACTION_TABS,
    relatedDocuments: ['Sales Invoice', 'Receipt', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'pending-definition', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, tax: docs.accountingRules, reversal: 'Credit memo reversal/void flow' },
    rollout: { phase: 1, sequence: 5, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve application and tax reversal evidence.' },
  }),
  defineTransaction({
    key: 'purchase-order',
    name: 'Purchase Order',
    module: 'Purchasing',
    family: 'purchasing',
    documentPrefix: 'PO',
    routes: { list: '/purchase-orders', create: '/purchase-orders/new', edit: '/purchase-orders/:id/edit', view: '/purchase-orders/:id' },
    primaryParty: { type: 'supplier', label: 'Supplier', masterRoute: '/suppliers' },
    lifecycleStatuses: ['draft', 'submitted', 'approved', 'partially_received', 'received', 'partially_billed', 'billed', 'cancelled'],
    headerKpis: ['Order Total', 'Received', 'Remaining'],
    actionGroupsByStatus: { approved: ['Create Goods Receipt', 'Create Vendor Bill', 'Cancel'] },
    informationPanels: purchasePanels,
    tabs: ['lines', 'financial', 'validation', 'workflow', 'approval', 'audit', 'related', 'party', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Purchase Request', 'Goods Receipt', 'Vendor Bill', 'Vendor Credit'],
    impacts: { posting: 'none', gl: 'none', tax: 'informational', inventory: 'informational', payment: 'none' },
    behaviorReferences: { correction: 'Cancel or revise while open according to procurement lifecycle' },
    rollout: { phase: 2, sequence: 1, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'First purchasing-family candidate after sales rollout.' },
  }),
  defineTransaction({
    key: 'goods-receipt',
    name: 'Goods Receipt',
    module: 'Purchasing',
    family: 'purchasing',
    documentPrefix: 'GR',
    routes: { list: '/receiving-reports', create: '/receiving-reports/new', edit: '/receiving-reports/:id/edit', view: '/receiving-reports/:id' },
    primaryParty: { type: 'supplier', label: 'Supplier', masterRoute: '/suppliers' },
    lifecycleStatuses: ['draft', 'received', 'partially_billed', 'billed', 'cancelled'],
    headerKpis: ['Received Quantity', 'Billed Quantity', 'Remaining Quantity'],
    actionGroupsByStatus: { received: ['Create Vendor Bill', 'Return Goods', 'Cancel'] },
    informationPanels: purchasePanels,
    tabs: ['lines', 'inventory', 'validation', 'workflow', 'approval', 'audit', 'related', 'party', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Purchase Order', 'Vendor Bill', 'Purchase Return'],
    impacts: { posting: 'pending-definition', gl: 'pending-definition', tax: 'none', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { inventory: docs.matrix, correction: 'Purchase Return or cancellation flow' },
    rollout: { phase: 2, sequence: 2, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Requires receiving and inventory valuation policy confirmation.' },
  }),
  defineTransaction({
    key: 'vendor-bill',
    name: 'Vendor Bill',
    module: 'Payables',
    family: 'payables',
    documentPrefix: 'VB',
    routes: { list: '/vendor-bills', create: '/vendor-bills/new', edit: '/vendor-bills/:id/edit', view: '/vendor-bills/:id' },
    primaryParty: { type: 'supplier', label: 'Supplier', masterRoute: '/suppliers' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'partially_paid', 'paid', 'voided'],
    headerKpis: ['Bill Total', 'Paid', 'Balance Due'],
    actionGroupsByStatus: { approved: ['Post'], posted: ['Create Vendor Payment', 'Create Vendor Credit', 'Void'] },
    informationPanels: purchasePanels,
    tabs: STANDARD_TRANSACTION_TABS,
    relatedDocuments: ['Purchase Order', 'Goods Receipt', 'Vendor Payment', 'Vendor Credit', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'pending-definition', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, tax: docs.accountingRules, correction: 'Vendor Credit', reversal: 'Void/reversal flow' },
    rollout: { phase: 2, sequence: 3, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Strong existing core flow; view rollout must preserve AP EWT policy.' },
  }),
  defineTransaction({
    key: 'vendor-payment',
    name: 'Vendor Payment',
    module: 'Payables',
    family: 'payables',
    documentPrefix: 'PV',
    routes: { list: '/payment-vouchers', create: '/payment-vouchers/new', edit: '/payment-vouchers/:id/edit', view: '/payment-vouchers/:id' },
    primaryParty: { type: 'supplier', label: 'Supplier', masterRoute: '/suppliers' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'voided'],
    headerKpis: ['Payment Total', 'Applied', 'Unapplied'],
    actionGroupsByStatus: { approved: ['Post'], posted: ['Void', 'Print'] },
    informationPanels: ['document', 'supplier', 'paymentContext'],
    tabs: STANDARD_TRANSACTION_TABS,
    relatedDocuments: ['Vendor Bill', 'Vendor Credit', 'Journal Entry', 'Form 2307 Issued'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, tax: docs.accountingRules, reversal: 'Payment void/reversal flow' },
    rollout: { phase: 2, sequence: 4, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve payment-basis EWT treatment and certificate links.' },
  }),
  defineTransaction({
    key: 'vendor-credit',
    name: 'Vendor Credit',
    module: 'Payables',
    family: 'payables',
    documentPrefix: 'VC',
    routes: { list: '/vendor-credits', create: '/vendor-credits/new', edit: '/vendor-credits/:id/edit', view: '/vendor-credits/:id' },
    primaryParty: { type: 'supplier', label: 'Supplier', masterRoute: '/suppliers' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'applied', 'voided'],
    headerKpis: ['Credit Total', 'Applied', 'Open Credit'],
    actionGroupsByStatus: { approved: ['Post'], posted: ['Apply Credit', 'Void'] },
    informationPanels: purchasePanels,
    tabs: STANDARD_TRANSACTION_TABS,
    relatedDocuments: ['Vendor Bill', 'Vendor Payment', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'pending-definition', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, tax: docs.accountingRules, reversal: 'Vendor credit void/reversal flow' },
    rollout: { phase: 2, sequence: 5, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve AP aging and application controls.' },
  }),
  defineTransaction({
    key: 'purchase-return',
    name: 'Purchase Return',
    module: 'Purchasing',
    family: 'purchasing',
    documentPrefix: 'PRT',
    routes: { list: '/purchase-returns', create: '/purchase-returns/new', edit: '/purchase-returns/:id/edit', view: '/purchase-returns/:id' },
    primaryParty: { type: 'supplier', label: 'Supplier', masterRoute: '/suppliers' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'cancelled'],
    headerKpis: ['Return Total', 'Credited', 'Open Return'],
    actionGroupsByStatus: { approved: ['Post'], posted: ['Create Vendor Credit', 'Cancel'] },
    informationPanels: purchasePanels,
    tabs: STANDARD_TRANSACTION_TABS,
    relatedDocuments: ['Goods Receipt', 'Vendor Credit', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { posting: docs.accountingRules, inventory: docs.matrix, tax: docs.accountingRules },
    rollout: { phase: 2, sequence: 6, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Requires purchase return accounting and inventory trace validation.' },
  }),
  defineTransaction({
    key: 'purchase-request',
    name: 'Purchase Request',
    module: 'Purchasing',
    family: 'purchasing',
    documentPrefix: 'PR',
    routes: { list: '/purchase-requests', create: '/purchase-requests/new', edit: '/purchase-requests/:id/edit', view: '/purchase-requests/:id' },
    primaryParty: { type: 'internal', label: 'Requester' },
    lifecycleStatuses: ['draft', 'submitted', 'approved', 'converted', 'rejected', 'cancelled'],
    headerKpis: ['Requested Amount', 'Approved Amount', 'Open Amount'],
    actionGroupsByStatus: { submitted: ['Approve', 'Reject'], approved: ['Create Purchase Order'] },
    informationPanels: ['document', 'purchaseContext', 'relatedParty'],
    tabs: ['lines', 'financial', 'validation', 'workflow', 'approval', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Purchase Order'],
    impacts: { posting: 'none', gl: 'none', tax: 'none', inventory: 'informational', payment: 'none' },
    behaviorReferences: { correction: 'Reject/cancel/revise request before PO conversion' },
    rollout: { phase: 2, sequence: 7, status: 'NOT_DEFINED', createEditStatus: 'NOT_STARTED', viewStatus: 'NOT_STARTED', definitionStatus: 'NOT_DEFINED', blockers: ['No confirmed current route or business definition in app routes.'], notes: 'Included only if purchase-request scope is confirmed.' },
  }),
  defineTransaction({
    key: 'journal-entry',
    name: 'Journal Entry',
    module: 'Accounting',
    family: 'accounting',
    documentPrefix: 'JE',
    routes: { list: '/journal-entries', create: '/journal-entries/new', edit: '/journal-entries/:id/edit', view: '/journal-entries/:id' },
    primaryParty: { type: 'none', label: 'N/A' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'reversed', 'voided'],
    headerKpis: ['Total Debit', 'Total Credit', 'Difference'],
    actionGroupsByStatus: { draft: ['Submit'], approved: ['Post'], posted: ['Reverse'] },
    informationPanels: accountingPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'approval', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Source Document', 'Reversal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'pending-definition', inventory: 'none', payment: 'none' },
    behaviorReferences: { posting: docs.accountingRules, reversal: 'Exact reversal entry' },
    rollout: { phase: 3, sequence: 1, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Accounting-family reference candidate after sales/purchasing workspace patterns stabilize.' },
  }),
  defineTransaction({
    key: 'recurring-journal-entry',
    name: 'Recurring Journal Entry',
    module: 'Accounting',
    family: 'accounting',
    documentPrefix: 'RJE',
    routes: { list: '/recurring-journal-templates', create: '/recurring-journal-templates/new', edit: '/recurring-journal-templates/:id/edit', view: '/recurring-journal-templates/:id' },
    primaryParty: { type: 'none', label: 'N/A' },
    lifecycleStatuses: ['draft', 'active', 'paused', 'completed', 'cancelled'],
    headerKpis: ['Template Amount', 'Generated Entries', 'Next Run'],
    actionGroupsByStatus: { active: ['Generate', 'Pause', 'Cancel'] },
    informationPanels: accountingPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Journal Entry'],
    impacts: { posting: 'preview', gl: 'preview', tax: 'pending-definition', inventory: 'none', payment: 'none' },
    behaviorReferences: { posting: docs.accountingRules, reversal: 'Generated JE reversal where applicable' },
    rollout: { phase: 3, sequence: 2, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Template workspace must distinguish template from generated JE.' },
  }),
  defineTransaction({
    key: 'customer-credit-application',
    name: 'Customer Credit Application',
    module: 'Receivables',
    family: 'receivables',
    documentPrefix: null,
    routes: { list: '/credit-memos', view: '/credit-memos/:id' },
    primaryParty: { type: 'customer', label: 'Customer', masterRoute: '/customers' },
    lifecycleStatuses: ['draft', 'applied', 'reversed'],
    headerKpis: ['Applied Amount', 'Remaining Credit', 'Invoice Balance'],
    actionGroupsByStatus: { applied: ['Reverse Application'] },
    informationPanels: ['document', 'customer', 'paymentContext'],
    tabs: ['financial', 'validation', 'workflow', 'audit', 'related', 'party', 'activity', 'notes', 'system'],
    relatedDocuments: ['Credit Memo', 'Sales Invoice', 'Receipt'],
    impacts: { posting: 'pending-definition', gl: 'pending-definition', tax: 'none', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { correction: 'Reverse application through governed AR application flow' },
    rollout: { phase: 3, sequence: 5, status: 'DEFINED', createEditStatus: 'NOT_REQUIRED', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Likely implemented as a subworkspace or tab-level document, not a full standalone document shell unless required.' },
  }),
  defineTransaction({
    key: 'vendor-credit-application',
    name: 'Vendor Credit Application',
    module: 'Payables',
    family: 'payables',
    documentPrefix: null,
    routes: { list: '/vendor-credits', view: '/vendor-credits/:id' },
    primaryParty: { type: 'supplier', label: 'Supplier', masterRoute: '/suppliers' },
    lifecycleStatuses: ['draft', 'applied', 'reversed'],
    headerKpis: ['Applied Amount', 'Remaining Credit', 'Bill Balance'],
    actionGroupsByStatus: { applied: ['Reverse Application'] },
    informationPanels: ['document', 'supplier', 'paymentContext'],
    tabs: ['financial', 'validation', 'workflow', 'audit', 'related', 'party', 'activity', 'notes', 'system'],
    relatedDocuments: ['Vendor Credit', 'Vendor Bill', 'Vendor Payment'],
    impacts: { posting: 'pending-definition', gl: 'pending-definition', tax: 'none', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { correction: 'Reverse application through governed AP application flow' },
    rollout: { phase: 3, sequence: 6, status: 'DEFINED', createEditStatus: 'NOT_REQUIRED', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve AP aging and application-date controls.' },
  }),
  defineTransaction({
    key: 'reversal-entry',
    name: 'Reversal Entry',
    module: 'Accounting',
    family: 'accounting',
    documentPrefix: 'REV',
    routes: { list: '/reversal-review', view: '/reversal-review/:id' },
    primaryParty: { type: 'none', label: 'N/A' },
    lifecycleStatuses: ['posted', 'reviewed'],
    headerKpis: ['Debit', 'Credit', 'Difference'],
    actionGroupsByStatus: { posted: ['Open Source', 'Open Journal Entry'] },
    informationPanels: accountingPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'activity', 'notes', 'system'],
    relatedDocuments: ['Original Document', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'pending-definition', payment: 'pending-definition' },
    behaviorReferences: { posting: docs.accountingRules, reversal: 'Exact reversal relationship to original source' },
    rollout: { phase: 3, sequence: 7, status: 'DEFINED', createEditStatus: 'NOT_REQUIRED', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Read-only trace/review workspace candidate.' },
  }),
  defineTransaction({
    key: 'inventory-receipt',
    name: 'Inventory Receipt',
    module: 'Inventory',
    family: 'inventory',
    documentPrefix: 'IR',
    routes: { list: '/inventory-movements', create: '/inventory-receipts/new', edit: '/inventory-receipts/:id/edit', view: '/inventory-receipts/:id' },
    primaryParty: { type: 'internal', label: 'Warehouse' },
    lifecycleStatuses: ['draft', 'posted', 'cancelled'],
    headerKpis: ['Received Quantity', 'Inventory Value', 'Variance'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reverse'] },
    informationPanels: inventoryPanels,
    tabs: ['lines', 'inventory', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Purchase Order', 'Goods Receipt', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { inventory: docs.matrix, posting: docs.accountingRules },
    rollout: { phase: 4, sequence: 1, status: 'NOT_DEFINED', createEditStatus: 'NOT_STARTED', viewStatus: 'NOT_STARTED', definitionStatus: 'NOT_DEFINED', blockers: ['Dedicated route and document model need confirmation.'], notes: 'Inventory family rollout depends on inventory valuation policy.' },
  }),
  defineTransaction({
    key: 'inventory-issue',
    name: 'Inventory Issue / Goods Issue',
    module: 'Inventory',
    family: 'inventory',
    documentPrefix: 'GI',
    routes: { list: '/goods-issue', create: '/goods-issue/new', edit: '/goods-issue/:id/edit', view: '/goods-issue/:id' },
    primaryParty: { type: 'internal', label: 'Warehouse' },
    lifecycleStatuses: ['draft', 'posted', 'reversed', 'cancelled'],
    headerKpis: ['Issued Quantity', 'Inventory Value', 'Variance'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reverse'] },
    informationPanels: inventoryPanels,
    tabs: ['lines', 'inventory', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Journal Entry', 'Inventory Movement'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { inventory: docs.matrix, posting: docs.accountingRules },
    rollout: { phase: 4, sequence: 2, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve cost and stock movement authority.' },
  }),
  defineTransaction({
    key: 'inventory-transfer',
    name: 'Inventory Transfer / Stock Transfer',
    module: 'Inventory',
    family: 'inventory',
    documentPrefix: 'ST',
    routes: { list: '/stock-transfer', create: '/stock-transfer/new', edit: '/stock-transfer/:id/edit', view: '/stock-transfer/:id' },
    primaryParty: { type: 'internal', label: 'Warehouse' },
    lifecycleStatuses: ['draft', 'posted', 'reversed', 'cancelled'],
    headerKpis: ['Transfer Quantity', 'Source Value', 'Destination Value'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reverse'] },
    informationPanels: inventoryPanels,
    tabs: ['lines', 'inventory', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Journal Entry', 'Inventory Movement'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { inventory: docs.matrix, posting: docs.accountingRules },
    rollout: { phase: 4, sequence: 3, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Source/destination warehouse context must be explicit.' },
  }),
  defineTransaction({
    key: 'inventory-adjustment',
    name: 'Inventory Adjustment / Stock Adjustment',
    module: 'Inventory',
    family: 'inventory',
    documentPrefix: 'SA',
    routes: { list: '/stock-adjustment', create: '/stock-adjustment/new', edit: '/stock-adjustment/:id/edit', view: '/stock-adjustment/:id' },
    primaryParty: { type: 'internal', label: 'Warehouse' },
    lifecycleStatuses: ['draft', 'posted', 'reversed', 'cancelled'],
    headerKpis: ['Adjustment Quantity', 'Adjustment Value', 'Variance'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reverse'] },
    informationPanels: inventoryPanels,
    tabs: ['lines', 'inventory', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Journal Entry', 'Inventory Movement'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { inventory: docs.matrix, posting: docs.accountingRules },
    rollout: { phase: 4, sequence: 4, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Requires reason-code and valuation evidence.' },
  }),
  defineTransaction({
    key: 'stock-count',
    name: 'Stock Count / Physical Count',
    module: 'Inventory',
    family: 'inventory',
    documentPrefix: 'PC',
    routes: { list: '/physical-count', create: '/physical-count/new', edit: '/physical-count/:id/edit', view: '/physical-count/:id' },
    primaryParty: { type: 'internal', label: 'Warehouse' },
    lifecycleStatuses: ['draft', 'counted', 'approved', 'posted', 'cancelled'],
    headerKpis: ['Counted Items', 'Variance Quantity', 'Variance Value'],
    actionGroupsByStatus: { counted: ['Submit'], approved: ['Post Adjustment'] },
    informationPanels: inventoryPanels,
    tabs: ['lines', 'inventory', 'financial', 'gl', 'validation', 'workflow', 'approval', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Inventory Adjustment', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { inventory: docs.matrix, posting: docs.accountingRules },
    rollout: { phase: 4, sequence: 5, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Count freeze and variance approval must be defined before rollout.' },
  }),
  defineTransaction({
    key: 'assembly-production',
    name: 'Assembly / Production Transaction',
    module: 'Inventory',
    family: 'inventory',
    documentPrefix: null,
    routes: { list: '/inventory-movements' },
    primaryParty: { type: 'internal', label: 'Production' },
    lifecycleStatuses: ['draft', 'released', 'posted', 'closed', 'cancelled'],
    headerKpis: ['Output Quantity', 'Input Cost', 'Variance'],
    actionGroupsByStatus: { released: ['Post Production', 'Close'] },
    informationPanels: inventoryPanels,
    tabs: ['lines', 'inventory', 'financial', 'gl', 'validation', 'workflow', 'approval', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Inventory Issue', 'Inventory Receipt', 'Journal Entry'],
    impacts: { posting: 'pending-definition', gl: 'pending-definition', tax: 'none', inventory: 'authoritative', payment: 'none' },
    behaviorReferences: { inventory: docs.matrix, posting: docs.accountingRules },
    rollout: { phase: 4, sequence: 6, status: 'NOT_DEFINED', createEditStatus: 'NOT_STARTED', viewStatus: 'NOT_STARTED', definitionStatus: 'NOT_DEFINED', blockers: ['Production/assembly scope not confirmed.'], notes: 'Only in scope if production transactions are adopted.' },
  }),
  defineTransaction({
    key: 'bank-deposit',
    name: 'Bank Deposit',
    module: 'Banking',
    family: 'banking',
    documentPrefix: 'BD',
    routes: { list: '/bank-accounts' },
    primaryParty: { type: 'bank', label: 'Bank Account', masterRoute: '/bank-accounts' },
    lifecycleStatuses: ['draft', 'posted', 'reconciled', 'voided'],
    headerKpis: ['Deposit Total', 'Cleared Amount', 'Uncleared Amount'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reconcile', 'Void'] },
    informationPanels: bankingPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Receipt', 'Fund Transfer', 'Journal Entry', 'Bank Reconciliation'],
    impacts: { posting: 'pending-definition', gl: 'authoritative', tax: 'none', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, correction: 'Void/reverse deposit' },
    rollout: { phase: 5, sequence: 1, status: 'NOT_DEFINED', createEditStatus: 'NOT_STARTED', viewStatus: 'NOT_STARTED', definitionStatus: 'NOT_DEFINED', blockers: ['Dedicated bank deposit transaction route not confirmed.'], notes: 'Banking family candidate after payment workspaces.' },
  }),
  defineTransaction({
    key: 'bank-withdrawal',
    name: 'Bank Withdrawal',
    module: 'Banking',
    family: 'banking',
    documentPrefix: 'BW',
    routes: { list: '/bank-accounts' },
    primaryParty: { type: 'bank', label: 'Bank Account', masterRoute: '/bank-accounts' },
    lifecycleStatuses: ['draft', 'posted', 'reconciled', 'voided'],
    headerKpis: ['Withdrawal Total', 'Cleared Amount', 'Uncleared Amount'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reconcile', 'Void'] },
    informationPanels: bankingPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Check Voucher', 'Fund Transfer', 'Journal Entry', 'Bank Reconciliation'],
    impacts: { posting: 'pending-definition', gl: 'authoritative', tax: 'none', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, correction: 'Void/reverse withdrawal' },
    rollout: { phase: 5, sequence: 2, status: 'NOT_DEFINED', createEditStatus: 'NOT_STARTED', viewStatus: 'NOT_STARTED', definitionStatus: 'NOT_DEFINED', blockers: ['Dedicated bank withdrawal transaction route not confirmed.'], notes: 'May be represented by other payment/treasury documents.' },
  }),
  defineTransaction({
    key: 'bank-transfer',
    name: 'Bank Transfer / Fund Transfer',
    module: 'Banking',
    family: 'banking',
    documentPrefix: 'FT',
    routes: { list: '/fund-transfers', create: '/fund-transfers/new', edit: '/fund-transfers/:id/edit', view: '/fund-transfers/:id' },
    primaryParty: { type: 'bank', label: 'Bank Account', masterRoute: '/bank-accounts' },
    lifecycleStatuses: ['draft', 'posted', 'reconciled', 'voided'],
    headerKpis: ['Transfer Amount', 'Source Cleared', 'Destination Cleared'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Void'] },
    informationPanels: bankingPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Journal Entry', 'Bank Reconciliation'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, reversal: 'Fund transfer reversal' },
    rollout: { phase: 5, sequence: 3, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve source/destination bank identity and clearing state.' },
  }),
  defineTransaction({
    key: 'check-payment',
    name: 'Check Payment / Check Voucher',
    module: 'Banking',
    family: 'banking',
    documentPrefix: 'CV',
    routes: { list: '/check-vouchers', create: '/check-vouchers/new', edit: '/check-vouchers/:id/edit', view: '/check-vouchers/:id' },
    primaryParty: { type: 'supplier', label: 'Payee / Supplier', masterRoute: '/suppliers' },
    lifecycleStatuses: ['draft', 'posted', 'cancelled', 'voided'],
    headerKpis: ['Check Amount', 'EWT', 'Net Cash'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Cancel', 'Print'] },
    informationPanels: ['document', 'supplier', 'bankingContext'],
    tabs: STANDARD_TRANSACTION_TABS,
    relatedDocuments: ['Journal Entry', 'Form 2307 Issued', 'Bank Reconciliation'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'authoritative', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, tax: docs.accountingRules, reversal: 'Cancel Check Voucher' },
    rollout: { phase: 5, sequence: 4, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve supplier-linked EWT and cancellation counter-row behavior.' },
  }),
  defineTransaction({
    key: 'bank-adjustment',
    name: 'Bank Adjustment',
    module: 'Banking',
    family: 'banking',
    documentPrefix: 'BADJ',
    routes: { list: '/bank-adjustments', create: '/bank-adjustments/new', edit: '/bank-adjustments/:id/edit', view: '/bank-adjustments/:id' },
    primaryParty: { type: 'bank', label: 'Bank Account', masterRoute: '/bank-accounts' },
    lifecycleStatuses: ['draft', 'posted', 'reversed', 'voided'],
    headerKpis: ['Adjustment Amount', 'Debit', 'Credit'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reverse'] },
    informationPanels: bankingPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Journal Entry', 'Bank Reconciliation'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { posting: docs.accountingRules, reversal: 'Bank adjustment reversal' },
    rollout: { phase: 5, sequence: 5, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Requires reason-code and reconciliation state visibility.' },
  }),
  defineTransaction({
    key: 'bank-reconciliation-transaction',
    name: 'Reconciliation Transaction View',
    module: 'Banking',
    family: 'banking',
    documentPrefix: null,
    routes: { list: '/bank-reconciliation', view: '/bank-reconciliation/:id' },
    primaryParty: { type: 'bank', label: 'Bank Account', masterRoute: '/bank-accounts' },
    lifecycleStatuses: ['draft', 'reconciled', 'locked', 'reopened'],
    headerKpis: ['Statement Balance', 'Book Balance', 'Difference'],
    actionGroupsByStatus: { draft: ['Reconcile'], reconciled: ['Reopen'] },
    informationPanels: bankingPanels,
    tabs: ['lines', 'financial', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Deposit', 'Withdrawal', 'Check Voucher', 'Bank Adjustment', 'Journal Entry'],
    impacts: { posting: 'none', gl: 'informational', tax: 'none', inventory: 'none', payment: 'authoritative' },
    behaviorReferences: { correction: 'Controlled reopen/reconcile workflow' },
    rollout: { phase: 5, sequence: 6, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Read-only evidence and matching controls are the main workspace concerns.' },
  }),
  defineTransaction({
    key: 'asset-acquisition',
    name: 'Asset Acquisition',
    module: 'Fixed Assets',
    family: 'fixed-assets',
    documentPrefix: 'FA',
    routes: { list: '/asset-acquisition', create: '/asset-acquisition/new', edit: '/asset-acquisition/:id/edit', view: '/asset-acquisition/:id' },
    primaryParty: { type: 'asset', label: 'Asset' },
    lifecycleStatuses: ['draft', 'posted', 'capitalized', 'voided'],
    headerKpis: ['Acquisition Cost', 'Capitalized Amount', 'Open Amount'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Capitalize', 'Void'] },
    informationPanels: assetPanels,
    tabs: ['lines', 'financial', 'gl', 'tax', 'validation', 'workflow', 'approval', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Vendor Bill', 'Journal Entry', 'Asset Register'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'pending-definition', inventory: 'none', payment: 'none' },
    behaviorReferences: { posting: docs.accountingRules, correction: 'Asset adjustment or disposal flow' },
    rollout: { phase: 6, sequence: 1, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve asset register and capitalization evidence.' },
  }),
  defineTransaction({
    key: 'capitalization',
    name: 'Capitalization',
    module: 'Fixed Assets',
    family: 'fixed-assets',
    documentPrefix: 'CAP',
    routes: { list: '/asset-register' },
    primaryParty: { type: 'asset', label: 'Asset' },
    lifecycleStatuses: ['draft', 'posted', 'reversed'],
    headerKpis: ['Capitalized Amount', 'Asset Cost', 'Difference'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reverse'] },
    informationPanels: assetPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Asset Acquisition', 'Journal Entry', 'Asset Register'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'none', payment: 'none' },
    behaviorReferences: { posting: docs.accountingRules, reversal: 'Capitalization reversal' },
    rollout: { phase: 6, sequence: 2, status: 'NOT_DEFINED', createEditStatus: 'NOT_STARTED', viewStatus: 'NOT_STARTED', definitionStatus: 'NOT_DEFINED', blockers: ['Capitalization document model needs confirmation.'], notes: 'May be a state/action within Asset Acquisition or Asset Register rather than a separate workspace.' },
  }),
  defineTransaction({
    key: 'depreciation-run',
    name: 'Depreciation Run',
    module: 'Fixed Assets',
    family: 'fixed-assets',
    documentPrefix: 'DEP',
    routes: { list: '/depreciation-run', create: '/depreciation-run/new', edit: '/depreciation-run/:id/edit', view: '/depreciation-run/:id' },
    primaryParty: { type: 'internal', label: 'Asset Group' },
    lifecycleStatuses: ['draft', 'posted', 'reversed'],
    headerKpis: ['Depreciation Amount', 'Assets Count', 'Difference'],
    actionGroupsByStatus: { draft: ['Run Preview', 'Post'], posted: ['Reverse'] },
    informationPanels: assetPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Journal Entry', 'Asset Register'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'pending-definition', inventory: 'none', payment: 'none' },
    behaviorReferences: { posting: docs.accountingRules, reversal: 'Depreciation run reversal' },
    rollout: { phase: 6, sequence: 3, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Run output must be authoritative and not recomputed in posted view.' },
  }),
  defineTransaction({
    key: 'asset-transfer',
    name: 'Asset Transfer',
    module: 'Fixed Assets',
    family: 'fixed-assets',
    documentPrefix: 'FAT',
    routes: { list: '/asset-transfer', create: '/asset-transfer/new', edit: '/asset-transfer/:id/edit', view: '/asset-transfer/:id' },
    primaryParty: { type: 'asset', label: 'Asset' },
    lifecycleStatuses: ['draft', 'posted', 'reversed', 'cancelled'],
    headerKpis: ['Asset Cost', 'Source Location', 'Destination Location'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reverse'] },
    informationPanels: assetPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Asset Register', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'none', inventory: 'none', payment: 'none' },
    behaviorReferences: { posting: docs.accountingRules, correction: 'Reverse or transfer back through governed flow' },
    rollout: { phase: 6, sequence: 4, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Source/destination ownership and location dimensions must be visible.' },
  }),
  defineTransaction({
    key: 'asset-disposal',
    name: 'Asset Disposal',
    module: 'Fixed Assets',
    family: 'fixed-assets',
    documentPrefix: 'FAD',
    routes: { list: '/asset-disposal', create: '/asset-disposal/new', edit: '/asset-disposal/:id/edit', view: '/asset-disposal/:id' },
    primaryParty: { type: 'asset', label: 'Asset' },
    lifecycleStatuses: ['draft', 'posted', 'reversed', 'voided'],
    headerKpis: ['Proceeds', 'Carrying Amount', 'Gain/Loss'],
    actionGroupsByStatus: { draft: ['Post'], posted: ['Reverse'] },
    informationPanels: assetPanels,
    tabs: ['lines', 'financial', 'gl', 'tax', 'validation', 'workflow', 'approval', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Asset Register', 'Journal Entry', 'Receipt'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'pending-definition', inventory: 'none', payment: 'pending-definition' },
    behaviorReferences: { posting: docs.accountingRules, tax: docs.accountingRules, reversal: 'Asset disposal reversal' },
    rollout: { phase: 6, sequence: 5, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Must preserve gain/loss and tax evidence.' },
  }),
  defineTransaction({
    key: 'asset-adjustment',
    name: 'Asset Adjustment / Impairment',
    module: 'Fixed Assets',
    family: 'fixed-assets',
    documentPrefix: 'FAA',
    routes: { list: '/asset-impairment', create: '/asset-impairment/new', edit: '/asset-impairment/:id/edit', view: '/asset-impairment/:id' },
    primaryParty: { type: 'asset', label: 'Asset' },
    lifecycleStatuses: ['draft', 'approved', 'posted', 'reversed'],
    headerKpis: ['Adjustment Amount', 'Carrying Amount', 'Revised Amount'],
    actionGroupsByStatus: { approved: ['Post'], posted: ['Reverse'] },
    informationPanels: assetPanels,
    tabs: ['lines', 'financial', 'gl', 'validation', 'workflow', 'approval', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Asset Register', 'Journal Entry'],
    impacts: { posting: 'posting', gl: 'authoritative', tax: 'pending-definition', inventory: 'none', payment: 'none' },
    behaviorReferences: { posting: docs.accountingRules, reversal: 'Asset adjustment reversal' },
    rollout: { phase: 6, sequence: 6, status: 'DEFINED', createEditStatus: 'PARTIAL', viewStatus: 'NOT_STARTED', definitionStatus: 'DEFINED', notes: 'Approval and valuation evidence should be prominent.' },
  }),
  defineTransaction({
    key: 'compliance-transaction-views',
    name: 'Compliance and Specialized Transaction Views',
    module: 'Compliance',
    family: 'compliance',
    documentPrefix: null,
    routes: { list: '/vat-dashboard' },
    primaryParty: { type: 'none', label: 'N/A' },
    lifecycleStatuses: ['draft', 'generated', 'reviewed', 'filed', 'superseded', 'voided'],
    headerKpis: ['Tax Base', 'Tax Amount', 'Variance'],
    actionGroupsByStatus: { generated: ['Review', 'File', 'Supersede'] },
    informationPanels: ['document', 'taxContext', 'accountingContext'],
    tabs: ['lines', 'financial', 'tax', 'validation', 'workflow', 'approval', 'audit', 'related', 'attachments', 'activity', 'notes', 'system'],
    relatedDocuments: ['Source Transactions', 'Tax Detail Entries', 'Report Snapshot'],
    impacts: { posting: 'none', gl: 'informational', tax: 'authoritative', inventory: 'none', payment: 'none' },
    behaviorReferences: { tax: docs.accountingRules, correction: 'Supersede or amend compliance snapshot' },
    rollout: { phase: 7, sequence: 1, status: 'BLOCKED', createEditStatus: 'NOT_REQUIRED', viewStatus: 'NOT_STARTED', definitionStatus: 'NOT_DEFINED', blockers: ['Implement only after core operational, accounting, and audit workspace patterns are stable.'], notes: 'Specialized compliance views should inherit the read-only workspace pattern only after core transactions are stable.' },
  }),
] as const satisfies readonly TransactionWorkspaceDefinition[]

export function getTransactionWorkspaceDefinitions() {
  return TRANSACTION_WORKSPACE_REGISTRY
}

export function getTransactionWorkspaceDefinition(key: string) {
  return TRANSACTION_WORKSPACE_REGISTRY.find(transaction => transaction.key === key)
}

export function getNextEligibleTransaction() {
  return TRANSACTION_WORKSPACE_REGISTRY
    .filter(transaction =>
      transaction.rollout.status === 'READY_FOR_IMPLEMENTATION'
      && ['COMPLETE', 'VALIDATED'].includes(transaction.fieldSourceMatrix.status),
    )
    .sort((a, b) => a.rollout.phase - b.rollout.phase || a.rollout.sequence - b.rollout.sequence)[0]
}

export function getTransactionsByRolloutStatus(status: TransactionWorkspaceRolloutStatus) {
  return TRANSACTION_WORKSPACE_REGISTRY.filter(transaction => transaction.rollout.status === status)
}
