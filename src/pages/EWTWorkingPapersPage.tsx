import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

// ── Types ─────────────────────────────────────────────────────────────────────
type Status = 'draft' | 'final' | 'filed'

type Header = {
  id: string
  company_id: string
  period: string
  description: string | null
  status: Status
  created_at: string
  updated_at: string
}

type DBLine = {
  id: string
  header_id: string
  transaction_id: string | null
  reference: string | null
  amount: number
  remarks: string | null
}

type FormLine = {
  _key: string
  id?: string
  reference: string
  amount: number
  remarks: string
}

type FormData = {
  period: string
  description: string
  status: Status
}

// ── Constants ─────────────────────────────────────────────────────────────────
const EMPTY_FORM: FormData = { period: '', description: '', status: 'draft' }

const STATUS_LABELS: Record<Status, string> = {
  draft: 'Draft',
  final: 'Final',
  filed: 'Filed',
}

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const ro  = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

// ── Helpers ───────────────────────────────────────────────────────────────────
const MONTHS = ['January','February','March','April','May','June',
  'July','August','September','October','November','December']

const fmtPeriod = (d: string) => {
  if (!d) return '—'
  const [y, m] = d.split('-')
  return `${MONTHS[parseInt(m) - 1]} ${y}`
}

const fmtNum = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

let _keyCounter = 0
const nextKey = () => String(++_keyCounter)

// ── Status Badge ──────────────────────────────────────────────────────────────
function StatusBadge({ status }: { status: Status }) {
  const cls: Record<Status, string> = {
    draft: 'bg-gray-100 text-gray-600',
    final: 'bg-blue-50 text-blue-700',
    filed: 'bg-green-50 text-green-700',
  }
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls[status]}`}>
      {STATUS_LABELS[status]}
    </span>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────────
export default function EWTWorkingPapersPage() {
  const { companyId } = useAppCtx()

  const [headers, setHeaders] = useState<Header[]>([])
  const [loading, setLoading]  = useState(false)
  const [mode, setMode]        = useState<'list' | 'new' | 'edit' | 'view'>('list')
  const [editId, setEditId]    = useState<string | null>(null)
  const [form, setForm]        = useState<FormData>({ ...EMPTY_FORM })
  const [lines, setLines]      = useState<FormLine[]>([])
  const [saving, setSaving]    = useState(false)
  const [genMsg, setGenMsg]    = useState('')

  // List filters
  const [search,       setSearch]       = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | Status>('all')
  const [filterFrom,   setFilterFrom]   = useState('')
  const [filterTo,     setFilterTo]     = useState('')

  // ── Data fetching ──────────────────────────────────────────────────────────
  const loadHeaders = async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase
      .from('compliance_ewt_working_papers_headers')
      .select('*')
      .eq('company_id', companyId)
      .order('period', { ascending: false })
    setHeaders((data as Header[]) || [])
    setLoading(false)
  }

  useEffect(() => { loadHeaders() }, [companyId])

  const loadLines = async (headerId: string): Promise<FormLine[]> => {
    const { data } = await supabase
      .from('compliance_ewt_working_papers_lines')
      .select('*')
      .eq('header_id', headerId)
      .order('created_at')
    return ((data as DBLine[]) || []).map(l => ({
      _key: nextKey(),
      id: l.id,
      reference: l.reference || '',
      amount: Number(l.amount),
      remarks: l.remarks || '',
    }))
  }

  // ── Form helpers ───────────────────────────────────────────────────────────
  const set = (k: keyof FormData, v: string) => setForm(f => ({ ...f, [k]: v }))

  const openNew = () => {
    const today = new Date()
    const defaultPeriod = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-01`
    setForm({ ...EMPTY_FORM, period: defaultPeriod })
    setLines([])
    setEditId(null)
    setMode('new')
  }

  const openEdit = async (h: Header) => {
    setForm({ period: h.period, description: h.description || '', status: h.status })
    setLines(await loadLines(h.id))
    setEditId(h.id)
    setMode('edit')
  }

  const openView = async (h: Header) => {
    setForm({ period: h.period, description: h.description || '', status: h.status })
    setLines(await loadLines(h.id))
    setEditId(h.id)
    setMode('view')
  }

  const addLine = () => {
    setLines(ls => [...ls, { _key: nextKey(), reference: '', amount: 0, remarks: '' }])
  }

  const removeLine = (key: string) => setLines(ls => ls.filter(l => l._key !== key))

  const setLineField = (key: string, field: 'reference' | 'remarks', val: string) =>
    setLines(ls => ls.map(l => l._key === key ? { ...l, [field]: val } : l))

  // ── Save ───────────────────────────────────────────────────────────────────
  const handleSave = async () => {
    if (!companyId || !form.period) {
      alert('Cannot save.\nReason: Period is required.')
      return
    }
    setSaving(true)

    let headerId = editId

    if (!headerId) {
      const { data, error } = await supabase
        .from('compliance_ewt_working_papers_headers')
        .insert([{
          company_id: companyId,
          period: form.period,
          description: form.description || null,
          status: form.status,
        }])
        .select('id').single()
      if (error) {
        alert('Cannot save EWT Working Paper.\nReason: ' + (
          error.code === '23505'
            ? `A working paper for ${fmtPeriod(form.period)} already exists.`
            : error.message
        ))
        setSaving(false)
        return
      }
      headerId = data.id
    } else {
      const { error } = await supabase
        .from('compliance_ewt_working_papers_headers')
        .update({
          period: form.period,
          description: form.description || null,
          status: form.status,
        })
        .eq('id', headerId)
      if (error) {
        alert('Cannot update EWT Working Paper.\nReason: ' + error.message)
        setSaving(false)
        return
      }
    }

    // Remove deleted lines
    if (editId) {
      const keepIds = lines.filter(l => l.id).map(l => l.id!)
      const { data: dbLines } = await supabase
        .from('compliance_ewt_working_papers_lines')
        .select('id').eq('header_id', headerId)
      const toDelete = ((dbLines || []) as { id: string }[])
        .filter(dl => !keepIds.includes(dl.id)).map(dl => dl.id)
      if (toDelete.length > 0) {
        await supabase.from('compliance_ewt_working_papers_lines').delete().in('id', toDelete)
      }
    }

    // Upsert lines in order
    for (const l of lines) {
      if (l.id) {
        await supabase.from('compliance_ewt_working_papers_lines').update({
          reference: l.reference || null,
          amount: l.amount,
          remarks: l.remarks || null,
        }).eq('id', l.id)
      } else {
        await supabase.from('compliance_ewt_working_papers_lines').insert([{
          header_id: headerId,
          reference: l.reference || null,
          amount: l.amount,
          remarks: l.remarks || null,
        }])
      }
    }

    setSaving(false)
    loadHeaders()
    setMode('list')
  }

  // ── Generate ───────────────────────────────────────────────────────────────
  const handleGenerate = () => {
    setGenMsg('Generate complete — no ledger data available yet.')
    setTimeout(() => setGenMsg(''), 5000)
  }

  // ── Filtered list ──────────────────────────────────────────────────────────
  const filtered = headers.filter(h => {
    const q = search.toLowerCase()
    const matchSearch = !q ||
      fmtPeriod(h.period).toLowerCase().includes(q) ||
      (h.description || '').toLowerCase().includes(q)
    const matchStatus = filterStatus === 'all' || h.status === filterStatus
    const matchFrom   = !filterFrom || h.period >= filterFrom
    const matchTo     = !filterTo   || h.period <= filterTo
    return matchSearch && matchStatus && matchFrom && matchTo
  })

  const totalAmount = lines.reduce((s, l) => s + l.amount, 0)
  const isView = mode === 'view'

  // ── FORM VIEW ──────────────────────────────────────────────────────────────
  if (mode === 'new' || mode === 'edit' || mode === 'view') {
    return (
      <div className="max-w-5xl mx-auto space-y-5">
        {/* Header bar */}
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setMode('list')}
              className="text-xs text-gray-500 hover:text-gray-900 mb-1">
              ← EWT Working Papers
            </button>
            <h1 className="text-xl font-semibold text-gray-900">
              {isView ? 'EWT Working Paper' : editId ? 'Edit EWT Working Paper' : 'New EWT Working Paper'}
            </h1>
            <p className="text-sm text-gray-500 mt-0.5">
              Expanded Withholding Tax — {fmtPeriod(form.period) || 'No period selected'}
            </p>
          </div>
          <div className="flex gap-2">
            {isView ? (
              <>
                <button onClick={() => setMode('edit')}
                  className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
                  Edit
                </button>
                <button onClick={() => window.print()}
                  className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
                  Print
                </button>
                <button onClick={() => setMode('list')}
                  className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
                  Close
                </button>
              </>
            ) : (
              <>
                <button onClick={() => setMode('list')}
                  className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
                  Cancel
                </button>
                <button onClick={handleSave} disabled={saving}
                  className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
                  {saving ? 'Saving...' : editId ? 'Update' : 'Save'}
                </button>
              </>
            )}
          </div>
        </div>

        {/* Header fields */}
        <div className={sec}>
          <h2 className={hd}>Working Paper Details</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={lbl}>Schedule Period <span className="text-red-500">*</span></label>
              <input
                type="month"
                value={form.period ? form.period.slice(0, 7) : ''}
                onChange={e => set('period', e.target.value ? e.target.value + '-01' : '')}
                readOnly={isView}
                className={isView ? ro : inp}
              />
            </div>
            <div>
              <label className={lbl}>Status</label>
              {isView ? (
                <div className="mt-1.5"><StatusBadge status={form.status} /></div>
              ) : (
                <select value={form.status} onChange={e => set('status', e.target.value as Status)}
                  className={inp}>
                  <option value="draft">Draft</option>
                  <option value="final">Final</option>
                  <option value="filed">Filed</option>
                </select>
              )}
            </div>
            <div className="col-span-2">
              <label className={lbl}>Description</label>
              {isView ? (
                <textarea readOnly value={form.description || '—'} rows={2} className={ro} />
              ) : (
                <textarea
                  value={form.description}
                  onChange={e => set('description', e.target.value)}
                  rows={2}
                  placeholder="e.g. EWT Working Paper for June 2026 — Compensation, Professional Fees"
                  className={inp}
                />
              )}
            </div>
          </div>
        </div>

        {/* Lines table */}
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
            <h2 className={hd.replace('pb-2 border-b border-gray-100', '')}>Line Items</h2>
            {!isView && (
              <button onClick={addLine}
                className="text-xs bg-gray-900 text-white px-3 py-1.5 rounded-md hover:bg-gray-800">
                + Add Row
              </button>
            )}
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-200">
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide w-10">#</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Reference</th>
                  <th className="text-right px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide w-48">Amount</th>
                  <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Remarks</th>
                  {!isView && <th className="w-10" />}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {lines.length === 0 ? (
                  <tr>
                    <td colSpan={isView ? 4 : 5} className="text-center py-12 text-xs text-gray-400">
                      {isView
                        ? 'No line items on this working paper.'
                        : 'No lines yet. Click "+ Add Row" to begin, or use Generate to pull from ledger data.'}
                    </td>
                  </tr>
                ) : lines.map((l, i) => (
                  <tr key={l._key} className="hover:bg-gray-50/50">
                    <td className="px-4 py-2 text-xs text-gray-400">{i + 1}</td>
                    <td className="px-4 py-2">
                      {isView
                        ? <span className="text-sm text-gray-700">{l.reference || '—'}</span>
                        : <input
                            value={l.reference}
                            onChange={e => setLineField(l._key, 'reference', e.target.value)}
                            className="w-full border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900"
                            placeholder="Reference / Transaction ID"
                          />
                      }
                    </td>
                    <td className="px-4 py-2 text-right">
                      <span className="text-sm font-mono tabular-nums text-gray-700">
                        {fmtNum(l.amount)}
                      </span>
                    </td>
                    <td className="px-4 py-2">
                      {isView
                        ? <span className="text-sm text-gray-700">{l.remarks || '—'}</span>
                        : <input
                            value={l.remarks}
                            onChange={e => setLineField(l._key, 'remarks', e.target.value)}
                            className="w-full border border-gray-300 rounded px-2 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900"
                            placeholder="Notes"
                          />
                      }
                    </td>
                    {!isView && (
                      <td className="px-2 py-2 text-center">
                        <button onClick={() => removeLine(l._key)}
                          className="text-gray-300 hover:text-red-500 text-sm font-medium transition-colors"
                          aria-label="Remove line">✕</button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
              {lines.length > 0 && (
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr>
                    <td colSpan={2} className="px-4 py-2.5 text-xs font-semibold text-gray-600 uppercase tracking-wide">
                      Total — {lines.length} line{lines.length !== 1 ? 's' : ''}
                    </td>
                    <td className="px-4 py-2.5 text-right font-mono text-sm font-bold tabular-nums text-gray-900">
                      {fmtNum(totalAmount)}
                    </td>
                    <td colSpan={isView ? 1 : 2} />
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        </div>
      </div>
    )
  }

  // ── LIST VIEW ──────────────────────────────────────────────────────────────
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">EWT Working Papers</h1>
          <p className="text-sm text-gray-500 mt-0.5">Expanded Withholding Tax — Schedule &amp; Reconciliation</p>
        </div>
      </div>

      {/* Action bar */}
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-56 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search period or description..."
        />
        <input
          type="month"
          value={filterFrom ? filterFrom.slice(0, 7) : ''}
          onChange={e => setFilterFrom(e.target.value ? e.target.value + '-01' : '')}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
          title="From Period"
        />
        <span className="text-xs text-gray-400">to</span>
        <input
          type="month"
          value={filterTo ? filterTo.slice(0, 7) : ''}
          onChange={e => setFilterTo(e.target.value ? e.target.value + '-01' : '')}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
          title="To Period"
        />
        <select
          value={filterStatus}
          onChange={e => setFilterStatus(e.target.value as typeof filterStatus)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="all">All Status</option>
          <option value="draft">Draft</option>
          <option value="final">Final</option>
          <option value="filed">Filed</option>
        </select>
        <div className="ml-auto flex items-center gap-2">
          {genMsg && (
            <span className="text-xs text-blue-700 bg-blue-50 border border-blue-200 px-3 py-1.5 rounded-md">
              {genMsg}
            </span>
          )}
          <button onClick={handleGenerate}
            className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
            ⚡ Generate
          </button>
          <button className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
            ↑ Import
          </button>
          <button className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
            ↓ Export
          </button>
          <button onClick={openNew}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + New Working Paper
          </button>
        </div>
      </div>

      {/* Table */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(5)].map((_, i) => (
              <div key={i} className="px-4 py-3 flex gap-4 animate-pulse">
                <div className="h-3 bg-gray-100 rounded w-28" />
                <div className="h-3 bg-gray-100 rounded flex-1" />
                <div className="h-3 bg-gray-100 rounded w-16" />
              </div>
            ))}
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Period</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Description</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Last Updated</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={5} className="text-center py-16 text-gray-400">
                    <p className="text-base font-medium text-gray-500">No EWT Working Papers Found</p>
                    <p className="text-sm mt-1 text-gray-400">
                      {!companyId
                        ? 'Select a company from the context bar above.'
                        : 'Click "+ New Working Paper" to create the first schedule.'}
                    </p>
                  </td>
                </tr>
              ) : filtered.map((h, i) => (
                <tr key={h.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-medium text-gray-900">{fmtPeriod(h.period)}</td>
                  <td className="px-4 py-3 text-gray-600 max-w-xs truncate">{h.description || '—'}</td>
                  <td className="px-4 py-3"><StatusBadge status={h.status} /></td>
                  <td className="px-4 py-3 text-xs text-gray-400">
                    {new Date(h.updated_at).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' })}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <button onClick={() => openView(h)}
                        className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button>
                      <button onClick={() => openEdit(h)}
                        className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                      <button onClick={() => openView(h).then(() => window.print())}
                        className="text-xs text-gray-500 hover:text-gray-700 font-medium">Print</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {filtered.length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {filtered.length} of {headers.length} working paper{headers.length !== 1 ? 's' : ''}
          </div>
        )}
      </div>
    </div>
  )
}
