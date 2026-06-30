import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

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
  const [tab, setTab] = useState<'new' | 'history'>('new')

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
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset Disposal</span>
        <div className="ml-auto flex gap-1">
          {(['new','history'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-3 py-1 rounded text-xs font-medium ${tab === t ? 'bg-gray-900 text-white' : 'text-gray-500 hover:text-gray-900'}`}>
              {t === 'new' ? 'New Disposal' : 'History'}
            </button>
          ))}
        </div>
      </div>

      {tab === 'new' ? (
        <div className="px-5 py-4 max-w-2xl space-y-4">
          {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
          {success && <div className="text-xs text-green-700 bg-green-50 border border-green-200 rounded px-3 py-2">{success}</div>}

          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Select Asset</p>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Asset *</label>
              <select value={form.asset_id} onChange={e => f('asset_id', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">— Select Asset —</option>
                {assets.map(a => <option key={a.id} value={a.id}>{a.asset_number} — {a.asset_name}</option>)}
              </select>
            </div>
            {selectedAsset && (
              <div className="bg-gray-50 rounded px-3 py-2 text-xs grid grid-cols-3 gap-3 font-mono">
                <div><p className="text-gray-400 text-[10px]">Cost</p><p className="font-semibold text-gray-900">₱ {fmt(selectedAsset.acquisition_cost)}</p></div>
                <div><p className="text-gray-400 text-[10px]">Accum. Depr</p><p className="font-semibold text-gray-600">₱ {fmt(selectedAsset.accum_depr)}</p></div>
                <div><p className="text-gray-400 text-[10px]">Net Book Value</p><p className="font-semibold text-blue-700">₱ {fmt(selectedAsset.nbv)}</p></div>
              </div>
            )}
          </div>

          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Disposal Details</p>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Disposal Date *</label>
                <input type="date" value={form.disposal_date} onChange={e => f('disposal_date', e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Disposal Type</label>
                <select value={form.disposal_type} onChange={e => f('disposal_type', e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  {DISPOSAL_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Proceeds Amount (₱)</label>
                <input type="number" min={0} step={0.01} value={form.proceeds_amount}
                  onChange={e => f('proceeds_amount', e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Proceeds Account (Cash/AR)</label>
                <select value={form.proceeds_account_id} onChange={e => f('proceeds_account_id', e.target.value)}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                  <option value="">— None —</option>
                  {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                </select>
              </div>
              <div className="col-span-2">
                <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                <textarea value={form.notes} onChange={e => f('notes', e.target.value)} rows={2}
                  className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 resize-none" />
              </div>
            </div>

            {selectedAsset && previewGainLoss !== null && (
              <div className={`rounded px-3 py-2 text-xs font-mono ${previewGainLoss >= 0 ? 'bg-green-50 text-green-800' : 'bg-red-50 text-red-800'}`}>
                {previewGainLoss >= 0
                  ? `Gain on Disposal: ₱ ${fmt(previewGainLoss)}`
                  : `Loss on Disposal: ₱ ${fmt(Math.abs(previewGainLoss))}`}
              </div>
            )}
          </div>

          <button onClick={submit} disabled={saving || !form.asset_id}
            className="px-5 py-2 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {saving ? 'Processing…' : 'Record Disposal'}
          </button>
        </div>
      ) : (
        <div className="px-5 py-4">
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Asset #','Name','Date','Type','Proceeds (₱)','NBV (₱)','Gain / (Loss) (₱)','JE'].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {history.length === 0 ? (
                  <tr><td colSpan={8} className="py-12 text-center text-gray-400 text-xs">No disposal records</td></tr>
                ) : history.map(d => (
                  <tr key={d.id} className="hover:bg-gray-50/60">
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{d.asset_number}</td>
                    <td className="px-3 py-2 text-gray-800 max-w-[160px] truncate">{d.asset_name}</td>
                    <td className="px-3 py-2 font-mono text-gray-500">{d.disposal_date}</td>
                    <td className="px-3 py-2 text-gray-600">{DISPOSAL_TYPES.find(t => t.value === d.disposal_type)?.label || d.disposal_type}</td>
                    <td className="px-3 py-2 text-right font-mono text-gray-800">{fmt(d.proceeds_amount)}</td>
                    <td className="px-3 py-2 text-right font-mono text-gray-600">{fmt(d.net_book_value)}</td>
                    <td className={`px-3 py-2 text-right font-mono font-semibold ${d.gain_loss_amount >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                      {d.gain_loss_amount >= 0 ? '' : '('}{fmt(Math.abs(d.gain_loss_amount))}{d.gain_loss_amount >= 0 ? '' : ')'}
                    </td>
                    <td className="px-3 py-2 font-mono text-xs text-blue-600">{d.journal_entry_id ? d.journal_entry_id.slice(0, 8) + '…' : '—'}</td>
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
