-- 136 — Production inventory writer coverage
-- Exercises Goods Issue, Stock Adjustment, Stock Transfer, and Physical Count
-- through their real public posting entrypoints using FIFO and Specific ID.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(17);

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
VALUES('00000000-0000-0000-0000-000000000000','13600000-0000-0000-0000-000000000001',
  'authenticated','authenticated','writers@test.local','',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"13600000-0000-0000-0000-000000000001","role":"authenticated"}',true);

INSERT INTO companies(id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,email,
  signatory_name,signatory_position,created_by,updated_by)
VALUES('13600000-0000-0000-0000-0000000000c1','corporation','Writer Coverage Corp',
  'Wholesale','400-000-136-00000','vat','calendar','W St','','Makati','Metro Manila',
  '1200','writers@test.local','Owner','President',auth.uid(),auth.uid());
INSERT INTO branches(id,company_id,branch_code,branch_name,address_line_1,address_line_2,
  city,province,zip_code,created_by,updated_by)
VALUES('13600000-0000-0000-0000-0000000000b1','13600000-0000-0000-0000-0000000000c1',
  'HO','Head Office','W St','','Makati','Metro Manila','1200',auth.uid(),auth.uid());
INSERT INTO fiscal_years(id,company_id,year_name,start_date,end_date,is_calendar)
VALUES('13600000-0000-0000-0000-0000000000f1','13600000-0000-0000-0000-0000000000c1',
  'FY2026','2026-01-01','2026-12-31',true);
INSERT INTO fiscal_periods(company_id,fiscal_year_id,period_number,period_name,start_date,end_date,is_locked)
VALUES('13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000f1',
  1,'Jan 2026','2026-01-01','2026-12-31',false);

INSERT INTO chart_of_accounts(id,company_id,account_code,account_name,account_type,
  normal_balance,is_postable,is_active,created_by,updated_by)
VALUES
 ('13600000-0000-0000-0000-00000000a001','13600000-0000-0000-0000-0000000000c1','1300','Inventory','asset','debit',true,true,auth.uid(),auth.uid()),
 ('13600000-0000-0000-0000-00000000a002','13600000-0000-0000-0000-0000000000c1','5100','Inventory Expense','expense','debit',true,true,auth.uid(),auth.uid()),
 ('13600000-0000-0000-0000-00000000a003','13600000-0000-0000-0000-0000000000c1','5900','Inventory Variance','expense','debit',true,true,auth.uid(),auth.uid());
INSERT INTO number_series(company_id,branch_id,document_type_id,prefix,number_length,
  starting_number,next_number,is_active,created_by,updated_by)
SELECT '13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000b1',
  id,'JE-136-',6,1,1,true,auth.uid(),auth.uid()
FROM ref_document_types WHERE document_code='JE';

INSERT INTO warehouses(id,company_id,branch_id,warehouse_code,warehouse_name,
  gl_inventory_account_id,gl_variance_account_id,created_by,updated_by)
VALUES
 ('13600000-0000-0000-0000-0000000000a1','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000b1','MAIN','Main','13600000-0000-0000-0000-00000000a001','13600000-0000-0000-0000-00000000a003',auth.uid(),auth.uid()),
 ('13600000-0000-0000-0000-0000000000a2','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000b1','SECOND','Second','13600000-0000-0000-0000-00000000a001','13600000-0000-0000-0000-00000000a003',auth.uid(),auth.uid());
INSERT INTO units_of_measure(id,company_id,uom_code,description,is_active,created_by,updated_by)
VALUES('13600000-0000-0000-0000-0000000000b2','13600000-0000-0000-0000-0000000000c1','EA','Each',true,auth.uid(),auth.uid());
INSERT INTO item_categories(id,company_id,category_code,category_name,created_by,updated_by)
VALUES('13600000-0000-0000-0000-0000000000ca','13600000-0000-0000-0000-0000000000c1','GEN','General',auth.uid(),auth.uid());
INSERT INTO items(id,company_id,item_code,description,item_type,category_id,uom_id,
  standard_cost,cogs_account_id,inventory_account_id,costing_method,specific_id_tracking,
  created_by,updated_by)
VALUES
 ('13600000-0000-0000-0000-0000000000d1','13600000-0000-0000-0000-0000000000c1','FIFO-136','FIFO Item','inventory_item','13600000-0000-0000-0000-0000000000ca','13600000-0000-0000-0000-0000000000b2',10,'13600000-0000-0000-0000-00000000a002','13600000-0000-0000-0000-00000000a001','fifo',NULL,auth.uid(),auth.uid()),
 ('13600000-0000-0000-0000-0000000000d2','13600000-0000-0000-0000-0000000000c1','SER-136','Serial Item','inventory_item','13600000-0000-0000-0000-0000000000ca','13600000-0000-0000-0000-0000000000b2',10000,'13600000-0000-0000-0000-00000000a002','13600000-0000-0000-0000-00000000a001','specific_identification','serial',auth.uid(),auth.uid());

SELECT fn_receive_inventory('{"company_id":"13600000-0000-0000-0000-0000000000c1","warehouse_id":"13600000-0000-0000-0000-0000000000a1","item_id":"13600000-0000-0000-0000-0000000000d1","qty":100,"unit_cost":10,"receipt_date":"2026-01-01","reference_doc_type":"TEST","reference_doc_id":"13600000-0000-0000-0000-000000000101"}');
SELECT fn_receive_inventory('{"company_id":"13600000-0000-0000-0000-0000000000c1","warehouse_id":"13600000-0000-0000-0000-0000000000a1","item_id":"13600000-0000-0000-0000-0000000000d1","qty":100,"unit_cost":14,"receipt_date":"2026-01-02","reference_doc_type":"TEST","reference_doc_id":"13600000-0000-0000-0000-000000000102"}');
SELECT fn_receive_inventory('{"company_id":"13600000-0000-0000-0000-0000000000c1","warehouse_id":"13600000-0000-0000-0000-0000000000a1","item_id":"13600000-0000-0000-0000-0000000000d2","qty":1,"unit_cost":12000,"receipt_date":"2026-01-01","reference_doc_type":"TEST","reference_doc_id":"13600000-0000-0000-0000-000000000103","serial_number":"SER-B"}');

-- FIFO Goods Issue: real Posting Engine surface, exact 1,280 allocation and GL.
INSERT INTO goods_issues(id,company_id,branch_id,warehouse_id,issue_number,issue_date,purpose,status,created_by,updated_by)
VALUES('13600000-0000-0000-0000-00000000e100','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000b1','13600000-0000-0000-0000-0000000000a1','GI-136','2026-01-03','Operations','draft',auth.uid(),auth.uid());
INSERT INTO goods_issue_lines(id,issue_id,company_id,item_id,qty_issued,gl_expense_account_id)
VALUES('13600000-0000-0000-0000-00000000e101','13600000-0000-0000-0000-00000000e100','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000d1',120,'13600000-0000-0000-0000-00000000a002');
SELECT lives_ok($$SELECT fn_post_goods_issue('13600000-0000-0000-0000-00000000e100')$$,'FIFO Goods Issue posts');
SELECT is((SELECT total_cost FROM goods_issue_lines WHERE id='13600000-0000-0000-0000-00000000e101'),1280::numeric,'Goods Issue carries exact FIFO cost');
SELECT is((SELECT count(*)::int FROM inventory_layer_allocations a JOIN goods_issue_lines l ON l.inventory_transaction_id=a.inventory_transaction_id WHERE l.id='13600000-0000-0000-0000-00000000e101' AND a.allocation_kind='consume'),2,'Goods Issue persists both FIFO allocations');
SELECT is((SELECT SUM(credit_amount) FROM journal_entry_lines jel JOIN goods_issues gi ON gi.journal_entry_id=jel.je_id WHERE gi.id='13600000-0000-0000-0000-00000000e100' AND jel.account_id='13600000-0000-0000-0000-00000000a001'),1280::numeric,'Goods Issue credits Inventory by exact cost');

-- Negative adjustment consumes the remaining FIFO layer at 14, not standard 10.
INSERT INTO stock_adjustments(id,company_id,branch_id,warehouse_id,adjustment_number,adjustment_date,reason,status,created_by,updated_by)
VALUES('13600000-0000-0000-0000-00000000e200','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000b1','13600000-0000-0000-0000-0000000000a1','ADJ-136','2026-01-04','damage','draft',auth.uid(),auth.uid());
INSERT INTO stock_adjustment_lines(id,adjustment_id,company_id,item_id,qty_before,qty_adjusted,qty_after,gl_offset_account_id)
VALUES('13600000-0000-0000-0000-00000000e201','13600000-0000-0000-0000-00000000e200','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000d1',80,-10,70,'13600000-0000-0000-0000-00000000a003');
SELECT lives_ok($$SELECT fn_post_stock_adjustment('13600000-0000-0000-0000-00000000e200')$$,'negative FIFO adjustment posts');
SELECT is((SELECT total_cost_impact FROM stock_adjustment_lines WHERE id='13600000-0000-0000-0000-00000000e201'),-140::numeric,'negative adjustment uses exact FIFO value, not standard cost');
SELECT is((SELECT total_cost FROM stock_balances WHERE item_id='13600000-0000-0000-0000-0000000000d1'),980::numeric,'FIFO balance remains 70 at 14');

-- Specific-ID stock transfer moves the same serial and preserves source lineage.
INSERT INTO stock_transfers(id,company_id,transfer_number,transfer_date,from_warehouse_id,to_warehouse_id,status,created_by,updated_by)
VALUES('13600000-0000-0000-0000-00000000e300','13600000-0000-0000-0000-0000000000c1','STX-136','2026-01-05','13600000-0000-0000-0000-0000000000a1','13600000-0000-0000-0000-0000000000a2','draft',auth.uid(),auth.uid());
INSERT INTO stock_transfer_lines(id,transfer_id,company_id,item_id,qty_transferred,inventory_cost_layer_id,serial_number)
SELECT '13600000-0000-0000-0000-00000000e301','13600000-0000-0000-0000-00000000e300','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000d2',1,id,'SER-B'
FROM inventory_cost_layers WHERE serial_number='SER-B' AND warehouse_id='13600000-0000-0000-0000-0000000000a1';
SELECT lives_ok($$SELECT fn_post_stock_transfer('13600000-0000-0000-0000-00000000e300')$$,'Specific-ID transfer posts');
SELECT is((SELECT total_cost FROM stock_transfer_lines WHERE id='13600000-0000-0000-0000-00000000e301'),12000::numeric,'transfer carries the selected serial value');
SELECT results_eq($$SELECT warehouse_id,serial_number,qty_remaining FROM inventory_cost_layers WHERE serial_number='SER-B' ORDER BY warehouse_id$$,
  $$VALUES ('13600000-0000-0000-0000-0000000000a1'::uuid,'SER-B'::text,0::numeric),('13600000-0000-0000-0000-0000000000a2'::uuid,'SER-B'::text,1::numeric)$$,
  'the same serial leaves source and becomes available at destination');
SELECT ok((SELECT parent_layer_id IS NOT NULL FROM inventory_cost_layers WHERE serial_number='SER-B' AND warehouse_id='13600000-0000-0000-0000-0000000000a2'),'destination serial layer retains source-layer lineage');
SELECT is((SELECT SUM(total_cost) FROM stock_balances WHERE item_id='13600000-0000-0000-0000-0000000000d2'),12000::numeric,'transfer preserves company-wide inventory value');

-- Physical count removes the selected serial from its destination at exact cost.
INSERT INTO physical_count_sheets(id,company_id,branch_id,warehouse_id,count_number,count_date,status,created_by,updated_by)
VALUES('13600000-0000-0000-0000-00000000e400','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000b1','13600000-0000-0000-0000-0000000000a2','COUNT-136','2026-01-06','variance_review',auth.uid(),auth.uid());
INSERT INTO physical_count_sheet_lines(id,count_sheet_id,company_id,item_id,system_qty,counted_qty,unit_cost,gl_variance_account_id,inventory_cost_layer_id,serial_number)
SELECT '13600000-0000-0000-0000-00000000e401','13600000-0000-0000-0000-00000000e400','13600000-0000-0000-0000-0000000000c1','13600000-0000-0000-0000-0000000000d2',1,0,0,'13600000-0000-0000-0000-00000000a003',id,'SER-B'
FROM inventory_cost_layers WHERE serial_number='SER-B' AND warehouse_id='13600000-0000-0000-0000-0000000000a2';
SELECT lives_ok($$SELECT fn_post_physical_count('13600000-0000-0000-0000-00000000e400')$$,'Specific-ID physical-count variance posts');
SELECT is((SELECT ABS(total_cost) FROM inventory_transactions it JOIN physical_count_sheet_lines l ON l.inventory_transaction_id=it.id WHERE l.id='13600000-0000-0000-0000-00000000e401'),12000::numeric,'physical count removes the selected serial at exact cost');
SELECT is((SELECT qty_on_hand FROM stock_balances WHERE warehouse_id='13600000-0000-0000-0000-0000000000a2' AND item_id='13600000-0000-0000-0000-0000000000d2'),0::numeric,'physical count leaves destination serial stock at zero');

SELECT is((SELECT COUNT(*)::int FROM vw_inventory_valuation_reconciliation WHERE company_id='13600000-0000-0000-0000-0000000000c1' AND (ABS(quantity_variance)>0.0001 OR ABS(value_variance)>0.01)),0,'all layered stock projections reconcile to active layers');
SELECT ok(NOT has_function_privilege('authenticated','public.fn_transfer_inventory(jsonb)','EXECUTE') AND has_table_privilege('authenticated','public.vw_available_inventory_identities','SELECT'),'transfer authority is private while identity choices are browser-readable');

SELECT * FROM finish();
ROLLBACK;
