import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type Company = { id: string; registered_name: string }
type COA = { id: string; account_code: string; account_name: string }
type ItemCategory = {
  id: string; company_id: string; category_code: string; category_name: string
  parent_category_id: string | null; description: string | null; is_active: boolean
  companies?: { registered_name: string }; parent?: { category_name: string }
}
type UOM = {
  id: string; company_id: string; uom_code: string; description: string
  is_base_unit: boolean; base_uom_id: string | null; conversion_factor: number | null; is_active: boolean
  companies?: { registered_name: string }; base_uom?: { uom_code: string }
}
type VATCode = { id: string; vat_code: string; description: string; vat_classification: string; transaction_type: string }
type Item = {
  id: string; company_id: string; item_code: string; description: string; item_type: string
  category_id: string; uom_id: string; barcode: string | null
  standard_selling_price: number; standard_cost: number; price_is_vat_inclusive: boolean
  default_sales_vat_id: string | null; default_purchase_vat_id: string | null
  costing_method: string | null
  min_stock_level: number | null; reorder_point: number | null; is_active: boolean
  companies?: { registered_name: string }
  item_categories?: { category_name: string }
  units_of_measure?: { uom_code: string }
  vat_codes_sales?: { vat_code: string }
}

const ITEM_TYPES = [
  { value: 'inventory_item', label: 'Inventory Item (tracked in stock)' },
  { value: 'service', label: 'Service (no stock movement)' },
  { value: 'non_inventory', label: 'Non-Inventory (bought/sold, not tracked)' },
]
const COSTING_METHODS = [
  { value: 'fifo', label: 'FIFO (First In, First Out)' },
  { value: 'weighted_average', label: 'Weighted Average Cost' },
  { value: 'specific_identification', label: 'Specific Identification' },
]
const TYPE_BADGE: Record<string, string> = {
  inventory_item: 'bg-blue-50 text-blue-700',
  service: 'bg-purple-50 text-purple-700',
  non_inventory: 'bg-gray-100 text-gray-600',
}

const inp = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
const lbl = 'block text-xs font-medium text-gray-500 mb-1'
const sec = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
const hd  = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

export default function ItemCatalogPage() {
  const [tab, setTab] = useState<'items' | 'categories' | 'uom'>('items')
  const [companies, setCompanies] = useState<Company[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [categories, setCategories] = useState<ItemCategory[]>([])
  const [uoms, setUoms] = useState<UOM[]>([])
  const [items, setItems] = useState<Item[]>([])
  const [vatCodes, setVatCodes] = useState<VATCode[]>([])
  const [filterCompany, setFilterCompany] = useState('')
  const [filterType, setFilterType] = useState('')
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'inactive'>('all')
  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  // Forms
  const [catForm, setCatForm] = useState({ company_id: '', category_code: '', category_name: '', parent_category_id: '', description: '', sales_account_id: '', cogs_account_id: '', inventory_account_id: '', adj_account_id: '' })
  const [uomForm, setUomForm] = useState({ company_id: '', uom_code: '', description: '', is_base_unit: true, base_uom_id: '', conversion_factor: '' })
  const [itemForm, setItemForm] = useState({
    company_id: '', item_code: '', description: '', description_long: '', item_type: 'inventory_item',
    category_id: '', uom_id: '', barcode: '',
    standard_selling_price: '0', standard_cost: '0', price_is_vat_inclusive: false,
    default_sales_vat_id: '', default_purchase_vat_id: '',
    sales_account_id: '', cogs_account_id: '', inventory_account_id: '', purchase_expense_account_id: '',
    costing_method: 'weighted_average', min_stock_level: '', reorder_point: '',
  })

  const fetchAll = async () => {
    const [cat, uom, itm] = await Promise.all([
      supabase.from('item_categories').select('*, companies(registered_name), parent:parent_category_id(category_name)').order('category_code'),
      supabase.from('units_of_measure').select('*, companies(registered_name), base_uom:base_uom_id(uom_code)').order('uom_code'),
      supabase.from('items').select('*, companies(registered_name), item_categories(category_name), units_of_measure(uom_code)').order('item_code'),
    ])
    setCategories((cat.data as ItemCategory[]) || [])
    setUoms((uom.data as UOM[]) || [])
    setItems((itm.data as Item[]) || [])
  }
  useEffect(() => {
    fetchAll()
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
    supabase.from('vat_codes').select('id,vat_code,description,vat_classification,transaction_type').eq('is_active', true).order('vat_code').then(({ data }) => setVatCodes(data || []))
  }, [])

  // Load COA when company changes in item form
  useEffect(() => {
    const cid = itemForm.company_id || catForm.company_id
    if (!cid) { setCoa([]); return }
    supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', cid).eq('is_active', true).eq('is_postable', true).order('account_code').then(({ data }) => setCoa(data || []))
  }, [itemForm.company_id, catForm.company_id])

  const setC = (k: string, v: string) => { setSaved(false); setCatForm(f => ({ ...f, [k]: v })) }
  const setU = (k: string, v: string | boolean) => { setSaved(false); setUomForm(f => ({ ...f, [k]: v })) }
  const setI = (k: string, v: string | boolean) => { setSaved(false); setItemForm(f => ({ ...f, [k]: v })) }

  const openCreate = () => { setEditId(null); setShowForm(true); setSaved(false) }

  const openEditCat = (c: ItemCategory) => {
    setCatForm({ company_id: c.company_id, category_code: c.category_code, category_name: c.category_name, parent_category_id: c.parent_category_id || '', description: c.description || '', sales_account_id: '', cogs_account_id: '', inventory_account_id: '', adj_account_id: '' })
    setEditId(c.id); setShowForm(true); setSaved(false)
  }
  const openEditUom = (u: UOM) => {
    setUomForm({ company_id: u.company_id, uom_code: u.uom_code, description: u.description, is_base_unit: u.is_base_unit, base_uom_id: u.base_uom_id || '', conversion_factor: u.conversion_factor ? String(u.conversion_factor) : '' })
    setEditId(u.id); setShowForm(true); setSaved(false)
  }
  const openEditItem = (item: Item) => {
    setItemForm({
      company_id: item.company_id, item_code: item.item_code, description: item.description,
      description_long: '', item_type: item.item_type, category_id: item.category_id,
      uom_id: item.uom_id, barcode: item.barcode || '',
      standard_selling_price: String(item.standard_selling_price),
      standard_cost: String(item.standard_cost),
      price_is_vat_inclusive: item.price_is_vat_inclusive,
      default_sales_vat_id: item.default_sales_vat_id || '',
      default_purchase_vat_id: item.default_purchase_vat_id || '',
      sales_account_id: '', cogs_account_id: '', inventory_account_id: '', purchase_expense_account_id: '',
      costing_method: item.costing_method || 'weighted_average',
      min_stock_level: item.min_stock_level ? String(item.min_stock_level) : '',
      reorder_point: item.reorder_point ? String(item.reorder_point) : '',
    })
    setEditId(item.id); setShowForm(true); setSaved(false)
  }

  const handleSave = async () => {
    setSaving(true)
    let error: { message: string } | null = null
    if (tab === 'categories') {
      const payload = { company_id: catForm.company_id, category_code: catForm.category_code.toUpperCase(), category_name: catForm.category_name, parent_category_id: catForm.parent_category_id || null, description: catForm.description || null, sales_account_id: catForm.sales_account_id || null, cogs_account_id: catForm.cogs_account_id || null, inventory_account_id: catForm.inventory_account_id || null, adj_account_id: catForm.adj_account_id || null }
      const res = editId ? await supabase.from('item_categories').update(payload).eq('id', editId) : await supabase.from('item_categories').insert([payload])
      error = res.error
    } else if (tab === 'uom') {
      const payload = { company_id: uomForm.company_id, uom_code: uomForm.uom_code.toUpperCase(), description: uomForm.description, is_base_unit: uomForm.is_base_unit, base_uom_id: !uomForm.is_base_unit ? uomForm.base_uom_id || null : null, conversion_factor: !uomForm.is_base_unit && uomForm.conversion_factor ? parseFloat(uomForm.conversion_factor) : null }
      const res = editId ? await supabase.from('units_of_measure').update(payload).eq('id', editId) : await supabase.from('units_of_measure').insert([payload])
      error = res.error
    } else {
      const isInventory = itemForm.item_type === 'inventory_item'
      const payload = {
        company_id: itemForm.company_id, item_code: itemForm.item_code.toUpperCase(),
        description: itemForm.description, description_long: itemForm.description_long || null,
        item_type: itemForm.item_type, category_id: itemForm.category_id, uom_id: itemForm.uom_id,
        barcode: itemForm.barcode || null,
        standard_selling_price: parseFloat(itemForm.standard_selling_price) || 0,
        standard_cost: parseFloat(itemForm.standard_cost) || 0,
        price_is_vat_inclusive: itemForm.price_is_vat_inclusive,
        default_sales_vat_id: itemForm.default_sales_vat_id || null,
        default_purchase_vat_id: itemForm.default_purchase_vat_id || null,
        sales_account_id: itemForm.sales_account_id || null,
        cogs_account_id: itemForm.cogs_account_id || null,
        inventory_account_id: itemForm.inventory_account_id || null,
        purchase_expense_account_id: itemForm.purchase_expense_account_id || null,
        costing_method: isInventory ? itemForm.costing_method : null,
        min_stock_level: itemForm.min_stock_level ? parseFloat(itemForm.min_stock_level) : null,
        reorder_point: itemForm.reorder_point ? parseFloat(itemForm.reorder_point) : null,
      }
      const res = editId ? await supabase.from('items').update(payload).eq('id', editId) : await supabase.from('items').insert([payload])
      error = res.error
    }
    if (error) alert('Error: ' + error.message)
    else { setSaved(true); fetchAll() }
    setSaving(false)
  }

  const toggleActive = async (id: string, table: 'item_categories' | 'units_of_measure' | 'items', current: boolean) => {
    await supabase.from(table).update({ is_active: !current }).eq('id', id)
    fetchAll()
  }

  const formCompanyId = tab === 'categories' ? catForm.company_id : tab === 'uom' ? uomForm.company_id : itemForm.company_id
  const filteredCats = categories.filter(c => !formCompanyId || c.company_id === formCompanyId)
  const filteredUoms = uoms.filter(u => !formCompanyId || u.company_id === formCompanyId).filter(u => u.is_base_unit)
  const outputVatCodes = vatCodes.filter(v => v.transaction_type === 'output_vat')
  const inputVatCodes = vatCodes.filter(v => v.transaction_type === 'input_vat')
  const filterCats = categories.filter(c => (!filterCompany || c.company_id === filterCompany) && (filterStatus === 'all' || (filterStatus === 'active' ? c.is_active : !c.is_active)) && (!search || c.category_code.toLowerCase().includes(search.toLowerCase()) || c.category_name.toLowerCase().includes(search.toLowerCase())))
  const filterUomList = uoms.filter(u => (!filterCompany || u.company_id === filterCompany) && (filterStatus === 'all' || (filterStatus === 'active' ? u.is_active : !u.is_active)) && (!search || u.uom_code.toLowerCase().includes(search.toLowerCase()) || u.description.toLowerCase().includes(search.toLowerCase())))
  const filterItems = items.filter(i => (!filterCompany || i.company_id === filterCompany) && (filterStatus === 'all' || (filterStatus === 'active' ? i.is_active : !i.is_active)) && (!filterType || i.item_type === filterType) && (!search || i.item_code.toLowerCase().includes(search.toLowerCase()) || i.description.toLowerCase().includes(search.toLowerCase())))

  if (showForm) return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">
            {editId ? 'Edit' : 'Create'} {tab === 'categories' ? 'Item Category' : tab === 'uom' ? 'Unit of Measure' : 'Item / Service'}
          </h1>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)} className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">Cancel</button>
          <button onClick={handleSave} disabled={saving} className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update' : 'Save'}
          </button>
        </div>
      </div>

      {tab === 'categories' && <>
        <div className={sec}><h2 className={hd}>Section 1 — Category Identity</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
              <select value={catForm.company_id} onChange={e => setC('company_id', e.target.value)} className={inp}>
                <option value="">Select company...</option>
                {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select></div>
            <div><label className={lbl}>Category Code <span className="text-red-500">*</span></label>
              <input value={catForm.category_code} onChange={e => setC('category_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., CAT-ELEC, CAT-SVCS" /></div>
            <div className="col-span-2"><label className={lbl}>Category Name <span className="text-red-500">*</span></label>
              <input value={catForm.category_name} onChange={e => setC('category_name', e.target.value)} className={inp} placeholder="e.g., Electronics, Raw Materials, IT Services" /></div>
            <div><label className={lbl}>Parent Category</label>
              <select value={catForm.parent_category_id} onChange={e => setC('parent_category_id', e.target.value)} className={inp}>
                <option value="">None (Top-level)</option>
                {filteredCats.filter(c => c.id !== editId).map(c => <option key={c.id} value={c.id}>{c.category_code} — {c.category_name}</option>)}
              </select></div>
            <div className="col-span-2"><label className={lbl}>Description</label>
              <textarea value={catForm.description} onChange={e => setC('description', e.target.value)} className={inp + ' h-16 resize-none'} /></div>
          </div>
        </div>
        <div className={sec}><h2 className={hd}>Section 2 — Default GL Accounts (Auto-fill chain fallback)</h2>
          <div className="bg-blue-50 border border-blue-100 rounded px-3 py-2 mb-2 text-xs text-blue-700">
            These accounts are used when individual item-level GL accounts are not set. They form the second tier of the auto-posting chain: Item → Category → Module default.
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Sales / Revenue Account</label>
              <select value={catForm.sales_account_id} onChange={e => setC('sales_account_id', e.target.value)} className={inp}>
                <option value="">Not set (use module default)</option>
                {coa.filter(a => a.account_code.startsWith('4')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select></div>
            <div><label className={lbl}>COGS / Cost of Sales Account</label>
              <select value={catForm.cogs_account_id} onChange={e => setC('cogs_account_id', e.target.value)} className={inp}>
                <option value="">Not set</option>
                {coa.filter(a => a.account_code.startsWith('5')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select></div>
            <div><label className={lbl}>Inventory Asset Account</label>
              <select value={catForm.inventory_account_id} onChange={e => setC('inventory_account_id', e.target.value)} className={inp}>
                <option value="">Not set</option>
                {coa.filter(a => a.account_code.startsWith('1')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select></div>
            <div><label className={lbl}>Inventory Adjustment / Write-off Account</label>
              <select value={catForm.adj_account_id} onChange={e => setC('adj_account_id', e.target.value)} className={inp}>
                <option value="">Not set</option>
                {coa.filter(a => a.account_code.startsWith('5') || a.account_code.startsWith('6')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select></div>
          </div>
        </div>
      </>}

      {tab === 'uom' && <>
        <div className={sec}><h2 className={hd}>Section 1 — Unit of Measure</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
              <select value={uomForm.company_id} onChange={e => setU('company_id', e.target.value)} className={inp}>
                <option value="">Select company...</option>
                {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select></div>
            <div><label className={lbl}>UOM Code <span className="text-red-500">*</span></label>
              <input value={uomForm.uom_code} onChange={e => setU('uom_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., PCS, BOX, KG, LTR, SVC" /></div>
            <div className="col-span-2"><label className={lbl}>Description <span className="text-red-500">*</span></label>
              <input value={uomForm.description} onChange={e => setU('description', e.target.value)} className={inp} placeholder="e.g., Pieces, Box, Kilograms, Liters, Service Rendered" /></div>
            <div className="col-span-2 flex items-center gap-2 pt-1">
              <input type="checkbox" id="is_base" checked={uomForm.is_base_unit} onChange={e => setU('is_base_unit', e.target.checked)} className="rounded border-gray-300" />
              <label htmlFor="is_base" className="text-sm text-gray-700">Base unit (smallest indivisible unit — e.g., PCS is base for BOX)</label>
            </div>
          </div>
        </div>
        {!uomForm.is_base_unit && (
          <div className={sec}><h2 className={hd}>Section 2 — Conversion (required for non-base units)</h2>
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>Base UOM <span className="text-red-500">*</span></label>
                <select value={uomForm.base_uom_id} onChange={e => setU('base_uom_id', e.target.value)} className={inp}>
                  <option value="">Select base unit...</option>
                  {filteredUoms.map(u => <option key={u.id} value={u.id}>{u.uom_code} — {u.description}</option>)}
                </select></div>
              <div><label className={lbl}>Conversion Factor <span className="text-red-500">*</span></label>
                <input type="number" min="0.000001" step="0.000001" value={uomForm.conversion_factor} onChange={e => setU('conversion_factor', e.target.value)} className={inp} placeholder="e.g., 12 (1 BOX = 12 PCS)" /></div>
              {uomForm.base_uom_id && uomForm.conversion_factor && (
                <div className="col-span-2 bg-gray-50 border border-gray-200 rounded px-3 py-2 text-xs text-gray-600">
                  1 {uomForm.uom_code || '—'} = {uomForm.conversion_factor} {filteredUoms.find(u => u.id === uomForm.base_uom_id)?.uom_code || '—'}
                </div>
              )}
            </div>
          </div>
        )}
      </>}

      {tab === 'items' && <>
        <div className={sec}><h2 className={hd}>Section 1 — Basic Information</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Company <span className="text-red-500">*</span></label>
              <select value={itemForm.company_id} onChange={e => setI('company_id', e.target.value)} className={inp}>
                <option value="">Select company...</option>
                {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
              </select></div>
            <div><label className={lbl}>Item Type <span className="text-red-500">*</span></label>
              <select value={itemForm.item_type} onChange={e => setI('item_type', e.target.value)} className={inp}>
                {ITEM_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
              </select></div>
            <div><label className={lbl}>Item Code <span className="text-red-500">*</span></label>
              <input value={itemForm.item_code} onChange={e => setI('item_code', e.target.value.toUpperCase())} className={inp} placeholder="e.g., ITM-0001, SVC-001" /></div>
            <div><label className={lbl}>Category <span className="text-red-500">*</span></label>
              <select value={itemForm.category_id} onChange={e => setI('category_id', e.target.value)} className={inp}>
                <option value="">Select category...</option>
                {filteredCats.filter(c => c.is_active).map(c => <option key={c.id} value={c.id}>{c.category_code} — {c.category_name}</option>)}
              </select></div>
            <div className="col-span-2"><label className={lbl}>Description (as printed on invoices) <span className="text-red-500">*</span></label>
              <input value={itemForm.description} onChange={e => setI('description', e.target.value)} className={inp} /></div>
            <div><label className={lbl}>Unit of Measure <span className="text-red-500">*</span></label>
              <select value={itemForm.uom_id} onChange={e => setI('uom_id', e.target.value)} className={inp}>
                <option value="">Select UOM...</option>
                {uoms.filter(u => (!itemForm.company_id || u.company_id === itemForm.company_id) && u.is_active).map(u => <option key={u.id} value={u.id}>{u.uom_code} — {u.description}</option>)}
              </select></div>
            <div><label className={lbl}>Barcode / SKU</label>
              <input value={itemForm.barcode} onChange={e => setI('barcode', e.target.value)} className={inp} placeholder="Optional" /></div>
            <div className="col-span-2"><label className={lbl}>Extended Description (for PO/quotes)</label>
              <textarea value={itemForm.description_long} onChange={e => setI('description_long', e.target.value)} className={inp + ' h-16 resize-none'} /></div>
          </div>
        </div>

        <div className={sec}><h2 className={hd}>Section 2 — Pricing</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Standard Selling Price (₱) <span className="text-red-500">*</span></label>
              <input type="number" min="0" step="0.01" value={itemForm.standard_selling_price} onChange={e => setI('standard_selling_price', e.target.value)} className={inp} /></div>
            <div><label className={lbl}>Standard Cost (₱) <span className="text-red-500">*</span></label>
              <input type="number" min="0" step="0.01" value={itemForm.standard_cost} onChange={e => setI('standard_cost', e.target.value)} className={inp} /></div>
            <div className="col-span-2 flex items-center gap-2">
              <input type="checkbox" id="vat_incl" checked={itemForm.price_is_vat_inclusive} onChange={e => setI('price_is_vat_inclusive', e.target.checked)} className="rounded border-gray-300" />
              <label htmlFor="vat_incl" className="text-sm text-gray-700">Selling price is VAT-inclusive (system will back-compute VAT on invoices)</label>
            </div>
          </div>
        </div>

        <div className={sec}><h2 className={hd}>Section 3 — Tax Defaults</h2>
          <div className="bg-blue-50 border border-blue-100 rounded px-3 py-2 mb-2 text-xs text-blue-700">
            VAT codes auto-fill on every Sales Invoice or Purchase Invoice line when this item is selected.
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Default Sales VAT Code <span className="text-red-500">*</span></label>
              <select value={itemForm.default_sales_vat_id} onChange={e => setI('default_sales_vat_id', e.target.value)} className={inp}>
                <option value="">Select output VAT code...</option>
                {outputVatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code} — {v.description}</option>)}
              </select></div>
            <div><label className={lbl}>Default Purchase VAT Code <span className="text-red-500">*</span></label>
              <select value={itemForm.default_purchase_vat_id} onChange={e => setI('default_purchase_vat_id', e.target.value)} className={inp}>
                <option value="">Select input VAT code...</option>
                {inputVatCodes.map(v => <option key={v.id} value={v.id}>{v.vat_code} — {v.description}</option>)}
              </select></div>
          </div>
        </div>

        <div className={sec}><h2 className={hd}>Section 4 — Accounting GL Defaults (Highest priority in auto-posting chain)</h2>
          <div className="grid grid-cols-2 gap-4">
            <div><label className={lbl}>Sales Revenue Account</label>
              <select value={itemForm.sales_account_id} onChange={e => setI('sales_account_id', e.target.value)} className={inp}>
                <option value="">Use category default</option>
                {coa.filter(a => a.account_code.startsWith('4')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select></div>
            <div><label className={lbl}>COGS / Cost of Sales Account</label>
              <select value={itemForm.cogs_account_id} onChange={e => setI('cogs_account_id', e.target.value)} className={inp}>
                <option value="">Use category default</option>
                {coa.filter(a => a.account_code.startsWith('5')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
              </select></div>
            {itemForm.item_type === 'inventory_item' && (
              <div><label className={lbl}>Inventory Asset Account</label>
                <select value={itemForm.inventory_account_id} onChange={e => setI('inventory_account_id', e.target.value)} className={inp}>
                  <option value="">Use category default</option>
                  {coa.filter(a => a.account_code.startsWith('1')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                </select></div>
            )}
            {(itemForm.item_type === 'service' || itemForm.item_type === 'non_inventory') && (
              <div><label className={lbl}>Purchase Expense Account</label>
                <select value={itemForm.purchase_expense_account_id} onChange={e => setI('purchase_expense_account_id', e.target.value)} className={inp}>
                  <option value="">Use category default</option>
                  {coa.filter(a => a.account_code.startsWith('6') || a.account_code.startsWith('5')).map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
                </select></div>
            )}
          </div>
        </div>

        {itemForm.item_type === 'inventory_item' && (
          <div className={sec}><h2 className={hd}>Section 5 — Inventory Settings</h2>
            <div className="grid grid-cols-2 gap-4">
              <div><label className={lbl}>Costing Method <span className="text-red-500">*</span></label>
                <select value={itemForm.costing_method} onChange={e => setI('costing_method', e.target.value)} className={inp}>
                  {COSTING_METHODS.map(m => <option key={m.value} value={m.value}>{m.label}</option>)}
                </select></div>
              <div><label className={lbl}>Minimum Stock Level (alert threshold)</label>
                <input type="number" min="0" step="0.0001" value={itemForm.min_stock_level} onChange={e => setI('min_stock_level', e.target.value)} className={inp} /></div>
              <div><label className={lbl}>Reorder Point (purchase suggestion trigger)</label>
                <input type="number" min="0" step="0.0001" value={itemForm.reorder_point} onChange={e => setI('reorder_point', e.target.value)} className={inp} /></div>
            </div>
          </div>
        )}
      </>}
    </div>
  )

  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Item Catalog</h1>
        <p className="text-sm text-gray-500 mt-0.5">Items, services, categories, and units of measure</p></div>
      <div className="flex border-b border-gray-200">
        {(['items','categories','uom'] as const).map(t => (
          <button key={t} onClick={() => { setTab(t); setSearch(''); setFilterCompany(''); setFilterStatus('all'); setFilterType('') }}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${tab === t ? 'border-gray-900 text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>
            {t === 'items' ? 'Items & Services' : t === 'categories' ? 'Item Categories' : 'Units of Measure'}
          </button>
        ))}
      </div>
      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-48 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search..." />
        <select value={filterCompany} onChange={e => setFilterCompany(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="">All Companies</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
        {tab === 'items' && (
          <select value={filterType} onChange={e => setFilterType(e.target.value)}
            className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
            <option value="">All Types</option>
            {ITEM_TYPES.map(t => <option key={t.value} value={t.value}>{t.label.split(' (')[0]}</option>)}
          </select>
        )}
        <select value={filterStatus} onChange={e => setFilterStatus(e.target.value as typeof filterStatus)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="all">All Status</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
        <div className="ml-auto">
          <button onClick={openCreate} className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create {tab === 'items' ? 'Item' : tab === 'categories' ? 'Category' : 'UOM'}
          </button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        {tab === 'categories' ? (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Code</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Category Name</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Parent</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {filterCats.length === 0 ? <tr><td colSpan={6} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Item Categories</p><p className="text-sm mt-1">Create categories to organize your item catalog.</p></td></tr>
              : filterCats.map((c, i) => (
                <tr key={c.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{c.category_code}</td>
                  <td className="px-4 py-3 text-gray-900">{c.parent_category_id ? <span className="pl-3 text-gray-700">{c.category_name}</span> : <span className="font-medium">{c.category_name}</span>}</td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{c.parent ? (c.parent as ItemCategory).category_name : '—'}</td>
                  <td className="px-4 py-3 text-gray-500">{c.companies?.registered_name}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${c.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{c.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openEditCat(c)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleActive(c.id, 'item_categories', c.is_active)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{c.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : tab === 'uom' ? (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">UOM Code</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Description</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Base Unit?</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Conversion</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Company</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {filterUomList.length === 0 ? <tr><td colSpan={7} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Units of Measure</p><p className="text-sm mt-1">Create base units like PCS, KG, LTR first, then conversion units.</p></td></tr>
              : filterUomList.map((u, i) => (
                <tr key={u.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{u.uom_code}</td>
                  <td className="px-4 py-3 text-gray-700">{u.description}</td>
                  <td className="px-4 py-3">{u.is_base_unit ? <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-50 text-blue-700">Base</span> : <span className="text-gray-400 text-xs">—</span>}</td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{!u.is_base_unit && u.conversion_factor && u.base_uom ? `1 ${u.uom_code} = ${u.conversion_factor} ${(u.base_uom as UOM).uom_code}` : '—'}</td>
                  <td className="px-4 py-3 text-gray-500">{u.companies?.registered_name}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${u.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{u.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openEditUom(u)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleActive(u.id, 'units_of_measure', u.is_active)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{u.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <table className="w-full text-sm">
            <thead><tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Code</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Description</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Type</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Category</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">UOM</th>
              <th className="text-right px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Selling Price</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr></thead>
            <tbody>
              {filterItems.length === 0 ? <tr><td colSpan={8} className="text-center py-16 text-gray-400"><p className="font-medium text-gray-500">No Items Found</p><p className="text-sm mt-1">Create item categories and units of measure first, then add items.</p></td></tr>
              : filterItems.map((item, i) => (
                <tr key={item.id} className={`border-b border-gray-100 hover:bg-gray-50 ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                  <td className="px-4 py-3 font-mono font-medium text-gray-900">{item.item_code}</td>
                  <td className="px-4 py-3 text-gray-900">{item.description}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${TYPE_BADGE[item.item_type] || 'bg-gray-100 text-gray-600'}`}>{ITEM_TYPES.find(t => t.value === item.item_type)?.label.split(' (')[0] || item.item_type}</span></td>
                  <td className="px-4 py-3 text-gray-500 text-xs">{item.item_categories?.category_name || '—'}</td>
                  <td className="px-4 py-3 font-mono text-gray-600 text-xs">{item.units_of_measure?.uom_code || '—'}</td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-gray-900">{Number(item.standard_selling_price).toLocaleString('en-PH', { minimumFractionDigits: 2 })}</td>
                  <td className="px-4 py-3"><span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${item.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>{item.is_active ? 'Active' : 'Inactive'}</span></td>
                  <td className="px-4 py-3"><div className="flex items-center gap-2">
                    <button onClick={() => openEditItem(item)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => toggleActive(item.id, 'items', item.is_active)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">{item.is_active ? 'Deactivate' : 'Activate'}</button>
                  </div></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {(tab === 'categories' ? filterCats : tab === 'uom' ? filterUomList : filterItems).length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {(tab === 'categories' ? filterCats : tab === 'uom' ? filterUomList : filterItems).length} records
          </div>
        )}
      </div>
    </div>
  )
}
