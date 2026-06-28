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

export function AppContextProvider({ children }: { children: React.ReactNode }) {
  const [companyId, setCompanyId] = useState('')
  const [branchId, setBranchId] = useState('')
  const [periodId, setPeriodId] = useState('')
  return (
    <AppContext.Provider value={{ companyId, branchId, periodId, setCompanyId, setBranchId, setPeriodId }}>
      {children}
    </AppContext.Provider>
  )
}
