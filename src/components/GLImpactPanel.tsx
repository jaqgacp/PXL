import { useEffect, useMemo, useState } from 'react'
import { supabase } from '@/lib/supabase'

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

type Account = { id: string; account_code: string; account_name: string }
type JournalEntry = {
  id: string
  je_number: string
  je_date: string
  status: string
  total_debit: number
  total_credit: number
}
type JournalLine = {
  id: string
  line_number: number
  description: string | null
  debit_amount: number
  credit_amount: number
  chart_of_accounts: Account | null
}

type Props = {
  companyId?: string | null
  sourceDocType: string
  sourceDocId?: string | null
  previewRows: GLImpactRow[]
  title?: string
}

const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export function GLImpactPanel({ companyId, sourceDocType, sourceDocId, previewRows, title = 'GL Impact' }: Props) {
  const [accounts, setAccounts] = useState<Record<string, Account>>({})
  const [config, setConfig] = useState<Record<string, string | null>>({})
  const [postedJe, setPostedJe] = useState<JournalEntry | null>(null)
  const [postedLines, setPostedLines] = useState<JournalLine[]>([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (!companyId) return
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
    load()
    return () => { alive = false }
  }, [companyId])

  useEffect(() => {
    if (!companyId || !sourceDocId) {
      setPostedJe(null)
      setPostedLines([])
      setLoading(false)
      return
    }
    let alive = true
    const load = async () => {
      setLoading(true)
      const { data: jeData } = await supabase.from('journal_entries')
        .select('id,je_number,je_date,status,total_debit,total_credit')
        .eq('company_id', companyId)
        .eq('reference_doc_type', sourceDocType)
        .eq('reference_doc_id', sourceDocId)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (!alive) return
      setPostedJe((jeData as JournalEntry) || null)

      if (jeData?.id) {
        const { data: lineData } = await supabase.from('journal_entry_lines')
          .select('id,line_number,description,debit_amount,credit_amount,chart_of_accounts(account_code,account_name)')
          .eq('je_id', jeData.id)
          .order('line_number')
        if (!alive) return
        setPostedLines((lineData as any as JournalLine[]) || [])
      } else {
        setPostedLines([])
      }
      setLoading(false)
    }
    load()
    return () => { alive = false }
  }, [companyId, sourceDocType, sourceDocId])

  const rows = useMemo(() => {
    if (postedJe) {
      return postedLines.map(line => ({
        accountLabel: line.chart_of_accounts
          ? `${line.chart_of_accounts.account_code} - ${line.chart_of_accounts.account_name}`
          : 'Unmapped account',
        description: line.description || '',
        debit: Number(line.debit_amount),
        credit: Number(line.credit_amount),
        missingAccount: !line.chart_of_accounts,
      }))
    }

    return previewRows
      .filter(row => Math.abs(row.debit) > 0.005 || Math.abs(row.credit) > 0.005)
      .map(row => {
        const accountId = row.accountId || (row.configKey ? config[row.configKey] : null)
        const account = accountId ? accounts[accountId] : null
        return {
          accountLabel: account
            ? `${account.account_code} - ${account.account_name}`
            : row.accountLabel || (row.configKey ? `Missing ${row.configKey.replace(/_/g, ' ')}` : 'Missing account'),
          description: row.description,
          debit: row.debit,
          credit: row.credit,
          missingAccount: !accountId && !row.accountLabel,
        }
      })
  }, [accounts, config, postedJe, postedLines, previewRows])

  const totalDebit = rows.reduce((sum, row) => sum + row.debit, 0)
  const totalCredit = rows.reduce((sum, row) => sum + row.credit, 0)
  const balanced = Math.abs(totalDebit - totalCredit) <= 0.01
  const missingAccount = rows.some(row => row.missingAccount)
  const modeLabel = postedJe ? `Posted JE ${postedJe.je_number}` : 'Preview before posting'

  return (
    <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
      <div className="px-4 py-2.5 border-b border-gray-100 flex items-center justify-between gap-3">
        <div>
          <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400">{title}</div>
          <div className="text-xs text-gray-500 mt-0.5">{loading ? 'Loading posted journal entry...' : modeLabel}</div>
        </div>
        <div className={`text-xs font-medium ${balanced && !missingAccount ? 'text-green-700' : 'text-amber-700'}`}>
          {balanced ? 'Balanced' : `Out by ${fmt(totalDebit - totalCredit)}`}
        </div>
      </div>

      {rows.length === 0 ? (
        <div className="px-4 py-6 text-sm text-gray-400">Enter transaction lines to preview accounting impact.</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['Account', 'Description', 'Debit', 'Credit'].map(header => (
                  <th key={header} className={`px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 ${['Debit', 'Credit'].includes(header) ? 'text-right' : 'text-left'}`}>
                    {header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map((row, index) => (
                <tr key={`${row.description}-${index}`} className={row.missingAccount ? 'bg-amber-50/40' : ''}>
                  <td className="px-3 py-2 text-gray-900">{row.accountLabel}</td>
                  <td className="px-3 py-2 text-gray-500">{row.description}</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{row.debit ? fmt(row.debit) : '-'}</td>
                  <td className="px-3 py-2 text-right font-mono tabular-nums text-gray-700">{row.credit ? fmt(row.credit) : '-'}</td>
                </tr>
              ))}
            </tbody>
            <tfoot className="bg-gray-50 border-t border-gray-200">
              <tr>
                <td colSpan={2} className="px-3 py-2 text-right font-semibold text-gray-700">Totals</td>
                <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(totalDebit)}</td>
                <td className="px-3 py-2 text-right font-mono tabular-nums font-bold text-gray-900">{fmt(totalCredit)}</td>
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </div>
  )
}
