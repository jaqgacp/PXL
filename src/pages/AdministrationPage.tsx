import { useCallback, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

export type AdministrationScreen = 'users' | 'memberships' | 'roles' | 'branch-scopes'
type CompanyUser = { membership_id: string; user_id: string; email: string; role: string; granted_at: string; last_sign_in_at: string | null }
type Branch = { id: string; branch_code: string; branch_name: string }

const screens: { key: AdministrationScreen; label: string; path: string }[] = [
  { key: 'users', label: 'Users & Invite', path: '/admin-users' },
  { key: 'memberships', label: 'Memberships', path: '/admin-memberships' },
  { key: 'roles', label: 'Role Assignment', path: '/admin-roles' },
  { key: 'branch-scopes', label: 'Branch Scope', path: '/admin-branch-scopes' },
]
const roles = ['owner', 'admin', 'member', 'viewer']
const formatDate = (value: string | null) => value ? new Date(value).toLocaleString('en-PH') : 'Never'

export default function AdministrationPage({ screen }: { screen: AdministrationScreen }) {
  const { companyId } = useAppCtx()
  const navigate = useNavigate()
  const [users, setUsers] = useState<CompanyUser[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [selectedUserId, setSelectedUserId] = useState('')
  const [selectedBranches, setSelectedBranches] = useState<string[]>([])
  const [email, setEmail] = useState('')
  const [inviteRole, setInviteRole] = useState('member')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  const selectedUser = useMemo(() => users.find(user => user.user_id === selectedUserId), [users, selectedUserId])

  const load = useCallback(async () => {
    if (!companyId) { setUsers([]); setBranches([]); return }
    setBusy(true); setError('')
    const [userResult, branchResult] = await Promise.all([
      (supabase as any).rpc('fn_admin_list_company_users', { p_company_id: companyId }),
      supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true).order('branch_code'),
    ])
    setBusy(false)
    if (userResult.error) { setError(userResult.error.message); return }
    setUsers((userResult.data as CompanyUser[]) || [])
    setBranches((branchResult.data as Branch[]) || [])
  }, [companyId])

  useEffect(() => { load() }, [load])

  useEffect(() => {
    if (!companyId || !selectedUserId || screen !== 'branch-scopes') return
    ;(supabase as any).from('user_company_branch_scopes').select('branch_id')
      .eq('company_id', companyId).eq('user_id', selectedUserId).eq('is_active', true)
      .then(({ data }: any) => setSelectedBranches((data || []).map((row: any) => row.branch_id)))
  }, [companyId, selectedUserId, screen])

  const invite = async () => {
    if (!companyId || !email.trim()) return
    setBusy(true); setError(''); setMessage('')
    const { error: inviteError } = await supabase.functions.invoke('admin-invite', {
      body: { company_id: companyId, email: email.trim().toLowerCase(), role: inviteRole },
    })
    setBusy(false)
    if (inviteError) { setError(inviteError.message); return }
    setEmail(''); setMessage('Invitation sent and company membership assigned.'); await load()
  }

  const setRole = async (user: CompanyUser, role: string) => {
    if (!companyId) return
    setBusy(true); setError(''); setMessage('')
    const { error: rpcError } = await (supabase as any).rpc('fn_admin_upsert_membership', {
      p_company_id: companyId, p_user_id: user.user_id, p_role: role,
    })
    setBusy(false)
    if (rpcError) { setError(rpcError.message); return }
    setMessage(`Role updated for ${user.email}.`); await load()
  }

  const removeMembership = async (user: CompanyUser) => {
    if (!companyId || !confirm(`Remove ${user.email} from this company?`)) return
    setBusy(true); setError(''); setMessage('')
    const { error: rpcError } = await (supabase as any).rpc('fn_admin_remove_membership', {
      p_company_id: companyId, p_user_id: user.user_id,
    })
    setBusy(false)
    if (rpcError) { setError(rpcError.message); return }
    setMessage(`${user.email} removed from the company.`); await load()
  }

  const saveBranchScopes = async () => {
    if (!companyId || !selectedUserId) return
    setBusy(true); setError(''); setMessage('')
    const { error: rpcError } = await (supabase as any).rpc('fn_admin_set_branch_scopes', {
      p_company_id: companyId, p_user_id: selectedUserId, p_branch_ids: selectedBranches,
    })
    setBusy(false)
    if (rpcError) { setError(rpcError.message); return }
    setMessage(`Branch scope saved for ${selectedUser?.email}.`)
  }

  if (!companyId) return <div className="p-8 text-sm text-gray-500">Select a company before administering users.</div>

  return <div className="space-y-5">
    <div><h1 className="text-xl font-semibold text-gray-900">Administration</h1><p className="mt-1 text-sm text-gray-500">Company-scoped users, memberships, roles, and branch access.</p></div>
    <nav className="flex flex-wrap gap-2 border-b border-gray-200 pb-3">{screens.map(item => <button key={item.key} onClick={() => navigate(item.path)} className={`rounded px-3 py-2 text-sm ${screen === item.key ? 'bg-gray-900 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'}`}>{item.label}</button>)}</nav>
    {(error || message) && <div className={`rounded border px-4 py-3 text-sm ${error ? 'border-red-200 bg-red-50 text-red-700' : 'border-green-200 bg-green-50 text-green-700'}`}>{error || message}</div>}

    {screen === 'users' && <div className="grid gap-5 xl:grid-cols-[360px_minmax(0,1fr)]">
      <section className="rounded-lg border border-gray-200 bg-white p-5"><h2 className="font-semibold text-gray-900">Invite user</h2><p className="mt-1 text-xs text-gray-500">Sends the Supabase invitation, then assigns a company role.</p><label className="mt-4 block text-xs font-medium text-gray-500">Email<input type="email" value={email} onChange={event => setEmail(event.target.value)} className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm" /></label><label className="mt-3 block text-xs font-medium text-gray-500">Initial role<select value={inviteRole} onChange={event => setInviteRole(event.target.value)} className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm">{roles.map(role => <option key={role} value={role}>{role}</option>)}</select></label><button onClick={invite} disabled={busy || !email.trim()} className="mt-4 w-full rounded bg-gray-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50">Send invitation</button></section>
      <UserTable users={users} busy={busy} />
    </div>}

    {screen === 'memberships' && <section className="overflow-hidden rounded-lg border border-gray-200 bg-white"><div className="border-b px-4 py-3"><h2 className="font-semibold text-gray-900">Company memberships</h2><p className="text-xs text-gray-500">Removal also clears the user's company branch scopes. The last owner cannot be removed.</p></div><table className="w-full text-sm"><thead className="bg-gray-50"><tr>{['User','Role','Granted',''].map(label => <th key={label} className="px-4 py-2 text-left text-xs text-gray-500">{label}</th>)}</tr></thead><tbody>{users.map(user => <tr key={user.user_id} className="border-t"><td className="px-4 py-3">{user.email}</td><td className="px-4 py-3 capitalize">{user.role}</td><td className="px-4 py-3 text-gray-500">{formatDate(user.granted_at)}</td><td className="px-4 py-3 text-right"><button onClick={() => removeMembership(user)} disabled={busy} className="text-xs font-medium text-red-600 disabled:opacity-50">Remove</button></td></tr>)}</tbody></table></section>}

    {screen === 'roles' && <section className="overflow-hidden rounded-lg border border-gray-200 bg-white"><div className="border-b px-4 py-3"><h2 className="font-semibold text-gray-900">Role assignment</h2><p className="text-xs text-gray-500">Only owners can assign another owner; every company must retain at least one.</p></div><table className="w-full text-sm"><thead className="bg-gray-50"><tr><th className="px-4 py-2 text-left text-xs text-gray-500">User</th><th className="px-4 py-2 text-left text-xs text-gray-500">Role</th></tr></thead><tbody>{users.map(user => <tr key={user.user_id} className="border-t"><td className="px-4 py-3">{user.email}</td><td className="px-4 py-3"><select value={user.role} disabled={busy} onChange={event => setRole(user, event.target.value)} className="rounded border border-gray-300 px-3 py-1.5 capitalize">{roles.map(role => <option key={role} value={role}>{role}</option>)}</select></td></tr>)}</tbody></table></section>}

    {screen === 'branch-scopes' && <section className="rounded-lg border border-gray-200 bg-white p-5"><div className="grid gap-5 md:grid-cols-[320px_minmax(0,1fr)]"><div><label className="text-xs font-medium text-gray-500">Company user<select value={selectedUserId} onChange={event => setSelectedUserId(event.target.value)} className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"><option value="">Select user...</option>{users.map(user => <option key={user.user_id} value={user.user_id}>{user.email} · {user.role}</option>)}</select></label><p className="mt-3 text-xs text-gray-500">No selected branches means company-wide branch access under the current scope helper.</p></div><div><div className="text-xs font-medium text-gray-500">Allowed branches</div><div className="mt-2 grid gap-2 sm:grid-cols-2">{branches.map(branch => <label key={branch.id} className="flex items-center gap-2 rounded border border-gray-200 px-3 py-2 text-sm"><input type="checkbox" disabled={!selectedUserId} checked={selectedBranches.includes(branch.id)} onChange={event => setSelectedBranches(ids => event.target.checked ? [...ids, branch.id] : ids.filter(id => id !== branch.id))} />{branch.branch_code} — {branch.branch_name}</label>)}</div><button onClick={saveBranchScopes} disabled={busy || !selectedUserId} className="mt-4 rounded bg-gray-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Save branch scope</button></div></div></section>}
  </div>
}

function UserTable({ users, busy }: { users: CompanyUser[]; busy: boolean }) {
  return <section className="overflow-hidden rounded-lg border border-gray-200 bg-white"><div className="border-b px-4 py-3"><h2 className="font-semibold text-gray-900">Company users</h2></div>{busy ? <p className="p-8 text-center text-sm text-gray-400">Loading…</p> : users.length === 0 ? <p className="p-8 text-center text-sm text-gray-400">No company users</p> : <table className="w-full text-sm"><thead className="bg-gray-50"><tr>{['Email','Role','Last sign-in'].map(label => <th key={label} className="px-4 py-2 text-left text-xs text-gray-500">{label}</th>)}</tr></thead><tbody>{users.map(user => <tr key={user.user_id} className="border-t"><td className="px-4 py-3">{user.email}</td><td className="px-4 py-3 capitalize">{user.role}</td><td className="px-4 py-3 text-gray-500">{formatDate(user.last_sign_in_at)}</td></tr>)}</tbody></table>}</section>
}
