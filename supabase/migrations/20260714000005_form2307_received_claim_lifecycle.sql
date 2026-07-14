-- PXL-AUD-047: govern Form 2307 received claim lifecycle.
--
-- Received certificates must be recorded through RPC validation against the
-- posted receipt CWT and unreversed CWT tax ledger. Claims must carry an ITR
-- quarter, claimed/invalidated rows must be locked, and receipt bounce must
-- invalidate any linked received-certificate evidence. AP-side EWT reversals
-- flag sent/acknowledged issued certificates for supersede without changing
-- their frozen certificate amounts.

ALTER TABLE form_2307_tracking
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS claimed_by UUID,
  ADD COLUMN IF NOT EXISTS claim_tax_year INT,
  ADD COLUMN IF NOT EXISTS claim_tax_quarter INT,
  ADD COLUMN IF NOT EXISTS invalidated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS invalidated_reason TEXT;

DO $$
DECLARE
  v_name TEXT;
BEGIN
  FOR v_name IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'form_2307_tracking'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE form_2307_tracking DROP CONSTRAINT %I', v_name);
  END LOOP;
END $$;

ALTER TABLE form_2307_tracking
  ADD CONSTRAINT form_2307_tracking_status_check
  CHECK (status IN ('pending', 'received', 'claimed', 'invalidated'));

ALTER TABLE form_2307_tracking
  DROP CONSTRAINT IF EXISTS form_2307_tracking_claim_quarter_check;
ALTER TABLE form_2307_tracking
  ADD CONSTRAINT form_2307_tracking_claim_quarter_check
  CHECK (claim_tax_quarter IS NULL OR claim_tax_quarter BETWEEN 1 AND 4);

UPDATE form_2307_tracking
SET claimed_at = COALESCE(claimed_at, updated_at),
    claimed_by = COALESCE(claimed_by, updated_by),
    claim_tax_quarter = COALESCE(
      claim_tax_quarter,
      CASE WHEN period_covered ~ '^Q[1-4]-[0-9]{4}$'
           THEN SUBSTRING(period_covered FROM 2 FOR 1)::INT END
    ),
    claim_tax_year = COALESCE(
      claim_tax_year,
      CASE WHEN period_covered ~ '^Q[1-4]-[0-9]{4}$'
           THEN RIGHT(period_covered, 4)::INT END
    )
WHERE status = 'claimed';

CREATE OR REPLACE FUNCTION fn_validate_form2307_received_tracking(
  p_company_id UUID,
  p_receipt_line_id UUID,
  p_cwt_amount_booked NUMERIC,
  p_status TEXT,
  p_date_received DATE,
  p_atc_code_id UUID,
  p_period_covered TEXT,
  p_claim_tax_year INT,
  p_claim_tax_quarter INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
  v_line_specific_ledger NUMERIC(15,2);
  v_doc_ledger NUMERIC(15,2);
  v_ledger_available NUMERIC(15,2);
BEGIN
  SELECT
    rl.id AS receipt_line_id,
    rl.cwt_amount,
    rl.atc_code_id,
    r.id AS receipt_id,
    r.company_id,
    r.customer_id,
    r.status AS receipt_status
  INTO v_line
  FROM receipt_lines rl
  JOIN receipts r ON r.id = rl.receipt_id
  WHERE rl.id = p_receipt_line_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Receipt line not found: %', p_receipt_line_id;
  END IF;
  IF v_line.company_id <> p_company_id THEN
    RAISE EXCEPTION 'Form 2307 company does not match the receipt line company';
  END IF;
  IF COALESCE(v_line.cwt_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Form 2307 tracking requires a receipt line with CWT';
  END IF;
  IF p_status NOT IN ('pending', 'received', 'claimed', 'invalidated') THEN
    RAISE EXCEPTION 'Invalid Form 2307 received status: %', p_status;
  END IF;
  IF COALESCE(p_cwt_amount_booked, 0) < 0 THEN
    RAISE EXCEPTION 'Form 2307 certificate amount cannot be negative';
  END IF;
  IF COALESCE(p_cwt_amount_booked, 0) - COALESCE(v_line.cwt_amount, 0) > 0.02 THEN
    RAISE EXCEPTION 'Form 2307 certificate amount % cannot exceed receipt line CWT %',
      p_cwt_amount_booked, v_line.cwt_amount;
  END IF;

  IF p_status IN ('received', 'claimed') THEN
    IF v_line.receipt_status <> 'posted' THEN
      RAISE EXCEPTION 'Only posted, unreversed receipts can support received/claimed Form 2307 records (current receipt status: %)',
        v_line.receipt_status;
    END IF;
    IF p_date_received IS NULL THEN
      RAISE EXCEPTION 'Date received is required for received Form 2307 records';
    END IF;
    IF p_atc_code_id IS NULL THEN
      RAISE EXCEPTION 'ATC code is required for received Form 2307 records';
    END IF;
    IF v_line.atc_code_id IS NOT NULL AND p_atc_code_id <> v_line.atc_code_id THEN
      RAISE EXCEPTION 'Form 2307 ATC must match the receipt line ATC';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM atc_codes ac
      WHERE ac.id = p_atc_code_id
        AND COALESCE(ac.is_active, true)
        AND ac.deprecated_at IS NULL
    ) THEN
      RAISE EXCEPTION 'Form 2307 ATC is inactive or deprecated';
    END IF;
    IF NULLIF(BTRIM(COALESCE(p_period_covered, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Period covered is required for received Form 2307 records';
    END IF;
    IF COALESCE(p_cwt_amount_booked, 0) <= 0 THEN
      RAISE EXCEPTION 'Form 2307 certificate amount must be greater than zero';
    END IF;

    SELECT COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2)
    INTO v_line_specific_ledger
    FROM tax_detail_entries tde
    WHERE tde.source_doc_type = 'OR'
      AND tde.source_doc_id = v_line.receipt_id
      AND tde.source_line_id = p_receipt_line_id
      AND tde.tax_kind = 'cwt_receivable';

    IF v_line_specific_ledger = 0 THEN
      SELECT COALESCE(SUM(tde.tax_amount), 0)::NUMERIC(15,2)
      INTO v_doc_ledger
      FROM tax_detail_entries tde
      WHERE tde.source_doc_type = 'OR'
        AND tde.source_doc_id = v_line.receipt_id
        AND tde.tax_kind = 'cwt_receivable';
      v_ledger_available := v_doc_ledger;
    ELSE
      v_ledger_available := v_line_specific_ledger;
    END IF;

    IF COALESCE(p_cwt_amount_booked, 0) - COALESCE(v_ledger_available, 0) > 0.02 THEN
      RAISE EXCEPTION 'Form 2307 certificate amount % cannot exceed unreversed CWT ledger amount %',
        p_cwt_amount_booked, v_ledger_available;
    END IF;
  END IF;

  IF p_status = 'claimed' THEN
    IF p_claim_tax_year IS NULL OR p_claim_tax_quarter IS NULL THEN
      RAISE EXCEPTION 'Claim tax year and quarter are required before a Form 2307 record can be claimed';
    END IF;
    IF p_claim_tax_quarter NOT BETWEEN 1 AND 4 THEN
      RAISE EXCEPTION 'Invalid claim tax quarter: %', p_claim_tax_quarter;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_guard_form2307_received_tracking()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_internal BOOLEAN := COALESCE(current_setting('pxl.form2307_tracking_internal', true), '') = 'on';
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT v_internal THEN
      RAISE EXCEPTION 'Form 2307 received records must not be deleted; update through controlled RPCs';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status IN ('claimed', 'invalidated') AND NOT v_internal THEN
      RAISE EXCEPTION 'Form 2307 received status % can only be set through controlled RPCs', NEW.status;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.status IN ('claimed', 'invalidated') AND NOT v_internal THEN
      RAISE EXCEPTION 'Form 2307 received record % is locked in status %', OLD.id, OLD.status;
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status
       AND NEW.status IN ('claimed', 'invalidated')
       AND NOT v_internal THEN
      RAISE EXCEPTION 'Form 2307 received status % can only be set through controlled RPCs', NEW.status;
    END IF;
  END IF;

  PERFORM fn_validate_form2307_received_tracking(
    NEW.company_id,
    NEW.receipt_line_id,
    NEW.cwt_amount_booked,
    NEW.status,
    NEW.date_received,
    NEW.atc_code_id,
    NEW.period_covered,
    NEW.claim_tax_year,
    NEW.claim_tax_quarter
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_form2307_received_tracking ON form_2307_tracking;
CREATE TRIGGER trg_guard_form2307_received_tracking
BEFORE INSERT OR UPDATE OR DELETE ON form_2307_tracking
FOR EACH ROW
EXECUTE FUNCTION fn_guard_form2307_received_tracking();

CREATE OR REPLACE FUNCTION fn_record_form2307_received(
  p_receipt_line_id UUID,
  p_date_received DATE,
  p_atc_code_id UUID,
  p_period_covered TEXT,
  p_file_url TEXT DEFAULT NULL,
  p_remarks TEXT DEFAULT NULL,
  p_certificate_amount NUMERIC DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line RECORD;
  v_existing form_2307_tracking%ROWTYPE;
  v_id UUID;
  v_amount NUMERIC(15,2);
  v_previous_internal TEXT;
BEGIN
  SELECT
    rl.id AS receipt_line_id,
    rl.cwt_amount,
    r.company_id,
    r.customer_id
  INTO v_line
  FROM receipt_lines rl
  JOIN receipts r ON r.id = rl.receipt_id
  WHERE rl.id = p_receipt_line_id
  FOR UPDATE OF rl;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Receipt line not found: %', p_receipt_line_id;
  END IF;
  IF NOT is_company_member(v_line.company_id) THEN
    RAISE EXCEPTION 'Access denied for Form 2307 received record';
  END IF;

  SELECT * INTO v_existing
  FROM form_2307_tracking
  WHERE receipt_line_id = p_receipt_line_id
  FOR UPDATE;

  IF FOUND AND v_existing.status IN ('claimed', 'invalidated') THEN
    RAISE EXCEPTION 'Form 2307 received record % is already % and cannot be edited',
      v_existing.id, v_existing.status;
  END IF;

  v_amount := ROUND(COALESCE(p_certificate_amount, v_line.cwt_amount), 2);

  PERFORM fn_validate_form2307_received_tracking(
    v_line.company_id, p_receipt_line_id, v_amount, 'received',
    p_date_received, p_atc_code_id, p_period_covered, NULL, NULL
  );

  v_previous_internal := current_setting('pxl.form2307_tracking_internal', true);
  PERFORM set_config('pxl.form2307_tracking_internal', 'on', true);

  BEGIN
    INSERT INTO form_2307_tracking (
      company_id, receipt_line_id, customer_id, cwt_amount_booked,
      status, date_received, atc_code_id, period_covered, file_url, remarks,
      created_by, updated_by
    )
    VALUES (
      v_line.company_id, p_receipt_line_id, v_line.customer_id, v_amount,
      'received', p_date_received, p_atc_code_id,
      NULLIF(BTRIM(COALESCE(p_period_covered, '')), ''),
      NULLIF(BTRIM(COALESCE(p_file_url, '')), ''),
      NULLIF(BTRIM(COALESCE(p_remarks, '')), ''),
      auth.uid(), auth.uid()
    )
    ON CONFLICT (receipt_line_id)
    DO UPDATE SET
      customer_id = EXCLUDED.customer_id,
      cwt_amount_booked = EXCLUDED.cwt_amount_booked,
      status = 'received',
      date_received = EXCLUDED.date_received,
      atc_code_id = EXCLUDED.atc_code_id,
      period_covered = EXCLUDED.period_covered,
      file_url = EXCLUDED.file_url,
      remarks = EXCLUDED.remarks,
      updated_by = auth.uid(),
      updated_at = NOW()
    RETURNING id INTO v_id;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('pxl.form2307_tracking_internal', COALESCE(v_previous_internal, ''), true);
    RAISE;
  END;

  PERFORM set_config('pxl.form2307_tracking_internal', COALESCE(v_previous_internal, ''), true);

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_claim_form2307_received(
  p_tracking_id UUID,
  p_claim_tax_year INT,
  p_claim_tax_quarter INT,
  p_claimed_date DATE DEFAULT CURRENT_DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec form_2307_tracking%ROWTYPE;
  v_previous_internal TEXT;
BEGIN
  SELECT * INTO v_rec
  FROM form_2307_tracking
  WHERE id = p_tracking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Form 2307 received record not found: %', p_tracking_id;
  END IF;
  IF NOT can_admin_company(v_rec.company_id) THEN
    RAISE EXCEPTION 'Access denied: owner/admin role required to claim Form 2307 received records';
  END IF;
  IF v_rec.status <> 'received' THEN
    RAISE EXCEPTION 'Only received Form 2307 records can be claimed (current status: %)', v_rec.status;
  END IF;
  IF p_claim_tax_quarter NOT BETWEEN 1 AND 4 THEN
    RAISE EXCEPTION 'Invalid claim tax quarter: %', p_claim_tax_quarter;
  END IF;
  IF p_claimed_date IS NOT NULL AND v_rec.date_received IS NOT NULL
     AND p_claimed_date < v_rec.date_received THEN
    RAISE EXCEPTION 'Claim date cannot be before the certificate received date';
  END IF;

  PERFORM fn_validate_form2307_received_tracking(
    v_rec.company_id, v_rec.receipt_line_id, v_rec.cwt_amount_booked,
    'claimed', v_rec.date_received, v_rec.atc_code_id, v_rec.period_covered,
    p_claim_tax_year, p_claim_tax_quarter
  );

  v_previous_internal := current_setting('pxl.form2307_tracking_internal', true);
  PERFORM set_config('pxl.form2307_tracking_internal', 'on', true);

  BEGIN
    UPDATE form_2307_tracking
    SET status = 'claimed',
        claim_tax_year = p_claim_tax_year,
        claim_tax_quarter = p_claim_tax_quarter,
        claimed_at = COALESCE(p_claimed_date, CURRENT_DATE)::TIMESTAMPTZ,
        claimed_by = auth.uid(),
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE id = v_rec.id;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('pxl.form2307_tracking_internal', COALESCE(v_previous_internal, ''), true);
    RAISE;
  END;

  PERFORM set_config('pxl.form2307_tracking_internal', COALESCE(v_previous_internal, ''), true);
END;
$$;

CREATE OR REPLACE FUNCTION fn_invalidate_form2307_received_for_receipt(
  p_receipt_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt receipts%ROWTYPE;
  v_reason TEXT := NULLIF(BTRIM(COALESCE(p_reason, '')), '');
  v_previous_internal TEXT;
BEGIN
  SELECT * INTO v_receipt
  FROM receipts
  WHERE id = p_receipt_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Receipt not found: %', p_receipt_id;
  END IF;

  v_previous_internal := current_setting('pxl.form2307_tracking_internal', true);
  PERFORM set_config('pxl.form2307_tracking_internal', 'on', true);

  BEGIN
    UPDATE form_2307_tracking ft
    SET status = 'invalidated',
        invalidated_at = NOW(),
        invalidated_reason = COALESCE(v_reason, 'Receipt was bounced/reversed'),
        updated_by = COALESCE(auth.uid(), ft.updated_by),
        updated_at = NOW()
    FROM receipt_lines rl
    WHERE rl.id = ft.receipt_line_id
      AND rl.receipt_id = p_receipt_id
      AND ft.status IN ('pending', 'received', 'claimed');
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('pxl.form2307_tracking_internal', COALESCE(v_previous_internal, ''), true);
    RAISE;
  END;

  PERFORM set_config('pxl.form2307_tracking_internal', COALESCE(v_previous_internal, ''), true);
END;
$$;

-- Route application writes through RPCs; SELECT remains governed by the
-- existing company-scoped read policy.
DROP POLICY IF EXISTS "insert_form_2307_tracking" ON form_2307_tracking;
DROP POLICY IF EXISTS "update_form_2307_tracking" ON form_2307_tracking;
DROP POLICY IF EXISTS "delete_form_2307_tracking" ON form_2307_tracking;
DROP POLICY IF EXISTS "insert_form_2307_tracking_rpc_only" ON form_2307_tracking;
CREATE POLICY "insert_form_2307_tracking_rpc_only" ON form_2307_tracking
  FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS "update_form_2307_tracking_rpc_only" ON form_2307_tracking;
CREATE POLICY "update_form_2307_tracking_rpc_only" ON form_2307_tracking
  FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "delete_form_2307_tracking_rpc_only" ON form_2307_tracking;
CREATE POLICY "delete_form_2307_tracking_rpc_only" ON form_2307_tracking
  FOR DELETE TO authenticated USING (false);

CREATE OR REPLACE FUNCTION fn_bounce_receipt(p_receipt_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec receipts%ROWTYPE;
  v_reversal_id UUID;
  v_period_id UUID;
BEGIN
  SELECT * INTO v_rec
  FROM receipts
  WHERE id = p_receipt_id
  FOR UPDATE;
  IF NOT FOUND OR NOT is_company_member(v_rec.company_id) THEN
    RAISE EXCEPTION 'Receipt not found or access denied';
  END IF;
  IF v_rec.status <> 'posted' OR v_rec.journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Only posted receipts can be marked as bounced (current status: %)', v_rec.status;
  END IF;
  PERFORM fn_assert_source_journal_link(
    'OR', v_rec.id, v_rec.journal_entry_id, v_rec.company_id
  );

  v_reversal_id := fn_reverse_posted_journal_entry(
    v_rec.journal_entry_id, CURRENT_DATE,
    'REV', v_rec.id,
    'JE-REV-' || v_rec.receipt_number,
    'Bounced Receipt ' || v_rec.receipt_number
  );
  SELECT fiscal_period_id INTO v_period_id
  FROM journal_entries WHERE id = v_reversal_id;
  PERFORM fn_reverse_tax_detail_entries('OR', v_rec.id, CURRENT_DATE, v_period_id);
  PERFORM fn_invalidate_form2307_received_for_receipt(
    v_rec.id,
    'Receipt ' || v_rec.receipt_number || ' bounced on ' || CURRENT_DATE::TEXT
  );

  UPDATE receipts
  SET status = 'bounced', updated_by = auth.uid(), updated_at = NOW()
  WHERE id = v_rec.id;

  PERFORM fn_record_posting_event(
    v_rec.company_id, 'OR', v_rec.id, 'BOUNCED', v_reversal_id,
    jsonb_build_object('reversal_date', CURRENT_DATE)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_record_form2307_received(UUID, DATE, UUID, TEXT, TEXT, TEXT, NUMERIC) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_claim_form2307_received(UUID, INT, INT, DATE) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_bounce_receipt(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION fn_validate_form2307_received_tracking(UUID, UUID, NUMERIC, TEXT, DATE, UUID, TEXT, INT, INT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_guard_form2307_received_tracking() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_invalidate_form2307_received_for_receipt(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- Issued-side stale prompt: sent/acknowledged certificates remain immutable
-- evidence, but upstream EWT reversals flag them for supersede.
ALTER TABLE form_2307_issuances
  ADD COLUMN IF NOT EXISTS requires_supersede BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS supersede_required_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS supersede_reason TEXT;

CREATE OR REPLACE FUNCTION fn_form2307_report_payload(p_issuance form_2307_issuances)
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', p_issuance.id,
    'company_id', p_issuance.company_id,
    'supplier_id', p_issuance.supplier_id,
    'tax_year', p_issuance.tax_year,
    'tax_quarter', p_issuance.tax_quarter,
    'total_tax_base', p_issuance.total_tax_base,
    'total_ewt', p_issuance.total_ewt,
    'status', p_issuance.status,
    'version', p_issuance.version,
    'date_generated', p_issuance.date_generated,
    'date_sent', p_issuance.date_sent,
    'date_acknowledged', p_issuance.date_acknowledged,
    'supersedes_issuance_id', p_issuance.supersedes_issuance_id,
    'superseded_by_issuance_id', p_issuance.superseded_by_issuance_id,
    'superseded_at', p_issuance.superseded_at,
    'requires_supersede', p_issuance.requires_supersede,
    'supersede_required_at', p_issuance.supersede_required_at,
    'supersede_reason', p_issuance.supersede_reason
  );
$$;

CREATE OR REPLACE FUNCTION fn_flag_form2307_issued_for_ewt_reversal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_original tax_detail_entries%ROWTYPE;
  v_tax_year INT;
  v_tax_quarter INT;
  v_reason TEXT;
BEGIN
  IF NEW.tax_kind <> 'ewt_payable'
     OR NEW.is_reversal IS DISTINCT FROM true
     OR NEW.reverses_tax_detail_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_original
  FROM tax_detail_entries
  WHERE id = NEW.reverses_tax_detail_id;

  IF NOT FOUND OR v_original.counterparty_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_tax_year := EXTRACT(YEAR FROM v_original.document_date)::INT;
  v_tax_quarter := FLOOR((EXTRACT(MONTH FROM v_original.document_date)::INT - 1) / 3)::INT + 1;
  v_reason := 'EWT source ' || v_original.source_doc_type || ' reversed on ' || NEW.document_date::TEXT
    || '; supersede the affected Form 2307 certificate.';

  UPDATE form_2307_issuances f
  SET requires_supersede = true,
      supersede_required_at = COALESCE(f.supersede_required_at, NOW()),
      supersede_reason = COALESCE(f.supersede_reason, v_reason),
      updated_by = COALESCE(auth.uid(), f.updated_by),
      updated_at = NOW()
  WHERE f.company_id = v_original.company_id
    AND f.supplier_id = v_original.counterparty_id
    AND f.tax_year = v_tax_year
    AND f.tax_quarter = v_tax_quarter
    AND f.status IN ('sent', 'acknowledged')
    AND f.superseded_by_issuance_id IS NULL;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_flag_form2307_issued_for_ewt_reversal ON tax_detail_entries;
CREATE TRIGGER trg_flag_form2307_issued_for_ewt_reversal
AFTER INSERT ON tax_detail_entries
FOR EACH ROW
EXECUTE FUNCTION fn_flag_form2307_issued_for_ewt_reversal();

REVOKE ALL ON FUNCTION fn_flag_form2307_issued_for_ewt_reversal() FROM PUBLIC, anon, authenticated;
