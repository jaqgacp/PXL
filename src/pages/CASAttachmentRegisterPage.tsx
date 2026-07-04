import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type DocType = 'receipt' | 'contract' | 'permit' | 'invoice_scan' | 'id_document' | 'other'

type Row = {
  id: string
  document_type: DocType
  reference_no: string | null
  source_doc_type: string | null
  source_doc_ref: string | null
  file_name: string
  description: string | null
  remarks: string | null
  uploaded_at: string
}

type FormData = Omit<Row, 'id' | 'uploaded_at'>

const DOC_LABELS: Record<DocType, string> = { receipt: 'Receipt', contract: 'Contract', permit: 'Permit', invoice_scan: 'Invoice Scan', id_document: 'ID Document', other: 'Other' }
const EMPTY_FORM: FormData = { document_type: 'receipt', reference_no: '', source_doc_type: '', source_doc_ref: '', file_name: '', description: '', remarks: '' }
const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'

export default function CASAttachmentRegisterPage() {
  const { companyId } = useAppCtx()
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(false)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState<FormData>({ ...EMPTY_FORM })
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState('')

  const load = async () => {
    if (!companyId) return
    setLoading(true)
    const { data } = await supabase.from('cas_attachment_register').select('*').eq('company_id', companyId).order('uploaded_at', { ascending: false })
    setRows((data as Row[]) || [])
    setLoading(false)
  }

  // eslint-disable-next-line react-hooks/exhaustive-deps -- loader is re-created each render; refetch is intentionally keyed to this dep list, and user actions call the loader directly
  useEffect(() => { load() }, [companyId])

  const set = (k: keyof FormData, v: string) => setForm(f => ({ ...f, [k]: v }))

  const handleSave = async () => {
    if (!companyId || !form.file_name) { alert('Cannot save.\nReason: File name is required.'); return }
    setSaving(true)
    const { error } = await supabase.from('cas_attachment_register').insert([{
      company_id: companyId, document_type: form.document_type,
      reference_no: form.reference_no || null, source_doc_type: form.source_doc_type || null, source_doc_ref: form.source_doc_ref || null,
      file_name: form.file_name, description: form.description || null, remarks: form.remarks || null,
    }])
    if (error) { alert('Cannot save.\nReason: ' + error.message); setSaving(false); return }
    setSaving(false); setForm({ ...EMPTY_FORM }); setShowForm(false); load()
  }

  const filtered = rows.filter(r => !search || r.file_name.toLowerCase().includes(search.toLowerCase()) || (r.reference_no || '').toLowerCase().includes(search.toLowerCase()) || (r.source_doc_ref || '').toLowerCase().includes(search.toLowerCase()))

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Attachment Register</h1>
          <p className="text-sm text-gray-500 mt-0.5">Log of supporting documents — receipts, contracts, permits, scans</p>
        </div>
        <button onClick={() => setShowForm(true)} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">+ Log Attachment</button>
      </div>

      {showForm && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg p-6 w-full max-w-lg space-y-4">
            <h3 className="text-sm font-semibold text-gray-900">Log New Attachment</h3>
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>Document Type</label><select value={form.document_type} onChange={e => set('document_type', e.target.value)} className={inp}>{Object.entries(DOC_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></div>
              <div><label className={lbl}>Reference No.</label><input value={form.reference_no || ''} onChange={e => set('reference_no', e.target.value)} className={inp} /></div>
              <div><label className={lbl}>Source Document Type</label><input value={form.source_doc_type || ''} onChange={e => set('source_doc_type', e.target.value)} placeholder="e.g. Sales Invoice" className={inp} /></div>
              <div><label className={lbl}>Source Document Ref.</label><input value={form.source_doc_ref || ''} onChange={e => set('source_doc_ref', e.target.value)} placeholder="e.g. SI-2026-0001" className={inp} /></div>
              <div className="col-span-2"><label className={lbl}>File Name <span className="text-red-500">*</span></label><input value={form.file_name} onChange={e => set('file_name', e.target.value)} className={inp} /></div>
              <div className="col-span-2"><label className={lbl}>Description</label><input value={form.description || ''} onChange={e => set('description', e.target.value)} className={inp} /></div>
              <div className="col-span-2"><label className={lbl}>Remarks</label><textarea value={form.remarks || ''} onChange={e => set('remarks', e.target.value)} rows={2} className={inp} /></div>
            </div>
            <div className="flex justify-end gap-2">
              <button onClick={() => { setShowForm(false); setForm({ ...EMPTY_FORM }) }} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
              <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">{saving ? 'Saving...' : 'Save'}</button>
            </div>
          </div>
        </div>
      )}

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3">
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search file name or reference..." className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-64" />
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Uploaded</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">File Name</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Source Document</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-gray-500 uppercase tracking-wide">Description</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr><td colSpan={5} className="text-center py-16 text-gray-400">{!companyId ? 'Select a company from the context bar above.' : 'No attachments logged yet.'}</td></tr>
              ) : filtered.map(r => (
                <tr key={r.id} className="border-b border-gray-100 hover:bg-gray-50">
                  <td className="px-4 py-2.5 text-xs text-gray-500">{new Date(r.uploaded_at).toLocaleDateString('en-PH')}</td>
                  <td className="px-4 py-2.5 text-gray-700">{DOC_LABELS[r.document_type]}</td>
                  <td className="px-4 py-2.5 text-gray-700">{r.file_name}</td>
                  <td className="px-4 py-2.5 text-gray-500">{r.source_doc_type ? `${r.source_doc_type} — ${r.source_doc_ref || ''}` : '—'}</td>
                  <td className="px-4 py-2.5 text-gray-600 max-w-xs truncate">{r.description || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
