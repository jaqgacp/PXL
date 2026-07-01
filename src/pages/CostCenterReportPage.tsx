import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Row = {
  id: string
  cost_center_code: string
  cost_center_name: string
  cost_center_type: string
  branches: { branch_name: string } | null
  departments: { department_name: string } | null
}

const TYPE_LABELS: Record<string, string> = { revenue_center: 'Revenue Center', cost_center: 'Cost Center', profit_center: 'Profit Center', investment_center: 'Investment Center' }

export default function CostCenterReportPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('cost_centers')
      .select('id,cost_center_code,cost_center_name,cost_center_type,branches(branch_name),departments(department_name)')
      .eq('company_id', companyId).order('cost_center_code')
    setRows((data as unknown as Row[]) || [])
    setLoading(false)
  }, [companyId])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Cost Center Report</h1>
        <p className="text-sm text-gray-500 mt-0.5">Cost center directory by branch &amp; department</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Code</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Name</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Branch</th>
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Department</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No cost centers configured.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700 font-mono">{r.cost_center_code}</td>
                  <td className="px-4 py-2 text-gray-700">{r.cost_center_name}</td>
                  <td className="px-4 py-2 text-gray-500">{TYPE_LABELS[r.cost_center_type] || r.cost_center_type}</td>
                  <td className="px-4 py-2 text-gray-500">{r.branches?.branch_name || '—'}</td>
                  <td className="px-4 py-2 text-gray-500">{r.departments?.department_name || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
