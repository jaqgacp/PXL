import { useState, useEffect, useRef } from 'react'
import { supabase } from '@/lib/supabase'

type RDO = { id: string; rdo_code: string; rdo_name: string }
type Company = {
  id: string
  registered_name: string
  trade_name: string
  tin: string
  tax_registration: string
  rdo_id: string
  is_active: boolean
  parent_company_id: string | null
  entity_type: string
  ref_rdo_codes?: { rdo_code: string; rdo_name: string }
}
type ImportRow = {
  row: number
  data: Record<string, string>
  status: 'pending' | 'success' | 'error'
  error?: string
}

const ENTITY_TYPES = [
  { value: 'sole_proprietor', label: 'Sole Proprietor' },
  { value: 'opc', label: 'OPC' },
  { value: 'corporation', label: 'Regular Corporation' },
  { value: 'partnership', label: 'Partnership' },
  { value: 'cooperative', label: 'Cooperative' },
]

const TAX_REG_LABELS: Record<string, string> = {
  vat: 'VAT', non_vat: 'Non-VAT', exempt: 'Exempt'
}

const REG_NUMBER_LABEL: Record<string, string> = {
  sole_proprietor: 'DTI No.', opc: 'SEC No.',
  corporation: 'SEC No.', partnership: 'SEC No.', cooperative: 'CDA No.',
}

const MONTHS = ['January','February','March','April','May','June',
  'July','August','September','October','November','December']

const EMPTY_FORM = {
  parent_company_id: '', entity_type: '', registered_name: '',
  trade_name: '', line_of_business: '', psic_code: '', tin: '',
  tax_registration: '', rdo_id: '', registration_number: '',
  bir_reg_date: '', sec_dti_reg_date: '', lgu_reg_date: '',
  accounting_period: '', fiscal_start_month: '', cas_permit_no: '',
  cas_date_issued: '', address_line_1: '', address_line_2: '',
  city: '', province: '', zip_code: '', email: '',
  phone_number: '', mobile_number: '', signatory_name: '',
  signatory_position: '', signatory_tin: '',
}

const CSV_COLUMNS = [
  'registered_name','trade_name','entity_type','tin','tax_registration',
  'line_of_business','psic_code','address_line_1','address_line_2',
  'city','province','zip_code','email','phone_number','mobile_number',
  'signatory_name','signatory_position','signatory_tin','accounting_period',
  'registration_number','bir_reg_date','sec_dti_reg_date','lgu_reg_date',
  'cas_permit_no','cas_date_issued',
]

const REQUIRED_COLUMNS = [
  'registered_name','entity_type','tin','tax_registration',
  'line_of_business','address_line_1','address_line_2',
  'city','province','zip_code','email','signatory_name',
  'signatory_position','accounting_period',
]

const VALID_ENTITY_TYPES = ['sole_proprietor','opc','corporation','partnership','cooperative']
const VALID_TAX_REG = ['vat','non_vat','exempt']
const VALID_PERIODS = ['calendar','fiscal']

export default function CompanySetupPage() {
  const [companies, setCompanies] = useState<Company[]>([])
  const [rdos, setRdos] = useState<RDO[]>([])
  const [search, setSearch] = useState('')
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'inactive'>('all')
  const [showForm, setShowForm] = useState(false)
  const [showImport, setShowImport] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState({ ...EMPTY_FORM })
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [importRows, setImportRows] = useState<ImportRow[]>([])
  const [importing, setImporting] = useState(false)
  const [importDone, setImportDone] = useState(false)
  const [showView, setShowView] = useState(false)
  const [viewForm, setViewForm] = useState({ ...EMPTY_FORM })
  const fileRef = useRef<HTMLInputElement>(null)

  const fetchCompanies = async () => {
    const { data } = await supabase
      .from('companies')
      .select('*, ref_rdo_codes(rdo_code, rdo_name)')
      .order('registered_name')
    setCompanies((data as Company[]) || [])
  }

  useEffect(() => {
    fetchCompanies()
    supabase.from('ref_rdo_codes').select('id, rdo_code, rdo_name').order('rdo_code')
      .then(({ data }) => setRdos(data || []))
  }, [])

  const set = (k: string, v: string) => { setSaved(false); setForm(f => ({ ...f, [k]: v })) }

  const openCreate = () => { setForm({ ...EMPTY_FORM }); setEditId(null); setShowForm(true); setSaved(false) }

  const openEdit = (c: Company) => {
    setForm({
      parent_company_id: c.parent_company_id || '',
      entity_type: c.entity_type || '',
      registered_name: c.registered_name || '',
      trade_name: c.trade_name || '',
      line_of_business: '', psic_code: '', tin: c.tin || '',
      tax_registration: c.tax_registration || '',
      rdo_id: c.rdo_id || '', registration_number: '',
      bir_reg_date: '', sec_dti_reg_date: '', lgu_reg_date: '',
      accounting_period: '', fiscal_start_month: '', cas_permit_no: '',
      cas_date_issued: '', address_line_1: '', address_line_2: '',
      city: '', province: '', zip_code: '', email: '',
      phone_number: '', mobile_number: '', signatory_name: '',
      signatory_position: '', signatory_tin: '',
    })
    setEditId(c.id); setShowForm(true); setSaved(false)
  }

  const openView = async (c: Company) => {
    const { data } = await supabase.from('companies').select('*').eq('id', c.id).single()
    if (data) setViewForm({
      parent_company_id: data.parent_company_id || '',
      entity_type: data.entity_type || '',
      registered_name: data.registered_name || '',
      trade_name: data.trade_name || '',
      line_of_business: data.line_of_business || '',
      psic_code: data.psic_code || '',
      tin: data.tin || '',
      tax_registration: data.tax_registration || '',
      rdo_id: data.rdo_id || '',
      registration_number: data.registration_number || '',
      bir_reg_date: data.bir_reg_date || '',
      sec_dti_reg_date: data.sec_dti_reg_date || '',
      lgu_reg_date: data.lgu_reg_date || '',
      accounting_period: data.accounting_period || '',
      fiscal_start_month: data.fiscal_start_month ? String(data.fiscal_start_month) : '',
      cas_permit_no: data.cas_permit_no || '',
      cas_date_issued: data.cas_date_issued || '',
      address_line_1: data.address_line_1 || '',
      address_line_2: data.address_line_2 || '',
      city: data.city || '',
      province: data.province || '',
      zip_code: data.zip_code || '',
      email: data.email || '',
      phone_number: data.phone_number || '',
      mobile_number: data.mobile_number || '',
      signatory_name: data.signatory_name || '',
      signatory_position: data.signatory_position || '',
      signatory_tin: data.signatory_tin || '',
    })
    setShowView(true)
  }

  const handleSave = async () => {
    setSaving(true)
    const payload = {
      ...form,
      parent_company_id: form.parent_company_id || null,
      rdo_id: form.rdo_id || null,
      fiscal_start_month: form.fiscal_start_month ? parseInt(form.fiscal_start_month) : null,
      bir_reg_date: form.bir_reg_date || null,
      sec_dti_reg_date: form.sec_dti_reg_date || null,
      lgu_reg_date: form.lgu_reg_date || null,
      cas_date_issued: form.cas_date_issued || null,
    }
    const { error } = editId
      ? await supabase.from('companies').update(payload).eq('id', editId)
      : await supabase.from('companies').insert([payload])
    if (error) alert('Cannot save company.\nReason: ' + error.message)
    else { setSaved(true); fetchCompanies() }
    setSaving(false)
  }

  const handleToggleStatus = async (c: Company) => {
    await supabase.from('companies').update({ is_active: !c.is_active }).eq('id', c.id)
    fetchCompanies()
  }

  // Download CSV template
  const downloadTemplate = () => {
    const sampleRow = [
      'ABC Trading Corporation','ABC Trading','corporation','123-456-789-00000','vat',
      'Wholesale Trading of General Merchandise','46900',
      'Unit 4B 123 Ayala Avenue','Barangay San Lorenzo',
      'Makati City','Metro Manila','1226','accounting@abctrading.com.ph',
      '(02) 8888-1234','0917-123-4567','Juan dela Cruz','President','',
      'calendar','CS201800012345','2018-03-15','2018-02-10','2026-01-05',
      'PTU-2019-00123','2019-06-01',
    ]
    const csv = [CSV_COLUMNS.join(','), sampleRow.join(',')].join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'PXL_Company_Import_Template.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  // Parse and validate CSV
  const handleFileSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setImportDone(false)
    const text = await file.text()
    const lines = text.split('\n').filter(l => l.trim())
    const headers = lines[0].split(',').map(h => h.trim().toLowerCase())

    const rows: ImportRow[] = lines.slice(1).map((line, idx) => {
      const vals = line.split(',')
      const data: Record<string, string> = {}
      headers.forEach((h, i) => { data[h] = vals[i]?.trim() || '' })

      const errors: string[] = []

      // Required field check
      REQUIRED_COLUMNS.forEach(col => {
        if (!data[col]) errors.push(`"${col}" is required`)
      })

      // Enum validation
      if (data.entity_type && !VALID_ENTITY_TYPES.includes(data.entity_type))
        errors.push(`entity_type must be one of: ${VALID_ENTITY_TYPES.join(', ')}`)
      if (data.tax_registration && !VALID_TAX_REG.includes(data.tax_registration))
        errors.push(`tax_registration must be one of: ${VALID_TAX_REG.join(', ')}`)
      if (data.accounting_period && !VALID_PERIODS.includes(data.accounting_period))
        errors.push(`accounting_period must be: calendar or fiscal`)

      // Fiscal year requires fiscal_start_month
      if (data.accounting_period === 'fiscal' && !data.fiscal_start_month)
        errors.push('"fiscal_start_month" is required when accounting_period is "fiscal"')

      // TIN format check
      if (data.tin && !/^\d{3}-\d{3}-\d{3}/.test(data.tin))
        errors.push('TIN format should be 000-000-000-00000')

      // Duplicate TIN check against existing companies
      if (data.tin && companies.some(c => c.tin === data.tin))
        errors.push(`TIN "${data.tin}" already exists in the system`)

      return {
        row: idx + 2,
        data,
        status: errors.length > 0 ? 'error' : 'pending',
        error: errors.join(' | '),
      }
    })

    setImportRows(rows)
    e.target.value = ''
  }

  const validateRowFields = (data: Record<string, string>): string[] => {
    const missing = REQUIRED_COLUMNS.filter(col => !data[col])
    if (data.accounting_period === 'fiscal' && !data.fiscal_start_month)
      missing.push('fiscal_start_month')
    return missing
  }

  // Execute import row by row — only inserts rows that pass full validation
  const executeImport = async () => {
    setImporting(true)
    const pendingRows = importRows.filter(r => r.status === 'pending')

    for (const row of pendingRows) {
      // Secondary guard: re-validate required fields before every insert
      const missingFields = validateRowFields(row.data)
      if (missingFields.length > 0) {
        setImportRows(prev => prev.map(r =>
          r.row === row.row
            ? { ...r, status: 'error', error: `Missing required fields: ${missingFields.join(', ')}` }
            : r
        ))
        continue
      }

      const { error } = await supabase.from('companies').insert([{
        ...row.data,
        fiscal_start_month: row.data.fiscal_start_month ? parseInt(row.data.fiscal_start_month) : null,
        bir_reg_date: row.data.bir_reg_date || null,
        sec_dti_reg_date: row.data.sec_dti_reg_date || null,
        lgu_reg_date: row.data.lgu_reg_date || null,
        cas_date_issued: row.data.cas_date_issued || null,
        rdo_id: null,
      }])
      setImportRows(prev => prev.map(r =>
        r.row === row.row
          ? { ...r, status: error ? 'error' : 'success', error: error?.message }
          : r
      ))
    }

    setImporting(false)
    setImportDone(true)
    fetchCompanies()
  }

  const successCount = importRows.filter(r => r.status === 'success').length
  const errorCount = importRows.filter(r => r.status === 'error').length
  const pendingCount = importRows.filter(r => r.status === 'pending').length

  const inputClass = 'w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900'
  const labelClass = 'block text-xs font-medium text-gray-500 mb-1'
  const sectionClass = 'bg-white border border-gray-200 rounded-lg p-6 space-y-4'
  const headingClass = 'text-xs font-semibold text-gray-400 uppercase tracking-widest pb-2 border-b border-gray-100'

  // IMPORT VIEW
  if (showImport) return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => { setShowImport(false); setImportRows([]) }}
            className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">Import Companies</h1>
          <p className="text-sm text-gray-500 mt-0.5">Bulk create companies from a CSV file</p>
        </div>
        <button onClick={downloadTemplate}
          className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50 flex items-center gap-2">
          ↓ Download CSV Template
        </button>
      </div>

      {/* Instructions */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 text-sm text-blue-800 space-y-1">
        <p className="font-semibold">How to import:</p>
        <ol className="list-decimal ml-4 space-y-1 text-xs">
          <li>Download the CSV template above</li>
          <li>Fill in your company data — do not change the column headers</li>
          <li>Required fields: registered_name, entity_type, tin, tax_registration, line_of_business, address fields, email, signatory_name, signatory_position, accounting_period</li>
          <li>entity_type values: sole_proprietor, opc, corporation, partnership, cooperative</li>
          <li>tax_registration values: vat, non_vat, exempt</li>
          <li>accounting_period values: calendar, fiscal</li>
          <li>Upload the file below — errors will be shown before any data is saved</li>
        </ol>
      </div>

      {/* File Upload */}
      <div className="bg-white border border-gray-200 rounded-lg p-6">
        <label className="block text-sm font-medium text-gray-700 mb-3">Select CSV File</label>
        <div className="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-gray-400 transition-colors cursor-pointer"
          onClick={() => fileRef.current?.click()}>
          <p className="text-sm text-gray-500">Click to browse or drag and drop your CSV file here</p>
          <p className="text-xs text-gray-400 mt-1">Only .csv files are accepted</p>
          <input ref={fileRef} type="file" accept=".csv" className="hidden" onChange={handleFileSelect} />
        </div>
      </div>

      {/* Validation Results */}
      {importRows.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          {/* Summary bar */}
          <div className="px-4 py-3 border-b border-gray-100 flex items-center gap-4 bg-gray-50">
            <span className="text-sm font-medium text-gray-700">{importRows.length} rows parsed</span>
            {pendingCount > 0 && <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded">{pendingCount} ready to import</span>}
            {errorCount > 0 && <span className="text-xs bg-red-100 text-red-700 px-2 py-0.5 rounded">{errorCount} have errors</span>}
            {successCount > 0 && <span className="text-xs bg-blue-100 text-blue-700 px-2 py-0.5 rounded">{successCount} imported</span>}
            {importing && (
              <div className="ml-auto flex items-center gap-2 text-xs text-gray-500">
                <span className="animate-spin">⟳</span> Importing...
              </div>
            )}
            {importDone && (
              <span className="ml-auto text-xs font-medium flex items-center gap-2">
                <span className="text-green-600">✓ {successCount} imported</span>
                {errorCount > 0 && <span className="text-red-500">· {errorCount} skipped (errors)</span>}
              </span>
            )}
          </div>

          {/* Progress bar */}
          {importing && (
            <div className="h-1 bg-gray-100">
              <div className="h-1 bg-blue-500 transition-all duration-300"
                style={{ width: `${((successCount + errorCount) / importRows.length) * 100}%` }} />
            </div>
          )}

          {/* Row results table */}
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase w-12">Row</th>
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase">Registered Name</th>
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase">TIN</th>
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase">Entity Type</th>
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase w-16">Status</th>
                <th className="text-left px-4 py-2 text-xs font-semibold text-gray-500 uppercase">Error</th>
              </tr>
            </thead>
            <tbody>
              {importRows.map(row => (
                <tr key={row.row} className={`border-b border-gray-100 ${
                  row.status === 'error' ? 'bg-red-50' :
                  row.status === 'success' ? 'bg-green-50' : ''
                }`}>
                  <td className="px-4 py-2 text-xs text-gray-500">{row.row}</td>
                  <td className="px-4 py-2 text-gray-900">{row.data.registered_name || '—'}</td>
                  <td className="px-4 py-2 font-mono text-gray-600">{row.data.tin || '—'}</td>
                  <td className="px-4 py-2 text-gray-600">{row.data.entity_type || '—'}</td>
                  <td className="px-4 py-2">
                    <span className={`text-xs font-medium px-2 py-0.5 rounded ${
                      row.status === 'success' ? 'bg-green-100 text-green-700' :
                      row.status === 'error' ? 'bg-red-100 text-red-700' :
                      'bg-gray-100 text-gray-600'
                    }`}>
                      {row.status === 'success' ? '✓ Done' :
                       row.status === 'error' ? '✗ Error' : 'Ready'}
                    </span>
                  </td>
                  <td className="px-4 py-2 text-xs text-red-600">{row.error || ''}</td>
                </tr>
              ))}
            </tbody>
          </table>

          {/* Import action */}
          {pendingCount > 0 && !importDone && (
            <div className="px-4 py-3 border-t border-gray-100 flex items-center justify-between">
              <p className="text-xs text-gray-500">
                {errorCount > 0
                  ? `${errorCount} rows have errors and will be skipped. ${pendingCount} valid rows will be imported.`
                  : `All ${pendingCount} rows are valid and ready to import.`}
              </p>
              <button onClick={executeImport} disabled={importing}
                className="bg-gray-900 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
                {importing ? 'Importing...' : `Import ${pendingCount} Companies`}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )

  // VIEW VIEW
  if (showView) {
    const roInput = 'w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-700'
    const parentName = companies.find(c => c.id === viewForm.parent_company_id)?.registered_name
    const viewRdo = rdos.find(r => r.id === viewForm.rdo_id)
    return (
      <div className="max-w-4xl mx-auto space-y-5">
        <div className="flex items-center justify-between">
          <div>
            <button onClick={() => setShowView(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
            <h1 className="text-xl font-semibold text-gray-900">View Company</h1>
            <p className="text-sm text-gray-500 mt-0.5">{viewForm.registered_name}</p>
          </div>
          <button onClick={() => setShowView(false)}
            className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
            Close
          </button>
        </div>

        <div className={sectionClass}>
          <h2 className={headingClass}>Section 1 — Basic Information</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={labelClass}>Parent Company</label>
              <input readOnly value={parentName || (viewForm.parent_company_id ? viewForm.parent_company_id : 'None (Independent / Holding)')} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Entity Type</label>
              <input readOnly value={ENTITY_TYPES.find(t => t.value === viewForm.entity_type)?.label || viewForm.entity_type || '—'} className={roInput} />
            </div>
            <div className="col-span-2">
              <label className={labelClass}>Registered Name</label>
              <input readOnly value={viewForm.registered_name || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Trade Name</label>
              <input readOnly value={viewForm.trade_name || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Line of Business</label>
              <input readOnly value={viewForm.line_of_business || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>PSIC Code</label>
              <input readOnly value={viewForm.psic_code || '—'} className={roInput} />
            </div>
          </div>
        </div>

        <div className={sectionClass}>
          <h2 className={headingClass}>Section 2 — Registration & Tax Compliance</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={labelClass}>TIN</label>
              <input readOnly value={viewForm.tin || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Tax Registration</label>
              <input readOnly value={TAX_REG_LABELS[viewForm.tax_registration] || viewForm.tax_registration || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>RDO Code</label>
              <input readOnly value={viewRdo ? `${viewRdo.rdo_code} — ${viewRdo.rdo_name}` : viewForm.rdo_id || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>{viewForm.entity_type ? REG_NUMBER_LABEL[viewForm.entity_type] : 'Registration Number'}</label>
              <input readOnly value={viewForm.registration_number || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>BIR Registration Date</label>
              <input readOnly value={viewForm.bir_reg_date || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>SEC / DTI Registration Date</label>
              <input readOnly value={viewForm.sec_dti_reg_date || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>LGU / Mayor's Permit Date</label>
              <input readOnly value={viewForm.lgu_reg_date || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Accounting Period</label>
              <input readOnly value={
                viewForm.accounting_period === 'calendar' ? 'Calendar Year (Jan–Dec)' :
                viewForm.accounting_period === 'fiscal' ? 'Fiscal Year' : '—'
              } className={roInput} />
            </div>
            {viewForm.accounting_period === 'fiscal' && (
              <div>
                <label className={labelClass}>Fiscal Start Month</label>
                <input readOnly value={viewForm.fiscal_start_month ? MONTHS[parseInt(viewForm.fiscal_start_month) - 1] : '—'} className={roInput} />
              </div>
            )}
          </div>
        </div>

        <div className={sectionClass}>
          <h2 className={headingClass}>Section 3 — System Compliance (CAS / PTU)</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={labelClass}>CAS / PTU Number</label>
              <input readOnly value={viewForm.cas_permit_no || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Date Issued</label>
              <input readOnly value={viewForm.cas_date_issued || '—'} className={roInput} />
            </div>
          </div>
        </div>

        <div className={sectionClass}>
          <h2 className={headingClass}>Section 4 — Registered Address</h2>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2">
              <label className={labelClass}>Address Line 1</label>
              <input readOnly value={viewForm.address_line_1 || '—'} className={roInput} />
            </div>
            <div className="col-span-2">
              <label className={labelClass}>Address Line 2</label>
              <input readOnly value={viewForm.address_line_2 || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>City / Municipality</label>
              <input readOnly value={viewForm.city || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Province</label>
              <input readOnly value={viewForm.province || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>ZIP Code</label>
              <input readOnly value={viewForm.zip_code || '—'} className={roInput} />
            </div>
          </div>
        </div>

        <div className={sectionClass}>
          <h2 className={headingClass}>Section 5 — Contact & Authorized Representative</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className={labelClass}>Official Email</label>
              <input readOnly value={viewForm.email || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Phone Number</label>
              <input readOnly value={viewForm.phone_number || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Mobile Number</label>
              <input readOnly value={viewForm.mobile_number || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Signatory Name</label>
              <input readOnly value={viewForm.signatory_name || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Signatory Position</label>
              <input readOnly value={viewForm.signatory_position || '—'} className={roInput} />
            </div>
            <div>
              <label className={labelClass}>Signatory TIN</label>
              <input readOnly value={viewForm.signatory_tin || '—'} className={roInput} />
            </div>
          </div>
        </div>
      </div>
    )
  }

  // FORM VIEW
  if (showForm) return (
    <div className="max-w-4xl mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <button onClick={() => setShowForm(false)} className="text-xs text-gray-500 hover:text-gray-900 mb-1">← Back to list</button>
          <h1 className="text-xl font-semibold text-gray-900">{editId ? 'Edit Company' : 'Create New Company'}</h1>
          <p className="text-sm text-gray-500 mt-0.5">Legal, tax, and registration details</p>
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowForm(false)}
            className="border border-gray-300 text-gray-700 px-4 py-2 rounded-md text-sm hover:bg-gray-50">
            Cancel
          </button>
          <button onClick={handleSave} disabled={saving}
            className="bg-gray-900 text-white px-5 py-2 rounded-md text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
            {saving ? 'Saving...' : saved ? '✓ Saved' : editId ? 'Update Company' : 'Save Company'}
          </button>
        </div>
      </div>

      <div className={sectionClass}>
        <h2 className={headingClass}>Section 1 — Basic Information</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={labelClass}>Parent Company</label>
            <select value={form.parent_company_id} onChange={e => set('parent_company_id', e.target.value)} className={inputClass}>
              <option value="">None (Independent / Holding)</option>
              {companies.filter(c => c.id !== editId).map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
            </select>
          </div>
          <div>
            <label className={labelClass}>Entity Type <span className="text-red-500">*</span></label>
            <select value={form.entity_type} onChange={e => set('entity_type', e.target.value)} className={inputClass}>
              <option value="">Select...</option>
              {ENTITY_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </div>
          <div className="col-span-2">
            <label className={labelClass}>Registered Name <span className="text-red-500">*</span></label>
            <input value={form.registered_name} onChange={e => set('registered_name', e.target.value)}
              className={inputClass} placeholder="As it appears on BIR Form 2303" />
          </div>
          <div>
            <label className={labelClass}>Trade Name</label>
            <input value={form.trade_name} onChange={e => set('trade_name', e.target.value)}
              className={inputClass} placeholder="Doing Business As (DBA)" />
          </div>
          <div>
            <label className={labelClass}>Line of Business <span className="text-red-500">*</span></label>
            <input value={form.line_of_business} onChange={e => set('line_of_business', e.target.value)}
              className={inputClass} placeholder="Main business activity" />
          </div>
          <div>
            <label className={labelClass}>PSIC Code <span className="text-red-500">*</span></label>
            <input value={form.psic_code} onChange={e => set('psic_code', e.target.value)}
              className={inputClass} placeholder="Philippine Standard Industrial Classification" />
          </div>
        </div>
      </div>

      <div className={sectionClass}>
        <h2 className={headingClass}>Section 2 — Registration & Tax Compliance</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={labelClass}>TIN <span className="text-red-500">*</span></label>
            <input value={form.tin} onChange={e => set('tin', e.target.value)} className={inputClass} placeholder="000-000-000-00000" />
          </div>
          <div>
            <label className={labelClass}>Tax Registration <span className="text-red-500">*</span></label>
            <select value={form.tax_registration} onChange={e => set('tax_registration', e.target.value)} className={inputClass}>
              <option value="">Select...</option>
              <option value="vat">VAT</option>
              <option value="non_vat">Non-VAT (Percentage Tax)</option>
              <option value="exempt">Exempt</option>
            </select>
          </div>
          <div>
            <label className={labelClass}>RDO Code <span className="text-red-500">*</span></label>
            <select value={form.rdo_id} onChange={e => set('rdo_id', e.target.value)} className={inputClass}>
              <option value="">Select RDO...</option>
              {rdos.map(r => <option key={r.id} value={r.id}>{r.rdo_code} — {r.rdo_name}</option>)}
            </select>
          </div>
          <div>
            <label className={labelClass}>{form.entity_type ? REG_NUMBER_LABEL[form.entity_type] : 'Registration Number'}</label>
            <input value={form.registration_number} onChange={e => set('registration_number', e.target.value)}
              className={inputClass} placeholder="SEC / DTI / CDA number" />
          </div>
          <div>
            <label className={labelClass}>BIR Registration Date</label>
            <input type="date" value={form.bir_reg_date} onChange={e => set('bir_reg_date', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>SEC / DTI Registration Date</label>
            <input type="date" value={form.sec_dti_reg_date} onChange={e => set('sec_dti_reg_date', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>LGU / Mayor's Permit Date</label>
            <input type="date" value={form.lgu_reg_date} onChange={e => set('lgu_reg_date', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>Accounting Period <span className="text-red-500">*</span></label>
            <select value={form.accounting_period} onChange={e => set('accounting_period', e.target.value)} className={inputClass}>
              <option value="">Select...</option>
              <option value="calendar">Calendar Year (Jan–Dec)</option>
              <option value="fiscal">Fiscal Year</option>
            </select>
          </div>
          {form.accounting_period === 'fiscal' && (
            <div>
              <label className={labelClass}>Fiscal Start Month <span className="text-red-500">*</span></label>
              <select value={form.fiscal_start_month} onChange={e => set('fiscal_start_month', e.target.value)} className={inputClass}>
                <option value="">Select month...</option>
                {MONTHS.map((m, i) => <option key={i} value={i + 1}>{m}</option>)}
              </select>
            </div>
          )}
        </div>
      </div>

      <div className={sectionClass}>
        <h2 className={headingClass}>Section 3 — System Compliance (CAS / PTU)</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={labelClass}>CAS / PTU Number</label>
            <input value={form.cas_permit_no} onChange={e => set('cas_permit_no', e.target.value)}
              className={inputClass} placeholder="Acknowledgement Certificate or PTU number" />
          </div>
          <div>
            <label className={labelClass}>Date Issued</label>
            <input type="date" value={form.cas_date_issued} onChange={e => set('cas_date_issued', e.target.value)} className={inputClass} />
          </div>
        </div>
      </div>

      <div className={sectionClass}>
        <h2 className={headingClass}>Section 4 — Registered Address</h2>
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2">
            <label className={labelClass}>Address Line 1 <span className="text-red-500">*</span></label>
            <input value={form.address_line_1} onChange={e => set('address_line_1', e.target.value)}
              className={inputClass} placeholder="Unit / Building / Lot / Block / Street" />
          </div>
          <div className="col-span-2">
            <label className={labelClass}>Address Line 2 <span className="text-red-500">*</span></label>
            <input value={form.address_line_2} onChange={e => set('address_line_2', e.target.value)}
              className={inputClass} placeholder="Subdivision / Village / Barangay" />
          </div>
          <div>
            <label className={labelClass}>City / Municipality <span className="text-red-500">*</span></label>
            <input value={form.city} onChange={e => set('city', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>Province <span className="text-red-500">*</span></label>
            <input value={form.province} onChange={e => set('province', e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>ZIP Code <span className="text-red-500">*</span></label>
            <input value={form.zip_code} onChange={e => set('zip_code', e.target.value)}
              className={inputClass} placeholder="4-digit postal code" maxLength={4} />
          </div>
        </div>
      </div>

      <div className={sectionClass}>
        <h2 className={headingClass}>Section 5 — Contact & Authorized Representative</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className={labelClass}>Official Email <span className="text-red-500">*</span></label>
            <input type="email" value={form.email} onChange={e => set('email', e.target.value)}
              className={inputClass} placeholder="Registered company email" />
          </div>
          <div>
            <label className={labelClass}>Phone Number</label>
            <input value={form.phone_number} onChange={e => set('phone_number', e.target.value)} className={inputClass} placeholder="Landline" />
          </div>
          <div>
            <label className={labelClass}>Mobile Number</label>
            <input value={form.mobile_number} onChange={e => set('mobile_number', e.target.value)} className={inputClass} placeholder="Mobile" />
          </div>
          <div>
            <label className={labelClass}>Signatory Name <span className="text-red-500">*</span></label>
            <input value={form.signatory_name} onChange={e => set('signatory_name', e.target.value)}
              className={inputClass} placeholder="Authorized to sign tax returns and 2307s" />
          </div>
          <div>
            <label className={labelClass}>Signatory Position <span className="text-red-500">*</span></label>
            <input value={form.signatory_position} onChange={e => set('signatory_position', e.target.value)}
              className={inputClass} placeholder="e.g., President, Treasurer, Owner" />
          </div>
          <div>
            <label className={labelClass}>Signatory TIN</label>
            <input value={form.signatory_tin} onChange={e => set('signatory_tin', e.target.value)}
              className={inputClass} placeholder="Personal TIN of signatory" />
          </div>
        </div>
      </div>
    </div>
  )

  // LIST VIEW
  const filtered = companies.filter(c => {
    const matchSearch = !search ||
      c.registered_name?.toLowerCase().includes(search.toLowerCase()) ||
      c.tin?.includes(search)
    const matchStatus = filterStatus === 'all' ||
      (filterStatus === 'active' && c.is_active) ||
      (filterStatus === 'inactive' && !c.is_active)
    return matchSearch && matchStatus
  })

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Company Setup</h1>
          <p className="text-sm text-gray-500 mt-0.5">Manage all registered business entities</p>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3 flex-wrap">
        <input value={search} onChange={e => setSearch(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-64 focus:outline-none focus:ring-2 focus:ring-gray-900"
          placeholder="Search by name or TIN..." />
        <select value={filterStatus} onChange={e => setFilterStatus(e.target.value as typeof filterStatus)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm focus:outline-none">
          <option value="all">All Status</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
        <div className="ml-auto flex items-center gap-2">
          <button onClick={() => { setShowImport(true); setImportRows([]); setImportDone(false) }}
            className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
            ↑ Import
          </button>
          <button className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
            ↓ Export
          </button>
          <button className="border border-gray-300 text-gray-700 px-3 py-1.5 rounded-md text-sm hover:bg-gray-50">
            🖨 Print
          </button>
          <button onClick={openCreate}
            className="bg-gray-900 text-white px-4 py-1.5 rounded-md text-sm font-medium hover:bg-gray-800">
            + Create New Company
          </button>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 border-b border-gray-200">
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Registered Name</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Parent Company</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">TIN</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">RDO</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Tax Type</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Status</th>
              <th className="text-left px-4 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide">Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan={7} className="text-center py-16 text-gray-400">
                  <p className="text-base font-medium text-gray-500">No Companies Found</p>
                  <p className="text-sm mt-1">Click "+ Create New Company" to add your first company.</p>
                </td>
              </tr>
            ) : filtered.map((c, i) => (
              <tr key={c.id} className={`border-b border-gray-100 hover:bg-gray-50 transition-colors ${i % 2 === 1 ? 'bg-gray-50/50' : ''}`}>
                <td className="px-4 py-3 font-medium text-gray-900">
                  {c.registered_name}
                  {c.trade_name && <span className="text-gray-400 text-xs ml-1">({c.trade_name})</span>}
                </td>
                <td className="px-4 py-3 text-gray-500">—</td>
                <td className="px-4 py-3 text-gray-600 font-mono">{c.tin}</td>
                <td className="px-4 py-3 text-gray-600">
                  {c.ref_rdo_codes ? `${c.ref_rdo_codes.rdo_code} — ${c.ref_rdo_codes.rdo_name}` : '—'}
                </td>
                <td className="px-4 py-3">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                    c.tax_registration === 'vat' ? 'bg-blue-50 text-blue-700' :
                    c.tax_registration === 'non_vat' ? 'bg-amber-50 text-amber-700' :
                    'bg-gray-100 text-gray-600'
                  }`}>
                    {TAX_REG_LABELS[c.tax_registration] || c.tax_registration}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                    c.is_active ? 'bg-green-50 text-green-700' : 'bg-gray-100 text-gray-500'
                  }`}>
                    {c.is_active ? 'Active' : 'Inactive'}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <button onClick={() => openView(c)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">View</button>
                    <button onClick={() => openEdit(c)} className="text-xs text-blue-600 hover:text-blue-800 font-medium">Edit</button>
                    <button onClick={() => handleToggleStatus(c)} className="text-xs text-gray-500 hover:text-gray-700 font-medium">
                      {c.is_active ? 'Deactivate' : 'Activate'}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {filtered.length > 0 && (
          <div className="px-4 py-3 border-t border-gray-100 text-xs text-gray-500">
            Showing {filtered.length} of {companies.length} companies
          </div>
        )}
      </div>
    </div>
  )
}