import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import test from 'node:test'

const root = process.cwd()
const app = readFileSync(join(root, 'src/App.tsx'), 'utf8')
const shell = readFileSync(join(root, 'src/components/AppShell.tsx'), 'utf8')

test('opening balances are routed, navigable, and use only the governed lifecycle RPCs', () => {
  const page = readFileSync(join(root, 'src/pages/OpeningBalancesPage.tsx'), 'utf8')
  assert.match(app, /path="\/opening-balances"/)
  assert.match(shell, /s\('Opening Balances', 'opening-balances'\)/)
  for (const rpc of ['fn_save_opening_balance', 'fn_post_opening_balance', 'fn_reverse_opening_balance']) {
    assert.match(page, new RegExp(rpc))
  }
  assert.doesNotMatch(page, /inventory_events|inventory_event_/)
})

test('opening AR and AP continue through ordinary settlement workflows', () => {
  const receipts = readFileSync(join(root, 'src/pages/ReceiptsPage.tsx'), 'utf8')
  const vouchers = readFileSync(join(root, 'src/pages/PaymentVouchersPage.tsx'), 'utf8')
  const migration = readFileSync(
    join(root, 'supabase/migrations/20260802000002_opening_balances.sql'),
    'utf8',
  )
  assert.match(receipts, /opening_balance_ar_lines/)
  assert.match(receipts, /opening_ar_line_id/)
  assert.match(vouchers, /opening_balance_ap_lines/)
  assert.match(vouchers, /opening_ap_line_id/)
  assert.match(migration, /fn_validate_settlement_posting/)
  assert.match(migration, /Receipt application exceeds opening invoice/)
  assert.match(migration, /Payment application exceeds opening bill/)
})

test('supplier master and payment vouchers surface verified payee bank snapshots', () => {
  const supplier = readFileSync(join(root, 'src/pages/SuppliersPage.tsx'), 'utf8')
  const voucher = readFileSync(join(root, 'src/pages/PaymentVouchersPage.tsx'), 'utf8')
  assert.match(supplier, /supplier_bank_accounts/)
  assert.match(supplier, /verification_status/)
  assert.match(voucher, /supplier_bank_account_id/)
  assert.match(voucher, /payee_account_number_snapshot/)
  assert.match(voucher, /verified/)
  const migration = readFileSync(
    join(root, 'supabase/migrations/20260802000003_supplier_bank_details.sql'),
    'utf8',
  )
  assert.match(migration, /A verified supplier bank account is required for bank-transfer vouchers/)
})

test('PAD-003 exposes four administration screens and a server-side invite boundary', () => {
  const page = readFileSync(join(root, 'src/pages/AdministrationPage.tsx'), 'utf8')
  const invite = readFileSync(join(root, 'supabase/functions/admin-invite/index.ts'), 'utf8')
  for (const route of ['admin-users', 'admin-memberships', 'admin-roles', 'admin-branch-scopes']) {
    assert.match(app, new RegExp(`path="/${route}"`))
    assert.match(shell, new RegExp(`'${route}'`))
  }
  assert.match(page, /fn_admin_list_company_users/)
  assert.match(page, /fn_admin_upsert_membership/)
  assert.match(page, /fn_admin_set_branch_scopes/)
  assert.match(invite, /SUPABASE_SERVICE_ROLE_KEY/)
  assert.match(invite, /inviteUserByEmail/)
  assert.doesNotMatch(page, /SUPABASE_SERVICE_ROLE_KEY/)
})

test('the existing master-data framework is reachable with preview before commit', () => {
  const page = readFileSync(join(root, 'src/pages/MasterDataImportPage.tsx'), 'utf8')
  assert.match(app, /path="\/master-data-import"/)
  assert.match(shell, /s\('Master Data Import', 'master-data-import'\)/)
  assert.match(page, /fn_master_data_import_template/)
  assert.match(page, /fn_import_master_data/)
  assert.match(page, /p_preview: !commit/)
  assert.match(page, /disabled=\{busy \|\| !preview\?\.valid\}/)
})
