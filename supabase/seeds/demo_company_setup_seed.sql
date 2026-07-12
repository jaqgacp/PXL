-- =============================================================================
-- PXL DEMO/TEST company setup seed
-- =============================================================================
-- Purpose: create a clearly-identified TEST environment company with enough
-- setup data (COA, GL posting config, fiscal year/periods, compliance profile,
-- EWT company codes, number series) to pass the Company Setup Checklist and
-- support transaction testing. NO posted business transactions are created.
--
-- Properties:
--   * Idempotent: safe to run repeatedly (stable codes + ON CONFLICT/NOT EXISTS).
--   * Non-destructive: never deletes or overwrites existing user data; upserts
--     only fill fields that are currently NULL.
--   * Self-sufficient: creates the demo company/branch/department/cost center
--     if missing, so it works on a fresh local reset as well as the hosted DB.
--   * All records are sample/TEST data. Tables without a description/notes
--     column cannot carry an explicit marker; the demo company name itself
--     ("PXL Demo Trading Corporation") is the marker.
--
-- Run (local):  psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
--                 -f supabase/seeds/demo_company_setup_seed.sql
-- Run (hosted): execute this file's contents through the Supabase management
--               API SQL endpoint (see AI_HANDOFF.md) or the SQL editor.
--
-- Intentionally NOT wired into supabase/config.toml [db.seed] so pgTAP test
-- runs and CI resets stay unaffected.
-- =============================================================================

DO $$
DECLARE
  v_company uuid;
  v_branch  uuid;
  v_user    uuid;
  v_fy      uuid;
  v_re      uuid;  -- retained earnings account
  m         int;
BEGIN
  -- ---------------------------------------------------------------------------
  -- 0. Demo company, branch, department, cost center, membership
  -- ---------------------------------------------------------------------------
  SELECT id INTO v_company FROM companies
  WHERE registered_name = 'PXL Demo Trading Corporation';

  SELECT id INTO v_user FROM auth.users ORDER BY created_at LIMIT 1;

  IF v_company IS NULL THEN
    INSERT INTO companies (entity_type, registered_name, trade_name, line_of_business,
      tin, tax_registration, accounting_period, address_line_1, address_line_2,
      city, province, zip_code, email, signatory_name, signatory_position,
      is_active, created_by)
    VALUES ('corporation', 'PXL Demo Trading Corporation', 'PXL Demo',
      'Wholesale and Retail Trading', '008-123-456-000', 'vat', 'calendar',
      'Unit 1201, One Ayala Tower', 'Ayala Avenue, Barangay San Lorenzo',
      'Makati City', 'Metro Manila', '1226', 'demo@pxldemo.ph',
      'Jose Ramos', 'President', true, v_user)
    RETURNING id INTO v_company;
  END IF;

  SELECT id INTO v_branch FROM branches
  WHERE company_id = v_company AND branch_code = 'HO';

  IF v_branch IS NULL THEN
    INSERT INTO branches (company_id, branch_code, branch_name, branch_type,
      tin_branch_code, address_line_1, address_line_2, city, province, zip_code,
      is_active, created_by)
    VALUES (v_company, 'HO', 'Head Office', 'head_office', '000',
      'Unit 1201, One Ayala Tower', 'Ayala Avenue, Barangay San Lorenzo',
      'Makati City', 'Metro Manila', '1226', true, v_user)
    RETURNING id INTO v_branch;
  END IF;

  INSERT INTO departments (company_id, branch_id, department_code, department_name,
    department_head_name, description, is_active, created_by)
  SELECT v_company, v_branch, 'FIN', 'Finance', 'Maria Cruz',
    'Finance and accounting department (TEST seed)', true, v_user
  WHERE NOT EXISTS (SELECT 1 FROM departments
    WHERE company_id = v_company AND department_code = 'FIN');

  INSERT INTO cost_centers (company_id, branch_id, department_id, cost_center_code,
    cost_center_name, cost_center_type, valid_from, description, is_active, created_by)
  SELECT v_company, v_branch, d.id, 'CC-GA', 'General and Administrative',
    'cost_center', DATE '2026-01-01', 'Default administrative cost center (TEST seed)',
    true, v_user
  FROM departments d
  WHERE d.company_id = v_company AND d.department_code = 'FIN'
    AND NOT EXISTS (SELECT 1 FROM cost_centers
      WHERE company_id = v_company AND cost_center_code = 'CC-GA');

  IF v_user IS NOT NULL THEN
    INSERT INTO user_company_memberships (user_id, company_id, role)
    SELECT v_user, v_company, 'admin'
    WHERE NOT EXISTS (SELECT 1 FROM user_company_memberships
      WHERE user_id = v_user AND company_id = v_company);
  END IF;

  -- ---------------------------------------------------------------------------
  -- A. Chart of accounts (PH trading/service company)
  -- ---------------------------------------------------------------------------
  INSERT INTO chart_of_accounts
    (company_id, account_code, account_name, account_type, normal_balance,
     is_postable, is_active, created_by)
  SELECT v_company, x.code, x.name, x.typ, x.nb, x.postable, true, v_user
  FROM (VALUES
    -- ASSETS
    ('1000-00', 'Cash and Cash Equivalents',            'asset',     'debit',  false),
    ('1010-00', 'Cash on Hand',                         'asset',     'debit',  true),
    ('1020-00', 'Petty Cash Fund',                      'asset',     'debit',  true),
    ('1030-00', 'Cash in Bank - BPI',                   'asset',     'debit',  true),
    ('1040-00', 'Cash in Bank - BDO',                   'asset',     'debit',  true),
    ('1100-00', 'Accounts Receivable - Trade',          'asset',     'debit',  true),
    ('1110-00', 'Allowance for Doubtful Accounts',      'asset',     'credit', true),
    ('1200-00', 'Inventory - Merchandise',              'asset',     'debit',  true),
    ('1210-00', 'Inventory in Transit',                 'asset',     'debit',  true),
    ('1300-00', 'Creditable Withholding Tax Receivable','asset',     'debit',  true),
    ('1310-00', 'Input VAT',                            'asset',     'debit',  true),
    ('1320-00', 'Prepaid Expenses',                     'asset',     'debit',  true),
    ('1400-00', 'Advances to Suppliers',                'asset',     'debit',  true),
    ('1500-00', 'Office Equipment',                     'asset',     'debit',  true),
    ('1510-00', 'Furniture and Fixtures',               'asset',     'debit',  true),
    ('1590-00', 'Accumulated Depreciation',             'asset',     'credit', true),
    -- LIABILITIES
    ('2000-00', 'Accounts Payable - Trade',             'liability', 'credit', true),
    ('2100-00', 'Output VAT Payable',                   'liability', 'credit', true),
    ('2110-00', 'Expanded Withholding Tax Payable',     'liability', 'credit', true),
    ('2120-00', 'Final Withholding Tax Payable',        'liability', 'credit', true),
    ('2130-00', 'Percentage Tax Payable',               'liability', 'credit', true),
    ('2140-00', 'Other Taxes Payable',                  'liability', 'credit', true),
    ('2200-00', 'Accrued Expenses',                     'liability', 'credit', true),
    ('2210-00', 'Customer Advances',                    'liability', 'credit', true),
    ('2300-00', 'Loans Payable',                        'liability', 'credit', true),
    -- EQUITY
    ('3000-00', 'Share Capital',                        'equity',    'credit', true),
    ('3100-00', 'Additional Paid-in Capital',           'equity',    'credit', true),
    ('3200-00', 'Retained Earnings',                    'equity',    'credit', true),
    ('3300-00', 'Current Year Earnings',                'equity',    'credit', true),
    ('3400-00', 'Dividends Declared',                   'equity',    'debit',  true),
    -- REVENUE
    ('4000-00', 'Sales Revenue - Goods',                'revenue',   'credit', true),
    ('4010-00', 'Service Revenue',                      'revenue',   'credit', true),
    ('4020-00', 'Delivery Income',                      'revenue',   'credit', true),
    ('4100-00', 'Sales Returns and Allowances',         'revenue',   'debit',  true),
    ('4110-00', 'Sales Discounts',                      'revenue',   'debit',  true),
    ('4200-00', 'Other Income',                         'revenue',   'credit', true),
    ('4210-00', 'Interest Income',                      'revenue',   'credit', true),
    -- COST OF SALES
    ('5000-00', 'Cost of Goods Sold',                   'expense',   'debit',  true),
    ('5010-00', 'Freight and Delivery Cost',            'expense',   'debit',  true),
    ('5020-00', 'Inventory Variance',                   'expense',   'debit',  true),
    ('5030-00', 'Inventory Write-Off',                  'expense',   'debit',  true),
    -- OPERATING EXPENSES
    ('6000-00', 'Salaries and Wages',                   'expense',   'debit',  true),
    ('6010-00', 'Employee Benefits',                    'expense',   'debit',  true),
    ('6020-00', 'Rent Expense',                         'expense',   'debit',  true),
    ('6030-00', 'Utilities Expense',                    'expense',   'debit',  true),
    ('6040-00', 'Internet and Communication',           'expense',   'debit',  true),
    ('6050-00', 'Office Supplies',                      'expense',   'debit',  true),
    ('6060-00', 'Professional Fees',                    'expense',   'debit',  true),
    ('6070-00', 'Repairs and Maintenance',              'expense',   'debit',  true),
    ('6080-00', 'Transportation and Travel',            'expense',   'debit',  true),
    ('6090-00', 'Representation Expense',               'expense',   'debit',  true),
    ('6100-00', 'Advertising and Marketing',            'expense',   'debit',  true),
    ('6110-00', 'Bank Charges',                         'expense',   'debit',  true),
    ('6120-00', 'Depreciation Expense',                 'expense',   'debit',  true),
    ('6130-00', 'Taxes and Licenses',                   'expense',   'debit',  true),
    ('6140-00', 'Insurance Expense',                    'expense',   'debit',  true),
    ('6150-00', 'Miscellaneous Expense',                'expense',   'debit',  true),
    ('6160-00', 'Bad Debt Expense',                     'expense',   'debit',  true),
    -- OTHER / CONTROL
    ('9000-00', 'Suspense Account',                     'asset',     'debit',  true),
    ('9010-00', 'Opening Balance Equity',               'equity',    'credit', true),
    ('9020-00', 'Inventory Adjustment Clearing',        'asset',     'debit',  true),
    ('9030-00', 'Interbranch Clearing',                 'asset',     'debit',  true),
    ('9040-00', 'Undeposited Funds',                    'asset',     'debit',  true)
  ) AS x(code, name, typ, nb, postable)
  ON CONFLICT (company_id, account_code) DO NOTHING;

  -- Cash group hierarchy: 1000-00 is a non-postable header
  UPDATE chart_of_accounts child
  SET parent_id = parent.id
  FROM chart_of_accounts parent
  WHERE parent.company_id = v_company AND parent.account_code = '1000-00'
    AND child.company_id = v_company
    AND child.account_code IN ('1010-00','1020-00','1030-00','1040-00')
    AND child.parent_id IS NULL;

  -- ---------------------------------------------------------------------------
  -- B. GL posting configuration (only fields that exist in the schema)
  -- ---------------------------------------------------------------------------
  INSERT INTO company_accounting_config
    (company_id, ar_account_id, ap_account_id, default_cash_account_id,
     vat_payable_account_id, input_vat_account_id,
     ewt_withheld_account_id, ewt_payable_account_id, created_by)
  SELECT v_company,
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1100-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '2000-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1010-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '2100-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1310-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '1300-00'),
    (SELECT id FROM chart_of_accounts WHERE company_id = v_company AND account_code = '2110-00'),
    v_user
  ON CONFLICT (company_id) DO UPDATE SET
    ar_account_id           = COALESCE(company_accounting_config.ar_account_id,           EXCLUDED.ar_account_id),
    ap_account_id           = COALESCE(company_accounting_config.ap_account_id,           EXCLUDED.ap_account_id),
    default_cash_account_id = COALESCE(company_accounting_config.default_cash_account_id, EXCLUDED.default_cash_account_id),
    vat_payable_account_id  = COALESCE(company_accounting_config.vat_payable_account_id,  EXCLUDED.vat_payable_account_id),
    input_vat_account_id    = COALESCE(company_accounting_config.input_vat_account_id,    EXCLUDED.input_vat_account_id),
    ewt_withheld_account_id = COALESCE(company_accounting_config.ewt_withheld_account_id, EXCLUDED.ewt_withheld_account_id),
    ewt_payable_account_id  = COALESCE(company_accounting_config.ewt_payable_account_id,  EXCLUDED.ewt_payable_account_id),
    updated_at = now();

  -- ---------------------------------------------------------------------------
  -- C. Fiscal year FY 2026 with 12 open monthly periods
  --    (fiscal_periods.period_number is constrained to 1..12: no period 13 /
  --     adjustment period is supported by the schema.)
  -- ---------------------------------------------------------------------------
  SELECT id INTO v_re FROM chart_of_accounts
  WHERE company_id = v_company AND account_code = '3200-00';

  INSERT INTO fiscal_years (company_id, year_name, start_date, end_date,
    is_calendar, status, retained_earnings_id, created_by)
  VALUES (v_company, 'FY 2026', DATE '2026-01-01', DATE '2026-12-31',
    true, 'open', v_re, v_user)
  ON CONFLICT (company_id, year_name) DO NOTHING;

  SELECT id INTO v_fy FROM fiscal_years
  WHERE company_id = v_company AND year_name = 'FY 2026';

  UPDATE fiscal_years SET retained_earnings_id = v_re
  WHERE id = v_fy AND retained_earnings_id IS NULL;

  FOR m IN 1..12 LOOP
    INSERT INTO fiscal_periods (company_id, fiscal_year_id, period_number,
      period_name, start_date, end_date, is_locked)
    VALUES (v_company, v_fy, m,
      trim(to_char(make_date(2026, m, 1), 'FMMonth')) || ' 2026',
      make_date(2026, m, 1),
      (make_date(2026, m, 1) + interval '1 month' - interval '1 day')::date,
      false)
    ON CONFLICT (fiscal_year_id, period_number) DO NOTHING;
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- D. Compliance profile: VAT-registered withholding agent, calendar year,
  --    accrual RCIT. No CAS/PTU/accreditation registrations are claimed.
  -- ---------------------------------------------------------------------------
  INSERT INTO compliance_profiles (company_id,
    efps_enrolled, vat_registered, vat_effective_date, vat_filing_frequency,
    vat_threshold_monitoring, percentage_tax_registered,
    ewt_registered, is_twa, twa_auto_ewt_enabled,
    files_0619e, qap_required, requires_1604e,
    fwt_registered, files_0619f,
    income_tax_regime, corporate_tax_rate, mcit_applicable, nolco_applicable,
    sawt_required, slsp_required, relief_required, dat_file_required,
    is_active, created_by)
  VALUES (v_company,
    false, true, DATE '2026-01-01', 'quarterly',
    true, false,
    true, false, false,
    true, true, true,
    false, false,
    'rcit', 25.00, false, false,
    true, true, true, false,
    true, v_user)
  ON CONFLICT (company_id) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- D2. Company EWT codes (required by the checklist when ewt_registered).
  --     Global EWT tax_codes are created once if absent; ewt_codes link the
  --     company to current active ATC masters.
  -- ---------------------------------------------------------------------------
  INSERT INTO tax_codes (code, description, tax_type, rate, is_active, created_by)
  SELECT x.code, x.descr, 'ewt', x.rate, true, v_user
  FROM (VALUES
    ('EWT-1',  'Expanded withholding 1% (TEST seed)',  1.00),
    ('EWT-2',  'Expanded withholding 2% (TEST seed)',  2.00),
    ('EWT-5',  'Expanded withholding 5% (TEST seed)',  5.00),
    ('EWT-10', 'Expanded withholding 10% (TEST seed)', 10.00)
  ) AS x(code, descr, rate)
  WHERE NOT EXISTS (SELECT 1 FROM tax_codes t WHERE t.code = x.code);

  INSERT INTO ewt_codes (company_id, tax_code_id, ewt_code, description, atc_id,
    rate, form_type, is_active, created_by)
  SELECT v_company, tc.id, x.ewt_code, a.description || ' (TEST seed)', a.id,
    a.rate, '1601EQ', true, v_user
  FROM (VALUES
    ('EWT-PF-CORP', 'WC010', 'EWT-10'),
    ('EWT-RENT-PP', 'WC120', 'EWT-5'),
    ('EWT-RENT-RP', 'WC130', 'EWT-2'),
    ('EWT-CONTRACTOR', 'WC140', 'EWT-2'),
    ('EWT-GOODS-TWA', 'WC158', 'EWT-1')
  ) AS x(ewt_code, atc, tax_code)
  JOIN atc_codes a ON a.code = x.atc AND a.is_active AND a.deprecated_at IS NULL
  JOIN tax_codes tc ON tc.code = x.tax_code
  ON CONFLICT DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- E. Number series: one active series per document code the application
  --    actually requests (UI readiness checks + live posting RPCs), plus the
  --    remaining governed registry codes. Format: <PREFIX>-2026-000001.
  --    Every requested code (incl. JE, FA, SDM, PRT) now exists in
  --    ref_document_types (PXL-AUD-051), so each series points at its own
  --    governed type and fn_next_document_number matches on document_code.
  -- ---------------------------------------------------------------------------
  INSERT INTO number_series (company_id, branch_id, document_type_id,
    document_code, prefix, has_dynamic_year, number_length, padding,
    starting_number, next_number, current_sequence, reset_frequency,
    allow_manual_override, is_active, created_by)
  SELECT v_company, v_branch, dt.id,
    x.code, x.code || '-2026-', false, 6, 6,
    1, 1, 0, 'yearly',
    false, true, v_user
  FROM (VALUES
    -- sales
    ('QT',   'QT'),   ('SO',  'SO'),  ('DR', 'DR'), ('SI', 'SI'), ('CS', 'CS'),
    ('OR',   'OR'),   ('CM',  'CM'),  ('DM-S', 'DM-S'), ('CR', 'CR'),
    -- purchasing
    ('PO',   'PO'),   ('RR',  'RR'),  ('VB', 'VB'), ('CP', 'CP'), ('PV', 'PV'),
    ('VC',   'VC'),   ('SDM', 'SDM'), ('PRT', 'PRT'),
    -- accounting / treasury / petty cash / fixed assets
    ('JE',   'JE'),   ('FA',  'FA'),  ('RJV', 'RJV'), ('CV', 'CV'), ('PCF', 'PCF'),
    ('PCV',  'PCV'),  ('PCR', 'PCR'), ('CCS', 'CCS'),
    ('FT',   'FT'),   ('IBT', 'IBT'), ('BADJ', 'BADJ')
  ) AS x(code, type_code)
  JOIN ref_document_types dt ON dt.document_code = x.type_code
  ON CONFLICT DO NOTHING;

  RAISE NOTICE 'Demo setup seed complete for company %', v_company;
END $$;

-- Post-seed summary (safe to run standalone)
SELECT
  (SELECT count(*) FROM chart_of_accounts c JOIN companies co ON co.id = c.company_id
    WHERE co.registered_name = 'PXL Demo Trading Corporation') AS coa_accounts,
  (SELECT count(*) FROM fiscal_periods p JOIN companies co ON co.id = p.company_id
    WHERE co.registered_name = 'PXL Demo Trading Corporation') AS fiscal_periods,
  (SELECT count(*) FROM number_series n JOIN companies co ON co.id = n.company_id
    WHERE co.registered_name = 'PXL Demo Trading Corporation' AND n.is_active) AS number_series,
  (SELECT count(*) FROM ewt_codes e JOIN companies co ON co.id = e.company_id
    WHERE co.registered_name = 'PXL Demo Trading Corporation' AND e.is_active) AS ewt_codes,
  (SELECT count(*) FROM compliance_profiles cp JOIN companies co ON co.id = cp.company_id
    WHERE co.registered_name = 'PXL Demo Trading Corporation' AND cp.is_active) AS compliance_profiles;
