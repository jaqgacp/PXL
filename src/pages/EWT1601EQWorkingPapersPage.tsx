import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Status = 'draft' | 'final' | 'filed'

type Header = { id: string; company_id: string; period_year: number; period_quarter: number; description: string | null; status: Status; created_at: string; updated_at: string }
type DBLine = { id: string; header_id: string; reference: string | null; amount: number; remarks: string | null }
type FormLine = { _key: string; id?: string; reference: string; amount: number; remarks: string }
type FormData = { period_year: number; period_quarter: number; description: string; status: Status }

const now = new Date()
const EMPTY_FORM: FormData = { period_year: now.getFullYear(), period_quarter: Math.floor(now.getMonth() / 3) + 1, description: '', status: 'draft' }
const STATUS_LABELS: Record<Status, string> = { draft: 'Draft', final: 'Final', filed: 'Filed' }

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

const fmtQuarter = (y: number, q: number) => `Q${q} ${y}`
const fmtNum = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

let _keyCounter = 0
const nextKey = () => String(++_keyCounter)

function StatusBadge({ status }: { status: Status }) {
  const cls: Record<Status, string> = { draft: 'bg-gray-100 text-gray-600', final: 'bg-blue-50 text-blue-700', filed: 'bg-green-50 text-green-700' }
  return <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>{STATUS_LABELS[status]}</span>
}

export default function EWT1601EQWorkingPapersPage() {
  const { companyId } = useAppCtx()
  const [headers, setHeaders] = useState<Header[]>([])
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState<FormData>({ ...EMPTY_FORM })
  const [lines, setLines] = useState<FormLine[]>([])
  const [saving, setSaving] = useState(false)

  const loadHeaders = async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('compliance_1601eq_working_papers_headers').select('*').eq('company_id', companyId)
      .order('period_year', { ascending: false }).order('period_quarter', { ascending: false })
    setHeaders((data as Header[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { loadHeaders() }, [companyId])

  const loadLines = async (headerId: string): Promise<FormLine[]> => {
    const { data } = await supabase.from('compliance_1601eq_working_papers_lines').select('*').eq('header_id', headerId).order('created_at')
    return ((data as DBLine[]) || []).map(l => ({ _key: nextKey(), id: l.id, reference: l.reference || '', amount: Number(l.amount), remarks: l.remarks || '' }))
  }

  const set = (k: keyof FormData, v: string | number) => setForm(f => ({ ...f, [k]: v }))
  const openNew = () => { setForm({ ...EMPTY_FORM }); setLines([]); setEditId(null); setMode('new') }
  const openEdit = async (h: Header) => { setForm({ period_year: h.period_year, period_quarter: h.period_quarter, description: h.description || '', status: h.status }); setLines(await loadLines(h.id)); setEditId(h.id); setMode('edit') }
  const openView = async (h: Header) => { setForm({ period_year: h.period_year, period_quarter: h.period_quarter, description: h.description || '', status: h.status }); setLines(await loadLines(h.id)); setEditId(h.id); setMode('view') }
  const addLine = () => setLines(ls => [...ls, { _key: nextKey(), reference: '', amount: 0, remarks: '' }])
  const removeLine = (key: string) => setLines(ls => ls.filter(l => l._key !== key))
  const setLineField = (key: string, field: 'reference' | 'remarks', val: string) => setLines(ls => ls.map(l => l._key === key ? { ...l, [field]: val } : l))

  const handleSave = async () => {
    if (!companyId) { alert('Cannot save.\nReason: Select a company first.'); return }
    setSaving(true)
    let headerId = editId

    if (!headerId) {
      const { data, error } = await supabase.from('compliance_1601eq_working_papers_headers')
        .insert([{ company_id: companyId, period_year: form.period_year, period_quarter: form.period_quarter, description: form.description || null, status: form.status }])
        .select('id').single()
      if (error) { alert('Cannot save.\nReason: ' + (error.code === '23505' ? `A working paper for ${fmtQuarter(form.period_year, form.period_quarter)} already exists.` : error.message)); setSaving(false); return }
      headerId = data.id
    } else {
      const { error } = await supabase.from('compliance_1601eq_working_papers_headers')
        .update({ period_year: form.period_year, period_quarter: form.period_quarter, description: form.description || null, status: form.status }).eq('id', headerId)
      if (error) { alert('Cannot update.\nReason: ' + error.message); setSaving(false); return }
    }

    if (editId) {
      const keepIds = lines.filter(l => l.id).map(l => l.id!)
      const { data: dbLines } = await supabase.from('compliance_1601eq_working_papers_lines').select('id').eq('header_id', headerId)
      const toDelete = ((dbLines || []) as { id: string }[]).filter(dl => !keepIds.includes(dl.id)).map(dl => dl.id)
      if (toDelete.length > 0) await supabase.from('compliance_1601eq_working_papers_lines').delete().in('id', toDelete)
    }

    for (const l of lines) {
      if (l.id) await supabase.from('compliance_1601eq_working_papers_lines').update({ reference: l.reference || null, amount: l.amount, remarks: l.remarks || null }).eq('id', l.id)
      else await supabase.from('compliance_1601eq_working_papers_lines').insert([{ header_id: headerId, reference: l.reference || null, amount: l.amount, remarks: l.remarks || null }])
    }

    setSaving(false); loadHeaders(); setMode('list')
  }

  const totalAmount = lines.reduce((s, l) => s + l.amount, 0)
  const isView = mode === 'view'
  const years = Array.from({ length: 6 }, (_, i) => now.getFullYear() - 4 + i)

  if (mode === 'new' || mode === 'edit' || mode === 'view') {
    return (
      <div className="max-w-5xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← 1601EQ Working Papers</button>
            <h1 className="text-xl font-semibold text-gray-900">{isView ? '1601EQ Working Paper' : editId ? 'Edit Working Paper' : 'New Working Paper'}</h1>
            <p className="text-sm text-gray-500 mt-0.5">Expanded Withholding Tax — {fmtQuarter(form.period_year, form.period_quarter)}</p>
          </div>
          <div className="flex gap-2">
            {isView ? (
              <>
                <button onClick={() => setMode('edit')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Edit</button>
                <button onClick={() => window.print()} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Print</button>
                <button onClick={() => setMode('list')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Close</button>
              </>
            ) : (
              <>
                <button onClick={() => setMode('list')} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
                <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving...' : editId ? 'Update' : 'Save'}</button>
              </>
            )}
          </div>
        </div>

        <div className={sec}>
          <h2 className={hd}>Working Paper Details</h2>
          <div className="grid grid-cols-3 gap-4">
            <div><label className={lbl}>Year</label>{isView ? <div className={ro}>{form.period_year}</div> : <select value={form.period_year} onChange={e => set('period_year', Number(e.target.value))} className={inp}>{years.map(y => <option key={y} value={y}>{y}</option>)}</select>}</div>
            <div><label className={lbl}>Quarter</label>{isView ? <div className={ro}>Q{form.period_quarter}</div> : <select value={form.period_quarter} onChange={e => set('period_quarter', Number(e.target.value))} className={inp}>{[1, 2, 3, 4].map(q => <option key={q} value={q}>Q{q}</option>)}</select>}</div>
            <div><label className={lbl}>Status</label>{isView ? <div className="mt-1.5"><StatusBadge status={form.status} /></div> : <select value={form.status} onChange={e => set('status', e.target.value)} className={inp}><option value="draft">Draft</option><option value="final">Final</option><option value="filed">Filed</option></select>}</div>
            <div className="col-span-3"><label className={lbl}>Description</label>{isView ? <textarea readOnly value={form.description || '—'} rows={2} className={ro} /> : <textarea value={form.description} onChange={e => set('description', e.target.value)} rows={2} placeholder="e.g. 1601EQ Working Paper for Q1 2026" className={inp} />}</div>
          </div>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
            <h2 className={hd.replace('pb-2 border-b border-gray-100', '')}>Line Items</h2>
            {!isView && <button onClick={addLine} className="text-xs bg-gray-900 text-white px-3 py-1.5 rounded-md hover:bg-gray-800">+ Add Row</button>}
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide w-10">#</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Reference</th>
                <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide w-48">Amount</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Remarks</th>
                {!isView && <th className="w-10" />}
              </tr></thead>
              <tbody className="divide-y divide-gray-100">
                {lines.length === 0 ? (
                  <tr><td colSpan={isView ? 4 : 5} className="text-center py-12 text-xs text-gray-400">{isView ? 'No line items.' : 'No lines yet. Click "+ Add Row" to begin.'}</td></tr>
                ) : lines.map((l, i) => (
                  <tr key={l._key} className="hover:bg-gray-50/50">
                    <td className="px-4 py-2 text-xs text-gray-400">{i + 1}</td>
                    <td className="px-4 py-2">{isView ? <span className="text-sm text-gray-700">{l.reference || '—'}</span> : <input value={l.reference} onChange={e => setLineField(l._key, 'reference', e.target.value)} className="w-full border border-gray-300 rounded px-2 py-1.5 text-sm" placeholder="Reference" />}</td>
                    <td className="px-4 py-2 text-right"><span className="text-sm font-mono tabular-nums text-gray-700">{fmtNum(l.amount)}</span></td>
                    <td className="px-4 py-2">{isView ? <span className="text-sm text-gray-700">{l.remarks || '—'}</span> : <input value={l.remarks} onChange={e => setLineField(l._key, 'remarks', e.target.value)} className="w-full border border-gray-300 rounded px-2 py-1.5 text-sm" placeholder="Notes" />}</td>
                    {!isView && <td className="px-2 py-2 text-center"><button onClick={() => removeLine(l._key)} className="text-gray-300 hover:text-red-500 text-sm font-medium" aria-label="Remove line">✕</button></td>}
                  </tr>
                ))}
              </tbody>
              {lines.length > 0 && (
                <tfoot className="border-t-2 border-gray-300 bg-gray-50"><tr>
                  <td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">Total — {lines.length} line{lines.length !== 1 ? 's' : ''}</td>
                  <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">{fmtNum(totalAmount)}</td>
                  <td colSpan={isView ? 1 : 2} />
                </tr></tfoot>
              )}
            </table>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div><h1 className="text-xl font-semibold text-gray-900">1601EQ Working Papers</h1><p className="text-sm text-gray-500 mt-0.5">Quarterly Expanded Withholding Tax — Schedule &amp; Reconciliation</p></div>
        <button onClick={openNew} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ New Working Paper</button>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">{[...Array(5)].map((_, i) => <div key={i} className="px-4 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-28" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Quarter</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Description</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Last Updated</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {headers.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400"><p className="text-base font-medium text-gray-500">No Working Papers Found</p><p className="text-sm mt-1 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'Click "+ New Working Paper" to create the first schedule.'}</p></td></tr>
              ) : headers.map((h, i) => (
                <tr key={h.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtQuarter(h.period_year, h.period_quarter)}</td>
                  <td className="px-4 py-3 text-gray-600 max-w-xs truncate">{h.description || '—'}</td>
                  <td className="px-4 py-3"><StatusBadge status={h.status} /></td>
                  <td className="px-4 py-3 text-xs text-gray-400">{new Date(h.updated_at).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })}</td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2"><button onClick={() => openView(h)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button><button onClick={() => openEdit(h)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button></div></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
