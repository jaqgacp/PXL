import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { transactionHeaderClass, transactionSegmentButtonClass } from '@/lib/transactionWorkspace'

type Asset = { id: string; asset_number: string; asset_name: string; branch_name: string | null; department_name: string | null; status: string }
type Branch = { id: string; branch_name: string }
type Department = { id: string; department_name: string }

type TransferRecord = {
  id: string
  asset_number: string
  asset_name: string
  transfer_date: string
  from_branch: string | null
  from_dept: string | null
  to_branch: string | null
  to_dept: string | null
  notes: string | null
}

export default function AssetTransferPage() {
  const { companyId } = useAppCtx()
  const today = new Date().toISOString().slice(0, 10)
  const [assets, setAssets] = useState<Asset[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [departments, setDepartments] = useState<Department[]>([])
  const [history, setHistory] = useState<TransferRecord[]>([])
  const [assetId, setAssetId] = useState('')
  const [transferDate, setTransferDate] = useState(today)
  const [toBranch, setToBranch] = useState('')
  const [toDept, setToDept] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [tab, setTab] = useState<'new' | 'history'>('new')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: faData }, { data: brs }, { data: depts }, { data: xfrs }] = await Promise.all([
      supabase.from('fixed_assets').select(`
        id, asset_number, asset_name, status,
        branches(branch_name), departments(department_name)
      `).eq('company_id', companyId).in('status', ['active','fully_depreciated']).order('asset_number'),
      supabase.from('branches').select('id,branch_name').eq('company_id', companyId).order('branch_name'),
      supabase.from('departments').select('id,department_name').eq('company_id', companyId).order('department_name'),
      supabase.from('asset_transfers').select(`
        id, transfer_date, notes,
        from_branch:branches!asset_transfers_from_branch_id_fkey(branch_name),
        to_branch:branches!asset_transfers_to_branch_id_fkey(branch_name),
        from_dept:departments!asset_transfers_from_department_id_fkey(department_name),
        to_dept:departments!asset_transfers_to_department_id_fkey(department_name),
        fixed_assets!inner(asset_number, asset_name, company_id)
      `).eq('fixed_assets.company_id', companyId).order('transfer_date', { ascending: false }).limit(50),
    ])

    setAssets(((faData || []) as any[]).map(a => ({
      id: a.id, asset_number: a.asset_number, asset_name: a.asset_name, status: a.status,
      branch_name: a.branches?.branch_name ?? null, department_name: a.departments?.department_name ?? null,
    })))
    setBranches((brs as Branch[]) || [])
    setDepartments((depts as Department[]) || [])
    setHistory(((xfrs || []) as any[]).map(x => ({
      id: x.id, transfer_date: x.transfer_date, notes: x.notes,
      asset_number: x.fixed_assets?.asset_number ?? '', asset_name: x.fixed_assets?.asset_name ?? '',
      from_branch: x.from_branch?.branch_name ?? null, to_branch: x.to_branch?.branch_name ?? null,
      from_dept: x.from_dept?.department_name ?? null, to_dept: x.to_dept?.department_name ?? null,
    })))
  }, [companyId])

  useEffect(() => { load() }, [load])

  const selectedAsset = assets.find(a => a.id === assetId)

  const submit = async () => {
    if (!companyId || !assetId) { setError('Select an asset'); return }
    if (!transferDate) { setError('Transfer date required'); return }
    if (!toBranch && !toDept) { setError('Select at least a destination branch or department'); return }
    setSaving(true); setError(''); setSuccess('')
    const { error: e } = await supabase.rpc('fn_transfer_fixed_asset', {
      p_data: {
        company_id: companyId,
        asset_id: assetId,
        transfer_date: transferDate,
        to_branch_id: toBranch || null,
        to_department_id: toDept || null,
        notes: notes || null,
      }
    })
    setSaving(false)
    if (e) { setError(e.message); return }
    setSuccess('Transfer recorded successfully.')
    setAssetId(''); setToBranch(''); setToDept(''); setNotes('')
    load()
  }

  return (
    <div>
      <div className={transactionHeaderClass('inventory')}>
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset Transfer</span>
        <div className="ml-auto flex gap-1">
          {(['new','history'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={transactionSegmentButtonClass('inventory', tab === t)}>
              {t === 'new' ? 'New Transfer' : 'History'}
            </button>
          ))}
        </div>
      </div>

      {tab === 'new' ? (
        <div className="px-5 py-4 max-w-2xl space-y-4">
          {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
          {success && <div className="text-xs text-green-700 bg-green-50 border border-green-200 rounded px-3 py-2">{success}</div>}

          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Transfer Details</p>

            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Asset *</label>
              <select value={assetId} onChange={e => setAssetId(e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">— Select Asset —</option>
                {assets.map(a => <option key={a.id} value={a.id}>{a.asset_number} — {a.asset_name}</option>)}
              </select>
            </div>

            {selectedAsset && (
              <div className="bg-gray-50 rounded px-3 py-2 text-xs grid grid-cols-2 gap-2">
                <div><p className="text-gray-400 text-[10px]">Current Branch</p><p className="font-medium text-gray-800">{selectedAsset.branch_name || '—'}</p></div>
                <div><p className="text-gray-400 text-[10px]">Current Department</p><p className="font-medium text-gray-800">{selectedAsset.department_name || '—'}</p></div>
              </div>
            )}

            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Transfer Date *</label>
              <input type="date" value={transferDate} onChange={e => setTransferDate(e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">To Branch</label>
                <select value={toBranch} onChange={e => setToBranch(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">— Keep current —</option>
                  {branches.map(b => <option key={b.id} value={b.id}>{b.branch_name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">To Department</label>
                <select value={toDept} onChange={e => setToDept(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">— Keep current —</option>
                  {departments.map(d => <option key={d.id} value={d.id}>{d.department_name}</option>)}
                </select>
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
              <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 resize-none" />
            </div>
          </div>

          <button onClick={submit} disabled={saving || !assetId}
            className="px-5 py-2 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {saving ? 'Saving…' : 'Record Transfer'}
          </button>
        </div>
      ) : (
        <div className="px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Asset #','Name','Date','From Branch','From Dept','To Branch','To Dept','Notes'].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {history.length === 0 ? (
                  <tr><td colSpan={8} className="py-12 text-center text-gray-400">No transfer records</td></tr>
                ) : history.map(x => (
                  <tr key={x.id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{x.asset_number}</td>
                    <td className="px-3 py-2 text-gray-800 max-w-[140px] truncate">{x.asset_name}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{x.transfer_date}</td>
                    <td className="px-3 py-2 text-gray-600">{x.from_branch || '—'}</td>
                    <td className="px-3 py-2 text-gray-600">{x.from_dept || '—'}</td>
                    <td className="px-3 py-2 text-blue-700 font-medium">{x.to_branch || '—'}</td>
                    <td className="px-3 py-2 text-blue-700 font-medium">{x.to_dept || '—'}</td>
                    <td className="px-3 py-2 text-gray-500 max-w-[120px] truncate">{x.notes || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
