import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

type PendingEntry = {
  id: string
  asset_id: string
  asset_number: string
  asset_name: string
  category_name: string
  period_number: number
  entry_date: string
  depreciation_amount: number
  accumulated_depr_after: number
  net_book_value_after: number
}

const fmt = (n: number) => n?.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) ?? '0.00'

export default function DepreciationRunPage() {
  const { companyId } = useAppCtx()
  const [entries, setEntries] = useState<PendingEntry[]>([])
  const [cutoff, setCutoff] = useState(() => new Date().toISOString().slice(0, 10))
  const [loading, setLoading] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [posting, setPosting] = useState(false)
  const [progress, setProgress] = useState<{ done: number; total: number; errors: string[] } | null>(null)
  const [previewEntryId, setPreviewEntryId] = useState<string | null>(null)

  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    setSelected(new Set())
    setProgress(null)

    const { data } = await supabase
      .from('asset_depreciation_entries')
      .select(`
        id, asset_id, period_number, entry_date, depreciation_amount,
        accumulated_depr_after, net_book_value_after,
        fixed_assets!inner(
          asset_number, asset_name, company_id,
          fixed_asset_categories!inner(category_name)
        )
      `)
      .eq('fixed_assets.company_id', companyId)
      .eq('status', 'pending')
      .lte('entry_date', cutoff)
      .order('entry_date')
      .order('asset_id')

    const list = (data || []).map((d: any) => ({
      id: d.id,
      asset_id: d.asset_id,
      asset_number: d.fixed_assets?.asset_number ?? '',
      asset_name: d.fixed_assets?.asset_name ?? '',
      category_name: d.fixed_assets?.fixed_asset_categories?.category_name ?? '',
      period_number: d.period_number,
      entry_date: d.entry_date,
      depreciation_amount: Number(d.depreciation_amount),
      accumulated_depr_after: Number(d.accumulated_depr_after),
      net_book_value_after: Number(d.net_book_value_after),
    }))

    setEntries(list)
    setSelected(new Set(list.map(e => e.id)))
    setLoading(false)
  }, [companyId, cutoff])

  useEffect(() => { load() }, [load])

  const toggleAll = () => {
    if (selected.size === entries.length) setSelected(new Set())
    else setSelected(new Set(entries.map(e => e.id)))
  }

  const toggle = (id: string) => {
    setSelected(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const postSelected = async () => {
    const ids = [...selected]
    if (ids.length === 0) return
    setPosting(true)
    setProgress({ done: 0, total: ids.length, errors: [] })

    const errors: string[] = []
    for (let i = 0; i < ids.length; i++) {
      const { error: previewError } = await supabase.rpc('fn_preview_gl_impact', { p_source_doc_type: 'FA_DEPR', p_source_doc_id: ids[i] })
      if (previewError) {
        errors.push(`Entry ${ids[i].slice(0, 8)} preview: ${previewError.message}`)
        setProgress({ done: i + 1, total: ids.length, errors })
        continue
      }
      const { error: e } = await supabase.rpc('fn_post_depreciation_entry', { p_entry_id: ids[i] })
      if (e) errors.push(`Entry ${ids[i].slice(0, 8)}: ${e.message}`)
      setProgress({ done: i + 1, total: ids.length, errors })
    }

    setPosting(false)
    load()
  }

  const totalDepr = entries.filter(e => selected.has(e.id)).reduce((s, e) => s + e.depreciation_amount, 0)

  return (
    <LegacyTransactionWorkspace title="Depreciation Run" family="neutral" pattern="D" posting
      documentNo={cutoff} status={posting ? 'posting' : 'draft'} identity="Pending depreciation entries"
      financialFacts={[{ label: 'Selected Depreciation', value: fmt(totalDepr) }, { label: 'Selected Entries', value: selected.size }, { label: 'Available Entries', value: entries.length }, { label: 'Posting Errors', value: progress?.errors.length || 0 }]}
      contextFacts={[{ label: 'Cutoff Date', value: cutoff }, { label: 'Run State', value: posting ? 'Posting' : 'Ready' }, { label: 'Progress', value: progress && progress.total > 0 ? `${progress.done} / ${progress.total}` : 'Not started' }]}
      sourceDocType="FA_DEPR" sourceDocId={previewEntryId}
      actions={[
        { key: 'refresh', label: loading ? 'Refreshing…' : 'Refresh', onClick: load, disabled: loading },
        { key: 'post', label: posting ? `Posting ${progress?.done || 0}/${progress?.total || selected.size}…` : `Post ${selected.size} Entries`, onClick: postSelected, disabled: posting || selected.size === 0, variant: 'primary' },
      ]}
      headerFields={[
        { key: 'cutoff', label: 'Post Pending Up To', card: 0, content: <input type="date" value={cutoff} onChange={e => setCutoff(e.target.value)} className="pxl-input w-full" /> },
        { key: 'state', label: 'Run State', card: 0, content: <div className="pxl-readonly-field">{posting ? 'Posting' : 'Ready'}</div> },
        { key: 'basis', label: 'Posting Basis', card: 1, span: 2, content: <div className="pxl-readonly-field">Pending fixed-asset depreciation entries</div> },
        { key: 'scope', label: 'Selection', card: 2, span: 2, content: <div className="pxl-readonly-field">{selected.size} of {entries.length} entries</div> },
      ]}
      tabContent={{
        validation: progress ? <div className={`pxl-validation-message border ${progress.errors.length > 0 ? 'border-red-200 bg-red-50' : 'border-green-200 bg-green-50'}`}><p>{progress.done === progress.total ? 'Complete' : 'Posting'} ({progress.done}/{progress.total})</p>{progress.errors.map((entry, index) => <p key={index} className="text-red-600">{entry}</p>)}</div> : <div className="pxl-validation-message border border-gray-200">{selected.size ? `${selected.size} entries selected and ready.` : 'Select at least one pending entry.'}</div>,
        gl: previewEntryId ? <GLImpactPanel companyId={companyId} sourceDocType="FA_DEPR" sourceDocId={previewEntryId} previewRows={[]} /> : undefined,
      }}>
    <div>
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-3 py-2 border-b border-gray-100 flex items-center gap-3">
            <span className="text-xs text-gray-500 font-medium">{entries.length} pending entries</span>
            <span className="text-xs text-gray-400">|</span>
            <span className="text-xs text-gray-500">{selected.size} selected — Total: ₱ {fmt(totalDepr)}</span>
          </div>

          {loading ? (
            <div className="py-12 text-center text-xs text-gray-400">Loading pending entries…</div>
          ) : entries.length === 0 ? (
            <div className="py-12 text-center">
              <p className="text-sm font-medium text-gray-500">No pending depreciation entries</p>
              <p className="text-xs text-gray-400 mt-1">All assets are up to date as of {cutoff}</p>
            </div>
          ) : (
            <table className="pxl-data-grid w-full">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-3 py-2 w-8">
                    <input type="checkbox" checked={selected.size === entries.length && entries.length > 0} onChange={toggleAll}
                      className="rounded border-gray-300" />
                  </th>
                  {['Asset #','Name','Category','Period','Date','Depr. Amount (₱)','Accum. Depr (₱)','NBV After (₱)'].map(h => (
                    <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                  ))}
                  <th className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left">GL</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {entries.map(e => (
                  <tr key={e.id} className={`hover:bg-gray-50/60 ${selected.has(e.id) ? 'bg-blue-50/20' : ''}`}>
                    <td className="px-3 py-2">
                      <input type="checkbox" checked={selected.has(e.id)} onChange={() => toggle(e.id)}
                        className="rounded border-gray-300" />
                    </td>
                    <td className="px-3 py-2 font-mono font-semibold text-gray-900">{e.asset_number}</td>
                    <td className="px-3 py-2 text-gray-800 max-w-[140px] truncate">{e.asset_name}</td>
                    <td className="px-3 py-2 text-gray-500">{e.category_name}</td>
                    <td className="px-3 py-2 font-mono text-gray-600 text-right">{e.period_number}</td>
                    <td className="px-3 py-2 font-mono text-gray-600">{e.entry_date}</td>
                    <td className="px-3 py-2 font-mono text-right font-semibold text-gray-900">{fmt(e.depreciation_amount)}</td>
                    <td className="px-3 py-2 font-mono text-right text-gray-500">{fmt(e.accumulated_depr_after)}</td>
                    <td className="px-3 py-2 font-mono text-right text-gray-800">{fmt(e.net_book_value_after)}</td>
                    <td className="px-3 py-2">
                      <button onClick={() => setPreviewEntryId(e.id)} className="text-xs font-medium text-blue-700 hover:text-blue-900">Preview</button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="bg-gray-50 border-t border-gray-200">
                <tr>
                  <td colSpan={6} className="px-3 py-2 text-xs font-semibold text-right text-gray-500">Selected Total:</td>
                  <td className="px-3 py-2 font-mono font-bold text-right text-gray-900">₱ {fmt(totalDepr)}</td>
                  <td colSpan={3}></td>
                </tr>
              </tfoot>
            </table>
          )}
        </div>

    </div>
    </LegacyTransactionWorkspace>
  )
}
