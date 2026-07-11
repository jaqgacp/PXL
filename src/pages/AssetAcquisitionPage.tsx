import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'

type Category = { id: string; category_code: string; category_name: string; depreciation_method: string; useful_life_months: number; salvage_rate: number }
type Branch = { id: string; branch_name: string }
type Department = { id: string; department_name: string }
type COA = { id: string; account_code: string; account_name: string }
type Supplier = { id: string; supplier_name: string }

type Form = {
  asset_name: string
  description: string
  category_id: string
  branch_id: string
  department_id: string
  acquisition_date: string
  depreciation_start_date: string
  acquisition_cost: string
  salvage_value: string
  useful_life_months: string
  depreciation_method: string
  serial_number: string
  location: string
  supplier_id: string
  credit_account_id: string
}

const METHODS = [
  { value: 'straight_line', label: 'Straight-Line (SLM)' },
  { value: 'declining_balance', label: 'Declining Balance (DDB)' },
  { value: 'sum_of_years', label: 'Sum-of-Years-Digits (SYD)' },
  { value: 'none', label: 'None (Non-depreciable)' },
]

const blank = (today: string): Form => ({
  asset_name: '', description: '', category_id: '', branch_id: '', department_id: '',
  acquisition_date: today, depreciation_start_date: today,
  acquisition_cost: '', salvage_value: '0', useful_life_months: '60',
  depreciation_method: 'straight_line', serial_number: '', location: '',
  supplier_id: '', credit_account_id: '',
})

export default function AssetAcquisitionPage() {
  const { companyId, branchId } = useAppCtx()
  const today = new Date().toISOString().slice(0, 10)
  const [form, setForm] = useState<Form>(blank(today))
  const [categories, setCategories] = useState<Category[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [departments, setDepartments] = useState<Department[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  useEffect(() => {
    if (branchId) setForm(p => ({ ...p, branch_id: branchId }))
  }, [branchId])

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: cats }, { data: brs }, { data: depts }, { data: accounts }, { data: sups }] = await Promise.all([
      supabase.from('fixed_asset_categories').select('id,category_code,category_name,depreciation_method,useful_life_months,salvage_rate').eq('company_id', companyId).eq('is_active', true).order('category_code'),
      supabase.from('branches').select('id,branch_name').eq('company_id', companyId).order('branch_name'),
      supabase.from('departments').select('id,department_name').eq('company_id', companyId).order('department_name'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_postable', true).order('account_code'),
      supabase.from('suppliers').select('id,supplier_name:registered_name').eq('company_id', companyId).order('registered_name'),
    ])
    setCategories((cats as Category[]) || [])
    setBranches((brs as Branch[]) || [])
    setDepartments((depts as Department[]) || [])
    setCoa((accounts as COA[]) || [])
    setSuppliers((sups as Supplier[]) || [])
  }, [companyId])

  useEffect(() => { load() }, [load])

  const f = (k: keyof Form, v: string) => setForm(p => ({ ...p, [k]: v }))

  const onCategoryChange = (catId: string) => {
    const cat = categories.find(c => c.id === catId)
    if (cat) {
      setForm(p => ({
        ...p,
        category_id: catId,
        depreciation_method: cat.depreciation_method,
        useful_life_months: cat.useful_life_months.toString(),
        salvage_value: p.acquisition_cost ? (Number(p.acquisition_cost) * cat.salvage_rate).toFixed(2) : '0',
      }))
    } else {
      f('category_id', catId)
    }
  }

  const onCostChange = (cost: string) => {
    const cat = categories.find(c => c.id === form.category_id)
    if (cat && cost) {
      setForm(p => ({ ...p, acquisition_cost: cost, salvage_value: (Number(cost) * cat.salvage_rate).toFixed(2) }))
    } else {
      f('acquisition_cost', cost)
    }
  }

  const previewSalvage = () => {
    const cost = Number(form.acquisition_cost) || 0
    const salvage = Number(form.salvage_value) || 0
    const months = Number(form.useful_life_months) || 1
    if (form.depreciation_method === 'none') return null
    const monthly = (cost - salvage) / months
    return { monthly, annual: monthly * 12 }
  }

  const submit = async () => {
    if (!companyId) return
    if (!form.asset_name.trim()) { setError('Asset name is required'); return }
    if (!form.category_id) { setError('Category is required'); return }
    if (!form.acquisition_date) { setError('Acquisition date is required'); return }
    if (!form.acquisition_cost || Number(form.acquisition_cost) <= 0) { setError('Acquisition cost must be positive'); return }
    if (form.depreciation_method !== 'none' && !form.useful_life_months) { setError('Useful life is required'); return }
    if (Number(form.salvage_value) >= Number(form.acquisition_cost)) { setError('Salvage value must be less than acquisition cost'); return }

    setSaving(true); setError(''); setSuccess('')
    const { data, error: e } = await supabase.rpc('fn_register_fixed_asset', {
      p_data: {
        company_id: companyId,
        branch_id: form.branch_id || null,
        department_id: form.department_id || null,
        asset_name: form.asset_name.trim(),
        description: form.description.trim() || null,
        category_id: form.category_id,
        acquisition_date: form.acquisition_date,
        depreciation_start_date: form.depreciation_start_date || form.acquisition_date,
        acquisition_cost: Number(form.acquisition_cost),
        salvage_value: Number(form.salvage_value) || 0,
        useful_life_months: Number(form.useful_life_months),
        depreciation_method: form.depreciation_method,
        serial_number: form.serial_number.trim() || null,
        location: form.location.trim() || null,
        supplier_id: form.supplier_id || null,
        credit_account_id: form.credit_account_id || null,
      }
    })
    setSaving(false)
    if (e) { setError(e.message); return }
    setSuccess(`Asset registered successfully. Asset ID: ${data}`)
    setForm(blank(today))
  }

  const preview = previewSalvage()
  const acquisitionCost = Number(form.acquisition_cost) || 0
  const glPreviewRows: GLImpactRow[] = form.credit_account_id && acquisitionCost > 0 ? [
    {
      accountLabel: 'Asset account from selected category',
      description: `Acquisition — ${form.asset_name || 'fixed asset'}`,
      debit: acquisitionCost,
      credit: 0,
    },
    {
      accountId: form.credit_account_id,
      description: `Acquisition — ${form.asset_name || 'fixed asset'}`,
      debit: 0,
      credit: acquisitionCost,
    },
  ] : []

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset Acquisition</span>
      </div>

      <div className="px-5 py-4 max-w-4xl space-y-4">
        {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
        {success && <div className="text-xs text-green-700 bg-green-50 border border-green-200 rounded px-3 py-2">{success}</div>}

        {/* Basic Info */}
        <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Asset Details</p>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2">
              <label className="block text-xs font-medium text-gray-600 mb-1">Asset Name *</label>
              <input value={form.asset_name} onChange={e => f('asset_name', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900"
                placeholder="e.g. Delivery Van 2026 — Toyota Hi-Ace" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Category *</label>
              <select value={form.category_id} onChange={e => onCategoryChange(e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">— Select Category —</option>
                {categories.map(c => <option key={c.id} value={c.id}>{c.category_code} — {c.category_name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Supplier</label>
              <select value={form.supplier_id} onChange={e => f('supplier_id', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">— None —</option>
                {suppliers.map(s => <option key={s.id} value={s.id}>{s.supplier_name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Branch</label>
              <select value={form.branch_id} onChange={e => f('branch_id', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">— None —</option>
                {branches.map(b => <option key={b.id} value={b.id}>{b.branch_name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Department</label>
              <select value={form.department_id} onChange={e => f('department_id', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">— None —</option>
                {departments.map(d => <option key={d.id} value={d.id}>{d.department_name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Serial Number</label>
              <input value={form.serial_number} onChange={e => f('serial_number', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm font-mono focus:outline-none focus:ring-1 focus:ring-gray-900" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Location</label>
              <input value={form.location} onChange={e => f('location', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900"
                placeholder="e.g. Head Office — 3rd Floor" />
            </div>
            <div className="col-span-2">
              <label className="block text-xs font-medium text-gray-600 mb-1">Description</label>
              <textarea value={form.description} onChange={e => f('description', e.target.value)} rows={2}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 resize-none" />
            </div>
          </div>
        </div>

        {/* Cost & Dates */}
        <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Cost & Dates</p>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Acquisition Date *</label>
              <input type="date" value={form.acquisition_date} onChange={e => f('acquisition_date', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Depreciation Start *</label>
              <input type="date" value={form.depreciation_start_date} onChange={e => f('depreciation_start_date', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
              <p className="text-[10px] text-gray-400 mt-0.5">BIR full-month convention: use acquisition date</p>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Acquisition Cost (₱) *</label>
              <input type="number" min={0.01} step={0.01} value={form.acquisition_cost}
                onChange={e => onCostChange(e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900" />
            </div>
          </div>
        </div>

        {/* Depreciation Parameters */}
        <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Depreciation Parameters (PAS 16)</p>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Method</label>
              <select value={form.depreciation_method} onChange={e => f('depreciation_method', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                {METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Useful Life (months)</label>
              <input type="number" min={1} max={600} value={form.useful_life_months}
                onChange={e => f('useful_life_months', e.target.value)}
                disabled={form.depreciation_method === 'none'}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Salvage Value (₱)</label>
              <input type="number" min={0} step={0.01} value={form.salvage_value}
                onChange={e => f('salvage_value', e.target.value)}
                disabled={form.depreciation_method === 'none'}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
            </div>
          </div>
          {preview && (
            <div className="bg-gray-50 rounded px-3 py-2 text-xs text-gray-600 font-mono">
              Monthly depreciation (SLM preview): ₱ {preview.monthly.toLocaleString('en-PH', { minimumFractionDigits: 2 })} &nbsp;/&nbsp; Annual: ₱ {preview.annual.toLocaleString('en-PH', { minimumFractionDigits: 2 })}
            </div>
          )}
        </div>

        {/* GL Accounts */}
        <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Journal Entry — Acquisition</p>
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">Credit Account (Cash / AP / Bank)</label>
            <select value={form.credit_account_id} onChange={e => f('credit_account_id', e.target.value)}
              className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
              <option value="">— Post acquisition JE manually / skip —</option>
              {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
            </select>
            <p className="text-[10px] text-gray-400 mt-0.5">If selected, posts DR Asset Account / CR this account automatically.</p>
          </div>
        </div>

        <GLImpactPanel
          companyId={companyId}
          sourceDocType="FA"
          sourceDocId={null}
          previewRows={glPreviewRows}
          title="GL Impact — Acquisition"
        />

        <div className="flex gap-2">
          <button onClick={submit} disabled={saving}
            className="px-5 py-2 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {saving ? 'Registering…' : 'Register Asset'}
          </button>
        </div>
      </div>
    </div>
  )
}
