import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

// ── Types ─────────────────────────────────────────────────────────────────────
type Mode = 'list' | 'new'

type CashSale = {
  id: string; si_number: string; date: string
  customer_name_snapshot: string; customer_tin_snapshot: string | null
  total_amount: number; total_vat_amount: number
  receipt_number: string | null; posted_at: string | null
}

type Customer    = { id: string; registered_name: string; tin: string; address: string | null }
type VATCode     = { id: string; vat_code: string; description: string; vat_classification: string; rate: number }
type COAAccount  = { id: string; account_code: string; account_name: string }
type PaymentMode = { id: string; name: string }
type Item        = { id: string; item_code: string; item_name: string; unit_price: number; vat_code_id: string | null }

type Line = {
  _key: string; item_id: string; description: string; quantity: number
  unit_price: number; discount_amount: number; vat_code_id: string
  vat_classification: string; vat_rate: number
  net_amount: number; vat_amount: number; total_amount: number
  revenue_account_id: string
}

// ── Helpers ───────────────────────────────────────────────────────────────────
const fmt = (n: number) => new Intl.NumberFormat('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
const uid = () => Math.random().toString(36).slice(2)
const today = () => new Date().toISOString().split('T')[0]

const newLine = (): Line => ({
  _key: uid(), item_id: '', description: '', quantity: 1, unit_price: 0,
  discount_amount: 0, vat_code_id: '', vat_classification: 'regular', vat_rate: 12,
  net_amount: 0, vat_amount: 0, total_amount: 0, revenue_account_id: '',
})

function computeLine(l: Line): Line {
  const net = Math.max(l.quantity * l.unit_price - l.discount_amount, 0)
  const vat = l.vat_classification === 'regular' ? Math.round(net * l.vat_rate) / 100 : 0
  return { ...l, net_amount: Math.round(net * 100) / 100, vat_amount: Math.round(vat * 100) / 100, total_amount: Math.round((net + vat) * 100) / 100 }
}

// ── Component ─────────────────────────────────────────────────────────────────
export default function CashSalesPage() {
  const { companyId, branchId } = useAppCtx()
  const [mode, setMode] = useState<Mode>('list')

  // List state
  const [list, setList] = useState<CashSale[]>([])
  const [listLoading, setListLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(0)
  const [totalCount, setTotalCount] = useState(0)
  const PAGE_SIZE = 30

  // Form state
  const [fDate, setFDate] = useState(today())
  const [fBranch] = useState('')
  const [fCustomer, setFCustomer] = useState('')
  const [fCustomerName, setFCustomerName] = useState('')
  const [fCustomerTIN, setFCustomerTIN] = useState('')
  const [fCustomerAddr, setFCustomerAddr] = useState('')
  const [fPaymentMode, setFPaymentMode] = useState('')
  const [fBankAccount, setFBankAccount] = useState('')
  const [fCWT, setFCWT] = useState(0)
  const [fCwtAtc, setFCwtAtc] = useState('')
  const [atcCodes, setAtcCodes] = useState<{ id: string; code: string; description: string; rate: number }[]>([])
  const [fReference, setFReference] = useState('')
  const [fMemo, setFMemo] = useState('')
  const [lines, setLines] = useState<Line[]>([newLine()])

  // Reference data
  const [customers, setCustomers] = useState<Customer[]>([])
  const [vatCodes, setVatCodes] = useState<VATCode[]>([])
  const [accounts, setAccounts] = useState<COAAccount[]>([])
  const [bankAccounts, setBankAccounts] = useState<COAAccount[]>([])
  const [paymentModes, setPaymentModes] = useState<PaymentMode[]>([])
  const [items, setItems] = useState<Item[]>([])

  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const loadList = useCallback(async () => {
    if (!companyId) return
    setListLoading(true)
    const from = page * PAGE_SIZE, to = from + PAGE_SIZE - 1
    let q = supabase.from('sales_invoices')
      .select(`id,si_number,date,customer_name_snapshot,customer_tin_snapshot,total_amount,total_vat_amount,posted_at,
        receipts!inner(receipt_number)`, { count: 'exact' })
      .eq('company_id', companyId).eq('is_cash_sale', true).eq('status', 'posted')
      .order('date', { ascending: false }).order('si_number', { ascending: false })
      .range(from, to)
    if (search) q = q.or(`si_number.ilike.%${search}%,customer_name_snapshot.ilike.%${search}%`)
    const { data, count } = await q
    // Flatten receipt_number from join
    const rows = (data || []).map((r: Record<string, unknown>) => {
      const rec = Array.isArray(r.receipts) ? r.receipts[0] : r.receipts
      return { ...r, receipt_number: (rec as Record<string, unknown>)?.receipt_number || null } as CashSale
    })
    setList(rows)
    setTotalCount(count || 0)
    setListLoading(false)
  }, [companyId, page, search])

  useEffect(() => { loadList() }, [loadList])

  useEffect(() => {
    if (!companyId) return
    Promise.all([
      supabase.from('customers').select('id,registered_name,tin,address').eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('vat_codes').select('id,vat_code,description,vat_classification,tax_codes(rate)').eq('is_active', true).order('vat_code'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('account_type', 'revenue').eq('is_postable', true).eq('is_active', true).order('account_code'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('account_type', 'asset').eq('is_postable', true).eq('is_active', true).order('account_code'),
      supabase.from('ref_payment_modes').select('id,name').eq('is_active', true).order('sort_order'),
      supabase.from('items').select('id,item_code,item_name,unit_price,vat_code_id').eq('company_id', companyId).eq('is_active', true).order('item_name'),
      supabase.from('atc_codes').select('id,code,description,rate').eq('is_active', true).eq('tax_category', 'ewt').order('code'),
    ]).then(([custR, vatR, accR, bankR, pmR, itemR, atcR]) => {
      setCustomers(custR.data as Customer[] || [])
      setVatCodes((vatR.data || []).map((v: Record<string, unknown>) => ({
        id: v.id as string, vat_code: v.vat_code as string, description: v.description as string,
        vat_classification: v.vat_classification as string,
        rate: ((v.tax_codes as Record<string, unknown>)?.rate as number) || 0,
      })))
      setAccounts(accR.data as COAAccount[] || [])
      setBankAccounts(bankR.data as COAAccount[] || [])
      setPaymentModes(pmR.data as PaymentMode[] || [])
      setItems(itemR.data as Item[] || [])
      setAtcCodes(atcR.data as { id: string; code: string; description: string; rate: number }[] || [])
    })
  }, [companyId])

  const selectCustomer = (cid: string) => {
    setFCustomer(cid)
    const c = customers.find(x => x.id === cid)
    if (c) { setFCustomerName(c.registered_name); setFCustomerTIN(c.tin || ''); setFCustomerAddr(c.address || '') }
  }

  const updateLine = (key: string, patch: Partial<Line>) => {
    setLines(prev => prev.map(l => {
      if (l._key !== key) return l
      const merged = { ...l, ...patch }
      if (patch.vat_code_id !== undefined) {
        const vc = vatCodes.find(v => v.id === patch.vat_code_id)
        merged.vat_classification = vc?.vat_classification || 'exempt'
        merged.vat_rate = vc?.rate || 0
      }
      if (patch.item_id) {
        const it = items.find(i => i.id === patch.item_id)
        if (it) {
          merged.description = it.item_name
          merged.unit_price  = Number(it.unit_price)
          if (it.vat_code_id) {
            const vc = vatCodes.find(v => v.id === it.vat_code_id)
            merged.vat_code_id = it.vat_code_id
            merged.vat_classification = vc?.vat_classification || 'exempt'
            merged.vat_rate = vc?.rate || 0
          }
        }
      }
      return computeLine(merged)
    }))
  }

  const totals = {
    net: lines.reduce((s, l) => s + l.net_amount, 0),
    vat: lines.reduce((s, l) => s + l.vat_amount, 0),
    total: lines.reduce((s, l) => s + l.total_amount, 0),
  }

  const save = async () => {
    if (!companyId || !fCustomer) { setError('Customer is required.'); return }
    if (lines.every(l => !l.description.trim())) { setError('At least one line is required.'); return }
    setSaving(true); setError('')
    const header = {
      company_id: companyId, branch_id: fBranch || branchId,
      customer_id: fCustomer, customer_name_snapshot: fCustomerName,
      customer_tin_snapshot: fCustomerTIN, customer_address_snapshot: fCustomerAddr,
      date: fDate, payment_mode_id: fPaymentMode || '',
      bank_account_id: fBankAccount || '', reference: fReference, memo: fMemo,
      cwt_atc_id: fCwtAtc || '',
    }
    if (fCWT > 0 && !fCwtAtc) { setError('Select the CWT ATC code when a CWT amount is entered.'); setSaving(false); return }
    const linesPayload = lines.filter(l => l.description.trim()).map(l => ({
      item_id: l.item_id, description: l.description, quantity: l.quantity,
      unit_price: l.unit_price, discount_amount: l.discount_amount,
      vat_code_id: l.vat_code_id, revenue_account_id: l.revenue_account_id,
    }))
    const { data, error: rpcErr } = await supabase.rpc('fn_save_cash_sale', {
      p_header: header, p_lines: linesPayload, p_cwt_amount: fCWT,
    })
    if (rpcErr) { setError(rpcErr.message); setSaving(false); return }
    const result = data as { si_number: string; receipt_number: string }
    alert(`Cash Sale posted.\nSI: ${result.si_number}\nOR: ${result.receipt_number}`)
    setMode('list')
    loadList()
    setSaving(false)
  }

  const inp = 'border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-full'
  const th  = 'px-2 py-2 text-[11px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap'
  const td  = 'px-2 py-1.5 align-top'

  // ── List view ──────────────────────────────────────────────────────────────
  if (mode === 'list') {
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap">
          <input value={search} onChange={e => { setSearch(e.target.value); setPage(0) }}
            placeholder="Search SI#, customer…"
            className="border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 w-56" />
          <div className="flex-1" />
          <span className="text-xs text-gray-400">{totalCount.toLocaleString()} records</span>
          {companyId ? (
            <button onClick={() => { setLines([newLine()]); setMode('new') }}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
              New Cash Sale
            </button>
          ) : <span className="text-xs text-gray-400">Select a company first</span>}
        </div>

        {!companyId ? (
          <div className="py-16 text-center text-sm text-gray-400">Select a company to view Cash Sales.</div>
        ) : listLoading ? (
          <div className="divide-y divide-gray-100">{[...Array(6)].map((_, i) => <div key={i} className="px-5 py-3 flex gap-4 animate-pulse"><div className="h-3 bg-gray-100 rounded w-24" /><div className="h-3 bg-gray-100 rounded flex-1" /></div>)}</div>
        ) : list.length === 0 ? (
          <div className="py-20 text-center">
            <p className="text-sm font-medium text-gray-500">No Cash Sales found</p>
            <p className="text-xs text-gray-400 mt-1">{search ? 'No records match the search.' : 'Create your first Cash Sale.'}</p>
          </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    {['Date','SI Number','OR Number','Customer','TIN','Total','VAT'].map(h => (
                      <th key={h} className={`${th} ${['Total','VAT'].includes(h) ? 'text-right' : ''}`}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {list.map(cs => (
                    <tr key={cs.id} className="hover:bg-gray-50/50">
                      <td className="px-4 py-2.5 text-xs text-gray-600 whitespace-nowrap">{cs.date}</td>
                      <td className="px-4 py-2.5 font-mono text-xs font-semibold text-gray-900">{cs.si_number}</td>
                      <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{cs.receipt_number || '—'}</td>
                      <td className="px-4 py-2.5 text-xs text-gray-900 max-w-[180px] truncate">{cs.customer_name_snapshot}</td>
                      <td className="px-4 py-2.5 font-mono text-xs text-gray-500">{cs.customer_tin_snapshot || '—'}</td>
                      <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums font-semibold text-gray-900">{fmt(Number(cs.total_amount))}</td>
                      <td className="px-4 py-2.5 text-right font-mono text-xs tabular-nums text-blue-700">{cs.total_vat_amount ? fmt(Number(cs.total_vat_amount)) : '—'}</td>
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

  // ── New Cash Sale form ─────────────────────────────────────────────────────
  return (
    <div>
      {/* Toolbar */}
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3 flex-wrap sticky top-0 z-10">
        <button onClick={() => setMode('list')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900">
          <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M15 18l-6-6 6-6" /></svg>
          Cash Sales
        </button>
        <span className="text-gray-300">|</span>
        <span className="text-sm font-semibold text-gray-900">New Cash Sale</span>
        <span className="inline-block px-2 py-0.5 rounded text-[10px] font-semibold uppercase bg-green-50 text-green-700 border border-green-200">Post Immediately</span>
        <div className="flex-1" />
        {error && <span className="text-xs text-red-600 font-medium max-w-sm truncate">{error}</span>}
        <button onClick={save} disabled={saving}
          className="px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
          {saving ? 'Posting…' : 'Post Cash Sale'}
        </button>
      </div>

      <div className="divide-y divide-gray-200">
        {/* Header */}
        <div className="bg-white px-5 py-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Transaction Details</div>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-5 gap-y-3">
            <div>
              <label className="block text-xs text-gray-500 mb-1">Date *</label>
              <input type="date" value={fDate} onChange={e => setFDate(e.target.value)} className={inp} />
            </div>
            <div className="col-span-2">
              <label className="block text-xs text-gray-500 mb-1">Customer *</label>
              <select value={fCustomer} onChange={e => selectCustomer(e.target.value)} className={inp}>
                <option value="">Select customer…</option>
                {customers.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs text-gray-500 mb-1">TIN</label>
              <input value={fCustomerTIN} onChange={e => setFCustomerTIN(e.target.value)} className={inp} />
            </div>
            <div>
              <label className="block text-xs text-gray-500 mb-1">Payment Mode</label>
              <select value={fPaymentMode} onChange={e => setFPaymentMode(e.target.value)} className={inp}>
                <option value="">Select…</option>
                {paymentModes.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs text-gray-500 mb-1">Cash / Bank Account</label>
              <select value={fBankAccount} onChange={e => setFBankAccount(e.target.value)} className={inp}>
                <option value="">Use GL default</option>
                {bankAccounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs text-gray-500 mb-1">CWT Amount</label>
              <input type="number" value={fCWT} onChange={e => setFCWT(Number(e.target.value))} min="0" step="0.01" className={inp} />
            </div>
            {fCWT > 0 && (
              <div>
                <label className="block text-xs text-gray-500 mb-1">CWT ATC Code</label>
                <select value={fCwtAtc} onChange={e => setFCwtAtc(e.target.value)} className={inp}>
                  <option value="">Select ATC…</option>
                  {atcCodes.map(a => <option key={a.id} value={a.id}>{a.code} ({a.rate}%) — {a.description}</option>)}
                </select>
              </div>
            )}
            <div>
              <label className="block text-xs text-gray-500 mb-1">Reference</label>
              <input value={fReference} onChange={e => setFReference(e.target.value)} className={inp} placeholder="Check #, ref…" />
            </div>
            <div className="col-span-2">
              <label className="block text-xs text-gray-500 mb-1">Memo</label>
              <input value={fMemo} onChange={e => setFMemo(e.target.value)} className={inp} />
            </div>
          </div>
        </div>

        {/* Lines */}
        <div className="bg-white px-5 py-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3">Line Items</div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className={th} style={{ minWidth: 120 }}>Item</th>
                  <th className={th} style={{ minWidth: 200 }}>Description</th>
                  <th className={`${th} text-right`} style={{ width: 70 }}>Qty</th>
                  <th className={`${th} text-right`} style={{ width: 100 }}>Unit Price</th>
                  <th className={`${th} text-right`} style={{ width: 80 }}>Discount</th>
                  <th className={th} style={{ minWidth: 120 }}>VAT</th>
                  <th className={th} style={{ minWidth: 150 }}>Revenue Acct</th>
                  <th className={`${th} text-right`} style={{ width: 90 }}>Net</th>
                  <th className={`${th} text-right`} style={{ width: 80 }}>VAT Amt</th>
                  <th className={`${th} text-right`} style={{ width: 90 }}>Total</th>
                  <th className={th} style={{ width: 32 }} />
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {lines.map(l => (
                  <tr key={l._key}>
                    <td className={td}>
                      <select value={l.item_id} onChange={e => updateLine(l._key, { item_id: e.target.value })}
                        className="border border-gray-200 rounded px-1.5 py-1 text-xs w-full">
                        <option value="">—</option>
                        {items.map(i => <option key={i.id} value={i.id}>{i.item_name}</option>)}
                      </select>
                    </td>
                    <td className={td}>
                      <input value={l.description} onChange={e => updateLine(l._key, { description: e.target.value })}
                        className="border border-gray-200 rounded px-1.5 py-1 text-xs w-full" placeholder="Description" />
                    </td>
                    <td className={td}>
                      <input type="number" value={l.quantity} min="0" step="0.001"
                        onChange={e => updateLine(l._key, { quantity: Number(e.target.value) })}
                        className="border border-gray-200 rounded px-1.5 py-1 text-xs w-full text-right tabular-nums" />
                    </td>
                    <td className={td}>
                      <input type="number" value={l.unit_price} min="0" step="0.01"
                        onChange={e => updateLine(l._key, { unit_price: Number(e.target.value) })}
                        className="border border-gray-200 rounded px-1.5 py-1 text-xs w-full text-right tabular-nums" />
                    </td>
                    <td className={td}>
                      <input type="number" value={l.discount_amount} min="0" step="0.01"
                        onChange={e => updateLine(l._key, { discount_amount: Number(e.target.value) })}
                        className="border border-gray-200 rounded px-1.5 py-1 text-xs w-full text-right tabular-nums" />
                    </td>
                    <td className={td}>
                      <select value={l.vat_code_id} onChange={e => updateLine(l._key, { vat_code_id: e.target.value })}
                        className="border border-gray-200 rounded px-1.5 py-1 text-xs w-full">
                        <option value="">—</option>
                        {vatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code}</option>)}
                      </select>
                    </td>
                    <td className={td}>
                      <select value={l.revenue_account_id} onChange={e => updateLine(l._key, { revenue_account_id: e.target.value })}
                        className="border border-gray-200 rounded px-1.5 py-1 text-xs w-full">
                        <option value="">—</option>
                        {accounts.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                      </select>
                    </td>
                    <td className={`${td} text-right font-mono text-xs tabular-nums text-gray-700`}>{fmt(l.net_amount)}</td>
                    <td className={`${td} text-right font-mono text-xs tabular-nums text-blue-700`}>{l.vat_amount ? fmt(l.vat_amount) : '—'}</td>
                    <td className={`${td} text-right font-mono text-xs tabular-nums font-semibold text-gray-900`}>{fmt(l.total_amount)}</td>
                    <td className={td}>
                      <button onClick={() => setLines(p => p.filter(x => x._key !== l._key))} disabled={lines.length === 1}
                        className="text-gray-300 hover:text-red-500 disabled:opacity-0">
                        <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}><path d="M18 6L6 18M6 6l12 12" /></svg>
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button onClick={() => setLines(p => [...p, newLine()])}
            className="mt-2 text-xs text-gray-500 hover:text-gray-900 flex items-center gap-1">
            <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5}><path d="M12 5v14M5 12h14" /></svg>
            Add Row
          </button>
        </div>

        {/* Totals */}
        <div className="bg-gray-50 px-5 py-4 flex justify-end">
          <div className="w-64 space-y-1.5 text-sm">
            <div className="flex justify-between text-gray-600"><span>Net Amount</span><span className="font-mono tabular-nums">{fmt(totals.net)}</span></div>
            <div className="flex justify-between text-gray-600"><span>Output VAT</span><span className="font-mono tabular-nums text-blue-700">{fmt(totals.vat)}</span></div>
            {fCWT > 0 && <div className="flex justify-between text-gray-600"><span>CWT</span><span className="font-mono tabular-nums text-amber-600">({fmt(fCWT)})</span></div>}
            <div className="flex justify-between font-bold text-gray-900 border-t border-gray-300 pt-1.5"><span>Total Amount</span><span className="font-mono tabular-nums">{fmt(totals.total)}</span></div>
          </div>
        </div>
      </div>
    </div>
  )
}
