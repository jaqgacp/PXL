#!/usr/bin/env node
/**
 * Sales conversion lifecycle across committed transactions.
 *
 * Proves Quotation -> Sales Order -> Delivery Receipt -> Sales Invoice ->
 * Official Receipt with WAC, FIFO, and Specific Identification in one sale.
 * Every business action is a separate local database connection/transaction.
 * A two-connection race also proves the shared Sales Order quantity budget.
 */
import { execFile, execFileSync } from 'node:child_process'

const RUN = Date.now().toString(16).slice(-6).padStart(6, '0')
const P = `${RUN}10-0000-0000-0000-0000000000`
const RUNNUM = String(Date.now()).slice(-5)
const id = {
  user: `${P}01`, company: `${P}c1`, branch: `${P}d1`, fy: `${P}f1`,
  inventory: `${P}a1`, clearing: `${P}a2`, cogs: `${P}a3`, variance: `${P}a4`,
  ar: `${P}a5`, vat: `${P}a6`, cash: `${P}a7`, sales: `${P}a8`, equity: `${P}a9`,
  customer: `${P}e1`, uom: `${P}b1`, category: `${P}ca`, warehouse: `${P}ba`,
  wac: `${P}c2`, fifo: `${P}c3`, serial: `${P}c4`,
  quote: `${P}d2`, qWac: `${P}e2`, qFifo: `${P}e3`, qSerial: `${P}e4`,
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
    console.error(`\nSQL FAILED\n${statement.slice(0, 1200)}\n\n${detail}\n`)
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
const claimBlock = body => `DO $sales_conversion$ BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"${id.user}","role":"authenticated"}', true);
  ${body}
END $sales_conversion$;`
const act = body => sql(claimBlock(body))

console.log('\n══ Sales document conversion lifecycle across committed transactions ══')

const fixture = [
  `INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
   VALUES('00000000-0000-0000-0000-000000000000','${id.user}','authenticated','authenticated',
    'sales-conversion-${RUN}@test.local','',now(),now(),now(),'{"provider":"email","providers":["email"]}','{}')`,
  `INSERT INTO companies(id,entity_type,registered_name,line_of_business,tin,tax_registration,
    accounting_period,address_line_1,address_line_2,city,province,zip_code,email,
    signatory_name,signatory_position,created_by,updated_by)
   VALUES('${id.company}','corporation','Sales Conversion ${RUN}','Wholesale','400-138-${RUNNUM}-000',
    'vat','calendar','S St','','Makati','Metro Manila','1200','sales-conversion-${RUN}@test.local',
    'Owner','President','${id.user}','${id.user}')`,
  `INSERT INTO user_company_memberships(user_id,company_id,role) VALUES('${id.user}','${id.company}','admin')`,
  `INSERT INTO branches(id,company_id,branch_code,branch_name,address_line_1,address_line_2,
    city,province,zip_code,created_by,updated_by)
   VALUES('${id.branch}','${id.company}','HO','Head Office','S St','','Makati','Metro Manila','1200','${id.user}','${id.user}')`,
  `INSERT INTO fiscal_years(id,company_id,year_name,start_date,end_date,is_calendar)
   VALUES('${id.fy}','${id.company}','FY2026','2026-01-01','2026-12-31',true)`,
  `INSERT INTO fiscal_periods(company_id,fiscal_year_id,period_number,period_name,start_date,end_date,is_locked)
   SELECT '${id.company}','${id.fy}',m,to_char(make_date(2026,m,1),'Mon YYYY'),make_date(2026,m,1),
    (make_date(2026,m,1)+interval '1 month'-interval '1 day')::date,false FROM generate_series(1,12)m`,
  `INSERT INTO chart_of_accounts(id,company_id,account_code,account_name,account_type,normal_balance,
    is_postable,is_active,created_by,updated_by) VALUES
   ('${id.inventory}','${id.company}','1300','Inventory','asset','debit',true,true,'${id.user}','${id.user}'),
   ('${id.clearing}','${id.company}','1310','Goods Delivered Not Invoiced','asset','debit',true,true,'${id.user}','${id.user}'),
   ('${id.cogs}','${id.company}','5010','Cost of Goods Sold','expense','debit',true,true,'${id.user}','${id.user}'),
   ('${id.variance}','${id.company}','5900','Inventory Variance','expense','debit',true,true,'${id.user}','${id.user}'),
   ('${id.ar}','${id.company}','1200','Accounts Receivable','asset','debit',true,true,'${id.user}','${id.user}'),
   ('${id.vat}','${id.company}','2100','Output VAT','liability','credit',true,true,'${id.user}','${id.user}'),
   ('${id.cash}','${id.company}','1010','Cash','asset','debit',true,true,'${id.user}','${id.user}'),
   ('${id.sales}','${id.company}','4010','Sales','revenue','credit',true,true,'${id.user}','${id.user}'),
   ('${id.equity}','${id.company}','3010','Opening Equity','equity','credit',true,true,'${id.user}','${id.user}')`,
  `INSERT INTO company_accounting_config(company_id,ar_account_id,vat_payable_account_id,
    default_cash_account_id,inventory_account_id,sales_delivery_clearing_account_id,created_by,updated_by)
   VALUES('${id.company}','${id.ar}','${id.vat}','${id.cash}','${id.inventory}','${id.clearing}','${id.user}','${id.user}')`,
  `INSERT INTO number_series(company_id,branch_id,document_type_id,prefix,number_length,starting_number,
    next_number,is_active,created_by,updated_by)
   SELECT '${id.company}','${id.branch}',id,document_code||'-${RUN}-',6,1,1,true,'${id.user}','${id.user}'
   FROM ref_document_types WHERE document_code IN ('QT','SO','DR','SI','OR','JE')`,
  `INSERT INTO customers(id,company_id,customer_code,registered_name,tin,registered_address,
    delivery_address,created_by,updated_by)
   VALUES('${id.customer}','${id.company}','C-${RUN}','Conversion Buyer','444-555-${RUNNUM}-000',
    'Pasig','Pasig','${id.user}','${id.user}')`,
  `INSERT INTO units_of_measure(id,company_id,uom_code,description,is_active,created_by,updated_by)
   VALUES('${id.uom}','${id.company}','EA','Each',true,'${id.user}','${id.user}')`,
  `INSERT INTO item_categories(id,company_id,category_code,category_name,created_by,updated_by)
   VALUES('${id.category}','${id.company}','GEN','General','${id.user}','${id.user}')`,
  `INSERT INTO items(id,company_id,item_code,description,item_type,category_id,uom_id,
    standard_selling_price,standard_cost,default_sales_vat_id,sales_account_id,cogs_account_id,
    inventory_account_id,costing_method,specific_id_tracking,created_by,updated_by) VALUES
   ('${id.wac}','${id.company}','WAC-${RUN}','WAC Item','inventory_item','${id.category}','${id.uom}',100,10,(SELECT id FROM vat_codes WHERE vat_code='VAT-12' LIMIT 1),'${id.sales}','${id.cogs}','${id.inventory}','weighted_average',NULL,'${id.user}','${id.user}'),
   ('${id.fifo}','${id.company}','FIFO-${RUN}','FIFO Item','inventory_item','${id.category}','${id.uom}',100,10,(SELECT id FROM vat_codes WHERE vat_code='VAT-12' LIMIT 1),'${id.sales}','${id.cogs}','${id.inventory}','fifo',NULL,'${id.user}','${id.user}'),
   ('${id.serial}','${id.company}','SER-${RUN}','Serial Item','inventory_item','${id.category}','${id.uom}',1000,100,(SELECT id FROM vat_codes WHERE vat_code='VAT-12' LIMIT 1),'${id.sales}','${id.cogs}','${id.inventory}','specific_identification','serial','${id.user}','${id.user}')`,
  `INSERT INTO warehouses(id,company_id,branch_id,warehouse_code,warehouse_name,
    gl_inventory_account_id,gl_variance_account_id,created_by,updated_by)
   VALUES('${id.warehouse}','${id.company}','${id.branch}','MAIN','Main Warehouse','${id.inventory}','${id.variance}','${id.user}','${id.user}')`,
]
fixture.forEach(statement => sql(statement))
check(true, `fixture committed over ${fixture.length} independent transactions`)

step('Receive WAC, FIFO, and Specific-ID stock')
for (const [item, qty, cost, date, serial] of [
  [id.wac,100,10,'2026-01-01',null],[id.wac,100,14,'2026-01-02',null],
  [id.fifo,100,10,'2026-01-01',null],[id.fifo,100,14,'2026-01-02',null],
  [id.serial,1,100,'2026-01-01','SER-A'],[id.serial,1,120,'2026-01-02','SER-B'],
]) {
  act(`PERFORM fn_receive_inventory(jsonb_build_object('company_id','${id.company}',
    'warehouse_id','${id.warehouse}','item_id','${item}','qty',${qty},'unit_cost',${cost},
    'receipt_date','${date}','reference_doc_type','SALES_CONVERSION','reference_doc_id','${item}'${serial ? `,'serial_number','${serial}'` : ''}));`)
}
sql(`DO $opening_inventory$ DECLARE v_je uuid; BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"${id.user}","role":"authenticated"}', true);
  v_je := fn_create_posted_journal_entry('${id.company}','${id.branch}','OPEN-${RUN}',
    '2026-01-02','Verifier opening inventory seeded through the one costing authority',
    'MANUAL',NULL,(SELECT id FROM fiscal_periods WHERE company_id='${id.company}' AND period_number=1),
    'posted',5020,5020,NULL,'opening',false,false,false);
  PERFORM fn_add_posting_line(v_je,1,'${id.inventory}','Opening inventory valuation',5020,0,
    '${id.branch}',NULL,NULL,NULL,NULL,NULL);
  PERFORM fn_add_posting_line(v_je,2,'${id.equity}','Opening inventory equity',0,5020,
    '${id.branch}',NULL,NULL,NULL,NULL,NULL);
END $opening_inventory$;`)
const serialLayer = scalar(`SELECT inventory_cost_layer_id AS v FROM vw_available_inventory_identities
  WHERE item_id='${id.serial}' AND serial_number='SER-B'`)
check(num(`SELECT wac_unit_cost AS v FROM stock_balances WHERE item_id='${id.wac}'`) === 12,'WAC pool rate is 12.00')
check(num(`SELECT count(*) AS v FROM inventory_cost_layers WHERE item_id='${id.fifo}' AND qty_remaining>0`) === 2,'FIFO retains two source layers')
check(Boolean(serialLayer),'Specific-ID exposes SER-B as an available identity')

step('Convert an approved Quotation to an approved Sales Order')
sql(`INSERT INTO sales_quotations(id,company_id,branch_id,customer_id,customer_name_snapshot,
  customer_tin_snapshot,quotation_number,quotation_date,validity_date,currency_code,total_amount,status,created_by,updated_by)
 VALUES('${id.quote}','${id.company}','${id.branch}','${id.customer}','Conversion Buyer','444-555-${RUNNUM}-000',
  'QT-${RUN}-1','2026-02-01','2026-12-31','PHP',18100,'draft','${id.user}','${id.user}')`)
sql(`INSERT INTO sales_quotation_lines(id,quotation_id,company_id,item_id,description,quantity,uom_id,
  unit_price,discount_amount,net_amount,line_number,created_by,updated_by) VALUES
 ('${id.qWac}','${id.quote}','${id.company}','${id.wac}','WAC Item',51,'${id.uom}',100,0,5100,1,'${id.user}','${id.user}'),
 ('${id.qFifo}','${id.quote}','${id.company}','${id.fifo}','FIFO Item',120,'${id.uom}',100,0,12000,2,'${id.user}','${id.user}'),
 ('${id.qSerial}','${id.quote}','${id.company}','${id.serial}','Serial Item',1,'${id.uom}',1000,0,1000,3,'${id.user}','${id.user}')`)
sql(`UPDATE sales_quotations SET status='approved',approved_by='${id.user}',approved_at=now() WHERE id='${id.quote}'`)
act(`PERFORM fn_convert_sales_document('sales_quotation','${id.quote}','sales_order',
  '{"date":"2026-02-02"}',jsonb_build_array(
    jsonb_build_object('source_line_id','${id.qWac}','quantity',51),
    jsonb_build_object('source_line_id','${id.qFifo}','quantity',120),
    jsonb_build_object('source_line_id','${id.qSerial}','quantity',1)));`)
const so = scalar(`SELECT id AS v FROM sales_orders WHERE quotation_id='${id.quote}'`)
act(`PERFORM fn_set_converted_sales_order_decision('${so}','approved');`)
check(scalar(`SELECT approval_status AS v FROM sales_orders WHERE id='${so}'`) === 'approved','Sales Order approval commits separately')
check(num(`SELECT remaining_quantity AS v FROM vw_sales_document_conversion_progress WHERE source_line_id='${id.qWac}'`) === 0,'Quotation quantity is fully reserved')

const sol = {
  wac: scalar(`SELECT id AS v FROM sales_order_lines WHERE sales_order_id='${so}' AND item_id='${id.wac}'`),
  fifo: scalar(`SELECT id AS v FROM sales_order_lines WHERE sales_order_id='${so}' AND item_id='${id.fifo}'`),
  serial: scalar(`SELECT id AS v FROM sales_order_lines WHERE sales_order_id='${so}' AND item_id='${id.serial}'`),
}

step('Convert and complete three partial deliveries across all costing methods')
act(`PERFORM fn_convert_sales_document('sales_order','${so}','delivery_receipt',
  '{"date":"2026-02-03","delivery_address":"Pasig"}',jsonb_build_array(
    jsonb_build_object('source_line_id','${sol.wac}','quantity',20,'warehouse_id','${id.warehouse}'),
    jsonb_build_object('source_line_id','${sol.fifo}','quantity',120,'warehouse_id','${id.warehouse}'),
    jsonb_build_object('source_line_id','${sol.serial}','quantity',1,'warehouse_id','${id.warehouse}',
      'inventory_cost_layer_id','${serialLayer}','serial_number','SER-B')));`)
const dr1 = scalar(`SELECT id AS v FROM delivery_receipts WHERE sales_order_id='${so}' AND dr_date='2026-02-03'`)
act(`PERFORM fn_update_converted_delivery_details('${dr1}','{}','[]','delivered');`)

for (const [date, quantity] of [['2026-02-04',15],['2026-02-05',15]]) {
  act(`PERFORM fn_convert_sales_document('sales_order','${so}','delivery_receipt',
    '{"date":"${date}","delivery_address":"Pasig"}',jsonb_build_array(
      jsonb_build_object('source_line_id','${sol.wac}','quantity',${quantity},'warehouse_id','${id.warehouse}')));`)
  const deliveryId = scalar(`SELECT id AS v FROM delivery_receipts WHERE sales_order_id='${so}' AND dr_date='${date}'`)
  act(`PERFORM fn_update_converted_delivery_details('${deliveryId}','{}','[]','delivered');`)
}
const dr2 = scalar(`SELECT id AS v FROM delivery_receipts WHERE sales_order_id='${so}' AND dr_date='2026-02-04'`)
const dr3 = scalar(`SELECT id AS v FROM delivery_receipts WHERE sales_order_id='${so}' AND dr_date='2026-02-05'`)
check(num(`SELECT count(*) AS v FROM delivery_receipts WHERE sales_order_id='${so}' AND status='delivered'`) === 3,'three partial deliveries commit independently')
check(num(`SELECT remaining_quantity AS v FROM vw_sales_document_conversion_progress WHERE source_line_id='${sol.wac}'`) === 1,'one WAC unit remains after 20 + 15 + 15 deliveries')
check(num(`SELECT inventory_cost AS v FROM delivery_receipt_lines WHERE dr_id='${dr1}' AND item_id='${id.wac}'`) === 240,'first WAC delivery uses 20 x 12 = 240')
check(num(`SELECT inventory_cost AS v FROM delivery_receipt_lines WHERE dr_id='${dr1}' AND item_id='${id.fifo}'`) === 1280,'FIFO delivery consumes 100 x 10 plus 20 x 14 = 1,280')
check(num(`SELECT inventory_cost AS v FROM delivery_receipt_lines WHERE dr_id='${dr1}' AND item_id='${id.serial}'`) === 120,'Specific-ID delivery uses selected SER-B cost 120')
check(num(`SELECT COALESCE(sum(debit_amount-credit_amount),0) AS v FROM journal_entry_lines
  WHERE je_id=(SELECT journal_entry_id FROM delivery_receipts WHERE id='${dr1}')`) === 0,'delivery journal is balanced')

const drl1 = {
  wac: scalar(`SELECT id AS v FROM delivery_receipt_lines WHERE dr_id='${dr1}' AND item_id='${id.wac}'`),
  fifo: scalar(`SELECT id AS v FROM delivery_receipt_lines WHERE dr_id='${dr1}' AND item_id='${id.fifo}'`),
  serial: scalar(`SELECT id AS v FROM delivery_receipt_lines WHERE dr_id='${dr1}' AND item_id='${id.serial}'`),
}
const drl2 = scalar(`SELECT id AS v FROM delivery_receipt_lines WHERE dr_id='${dr2}'`)
const drl3 = scalar(`SELECT id AS v FROM delivery_receipt_lines WHERE dr_id='${dr3}'`)

const bill = (deliveryId, date, lines) => {
  act(`PERFORM fn_convert_sales_document('delivery_receipt','${deliveryId}','sales_invoice',
    '{"date":"${date}"}',${lines});`)
  return scalar(`SELECT target_document_id AS v FROM document_relationships
    WHERE source_document_type='delivery_receipt' AND source_document_id='${deliveryId}'
      AND status='active' ORDER BY created_at DESC LIMIT 1`)
}
const postInvoice = invoiceId => {
  act(`PERFORM fn_approve_sales_invoice('${invoiceId}');`)
  act(`PERFORM fn_post_sales_invoice('${invoiceId}');`)
}

step('Partially and fully invoice the deliveries, then correct and replace one invoice')
const si1 = bill(dr1,'2026-02-06',`jsonb_build_array(
  jsonb_build_object('source_line_id','${drl1.wac}','quantity',10),
  jsonb_build_object('source_line_id','${drl1.fifo}','quantity',120),
  jsonb_build_object('source_line_id','${drl1.serial}','quantity',1))`)
postInvoice(si1)
const si2 = bill(dr1,'2026-02-07',`jsonb_build_array(
  jsonb_build_object('source_line_id','${drl1.wac}','quantity',10))`)
postInvoice(si2)
const si3 = bill(dr2,'2026-02-08',`jsonb_build_array(
  jsonb_build_object('source_line_id','${drl2}','quantity',15))`)
postInvoice(si3)
const replacedSi = bill(dr3,'2026-02-09',`jsonb_build_array(
  jsonb_build_object('source_line_id','${drl3}','quantity',5))`)
postInvoice(replacedSi)
act(`PERFORM fn_void_sales_invoice('${replacedSi}',
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),'replace partial billing');`)
check(scalar(`SELECT status AS v FROM sales_invoices WHERE id='${replacedSi}'`) === 'cancelled','posted partial invoice is voided through the shared correction authority')
check(num(`SELECT remaining_quantity AS v FROM vw_sales_document_conversion_progress WHERE source_line_id='${drl3}'`) === 15,'invoice void reopens the exact delivered quantity')
check(num(`SELECT COALESCE(sum(debit_amount-credit_amount),0) AS v FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id=jel.je_id WHERE je.company_id='${id.company}' AND jel.account_id='${id.clearing}'`) === 180,'void restores the exact 15-unit delivery clearing balance')
const si4 = bill(dr3,'2026-02-10',`jsonb_build_array(
  jsonb_build_object('source_line_id','${drl3}','quantity',15))`)
postInvoice(si4)
check(num(`SELECT count(*) AS v FROM sales_invoices WHERE id IN ('${si1}','${si2}','${si3}','${si4}') AND status='posted'`) === 4,'partial and full replacement invoices post in separate transactions')
check(num(`SELECT COALESCE(sum(debit_amount-credit_amount),0) AS v FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id=jel.je_id WHERE je.company_id='${id.company}' AND jel.account_id='${id.clearing}'`) === 0,'live invoices clear all delivered cost exactly')

step('Collect all live converted invoices in one Official Receipt')
act(`PERFORM fn_save_receipt(NULL,jsonb_build_object('company_id','${id.company}','branch_id','${id.branch}',
  'customer_id','${id.customer}','customer_name_snapshot','Conversion Buyer','customer_tin_snapshot','444-555-${RUNNUM}-000',
  'receipt_date','2026-02-11','payment_mode_id',(SELECT id FROM ref_payment_modes WHERE code='CASH' LIMIT 1)),
  (SELECT jsonb_agg(jsonb_build_object('invoice_id',id,'payment_amount',total_amount,'cwt_amount',0) ORDER BY si_number)
   FROM sales_invoices WHERE id IN ('${si1}','${si2}','${si3}','${si4}')));`)
const receipt1 = scalar(`SELECT receipt_id AS v FROM receipt_lines WHERE invoice_id='${si1}'`)
act(`PERFORM fn_post_receipt('${receipt1}');`)
check(scalar(`SELECT status AS v FROM receipts WHERE id='${receipt1}'`) === 'posted','one Official Receipt settles four live converted invoices')
check(num(`SELECT count(*) AS v FROM receipt_lines WHERE receipt_id='${receipt1}'`) === 4,'collection retains one settlement edge per invoice')

step('Race two committed conversions for the final Sales Order unit, cancel the winner, then finish cleanly')
const raceSql = claimBlock(`PERFORM fn_convert_sales_document('sales_order','${so}','delivery_receipt',
  '{"date":"2026-02-12","delivery_address":"Pasig"}',
  '[{"source_line_id":"${sol.wac}","quantity":1,"warehouse_id":"${id.warehouse}"}]');`)
const race = await Promise.all([sqlAsync(raceSql),sqlAsync(raceSql)])
check(race.filter(result => result.ok).length === 1,'exactly one concurrent conversion reserves the last unit')
check(race.filter(result => !result.ok).length === 1,'the competing conversion is rejected after the source lock')
check(num(`SELECT remaining_quantity AS v FROM vw_sales_document_conversion_progress WHERE source_line_id='${sol.wac}'`) === 0,'backend progress remains non-negative after the race')

const raceDr = scalar(`SELECT dr.id AS v FROM delivery_receipts dr JOIN document_relationships r
  ON r.target_document_id=dr.id AND r.target_document_type='delivery_receipt'
  WHERE r.source_line_id='${sol.wac}' AND r.status='active' AND dr.status='draft'
  ORDER BY dr.created_at DESC LIMIT 1`)
act(`PERFORM fn_void_delivery_receipt('${raceDr}',
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),'race winner withdrawn');`)
check(num(`SELECT remaining_quantity AS v FROM vw_sales_document_conversion_progress WHERE source_line_id='${sol.wac}'`) === 1,'cancelling the draft race winner reopens exactly one unit')

act(`PERFORM fn_convert_sales_document('sales_order','${so}','delivery_receipt',
  '{"date":"2026-02-13","delivery_address":"Pasig"}',
  '[{"source_line_id":"${sol.wac}","quantity":1,"warehouse_id":"${id.warehouse}"}]');`)
const finalDr = scalar(`SELECT id AS v FROM delivery_receipts WHERE sales_order_id='${so}' AND dr_date='2026-02-13'`)
act(`PERFORM fn_update_converted_delivery_details('${finalDr}','{}','[]','delivered');`)
const finalDrl = scalar(`SELECT id AS v FROM delivery_receipt_lines WHERE dr_id='${finalDr}'`)
const finalSi = bill(finalDr,'2026-02-14',`jsonb_build_array(
  jsonb_build_object('source_line_id','${finalDrl}','quantity',1))`)
postInvoice(finalSi)
const finalInvoiceTotal = num(`SELECT total_amount AS v FROM sales_invoices WHERE id='${finalSi}'`)
act(`PERFORM fn_save_receipt(NULL,jsonb_build_object('company_id','${id.company}','branch_id','${id.branch}',
  'customer_id','${id.customer}','customer_name_snapshot','Conversion Buyer','customer_tin_snapshot','444-555-${RUNNUM}-000',
  'receipt_date','2026-02-15','payment_mode_id',(SELECT id FROM ref_payment_modes WHERE code='CASH' LIMIT 1)),
  jsonb_build_array(jsonb_build_object('invoice_id','${finalSi}','payment_amount',${finalInvoiceTotal},'cwt_amount',0)));`)
const receipt2 = scalar(`SELECT receipt_id AS v FROM receipt_lines WHERE invoice_id='${finalSi}'`)
act(`PERFORM fn_post_receipt('${receipt2}');`)

step('Reconcile lineage, inventory, accounting, tax, and settlement')
check(scalar(`SELECT fulfillment_status AS v FROM sales_orders WHERE id='${so}'`) === 'fulfilled','Sales Order becomes fulfilled only after all 51 / 120 / 1 units are reserved')
check(num(`SELECT COALESCE(sum(remaining_quantity),0) AS v FROM vw_sales_document_conversion_progress WHERE source_document_type='sales_order' AND source_document_id='${so}'`) === 0,'backend remaining quantity is zero across every Sales Order line')
check(num(`SELECT count(*) AS v FROM vw_sales_document_trace WHERE company_id='${id.company}' AND relationship_status='active'`) === 21,'trace exposes QT→SO, four live deliveries, five live invoices, and five settlement edges')
check(num(`SELECT count(*) AS v FROM document_relationships WHERE company_id='${id.company}' AND status='reversed'`) === 2,'trace retains both corrected invoice and cancelled race-target lineage')
check(num(`SELECT count(*) AS v FROM vw_inventory_valuation_reconciliation WHERE company_id='${id.company}'
  AND (abs(quantity_variance)>0.0001 OR abs(value_variance)>0.01)`) === 0,'inventory projections and layers reconcile after the converted sale')
const inventoryValue = num(`SELECT COALESCE(sum(total_cost),0) AS v FROM stock_balances WHERE company_id='${id.company}'`)
const inventoryGl = num(`SELECT COALESCE(sum(debit_amount-credit_amount),0) AS v FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id=jel.je_id WHERE je.company_id='${id.company}' AND jel.account_id='${id.inventory}'`)
check(inventoryValue === 3008 && inventoryGl === inventoryValue,'Inventory subledger equals Inventory Control GL at 3,008.00')
check(num(`SELECT COALESCE(sum(debit_amount-credit_amount),0) AS v FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id=jel.je_id WHERE je.company_id='${id.company}' AND jel.account_id='${id.cogs}'`) === 2012,'COGS equals exact WAC + FIFO + selected-serial historical cost')
check(num(`SELECT COALESCE(sum(tax_amount),0) AS v FROM tax_detail_entries WHERE company_id='${id.company}'`) === 2172,'tax ledger nets corrected and live invoices to 2,172.00 output VAT')
check(num(`SELECT COALESCE(sum(debit_amount-credit_amount),0) AS v FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id=jel.je_id WHERE je.company_id='${id.company}' AND jel.account_id='${id.ar}'`) === 0,'Official Receipts settle Accounts Receivable exactly')
check(num(`SELECT COALESCE(sum(debit_amount-credit_amount),0) AS v FROM journal_entry_lines jel
  JOIN journal_entries je ON je.id=jel.je_id WHERE je.company_id='${id.company}'`) === 0,'Trial Balance remains balanced through delivery, correction, tax, and collection')

console.log(`\n══ ${checks - failures}/${checks} checks passed ══`)
if (failures > 0) process.exit(1)
