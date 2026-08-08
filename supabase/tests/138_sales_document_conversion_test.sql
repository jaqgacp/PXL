-- 138 — Sales Document Conversion authority
-- Draft targets reserve source quantity; atomic RPCs own every lineage edge;
-- rejection/cancellation reopens quantity; conversion itself never posts.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(42);

SELECT has_table('public','document_relationships','conversion lineage table exists');
SELECT has_view('public','vw_sales_document_conversion_progress','backend progress view exists');
SELECT has_view('public','vw_sales_document_trace','forward/reverse trace view exists');
SELECT ok(NOT has_table_privilege('authenticated','public.document_relationships','INSERT')
  AND has_table_privilege('authenticated','public.document_relationships','SELECT'),
  'browser may read lineage but may not write it');
SELECT ok(has_function_privilege('authenticated','public.fn_convert_sales_document(text,uuid,text,jsonb,jsonb)','EXECUTE')
  AND NOT has_function_privilege('anon','public.fn_convert_sales_document(text,uuid,text,jsonb,jsonb)','EXECUTE'),
  'conversion RPC is authenticated and not anonymous');
SELECT ok(NOT has_function_privilege('authenticated','public.fn_refresh_sales_order_conversion(uuid)','EXECUTE')
  AND NOT has_function_privilege('service_role','public.fn_reverse_document_relationships(text,uuid,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.fn_resolve_sales_invoice_delivered_cost(uuid)','EXECUTE'),
  'relationship lifecycle helpers are private');

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
VALUES('00000000-0000-0000-0000-000000000000','13800000-0000-0000-0000-000000000001',
  'authenticated','authenticated','conversion@test.local','',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"13800000-0000-0000-0000-000000000001","role":"authenticated"}',true);

INSERT INTO companies(id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,email,
  signatory_name,signatory_position,created_by,updated_by)
VALUES('13800000-0000-0000-0000-0000000000c1','corporation','Conversion Corp','Services',
  '400-000-138-00000','vat','calendar','C St','','Makati','Metro Manila','1200',
  'conversion@test.local','Owner','President',auth.uid(),auth.uid());
INSERT INTO user_company_memberships(user_id,company_id,role)
VALUES(auth.uid(),'13800000-0000-0000-0000-0000000000c1','admin')
ON CONFLICT (user_id,company_id) DO UPDATE SET role=EXCLUDED.role;
INSERT INTO branches(id,company_id,branch_code,branch_name,address_line_1,address_line_2,
  city,province,zip_code,created_by,updated_by)
VALUES('13800000-0000-0000-0000-0000000000d1','13800000-0000-0000-0000-0000000000c1',
  'HO','Head Office','C St','','Makati','Metro Manila','1200',auth.uid(),auth.uid());
INSERT INTO fiscal_years(id,company_id,year_name,start_date,end_date,is_calendar)
VALUES('13800000-0000-0000-0000-0000000000f1','13800000-0000-0000-0000-0000000000c1',
  'FY2026','2026-01-01','2026-12-31',true);
INSERT INTO fiscal_periods(company_id,fiscal_year_id,period_number,period_name,start_date,end_date,is_locked)
SELECT '13800000-0000-0000-0000-0000000000c1','13800000-0000-0000-0000-0000000000f1',m,
  to_char(make_date(2026,m,1),'Mon YYYY'),make_date(2026,m,1),
  (make_date(2026,m,1)+interval '1 month'-interval '1 day')::date,false
FROM generate_series(1,12)m;

INSERT INTO chart_of_accounts(id,company_id,account_code,account_name,account_type,normal_balance,
  is_postable,is_active,created_by,updated_by) VALUES
 ('13800000-0000-0000-0000-00000000a001','13800000-0000-0000-0000-0000000000c1','1200','AR','asset','debit',true,true,auth.uid(),auth.uid()),
 ('13800000-0000-0000-0000-00000000a002','13800000-0000-0000-0000-0000000000c1','2100','VAT','liability','credit',true,true,auth.uid(),auth.uid()),
 ('13800000-0000-0000-0000-00000000a003','13800000-0000-0000-0000-0000000000c1','4000','Revenue','revenue','credit',true,true,auth.uid(),auth.uid());
INSERT INTO company_accounting_config(company_id,ar_account_id,vat_payable_account_id,created_by,updated_by)
VALUES('13800000-0000-0000-0000-0000000000c1','13800000-0000-0000-0000-00000000a001',
  '13800000-0000-0000-0000-00000000a002',auth.uid(),auth.uid());
INSERT INTO number_series(company_id,branch_id,document_type_id,prefix,number_length,starting_number,
  next_number,is_active,created_by,updated_by)
SELECT '13800000-0000-0000-0000-0000000000c1','13800000-0000-0000-0000-0000000000d1',id,
  document_code||'-138-',6,1,1,true,auth.uid(),auth.uid()
FROM ref_document_types WHERE document_code IN ('SO','DR','SI');
INSERT INTO customers(id,company_id,customer_code,registered_name,tin,registered_address,
  delivery_address,created_by,updated_by)
VALUES('13800000-0000-0000-0000-0000000000e1','13800000-0000-0000-0000-0000000000c1',
  'C138','Conversion Customer','444-555-138-000','Makati','Makati',auth.uid(),auth.uid());
INSERT INTO units_of_measure(id,company_id,uom_code,description,is_active,created_by,updated_by)
VALUES('13800000-0000-0000-0000-0000000000b1','13800000-0000-0000-0000-0000000000c1',
  'EA','Each',true,auth.uid(),auth.uid());
INSERT INTO item_categories(id,company_id,category_code,category_name,created_by,updated_by)
VALUES('13800000-0000-0000-0000-0000000000ca','13800000-0000-0000-0000-0000000000c1',
  'SVC','Services',auth.uid(),auth.uid());
INSERT INTO items(id,company_id,item_code,description,item_type,category_id,uom_id,
  standard_selling_price,default_sales_vat_id,sales_account_id,created_by,updated_by)
VALUES('13800000-0000-0000-0000-0000000000bb','13800000-0000-0000-0000-0000000000c1',
  'SVC-138','Governed Service','service','13800000-0000-0000-0000-0000000000ca',
  '13800000-0000-0000-0000-0000000000b1',100,
  (SELECT id FROM vat_codes WHERE vat_code='VAT-12'),'13800000-0000-0000-0000-00000000a003',auth.uid(),auth.uid());

INSERT INTO sales_quotations(id,company_id,branch_id,customer_id,customer_name_snapshot,
  customer_tin_snapshot,quotation_number,quotation_date,validity_date,currency_code,total_amount,
  status,created_by,updated_by)
VALUES('13800000-0000-0000-0000-00000000c100','13800000-0000-0000-0000-0000000000c1',
  '13800000-0000-0000-0000-0000000000d1','13800000-0000-0000-0000-0000000000e1',
  'Conversion Customer','444-555-138-000','QT-138-1','2026-08-01','2026-12-31','PHP',1000,
  'approved',auth.uid(),auth.uid());
INSERT INTO sales_quotation_lines(id,quotation_id,company_id,item_id,description,quantity,uom_id,
  unit_price,discount_amount,net_amount,line_number,created_by,updated_by)
VALUES('13800000-0000-0000-0000-00000000c101','13800000-0000-0000-0000-00000000c100',
  '13800000-0000-0000-0000-0000000000c1','13800000-0000-0000-0000-0000000000bb',
  'Governed Service',10,'13800000-0000-0000-0000-0000000000b1',100,0,1000,1,auth.uid(),auth.uid());

SELECT set_config('request.jwt.claims',
  '{"sub":"13800000-0000-0000-0000-000000000099","role":"authenticated"}',true);
SELECT throws_ok($$SELECT fn_convert_sales_document('sales_quotation',
  '13800000-0000-0000-0000-00000000c100','sales_order','{}',
  '[{"source_line_id":"13800000-0000-0000-0000-00000000c101","quantity":1}]')$$,
  'P0001','Sales Quotation not found or access denied',
  'a user outside the company cannot convert its quotation');
SELECT set_config('request.jwt.claims',
  '{"sub":"13800000-0000-0000-0000-000000000001","role":"authenticated"}',true);

CREATE TEMP TABLE t_conversion(k TEXT PRIMARY KEY,id UUID);
INSERT INTO t_conversion VALUES('so1',fn_convert_sales_document('sales_quotation',
  '13800000-0000-0000-0000-00000000c100','sales_order','{"date":"2026-08-02"}',
  '[{"source_line_id":"13800000-0000-0000-0000-00000000c101","quantity":4}]'));
SELECT is((SELECT approval_status FROM sales_orders WHERE id=(SELECT id FROM t_conversion WHERE k='so1')),
  'pending','conversion creates a pending Sales Order');
SELECT is((SELECT converted_quantity FROM document_relationships WHERE target_document_id=(SELECT id FROM t_conversion WHERE k='so1')),
  4::numeric,'draft target reserves four quotation units');
SELECT results_eq($$SELECT original_quantity,converted_quantity,remaining_quantity
  FROM vw_sales_document_conversion_progress WHERE source_line_id='13800000-0000-0000-0000-00000000c101'$$,
  $$SELECT 10::numeric,4::numeric,6::numeric$$,'progress is server-derived after partial conversion');

INSERT INTO t_conversion VALUES('so2',fn_convert_sales_document('sales_quotation',
  '13800000-0000-0000-0000-00000000c100','sales_order','{}',
  '[{"source_line_id":"13800000-0000-0000-0000-00000000c101","quantity":6}]'));
SELECT is((SELECT count(*)::int FROM document_relationships WHERE source_line_id='13800000-0000-0000-0000-00000000c101' AND status='active'),
  2,'one quotation supports multiple targets');
SELECT is((SELECT remaining_quantity FROM vw_sales_document_conversion_progress WHERE source_line_id='13800000-0000-0000-0000-00000000c101'),
  0::numeric,'the backend reports no unreserved quotation quantity');
SELECT throws_ok($$SELECT fn_convert_sales_document('sales_quotation','13800000-0000-0000-0000-00000000c100',
  'sales_order','{}','[{"source_line_id":"13800000-0000-0000-0000-00000000c101","quantity":1}]')$$,
  'P0001','Quotation line 1 has 0.0000 remaining; requested 1.0000','over-conversion is rejected while the source line is locked');

SELECT lives_ok($$SELECT fn_set_converted_sales_order_decision((SELECT id FROM t_conversion WHERE k='so1'),'approved')$$,
  'converted order approval uses its governed decision RPC');
SELECT is((SELECT approval_status FROM sales_orders WHERE id=(SELECT id FROM t_conversion WHERE k='so1')),
  'approved','decision is persisted');
SELECT throws_ok($$SELECT fn_convert_sales_document('sales_order',(SELECT id FROM t_conversion WHERE k='so1'),
  'delivery_receipt','{}','[{"source_line_id":"13800000-0000-0000-0000-00000000c101","quantity":1}]')$$,
  'P0001','Sales Order source line is invalid',
  'a line outside the selected source document cannot be smuggled into a target');
SELECT lives_ok($$SELECT fn_set_converted_sales_order_decision((SELECT id FROM t_conversion WHERE k='so2'),'rejected')$$,
  'a pending converted order can be rejected');
SELECT is((SELECT status FROM document_relationships WHERE target_document_id=(SELECT id FROM t_conversion WHERE k='so2')),
  'reversed','rejection reverses its inbound reservation');
SELECT is((SELECT remaining_quantity FROM vw_sales_document_conversion_progress WHERE source_line_id='13800000-0000-0000-0000-00000000c101'),
  6::numeric,'rejection reopens quotation quantity');
SELECT throws_ok($$SELECT fn_cancel_sales_quotation('13800000-0000-0000-0000-00000000c100','superseded')$$,
  'P0001','Sales Quotation has active downstream Sales Orders; cancel or reject them first',
  'a quotation with an active converted order cannot be cancelled');

SELECT set_config('pxl.document_conversion_write','off',true);
SELECT throws_ok($q$SELECT fn_save_sales_invoice(NULL,
  '{"company_id":"13800000-0000-0000-0000-0000000000c1","branch_id":"13800000-0000-0000-0000-0000000000d1","customer_id":"13800000-0000-0000-0000-0000000000e1","customer_name_snapshot":"Conversion Customer","customer_tin_snapshot":"444-555-138-000","customer_address_snapshot":"Makati","date":"2026-08-03"}',
  jsonb_build_array(jsonb_build_object('item_id','13800000-0000-0000-0000-0000000000bb','description','Bypass',
  'quantity',1,'unit_price',100,'vat_code_id',(SELECT id FROM vat_codes WHERE vat_code='VAT-12'),
  'revenue_account_id','13800000-0000-0000-0000-00000000a003','source_document_type','sales_order',
  'source_line_id',(SELECT id FROM sales_order_lines WHERE sales_order_id=(SELECT id FROM t_conversion WHERE k='so1')))))$q$,
  'P0001','Source-linked Sales Invoice lines must be created by fn_convert_sales_document',
  'direct authenticated source linkage is blocked');

INSERT INTO t_conversion VALUES('si1',fn_convert_sales_document('sales_order',(SELECT id FROM t_conversion WHERE k='so1'),
  'sales_invoice','{"date":"2026-08-03"}',jsonb_build_array(jsonb_build_object('source_line_id',
  (SELECT id FROM sales_order_lines WHERE sales_order_id=(SELECT id FROM t_conversion WHERE k='so1')),'quantity',2))));
SELECT is((SELECT status FROM sales_invoices WHERE id=(SELECT id FROM t_conversion WHERE k='si1')),
  'draft','direct service conversion creates a draft invoice');
SELECT is((SELECT source_document_type FROM sales_invoice_lines WHERE sales_invoice_id=(SELECT id FROM t_conversion WHERE k='si1')),
  'sales_order','invoice line retains governed source lineage');
SELECT results_eq($$SELECT converted_quantity,remaining_quantity FROM vw_sales_document_conversion_progress
  WHERE source_document_type='sales_order' AND source_document_id=(SELECT id FROM t_conversion WHERE k='so1')$$,
  $$SELECT 2::numeric,2::numeric$$,'direct billing consumes the shared order budget');

INSERT INTO t_conversion VALUES('dr1',fn_convert_sales_document('sales_order',(SELECT id FROM t_conversion WHERE k='so1'),
  'delivery_receipt','{"date":"2026-08-04","delivery_address":"Makati"}',jsonb_build_array(jsonb_build_object('source_line_id',
  (SELECT id FROM sales_order_lines WHERE sales_order_id=(SELECT id FROM t_conversion WHERE k='so1')),'quantity',2))));
SELECT is((SELECT fulfillment_status FROM sales_orders WHERE id=(SELECT id FROM t_conversion WHERE k='so1')),
  'fulfilled','draft delivery plus draft invoice reserve the whole shared order budget');
SELECT set_config('pxl.document_conversion_write','off',true);
SELECT throws_ok($$UPDATE delivery_receipt_lines SET quantity=1 WHERE dr_id=(SELECT id FROM t_conversion WHERE k='dr1')$$,
  'P0001',NULL,'converted target quantity cannot be edited directly');
SELECT lives_ok($$SELECT fn_update_converted_delivery_details((SELECT id FROM t_conversion WHERE k='dr1'),
  '{}','[]','delivered')$$,'converted service delivery completes atomically without an inventory event');
SELECT is((SELECT status FROM delivery_receipts WHERE id=(SELECT id FROM t_conversion WHERE k='dr1')),
  'delivered','delivery status is committed');

INSERT INTO t_conversion VALUES('si2',fn_convert_sales_document('delivery_receipt',(SELECT id FROM t_conversion WHERE k='dr1'),
  'sales_invoice','{"date":"2026-08-05"}',jsonb_build_array(jsonb_build_object('source_line_id',
  (SELECT id FROM delivery_receipt_lines WHERE dr_id=(SELECT id FROM t_conversion WHERE k='dr1')),'quantity',1))));
SELECT results_eq($$SELECT converted_quantity,remaining_quantity FROM vw_sales_document_conversion_progress
  WHERE source_document_type='delivery_receipt' AND source_document_id=(SELECT id FROM t_conversion WHERE k='dr1')$$,
  $$SELECT 1::numeric,1::numeric$$,'delivered quantity supports partial billing');
SELECT is((SELECT count(*)::int FROM vw_sales_document_trace WHERE source_document_id='13800000-0000-0000-0000-00000000c100'
  OR target_document_id='13800000-0000-0000-0000-00000000c100'),2,'trace exposes both quotation conversion edges');
SELECT is((SELECT count(*)::int FROM vw_sales_document_trace WHERE relationship_status='active'
  AND (source_document_id=(SELECT id FROM t_conversion WHERE k='so1') OR target_document_id=(SELECT id FROM t_conversion WHERE k='so1'))),
  3,'trace walks active inbound and outbound order relationships');

SELECT throws_ok($$SELECT fn_void_delivery_receipt((SELECT id FROM t_conversion WHERE k='dr1'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'), 'invoice still active')$$,
  NULL,NULL,'a converted delivery cannot be cancelled while even a draft invoice bills it');
SELECT lives_ok($$SELECT fn_void_sales_invoice((SELECT id FROM t_conversion WHERE k='si2'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),'replace partial invoice')$$,
  'voiding the converted invoice releases its delivery reservation');
SELECT is((SELECT remaining_quantity FROM vw_sales_document_conversion_progress
  WHERE source_document_type='delivery_receipt' AND source_document_id=(SELECT id FROM t_conversion WHERE k='dr1')),
  2::numeric,'invoice void reopens the exact delivery quantity');
SELECT lives_ok($$SELECT fn_void_delivery_receipt((SELECT id FROM t_conversion WHERE k='dr1'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),'delivery withdrawn')$$,
  'the converted delivery cancels after its downstream invoice is corrected');
SELECT results_eq($$SELECT converted_quantity,remaining_quantity FROM vw_sales_document_conversion_progress
  WHERE source_document_type='sales_order' AND source_document_id=(SELECT id FROM t_conversion WHERE k='so1')$$,
  $$SELECT 2::numeric,2::numeric$$,'delivery cancellation reopens only its order quantity');
SELECT throws_ok($$SELECT fn_cancel_sales_order((SELECT id FROM t_conversion WHERE k='so1'),'order withdrawn')$$,
  'P0001','Sales Order has active downstream deliveries or invoices; cancel or void them first',
  'the order cannot be cancelled while its direct converted invoice remains active');
SELECT lives_ok($$SELECT fn_void_sales_invoice((SELECT id FROM t_conversion WHERE k='si1'),
  (SELECT id FROM void_reason_codes WHERE code='DATA_ENTRY_ERROR'),'service invoice withdrawn')$$,
  'the final active order target is corrected first');
SELECT lives_ok($$SELECT fn_cancel_sales_order((SELECT id FROM t_conversion WHERE k='so1'),'order withdrawn')$$,
  'the converted order can then be cancelled');
SELECT is((SELECT remaining_quantity FROM vw_sales_document_conversion_progress
  WHERE source_line_id='13800000-0000-0000-0000-00000000c101'),
  10::numeric,'order cancellation reopens its exact quotation reservation');
SELECT lives_ok($$SELECT fn_cancel_sales_quotation('13800000-0000-0000-0000-00000000c100','customer withdrew')$$,
  'the quotation can be cancelled after all downstream corrections');
SELECT throws_ok($$SELECT fn_convert_sales_document('sales_quotation',
  '13800000-0000-0000-0000-00000000c100','sales_order','{}',
  '[{"source_line_id":"13800000-0000-0000-0000-00000000c101","quantity":1}]')$$,
  'P0001','Only a current approved Sales Quotation can be converted',
  'a cancelled quotation cannot be converted');

SELECT * FROM finish();
ROLLBACK;
