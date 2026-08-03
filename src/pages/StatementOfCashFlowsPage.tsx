import { useState } from 'react'
import { useAppCtx } from '@/lib/context'
import { FinancialStatementPage } from '@/components/FinancialStatement'

const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function StatementOfCashFlowsPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())

  return (
    <FinancialStatementPage
      title="Statement of Cash Flows"
      subtitle="Indirect method, by account movement"
      companyId={companyId}
      statement="cash_flow"
      periodStart={dateFrom} periodEnd={dateTo}
      onPeriodStart={setDateFrom} onPeriodEnd={setDateTo}
      columns={[{ key: 'movement_amount', label: 'For the period' }]}
      emptyMessage="No governed cash flow lines are mapped for this company."
      footnote="Every non-cash account explains the movement in cash: an increase in an asset consumes cash, an increase in a liability or in equity provides it. The three activity totals must equal the movement in Cash and Cash Equivalents — that agreement is the statement's own proof."
    />
  )
}
