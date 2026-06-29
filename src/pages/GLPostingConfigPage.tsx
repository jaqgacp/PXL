import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAppCtx } from '@/lib/context'

type COAAccount = { id: string; account_code: string; account_name: string; account_type: string }
type Config = {
  id?: string
  ar_account_id: string
  vat_payable_account_id: string
  ewt_withheld_account_id: string
  default_cash_account_id: string
}

const EMPTY: Config = { ar_account_id: '', vat_payable_account_id: '', ewt_withheld_account_id: '', default_cash_account_id: '' }

export default function GLPostingConfigPage() {
  const { companyId } = useAppCtx()
  const [config, setConfig] = useState<Config>(EMPTY)
  const [accounts, setAccounts] = useState<COAAccount[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!companyId) { setConfig(EMPTY); return }
    setLoading(true)
    Promise.all([
      supabase.from('chart_of_accounts').select('id,account_code,account_name,account_type')
        .eq('company_id', companyId).eq('is_active', true).eq('is_postable', true)
        .order('account_code'),
      supabase.from('company_accounting_config').select('*').eq('company_id', companyId).maybeSingle(),
    ]).then(([coaRes, cfgRes]) => {
      setAccounts(coaRes.data as COAAccount[] || [])
      if (cfgRes.data) {
        setConfig({
          id: cfgRes.data.id,
          ar_account_id: cfgRes.data.ar_account_id || '',
          vat_payable_account_id: cfgRes.data.vat_payable_account_id || '',
          ewt_withheld_account_id: cfgRes.data.ewt_withheld_account_id || '',
          default_cash_account_id: cfgRes.data.default_cash_account_id || '',
        })
      } else {
        setConfig(EMPTY)
      }
      setLoading(false)
    })
  }, [companyId])

  const save = async () => {
    if (!companyId) return
    setSaving(true); setError(''); setSaved(false)
    const payload = {
      company_id: companyId,
      ar_account_id: config.ar_account_id || null,
      vat_payable_account_id: config.vat_payable_account_id || null,
      ewt_withheld_account_id: config.ewt_withheld_account_id || null,
      default_cash_account_id: config.default_cash_account_id || null,
      updated_by: (await supabase.auth.getUser()).data.user?.id,
    }
    const { error: e } = config.id
      ? await supabase.from('company_accounting_config').update(payload).eq('id', config.id)
      : await supabase.from('company_accounting_config').insert({ ...payload, created_by: payload.updated_by })
    if (e) setError(e.message)
    else setSaved(true)
    setSaving(false)
  }

  const assetAccounts     = accounts.filter(a => a.account_type === 'asset')
  const liabilityAccounts = accounts.filter(a => a.account_type === 'liability')
  const allPostable       = accounts

  const sel = (label: string, value: string, onChange: (v: string) => void, list: COAAccount[], hint: string) => (
    <div className="flex flex-col gap-1">
      <label className="text-xs font-semibold text-gray-600 uppercase tracking-wide">{label}</label>
      <select value={value} onChange={e => { onChange(e.target.value); setSaved(false) }}
        className="border border-gray-300 rounded px-2.5 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 bg-white">
        <option value="">— not configured —</option>
        {list.map(a => <option key={a.id} value={a.id}>{a.account_code} — {a.account_name}</option>)}
      </select>
      <span className="text-[11px] text-gray-400">{hint}</span>
    </div>
  )

  return (
    <div className="max-w-2xl mx-auto px-5 py-8">
      <div className="mb-6">
        <h1 className="text-lg font-semibold text-gray-900">GL Posting Configuration</h1>
        <p className="text-sm text-gray-500 mt-1">
          Map document types to your Chart of Accounts. These accounts are required before any document can be posted.
        </p>
      </div>

      {!companyId ? (
        <div className="py-16 text-center text-sm text-gray-400">Select a company first.</div>
      ) : loading ? (
        <div className="space-y-4">{[...Array(4)].map((_, i) => <div key={i} className="h-14 bg-gray-100 rounded animate-pulse" />)}</div>
      ) : (
        <div className="bg-white border border-gray-200 rounded-lg divide-y divide-gray-100">
          <div className="px-5 py-4">
            <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-4">Accounts Receivable</div>
            {sel('AR Control Account', config.ar_account_id,
              v => setConfig(c => ({ ...c, ar_account_id: v })),
              assetAccounts,
              'Debited when posting Sales Invoices; credited when posting Receipts.')}
          </div>

          <div className="px-5 py-4">
            <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-4">VAT</div>
            {sel('Output VAT Payable', config.vat_payable_account_id,
              v => setConfig(c => ({ ...c, vat_payable_account_id: v })),
              liabilityAccounts,
              'Credited with the VAT portion when posting Sales Invoices. Required if any invoice has VAT.')}
          </div>

          <div className="px-5 py-4">
            <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-4">Withholding Tax</div>
            {sel('EWT Withheld (Receivable)', config.ewt_withheld_account_id,
              v => setConfig(c => ({ ...c, ewt_withheld_account_id: v })),
              assetAccounts,
              'Debited with the CWT amount when posting Receipts. Required if any receipt has CWT.')}
          </div>

          <div className="px-5 py-4">
            <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-4">Cash & Banking</div>
            {sel('Default Cash / Bank Account', config.default_cash_account_id,
              v => setConfig(c => ({ ...c, default_cash_account_id: v })),
              allPostable,
              'Used as the debit account on Receipts when no specific bank account is selected.')}
          </div>

          <div className="px-5 py-4 flex items-center gap-3">
            <button onClick={save} disabled={saving || !companyId}
              className="px-4 py-2 bg-gray-900 text-white rounded text-sm font-medium hover:bg-gray-800 disabled:opacity-50">
              {saving ? 'Saving…' : 'Save Configuration'}
            </button>
            {saved && <span className="text-sm text-green-700 font-medium">Saved.</span>}
            {error && <span className="text-sm text-red-600">{error}</span>}
          </div>
        </div>
      )}

      <div className="mt-6 bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 text-sm text-amber-800">
        <strong>Important:</strong> Posting any Sales Invoice or Receipt will fail until the AR Control Account is configured.
        All four accounts are recommended before using Cash Sales.
      </div>
    </div>
  )
}
