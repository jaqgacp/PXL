import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ERP_EMPTY_CELL, ERP_TABLE, ERP_THEAD, ERP_TH } from '@/components/document/ErpSection'

// ────────────────────────────────────────────────────────────
// LineGrid — shared enterprise transaction table framework.
// UI/state only: saved views, column visibility/order/width,
// density, sorting, filtering, export, sticky headers/totals, and
// sticky pinned columns. Persistence is browser-local and scoped by
// the caller-provided storageKey, so it can be reused across modules
// without schema/API changes.
// ────────────────────────────────────────────────────────────

export type LineColumnGroup =
  | 'general'
  | 'business'
  | 'sales'
  | 'inventory'
  | 'tax'
  | 'withholding'
  | 'accounting'
  | 'dimensions'
  | 'audit'
  | 'reference'
  | 'system'

export type LineCellValue = string | number | boolean | Date | null | undefined
export type TableDensity = 'compact' | 'comfortable' | 'spacious'
export type SortDirection = 'asc' | 'desc'
export type LineSortState = { key: string; direction: SortDirection } | null

export type LineColumn<T> = {
  key: string
  header: string
  align?: 'left' | 'right' | 'center'
  group?: LineColumnGroup
  hidden?: boolean
  pinned?: boolean
  render: (row: T, index: number) => React.ReactNode
  footer?: React.ReactNode
  minWidth?: string
  defaultWidth?: number
  sortValue?: (row: T, index: number) => LineCellValue
  filterValue?: (row: T, index: number) => LineCellValue
  exportValue?: (row: T, index: number) => LineCellValue
}

export type LineColumnProfile = {
  key: string
  label: string
  columnKeys: string[]
  columnOrder?: string[]
  pinnedColumnKeys?: string[]
  columnWidths?: Record<string, number>
  density?: TableDensity
  sort?: LineSortState
  filters?: Record<string, string>
  system?: boolean
}

export type LineSummaryMetric = {
  key: string
  label: string
  value: React.ReactNode
  emphasis?: boolean
}

type SavedLineView = LineColumnProfile & {
  custom: true
  createdAt: string
  updatedAt: string
}

type ViewState = {
  columnKeys: string[]
  columnOrder: string[]
  pinnedColumnKeys: string[]
  columnWidths: Record<string, number>
  density: TableDensity
  sort: LineSortState
  filters: Record<string, string>
}

type PersistedLineGrid = {
  selectedViewKey?: string
  customDraft?: ViewState
  savedViews?: SavedLineView[]
}

const STORAGE_VERSION = 1

const GROUP_LABELS: Record<LineColumnGroup, string> = {
  general: 'General',
  business: 'General',
  sales: 'Sales',
  inventory: 'Inventory',
  tax: 'Tax',
  withholding: 'Tax',
  accounting: 'Accounting',
  dimensions: 'Dimensions',
  audit: 'Audit',
  reference: 'Audit',
  system: 'System',
}

const GROUP_ORDER: LineColumnGroup[] = [
  'general',
  'business',
  'sales',
  'inventory',
  'tax',
  'withholding',
  'accounting',
  'dimensions',
  'audit',
  'reference',
  'system',
]

const DENSITY_ROW: Record<TableDensity, string> = {
  compact: 'py-1',
  comfortable: 'py-1.5',
  spacious: 'py-2.5',
}

const DENSITY_HEADER: Record<TableDensity, string> = {
  compact: 'py-1',
  comfortable: 'py-1.5',
  spacious: 'py-2',
}

const DENSITY_EXPAND: Record<TableDensity, string> = {
  compact: 'py-1',
  comfortable: 'py-1.5',
  spacious: 'py-2.5',
}

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value))

const textValue = (value: LineCellValue): string => {
  if (value instanceof Date) return value.toISOString()
  if (value === null || value === undefined) return ''
  return String(value)
}

const normalizeKeyList = (keys: string[] | undefined, allKeys: string[]) => {
  const allowed = new Set(allKeys)
  const seen = new Set<string>()
  const result: string[] = []
  for (const key of keys ?? []) {
    if (allowed.has(key) && !seen.has(key)) {
      seen.add(key)
      result.push(key)
    }
  }
  return result
}

const readStored = (key: string): PersistedLineGrid | null => {
  try {
    const raw = localStorage.getItem(key)
    if (!raw) return null
    const parsed = JSON.parse(raw) as PersistedLineGrid & { version?: number }
    return parsed
  } catch {
    return null
  }
}

const writeStored = (key: string, value: PersistedLineGrid) => {
  try {
    localStorage.setItem(key, JSON.stringify({ version: STORAGE_VERSION, ...value }))
  } catch {
    // Local persistence is an enhancement; the table must continue to work without it.
  }
}

export function LineGrid<T>({
  columns,
  rows,
  getRowKey,
  emptyLabel = 'No lines on this document.',
  onRowClick,
  selectedKey,
  renderExpandedRow,
  profiles = [],
  initialProfileKey,
  summary = [],
  storageKey = 'default',
  tableLabel = 'Transaction Lines',
  onRefresh,
}: {
  columns: LineColumn<T>[]
  rows: T[]
  getRowKey: (row: T, index: number) => string
  emptyLabel?: string
  onRowClick?: (row: T, index: number) => void
  selectedKey?: string
  renderExpandedRow?: (row: T, index: number) => React.ReactNode
  profiles?: LineColumnProfile[]
  initialProfileKey?: string
  summary?: LineSummaryMetric[]
  storageKey?: string
  tableLabel?: string
  onRefresh?: () => void | Promise<void>
}) {
  const allKeys = useMemo(() => columns.map(column => column.key), [columns])
  const defaultVisibleKeys = useMemo(() => columns.filter(column => !column.hidden).map(column => column.key), [columns])
  const defaultPinnedKeys = useMemo(() => columns.filter(column => column.pinned).map(column => column.key), [columns])
  const storageName = `pxl.tableViews.${storageKey}`
  const initialStored = useRef<PersistedLineGrid | null>(readStored(storageName))

  const baseProfiles = useMemo<LineColumnProfile[]>(() => {
    if (profiles.length > 0) return profiles
    return [{ key: 'default', label: 'Default', columnKeys: defaultVisibleKeys, system: true }]
  }, [defaultVisibleKeys, profiles])

  const normalizeView = useCallback((view?: Partial<LineColumnProfile | ViewState>): ViewState => {
    const baseColumnKeys = normalizeKeyList(view?.columnKeys, allKeys)
    const columnKeys = baseColumnKeys.length > 0 ? baseColumnKeys : defaultVisibleKeys
    const baseOrder = normalizeKeyList(view?.columnOrder, allKeys)
    const columnOrder = [
      ...baseOrder,
      ...allKeys.filter(key => !baseOrder.includes(key)),
    ]
    const pinnedColumnKeys = normalizeKeyList(view?.pinnedColumnKeys, allKeys)
    const columnWidths = Object.fromEntries(
      Object.entries(view?.columnWidths ?? {}).filter(([key]) => allKeys.includes(key)).map(([key, width]) => [key, clamp(Number(width) || 96, 48, 640)])
    )
    return {
      columnKeys,
      columnOrder,
      pinnedColumnKeys: pinnedColumnKeys.length > 0 ? pinnedColumnKeys : defaultPinnedKeys,
      columnWidths,
      density: view?.density ?? 'compact',
      sort: view?.sort && allKeys.includes(view.sort.key) ? view.sort : null,
      filters: { ...(view?.filters ?? {}) },
    }
  }, [allKeys, defaultPinnedKeys, defaultVisibleKeys])

  const firstProfile = baseProfiles.find(profile => profile.key === initialProfileKey) ?? baseProfiles[0]
  const customBase = normalizeView(initialStored.current?.customDraft ?? firstProfile)
  const [savedViews, setSavedViews] = useState<SavedLineView[]>(() =>
    (initialStored.current?.savedViews ?? []).map(view => ({ ...view, custom: true as const }))
  )
  const [customState, setCustomState] = useState<ViewState>(customBase)
  const [activeViewKey, setActiveViewKey] = useState(() => initialStored.current?.selectedViewKey || firstProfile.key || 'default')

  const initialActiveView = useMemo(() => {
    const allViews = [...baseProfiles, { key: 'custom', label: 'Custom', columnKeys: customState.columnKeys }, ...savedViews]
    return allViews.find(view => view.key === activeViewKey) ?? firstProfile
  }, [activeViewKey, baseProfiles, customState.columnKeys, firstProfile, savedViews])

  const initialState = useMemo(
    () => activeViewKey === 'custom' ? customState : normalizeView(initialActiveView),
    [activeViewKey, customState, initialActiveView, normalizeView],
  )

  const [visibleKeys, setVisibleKeys] = useState<Set<string>>(() => new Set(initialState.columnKeys))
  const [columnOrder, setColumnOrder] = useState<string[]>(initialState.columnOrder)
  const [pinnedColumnKeys, setPinnedColumnKeys] = useState<Set<string>>(() => new Set(initialState.pinnedColumnKeys))
  const [columnWidths, setColumnWidths] = useState<Record<string, number>>(initialState.columnWidths)
  const [density, setDensity] = useState<TableDensity>(initialState.density)
  const [sort, setSort] = useState<LineSortState>(initialState.sort)
  const [filters, setFilters] = useState<Record<string, string>>(initialState.filters)
  const [pickerOpen, setPickerOpen] = useState(false)
  const [filterOpen, setFilterOpen] = useState(Boolean(initialState.filters.global))
  const [columnSearch, setColumnSearch] = useState('')
  const [dragKey, setDragKey] = useState<string | null>(null)
  const pickerRef = useRef<HTMLDivElement>(null)

  const allViews = useMemo(() => [
    ...baseProfiles.map(profile => ({ ...profile, system: true })),
    { key: 'custom', label: 'Custom', columnKeys: customState.columnKeys, system: true },
    ...savedViews,
  ], [baseProfiles, customState.columnKeys, savedViews])

  const activeView = allViews.find(view => view.key === activeViewKey) ?? allViews[0]
  const activeSavedView = savedViews.find(view => view.key === activeViewKey)
  const activeIsSystemView = Boolean(activeView?.system) && activeViewKey !== 'custom'
  const currentViewState: ViewState = useMemo(() => ({
    columnKeys: Array.from(visibleKeys).filter(key => allKeys.includes(key)),
    columnOrder: normalizeKeyList(columnOrder, allKeys),
    pinnedColumnKeys: Array.from(pinnedColumnKeys).filter(key => allKeys.includes(key)),
    columnWidths,
    density,
    sort,
    filters,
  }), [allKeys, columnOrder, columnWidths, density, filters, pinnedColumnKeys, sort, visibleKeys])

  useEffect(() => {
    if (activeViewKey === 'custom') setCustomState(currentViewState)
  }, [activeViewKey, currentViewState])

  useEffect(() => {
    writeStored(storageName, {
      selectedViewKey: activeViewKey,
      customDraft: activeViewKey === 'custom' ? currentViewState : customState,
      savedViews,
    })
  }, [activeViewKey, currentViewState, customState, savedViews, storageName])

  useEffect(() => {
    if (!pickerOpen) return
    const close = (event: MouseEvent) => {
      if (pickerRef.current && !pickerRef.current.contains(event.target as Node)) setPickerOpen(false)
    }
    document.addEventListener('mousedown', close)
    return () => document.removeEventListener('mousedown', close)
  }, [pickerOpen])

  const alignClass = (align?: string) => align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : 'text-left'
  const columnByKey = useMemo(() => new Map(columns.map(column => [column.key, column])), [columns])

  const markEdited = () => {
    if (activeIsSystemView) setActiveViewKey('custom')
  }

  const applyViewState = (state: ViewState) => {
    setVisibleKeys(new Set(state.columnKeys))
    setColumnOrder(state.columnOrder)
    setPinnedColumnKeys(new Set(state.pinnedColumnKeys))
    setColumnWidths(state.columnWidths)
    setDensity(state.density)
    setSort(state.sort)
    setFilters(state.filters)
    setFilterOpen(Boolean(state.filters.global))
  }

  const applyView = (key: string) => {
    const target = allViews.find(view => view.key === key)
    if (!target) return
    if (activeViewKey === 'custom') setCustomState(currentViewState)
    setActiveViewKey(key)
    applyViewState(key === 'custom' ? customState : normalizeView(target))
  }

  const applyDefaultView = () => {
    const defaultView = baseProfiles.find(view => view.key === 'default') ?? baseProfiles[0]
    applyView(defaultView.key)
  }

  const resetToCurrentView = () => {
    const target = allViews.find(view => view.key === activeViewKey)
    if (!target) return
    applyViewState(activeViewKey === 'custom' ? customState : normalizeView(target))
  }

  const toggleColumn = (key: string) => {
    setVisibleKeys(current => {
      const next = new Set(current)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
    if (!columnOrder.includes(key)) setColumnOrder(current => [...current, key])
    markEdited()
  }

  const selectAllColumns = () => {
    setVisibleKeys(new Set(allKeys))
    setColumnOrder(current => [...current, ...allKeys.filter(key => !current.includes(key))])
    markEdited()
  }

  const clearAllColumns = () => {
    setVisibleKeys(new Set())
    markEdited()
  }

  const togglePinnedColumn = (key: string) => {
    setPinnedColumnKeys(current => {
      const next = new Set(current)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
    markEdited()
  }

  const moveColumn = (sourceKey: string, targetKey: string) => {
    if (sourceKey === targetKey) return
    setColumnOrder(current => {
      const base = [...current, ...allKeys.filter(key => !current.includes(key))]
      const without = base.filter(key => key !== sourceKey)
      const targetIndex = without.indexOf(targetKey)
      if (targetIndex < 0) return base
      without.splice(targetIndex, 0, sourceKey)
      return without
    })
    markEdited()
  }

  const getColumnWidth = (column: LineColumn<T>) => {
    if (columnWidths[column.key]) return columnWidths[column.key]
    if (column.defaultWidth) return column.defaultWidth
    if (column.minWidth) {
      const parsed = Number.parseInt(column.minWidth, 10)
      if (!Number.isNaN(parsed)) return parsed
    }
    return clamp(column.header.length * 8 + 44, 72, 220)
  }

  const beginResize = (event: React.MouseEvent, key: string) => {
    event.preventDefault()
    event.stopPropagation()
    const startX = event.clientX
    const column = columnByKey.get(key)
    const startWidth = column ? getColumnWidth(column) : 96
    const onMove = (moveEvent: MouseEvent) => {
      const nextWidth = clamp(startWidth + moveEvent.clientX - startX, 48, 640)
      setColumnWidths(current => ({ ...current, [key]: nextWidth }))
    }
    const onUp = () => {
      document.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseup', onUp)
      markEdited()
    }
    document.addEventListener('mousemove', onMove)
    document.addEventListener('mouseup', onUp)
  }

  const toggleSort = (key: string) => {
    setSort(current => {
      if (!current || current.key !== key) return { key, direction: 'asc' }
      if (current.direction === 'asc') return { key, direction: 'desc' }
      return null
    })
    markEdited()
  }

  const updateGlobalFilter = (value: string) => {
    setFilters(current => ({ ...current, global: value }))
    markEdited()
  }

  const updateDensity = (value: TableDensity) => {
    setDensity(value)
    markEdited()
  }

  const saveCurrentView = () => {
    const name = window.prompt('Save current view as:', activeView?.label && activeViewKey !== 'custom' ? `${activeView.label} Copy` : 'My View')
    if (!name?.trim()) return
    const now = new Date().toISOString()
    const key = `saved-${Date.now()}`
    const view: SavedLineView = {
      key,
      label: name.trim(),
      custom: true,
      createdAt: now,
      updatedAt: now,
      ...currentViewState,
    }
    setSavedViews(current => [...current, view])
    setActiveViewKey(key)
  }

  const updateSavedView = () => {
    if (!activeSavedView) {
      setCustomState(currentViewState)
      setActiveViewKey('custom')
      return
    }
    const now = new Date().toISOString()
    setSavedViews(current => current.map(view => view.key === activeSavedView.key ? { ...view, ...currentViewState, updatedAt: now } : view))
  }

  const renameSavedView = () => {
    if (!activeSavedView) return
    const name = window.prompt('Rename saved view:', activeSavedView.label)
    if (!name?.trim()) return
    const now = new Date().toISOString()
    setSavedViews(current => current.map(view => view.key === activeSavedView.key ? { ...view, label: name.trim(), updatedAt: now } : view))
  }

  const deleteSavedView = () => {
    if (!activeSavedView) return
    if (!window.confirm(`Delete saved view "${activeSavedView.label}"?`)) return
    setSavedViews(current => current.filter(view => view.key !== activeSavedView.key))
    applyDefaultView()
  }

  const orderedColumns = useMemo(() => {
    const orderedKeys = [...columnOrder, ...allKeys.filter(key => !columnOrder.includes(key))]
    const visible = orderedKeys.map(key => columnByKey.get(key)).filter((column): column is LineColumn<T> => Boolean(column && visibleKeys.has(column.key)))
    const pinned = visible.filter(column => pinnedColumnKeys.has(column.key))
    const normal = visible.filter(column => !pinnedColumnKeys.has(column.key))
    return [...pinned, ...normal]
  }, [allKeys, columnByKey, columnOrder, pinnedColumnKeys, visibleKeys])

  const hasFooter = orderedColumns.some(column => column.footer != null)
  const detailColSpan = Math.max(1, orderedColumns.length + (renderExpandedRow ? 1 : 0))

  const pinnedOffsets = useMemo(() => {
    const offsets: Record<string, number> = {}
    let left = renderExpandedRow ? 28 : 0
    for (const column of orderedColumns) {
      if (!pinnedColumnKeys.has(column.key)) continue
      offsets[column.key] = left
      left += getColumnWidth(column)
    }
    return offsets
  // getColumnWidth intentionally depends on the latest width state, represented by columnWidths.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [columnWidths, orderedColumns, pinnedColumnKeys, renderExpandedRow])

  const comparableValue = (column: LineColumn<T>, row: T, index: number) =>
    column.sortValue?.(row, index) ?? column.filterValue?.(row, index) ?? column.exportValue?.(row, index) ?? ''

  const displayRows = useMemo(() => {
    const globalFilter = (filters.global ?? '').trim().toLowerCase()
    const visibleColumns = orderedColumns
    const base = rows.map((row, index) => ({ row, index }))
      .filter(({ row, index }) => {
        if (!globalFilter) return true
        const haystack = visibleColumns
          .map(column => textValue(column.filterValue?.(row, index) ?? column.exportValue?.(row, index) ?? column.sortValue?.(row, index)))
          .join(' ')
          .toLowerCase()
        return haystack.includes(globalFilter)
      })

    if (!sort) return base
    const sortColumn = columnByKey.get(sort.key)
    if (!sortColumn) return base
    return [...base].sort((a, b) => {
      const av = comparableValue(sortColumn, a.row, a.index)
      const bv = comparableValue(sortColumn, b.row, b.index)
      if (typeof av === 'number' && typeof bv === 'number') return sort.direction === 'asc' ? av - bv : bv - av
      const as = textValue(av).toLowerCase()
      const bs = textValue(bv).toLowerCase()
      return sort.direction === 'asc' ? as.localeCompare(bs) : bs.localeCompare(as)
    })
  }, [columnByKey, filters.global, orderedColumns, rows, sort])

  const groupedColumns = useMemo(() => {
    const search = columnSearch.trim().toLowerCase()
    const groups = new Map<string, LineColumn<T>[]>()
    for (const group of GROUP_ORDER) groups.set(GROUP_LABELS[group], [])
    for (const column of columns) {
      if (search && !`${column.header} ${column.key}`.toLowerCase().includes(search)) continue
      const label = GROUP_LABELS[column.group ?? 'general']
      groups.set(label, [...(groups.get(label) ?? []), column])
    }
    return Array.from(groups.entries()).filter(([, cols]) => cols.length > 0)
  }, [columnSearch, columns])

  const exportCsv = () => {
    const headers = orderedColumns.map(column => column.header)
    const csvRows = [
      headers,
      ...displayRows.map(({ row, index }) => orderedColumns.map(column =>
        textValue(column.exportValue?.(row, index) ?? column.filterValue?.(row, index) ?? column.sortValue?.(row, index))
      )),
    ]
    const csv = csvRows.map(row => row.map(cell => `"${cell.replace(/"/g, '""')}"`).join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `${tableLabel.toLowerCase().replace(/[^a-z0-9]+/g, '-') || 'table'}-${new Date().toISOString().slice(0, 10)}.csv`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    URL.revokeObjectURL(url)
  }

  const thStyle = (column: LineColumn<T>): React.CSSProperties => {
    const width = getColumnWidth(column)
    const pinned = pinnedColumnKeys.has(column.key)
    return {
      width,
      minWidth: width,
      ...(pinned ? { position: 'sticky', left: pinnedOffsets[column.key], zIndex: 31, background: 'var(--pxl-surface-table-header)' } : {}),
    }
  }

  const tdStyle = (column: LineColumn<T>, expanded = false): React.CSSProperties => {
    const width = getColumnWidth(column)
    const pinned = pinnedColumnKeys.has(column.key)
    return {
      width,
      minWidth: width,
      ...(pinned ? { position: 'sticky', left: pinnedOffsets[column.key], zIndex: 12, background: expanded ? 'var(--pxl-surface-table-selected)' : 'var(--pxl-surface-raised)' } : {}),
    }
  }

  const expandStickyStyle: React.CSSProperties = renderExpandedRow
    ? { position: 'sticky', left: 0, zIndex: 32, background: 'var(--pxl-surface-table-header)' }
    : {}

  return (
    <div>
      <div className="flex items-center justify-between gap-2 pb-2">
        <div className="flex items-center gap-1.5 min-w-0 flex-wrap">
          <label className="sr-only" htmlFor={`${storageKey}-view-selector`}>Table view</label>
          <select
            id={`${storageKey}-view-selector`}
            value={activeViewKey}
            onChange={event => applyView(event.target.value)}
            className="pxl-input h-8 max-w-44 px-2 py-1 text-xs"
          >
            {allViews.map(view => (
              <option key={view.key} value={view.key}>{view.label}</option>
            ))}
          </select>

          <div className="relative shrink-0" ref={pickerRef}>
            <button type="button" onClick={() => setPickerOpen(open => !open)}
              className="pxl-button pxl-button--neutral h-8 px-2.5 text-xs">
              Choose Columns ▾
            </button>
            {pickerOpen && (
              <div className="pxl-dialog absolute left-0 top-full z-30 mt-1 max-h-[70vh] w-[420px] max-w-[calc(100vw-2rem)] overflow-y-auto p-3">
                <div className="flex items-start justify-between gap-3 pb-2 border-b border-gray-100">
                  <div>
                    <div className="pxl-section-title">Table View</div>
                    <div className="pxl-caption">{activeView?.label || 'Custom'} · {orderedColumns.length} visible column{orderedColumns.length !== 1 ? 's' : ''}</div>
                  </div>
                  <button type="button" onClick={() => setPickerOpen(false)} className="text-gray-400 hover:text-gray-700 text-sm leading-none">×</button>
                </div>

                <div className="grid grid-cols-2 gap-2 py-2 border-b border-gray-100">
                  <button type="button" onClick={saveCurrentView} className="pxl-button pxl-button--neutral h-8 px-2 text-xs">Save View</button>
                  <button type="button" onClick={updateSavedView} className="pxl-button pxl-button--neutral h-8 px-2 text-xs">
                    {activeSavedView ? 'Update View' : 'Save as Custom'}
                  </button>
                  <button type="button" onClick={renameSavedView} disabled={!activeSavedView} className="pxl-button pxl-button--neutral h-8 px-2 text-xs">Rename</button>
                  <button type="button" onClick={deleteSavedView} disabled={!activeSavedView} className="pxl-button pxl-button--danger h-8 px-2 text-xs">Delete</button>
                </div>

                <div className="grid grid-cols-2 gap-2 py-2 border-b border-gray-100">
                  <label className="text-[11px] text-gray-500">
                    <span className="pxl-field-label mb-1 block uppercase">Density</span>
                    <select value={density} onChange={event => updateDensity(event.target.value as TableDensity)}
                      className="pxl-input w-full px-2 py-1 text-xs">
                      <option value="compact">Compact</option>
                      <option value="comfortable">Comfortable</option>
                      <option value="spacious">Spacious</option>
                    </select>
                  </label>
                  <label className="text-[11px] text-gray-500">
                    <span className="pxl-field-label mb-1 block uppercase">Find columns</span>
                    <input value={columnSearch} onChange={event => setColumnSearch(event.target.value)}
                      className="pxl-input w-full px-2 py-1 text-xs"
                      placeholder="Search columns…" />
                  </label>
                </div>

                <div className="flex items-center gap-1.5 flex-wrap py-2 border-b border-gray-100">
                  <button type="button" onClick={selectAllColumns} className="pxl-button pxl-button--neutral h-8 px-2 text-xs">Select All</button>
                  <button type="button" onClick={clearAllColumns} className="pxl-button pxl-button--neutral h-8 px-2 text-xs">Clear All</button>
                  <button type="button" onClick={resetToCurrentView} className="pxl-button pxl-button--neutral h-8 px-2 text-xs">Reset to Current View</button>
                  <button type="button" onClick={applyDefaultView} className="pxl-button pxl-button--neutral h-8 px-2 text-xs">Reset to System Default</button>
                </div>

                <div className="py-2 border-b border-gray-100">
                  <div className="pxl-section-title mb-1.5">Column Order</div>
                  <div className="space-y-1 max-h-40 overflow-y-auto pr-1">
                    {orderedColumns.length === 0 ? (
                      <div className="text-[11px] text-gray-400 px-2 py-2 border border-dashed border-gray-200 rounded">No visible columns selected.</div>
                    ) : orderedColumns.map(column => {
                      const pinned = pinnedColumnKeys.has(column.key)
                      return (
                        <div
                          key={column.key}
                          draggable
                          onDragStart={() => setDragKey(column.key)}
                          onDragOver={event => event.preventDefault()}
                          onDrop={event => { event.preventDefault(); if (dragKey) moveColumn(dragKey, column.key); setDragKey(null) }}
                          className="flex cursor-move items-center gap-2 rounded border border-[var(--pxl-border-subtle)] bg-white px-2 py-1 text-xs text-gray-700"
                        >
                          <span className="text-gray-300">⋮⋮</span>
                          <span className="min-w-0 flex-1 truncate">{column.header}</span>
                          <button type="button" onClick={() => togglePinnedColumn(column.key)}
                            className={`px-1.5 py-0.5 rounded text-[10px] ${pinned ? 'bg-gray-800 text-white' : 'bg-gray-100 text-gray-500 hover:text-gray-700'}`}>
                            {pinned ? 'Pinned' : 'Pin'}
                          </button>
                        </div>
                      )
                    })}
                  </div>
                </div>

                <div className="pt-2 space-y-2">
                  {groupedColumns.map(([groupLabel, groupColumns]) => (
                    <section key={groupLabel}>
                      <div className="pxl-field-label mb-1 uppercase">{groupLabel}</div>
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-1">
                        {groupColumns.map(column => (
                          <label key={column.key} className="flex items-center gap-2 px-2 py-1.5 text-xs text-gray-700 rounded hover:bg-gray-50 cursor-pointer">
                            <input type="checkbox" checked={visibleKeys.has(column.key)} onChange={() => toggleColumn(column.key)} className="rounded border-gray-300" />
                            <span className="truncate">{column.header}</span>
                          </label>
                        ))}
                      </div>
                    </section>
                  ))}
                </div>
              </div>
            )}
          </div>

          <button type="button" onClick={() => setFilterOpen(open => !open)}
            className={`pxl-button h-8 px-2.5 text-xs ${filters.global ? 'pxl-button--secondary' : 'pxl-button--neutral'}`}>
            Filter
          </button>
          <button type="button" onClick={exportCsv} className="pxl-button pxl-button--neutral h-8 px-2.5 text-xs">Export</button>
          <button type="button" onClick={() => void onRefresh?.()} disabled={!onRefresh}
            className="pxl-button pxl-button--neutral h-8 px-2.5 text-xs">
            Refresh
          </button>
        </div>

        <div className="pxl-caption whitespace-nowrap">
          {displayRows.length}/{rows.length} row{rows.length !== 1 ? 's' : ''}
        </div>
      </div>

      {filterOpen && (
        <div className="pb-2">
          <input value={filters.global ?? ''} onChange={event => updateGlobalFilter(event.target.value)}
            className="pxl-input w-full max-w-sm px-2 py-1 text-xs"
            placeholder="Filter visible columns…" />
        </div>
      )}

      <div className="overflow-x-auto rounded border border-[var(--pxl-border-medium)]">
        <table className={`min-w-full w-max ${ERP_TABLE}`}>
          <colgroup>
            {renderExpandedRow && <col style={{ width: 28, minWidth: 28 }} />}
            {orderedColumns.map(column => {
              const width = getColumnWidth(column)
              return <col key={column.key} style={{ width, minWidth: width }} />
            })}
          </colgroup>
          <thead className={`${ERP_THEAD} sticky top-0 z-30`}>
            <tr>
              {renderExpandedRow && <th className="w-7 px-1 py-1" style={expandStickyStyle} aria-label="Expand line" />}
              {orderedColumns.map(column => (
                <th key={column.key} style={thStyle(column)}
                  className={`${ERP_TH} ${DENSITY_HEADER[density]} ${alignClass(column.align)} relative select-none`}>
                  <button type="button" onClick={() => toggleSort(column.key)}
                    className={`inline-flex items-center gap-1 max-w-full truncate ${alignClass(column.align) === 'text-right' ? 'justify-end' : 'justify-start'}`}>
                    <span className="truncate">{column.header}</span>
                    {sort?.key === column.key && <span className="text-gray-400">{sort.direction === 'asc' ? '▲' : '▼'}</span>}
                  </button>
                  <span
                    role="separator"
                    aria-orientation="vertical"
                    onMouseDown={event => beginResize(event, column.key)}
                    className="absolute right-0 top-0 h-full w-1 cursor-col-resize hover:bg-gray-300"
                  />
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--pxl-border-subtle)]">
            {displayRows.length === 0 ? (
              <tr><td colSpan={detailColSpan} className={ERP_EMPTY_CELL}>{rows.length === 0 ? emptyLabel : 'No rows match the current filter.'}</td></tr>
            ) : displayRows.map(({ row, index }) => {
              const key = getRowKey(row, index)
              const expanded = selectedKey === key
              return (
                <Fragment key={key}>
                  <tr onClick={onRowClick ? () => onRowClick(row, index) : undefined}
                    aria-expanded={renderExpandedRow ? expanded : undefined}
                    data-selected={expanded ? 'true' : undefined}
                    className={`${onRowClick ? 'cursor-pointer' : ''}`}>
                    {renderExpandedRow && (
                      <td className={`px-1 ${DENSITY_EXPAND[density]} text-center text-gray-400`} style={{ position: 'sticky', left: 0, zIndex: 13, background: expanded ? 'var(--pxl-surface-table-selected)' : 'var(--pxl-surface-raised)' }}>
                        <span aria-hidden>{expanded ? '▾' : '›'}</span>
                      </td>
                    )}
                    {orderedColumns.map(column => (
                      <td key={column.key}
                        style={tdStyle(column, expanded)}
                        className={`px-2 ${DENSITY_ROW[density]} whitespace-nowrap ${alignClass(column.align)}`}>
                        {column.render(row, index)}
                      </td>
                    ))}
                  </tr>
                  {expanded && renderExpandedRow && (
                    <tr className="bg-[var(--pxl-surface-table-selected)]">
                      <td colSpan={detailColSpan} className="p-0">{renderExpandedRow(row, index)}</td>
                    </tr>
                  )}
                </Fragment>
              )
            })}
          </tbody>
          {hasFooter && displayRows.length > 0 && (
            <tfoot className="sticky bottom-0 z-20">
              <tr className="border-t border-[var(--pxl-border-strong)] bg-[var(--pxl-surface-table-selected)]">
                {renderExpandedRow && <td style={{ position: 'sticky', left: 0, zIndex: 21, background: 'var(--pxl-surface-table-selected)' }} />}
                {orderedColumns.map(column => (
                  <td key={column.key}
                    style={{ ...tdStyle(column, true), background: 'var(--pxl-surface-table-selected)' }}
                    className={`px-2 py-1.5 font-semibold text-gray-900 ${alignClass(column.align)}`}>
                    {column.footer}
                  </td>
                ))}
              </tr>
            </tfoot>
          )}
        </table>
      </div>

      {summary.length > 0 && (
        <dl className="mt-2 flex flex-wrap items-center justify-end gap-x-5 gap-y-1.5 rounded border border-[var(--pxl-border-medium)] bg-[var(--pxl-surface-table-selected)] px-2.5 py-1.5">
          {summary.map(metric => (
            <div key={metric.key} className="flex items-baseline gap-1.5 whitespace-nowrap">
              <dt className="pxl-caption uppercase">{metric.label}</dt>
              <dd className={`font-mono tabular-nums ${metric.emphasis ? 'font-semibold text-gray-900' : 'text-gray-700'}`}>{metric.value}</dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  )
}

export default LineGrid
