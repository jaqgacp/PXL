-- Semantic transaction lifecycle event log (PXL-DA-016).
--
-- Row audit remains useful for forensic diffs, but it is too noisy to prove
-- business lifecycle evidence on its own.  This migration adds a governed
-- transaction_events stream for create/approve/post/void/reverse/export/file
-- style events, then wires it into existing posting-event helpers and generic
-- lifecycle/report triggers.

CREATE TABLE IF NOT EXISTS public.transaction_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  source_doc_type TEXT NOT NULL,
  source_doc_id UUID,
  source_table TEXT,
  source_document_no TEXT,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'CREATED',
    'EDITED',
    'SUBMITTED',
    'APPROVED',
    'REJECTED',
    'BYPASSED',
    'POSTED',
    'REVERSED',
    'VOIDED',
    'CANCELLED',
    'BOUNCED',
    'RETURNED_TO_DRAFT',
    'FINALIZED',
    'FILED',
    'EXPORTED',
    'GENERATED',
    'SENT',
    'ACKNOWLEDGED',
    'APPLIED',
    'RELEASED',
    'CLOSED',
    'STATUS_CHANGED'
  )),
  before_status TEXT,
  after_status TEXT,
  reason TEXT,
  actor_id UUID,
  actor_role TEXT,
  journal_entry_id UUID REFERENCES journal_entries(id),
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transaction_events_company_time
  ON public.transaction_events (company_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_transaction_events_source
  ON public.transaction_events (source_doc_type, source_doc_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_transaction_events_je
  ON public.transaction_events (journal_entry_id)
  WHERE journal_entry_id IS NOT NULL;

ALTER TABLE public.transaction_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS transaction_events_read ON public.transaction_events;
CREATE POLICY transaction_events_read
  ON public.transaction_events
  FOR SELECT TO authenticated
  USING (is_company_member(company_id));

REVOKE ALL ON public.transaction_events FROM authenticated;
GRANT SELECT ON public.transaction_events TO authenticated;
GRANT ALL ON public.transaction_events TO service_role;

COMMENT ON TABLE public.transaction_events IS
  'Governed semantic lifecycle event stream for source documents, approvals, postings, reversals, compliance filings, and exports. Direct client writes are not granted; events are written by SECURITY DEFINER helpers and triggers.';

CREATE OR REPLACE FUNCTION public.fn_transaction_actor_role()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_claims JSONB := '{}'::jsonb;
BEGIN
  BEGIN
    v_claims := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    v_claims := '{}'::jsonb;
  END;

  RETURN COALESCE(NULLIF(v_claims->>'role', ''), NULLIF(current_setting('role', true), ''), current_user);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_transaction_event_type_for_status(
  p_before_status TEXT,
  p_after_status TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE lower(coalesce(p_after_status, ''))
    WHEN 'draft' THEN
      CASE WHEN p_before_status IS NULL THEN 'CREATED' ELSE 'RETURNED_TO_DRAFT' END
    WHEN 'submitted' THEN 'SUBMITTED'
    WHEN 'approved' THEN 'APPROVED'
    WHEN 'rejected' THEN 'REJECTED'
    WHEN 'posted' THEN 'POSTED'
    WHEN 'reversed' THEN 'REVERSED'
    WHEN 'voided' THEN 'VOIDED'
    WHEN 'void' THEN 'VOIDED'
    WHEN 'cancelled' THEN 'CANCELLED'
    WHEN 'canceled' THEN 'CANCELLED'
    WHEN 'bounced' THEN 'BOUNCED'
    WHEN 'final' THEN 'FINALIZED'
    WHEN 'filed' THEN 'FILED'
    WHEN 'exported' THEN 'EXPORTED'
    WHEN 'generated' THEN 'GENERATED'
    WHEN 'sent' THEN 'SENT'
    WHEN 'acknowledged' THEN 'ACKNOWLEDGED'
    WHEN 'applied' THEN 'APPLIED'
    WHEN 'released' THEN 'RELEASED'
    WHEN 'closed' THEN 'CLOSED'
    ELSE 'STATUS_CHANGED'
  END;
$$;

CREATE OR REPLACE FUNCTION public.fn_record_transaction_event(
  p_company_id UUID,
  p_source_doc_type TEXT,
  p_source_doc_id UUID,
  p_event_type TEXT,
  p_source_table TEXT DEFAULT NULL,
  p_before_status TEXT DEFAULT NULL,
  p_after_status TEXT DEFAULT NULL,
  p_reason TEXT DEFAULT NULL,
  p_journal_entry_id UUID DEFAULT NULL,
  p_details JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_type TEXT := upper(btrim(coalesce(p_event_type, '')));
  v_source_type TEXT := upper(btrim(coalesce(p_source_doc_type, '')));
  v_details JSONB := coalesce(p_details, '{}'::jsonb);
  v_source_table TEXT := NULLIF(btrim(coalesce(p_source_table, '')), '');
  v_source_document_no TEXT;
  v_doc_column NAME;
  v_registry_table REGCLASS;
  v_id UUID;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'Transaction event company_id is required';
  END IF;
  IF v_source_type = '' THEN
    RAISE EXCEPTION 'Transaction event source_doc_type is required';
  END IF;
  IF v_event_type NOT IN (
    'CREATED','EDITED','SUBMITTED','APPROVED','REJECTED','BYPASSED',
    'POSTED','REVERSED','VOIDED','CANCELLED','BOUNCED','RETURNED_TO_DRAFT',
    'FINALIZED','FILED','EXPORTED','GENERATED','SENT','ACKNOWLEDGED',
    'APPLIED','RELEASED','CLOSED','STATUS_CHANGED'
  ) THEN
    RAISE EXCEPTION 'Unsupported transaction event type %', p_event_type;
  END IF;

  IF auth.uid() IS NOT NULL AND NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'Access denied: not a member of company %', p_company_id;
  END IF;

  SELECT source_table, document_number_column
    INTO v_registry_table, v_doc_column
  FROM ref_posting_source_types
  WHERE document_type = v_source_type
    AND is_active = true;

  IF FOUND AND p_source_doc_id IS NOT NULL THEN
    PERFORM fn_assert_posting_source(v_source_type, p_source_doc_id, p_company_id);
  END IF;

  IF v_source_table IS NULL AND v_registry_table IS NOT NULL THEN
    v_source_table := v_registry_table::TEXT;
  END IF;

  IF v_registry_table IS NOT NULL AND v_doc_column IS NOT NULL AND p_source_doc_id IS NOT NULL THEN
    EXECUTE format('SELECT (%I)::text FROM %s WHERE id = $1', v_doc_column, v_registry_table)
      INTO v_source_document_no
      USING p_source_doc_id;
  END IF;

  INSERT INTO public.transaction_events (
    company_id, source_doc_type, source_doc_id, source_table, source_document_no,
    event_type, before_status, after_status, reason, actor_id, actor_role,
    journal_entry_id, details
  ) VALUES (
    p_company_id, v_source_type, p_source_doc_id, v_source_table, v_source_document_no,
    v_event_type, NULLIF(p_before_status, ''), NULLIF(p_after_status, ''),
    COALESCE(NULLIF(p_reason, ''), NULLIF(v_details->>'reason', ''), NULLIF(v_details->>'memo', '')),
    auth.uid(), fn_transaction_actor_role(),
    p_journal_entry_id, v_details
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_record_transaction_event(
  UUID, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, JSONB
) FROM PUBLIC;

-- Preserve the existing posting audit contract while also writing the governed
-- semantic event row used by PXL-DA-016.
CREATE OR REPLACE FUNCTION public.fn_record_posting_event(
  p_company_id UUID,
  p_source_doc_type TEXT,
  p_source_doc_id UUID,
  p_event_type TEXT,
  p_journal_entry_id UUID DEFAULT NULL,
  p_details JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_event_type TEXT := upper(btrim(coalesce(p_event_type, '')));
BEGIN
  IF v_event_type NOT IN ('POSTED', 'REVERSED', 'VOIDED', 'CANCELLED', 'BOUNCED') THEN
    RAISE EXCEPTION 'Unsupported posting event %', p_event_type;
  END IF;

  PERFORM fn_assert_posting_source(
    p_source_doc_type,
    p_source_doc_id,
    p_company_id
  );

  v_id := fn_record_transaction_event(
    p_company_id,
    p_source_doc_type,
    p_source_doc_id,
    v_event_type,
    NULL,
    NULL,
    CASE v_event_type
      WHEN 'POSTED' THEN 'posted'
      WHEN 'REVERSED' THEN 'reversed'
      WHEN 'VOIDED' THEN 'voided'
      WHEN 'CANCELLED' THEN 'cancelled'
      WHEN 'BOUNCED' THEN 'bounced'
      ELSE NULL
    END,
    NULL,
    p_journal_entry_id,
    coalesce(p_details, '{}'::jsonb)
  );

  INSERT INTO sys_audit_logs (
    company_id, table_name, record_id, action, old_data, new_data, changed_by
  ) VALUES (
    p_company_id,
    'posting_event',
    p_source_doc_id,
    'UPDATE',
    NULL,
    jsonb_build_object(
      'event_type', v_event_type,
      'source_doc_type', upper(btrim(p_source_doc_type)),
      'journal_entry_id', p_journal_entry_id,
      'transaction_event_id', v_id,
      'details', coalesce(p_details, '{}'::jsonb)
    ),
    auth.uid()
  );

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_record_posting_event(UUID, TEXT, UUID, TEXT, UUID, JSONB)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_capture_registered_source_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc_type TEXT := TG_ARGV[0];
  v_status_column TEXT := TG_ARGV[1];
  v_doc_column TEXT := TG_ARGV[2];
  v_new JSONB := to_jsonb(NEW);
  v_old JSONB := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;
  v_company_id UUID;
  v_before_status TEXT;
  v_after_status TEXT;
  v_event_type TEXT;
BEGIN
  v_company_id := NULLIF(v_new->>'company_id', '')::uuid;
  IF v_company_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_after_status := NULLIF(v_new->>v_status_column, '');
  IF TG_OP = 'INSERT' THEN
    v_event_type := CASE
      WHEN lower(coalesce(v_after_status, '')) IN (
        'approved','posted','final','filed','exported','generated','sent',
        'acknowledged','applied','released','closed'
      ) THEN fn_transaction_event_type_for_status(NULL, v_after_status)
      ELSE 'CREATED'
    END;
  ELSE
    v_before_status := NULLIF(v_old->>v_status_column, '');
    IF v_after_status IS NOT DISTINCT FROM v_before_status THEN
      RETURN NEW;
    END IF;
    v_event_type := fn_transaction_event_type_for_status(v_before_status, v_after_status);
  END IF;

  PERFORM fn_record_transaction_event(
    v_company_id,
    v_doc_type,
    NEW.id,
    v_event_type,
    TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
    v_before_status,
    v_after_status,
    NULL,
    NULL,
    jsonb_build_object(
      'source', 'registered_source_status_trigger',
      'document_number', CASE WHEN v_doc_column IS NULL OR v_doc_column = '' THEN NULL ELSE v_new->>v_doc_column END
    )
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_capture_journal_entry_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_before_status TEXT;
  v_after_status TEXT;
  v_event_type TEXT;
  v_source_type TEXT;
  v_source_id UUID;
BEGIN
  IF NEW.company_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_after_status := NEW.status;
    v_event_type := CASE
      WHEN lower(coalesce(v_after_status, '')) = 'posted' THEN 'POSTED'
      ELSE 'CREATED'
    END;
  ELSE
    v_before_status := OLD.status;
    v_after_status := NEW.status;
    IF v_after_status IS NOT DISTINCT FROM v_before_status
       AND NEW.reference_doc_id IS DISTINCT FROM OLD.reference_doc_id
       AND lower(coalesce(NEW.status, '')) = 'posted' THEN
      v_event_type := 'POSTED';
    ELSIF v_after_status IS NOT DISTINCT FROM v_before_status THEN
      RETURN NEW;
    ELSE
      v_event_type := fn_transaction_event_type_for_status(v_before_status, v_after_status);
    END IF;
  END IF;

  v_source_type := coalesce(NULLIF(NEW.reference_doc_type, ''), 'MANUAL');
  v_source_id := CASE
    WHEN NEW.reference_doc_id IS NOT NULL AND v_source_type NOT IN ('MANUAL', 'CLOSE')
      THEN NEW.reference_doc_id
    ELSE NEW.id
  END;

  -- Fixed-asset and some schedule writers create the journal before the source
  -- row exists.  The link triggers attach reference_doc_id shortly afterward;
  -- record the semantic event on that link update instead of failing the insert.
  IF v_source_type NOT IN ('MANUAL', 'CLOSE', 'REV')
     AND NEW.reference_doc_id IS NULL THEN
    RETURN NEW;
  END IF;

  BEGIN
    PERFORM fn_record_transaction_event(
      NEW.company_id,
      v_source_type,
      v_source_id,
      v_event_type,
      'public.journal_entries',
      v_before_status,
      v_after_status,
      NULL,
      NEW.id,
      jsonb_build_object(
        'source', 'journal_entry_status_trigger',
        'je_number', NEW.je_number,
        'entry_class', NEW.entry_class,
        'reference_doc_type', NEW.reference_doc_type,
        'reference_doc_id', NEW.reference_doc_id
      )
    );
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'Posting source %.% does not exist' THEN
      RETURN NEW;
    END IF;
    RAISE;
  END;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_capture_approval_instance_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_type TEXT;
  v_before_status TEXT;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    v_before_status := OLD.status;
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
      RETURN NEW;
    END IF;
  END IF;

  v_event_type := CASE lower(coalesce(NEW.status, ''))
    WHEN 'approved' THEN 'APPROVED'
    WHEN 'rejected' THEN 'REJECTED'
    WHEN 'bypassed' THEN 'BYPASSED'
    ELSE NULL
  END;

  IF v_event_type IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM fn_record_transaction_event(
    NEW.company_id,
    NEW.source_document_type,
    NEW.source_document_id,
    v_event_type,
    NULL,
    v_before_status,
    NEW.status,
    NEW.remarks,
    NULL,
    jsonb_build_object(
      'source', 'approval_instance_trigger',
      'approval_instance_id', NEW.id,
      'workflow_id', NEW.workflow_id,
      'workflow_step_id', NEW.workflow_step_id,
      'actual_approver_id', NEW.actual_approver_id,
      'source_document_no', NEW.source_document_no,
      'source_document_amount', NEW.source_document_amount
    )
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_capture_report_snapshot_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_type TEXT;
BEGIN
  v_event_type := fn_transaction_event_type_for_status(NULL, NEW.snapshot_status);

  PERFORM fn_record_transaction_event(
    NEW.company_id,
    NEW.report_type,
    NEW.source_id,
    v_event_type,
    NEW.source_table,
    NULL,
    NEW.snapshot_status,
    NULL,
    NULL,
    jsonb_build_object(
      'source', 'report_snapshot_trigger',
      'snapshot_id', NEW.id,
      'snapshot_status', NEW.snapshot_status,
      'snapshot_version', NEW.snapshot_version,
      'period_start', NEW.period_start,
      'period_end', NEW.period_end,
      'source_hash', NEW.source_hash,
      'source_row_count', NEW.source_row_count
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_transaction_event_journal_insert ON public.journal_entries;
CREATE TRIGGER trg_transaction_event_journal_insert
  AFTER INSERT ON public.journal_entries
  FOR EACH ROW EXECUTE FUNCTION public.fn_capture_journal_entry_event();

DROP TRIGGER IF EXISTS trg_transaction_event_journal_status ON public.journal_entries;
CREATE TRIGGER trg_transaction_event_journal_status
  AFTER UPDATE OF status ON public.journal_entries
  FOR EACH ROW EXECUTE FUNCTION public.fn_capture_journal_entry_event();

DROP TRIGGER IF EXISTS trg_transaction_event_journal_source_link ON public.journal_entries;
CREATE TRIGGER trg_transaction_event_journal_source_link
  AFTER UPDATE OF reference_doc_id ON public.journal_entries
  FOR EACH ROW EXECUTE FUNCTION public.fn_capture_journal_entry_event();

DROP TRIGGER IF EXISTS trg_transaction_event_approval_insert ON public.approval_instances;
CREATE TRIGGER trg_transaction_event_approval_insert
  AFTER INSERT ON public.approval_instances
  FOR EACH ROW EXECUTE FUNCTION public.fn_capture_approval_instance_event();

DROP TRIGGER IF EXISTS trg_transaction_event_approval_status ON public.approval_instances;
CREATE TRIGGER trg_transaction_event_approval_status
  AFTER UPDATE OF status ON public.approval_instances
  FOR EACH ROW EXECUTE FUNCTION public.fn_capture_approval_instance_event();

DROP TRIGGER IF EXISTS trg_transaction_event_report_snapshot ON public.report_snapshots;
CREATE TRIGGER trg_transaction_event_report_snapshot
  AFTER INSERT ON public.report_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.fn_capture_report_snapshot_event();

DO $$
DECLARE
  v_ref RECORD;
BEGIN
  FOR v_ref IN
    SELECT rpst.document_type,
           rpst.source_table,
           rpst.status_column,
           rpst.document_number_column,
           n.nspname AS table_schema,
           c.relname AS table_name
    FROM ref_posting_source_types rpst
    JOIN pg_class c ON c.oid = source_table
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE is_active = true
      AND source_table IS NOT NULL
      AND source_table <> 'journal_entries'::regclass
      AND status_column IS NOT NULL
    ORDER BY document_type
  LOOP
    IF EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = v_ref.table_schema
        AND table_name = v_ref.table_name
        AND column_name IN ('id', 'company_id', v_ref.status_column::text)
      GROUP BY table_schema, table_name
      HAVING count(DISTINCT column_name) = 3
    ) THEN
      EXECUTE format(
        'DROP TRIGGER IF EXISTS trg_transaction_event_source_insert ON %s',
        v_ref.source_table
      );
      EXECUTE format(
        'CREATE TRIGGER trg_transaction_event_source_insert
           AFTER INSERT ON %s
           FOR EACH ROW EXECUTE FUNCTION public.fn_capture_registered_source_event(%L, %L, %L)',
        v_ref.source_table,
        v_ref.document_type,
        v_ref.status_column::text,
        coalesce(v_ref.document_number_column::text, '')
      );

      EXECUTE format(
        'DROP TRIGGER IF EXISTS trg_transaction_event_source_status ON %s',
        v_ref.source_table
      );
      EXECUTE format(
        'CREATE TRIGGER trg_transaction_event_source_status
           AFTER UPDATE OF %I ON %s
           FOR EACH ROW EXECUTE FUNCTION public.fn_capture_registered_source_event(%L, %L, %L)',
        v_ref.status_column::text,
        v_ref.source_table,
        v_ref.document_type,
        v_ref.status_column::text,
        coalesce(v_ref.document_number_column::text, '')
      );
    END IF;
  END LOOP;
END;
$$;
