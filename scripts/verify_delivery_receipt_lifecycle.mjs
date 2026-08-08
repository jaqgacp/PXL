#!/usr/bin/env node
/**
 * Delivery Receipt lifecycle, proven ACROSS TRANSACTIONS (Backlog 18c).
 *
 * WHY THIS EXISTS AND WHY IT IS NOT A pgTAP FILE
 *   pgTAP runs every assertion inside ONE transaction. The status guard on
 *   `delivery_receipts` has a `same_txn` escape hatch — a row written by the
 *   current transaction may still be updated freely — so inside pgTAP the guard
 *   never engages, and a whole class of defect is invisible to all 131 files.
 *
 *   One such defect was live: `delivery_receipts` became a posting document on
 *   2026-08-03, but its 2026-07-04 status guard still allowed only `delivered_at`
 *   to change once the row left draft. The final statement of
 *   `fn_post_delivery_receipt`, which stamps `journal_entry_id` / `posted_at` /
 *   `posted_by`, was therefore refused whenever the receipt had been marked
 *   delivered in an EARLIER transaction — which is exactly what the screen does:
 *   it commits the status update, then calls the posting RPC.
 *
 *   Every statement below is its own `supabase db query` invocation, so every
 *   statement is its own connection and its own committed transaction — the same
 *   shape as a browser making one request per action.
 *
 * WHAT IT PROVES
 *   1. A delivery marked delivered in one transaction POSTS in the next.
 *   2. Stock leaves and the cost parks in Goods Delivered Not Invoiced.
 *   3. The delivery CANCELS in a further transaction, the stock comes back, and
 *      the clearing account nets to zero.
 *
 * It provisions its own company and never reads the canonical/demo seed
 * (`PXL_HOW_WE_WORK.md` §5a). Run against a local Supabase:
 *
 *     node scripts/verify_delivery_receipt_lifecycle.mjs
 */
import { execFileSync } from 'node:child_process'

const P = '19000000-0000-0000-0000-0000000000'   // fixture id prefix
const id = {
  user: `${P}01`, company: `${P}c1`, branch: `${P}d1`, fy: `${P}f1`,
  cash: `${P}a1`, ar: `${P}a2`, inv: `${P}a4`, clearing: `${P}a0`,
  vat: `${P}a5`, sales: `${P}a6`, cogs: `${P}a8`, variance: `${P}a9`,
  customer: `${P}e1`, uom: `${P}ab`, category: `${P}ca`, item: `${P}bb`,
  warehouse: `${P}ba`, dr: `${P}90`, drLine: `${P}91`,
}

let failures = 0
const log = (ok, message) => {
  if (!ok) failures += 1
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${message}`)
}

/**
 * One invocation = one connection = one committed transaction. The CLI refuses
 * multiple commands per call, which is exactly the property this script needs.
 */
function sql(statement, { tolerant = false } = {}) {
  try {
    return execFileSync('npx', ['supabase', 'db', 'query', '--local', statement],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  } catch (error) {
    const text = `${error.stdout || ''}\n${error.stderr || ''}`.trim()
    if (tolerant) return text
    console.error(`\nSQL FAILED:\n${statement}\n\n${text}\n`)
    process.exit(1)
  }
}

/** Reads run as `postgres`, which is not subject to RLS; no session claim needed. */
const scalar = (statement) => {
  const out = sql(statement)
  const match = out.match(/"v"\s*:\s*("?)([^",\n}]*)\1/)
  return match ? match[2].trim() : null
}

/** Writes that check `is_company_member` need an acting user, so they carry one. */
const asUser = (body) => sql(
  `DO $lifecycle$ BEGIN
     PERFORM set_config('request.jwt.claims', '{"sub":"${id.user}","role":"authenticated"}', true);
     ${body}
   END $lifecycle$;`)

console.log('\n── Delivery Receipt lifecycle across separate transactions ──\n')

// ── Each of these is its own committed transaction ───────────────────────────
const fixture = [
  `INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
     email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
   VALUES ('00000000-0000-0000-0000-000000000000', '${id.user}', 'authenticated',
     'authenticated', 'dr-lifecycle@test.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{}') ON CONFLICT (id) DO NOTHING`,

  `INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
     tax_registration, accounting_period, address_line_1, address_line_2, city, province,
     zip_code, email, signatory_name, signatory_position, created_by, updated_by)
   VALUES ('${id.company}', 'corporation', 'DR Lifecycle Corp', 'Wholesale',
     '400-000-190-00000', 'vat', 'calendar', 'L St', 'L Bldg', 'Makati', 'Metro Manila',
     '1200', 'dr-lifecycle@test.local', 'L Owner', 'President', '${id.user}', '${id.user}')`,

  `INSERT INTO user_company_memberships (user_id, company_id, role)
   VALUES ('${id.user}', '${id.company}', 'admin')`,

  `INSERT INTO branches (id, company_id, branch_code, branch_name, address_line_1,
     address_line_2, city, province, zip_code, created_by, updated_by)
   VALUES ('${id.branch}', '${id.company}', 'HO', 'Head Office', 'L St', '', 'Makati',
     'Metro Manila', '1200', '${id.user}', '${id.user}')`,

  `INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
   VALUES ('${id.fy}', '${id.company}', 'FY2026', '2026-01-01', '2026-12-31', true)`,

  `INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
     start_date, end_date, is_locked)
   SELECT '${id.company}', '${id.fy}', m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
     make_date(2026, m, 1), (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
   FROM generate_series(1, 12) AS m`,

  `INSERT INTO chart_of_accounts (id, company_id, account_code, account_name, account_type,
     normal_balance, is_postable, is_active, created_by, updated_by)
   VALUES
     ('${id.cash}',     '${id.company}', '1010', 'Cash on Hand',                 'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.ar}',       '${id.company}', '1200', 'Accounts Receivable',          'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.inv}',      '${id.company}', '1300', 'Merchandise Inventory',        'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.clearing}', '${id.company}', '1310', 'Goods Delivered Not Invoiced', 'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.vat}',      '${id.company}', '2100', 'Output VAT Payable',           'liability', 'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.sales}',    '${id.company}', '4010', 'Merchandise Sales',            'revenue',   'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.cogs}',     '${id.company}', '5010', 'Cost of Goods Sold',           'expense',   'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.variance}', '${id.company}', '5900', 'Inventory Variance',           'expense',   'debit',  true, true, '${id.user}', '${id.user}')`,

  `INSERT INTO company_accounting_config (company_id, ar_account_id, vat_payable_account_id,
     default_cash_account_id, inventory_account_id, sales_delivery_clearing_account_id,
     created_by, updated_by)
   VALUES ('${id.company}', '${id.ar}', '${id.vat}', '${id.cash}', '${id.inv}',
     '${id.clearing}', '${id.user}', '${id.user}')`,

  `INSERT INTO number_series (company_id, branch_id, document_type_id, prefix, number_length,
     starting_number, next_number, is_active, created_by, updated_by)
   SELECT '${id.company}', '${id.branch}', rdt.id, rdt.document_code || '-190-', 6, 1, 1,
     true, '${id.user}', '${id.user}'
   FROM ref_document_types rdt WHERE rdt.document_code IN ('SI', 'DR', 'CM', 'OR')`,

  `INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
     registered_address, delivery_address, created_by, updated_by)
   VALUES ('${id.customer}', '${id.company}', 'CUST-190', 'Lifecycle Buyer Inc',
     '444-555-666-190', 'Pasig', 'Pasig', '${id.user}', '${id.user}')`,

  `INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active,
     created_by, updated_by)
   VALUES ('${id.uom}', '${id.company}', 'EA', 'Each', true, '${id.user}', '${id.user}')`,

  `INSERT INTO item_categories (id, company_id, category_code, category_name,
     created_by, updated_by)
   VALUES ('${id.category}', '${id.company}', 'GEN', 'General', '${id.user}', '${id.user}')`,

  `INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
     standard_selling_price, standard_cost, default_sales_vat_id, sales_account_id,
     cogs_account_id, inventory_account_id, costing_method, created_by, updated_by)
   VALUES ('${id.item}', '${id.company}', 'GOODS-190', 'Traded Merchandise', 'inventory_item',
     '${id.category}', '${id.uom}', 1000, 600,
     (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12' LIMIT 1),
     '${id.sales}', '${id.cogs}', '${id.inv}', 'weighted_average', '${id.user}', '${id.user}')`,

  `INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
     gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
   VALUES ('${id.warehouse}', '${id.company}', '${id.branch}', 'MAIN', 'Main Warehouse',
     '${id.inv}', '${id.variance}', '${id.user}', '${id.user}')`,

  `INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
   VALUES ('${id.company}', '${id.warehouse}', '${id.item}', 20, 12000, 600)`,

  `INSERT INTO delivery_receipts (id, company_id, branch_id, customer_id,
     customer_name_snapshot, dr_number, dr_date, delivery_address, status, created_by, updated_by)
   VALUES ('${id.dr}', '${id.company}', '${id.branch}', '${id.customer}',
     'Lifecycle Buyer Inc', 'DR-190-000001', '2026-03-05', 'Pasig', 'draft',
     '${id.user}', '${id.user}')`,

  `INSERT INTO delivery_receipt_lines (id, dr_id, company_id, line_number, item_id,
     description, quantity, uom_id, warehouse_id, created_by, updated_by)
   VALUES ('${id.drLine}', '${id.dr}', '${id.company}', 1, '${id.item}',
     'Traded Merchandise', 5, '${id.uom}', '${id.warehouse}', '${id.user}', '${id.user}')`,
]
fixture.forEach((statement) => sql(statement))
log(true, `fixture committed over ${fixture.length} separate transactions (own company, 20 units on hand)`)

// ── The screen marks it delivered, and commits ───────────────────────────────
sql(`UPDATE delivery_receipts SET status = 'delivered', delivered_at = NOW() WHERE id = '${id.dr}'`)
log(true, 'delivery marked delivered and COMMITTED')

// ── A separate request calls the posting RPC. This is the step that failed
//    before the guard was widened.
asUser(`PERFORM fn_post_delivery_receipt('${id.dr}');`)
log(true, 'fn_post_delivery_receipt succeeded on a delivery committed by an EARLIER transaction')

log(scalar(`SELECT (journal_entry_id IS NOT NULL) AS v FROM delivery_receipts WHERE id = '${id.dr}'`) === 'true',
  '  the posting stamps were written — the guard no longer refuses them')
log(scalar(`SELECT qty_on_hand AS v FROM stock_balances WHERE warehouse_id = '${id.warehouse}' AND item_id = '${id.item}'`) === '15.0000',
  '  stock fell from 20 to 15')
log(scalar(`SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0) AS v FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id WHERE je.company_id = '${id.company}' AND jel.account_id = '${id.clearing}'`) === '3000.00',
  '  3,000 of cost is parked in Goods Delivered Not Invoiced')

// ── The warehouse reports a mis-ship. Another request cancels the delivery ───
asUser(`PERFORM fn_void_delivery_receipt('${id.dr}',
  (SELECT id FROM void_reason_codes WHERE code = 'DATA_ENTRY_ERROR' LIMIT 1),
  'shipped to the wrong address');`)
log(true, 'fn_void_delivery_receipt succeeded across the commit boundary')

log(scalar(`SELECT status AS v FROM delivery_receipts WHERE id = '${id.dr}'`) === 'cancelled',
  '  the delivery is cancelled')
log(scalar(`SELECT qty_on_hand AS v FROM stock_balances WHERE warehouse_id = '${id.warehouse}' AND item_id = '${id.item}'`) === '20.0000',
  '  the five units are back on hand')
log(scalar(`SELECT total_cost AS v FROM stock_balances WHERE warehouse_id = '${id.warehouse}' AND item_id = '${id.item}'`) === '12000.00',
  '  stock value is back to 12,000')
log(scalar(`SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0) AS v FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id WHERE je.company_id = '${id.company}' AND jel.account_id = '${id.clearing}'`) === '0.00',
  '  Goods Delivered Not Invoiced nets to zero')
log(scalar(`SELECT COALESCE(SUM(jel.debit_amount) - SUM(jel.credit_amount), 0) AS v FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id WHERE je.company_id = '${id.company}'`) === '0.00',
  '  every journal the company owns still balances')

// ── Cleanup, so a rerun starts clean ────────────────────────────────────────
const cleanup = [
  `DELETE FROM inventory_transactions WHERE company_id = '${id.company}'`,
  `DELETE FROM cas_document_void_events WHERE company_id = '${id.company}'`,
  `DELETE FROM cas_document_number_issuances WHERE company_id = '${id.company}'`,
  `UPDATE delivery_receipts SET journal_entry_id = NULL WHERE company_id = '${id.company}'`,
  `DELETE FROM journal_entry_lines WHERE je_id IN (SELECT id FROM journal_entries WHERE company_id = '${id.company}')`,
  `DELETE FROM journal_entries WHERE company_id = '${id.company}'`,
  `DELETE FROM delivery_receipt_lines WHERE company_id = '${id.company}'`,
  `DELETE FROM delivery_receipts WHERE company_id = '${id.company}'`,
  `DELETE FROM stock_balances WHERE company_id = '${id.company}'`,
  `DELETE FROM warehouses WHERE company_id = '${id.company}'`,
  `DELETE FROM items WHERE company_id = '${id.company}'`,
  `DELETE FROM item_categories WHERE company_id = '${id.company}'`,
  `DELETE FROM units_of_measure WHERE company_id = '${id.company}'`,
  `DELETE FROM customers WHERE company_id = '${id.company}'`,
  `DELETE FROM number_series WHERE company_id = '${id.company}'`,
  `DELETE FROM company_accounting_config WHERE company_id = '${id.company}'`,
  `DELETE FROM chart_of_accounts WHERE company_id = '${id.company}'`,
  `DELETE FROM fiscal_periods WHERE company_id = '${id.company}'`,
  `DELETE FROM fiscal_years WHERE company_id = '${id.company}'`,
  `DELETE FROM user_company_memberships WHERE company_id = '${id.company}'`,
  `DELETE FROM branches WHERE company_id = '${id.company}'`,
  `DELETE FROM sys_audit_logs WHERE company_id = '${id.company}'`,
  `DELETE FROM companies WHERE id = '${id.company}'`,
  `DELETE FROM auth.users WHERE id = '${id.user}'`,
]
cleanup.forEach((statement) => sql(statement, { tolerant: true }))
log(true, 'fixture removed')

console.log(`\n${failures === 0 ? 'PASS' : 'FAIL'}: delivery receipt lifecycle across transactions (${failures} failure(s))\n`)
process.exit(failures === 0 ? 0 : 1)
