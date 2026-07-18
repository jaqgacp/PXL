import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'

/** Resolve a branch context to an operator-facing label without changing its stored ID. */
export function useBranchLabel(branchId?: string | null) {
  const [label, setLabel] = useState(branchId ? 'Loading branch…' : 'Company level')

  useEffect(() => {
    let active = true
    if (!branchId) {
      setLabel('Company level')
      return () => { active = false }
    }

    setLabel('Loading branch…')
    supabase
      .from('branches')
      .select('branch_code,branch_name')
      .eq('id', branchId)
      .maybeSingle()
      .then(({ data }) => {
        if (!active) return
        setLabel(data ? `${data.branch_code} — ${data.branch_name}` : 'Assigned branch')
      })

    return () => { active = false }
  }, [branchId])

  return label
}
