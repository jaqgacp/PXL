import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

// ── Types ─────────────────────────────────────────────────────────────────────
type TrackingStatus = 'pending' | 'received' | 'claimed'

type Line2307 = {
  receipt_line_id: string
  receipt_id: string
  receipt_number: string
  receipt_date: string
  customer_name: string
  customer_tin: string
  customer_id: string | null
  cwt_amount: number
  atc_code_id: string | null
  atc_code: string | null
  tracking_id: string | null
  tracking_status: TrackingStatus | null
  date_received: string | null
  period_covered: string | null
  tracking_atc_code_id: string | null
  remarks: string | null
}

type ATCCode = { id: string; atc_code: string; description: string; tax_rate: number }

// ── Helpers ───────────────────────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)

const QUARTERS = ['Q1-2024','Q2-2024','Q3-2024','Q4-2024','Q1-2025','Q2-2025','Q3-2025','Q4-2025','Q1-2026','Q2-2026','Q3-2026','Q4-2026']

function StatusBadge2307({ status }: { status: TrackingStatus | null }) {
  if (!status || status === 'pending') {
    return <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-red-50 text-red-700">Pending 2307</span>
  }
  if (status === 'received') {
    return <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-amber-50 text-amber-700">Received</span>
  }
  return <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-green-50 text-green-700">Claimed</span>
}

// ── Page ──────────────────────────────────────────────────────────────────────
export default function Form2307ReceivedPage() {
  const { companyId } = useAppCtx()

  const [lines, setLines]       = useState<Line2307[]>([])
  const [atcCodes, setAtcCodes] = useState<ATCCode[]>([])
  const [loading, setLoading]   = useState(false)

  // Filters
  const [search,       setSearch]       = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | TrackingStatus>('all')
  const [filterQuarter, setFilterQuarter] = useState('')

  // Modal state
  const [modalLine,     setModalLine]     = useState<Line2307 | null>(null)
  const [mDateReceived, setMDateReceived] = useState('')
  const [mAtcCodeId,    setMAtcCodeId]    = useState('')
  const [mPeriod,       setMPeriod]       = useState('')
  const [mFileRef,      setMFileRef]      = useState('')
  const [mRemarks,      setMRemarks]      = useState('')
  const [mSaving,       setMSaving]       = useState(false)
  const [mError,        setMError]        = useState('')

  // ── Load data ──────────────────────────────────────────────────────────────
  const load = useCallback(async () => {
    if (!companyId) return
    setLoading(true)

    // Load receipts for this company (exclude cancelled)
    const { data: receipts } = await supabase
      .from('receipts')
      .select('id,receipt_number,receipt_date,customer_name_snapshot,customer_tin_snapshot,customer_id')
      .eq('company_id', companyId)
      .in('status', ['posted', 'bounced'])
      .order('receipt_date', { ascending: false })

    // Load ATC codes
    const { data: atcs } = await supabase
      .from('ref_atc_codes')
      .select('id,atc_code,description,tax_rate')
      .eq('is_active', true)
      .order('atc_code')
    setAtcCodes((atcs as ATCCode[]) || [])

    const receiptIds = (receipts || []).map(r => r.id)
    if (receiptIds.length === 0) { setLines([]); setLoading(false); return }

    // Load receipt lines with CWT > 0
    const { data: rls } = await supabase
      .from('receipt_lines')
      .select('id,receipt_id,cwt_amount,atc_code_id')
      .in('receipt_id', receiptIds)
      .gt('cwt_amount', 0)

    const rlIds = (rls || []).map(l => l.id)

    // Load 2307 tracking records
    const { data: tracking } = rlIds.length > 0
      ? await supabase.from('form_2307_tracking').select('*').in('receipt_line_id', rlIds)
      : { data: [] }

    // Build lookup maps
    const receiptMap = Object.fromEntries((receipts || []).map(r => [r.id, r]))
    const trackingMap = Object.fromEntries((tracking || []).map(t => [t.receipt_line_id, t]))
    const atcMap = Object.fromEntries((atcs || []).map(a => [a.id, a as ATCCode]))

    const joined: Line2307[] = (rls || []).map(l => {
      const r = receiptMap[l.receipt_id]
      const t = trackingMap[l.id]
      const atc = atcMap[l.atc_code_id || '']
      return {
        receipt_line_id: l.id,
        receipt_id: l.receipt_id,
        receipt_number: r?.receipt_number || '—',
        receipt_date: r?.receipt_date || '',
        customer_name: r?.customer_name_snapshot || '—',
        customer_tin: r?.customer_tin_snapshot || '—',
        customer_id: r?.customer_id || null,
        cwt_amount: Number(l.cwt_amount),
        atc_code_id: l.atc_code_id || null,
        atc_code: atc?.atc_code || null,
        tracking_id: t?.id || null,
        tracking_status: (t?.status as TrackingStatus) || null,
        date_received: t?.date_received || null,
        period_covered: t?.period_covered || null,
        tracking_atc_code_id: t?.atc_code_id || null,
        remarks: t?.remarks || null,
      }
    })

    setLines(joined.sort((a, b) => b.receipt_date.localeCompare(a.receipt_date)))
    setLoading(false)
  }, [companyId])

  useEffect(() => { load() }, [load])

  // ── Open modal ─────────────────────────────────────────────────────────────
  const openMarkReceived = (l: Line2307) => {
    setModalLine(l)
    setMDateReceived(l.date_received || new Date().toISOString().split('T')[0])
    setMAtcCodeId(l.tracking_atc_code_id || l.atc_code_id || '')
    setMPeriod(l.period_covered || '')
    setMFileRef('')
    setMRemarks(l.remarks || '')
    setMError('')
  }

  const closeModal = () => { setModalLine(null); setMError('') }

  const handleMarkReceived = async () => {
    if (!modalLine || !companyId) return
    if (!mDateReceived) { setMError('Date Received is required.'); return }
    if (!mAtcCodeId)    { setMError('ATC Code is required.'); return }
    if (!mPeriod)       { setMError('Period Covered is required.'); return }
    setMSaving(true); setMError('')

    const payload = {
      company_id: companyId,
      receipt_line_id: modalLine.receipt_line_id,
      customer_id: modalLine.customer_id,
      cwt_amount_booked: modalLine.cwt_amount,
      status: 'received' as TrackingStatus,
      date_received: mDateReceived,
      atc_code_id: mAtcCodeId,
      period_covered: mPeriod,
      file_url: mFileRef || null,
      remarks: mRemarks || null,
    }

    let error
    if (modalLine.tracking_id) {
      ;({ error } = await supabase
        .from('form_2307_tracking')
        .update({ ...payload, status: modalLine.tracking_status === 'claimed' ? 'claimed' : 'received' })
        .eq('id', modalLine.tracking_id))
    } else {
      ;({ error } = await supabase.from('form_2307_tracking').insert([payload]))
    }

    if (error) {
      setMError('Cannot save.\nReason: ' + error.message)
      setMSaving(false)
      return
    }
    setMSaving(false)
    closeModal()
    load()
  }

  const handleMarkClaimed = async (l: Line2307) => {
    if (!l.tracking_id) return
    await supabase.from('form_2307_tracking').update({ status: 'claimed' }).eq('id', l.tracking_id)
    load()
  }

  // ── Filtered list ──────────────────────────────────────────────────────────
  const filtered = lines.filter(l => {
    const q = search.toLowerCase()
    const matchSearch = !q ||
      l.receipt_number.toLowerCase().includes(q) ||
      l.customer_name.toLowerCase().includes(q) ||
      (l.atc_code || '').toLowerCase().includes(q)
    const matchStatus = filterStatus === 'all' ||
      (filterStatus === 'pending' && !l.tracking_status) ||
      l.tracking_status === filterStatus
    const matchQuarter = !filterQuarter || l.period_covered === filterQuarter
    return matchSearch && matchStatus && matchQuarter
  })

  const pendingCount  = lines.filter(l => !l.tracking_status || l.tracking_status === 'pending').length
  const receivedCount = lines.filter(l => l.tracking_status === 'received').length
  const claimedCount  = lines.filter(l => l.tracking_status === 'claimed').length

  const inp = 'border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
  const minp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
  const mlbl = 'block text-xs font-medium text-gray-500 mb-1'

  return (
    <div className="space-y-4">
      {/* Page header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">2307 Received Review</h1>
          <p className="text-sm text-gray-500 mt-0.5">Track BIR Form 2307 receipt from customers with withheld CWT</p>
        </div>
      </div>

      {/* KPI strip */}
      {lines.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg grid grid-cols-3 divide-x divide-gray-200">
          <div className="px-5 py-3">
            <div className="text-[11px] font-medium text-gray-400 uppercase tracking-wide">Pending 2307</div>
            <div className="text-xl font-bold font-mono tabular-nums text-red-600 mt-0.5">{pendingCount}</div>
          </div>
          <div className="px-5 py-3">
            <div className="text-[11px] font-medium text-gray-400 uppercase tracking-wide">Received</div>
            <div className="text-xl font-bold font-mono tabular-nums text-amber-600 mt-0.5">{receivedCount}</div>
          </div>
          <div className="px-5 py-3">
            <div className="text-[11px] font-medium text-gray-400 uppercase tracking-wide">Claimed</div>
            <div className="text-xl font-bold font-mono tabular-nums text-green-700 mt-0.5">{claimedCount}</div>
          </div>
        </div>
      )}

      {/* Action bar */}
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input
          value={search}
          onChange={e => setSearch(e.target.value)}
          className={`${inp} w-60`}
          placeholder="Search customer or receipt…"
        />
        <select value={filterStatus} onChange={e => setFilterStatus(e.target.value as typeof filterStatus)} className={inp}>
          <option value="all">All Status</option>
          <option value="pending">Pending 2307</option>
          <option value="received">Received</option>
          <option value="claimed">Claimed</option>
        </select>
        <select value={filterQuarter} onChange={e => setFilterQuarter(e.target.value)} className={inp}>
          <option value="">All Quarters</option>
          {QUARTERS.map(q => <option key={q} value={q}>{q}</option>)}
        </select>
        <div className="ml-auto">
          <button className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
            ↓ Export Missing
          </button>
        </div>
      </div>

      {/* Table */}
      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? (
          <div className="divide-y divide-gray-100">
            {[...Array(6)].map((_, i) => (
              <div key={i} className="px-4 py-3 flex gap-4 animate-pulse">
                <div className="h-3 bg-gray-100 rounded w-24" />
                <div className="h-3 bg-gray-100 rounded w-32" />
                <div className="h-3 bg-gray-100 rounded flex-1" />
              </div>
            ))}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm" style={{ minWidth: 1000 }}>
              <thead>
                <tr className="bg-gray-50 border-b border-gray-200">
                  {['Date','Receipt No.','Customer','TIN','ATC Code','CWT Amount','Period','Status','Actions'].map(h => (
                    <th key={h} className={`px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap
                      ${h === 'CWT Amount' ? 'text-right' : 'text-left'}`}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {filtered.length === 0 ? (
                  <tr>
                    <td colSpan={9} className="text-center py-16 text-gray-400">
                      <p className="text-base font-medium text-gray-500">No CWT Receipts Found</p>
                      <p className="text-sm mt-1 text-gray-400">
                        {!companyId
                          ? 'Select a company from the context bar above.'
                          : 'No posted receipts with CWT withheld exist for this company.'}
                      </p>
                    </td>
                  </tr>
                ) : filtered.map((l, i) => (
                  <tr key={l.receipt_line_id}
                    className={`border-b border-gray-100 hover:bg-gray-50/50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/30' : ''}`}>
                    <td className="px-4 py-2.5 text-xs text-gray-500 whitespace-nowrap">
                      {l.receipt_date || '—'}
                    </td>
                    <td className="px-4 py-2.5 font-mono text-xs font-semibold text-gray-900 whitespace-nowrap">
                      {l.receipt_number}
                    </td>
                    <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[180px] truncate">
                      {l.customer_name}
                    </td>
                    <td className="px-4 py-2.5 font-mono text-xs text-gray-500 whitespace-nowrap">
                      {l.customer_tin || '—'}
                    </td>
                    <td className="px-4 py-2.5">
                      {l.atc_code ? (
                        <span className="font-mono text-xs text-gray-700 bg-gray-100 px-1.5 py-0.5 rounded">{l.atc_code}</span>
                      ) : (
                        <span className="text-xs text-gray-400 italic">Not set</span>
                      )}
                    </td>
                    <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">
                      {fmt(l.cwt_amount)}
                    </td>
                    <td className="px-4 py-2.5 text-xs text-gray-600">
                      {l.period_covered || (l.tracking_status ? '—' : '')}
                    </td>
                    <td className="px-4 py-2.5">
                      <StatusBadge2307 status={l.tracking_status} />
                    </td>
                    <td className="px-4 py-2.5">
                      <div className="flex items-center gap-2">
                        {(!l.tracking_status || l.tracking_status === 'pending') && (
                          <button onClick={() => openMarkReceived(l)}
                            className="text-xs text-blue-600 hover:text-blue-800 font-medium whitespace-nowrap">
                            Mark Received
                          </button>
                        )}
                        {l.tracking_status === 'received' && (
                          <>
                            <button onClick={() => openMarkReceived(l)}
                              className="text-xs text-gray-500 hover:text-gray-700 font-medium">Edit</button>
                            <button onClick={() => handleMarkClaimed(l)}
                              className="text-xs text-green-600 hover:text-green-800 font-medium whitespace-nowrap">
                              Mark Claimed
                            </button>
                          </>
                        )}
                        {l.tracking_status === 'claimed' && (
                          <button onClick={() => openMarkReceived(l)}
                            className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {filtered.length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {filtered.length} of {lines.length} CWT receipt line{lines.length !== 1 ? 's' : ''}
            {' '}·{' '}Total CWT: ₱{fmt(filtered.reduce((s, l) => s + l.cwt_amount, 0))}
          </div>
        )}
      </div>

      {/* Mark Received Modal */}
      {modalLine && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40" onClick={closeModal} />
          <div className="relative bg-white rounded-lg shadow-xl border border-gray-200 w-full max-w-md p-6 z-10">
            <div className="mb-4">
              <h2 className="text-sm font-semibold text-gray-900">Mark 2307 as Received</h2>
              <p className="text-xs text-gray-500 mt-0.5">
                {modalLine.receipt_number} · {modalLine.customer_name} · ₱{fmt(modalLine.cwt_amount)} CWT
              </p>
            </div>

            <div className="space-y-3">
              <div>
                <label className={mlbl}>Date Received <span className="text-red-500">*</span></label>
                <input type="date" value={mDateReceived} onChange={e => setMDateReceived(e.target.value)} className={minp} />
              </div>
              <div>
                <label className={mlbl}>ATC Code <span className="text-red-500">*</span></label>
                <select value={mAtcCodeId} onChange={e => setMAtcCodeId(e.target.value)} className={minp}>
                  <option value="">Select ATC Code…</option>
                  {atcCodes.map(a => (
                    <option key={a.id} value={a.id}>
                      {a.atc_code} — {a.description} ({a.tax_rate}%)
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className={mlbl}>Period Covered <span className="text-red-500">*</span></label>
                <select value={mPeriod} onChange={e => setMPeriod(e.target.value)} className={minp}>
                  <option value="">Select Quarter…</option>
                  {QUARTERS.map(q => <option key={q} value={q}>{q}</option>)}
                </select>
              </div>
              <div>
                <label className={mlbl}>File Reference <span className="text-gray-400 font-normal">(optional)</span></label>
                <input
                  value={mFileRef}
                  onChange={e => setMFileRef(e.target.value)}
                  className={minp}
                  placeholder="File name, Google Drive link, or DMS reference"
                />
              </div>
              <div>
                <label className={mlbl}>Remarks <span className="text-gray-400 font-normal">(optional)</span></label>
                <textarea
                  value={mRemarks}
                  onChange={e => setMRemarks(e.target.value)}
                  rows={2}
                  className={minp}
                  placeholder="Note any amount discrepancies or conditions"
                />
              </div>
            </div>

            {mError && (
              <p className="mt-3 text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{mError}</p>
            )}

            <div className="mt-5 flex justify-end gap-2">
              <button onClick={closeModal}
                className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
                Cancel
              </button>
              <button onClick={handleMarkReceived} disabled={mSaving}
                className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
                {mSaving ? 'Saving…' : 'Confirm Received'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
