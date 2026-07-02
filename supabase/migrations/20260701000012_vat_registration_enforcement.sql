-- Enforce company VAT registration on VAT-bearing transactions and VAT returns.

CREATE OR REPLACE FUNCTION fn_require_vat_registered_company(
  p_company_id UUID,
  p_context TEXT DEFAULT 'VAT action'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tax_registration TEXT;
BEGIN
  SELECT tax_registration INTO v_tax_registration
  FROM companies
  WHERE id = p_company_id;

  IF v_tax_registration IS NULL THEN
    RAISE EXCEPTION 'Company not found';
  END IF;

  IF v_tax_registration != 'vat' THEN
    RAISE EXCEPTION '% requires a VAT-registered company. Current company tax registration is %.',
      p_context, v_tax_registration;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_company_vat_code(
  p_company_id UUID,
  p_vat_code_id UUID,
  p_transaction_type TEXT,
  p_context TEXT DEFAULT 'VAT code'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tax_registration TEXT;
  v_vat_code TEXT;
  v_classification TEXT;
  v_transaction_type TEXT;
  v_rate NUMERIC(6,2);
  v_is_active BOOLEAN;
BEGIN
  IF p_vat_code_id IS NULL THEN
    RETURN;
  END IF;

  SELECT tax_registration INTO v_tax_registration
  FROM companies
  WHERE id = p_company_id;

  IF v_tax_registration IS NULL THEN
    RAISE EXCEPTION 'Company not found';
  END IF;

  SELECT vc.vat_code, vc.vat_classification, vc.transaction_type, COALESCE(tc.rate, 0), COALESCE(vc.is_active, false)
  INTO v_vat_code, v_classification, v_transaction_type, v_rate, v_is_active
  FROM vat_codes vc
  JOIN tax_codes tc ON tc.id = vc.tax_code_id
  WHERE vc.id = p_vat_code_id;

  IF v_vat_code IS NULL THEN
    RAISE EXCEPTION '% is not a valid VAT code', p_context;
  END IF;
  IF NOT v_is_active THEN
    RAISE EXCEPTION '% % is inactive', p_context, v_vat_code;
  END IF;
  IF v_transaction_type != p_transaction_type THEN
    RAISE EXCEPTION '% % is for %, not %', p_context, v_vat_code, v_transaction_type, p_transaction_type;
  END IF;

  IF v_tax_registration != 'vat' AND v_rate <> 0 THEN
    RAISE EXCEPTION 'Non-VAT or exempt companies cannot use VAT-bearing code % (% rate). Use a zero-rate/exempt code instead.',
      v_vat_code, v_rate;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_si_line_vat_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id
  FROM sales_invoices
  WHERE id = NEW.sales_invoice_id;

  PERFORM fn_validate_company_vat_code(
    COALESCE(NEW.company_id, v_company_id),
    NEW.vat_code_id,
    'output_vat',
    'Sales invoice VAT code'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_si_line_vat_registration ON sales_invoice_lines;
CREATE TRIGGER trg_si_line_vat_registration
  BEFORE INSERT OR UPDATE OF vat_code_id, company_id, sales_invoice_id
  ON sales_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_si_line_vat_registration();

CREATE OR REPLACE FUNCTION fn_require_vb_line_vat_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id
  FROM vendor_bills
  WHERE id = NEW.vendor_bill_id;

  PERFORM fn_validate_company_vat_code(
    COALESCE(NEW.company_id, v_company_id),
    NEW.vat_code_id,
    'input_vat',
    'Vendor bill VAT code'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vb_line_vat_registration ON vendor_bill_lines;
CREATE TRIGGER trg_vb_line_vat_registration
  BEFORE INSERT OR UPDATE OF vat_code_id, company_id, vendor_bill_id
  ON vendor_bill_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_vb_line_vat_registration();

CREATE OR REPLACE FUNCTION fn_validate_sales_invoice_vat_registration(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
BEGIN
  FOR v_line IN
    SELECT si.company_id, sil.vat_code_id
    FROM sales_invoices si
    JOIN sales_invoice_lines sil ON sil.sales_invoice_id = si.id
    WHERE si.id = p_invoice_id
  LOOP
    PERFORM fn_validate_company_vat_code(v_line.company_id, v_line.vat_code_id, 'output_vat', 'Sales invoice VAT code');
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION fn_validate_vendor_bill_vat_registration(p_bill_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
BEGIN
  FOR v_line IN
    SELECT vb.company_id, vbl.vat_code_id
    FROM vendor_bills vb
    JOIN vendor_bill_lines vbl ON vbl.vendor_bill_id = vb.id
    WHERE vb.id = p_bill_id
  LOOP
    PERFORM fn_validate_company_vat_code(v_line.company_id, v_line.vat_code_id, 'input_vat', 'Vendor bill VAT code');
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_si_vat_registration_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('approved', 'posted') THEN
    PERFORM fn_validate_sales_invoice_vat_registration(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_si_vat_registration_status ON sales_invoices;
CREATE TRIGGER trg_si_vat_registration_status
  BEFORE INSERT OR UPDATE OF status
  ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_require_si_vat_registration_status();

CREATE OR REPLACE FUNCTION fn_require_vb_vat_registration_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('approved', 'posted') THEN
    PERFORM fn_validate_vendor_bill_vat_registration(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vb_vat_registration_status ON vendor_bills;
CREATE TRIGGER trg_vb_vat_registration_status
  BEFORE INSERT OR UPDATE OF status
  ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_require_vb_vat_registration_status();

CREATE OR REPLACE FUNCTION fn_require_vat_return_registered_company()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_require_vat_registered_company(NEW.company_id, NEW.return_type || ' return');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vat_returns_registration ON vat_returns;
CREATE TRIGGER trg_vat_returns_registration
  BEFORE INSERT OR UPDATE OF company_id, return_type, status
  ON vat_returns
  FOR EACH ROW EXECUTE FUNCTION fn_require_vat_return_registered_company();
