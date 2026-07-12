-- PXL-DA-019 (first slice): database-governed document-number issuance,
-- ATP exhaustion, and immutable terminal-document evidence.
--
-- This is intentionally independent from the held-out broken draft
-- 20260710000005. It preserves the deployed three-argument, branch-scoped
-- allocator and its authenticated callers. A failed browser insert burns a
-- visible reservation but never blocks a later allocation or permits reuse.

-- ---------------------------------------------------------------------------
-- 1. Immutable evidence tables
-- ---------------------------------------------------------------------------

CREATE TABLE public.cas_document_number_issuances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  branch_id UUID REFERENCES public.branches(id),
  number_series_id UUID REFERENCES public.number_series(id),
  document_code TEXT NOT NULL,
  sequence_number BIGINT,
  document_number TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'reserved'
    CHECK (status IN ('reserved', 'issued', 'voided', 'abandoned')),
  source_table TEXT,
  source_id UUID,
  allocated_by UUID,
  allocated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  issued_at TIMESTAMPTZ,
  voided_at TIMESTAMPTZ,
  void_reason TEXT,
  UNIQUE (number_series_id, sequence_number),
  UNIQUE (company_id, branch_id, document_code, document_number),
  CHECK ((source_table IS NULL) = (source_id IS NULL))
);

CREATE UNIQUE INDEX uq_cas_number_issuance_source
  ON public.cas_document_number_issuances (source_table, source_id)
  WHERE source_table IS NOT NULL AND source_id IS NOT NULL;
CREATE INDEX idx_cas_number_issuance_company_time
  ON public.cas_document_number_issuances (company_id, allocated_at DESC);

CREATE TABLE public.cas_document_void_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  branch_id UUID REFERENCES public.branches(id),
  number_issuance_id UUID REFERENCES public.cas_document_number_issuances(id),
  source_table TEXT NOT NULL,
  source_id UUID NOT NULL,
  document_code TEXT NOT NULL,
  document_number TEXT NOT NULL,
  document_date DATE,
  terminal_status TEXT NOT NULL,
  reason_code_id UUID REFERENCES public.void_reason_codes(id),
  reason_text TEXT NOT NULL CHECK (BTRIM(reason_text) <> ''),
  event_actor_id UUID,
  original_journal_entry_id UUID REFERENCES public.journal_entries(id),
  reversal_journal_entry_id UUID REFERENCES public.journal_entries(id),
  party_id UUID,
  party_type TEXT,
  party_name TEXT,
  party_tin TEXT,
  document_amount NUMERIC(15,2),
  source_snapshot JSONB NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (source_table, source_id, terminal_status)
);

CREATE INDEX idx_cas_void_events_company_time
  ON public.cas_document_void_events (company_id, occurred_at DESC);
CREATE INDEX idx_cas_void_events_number
  ON public.cas_document_void_events (company_id, document_code, document_number);

ALTER TABLE public.cas_document_number_issuances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cas_document_void_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY cas_document_number_issuances_read
  ON public.cas_document_number_issuances
  FOR SELECT TO authenticated
  USING (is_company_member(company_id));

CREATE POLICY cas_document_void_events_read
  ON public.cas_document_void_events
  FOR SELECT TO authenticated
  USING (is_company_member(company_id));

-- Migration 20260702000008 granted DML on all public tables. RLS protects row
-- DML, but not TRUNCATE; revoke every mutation privilege explicitly.
REVOKE ALL PRIVILEGES ON TABLE public.cas_document_number_issuances
  FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.cas_document_void_events
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.cas_document_number_issuances TO authenticated;
GRANT SELECT ON TABLE public.cas_document_void_events TO authenticated;
GRANT ALL ON TABLE public.cas_document_number_issuances TO service_role;
GRANT ALL ON TABLE public.cas_document_void_events TO service_role;

COMMENT ON TABLE public.cas_document_number_issuances IS
  'Forward-only CAS evidence for every controlled document-number allocation; reservations and terminal gaps are never recycled.';
COMMENT ON TABLE public.cas_document_void_events IS
  'Immutable CAS terminal-document evidence with reason, actor, party/amount snapshot, and original/reversal journal links.';

-- Terminal-document evidence is append-only: it is written once by the capture
-- trigger and never revised. Block every UPDATE/DELETE/TRUNCATE, including one
-- issued directly by the table owner, so the audit record cannot be rewritten.
CREATE OR REPLACE FUNCTION public.fn_forbid_cas_void_evidence_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'CAS terminal-document void evidence is immutable (% is not permitted)', TG_OP
    USING ERRCODE = 'P0001';
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_forbid_cas_void_evidence_row ON public.cas_document_void_events;
CREATE TRIGGER trg_zz_forbid_cas_void_evidence_row
  BEFORE UPDATE OR DELETE ON public.cas_document_void_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_forbid_cas_void_evidence_change();

DROP TRIGGER IF EXISTS trg_zz_forbid_cas_void_evidence_stmt ON public.cas_document_void_events;
CREATE TRIGGER trg_zz_forbid_cas_void_evidence_stmt
  BEFORE TRUNCATE ON public.cas_document_void_events
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_forbid_cas_void_evidence_change();

REVOKE ALL ON FUNCTION public.fn_forbid_cas_void_evidence_change()
  FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Number-series setup guard and ATP-aware branch-scoped allocator
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_guard_cas_number_series()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_evidence BOOLEAN := FALSE;
BEGIN
  IF (NEW.atp_series_start IS NULL) <> (NEW.atp_series_end IS NULL) THEN
    RAISE EXCEPTION 'ATP series start and end must be configured together';
  END IF;
  IF NEW.atp_series_start IS NOT NULL AND (
    NEW.atp_series_start < 1 OR NEW.atp_series_end < NEW.atp_series_start
  ) THEN
    RAISE EXCEPTION 'Invalid ATP range % to %',
      NEW.atp_series_start, NEW.atp_series_end;
  END IF;
  IF NEW.atp_series_end IS NOT NULL
     AND COALESCE(NEW.current_sequence, 0) > NEW.atp_series_end THEN
    RAISE EXCEPTION 'ATP end % is below current sequence %',
      NEW.atp_series_end, NEW.current_sequence;
  END IF;

  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.current_sequence, 0) < COALESCE(OLD.current_sequence, 0)
     OR COALESCE(NEW.next_number, 1) < COALESCE(OLD.next_number, 1) THEN
    RAISE EXCEPTION 'Document sequence counters cannot move backward; issued numbers are never reusable';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.cas_document_number_issuances i
    WHERE i.number_series_id = OLD.id
  ) INTO v_has_evidence;

  IF v_has_evidence AND (
    NEW.company_id IS DISTINCT FROM OLD.company_id OR
    NEW.branch_id IS DISTINCT FROM OLD.branch_id OR
    NEW.document_type_id IS DISTINCT FROM OLD.document_type_id OR
    NEW.document_code IS DISTINCT FROM OLD.document_code OR
    NEW.prefix IS DISTINCT FROM OLD.prefix OR
    NEW.suffix IS DISTINCT FROM OLD.suffix OR
    NEW.padding IS DISTINCT FROM OLD.padding OR
    NEW.number_length IS DISTINCT FROM OLD.number_length OR
    NEW.has_dynamic_year IS DISTINCT FROM OLD.has_dynamic_year OR
    NEW.reset_frequency IS DISTINCT FROM OLD.reset_frequency OR
    NEW.atp_series_start IS DISTINCT FROM OLD.atp_series_start
  ) THEN
    RAISE EXCEPTION 'A number series with issuance evidence cannot change tenant, branch, document identity, format, reset rule, or ATP start';
  END IF;

  IF v_has_evidence
     AND OLD.atp_series_end IS NOT NULL
     AND NEW.atp_series_end IS NOT NULL
     AND NEW.atp_series_end < OLD.atp_series_end THEN
    RAISE EXCEPTION 'ATP series end cannot shrink after number issuance';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_guard_cas_number_series ON public.number_series;
CREATE TRIGGER trg_zz_guard_cas_number_series
  BEFORE INSERT OR UPDATE ON public.number_series
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_cas_number_series();

CREATE OR REPLACE FUNCTION public.fn_next_document_number(
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
  v_series public.number_series%ROWTYPE;
  v_seq BIGINT;
  v_number TEXT;
BEGIN
  IF NOT public.is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT ns.* INTO v_series
  FROM public.number_series ns
  WHERE ns.company_id = p_company_id
    AND ns.branch_id = p_branch_id
    AND ns.document_code = p_document_code
    AND ns.is_active = TRUE
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active number series for document code "%" in this branch. Set one up under Number Series Setup.',
      p_document_code;
  END IF;

  v_seq := COALESCE(v_series.current_sequence, 0) + 1;
  IF v_series.atp_series_start IS NOT NULL THEN
    v_seq := GREATEST(v_seq, v_series.atp_series_start);
    IF v_seq > v_series.atp_series_end THEN
      RAISE EXCEPTION 'ATP range exhausted for document code % (authorized % to %)',
        p_document_code, v_series.atp_series_start, v_series.atp_series_end;
    END IF;
  END IF;

  UPDATE public.number_series
  SET current_sequence = v_seq,
      updated_at = NOW()
  WHERE id = v_series.id;

  v_number := CONCAT(
    COALESCE(v_series.prefix, ''),
    LPAD(v_seq::TEXT, COALESCE(v_series.padding, v_series.number_length, 6), '0'),
    COALESCE(v_series.suffix, '')
  );

  INSERT INTO public.cas_document_number_issuances (
    company_id, branch_id, number_series_id, document_code,
    sequence_number, document_number, status, allocated_by
  ) VALUES (
    p_company_id, p_branch_id, v_series.id, p_document_code,
    v_seq, v_number, 'reserved', auth.uid()
  );

  RETURN v_number;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_next_document_number(UUID, UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_next_document_number(UUID, UUID, TEXT)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Bind every allocated number to the inserted source document
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_bind_cas_document_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row JSONB := TO_JSONB(NEW);
  v_company_id UUID := NULLIF(v_row->>'company_id', '')::UUID;
  v_code TEXT := TG_ARGV[0];
  v_number TEXT := NULLIF(v_row->>TG_ARGV[1], '');
  v_branch UUID;
  v_issuance_id UUID;
  v_candidate_count INTEGER := 0;
BEGIN
  IF TG_TABLE_NAME = 'sales_invoices'
     AND COALESCE((v_row->>'is_cash_sale')::BOOLEAN, FALSE) THEN
    v_code := 'CS';
  END IF;
  IF COALESCE(TG_ARGV[2], '') <> '' THEN
    v_branch := NULLIF(v_row->>TG_ARGV[2], '')::UUID;
  END IF;
  IF v_company_id IS NULL OR v_number IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_branch IS NOT NULL THEN
    SELECT i.id INTO v_issuance_id
    FROM public.cas_document_number_issuances i
    WHERE i.company_id = v_company_id
      AND i.branch_id = v_branch
      AND i.document_code = v_code
      AND i.document_number = v_number
      AND i.status = 'reserved'
    ORDER BY i.allocated_at DESC
    LIMIT 1
    FOR UPDATE;
  ELSE
    -- Cross-branch stock-transfer JEs intentionally have no reporting branch.
    -- Their allocator row was created in the same transaction using the source
    -- warehouse branch, so prefer that unambiguously over historical matches.
    SELECT i.id INTO v_issuance_id
    FROM public.cas_document_number_issuances i
    WHERE i.company_id = v_company_id
      AND i.document_code = v_code
      AND i.document_number = v_number
      AND i.status = 'reserved'
      AND public.fn_row_written_by_current_txn(i.xmin::TEXT::BIGINT)
    ORDER BY i.allocated_at DESC
    LIMIT 1
    FOR UPDATE;

    IF v_issuance_id IS NULL THEN
      SELECT COUNT(*)::INTEGER, MIN(i.id::TEXT)::UUID
      INTO v_candidate_count, v_issuance_id
      FROM public.cas_document_number_issuances i
      WHERE i.company_id = v_company_id
        AND i.document_code = v_code
        AND i.document_number = v_number
        AND i.status = 'reserved';
      IF v_candidate_count > 1 THEN
        RAISE EXCEPTION 'Ambiguous CAS number reservation for % %', v_code, v_number;
      END IF;
    END IF;
  END IF;

  IF v_issuance_id IS NULL THEN
    INSERT INTO public.cas_document_number_issuances (
      company_id, branch_id, document_code, document_number,
      status, source_table, source_id, allocated_by, issued_at
    ) VALUES (
      v_company_id, v_branch, v_code, v_number,
      'issued', TG_TABLE_NAME, NEW.id,
      COALESCE(NULLIF(v_row->>'created_by', '')::UUID, auth.uid()), NOW()
    );
  ELSE
    UPDATE public.cas_document_number_issuances
    SET status = 'issued',
        source_table = TG_TABLE_NAME,
        source_id = NEW.id,
        issued_at = NOW()
    WHERE id = v_issuance_id;
  END IF;

  RETURN NEW;
END;
$$;

DO $$
DECLARE
  v_cfg RECORD;
BEGIN
  FOR v_cfg IN
    SELECT * FROM (VALUES
      ('sales_quotations',          'QT',   'quotation_number', 'branch_id'),
      ('sales_orders',              'SO',   'so_number',        'branch_id'),
      ('delivery_receipts',         'DR',   'dr_number',        'branch_id'),
      ('sales_invoices',            'SI',   'si_number',        'branch_id'),
      ('receipts',                  'OR',   'receipt_number',   'branch_id'),
      ('credit_memos',              'CM',   'cm_number',        'branch_id'),
      ('debit_memos',               'DM-S', 'dm_number',        'branch_id'),
      ('purchase_orders',           'PO',   'po_number',        'branch_id'),
      ('receiving_reports',         'RR',   'rr_number',        'branch_id'),
      ('vendor_bills',              'VB',   'bill_number',      'branch_id'),
      ('payment_vouchers',          'PV',   'voucher_number',   'branch_id'),
      ('cash_purchases',            'CP',   'cp_number',        'branch_id'),
      ('vendor_credits',            'VC',   'vc_number',        'branch_id'),
      ('supplier_debit_memos',      'SDM',  'sdm_number',       'branch_id'),
      ('purchase_returns',          'PRT',  'return_number',    'branch_id'),
      ('fund_transfers',            'FT',   'ft_number',        'branch_id'),
      ('inter_branch_transfers',    'IBT',  'ibt_number',       'from_branch_id'),
      ('bank_adjustments',          'BADJ', 'ba_number',        'branch_id'),
      ('petty_cash_vouchers',       'PCV',  'pcv_number',       'branch_id'),
      ('petty_cash_replenishments', 'PCR',  'pcr_number',       'branch_id'),
      ('check_vouchers',            'CV',   'cv_number',        'branch_id'),
      ('cash_count_sheets',         'CCS',  'sheet_number',     'branch_id'),
      ('fixed_assets',              'FA',   'asset_number',     'branch_id'),
      ('journal_entries',           'JE',   'je_number',        'branch_id')
    ) AS x(table_name, document_code, number_column, branch_column)
  LOOP
    EXECUTE FORMAT('DROP TRIGGER IF EXISTS %I ON public.%I',
      'trg_cas_number_' || v_cfg.table_name, v_cfg.table_name);
    EXECUTE FORMAT(
      'CREATE TRIGGER %I AFTER INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fn_bind_cas_document_number(%L,%L,%L)',
      'trg_cas_number_' || v_cfg.table_name,
      v_cfg.table_name, v_cfg.document_code,
      v_cfg.number_column, v_cfg.branch_column
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Capture immutable terminal-document evidence
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_capture_cas_document_void()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old JSONB := TO_JSONB(OLD);
  v_new JSONB := TO_JSONB(NEW);
  v_code TEXT := TG_ARGV[0];
  v_number TEXT := NULLIF(v_new->>TG_ARGV[1], '');
  v_date DATE := NULLIF(v_new->>TG_ARGV[2], '')::DATE;
  v_terminals TEXT[] := STRING_TO_ARRAY(TG_ARGV[3], ',');
  v_party_id UUID;
  v_party_name TEXT;
  v_party_tin TEXT;
  v_amount NUMERIC(15,2);
  v_branch UUID;
  v_reason_id UUID := NULLIF(v_new->>'void_reason_id', '')::UUID;
  v_reason TEXT := NULLIF(BTRIM(current_setting('pxl.cas_void_reason', TRUE)), '');
  v_original_je UUID := NULLIF(v_new->>'journal_entry_id', '')::UUID;
  v_reversal_je UUID;
  v_issuance_id UUID;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NOT (NEW.status = ANY(v_terminals)) THEN
    RETURN NEW;
  END IF;
  IF TG_TABLE_NAME = 'sales_invoices'
     AND COALESCE((v_new->>'is_cash_sale')::BOOLEAN, FALSE) THEN
    v_code := 'CS';
  END IF;

  IF COALESCE(TG_ARGV[4], '') <> '' THEN
    v_party_id := NULLIF(v_new->>TG_ARGV[4], '')::UUID;
  END IF;
  IF COALESCE(TG_ARGV[6], '') <> '' THEN v_party_name := NULLIF(v_new->>TG_ARGV[6], ''); END IF;
  IF COALESCE(TG_ARGV[7], '') <> '' THEN v_party_tin := NULLIF(v_new->>TG_ARGV[7], ''); END IF;
  IF COALESCE(TG_ARGV[8], '') <> '' THEN v_amount := NULLIF(v_new->>TG_ARGV[8], '')::NUMERIC; END IF;
  IF COALESCE(TG_ARGV[9], '') <> '' THEN v_branch := NULLIF(v_new->>TG_ARGV[9], '')::UUID; END IF;

  IF v_reason_id IS NOT NULL THEN
    SELECT COALESCE(v_reason, vrc.description)
    INTO v_reason
    FROM public.void_reason_codes vrc
    WHERE vrc.id = v_reason_id AND vrc.is_active = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or inactive void reason'; END IF;
  END IF;

  IF v_reason IS NULL AND TG_TABLE_NAME = 'receipts' AND NEW.status = 'bounced' THEN
    v_reason := 'Bounced payment instrument';
  END IF;
  IF v_reason IS NULL THEN
    v_reason := NULLIF(BTRIM(COALESCE(
      v_new->>'memo', v_new->>'remarks', v_new->>'notes', ''
    )), '');
  END IF;

  SELECT je.id,
         COALESCE(v_reason,
           NULLIF(BTRIM(REGEXP_REPLACE(COALESCE(je.description, ''), '^.* — ', '')), ''))
  INTO v_reversal_je, v_reason
  FROM public.journal_entries je
  WHERE je.company_id = NEW.company_id
    AND je.reference_doc_id = NEW.id
    AND je.id IS DISTINCT FROM v_original_je
    AND je.status = 'posted'
  ORDER BY je.created_at DESC
  LIMIT 1;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'A cancellation/void reason is required for CAS audit evidence';
  END IF;

  SELECT i.id INTO v_issuance_id
  FROM public.cas_document_number_issuances i
  WHERE i.source_table = TG_TABLE_NAME AND i.source_id = NEW.id;

  INSERT INTO public.cas_document_void_events (
    company_id, branch_id, number_issuance_id, source_table, source_id,
    document_code, document_number, document_date, terminal_status,
    reason_code_id, reason_text, event_actor_id,
    original_journal_entry_id, reversal_journal_entry_id,
    party_id, party_type, party_name, party_tin, document_amount,
    source_snapshot, occurred_at
  ) VALUES (
    NEW.company_id, v_branch, v_issuance_id, TG_TABLE_NAME, NEW.id,
    v_code, v_number, v_date, NEW.status,
    v_reason_id, v_reason, auth.uid(),
    v_original_je, v_reversal_je,
    v_party_id, NULLIF(TG_ARGV[5], ''), v_party_name, v_party_tin, v_amount,
    v_old, NOW()
  ) ON CONFLICT (source_table, source_id, terminal_status) DO NOTHING;

  UPDATE public.cas_document_number_issuances
  SET status = 'voided', voided_at = NOW(), void_reason = v_reason
  WHERE id = v_issuance_id AND status IN ('reserved', 'issued');

  RETURN NEW;
END;
$$;

DO $$
DECLARE
  v_cfg RECORD;
BEGIN
  FOR v_cfg IN
    SELECT * FROM (VALUES
      ('sales_invoices','SI','si_number','date','cancelled','customer_id','customer','customer_name_snapshot','customer_tin_snapshot','total_amount','branch_id'),
      ('vendor_bills','VB','bill_number','bill_date','cancelled','supplier_id','supplier','supplier_name_snapshot','supplier_tin_snapshot','total_amount','branch_id'),
      ('payment_vouchers','PV','voucher_number','voucher_date','cancelled','supplier_id','supplier','supplier_name_snapshot','supplier_tin_snapshot','total_amount','branch_id'),
      ('receipts','OR','receipt_number','receipt_date','bounced,cancelled','customer_id','customer','customer_name_snapshot','customer_tin_snapshot','total_amount','branch_id'),
      ('credit_memos','CM','cm_number','cm_date','cancelled','customer_id','customer','customer_name_snapshot','customer_tin_snapshot','total_amount','branch_id'),
      ('debit_memos','DM-S','dm_number','dm_date','cancelled','customer_id','customer','customer_name_snapshot','customer_tin_snapshot','total_amount','branch_id'),
      ('vendor_credits','VC','vc_number','credit_date','cancelled','supplier_id','supplier','supplier_name_snapshot','supplier_tin_snapshot','total_amount','branch_id'),
      ('fund_transfers','FT','ft_number','transfer_date','cancelled','','','','','amount','branch_id'),
      ('inter_branch_transfers','IBT','ibt_number','transfer_date','cancelled','','','','','amount','from_branch_id'),
      ('bank_adjustments','BADJ','ba_number','adjustment_date','cancelled','','','','','amount','branch_id'),
      ('petty_cash_vouchers','PCV','pcv_number','voucher_date','cancelled','','payee','payee','','amount','branch_id'),
      ('check_vouchers','CV','cv_number','voucher_date','cancelled','supplier_id','supplier','payee','payee_tin','total_gross_amount','branch_id')
    ) AS x(table_name, document_code, number_column, date_column, terminal_statuses,
           party_id_column, party_type, party_name_column, party_tin_column,
           amount_column, branch_column)
  LOOP
    EXECUTE FORMAT('DROP TRIGGER IF EXISTS %I ON public.%I',
      'trg_cas_void_' || v_cfg.table_name, v_cfg.table_name);
    EXECUTE FORMAT(
      'CREATE TRIGGER %I AFTER UPDATE OF status ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fn_capture_cas_document_void(%L,%L,%L,%L,%L,%L,%L,%L,%L,%L)',
      'trg_cas_void_' || v_cfg.table_name, v_cfg.table_name,
      v_cfg.document_code, v_cfg.number_column, v_cfg.date_column,
      v_cfg.terminal_statuses, v_cfg.party_id_column, v_cfg.party_type,
      v_cfg.party_name_column, v_cfg.party_tin_column,
      v_cfg.amount_column, v_cfg.branch_column
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Backfill surviving numbered documents and core historical terminal states
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_cfg RECORD;
  v_code_expr TEXT;
BEGIN
  FOR v_cfg IN
    SELECT * FROM (VALUES
      ('sales_quotations','QT','quotation_number','branch_id'),
      ('sales_orders','SO','so_number','branch_id'),
      ('delivery_receipts','DR','dr_number','branch_id'),
      ('sales_invoices','SI','si_number','branch_id'),
      ('receipts','OR','receipt_number','branch_id'),
      ('credit_memos','CM','cm_number','branch_id'),
      ('debit_memos','DM-S','dm_number','branch_id'),
      ('purchase_orders','PO','po_number','branch_id'),
      ('receiving_reports','RR','rr_number','branch_id'),
      ('vendor_bills','VB','bill_number','branch_id'),
      ('payment_vouchers','PV','voucher_number','branch_id'),
      ('cash_purchases','CP','cp_number','branch_id'),
      ('vendor_credits','VC','vc_number','branch_id'),
      ('supplier_debit_memos','SDM','sdm_number','branch_id'),
      ('purchase_returns','PRT','return_number','branch_id'),
      ('fund_transfers','FT','ft_number','branch_id'),
      ('inter_branch_transfers','IBT','ibt_number','from_branch_id'),
      ('bank_adjustments','BADJ','ba_number','branch_id'),
      ('petty_cash_vouchers','PCV','pcv_number','branch_id'),
      ('petty_cash_replenishments','PCR','pcr_number','branch_id'),
      ('check_vouchers','CV','cv_number','branch_id'),
      ('cash_count_sheets','CCS','sheet_number','branch_id'),
      ('fixed_assets','FA','asset_number','branch_id'),
      ('journal_entries','JE','je_number','branch_id')
    ) AS x(table_name, document_code, number_column, branch_column)
  LOOP
    v_code_expr := CASE WHEN v_cfg.table_name = 'sales_invoices'
      THEN 'CASE WHEN COALESCE(t.is_cash_sale, false) THEN ''CS'' ELSE ''SI'' END'
      ELSE QUOTE_LITERAL(v_cfg.document_code) END;
    EXECUTE FORMAT(
      'INSERT INTO public.cas_document_number_issuances (
         company_id, branch_id, document_code, document_number, status,
         source_table, source_id, allocated_by, allocated_at, issued_at
       )
       SELECT t.company_id, NULLIF(to_jsonb(t)->>%L, '''')::uuid,
              %s, t.%I::text, ''issued'', %L, t.id,
              t.created_by, COALESCE(t.created_at, NOW()), COALESCE(t.created_at, NOW())
       FROM public.%I t
       WHERE NULLIF(t.%I::text, '''') IS NOT NULL
       ON CONFLICT DO NOTHING',
      v_cfg.branch_column, v_code_expr, v_cfg.number_column,
      v_cfg.table_name, v_cfg.table_name, v_cfg.number_column
    );
  END LOOP;
END;
$$;

WITH historical AS (
  SELECT si.company_id, si.branch_id, 'sales_invoices'::TEXT AS source_table,
         si.id AS source_id, CASE WHEN si.is_cash_sale THEN 'CS' ELSE 'SI' END AS document_code,
         si.si_number AS document_number, si.date AS document_date, si.status AS terminal_status,
         si.void_reason_id AS reason_code_id,
         COALESCE(vr.description, NULLIF(BTRIM(si.memo), ''), 'Historical terminal state; original reason unavailable') AS reason_text,
         si.updated_by AS actor_id, si.journal_entry_id AS original_je_id,
         si.customer_id AS party_id, 'customer'::TEXT AS party_type,
         si.customer_name_snapshot AS party_name, si.customer_tin_snapshot AS party_tin,
         si.total_amount AS amount, TO_JSONB(si) AS snapshot, si.updated_at AS occurred_at
  FROM public.sales_invoices si
  LEFT JOIN public.void_reason_codes vr ON vr.id = si.void_reason_id
  WHERE si.status = 'cancelled'
  UNION ALL
  SELECT vb.company_id, vb.branch_id, 'vendor_bills', vb.id, 'VB', vb.bill_number,
         vb.bill_date, vb.status, vb.void_reason_id,
         COALESCE(vr.description, NULLIF(BTRIM(vb.memo), ''), 'Historical terminal state; original reason unavailable'),
         vb.updated_by, vb.journal_entry_id, vb.supplier_id, 'supplier',
         vb.supplier_name_snapshot, vb.supplier_tin_snapshot, vb.total_amount,
         TO_JSONB(vb), vb.updated_at
  FROM public.vendor_bills vb
  LEFT JOIN public.void_reason_codes vr ON vr.id = vb.void_reason_id
  WHERE vb.status = 'cancelled'
  UNION ALL
  SELECT pv.company_id, pv.branch_id, 'payment_vouchers', pv.id, 'PV', pv.voucher_number,
         pv.voucher_date, pv.status, NULL::UUID,
         COALESCE(NULLIF(BTRIM(pv.remarks), ''), 'Historical terminal state; original reason unavailable'),
         pv.updated_by, pv.journal_entry_id, pv.supplier_id, 'supplier',
         pv.supplier_name_snapshot, pv.supplier_tin_snapshot, pv.total_amount,
         TO_JSONB(pv), pv.updated_at
  FROM public.payment_vouchers pv WHERE pv.status = 'cancelled'
  UNION ALL
  SELECT r.company_id, r.branch_id, 'receipts', r.id, 'OR', r.receipt_number,
         r.receipt_date, r.status, NULL::UUID,
         CASE WHEN r.status = 'bounced' THEN 'Bounced payment instrument'
              ELSE 'Historical terminal state; original reason unavailable' END,
         r.updated_by, r.journal_entry_id, r.customer_id, 'customer',
         r.customer_name_snapshot, r.customer_tin_snapshot, r.total_amount,
         TO_JSONB(r), r.updated_at
  FROM public.receipts r WHERE r.status IN ('bounced', 'cancelled')
  UNION ALL
  SELECT cv.company_id, cv.branch_id, 'check_vouchers', cv.id, 'CV', cv.cv_number,
         cv.voucher_date, cv.status, NULL::UUID,
         'Historical terminal state; original reason unavailable',
         cv.updated_by, cv.journal_entry_id, cv.supplier_id, 'supplier',
         cv.payee, cv.payee_tin, cv.total_gross_amount,
         TO_JSONB(cv), cv.updated_at
  FROM public.check_vouchers cv WHERE cv.status = 'cancelled'
)
INSERT INTO public.cas_document_void_events (
  company_id, branch_id, number_issuance_id, source_table, source_id,
  document_code, document_number, document_date, terminal_status,
  reason_code_id, reason_text, event_actor_id,
  original_journal_entry_id, reversal_journal_entry_id,
  party_id, party_type, party_name, party_tin, document_amount,
  source_snapshot, occurred_at
)
SELECT h.company_id, h.branch_id, i.id, h.source_table, h.source_id,
       h.document_code, h.document_number, h.document_date, h.terminal_status,
       h.reason_code_id, h.reason_text, h.actor_id,
       h.original_je_id, rev.id,
       h.party_id, h.party_type, h.party_name, h.party_tin, h.amount,
       h.snapshot, COALESCE(h.occurred_at, NOW())
FROM historical h
LEFT JOIN public.cas_document_number_issuances i
  ON i.source_table = h.source_table AND i.source_id = h.source_id
LEFT JOIN LATERAL (
  SELECT je.id
  FROM public.journal_entries je
  WHERE je.company_id = h.company_id
    AND je.reference_doc_id = h.source_id
    AND je.id IS DISTINCT FROM h.original_je_id
    AND je.status = 'posted'
  ORDER BY je.created_at DESC
  LIMIT 1
) rev ON TRUE
ON CONFLICT (source_table, source_id, terminal_status) DO NOTHING;

UPDATE public.cas_document_number_issuances i
SET status = 'voided',
    voided_at = v.occurred_at,
    void_reason = v.reason_text
FROM public.cas_document_void_events v
WHERE v.number_issuance_id = i.id
  AND i.status IN ('reserved', 'issued');

-- ---------------------------------------------------------------------------
-- 6. Governed ATP usage read model
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.vw_cas_atp_usage
WITH (security_invoker = TRUE)
AS
SELECT
  ns.id AS number_series_id,
  ns.company_id,
  ns.branch_id,
  b.branch_name,
  ns.document_code,
  dt.document_name,
  ns.prefix,
  ns.suffix,
  COALESCE(ns.padding, ns.number_length, 6) AS padding,
  ns.atp_series_start,
  ns.atp_series_end,
  COALESCE(ns.current_sequence, 0) AS current_sequence,
  CASE
    WHEN ns.atp_series_start IS NOT NULL
      THEN GREATEST(COALESCE(ns.current_sequence, 0) + 1, ns.atp_series_start)
    ELSE COALESCE(ns.current_sequence, 0) + 1
  END AS next_sequence,
  CASE
    WHEN ns.atp_series_start IS NULL THEN NULL
    ELSE GREATEST(
      ns.atp_series_end - GREATEST(COALESCE(ns.current_sequence, 0), ns.atp_series_start - 1),
      0
    )
  END AS numbers_remaining,
  COUNT(i.id) FILTER (WHERE i.status = 'reserved')::INTEGER AS reserved_count,
  COUNT(i.id) FILTER (WHERE i.status = 'issued')::INTEGER AS issued_count,
  COUNT(i.id) FILTER (WHERE i.status IN ('voided', 'abandoned'))::INTEGER AS voided_count,
  COUNT(i.id)::INTEGER AS total_allocated_count,
  CASE
    WHEN ns.atp_series_start IS NULL OR ns.atp_series_end < ns.atp_series_start THEN NULL
    ELSE ROUND(
      100.0 * (
        (ns.atp_series_end - ns.atp_series_start + 1)
        - GREATEST(ns.atp_series_end - GREATEST(COALESCE(ns.current_sequence, 0), ns.atp_series_start - 1), 0)
      ) / NULLIF(ns.atp_series_end - ns.atp_series_start + 1, 0),
      2
    )
  END AS usage_percent,
  (ns.atp_series_end IS NOT NULL AND COALESCE(ns.current_sequence, 0) >= ns.atp_series_end) AS is_exhausted,
  (
    ns.atp_series_end IS NOT NULL
    AND ns.atp_alert_threshold IS NOT NULL
    AND GREATEST(
      ns.atp_series_end - GREATEST(COALESCE(ns.current_sequence, 0), ns.atp_series_start - 1),
      0
    ) <= ns.atp_alert_threshold
  ) AS at_or_below_alert_threshold,
  ns.atp_alert_threshold,
  ns.is_active
FROM public.number_series ns
JOIN public.branches b ON b.id = ns.branch_id
LEFT JOIN public.ref_document_types dt ON dt.id = ns.document_type_id
LEFT JOIN public.cas_document_number_issuances i ON i.number_series_id = ns.id
GROUP BY ns.id, b.branch_name, dt.document_name;

GRANT SELECT ON public.vw_cas_atp_usage TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.fn_guard_cas_number_series()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_bind_cas_document_number()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_capture_cas_document_void()
  FROM PUBLIC, anon, authenticated, service_role;

