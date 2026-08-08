import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'

export type InventoryIdentityChoice = {
  inventory_cost_layer_id: string
  lot_number: string | null
  serial_number: string | null
  available_qty: number
  unit_cost: number
}

type Props = {
  companyId: string
  warehouseId: string
  itemId: string
  costingMethod: string
  value: string
  onChange: (choice: InventoryIdentityChoice | null) => void
  disabled?: boolean
  className?: string
}

export function InventoryIdentitySelect({
  companyId, warehouseId, itemId, costingMethod, value, onChange, disabled, className,
}: Props) {
  const [choices, setChoices] = useState<InventoryIdentityChoice[]>([])
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (costingMethod !== 'specific_identification' || !companyId || !warehouseId || !itemId) {
      setChoices([])
      return
    }
    let active = true
    setLoading(true)
    ;(supabase as any).from('vw_available_inventory_identities')
      .select('inventory_cost_layer_id,lot_number,serial_number,available_qty,unit_cost')
      .eq('company_id', companyId).eq('warehouse_id', warehouseId).eq('item_id', itemId)
      .order('layer_date').then(({ data }: { data: InventoryIdentityChoice[] | null }) => {
        if (active) {
          setChoices((data || []).map(row => ({ ...row, available_qty: Number(row.available_qty), unit_cost: Number(row.unit_cost) })))
          setLoading(false)
        }
      })
    return () => { active = false }
  }, [companyId, warehouseId, itemId, costingMethod])

  if (costingMethod !== 'specific_identification') return null
  return (
    <select
      value={value}
      disabled={disabled || loading || !warehouseId}
      onChange={event => onChange(choices.find(choice => choice.inventory_cost_layer_id === event.target.value) || null)}
      className={className || 'pxl-input w-full'}
      aria-label="Inventory identity"
    >
      <option value="">{loading ? 'Loading identities…' : !warehouseId ? 'Select warehouse first' : 'Select serial / lot…'}</option>
      {choices.map(choice => (
        <option key={choice.inventory_cost_layer_id} value={choice.inventory_cost_layer_id}>
          {choice.serial_number || choice.lot_number || choice.inventory_cost_layer_id} — {choice.available_qty.toLocaleString()} available
        </option>
      ))}
    </select>
  )
}
