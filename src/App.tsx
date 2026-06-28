import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import LoginPage from '@/pages/LoginPage'
import type { Session } from '@supabase/supabase-js'

export default function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session)
      setLoading(false)
    })
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session)
    })
    return () => subscription.unsubscribe()
  }, [])

  if (loading) return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <p className="text-sm text-gray-500">Loading...</p>
    </div>
  )

  if (!session) return <LoginPage />

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <div className="text-center">
        <h1 className="text-2xl font-bold text-gray-900">PXL</h1>
        <p className="text-sm text-gray-500 mt-1">Welcome, {session.user.email}</p>
        <button onClick={() => supabase.auth.signOut()}
          className="mt-4 text-sm text-gray-500 underline">
          Sign out
        </button>
      </div>
    </div>
  )
}