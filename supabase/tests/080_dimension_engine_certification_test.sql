-- ══════════════════════════════════════════════════════════════════════════════
-- DIM-ENGINE-CERT-001 — Dimension Engine certification regression
--
-- Permanent cross-transaction protection for the Dimension Engine. Proves that
-- every implemented, dimension-bearing posting transaction propagates all six
-- governed dimensions (branch, department, cost_center, project, location,
-- functional_entity) to the posted journal lines, that reversal preserves them,
-- that the dimensional GL report reconciles without double counting, and that
-- cross-company / hierarchy violations are rejected.
--
-- Covers: Manual Journal, Vendor Bill (via the P3A push helper fn_add_posting_line), Goods Issue,
-- Fixed Asset acquisition + depreciation, reversal, GL propagation, dimension
-- validation, cross-company rejection, hierarchy rejection, reconciliation, and
-- non-double-counting.
-- ══════════════════════════════════════════════════════════════════════════════
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(43);

-- ── User ────────────────────────────────────────────────────────────────────────
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000',
        '11110000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
        'dimcert-owner@test.local', '', now(), now(), now(),
        '{"provider":"email","providers":["email"]}', '{}');

CREATE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid) TO authenticated;

-- Claims set early so auth.uid() drives created_by + the creator-owner trigger.
SELECT pg_temp.as_user('11110000-0000-0000-0000-000000000001');

-- ── Companies A + B (creator becomes owner via trg_company_creator_owner) ────────
INSERT INTO companies (id, entity_type, registered_name, line_of_business, tin,
                       tax_registration, accounting_period,
                       address_line_1, address_line_2, city, province, zip_code,
                       email, signatory_name, signatory_position, created_by, updated_by)
VALUES
  ('2222aaaa-0000-0000-0000-000000000001', 'corporation', 'DimCert Alpha Corp',
   'Manufacturing', '331-000-001-00000', 'vat', 'calendar',
   'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   'dimcert-owner@test.local', 'A Owner', 'President',
   '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('2222bbbb-0000-0000-0000-000000000001', 'corporation', 'DimCert Beta Corp',
   'Trading', '331-000-002-00000', 'vat', 'calendar',
   'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   'dimcert-owner@test.local', 'B Owner', 'President',
   '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001');

INSERT INTO branches (id, company_id, branch_code, branch_name,
                      address_line_1, address_line_2, city, province, zip_code, created_by, updated_by)
VALUES
  ('3333aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001',
   'HO', 'Head Office', 'A St', 'A Bldg', 'Makati', 'Metro Manila', '1200',
   '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('3333bbbb-0000-0000-0000-000000000001', '2222bbbb-0000-0000-0000-000000000001',
   'HO', 'Head Office', 'B St', 'B Bldg', 'Makati', 'Metro Manila', '1200',
   '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001');

-- ── Governed dimensions for A and B ─────────────────────────────────────────────
INSERT INTO departments (id, company_id, department_code, department_name, created_by, updated_by) VALUES
  ('4444aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'FIN', 'Finance', '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('4444bbbb-0000-0000-0000-000000000001', '2222bbbb-0000-0000-0000-000000000001', 'OPS', 'Ops',     '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001');
INSERT INTO cost_centers (id, company_id, cost_center_code, cost_center_name, created_by, updated_by) VALUES
  ('5555aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'CC-A', 'Admin CC', '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('5555bbbb-0000-0000-0000-000000000001', '2222bbbb-0000-0000-0000-000000000001', 'CC-B', 'Beta CC',  '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001');
INSERT INTO projects (id, company_id, branch_id, project_code, project_name) VALUES
  ('6666aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', '3333aaaa-0000-0000-0000-000000000001', 'PRJ-A', 'Alpha Project'),
  ('6666bbbb-0000-0000-0000-000000000001', '2222bbbb-0000-0000-0000-000000000001', NULL, 'PRJ-B', 'Beta Project');
INSERT INTO locations (id, company_id, location_code, location_name) VALUES
  ('7777aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'LOC-A', 'Alpha Site'),
  ('7777bbbb-0000-0000-0000-000000000001', '2222bbbb-0000-0000-0000-000000000001', 'LOC-B', 'Beta Site');
INSERT INTO functional_entities (id, company_id, entity_code, entity_name) VALUES
  ('8888aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'FE-A', 'Alpha Segment'),
  ('8888bbbb-0000-0000-0000-000000000001', '2222bbbb-0000-0000-0000-000000000001', 'FE-B', 'Beta Segment');

-- ── Chart of accounts for A ─────────────────────────────────────────────────────
INSERT INTO chart_of_accounts (id, company_id, account_code, account_name, account_type, normal_balance, is_postable, is_active, created_by, updated_by) VALUES
  ('9999aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', '6010', 'Supplies Expense',     'expense',   'debit',  true, true, '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('9999aaaa-0000-0000-0000-000000000002', '2222aaaa-0000-0000-0000-000000000001', '1010', 'Cash',                 'asset',     'debit',  true, true, '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('9999aaaa-0000-0000-0000-000000000003', '2222aaaa-0000-0000-0000-000000000001', '1500', 'Machinery',            'asset',     'debit',  true, true, '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('9999aaaa-0000-0000-0000-000000000004', '2222aaaa-0000-0000-0000-000000000001', '6020', 'Depreciation Expense', 'expense',   'debit',  true, true, '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('9999aaaa-0000-0000-0000-000000000005', '2222aaaa-0000-0000-0000-000000000001', '1510', 'Accum Depreciation',   'asset',     'credit', true, true, '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('9999aaaa-0000-0000-0000-000000000006', '2222aaaa-0000-0000-0000-000000000001', '1300', 'Inventory',            'asset',     'debit',  true, true, '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('9999aaaa-0000-0000-0000-000000000007', '2222aaaa-0000-0000-0000-000000000001', '5010', 'COGS',                 'expense',   'debit',  true, true, '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'),
  ('9999aaaa-0000-0000-0000-000000000008', '2222aaaa-0000-0000-0000-000000000001', '2010', 'Accounts Payable',     'liability', 'credit', true, true, '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001');

-- ── Fiscal calendar + JE/FA numbering for A ─────────────────────────────────────
INSERT INTO fiscal_years (id, company_id, year_name, start_date, end_date, is_calendar)
VALUES ('aaaa0001-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'FY2026', '2026-01-01', '2026-12-31', true);
INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number, period_name, start_date, end_date, is_locked)
SELECT '2222aaaa-0000-0000-0000-000000000001', 'aaaa0001-0000-0000-0000-000000000001',
       m, to_char(make_date(2026, m, 1), 'Mon YYYY'),
       make_date(2026, m, 1),
       (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date, false
FROM generate_series(1, 12) AS m;

INSERT INTO number_series (company_id, branch_id, document_type_id, prefix, number_length, starting_number, next_number, is_active, created_by, updated_by)
SELECT '2222aaaa-0000-0000-0000-000000000001', '3333aaaa-0000-0000-0000-000000000001',
       rdt.id, rdt.document_code || '-2026-', 6, 1, 1, true,
       '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001'
FROM ref_document_types rdt WHERE rdt.document_code IN ('JE', 'FA');

-- ── Inventory masters + stock for Goods Issue ───────────────────────────────────
INSERT INTO item_categories (id, company_id, category_code, category_name)
VALUES ('cccc0001-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'CAT', 'General');
INSERT INTO units_of_measure (id, company_id, uom_code, description)
VALUES ('aaaa0002-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'PC', 'Piece');
INSERT INTO warehouses (id, company_id, warehouse_code, warehouse_name, branch_id, created_by, updated_by)
VALUES ('dddd0001-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'WH1', 'Main WH',
        '3333aaaa-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001');
INSERT INTO items (id, company_id, item_code, description, item_type, category_id, uom_id,
                   inventory_account_id, cogs_account_id, costing_method, created_by, updated_by)
VALUES ('eeee0001-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001',
        'ITEM-1', 'Test Item', 'inventory_item',
        'cccc0001-0000-0000-0000-000000000001', 'aaaa0002-0000-0000-0000-000000000001',
        '9999aaaa-0000-0000-0000-000000000006', '9999aaaa-0000-0000-0000-000000000007',
        'weighted_average', '11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001');
INSERT INTO stock_balances (company_id, warehouse_id, item_id, qty_on_hand, wac_unit_cost, total_cost)
VALUES ('2222aaaa-0000-0000-0000-000000000001', 'dddd0001-0000-0000-0000-000000000001',
        'eeee0001-0000-0000-0000-000000000001', 100, 50, 5000);

-- ── Fixed Asset category with GL accounts ───────────────────────────────────────
INSERT INTO fixed_asset_categories (id, company_id, category_code, category_name,
                                    gl_asset_account_id, gl_depr_expense_account_id, gl_accum_depr_account_id)
VALUES ('faca0001-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'MACH', 'Machinery',
        '9999aaaa-0000-0000-0000-000000000003', '9999aaaa-0000-0000-0000-000000000004', '9999aaaa-0000-0000-0000-000000000005');

-- ── Supplier + Vendor Bill (dimension source the Section C push reads from) ─────
INSERT INTO suppliers (id, company_id, supplier_code, registered_name, tin, registered_address)
VALUES ('bbbb0001-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', 'SUP-1', 'Supplier One', '444-000-001-00000', 'Supplier Addr');
INSERT INTO vendor_bills (id, company_id, branch_id, supplier_id, supplier_name_snapshot, bill_number, bill_date,
                          department_id, cost_center_id, project_id, location_id, functional_entity_id)
VALUES ('bbbb0002-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001', '3333aaaa-0000-0000-0000-000000000001',
        'bbbb0001-0000-0000-0000-000000000001', 'Supplier One', 'VB-0001', '2026-05-10',
        '4444aaaa-0000-0000-0000-000000000001', '5555aaaa-0000-0000-0000-000000000001',
        '6666aaaa-0000-0000-0000-000000000001', '7777aaaa-0000-0000-0000-000000000001', '8888aaaa-0000-0000-0000-000000000001');

-- Draft VB journal (created here as the privileged setup role; journal_entries are
-- otherwise only created by the SECURITY DEFINER posting RPCs). Section C then calls
-- the governed fn_add_posting_line against it as the authenticated member.
CREATE TEMP TABLE t_ctx (key text PRIMARY KEY, id uuid);
GRANT SELECT, INSERT ON t_ctx TO authenticated;

INSERT INTO t_ctx
SELECT 'vb_probe_je', fn_create_posted_journal_entry(
  '2222aaaa-0000-0000-0000-000000000001',
  '3333aaaa-0000-0000-0000-000000000001',
  'VBJE-0001', '2026-05-10', 'Vendor Bill dimension push probe',
  'VB', 'bbbb0002-0000-0000-0000-000000000001',
  (SELECT id FROM fiscal_periods
    WHERE company_id='2222aaaa-0000-0000-0000-000000000001'
      AND period_number=5),
  'draft', 0, 0, NULL, 'regular', false, false, true
);

-- ══════════════════════════════════════════════════════════════════════════════
-- All operations below run as the authenticated member of both companies.
-- ══════════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11110000-0000-0000-0000-000000000001');

-- ── SECTION A — Manual Journal carries all six dimensions onto the GL ───────────
INSERT INTO t_ctx SELECT 'mje1', fn_post_manual_je(
  '2222aaaa-0000-0000-0000-000000000001', '3333aaaa-0000-0000-0000-000000000001',
  '2026-05-12', 'Dimensioned supplies accrual', NULL, false,
  jsonb_build_array(
    jsonb_build_object('account_id','9999aaaa-0000-0000-0000-000000000001','debit_amount',1000,
      'department_id','4444aaaa-0000-0000-0000-000000000001',
      'cost_center_id','5555aaaa-0000-0000-0000-000000000001',
      'project_id','6666aaaa-0000-0000-0000-000000000001',
      'location_id','7777aaaa-0000-0000-0000-000000000001',
      'functional_entity_id','8888aaaa-0000-0000-0000-000000000001'),
    jsonb_build_object('account_id','9999aaaa-0000-0000-0000-000000000002','credit_amount',1000)
  ));

SELECT is((SELECT branch_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje1') AND line_number=1),
  '3333aaaa-0000-0000-0000-000000000001'::uuid, 'MJE line inherits the header branch');
SELECT is((SELECT department_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje1') AND line_number=1),
  '4444aaaa-0000-0000-0000-000000000001'::uuid, 'MJE line carries department');
SELECT is((SELECT cost_center_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje1') AND line_number=1),
  '5555aaaa-0000-0000-0000-000000000001'::uuid, 'MJE line carries cost center');
SELECT is((SELECT project_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje1') AND line_number=1),
  '6666aaaa-0000-0000-0000-000000000001'::uuid, 'MJE line carries project');
SELECT is((SELECT location_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje1') AND line_number=1),
  '7777aaaa-0000-0000-0000-000000000001'::uuid, 'MJE line carries location');
SELECT is((SELECT functional_entity_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje1') AND line_number=1),
  '8888aaaa-0000-0000-0000-000000000001'::uuid, 'MJE line carries functional entity');
SELECT is((SELECT project_id FROM vw_general_ledger WHERE je_id=(SELECT id FROM t_ctx WHERE key='mje1') AND line_number=1),
  '6666aaaa-0000-0000-0000-000000000001'::uuid, 'vw_general_ledger exposes the line project');
SELECT ok(EXISTS(SELECT 1 FROM vw_gl_dimension_summary
   WHERE company_id='2222aaaa-0000-0000-0000-000000000001' AND project_id='6666aaaa-0000-0000-0000-000000000001'),
  'vw_gl_dimension_summary aggregates a row for the project dimension');

-- ── SECTION B — Reversal preserves all six dimensions ───────────────────────────
INSERT INTO t_ctx SELECT 'mje2', fn_post_manual_je(
  '2222aaaa-0000-0000-0000-000000000001', '3333aaaa-0000-0000-0000-000000000001',
  '2026-05-13', 'Reversible dimensioned entry', NULL, false,
  jsonb_build_array(
    jsonb_build_object('account_id','9999aaaa-0000-0000-0000-000000000001','debit_amount',500,
      'department_id','4444aaaa-0000-0000-0000-000000000001',
      'cost_center_id','5555aaaa-0000-0000-0000-000000000001',
      'project_id','6666aaaa-0000-0000-0000-000000000001',
      'location_id','7777aaaa-0000-0000-0000-000000000001',
      'functional_entity_id','8888aaaa-0000-0000-0000-000000000001'),
    jsonb_build_object('account_id','9999aaaa-0000-0000-0000-000000000002','credit_amount',500)
  ));
INSERT INTO t_ctx SELECT 'rev', fn_reverse_je((SELECT id FROM t_ctx WHERE key='mje2'), '2026-05-20');

SELECT is((SELECT department_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='rev') AND line_number=1),
  '4444aaaa-0000-0000-0000-000000000001'::uuid, 'reversal line preserves department');
SELECT is((SELECT cost_center_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='rev') AND line_number=1),
  '5555aaaa-0000-0000-0000-000000000001'::uuid, 'reversal line preserves cost center');
SELECT is((SELECT project_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='rev') AND line_number=1),
  '6666aaaa-0000-0000-0000-000000000001'::uuid, 'reversal line preserves project');
SELECT is((SELECT location_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='rev') AND line_number=1),
  '7777aaaa-0000-0000-0000-000000000001'::uuid, 'reversal line preserves location');
SELECT is((SELECT functional_entity_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='rev') AND line_number=1),
  '8888aaaa-0000-0000-0000-000000000001'::uuid, 'reversal line preserves functional entity');
SELECT is((SELECT branch_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='rev') AND line_number=1),
  '3333aaaa-0000-0000-0000-000000000001'::uuid, 'reversal line preserves branch');

-- ── SECTION C — Vendor Bill dimensions reach the line through the P3A push ──────
-- Posting Engine P3A (frozen PXL_POSTING_ENGINE_P3_SPEC.md §3) retired the helper's
-- source pull: the document writer now owns dimension resolution and pushes all six
-- governed dimensions, and fn_add_posting_line persists exactly what it is handed.
-- The bill's own header dimensions are read here and pushed, mirroring what
-- fn_post_vendor_bill does; the end-to-end writer proof lives in test 087.
--
-- This one call runs with the OWNER's privilege, not the member's, because that is how
-- the real caller invokes it: fn_post_vendor_bill is SECURITY DEFINER, so the helper
-- executes as the function owner. Posting Engine P5.0 revoked the helper's
-- `authenticated` EXECUTE grant (it is engine-internal and has no client caller), so
-- simulating the writer from the member role would test a path that does not exist.
-- The dimension assertions below are unchanged and unweakened.
RESET ROLE;
SELECT fn_add_posting_line((SELECT id FROM t_ctx WHERE key='vb_probe_je'), 1,
  '9999aaaa-0000-0000-0000-000000000001', 'Bill expense', 1000, 0,
  '3333aaaa-0000-0000-0000-000000000001',
  (SELECT department_id        FROM vendor_bills WHERE id='bbbb0002-0000-0000-0000-000000000001'),
  (SELECT cost_center_id       FROM vendor_bills WHERE id='bbbb0002-0000-0000-0000-000000000001'),
  (SELECT project_id           FROM vendor_bills WHERE id='bbbb0002-0000-0000-0000-000000000001'),
  (SELECT location_id          FROM vendor_bills WHERE id='bbbb0002-0000-0000-0000-000000000001'),
  (SELECT functional_entity_id FROM vendor_bills WHERE id='bbbb0002-0000-0000-0000-000000000001'));
-- Back to the member identity for the remaining end-user assertions.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('11110000-0000-0000-0000-000000000001');

SELECT is((SELECT department_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='vb_probe_je') AND line_number=1),
  '4444aaaa-0000-0000-0000-000000000001'::uuid, 'VB posting line carries the bill department');
SELECT is((SELECT cost_center_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='vb_probe_je') AND line_number=1),
  '5555aaaa-0000-0000-0000-000000000001'::uuid, 'VB posting line carries the bill cost center');
SELECT is((SELECT project_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='vb_probe_je') AND line_number=1),
  '6666aaaa-0000-0000-0000-000000000001'::uuid, 'VB posting line carries the bill project');
SELECT is((SELECT location_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='vb_probe_je') AND line_number=1),
  '7777aaaa-0000-0000-0000-000000000001'::uuid, 'VB posting line carries the bill location');
SELECT is((SELECT functional_entity_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='vb_probe_je') AND line_number=1),
  '8888aaaa-0000-0000-0000-000000000001'::uuid, 'VB posting line carries the bill functional entity');

-- ── SECTION D — Goods Issue propagates dept/cc/trio to GL + inventory movement ──
INSERT INTO goods_issues (id, company_id, warehouse_id, branch_id, issue_number, issue_date, purpose, status,
                          department_id, cost_center_id, project_id, location_id, functional_entity_id)
VALUES ('9111aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001',
        'dddd0001-0000-0000-0000-000000000001', '3333aaaa-0000-0000-0000-000000000001',
        'GI-0001', '2026-05-14', 'Production use', 'draft',
        '4444aaaa-0000-0000-0000-000000000001', '5555aaaa-0000-0000-0000-000000000001',
        '6666aaaa-0000-0000-0000-000000000001', '7777aaaa-0000-0000-0000-000000000001', '8888aaaa-0000-0000-0000-000000000001');
INSERT INTO goods_issue_lines (issue_id, company_id, item_id, qty_issued)
VALUES ('9111aaaa-0000-0000-0000-000000000001', '2222aaaa-0000-0000-0000-000000000001',
        'eeee0001-0000-0000-0000-000000000001', 2);
INSERT INTO t_ctx SELECT 'gije', fn_post_goods_issue('9111aaaa-0000-0000-0000-000000000001');

SELECT is((SELECT department_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='gije') AND line_number=1),
  '4444aaaa-0000-0000-0000-000000000001'::uuid, 'Goods Issue GL line carries department');
SELECT is((SELECT cost_center_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='gije') AND line_number=1),
  '5555aaaa-0000-0000-0000-000000000001'::uuid, 'Goods Issue GL line carries cost center');
SELECT is((SELECT project_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='gije') AND line_number=1),
  '6666aaaa-0000-0000-0000-000000000001'::uuid, 'Goods Issue GL line carries project');
SELECT is((SELECT location_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='gije') AND line_number=1),
  '7777aaaa-0000-0000-0000-000000000001'::uuid, 'Goods Issue GL line carries location');
SELECT is((SELECT functional_entity_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='gije') AND line_number=1),
  '8888aaaa-0000-0000-0000-000000000001'::uuid, 'Goods Issue GL line carries functional entity');
SELECT is((SELECT project_id FROM inventory_transactions WHERE reference_doc_type='INV_GI' AND reference_doc_id='9111aaaa-0000-0000-0000-000000000001' LIMIT 1),
  '6666aaaa-0000-0000-0000-000000000001'::uuid, 'Goods Issue inventory movement carries project');

-- ── SECTION E — Fixed Asset acquisition + depreciation propagate dimensions ─────
INSERT INTO t_ctx SELECT 'fa', fn_register_fixed_asset(jsonb_build_object(
  'company_id','2222aaaa-0000-0000-0000-000000000001',
  'branch_id','3333aaaa-0000-0000-0000-000000000001',
  'category_id','faca0001-0000-0000-0000-000000000001',
  'asset_name','CNC Lathe',
  'acquisition_date','2026-05-15',
  'depreciation_start_date','2026-05-31',
  'acquisition_cost',12000,'salvage_value',0,'useful_life_months',12,
  'depreciation_method','straight_line',
  'credit_account_id','9999aaaa-0000-0000-0000-000000000008',
  'department_id','4444aaaa-0000-0000-0000-000000000001',
  'cost_center_id','5555aaaa-0000-0000-0000-000000000001',
  'project_id','6666aaaa-0000-0000-0000-000000000001',
  'location_id','7777aaaa-0000-0000-0000-000000000001',
  'functional_entity_id','8888aaaa-0000-0000-0000-000000000001'));

SELECT is((SELECT jel.department_id FROM journal_entry_lines jel JOIN fixed_assets fa ON fa.acquisition_je_id=jel.je_id
   WHERE fa.id=(SELECT id FROM t_ctx WHERE key='fa') AND jel.line_number=1),
  '4444aaaa-0000-0000-0000-000000000001'::uuid, 'FA acquisition line carries department');
SELECT is((SELECT jel.cost_center_id FROM journal_entry_lines jel JOIN fixed_assets fa ON fa.acquisition_je_id=jel.je_id
   WHERE fa.id=(SELECT id FROM t_ctx WHERE key='fa') AND jel.line_number=1),
  '5555aaaa-0000-0000-0000-000000000001'::uuid, 'FA acquisition line carries cost center');
SELECT is((SELECT jel.project_id FROM journal_entry_lines jel JOIN fixed_assets fa ON fa.acquisition_je_id=jel.je_id
   WHERE fa.id=(SELECT id FROM t_ctx WHERE key='fa') AND jel.line_number=1),
  '6666aaaa-0000-0000-0000-000000000001'::uuid, 'FA acquisition line carries project');

INSERT INTO t_ctx SELECT 'dep', fn_post_depreciation_entry(
  (SELECT id FROM asset_depreciation_entries
   WHERE asset_id=(SELECT id FROM t_ctx WHERE key='fa') AND status='pending'
   ORDER BY period_number LIMIT 1));

SELECT is((SELECT department_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='dep') AND line_number=1),
  '4444aaaa-0000-0000-0000-000000000001'::uuid, 'FA depreciation line carries department');
SELECT is((SELECT project_id FROM journal_entry_lines WHERE je_id=(SELECT id FROM t_ctx WHERE key='dep') AND line_number=1),
  '6666aaaa-0000-0000-0000-000000000001'::uuid, 'FA depreciation line carries project');

-- ── SECTION F — Cross-company rejection at the JE-line guard (all six dims) ──────
-- Driven through the governed posting path (fn_post_manual_je) so the BEFORE-INSERT
-- guard fires; a company-A journal can never carry a company-B dimension.
CREATE FUNCTION pg_temp.mje_with_dim(p_key TEXT, p_val UUID)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM fn_post_manual_je(
    '2222aaaa-0000-0000-0000-000000000001', '3333aaaa-0000-0000-0000-000000000001',
    '2026-05-16', 'Cross-company dimension probe', NULL, false,
    jsonb_build_array(
      jsonb_build_object('account_id','9999aaaa-0000-0000-0000-000000000001','debit_amount',100)
        || jsonb_build_object(p_key, p_val::text),
      jsonb_build_object('account_id','9999aaaa-0000-0000-0000-000000000002','credit_amount',100)
    ));
END;
$fn$;
GRANT EXECUTE ON FUNCTION pg_temp.mje_with_dim(TEXT, UUID) TO authenticated;

SELECT throws_like($$SELECT pg_temp.mje_with_dim('department_id','4444bbbb-0000-0000-0000-000000000001')$$,
  '%department%does not belong to company%', 'cross-company department is rejected on the JE line');
SELECT throws_like($$SELECT pg_temp.mje_with_dim('cost_center_id','5555bbbb-0000-0000-0000-000000000001')$$,
  '%cost center%does not belong to company%', 'cross-company cost center is rejected on the JE line');
SELECT throws_like($$SELECT pg_temp.mje_with_dim('project_id','6666bbbb-0000-0000-0000-000000000001')$$,
  '%project%does not belong to company%', 'cross-company project is rejected on the JE line');
SELECT throws_like($$SELECT pg_temp.mje_with_dim('location_id','7777bbbb-0000-0000-0000-000000000001')$$,
  '%location%does not belong to company%', 'cross-company location is rejected on the JE line');
SELECT throws_like($$SELECT pg_temp.mje_with_dim('functional_entity_id','8888bbbb-0000-0000-0000-000000000001')$$,
  '%functional entity%does not belong to company%', 'cross-company functional entity is rejected on the JE line');
SELECT throws_like($$SELECT pg_temp.mje_with_dim('branch_id','3333bbbb-0000-0000-0000-000000000001')$$,
  '%branch%does not belong to company%', 'cross-company branch is rejected on the JE line');

-- ── SECTION G — Hierarchy rejection on a dimension master ────────────────────────
SELECT throws_ok($$UPDATE projects SET parent_project_id=id WHERE id='6666aaaa-0000-0000-0000-000000000001'$$,
  '23514', NULL, 'a project cannot be its own parent');
SELECT throws_ok($$UPDATE projects SET parent_project_id='6666bbbb-0000-0000-0000-000000000001' WHERE id='6666aaaa-0000-0000-0000-000000000001'$$,
  '23514', NULL, 'a cross-company parent is rejected');

-- ── SECTION H — Source-side validation rejects a cross-company dimension ─────────
SELECT throws_like($$SELECT fn_register_fixed_asset(jsonb_build_object(
    'company_id','2222aaaa-0000-0000-0000-000000000001',
    'branch_id','3333aaaa-0000-0000-0000-000000000001',
    'category_id','faca0001-0000-0000-0000-000000000001',
    'asset_name','Bad Asset','acquisition_date','2026-05-15','depreciation_start_date','2026-05-31',
    'acquisition_cost',1000,'salvage_value',0,'useful_life_months',12,'depreciation_method','straight_line',
    'credit_account_id','9999aaaa-0000-0000-0000-000000000008',
    'project_id','6666bbbb-0000-0000-0000-000000000001'))$$,
  '%Invalid project for Fixed Asset%', 'FA registration rejects a cross-company project at source');

-- ── SECTION I — Reconciliation and non-double-counting ──────────────────────────
-- The dimensional summary is a pure GROUP BY of the certified GL, so its total
-- debit equals the undimensioned GL control total (no double counting).
SELECT is(
  (SELECT COALESCE(SUM(total_debit),0) FROM vw_gl_dimension_summary WHERE company_id='2222aaaa-0000-0000-0000-000000000001'),
  (SELECT COALESCE(SUM(debit_amount),0) FROM vw_general_ledger WHERE company_id='2222aaaa-0000-0000-0000-000000000001'),
  'vw_gl_dimension_summary reconciles to the GL control total (no double counting)');
SELECT is(
  (SELECT COALESCE(SUM(total_debit),0) FROM fn_report_gl_by_dimension('2222aaaa-0000-0000-0000-000000000001','department',NULL,NULL)),
  (SELECT COALESCE(SUM(debit_amount),0) FROM vw_general_ledger WHERE company_id='2222aaaa-0000-0000-0000-000000000001'),
  'department drill-down reconciles to the GL control total');
SELECT is(
  (SELECT COALESCE(SUM(total_debit),0) FROM fn_report_gl_by_dimension('2222aaaa-0000-0000-0000-000000000001','project',NULL,NULL)),
  (SELECT COALESCE(SUM(debit_amount),0) FROM vw_general_ledger WHERE company_id='2222aaaa-0000-0000-0000-000000000001'),
  'project drill-down reconciles to the same control total (grouping dimension does not change the total)');
SELECT is(
  (SELECT COALESCE(SUM(total_debit),0) FROM fn_report_gl_by_dimension('2222aaaa-0000-0000-0000-000000000001','functional_entity',NULL,NULL)),
  (SELECT COALESCE(SUM(debit_amount),0) FROM vw_general_ledger WHERE company_id='2222aaaa-0000-0000-0000-000000000001'),
  'functional-entity drill-down reconciles to the same control total');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
