import { useState, useEffect, useCallback } from 'react'
import { supabase } from './supabase'

/**
 * The financial statement data contract.
 *
 * There is deliberately no layout for any particular statement anywhere in the
 * frontend. The line hierarchy, the labels, the order and which line is a
 * subtotal all come from `fs_structure` and `account_fs_map`, through
 * `fn_financial_statement_report`. That is what lets a company re-present its
 * accounts — a local GAAP or IFRS change — without touching a component.
 */
export type FsStatement = 'balance_sheet' | 'income_statement' | 'cash_flow' | 'equity_statement'

export type FsLine = {
  line_code: string
  line_label: string
  parent_code: string | null
  depth: number
  line_role: string
  is_subtotal: boolean
  display_order: number
  opening_amount: number
  movement_amount: number
  closing_amount: number
}

/** Which amount columns a statement reads from the one report contract. */
export type FsColumn = { key: 'opening_amount' | 'movement_amount' | 'closing_amount'; label: string }

export function useFinancialStatement(
  companyId: string | null | undefined,
  statement: FsStatement,
  periodStart: string,
  periodEnd: string,
) {
  const [lines, setLines] = useState<FsLine[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const run = useCallback(async () => {
    if (!companyId) { setLines([]); return }
    setLoading(true); setError('')
    const { data, error: e } = await supabase.rpc('fn_financial_statement_report', {
      p_company_id: companyId,
      p_statement: statement,
      p_period_start: periodStart,
      p_period_end: periodEnd,
    })
    if (e) setError(e.message)
    setLines(((data || []) as FsLine[]).map(l => ({
      ...l,
      opening_amount: Number(l.opening_amount),
      movement_amount: Number(l.movement_amount),
      closing_amount: Number(l.closing_amount),
    })))
    setLoading(false)
  }, [companyId, statement, periodStart, periodEnd])

  useEffect(() => { void run() }, [run])
  return { lines, loading, error, reload: run }
}

