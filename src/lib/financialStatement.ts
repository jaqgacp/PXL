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

/**
 * Comparative reporting.
 *
 * The prior column is not "last year" as the browser understands it. It is the
 * prior comparable period resolved from the company's own fiscal calendar by
 * `fn_resolve_comparative_period`, which also says — in data, not by throwing —
 * when there isn't one, because a company in its first year legitimately has no
 * comparative and the screen has to say so rather than show zeroes.
 */
export type ComparativePeriod = {
  available: boolean
  reason?: string
  basis?: string
  period_start?: string
  period_end?: string
  fiscal_year_name?: string
  fiscal_year_status?: string
  prior_period_start?: string
  prior_period_end?: string
  prior_fiscal_year_name?: string
  prior_fiscal_year_status?: string
  prior_year_closed?: boolean
  prior_has_activity?: boolean
}

export type ComparativeFsLine = {
  line_code: string
  line_label: string
  parent_code: string | null
  depth: number
  line_role: string
  is_subtotal: boolean
  display_order: number
  comparison_basis: 'closing' | 'movement'
  current_amount: number
  prior_amount: number
  variance_amount: number
  variance_percent: number | null
}

export type FsLineAccount = {
  account_id: string
  account_code: string
  account_name: string
  account_type: string
  comparison_basis: 'closing' | 'movement'
  current_amount: number
  prior_amount: number
  variance_amount: number
  variance_percent: number | null
}

export type FsNoteItem = {
  note_code: string
  note_title: string
  note_order: number
  item_order: number
  item_label: string
  item_value: string
  item_source: string
  is_configured: boolean
}

const num = (v: unknown) => Number(v ?? 0)
const numOrNull = (v: unknown) => (v === null || v === undefined ? null : Number(v))

export function useComparativePeriod(
  companyId: string | null | undefined,
  periodStart: string,
  periodEnd: string,
) {
  const [period, setPeriod] = useState<ComparativePeriod | null>(null)
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) { setPeriod(null); return }
    setLoading(true)
    const { data, error } = await supabase.rpc('fn_resolve_comparative_period', {
      p_company_id: companyId, p_period_start: periodStart, p_period_end: periodEnd,
    })
    setPeriod(error
      ? { available: false, reason: error.message }
      : (data as unknown as ComparativePeriod))
    setLoading(false)
  }, [companyId, periodStart, periodEnd])

  useEffect(() => { void run() }, [run])
  return { period, loading }
}

export function useComparativeFinancialStatement(
  companyId: string | null | undefined,
  statement: FsStatement,
  periodStart: string,
  periodEnd: string,
  priorStart: string | null | undefined,
  priorEnd: string | null | undefined,
) {
  const [lines, setLines] = useState<ComparativeFsLine[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const run = useCallback(async () => {
    if (!companyId || !priorStart || !priorEnd) { setLines([]); return }
    setLoading(true); setError('')
    const { data, error: e } = await supabase.rpc('fn_comparative_financial_statement_report', {
      p_company_id: companyId,
      p_statement: statement,
      p_period_start: periodStart,
      p_period_end: periodEnd,
      p_prior_start: priorStart,
      p_prior_end: priorEnd,
    })
    if (e) setError(e.message)
    setLines(((data || []) as ComparativeFsLine[]).map(l => ({
      ...l,
      current_amount: num(l.current_amount),
      prior_amount: num(l.prior_amount),
      variance_amount: num(l.variance_amount),
      variance_percent: numOrNull(l.variance_percent),
    })))
    setLoading(false)
  }, [companyId, statement, periodStart, periodEnd, priorStart, priorEnd])

  useEffect(() => { void run() }, [run])
  return { lines, loading, error, reload: run }
}

/** The accounts behind one governed line — the statement's own supporting schedule. */
export function useFsLineAccounts(
  companyId: string | null | undefined,
  statement: FsStatement,
  lineCode: string | null,
  periodStart: string,
  periodEnd: string,
  priorStart?: string | null,
  priorEnd?: string | null,
) {
  const [accounts, setAccounts] = useState<FsLineAccount[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const run = useCallback(async () => {
    if (!companyId || !lineCode) { setAccounts([]); return }
    setLoading(true); setError('')
    const { data, error: e } = await supabase.rpc('fn_financial_statement_line_accounts', {
      p_company_id: companyId,
      p_statement: statement,
      p_line_code: lineCode,
      p_period_start: periodStart,
      p_period_end: periodEnd,
      p_prior_start: priorStart ?? undefined,
      p_prior_end: priorEnd ?? undefined,
    })
    if (e) setError(e.message)
    setAccounts(((data || []) as FsLineAccount[]).map(a => ({
      ...a,
      current_amount: num(a.current_amount),
      prior_amount: num(a.prior_amount),
      variance_amount: num(a.variance_amount),
      variance_percent: numOrNull(a.variance_percent),
    })))
    setLoading(false)
  }, [companyId, statement, lineCode, periodStart, periodEnd, priorStart, priorEnd])

  useEffect(() => { void run() }, [run])
  return { accounts, loading, error }
}

export function useFinancialStatementNotes(
  companyId: string | null | undefined,
  periodStart: string,
  periodEnd: string,
  priorStart?: string | null,
  priorEnd?: string | null,
) {
  const [notes, setNotes] = useState<FsNoteItem[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const run = useCallback(async () => {
    if (!companyId) { setNotes([]); return }
    setLoading(true); setError('')
    const { data, error: e } = await supabase.rpc('fn_financial_statement_notes', {
      p_company_id: companyId,
      p_period_start: periodStart,
      p_period_end: periodEnd,
      p_prior_start: priorStart ?? undefined,
      p_prior_end: priorEnd ?? undefined,
    })
    if (e) setError(e.message)
    setNotes((data || []) as FsNoteItem[])
    setLoading(false)
  }, [companyId, periodStart, periodEnd, priorStart, priorEnd])

  useEffect(() => { void run() }, [run])
  return { notes, loading, error }
}

