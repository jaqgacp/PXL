import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import type { TablesInsert } from '@/lib/database.types'
import { useAppCtx } from '@/lib/context'

type Warehouse = {
  id: string; company_id: string; branch_id: string | null
  warehouse_code: string; warehouse_name: string; warehouse_type: string
  address: string | null; gl_inventory_account_id: string | null
  gl_variance_account_id: string | null; is_active: boolean
}
type Zone = { id: string; warehouse_id: string; zone_code: string; zone_name: string; is_active: boolean }
type Branch = { id: string; branch_name: string }
type COA = { id: string; account_code: string; account_name: string }

const TYPES = [
  { value: 'main', label: 'Main Warehouse' },
  { value: 'transit', label: 'Transit / In-Transit' },
  { value: 'consignment', label: 'Consignment' },
  { value: 'damaged', label: 'Damaged / Quarantine' },
]

const blank = (): Partial<Warehouse> => ({
  warehouse_code: '', warehouse_name: '', warehouse_type: 'main',
  address: '', is_active: true, gl_inventory_account_id: null, gl_variance_account_id: null,
})

export default function WarehousesPage() {
  const { companyId } = useAppCtx()
  const [warehouses, setWarehouses] = useState<Warehouse[]>([])
  const [zones, setZones] = useState<Zone[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [coa, setCoa] = useState<COA[]>([])
  const [mode, setMode] = useState<'list' | 'form' | 'zones'>('list')
  const [editing, setEditing] = useState<Warehouse | null>(null)
  const [activeWh, setActiveWh] = useState<Warehouse | null>(null)
  const [form, setForm] = useState<Partial<Warehouse>>(blank())
  const [zoneForm, setZoneForm] = useState({ zone_code: '', zone_name: '' })
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!companyId) return
    const [{ data: whs }, { data: zns }, { data: brs }, { data: accts }] = await Promise.all([
      supabase.from('warehouses').select('*').eq('company_id', companyId).order('warehouse_code'),
      supabase.from('warehouse_zones').select('*').order('zone_code'),
      supabase.from('branches').select('id,branch_name').eq('company_id', companyId).order('branch_name'),
      supabase.from('chart_of_accounts').select('id,account_code,account_name').eq('company_id', companyId).eq('is_postable', true).order('account_code'),
    ])
    setWarehouses((whs as Warehouse[]) || [])
    setZones((zns as Zone[]) || [])
    setBranches((brs as Branch[]) || [])
    setCoa((accts as COA[]) || [])
  }, [companyId])

  useEffect(() => { load() }, [load])

  const f = (k: keyof Warehouse, v: unknown) => setForm(p => ({ ...p, [k]: v }))

  const save = async () => {
    if (!companyId) return
    if (!form.warehouse_code?.trim()) { setError('Code required'); return }
    if (!form.warehouse_name?.trim()) { setError('Name required'); return }
    setSaving(true); setError('')
    const payload = { ...form, company_id: companyId }
    const { error: e } = editing
      ? await supabase.from('warehouses').update(payload).eq('id', editing.id)
      : await supabase.from('warehouses').insert(payload as TablesInsert<'warehouses'>)
    setSaving(false)
    if (e) { setError(e.message); return }
    setMode('list'); load()
  }

  const addZone = async () => {
    if (!activeWh || !zoneForm.zone_code.trim() || !zoneForm.zone_name.trim()) return
    await supabase.from('warehouse_zones').insert({ ...zoneForm, warehouse_id: activeWh.id })
    setZoneForm({ zone_code: '', zone_name: '' }); load()
  }

  const COASelect = ({ label, field }: { label: string; field: keyof Warehouse }) => (
    <div>
      <label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>
      <select value={(form[field] as string) || ''} onChange={e => f(field, e.target.value || null)}
        className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
        <option value="">— None —</option>
        {coa.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
      </select>
    </div>
  )

  if (mode === 'zones' && activeWh) {
    const whZones = zones.filter(z => z.warehouse_id === activeWh.id)
    return (
      <div>
        <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
          <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900">← Back</button>
          <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Zones — {activeWh.warehouse_name}</span>
        </div>
        <div className="px-5 py-4 max-w-xl space-y-4">
          <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-400">Add Zone</p>
            <div className="flex gap-2">
              <input value={zoneForm.zone_code} onChange={e => setZoneForm(p => ({ ...p, zone_code: e.target.value.toUpperCase() }))}
                placeholder="Code" className="border border-gray-300 rounded px-2.5 py-1.5 text-sm w-24 font-mono focus:outline-none focus:ring-1 focus:ring-gray-900" />
              <input value={zoneForm.zone_name} onChange={e => setZoneForm(p => ({ ...p, zone_name: e.target.value }))}
                placeholder="Zone name" className="border border-gray-300 rounded px-2.5 py-1.5 text-sm flex-1 focus:outline-none focus:ring-1 focus:ring-gray-900" />
              <button onClick={addZone} className="px-3 py-1.5 bg-gray-900 text-white rounded text-xs font-medium hover:bg-gray-800">Add</button>
            </div>
          </div>
          <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            {whZones.length === 0 ? (
              <div className="py-10 text-center text-xs text-gray-400">No zones defined</div>
            ) : (
              <table className="w-full text-xs">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>{['Code','Name','Active'].map(h => <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left">{h}</th>)}</tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {whZones.map(z => (
                    <tr key={z.id} className="hover:bg-gray-50/60">
                      <td className="px-3 py-2 font-mono font-semibold text-gray-900">{z.zone_code}</td>
                      <td className="px-3 py-2 text-gray-800">{z.zone_name}</td>
                      <td className="px-3 py-2">
                        <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${z.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>
                          {z.is_active ? 'Active' : 'Inactive'}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      </div>
    )
  }

  if (mode === 'form') return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <button onClick={() => setMode('list')} className="text-xs text-gray-500 hover:text-gray-900">← Back</button>
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">{editing ? 'Edit' : 'New'} Warehouse</span>
      </div>
      <div className="px-5 py-4 max-w-2xl space-y-4">
        {error && <div className="text-xs text-red-600 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>}
        <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Warehouse Code *</label>
              <input value={form.warehouse_code || ''} onChange={e => f('warehouse_code', e.target.value.toUpperCase())}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm font-mono focus:outline-none focus:ring-1 focus:ring-gray-900" placeholder="WH-MAIN" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Warehouse Name *</label>
              <input value={form.warehouse_name || ''} onChange={e => f('warehouse_name', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Type</label>
              <select value={form.warehouse_type || 'main'} onChange={e => f('warehouse_type', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                {TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Branch</label>
              <select value={form.branch_id || ''} onChange={e => f('branch_id', e.target.value || null)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-xs focus:outline-none focus:ring-1 focus:ring-gray-900">
                <option value="">— None —</option>
                {branches.map(b => <option key={b.id} value={b.id}>{b.branch_name}</option>)}
              </select>
            </div>
            <div className="col-span-2">
              <label className="block text-xs font-medium text-gray-600 mb-1">Address</label>
              <input value={form.address || ''} onChange={e => f('address', e.target.value)}
                className="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900" />
            </div>
            <COASelect label="Inventory GL Account" field="gl_inventory_account_id" />
            <COASelect label="Variance GL Account (Count variances)" field="gl_variance_account_id" />
          </div>
          <div className="flex items-center gap-2">
            <input type="checkbox" checked={form.is_active ?? true} onChange={e => f('is_active', e.target.checked)} className="rounded border-gray-300" />
            <label className="text-xs text-gray-600">Active</label>
          </div>
        </div>
        <div className="flex gap-2">
          <button onClick={save} disabled={saving} className="px-4 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-40">
            {saving ? 'Saving…' : 'Save'}
          </button>
          <button onClick={() => setMode('list')} className="px-4 py-1.5 border border-gray-300 text-gray-700 rounded text-sm hover:bg-gray-50">Cancel</button>
        </div>
      </div>
    </div>
  )

  return (
    <div>
      <div className="bg-white border-b border-gray-200 px-5 py-2.5 flex items-center gap-3">
        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Warehouses</span>
        <button onClick={() => { setEditing(null); setForm(blank()); setError(''); setMode('form') }}
          className="ml-auto px-3 py-1.5 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800">+ New Warehouse</button>
      </div>
      <div className="px-5 py-4">
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          {warehouses.length === 0 ? (
            <div className="py-14 text-center text-sm text-gray-400">No warehouses. Create one to start tracking inventory.</div>
          ) : (
            <table className="w-full text-xs">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>{['Code','Name','Type','Branch','Inventory GL','Status',''].map(h => (
                  <th key={h} className="px-3 py-2 text-[10px] font-semibold uppercase text-gray-500 text-left whitespace-nowrap">{h}</th>
                ))}</tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {warehouses.map(w => {
                  const invAcct = coa.find(a => a.id === w.gl_inventory_account_id)
                  const br = branches.find(b => b.id === w.branch_id)
                  return (
                    <tr key={w.id} className={`hover:bg-gray-50/60 ${!w.is_active ? 'opacity-50' : ''}`}>
                      <td className="px-3 py-2 font-mono font-semibold text-gray-900">{w.warehouse_code}</td>
                      <td className="px-3 py-2 text-gray-800">{w.warehouse_name}</td>
                      <td className="px-3 py-2 text-gray-500 capitalize">{w.warehouse_type.replace('_', ' ')}</td>
                      <td className="px-3 py-2 text-gray-500">{br?.branch_name || '—'}</td>
                      <td className="px-3 py-2 text-gray-500">{invAcct?.account_code || <span className="text-amber-600">Not set</span>}</td>
                      <td className="px-3 py-2">
                        <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${w.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'}`}>
                          {w.is_active ? 'Active' : 'Inactive'}
                        </span>
                      </td>
                      <td className="px-3 py-2 text-right space-x-3">
                        <button onClick={() => { setEditing(w); setForm({ ...w }); setError(''); setMode('form') }}
                          className="text-xs text-blue-600 hover:text-blue-800">Edit</button>
                        <button onClick={() => { setActiveWh(w); setMode('zones') }}
                          className="text-xs text-gray-500 hover:text-gray-700">Zones ({zones.filter(z => z.warehouse_id === w.id).length})</button>
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
