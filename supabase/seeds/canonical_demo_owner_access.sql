-- =============================================================================
-- PXL canonical demo owner-access grant
-- =============================================================================
--
-- Purpose:
--   Grant an existing hosted authentication account owner access to all five
--   canonical demo companies without hard-coding an operator email in source.
--
-- Required guard:
--   SET pxl.demo_owner_email = 'operator@example.com';
-- =============================================================================

DO $owner_access$
DECLARE
  v_email TEXT := NULLIF(current_setting('pxl.demo_owner_email', true), '');
  v_user UUID;
  v_company_count INTEGER;
BEGIN
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Refusing owner grant. Set pxl.demo_owner_email first.';
  END IF;

  SELECT id INTO v_user
  FROM auth.users
  WHERE lower(email) = lower(v_email);

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication user not found for %', v_email;
  END IF;

  SELECT count(*) INTO v_company_count
  FROM companies
  WHERE trade_name IN (
    'DEMO-SP-NONVAT',
    'DEMO-CORP-VAT',
    'DEMO-OPC-NONVAT',
    'DEMO-SVC-VAT',
    'DEMO-PARTNERSHIP-VAT'
  );

  IF v_company_count <> 5 THEN
    RAISE EXCEPTION 'Expected five canonical companies before owner grant; found %', v_company_count;
  END IF;

  INSERT INTO user_company_memberships (user_id, company_id, role, granted_by)
  SELECT v_user, c.id, 'owner', v_user
  FROM companies c
  WHERE c.trade_name IN (
    'DEMO-SP-NONVAT',
    'DEMO-CORP-VAT',
    'DEMO-OPC-NONVAT',
    'DEMO-SVC-VAT',
    'DEMO-PARTNERSHIP-VAT'
  )
  ON CONFLICT (user_id, company_id) DO UPDATE SET
    role = EXCLUDED.role,
    granted_by = EXCLUDED.granted_by;
END
$owner_access$;
