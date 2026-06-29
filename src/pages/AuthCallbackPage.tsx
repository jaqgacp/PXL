import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'

export default function AuthCallbackPage() {
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    // Supabase JS automatically exchanges the OAuth code/hash from the URL on init.
    // We wait for the resulting SIGNED_IN event, then redirect to the app.
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_IN' && session) {
        navigate('/', { replace: true })
      }
    })

    // Handle the case where the session was established before this component mounted
    supabase.auth.getSession().then(({ data: { session }, error: err }) => {
      if (session) {
        navigate('/', { replace: true })
      } else if (err) {
        setError(err.message)
      }
    })

    return () => subscription.unsubscribe()
  }, [navigate])

  if (error) return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <div className="bg-white rounded-lg border border-red-200 p-8 max-w-sm w-full text-center">
        <p className="text-sm font-medium text-red-700 mb-1">Sign-in failed</p>
        <p className="text-xs text-gray-500 mb-4">{error}</p>
        <button onClick={() => navigate('/', { replace: true })}
          className="text-xs text-gray-600 hover:text-gray-900 underline">
          Back to login
        </button>
      </div>
    </div>
  )

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <p className="text-sm text-gray-500">Completing sign-in…</p>
    </div>
  )
}
