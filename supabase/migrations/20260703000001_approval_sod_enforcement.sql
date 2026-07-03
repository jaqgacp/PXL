-- ══════════════════════════════════════════════════════════════════════════════
-- APPROVAL SEGREGATION OF DUTIES (DEC-010)
-- Finding coverage: PXL-DA-012.
--
-- The approval workflow tables (approval_workflows/steps/instances) existed as
-- setup-only: nothing created instances and no posting path consulted them, so
-- a configured approval was cosmetic. Per DEC-010:
--   - When an active workflow matches a company/document (module, optional
--     document-type label, trigger condition), the transition into 'approved'
--     requires an approver different from the document creator, and the
--     approval is recorded as an approval_instances row with actor+timestamp.
--   - Posting a two-step document (draft -> approved -> posted) then requires
--     a recorded qualifying approval (or, for documents approved before this
--     migration, approved_by set and different from the creator).
--   - Documents that post directly from draft (receipts, payment vouchers)
--     treat posting as the approval act: creator cannot post, and the posting
--     is recorded as the approval instance.
--   - When no workflow is configured, nothing changes: the DEC-009 role gate
--     (owner/admin only) still applies. Workflows are not force-enabled.
--
-- Enforcement is trigger-based like the DEC-009 lifecycle gate: BEFORE triggers
-- fire inside SECURITY DEFINER RPC DML with auth.uid() as the calling user, and
-- they equally catch direct status UPDATEs that shortcut the RPCs.
--
-- Scope: sales_invoices, receipts, vendor_bills, payment_vouchers,
-- purchase_orders, petty_cash_vouchers. journal_entries is NOT gated: system
-- JEs from posting RPCs are indistinguishable from manual JEs today, so a
-- 'journal' workflow would block every posting path (tracked in PXL-DA-012
-- notes until a manual/system discriminator exists).
-- ══════════════════════════════════════════════════════════════════════════════

-- Instances may now record approvals for workflows configured without steps.
ALTER TABLE approval_instances ALTER COLUMN workflow_step_id DROP NOT NULL;

-- ── 1. Which workflow (if any) demands approval for this document? ─────────────
-- Blank document_type on a workflow means "all documents of the module".
-- trigger_condition_type semantics: 'amount_exceeds' compares the document
-- total against threshold_value; 'always' always applies. The remaining
-- configured conditions (discount_pct_exceeds, credit_limit_exceeded) have no
-- generic evaluator yet and are treated as always-required — the conservative
-- reading: a configured control must operate, never silently skip.
CREATE OR REPLACE FUNCTION fn_required_approval_workflow(
  p_company_id UUID,
  p_module_type TEXT,
  p_document_label TEXT,
  p_amount NUMERIC
)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT aw.id
  FROM approval_workflows aw
  WHERE aw.company_id = p_company_id
    AND aw.is_active
    AND aw.module_type = p_module_type
    AND (COALESCE(TRIM(aw.document_type), '') = ''
         OR lower(TRIM(aw.document_type)) = lower(p_document_label))
    AND (aw.trigger_condition_type <> 'amount_exceeds'
         OR COALESCE(p_amount, 0) > COALESCE(aw.threshold_value, 0))
  ORDER BY (COALESCE(TRIM(aw.document_type), '') = '') ASC,
           (aw.trigger_condition_type = 'always') DESC,
           aw.created_at ASC
  LIMIT 1;
$$;

COMMENT ON FUNCTION fn_required_approval_workflow(UUID, TEXT, TEXT, NUMERIC) IS
  'DEC-010: returns the active approval workflow governing a document, or NULL '
  'when approval is not required. Specific document-type workflows win over '
  'blank (all-documents) ones.';

GRANT EXECUTE ON FUNCTION fn_required_approval_workflow(UUID, TEXT, TEXT, NUMERIC) TO authenticated;

-- ── 2. Trigger: SoD on approval, qualifying approval required to post ──────────
-- TG_ARGV: [0] module_type, [1] document label, [2] amount column,
--          [3] document-number column, [4] mode:
--            two_step     draft -> approved -> posted (SI, VB)
--            direct_post  draft -> posted; posting is the approval act (OR, PV)
--            approve_only approved is terminal for accounting purposes (PO, PCV)
CREATE OR REPLACE FUNCTION fn_enforce_approval_sod()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_module      TEXT := TG_ARGV[0];
  v_label       TEXT := TG_ARGV[1];
  v_mode        TEXT := TG_ARGV[4];
  v_doc         JSONB;
  v_amount      NUMERIC;
  v_doc_no      TEXT;
  v_workflow_id UUID;
  v_wf_name     TEXT;
  v_is_approval_act BOOLEAN;
BEGIN
  IF NOT (
       (TG_OP = 'INSERT' AND NEW.status IN ('approved', 'posted'))
    OR (TG_OP = 'UPDATE'
        AND NEW.status IS DISTINCT FROM OLD.status
        AND NEW.status IN ('approved', 'posted'))
  ) THEN
    RETURN NEW;
  END IF;

  v_doc    := to_jsonb(NEW);
  v_amount := NULLIF(v_doc ->> TG_ARGV[2], '')::numeric;
  v_doc_no := COALESCE(v_doc ->> TG_ARGV[3], '(unnumbered)');

  v_workflow_id := fn_required_approval_workflow(NEW.company_id, v_module, v_label, v_amount);
  IF v_workflow_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT workflow_name INTO v_wf_name FROM approval_workflows WHERE id = v_workflow_id;

  v_is_approval_act := (NEW.status = 'approved')
                       OR (NEW.status = 'posted' AND v_mode = 'direct_post');

  IF v_is_approval_act THEN
    IF auth.uid() IS NOT DISTINCT FROM NEW.created_by THEN
      RAISE EXCEPTION 'Approval workflow "%" requires segregation of duties: % % cannot be approved by its creator',
        v_wf_name, v_label, v_doc_no;
    END IF;

    INSERT INTO approval_instances (
      company_id, workflow_id, workflow_step_id,
      source_document_type, source_document_id, source_document_no,
      source_document_amount, step_sequence,
      required_approver_type, required_approver_id,
      actual_approver_id, status, acted_at, created_by
    )
    SELECT NEW.company_id, v_workflow_id, s.id,
           v_label, NEW.id, v_doc_no,
           v_amount, COALESCE(s.step_sequence, 1),
           COALESCE(s.approver_type, 'role'), s.approver_user_id,
           auth.uid(), 'approved', NOW(), auth.uid()
    FROM (SELECT NULL) AS one
    LEFT JOIN LATERAL (
      SELECT id, step_sequence, approver_type, approver_user_id
      FROM approval_workflow_steps
      WHERE workflow_id = v_workflow_id
      ORDER BY step_sequence
      LIMIT 1
    ) s ON TRUE;

  ELSIF NEW.status = 'posted' THEN
    -- Two-step post: a qualifying approval must already be recorded. Documents
    -- approved before this migration qualify through approved_by evidence, as
    -- long as the approver differed from the creator.
    IF NOT EXISTS (
         SELECT 1 FROM approval_instances ai
         WHERE ai.source_document_id = NEW.id
           AND ai.company_id = NEW.company_id
           AND ai.status = 'approved'
           AND ai.actual_approver_id IS NOT NULL
           AND ai.actual_approver_id IS DISTINCT FROM NEW.created_by
       )
       AND NOT (
         NULLIF(v_doc ->> 'approved_by', '') IS NOT NULL
         AND (v_doc ->> 'approved_by')::uuid IS DISTINCT FROM NEW.created_by
       )
    THEN
      RAISE EXCEPTION 'Approval workflow "%" requires an approval by someone other than the creator before posting % %',
        v_wf_name, v_label, v_doc_no;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_enforce_approval_sod() IS
  'DEC-010 approval segregation of duties (PXL-DA-012): when an active workflow '
  'matches, approving requires approver <> creator and records an '
  'approval_instances row; posting a two-step document requires a recorded '
  'qualifying approval. No workflow configured -> no change (DEC-009 role gate '
  'still applies).';

-- ── 3. Attach to the governed document tables ──────────────────────────────────
DO $$
DECLARE
  spec RECORD;
BEGIN
  FOR spec IN
    SELECT * FROM (VALUES
      ('sales_invoices',      'sales',      'Sales Invoice',       'total_amount', 'si_number',      'two_step'),
      ('vendor_bills',        'purchasing', 'Vendor Bill',         'total_amount', 'bill_number',    'two_step'),
      ('receipts',            'sales',      'Official Receipt',    'total_amount', 'receipt_number', 'direct_post'),
      ('payment_vouchers',    'payment',    'Payment Voucher',     'total_amount', 'voucher_number', 'direct_post'),
      ('purchase_orders',     'purchasing', 'Purchase Order',      'total_amount', 'po_number',      'approve_only'),
      ('petty_cash_vouchers', 'payment',    'Petty Cash Voucher',  'amount',       'pcv_number',     'approve_only')
    ) AS t(tbl, module, label, amount_col, docno_col, mode)
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_approval_sod_%s_insert ON %I', spec.tbl, spec.tbl);
    EXECUTE format(
      'CREATE TRIGGER trg_approval_sod_%s_insert
         BEFORE INSERT ON %I
         FOR EACH ROW EXECUTE FUNCTION fn_enforce_approval_sod(%L, %L, %L, %L, %L)',
      spec.tbl, spec.tbl, spec.module, spec.label, spec.amount_col, spec.docno_col, spec.mode);

    EXECUTE format('DROP TRIGGER IF EXISTS trg_approval_sod_%s ON %I', spec.tbl, spec.tbl);
    EXECUTE format(
      'CREATE TRIGGER trg_approval_sod_%s
         BEFORE UPDATE OF status ON %I
         FOR EACH ROW EXECUTE FUNCTION fn_enforce_approval_sod(%L, %L, %L, %L, %L)',
      spec.tbl, spec.tbl, spec.module, spec.label, spec.amount_col, spec.docno_col, spec.mode);
  END LOOP;
END;
$$;
