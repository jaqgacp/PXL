import { useEffect, useMemo, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Registry = { master_key: string; display_name: string; scope: string; import_mode: string; notes: string | null }
type ImportResult = {
  valid?: boolean; status?: string; row_count?: number; valid_row_count?: number; error_count?: number
  insert_count?: number; update_count?: number; inserted_count?: number; updated_count?: number
  skipped_count?: number; batch_id?: string; errors?: unknown[]; rows?: unknown[]
}

const downloadJson = (filename: string, value: unknown) => {
  const url = URL.createObjectURL(new Blob([JSON.stringify(value, null, 2)], { type: 'application/json' }))
  const anchor = document.createElement('a'); anchor.href = url; anchor.download = filename; anchor.click()
  URL.revokeObjectURL(url)
}

export default function MasterDataImportPage() {
  const { companyId } = useAppCtx()
  const [registry, setRegistry] = useState<Registry[]>([])
  const [masterKey, setMasterKey] = useState('')
  const [jsonText, setJsonText] = useState('[]')
  const [preview, setPreview] = useState<ImportResult | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const selected = useMemo(() => registry.find(row => row.master_key === masterKey), [registry, masterKey])

  useEffect(() => {
    ;(supabase as any).from('master_data_import_registry')
      .select('master_key,display_name,scope,import_mode,notes').eq('import_mode', 'upsert').order('export_sequence')
      .then(({ data }: any) => { const rows = (data as Registry[]) || []; setRegistry(rows); if (rows[0]) setMasterKey(rows[0].master_key) })
  }, [])

  const rows = () => {
    const parsed = JSON.parse(jsonText)
    const value = Array.isArray(parsed) ? parsed : parsed?.rows
    if (!Array.isArray(value)) throw new Error('Import JSON must be an array, or an exported object with a rows array.')
    return value
  }

  const loadTemplate = async () => {
    if (!masterKey) return
    setBusy(true); setError('')
    const { data, error: rpcError } = await (supabase as any).rpc('fn_master_data_import_template', { p_master_key: masterKey })
    setBusy(false)
    if (rpcError) { setError(rpcError.message); return }
    downloadJson(`${masterKey}-template.json`, data)
  }

  const run = async (commit: boolean) => {
    if (!companyId || !masterKey) return
    let payload: unknown[]
    try { payload = rows() } catch (parseError: any) { setError(parseError.message); return }
    if (commit && (!preview?.valid || !confirm(`Commit ${payload.length} ${selected?.display_name || masterKey} row(s)? This writes governed master data.`))) return
    setBusy(true); setError('')
    const { data, error: rpcError } = await (supabase as any).rpc('fn_import_master_data', {
      p_company_id: companyId, p_master_key: masterKey, p_rows: payload,
      p_preview: !commit, p_idempotency_key: commit ? crypto.randomUUID() : null, p_options: {},
    })
    setBusy(false)
    if (rpcError) { setError(rpcError.message); return }
    setPreview(data as ImportResult)
  }

  const loadFile = async (file?: File) => {
    if (!file) return
    setJsonText(await file.text()); setPreview(null); setError('')
  }

  if (!companyId) return <div className="p-8 text-sm text-gray-500">Select a company before importing master data.</div>

  return <div className="space-y-5">
    <div><h1 className="text-xl font-semibold text-gray-900">Master Data Import</h1><p className="mt-1 text-sm text-gray-500">Preview-first access to the existing governed import framework. A commit is unavailable until the same payload validates.</p></div>
    {error && <div className="rounded border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
    <section className="rounded-lg border border-gray-200 bg-white p-5">
      <div className="grid gap-4 md:grid-cols-[minmax(0,1fr)_auto_auto]"><label className="text-xs font-medium text-gray-500">Master<select value={masterKey} onChange={event => { setMasterKey(event.target.value); setPreview(null) }} className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm">{registry.map(row => <option key={row.master_key} value={row.master_key}>{row.display_name}</option>)}</select></label><button onClick={loadTemplate} disabled={busy || !masterKey} className="self-end rounded border border-gray-300 px-3 py-2 text-sm disabled:opacity-50">Download schema</button><label className="self-end rounded border border-gray-300 px-3 py-2 text-center text-sm hover:bg-gray-50">Load JSON<input type="file" accept="application/json,.json" className="hidden" onChange={event => loadFile(event.target.files?.[0])} /></label></div>
      {selected && <p className="mt-3 text-xs text-gray-500">{selected.display_name} · {selected.scope} scope · {selected.notes}</p>}
      <label className="mt-4 block text-xs font-medium text-gray-500">Rows as JSON<textarea value={jsonText} onChange={event => { setJsonText(event.target.value); setPreview(null) }} spellCheck={false} className="mt-1 h-80 w-full rounded border border-gray-300 p-3 font-mono text-xs" /></label>
      <div className="mt-4 flex gap-2"><button onClick={() => run(false)} disabled={busy} className="rounded border border-gray-300 px-4 py-2 text-sm disabled:opacity-50">{busy ? 'Working…' : 'Validate preview'}</button><button onClick={() => run(true)} disabled={busy || !preview?.valid} className="rounded bg-gray-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-40">Commit import</button></div>
    </section>
    {preview && <section className={`rounded-lg border p-5 ${preview.valid || preview.status === 'imported' ? 'border-green-200 bg-green-50' : 'border-red-200 bg-red-50'}`}><h2 className="font-semibold text-gray-900">{preview.status === 'imported' ? 'Import committed' : preview.valid ? 'Preview valid' : 'Preview failed'}</h2><div className="mt-3 grid grid-cols-2 gap-3 text-sm sm:grid-cols-5"><Fact label="Rows" value={preview.row_count} /><Fact label="Valid" value={preview.valid_row_count} /><Fact label="Errors" value={preview.error_count} /><Fact label="Inserts" value={preview.inserted_count ?? preview.insert_count} /><Fact label="Updates" value={preview.updated_count ?? preview.update_count} /></div>{Boolean(preview.error_count) && <pre className="mt-4 max-h-72 overflow-auto rounded bg-white/70 p-3 text-xs">{JSON.stringify(preview.errors || preview.rows, null, 2)}</pre>}{preview.batch_id && <div className="mt-3 text-xs text-gray-500">Batch {preview.batch_id}</div>}</section>}
  </div>
}

function Fact({ label, value }: { label: string; value?: number }) {
  return <div><div className="text-xs text-gray-500">{label}</div><div className="font-mono text-lg font-semibold">{value ?? 0}</div></div>
}
