import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Batch = {
  id: string; batch_number: string; cutover_date: string; description: string | null
  branch_id: string | null; status: 'draft' | 'posted' | 'reversed'
  journal_entry_id: string | null; reversal_je_id: string | null
}
type Ref = { id: string; label: string }
type GLLine = { account_id: string; description: string; debit_amount: number; credit_amount: number }
type ARLine = { customer_id: string; legacy_invoice_number: string; invoice_date: string; due_date: string; original_amount: number; memo: string }
type APLine = { supplier_id: string; legacy_bill_number: string; supplier_invoice_number: string; bill_date: string; due_date: string; original_amount: number; memo: string }
type InventoryLine = { warehouse_id: string; item_id: string; quantity: number; unit_cost: number; lot_number: string; serial_number: string; memo: string }
type BankLine = { bank_account_id: string; amount: number; memo: string }

const today = () => new Date().toISOString().slice(0, 10)
const money = (value: number) => new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' }).format(value || 0)
const input = 'w-full rounded border border-gray-300 px-2 py-1.5 text-sm disabled:bg-gray-50 disabled:text-gray-500'
const emptyGL = (): GLLine => ({ account_id: '', description: '', debit_amount: 0, credit_amount: 0 })
const emptyAR = (): ARLine => ({ customer_id: '', legacy_invoice_number: '', invoice_date: '', due_date: '', original_amount: 0, memo: '' })
const emptyAP = (): APLine => ({ supplier_id: '', legacy_bill_number: '', supplier_invoice_number: '', bill_date: '', due_date: '', original_amount: 0, memo: '' })
const emptyInventory = (): InventoryLine => ({ warehouse_id: '', item_id: '', quantity: 0, unit_cost: 0, lot_number: '', serial_number: '', memo: '' })
const emptyBank = (): BankLine => ({ bank_account_id: '', amount: 0, memo: '' })

export default function OpeningBalancesPage() {
  const { companyId, branchId } = useAppCtx()
  const [batches, setBatches] = useState<Batch[]>([])
  const [batchId, setBatchId] = useState<string | null>(null)
  const [batchNumber, setBatchNumber] = useState('')
  const [cutoverDate, setCutoverDate] = useState(today())
  const [description, setDescription] = useState('Opening balances at cut-over')
  const [selectedBranch, setSelectedBranch] = useState(branchId || '')
  const [status, setStatus] = useState<Batch['status']>('draft')
  const [glLines, setGlLines] = useState<GLLine[]>([emptyGL()])
  const [arLines, setArLines] = useState<ARLine[]>([])
  const [apLines, setApLines] = useState<APLine[]>([])
  const [inventoryLines, setInventoryLines] = useState<InventoryLine[]>([])
  const [bankLines, setBankLines] = useState<BankLine[]>([])
  const [accounts, setAccounts] = useState<Ref[]>([])
  const [customers, setCustomers] = useState<Ref[]>([])
  const [suppliers, setSuppliers] = useState<Ref[]>([])
  const [warehouses, setWarehouses] = useState<Ref[]>([])
  const [items, setItems] = useState<Ref[]>([])
  const [bankAccounts, setBankAccounts] = useState<Ref[]>([])
  const [branches, setBranches] = useState<Ref[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  const readOnly = status !== 'draft'
  const totalDebit = useMemo(() => glLines.reduce((sum, line) => sum + Number(line.debit_amount || 0), 0)
    + arLines.reduce((sum, line) => sum + Number(line.original_amount || 0), 0)
    + inventoryLines.reduce((sum, line) => sum + Number(line.quantity || 0) * Number(line.unit_cost || 0), 0)
    + bankLines.reduce((sum, line) => sum + Number(line.amount || 0), 0), [glLines, arLines, inventoryLines, bankLines])
  const totalCredit = useMemo(() => glLines.reduce((sum, line) => sum + Number(line.credit_amount || 0), 0)
    + apLines.reduce((sum, line) => sum + Number(line.original_amount || 0), 0), [glLines, apLines])

  const loadBatches = useCallback(async () => {
    if (!companyId) { setBatches([]); return }
    const { data } = await (supabase as any).from('opening_balance_batches').select('*')
      .eq('company_id', companyId).order('cutover_date', { ascending: false })
    setBatches((data as Batch[]) || [])
  }, [companyId])

  const loadRefs = useCallback(async () => {
    if (!companyId) return
    const [coa, customer, supplier, warehouse, item, bank, branch] = await Promise.all([
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_active', true).eq('is_postable', true).order('account_code'),
      supabase.from('customers').select('id,customer_code,registered_name').eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('suppliers').select('id,supplier_code,registered_name').eq('company_id', companyId).eq('is_active', true).order('registered_name'),
      supabase.from('warehouses').select('id,warehouse_code,warehouse_name').eq('company_id', companyId).eq('is_active', true).order('warehouse_code'),
      supabase.from('items').select('id,item_code,description').eq('company_id', companyId).eq('is_active', true).eq('item_type', 'inventory_item').order('item_code'),
      supabase.from('bank_accounts').select('id,bank_name,account_name,account_number').eq('company_id', companyId).eq('is_active', true).order('bank_name'),
      supabase.from('branches').select('id,branch_code,branch_name').eq('company_id', companyId).eq('is_active', true).order('branch_code'),
    ])
    setAccounts((coa.data || []).map((row: any) => ({ id: row.id, label: `${row.account_code} — ${row.account_name}` })))
    setCustomers((customer.data || []).map((row: any) => ({ id: row.id, label: `${row.customer_code} — ${row.registered_name}` })))
    setSuppliers((supplier.data || []).map((row: any) => ({ id: row.id, label: `${row.supplier_code} — ${row.registered_name}` })))
    setWarehouses((warehouse.data || []).map((row: any) => ({ id: row.id, label: `${row.warehouse_code} — ${row.warehouse_name}` })))
    setItems((item.data || []).map((row: any) => ({ id: row.id, label: `${row.item_code} — ${row.description}` })))
    setBankAccounts((bank.data || []).map((row: any) => ({ id: row.id, label: `${row.bank_name} — ${row.account_name} · ••••${row.account_number.slice(-4)}` })))
    setBranches((branch.data || []).map((row: any) => ({ id: row.id, label: `${row.branch_code} — ${row.branch_name}` })))
  }, [companyId])

  useEffect(() => { loadBatches(); loadRefs() }, [loadBatches, loadRefs])

  const newBatch = () => {
    setBatchId(null); setBatchNumber(''); setCutoverDate(today()); setDescription('Opening balances at cut-over')
    setSelectedBranch(branchId || ''); setStatus('draft'); setGlLines([emptyGL()]); setArLines([])
    setApLines([]); setInventoryLines([]); setBankLines([]); setError(''); setMessage('')
  }

  const openBatch = async (batch: Batch) => {
    setBusy(true); setError(''); setMessage('')
    const [gl, ar, ap, inventory, bank] = await Promise.all([
      (supabase as any).from('opening_balance_gl_lines').select('*').eq('batch_id', batch.id).order('line_number'),
      (supabase as any).from('opening_balance_ar_lines').select('*').eq('batch_id', batch.id).order('line_number'),
      (supabase as any).from('opening_balance_ap_lines').select('*').eq('batch_id', batch.id).order('line_number'),
      (supabase as any).from('opening_balance_inventory_lines').select('*').eq('batch_id', batch.id).order('line_number'),
      (supabase as any).from('opening_balance_bank_lines').select('*').eq('batch_id', batch.id).order('line_number'),
    ])
    setBatchId(batch.id); setBatchNumber(batch.batch_number); setCutoverDate(batch.cutover_date)
    setDescription(batch.description || ''); setSelectedBranch(batch.branch_id || ''); setStatus(batch.status)
    setGlLines((gl.data || []).map((line: any) => ({ ...line, debit_amount: Number(line.debit_amount), credit_amount: Number(line.credit_amount) })))
    setArLines((ar.data || []).map((line: any) => ({ ...line, original_amount: Number(line.original_amount), due_date: line.due_date || '', memo: line.memo || '' })))
    setApLines((ap.data || []).map((line: any) => ({ ...line, original_amount: Number(line.original_amount), due_date: line.due_date || '', supplier_invoice_number: line.supplier_invoice_number || '', memo: line.memo || '' })))
    setInventoryLines((inventory.data || []).map((line: any) => ({ ...line, quantity: Number(line.quantity), unit_cost: Number(line.unit_cost), lot_number: line.lot_number || '', serial_number: line.serial_number || '', memo: line.memo || '' })))
    setBankLines((bank.data || []).map((line: any) => ({ ...line, amount: Number(line.amount), memo: line.memo || '' })))
    setBusy(false)
  }

  const validate = () => {
    if (!companyId || !cutoverDate) return 'Company and cut-over date are required.'
    if (Math.abs(totalDebit - totalCredit) > 0.005) return `Opening balances do not balance. Variance: ${money(totalDebit - totalCredit)}.`
    if (totalDebit <= 0) return 'Enter at least one financial amount.'
    if (glLines.some(line => !line.account_id || (Number(line.debit_amount) > 0) === (Number(line.credit_amount) > 0))) return 'Every other-GL row needs an account and exactly one positive debit or credit.'
    if (arLines.some(line => !line.customer_id || !line.legacy_invoice_number || !line.invoice_date || Number(line.original_amount) <= 0)) return 'Complete every AR row.'
    if (apLines.some(line => !line.supplier_id || !line.legacy_bill_number || !line.bill_date || Number(line.original_amount) <= 0)) return 'Complete every AP row.'
    if (inventoryLines.some(line => !line.warehouse_id || !line.item_id || Number(line.quantity) <= 0 || Number(line.unit_cost) <= 0)) return 'Complete every inventory row with positive quantity and cost.'
    if (bankLines.some(line => !line.bank_account_id || Number(line.amount) <= 0)) return 'Complete every bank row.'
    return ''
  }

  const save = async () => {
    const validation = validate()
    if (validation) { setError(validation); return null }
    setBusy(true); setError(''); setMessage('')
    const { data, error: rpcError } = await (supabase as any).rpc('fn_save_opening_balance', {
      p_batch_id: batchId,
      p_header: { company_id: companyId, branch_id: selectedBranch || '', batch_number: batchNumber, cutover_date: cutoverDate, description, currency_code: 'PHP' },
      p_gl_lines: glLines, p_ar_lines: arLines, p_ap_lines: apLines,
      p_inventory_lines: inventoryLines, p_bank_lines: bankLines,
    })
    setBusy(false)
    if (rpcError) { setError(rpcError.message); return null }
    setBatchId(data); setMessage('Draft saved.'); await loadBatches()
    return data as string
  }

  const post = async () => {
    const savedId = await save()
    if (!savedId || !confirm('Post this opening balance? Posted detail is immutable and corrections require a reversal.')) return
    setBusy(true); setError(''); setMessage('')
    const { error: rpcError } = await (supabase as any).rpc('fn_post_opening_balance', { p_batch_id: savedId })
    setBusy(false)
    if (rpcError) { setError(rpcError.message); return }
    setStatus('posted'); setMessage('Opening balances posted through the Accounting Kernel.'); await loadBatches()
  }

  const reverse = async () => {
    if (!batchId) return
    const reason = prompt('Reason for reversing this untouched cut-over:')?.trim()
    if (!reason) return
    const reversalDate = prompt('Reversal date (YYYY-MM-DD):', cutoverDate)?.trim()
    if (!reversalDate) return
    setBusy(true); setError(''); setMessage('')
    const { error: rpcError } = await (supabase as any).rpc('fn_reverse_opening_balance', {
      p_batch_id: batchId, p_reversal_date: reversalDate, p_reason: reason,
    })
    setBusy(false)
    if (rpcError) { setError(rpcError.message); return }
    setStatus('reversed'); setMessage('Opening balances reversed with equal-and-opposite journal and inventory movements.'); await loadBatches()
  }

  const update = <T,>(setter: React.Dispatch<React.SetStateAction<T[]>>, index: number, patch: Partial<T>) => setter(rows => rows.map((row, rowIndex) => rowIndex === index ? { ...row, ...patch } : row))
  const remove = <T,>(setter: React.Dispatch<React.SetStateAction<T[]>>, index: number) => setter(rows => rows.filter((_, rowIndex) => rowIndex !== index))
  const options = (refs: Ref[]) => <><option value="">Select...</option>{refs.map(ref => <option key={ref.id} value={ref.id}>{ref.label}</option>)}</>

  if (!companyId) return <div className="p-8 text-sm text-gray-500">Select a company to maintain its opening balances.</div>

  return <div className="space-y-5">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h1 className="text-xl font-semibold text-gray-900">Opening Balances</h1><p className="mt-1 text-sm text-gray-500">One governed cut-over document; AR, AP, inventory, and bank controls are derived from detail.</p></div>
      <div className="flex gap-2"><button onClick={newBatch} className="rounded border border-gray-300 px-3 py-2 text-sm">New</button>{!readOnly && <><button onClick={save} disabled={busy} className="rounded border border-gray-300 px-3 py-2 text-sm disabled:opacity-50">Save Draft</button><button onClick={post} disabled={busy} className="rounded bg-gray-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50">Save & Post</button></>}{status === 'posted' && <button onClick={reverse} disabled={busy} className="rounded border border-red-300 px-3 py-2 text-sm text-red-700 disabled:opacity-50">Reverse</button>}</div>
    </div>

    <div className="grid gap-5 xl:grid-cols-[260px_minmax(0,1fr)]">
      <aside className="rounded-lg border border-gray-200 bg-white p-3"><div className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500">Cut-over batches</div>{batches.length === 0 ? <p className="py-6 text-center text-sm text-gray-400">No batches</p> : <div className="space-y-1">{batches.map(batch => <button key={batch.id} onClick={() => openBatch(batch)} className={`w-full rounded px-3 py-2 text-left text-sm ${batch.id === batchId ? 'bg-gray-900 text-white' : 'hover:bg-gray-50'}`}><div className="font-medium">{batch.batch_number}</div><div className={`text-xs ${batch.id === batchId ? 'text-gray-300' : 'text-gray-500'}`}>{batch.cutover_date} · {batch.status}</div></button>)}</div>}</aside>

      <main className="space-y-4">
        {(error || message) && <div className={`rounded border px-4 py-3 text-sm ${error ? 'border-red-200 bg-red-50 text-red-700' : 'border-green-200 bg-green-50 text-green-700'}`}>{error || message}</div>}
        <section className="rounded-lg border border-gray-200 bg-white p-4"><div className="grid gap-3 md:grid-cols-4"><label className="text-xs font-medium text-gray-500">Batch number<input value={batchNumber} disabled={readOnly} onChange={event => setBatchNumber(event.target.value.toUpperCase())} placeholder="Auto if blank" className={`${input} mt-1`} /></label><label className="text-xs font-medium text-gray-500">Cut-over date<input type="date" value={cutoverDate} disabled={readOnly} onChange={event => setCutoverDate(event.target.value)} className={`${input} mt-1`} /></label><label className="text-xs font-medium text-gray-500">Branch<select value={selectedBranch} disabled={readOnly} onChange={event => setSelectedBranch(event.target.value)} className={`${input} mt-1`}><option value="">Company-wide</option>{branches.map(ref => <option key={ref.id} value={ref.id}>{ref.label}</option>)}</select></label><label className="text-xs font-medium text-gray-500">Status<div className="mt-1 rounded border border-gray-200 bg-gray-50 px-2 py-1.5 text-sm capitalize">{status}</div></label><label className="text-xs font-medium text-gray-500 md:col-span-4">Description<input value={description} disabled={readOnly} onChange={event => setDescription(event.target.value)} className={`${input} mt-1`} /></label></div></section>

        <LineSection title="Other trial-balance accounts" onAdd={() => setGlLines(lines => [...lines, emptyGL()])} readOnly={readOnly}><table className="w-full text-sm"><thead><tr>{['Account','Description','Debit','Credit',''].map(label => <th key={label} className="px-2 py-2 text-left text-xs text-gray-500">{label}</th>)}</tr></thead><tbody>{glLines.map((line, index) => <tr key={index} className="border-t"><td className="p-2"><select value={line.account_id} disabled={readOnly} onChange={event => update(setGlLines, index, { account_id: event.target.value })} className={input}>{options(accounts)}</select></td><td className="p-2"><input value={line.description} disabled={readOnly} onChange={event => update(setGlLines, index, { description: event.target.value })} className={input} /></td><td className="p-2"><input type="number" min="0" step="0.01" value={line.debit_amount} disabled={readOnly} onChange={event => update(setGlLines, index, { debit_amount: Number(event.target.value), credit_amount: 0 })} className={input} /></td><td className="p-2"><input type="number" min="0" step="0.01" value={line.credit_amount} disabled={readOnly} onChange={event => update(setGlLines, index, { credit_amount: Number(event.target.value), debit_amount: 0 })} className={input} /></td><RemoveButton readOnly={readOnly} onClick={() => remove(setGlLines, index)} /></tr>)}</tbody></table></LineSection>

        <LineSection title="Accounts receivable by customer and invoice" onAdd={() => setArLines(lines => [...lines, emptyAR()])} readOnly={readOnly}><table className="w-full text-sm"><thead><tr>{['Customer','Legacy invoice','Invoice date','Due date','Amount',''].map(label => <th key={label} className="px-2 py-2 text-left text-xs text-gray-500">{label}</th>)}</tr></thead><tbody>{arLines.map((line, index) => <tr key={index} className="border-t"><td className="p-2"><select value={line.customer_id} disabled={readOnly} onChange={event => update(setArLines, index, { customer_id: event.target.value })} className={input}>{options(customers)}</select></td><td className="p-2"><input value={line.legacy_invoice_number} disabled={readOnly} onChange={event => update(setArLines, index, { legacy_invoice_number: event.target.value })} className={input} /></td><td className="p-2"><input type="date" value={line.invoice_date} disabled={readOnly} onChange={event => update(setArLines, index, { invoice_date: event.target.value })} className={input} /></td><td className="p-2"><input type="date" value={line.due_date} disabled={readOnly} onChange={event => update(setArLines, index, { due_date: event.target.value })} className={input} /></td><td className="p-2"><input type="number" min="0" step="0.01" value={line.original_amount} disabled={readOnly} onChange={event => update(setArLines, index, { original_amount: Number(event.target.value) })} className={input} /></td><RemoveButton readOnly={readOnly} onClick={() => remove(setArLines, index)} /></tr>)}</tbody></table></LineSection>

        <LineSection title="Accounts payable by supplier and bill" onAdd={() => setApLines(lines => [...lines, emptyAP()])} readOnly={readOnly}><table className="w-full text-sm"><thead><tr>{['Supplier','Legacy bill','Supplier invoice','Bill date','Due date','Amount',''].map(label => <th key={label} className="px-2 py-2 text-left text-xs text-gray-500">{label}</th>)}</tr></thead><tbody>{apLines.map((line, index) => <tr key={index} className="border-t"><td className="p-2"><select value={line.supplier_id} disabled={readOnly} onChange={event => update(setApLines, index, { supplier_id: event.target.value })} className={input}>{options(suppliers)}</select></td><td className="p-2"><input value={line.legacy_bill_number} disabled={readOnly} onChange={event => update(setApLines, index, { legacy_bill_number: event.target.value })} className={input} /></td><td className="p-2"><input value={line.supplier_invoice_number} disabled={readOnly} onChange={event => update(setApLines, index, { supplier_invoice_number: event.target.value })} className={input} /></td><td className="p-2"><input type="date" value={line.bill_date} disabled={readOnly} onChange={event => update(setApLines, index, { bill_date: event.target.value })} className={input} /></td><td className="p-2"><input type="date" value={line.due_date} disabled={readOnly} onChange={event => update(setApLines, index, { due_date: event.target.value })} className={input} /></td><td className="p-2"><input type="number" min="0" step="0.01" value={line.original_amount} disabled={readOnly} onChange={event => update(setApLines, index, { original_amount: Number(event.target.value) })} className={input} /></td><RemoveButton readOnly={readOnly} onClick={() => remove(setApLines, index)} /></tr>)}</tbody></table></LineSection>

        <LineSection title="Inventory by warehouse, item, quantity, and cost" onAdd={() => setInventoryLines(lines => [...lines, emptyInventory()])} readOnly={readOnly}><table className="w-full text-sm"><thead><tr>{['Warehouse','Item','Quantity','Unit cost','Value',''].map(label => <th key={label} className="px-2 py-2 text-left text-xs text-gray-500">{label}</th>)}</tr></thead><tbody>{inventoryLines.map((line, index) => <tr key={index} className="border-t"><td className="p-2"><select value={line.warehouse_id} disabled={readOnly} onChange={event => update(setInventoryLines, index, { warehouse_id: event.target.value })} className={input}>{options(warehouses)}</select></td><td className="p-2"><select value={line.item_id} disabled={readOnly} onChange={event => update(setInventoryLines, index, { item_id: event.target.value })} className={input}>{options(items)}</select></td><td className="p-2"><input type="number" min="0" step="0.0001" value={line.quantity} disabled={readOnly} onChange={event => update(setInventoryLines, index, { quantity: Number(event.target.value) })} className={input} /></td><td className="p-2"><input type="number" min="0" step="0.000001" value={line.unit_cost} disabled={readOnly} onChange={event => update(setInventoryLines, index, { unit_cost: Number(event.target.value) })} className={input} /></td><td className="p-2 whitespace-nowrap font-mono">{money(line.quantity * line.unit_cost)}</td><RemoveButton readOnly={readOnly} onClick={() => remove(setInventoryLines, index)} /></tr>)}</tbody></table></LineSection>

        <LineSection title="Bank balances" onAdd={() => setBankLines(lines => [...lines, emptyBank()])} readOnly={readOnly}><table className="w-full text-sm"><thead><tr>{['Company bank account','Amount','Memo',''].map(label => <th key={label} className="px-2 py-2 text-left text-xs text-gray-500">{label}</th>)}</tr></thead><tbody>{bankLines.map((line, index) => <tr key={index} className="border-t"><td className="p-2"><select value={line.bank_account_id} disabled={readOnly} onChange={event => update(setBankLines, index, { bank_account_id: event.target.value })} className={input}>{options(bankAccounts)}</select></td><td className="p-2"><input type="number" min="0" step="0.01" value={line.amount} disabled={readOnly} onChange={event => update(setBankLines, index, { amount: Number(event.target.value) })} className={input} /></td><td className="p-2"><input value={line.memo} disabled={readOnly} onChange={event => update(setBankLines, index, { memo: event.target.value })} className={input} /></td><RemoveButton readOnly={readOnly} onClick={() => remove(setBankLines, index)} /></tr>)}</tbody></table></LineSection>

        <div className={`rounded-lg border p-4 ${Math.abs(totalDebit - totalCredit) <= 0.005 && totalDebit > 0 ? 'border-green-200 bg-green-50' : 'border-amber-200 bg-amber-50'}`}><div className="grid grid-cols-3 gap-4 text-sm"><div><div className="text-xs text-gray-500">Total debit</div><div className="font-mono font-semibold">{money(totalDebit)}</div></div><div><div className="text-xs text-gray-500">Total credit</div><div className="font-mono font-semibold">{money(totalCredit)}</div></div><div><div className="text-xs text-gray-500">Variance</div><div className="font-mono font-semibold">{money(totalDebit - totalCredit)}</div></div></div></div>
      </main>
    </div>
  </div>
}

function LineSection({ title, onAdd, readOnly, children }: { title: string; onAdd: () => void; readOnly: boolean; children: React.ReactNode }) {
  return <section className="overflow-x-auto rounded-lg border border-gray-200 bg-white"><div className="flex items-center justify-between border-b border-gray-200 px-4 py-3"><h2 className="text-sm font-semibold text-gray-800">{title}</h2>{!readOnly && <button onClick={onAdd} className="text-xs font-medium text-blue-600 hover:text-blue-800">+ Add row</button>}</div>{children}</section>
}

function RemoveButton({ readOnly, onClick }: { readOnly: boolean; onClick: () => void }) {
  return <td className="p-2">{!readOnly && <button onClick={onClick} className="text-xs text-red-600">Remove</button>}</td>
}
