import { createClient } from '@supabase/supabase-js'
import type { Database } from './database.types'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

const missing = [
  !supabaseUrl && 'VITE_SUPABASE_URL',
  !supabaseAnonKey && 'VITE_SUPABASE_ANON_KEY',
].filter(Boolean)

if (missing.length > 0) {
  throw new Error(
    `Missing required environment variable(s): ${missing.join(', ')}. ` +
    'Set them in your .env file (VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY).'
  )
}

// A root-relative value (for example `/supabase`) is resolved against the page
// origin. This lets the dev server proxy Supabase on its own origin, which is
// what makes the app work in a remote workspace: the browser cannot reach the
// container's 127.0.0.1:54321, and proxying avoids forwarding a second port,
// widening the CSP, or making an API endpoint publicly visible. Absolute URLs
// are passed through untouched, so hosted behaviour is unchanged.
const resolvedUrl = supabaseUrl!.startsWith('/')
  ? `${window.location.origin}${supabaseUrl!.replace(/\/$/, '')}`
  : supabaseUrl!

export const supabase = createClient<Database>(resolvedUrl, supabaseAnonKey!)
