import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type Asset = { id: string; asset_number: string; asset_name: string; acquisition_cost: number; accum_depr: number; carrying_amount: number; status: string }
type COA = { id: string; account_code: string; account_name: string }

type ImpairmentRecord = {
  id: string
  asset_number: string
  asset_name: string
  impairment_date: string
  carrying_amount_before: number
  recoverable_amount: number
  impairment_loss: number
  journal_entry_id: string | null
  notes: string | null
}

const fmt = (n: number) => n?.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? '0.00'

export default function AssetImpairmentPage() {
  const { companyId } = useAppCtx()
  const today = new Date().toISOString().slice(0, 10)
  const [assets, setAssets] = useState<Asset[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [history, setHistory] = useState<ImpairmentRecord[]>([])
  const [assetId, setAssetId] = useState('')
  const [impDate, setImpDate] = useState(today)
  const [recoverable, setRecoverable] = useState('0')
  const [impLossAcct, setImpLossAcct] = useState('')
  const [accumImpAcct, setAccumImpAcct] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: faData }, { data: deprData }, { data: impData }, { data: coaData }] = await Promise.all([
      supabase.from('fixed_assets').select('id,asset_number,asset_name,acquisition_cost,status').eq('company_id', companyId).in('status', ['active','impaired']).order('asset_number'),
      supabase.from('asset_depreciation_entries').select('asset_id,depreciation_amount').eq('company_id', companyId).eq('status', 'posted'),
      supabase.from('asset_impairments').select(`
        id, impairment_date, carrying_amount_before, recoverable_amount, impairment_loss, journal_entry_id, notes,
        fixed_assets!inner(asset_number, asset_name, company_id)
      `).eq('fixed_assets.company_id', companyId).order('impairment_date', { ascending: false }).limit(50),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_postable', true).order('account_code'),
    ])

    const deprMap: Record<string, number> = {}
    for (const d of (deprData || [])) {
      deprMap[d.asset_id] = (deprMap[d.asset_id] || 0) + Number(d.depreciation_amount)
    }

    setAssets(((faData || []) as any[]).map(a => {
      const ad = deprMap[a.id] || 0
      return { id: a.id, asset_number: a.asset_number, asset_name: a.asset_name,
        acquisition_cost: Number(a.acquisition_cost), status: a.status,
        accum_depr: ad, carrying_amount: Number(a.acquisition_cost) - ad }
    }))
    setCoa((coaData as COA[]) || [])
    setHistory(((impData || []) as any[]).map(r => ({
      id: r.id, impairment_date: r.impairment_date, notes: r.notes,
      asset_number: r.fixed_assets?.asset_number ?? '', asset_name: r.fixed_assets?.asset_name ?? '',
      carrying_amount_before: Number(r.carrying_amount_before),
      recoverable_amount: Number(r.recoverable_amount),
      impairment_loss: Number(r.impairment_loss),
      journal_entry_id: r.journal_entry_id,
    })))
  }, [companyId])

  useEffect(() => { load() }, [load])

  const selectedAsset = assets.find(a => a.id === assetId)
  const recoverableNum = Number(recoverable) || 0
  const previewLoss = selectedAsset ? Math.max(0, selectedAsset.carrying_amount - recoverableNum) : null
  const glPreviewRows: GLImpactRow[] = selectedAsset && previewLoss && previewLoss > 0.005 ? [
    {
      accountId: impLossAcct || null,
      accountLabel: impLossAcct ? undefined : 'Impairment loss account from asset category',
      description: `Impairment loss — ${selectedAsset.asset_name}`,
      debit: previewLoss,
      credit: 0,
    },
    {
      accountId: accumImpAcct || null,
      accountLabel: accumImpAcct ? undefined : 'Accumulated impairment account from asset category',
      description: `Accumulated impairment — ${selectedAsset.asset_name}`,
      debit: 0,
      credit: previewLoss,
    },
  ] : []

  const submit = async () => {
    if (!companyId || !assetId) { setError('Select an asset'); return }
    if (!impDate) { setError('Impairment date required'); return }
    if (selectedAsset && recoverableNum >= selectedAsset.carrying_amount) { setError('Recoverable amount must be less than carrying amount'); return }
    setSaving(true); setError(''); setSuccess('')
    const { error: e } = await supabase.rpc('fn_record_impairment', {
      p_data: {
        company_id: companyId,
        asset_id: assetId,
        impairment_date: impDate,
        recoverable_amount: recoverableNum,
        gl_impairment_loss_account_id: impLossAcct || null,
        gl_accum_impairment_account_id: accumImpAcct || null,
        notes: notes || null,
      }
    })
    setSaving(false)
    if (e) { setError(e.message); return }
    setSuccess('Impairment recorded and journal entry posted.')
    setAssetId(''); setRecoverable('0'); setImpLossAcct(''); setAccumImpAcct(''); setNotes('')
    load()
  }

  return (
    <LegacyTransactionWorkspace title="Asset Impairment" family="neutral" pattern="D" posting
      status="draft" identity={selectedAsset?.asset_name}
      financialFacts={[{ label: 'Carrying Amount', value: fmt(selectedAsset?.carrying_amount || 0) }, { label: 'Recoverable Amount', value: fmt(recoverableNum) }, { label: 'Impairment Loss', value: previewLoss == null ? 'Not calculated' : fmt(previewLoss) }, { label: 'Acquisition Cost', value: fmt(selectedAsset?.acquisition_cost || 0) }]}
      contextFacts={[{ label: 'Asset', value: selectedAsset ? `${selectedAsset.asset_number} — ${selectedAsset.asset_name}` : 'Not selected' }, { label: 'Impairment Date', value: impDate }, { label: 'Status', value: selectedAsset?.status || 'Not selected' }, { label: 'Loss Account', value: coa.find(account => account.id === impLossAcct)?.account_name || 'Not selected' }]}
      actions={[{ key: 'post', label: saving ? 'Recording…' : 'Record Impairment', onClick: submit, disabled: saving || !assetId, variant: 'primary' }]}
      headerFields={[
        { key: 'date', label: 'Impairment Date *', card: 0, content: <input type="date" value={impDate} onChange={e => setImpDate(e.target.value)} className="pxl-input w-full" /> },
        { key: 'basis', label: 'Measurement Basis', card: 0, content: <div className="pxl-readonly-field">PAS 36 recoverable amount</div> },
        { key: 'asset', label: 'Asset *', card: 1, span: 2, content: <select value={assetId} onChange={e => setAssetId(e.target.value)} className="pxl-input w-full"><option value="">Select asset…</option>{assets.map(asset => <option key={asset.id} value={asset.id}>{asset.asset_number} — {asset.asset_name}</option>)}</select> },
        { key: 'recoverable', label: 'Recoverable Amount', card: 1, content: <input type="number" min={0} step={0.01} value={recoverable} onChange={e => setRecoverable(e.target.value)} className="pxl-input w-full text-right" /> },
        { key: 'loss-account', label: 'Impairment Loss Account (DR)', card: 2, span: 2, content: <select value={impLossAcct} onChange={e => setImpLossAcct(e.target.value)} className="pxl-input w-full"><option value="">Use category default</option>{coa.map(account => <option key={account.id} value={account.id}>{account.account_code} — {account.account_name}</option>)}</select> },
        { key: 'accum-account', label: 'Accumulated Impairment (CR)', card: 2, span: 2, content: <select value={accumImpAcct} onChange={e => setAccumImpAcct(e.target.value)} className="pxl-input w-full"><option value="">Use category default</option>{coa.map(account => <option key={account.id} value={account.id}>{account.account_code} — {account.account_name}</option>)}</select> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{success && <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-700">{success}</div>}</div>,
        gl: <GLImpactPanel companyId={companyId} sourceDocType="FA_IMP" sourceDocId={null} previewRows={glPreviewRows} title="GL Impact — Asset Impairment" />,
        notes: <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3} className="pxl-input w-full" aria-label="Impairment basis and notes" />,
        activity: <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr>{['Asset #','Name','Date','Carrying Amount','Recoverable','Impairment Loss','JE','Notes'].map(label => <th key={label} className="text-left">{label}</th>)}</tr></thead><tbody>{history.length === 0 ? <tr><td colSpan={8} className="pxl-empty-state">No impairment records</td></tr> : history.map(record => <tr key={record.id}><td>{record.asset_number}</td><td>{record.asset_name}</td><td>{record.impairment_date}</td><td>{fmt(record.carrying_amount_before)}</td><td>{fmt(record.recoverable_amount)}</td><td>{fmt(record.impairment_loss)}</td><td>{record.journal_entry_id ? record.journal_entry_id.slice(0, 8) : '—'}</td><td>{record.notes || '—'}</td></tr>)}</tbody></table></div>,
      }}>
      <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr>{['Asset','Acquisition Cost','Accumulated Depreciation','Carrying Amount','Recoverable Amount','Impairment Loss'].map(label => <th key={label} className="text-left">{label}</th>)}</tr></thead><tbody><tr><td>{selectedAsset ? `${selectedAsset.asset_number} — ${selectedAsset.asset_name}` : 'Select an asset above'}</td><td>{fmt(selectedAsset?.acquisition_cost || 0)}</td><td>{fmt(selectedAsset?.accum_depr || 0)}</td><td>{fmt(selectedAsset?.carrying_amount || 0)}</td><td>{fmt(recoverableNum)}</td><td>{previewLoss == null ? '—' : fmt(previewLoss)}</td></tr></tbody></table></div>
    </LegacyTransactionWorkspace>
  )
}
