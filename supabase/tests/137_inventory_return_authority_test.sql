-- 137 — Historical-cost customer and supplier return authority
-- Proves returns do not use today's WAC/FIFO result and that serial identity
-- and receipt-layer lineage survive both directions.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(14);

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
VALUES('00000000-0000-0000-0000-000000000000','13700000-0000-0000-0000-000000000001',
  'authenticated','authenticated','returns@test.local','',now(),now(),now(),
  '{"provider":"email","providers":["email"]}','{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"13700000-0000-0000-0000-000000000001","role":"authenticated"}',true);

INSERT INTO companies(id,entity_type,registered_name,line_of_business,tin,tax_registration,
  accounting_period,address_line_1,address_line_2,city,province,zip_code,email,
  signatory_name,signatory_position,created_by,updated_by)
VALUES('13700000-0000-0000-0000-0000000000c1','corporation','Return Authority Corp',
  'Wholesale','400-000-137-00000','vat','calendar','R St','','Makati','Metro Manila',
  '1200','returns@test.local','Owner','President',auth.uid(),auth.uid());
INSERT INTO warehouses(id,company_id,warehouse_code,warehouse_name,created_by,updated_by)
VALUES('13700000-0000-0000-0000-0000000000a1','13700000-0000-0000-0000-0000000000c1','MAIN','Main',auth.uid(),auth.uid());
INSERT INTO units_of_measure(id,company_id,uom_code,description,is_active,created_by,updated_by)
VALUES('13700000-0000-0000-0000-0000000000b1','13700000-0000-0000-0000-0000000000c1','EA','Each',true,auth.uid(),auth.uid());
INSERT INTO item_categories(id,company_id,category_code,category_name,created_by,updated_by)
VALUES('13700000-0000-0000-0000-0000000000ca','13700000-0000-0000-0000-0000000000c1','GEN','General',auth.uid(),auth.uid());
INSERT INTO items(id,company_id,item_code,description,item_type,category_id,uom_id,
  costing_method,specific_id_tracking,created_by,updated_by)
VALUES
 ('13700000-0000-0000-0000-0000000000d1','13700000-0000-0000-0000-0000000000c1','WAC','WAC','inventory_item','13700000-0000-0000-0000-0000000000ca','13700000-0000-0000-0000-0000000000b1','weighted_average',NULL,auth.uid(),auth.uid()),
 ('13700000-0000-0000-0000-0000000000d2','13700000-0000-0000-0000-0000000000c1','FIFO','FIFO','inventory_item','13700000-0000-0000-0000-0000000000ca','13700000-0000-0000-0000-0000000000b1','fifo',NULL,auth.uid(),auth.uid()),
 ('13700000-0000-0000-0000-0000000000d3','13700000-0000-0000-0000-0000000000c1','SER','Serial','inventory_item','13700000-0000-0000-0000-0000000000ca','13700000-0000-0000-0000-0000000000b1','specific_identification','serial',auth.uid(),auth.uid()),
 ('13700000-0000-0000-0000-0000000000d4','13700000-0000-0000-0000-0000000000c1','SUP','Supplier return FIFO','inventory_item','13700000-0000-0000-0000-0000000000ca','13700000-0000-0000-0000-0000000000b1','fifo',NULL,auth.uid(),auth.uid());

CREATE TEMP TABLE t_return(k TEXT PRIMARY KEY,id UUID);

-- WAC customer return uses the original issue rate even after the pool changes.
SELECT fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d1","qty":100,"unit_cost":10,"receipt_date":"2026-01-01"}');
SELECT fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d1","qty":100,"unit_cost":14,"receipt_date":"2026-01-02"}');
INSERT INTO t_return SELECT 'wac_issue',(fn_issue_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d1","qty":50,"transaction_date":"2026-01-03"}')->>'inventory_transaction_id')::uuid;
SELECT fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d1","qty":100,"unit_cost":30,"receipt_date":"2026-01-04"}');
INSERT INTO t_return SELECT 'wac_return',(fn_return_inventory(jsonb_build_object(
  'company_id','13700000-0000-0000-0000-0000000000c1','warehouse_id','13700000-0000-0000-0000-0000000000a1',
  'item_id','13700000-0000-0000-0000-0000000000d1','qty',10,
  'original_inventory_transaction_id',(SELECT id FROM t_return WHERE k='wac_issue')))->>'inventory_transaction_id')::uuid;
SELECT is((SELECT total_cost FROM inventory_transactions WHERE id=(SELECT id FROM t_return WHERE k='wac_return')),120::numeric,'WAC customer return uses original issue cost 10 x 12');
SELECT results_eq($$SELECT qty_on_hand,total_cost FROM stock_balances WHERE item_id='13700000-0000-0000-0000-0000000000d1'$$,$$SELECT 260::numeric,4920::numeric$$,'WAC return restores historical value into the changed pool');

-- FIFO partial returns consume the original allocation evidence deterministically.
INSERT INTO t_return VALUES('fifo_r1',fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d2","qty":100,"unit_cost":10,"receipt_date":"2026-02-01"}'));
INSERT INTO t_return VALUES('fifo_r2',fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d2","qty":100,"unit_cost":14,"receipt_date":"2026-02-02"}'));
INSERT INTO t_return SELECT 'fifo_issue',(fn_issue_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d2","qty":120,"transaction_date":"2026-02-03"}')->>'inventory_transaction_id')::uuid;
INSERT INTO t_return SELECT 'fifo_ret1',(fn_return_inventory(jsonb_build_object('company_id','13700000-0000-0000-0000-0000000000c1','warehouse_id','13700000-0000-0000-0000-0000000000a1','item_id','13700000-0000-0000-0000-0000000000d2','qty',20,'original_inventory_transaction_id',(SELECT id FROM t_return WHERE k='fifo_issue')))->>'inventory_transaction_id')::uuid;
SELECT is((SELECT total_cost FROM inventory_transactions WHERE id=(SELECT id FROM t_return WHERE k='fifo_ret1')),200::numeric,'partial FIFO customer return restores its original first allocation at 10');
SELECT is((SELECT sum(total_cost) FROM inventory_layer_allocations WHERE inventory_transaction_id=(SELECT id FROM t_return WHERE k='fifo_ret1') AND allocation_kind='return'),200::numeric,'FIFO return persists exact source-layer restoration evidence');
INSERT INTO t_return SELECT 'fifo_ret2',(fn_return_inventory(jsonb_build_object('company_id','13700000-0000-0000-0000-0000000000c1','warehouse_id','13700000-0000-0000-0000-0000000000a1','item_id','13700000-0000-0000-0000-0000000000d2','qty',100,'original_inventory_transaction_id',(SELECT id FROM t_return WHERE k='fifo_issue')))->>'inventory_transaction_id')::uuid;
SELECT is((SELECT total_cost FROM inventory_transactions WHERE id=(SELECT id FROM t_return WHERE k='fifo_ret2')),1080::numeric,'remaining FIFO customer return restores the remaining historical 80 x 10 and 20 x 14');
SELECT throws_ok($$SELECT fn_return_inventory(jsonb_build_object('company_id','13700000-0000-0000-0000-0000000000c1','warehouse_id','13700000-0000-0000-0000-0000000000a1','item_id','13700000-0000-0000-0000-0000000000d2','qty',1,'original_inventory_transaction_id',(SELECT id FROM t_return WHERE k='fifo_issue')))$$,'23514',NULL,'customer return cannot exceed original issued quantity');

-- Specific-ID returns restore the same serial, never a substitute unit.
INSERT INTO t_return VALUES('ser_a',fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d3","qty":1,"unit_cost":100,"serial_number":"SER-A"}'));
INSERT INTO t_return VALUES('ser_b',fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d3","qty":1,"unit_cost":120,"serial_number":"SER-B"}'));
INSERT INTO t_return SELECT 'ser_issue',(fn_issue_inventory(jsonb_build_object('company_id','13700000-0000-0000-0000-0000000000c1','warehouse_id','13700000-0000-0000-0000-0000000000a1','item_id','13700000-0000-0000-0000-0000000000d3','qty',1,'inventory_cost_layer_id',(SELECT id FROM inventory_cost_layers WHERE serial_number='SER-B')))->>'inventory_transaction_id')::uuid;
INSERT INTO t_return SELECT 'ser_return',(fn_return_inventory(jsonb_build_object('company_id','13700000-0000-0000-0000-0000000000c1','warehouse_id','13700000-0000-0000-0000-0000000000a1','item_id','13700000-0000-0000-0000-0000000000d3','qty',1,'original_inventory_transaction_id',(SELECT id FROM t_return WHERE k='ser_issue')))->>'inventory_transaction_id')::uuid;
SELECT results_eq($$SELECT serial_number,total_cost FROM inventory_transactions WHERE id=(SELECT id FROM t_return WHERE k='ser_return')$$,$$SELECT 'SER-B'::text,120::numeric$$,'Specific-ID customer return restores the sold serial and cost');
SELECT results_eq($$SELECT serial_number,qty_remaining,remaining_value FROM inventory_cost_layers WHERE origin_inventory_transaction_id=(SELECT id FROM t_return WHERE k='ser_b')$$,$$SELECT 'SER-B'::text,1::numeric,120::numeric$$,'Specific-ID source layer is available again');

-- Supplier return must select its receipt layer, even when that is not FIFO.
INSERT INTO t_return VALUES('sup_cheap',fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d4","qty":50,"unit_cost":10,"receipt_date":"2026-03-01","lot_number":"CHEAP"}'));
INSERT INTO t_return VALUES('sup_exact',fn_receive_inventory('{"company_id":"13700000-0000-0000-0000-0000000000c1","warehouse_id":"13700000-0000-0000-0000-0000000000a1","item_id":"13700000-0000-0000-0000-0000000000d4","qty":50,"unit_cost":20,"receipt_date":"2026-03-02","lot_number":"RETURN-ME"}'));
INSERT INTO t_return SELECT 'sup_return',(fn_issue_inventory_from_layer(jsonb_build_object('company_id','13700000-0000-0000-0000-0000000000c1','warehouse_id','13700000-0000-0000-0000-0000000000a1','item_id','13700000-0000-0000-0000-0000000000d4','qty',10,'inventory_cost_layer_id',(SELECT id FROM inventory_cost_layers WHERE origin_inventory_transaction_id=(SELECT id FROM t_return WHERE k='sup_exact'))))->>'inventory_transaction_id')::uuid;
SELECT is((SELECT ABS(total_cost) FROM inventory_transactions WHERE id=(SELECT id FROM t_return WHERE k='sup_return')),200::numeric,'supplier return uses exact referenced receipt layer, not FIFO head');
SELECT is((SELECT qty_remaining FROM inventory_cost_layers WHERE origin_inventory_transaction_id=(SELECT id FROM t_return WHERE k='sup_cheap')),50::numeric,'unreferenced older FIFO receipt remains untouched');
SELECT is((SELECT lot_number FROM inventory_transactions WHERE id=(SELECT id FROM t_return WHERE k='sup_return')),'RETURN-ME','supplier return evidence retains receipt lot');
SELECT throws_ok($$SELECT fn_issue_inventory_from_layer(jsonb_build_object('company_id','13700000-0000-0000-0000-0000000000c1','warehouse_id','13700000-0000-0000-0000-0000000000a1','item_id','13700000-0000-0000-0000-0000000000d4','qty',1))$$,'P0001','An exact receipt layer is required for this supplier return','layered supplier return cannot fall back to current FIFO');

SELECT is((SELECT count(*)::int FROM vw_inventory_valuation_reconciliation WHERE company_id='13700000-0000-0000-0000-0000000000c1' AND (ABS(quantity_variance)>0.0001 OR ABS(value_variance)>0.01)),0,'all returns reconcile stock projections to active layers');
SELECT ok(NOT has_function_privilege('authenticated','public.fn_return_inventory(jsonb)','EXECUTE') AND NOT has_function_privilege('authenticated','public.fn_issue_inventory_from_layer(jsonb)','EXECUTE'),'return costing helpers remain server-only authorities');

SELECT * FROM finish();
ROLLBACK;
