import { useState } from 'react'
import { useAppCtx } from '@/lib/context'
import { FinancialStatementPage } from '@/components/FinancialStatement'

const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function BalanceSheetPage() {
  const { companyId } = useAppCtx()
  const [periodStart, setPeriodStart] = useState(firstOfYear())
  const [asOfDate, setAsOfDate] = useState(today())

  return (
    <FinancialStatementPage
      title="Balance Sheet"
      subtitle="Statement of Financial Position"
      companyId={companyId}
      statement="balance_sheet"
      periodStart={periodStart} periodEnd={asOfDate}
      onPeriodStart={setPeriodStart} onPeriodEnd={setAsOfDate}
      periodStartLabel="Year begins" periodEndLabel="as of"
      columns={[{ key: 'closing_amount', label: 'As of date' }]}
      emptyMessage="No governed statement lines are mapped for this company."
      footnote="Current Year Earnings is computed from the income-statement accounts because profit is not posted to equity until the year is closed; without it a mid-year position would not balance. ASSETS must equal LIABILITIES plus EQUITY."
    />
  )
}
