import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { StatusBadge, AmountCell, DateCell } from '@/components/ui/shared'

type PVRow = {
  id: string; company_id: string; voucher_number: string; voucher_date: string
  supplier_name_snapshot: string; supplier_tin_snapshot: string | null
  reference_number: string | null; check_number: string | null; check_date: string | null
  total_amount: number; total_ewt: number; status: string
  date_released: string | null; date_cleared: string | null
  remarks: string | null
}

type ActionModal = { pv: PVRow; action: 'released' | 'cleared' | 'stale' } | null

const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

const STATUS_COLORS: Record<string, string> = {
  draft: 'draft', posted: 'approved', released: 'warning',
  cleared: 'posted', stale: 'error', cancelled: 'error',
}

export default function PaymentMonitoringPage() {
  const { companyId } = useAppCtx()
  const [vouchers, setVouchers] = useState<PVRow[]>([])
  const [loading, setLoading] = useState(false)
  const [fStatus, setFStatus] = useState('posted')
  const [fSearch, setFSearch] = useState('')
  const [modal, setModal] = useState<ActionModal>(null)
  const [modalDate, setModalDate] = useState(today())
  const [modalRemarks, setModalRemarks] = useState('')
  const [saving, setSaving] = useState(false)

  const loadVouchers = useCallback(async () => {
    if (!companyId) return
    setLoading(true)
    let q = supabase.from('payment_vouchers').select('id,company_id,voucher_number,voucher_date,supplier_name_snapshot,supplier_tin_snapshot,reference_number,check_number,check_date,total_amount,total_ewt,status,date_released,date_cleared,remarks')
      .eq('company_id', companyId).neq('status', 'draft').neq('status', 'cancelled').order('voucher_date', { ascending: false })
    if (fStatus) q = q.eq('status', fStatus)
    if (fSearch) q = q.or(`voucher_number.ilike.%${fSearch}%,supplier_name_snapshot.ilike.%${fSearch}%,check_number.ilike.%${fSearch}%`)
    const { data } = await q
    setVouchers(data as PVRow[] || [])
    setLoading(false)
  }, [companyId, fStatus, fSearch])

  useEffect(() => { if (companyId) loadVouchers() }, [loadVouchers, companyId])

  const openModal = (pv: PVRow, action: 'released' | 'cleared' | 'stale') => {
    setModal({ pv, action })
    setModalDate(today())
    setModalRemarks('')
  }

  const submitAction = async () => {
    if (!modal) return
    setSaving(true)
    const { error: e } = await supabase.rpc('fn_update_payment_tracking', {
      p_voucher_id: modal.pv.id,
      p_action: modal.action,
      p_date: modal.action !== 'stale' ? modalDate : null,
      p_remarks: modalRemarks || null,
    })
    if (e) { alert(e.message); setSaving(false); return }
    setModal(null); loadVouchers(); setSaving(false)
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900'

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-gray-900">Payment Monitoring</h2>
      </div>

      <div className="flex gap-2">
        <input placeholder="Search voucher, supplier, check…" value={fSearch} onChange={e => setFSearch(e.target.value)} className={inp + ' w-60'} />
        <select value={fStatus} onChange={e => setFStatus(e.target.value)} className={inp}>
          <option value="">All (excl. draft)</option>
          <option value="posted">Posted</option>
          <option value="released">Released</option>
          <option value="cleared">Cleared</option>
          <option value="stale">Stale</option>
        </select>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {loading ? <div className="p-8 text-center text-sm text-gray-400">Loading…</div> : vouchers.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-400">No payment vouchers found.</div>
        ) : (
          <table className="w-full text-xs">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                {['PV Date','PV Number','Supplier','Check / Ref #','Amount','EWT','Status','Released','Cleared','Actions'].map(h => (
                  <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {vouchers.map(pv => (
                <tr key={pv.id} className="hover:bg-gray-50">
                  <td className="px-3 py-2"><DateCell date={pv.voucher_date} /></td>
                  <td className="px-3 py-2 font-mono font-medium text-gray-900">{pv.voucher_number}</td>
                  <td className="px-3 py-2 text-gray-700 max-w-[150px] truncate">{pv.supplier_name_snapshot}</td>
                  <td className="px-3 py-2 font-mono text-gray-500">{pv.check_number || pv.reference_number || '—'}</td>
                  <td className="px-3 py-2 text-right"><AmountCell amount={pv.total_amount} /></td>
                  <td className="px-3 py-2 text-right font-mono text-gray-500">{pv.total_ewt > 0 ? fmt(pv.total_ewt) : '—'}</td>
                  <td className="px-3 py-2"><StatusBadge status={STATUS_COLORS[pv.status] || 'draft'} label={pv.status} /></td>
                  <td className="px-3 py-2 text-gray-500">{pv.date_released ? <DateCell date={pv.date_released} /> : '—'}</td>
                  <td className="px-3 py-2 text-gray-500">{pv.date_cleared ? <DateCell date={pv.date_cleared} /> : '—'}</td>
                  <td className="px-3 py-2">
                    <div className="flex gap-2">
                      {pv.status === 'posted' && <button onClick={() => openModal(pv, 'released')} className="text-orange-600 hover:text-orange-800">Release</button>}
                      {pv.status === 'released' && <button onClick={() => openModal(pv, 'cleared')} className="text-green-600 hover:text-green-800">Clear</button>}
                      {['posted','released'].includes(pv.status) && <button onClick={() => openModal(pv, 'stale')} className="text-gray-400 hover:text-gray-600">Stale</button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Action Modal */}
      {modal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg border border-gray-200 shadow-xl p-6 w-96 space-y-4">
            <h3 className="text-sm font-semibold text-gray-900 capitalize">Mark as {modal.action}</h3>
            <p className="text-xs text-gray-600">Payment Voucher: <span className="font-mono font-medium">{modal.pv.voucher_number}</span></p>
            <p className="text-xs text-gray-600">Supplier: {modal.pv.supplier_name_snapshot}</p>
            <p className="text-xs text-gray-600">Amount: {fmt(modal.pv.total_amount)}</p>
            {modal.action !== 'stale' && (
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">{modal.action === 'released' ? 'Date Released' : 'Date Cleared'}</label>
                <input type="date" value={modalDate} onChange={e => setModalDate(e.target.value)} className={inp + ' w-full'} />
              </div>
            )}
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Remarks (optional)</label>
              <input type="text" value={modalRemarks} onChange={e => setModalRemarks(e.target.value)} className={inp + ' w-full'} placeholder="Notes…" />
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button onClick={() => setModal(null)} className="px-3 py-1.5 text-sm border border-gray-300 rounded-md hover:bg-gray-50">Cancel</button>
              <button onClick={submitAction} disabled={saving} className="px-3 py-1.5 text-sm bg-gray-900 text-white rounded-md hover:bg-gray-700 disabled:opacity-50">
                {saving ? 'Saving…' : `Confirm ${modal.action}`}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
