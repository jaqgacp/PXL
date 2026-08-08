#!/usr/bin/env node
/**
 * Procure-to-Pay lifecycle across separate committed transactions.
 *
 * Every production action is one `supabase db query` invocation: save, commit,
 * approve/confirm/post, commit, then correct, commit. This exposes status guards,
 * relationship state, and reversal ordering that a single-transaction pgTAP
 * file cannot. It provisions fresh data and never reads the canonical demo.
 */
import { execFileSync } from 'node:child_process'

const RUN = Date.now().toString(16).slice(-6).padStart(6, '0')
const P = `${RUN}00-0000-0000-0000-0000000000`
const RUNNUM = String(Date.now()).slice(-5)
const id = {
  user: `${P}01`, company: `${P}c1`, branch: `${P}d1`, fy: `${P}f1`,
  cash: `${P}a1`, ap: `${P}a3`, inventory: `${P}a4`, inputVat: `${P}a6`,
  clearing: `${P}b1`, expense: `${P}b4`, variance: `${P}a9`,
  supplier: `${P}e2`, uom: `${P}ab`, category: `${P}ca`, item: `${P}bb`,
  warehouse: `${P}ba`,
}

let checks = 0
let failures = 0
const captured = {}

const check = (condition, message) => {
  checks += 1
  if (!condition) failures += 1
  console.log(`${condition ? '  ok  ' : '  FAIL'}  ${message}`)
}
const step = message => console.log(`\n▸ ${message}`)

function sql(statement, { tolerant = false } = {}) {
  try {
    return execFileSync('npx', ['supabase', 'db', 'query', '--local', statement], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 32 * 1024 * 1024,
    })
  } catch (error) {
    const detail = `${error.stdout || ''}\n${error.stderr || ''}`.trim()
    if (tolerant) return `__ERROR__ ${detail}`
    console.error(`\n╳ SQL FAILED\n${statement.slice(0, 600)}\n\n${detail}\n`)
    process.exit(1)
  }
}

const scalar = statement => {
  const output = sql(statement)
  const match = output.match(/"v"\s*:\s*("?)([^",\n}]*)\1/)
  return match ? match[2].trim() : null
}

const act = (body, options = {}) => sql(
  `DO $p2p$ BEGIN
     PERFORM set_config('request.jwt.claims', '{"sub":"${id.user}","role":"authenticated"}', true);
     ${body}
   END $p2p$;`,
  options,
)

const actReturning = (key, body) => {
  const output = sql(
    `WITH claim AS (
       SELECT set_config('request.jwt.claims', '{"sub":"${id.user}","role":"authenticated"}', true)
     )
     SELECT (${body})::text AS v FROM claim`,
  )
  const match = output.match(/"v"\s*:\s*("?)([^",\n}]*)\1/)
  captured[key] = match ? match[2].trim() : null
  return captured[key]
}

const ctx = key => `'${captured[key]}'::uuid`
const gl = accountId => scalar(
  `SELECT COALESCE(SUM(jel.debit_amount - jel.credit_amount), 0) AS v
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE je.company_id = '${id.company}' AND jel.account_id = '${accountId}'`,
)
const expectRefusal = (body, pattern, message) => {
  const result = act(body, { tolerant: true })
  const refused = String(result).startsWith('__ERROR__') && pattern.test(String(result))
  check(refused, message)
  if (!refused) console.log(`        ${String(result).slice(0, 300)}`)
}

console.log('\n══ Procure-to-Pay lifecycle across committed transactions ══')

// Fixture creation is intentionally split: every statement commits independently.
const fixture = [
  `INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
     email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
   VALUES ('00000000-0000-0000-0000-000000000000', '${id.user}', 'authenticated',
     'authenticated', 'p2p-${RUN}@test.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{}')`,

  `INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
     tax_registration, accounting_period, address_line_1, address_line_2, city, province,
     zip_code, email, signatory_name, signatory_position, created_by, updated_by)
   VALUES ('${id.company}', 'corporation', 'P2P Proof ${RUN}', 'Wholesale',
     '400-000-210-${RUNNUM}', 'vat', 'calendar', 'P St', 'P Bldg', 'Makati',
     'Metro Manila', '1200', 'p2p-${RUN}@test.local', 'P Owner', 'President',
     '${id.user}', '${id.user}')`,

  `INSERT INTO user_company_memberships (user_id, company_id, role)
   VALUES ('${id.user}', '${id.company}', 'admin')`,

  `INSERT INTO branches (id, company_id, branch_code, branch_name, address_line_1,
     address_line_2, city, province, zip_code, created_by, updated_by)
   VALUES ('${id.branch}', '${id.company}', 'HO', 'Head Office', 'P St', '',
     'Makati', 'Metro Manila', '1200', '${id.user}', '${id.user}')`,

  `INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
   VALUES ('${id.fy}', '${id.company}', 'FY2026', '2026-01-01', '2026-12-31', true)`,

  `INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name,
     start_date, end_date, is_locked)
   SELECT '${id.company}', '${id.fy}', m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
     make_date(2026, m, 1),
     (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
   FROM generate_series(1, 12) AS m`,

  `INSERT INTO chart_of_accounts (id, company_id, account_code, account_name,
     account_type, normal_balance, is_postable, is_active, created_by, updated_by)
   VALUES
     ('${id.cash}',      '${id.company}', '1010', 'Cash on Hand',                 'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.inventory}', '${id.company}', '1300', 'Merchandise Inventory',        'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.inputVat}',  '${id.company}', '1400', 'Input VAT',                    'asset',     'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.ap}',        '${id.company}', '2000', 'Accounts Payable',             'liability', 'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.clearing}',  '${id.company}', '2015', 'Goods Received Not Invoiced',  'liability', 'credit', true, true, '${id.user}', '${id.user}'),
     ('${id.expense}',   '${id.company}', '5010', 'Purchases',                    'expense',   'debit',  true, true, '${id.user}', '${id.user}'),
     ('${id.variance}',  '${id.company}', '5900', 'Inventory Variance',           'expense',   'debit',  true, true, '${id.user}', '${id.user}')`,

  `INSERT INTO company_accounting_config (company_id, ap_account_id,
     input_vat_account_id, default_cash_account_id, inventory_account_id,
     purchase_clearing_account_id, created_by, updated_by)
   VALUES ('${id.company}', '${id.ap}', '${id.inputVat}', '${id.cash}',
     '${id.inventory}', '${id.clearing}', '${id.user}', '${id.user}')`,

  `INSERT INTO number_series (company_id, branch_id, document_type_id, prefix,
     number_length, starting_number, next_number, is_active, created_by, updated_by)
   SELECT '${id.company}', '${id.branch}', rdt.id, rdt.document_code || '-${RUN}-',
     6, 1, 1, true, '${id.user}', '${id.user}'
   FROM ref_document_types rdt WHERE rdt.document_code IN ('PO','RR','VB','PV')`,

  `INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin,
     registered_address, created_by, updated_by)
   VALUES ('${id.supplier}', '${id.company}', 'SUPP-${RUN}', 'P2P Vendor Inc',
     '777-888-999-${RUNNUM}', 'Quezon City', '${id.user}', '${id.user}')`,

  `INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active,
     created_by, updated_by)
   VALUES ('${id.uom}', '${id.company}', 'EA', 'Each', true, '${id.user}', '${id.user}')`,

  `INSERT INTO item_categories (id, company_id, category_code, category_name,
     created_by, updated_by)
   VALUES ('${id.category}', '${id.company}', 'GEN', 'General', '${id.user}', '${id.user}')`,

  `INSERT INTO items (id, company_id, item_code, description, item_type, category_id,
     uom_id, standard_selling_price, standard_cost, default_purchase_vat_id,
     purchase_expense_account_id, cogs_account_id, inventory_account_id,
     costing_method, created_by, updated_by)
   VALUES ('${id.item}', '${id.company}', 'GOODS-${RUN}', 'Purchased Merchandise',
     'inventory_item', '${id.category}', '${id.uom}', 1000, 600,
     (SELECT id FROM vat_codes WHERE vat_code='IVAT-12' LIMIT 1),
     '${id.expense}', '${id.expense}', '${id.inventory}', 'weighted_average',
     '${id.user}', '${id.user}')`,

  `INSERT INTO warehouses (id, company_id, branch_id, warehouse_code, warehouse_name,
     gl_inventory_account_id, gl_variance_account_id, created_by, updated_by)
   VALUES ('${id.warehouse}', '${id.company}', '${id.branch}', 'MAIN', 'Main Warehouse',
     '${id.inventory}', '${id.variance}', '${id.user}', '${id.user}')`,
]
fixture.forEach(statement => sql(statement))
check(true, `fresh fixture committed over ${fixture.length} separate transactions`)

step('Purchase Order: save → approve')
actReturning('po', `fn_save_purchase_order(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'supplier_id','${id.supplier}', 'supplier_name_snapshot','P2P Vendor Inc',
    'po_date','2026-03-01'),
  jsonb_build_array(jsonb_build_object(
    'item_id','${id.item}', 'description','Purchased Merchandise',
    'quantity',100, 'unit_price',600, 'uom_id','${id.uom}')))`)
check(Boolean(captured.po), 'Purchase Order saved and COMMITTED')
act(`PERFORM fn_approve_purchase_order(${ctx('po')});`)
check(scalar(`SELECT status AS v FROM purchase_orders WHERE id=${ctx('po')}`) === 'approved',
  'Purchase Order approved in a later transaction')

const poLine = scalar(`SELECT id AS v FROM purchase_order_lines WHERE po_id=${ctx('po')} ORDER BY line_number LIMIT 1`)

step('Partial receipt, over-receipt refusal, then second valid receipt')
actReturning('rr1', `fn_save_receiving_report(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'warehouse_id','${id.warehouse}', 'po_id',${ctx('po')},
    'rr_date','2026-03-02', 'supplier_dr_no','DR-${RUN}-1'),
  jsonb_build_array(jsonb_build_object(
    'po_line_id','${poLine}', 'item_id','${id.item}',
    'description','Purchased Merchandise', 'ordered_qty',100,
    'received_qty',60, 'unit_price',600, 'uom_id','${id.uom}')))`)
check(Boolean(captured.rr1), 'first Receiving Report saved for 60 and COMMITTED')
act(`PERFORM fn_confirm_receiving_report(${ctx('rr1')});`)
check(scalar(`SELECT remaining_qty AS v FROM vw_po_line_receipt_progress WHERE po_line_id='${poLine}'`) === '40.0000',
  'first receipt confirmed later; 40 remains')
check(scalar(`SELECT qty_on_hand AS v FROM stock_balances WHERE warehouse_id='${id.warehouse}' AND item_id='${id.item}'`) === '60.0000',
  'stock is 60 after partial receipt')

actReturning('rrOver', `fn_save_receiving_report(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'warehouse_id','${id.warehouse}', 'po_id',${ctx('po')},
    'rr_date','2026-03-03', 'supplier_dr_no','DR-${RUN}-OVER'),
  jsonb_build_array(jsonb_build_object(
    'po_line_id','${poLine}', 'item_id','${id.item}',
    'description','Purchased Merchandise', 'ordered_qty',100,
    'received_qty',50, 'unit_price',600, 'uom_id','${id.uom}')))`)
expectRefusal(`PERFORM fn_confirm_receiving_report(${ctx('rrOver')});`, /Over-receipt/,
  'a second receipt that would take cumulative quantity to 110 is refused')
check(scalar(`SELECT qty_on_hand AS v FROM stock_balances WHERE warehouse_id='${id.warehouse}' AND item_id='${id.item}'`) === '60.0000',
  'the refused receipt moves no stock')
act(`PERFORM fn_void_receiving_report(${ctx('rrOver')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1),
  'over-receipt draft abandoned');`)

actReturning('rr2', `fn_save_receiving_report(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'warehouse_id','${id.warehouse}', 'po_id',${ctx('po')},
    'rr_date','2026-03-04', 'supplier_dr_no','DR-${RUN}-2'),
  jsonb_build_array(jsonb_build_object(
    'po_line_id','${poLine}', 'item_id','${id.item}',
    'description','Purchased Merchandise', 'ordered_qty',100,
    'received_qty',40, 'unit_price',600, 'uom_id','${id.uom}')))`)
act(`PERFORM fn_confirm_receiving_report(${ctx('rr2')});`)
check(scalar(`SELECT remaining_qty AS v FROM vw_po_line_receipt_progress WHERE po_line_id='${poLine}'`) === '0.0000',
  'second valid receipt confirms and closes the ordered quantity')
check(scalar(`SELECT qty_on_hand AS v FROM stock_balances WHERE warehouse_id='${id.warehouse}' AND item_id='${id.item}'`) === '100.0000',
  'stock is 100 after both committed receipts')
check(gl(id.clearing) === '-60000.00', 'Goods Received Not Invoiced holds 60,000.00')

step('Partial bill, over-billing refusal, then second valid bill')
actReturning('vb1', `fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'supplier_id','${id.supplier}', 'supplier_name_snapshot','P2P Vendor Inc',
    'supplier_tin_snapshot','777-888-999-${RUNNUM}',
    'supplier_invoice_number','INV-${RUN}-1', 'rr_id',${ctx('rr1')},
    'bill_date','2026-03-05'),
  jsonb_build_array(jsonb_build_object(
    'item_id','${id.item}', 'description','Purchased Merchandise',
    'quantity',40, 'unit_price',600,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12' LIMIT 1),
    'expense_account_id','${id.clearing}')))`)
act(`PERFORM fn_approve_vendor_bill(${ctx('vb1')});`)
act(`PERFORM fn_post_vendor_bill(${ctx('vb1')});`)
check(scalar(`SELECT status AS v FROM vendor_bills WHERE id=${ctx('vb1')}`) === 'posted',
  'partial bill for 40 saves, approves, and posts across three transactions')
check(scalar(`SELECT remaining_billable_qty AS v FROM vw_rr_item_billing_progress WHERE rr_id=${ctx('rr1')} AND item_id='${id.item}'`) === '20.0000',
  '20 remains billable on the first receipt')

actReturning('vbOver', `fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'supplier_id','${id.supplier}', 'supplier_name_snapshot','P2P Vendor Inc',
    'supplier_tin_snapshot','777-888-999-${RUNNUM}',
    'supplier_invoice_number','INV-${RUN}-OVER', 'rr_id',${ctx('rr1')},
    'bill_date','2026-03-06'),
  jsonb_build_array(jsonb_build_object(
    'item_id','${id.item}', 'description','Purchased Merchandise',
    'quantity',30, 'unit_price',600,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12' LIMIT 1),
    'expense_account_id','${id.clearing}')))`)
expectRefusal(`PERFORM fn_approve_vendor_bill(${ctx('vbOver')});`, /Over-billing/,
  'a second bill that would claim 70 of 60 is refused')
act(`PERFORM fn_void_vendor_bill(${ctx('vbOver')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1),
  'over-bill draft abandoned');`)

actReturning('vb2', `fn_save_vendor_bill(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'supplier_id','${id.supplier}', 'supplier_name_snapshot','P2P Vendor Inc',
    'supplier_tin_snapshot','777-888-999-${RUNNUM}',
    'supplier_invoice_number','INV-${RUN}-2', 'rr_id',${ctx('rr1')},
    'bill_date','2026-03-07'),
  jsonb_build_array(jsonb_build_object(
    'item_id','${id.item}', 'description','Purchased Merchandise',
    'quantity',20, 'unit_price',600,
    'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='IVAT-12' LIMIT 1),
    'expense_account_id','${id.clearing}')))`)
act(`PERFORM fn_approve_vendor_bill(${ctx('vb2')});`)
act(`PERFORM fn_post_vendor_bill(${ctx('vb2')});`)
check(scalar(`SELECT remaining_billable_qty AS v FROM vw_rr_item_billing_progress WHERE rr_id=${ctx('rr1')} AND item_id='${id.item}'`) === '0.0000',
  'second bill posts only the valid remaining 20')
check(gl(id.clearing) === '-24000.00', 'only the unbilled second receipt remains in clearing')
check(gl(id.ap) === '-40320.00', 'AP is 40,320.00 including input VAT')
check(gl(id.inputVat) === '4320.00', 'input VAT is 4,320.00')

step('Payment, ordered correction, and receipt reversal')
actReturning('pv', `fn_save_payment_voucher(NULL,
  jsonb_build_object(
    'company_id','${id.company}', 'branch_id','${id.branch}',
    'supplier_id','${id.supplier}', 'supplier_name_snapshot','P2P Vendor Inc',
    'supplier_tin_snapshot','777-888-999-${RUNNUM}',
    'voucher_date','2026-03-08', 'total_amount',40320, 'total_ewt',0),
  jsonb_build_array(
    jsonb_build_object('vendor_bill_id',${ctx('vb1')}, 'payment_amount',26880, 'ewt_amount',0),
    jsonb_build_object('vendor_bill_id',${ctx('vb2')}, 'payment_amount',13440, 'ewt_amount',0)))`)
act(`PERFORM fn_post_payment_voucher(${ctx('pv')});`)
check(gl(id.ap) === '0.00', 'Payment Voucher settles AP to zero')
check(gl(id.cash) === '-40320.00', 'cash is credited 40,320.00')

expectRefusal(`PERFORM fn_void_receiving_report(${ctx('rr1')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1),
  'receipt correction');`, /billed by Vendor Bill/,
  'RR cancellation is refused while live bills claim it')

act(`PERFORM fn_cancel_payment_voucher(${ctx('pv')}, 'undo payment before bill correction');`)
check(gl(id.ap) === '-40320.00' && gl(id.cash) === '0.00',
  'Payment Voucher cancellation restores AP and cash before bill correction')

act(`PERFORM fn_void_vendor_bill(${ctx('vb2')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1),
  'bill correction before receipt');`)
act(`PERFORM fn_void_vendor_bill(${ctx('vb1')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1),
  'bill correction before receipt');`)
check(gl(id.ap) === '0.00', 'bill reversals return AP to zero')
check(gl(id.inputVat) === '0.00', 'bill reversals return input VAT to zero')
check(gl(id.clearing) === '-60000.00', 'bill reversals restore the two receipt clearing credits')
check(Number(scalar(`SELECT COALESCE(SUM(tax_amount), 0) AS v FROM tax_detail_entries WHERE company_id='${id.company}'`)) === 0,
  'tax-detail originals and reversals net to zero')

act(`PERFORM fn_void_receiving_report(${ctx('rr1')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1),
  'first receipt corrected');`)
check(scalar(`SELECT qty_on_hand AS v FROM stock_balances WHERE warehouse_id='${id.warehouse}' AND item_id='${id.item}'`) === '40.0000',
  'first RR cancellation removes its 60 units')
check(gl(id.clearing) === '-24000.00', 'clearing now represents only the second receipt')
check(scalar(`SELECT status AS v FROM purchase_orders WHERE id=${ctx('po')}`) === 'partially_received',
  'Purchase Order reopens to partially received')

act(`PERFORM fn_void_receiving_report(${ctx('rr2')},
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1),
  'second receipt corrected');`)
check(scalar(`SELECT qty_on_hand AS v FROM stock_balances WHERE warehouse_id='${id.warehouse}' AND item_id='${id.item}'`) === '0.0000',
  'second RR cancellation returns stock quantity to zero')
check(scalar(`SELECT total_cost AS v FROM stock_balances WHERE warehouse_id='${id.warehouse}' AND item_id='${id.item}'`) === '0.00',
  'stock value returns to zero')
check(gl(id.inventory) === '0.00' && gl(id.clearing) === '0.00',
  'inventory control and Goods Received Not Invoiced both return to zero')
check(scalar(`SELECT status AS v FROM purchase_orders WHERE id=${ctx('po')}`) === 'approved',
  'Purchase Order is reachable again for a replacement receipt')
check(scalar(`SELECT remaining_qty AS v FROM vw_po_line_receipt_progress WHERE po_line_id='${poLine}'`) === '100.0000',
  'all 100 ordered units are open again')

step('Whole-company invariants')
check(gl(id.ap) === '0.00' && gl(id.cash) === '0.00' && gl(id.inputVat) === '0.00',
  'AP, cash, and tax positions are fully reversed')
check(scalar(
  `SELECT COALESCE(SUM(jel.debit_amount) - SUM(jel.credit_amount), 0) AS v
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE je.company_id='${id.company}'`,
) === '0.00', 'trial balance remains balanced across every committed step')

console.log(`\n${failures === 0 ? 'PASS' : 'FAIL'}: purchasing lifecycle across transactions — ${checks - failures}/${checks} checks passed`)
console.log('Scratch evidence remains local until the next fresh-schema/reset lane.\n')
process.exit(failures === 0 ? 0 : 1)
