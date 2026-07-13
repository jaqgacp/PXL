-- End-to-end CAS controls: accountable numbering, void register, exact DAT
-- artifacts, and a server-attested audit package (PXL-DA-019).

CREATE TABLE cas_document_number_issuances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  branch_id UUID REFERENCES branches(id),
  number_series_id UUID REFERENCES number_series(id),
  document_code TEXT NOT NULL,
  sequence_number BIGINT,
  document_number TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'reserved'
    CHECK (status IN ('reserved', 'issued', 'voided', 'abandoned')),
  source_table TEXT,
  source_id UUID,
  reserved_by UUID,
  reserved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  issued_at TIMESTAMPTZ,
  voided_at TIMESTAMPTZ,
  void_reason TEXT,
  UNIQUE (company_id, branch_id, document_code, document_number),
  UNIQUE (number_series_id, sequence_number),
  UNIQUE (source_table, source_id)
);

CREATE INDEX idx_cas_number_issuances_company_period
  ON cas_document_number_issuances (company_id, reserved_at DESC);

ALTER TABLE cas_document_number_issuances ENABLE ROW LEVEL SECURITY;
CREATE POLICY cas_document_number_issuances_read
  ON cas_document_number_issuances FOR SELECT TO authenticated
  USING (is_company_member(company_id));
GRANT SELECT ON cas_document_number_issuances TO authenticated;

CREATE TABLE cas_document_void_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  branch_id UUID REFERENCES branches(id),
  source_table TEXT NOT NULL,
  source_id UUID NOT NULL,
  document_code TEXT NOT NULL,
  document_number TEXT NOT NULL,
  document_date DATE,
  terminal_status TEXT NOT NULL,
  reason_code_id UUID REFERENCES void_reason_codes(id),
  reason_text TEXT NOT NULL CHECK (btrim(reason_text) <> ''),
  original_journal_entry_id UUID REFERENCES journal_entries(id),
  reversal_journal_entry_id UUID REFERENCES journal_entries(id),
  voided_by UUID,
  voided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source_table, source_id, terminal_status)
);

ALTER TABLE cas_document_void_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY cas_document_void_events_read
  ON cas_document_void_events FOR SELECT TO authenticated
  USING (is_company_member(company_id));
GRANT SELECT ON cas_document_void_events TO authenticated;

CREATE TABLE cas_export_artifacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  snapshot_id UUID NOT NULL UNIQUE REFERENCES report_snapshots(id),
  layout_version TEXT NOT NULL,
  encoding TEXT NOT NULL DEFAULT 'UTF-8',
  newline_style TEXT NOT NULL DEFAULT 'CRLF',
  mime_type TEXT NOT NULL DEFAULT 'text/plain',
  file_name TEXT NOT NULL,
  file_content TEXT NOT NULL,
  file_hash TEXT NOT NULL CHECK (length(file_hash) = 64),
  byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
  generated_by UUID,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE cas_export_artifacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY cas_export_artifacts_read
  ON cas_export_artifacts FOR SELECT TO authenticated
  USING (is_company_member(company_id));
GRANT SELECT ON cas_export_artifacts TO authenticated;

ALTER TABLE cas_export_log
  ADD COLUMN artifact_id UUID REFERENCES cas_export_artifacts(id),
  ADD COLUMN file_hash TEXT,
  ADD COLUMN layout_version TEXT;

ALTER TABLE cas_export_log
  DROP CONSTRAINT cas_export_log_export_type_check,
  ADD CONSTRAINT cas_export_log_export_type_check
    CHECK (export_type IN ('dat_file', 'csv_export', 'report', 'audit_package'));

CREATE OR REPLACE FUNCTION fn_next_document_number(
  p_company_id UUID,
  p_branch_id UUID,
  p_document_code TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_series number_series%ROWTYPE;
  v_seq BIGINT;
  v_padded TEXT;
  v_number TEXT;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT * INTO v_series
  FROM number_series
  WHERE company_id = p_company_id
    AND branch_id = p_branch_id
    AND document_code = p_document_code
    AND is_active = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active number series for document code "%" in this branch. Set one up under Number Series Setup.', p_document_code;
  END IF;

  -- Browser-driven modules reserve before inserting the header. One unresolved
  -- reservation per actor/series prevents repeated calls from burning numbers;
  -- the reservation must be linked by the insert trigger or abandoned with a
  -- reason before another number is issued.
  IF EXISTS (
    SELECT 1
    FROM cas_document_number_issuances
    WHERE number_series_id = v_series.id
      AND reserved_by = auth.uid()
      AND status = 'reserved'
  ) THEN
    RAISE EXCEPTION 'An unresolved document-number reservation already exists for %. Complete or abandon it before requesting another number.', p_document_code;
  END IF;

  v_seq := COALESCE(v_series.current_sequence, 0) + 1;
  IF v_series.atp_series_start IS NOT NULL AND v_seq < v_series.atp_series_start THEN
    v_seq := v_series.atp_series_start;
  END IF;
  IF v_series.atp_series_end IS NOT NULL AND v_seq > v_series.atp_series_end THEN
    RAISE EXCEPTION 'ATP range exhausted for document code % (last authorized sequence: %)',
      p_document_code, v_series.atp_series_end;
  END IF;

  UPDATE number_series
  SET current_sequence = v_seq,
      next_number = v_seq + 1,
      updated_at = now()
  WHERE id = v_series.id;

  v_padded := lpad(v_seq::text, COALESCE(v_series.padding, v_series.number_length, 6), '0');
  v_number := concat(COALESCE(v_series.prefix, ''), v_padded, COALESCE(v_series.suffix, ''));

  INSERT INTO cas_document_number_issuances (
    company_id, branch_id, number_series_id, document_code,
    sequence_number, document_number, reserved_by
  ) VALUES (
    p_company_id, p_branch_id, v_series.id, p_document_code,
    v_seq, v_number, auth.uid()
  );

  RETURN v_number;
END;
$$;

CREATE OR REPLACE FUNCTION fn_next_document_number(
  p_company_id UUID,
  p_document_code TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch_id UUID;
BEGIN
  SELECT branch_id INTO v_branch_id
  FROM number_series
  WHERE company_id = p_company_id
    AND document_code = p_document_code
    AND is_active = true
  ORDER BY branch_id
  LIMIT 1;

  IF v_branch_id IS NULL THEN
    RAISE EXCEPTION 'No active company number series for document code "%"', p_document_code;
  END IF;

  RETURN fn_next_document_number(p_company_id, v_branch_id, p_document_code);
END;
$$;

-- Explicit reservation endpoint for the few legacy pages that allocate before
-- inserting a document. Save RPCs call fn_next_document_number internally.
CREATE OR REPLACE FUNCTION fn_reserve_document_number(
  p_company_id UUID,
  p_branch_id UUID,
  p_document_code TEXT
)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT fn_next_document_number(p_company_id, p_branch_id, p_document_code);
$$;

CREATE OR REPLACE FUNCTION fn_abandon_document_number(
  p_company_id UUID,
  p_branch_id UUID,
  p_document_code TEXT,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT is_company_member(p_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required to abandon a document number';
  END IF;

  SELECT id INTO v_id
  FROM cas_document_number_issuances
  WHERE company_id = p_company_id
    AND branch_id = p_branch_id
    AND document_code = p_document_code
    AND reserved_by = auth.uid()
    AND status = 'reserved'
  ORDER BY reserved_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN RAISE EXCEPTION 'No unresolved reservation was found'; END IF;

  UPDATE cas_document_number_issuances
  SET status = 'abandoned', voided_at = now(), void_reason = btrim(p_reason)
  WHERE id = v_id;
END;
$$;

REVOKE ALL ON FUNCTION fn_next_document_number(UUID, UUID, TEXT) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION fn_next_document_number(UUID, TEXT) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION fn_reserve_document_number(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_abandon_document_number(UUID, UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION fn_link_cas_document_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row JSONB := to_jsonb(NEW);
  v_doc_code TEXT := TG_ARGV[0];
  v_number TEXT := v_row->>TG_ARGV[1];
  v_branch UUID;
  v_issuance_id UUID;
BEGIN
  IF COALESCE(TG_ARGV[2], '') <> '' THEN
    v_branch := NULLIF(v_row->>TG_ARGV[2], '')::UUID;
  END IF;

  IF NULLIF(v_number, '') IS NULL THEN RETURN NEW; END IF;

  SELECT id INTO v_issuance_id
  FROM cas_document_number_issuances
  WHERE company_id = NEW.company_id
    AND branch_id IS NOT DISTINCT FROM v_branch
    AND document_code = v_doc_code
    AND document_number = v_number
    AND status = 'reserved'
  ORDER BY reserved_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_issuance_id IS NULL THEN
    INSERT INTO cas_document_number_issuances (
      company_id, branch_id, document_code, document_number,
      status, source_table, source_id, reserved_by, issued_at
    ) VALUES (
      NEW.company_id, v_branch, v_doc_code, v_number,
      'issued', TG_TABLE_NAME, NEW.id, COALESCE(NEW.created_by, auth.uid()), now()
    );
  ELSE
    UPDATE cas_document_number_issuances
    SET status = 'issued', source_table = TG_TABLE_NAME, source_id = NEW.id, issued_at = now()
    WHERE id = v_issuance_id;
  END IF;

  RETURN NEW;
END;
$$;

-- Link every document currently allocated through fn_next/reserve. The branch
-- argument may point to from_branch_id for an inter-branch document.
CREATE TRIGGER trg_cas_number_sales_quotations AFTER INSERT ON sales_quotations
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('QUO','quotation_number','branch_id');
CREATE TRIGGER trg_cas_number_sales_orders AFTER INSERT ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('SO','so_number','branch_id');
CREATE TRIGGER trg_cas_number_delivery_receipts AFTER INSERT ON delivery_receipts
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('DR','dr_number','branch_id');
CREATE TRIGGER trg_cas_number_sales_invoices AFTER INSERT ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('SI','si_number','branch_id');
CREATE TRIGGER trg_cas_number_receipts AFTER INSERT ON receipts
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('OR','receipt_number','branch_id');
CREATE TRIGGER trg_cas_number_credit_memos AFTER INSERT ON credit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('CM','cm_number','branch_id');
CREATE TRIGGER trg_cas_number_debit_memos AFTER INSERT ON debit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('DM-S','dm_number','branch_id');
CREATE TRIGGER trg_cas_number_purchase_orders AFTER INSERT ON purchase_orders
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('PO','po_number','branch_id');
CREATE TRIGGER trg_cas_number_receiving_reports AFTER INSERT ON receiving_reports
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('RR','rr_number','branch_id');
CREATE TRIGGER trg_cas_number_vendor_bills AFTER INSERT ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('VB','bill_number','branch_id');
CREATE TRIGGER trg_cas_number_payment_vouchers AFTER INSERT ON payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('PV','voucher_number','branch_id');
CREATE TRIGGER trg_cas_number_cash_purchases AFTER INSERT ON cash_purchases
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('CP','cp_number','branch_id');
CREATE TRIGGER trg_cas_number_vendor_credits AFTER INSERT ON vendor_credits
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('VC','vc_number','branch_id');
CREATE TRIGGER trg_cas_number_fund_transfers AFTER INSERT ON fund_transfers
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('FT','ft_number','branch_id');
CREATE TRIGGER trg_cas_number_inter_branch_transfers AFTER INSERT ON inter_branch_transfers
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('IBT','ibt_number','from_branch_id');
CREATE TRIGGER trg_cas_number_bank_adjustments AFTER INSERT ON bank_adjustments
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('BADJ','ba_number','branch_id');
CREATE TRIGGER trg_cas_number_petty_cash_vouchers AFTER INSERT ON petty_cash_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('PCV','pcv_number','branch_id');
CREATE TRIGGER trg_cas_number_petty_cash_replenishments AFTER INSERT ON petty_cash_replenishments
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('PCR','pcr_number','branch_id');
CREATE TRIGGER trg_cas_number_check_vouchers AFTER INSERT ON check_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('CV','cv_number','branch_id');
CREATE TRIGGER trg_cas_number_cash_count_sheets AFTER INSERT ON cash_count_sheets
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('CCS','sheet_number','branch_id');
CREATE TRIGGER trg_cas_number_journal_entries AFTER INSERT ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION fn_link_cas_document_number('JE','je_number','branch_id');

CREATE OR REPLACE FUNCTION fn_capture_cas_document_void()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old JSONB := to_jsonb(OLD);
  v_new JSONB := to_jsonb(NEW);
  v_doc_code TEXT := TG_ARGV[0];
  v_number TEXT := v_new->>TG_ARGV[1];
  v_date DATE := NULLIF(v_new->>TG_ARGV[2], '')::DATE;
  v_je_id UUID;
  v_reason_id UUID := NULLIF(v_new->>'void_reason_id', '')::UUID;
  v_reason TEXT := NULLIF(btrim(current_setting('pxl.cas_void_reason', true)), '');
  v_reason_from_row TEXT;
  v_reversal_id UUID;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status <> ALL (string_to_array(TG_ARGV[3], ',')) THEN
    RETURN NEW;
  END IF;

  v_je_id := NULLIF(v_new->>'journal_entry_id', '')::UUID;

  IF v_reason_id IS NOT NULL THEN
    SELECT description INTO v_reason_from_row
    FROM void_reason_codes WHERE id = v_reason_id AND is_active = true;
    IF v_reason_from_row IS NULL THEN RAISE EXCEPTION 'Invalid or inactive void reason'; END IF;
    v_reason := COALESCE(v_reason, v_reason_from_row);
  END IF;

  IF TG_TABLE_NAME IN ('sales_invoices', 'vendor_bills')
     AND v_reason_id IS NULL
     AND COALESCE(v_new->>'memo', '') IS NOT DISTINCT FROM COALESCE(v_old->>'memo', '')
     AND v_reason IS NULL THEN
    RAISE EXCEPTION 'A void reason code or new void memo is required for CAS audit evidence';
  END IF;

  IF v_reason IS NULL THEN
    v_reason_from_row := NULLIF(btrim(COALESCE(
      v_new->>'memo', v_new->>'remarks', v_new->>'notes', v_new->>'particulars', ''
    )), '');
    v_reason := v_reason_from_row;
  END IF;

  SELECT id,
         CASE WHEN v_reason IS NULL AND description LIKE '% — %'
              THEN split_part(description, ' — ', 2) END
  INTO v_reversal_id, v_reason_from_row
  FROM journal_entries
  WHERE company_id = NEW.company_id
    AND reference_doc_id = NEW.id
    AND id IS DISTINCT FROM v_je_id
    AND status = 'posted'
  ORDER BY created_at DESC
  LIMIT 1;
  v_reason := COALESCE(v_reason, v_reason_from_row);

  IF v_reason IS NULL AND TG_TABLE_NAME = 'receipts' AND NEW.status = 'bounced' THEN
    v_reason := 'Bounced payment instrument';
  END IF;

  IF NULLIF(btrim(COALESCE(v_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A cancellation/void reason is required for CAS audit evidence';
  END IF;

  INSERT INTO cas_document_void_events (
    company_id, branch_id, source_table, source_id,
    document_code, document_number, document_date, terminal_status,
    reason_code_id, reason_text, original_journal_entry_id,
    reversal_journal_entry_id, voided_by
  ) VALUES (
    NEW.company_id,
    COALESCE(NULLIF(v_new->>'branch_id', '')::UUID, NULLIF(v_new->>'from_branch_id', '')::UUID),
    TG_TABLE_NAME, NEW.id,
    v_doc_code, v_number, v_date, NEW.status,
    v_reason_id, btrim(v_reason), v_je_id, v_reversal_id, auth.uid()
  ) ON CONFLICT (source_table, source_id, terminal_status) DO NOTHING;

  UPDATE cas_document_number_issuances
  SET status = 'voided', voided_at = now(), void_reason = btrim(v_reason)
  WHERE source_table = TG_TABLE_NAME AND source_id = NEW.id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cas_void_sales_invoices AFTER UPDATE OF status ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('SI','si_number','date','cancelled');
CREATE TRIGGER trg_cas_void_vendor_bills AFTER UPDATE OF status ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('VB','bill_number','bill_date','cancelled');
CREATE TRIGGER trg_cas_void_payment_vouchers AFTER UPDATE OF status ON payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('PV','voucher_number','voucher_date','cancelled');
CREATE TRIGGER trg_cas_void_receipts AFTER UPDATE OF status ON receipts
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('OR','receipt_number','receipt_date','bounced,cancelled');
CREATE TRIGGER trg_cas_void_credit_memos AFTER UPDATE OF status ON credit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('CM','cm_number','cm_date','cancelled');
CREATE TRIGGER trg_cas_void_debit_memos AFTER UPDATE OF status ON debit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('DM-S','dm_number','dm_date','cancelled');
CREATE TRIGGER trg_cas_void_vendor_credits AFTER UPDATE OF status ON vendor_credits
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('VC','vc_number','credit_date','cancelled');
CREATE TRIGGER trg_cas_void_fund_transfers AFTER UPDATE OF status ON fund_transfers
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('FT','ft_number','transfer_date','cancelled');
CREATE TRIGGER trg_cas_void_inter_branch_transfers AFTER UPDATE OF status ON inter_branch_transfers
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('IBT','ibt_number','transfer_date','cancelled');
CREATE TRIGGER trg_cas_void_bank_adjustments AFTER UPDATE OF status ON bank_adjustments
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('BADJ','ba_number','adjustment_date','cancelled');
CREATE TRIGGER trg_cas_void_petty_cash_vouchers AFTER UPDATE OF status ON petty_cash_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('PCV','pcv_number','voucher_date','cancelled');
CREATE TRIGGER trg_cas_void_check_vouchers AFTER UPDATE OF status ON check_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_capture_cas_document_void('CV','cv_number','voucher_date','cancelled');

-- Banking/treasury cancellations all pass through this helper. Requiring and
-- carrying the reason in a transaction-local setting makes the terminal-state
-- trigger atomic with the reversal.
CREATE OR REPLACE FUNCTION fn_bt_reverse_je(
  p_company_id UUID,
  p_branch_id UUID,
  p_orig_je_id UUID,
  p_ref_type TEXT,
  p_ref_id UUID,
  p_je_number TEXT,
  p_memo TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_orig journal_entries%ROWTYPE;
  v_rev_id UUID;
  v_line RECORD;
  v_no INT := 1;
BEGIN
  IF NULLIF(btrim(COALESCE(p_memo, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A cancellation reason is required';
  END IF;
  PERFORM set_config('pxl.cas_void_reason', btrim(p_memo), true);

  SELECT * INTO v_orig FROM journal_entries WHERE id = p_orig_je_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Original journal entry not found for reversal'; END IF;

  INSERT INTO journal_entries (
    company_id, branch_id, je_number, je_date, fiscal_period_id,
    description, reference_doc_type, reference_doc_id, status,
    total_debit, total_credit, created_by, updated_by
  ) VALUES (
    p_company_id, p_branch_id, p_je_number, CURRENT_DATE,
    fn_require_open_fiscal_period(p_company_id, CURRENT_DATE, true),
    'REVERSAL: ' || v_orig.description || ' — ' || btrim(p_memo),
    p_ref_type, p_ref_id, 'posted',
    v_orig.total_credit, v_orig.total_debit,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_rev_id;

  FOR v_line IN
    SELECT * FROM journal_entry_lines WHERE je_id = v_orig.id ORDER BY line_number
  LOOP
    INSERT INTO journal_entry_lines (
      je_id, company_id, line_number, account_id, description,
      debit_amount, credit_amount, branch_id, department_id, cost_center_id,
      created_by, updated_by
    ) VALUES (
      v_rev_id, p_company_id, v_no, v_line.account_id,
      'REVERSAL — ' || COALESCE(v_line.description, ''),
      v_line.credit_amount, v_line.debit_amount,
      v_line.branch_id, v_line.department_id, v_line.cost_center_id,
      auth.uid(), auth.uid()
    );
    v_no := v_no + 1;
  END LOOP;

  UPDATE journal_entries
  SET status = 'reversed', updated_by = auth.uid(), updated_at = now()
  WHERE id = v_orig.id;

  RETURN v_rev_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_require_cas_reversal_reason()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.je_number LIKE 'JE-VOID-%'
     AND NEW.description NOT LIKE '% — %' THEN
    RAISE EXCEPTION 'A cancellation reason is required';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_require_cas_reversal_reason
  BEFORE INSERT ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION fn_require_cas_reversal_reason();

CREATE OR REPLACE VIEW vw_cas_atp_usage
WITH (security_invoker = true) AS
SELECT
  ns.id AS number_series_id,
  ns.company_id,
  ns.branch_id,
  ns.document_code,
  ns.prefix,
  ns.atp_series_start,
  ns.atp_series_end,
  ns.current_sequence,
  CASE WHEN ns.atp_series_end IS NULL THEN NULL
       ELSE GREATEST(ns.atp_series_end - ns.current_sequence, 0) END AS numbers_remaining,
  COUNT(i.id) FILTER (WHERE i.status = 'reserved') AS reserved_count,
  COUNT(i.id) FILTER (WHERE i.status = 'issued') AS issued_count,
  COUNT(i.id) FILTER (WHERE i.status IN ('voided','abandoned')) AS voided_count
FROM number_series ns
LEFT JOIN cas_document_number_issuances i ON i.number_series_id = ns.id
GROUP BY ns.id;

GRANT SELECT ON vw_cas_atp_usage TO authenticated;

CREATE OR REPLACE FUNCTION fn_render_cas_dat(p_snapshot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_snapshot report_snapshots%ROWTYPE;
  v_company_tin TEXT;
  v_row JSONB;
  v_content TEXT;
  v_line TEXT;
  v_source_hash TEXT;
  v_file_hash TEXT;
  v_file_name TEXT;
  v_artifact_id UUID;
  v_layout CONSTANT TEXT := 'PXL-CAS-DAT-1.0';
  v_crlf CONSTANT TEXT := E'\r\n';
BEGIN
  SELECT * INTO v_snapshot FROM report_snapshots WHERE id = p_snapshot_id;
  IF NOT FOUND OR v_snapshot.report_type NOT LIKE 'CAS_%'
     OR NOT is_company_member(v_snapshot.company_id) THEN
    RAISE EXCEPTION 'CAS export snapshot not found or access denied';
  END IF;

  SELECT regexp_replace(COALESCE(tin, ''), '[^0-9]', '', 'g')
  INTO v_company_tin FROM companies WHERE id = v_snapshot.company_id;

  v_file_name := regexp_replace(
    COALESCE(v_snapshot.report_payload->>'file_name', lower(v_snapshot.report_type) || '.dat'),
    '\.[^.]+$', '.dat'
  );
  IF v_file_name !~* '\.dat$' THEN v_file_name := v_file_name || '.dat'; END IF;

  v_content := concat_ws('|', 'H', v_layout, v_snapshot.report_type,
    v_company_tin, v_snapshot.period_start, v_snapshot.period_end,
    v_snapshot.snapshot_version) || v_crlf;

  FOR v_row IN SELECT value FROM jsonb_array_elements(v_snapshot.source_payload->'export_rows') LOOP
    IF v_snapshot.report_type = 'CAS_SLSP' THEN
      v_line := concat_ws('|', 'D', 'S', v_row->>'invoice_date', v_row->>'system_no',
        regexp_replace(COALESCE(v_row->>'customer_tin',''), '[^0-9]', '', 'g'),
        regexp_replace(COALESCE(v_row->>'customer_name',''), '[|\r\n]', ' ', 'g'),
        COALESCE(v_row->>'taxable_base','0'), COALESCE(v_row->>'output_vat','0'));
    ELSIF v_snapshot.report_type = 'CAS_RELIEF' THEN
      v_line := concat_ws('|', 'D', 'P', v_row->>'invoice_date', v_row->>'system_no',
        regexp_replace(COALESCE(v_row->>'supplier_tin',''), '[^0-9]', '', 'g'),
        regexp_replace(COALESCE(v_row->>'supplier_name',''), '[|\r\n]', ' ', 'g'),
        COALESCE(v_row->>'taxable_base','0'), COALESCE(v_row->>'input_vat','0'));
    ELSIF v_snapshot.report_type = 'CAS_GL' THEN
      v_line := concat_ws('|', 'D', 'GL', v_row->>'je_date', v_row->>'je_number',
        v_row->>'line_number', v_row->>'account_code',
        regexp_replace(COALESCE(v_row->>'account_name',''), '[|\r\n]', ' ', 'g'),
        COALESCE(v_row->>'debit_amount','0'), COALESCE(v_row->>'credit_amount','0'));
    ELSE
      v_line := concat_ws('|', 'D', 'QAP', v_row->>'invoice_date',
        regexp_replace(COALESCE(v_row->>'supplier_tin',''), '[^0-9]', '', 'g'),
        regexp_replace(COALESCE(v_row->>'supplier_name',''), '[|\r\n]', ' ', 'g'),
        v_row->>'atc_code', COALESCE(v_row->>'tax_base','0'),
        COALESCE(v_row->>'tax_withheld','0'));
    END IF;
    v_content := v_content || v_line || v_crlf;
  END LOOP;

  v_source_hash := v_snapshot.source_hash;
  v_content := v_content || concat_ws('|', 'T', v_snapshot.source_row_count, v_source_hash) || v_crlf;
  v_file_hash := encode(extensions.digest(convert_to(v_content, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO cas_export_artifacts (
    company_id, snapshot_id, layout_version, file_name, file_content,
    file_hash, byte_count, generated_by
  ) VALUES (
    v_snapshot.company_id, v_snapshot.id, v_layout, v_file_name, v_content,
    v_file_hash, octet_length(convert_to(v_content, 'UTF8')), auth.uid()
  ) ON CONFLICT (snapshot_id) DO NOTHING
  RETURNING id INTO v_artifact_id;

  IF v_artifact_id IS NULL THEN
    SELECT id, file_content, file_hash, file_name
    INTO v_artifact_id, v_content, v_file_hash, v_file_name
    FROM cas_export_artifacts
    WHERE snapshot_id = v_snapshot.id;
  END IF;

  UPDATE cas_export_log
  SET artifact_id = v_artifact_id,
      file_hash = v_file_hash,
      layout_version = v_layout,
      file_name = v_file_name
  WHERE snapshot_id = v_snapshot.id;

  RETURN jsonb_build_object(
    'artifact_id', v_artifact_id,
    'snapshot_id', v_snapshot.id,
    'file_name', v_file_name,
    'content', v_content,
    'file_hash', v_file_hash,
    'source_hash', v_source_hash,
    'layout_version', v_layout,
    'encoding', 'UTF-8',
    'newline_style', 'CRLF',
    'mime_type', 'text/plain'
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_snapshot_cas_audit_package(
  p_company_id UUID,
  p_date_from DATE,
  p_date_to DATE,
  p_file_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source_id UUID;
  v_version INTEGER;
  v_payload JSONB;
  v_hash TEXT;
  v_snapshot_id UUID := gen_random_uuid();
  v_row_count INTEGER;
BEGIN
  IF NOT is_company_member(p_company_id) THEN RAISE EXCEPTION 'Access denied'; END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Invalid CAS audit package date range';
  END IF;
  IF NULLIF(btrim(COALESCE(p_file_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'CAS audit package file name is required';
  END IF;

  SELECT jsonb_build_object(
    'number_issuances', COALESCE((
      SELECT jsonb_agg(to_jsonb(i) ORDER BY reserved_at, document_code, document_number)
      FROM cas_document_number_issuances i
      WHERE i.company_id = p_company_id
        AND i.reserved_at::date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb),
    'void_events', COALESCE((
      SELECT jsonb_agg(to_jsonb(v) ORDER BY voided_at, document_code, document_number)
      FROM cas_document_void_events v
      WHERE v.company_id = p_company_id
        AND v.voided_at::date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb),
    'journal_entries', COALESCE((
      SELECT jsonb_agg(to_jsonb(j) ORDER BY je_date, je_number)
      FROM journal_entries j
      WHERE j.company_id = p_company_id AND j.je_date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb),
    'audit_events', COALESCE((
      SELECT jsonb_agg(to_jsonb(a) ORDER BY changed_at, id)
      FROM sys_audit_logs a
      WHERE a.company_id = p_company_id
        AND a.changed_at::date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb),
    'exports', COALESCE((
      SELECT jsonb_agg(to_jsonb(e) ORDER BY generated_at, id)
      FROM cas_export_log e
      WHERE e.company_id = p_company_id
        AND e.generated_at::date BETWEEN p_date_from AND p_date_to
    ), '[]'::jsonb),
    'gl_control', jsonb_build_object(
      'total_debit', COALESCE((SELECT SUM(debit_amount) FROM vw_general_ledger
        WHERE company_id = p_company_id AND je_date BETWEEN p_date_from AND p_date_to), 0),
      'total_credit', COALESCE((SELECT SUM(credit_amount) FROM vw_general_ledger
        WHERE company_id = p_company_id AND je_date BETWEEN p_date_from AND p_date_to), 0)
    )
  ) INTO v_payload;

  v_row_count := jsonb_array_length(v_payload->'number_issuances')
               + jsonb_array_length(v_payload->'void_events')
               + jsonb_array_length(v_payload->'journal_entries')
               + jsonb_array_length(v_payload->'audit_events')
               + jsonb_array_length(v_payload->'exports');

  v_source_id := fn_report_snapshot_key_uuid(
    p_company_id::text || ':CAS_AUDIT_PACKAGE:' || p_date_from || ':' || p_date_to
  );
  SELECT COALESCE(MAX(snapshot_version), 0) + 1 INTO v_version
  FROM report_snapshots
  WHERE source_table = 'cas_audit_periods' AND source_id = v_source_id;

  v_hash := encode(extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO report_snapshots (
    id, company_id, report_type, source_table, source_id,
    snapshot_status, snapshot_version, period_start, period_end,
    report_payload, source_payload, source_hash, source_row_count, generated_by
  ) VALUES (
    v_snapshot_id, p_company_id, 'CAS_AUDIT_PACKAGE', 'cas_audit_periods', v_source_id,
    'exported', v_version, p_date_from, p_date_to,
    jsonb_build_object('file_name', p_file_name, 'date_from', p_date_from, 'date_to', p_date_to),
    v_payload, v_hash, v_row_count, auth.uid()
  );

  INSERT INTO cas_export_log (
    company_id, export_type, report_name, period_year,
    file_name, row_count, generated_by, snapshot_id, remarks
  ) VALUES (
    p_company_id, 'audit_package', 'CAS Audit Support Package',
    EXTRACT(YEAR FROM p_date_from)::integer,
    p_file_name, v_row_count, auth.uid(), v_snapshot_id,
    p_date_from::text || '..' || p_date_to::text
  );

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_version', v_version,
    'source_hash', v_hash,
    'row_count', v_row_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fn_render_cas_dat(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_snapshot_cas_audit_package(UUID, DATE, DATE, TEXT) TO authenticated;

COMMENT ON TABLE cas_document_number_issuances IS
  'Append-only CAS evidence for every reserved, issued, voided, or abandoned controlled document number.';
COMMENT ON TABLE cas_export_artifacts IS
  'Exact UTF-8 bytes delivered for a CAS DAT snapshot, with an independently reproducible SHA-256 hash.';
