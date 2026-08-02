import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const reply = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, 'Content-Type': 'application/json' },
})

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'POST') return reply(405, { error: 'Method not allowed' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceRoleKey) return reply(500, { error: 'Supabase function environment is incomplete' })

  const authorization = request.headers.get('Authorization')
  if (!authorization) return reply(401, { error: 'Authentication required' })

  let payload: { company_id?: string; email?: string; role?: string }
  try { payload = await request.json() } catch { return reply(400, { error: 'Invalid JSON body' }) }
  const companyId = payload.company_id
  const email = payload.email?.trim().toLowerCase()
  const role = payload.role || 'member'
  if (!companyId || !email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return reply(400, { error: 'A company and valid email are required' })
  if (!['owner', 'admin', 'member', 'viewer'].includes(role)) return reply(400, { error: 'Invalid company role' })

  const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } })
  const { data: callerData, error: callerError } = await caller.auth.getUser()
  if (callerError || !callerData.user) return reply(401, { error: 'Invalid session' })

  const { data: canAdmin, error: adminError } = await caller.rpc('can_admin_company', { p_company_id: companyId })
  if (adminError || !canAdmin) return reply(403, { error: 'Only a company owner or administrator can invite users' })

  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } })
  const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { invited_company_id: companyId },
  })
  if (inviteError || !inviteData.user) return reply(400, { error: inviteError?.message || 'Invitation failed' })

  const { error: membershipError } = await caller.rpc('fn_admin_upsert_membership', {
    p_company_id: companyId,
    p_user_id: inviteData.user.id,
    p_role: role,
  })
  if (membershipError) {
    await admin.auth.admin.deleteUser(inviteData.user.id)
    return reply(400, { error: membershipError.message })
  }

  return reply(200, { user_id: inviteData.user.id, email, role })
})
