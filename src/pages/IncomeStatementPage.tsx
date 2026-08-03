import { useState } from 'react'
import { useAppCtx } from '@/lib/context'
import { FinancialStatementPage } from '@/components/FinancialStatement'

const today = () => new Date().toISOString().split('T')[0]
const firstOfYear = () => new Date().getFullYear() + '-01-01'

export default function IncomeStatementPage() {
  const { companyId } = useAppCtx()
  const [dateFrom, setDateFrom] = useState(firstOfYear())
  const [dateTo, setDateTo] = useState(today())

  return (
    <FinancialStatementPage
      title="Income Statement"
      subtitle="Statement of Comprehensive Income"
      companyId={companyId}
      statement="income_statement"
      periodStart={dateFrom} periodEnd={dateTo}
      onPeriodStart={setDateFrom} onPeriodEnd={setDateTo}
      columns={[{ key: 'movement_amount', label: 'For the period' }]}
      emptyMessage="No governed income statement lines are mapped for this company."
      footnote="Revenue is positive and expenses are negative, so every subtotal is the plain sum of the lines beneath it. Presentation comes from the company's governed statement structure, not from this screen."
    />
  )
}
