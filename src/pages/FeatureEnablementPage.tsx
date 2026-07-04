import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'

type FeatureDef = {
  id: string; feature_key: string; feature_name: string; module_category: string
  description: string; always_enabled: boolean; sort_order: number
}
type Enablement = { id?: string; feature_definition_id: string; is_enabled: boolean }
type Company = { id: string; registered_name: string }

const MODULE_COLORS: Record<string, string> = {
  Accounting: 'bg-blue-50 text-blue-700',
  Sales: 'bg-green-50 text-green-700',
  Purchasing: 'bg-orange-50 text-orange-700',
  Inventory: 'bg-purple-50 text-purple-700',
  'Fixed Assets': 'bg-amber-50 text-amber-700',
  'Banking & Treasury': 'bg-cyan-50 text-cyan-700',
  Compliance: 'bg-red-50 text-red-700',
  Setup: 'bg-gray-100 text-gray-600',
}

export default function FeatureEnablementPage() {
  const [features, setFeatures] = useState<FeatureDef[]>([])
  const [enablements, setEnablements] = useState<Enablement[]>([])
  const [companies, setCompanies] = useState<Company[]>([])
  const [selectedCompany, setSelectedCompany] = useState('')
  const [saving, setSaving] = useState<string | null>(null)
  const [saved, setSaved] = useState<string | null>(null)

  useEffect(() => {
    supabase.from('ref_feature_definitions').select('*').order('sort_order').then(({ data }) => setFeatures((data || []) as unknown as FeatureDef[]))
    supabase.from('companies').select('id,registered_name').order('registered_name').then(({ data }) => setCompanies(data || []))
  }, [])

  useEffect(() => {
    if (!selectedCompany) { setEnablements([]); return }
    supabase.from('sys_feature_enablement').select('id, feature_definition_id, is_enabled').eq('company_id', selectedCompany)
      .then(({ data }) => setEnablements(data || []))
  }, [selectedCompany])

  const getStatus = (featureId: string): boolean => {
    const e = enablements.find(e => e.feature_definition_id === featureId)
    return e?.is_enabled ?? false
  }
  const toggle = async (feature: FeatureDef) => {
    if (!selectedCompany || feature.always_enabled) return
    const current = getStatus(feature.id)
    const newVal = !current
    setSaving(feature.id); setSaved(null)
    const { error } = await supabase.from('sys_feature_enablement').upsert([{
      company_id: selectedCompany,
      feature_definition_id: feature.id,
      is_enabled: newVal,
      ...(newVal ? { enabled_at: new Date().toISOString() } : { disabled_at: new Date().toISOString() }),
    }], { onConflict: 'company_id,feature_definition_id' })
    if (error) alert('Error: ' + error.message)
    else {
      setEnablements(prev => {
        const existing = prev.find(e => e.feature_definition_id === feature.id)
        if (existing) return prev.map(e => e.feature_definition_id === feature.id ? { ...e, is_enabled: newVal } : e)
        return [...prev, { feature_definition_id: feature.id, is_enabled: newVal }]
      })
      setSaved(feature.id)
      setTimeout(() => setSaved(null), 2000)
    }
    setSaving(null)
  }

  const modules = [...new Set(features.map(f => f.module_category))]

  return (
    <div className="space-y-4">
      <div><h1 className="text-xl font-semibold text-gray-900">Feature Enablement</h1>
        <p className="text-sm text-gray-500 mt-0.5">Enable or disable modules per company. Features can only be enabled once all prerequisites are met.</p></div>

      <div className="bg-white border border-gray-200 rounded-lg px-4 py-3 flex items-center gap-3">
        <select value={selectedCompany} onChange={e => setSelectedCompany(e.target.value)}
          className="border border-gray-300 rounded-md px-3 py-1.5 text-sm w-72 focus:outline-none focus:ring-2 focus:ring-gray-900">
          <option value="">Select a company to manage features...</option>
          {companies.map(c => <option key={c.id} value={c.id}>{c.registered_name}</option>)}
        </select>
      </div>

      {!selectedCompany ? (
        <div className="bg-white border border-gray-200 rounded-lg text-center py-16">
          <p className="text-base font-medium text-gray-500">Select a Company</p>
          <p className="text-sm mt-1 text-gray-400">Choose a company above to manage its feature toggles.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {modules.map(module => {
            const moduleFeatures = features.filter(f => f.module_category === module)
            return (
              <div key={module} className="bg-white border border-gray-200 rounded-lg overflow-hidden">
                <div className="px-4 py-3 border-b border-gray-100 flex items-center gap-2">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${MODULE_COLORS[module] || 'bg-gray-100 text-gray-600'}`}>{module}</span>
                  <span className="text-xs text-gray-400 ml-1">{moduleFeatures.length} feature{moduleFeatures.length !== 1 ? 's' : ''}</span>
                </div>
                <div>
                  {moduleFeatures.map((feature, i) => {
                    const enabled = feature.always_enabled || getStatus(feature.id)
                    const isSaving = saving === feature.id
                    const justSaved = saved === feature.id
                    return (
                      <div key={feature.id} className={`flex items-start gap-4 px-4 py-4 ${i < moduleFeatures.length - 1 ? 'border-b border-gray-50' : ''}`}>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <p className="text-sm font-medium text-gray-900">{feature.feature_name}</p>
                            {feature.always_enabled && (
                              <span className="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-blue-50 text-blue-600">Always On</span>
                            )}
                          </div>
                          <p className="text-xs text-gray-500 mt-0.5">{feature.description}</p>
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          {justSaved && <span className="text-xs text-green-600 font-medium">✓ Saved</span>}
                          {isSaving && <span className="text-xs text-gray-400">Saving...</span>}
                          <button
                            onClick={() => toggle(feature)}
                            disabled={feature.always_enabled || isSaving}
                            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none ${enabled ? 'bg-gray-900' : 'bg-gray-200'} ${feature.always_enabled ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer'}`}
                          >
                            <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${enabled ? 'translate-x-6' : 'translate-x-1'}`} />
                          </button>
                          <span className={`text-xs font-medium w-14 ${enabled ? 'text-green-700' : 'text-gray-400'}`}>
                            {enabled ? 'Enabled' : 'Disabled'}
                          </span>
                        </div>
                      </div>
                    )
                  })}
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
