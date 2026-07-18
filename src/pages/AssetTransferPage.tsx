import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

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
    <LegacyTransactionWorkspace title="Asset Transfer" family="inventory" pattern="B" posting={false}
      status="draft" identity={selectedAsset?.asset_name}
      financialFacts={[{ label: 'Assets Transferred', value: selectedAsset ? 1 : 0, hint: 'Custody movement; no direct GL posting' }]}
      contextFacts={[{ label: 'Asset', value: selectedAsset ? `${selectedAsset.asset_number} — ${selectedAsset.asset_name}` : 'Not selected' }, { label: 'Source Branch', value: selectedAsset?.branch_name || 'Not assigned' }, { label: 'Destination Branch', value: branches.find(branch => branch.id === toBranch)?.branch_name || 'Not selected' }, { label: 'Source Department', value: selectedAsset?.department_name || 'Not assigned' }, { label: 'Destination Department', value: departments.find(department => department.id === toDept)?.department_name || 'Not selected' }, { label: 'Transfer Date', value: transferDate }]}
      actions={[{ key: 'save', label: saving ? 'Saving…' : 'Record Transfer', onClick: submit, disabled: saving || !assetId, variant: 'primary' }]}
      headerFields={[
        { key: 'date', label: 'Transfer Date *', card: 0, content: <input type="date" value={transferDate} onChange={e => setTransferDate(e.target.value)} className="pxl-input w-full" /> },
        { key: 'state', label: 'Posting State', card: 0, content: <div className="pxl-readonly-field">No direct GL posting</div> },
        { key: 'asset', label: 'Asset *', card: 1, span: 2, content: <select value={assetId} onChange={e => setAssetId(e.target.value)} className="pxl-input w-full"><option value="">Select asset…</option>{assets.map(asset => <option key={asset.id} value={asset.id}>{asset.asset_number} — {asset.asset_name}</option>)}</select> },
        { key: 'branch', label: 'To Branch', card: 2, content: <select value={toBranch} onChange={e => setToBranch(e.target.value)} className="pxl-input w-full"><option value="">Keep current</option>{branches.map(branch => <option key={branch.id} value={branch.id}>{branch.branch_name}</option>)}</select> },
        { key: 'department', label: 'To Department', card: 2, content: <select value={toDept} onChange={e => setToDept(e.target.value)} className="pxl-input w-full"><option value="">Keep current</option>{departments.map(department => <option key={department.id} value={department.id}>{department.department_name}</option>)}</select> },
        { key: 'notes', label: 'Notes', card: 2, span: 2, content: <input value={notes} onChange={e => setNotes(e.target.value)} className="pxl-input w-full" /> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{success && <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-700">{success}</div>}</div>,
        activity: <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr>{['Asset #','Name','Date','From Branch','From Dept','To Branch','To Dept','Notes'].map(label => <th key={label} className="text-left">{label}</th>)}</tr></thead><tbody>{history.length === 0 ? <tr><td colSpan={8} className="pxl-empty-state">No transfer records</td></tr> : history.map(record => <tr key={record.id}><td>{record.asset_number}</td><td>{record.asset_name}</td><td>{record.transfer_date}</td><td>{record.from_branch || '—'}</td><td>{record.from_dept || '—'}</td><td>{record.to_branch || '—'}</td><td>{record.to_dept || '—'}</td><td>{record.notes || '—'}</td></tr>)}</tbody></table></div>,
      }}>
      <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr>{['Asset','Source Branch','Source Department','Destination Branch','Destination Department'].map(label => <th key={label} className="text-left">{label}</th>)}</tr></thead><tbody><tr><td>{selectedAsset ? `${selectedAsset.asset_number} — ${selectedAsset.asset_name}` : 'Select an asset above'}</td><td>{selectedAsset?.branch_name || '—'}</td><td>{selectedAsset?.department_name || '—'}</td><td>{branches.find(branch => branch.id === toBranch)?.branch_name || selectedAsset?.branch_name || '—'}</td><td>{departments.find(department => department.id === toDept)?.department_name || selectedAsset?.department_name || '—'}</td></tr></tbody></table></div>
    </LegacyTransactionWorkspace>
  )
}
