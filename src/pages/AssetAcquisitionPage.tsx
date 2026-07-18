import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'
import { GLImpactPanel, type GLImpactRow } from '@/components/GLImpactPanel'
import { LegacyTransactionWorkspace } from '@/components/document/LegacyTransactionWorkspace'

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
    <LegacyTransactionWorkspace title="Asset Acquisition" family="neutral" pattern="D" posting
      status="draft" identity={form.asset_name}
      financialFacts={[{ label: 'Acquisition Cost', value: acquisitionCost.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }, { label: 'Salvage Value', value: Number(form.salvage_value || 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }, { label: 'Depreciable Base', value: Math.max(0, acquisitionCost - Number(form.salvage_value || 0)).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }]}
      contextFacts={[{ label: 'Asset', value: form.asset_name || 'Not named' }, { label: 'Acquisition Date', value: form.acquisition_date }, { label: 'Depreciation Start', value: form.depreciation_start_date }, { label: 'Useful Life', value: `${form.useful_life_months || 0} months` }, { label: 'Method', value: METHODS.find(method => method.value === form.depreciation_method)?.label || form.depreciation_method }, { label: 'Monthly Depreciation', value: preview == null ? 'Not applicable' : preview.monthly.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }, { label: 'Annual Depreciation', value: preview == null ? 'Not applicable' : preview.annual.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }]}
      actions={[{ key: 'save', label: saving ? 'Registering…' : 'Register Asset', onClick: submit, disabled: saving, variant: 'primary' }]}
      headerFields={[
        { key: 'date', label: 'Acquisition Date *', card: 0, content: <input type="date" value={form.acquisition_date} onChange={e => f('acquisition_date', e.target.value)} className="pxl-input w-full" /> },
        { key: 'depreciation-date', label: 'Depreciation Start *', card: 0, content: <input type="date" value={form.depreciation_start_date} onChange={e => f('depreciation_start_date', e.target.value)} className="pxl-input w-full" /> },
        { key: 'branch', label: 'Branch', card: 0, content: <select value={form.branch_id} onChange={e => f('branch_id', e.target.value)} className="pxl-input w-full"><option value="">— None —</option>{branches.map(branch => <option key={branch.id} value={branch.id}>{branch.branch_name}</option>)}</select> },
        { key: 'supplier', label: 'Supplier', card: 1, span: 2, content: <select value={form.supplier_id} onChange={e => f('supplier_id', e.target.value)} className="pxl-input w-full"><option value="">— None —</option>{suppliers.map(supplier => <option key={supplier.id} value={supplier.id}>{supplier.supplier_name}</option>)}</select> },
        { key: 'department', label: 'Department', card: 1, content: <select value={form.department_id} onChange={e => f('department_id', e.target.value)} className="pxl-input w-full"><option value="">— None —</option>{departments.map(department => <option key={department.id} value={department.id}>{department.department_name}</option>)}</select> },
        { key: 'asset-name', label: 'Asset Name *', card: 2, span: 2, content: <input value={form.asset_name} onChange={e => f('asset_name', e.target.value)} className="pxl-input w-full" /> },
        { key: 'location', label: 'Location', card: 2, content: <input value={form.location} onChange={e => f('location', e.target.value)} className="pxl-input w-full" /> },
        { key: 'credit', label: 'Credit Account', card: 2, content: <select value={form.credit_account_id} onChange={e => f('credit_account_id', e.target.value)} className="pxl-input w-full"><option value="">Post JE manually / skip</option>{coa.map(account => <option key={account.id} value={account.id}>{account.account_code} — {account.account_name}</option>)}</select> },
      ]}
      tabContent={{
        validation: <div className="space-y-2">{error && <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>}{success && <div className="pxl-validation-message border border-green-200 bg-green-50 text-green-700">{success}</div>}</div>,
        gl: <GLImpactPanel companyId={companyId} sourceDocType="FA" sourceDocId={null} previewRows={glPreviewRows} title="GL Impact — Acquisition" />,
        notes: <textarea value={form.description} onChange={e => f('description', e.target.value)} rows={3} className="pxl-input w-full" aria-label="Asset description" />,
      }}>
    <div>
      <div className="overflow-x-auto">
        <table className="pxl-data-grid w-full">
          <thead><tr>{['Category','Serial Number','Acquisition Cost','Method','Useful Life','Salvage Value'].map(label => <th key={label} className="text-left">{label}</th>)}</tr></thead>
          <tbody><tr>
            <td><select value={form.category_id} onChange={e => onCategoryChange(e.target.value)} className="pxl-input w-full"><option value="">Select category…</option>{categories.map(category => <option key={category.id} value={category.id}>{category.category_code} — {category.category_name}</option>)}</select></td>
            <td><input value={form.serial_number} onChange={e => f('serial_number', e.target.value)} className="pxl-input w-full" /></td>
            <td><input type="number" min={0.01} step={0.01} value={form.acquisition_cost} onChange={e => onCostChange(e.target.value)} className="pxl-input w-full text-right" /></td>
            <td><select value={form.depreciation_method} onChange={e => f('depreciation_method', e.target.value)} className="pxl-input w-full">{METHODS.map(method => <option key={method.value} value={method.value}>{method.label}</option>)}</select></td>
            <td><input type="number" min={1} max={600} value={form.useful_life_months} onChange={e => f('useful_life_months', e.target.value)} disabled={form.depreciation_method === 'none'} className="pxl-input w-full text-right" /></td>
            <td><input type="number" min={0} step={0.01} value={form.salvage_value} onChange={e => f('salvage_value', e.target.value)} disabled={form.depreciation_method === 'none'} className="pxl-input w-full text-right" /></td>
          </tr></tbody>
        </table>

      </div>
    </div>
    </LegacyTransactionWorkspace>
  )
}
