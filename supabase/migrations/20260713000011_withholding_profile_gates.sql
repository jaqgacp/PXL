-- PXL-AUD-042: withholding profile gates + TWA auto-EWT defaults.
--
-- The compliance profile now controls AP-side EWT payable writes. An active
-- profile with ewt_registered = false blocks VB/PV/CV EWT payable. Companies
-- without a profile keep legacy behavior until setup makes the profile explicit.
-- TWA auto-defaulting requires ewt_registered, is_twa, and twa_auto_ewt_enabled.

-- ATC history must include vendor-bill source-EWT line references introduced
-- by PXL-AUD-037, otherwise a used ATC could still be edited after VB use.
CREATE OR REPLACE FUNCTION fn_atc_code_used(p_atc_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM receipt_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM payment_voucher_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM vendor_bill_lines WHERE ewt_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM tax_detail_entries WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM form_2307_issuance_lines WHERE atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM customers WHERE default_cwt_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM suppliers WHERE default_atc_code_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM ewt_codes WHERE atc_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM fwt_codes WHERE atc_id = p_atc_id)
      OR EXISTS (SELECT 1 FROM percentage_tax_codes WHERE atc_id = p_atc_id);
END;
$$;

-- The original seed carried WC160 as a 6% real-estate EWT row, but the BIR
-- 1601-EQ/2307 ATC list uses WC160 for TWA purchases of services at 2%.
DO $$
DECLARE
  v_start CONSTANT DATE := DATE '2026-07-13';
  v_atc atc_codes%ROWTYPE;
BEGIN
  SELECT *
  INTO v_atc
  FROM atc_codes
  WHERE code = 'WC158'
    AND tax_category = 'ewt'
    AND is_active = true
    AND deprecated_at IS NULL
    AND effective_from <= v_start
    AND (effective_to IS NULL OR effective_to >= v_start)
  ORDER BY effective_from DESC
  LIMIT 1;

  IF FOUND AND (v_atc.rate IS DISTINCT FROM 1.00 OR COALESCE(v_atc.description, '') NOT ILIKE '%goods%') THEN
    IF NOT fn_atc_code_used(v_atc.id) THEN
      UPDATE atc_codes
      SET description = 'Purchases of goods by Top Withholding Agents - juridical persons',
          rate = 1.00,
          is_active = true,
          deprecated_at = NULL,
          effective_to = NULL,
          updated_at = NOW()
      WHERE id = v_atc.id;
    ELSE
      UPDATE atc_codes
      SET effective_to = v_start - 1,
          updated_at = NOW()
      WHERE id = v_atc.id
        AND (effective_to IS NULL OR effective_to >= v_start);

      INSERT INTO atc_codes (code, description, tax_category, rate, is_active,
                             effective_from, supersedes_atc_code_id)
      VALUES ('WC158',
              'Purchases of goods by Top Withholding Agents - juridical persons',
              'ewt', 1.00, true, v_start, v_atc.id)
      ON CONFLICT (code, tax_category, effective_from) DO NOTHING;
    END IF;
  ELSIF NOT FOUND THEN
    INSERT INTO atc_codes (code, description, tax_category, rate, is_active, effective_from)
    VALUES ('WC158',
            'Purchases of goods by Top Withholding Agents - juridical persons',
            'ewt', 1.00, true, DATE '1900-01-01')
    ON CONFLICT (code, tax_category, effective_from) DO NOTHING;
  END IF;

  SELECT *
  INTO v_atc
  FROM atc_codes
  WHERE code = 'WC160'
    AND tax_category = 'ewt'
    AND is_active = true
    AND deprecated_at IS NULL
    AND effective_from <= v_start
    AND (effective_to IS NULL OR effective_to >= v_start)
  ORDER BY effective_from DESC
  LIMIT 1;

  IF FOUND AND (v_atc.rate IS DISTINCT FROM 2.00 OR COALESCE(v_atc.description, '') NOT ILIKE '%services%') THEN
    IF NOT fn_atc_code_used(v_atc.id) THEN
      UPDATE atc_codes
      SET description = 'Purchases of services by Top Withholding Agents - juridical persons',
          rate = 2.00,
          is_active = true,
          deprecated_at = NULL,
          effective_to = NULL,
          updated_at = NOW()
      WHERE id = v_atc.id;
    ELSE
      UPDATE atc_codes
      SET effective_to = v_start - 1,
          updated_at = NOW()
      WHERE id = v_atc.id
        AND (effective_to IS NULL OR effective_to >= v_start);

      INSERT INTO atc_codes (code, description, tax_category, rate, is_active,
                             effective_from, supersedes_atc_code_id)
      VALUES ('WC160',
              'Purchases of services by Top Withholding Agents - juridical persons',
              'ewt', 2.00, true, v_start, v_atc.id)
      ON CONFLICT (code, tax_category, effective_from) DO NOTHING;
    END IF;
  ELSIF NOT FOUND THEN
    INSERT INTO atc_codes (code, description, tax_category, rate, is_active, effective_from)
    VALUES ('WC160',
            'Purchases of services by Top Withholding Agents - juridical persons',
            'ewt', 2.00, true, DATE '1900-01-01')
    ON CONFLICT (code, tax_category, effective_from) DO NOTHING;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_company_ewt_payable_enabled(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT cp.ewt_registered
      FROM compliance_profiles cp
      WHERE cp.company_id = p_company_id
        AND cp.is_active = true
      LIMIT 1
    ),
    true
  );
$$;

CREATE OR REPLACE FUNCTION fn_require_company_ewt_payable_enabled(
  p_company_id UUID,
  p_context TEXT DEFAULT 'This transaction'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT fn_company_ewt_payable_enabled(p_company_id) THEN
    RAISE EXCEPTION 'Company is not EWT-registered; % cannot record EWT payable. Enable EWT registration in the compliance profile.',
      COALESCE(NULLIF(BTRIM(p_context), ''), 'this transaction');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_company_twa_auto_ewt_enabled(
  p_company_id UUID,
  p_document_date DATE DEFAULT CURRENT_DATE
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT cp.ewt_registered
         AND cp.is_twa
         AND cp.twa_auto_ewt_enabled
         AND (cp.twa_effective_date IS NULL OR cp.twa_effective_date <= COALESCE(p_document_date, CURRENT_DATE))
      FROM compliance_profiles cp
      WHERE cp.company_id = p_company_id
        AND cp.is_active = true
      LIMIT 1
    ),
    false
  );
$$;

CREATE OR REPLACE FUNCTION fn_twa_ewt_atc_asof(
  p_line_kind TEXT,
  p_document_date DATE DEFAULT CURRENT_DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_kind TEXT := lower(BTRIM(COALESCE(p_line_kind, 'services')));
  v_code TEXT;
  v_rate NUMERIC(8,4);
  v_atc UUID;
  v_as_of DATE := COALESCE(p_document_date, CURRENT_DATE);
BEGIN
  IF v_kind = 'goods' THEN
    v_code := 'WC158';
    v_rate := 1.00;
  ELSE
    v_code := 'WC160';
    v_rate := 2.00;
  END IF;

  SELECT id
  INTO v_atc
  FROM atc_codes
  WHERE code = v_code
    AND tax_category = 'ewt'
    AND is_active = true
    AND deprecated_at IS NULL
    AND ABS(rate - v_rate) < 0.0001
    AND effective_from <= v_as_of
    AND (effective_to IS NULL OR effective_to >= v_as_of)
  ORDER BY effective_from DESC
  LIMIT 1;

  IF v_atc IS NULL THEN
    RAISE EXCEPTION 'TWA % ATC % at % percent is not available or effective on document date %.',
      v_kind, v_code, v_rate, v_as_of;
  END IF;

  RETURN v_atc;
END;
$$;

CREATE OR REPLACE FUNCTION fn_apply_vendor_bill_line_ewt_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bill_company UUID;
  v_bill_date DATE;
  v_supplier_id UUID;
  v_policy TEXT;
  v_supplier_ewt BOOLEAN := false;
  v_supplier_atc UUID;
  v_has_ewt BOOLEAN;
  v_kind TEXT := 'services';
  v_rate NUMERIC(8,4);
  v_description TEXT;
BEGIN
  SELECT vb.company_id, vb.bill_date, vb.supplier_id, fn_company_ap_ewt_policy(vb.company_id)
  INTO v_bill_company, v_bill_date, v_supplier_id, v_policy
  FROM vendor_bills vb
  WHERE vb.id = NEW.vendor_bill_id;

  IF v_bill_company IS NULL THEN
    RAISE EXCEPTION 'Vendor bill not found for EWT validation.';
  END IF;
  IF NEW.company_id IS DISTINCT FROM v_bill_company THEN
    RAISE EXCEPTION 'Vendor bill line company does not match its vendor bill.';
  END IF;

  SELECT COALESCE(s.is_subject_to_ewt, false), s.default_atc_code_id
  INTO v_supplier_ewt, v_supplier_atc
  FROM suppliers s
  WHERE s.id = v_supplier_id
    AND s.company_id = NEW.company_id;

  v_has_ewt := NEW.ewt_atc_code_id IS NOT NULL
            OR NEW.ewt_tax_base IS NOT NULL
            OR COALESCE(NEW.ewt_amount, 0) > 0;

  IF v_policy = 'accrual_at_source'
     AND NOT v_has_ewt
     AND COALESCE(v_supplier_ewt, false) THEN
    IF v_supplier_atc IS NOT NULL THEN
      NEW.ewt_atc_code_id := v_supplier_atc;
    ELSIF fn_company_twa_auto_ewt_enabled(NEW.company_id, v_bill_date) THEN
      SELECT CASE WHEN i.item_type = 'inventory_item' THEN 'goods' ELSE 'services' END
      INTO v_kind
      FROM items i
      WHERE i.id = NEW.item_id
        AND i.company_id = NEW.company_id;

      NEW.ewt_atc_code_id := fn_twa_ewt_atc_asof(COALESCE(v_kind, 'services'), v_bill_date);
    END IF;
  END IF;

  IF NEW.ewt_atc_code_id IS NOT NULL THEN
    SELECT ac.rate, ac.description
    INTO v_rate, v_description
    FROM atc_codes ac
    WHERE ac.id = NEW.ewt_atc_code_id
      AND ac.is_active = true
      AND ac.deprecated_at IS NULL
      AND ac.tax_category = 'ewt'
      AND ac.effective_from <= v_bill_date
      AND (ac.effective_to IS NULL OR ac.effective_to >= v_bill_date);

    IF v_rate IS NULL THEN
      RAISE EXCEPTION 'ATC code is inactive, expired, deprecated, missing, or not effective on vendor bill date %.', v_bill_date;
    END IF;

    NEW.ewt_tax_base := ROUND(COALESCE(NEW.ewt_tax_base, NEW.net_amount, 0), 2);
    IF COALESCE(NEW.ewt_amount, 0) = 0 AND COALESCE(NEW.ewt_tax_base, 0) > 0 THEN
      NEW.ewt_amount := ROUND(NEW.ewt_tax_base * v_rate / 100.0, 2);
    END IF;
    NEW.ewt_income_nature := COALESCE(
      NULLIF(BTRIM(NEW.ewt_income_nature), ''),
      NULLIF(BTRIM(NEW.description), ''),
      v_description
    );
  END IF;

  v_has_ewt := NEW.ewt_atc_code_id IS NOT NULL
            OR NEW.ewt_tax_base IS NOT NULL
            OR COALESCE(NEW.ewt_amount, 0) > 0;

  IF v_has_ewt THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Vendor bill');

    IF v_policy <> 'accrual_at_source' THEN
      RAISE EXCEPTION 'Vendor bill source EWT is disabled by AP EWT policy %. Use payment voucher EWT instead.',
        v_policy;
    END IF;

    PERFORM fn_validate_payment_voucher_line_ewt(
      NEW.company_id,
      0,
      COALESCE(NEW.ewt_amount, 0),
      NEW.ewt_atc_code_id,
      NEW.ewt_tax_base,
      NEW.ewt_variance_reason,
      v_bill_date
    );
  END IF;

  NEW.ewt_amount := COALESCE(NEW.ewt_amount, 0);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vendor_bill_line_ewt_profile ON vendor_bill_lines;
CREATE TRIGGER trg_vendor_bill_line_ewt_profile
  BEFORE INSERT OR UPDATE OF company_id, vendor_bill_id, item_id, description,
    net_amount, ewt_atc_code_id, ewt_tax_base, ewt_amount,
    ewt_income_nature, ewt_variance_reason
  ON vendor_bill_lines
  FOR EACH ROW EXECUTE FUNCTION fn_apply_vendor_bill_line_ewt_profile();

CREATE OR REPLACE FUNCTION fn_sync_vendor_bill_ewt_expected()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line_ewt NUMERIC(15,2);
BEGIN
  IF fn_company_ap_ewt_policy(NEW.company_id) = 'accrual_at_source' THEN
    SELECT COALESCE(SUM(vbl.ewt_amount), 0)::NUMERIC(15,2)
    INTO v_line_ewt
    FROM vendor_bill_lines vbl
    WHERE vbl.vendor_bill_id = NEW.id;

    NEW.ewt_amount_expected := ROUND(COALESCE(v_line_ewt, 0), 2);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vendor_bill_sync_ewt_expected ON vendor_bills;
CREATE TRIGGER trg_vendor_bill_sync_ewt_expected
  BEFORE UPDATE OF total_taxable_amount, total_zero_rated_amount,
    total_exempt_amount, total_input_vat_amount, total_amount, ewt_amount_expected
  ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_sync_vendor_bill_ewt_expected();

CREATE OR REPLACE FUNCTION fn_require_vendor_bill_post_ewt_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'posted'
     AND OLD.status IS DISTINCT FROM NEW.status
     AND EXISTS (
       SELECT 1
       FROM vendor_bill_lines vbl
       WHERE vbl.vendor_bill_id = NEW.id
         AND (
           COALESCE(vbl.ewt_amount, 0) > 0
           OR vbl.ewt_atc_code_id IS NOT NULL
           OR vbl.ewt_tax_base IS NOT NULL
         )
     ) THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Vendor bill posting');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vendor_bill_post_ewt_profile ON vendor_bills;
CREATE TRIGGER trg_vendor_bill_post_ewt_profile
  BEFORE UPDATE OF status ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_require_vendor_bill_post_ewt_profile();

CREATE OR REPLACE FUNCTION fn_require_pvl_ewt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_document_date DATE;
BEGIN
  SELECT voucher_date INTO v_document_date
  FROM payment_vouchers WHERE id = NEW.payment_voucher_id;

  IF COALESCE(NEW.ewt_amount, 0) > 0
     OR NEW.atc_code_id IS NOT NULL
     OR NEW.ewt_tax_base IS NOT NULL THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Payment voucher');
  END IF;

  IF NEW.vendor_bill_id IS NOT NULL
     AND fn_vendor_bill_has_accrued_ewt(NEW.vendor_bill_id)
     AND (
       COALESCE(NEW.ewt_amount, 0) > 0
       OR NEW.atc_code_id IS NOT NULL
       OR NEW.ewt_tax_base IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Vendor bill % already accrued EWT at source; do not withhold EWT again on the payment voucher.',
      NEW.vendor_bill_id;
  END IF;

  PERFORM fn_validate_payment_voucher_line_ewt(
    NEW.company_id,
    NEW.payment_amount,
    NEW.ewt_amount,
    NEW.atc_code_id,
    NEW.ewt_tax_base,
    NEW.ewt_variance_reason,
    v_document_date
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pvl_ewt_validation ON payment_voucher_lines;
CREATE TRIGGER trg_pvl_ewt_validation
  BEFORE INSERT OR UPDATE OF payment_voucher_id, vendor_bill_id, payment_amount,
    ewt_amount, atc_code_id, company_id, ewt_tax_base, ewt_variance_reason
  ON payment_voucher_lines
  FOR EACH ROW EXECUTE FUNCTION fn_require_pvl_ewt_validation();

CREATE OR REPLACE FUNCTION fn_validate_payment_voucher_ewt_ready(p_voucher_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line          RECORD;
  v_company_id    UUID;
  v_header_ewt    NUMERIC(15,2);
  v_line_ewt      NUMERIC(15,2);
  v_header_cash   NUMERIC(15,2);
  v_line_cash     NUMERIC(15,2);
  v_document_date DATE;
BEGIN
  SELECT company_id, COALESCE(total_ewt, 0), COALESCE(total_amount, 0), voucher_date
  INTO v_company_id, v_header_ewt, v_header_cash, v_document_date
  FROM payment_vouchers WHERE id = p_voucher_id;

  IF v_document_date IS NULL THEN
    RAISE EXCEPTION 'Payment voucher not found.';
  END IF;

  SELECT COALESCE(SUM(ewt_amount), 0), COALESCE(SUM(payment_amount), 0)
  INTO v_line_ewt, v_line_cash
  FROM payment_voucher_lines WHERE payment_voucher_id = p_voucher_id;

  IF v_header_ewt > 0
     OR EXISTS (
       SELECT 1
       FROM payment_voucher_lines pvl
       WHERE pvl.payment_voucher_id = p_voucher_id
         AND (
           COALESCE(pvl.ewt_amount, 0) > 0
           OR pvl.atc_code_id IS NOT NULL
           OR pvl.ewt_tax_base IS NOT NULL
         )
     ) THEN
    PERFORM fn_require_company_ewt_payable_enabled(v_company_id, 'Payment voucher posting');
  END IF;

  IF ABS(v_header_ewt - v_line_ewt) > 0.02 THEN
    RAISE EXCEPTION 'Payment voucher total EWT % does not match line EWT total %.', v_header_ewt, v_line_ewt;
  END IF;

  IF ABS(v_header_cash - v_line_cash) > 0.02 THEN
    RAISE EXCEPTION 'Payment voucher total amount % does not match line payment total %.', v_header_cash, v_line_cash;
  END IF;

  FOR v_line IN
    SELECT company_id, vendor_bill_id, payment_amount, ewt_amount, atc_code_id, ewt_tax_base, ewt_variance_reason
    FROM payment_voucher_lines WHERE payment_voucher_id = p_voucher_id
  LOOP
    IF v_line.vendor_bill_id IS NOT NULL
       AND fn_vendor_bill_has_accrued_ewt(v_line.vendor_bill_id)
       AND (
         COALESCE(v_line.ewt_amount, 0) > 0
         OR v_line.atc_code_id IS NOT NULL
         OR v_line.ewt_tax_base IS NOT NULL
       ) THEN
      RAISE EXCEPTION 'Vendor bill % already accrued EWT at source; do not withhold EWT again on the payment voucher.',
        v_line.vendor_bill_id;
    END IF;

    PERFORM fn_validate_payment_voucher_line_ewt(
      v_line.company_id,
      v_line.payment_amount,
      v_line.ewt_amount,
      v_line.atc_code_id,
      v_line.ewt_tax_base,
      v_line.ewt_variance_reason,
      v_document_date
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_payment_voucher_post_ewt_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'posted'
     AND OLD.status IS DISTINCT FROM NEW.status
     AND (
       COALESCE(NEW.total_ewt, 0) > 0
       OR EXISTS (
         SELECT 1
         FROM payment_voucher_lines pvl
         WHERE pvl.payment_voucher_id = NEW.id
           AND (
             COALESCE(pvl.ewt_amount, 0) > 0
             OR pvl.atc_code_id IS NOT NULL
             OR pvl.ewt_tax_base IS NOT NULL
           )
       )
     ) THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Payment voucher posting');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_voucher_post_ewt_profile ON payment_vouchers;
CREATE TRIGGER trg_payment_voucher_post_ewt_profile
  BEFORE UPDATE OF status ON payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_payment_voucher_post_ewt_profile();

CREATE OR REPLACE FUNCTION fn_require_cv_ewt_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.supplier_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM suppliers WHERE id = NEW.supplier_id AND company_id = NEW.company_id
  ) THEN
    RAISE EXCEPTION 'Supplier does not belong to this company';
  END IF;

  IF COALESCE(NEW.total_ewt_amount, 0) > 0
     OR NEW.atc_code_id IS NOT NULL
     OR NEW.ewt_tax_base IS NOT NULL THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Check voucher');
  END IF;

  IF COALESCE(NEW.total_ewt_amount, 0) > 0 AND NEW.supplier_id IS NULL THEN
    RAISE EXCEPTION 'A supplier is required when EWT is withheld on a check voucher (Form 2307 traceability).';
  END IF;

  PERFORM fn_validate_payment_voucher_line_ewt(
    NEW.company_id,
    COALESCE(NEW.total_gross_amount, 0) - COALESCE(NEW.total_ewt_amount, 0),
    NEW.total_ewt_amount,
    NEW.atc_code_id,
    NEW.ewt_tax_base,
    NEW.ewt_variance_reason,
    NEW.voucher_date
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cv_ewt_validation ON check_vouchers;
CREATE TRIGGER trg_cv_ewt_validation
  BEFORE INSERT OR UPDATE OF company_id, supplier_id, voucher_date, total_gross_amount,
    total_ewt_amount, atc_code_id, ewt_tax_base, ewt_variance_reason
  ON check_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_cv_ewt_validation();

CREATE OR REPLACE FUNCTION fn_require_check_voucher_post_ewt_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('posted', 'released')
     AND OLD.status IS DISTINCT FROM NEW.status
     AND (
       COALESCE(NEW.total_ewt_amount, 0) > 0
       OR NEW.atc_code_id IS NOT NULL
       OR NEW.ewt_tax_base IS NOT NULL
     ) THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'Check voucher posting');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_voucher_post_ewt_profile ON check_vouchers;
CREATE TRIGGER trg_check_voucher_post_ewt_profile
  BEFORE UPDATE OF status ON check_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_require_check_voucher_post_ewt_profile();

CREATE OR REPLACE FUNCTION fn_require_ewt_return_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, '1601EQ/EWT return');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ewt_return_profile ON ewt_returns;
CREATE TRIGGER trg_ewt_return_profile
  BEFORE INSERT OR UPDATE ON ewt_returns
  FOR EACH ROW EXECUTE FUNCTION fn_require_ewt_return_profile();

CREATE OR REPLACE FUNCTION fn_require_wht_export_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.source_table = 'wht_export_periods'
     AND upper(NEW.report_type) = 'QAP' THEN
    PERFORM fn_require_company_ewt_payable_enabled(NEW.company_id, 'QAP export');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wht_export_profile ON report_snapshots;
CREATE TRIGGER trg_wht_export_profile
  BEFORE INSERT OR UPDATE ON report_snapshots
  FOR EACH ROW EXECUTE FUNCTION fn_require_wht_export_profile();

GRANT EXECUTE ON FUNCTION fn_atc_code_used(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_company_ewt_payable_enabled(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_require_company_ewt_payable_enabled(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_company_twa_auto_ewt_enabled(UUID, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_twa_ewt_atc_asof(TEXT, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_validate_payment_voucher_ewt_ready(UUID) TO authenticated, service_role;
