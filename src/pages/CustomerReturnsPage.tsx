import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { normalizePhTin } from '@/lib/philippines'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

// ── Types ─────────────────────────────────────────────────────────────────────
type Mode = 'list' | 'new'

type ReturnRecord = {
  id: string; cm_number: string; cm_date: string
  customer_name_snapshot: string; total_amount: number; status: string
  source_dr: string | null
}

type DR = {
  id: string; dr_number: string; date: string
  customer_id: string; customer_name_snapshot: string; customer_tin_snapshot: string | null
  sales_order_id: string | null
}

type VATCode = { id: string; vat_code: string; description: string; vat_classification: string; rate: number }
type ReasonCode = { id: string; code: string; description: string }

type ReturnLine = {
  dr_line_id: string; description: string; item_id: string | null
  quantity_delivered: number; quantity_returned: number; unit_price: number
  vat_code_id: string; vat_classification: string; vat_rate: number
  net_amount: number; vat_amount: number; total_amount: number
  revenue_account_id: string
}

// ── Helpers ───────────────────────────────────────────────────────────────────
const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const today = () => new Date().toISOString().split('T')[0]

function computeReturnLine(l: ReturnLine): ReturnLine {
  const qty = Math.min(Math.max(l.quantity_returned, 0), l.quantity_delivered)
  const net  = Math.round(qty * l.unit_price * 100) / 100
  const vat  = l.vat_classification === 'regular' ? Math.round(net * l.vat_rate) / 100 : 0
  return { ...l, quantity_returned: qty, net_amount: net, vat_amount: vat, total_amount: net + vat }
}

// ── Component ─────────────────────────────────────────────────────────────────
export default function CustomerReturnsPage() {
  const { companyId, branchId } = useAppCtx()
  const [mode, setMode] = useState<Mode>('list')

  // List state
  const [list, setList] = useState<ReturnRecord[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(0)
  const [totalCount, setTotalCount] = useState(0)
  const PAGE_SIZE = 30

  // Form state
  const [fDate, setFDate] = useState(today())
  const [fDR, setFDR] = useState<DR | null>(null)
  const [fReason, setFReason] = useState('')
  const [fRemarks, setFRemarks] = useState('')
  const [returnLines, setReturnLines] = useState<ReturnLine[]>([])

  // Reference data
  const [drs, setDRs] = useState<DR[]>([])
  const [drSearch, setDRSearch] = useState('')
  const [vatCodes, setVatCodes] = useState<VATCode[]>([])
  const [reasonCodes, setReasonCodes] = useState<ReasonCode[]>([])

  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const loadList = useCallback(async () => {
    if (!companyId) return
    setListLoading(true)
    const from = page * PAGE_SIZE, to = from + PAGE_SIZE - 1
    // Customer returns are CMs with a delivery receipt link in remarks/description
    let q = supabase.from('credit_memos')
      .select('id,cm_number,cm_date,customer_name_snapshot,total_amount,status,remarks', { count: 'exact' })
      .eq('company_id', companyId)
      .ilike('remarks', 'Customer Return%')
      .order('cm_date', { ascending: false })
      .range(from, to)
    if (search) q = q.or(`cm_number.ilike.%${search}%,customer_name_snapshot.ilike.%${search}%`)
    const { data, count } = await q
    setList((data || []).map((r: Record<string, unknown>) => ({
      id: r.id as string, cm_number: r.cm_number as string, cm_date: r.cm_date as string,
      customer_name_snapshot: r.customer_name_snapshot as string,
      total_amount: Number(r.total_amount), status: r.status as string,
      source_dr: r.remarks ? String(r.remarks).replace('Customer Return — DR: ', '') : null,
    })))
    setTotalCount(count || 0)
    setListLoading(false)
  }, [companyId, page, search])

  useEffect(() => { loadList() }, [loadList])

  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('vat_codes').select('id,vat_code,description,vat_classification,tax_codes(rate)').eq('is_active', true).order('vat_code'),
      supabase.from('ref_reason_codes').select('id,code,description').in('applies_to', ['credit_memo','both']).order('code'),
    ]).then(([vatR, rcR]) => {
      setVatCodes((vatR.data || []).map((v: Record<string, unknown>) => ({
        id: v.id as string, vat_code: v.vat_code as string, description: v.description as string,
        vat_classification: v.vat_classification as string,
        rate: ((v.tax_codes as Record<string, unknown>)?.rate as number) || 0,
      })))
      setReasonCodes(rcR.data as ReasonCode[] || [])
    })
  }, [companyId])

  const searchDRs = async (q: string) => {
    if (!companyId || q.length < 2) { setDRs([]); return }
    const { data } = await supabase.from('delivery_receipts')
      .select('id,dr_number,date:dr_date,customer_id,customer_name_snapshot,sales_order_id,customers(tin)')
      .eq('company_id', companyId).eq('status', 'delivered')
      .ilike('dr_number', `%${q}%`)
      .order('dr_date', { ascending: false }).limit(20)
    setDRs((data || []).map(d => ({
      id: d.id, dr_number: d.dr_number, date: d.date,
      customer_id: d.customer_id, customer_name_snapshot: d.customer_name_snapshot,
      customer_tin_snapshot: d.customers?.tin ? normalizePhTin(d.customers.tin) : null,
      sales_order_id: d.sales_order_id,
    })))
  }

  const selectDR = async (dr: DR) => {
    setFDR(dr); setDRs([])
    setReturnLines([])
    // Load DR lines. DR lines carry no price or accounts: unit price comes from
    // the fulfilled SO line, VAT/revenue defaults from the item master.
    const { data: drLines } = await supabase.from('delivery_receipt_lines')
      .select('id,line_number,item_id,description,quantity,uom_id,so_line:sales_order_lines(unit_price),item:items(default_sales_vat_id,sales_account_id)')
      .eq('dr_id', dr.id).order('line_number')
    if (!drLines) return
    const rl: ReturnLine[] = drLines.map(l => {
      const vatCodeId = l.item?.default_sales_vat_id || ''
      const vc = vatCodes.find(v => v.id === vatCodeId)
      return computeReturnLine({
        dr_line_id: l.id, description: l.description ?? '', item_id: l.item_id,
        quantity_delivered: Number(l.quantity), quantity_returned: 0,
        unit_price: Number(l.so_line?.unit_price ?? 0),
        vat_code_id: vatCodeId, vat_classification: vc?.vat_classification || 'exempt',
        vat_rate: vc?.rate || 0, net_amount: 0, vat_amount: 0, total_amount: 0,
        revenue_account_id: l.item?.sales_account_id || '',
      })
    })
    setReturnLines(rl)
  }

  const updateQty = (drLineId: string, qty: number) => {
    setReturnLines(prev => prev.map(l => l.dr_line_id === drLineId ? computeReturnLine({ ...l, quantity_returned: qty }) : l))
  }

  const save = async () => {
    if (!companyId || !fDR) { setError('Select a Delivery Receipt first.'); return }
    if (!fReason) { setError('Reason Code is required.'); return }
    const activeLines = returnLines.filter(l => l.quantity_returned > 0)
    if (activeLines.length === 0) { setError('Enter a return quantity for at least one line.'); return }
    setSaving(true); setError('')

    // Look up the SI for this DR via its sales order
    let invoiceId: string | null = null
    if (fDR.sales_order_id) {
      const { data: siRows } = await supabase.from('sales_invoices')
        .select('id').eq('company_id', companyId)
        .eq('customer_id', fDR.customer_id).eq('status', 'posted').limit(1)
      invoiceId = siRows?.[0]?.id || null
    }

    const header = {
      company_id: companyId, branch_id: branchId,
      customer_id: fDR.customer_id,
      customer_name_snapshot: fDR.customer_name_snapshot,
      customer_tin_snapshot: fDR.customer_tin_snapshot || '',
      invoice_id: invoiceId || '',
      cm_date: fDate, reason_code_id: fReason,
      remarks: `Customer Return — DR: ${fDR.dr_number}${fRemarks ? ' · ' + fRemarks : ''}`,
    }
    const linesPayload = activeLines.map(l => ({
      invoice_line_id: '', item_id: l.item_id || '',
      description: l.description,
      quantity: l.quantity_returned, unit_price: l.unit_price,
      vat_code_id: l.vat_code_id, revenue_account_id: l.revenue_account_id,
    }))

    const { error: rpcErr } = await supabase.rpc('fn_save_credit_memo', {
      p_cm_id: null!, p_header: header, p_lines: linesPayload, p_next_status: 'draft',
    })
    if (rpcErr) { setError(rpcErr.message); setSaving(false); return }

    setMode('list'); loadList(); setSaving(false)
  }

  const totals = {
    qty: returnLines.reduce((s, l) => s + l.quantity_returned, 0),
    net: returnLines.reduce((s, l) => s + l.net_amount, 0),
    vat: returnLines.reduce((s, l) => s + l.vat_amount, 0),
    total: returnLines.reduce((s, l) => s + l.total_amount, 0),
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full'
  const STATUS_COLOR: Record<string, string> = { draft: 'bg-gray-100 text-gray-600', approved: 'bg-blue-50 text-blue-700', applied: 'bg-green-50 text-green-700', cancelled: 'bg-red-50 text-red-600' }

  // ── List view ──────────────────────────────────────────────────────────────
  if (mode === 'list') {
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search CM#, customer…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {companyId ? (
            <button onClick={() => { setFDR(null); setDRSearch(''); setReturnLines([]); setMode('new') }}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Return
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Customer Returns.</div>
        ) : listLoading ? (
          <div className="divide-y divide-gray-100">{[...Array(5)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : list.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Customer Returns found</p>
            <p className="text-xs text-gray-400 mt-1">{search ? 'No records match.' : 'Create your first Customer Return.'}</p>
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['CM Number','Date','Customer','Source DR','Total','Status'].map(h => (
                      <th key={h} className={`px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-gray-500 whitespace-nowrap ${h === 'Total' ? 'text-right' : 'text-left'}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {list.map(r => (
                    <tr key={r.id} className="hover:bg-gray-50/50">
                      <td className="px-4 py-2.5 font-mono text-xs font-semibold text-gray-900">{r.cm_number}</td>
                      <td className="px-4 py-2.5 text-xs text-gray-600">{r.cm_date}</td>
                      <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[180px] truncate">{r.customer_name_snapshot}</td>
                      <td className="px-4 py-2.5 font-mono text-xs text-gray-500">{r.source_dr || '—'}</td>
                      <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(r.total_amount)}</td>
                      <td className="px-4 py-2.5">
                        <span className={`inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase ${STATUS_COLOR[r.status] || ''}`}>{r.status}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="px-5 py-3 border-t border-gray-100 flex items-center gap-3">
              <button onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0}
                className="px-2 py-1 rounded border border-gray-200 text-xs text-gray-600 disabled:opacity-40">Prev</button>
              <span className="text-xs text-gray-500">{page + 1} / {Math.max(1, Math.ceil(totalCount / PAGE_SIZE))}</span>
              <button onClick={() => setPage(p => p + 1)} disabled={(page + 1) * PAGE_SIZE >= totalCount}
                className="px-2 py-1 rounded border border-gray-200 text-xs text-gray-600 disabled:opacity-40">Next</button>
            </div>
          </>
        )}
      </div>
    )
  }

  // ── New Return form ────────────────────────────────────────────────────────
  return (
    <LegacyTransactionWorkspace title="Customer Return" family="sales" pattern="B" posting={false}
      status="draft" identity={fDR?.customer_name_snapshot}
      financialFacts={[{ label: 'Return Credit', value: fmt(totals.total) }, { label: 'Net Credit', value: fmt(totals.net) }, { label: 'VAT Credit', value: fmt(totals.vat) }, { label: 'Quantity Returned', value: totals.qty }]}
      taxFacts={[{ label: 'VAT Credit', value: fmt(totals.vat), hint: 'Tax reversal from returned lines' }]}
      contextFacts={[{ label: 'Customer', value: fDR?.customer_name_snapshot || 'Not selected' }, { label: 'Return Date', value: fDate }, { label: 'Reason', value: reasonCodes.find(reason => reason.id === fReason)?.description || 'Not selected' }]}
      relatedFacts={[{ label: 'Source Delivery Receipt', value: fDR?.dr_number || 'Not linked', hint: fDR ? 'Return source' : 'No receipt selected', to: '/delivery-receipts' }]}
      actions={[{ key: 'cancel', label: 'Cancel', onClick: () => setMode('list') }, { key: 'save', label: saving ? 'Saving…' : 'Save Return', onClick: save, disabled: saving, variant: 'primary' }]}
      headerFields={[
        { key: 'date', label: 'Return Date *', card: 0, content: <input type="date" value={fDate} onChange={e => setFDate(e.target.value)} className={`${inp} pxl-input`} /> },
        { key: 'number', label: 'Document Number', card: 0, content: <div className="pxl-readonly-field">Draft Credit Memo on save</div> },
        { key: 'customer', label: 'Customer', card: 1, span: 2, content: <div className="pxl-readonly-field">{fDR?.customer_name_snapshot || 'Select a delivery receipt'}</div> },
        { key: 'dr', label: 'Delivery Receipt *', card: 1, span: 2, content: <div className="relative"><input value={fDR ? `${fDR.dr_number} — ${fDR.customer_name_snapshot}` : drSearch} onChange={e => { setDRSearch(e.target.value); setFDR(null); searchDRs(e.target.value) }} placeholder="Type DR number to search…" className={`${inp} pxl-input`} />{drs.length > 0 && !fDR && <div className="absolute z-50 mt-1 max-h-48 w-full overflow-auto rounded border border-gray-200 bg-white shadow-lg">{drs.map(dr => <button key={dr.id} type="button" onClick={() => selectDR(dr)} className="w-full px-3 py-2 text-left text-xs hover:bg-gray-50"><span className="font-mono font-semibold">{dr.dr_number}</span><span className="ml-2">{dr.customer_name_snapshot}</span></button>)}</div>}</div> },
        { key: 'reason', label: 'Reason Code *', card: 2, span: 2, content: <select value={fReason} onChange={e => setFReason(e.target.value)} className={`${inp} pxl-input`}><option value="">Select reason…</option>{reasonCodes.map(r => <option key={r.id} value={r.id}>{r.code} — {r.description}</option>)}</select> },
        { key: 'remarks', label: 'Remarks', card: 2, span: 2, content: <input value={fRemarks} onChange={e => setFRemarks(e.target.value)} className={`${inp} pxl-input`} placeholder="Additional notes…" /> },
      ]}
      tabContent={{
        validation: error ? <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div> : undefined,
        financial: <div className="ml-auto w-full max-w-sm space-y-2 text-sm"><div className="flex justify-between"><span>Total Qty Returned</span><span className="font-mono">{totals.qty}</span></div><div className="flex justify-between"><span>Net Credit</span><span className="font-mono">{fmt(totals.net)}</span></div><div className="flex justify-between"><span>VAT Credit</span><span className="font-mono">{fmt(totals.vat)}</span></div><div className="flex justify-between border-t border-[var(--pxl-border-strong)] pt-2 font-bold"><span>Total Credit Memo</span><span className="font-mono">{fmt(totals.total)}</span></div></div>,
      }}
      onBack={() => setMode('list')} backLabel="Customer Returns">
    <div>
      <div>
        {returnLines.length > 0 && (
          <div>
            <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Return Quantities</div>
            <div className="overflow-x-auto">
              <table className="pxl-data-grid w-full text-sm">
                <thead className="border-b border-gray-200">
                  <tr>
                    {['Description','Delivered','Return Qty','Unit Price','Net','VAT','Total'].map(h => (
                      <th key={h} className={`px-2 py-2 text-[11px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap ${['Delivered','Return Qty','Unit Price','Net','VAT','Total'].includes(h) ? 'text-right' : ''}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {returnLines.map(l => (
                    <tr key={l.dr_line_id} className="hover:bg-gray-50/40">
                      <td className="px-2 py-2 text-xs text-gray-900">{l.description}</td>
                      <td className="px-2 py-2 text-right font-mono text-xs tabular-nums text-gray-500">{l.quantity_delivered}</td>
                      <td className="px-2 py-2">
                        <input type="number" value={l.quantity_returned} min="0" max={l.quantity_delivered} step="0.001"
                          onChange={e => updateQty(l.dr_line_id, Number(e.target.value))}
                          className="border border-gray-300 rounded px-1.5 py-1 text-xs w-20 text-right tabular-nums focus:outline-none focus:ring-1 focus:ring-gray-900" />
                      </td>
                      <td className="px-2 py-2 text-right font-mono text-xs tabular-nums text-gray-600">{fmt(l.unit_price)}</td>
                      <td className="px-2 py-2 text-right font-mono text-xs tabular-nums text-gray-700">{l.net_amount > 0 ? fmt(l.net_amount) : '—'}</td>
                      <td className="px-2 py-2 text-right font-mono text-xs tabular-nums text-blue-700">{l.vat_amount > 0 ? fmt(l.vat_amount) : '—'}</td>
                      <td className="px-2 py-2 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{l.total_amount > 0 ? fmt(l.total_amount) : '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {!fDR && (
          <div className="pxl-empty-state">
            Select a Delivery Receipt in Customer Information to load return lines.
          </div>
        )}
      </div>
    </div>
    </LegacyTransactionWorkspace>
  )
}
