import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { RefreshCw } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { ErpSectionHeader, ERP_EMPTY_CELL, ERP_TABLE, ERP_THEAD, ERP_TH, ERP_TD, ERP_TD_NUM, ERP_TOTAL_ROW } from '@/components/document/ErpSection'

type ConfigAccountKey =
  | 'ar_account_id'
  | 'ap_account_id'
  | 'vat_payable_account_id'
  | 'input_vat_account_id'
  | 'ewt_withheld_account_id'
  | 'ewt_payable_account_id'
  | 'customer_advances_account_id'
  | 'supplier_down_payments_account_id'
  | 'default_cash_account_id'

export type GLImpactRow = {
  accountId?: string | null
  configKey?: ConfigAccountKey
  accountLabel?: string
  accountSourceLabel?: string
  technicalSource?: string
  impactGroup?: 'COMMERCIAL' | 'INVENTORY' | 'WITHHOLDING_INFORMATIONAL' | 'OTHER'
  accountingEffect?: string
  sourceLabel?: string
  itemId?: string | null
  itemCode?: string | null
  warehouseId?: string | null
  warehouseCode?: string | null
  quantity?: number | null
  unitCost?: number | null
  totalCost?: number | null
  valuationMethod?: string | null
  inventoryMovementId?: string | null
  description: string
  debit: number
  credit: number
}

export type ServerGLImpactLine = {
  line_number: number
  account_id: string | null
  account_code: string
  account_name: string
  account_source: string
  description: string | null
  debit: number
  credit: number
  branch_id: string | null
  department_id: string | null
  cost_center_id: string | null
  impact_group?: string | null
  accounting_effect?: string | null
  source_type?: string | null
  source_line_id?: string | null
  item_id?: string | null
  item_code?: string | null
  warehouse_id?: string | null
  warehouse_code?: string | null
  quantity?: number | null
  unit_cost?: number | null
  total_cost?: number | null
  valuation_method?: string | null
  inventory_movement_id?: string | null
}

export type ServerGLImpact = {
  mode: string
  journal_entry_id: string | null
  je_number: string | null
  posting_date: string | null
  fiscal_period_id: string | null
  fiscal_period_name: string | null
  branch_id: string | null
  branch_name: string | null
  source_doc_type: string
  source_doc_id: string
  source_display_name: string | null
  source_route: string | null
  rule_explanation: string | null
  total_debit: number
  total_credit: number
  balanced: boolean
  lines: ServerGLImpactLine[]
}

type Account = { id: string; account_code: string; account_name: string }
type DisplayRow = {
  key: string
  lineNumber: number | null
  accountId: string | null
  accountCode: string
  accountName: string
  accountSource: string
  technicalSource: string
  description: string
  debit: number
  credit: number
  missingAccount: boolean
  branchId: string | null
  departmentId: string | null
  costCenterId: string | null
  impactGroup: 'COMMERCIAL' | 'INVENTORY' | 'WITHHOLDING_INFORMATIONAL' | 'OTHER'
  accountingEffect: string
  sourceLabel: string
  itemId: string | null
  itemCode: string | null
  warehouseId: string | null
  warehouseCode: string | null
  quantity: number | null
  unitCost: number | null
  totalCost: number | null
  valuationMethod: string | null
  inventoryMovementId: string | null
}

export type WithholdingInfo = {
  withholdingType: string
  atc?: string | null
  rate?: number | null
  base: number
  amount: number
  expectedNetCollectible: number
  recognitionEvent: string
  status: string
}

type Props = {
  companyId?: string | null
  sourceDocType: string
  sourceDocId?: string | null
  postingDate?: string | null
  previewRows: GLImpactRow[]
  title?: string
  separatedSalesInvoiceImpact?: boolean
  withholdingInfo?: WithholdingInfo | null
}

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const friendlyConfigSource: Partial<Record<ConfigAccountKey, string>> = {
  ar_account_id: 'Default Accounts Receivable Account',
  vat_payable_account_id: 'Default VAT Payable Account',
  input_vat_account_id: 'Default Input VAT Account',
  ap_account_id: 'Default Accounts Payable Account',
  ewt_withheld_account_id: 'Default EWT Withheld Account',
  ewt_payable_account_id: 'Default EWT Payable Account',
  customer_advances_account_id: 'Default Customer Advances Account',
  supplier_down_payments_account_id: 'Default Supplier Down Payments Account',
  default_cash_account_id: 'Default Cash Account',
}

const friendlyAccountSource = (source: string) => {
  const normalized = source.trim()
  if (normalized.startsWith('company_accounting_config.')) {
    const key = normalized.split('.')[1] as ConfigAccountKey
    return friendlyConfigSource[key] || 'Company Posting Configuration'
  }
  if (normalized === 'document line account') return 'Revenue Account from Item'
  if (normalized === 'client draft estimate') return 'Draft Preview'
  return normalized
    .replace(/_/g, ' ')
    .replace(/\b\w/g, char => char.toUpperCase())
}

const inferImpactGroup = (source: string, description: string): DisplayRow['impactGroup'] => {
  const normalized = `${source} ${description}`.toLowerCase()
  if (normalized.includes('cogs') || normalized.includes('inventory_account') || normalized.startsWith('inventory')) return 'INVENTORY'
  return 'COMMERCIAL'
}

const effectLabel = (effect?: string | null, fallback = 'OTHER') =>
  (effect || fallback).replace(/_/g, ' ').replace(/\b\w/g, char => char.toUpperCase())

const tracePath = (sourceDocType: string, sourceDocId: string, journalEntryId?: string | null) => {
  const params = new URLSearchParams()
  if (journalEntryId) params.set('jeId', journalEntryId)
  else {
    params.set('sourceType', sourceDocType)
    params.set('sourceId', sourceDocId)
  }
  return `/accounting-trace?${params.toString()}`
}

export function GLImpactPanel({
  companyId,
  sourceDocType,
  sourceDocId,
  postingDate,
  previewRows,
  title = 'GL Impact',
  separatedSalesInvoiceImpact = false,
  withholdingInfo = null,
}: Props) {
  const [accounts, setAccounts] = useState<Record<string, Account>>({})
  const [config, setConfig] = useState<Record<string, string | null>>({})
  const [serverImpact, setServerImpact] = useState<ServerGLImpact | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    if (sourceDocId || !companyId) {
      setAccounts({})
      setConfig({})
      return
    }
    let alive = true
    const load = async () => {
      const [coaRes, cfgRes] = await Promise.all([
        supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId),
        supabase.from('company_accounting_config').select('*').eq('company_id', companyId).maybeSingle(),
      ])
      if (!alive) return
      const map: Record<string, Account> = {}
      for (const account of (coaRes.data as Account[]) || []) map[account.id] = account
      setAccounts(map)
      setConfig((cfgRes.data as Record<string, string | null>) || {})
    }
    void load()
    return () => { alive = false }
  }, [companyId, sourceDocId])

  useEffect(() => {
    if (!sourceDocId) {
      setServerImpact(null)
      setError('')
      setLoading(false)
      return
    }
    let alive = true
    const load = async () => {
      setLoading(true)
      setError('')
      const { data, error: rpcError } = await supabase.rpc('fn_preview_gl_impact', {
        p_source_doc_type: sourceDocType,
        p_source_doc_id: sourceDocId,
        p_posting_date: postingDate || undefined,
      })
      if (!alive) return
      if (rpcError) {
        setServerImpact(null)
        setError(rpcError.message)
      } else {
        setServerImpact(data as unknown as ServerGLImpact)
      }
      setLoading(false)
    }
    void load()
    return () => { alive = false }
  }, [postingDate, sourceDocId, sourceDocType, reloadKey])

  const rows = useMemo<DisplayRow[]>(() => {
    if (sourceDocId) {
      return (serverImpact?.lines || []).map((line, index) => ({
        key: `server-${line.line_number}-${line.account_id}-${index}`,
        lineNumber: line.line_number,
        accountId: line.account_id,
        accountCode: line.account_code,
        accountName: line.account_name,
        accountSource: friendlyAccountSource(line.account_source),
        technicalSource: line.account_source,
        description: line.description || '',
        debit: Number(line.debit),
        credit: Number(line.credit),
        missingAccount: false,
        branchId: line.branch_id,
        departmentId: line.department_id,
        costCenterId: line.cost_center_id,
        impactGroup: (line.impact_group as DisplayRow['impactGroup'] | null) || inferImpactGroup(line.account_source, line.description || ''),
        accountingEffect: effectLabel(line.accounting_effect),
        sourceLabel: line.source_type || friendlyAccountSource(line.account_source),
        itemId: line.item_id || null,
        itemCode: line.item_code || null,
        warehouseId: line.warehouse_id || null,
        warehouseCode: line.warehouse_code || null,
        quantity: line.quantity == null ? null : Number(line.quantity),
        unitCost: line.unit_cost == null ? null : Number(line.unit_cost),
        totalCost: line.total_cost == null ? null : Number(line.total_cost),
        valuationMethod: line.valuation_method || null,
        inventoryMovementId: line.inventory_movement_id || null,
      }))
    }

    return previewRows
      .filter(row => Math.abs(row.debit) > 0.005 || Math.abs(row.credit) > 0.005)
      .map((row, index) => {
        const accountId = row.accountId || (row.configKey ? config[row.configKey] : null)
        const account = accountId ? accounts[accountId] : null
        const technicalSource = row.technicalSource || (row.configKey
          ? `company_accounting_config.${row.configKey}`
          : row.accountId
            ? 'document_line_account'
            : 'client_draft_estimate')
        return {
          key: `client-${index}-${row.description}`,
          lineNumber: index + 1,
          accountId: accountId || null,
          accountCode: account?.account_code || row.accountLabel || (row.configKey ? `Missing ${row.configKey.replace(/_/g, ' ')}` : 'Missing account'),
          accountName: account?.account_name || '',
          accountSource: row.accountSourceLabel || (row.configKey
            ? friendlyConfigSource[row.configKey] || 'Company Posting Configuration'
            : row.accountId
              ? 'Revenue Account from Item'
              : 'Draft Preview'),
          technicalSource,
          description: row.description,
          debit: Number(row.debit),
          credit: Number(row.credit),
          missingAccount: !accountId && !row.accountLabel,
          branchId: null,
          departmentId: null,
          costCenterId: null,
          impactGroup: row.impactGroup || inferImpactGroup(technicalSource, row.description),
          accountingEffect: effectLabel(row.accountingEffect),
          sourceLabel: row.sourceLabel || row.accountSourceLabel || (row.configKey ? friendlyConfigSource[row.configKey] || 'Company Posting Configuration' : 'Draft Preview'),
          itemId: row.itemId || null,
          itemCode: row.itemCode || null,
          warehouseId: row.warehouseId || null,
          warehouseCode: row.warehouseCode || null,
          quantity: row.quantity == null ? null : Number(row.quantity),
          unitCost: row.unitCost == null ? null : Number(row.unitCost),
          totalCost: row.totalCost == null ? null : Number(row.totalCost),
          valuationMethod: row.valuationMethod || null,
          inventoryMovementId: row.inventoryMovementId || null,
        }
      })
  }, [accounts, config, previewRows, serverImpact, sourceDocId])

  const totalDebit = sourceDocId && serverImpact
    ? Number(serverImpact.total_debit)
    : rows.reduce((sum, row) => sum + row.debit, 0)
  const totalCredit = sourceDocId && serverImpact
    ? Number(serverImpact.total_credit)
    : rows.reduce((sum, row) => sum + row.credit, 0)
  const balanced = sourceDocId && serverImpact
    ? serverImpact.balanced
    : Math.abs(totalDebit - totalCredit) <= 0.01
  const missingAccount = rows.some(row => row.missingAccount)
  const modeLabel = sourceDocId
    ? serverImpact?.mode === 'posted'
      ? `Posted JE ${serverImpact.je_number || ''}`.trim()
      : 'Posting Preview'
    : 'Draft GL preview'
  const ruleExplanation = sourceDocId
    ? serverImpact?.rule_explanation
    : 'Estimated from the current unsaved form.'
  const balanceLabel = balanced
    ? sourceDocId && serverImpact?.mode === 'posted'
      ? 'Posted Balanced'
      : 'Preview Balanced'
    : `Out by ${fmt(totalDebit - totalCredit)}`
  const branchLabel = (row: DisplayRow) => serverImpact?.branch_name || (row.branchId ? 'Assigned' : 'Not assigned')
  const dimensionLabel = (value: string | null) => value ? 'Assigned' : 'Not assigned'
  const commercialRows = rows.filter(row => row.impactGroup !== 'INVENTORY')
  const inventoryRows = rows.filter(row => row.impactGroup === 'INVENTORY')
  const rowTotals = (sourceRows: DisplayRow[]) => ({
    debit: sourceRows.reduce((sum, row) => sum + row.debit, 0),
    credit: sourceRows.reduce((sum, row) => sum + row.credit, 0),
  })
  const commercialTotals = rowTotals(commercialRows)
  const inventoryTotals = rowTotals(inventoryRows)
  const combinedDifference = totalDebit - totalCredit

  const actions = sourceDocId ? [
    serverImpact?.source_route
      ? { label: 'Source', to: serverImpact.source_route }
      : null,
    serverImpact?.journal_entry_id
      ? { label: 'Journal entry', to: `/journal-entries?jeId=${serverImpact.journal_entry_id}` }
      : null,
    serverImpact?.journal_entry_id
      ? { label: 'General ledger', to: `/general-ledger?jeId=${serverImpact.journal_entry_id}` }
      : null,
    { label: 'Full trace', to: tracePath(sourceDocType, sourceDocId, serverImpact?.journal_entry_id) },
  ].filter((action): action is NonNullable<typeof action> => Boolean(action)) : []

  return (
    <div className="bg-white border border-gray-200 rounded overflow-hidden">
      <div className="px-3 py-2 border-b border-gray-100 flex items-start justify-between gap-3">
        <ErpSectionHeader title={title} description={loading ? 'Loading GL impact...' : modeLabel} />
        <div className="flex items-center gap-2">
          <div className={`inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium ${balanced && !missingAccount ? 'bg-green-50 text-green-700' : 'bg-orange-50 text-orange-700'}`}>
            {balanceLabel}
          </div>
          {sourceDocId && (
            <button
              type="button"
              onClick={() => setReloadKey(key => key + 1)}
              disabled={loading}
              className="inline-flex h-7 w-7 items-center justify-center border border-gray-200 rounded text-gray-500 hover:bg-gray-50 disabled:opacity-50"
              title="Reload GL impact"
              aria-label="Reload GL impact"
            >
              <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" />
            </button>
          )}
        </div>
      </div>

      {serverImpact && sourceDocId && (
        <div className="px-3 py-2 border-b border-gray-100 bg-gray-50 grid grid-cols-2 lg:grid-cols-4 gap-x-3 gap-y-2">
          {[
            ['Posting date', serverImpact.posting_date || 'Not assigned'],
            ['Fiscal period', serverImpact.fiscal_period_name || 'Not assigned'],
            ['Branch', serverImpact.branch_name || 'Company level'],
            ['Source', serverImpact.source_display_name || sourceDocType],
          ].map(([label, value]) => (
            <div key={label} className="min-w-0">
              <div className="text-[10px] font-medium uppercase tracking-wide text-gray-400">{label}</div>
              <div className="text-xs text-gray-700 mt-0.5 truncate" title={value}>{value}</div>
            </div>
          ))}
        </div>
      )}

      {actions.length > 0 && (
        <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-x-4 gap-y-1.5 flex-wrap">
          {actions.map(action => (
            <Link key={action.label} to={action.to} className="text-xs text-blue-700 hover:text-blue-900 hover:underline">
              {action.label}
            </Link>
          ))}
        </div>
      )}

      {error && (
        <div className="mx-3 my-3 border border-red-200 bg-red-50 rounded px-3 py-2 text-xs text-red-700">
          GL impact could not be loaded.
          <details className="mt-1">
            <summary className="cursor-pointer">Technical detail</summary>
            <div className="mt-1 font-mono text-[11px]">{error}</div>
          </details>
        </div>
      )}

      {!error && !loading && rows.length === 0 ? (
        <div className={ERP_EMPTY_CELL}>
          {sourceDocId ? 'No GL lines are produced by the current posting rule.' : 'Enter transaction lines to preview accounting impact.'}
        </div>
      ) : !error && rows.length > 0 && separatedSalesInvoiceImpact ? (
        <div className="space-y-4 p-3">
          <AccountingImpactSection
            title="Commercial / Revenue Accounting Impact"
            subtitle="Customer receivable, revenue, VAT, discounts, and other commercial accounting effects."
            rows={commercialRows}
            totals={commercialTotals}
            serverImpact={serverImpact}
            sourceDocId={sourceDocId}
            ruleExplanation={ruleExplanation}
            branchLabel={branchLabel}
            dimensionLabel={dimensionLabel}
            kind="commercial"
          />
          <AccountingImpactSection
            title="Inventory / Cost Accounting Impact"
            subtitle="Inventory release, valuation, and cost-of-goods-sold accounting effects."
            rows={inventoryRows}
            totals={inventoryTotals}
            serverImpact={serverImpact}
            sourceDocId={sourceDocId}
            ruleExplanation={ruleExplanation}
            branchLabel={branchLabel}
            dimensionLabel={dimensionLabel}
            kind="inventory"
          />
          {withholdingInfo && withholdingInfo.amount > 0 && (
            <ExpectedWithholdingSection info={withholdingInfo} />
          )}
          <div className="rounded border border-gray-200 bg-gray-50 px-3 py-2">
            <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-700">Combined Journal Reconciliation</div>
            <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
              {[
                ['Total Debit', fmt(totalDebit)],
                ['Total Credit', fmt(totalCredit)],
                ['Difference', fmt(combinedDifference)],
                ['Status', balanced && !missingAccount ? (serverImpact?.mode === 'posted' ? 'Posted Balanced' : 'Preview Balanced') : 'Unbalanced'],
              ].map(([label, value]) => (
                <div key={label}>
                  <div className="text-[10px] font-medium uppercase tracking-wide text-gray-500">{label}</div>
                  <div className={`mt-0.5 text-sm ${label === 'Status' ? 'font-semibold' : 'font-mono tabular-nums'} text-gray-900`}>{value}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      ) : !error && rows.length > 0 ? (
        <div className="overflow-x-auto">
          <table className={ERP_TABLE}>
            <thead className={ERP_THEAD}>
              <tr>
                {['Line', 'Account Code', 'Account Name', 'Debit', 'Credit', 'Branch', 'Department', 'Cost Center', 'Memo', 'Journal Entry', 'Posting Rule', 'Posting Status'].map(header => (
                  <th key={header} className={`${ERP_TH} ${['Debit', 'Credit'].includes(header) ? 'text-right' : 'text-left'}`}>
                    {header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map(row => (
                <tr key={row.key} className={row.missingAccount ? 'bg-amber-50/40' : ''}>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.lineNumber ?? '—'}</td>
                  <td className={`${ERP_TD} text-gray-900 whitespace-nowrap`}>
                    {row.accountId ? (
                      <Link
                        to={`/account-detail-ledger?accountId=${row.accountId}${serverImpact?.journal_entry_id ? `&jeId=${serverImpact.journal_entry_id}` : ''}`}
                        className="font-medium text-blue-700 hover:text-blue-900 hover:underline"
                      >
                        {row.accountCode}
                      </Link>
                    ) : row.accountCode}
                  </td>
                  <td className={`${ERP_TD} whitespace-nowrap`}>{row.accountName || '—'}</td>
                  <td className={ERP_TD_NUM}>{row.debit ? fmt(row.debit) : '-'}</td>
                  <td className={ERP_TD_NUM}>{row.credit ? fmt(row.credit) : '-'}</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{branchLabel(row)}</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{dimensionLabel(row.departmentId)}</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{dimensionLabel(row.costCenterId)}</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.description || '—'}</td>
                  <td className={`${ERP_TD} whitespace-nowrap`}>
                    {serverImpact?.journal_entry_id
                      ? <Link to={`/journal-entries?jeId=${serverImpact.journal_entry_id}`} className="text-blue-700 hover:underline">{serverImpact.je_number || 'Open JE'}</Link>
                      : <span className="text-gray-500">{sourceDocId ? 'Preview' : 'Draft Preview'}</span>}
                  </td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.accountSource}</td>
                  <td className={`${ERP_TD} whitespace-nowrap`}>
                    <div className="flex flex-col gap-1">
                      <span className="text-gray-500">{sourceDocId ? (serverImpact?.mode === 'posted' ? 'Posted' : 'Preview') : 'Draft Preview'}</span>
                      <details className="text-[11px] text-gray-500">
                        <summary className="cursor-pointer text-gray-500 hover:text-gray-800">Details</summary>
                        <div className="mt-1 space-y-0.5 rounded bg-gray-50 p-2">
                          <div><span className="font-medium">Posting Rule:</span> {ruleExplanation || 'Not recorded'}</div>
                          <div><span className="font-medium">Created By Rule:</span> {row.technicalSource || 'Not recorded'}</div>
                          <div><span className="font-medium">Configuration Source:</span> {row.technicalSource || 'Not recorded'}</div>
                          <div><span className="font-medium">Branch:</span> {branchLabel(row)}</div>
                          <div><span className="font-medium">Department:</span> {dimensionLabel(row.departmentId)}</div>
                          <div><span className="font-medium">Cost Center:</span> {dimensionLabel(row.costCenterId)}</div>
                        </div>
                      </details>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot className={ERP_TOTAL_ROW}>
              <tr>
                <td colSpan={3} className="px-2 py-1.5 text-right font-semibold text-gray-700">Totals</td>
                <td className="px-2 py-1.5 text-right font-mono tabular-nums font-semibold text-gray-900">{fmt(totalDebit)}</td>
                <td className="px-2 py-1.5 text-right font-mono tabular-nums font-semibold text-gray-900">{fmt(totalCredit)}</td>
                <td colSpan={7} />
              </tr>
            </tfoot>
          </table>
        </div>
      ) : null}
    </div>
  )
}

type ImpactSectionProps = {
  title: string
  subtitle: string
  rows: DisplayRow[]
  totals: { debit: number; credit: number }
  serverImpact: ServerGLImpact | null
  sourceDocId?: string | null
  ruleExplanation?: string | null
  branchLabel: (row: DisplayRow) => string
  dimensionLabel: (value: string | null) => string
  kind: 'commercial' | 'inventory'
}

function AccountingImpactSection({
  title,
  subtitle,
  rows,
  totals,
  serverImpact,
  sourceDocId,
  ruleExplanation,
  branchLabel,
  dimensionLabel,
  kind,
}: ImpactSectionProps) {
  const isInventory = kind === 'inventory'
  const emptyText = isInventory
    ? 'No inventory or cost-of-goods-sold impact applies to this invoice.'
    : 'No commercial accounting preview is available for this invoice.'

  return (
    <section className="overflow-hidden rounded border border-gray-200 bg-white">
      <div className="border-b border-gray-200 bg-gray-50 px-3 py-2">
        <div className="text-xs font-semibold uppercase tracking-wide text-gray-800">{title}</div>
        <div className="mt-0.5 text-xs text-gray-500">{subtitle}</div>
      </div>
      {rows.length === 0 ? (
        <div className={ERP_EMPTY_CELL}>{emptyText}</div>
      ) : (
        <div className="overflow-x-auto">
          <table className={ERP_TABLE}>
            <thead className={ERP_THEAD}>
              <tr>
                {(isInventory
                  ? ['Line', 'Source Item', 'Item Code', 'Warehouse', 'Account Code', 'Account Name', 'Debit', 'Credit', 'Quantity', 'Unit Cost', 'Total Cost', 'Valuation Method', 'Branch', 'Department', 'Cost Center', 'Memo', 'Posting Rule', 'Posting Status', 'Inventory Movement', 'Journal Entry']
                  : ['Line', 'Source', 'Account Code', 'Account Name', 'Debit', 'Credit', 'Branch', 'Department', 'Cost Center', 'Customer', 'Memo', 'Posting Rule', 'Posting Status', 'Journal Entry']
                ).map(header => (
                  <th key={header} className={`${ERP_TH} ${['Debit', 'Credit', 'Quantity', 'Unit Cost', 'Total Cost'].includes(header) ? 'text-right' : 'text-left'}`}>
                    {header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map(row => (
                <tr key={row.key} className={row.missingAccount ? 'bg-amber-50/40' : ''}>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.lineNumber ?? '-'}</td>
                  {isInventory ? (
                    <>
                      <td className={`${ERP_TD} text-gray-700 whitespace-nowrap`}>{row.sourceLabel || 'Invoice Line'}</td>
                      <td className={`${ERP_TD} text-gray-700 whitespace-nowrap`}>{row.itemCode || '-'}</td>
                      <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.warehouseCode || (row.warehouseId ? 'Assigned' : 'Not assigned')}</td>
                    </>
                  ) : (
                    <td className={`${ERP_TD} text-gray-700 whitespace-nowrap`}>{row.sourceLabel || row.accountSource}</td>
                  )}
                  <td className={`${ERP_TD} text-gray-900 whitespace-nowrap`}>
                    {row.accountId ? (
                      <Link
                        to={`/account-detail-ledger?accountId=${row.accountId}${serverImpact?.journal_entry_id ? `&jeId=${serverImpact.journal_entry_id}` : ''}`}
                        className="font-medium text-blue-700 hover:text-blue-900 hover:underline"
                      >
                        {row.accountCode}
                      </Link>
                    ) : row.accountCode}
                  </td>
                  <td className={`${ERP_TD} whitespace-nowrap`}>{row.accountName || '-'}</td>
                  <td className={ERP_TD_NUM}>{row.debit ? fmt(row.debit) : '-'}</td>
                  <td className={ERP_TD_NUM}>{row.credit ? fmt(row.credit) : '-'}</td>
                  {isInventory && (
                    <>
                      <td className={ERP_TD_NUM}>{row.quantity == null ? '-' : fmt(row.quantity)}</td>
                      <td className={ERP_TD_NUM}>{row.unitCost == null ? '-' : fmt(row.unitCost)}</td>
                      <td className={ERP_TD_NUM}>{row.totalCost == null ? '-' : fmt(row.totalCost)}</td>
                      <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.valuationMethod || '-'}</td>
                    </>
                  )}
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{branchLabel(row)}</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{dimensionLabel(row.departmentId)}</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{dimensionLabel(row.costCenterId)}</td>
                  {!isInventory && <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>Invoice customer</td>}
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.description || '-'}</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.accountSource}</td>
                  <td className={`${ERP_TD} whitespace-nowrap`}>
                    <details className="text-[11px] text-gray-500">
                      <summary className="cursor-pointer text-gray-500 hover:text-gray-800">{sourceDocId ? (serverImpact?.mode === 'posted' ? 'Posted' : 'Preview') : 'Draft Preview'}</summary>
                      <div className="mt-1 space-y-0.5 rounded bg-gray-50 p-2">
                        <div><span className="font-medium">Posting Rule:</span> {ruleExplanation || 'Not recorded'}</div>
                        <div><span className="font-medium">Created By Rule:</span> {row.technicalSource || 'Not recorded'}</div>
                        <div><span className="font-medium">Accounting Effect:</span> {row.accountingEffect}</div>
                        <div><span className="font-medium">Source Type:</span> {row.sourceLabel}</div>
                      </div>
                    </details>
                  </td>
                  {isInventory && (
                    <td className={`${ERP_TD} whitespace-nowrap`}>
                      {row.inventoryMovementId ? (
                        <Link to={`/inventory-movements?movementId=${row.inventoryMovementId}`} className="text-blue-700 hover:underline">Open movement</Link>
                      ) : <span className="text-gray-500">{sourceDocId ? 'Preview' : 'Draft Preview'}</span>}
                    </td>
                  )}
                  <td className={`${ERP_TD} whitespace-nowrap`}>
                    {serverImpact?.journal_entry_id
                      ? <Link to={`/journal-entries?jeId=${serverImpact.journal_entry_id}`} className="text-blue-700 hover:underline">{serverImpact.je_number || 'Open JE'}</Link>
                      : <span className="text-gray-500">{sourceDocId ? 'Preview' : 'Draft Preview'}</span>}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot className={ERP_TOTAL_ROW}>
              <tr>
                <td colSpan={isInventory ? 6 : 4} className="px-2 py-1.5 text-right font-semibold text-gray-700">Section Total</td>
                <td className="px-2 py-1.5 text-right font-mono tabular-nums font-semibold text-gray-900">{fmt(totals.debit)}</td>
                <td className="px-2 py-1.5 text-right font-mono tabular-nums font-semibold text-gray-900">{fmt(totals.credit)}</td>
                <td colSpan={isInventory ? 12 : 8} />
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </section>
  )
}

function ExpectedWithholdingSection({ info }: { info: WithholdingInfo }) {
  return (
    <section className="overflow-hidden rounded border border-gray-200 bg-white">
      <div className="border-b border-gray-200 bg-gray-50 px-3 py-2">
        <div className="text-xs font-semibold uppercase tracking-wide text-gray-800">Expected Withholding — Informational</div>
        <div className="mt-0.5 text-xs text-gray-500">Informational only — not yet part of the posted journal entry.</div>
      </div>
      <div className="overflow-x-auto">
        <table className={ERP_TABLE}>
          <thead className={ERP_THEAD}>
            <tr>
              {['Withholding Type', 'ATC', 'Rate', 'Withholding Base', 'Expected Withholding Amount', 'Expected Net Collectible', 'Recognition Event', 'Current Status'].map((header, index) => (
                <th key={header} className={`${ERP_TH} ${index >= 2 && index <= 5 ? 'text-right' : 'text-left'}`}>{header}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            <tr>
              <td className={ERP_TD}>{info.withholdingType}</td>
              <td className={ERP_TD}>{info.atc || 'Not configured'}</td>
              <td className={ERP_TD_NUM}>{info.rate == null ? '-' : `${fmt(info.rate)}%`}</td>
              <td className={ERP_TD_NUM}>{fmt(info.base)}</td>
              <td className={ERP_TD_NUM}>{fmt(info.amount)}</td>
              <td className={ERP_TD_NUM}>{fmt(info.expectedNetCollectible)}</td>
              <td className={ERP_TD}>{info.recognitionEvent}</td>
              <td className={ERP_TD}>{info.status}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  )
}
