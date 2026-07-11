import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'

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
  const [tab, setTab] = useState<'new' | 'history'>('new')

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
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset Impairment (PAS 36)</span>
        <div className="ml-auto flex gap-1">
          {(['new','history'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-3 py-1 rounded text-xs font-medium ${tab === t ? 'bg-gray-900 text-white' : 'text-gray-500 hover:text-gray-900'}`}>
              {t === 'new' ? 'Record Impairment' : 'History'}
            </button>
          ))}
        </div>
      </div>

      {tab === 'new' ? (
        <div className="px-5 py-4 max-w-2xl space-y-4">
          {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
          {success && <div className="text-xs text-green-700 bg-green-50 border border-green-200 rounded px-3 py-2">{success}</div>}

          <div className="bg-amber-50 border border-amber-200 rounded px-3 py-2 text-xs text-amber-800">
            <strong>PAS 36 — Impairment of Assets:</strong> Record when the carrying amount of an asset exceeds its recoverable amount (higher of fair value less costs to sell vs. value-in-use).
          </div>

          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Impairment Assessment</p>

            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Asset *</label>
              <select value={assetId} onChange={e => setAssetId(e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">— Select Asset —</option>
                {assets.map(a => <option key={a.id} value={a.id}>{a.asset_number} — {a.asset_name}</option>)}
              </select>
            </div>

            {selectedAsset && (
              <div className="bg-gray-50 rounded px-3 py-2 text-xs grid grid-cols-3 gap-3 font-mono">
                <div><p className="text-gray-400 text-[10px]">Acquisition Cost</p><p className="font-semibold text-gray-800">₱ {fmt(selectedAsset.acquisition_cost)}</p></div>
                <div><p className="text-gray-400 text-[10px]">Accum. Depreciation</p><p className="font-semibold text-gray-600">₱ {fmt(selectedAsset.accum_depr)}</p></div>
                <div><p className="text-gray-400 text-[10px]">Carrying Amount</p><p className="font-semibold text-blue-700">₱ {fmt(selectedAsset.carrying_amount)}</p></div>
              </div>
            )}

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Impairment Date *</label>
                <input type="date" value={impDate} onChange={e => setImpDate(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Recoverable Amount (₱) *</label>
                <input type="number" min={0} step={0.01} value={recoverable} onChange={e => setRecoverable(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900" />
                <p className="text-[10px] text-gray-400 mt-0.5">Higher of: fair value less costs to sell vs. value-in-use</p>
              </div>
            </div>

            {previewLoss !== null && previewLoss > 0 && (
              <div className="bg-red-50 border border-red-200 rounded px-3 py-2 text-xs text-red-800 font-mono">
                Impairment Loss: ₱ {fmt(previewLoss)}
              </div>
            )}

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Impairment Loss Account (DR)</label>
                <select value={impLossAcct} onChange={e => setImpLossAcct(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">— Use category default —</option>
                  {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Accum. Impairment Account (CR)</label>
                <select value={accumImpAcct} onChange={e => setAccumImpAcct(e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">— Use category default —</option>
                  {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                </select>
              </div>
            </div>

            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Notes / Basis for Impairment</label>
              <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 resize-none"
                placeholder="Describe the indicators of impairment (physical damage, obsolescence, market decline, etc.)" />
            </div>
          </div>

          <GLImpactPanel
            companyId={companyId}
            sourceDocType="FA_IMP"
            sourceDocId={null}
            previewRows={glPreviewRows}
            title="GL Impact — Asset Impairment"
          />

          <button onClick={submit} disabled={saving || !assetId}
            className="px-5 py-2 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {saving ? 'Recording…' : 'Record Impairment'}
          </button>
        </div>
      ) : (
        <div className="px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Asset #','Name','Date','Carrying Amt (₱)','Recoverable (₱)','Impairment Loss (₱)','JE','Notes'].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {history.length === 0 ? (
                  <tr><td colSpan={8} className="py-12 text-center text-gray-400">No impairment records</td></tr>
                ) : history.map(r => (
                  <tr key={r.id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{r.asset_number}</td>
                    <td className="px-3 py-2 text-gray-800 max-w-[140px] truncate">{r.asset_name}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{r.impairment_date}</td>
                    <td className="px-3 py-2 font-mono text-right text-gray-600">{fmt(r.carrying_amount_before)}</td>
                    <td className="px-3 py-2 font-mono text-right text-gray-600">{fmt(r.recoverable_amount)}</td>
                    <td className="px-3 py-2 font-mono text-right font-semibold text-red-700">{fmt(r.impairment_loss)}</td>
                    <td className="px-3 py-2 font-mono text-xs text-blue-600">{r.journal_entry_id ? r.journal_entry_id.slice(0, 8) + '…' : '—'}</td>
                    <td className="px-3 py-2 text-gray-500 max-w-[160px] truncate">{r.notes || '—'}</td>
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
