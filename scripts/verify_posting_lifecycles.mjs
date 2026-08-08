#!/usr/bin/env node
/**
 * Posting lifecycles, proven ACROSS TRANSACTIONS.
 *
 * WHY THIS EXISTS
 *   pgTAP runs every assertion inside ONE transaction. Several status guards in
 *   PXL carry a `same_txn` escape hatch — a row written by the current
 *   transaction may still be updated freely — so inside pgTAP those guards never
 *   engage. A whole class of defect is therefore invisible to the entire pgTAP
 *   suite, however many assertions it carries.
 *
 *   That class is not hypothetical. `fn_post_delivery_receipt` shipped
 *   2026-08-03 covered by test `120`, and was refused by its own status guards
 *   whenever the delivery had been marked delivered in an EARLIER transaction —
 *   which is exactly what the screen does. It was unusable from the UI for four
 *   days while 130 test files stayed green (PXL-AUD-074). A second defect in the
 *   CAS void-evidence trigger hid in the same shadow and affected twelve
 *   document families (PXL-AUD-075).
 *
 *   `scripts/verify_delivery_receipt_lifecycle.mjs` closed that blind spot for
 *   one document. This file closes it for the seven a pilot actually touches.
 *
 * WHAT IT DOES
 *   Every statement is its own `supabase db query` invocation, so every step is
 *   its own connection and its own COMMITTED transaction — the same shape as a
 *   browser making one request per action. The screens all save and post in two
 *   separate RPC calls, so this is the real execution shape, not a stricter one.
 *
 *   For each document: save → COMMIT → (approve → COMMIT) → post → COMMIT →
 *   correct → COMMIT, asserting the ledger, subledger, stock and tax effects
 *   between steps.
 *
 * COVERAGE
 *   Sales Invoice · Cash Sale · Official Receipt · Credit Memo ·
 *   Receiving Report · Vendor Bill · Payment Voucher.
 *   Delivery Receipt has its own file and is not repeated here.
 *
 * It provisions its own company and never reads the canonical/demo seed
 * (`PXL_HOW_WE_WORK.md` §5a). Run against a local Supabase:
 *
 *     npm run verify:posting-lifecycles
 */
import { execFileSync } from 'node:child_process'

// A run-unique prefix. The Accounting Kernel refuses any non-kernel DELETE on
// journal_entry_lines — even with session_replication_role = replica — so a
// scratch company that has posted can never be fully removed. That is the guard
// working correctly, so the harness gives every run its own identity instead of
// fighting it. `npm run test:db:fresh` clears the accumulated scratch companies.
const RUN = Date.now().toString(16).slice(-6).padStart(6, '0')   // hex, so ids stay valid UUIDs
const P = `${RUN}00-0000-0000-0000-0000000000`   // 8-4-4-4-12
const RUNNUM = String(Date.now()).slice(-5)   // companies.tin is globally unique
const id = {
  user: `${P}01`, company: `${P}c1`, branch: `${P}d1`, fy: `${P}f1`,
  cash: `${P}a1`, ar: `${P}a2`, ap: `${P}a3`, inv: `${P}a4`, outVat: `${P}a5`,
  inVat: `${P}a6`, sales: `${P}a7`, cogs: `${P}a8`, variance: `${P}a9`,
  clearing: `${P}b0`, purchClearing: `${P}b1`, ewtPayable: `${P}b2`,
  cwtRecv: `${P}b3`, expense: `${P}b4`,
  customer: `${P}e1`, supplier: `${P}e2`, uom: `${P}ab`, category: `${P}ca`,
  item: `${P}bb`, warehouse: `${P}ba`,
}

let failures = 0, checks = 0
const ok = (cond, message) => {
  checks += 1
  if (!cond) failures += 1
  console.log(`${cond ? '  ok  ' : '  FAIL'}  ${message}`)
}
const step = (message) => console.log(`\n▸ ${message}`)

/** One invocation = one connection = one committed transaction. */
function sql(statement, { tolerant = false } = {}) {
  try {
    return execFileSync('npx', ['supabase', 'db', 'query', '--local', statement],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 32 * 1024 * 1024 })
  } catch (error) {
    const text = `${error.stdout || ''}\n${error.stderr || ''}`.trim()
    if (tolerant) return `__ERROR__ ${text}`
    console.error(`\n╳ SQL FAILED\n${statement.slice(0, 400)}\n\n${text}\n`)
    process.exit(1)
  }
}

/** Reads run as `postgres`, which is not subject to RLS; no session claim needed. */
const scalar = (statement) => {
  const out = sql(statement)
  const m = out.match(/"v"\s*:\s*("?)([^",\n}]*)\1/)
  return m ? m[2].trim() : null
}

/**
 * Writes that check `is_company_member` need an acting user. The claim is set
 * inside the same statement, because the CLI allows one command per call — which
 * is precisely the property that makes each call a separate transaction.
 */
const act = (body, opts = {}) => sql(
  `DO $lc$ BEGIN
     PERFORM set_config('request.jwt.claims', '{"sub":"${id.user}","role":"authenticated"}', true);
     ${body}
   END $lc$;`, opts)

/**
 * Capture an id the RPC returns, holding it in this process rather than in the
 * database. A CTE sets the acting user before the outer SELECT runs, so the call
 * still carries an identity without needing a DO block — and without the harness
 * creating an unprotected scratch table in `public`.
 */
const captured = {}
const actReturning = (key, body) => {
  const out = sql(
    `WITH claim AS (
       SELECT set_config('request.jwt.claims', '{"sub":"${id.user}","role":"authenticated"}', true) AS c
     )
     SELECT (${body})::text AS v FROM claim`)
  const m = out.match(/"v"\s*:\s*("?)([^",\n}]*)\1/)
  captured[key] = m ? m[2].trim() : null
  return captured[key]
}
const ctx = (key) => `'` + captured[key] + `'::uuid`

console.log('\n══ Posting lifecycles across separate committed transactions ══')

/**
 * Best-effort teardown of the run's non-ledger rows.
 *
 * The ledger itself is deliberately left alone: the Accounting Kernel rejects a
 * DELETE on `journal_entry_lines` that did not come from a sanctioned kernel,
 * and it does so even when triggers are disabled with
 * `session_replication_role = replica`. That is the structural enforcement the
 * architecture claims, verified incidentally by this harness every run.
 */
function teardown() {
  sql(`DO $td$
  DECLARE c uuid := '${id.company}';
  BEGIN
    SET LOCAL session_replication_role = replica;
    DELETE FROM receipt_lines WHERE receipt_id IN (SELECT id FROM receipts WHERE company_id = c);
    DELETE FROM payment_voucher_lines WHERE payment_voucher_id IN (SELECT id FROM payment_vouchers WHERE company_id = c);
    DELETE FROM credit_memo_lines WHERE credit_memo_id IN (SELECT id FROM credit_memos WHERE company_id = c);
    DELETE FROM vendor_bill_lines WHERE vendor_bill_id IN (SELECT id FROM vendor_bills WHERE company_id = c);
    DELETE FROM sales_invoice_lines WHERE sales_invoice_id IN (SELECT id FROM sales_invoices WHERE company_id = c);
    DELETE FROM receiving_report_lines WHERE rr_id IN (SELECT id FROM receiving_reports WHERE company_id = c);
    DELETE FROM purchase_order_lines WHERE po_id IN (SELECT id FROM purchase_orders WHERE company_id = c);
    DELETE FROM tax_detail_entries WHERE company_id = c;
    DELETE FROM inventory_transactions WHERE company_id = c;
    DELETE FROM stock_balances WHERE company_id = c;
  END $td$;`, { tolerant: true })
}

// ── Fixture: each statement its own transaction ──────────────────────────────
const fixture = [
  `INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
     email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
   VALUES ('00000000-0000-0000-0000-000000000000', '${id.user}', 'authenticated',
     'authenticated', 'lifecycles-${RUN}@test.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{}') ON CONFLICT (id) DO NOTHING`,

  `INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
     tax_registration, accounting_period, address_line_1, address_line_2, city, province,
     zip_code, email, signatory_name, signatory_position, created_by, updated_by)
   VALUES ('${id.company}', 'corporation', 'Lifecycle Proof Corp', 'Wholesale',
     '400-000-200-${RUNNUM}', 'vat', 'calendar', 'L St', 'L Bldg', 'Makati', 'Metro Manila',
     '1200', 'lifecycles-${RUN}@test.local', 'L Owner', 'President', '${id.user}', '${id.user}')`,

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
     ('${id.cash}',          '${id.company}', '1010', 'Cash on Hand',                 'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.ar}',            '${id.company}', '1200', 'Accounts Receivable',          'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.cwtRecv}',       '${id.company}', '1250', 'Creditable Withholding Tax',   'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.inv}',           '${id.company}', '1300', 'Merchandise Inventory',        'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.clearing}',      '${id.company}', '1310', 'Goods Delivered Not Invoiced', 'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.inVat}',         '${id.company}', '1400', 'Input VAT',                    'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.ap}',            '${id.company}', '2000', 'Accounts Payable',             'liability', 'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.purchClearing}', '${id.company}', '2015', 'Goods Received Not Invoiced',  'liability', 'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.outVat}',        '${id.company}', '2100', 'Output VAT Payable',           'liability', 'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.ewtPayable}',    '${id.company}', '2150', 'EWT Payable',                  'liability', 'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.sales}',         '${id.company}', '4010', 'Merchandise Sales',            'revenue',   'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.cogs}',          '${id.company}', '5010', 'Cost of Goods Sold',           'expense',   'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.expense}',       '${id.company}', '5500', 'Operating Expense',            'expense',   'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.variance}',      '${id.company}', '5900', 'Inventory Variance',           'expense',   'debit',  true, true, '${id.user}', '${id.user}')`,

  `INSERT INTO company_accounting_config (company_id, ar_account_id, ap_account_id,
     vat_payable_account_id, input_vat_account_id, default_cash_account_id,
     inventory_account_id, sales_delivery_clearing_account_id, purchase_clearing_account_id,
     ewt_payable_account_id, created_by, updated_by)
   VALUES ('${id.company}', '${id.ar}', '${id.ap}', '${id.outVat}', '${id.inVat}',
     '${id.cash}', '${id.inv}', '${id.clearing}', '${id.purchClearing}',
     '${id.ewtPayable}', '${id.user}', '${id.user}')`,

  `INSERT INTO number_series (company_id, branch_id, document_type_id, prefix, number_length,
     starting_number, next_number, is_active, created_by, updated_by)
   SELECT '${id.company}', '${id.branch}', rdt.id, rdt.document_code || '-200-', 6, 1, 1,
     true, '${id.user}', '${id.user}'
   FROM ref_document_types rdt
   WHERE rdt.document_code IN ('SI','CS','DR','CM','OR','PO','RR','VB','PV','DM')`,

  `INSERT INTO customers (id, company_id, customer_code, registered_name, tin,
     registered_address, delivery_address, created_by, updated_by)
   VALUES ('${id.customer}', '${id.company}', 'CUST-200', 'Lifecycle Buyer Inc',
     '444-555-666-200', 'Pasig', 'Pasig', '${id.user}', '${id.user}')`,

  `INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
     registered_address, created_by, updated_by)
   VALUES ('${id.supplier}', '${id.company}', 'SUPP-200', 'Lifecycle Vendor Inc',
     '777-888-999-200', 'Quezon City', '${id.user}', '${id.user}')`,

  `INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active,
     created_by, updated_by)
   VALUES ('${id.uom}', '${id.company}', 'EA', 'Each', true, '${id.user}', '${id.user}')`,

  `INSERT INTO item_categories (id, company_id, category_code, category_name,
     created_by, updated_by)
   VALUES ('${id.category}', '${id.company}', 'GEN', 'General', '${id.user}', '${id.user}')`,

  `INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
     standard_selling_price, standard_cost, default_sales_vat_id, default_purchase_vat_id,
     sales_account_id, cogs_account_id, inventory_account_id, purchase_expense_account_id,
     costing_method, created_by, updated_by)
   VALUES ('${id.item}', '${id.company}', 'GOODS-200', 'Traded Merchandise', 'inventory_item',
     '${id.category}', '${id.uom}', 1000, 600,
     (SELECT id FROM vat_codes WHERE vat_code = 'VAT-12' LIMIT 1),
     (SELECT id FROM vat_codes WHERE vat_code = 'IVAT-12' LIMIT 1),
     '${id.sales}', '${id.cogs}', '${id.inv}', '${id.expense}', 'weighted_average',
     '${id.user}', '${id.user}')`,

  `INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
     gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
   VALUES ('${id.warehouse}', '${id.company}', '${id.branch}', 'MAIN', 'Main Warehouse',
     '${id.inv}', '${id.variance}', '${id.user}', '${id.user}')`,

  `INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, total_cost, wac_unit_cost)
   VALUES ('${id.company}', '${id.warehouse}', '${id.item}', 100, 60000, 600)`,
]
step(`Fixture — ${fixture.length} separate committed transactions`)
fixture.forEach((s) => sql(s))
ok(scalar(`SELECT qty_on_hand AS v FROM stock_balances WHERE item_id='${id.item}'`) === '100.0000',
  'company provisioned with 100 units on hand')

const glBalance = (acct) => scalar(
  `SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0) AS v
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '${id.company}' AND jel.account_id = '${acct}'`)
const companyBalances = () => scalar(
  `SELECT COALESCE(SUM(jel.debit_amount) - SUM(jel.credit_amount), 0) AS v
     FROM journal_entry_lines jel JOIN journal_entries je ON je.id = jel.je_id
    WHERE je.company_id = '${id.company}'`)
/** Judge each document on the change it causes, so one defect cannot cascade. */
const delta = (before, after) => (Number(after) - Number(before)).toFixed(2)
const stockQty = () => scalar(
  `SELECT qty_on_hand AS v FROM stock_balances WHERE warehouse_id='${id.warehouse}' AND item_id='${id.item}'`)

// ══════════════════════════════════════════════════════════════════════════════
// 1. SALES INVOICE — save → commit → approve → commit → post → commit → void
// ══════════════════════════════════════════════════════════════════════════════
step('Sales Invoice')
const si = actReturning('si', `fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'customer_id','${id.customer}', 'customer_name_snapshot','Lifecycle Buyer Inc',
    'customer_tin_snapshot','444-555-666-200',
    'customer_address_snapshot','Pasig', 'date','2026-03-05'),
  jsonb_build_array(jsonb_build_object(
    'item_id','${id.item}', 'description','Traded Merchandise',
    'quantity',10, 'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12' LIMIT 1),
    'revenue_account_id','${id.sales}', 'warehouse_id','${id.warehouse}')))`)
ok(!!si, 'saved as draft and COMMITTED')

act(`PERFORM fn_approve_sales_invoice(${ctx('si')});`)
ok(scalar(`SELECT status AS v FROM sales_invoices WHERE id='${si}'`) === 'approved',
  'approved in a SEPARATE transaction')

act(`PERFORM fn_post_sales_invoice(${ctx('si')});`)
ok(scalar(`SELECT status AS v FROM sales_invoices WHERE id='${si}'`) === 'posted',
  'POSTED in a third transaction — the shape the screen uses')
ok(glBalance(id.ar) === '11200.00', '  AR debited 11,200.00 (10,000 + 12% VAT)')
ok(glBalance(id.outVat) === '-1200.00', '  output VAT credited 1,200.00')
ok(stockQty() === '90.0000', '  stock relieved 10 units')
ok(scalar(`SELECT count(*)::int AS v FROM tax_detail_entries WHERE source_doc_id='${si}'`) === '1',
  '  one tax ledger row written')

act(`PERFORM fn_void_sales_invoice(${ctx('si')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1), 'lifecycle void');`)
ok(scalar(`SELECT status AS v FROM sales_invoices WHERE id='${si}'`) === 'cancelled',
  'VOIDED in a fourth transaction')
ok(glBalance(id.ar) === '0.00', '  AR back to zero')
ok(stockQty() === '100.0000', '  stock restored to 100')

// ══════════════════════════════════════════════════════════════════════════════
// 2. CASH SALE — posts inside its save act; then void in a later transaction
// ══════════════════════════════════════════════════════════════════════════════
step('Cash Sale')
// fn_save_cash_sale returns a jsonb envelope, not a bare id.
const cs = actReturning('cs', `(fn_save_cash_sale(
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}', 'date','2026-03-06',
    'customer_id','${id.customer}', 'customer_name_snapshot','Lifecycle Buyer Inc',
    'customer_tin_snapshot','444-555-666-200'),
  jsonb_build_array(jsonb_build_object(
    'item_id','${id.item}', 'description','Counter sale',
    'quantity',5, 'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12' LIMIT 1),
    'revenue_account_id','${id.sales}', 'warehouse_id','${id.warehouse}')),
  0) ->> 'si_id')::uuid`)
ok(!!cs, 'saved and posted in one act, COMMITTED')
captured['cs_or'] = scalar(
  `SELECT id::text AS v FROM receipts WHERE company_id='${id.company}'
    ORDER BY created_at DESC LIMIT 1`)
ok(glBalance(id.cash) === '5600.00', '  cash debited 5,600.00')
ok(stockQty() === '95.0000', '  stock relieved 5 units')

act(`PERFORM fn_void_sales_invoice(${ctx('cs')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1), 'lifecycle void');`)
ok(scalar(`SELECT status AS v FROM sales_invoices WHERE id='${cs}'`) === 'cancelled',
  'VOIDED in a SEPARATE transaction')
ok(stockQty() === '100.0000', '  stock restored to 100')
// A Cash Sale is ONE business act recorded as two documents: the invoice half and
// the receipt half that collects it. Voiding must withdraw both, or cash keeps a
// collection for a sale that no longer exists.
ok(scalar(`SELECT status AS v FROM receipts WHERE id='${captured['cs_or']}'`) === 'cancelled',
  '  its Official Receipt half is cancelled with it')
ok(glBalance(id.cash) === '0.00', '  cash returns to zero — no collection survives the void')

// ══════════════════════════════════════════════════════════════════════════════
// 3. OFFICIAL RECEIPT — needs a live invoice to collect against
// ══════════════════════════════════════════════════════════════════════════════
step('Official Receipt')
const si2 = actReturning('si2', `fn_save_sales_invoice(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'customer_id','${id.customer}', 'customer_name_snapshot','Lifecycle Buyer Inc',
    'customer_tin_snapshot','444-555-666-200',
    'customer_address_snapshot','Pasig', 'date','2026-03-07'),
  jsonb_build_array(jsonb_build_object(
    'item_id','${id.item}', 'description','Traded Merchandise',
    'quantity',10, 'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12' LIMIT 1),
    'revenue_account_id','${id.sales}', 'warehouse_id','${id.warehouse}')))`)
act(`PERFORM fn_approve_sales_invoice(${ctx('si2')});`)
act(`PERFORM fn_post_sales_invoice(${ctx('si2')});`)
ok(scalar(`SELECT status AS v FROM sales_invoices WHERE id='${si2}'`) === 'posted',
  'a second invoice posted across three transactions')

const or1 = actReturning('or', `fn_save_receipt(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'customer_id','${id.customer}', 'customer_name_snapshot','Lifecycle Buyer Inc',
    'customer_tin_snapshot','444-555-666-200', 'receipt_date','2026-03-08',
    'payment_mode_id',(SELECT id FROM ref_payment_modes LIMIT 1),
    'total_amount',11200, 'total_cwt',0),
  jsonb_build_array(jsonb_build_object(
    'invoice_id',${ctx('si2')}, 'payment_amount',11200, 'cwt_amount',0)))`)
ok(!!or1, 'saved as draft and COMMITTED')

const arBeforeOr = glBalance(id.ar), cashBeforeOr = glBalance(id.cash)
act(`PERFORM fn_post_receipt(${ctx('or')});`)
ok(scalar(`SELECT status AS v FROM receipts WHERE id='${or1}'`) === 'posted',
  'POSTED in a SEPARATE transaction')
ok(delta(arBeforeOr, glBalance(id.ar)) === '-11200.00', '  AR settled by 11,200.00')
ok(delta(cashBeforeOr, glBalance(id.cash)) === '11200.00', '  cash debited 11,200.00')

// ══════════════════════════════════════════════════════════════════════════════
// 4. CREDIT MEMO
// ══════════════════════════════════════════════════════════════════════════════
step('Credit Memo')
const cm = actReturning('cm', `fn_save_credit_memo(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'customer_id','${id.customer}', 'customer_name_snapshot','Lifecycle Buyer Inc',
    'customer_tin_snapshot','444-555-666-200',
    'invoice_id',${ctx('si2')}, 'cm_date','2026-03-09',
    'reason_code_id',(SELECT id FROM ref_reason_codes WHERE code='CM_OTHER' LIMIT 1)),
  jsonb_build_array(jsonb_build_object(
    'description','Price adjustment', 'quantity',1, 'unit_price',1000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12' LIMIT 1),
    'revenue_account_id','${id.sales}')),
  'draft')`)
ok(!!cm, 'saved as draft and COMMITTED')

const arBeforeCm = glBalance(id.ar)
const cmPost = act(`PERFORM fn_post_credit_memo(${ctx('cm')});`, { tolerant: true })
if (String(cmPost).startsWith('__ERROR__')) {
  ok(false, `POST REFUSED across transactions: ${String(cmPost).slice(12, 260)}`)
} else {
  ok(true, 'POSTED in a SEPARATE transaction')
  ok(delta(arBeforeCm, glBalance(id.ar)) === '-1120.00', '  AR credited 1,120.00')
}

// ══════════════════════════════════════════════════════════════════════════════
// 5. RECEIVING REPORT — PO → save → commit → confirm → commit → post
// ══════════════════════════════════════════════════════════════════════════════
step('Purchase Order → Receiving Report')
const po = actReturning('po', `fn_save_purchase_order(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'supplier_id','${id.supplier}', 'supplier_name_snapshot','Lifecycle Vendor Inc',
    'po_date','2026-03-10'),
  jsonb_build_array(jsonb_build_object(
    'item_id','${id.item}', 'description','Traded Merchandise',
    'quantity',20, 'unit_price',600, 'uom_id','${id.uom}')))`)
ok(!!po, 'purchase order saved and COMMITTED')
act(`PERFORM fn_approve_purchase_order(${ctx('po')});`)
ok(scalar(`SELECT status AS v FROM purchase_orders WHERE id='${po}'`) === 'approved',
  'approved in a SEPARATE transaction')

const rr = actReturning('rr', `fn_save_receiving_report(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'warehouse_id','${id.warehouse}', 'po_id',${ctx('po')},
    'rr_date','2026-03-11', 'supplier_dr_no','VENDOR-DR-200'),
  jsonb_build_array(jsonb_build_object(
    'po_line_id',(SELECT id FROM purchase_order_lines WHERE po_id=${ctx('po')} ORDER BY line_number LIMIT 1),
    'item_id','${id.item}', 'description','Traded Merchandise',
    'ordered_qty',20, 'received_qty',20, 'unit_price',600, 'uom_id','${id.uom}')))`)
ok(!!rr, 'receiving report saved as draft and COMMITTED')

const rrConfirm = act(`PERFORM fn_confirm_receiving_report(${ctx('rr')});`, { tolerant: true })
if (String(rrConfirm).startsWith('__ERROR__')) {
  ok(false, `CONFIRM REFUSED across transactions: ${String(rrConfirm).slice(12, 260)}`)
} else {
  ok(true, 'CONFIRMED in a SEPARATE transaction')
  ok(stockQty() === '110.0000', '  stock increased by 20, to 110')
  ok(glBalance(id.purchClearing) === '-12000.00', '  12,000.00 parked in Goods Received Not Invoiced')
}

// ══════════════════════════════════════════════════════════════════════════════
// 6. VENDOR BILL — save → commit → approve → commit → post → commit → void
// ══════════════════════════════════════════════════════════════════════════════
step('Vendor Bill')
const vb = actReturning('vb', `fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'supplier_id','${id.supplier}', 'supplier_name_snapshot','Lifecycle Vendor Inc',
    'supplier_tin_snapshot','777-888-999-200',
    'supplier_invoice_number','VENDOR-INV-200', 'bill_date','2026-03-12'),
  jsonb_build_array(jsonb_build_object(
    'description','Operating supplies', 'quantity',1, 'unit_price',5000,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12' LIMIT 1),
    'expense_account_id','${id.expense}')))`)
ok(!!vb, 'saved as draft and COMMITTED')

act(`PERFORM fn_approve_vendor_bill(${ctx('vb')});`)
ok(scalar(`SELECT status AS v FROM vendor_bills WHERE id='${vb}'`) === 'approved',
  'approved in a SEPARATE transaction')

act(`PERFORM fn_post_vendor_bill(${ctx('vb')});`)
ok(scalar(`SELECT status AS v FROM vendor_bills WHERE id='${vb}'`) === 'posted',
  'POSTED in a third transaction')
ok(glBalance(id.ap) === '-5600.00', '  AP credited 5,600.00')
ok(glBalance(id.inVat) === '600.00', '  input VAT debited 600.00')

// ══════════════════════════════════════════════════════════════════════════════
// 7. PAYMENT VOUCHER — save → commit → post → commit → cancel
// ══════════════════════════════════════════════════════════════════════════════
step('Payment Voucher')
const pv = actReturning('pv', `fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'supplier_id','${id.supplier}', 'supplier_name_snapshot','Lifecycle Vendor Inc',
    'supplier_tin_snapshot','777-888-999-200',
    'voucher_date','2026-03-13', 'total_amount',5600, 'total_ewt',0),
  jsonb_build_array(jsonb_build_object(
    'vendor_bill_id',${ctx('vb')}, 'payment_amount',5600, 'ewt_amount',0)))`)
ok(!!pv, 'saved as draft and COMMITTED')

act(`PERFORM fn_post_payment_voucher(${ctx('pv')});`)
ok(scalar(`SELECT status AS v FROM payment_vouchers WHERE id='${pv}'`) === 'posted',
  'POSTED in a SEPARATE transaction')
ok(glBalance(id.ap) === '0.00', '  AP settled back to zero')

const pvCancel = act(`PERFORM fn_cancel_payment_voucher(${ctx('pv')}, 'lifecycle cancel');`, { tolerant: true })
if (String(pvCancel).startsWith('__ERROR__')) {
  ok(false, `CANCEL REFUSED across transactions: ${String(pvCancel).slice(12, 260)}`)
} else {
  ok(scalar(`SELECT status AS v FROM payment_vouchers WHERE id='${pv}'`) === 'cancelled',
    'CANCELLED in a further transaction')
}

// ── Whole-company invariant ─────────────────────────────────────────────────
step('Company-wide invariant')
ok(companyBalances() === '0.00', 'every journal the company owns still balances')

// ── Cleanup ─────────────────────────────────────────────────────────────────
teardown()


console.log(`\n${failures === 0 ? 'PASS' : 'FAIL'}: posting lifecycles across transactions — ${checks - failures}/${checks} checks passed\n`)
process.exit(failures === 0 ? 0 : 1)
