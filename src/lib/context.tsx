import { createContext, useContext, useState } from 'react'

type AppCtx = {
  companyId: string
  branchId: string
  periodId: string
  setCompanyId: (id: string) => void
  setBranchId: (id: string) => void
  setPeriodId: (id: string) => void
}

const AppContext = createContext<AppCtx>({
  companyId: '', branchId: '', periodId: '',
  setCompanyId: () => {}, setBranchId: () => {}, setPeriodId: () => {},
})

export const useAppCtx = () => useContext(AppContext)

// Selections survive a refresh; restored IDs are validated against the
// RLS-scoped lists in ContextSelectors, which clears anything no longer
// visible to the signed-in user.
const KEYS = { company: 'pxl.ctx.companyId', branch: 'pxl.ctx.branchId', period: 'pxl.ctx.periodId' }

function readStored(key: string): string {
  try { return localStorage.getItem(key) || '' } catch { return '' }
}

function store(key: string, value: string) {
  try {
    if (value) localStorage.setItem(key, value)
    else localStorage.removeItem(key)
  } catch { /* storage unavailable */ }
}

export function AppContextProvider({ children }: { children: React.ReactNode }) {
  const [companyId, setCompanyIdState] = useState(() => readStored(KEYS.company))
  const [branchId, setBranchIdState] = useState(() => readStored(KEYS.branch))
  const [periodId, setPeriodIdState] = useState(() => readStored(KEYS.period))

  const setCompanyId = (id: string) => { store(KEYS.company, id); setCompanyIdState(id) }
  const setBranchId = (id: string) => { store(KEYS.branch, id); setBranchIdState(id) }
  const setPeriodId = (id: string) => { store(KEYS.period, id); setPeriodIdState(id) }

  return (
    <AppContext.Provider value={{ companyId, branchId, periodId, setCompanyId, setBranchId, setPeriodId }}>
      {children}
    </AppContext.Provider>
  )
}
