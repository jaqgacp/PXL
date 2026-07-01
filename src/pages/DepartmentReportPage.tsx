import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Department = { id: string; department_code: string; department_name: string; branch_id: string | null }
type Employee = { department_id: string | null; separation_date: string | null }
type FixedAsset = { department_id: string | null; acquisition_cost: number; status: string }

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

export default function DepartmentReportPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<{ dept: Department; employeeCount: number; assetCount: number; assetValue: number }[]>([])
  const [loading, setLoading] = useState(false)

  const run = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    const [{ data: depts }, { data: emps }, { data: assets }] = await Promise.all([
      supabase.from('departments').select('id,department_code,department_name,branch_id').eq('company_id', companyId).order('department_name'),
      supabase.from('employees').select('department_id,separation_date').eq('company_id', companyId),
      supabase.from('fixed_assets').select('department_id,acquisition_cost,status').eq('company_id', companyId),
    ])

    const empList = (emps as Employee[]) || []
    const assetList = (assets as FixedAsset[]) || []

    const result = ((depts as Department[]) || []).map(d => {
      const employeeCount = empList.filter(e => e.department_id === d.id && !e.separation_date).length
      const deptAssets = assetList.filter(a => a.department_id === d.id && a.status !== 'disposed')
      return { dept: d, employeeCount, assetCount: deptAssets.length, assetValue: deptAssets.reduce((s, a) => s + Number(a.acquisition_cost), 0) }
    })

    setRows(result)
    setLoading(false)
  }, [companyId])

  useEffect(() => { if (companyId) run() }, [run, companyId])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Department Report</h1>
        <p className="text-sm text-gray-500 mt-0.5">Active headcount &amp; fixed asset allocation by department</p>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Department</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Active Employees</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Assets Assigned</th>
              <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset Value</th>
            </tr></thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={4} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No departments configured.'}</td></tr>
              ) : rows.map(r => (
                <tr key={r.dept.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-700">{r.dept.department_code} — {r.dept.department_name}</td>
                  <td className="px-4 py-2 text-right text-gray-700">{r.employeeCount}</td>
                  <td className="px-4 py-2 text-right text-gray-700">{r.assetCount}</td>
                  <td className="px-4 py-2 text-right font-mono tabular-nums text-gray-900 font-semibold">{fmt(r.assetValue)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
