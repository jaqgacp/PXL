import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { accountingTracePath } from '@/lib/accountingTrace'
import { reportTracePath } from '@/lib/accountingTrace'
import type { AccountingTraceTarget, ReportTraceTarget } from '@/lib/accountingTrace'

type AccountingTraceLinkProps = AccountingTraceTarget & {
  children: ReactNode
  className?: string
  title?: string
}

type ReportTraceLinkProps = ReportTraceTarget & {
  children: ReactNode
  className?: string
  title?: string
}

export function AccountingTraceLink({
  sourceType,
  sourceId,
  journalEntryId,
  children,
  className = 'text-blue-700 hover:text-blue-900',
  title,
}: AccountingTraceLinkProps) {
  if (!journalEntryId && !(sourceType && sourceId)) return <>{children}</>

  return (
    <Link
      to={accountingTracePath({ sourceType, sourceId, journalEntryId })}
      className={className}
      title={title}
    >
      {children}
    </Link>
  )
}

export function ReportTraceLink({
  companyId,
  reportFamily,
  filters,
  children,
  className = 'text-blue-700 hover:text-blue-900',
  title,
}: ReportTraceLinkProps) {
  if (!companyId) return <>{children}</>
  return <Link to={reportTracePath({ companyId, reportFamily, filters })} className={className} title={title}>{children}</Link>
}
