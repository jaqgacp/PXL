import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { GitBranch, RefreshCw } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { ErpSectionHeader, ERP_EMPTY_CELL, ERP_TABLE, ERP_THEAD, ERP_TH, ERP_TD, ERP_TD_NUM, ERP_TOTAL_ROW } from '@/components/document/ErpSection'

type ConfigAccountKey =
  | 'ar_account_id'
  | 'ap_account_id'
  | 'vat_payable_account_id'
  | 'input_vat_account_id'
  | 'ewt_withheld_account_id'
  | 'ewt_payable_account_id'
  | 'default_cash_account_id'

export type GLImpactRow = {
  accountId?: string | null
  configKey?: ConfigAccountKey
  accountLabel?: string
  description: string
  debit: number
  credit: number
}

export type ServerGLImpactLine = {
  line_number: number
  account_id: string
  account_code: string
  account_name: string
  account_source: string
  description: string | null
  debit: number
  credit: number
  branch_id: string | null
  department_id: string | null
  cost_center_id: string | null
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
  accountId: string | null
  accountCode: string
  accountName: string
  accountSource: string
  description: string
  debit: number
  credit: number
  missingAccount: boolean
  branchId: string | null
  departmentId: string | null
  costCenterId: string | null
}

type Props = {
  companyId?: string | null
  sourceDocType: string
  sourceDocId?: string | null
  postingDate?: string | null
  previewRows: GLImpactRow[]
  title?: string
}

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const tracePath = (sourceDocType: string, sourceDocId: string, journalEntryId?: string | null) => {
  const params = new URLSearchParams()
  if (journalEntryId) params.set('jeId', journalEntryId)
  else {
    params.set('sourceType', sourceDocType)
    params.set('sourceId', sourceDocId)
  }
  return `/accounting-trace?${params.toString()}`
}

export function GLImpactPanel({ companyId, sourceDocType, sourceDocId, postingDate, previewRows, title = 'GL Impact' }: Props) {
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
      return (serverImpact?.lines || []).map(line => ({
        key: `server-${line.line_number}-${line.account_id}`,
        accountId: line.account_id,
        accountCode: line.account_code,
        accountName: line.account_name,
        accountSource: line.account_source,
        description: line.description || '',
        debit: Number(line.debit),
        credit: Number(line.credit),
        missingAccount: false,
        branchId: line.branch_id,
        departmentId: line.department_id,
        costCenterId: line.cost_center_id,
      }))
    }

    return previewRows
      .filter(row => Math.abs(row.debit) > 0.005 || Math.abs(row.credit) > 0.005)
      .map((row, index) => {
        const accountId = row.accountId || (row.configKey ? config[row.configKey] : null)
        const account = accountId ? accounts[accountId] : null
        return {
          key: `client-${index}-${row.description}`,
          accountId: accountId || null,
          accountCode: account?.account_code || row.accountLabel || (row.configKey ? `Missing ${row.configKey.replace(/_/g, ' ')}` : 'Missing account'),
          accountName: account?.account_name || '',
          accountSource: row.configKey
            ? `company_accounting_config.${row.configKey}`
            : row.accountId
              ? 'document line account'
              : 'client draft estimate',
          description: row.description,
          debit: Number(row.debit),
          credit: Number(row.credit),
          missingAccount: !accountId && !row.accountLabel,
          branchId: null,
          departmentId: null,
          costCenterId: null,
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
      : 'Exact server preview'
    : 'Unsaved client estimate'
  const ruleExplanation = sourceDocId
    ? serverImpact?.rule_explanation
    : 'Estimated from the current unsaved form. Save the document to run the authoritative posting rule in rollback mode.'

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
        <ErpSectionHeader title={title} description={loading ? 'Running server preview...' : modeLabel} />
        <div className="flex items-center gap-2">
          <div className={`inline-flex items-center px-2 py-0.5 rounded text-[11px] font-medium ${balanced && !missingAccount ? 'bg-green-50 text-green-700' : 'bg-orange-50 text-orange-700'}`}>
            {balanced ? 'Balanced' : `Out by ${fmt(totalDebit - totalCredit)}`}
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

      {ruleExplanation && !loading && !error && (
        <div className="px-3 py-2 border-b border-gray-100 flex items-start gap-2 text-xs text-gray-600">
          <GitBranch className="h-3.5 w-3.5 mt-0.5 text-gray-400 shrink-0" aria-hidden="true" />
          <span>{ruleExplanation}</span>
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
          Server GL preview failed: {error}
        </div>
      )}

      {!error && !loading && rows.length === 0 ? (
        <div className={ERP_EMPTY_CELL}>
          {sourceDocId ? 'No GL lines are produced by the current posting rule.' : 'Enter transaction lines to preview accounting impact.'}
        </div>
      ) : !error && rows.length > 0 ? (
        <div className="overflow-x-auto">
          <table className={ERP_TABLE}>
            <thead className={ERP_THEAD}>
              <tr>
                {['GL Account', 'Account Name', 'Description', 'Debit', 'Credit', 'Source', 'Posting Rule', 'Cost Center', 'Department', 'Branch', 'Project', 'Created By Rule', 'Journal Link'].map(header => (
                  <th key={header} className={`${ERP_TH} ${['Debit', 'Credit'].includes(header) ? 'text-right' : 'text-left'}`}>
                    {header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map(row => (
                <tr key={row.key} className={row.missingAccount ? 'bg-amber-50/40' : ''}>
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
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.description}</td>
                  <td className={ERP_TD_NUM}>{row.debit ? fmt(row.debit) : '-'}</td>
                  <td className={ERP_TD_NUM}>{row.credit ? fmt(row.credit) : '-'}</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{sourceDocType}</td>
                  <td className="px-2 py-1.5 text-gray-500 font-mono text-[11px] whitespace-nowrap">{row.accountSource}</td>
                  <td className="px-2 py-1.5 text-gray-500 font-mono text-[11px]">{row.costCenterId || '—'}</td>
                  <td className="px-2 py-1.5 text-gray-500 font-mono text-[11px]">{row.departmentId || '—'}</td>
                  <td className="px-2 py-1.5 text-gray-500 font-mono text-[11px]">{row.branchId || serverImpact?.branch_name || '—'}</td>
                  <td className={`${ERP_TD} text-gray-400`}>—</td>
                  <td className={`${ERP_TD} text-gray-500 whitespace-nowrap`}>{row.accountSource}</td>
                  <td className={`${ERP_TD} whitespace-nowrap`}>
                    {serverImpact?.journal_entry_id
                      ? <Link to={`/journal-entries?jeId=${serverImpact.journal_entry_id}`} className="text-blue-700 hover:underline">{serverImpact.je_number || 'Open JE'}</Link>
                      : <span className="text-gray-400">Not posted</span>}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot className={ERP_TOTAL_ROW}>
              <tr>
                <td colSpan={3} className="px-2 py-1.5 text-right font-semibold text-gray-700">Totals</td>
                <td className="px-2 py-1.5 text-right font-mono tabular-nums font-semibold text-gray-900">{fmt(totalDebit)}</td>
                <td className="px-2 py-1.5 text-right font-mono tabular-nums font-semibold text-gray-900">{fmt(totalCredit)}</td>
                <td colSpan={8} />
              </tr>
            </tfoot>
          </table>
        </div>
      ) : null}
    </div>
  )
}
