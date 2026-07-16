-- System-wide Philippine TIN standard.
--
-- Official display/storage format:
--   XXX-XXX-XXX-XXXXX
--
-- The first 9 digits are the taxpayer number.
-- The last 5 digits are the BIR branch identifier.

CREATE OR REPLACE FUNCTION public.fn_ph_tin_digits(p_value TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(coalesce(p_value, ''), '\D', '', 'g')
$$;

CREATE OR REPLACE FUNCTION public.fn_format_ph_tin_branch(p_value TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_digits TEXT := public.fn_ph_tin_digits(p_value);
BEGIN
  IF v_digits = '' THEN
    RETURN '00000';
  END IF;

  IF length(v_digits) > 5 THEN
    RAISE EXCEPTION 'TIN Branch must be exactly 5 digits after normalization';
  END IF;

  RETURN lpad(v_digits, 5, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_format_ph_tin(p_value TEXT, p_default_branch TEXT DEFAULT '00000')
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_digits TEXT := public.fn_ph_tin_digits(p_value);
  v_taxpayer TEXT;
  v_branch TEXT;
BEGIN
  IF v_digits = '' THEN
    RETURN NULL;
  END IF;

  IF length(v_digits) = 14 THEN
    v_taxpayer := substr(v_digits, 1, 9);
    v_branch := substr(v_digits, 10, 5);
  ELSIF length(v_digits) = 9 THEN
    v_taxpayer := v_digits;
    v_branch := public.fn_format_ph_tin_branch(p_default_branch);
  ELSIF length(v_digits) > 9 AND length(v_digits) < 14 THEN
    v_taxpayer := substr(v_digits, 1, 9);
    v_branch := lpad(substr(v_digits, 10), 5, '0');
  ELSE
    RAISE EXCEPTION 'Philippine TIN must be 9 taxpayer digits plus 5 branch digits';
  END IF;

  RETURN substr(v_taxpayer, 1, 3) || '-' ||
         substr(v_taxpayer, 4, 3) || '-' ||
         substr(v_taxpayer, 7, 3) || '-' ||
         v_branch;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_normalize_ph_tin_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_column TEXT;
  v_raw TEXT;
  v_normalized TEXT;
BEGIN
  FOREACH v_column IN ARRAY TG_ARGV LOOP
    EXECUTE format('SELECT ($1).%I::text', v_column) USING NEW INTO v_raw;
    v_normalized := CASE
      WHEN NULLIF(btrim(coalesce(v_raw, '')), '') IS NULL THEN ''
      ELSE public.fn_format_ph_tin(v_raw)
    END;
    NEW := jsonb_populate_record(NEW, jsonb_build_object(v_column, v_normalized));
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_normalize_ph_tin_branch_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_column TEXT;
  v_raw TEXT;
BEGIN
  FOREACH v_column IN ARRAY TG_ARGV LOOP
    EXECUTE format('SELECT ($1).%I::text', v_column) USING NEW INTO v_raw;
    NEW := jsonb_populate_record(NEW, jsonb_build_object(v_column, public.fn_format_ph_tin_branch(v_raw)));
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_sync_customer_ph_tin()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_normalized TEXT;
BEGIN
  v_normalized := public.fn_format_ph_tin(NEW.tin, NEW.tin_branch_code);
  NEW.tin := v_normalized;
  NEW.tin_branch_code := substr(public.fn_ph_tin_digits(v_normalized), 10, 5);
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_format_ph_tin(TEXT, TEXT) IS
  'Formats Philippine TIN as XXX-XXX-XXX-XXXXX using 9 taxpayer digits plus 5 branch digits.';
COMMENT ON FUNCTION public.fn_format_ph_tin_branch(TEXT) IS
  'Formats the BIR TIN branch identifier as exactly 5 digits; defaults blank values to 00000.';

-- Master data repair and hard validation.
UPDATE public.companies
SET
  tin = public.fn_format_ph_tin(tin),
  signatory_tin = CASE
    WHEN NULLIF(btrim(coalesce(signatory_tin, '')), '') IS NULL THEN NULL
    ELSE public.fn_format_ph_tin(signatory_tin)
  END
WHERE tin IS NOT NULL;

ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_tin_ph_tin_ck;
ALTER TABLE public.companies
  ADD CONSTRAINT companies_tin_ph_tin_ck
  CHECK (tin ~ '^[0-9]{3}-[0-9]{3}-[0-9]{3}-[0-9]{5}$');

ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_signatory_tin_ph_tin_ck;
ALTER TABLE public.companies
  ADD CONSTRAINT companies_signatory_tin_ph_tin_ck
  CHECK (
    NULLIF(btrim(coalesce(signatory_tin, '')), '') IS NULL
    OR signatory_tin ~ '^[0-9]{3}-[0-9]{3}-[0-9]{3}-[0-9]{5}$'
  );

DROP TRIGGER IF EXISTS companies_ph_tin_normalize_trg ON public.companies;
CREATE TRIGGER companies_ph_tin_normalize_trg
  BEFORE INSERT OR UPDATE OF tin, signatory_tin ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_normalize_ph_tin_columns('tin', 'signatory_tin');

UPDATE public.branches
SET tin_branch_code = public.fn_format_ph_tin_branch(tin_branch_code)
WHERE tin_branch_code IS NOT NULL;

ALTER TABLE public.branches
  ALTER COLUMN tin_branch_code SET DEFAULT '00000';

ALTER TABLE public.branches DROP CONSTRAINT IF EXISTS branches_tin_branch_code_ph_ck;
ALTER TABLE public.branches
  ADD CONSTRAINT branches_tin_branch_code_ph_ck
  CHECK (tin_branch_code ~ '^[0-9]{5}$');

DROP TRIGGER IF EXISTS branches_ph_tin_branch_normalize_trg ON public.branches;
CREATE TRIGGER branches_ph_tin_branch_normalize_trg
  BEFORE INSERT OR UPDATE OF tin_branch_code ON public.branches
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_normalize_ph_tin_branch_columns('tin_branch_code');

UPDATE public.customers
SET
  tin = public.fn_format_ph_tin(tin, tin_branch_code),
  tin_branch_code = substr(public.fn_ph_tin_digits(public.fn_format_ph_tin(tin, tin_branch_code)), 10, 5)
WHERE tin IS NOT NULL;

ALTER TABLE public.customers
  ALTER COLUMN tin_branch_code SET DEFAULT '00000';

ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_tin_ph_tin_ck;
ALTER TABLE public.customers
  ADD CONSTRAINT customers_tin_ph_tin_ck
  CHECK (tin ~ '^[0-9]{3}-[0-9]{3}-[0-9]{3}-[0-9]{5}$');

ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_tin_branch_code_ph_ck;
ALTER TABLE public.customers
  ADD CONSTRAINT customers_tin_branch_code_ph_ck
  CHECK (tin_branch_code ~ '^[0-9]{5}$');

DROP TRIGGER IF EXISTS customers_ph_tin_sync_trg ON public.customers;
CREATE TRIGGER customers_ph_tin_sync_trg
  BEFORE INSERT OR UPDATE OF tin, tin_branch_code ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_sync_customer_ph_tin();

UPDATE public.suppliers
SET tin = public.fn_format_ph_tin(tin)
WHERE tin IS NOT NULL;

ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_tin_ph_tin_ck;
ALTER TABLE public.suppliers
  ADD CONSTRAINT suppliers_tin_ph_tin_ck
  CHECK (tin ~ '^[0-9]{3}-[0-9]{3}-[0-9]{3}-[0-9]{5}$');

DROP TRIGGER IF EXISTS suppliers_ph_tin_normalize_trg ON public.suppliers;
CREATE TRIGGER suppliers_ph_tin_normalize_trg
  BEFORE INSERT OR UPDATE OF tin ON public.suppliers
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_normalize_ph_tin_columns('tin');

-- Normalize every current transaction/reporting table that stores a full TIN.
DO $$
DECLARE
  v_rec RECORD;
  v_column TEXT;
  v_constraint TEXT;
  v_trigger TEXT;
  v_args TEXT;
BEGIN
  FOR v_rec IN
    SELECT c.table_schema, c.table_name, array_agg(c.column_name ORDER BY c.column_name) AS columns
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema
     AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_schema = 'public'
      AND c.data_type IN ('text', 'character varying')
      AND c.table_name NOT IN ('companies', 'customers', 'suppliers', 'branches', 'cas_document_void_events')
      AND c.column_name IN (
        'tin',
        'signatory_tin',
        'customer_tin',
        'customer_tin_snapshot',
        'supplier_tin',
        'supplier_tin_snapshot',
        'counterparty_tin',
        'party_tin',
        'payee_tin',
        'vendor_tin',
        'employee_tin',
        'taxpayer_tin',
        'branch_tin'
      )
    GROUP BY c.table_schema, c.table_name
  LOOP
    EXECUTE format('ALTER TABLE %I.%I DISABLE TRIGGER USER', v_rec.table_schema, v_rec.table_name);

    FOREACH v_column IN ARRAY v_rec.columns LOOP
      EXECUTE format(
        'UPDATE %I.%I SET %I = CASE WHEN NULLIF(BTRIM(COALESCE(%I, '''')), '''') IS NULL THEN %I ELSE public.fn_format_ph_tin(%I) END WHERE %I IS NOT NULL',
        v_rec.table_schema, v_rec.table_name, v_column, v_column, v_column, v_column, v_column
      );
    END LOOP;

    EXECUTE format('ALTER TABLE %I.%I ENABLE TRIGGER USER', v_rec.table_schema, v_rec.table_name);

    FOREACH v_column IN ARRAY v_rec.columns LOOP
      v_constraint := left(v_rec.table_name || '_' || v_column || '_ph_tin_ck', 55) ||
                      '_' || substr(md5(v_rec.table_name || '_' || v_column), 1, 7);

      EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I',
        v_rec.table_schema, v_rec.table_name, v_constraint);
      EXECUTE format(
        'ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK (NULLIF(BTRIM(COALESCE(%I, '''')), '''') IS NULL OR %I ~ ''^[0-9]{3}-[0-9]{3}-[0-9]{3}-[0-9]{5}$'')',
        v_rec.table_schema, v_rec.table_name, v_constraint, v_column, v_column
      );
    END LOOP;

    SELECT string_agg(quote_literal(col), ', ')
    INTO v_args
    FROM unnest(v_rec.columns) AS col;

    v_trigger := left(v_rec.table_name || '_ph_tin_normalize_trg', 55) ||
                 '_' || substr(md5(v_rec.table_name || '_ph_tin_normalize'), 1, 7);

    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
      v_trigger, v_rec.table_schema, v_rec.table_name);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION public.fn_normalize_ph_tin_columns(%s)',
      v_trigger, v_rec.table_schema, v_rec.table_name, v_args
    );
  END LOOP;
END $$;

-- Normalize every current table that stores only the BIR TIN branch identifier.
DO $$
DECLARE
  v_rec RECORD;
  v_column TEXT;
  v_constraint TEXT;
  v_trigger TEXT;
  v_args TEXT;
BEGIN
  FOR v_rec IN
    SELECT c.table_schema, c.table_name, array_agg(c.column_name ORDER BY c.column_name) AS columns
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema
     AND t.table_name = c.table_name
     AND t.table_type = 'BASE TABLE'
    WHERE c.table_schema = 'public'
      AND c.data_type IN ('text', 'character varying')
      AND c.table_name NOT IN ('customers', 'branches')
      AND c.column_name IN ('tin_branch_code', 'branch_tin_branch_code')
    GROUP BY c.table_schema, c.table_name
  LOOP
    EXECUTE format('ALTER TABLE %I.%I DISABLE TRIGGER USER', v_rec.table_schema, v_rec.table_name);

    FOREACH v_column IN ARRAY v_rec.columns LOOP
      EXECUTE format(
        'UPDATE %I.%I SET %I = public.fn_format_ph_tin_branch(%I) WHERE %I IS NOT NULL',
        v_rec.table_schema, v_rec.table_name, v_column, v_column, v_column
      );
    END LOOP;

    EXECUTE format('ALTER TABLE %I.%I ENABLE TRIGGER USER', v_rec.table_schema, v_rec.table_name);

    FOREACH v_column IN ARRAY v_rec.columns LOOP
      v_constraint := left(v_rec.table_name || '_' || v_column || '_ph_branch_ck', 55) ||
                      '_' || substr(md5(v_rec.table_name || '_' || v_column || '_branch'), 1, 7);

      EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I',
        v_rec.table_schema, v_rec.table_name, v_constraint);
      EXECUTE format(
        'ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK (%I ~ ''^[0-9]{5}$'')',
        v_rec.table_schema, v_rec.table_name, v_constraint, v_column
      );
    END LOOP;

    SELECT string_agg(quote_literal(col), ', ')
    INTO v_args
    FROM unnest(v_rec.columns) AS col;

    v_trigger := left(v_rec.table_name || '_ph_tin_branch_normalize_trg', 55) ||
                 '_' || substr(md5(v_rec.table_name || '_ph_tin_branch_normalize'), 1, 7);

    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
      v_trigger, v_rec.table_schema, v_rec.table_name);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION public.fn_normalize_ph_tin_branch_columns(%s)',
      v_trigger, v_rec.table_schema, v_rec.table_name, v_args
    );
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_ph_tin_digits(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_format_ph_tin_branch(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_format_ph_tin(TEXT, TEXT) TO authenticated, service_role;
