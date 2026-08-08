import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '@/lib/supabase'

type TraceRow = {
  relationship_id: string
  relationship_type: string
  relationship_status: string
  source_document_type: string
  source_document_id: string
  source_document_number: string | null
  source_status: string | null
  target_document_type: string
  target_document_id: string
  target_document_number: string | null
  target_status: string | null
  quantity: number | null
  amount: number | null
}

const routes: Record<string, string> = {
  sales_quotation: '/quotations',
  sales_order: '/sales-orders',
  delivery_receipt: '/delivery-receipts',
  sales_invoice: '/sales-invoices',
  official_receipt: '/receipts',
}

const labels: Record<string, string> = {
  sales_quotation: 'Quotation',
  sales_order: 'Sales Order',
  delivery_receipt: 'Delivery Receipt',
  sales_invoice: 'Sales Invoice',
  official_receipt: 'Official Receipt',
}

export function SalesDocumentTrace({ documentId }: { documentId?: string | null }) {
  const [rows, setRows] = useState<TraceRow[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    if (!documentId) {
      setRows([])
      return () => { active = false }
    }
    setLoading(true)
    setError('')
    void supabase.from('vw_sales_document_trace').select('*')
      .or(`source_document_id.eq.${documentId},target_document_id.eq.${documentId}`)
      .order('created_at')
      .then(({ data, error: queryError }) => {
        if (!active) return
        setRows((data || []) as TraceRow[])
        setError(queryError?.message || '')
        setLoading(false)
      })
    return () => { active = false }
  }, [documentId])

  if (!documentId) return <div className="pxl-validation-message">Save the document to establish conversion lineage.</div>
  if (loading) return <div className="pxl-validation-message">Loading authoritative document trace…</div>
  if (error) return <div className="pxl-validation-message border border-red-200 bg-red-50 text-red-700">{error}</div>
  if (rows.length === 0) return <div className="pxl-validation-message">No upstream or downstream document relationship is recorded.</div>

  return (
    <div className="overflow-x-auto rounded border border-gray-200">
      <table className="pxl-data-grid w-full">
        <thead><tr>
          {['Direction','Relationship','Document','Status','Quantity / Amount','Open'].map(label => <th key={label} className="text-left">{label}</th>)}
        </tr></thead>
        <tbody>
          {rows.flatMap(row => {
            const upstream = row.target_document_id === documentId
            const type = upstream ? row.source_document_type : row.target_document_type
            const id = upstream ? row.source_document_id : row.target_document_id
            const number = upstream ? row.source_document_number : row.target_document_number
            const status = upstream ? row.source_status : row.target_status
            return [<tr key={`${row.relationship_id}-${upstream ? 'up' : 'down'}`}>
              <td>{upstream ? 'Upstream' : 'Downstream'}</td>
              <td className="capitalize">{row.relationship_type} · {row.relationship_status}</td>
              <td><span className="font-medium">{labels[type] || type}</span><br /><span className="font-mono text-xs">{number || id}</span></td>
              <td className="capitalize">{status || 'Recorded'}</td>
              <td className="font-mono">{row.quantity != null ? Number(row.quantity).toLocaleString() : row.amount != null ? `₱${Number(row.amount).toLocaleString(undefined, { minimumFractionDigits: 2 })}` : '—'}</td>
              <td><Link to={routes[type] || '/'} className="text-blue-700 hover:underline">Open {labels[type] || 'document'}</Link></td>
            </tr>]
          })}
        </tbody>
      </table>
    </div>
  )
}

export default SalesDocumentTrace
