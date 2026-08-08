#!/usr/bin/env node
/**
 * Inventory costing lifecycle across committed transactions.
 *
 * This is deliberately not pgTAP. Fixture receipts, delivery, posting, void,
 * and the concurrent Goods Issues each use separate database connections and
 * committed transactions. It proves the production writers for WAC, FIFO, and
 * Specific Identification, their accounting, their correction behavior, and
 * serial admission under a real lock race.
 */
import { execFile, execFileSync } from 'node:child_process'

const RUN = Date.now().toString(16).slice(-6).padStart(6, '0')
const P = `${RUN}00-0000-0000-0000-0000000000`
const RUNNUM = String(Date.now()).slice(-5)
const id = {
  user: `${P}01`, company: `${P}c1`, branch: `${P}d1`, fy: `${P}f1`,
  inventory: `${P}a1`, clearing: `${P}a2`, cogs: `${P}a3`, variance: `${P}a4`,
  ar: `${P}a5`, vat: `${P}a6`, cash: `${P}a7`, sales: `${P}a8`,
  customer: `${P}e1`, uom: `${P}b1`, category: `${P}ca`, warehouse: `${P}ba`,
  wac: `${P}c2`, fifo: `${P}c3`, serial: `${P}c4`,
  dr: `${P}d2`, wacLine: `${P}e2`, fifoLine: `${P}e3`, serialLine: `${P}e4`,
  giA: `${P}f2`, giALine: `${P}f3`, giB: `${P}f4`, giBLine: `${P}f5`,
}

let checks = 0
let failures = 0
const check = (condition, message) => {
  checks += 1
  if (!condition) failures += 1
  console.log(`${condition ? '  ok  ' : '  FAIL'}  ${message}`)
}
const step = message => console.log(`\n▸ ${message}`)

function sql(statement, { tolerant = false } = {}) {
  try {
    return execFileSync('npx', ['supabase', 'db', 'query', '--local', statement], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 32 * 1024 * 1024,
    })
  } catch (error) {
    const detail = `${error.stdout || ''}\n${error.stderr || ''}`.trim()
    if (tolerant) return `__ERROR__ ${detail}`
    console.error(`\nSQL FAILED\n${statement.slice(0, 800)}\n\n${detail}\n`)
    process.exit(1)
  }
}

function sqlAsync(statement) {
  return new Promise(resolve => {
    execFile('npx', ['supabase', 'db', 'query', '--local', statement], {
      encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
    }, (error, stdout, stderr) => resolve({ ok: !error, text: `${stdout || ''}\n${stderr || ''}`.trim() }))
  })
}

const scalar = statement => {
  const output = sql(statement)
  const match = output.match(/"v"\s*:\s*("?)([^",\n}]*)\1/)
  return match ? match[2].trim() : null
}
const num = statement => Number(scalar(statement))
const claimBlock = body =>
  `DO $inventory_lifecycle$ BEGIN
     PERFORM set_config('request.jwt.claims', '{"sub":"${id.user}","role":"authenticated"}', true);
     ${body}
   END $inventory_lifecycle$;`
const act = body => sql(claimBlock(body))

console.log('\n══ Inventory costing lifecycle across committed transactions ══')

const fixture = [
  `INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
     created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
   VALUES('00000000-0000-0000-0000-000000000000','${id.user}','authenticated','authenticated',
     'inventory-${RUN}@test.local','',now(),now(),now(),'{"provider":"email","providers":["email"]}','{}')`,
  `INSERT INTO companies(id,entity_type,registered_name,line_of_business,tin,tax_registration,
     accounting_period,address_line_1,address_line_2,city,province,zip_code,email,
     signatory_name,signatory_position,created_by,updated_by)
   VALUES('${id.company}','corporation','Inventory Lifecycle ${RUN}','Wholesale',
     '400-000-230-${RUNNUM}','vat','calendar','I St','','Makati','Metro Manila','1200',
     'inventory-${RUN}@test.local','Owner','President','${id.user}','${id.user}')`,
  `INSERT INTO user_company_memberships(user_id,company_id,role)
   VALUES('${id.user}','${id.company}','admin')`,
  `INSERT INTO branches(id,company_id,branch_code,branch_name,address_line_1,address_line_2,
     city,province,zip_code,created_by,updated_by)
   VALUES('${id.branch}','${id.company}','HO','Head Office','I St','','Makati','Metro Manila',
     '1200','${id.user}','${id.user}')`,
  `INSERT INTO fiscal_years(id,company_id,year_name,start_date,end_date,is_calendar)
   VALUES('${id.fy}','${id.company}','FY2026','2026-01-01','2026-12-31',true)`,
  `INSERT INTO fiscal_periods(company_id,fiscal_year_id,period_number,period_name,start_date,end_date,is_locked)
   SELECT '${id.company}','${id.fy}',m,to_char(make_date(2026,m,1),'Mon YYYY'),
     make_date(2026,m,1),(make_date(2026,m,1)+interval '1 month'-interval '1 day')::date,false
   FROM generate_series(1,12) m`,
  `INSERT INTO chart_of_accounts(id,company_id,account_code,account_name,account_type,
     normal_balance,is_postable,is_active,created_by,updated_by) VALUES
   ('${id.inventory}','${id.company}','1300','Inventory','asset','debit',true,true,'${id.user}','${id.user}'),
   ('${id.clearing}','${id.company}','1310','Goods Delivered Not Invoiced','asset','debit',true,true,'${id.user}','${id.user}'),
   ('${id.cogs}','${id.company}','5010','Cost of Goods Sold','expense','debit',true,true,'${id.user}','${id.user}'),
   ('${id.variance}','${id.company}','5900','Inventory Variance','expense','debit',true,true,'${id.user}','${id.user}'),
   ('${id.ar}','${id.company}','1200','Accounts Receivable','asset','debit',true,true,'${id.user}','${id.user}'),
   ('${id.vat}','${id.company}','2100','Output VAT','liability','credit',true,true,'${id.user}','${id.user}'),
   ('${id.cash}','${id.company}','1010','Cash','asset','debit',true,true,'${id.user}','${id.user}'),
   ('${id.sales}','${id.company}','4010','Sales','revenue','credit',true,true,'${id.user}','${id.user}')`,
  `INSERT INTO company_accounting_config(company_id,ar_account_id,vat_payable_account_id,
     default_cash_account_id,inventory_account_id,sales_delivery_clearing_account_id,created_by,updated_by)
   VALUES('${id.company}','${id.ar}','${id.vat}','${id.cash}','${id.inventory}',
     '${id.clearing}','${id.user}','${id.user}')`,
  `INSERT INTO number_series(company_id,branch_id,document_type_id,prefix,number_length,
     starting_number,next_number,is_active,created_by,updated_by)
   SELECT '${id.company}','${id.branch}',id,document_code||'-${RUN}-',6,1,1,true,
     '${id.user}','${id.user}' FROM ref_document_types
   WHERE document_code IN ('JE','SI','DR','CM','OR','GI')`,
  `INSERT INTO customers(id,company_id,customer_code,registered_name,tin,registered_address,
     delivery_address,created_by,updated_by)
   VALUES('${id.customer}','${id.company}','CUST-${RUN}','Inventory Buyer','444-555-666-${RUNNUM}',
     'Pasig','Pasig','${id.user}','${id.user}')`,
  `INSERT INTO units_of_measure(id,company_id,uom_code,description,is_active,created_by,updated_by)
   VALUES('${id.uom}','${id.company}','EA','Each',true,'${id.user}','${id.user}')`,
  `INSERT INTO item_categories(id,company_id,category_code,category_name,created_by,updated_by)
   VALUES('${id.category}','${id.company}','GEN','General','${id.user}','${id.user}')`,
  `INSERT INTO items(id,company_id,item_code,description,item_type,category_id,uom_id,
     standard_selling_price,standard_cost,sales_account_id,cogs_account_id,inventory_account_id,
     costing_method,specific_id_tracking,created_by,updated_by) VALUES
   ('${id.wac}','${id.company}','WAC-${RUN}','WAC Item','inventory_item','${id.category}','${id.uom}',100,10,'${id.sales}','${id.cogs}','${id.inventory}','weighted_average',NULL,'${id.user}','${id.user}'),
   ('${id.fifo}','${id.company}','FIFO-${RUN}','FIFO Item','inventory_item','${id.category}','${id.uom}',100,10,'${id.sales}','${id.cogs}','${id.inventory}','fifo',NULL,'${id.user}','${id.user}'),
   ('${id.serial}','${id.company}','SER-${RUN}','Serial Item','inventory_item','${id.category}','${id.uom}',1000,100,'${id.sales}','${id.cogs}','${id.inventory}','specific_identification','serial','${id.user}','${id.user}')`,
  `INSERT INTO warehouses(id,company_id,branch_id,warehouse_code,warehouse_name,
     gl_inventory_account_id,gl_variance_account_id,created_by,updated_by)
   VALUES('${id.warehouse}','${id.company}','${id.branch}','MAIN','Main Warehouse',
     '${id.inventory}','${id.variance}','${id.user}','${id.user}')`,
]
fixture.forEach(statement => sql(statement))
check(true, `fixture committed over ${fixture.length} independent transactions`)

step('Receive distinct costs and identities in separate committed transactions')
const receipts = [
  [id.wac, 100, 10, '2026-01-01', null], [id.wac, 100, 14, '2026-01-02', null],
  [id.fifo, 100, 10, '2026-01-01', null], [id.fifo, 100, 14, '2026-01-02', null],
  [id.serial, 1, 100, '2026-01-01', 'SER-A'], [id.serial, 1, 120, '2026-01-02', 'SER-B'],
]
for (const [item, qty, cost, date, serial] of receipts) {
  act(`PERFORM fn_receive_inventory(jsonb_build_object(
    'company_id','${id.company}','warehouse_id','${id.warehouse}','item_id','${item}',
    'qty',${qty},'unit_cost',${cost},'receipt_date','${date}',
    'reference_doc_type','LIFECYCLE','reference_doc_id','${item}'${serial ? `,'serial_number','${serial}'` : ''}));`)
}
check(num(`SELECT qty_on_hand AS v FROM stock_balances WHERE item_id='${id.wac}'`) === 200,
  'WAC receipts commit 200 units')
check(num(`SELECT wac_unit_cost AS v FROM stock_balances WHERE item_id='${id.wac}'`) === 12,
  'WAC authority derives the 12.00 pool rate')
check(num(`SELECT total_cost AS v FROM stock_balances WHERE item_id='${id.fifo}'`) === 2400,
  'FIFO receipts commit two layers valued at 2,400')
check(num(`SELECT count(*) AS v FROM vw_available_inventory_identities WHERE item_id='${id.serial}'`) === 2,
  'both Specific-ID serials are independently available')

const serialLayer = scalar(`SELECT inventory_cost_layer_id AS v FROM vw_available_inventory_identities
  WHERE item_id='${id.serial}' AND serial_number='SER-B'`)

step('Post one real Delivery Receipt containing WAC, FIFO, and Specific-ID')
sql(`INSERT INTO delivery_receipts(id,company_id,branch_id,customer_id,customer_name_snapshot,
  dr_number,dr_date,delivery_address,status,created_by,updated_by)
  VALUES('${id.dr}','${id.company}','${id.branch}','${id.customer}','Inventory Buyer',
  'DR-${RUN}-000001','2026-01-03','Pasig','draft','${id.user}','${id.user}')`)
sql(`INSERT INTO delivery_receipt_lines(id,dr_id,company_id,line_number,item_id,description,
  quantity,uom_id,warehouse_id,inventory_cost_layer_id,serial_number,created_by,updated_by) VALUES
  ('${id.wacLine}','${id.dr}','${id.company}',1,'${id.wac}','WAC Item',50,'${id.uom}','${id.warehouse}',NULL,NULL,'${id.user}','${id.user}'),
  ('${id.fifoLine}','${id.dr}','${id.company}',2,'${id.fifo}','FIFO Item',120,'${id.uom}','${id.warehouse}',NULL,NULL,'${id.user}','${id.user}'),
  ('${id.serialLine}','${id.dr}','${id.company}',3,'${id.serial}','Serial Item',1,'${id.uom}','${id.warehouse}','${serialLayer}','SER-B','${id.user}','${id.user}')`)
sql(`UPDATE delivery_receipts SET status='delivered',delivered_at=now() WHERE id='${id.dr}'`)
act(`PERFORM fn_post_delivery_receipt('${id.dr}');`)
check(scalar(`SELECT (journal_entry_id IS NOT NULL) AS v FROM delivery_receipts WHERE id='${id.dr}'`) === 'true',
  'Delivery Receipt posts in a later committed transaction')
check(num(`SELECT inventory_cost AS v FROM delivery_receipt_lines WHERE id='${id.wacLine}'`) === 600,
  'WAC outbound uses 50 x 12 = 600')
check(num(`SELECT inventory_cost AS v FROM delivery_receipt_lines WHERE id='${id.fifoLine}'`) === 1280,
  'FIFO outbound consumes 100 x 10 plus 20 x 14 = 1,280')
check(num(`SELECT inventory_cost AS v FROM delivery_receipt_lines WHERE id='${id.serialLine}'`) === 120,
  'Specific-ID outbound uses selected SER-B cost 120')
check(num(`SELECT count(*) AS v FROM inventory_layer_allocations a
  JOIN delivery_receipt_lines l ON l.inventory_transaction_id=a.inventory_transaction_id
  WHERE l.id='${id.fifoLine}' AND a.allocation_kind='consume'`) === 2,
  'FIFO delivery persists both exact layer allocations')
check(num(`SELECT count(*) AS v FROM vw_available_inventory_identities
  WHERE item_id='${id.serial}' AND serial_number='SER-B'`) === 0,
  'the selected serial is no longer available')
check(num(`SELECT COALESCE(SUM(jel.debit_amount-jel.credit_amount),0) AS v
  FROM journal_entry_lines jel JOIN journal_entries je ON je.id=jel.je_id
  WHERE je.company_id='${id.company}' AND jel.account_id='${id.clearing}'`) === 2000,
  'delivery clearing debit equals the authoritative 2,000 outbound cost')
check(num(`SELECT COALESCE(SUM(jel.debit_amount-jel.credit_amount),0) AS v
  FROM journal_entry_lines jel JOIN journal_entries je ON je.id=jel.je_id
  WHERE je.company_id='${id.company}' AND jel.account_id='${id.inventory}'`) === -2000,
  'Inventory Control GL credits the same 2,000')
check(num(`SELECT COALESCE(SUM(jel.debit_amount)-SUM(jel.credit_amount),0) AS v
  FROM journal_entry_lines jel JOIN journal_entries je ON je.id=jel.je_id
  WHERE je.company_id='${id.company}'`) === 0,
  'Trial Balance remains balanced after multi-method delivery')

step('Void in a later committed transaction and restore exact cost evidence')
act(`PERFORM fn_void_delivery_receipt('${id.dr}',
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR' LIMIT 1),'costing lifecycle correction');`)
check(scalar(`SELECT status AS v FROM delivery_receipts WHERE id='${id.dr}'`) === 'cancelled',
  'Delivery Receipt correction commits')
check(num(`SELECT total_cost AS v FROM stock_balances WHERE item_id='${id.wac}'`) === 2400,
  'WAC value returns exactly to 2,400')
check(num(`SELECT sum(qty_remaining) AS v FROM inventory_cost_layers
  WHERE item_id='${id.fifo}' AND voided_by_inventory_transaction_id IS NULL`) === 200,
  'FIFO original layers return exactly to 200 units')
check(num(`SELECT count(*) AS v FROM vw_available_inventory_identities
  WHERE item_id='${id.serial}' AND serial_number='SER-B'`) === 1,
  'the same SER-B identity is available again')
check(num(`SELECT count(*) AS v FROM vw_inventory_valuation_reconciliation
  WHERE company_id='${id.company}' AND (abs(quantity_variance)>0.0001 OR abs(value_variance)>0.01)`) === 0,
  'inventory projection and layer valuation reconcile after correction')
check(num(`SELECT COALESCE(SUM(jel.debit_amount-jel.credit_amount),0) AS v
  FROM journal_entry_lines jel JOIN journal_entries je ON je.id=jel.je_id
  WHERE je.company_id='${id.company}' AND jel.account_id IN ('${id.inventory}','${id.clearing}')`) === 0,
  'Inventory and delivery-clearing GL balances return to zero')
check(num(`SELECT COALESCE(SUM(jel.debit_amount)-SUM(jel.credit_amount),0) AS v
  FROM journal_entry_lines jel JOIN journal_entries je ON je.id=jel.je_id
  WHERE je.company_id='${id.company}'`) === 0,
  'Trial Balance remains balanced after correction')

step('Race two real Goods Issues for the one available serial')
sql(`INSERT INTO goods_issues(id,company_id,branch_id,warehouse_id,issue_number,issue_date,
  purpose,status,created_by,updated_by) VALUES
  ('${id.giA}','${id.company}','${id.branch}','${id.warehouse}','GI-${RUN}-A','2026-01-05','Race A','draft','${id.user}','${id.user}'),
  ('${id.giB}','${id.company}','${id.branch}','${id.warehouse}','GI-${RUN}-B','2026-01-05','Race B','draft','${id.user}','${id.user}')`)
sql(`INSERT INTO goods_issue_lines(id,issue_id,company_id,item_id,qty_issued,
  gl_expense_account_id,inventory_cost_layer_id,serial_number) VALUES
  ('${id.giALine}','${id.giA}','${id.company}','${id.serial}',1,'${id.cogs}','${serialLayer}','SER-B'),
  ('${id.giBLine}','${id.giB}','${id.company}','${id.serial}',1,'${id.cogs}','${serialLayer}','SER-B')`)
const race = await Promise.all([
  sqlAsync(claimBlock(`PERFORM fn_post_goods_issue('${id.giA}');`)),
  sqlAsync(claimBlock(`PERFORM fn_post_goods_issue('${id.giB}');`)),
])
check(race.filter(result => result.ok).length === 1,
  'exactly one concurrent Goods Issue acquires the serial')
check(race.filter(result => !result.ok).length === 1,
  'the competing committed transaction is refused by database authority')
check(num(`SELECT count(*) AS v FROM goods_issues WHERE id IN ('${id.giA}','${id.giB}') AND status='posted'`) === 1,
  'only one source document reaches posted state')
check(num(`SELECT count(*) AS v FROM inventory_layer_allocations a
  JOIN inventory_transactions it ON it.id=a.inventory_transaction_id
  WHERE a.layer_id='${serialLayer}' AND a.allocation_kind='consume'
    AND it.reversed_by_inventory_transaction_id IS NULL`) === 1,
  'only one live allocation consumes SER-B')
check(num(`SELECT qty_on_hand AS v FROM stock_balances WHERE item_id='${id.serial}'`) === 1,
  'serial stock cannot be over-consumed; SER-A remains')
check(num(`SELECT COALESCE(SUM(jel.debit_amount)-SUM(jel.credit_amount),0) AS v
  FROM journal_entry_lines jel JOIN journal_entries je ON je.id=jel.je_id
  WHERE je.company_id='${id.company}'`) === 0,
  'Trial Balance remains balanced after the winning Goods Issue')

step('Remove the isolated fixture')
// Posted-document immutability and Posting Engine totality triggers must remain
// strict in normal use. Cleanup therefore runs as local postgres in one bounded
// transaction, disables those triggers only for this generated fixture, then
// explicitly restores the ALWAYS guards before commit.
const cleanupSql = `BEGIN;
  SET LOCAL session_replication_role=replica;
  ALTER TABLE journal_entry_lines DISABLE TRIGGER zz_trg_journal_entry_lines_kernel_origin;
  ALTER TABLE journal_entries DISABLE TRIGGER zz_trg_journal_entries_kernel_origin;
  DELETE FROM transaction_events WHERE company_id='${id.company}';
  DELETE FROM inventory_layer_allocations WHERE company_id='${id.company}';
  DELETE FROM goods_issue_lines WHERE company_id='${id.company}';
  DELETE FROM goods_issues WHERE company_id='${id.company}';
  DELETE FROM cas_document_void_events WHERE company_id='${id.company}';
  DELETE FROM cas_document_number_issuances WHERE company_id='${id.company}';
  DELETE FROM delivery_receipt_lines WHERE company_id='${id.company}';
  DELETE FROM delivery_receipts WHERE company_id='${id.company}';
  DELETE FROM inventory_cost_layers WHERE company_id='${id.company}';
  DELETE FROM inventory_transactions WHERE company_id='${id.company}';
  DELETE FROM journal_entry_lines WHERE company_id='${id.company}';
  DELETE FROM journal_entries WHERE company_id='${id.company}';
  DELETE FROM stock_balances WHERE company_id='${id.company}';
  DELETE FROM warehouses WHERE company_id='${id.company}';
  DELETE FROM items WHERE company_id='${id.company}';
  DELETE FROM item_categories WHERE company_id='${id.company}';
  DELETE FROM units_of_measure WHERE company_id='${id.company}';
  DELETE FROM customers WHERE company_id='${id.company}';
  DELETE FROM number_series WHERE company_id='${id.company}';
  DELETE FROM company_accounting_config WHERE company_id='${id.company}';
  DELETE FROM account_mapping WHERE company_id='${id.company}';
  DELETE FROM chart_of_accounts WHERE company_id='${id.company}';
  DELETE FROM fiscal_periods WHERE company_id='${id.company}';
  DELETE FROM fiscal_years WHERE company_id='${id.company}';
  DELETE FROM user_company_memberships WHERE company_id='${id.company}';
  DELETE FROM branches WHERE company_id='${id.company}';
  DELETE FROM sys_audit_logs WHERE company_id='${id.company}';
  DELETE FROM companies WHERE id='${id.company}';
  DELETE FROM auth.users WHERE id='${id.user}';
  ALTER TABLE journal_entry_lines ENABLE ALWAYS TRIGGER zz_trg_journal_entry_lines_kernel_origin;
  ALTER TABLE journal_entries ENABLE ALWAYS TRIGGER zz_trg_journal_entries_kernel_origin;
COMMIT;`
execFileSync('docker', ['exec','supabase_db_PXL','psql','-U','postgres','-d','postgres',
  '-v','ON_ERROR_STOP=1','-c',cleanupSql], { encoding: 'utf8', stdio: ['ignore','pipe','pipe'] })
check(num(`SELECT count(*) AS v FROM companies WHERE id='${id.company}'`) === 0,
  'fixture is fully removed')

console.log(`\n${failures === 0 ? 'PASS' : 'FAIL'}: inventory costing lifecycle (${checks} checks, ${failures} failure(s))\n`)
process.exit(failures === 0 ? 0 : 1)
