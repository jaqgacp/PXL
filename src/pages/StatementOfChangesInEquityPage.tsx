import { useState } from 'react'
import { useAppCtx } from '@/lib/context'
import { FinancialStatementPage } from '@/components/FinancialStatement'

const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function StatementOfChangesInEquityPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())

  return (
    <FinancialStatementPage
      title="Statement of Changes in Equity"
      subtitle="Opening balance, movement for the period, closing balance"
      companyId={companyId}
      statement="equity_statement"
      periodStart={dateFrom} periodEnd={dateTo}
      onPeriodStart={setDateFrom} onPeriodEnd={setDateTo}
      columns={[
        { key: 'opening_amount', label: 'Opening' },
        { key: 'movement_amount', label: 'Movement' },
        { key: 'closing_amount', label: 'Closing' },
      ]}
      emptyMessage="No governed equity lines are mapped for this company."
      footnote="Closing equity here must agree with the EQUITY total on the Statement of Financial Position for the same date."
    />
  )
}
