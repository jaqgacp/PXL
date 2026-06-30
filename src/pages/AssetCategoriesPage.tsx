import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type Category = {
  id: string
  category_code: string
  category_name: string
  depreciation_method: string
  useful_life_months: number
  salvage_rate: number
  gl_asset_account_id: string | null
  gl_accum_depr_account_id: string | null
  gl_depr_expense_account_id: string | null
  gl_gain_on_disposal_account_id: string | null
  gl_loss_on_disposal_account_id: string | null
  gl_impairment_loss_account_id: string | null
  is_active: boolean
}

type COA = { id: string; account_code: string; account_name: string; account_type: string }

const METHODS = [
  { value: 'straight_line', label: 'Straight-Line (SLM)' },
  { value: 'declining_balance', label: 'Declining Balance (DDB)' },
  { value: 'sum_of_years', label: 'Sum-of-Years-Digits (SYD)' },
  { value: 'none', label: 'None (Non-depreciable)' },
]

const blank = (): Partial<Category> => ({
  category_code: '', category_name: '',
  depreciation_method: 'straight_line', useful_life_months: 60,
  salvage_rate: 0, is_active: true,
  gl_asset_account_id: null, gl_accum_depr_account_id: null,
  gl_depr_expense_account_id: null, gl_gain_on_disposal_account_id: null,
  gl_loss_on_disposal_account_id: null, gl_impairment_loss_account_id: null,
})

export default function AssetCategoriesPage() {
  const { companyId } = useAppCtx()
  const [categories, setCategories] = useState<Category[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [mode, setMode] = useState<'list' | 'form'>('list')
  const [editing, setEditing] = useState<Category | null>(null)
  const [form, setForm] = useState<Partial<Category>>(blank())
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: cats }, { data: accounts }] = await Promise.all([
      supabase.from('fixed_asset_categories').select('*').eq('company_id', companyId).order('category_code'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name,account_type')
        .eq('company_id', companyId).eq('is_postable', true).order('account_code'),
    ])
    setCategories((cats as Category[]) || [])
    setCoa((accounts as COA[]) || [])
  }, [companyId])

  useEffect(() => { load() }, [load])

  const openNew = () => { setEditing(null); setForm(blank()); setError(''); setMode('form') }
  const openEdit = (c: Category) => { setEditing(c); setForm({ ...c }); setError(''); setMode('form') }

  const save = async () => {
    if (!companyId) return
    if (!form.category_code?.trim()) { setError('Category code is required'); return }
    if (!form.category_name?.trim()) { setError('Category name is required'); return }
    if (form.depreciation_method !== 'none' && !form.useful_life_months) { setError('Useful life is required'); return }
    setSaving(true); setError('')
    const payload = { ...form, company_id: companyId }
    const { error: e } = editing
      ? await supabase.from('fixed_asset_categories').update(payload).eq('id', editing.id)
      : await supabase.from('fixed_asset_categories').insert(payload)
    setSaving(false)
    if (e) { setError(e.message); return }
    setMode('list'); load()
  }

  const toggleActive = async (c: Category) => {
    await supabase.from('fixed_asset_categories').update({ is_active: !c.is_active }).eq('id', c.id)
    load()
  }

  const f = (id: keyof Category, val: unknown) => setForm(p => ({ ...p, [id]: val }))

  const AccountSelect = ({ label, field }: { label: string; field: keyof Category }) => (
    <div>
      <label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>
      <select value={(form[field] as string) || ''} onChange={e => f(field, e.target.value || null)}
        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
        <option value="">— None —</option>
        {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
      </select>
    </div>
  )

  if (mode === 'form') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
          {editing ? 'Edit' : 'New'} Asset Category
        </span>
      </div>
      <div className="px-5 py-4 max-w-3xl space-y-5">
        {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}

        <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Category Details</p>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Category Code *</label>
              <input value={form.category_code || ''} onChange={e => f('category_code', e.target.value.toUpperCase())}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm font-mono focus:outline-none focus:ring-1 focus:ring-gray-900" placeholder="e.g. PPE-BLDG" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Category Name *</label>
              <input value={form.category_name || ''} onChange={e => f('category_name', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" placeholder="e.g. Buildings" />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Depreciation Method</label>
              <select value={form.depreciation_method || 'straight_line'} onChange={e => f('depreciation_method', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                {METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Useful Life (months)</label>
              <input type="number" min={1} max={600} value={form.useful_life_months || 60}
                onChange={e => f('useful_life_months', Number(e.target.value))}
                disabled={form.depreciation_method === 'none'}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50 disabled:text-gray-400" />
              {(form.useful_life_months || 0) > 0 && form.depreciation_method !== 'none' &&
                <p className="text-[10px] text-gray-400 mt-0.5">{Math.floor((form.useful_life_months || 0) / 12)} yrs {(form.useful_life_months || 0) % 12} mo</p>}
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Salvage Rate (%)</label>
              <input type="number" min={0} max={99} step={0.01} value={((form.salvage_rate || 0) * 100).toFixed(2)}
                onChange={e => f('salvage_rate', Number(e.target.value) / 100)}
                disabled={form.depreciation_method === 'none'}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm text-right font-mono focus:outline-none focus:ring-1 focus:ring-gray-900 disabled:bg-gray-50" />
            </div>
          </div>
          <div className="flex items-center gap-2 pt-1">
            <input type="checkbox" id="is_active" checked={form.is_active ?? true} onChange={e => f('is_active', e.target.checked)}
              className="rounded border-gray-300" />
            <label htmlFor="is_active" className="text-xs text-gray-600">Active</label>
          </div>
        </div>

        <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">GL Account Mapping</p>
          <div className="grid grid-cols-2 gap-4">
            <AccountSelect label="Asset Account (DR on acquisition)" field="gl_asset_account_id" />
            <AccountSelect label="Accumulated Depreciation (CR on depreciation)" field="gl_accum_depr_account_id" />
            <AccountSelect label="Depreciation Expense (DR on depreciation)" field="gl_depr_expense_account_id" />
            <AccountSelect label="Gain on Disposal (CR when proceeds > NBV)" field="gl_gain_on_disposal_account_id" />
            <AccountSelect label="Loss on Disposal (DR when proceeds < NBV)" field="gl_loss_on_disposal_account_id" />
            <AccountSelect label="Impairment Loss (DR on impairment)" field="gl_impairment_loss_account_id" />
          </div>
        </div>

        <div className="flex gap-2">
          <button onClick={save} disabled={saving}
            className="px-4 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {saving ? 'Saving…' : 'Save Category'}
          </button>
          <button onClick={() => setMode('list')} className="px-4 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">Cancel</button>
        </div>
      </div>
    </div>
  )

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Asset Categories</span>
        <button onClick={openNew} className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">+ New Category</button>
      </div>
      <div className="px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          {categories.length === 0 ? (
            <div className="py-14 text-center">
              <p className="text-sm font-medium text-gray-500">No asset categories yet</p>
              <p className="text-xs text-gray-400 mt-1">Create categories to define depreciation methods and GL accounts per asset class.</p>
            </div>
          ) : (
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Code','Name','Method','Life','Salvage %','Asset GL','Accum Depr GL','Status',''].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500 text-left whitespace-nowrap">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {categories.map(c => {
                  const assetAcct = coa.find(a => a.id === c.gl_asset_account_id)
                  const accumAcct = coa.find(a => a.id === c.gl_accum_depr_account_id)
                  return (
                    <tr key={c.id} className={`hover:bg-gray-50/60 ${!c.is_active ? 'opacity-50' : ''}`}>
                      <td className="px-3 py-2 font-mono font-semibold text-gray-900">{c.category_code}</td>
                      <td className="px-3 py-2 text-gray-800">{c.category_name}</td>
                      <td className="px-3 py-2 text-gray-600">{METHODS.find(m => m.value === c.depreciation_method)?.label || c.depreciation_method}</td>
                      <td className="px-3 py-2 font-mono text-gray-600 text-right">{c.depreciation_method === 'none' ? '—' : `${c.useful_life_months}mo`}</td>
                      <td className="px-3 py-2 font-mono text-gray-600 text-right">{c.depreciation_method === 'none' ? '—' : `${(c.salvage_rate * 100).toFixed(1)}%`}</td>
                      <td className="px-3 py-2 text-gray-500">{assetAcct ? `${assetAcct.account_code}` : <span className="text-amber-600">Not set</span>}</td>
                      <td className="px-3 py-2 text-gray-500">{accumAcct ? `${accumAcct.account_code}` : <span className="text-amber-600">Not set</span>}</td>
                      <td className="px-3 py-2">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${c.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>
                          {c.is_active ? 'Active' : 'Inactive'}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-right space-x-3">
                        <button onClick={() => openEdit(c)} className="text-xs text-blue-600 hover:text-blue-800">Edit</button>
                        <button onClick={() => toggleActive(c)} className="text-xs text-gray-500 hover:text-gray-700">{c.is_active ? 'Deactivate' : 'Activate'}</button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  )
}
