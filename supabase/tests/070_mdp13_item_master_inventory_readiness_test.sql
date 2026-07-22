-- ══════════════════════════════════════════════════════════════════════════════
-- MDP-13 — Item Master Inventory Readiness (gaps MD-21, MD-22, MD-23, MD-24)
--
-- Proves the item-master readiness backend: company inventory defaults (costing /
-- negative-stock / default warehouse) with provision + validate + guard; item-level
-- overrides + reorder fields + preferred supplier + serial/batch flags with
-- effective-policy resolvers; item UOM conversions; item barcodes and media — each
-- company-isolated, audited, member/admin-gated, rollback-safe.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(41);

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
SELECT '00000000-0000-0000-0000-000000000000', u.id,
       'authenticated', 'authenticated', u.email, '',
       now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}'
FROM (VALUES
  ('11111111-1111-1111-1111-1111111110d1'::uuid, 'mdp13-admin@test.local'),
  ('11111111-1111-1111-1111-1111111110d2'::uuid, 'mdp13-member@test.local'),
  ('11111111-1111-1111-1111-1111111110d3'::uuid, 'mdp13-outsider@test.local')
) AS u(id, email);

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('22222222-2222-2222-2222-2222222211d1', 'corporation',
   'MDP13 Alpha Corp', 'Wholesale', '311-222-813-00000',
   'vat', 'calendar', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp13-admin@test.local', 'A Owner', 'President',
   '11111111-1111-1111-1111-1111111110d1', '11111111-1111-1111-1111-1111111110d1'),
  ('22222222-2222-2222-2222-2222222211d2', 'corporation',
   'MDP13 Beta Corp', 'Services', '311-222-814-00000',
   'vat', 'calendar', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'mdp13-admin@test.local', 'B Owner', 'President',
   '11111111-1111-1111-1111-1111111110d1', '11111111-1111-1111-1111-1111111110d1');
INSERT INTO user_company_memberships (user_id, company_id, role) VALUES
  ('11111111-1111-1111-1111-1111111110d1', '22222222-2222-2222-2222-2222222211d1', 'admin'),
  ('11111111-1111-1111-1111-1111111110d1', '22222222-2222-2222-2222-2222222211d2', 'admin'),
  ('11111111-1111-1111-1111-1111111110d2', '22222222-2222-2222-2222-2222222211d1', 'member');

-- Warehouses (A + B), item category (A), suppliers (A + B).
INSERT INTO warehouses (id, company_id, warehouse_code, warehouse_name, created_by, updated_by) VALUES
  ('33333333-3333-3333-3333-3333333300a1','22222222-2222-2222-2222-2222222211d1','WH1','Main WH',
   '11111111-1111-1111-1111-1111111110d1','11111111-1111-1111-1111-1111111110d1'),
  ('33333333-3333-3333-3333-3333333300b1','22222222-2222-2222-2222-2222222211d2','WHB','Beta WH',
   '11111111-1111-1111-1111-1111111110d1','11111111-1111-1111-1111-1111111110d1');
INSERT INTO item_categories (id, company_id, category_code, category_name, created_by, updated_by) VALUES
  ('44444444-0000-0000-0000-0000000000c1','22222222-2222-2222-2222-2222222211d1','CAT1','General',
   '11111111-1111-1111-1111-1111111110d1','11111111-1111-1111-1111-1111111110d1');
INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin, registered_address, created_by, updated_by) VALUES
  ('44444444-0000-0000-0000-0000000000a1','22222222-2222-2222-2222-2222222211d1','SUP-A','Alpha Supplier','111-222-333-000','Addr',
   '11111111-1111-1111-1111-1111111110d1','11111111-1111-1111-1111-1111111110d1'),
  ('44444444-0000-0000-0000-0000000000b1','22222222-2222-2222-2222-2222222211d2','SUP-B','Beta Supplier','111-222-444-000','Addr',
   '11111111-1111-1111-1111-1111111110d1','11111111-1111-1111-1111-1111111110d1');

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110d1');

-- Seed company UOM sets (admin-gated), then grab codes.
SELECT fn_seed_company_uom('22222222-2222-2222-2222-2222222211d1');
SELECT fn_seed_company_uom('22222222-2222-2222-2222-2222222211d2');

-- Items: I1 (no costing/policy override), I2 (fifo override).
INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id, created_by, updated_by)
VALUES ('44444444-0000-0000-0000-00000000a001','22222222-2222-2222-2222-2222222211d1','ITEM-1','Widget','inventory_item',
        '44444444-0000-0000-0000-0000000000c1',
        (SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d1' AND uom_code='PCS'),
        '11111111-1111-1111-1111-1111111110d1','11111111-1111-1111-1111-1111111110d1');
INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id, costing_method, created_by, updated_by)
VALUES ('44444444-0000-0000-0000-00000000a002','22222222-2222-2222-2222-2222222211d1','ITEM-2','Gadget','inventory_item',
        '44444444-0000-0000-0000-0000000000c1',
        (SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d1' AND uom_code='PCS'),
        'fifo','11111111-1111-1111-1111-1111111110d1','11111111-1111-1111-1111-1111111110d1');

-- ── Schema presence ───────────────────────────────────────────────────────────
SELECT has_table('company_inventory_config');
SELECT has_table('item_uom_conversions');
SELECT has_table('item_barcodes');
SELECT has_table('item_media');
SELECT has_column('items','negative_stock_policy');
SELECT has_column('items','preferred_supplier_id');
SELECT has_column('items','track_serial');

-- ── Company inventory config (MD-21 / MD-22) ──────────────────────────────────
SELECT ok(fn_provision_company_inventory_config('22222222-2222-2222-2222-2222222211d1') IS NOT NULL,
  'provisioning returns the inventory-config id');
SELECT results_eq(
  $q$SELECT default_costing_method, negative_stock_policy FROM company_inventory_config
     WHERE company_id='22222222-2222-2222-2222-2222222211d1'$q$,
  $$VALUES ('weighted_average'::text, 'block'::text)$$,
  'company defaults: weighted_average costing + block negative stock');
SELECT is(
  (SELECT w.warehouse_code FROM company_inventory_config cic JOIN warehouses w ON w.id=cic.default_warehouse_id
   WHERE cic.company_id='22222222-2222-2222-2222-2222222211d1'),
  'WH1', 'provisioning sets the default warehouse to the company active warehouse');
SELECT is(
  fn_provision_company_inventory_config('22222222-2222-2222-2222-2222222211d1'),
  (SELECT id FROM company_inventory_config WHERE company_id='22222222-2222-2222-2222-2222222211d1'),
  're-provisioning is idempotent (same id)');
SELECT is(
  (SELECT count(*)::int FROM fn_validate_company_inventory_config('22222222-2222-2222-2222-2222222211d1')),
  0, 'a provisioned inventory config validates clean');
SELECT ok(
  EXISTS (SELECT 1 FROM fn_validate_company_inventory_config('22222222-2222-2222-2222-2222222211d2') WHERE check_code='config_missing'),
  'validation reports a missing inventory config');
SELECT throws_ok(
  $q$UPDATE company_inventory_config SET default_warehouse_id='33333333-3333-3333-3333-3333333300b1'
     WHERE company_id='22222222-2222-2222-2222-2222222211d1'$q$,
  '23514', NULL, 'default warehouse must belong to the same company (guard)');

-- ── Effective-policy resolvers (MD-21 / MD-22) ────────────────────────────────
SELECT is(fn_item_costing_method('44444444-0000-0000-0000-00000000a001'), 'weighted_average',
  'costing resolver falls back to the company default for an unset item');
SELECT is(fn_item_costing_method('44444444-0000-0000-0000-00000000a002'), 'fifo',
  'costing resolver honors an item-level override');
SELECT is(fn_item_negative_stock_policy('44444444-0000-0000-0000-00000000a001'), 'block',
  'negative-stock resolver falls back to the company default');
UPDATE company_inventory_config SET negative_stock_policy='allow' WHERE company_id='22222222-2222-2222-2222-2222222211d1';
SELECT is(fn_item_negative_stock_policy('44444444-0000-0000-0000-00000000a001'), 'allow',
  'negative-stock resolver reflects the updated company default');
UPDATE items SET negative_stock_policy='warn' WHERE id='44444444-0000-0000-0000-00000000a001';
SELECT is(fn_item_negative_stock_policy('44444444-0000-0000-0000-00000000a001'), 'warn',
  'negative-stock resolver honors an item-level override');

-- ── Item field constraints + reference guard ──────────────────────────────────
SELECT throws_ok(
  $q$UPDATE items SET negative_stock_policy='invalid' WHERE id='44444444-0000-0000-0000-00000000a002'$q$,
  '23514', NULL, 'items.negative_stock_policy vocabulary is enforced');
SELECT throws_ok(
  $q$UPDATE items SET safety_stock=-1 WHERE id='44444444-0000-0000-0000-00000000a002'$q$,
  '23514', NULL, 'reorder fields must be non-negative');
SELECT throws_ok(
  $q$UPDATE items SET preferred_supplier_id='44444444-0000-0000-0000-0000000000b1' WHERE id='44444444-0000-0000-0000-00000000a001'$q$,
  '23514', NULL, 'preferred supplier must belong to the same company (guard)');
SELECT lives_ok(
  $q$UPDATE items SET preferred_supplier_id='44444444-0000-0000-0000-0000000000a1' WHERE id='44444444-0000-0000-0000-00000000a001'$q$,
  'a same-company preferred supplier is accepted');

-- ── Item UOM conversions (MD-23) ──────────────────────────────────────────────
INSERT INTO item_uom_conversions (company_id, item_id, uom_id, factor_to_base)
VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001',
        (SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d1' AND uom_code='BOX'), 12);
SELECT is(
  (SELECT count(*)::int FROM item_uom_conversions WHERE item_id='44444444-0000-0000-0000-00000000a001'),
  1, 'an item UOM conversion is stored');
SELECT throws_ok(
  $q$INSERT INTO item_uom_conversions (company_id, item_id, uom_id, factor_to_base)
     VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001',
       (SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d1' AND uom_code='BOX'), 6)$q$,
  '23505', NULL, 'a UOM can be converted only once per item');
SELECT throws_ok(
  $q$INSERT INTO item_uom_conversions (company_id, item_id, uom_id, factor_to_base)
     VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001',
       (SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d1' AND uom_code='PACK'), 0)$q$,
  '23514', NULL, 'the conversion factor must be positive');
SELECT throws_ok(
  $q$INSERT INTO item_uom_conversions (company_id, item_id, uom_id, factor_to_base)
     VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001',
       (SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d2' AND uom_code='BOX'), 12)$q$,
  '23514', NULL, 'a cross-company UOM is rejected by the child guard');
-- Company guard derives company_id from the item when omitted.
INSERT INTO item_uom_conversions (item_id, uom_id, factor_to_base)
VALUES ('44444444-0000-0000-0000-00000000a001',
        (SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d1' AND uom_code='DOZEN'), 12);
SELECT is(
  (SELECT company_id FROM item_uom_conversions
   WHERE item_id='44444444-0000-0000-0000-00000000a001'
     AND uom_id=(SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d1' AND uom_code='DOZEN')),
  '22222222-2222-2222-2222-2222222211d1'::uuid,
  'the child guard derives company_id from the parent item');

-- ── Item barcodes (MD-24) ─────────────────────────────────────────────────────
INSERT INTO item_barcodes (company_id, item_id, barcode, is_primary)
VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001','BC-001', true);
SELECT is(
  (SELECT count(*)::int FROM item_barcodes WHERE item_id='44444444-0000-0000-0000-00000000a001'),
  1, 'an item barcode is stored');
SELECT throws_ok(
  $q$INSERT INTO item_barcodes (company_id, item_id, barcode, is_primary)
     VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001','BC-002', true)$q$,
  '23505', NULL, 'at most one primary barcode per item');
SELECT throws_ok(
  $q$INSERT INTO item_barcodes (company_id, item_id, barcode)
     VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a002','BC-001')$q$,
  '23505', NULL, 'a barcode is unique per company');

-- ── Item media (MD-24) ────────────────────────────────────────────────────────
INSERT INTO item_media (company_id, item_id, url, is_primary)
VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001','s3://img/1.png', true);
SELECT is(
  (SELECT count(*)::int FROM item_media WHERE item_id='44444444-0000-0000-0000-00000000a001'),
  1, 'item media is stored');
SELECT throws_ok(
  $q$INSERT INTO item_media (company_id, item_id, url, is_primary)
     VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001','s3://img/2.png', true)$q$,
  '23505', NULL, 'at most one primary media per item');

-- ── Audit coverage ────────────────────────────────────────────────────────────
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs WHERE table_name='company_inventory_config' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-2222222211d1') >= 1,
  'inventory-config creation is audited');
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs WHERE table_name='item_barcodes' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-2222222211d1') >= 1,
  'item-barcode creation is audited');
SELECT ok(
  (SELECT count(*)::int FROM sys_audit_logs WHERE table_name='item_uom_conversions' AND action='INSERT'
     AND company_id='22222222-2222-2222-2222-2222222211d1') >= 1,
  'item-uom-conversion creation is audited');

-- ── Rollback safety ───────────────────────────────────────────────────────────
SAVEPOINT sp_iuc;
INSERT INTO item_uom_conversions (company_id, item_id, uom_id, factor_to_base)
VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a002',
        (SELECT id FROM units_of_measure WHERE company_id='22222222-2222-2222-2222-2222222211d1' AND uom_code='BOX'), 24);
SELECT is(
  (SELECT count(*)::int FROM item_uom_conversions WHERE item_id='44444444-0000-0000-0000-00000000a002'),
  1, 'conversion present inside the savepoint');
ROLLBACK TO SAVEPOINT sp_iuc;
SELECT is(
  (SELECT count(*)::int FROM item_uom_conversions WHERE item_id='44444444-0000-0000-0000-00000000a002'),
  0, 'rolling back removes the row (atomic)');

-- ── Authority (admin vs member vs non-member) ─────────────────────────────────
SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110d2');  -- member of A
SELECT throws_ok(
  $q$SELECT fn_provision_company_inventory_config('22222222-2222-2222-2222-2222222211d1')$q$,
  '42501', NULL, 'a non-admin member cannot provision inventory config');
SELECT lives_ok(
  $q$INSERT INTO item_barcodes (company_id, item_id, barcode)
     VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001','BC-MEM')$q$,
  'a company member can add an item barcode');

SELECT pg_temp.as_user('11111111-1111-1111-1111-1111111110d3');  -- outsider
SELECT throws_ok(
  $q$INSERT INTO item_barcodes (company_id, item_id, barcode)
     VALUES ('22222222-2222-2222-2222-2222222211d1','44444444-0000-0000-0000-00000000a001','BC-OUT')$q$,
  NULL, NULL, 'a non-member cannot add an item barcode');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
