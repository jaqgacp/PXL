-- 135 — Production inventory costing authority
-- Proves WAC, FIFO allocation evidence/reversal, Specific-ID selection and
-- restoration, receipt dependency ordering, succession, and authority grants.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(25);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
  '13500000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
  'costing@test.local', '', now(), now(), now(),
  '{"provider":"email","providers":["email"]}', '{}');
SELECT set_config('request.jwt.claims',
  '{"sub":"13500000-0000-0000-0000-000000000001","role":"authenticated"}', true);

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
  tax_registration, accounting_period, address_line_1, address_line_2, city,
  province, zip_code, email, signatory_name, signatory_position, created_by, updated_by)
VALUES ('13500000-0000-0000-0000-0000000000c1', 'corporation',
  'Costing Proof Corp', 'Wholesale', '400-000-135-00000', 'vat', 'calendar',
  'C St', '', 'Makati', 'Metro Manila', '1200', 'costing@test.local',
  'Owner', 'President', auth.uid(), auth.uid());
INSERT INTO warehouses (id, company_id, warehouse_code, warehouse_name, created_by, updated_by)
VALUES
  ('13500000-0000-0000-0000-0000000000a1', '13500000-0000-0000-0000-0000000000c1', 'MAIN', 'Main', auth.uid(), auth.uid()),
  ('13500000-0000-0000-0000-0000000000a2', '13500000-0000-0000-0000-0000000000c1', 'OTHER', 'Other', auth.uid(), auth.uid());
INSERT INTO units_of_measure (id, company_id, uom_code, description, is_active, created_by, updated_by)
VALUES ('13500000-0000-0000-0000-0000000000b1', '13500000-0000-0000-0000-0000000000c1', 'EA', 'Each', true, auth.uid(), auth.uid());
INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by)
VALUES ('13500000-0000-0000-0000-0000000000ca', '13500000-0000-0000-0000-0000000000c1', 'GEN', 'General', auth.uid(), auth.uid());
INSERT INTO items (id, company_id, item_code, description, item_type, category_id,
  uom_id, costing_method, specific_id_tracking, created_by, updated_by)
VALUES
  ('13500000-0000-0000-0000-0000000000d1', '13500000-0000-0000-0000-0000000000c1', 'WAC', 'WAC Item', 'inventory_item', '13500000-0000-0000-0000-0000000000ca', '13500000-0000-0000-0000-0000000000b1', 'weighted_average', NULL, auth.uid(), auth.uid()),
  ('13500000-0000-0000-0000-0000000000d2', '13500000-0000-0000-0000-0000000000c1', 'FIFO', 'FIFO Item', 'inventory_item', '13500000-0000-0000-0000-0000000000ca', '13500000-0000-0000-0000-0000000000b1', 'fifo', NULL, auth.uid(), auth.uid()),
  ('13500000-0000-0000-0000-0000000000d3', '13500000-0000-0000-0000-0000000000c1', 'SERIAL', 'Serial Item', 'inventory_item', '13500000-0000-0000-0000-0000000000ca', '13500000-0000-0000-0000-0000000000b1', 'specific_identification', 'serial', auth.uid(), auth.uid());

CREATE TEMP TABLE t_cost (k TEXT PRIMARY KEY, id UUID);

-- WAC: 100@10 + 100@14 = 200 / 2,400 / 12; issue 50 = 600.
INSERT INTO t_cost VALUES ('wac_r1', fn_receive_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d1","qty":100,"unit_cost":10,"receipt_date":"2026-01-01","reference_doc_type":"TEST","reference_doc_id":"13500000-0000-0000-0000-000000000101"}'));
INSERT INTO t_cost VALUES ('wac_r2', fn_receive_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d1","qty":100,"unit_cost":14,"receipt_date":"2026-01-02","reference_doc_type":"TEST","reference_doc_id":"13500000-0000-0000-0000-000000000102"}'));
SELECT is((SELECT qty_on_hand FROM stock_balances WHERE item_id='13500000-0000-0000-0000-0000000000d1'), 200::numeric, 'WAC pool quantity is 200');
SELECT is((SELECT total_cost FROM stock_balances WHERE item_id='13500000-0000-0000-0000-0000000000d1'), 2400::numeric, 'WAC pool value is 2,400');
SELECT is((SELECT wac_unit_cost FROM stock_balances WHERE item_id='13500000-0000-0000-0000-0000000000d1'), 12::numeric, 'WAC rate is 12');
INSERT INTO t_cost
SELECT 'wac_i1', (fn_issue_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d1","qty":50,"transaction_date":"2026-01-03","reference_doc_type":"TEST","reference_doc_id":"13500000-0000-0000-0000-000000000103"}')->>'inventory_transaction_id')::uuid;
SELECT is((SELECT ABS(total_cost) FROM inventory_transactions WHERE id=(SELECT id FROM t_cost WHERE k='wac_i1')), 600::numeric, 'WAC issue costs 600');
SELECT results_eq(
  $$SELECT qty_on_hand, total_cost FROM stock_balances WHERE item_id='13500000-0000-0000-0000-0000000000d1'$$,
  $$VALUES (150::numeric, 1800::numeric)$$, 'WAC leaves 150 units valued at 1,800');
SELECT lives_ok(format($q$SELECT fn_reverse_inventory_issue(%L,'2026-01-04','TEST_VOID','13500000-0000-0000-0000-000000000103',NULL,NULL,'reverse WAC')$q$, (SELECT id FROM t_cost WHERE k='wac_i1')), 'WAC issue reverses from its historical cost');
SELECT results_eq(
  $$SELECT qty_on_hand, total_cost FROM stock_balances WHERE item_id='13500000-0000-0000-0000-0000000000d1'$$,
  $$VALUES (200::numeric, 2400::numeric)$$, 'WAC reversal restores quantity and value exactly');

-- FIFO: exact two-layer allocation and exact restoration.
INSERT INTO t_cost VALUES ('fifo_r1', fn_receive_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d2","qty":100,"unit_cost":10,"receipt_date":"2026-02-01","reference_doc_type":"RR","reference_doc_id":"13500000-0000-0000-0000-000000000201"}'));
INSERT INTO t_cost VALUES ('fifo_r2', fn_receive_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d2","qty":100,"unit_cost":14,"receipt_date":"2026-02-02","reference_doc_type":"RR","reference_doc_id":"13500000-0000-0000-0000-000000000202"}'));
INSERT INTO t_cost
SELECT 'fifo_i1', (fn_issue_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d2","qty":120,"transaction_date":"2026-02-03","reference_doc_type":"DR","reference_doc_id":"13500000-0000-0000-0000-000000000203"}')->>'inventory_transaction_id')::uuid;
SELECT is((SELECT ABS(total_cost) FROM inventory_transactions WHERE id=(SELECT id FROM t_cost WHERE k='fifo_i1')), 1280::numeric, 'FIFO issue costs 100x10 + 20x14 = 1,280');
SELECT is((SELECT count(*)::int FROM inventory_layer_allocations WHERE inventory_transaction_id=(SELECT id FROM t_cost WHERE k='fifo_i1') AND allocation_kind='consume'), 2, 'FIFO issue persists both consumed layers');
SELECT results_eq(
  $$SELECT qty_remaining, remaining_value FROM inventory_cost_layers WHERE origin_inventory_transaction_id=(SELECT id FROM t_cost WHERE k='fifo_r2')$$,
  $$VALUES (80::numeric, 1120::numeric)$$, 'FIFO second layer retains 80 units / 1,120');
SELECT throws_ok(format($q$SELECT fn_reverse_inventory_receipt(%L,'2026-02-04','RR_VOID','13500000-0000-0000-0000-000000000201',NULL,NULL,'unsafe')$q$, (SELECT id FROM t_cost WHERE k='fifo_r1')), '23514', NULL, 'FIFO receipt cancellation refuses a consumed source layer');
SELECT lives_ok(format($q$SELECT fn_reverse_inventory_issue(%L,'2026-02-04','DR_VOID','13500000-0000-0000-0000-000000000203',NULL,NULL,'restore layers')$q$, (SELECT id FROM t_cost WHERE k='fifo_i1')), 'FIFO issue reversal restores the exact consumed layers');
SELECT is((SELECT sum(qty_remaining) FROM inventory_cost_layers WHERE item_id='13500000-0000-0000-0000-0000000000d2' AND voided_by_inventory_transaction_id IS NULL), 200::numeric, 'FIFO reversal restores all 200 units to their original layers');
SELECT lives_ok(format($q$SELECT fn_reverse_inventory_receipt(%L,'2026-02-05','RR_VOID','13500000-0000-0000-0000-000000000201',NULL,NULL,'cancel first receipt')$q$, (SELECT id FROM t_cost WHERE k='fifo_r1')), 'FIFO receipt cancellation succeeds after downstream issue reversal');
SELECT results_eq(
  $$SELECT qty_on_hand, total_cost FROM stock_balances WHERE item_id='13500000-0000-0000-0000-0000000000d2'$$,
  $$VALUES (100::numeric, 1400::numeric)$$, 'FIFO cancellation leaves only the second receipt');
SELECT ok((SELECT is_exhausted AND qty_remaining=0 AND remaining_value=0 FROM inventory_cost_layers WHERE origin_inventory_transaction_id=(SELECT id FROM t_cost WHERE k='fifo_r1')), 'cancelled FIFO layer remains as exhausted audit evidence');

-- Specific ID: exact selected serial cost, tenant/location validation, and same identity restoration.
INSERT INTO t_cost VALUES ('ser_a', fn_receive_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d3","qty":1,"unit_cost":10000,"receipt_date":"2026-03-01","reference_doc_type":"RR","reference_doc_id":"13500000-0000-0000-0000-000000000301","serial_number":"UNIT-A"}'));
INSERT INTO t_cost VALUES ('ser_b', fn_receive_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d3","qty":1,"unit_cost":12000,"receipt_date":"2026-03-01","reference_doc_type":"RR","reference_doc_id":"13500000-0000-0000-0000-000000000302","serial_number":"UNIT-B"}'));
INSERT INTO t_cost VALUES ('ser_c', fn_receive_inventory('{"company_id":"13500000-0000-0000-0000-0000000000c1","warehouse_id":"13500000-0000-0000-0000-0000000000a1","item_id":"13500000-0000-0000-0000-0000000000d3","qty":1,"unit_cost":15000,"receipt_date":"2026-03-01","reference_doc_type":"RR","reference_doc_id":"13500000-0000-0000-0000-000000000303","serial_number":"UNIT-C"}'));
INSERT INTO t_cost
SELECT 'ser_i', (fn_issue_inventory(jsonb_build_object(
  'company_id','13500000-0000-0000-0000-0000000000c1','warehouse_id','13500000-0000-0000-0000-0000000000a1',
  'item_id','13500000-0000-0000-0000-0000000000d3','qty',1,'transaction_date','2026-03-02',
  'reference_doc_type','DR','reference_doc_id','13500000-0000-0000-0000-000000000304',
  'inventory_cost_layer_id',(SELECT id FROM inventory_cost_layers WHERE serial_number='UNIT-B')))->>'inventory_transaction_id')::uuid;
SELECT is((SELECT ABS(total_cost) FROM inventory_transactions WHERE id=(SELECT id FROM t_cost WHERE k='ser_i')), 12000::numeric, 'selling Unit B uses Unit B cost, 12,000');
SELECT is((SELECT serial_number FROM inventory_transactions WHERE id=(SELECT id FROM t_cost WHERE k='ser_i')), 'UNIT-B', 'outbound evidence stamps the selected serial');
SELECT throws_ok(
  $$SELECT fn_issue_inventory(jsonb_build_object('company_id','13500000-0000-0000-0000-0000000000c1','warehouse_id','13500000-0000-0000-0000-0000000000a2','item_id','13500000-0000-0000-0000-0000000000d3','qty',1,'inventory_cost_layer_id',(SELECT id FROM inventory_cost_layers WHERE serial_number='UNIT-A')))$$,
  '23514', NULL, 'Specific-ID refuses a layer from the wrong warehouse');
SELECT throws_ok(
  $$SELECT fn_issue_inventory(jsonb_build_object('company_id','13500000-0000-0000-0000-0000000000c1','warehouse_id','13500000-0000-0000-0000-0000000000a1','item_id','13500000-0000-0000-0000-0000000000d3','qty',1,'inventory_cost_layer_id',(SELECT layer_id FROM inventory_layer_allocations WHERE inventory_transaction_id=(SELECT id FROM t_cost WHERE k='ser_i') AND allocation_kind='consume')))$$,
  '23514', NULL, 'Specific-ID refuses an already-consumed serial');
SELECT lives_ok(format($q$SELECT fn_reverse_inventory_issue(%L,'2026-03-03','DR_VOID','13500000-0000-0000-0000-000000000304',NULL,NULL,'restore Unit B')$q$, (SELECT id FROM t_cost WHERE k='ser_i')), 'Specific-ID issue reverses');
SELECT results_eq(
  $$SELECT serial_number, qty_remaining, remaining_value FROM inventory_cost_layers WHERE serial_number='UNIT-B'$$,
  $$VALUES ('UNIT-B'::text, 1::numeric, 12000::numeric)$$,
  'the same Unit B identity and carrying value are restored');

SELECT throws_ok(
  $$UPDATE items SET costing_method='weighted_average' WHERE id='13500000-0000-0000-0000-0000000000d2'$$,
  '23514', NULL, 'costing method cannot be reinterpreted after activity');
SELECT ok(
  NOT has_function_privilege('authenticated','public.fn_issue_inventory(jsonb)','EXECUTE')
  AND NOT has_function_privilege('anon','public.fn_issue_inventory(jsonb)','EXECUTE')
  AND NOT has_table_privilege('authenticated','public.stock_balances','INSERT')
  AND NOT has_table_privilege('authenticated','public.inventory_cost_layers','UPDATE'),
  'costing helpers and inventory projections are not browser write authorities');
SELECT is((SELECT count(*)::int FROM inventory_events), 0, 'dormant IA-5 inventory_events remain untouched');

SELECT * FROM finish();
ROLLBACK;
