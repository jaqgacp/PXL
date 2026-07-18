import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type Asset = { id: string; asset_number: string; asset_name: string; acquisition_cost: number; status: string; accum_depr: number; nbv: number }
type COA = { id: string; account_code: string; account_name: string }

type Form = {
  asset_id: string
  disposal_date: string
  disposal_type: string
  proceeds_amount: string
  proceeds_account_id: string
  notes: string
}

type DisposalRecord = {
  id: string
  asset_name: string
  asset_number: string
  disposal_date: string
  disposal_type: string
  proceeds_amount: number
  net_book_value: number
  gain_loss_amount: number
  journal_entry_id: string | null
}

const fmt = (n: number) => n?.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? '0.00'
const DISPOSAL_TYPES = [
  { value: 'sale', label: 'Sale' },
  { value: 'write_off', label: 'Write-Off' },
  { value: 'donation', label: 'Donation' },
  { value: 'trade_in', label: 'Trade-In' },
]

export default function AssetDisposalPage() {
  const { companyId } = useAppCtx()
  const today = new Date().toISOString().slice(0, 10)
  const [assets, setAssets] = useState<Asset[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [history, setHistory] = useState<DisposalRecord[]>([])
  const [form, setForm] = useState<Form>({ asset_id: '', disposal_date: today, disposal_type: 'sale', proceeds_amount: '0', proceeds_account_id: '', notes: '' })
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: faData }, { data: deprData }, { data: dispData }, { data: coaData }] = await Promise.all([
      supabase.from('fixed_assets').select('id,asset_number,asset_name,acquisition_cost,status').eq('company_id', companyId).in('status', ['active','impaired','fully_depreciated']).order('asset_number'),
      supabase.from('asset_depreciation_entries').select('asset_id,depreciation_amount').eq('company_id', companyId).eq('status', 'posted'),
      supabase.from('asset_disposals').select(`
        id, disposal_date, disposal_type, proceeds_amount, net_book_value, gain_loss_amount, journal_entry_id,
        fixed_assets!inner(asset_number, asset_name)
      `).eq('company_id', companyId).order('disposal_date', { ascending: false }).limit(50),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_postable', true).order('account_code'),
    ])

    const deprMap: Record<string, number> = {}
    for (const d of (deprData || [])) {
      deprMap[d.asset_id] = (deprMap[d.asset_id] || 0) + Number(d.depreciation_amount)
    }

    setAssets(((faData || []) as any[]).map(a => ({
      id: a.id, asset_number: a.asset_number, asset_name: a.asset_name,
      acquisition_cost: Number(a.acquisition_cost), status: a.status,
      accum_depr: deprMap[a.id] || 0, nbv: Number(a.acquisition_cost) - (deprMap[a.id] || 0),
    })))
    setCoa((coaData as COA[]) || [])
    setHistory(((dispData || []) as any[]).map(d => ({
      id: d.id, asset_name: d.fixed_assets?.asset_name ?? '', asset_number: d.fixed_assets?.asset_number ?? '',
      disposal_date: d.disposal_date, disposal_type: d.disposal_type,
      proceeds_amount: Number(d.proceeds_amount), net_book_value: Number(d.net_book_value),
      gain_loss_amount: Number(d.gain_loss_amount), journal_entry_id: d.journal_entry_id,
    })))
  }, [companyId])

  useEffect(() => { load() }, [load])

  const f = (k: keyof Form, v: string) => setForm(p => ({ ...p, [k]: v }))

  const selectedAsset = assets.find(a => a.id === form.asset_id)
  const proceeds = Number(form.proceeds_amount) || 0
  const previewGainLoss = selectedAsset ? proceeds - selectedAsset.nbv : null
  const glPreviewRows: GLImpactRow[] = selectedAsset ? [
    ...(selectedAsset.accum_depr > 0.005 ? [{
      accountLabel: 'Accumulated depreciation from asset category',
      description: `Accumulated depreciation — ${selectedAsset.asset_name}`,
      debit: selectedAsset.accum_depr,
      credit: 0,
    }] : []),
    ...(proceeds > 0.005 ? [{
      accountId: form.proceeds_account_id || null,
      accountLabel: form.proceeds_account_id ? undefined : 'Missing proceeds account',
      description: `Disposal proceeds — ${selectedAsset.asset_name}`,
      debit: proceeds,
      credit: 0,
    }] : []),
    ...(previewGainLoss != null && previewGainLoss < -0.005 ? [{
      accountLabel: 'Loss on disposal account from asset category',
      description: `Loss on disposal — ${selectedAsset.asset_name}`,
      debit: Math.abs(previewGainLoss),
      credit: 0,
    }] : []),
    {
      accountLabel: 'Asset cost account from asset category',
      description: `Asset cost — ${selectedAsset.asset_name}`,
      debit: 0,
      credit: selectedAsset.acquisition_cost,
    },
    ...(previewGainLoss != null && previewGainLoss > 0.005 ? [{
      accountLabel: 'Gain on disposal account from asset category',
      description: `Gain on disposal — ${selectedAsset.asset_name}`,
      debit: 0,
      credit: previewGainLoss,
    }] : []),
  ] : []

  const submit = async () => {
    if (!companyId || !form.asset_id) { setError('Select an asset'); return }
    if (!form.disposal_date) { setError('Disposal date required'); return }
    setSaving(true); setError(''); setSuccess('')
    const { error: e } = await supabase.rpc('fn_dispose_fixed_asset', {
      p_data: {
        company_id: companyId,
        asset_id: form.asset_id,
        disposal_date: form.disposal_date,
        disposal_type: form.disposal_type,
        proceeds_amount: Number(form.proceeds_amount) || 0,
        proceeds_account_id: form.proceeds_account_id || null,
        notes: form.notes || null,
      }
    })
    setSaving(false)
    if (e) { setError(e.message); return }
    setSuccess('Asset disposed and journal entry posted.')
    setForm({ asset_id: '', disposal_date: today, disposal_type: 'sale', proceeds_amount: '0', proceeds_account_id: '', notes: '' })
    load()
  }

  return (
    <LegacyTransactionWorkspace title="Asset Disposal" family="neutral" pattern="D" posting
      status="draft" identity={selectedAsset?.asset_name}
      financialFacts={[{ label: 'Carrying Amount', value: fmt(selectedAsset?.nbv || 0) }, { label: 'Disposal Proceeds', value: fmt(proceeds) }, { label: 'Gain / (Loss)', value: previewGainLoss == null ? 'Not calculated' : fmt(previewGainLoss) }, { label: 'Acquisition Cost', value: fmt(selectedAsset?.acquisition_cost || 0) }]}
      contextFacts={[{ label: 'Asset', value: selectedAsset ? `${selectedAsset.asset_number} — ${selectedAsset.asset_name}` : 'Not selected' }, { label: 'Disposal Date', value: form.disposal_date }, { label: 'Disposal Type', value: form.disposal_type }, { label: 'Status', value: selectedAsset?.status || 'Not selected' }]}
      actions={[{ key: 'post', label: saving ? 'Processing…' : 'Record Disposal', onClick: submit, disabled: saving || !form.asset_id, variant: 'primary' }]}
      headerFields={[
        { key: 'date', label: 'Disposal Date *', card: 0, content: <input type="date" value={form.disposal_date} onChange={e => f('disposal_date', e.target.value)} className="pxl-input w-full" /> },
        { key: 'type', label: 'Disposal Type', card: 0, content: <select value={form.disposal_type} onChange={e => f('disposal_type', e.target.value)} className="pxl-input w-full">{DISPOSAL_TYPES.map(type => <option key={type.value} value={type.value}>{type.label}</option>)}</select> },
        { key: 'asset', label: 'Asset *', card: 1, span: 2, content: <select value={form.asset_id} onChange={e => f('asset_id', e.target.value)} className="pxl-input w-full"><option value="">Select asset…</option>{assets.map(asset => <option key={asset.id} value={asset.id}>{asset.asset_number} — {asset.asset_name}</option>)}</select> },
        { key: 'proceeds', label: 'Proceeds Amount', card: 2, content: <input type="number" min={0} step={0.01} value={form.proceeds_amount} onChange={e => f('proceeds_amount', e.target.value)} className="pxl-input w-full text-right" /> },
        { key: 'account', label: 'Proceeds Account', card: 2, span: 2, content: <select value={form.proceeds_account_id} onChange={e => f('proceeds_account_id', e.target.value)} className="pxl-input w-full"><option value="">None</option>{coa.map(account => <option key={account.id} value={account.id}>{account.account_code} — {account.account_name}</option>)}</select> },
        { key: 'notes', label: 'Notes', card: 2, span: 2, content: <input value={form.notes} onChange={e => f('notes', e.target.value)} className="pxl-input w-full" /> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{success && <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-700">{success}</div>}</div>,
        gl: <GLImpactPanel companyId={companyId} sourceDocType="FA_DISP" sourceDocId={null} previewRows={glPreviewRows} title="GL Impact — Asset Disposal" />,
        activity: <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr>{['Asset #','Name','Date','Type','Proceeds','NBV','Gain / (Loss)','JE'].map(label => <th key={label} className="text-left">{label}</th>)}</tr></thead><tbody>{history.length === 0 ? <tr><td colSpan={8} className="pxl-empty-state">No disposal records</td></tr> : history.map(record => <tr key={record.id}><td>{record.asset_number}</td><td>{record.asset_name}</td><td>{record.disposal_date}</td><td>{record.disposal_type}</td><td>{fmt(record.proceeds_amount)}</td><td>{fmt(record.net_book_value)}</td><td>{fmt(record.gain_loss_amount)}</td><td>{record.journal_entry_id ? record.journal_entry_id.slice(0, 8) : '—'}</td></tr>)}</tbody></table></div>,
      }}>
      <div className="overflow-x-auto"><table className="pxl-data-grid w-full"><thead><tr>{['Asset','Acquisition Cost','Accumulated Depreciation','Net Book Value','Proceeds','Gain / (Loss)'].map(label => <th key={label} className="text-left">{label}</th>)}</tr></thead><tbody><tr><td>{selectedAsset ? `${selectedAsset.asset_number} — ${selectedAsset.asset_name}` : 'Select an asset above'}</td><td>{fmt(selectedAsset?.acquisition_cost || 0)}</td><td>{fmt(selectedAsset?.accum_depr || 0)}</td><td>{fmt(selectedAsset?.nbv || 0)}</td><td>{fmt(proceeds)}</td><td>{previewGainLoss == null ? '—' : fmt(previewGainLoss)}</td></tr></tbody></table></div>
    </LegacyTransactionWorkspace>
  )
}
