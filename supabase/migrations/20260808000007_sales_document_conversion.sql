-- ============================================================================
-- Sales Document Conversion Engine
--
-- One database authority owns commercial lineage and quantity reservation for:
--   Quotation -> Sales Order -> Delivery Receipt -> Sales Invoice -> Receipt
--
-- A draft target reserves its source quantity immediately.  Rejection,
-- cancellation, or void reverses that reservation.  Conversion records lineage;
-- it never creates inventory or accounting events.  Existing delivery/invoice
-- posting functions remain the only inventory/accounting authorities.
-- ============================================================================

ALTER TABLE public.sales_quotations
  DROP CONSTRAINT IF EXISTS sales_quotations_status_check;
ALTER TABLE public.sales_quotations
  ADD CONSTRAINT sales_quotations_status_check
  CHECK (status IN ('draft','pending','approved','rejected','expired','cancelled'));

-- The legacy outbound slice treated a delivery line as either wholly billed or
-- wholly unbilled. The conversion authority now meters exact quantities under
-- a source-line lock, so one delivery line may legitimately feed several
-- invoices while over-billing remains impossible.
DROP INDEX IF EXISTS public.uq_sil_delivery_source;

-- The historical readiness core checked current stock for every inventory SI
-- line. A DR-linked line has already relieved stock and must clear delivery cost,
-- not prove that the same stock is still on hand. Keep every other certified
-- readiness check and exclude only governed delivery sources from availability.
CREATE OR REPLACE FUNCTION public.fn_validate_sales_invoice_accounting_ready_aud053_core(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_company_id UUID;
BEGIN
  SELECT company_id INTO v_company_id FROM sales_invoices WHERE id=p_invoice_id;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Sales invoice not found'; END IF;
  IF NOT EXISTS(SELECT 1 FROM sales_invoice_lines WHERE sales_invoice_id=p_invoice_id AND NULLIF(trim(description),'') IS NOT NULL) THEN
    RAISE EXCEPTION 'Sales invoice must have at least one line before approval or posting.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoice_lines WHERE sales_invoice_id=p_invoice_id AND NULLIF(trim(description),'') IS NOT NULL AND revenue_account_id IS NULL) THEN
    RAISE EXCEPTION 'Every sales invoice line must have a revenue account before approval or posting.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoice_lines sil LEFT JOIN chart_of_accounts coa
      ON coa.id=sil.revenue_account_id AND coa.company_id=v_company_id AND coa.is_active AND coa.is_postable
    WHERE sil.sales_invoice_id=p_invoice_id AND NULLIF(trim(sil.description),'') IS NOT NULL AND coa.id IS NULL) THEN
    RAISE EXCEPTION 'Every sales invoice revenue account must be active, postable, and belong to the invoice company.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoice_lines WHERE sales_invoice_id=p_invoice_id AND NULLIF(trim(description),'') IS NOT NULL AND vat_code_id IS NULL) THEN
    RAISE EXCEPTION 'Every sales invoice line must have a VAT code before approval or posting.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoice_lines sil LEFT JOIN vat_codes vc
      ON vc.id=sil.vat_code_id AND vc.is_active AND vc.transaction_type='output_vat'
    WHERE sil.sales_invoice_id=p_invoice_id AND NULLIF(trim(sil.description),'') IS NOT NULL AND vc.id IS NULL) THEN
    RAISE EXCEPTION 'Every sales invoice VAT code must be active and valid for output VAT.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoices si LEFT JOIN departments d
      ON d.id=si.department_id AND d.company_id=si.company_id AND COALESCE(d.is_active,true)
    WHERE si.id=p_invoice_id AND si.department_id IS NOT NULL AND d.id IS NULL) THEN
    RAISE EXCEPTION 'Sales invoice department must be active and belong to the invoice company.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoices si LEFT JOIN cost_centers cc
      ON cc.id=si.cost_center_id AND cc.company_id=si.company_id AND COALESCE(cc.is_active,true)
    WHERE si.id=p_invoice_id AND si.cost_center_id IS NOT NULL AND cc.id IS NULL) THEN
    RAISE EXCEPTION 'Sales invoice cost center must be active and belong to the invoice company.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoice_lines sil JOIN items i ON i.id=sil.item_id
    WHERE sil.sales_invoice_id=p_invoice_id AND i.item_type='inventory_item' AND sil.warehouse_id IS NULL) THEN
    RAISE EXCEPTION 'Every inventory item sales invoice line must have a warehouse before approval or posting.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoice_lines sil JOIN items i ON i.id=sil.item_id
    LEFT JOIN warehouses w ON w.id=sil.warehouse_id AND w.company_id=v_company_id AND w.is_active
    WHERE sil.sales_invoice_id=p_invoice_id AND i.item_type='inventory_item' AND w.id IS NULL) THEN
    RAISE EXCEPTION 'Every sales invoice warehouse must be active and belong to the invoice company.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoice_lines sil JOIN items i ON i.id=sil.item_id
    LEFT JOIN chart_of_accounts inv ON inv.id=COALESCE(sil.inventory_account_id,i.inventory_account_id)
      AND inv.company_id=v_company_id AND inv.is_active AND inv.is_postable
    LEFT JOIN chart_of_accounts cogs ON cogs.id=COALESCE(sil.cogs_account_id,i.cogs_account_id)
      AND cogs.company_id=v_company_id AND cogs.is_active AND cogs.is_postable
    WHERE sil.sales_invoice_id=p_invoice_id AND i.item_type='inventory_item' AND (inv.id IS NULL OR cogs.id IS NULL)) THEN
    RAISE EXCEPTION 'Inventory item sales invoice lines require active Inventory and COGS accounts.';
  END IF;
  IF EXISTS(SELECT 1 FROM sales_invoice_lines sil JOIN items i ON i.id=sil.item_id
    LEFT JOIN stock_balances sb ON sb.warehouse_id=sil.warehouse_id AND sb.item_id=sil.item_id
    WHERE sil.sales_invoice_id=p_invoice_id AND i.item_type='inventory_item'
      AND NOT (sil.source_document_type='DR' AND sil.source_line_id IS NOT NULL)
      AND COALESCE(sb.qty_on_hand,0)<sil.quantity) THEN
    RAISE EXCEPTION 'Insufficient stock for one or more Sales Invoice inventory lines.';
  END IF;
END;
$$;

CREATE TABLE public.document_relationships (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id               UUID NOT NULL REFERENCES public.companies(id),
  branch_id                UUID NOT NULL REFERENCES public.branches(id),
  source_document_type     TEXT NOT NULL,
  source_document_id       UUID NOT NULL,
  source_line_id           UUID NOT NULL,
  target_document_type     TEXT NOT NULL,
  target_document_id       UUID NOT NULL,
  target_line_id           UUID NOT NULL,
  relationship_type        TEXT NOT NULL DEFAULT 'conversion',
  source_quantity_snapshot NUMERIC(18,4) NOT NULL CHECK (source_quantity_snapshot > 0),
  converted_quantity       NUMERIC(18,4) NOT NULL CHECK (converted_quantity > 0),
  source_cost_snapshot     NUMERIC(18,2) CHECK (source_cost_snapshot >= 0),
  converted_cost           NUMERIC(18,2) CHECK (converted_cost >= 0),
  status                   TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','reversed')),
  reversed_at              TIMESTAMPTZ,
  reversed_by              UUID,
  reversal_reason          TEXT,
  created_by               UUID,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT document_relationships_route_check CHECK (
    (source_document_type = 'sales_quotation' AND target_document_type = 'sales_order') OR
    (source_document_type = 'sales_order' AND target_document_type IN ('delivery_receipt','sales_invoice')) OR
    (source_document_type = 'delivery_receipt' AND target_document_type = 'sales_invoice')
  ),
  CONSTRAINT document_relationships_distinct_documents_check
    CHECK (source_document_id <> target_document_id),
  CONSTRAINT document_relationships_cost_shape_check CHECK (
    (source_document_type='delivery_receipt' AND target_document_type='sales_invoice'
      AND source_cost_snapshot IS NOT NULL AND converted_cost IS NOT NULL)
    OR
    (NOT (source_document_type='delivery_receipt' AND target_document_type='sales_invoice')
      AND source_cost_snapshot IS NULL AND converted_cost IS NULL)
  ),
  UNIQUE (target_document_type, target_line_id)
);

CREATE INDEX idx_document_relationships_source
  ON public.document_relationships
  (source_document_type, source_document_id, source_line_id, status);
CREATE INDEX idx_document_relationships_target
  ON public.document_relationships
  (target_document_type, target_document_id, target_line_id, status);
CREATE INDEX idx_document_relationships_company
  ON public.document_relationships (company_id, created_at DESC);

COMMENT ON TABLE public.document_relationships IS
  'Authoritative line-level conversion lineage. Active includes draft targets and therefore reserves quantity; reversed reopens it.';
COMMENT ON COLUMN public.document_relationships.source_quantity_snapshot IS
  'Original source quantity captured while the source line is locked.';
COMMENT ON COLUMN public.document_relationships.converted_cost IS
  'Exact immutable share of an already-relieved Delivery Receipt line cost assigned to this invoice line; the final quantity receives any rounding residual.';

CREATE TRIGGER trg_document_relationships_updated_at
  BEFORE UPDATE ON public.document_relationships
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();
CREATE TRIGGER trg_document_relationships_audit
  AFTER INSERT OR UPDATE OR DELETE ON public.document_relationships
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

ALTER TABLE public.document_relationships ENABLE ROW LEVEL SECURITY;
CREATE POLICY document_relationships_read ON public.document_relationships
  FOR SELECT TO authenticated
  USING (public.fn_can_access_company_branch(company_id, branch_id));

REVOKE ALL ON TABLE public.document_relationships FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.document_relationships TO authenticated, service_role;

-- The conversion RPC is the only browser path allowed to create a source-linked
-- invoice line. Privileged demo reset and the explicit internal-write context
-- remain available for deterministic fixtures; integrations use conversion.
CREATE OR REPLACE FUNCTION public.fn_guard_sales_invoice_source_authority()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(current_setting('pxl.document_conversion_write', true), '') <> 'on'
     AND NOT public.fn_demo_reset_bypass_authorized()
     AND NULLIF(NEW.source_document_type, '') IS NOT NULL
     AND (TG_OP = 'INSERT'
       OR NEW.source_document_type IS DISTINCT FROM OLD.source_document_type
       OR NEW.source_line_id IS DISTINCT FROM OLD.source_line_id) THEN
    RAISE EXCEPTION 'Source-linked Sales Invoice lines must be created by fn_convert_sales_document';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sales_invoice_source_authority ON public.sales_invoice_lines;
CREATE TRIGGER trg_sales_invoice_source_authority
  BEFORE INSERT OR UPDATE OF source_document_type, source_line_id
  ON public.sales_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_sales_invoice_source_authority();

-- Converted commercial lines are immutable on both sides of an active lineage.
-- Operational cost stamps written by the certified SI posting path remain valid.
CREATE OR REPLACE FUNCTION public.fn_guard_converted_sales_line()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row JSONB := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_old JSONB := CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END;
  v_doc_type TEXT;
  v_line_id UUID := (v_row->>'id')::UUID;
  v_linked BOOLEAN;
BEGIN
  IF COALESCE(current_setting('pxl.document_conversion_write', true), '') = 'on'
     OR public.fn_demo_reset_bypass_authorized() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  v_doc_type := CASE TG_TABLE_NAME
    WHEN 'sales_quotation_lines' THEN 'sales_quotation'
    WHEN 'sales_order_lines' THEN 'sales_order'
    WHEN 'delivery_receipt_lines' THEN 'delivery_receipt'
    WHEN 'sales_invoice_lines' THEN 'sales_invoice'
  END;

  SELECT EXISTS (
    SELECT 1 FROM public.document_relationships r
    WHERE (r.source_document_type = v_doc_type AND r.source_line_id = v_line_id AND r.status = 'active')
       OR (r.target_document_type = v_doc_type AND r.target_line_id = v_line_id)
  ) INTO v_linked;

  IF NOT v_linked THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_TABLE_NAME = 'sales_invoice_lines'
     AND TG_OP = 'UPDATE'
     AND COALESCE(current_setting('pxl.sales_invoice_posting_internal', true), '') = 'on'
     AND (v_old - ARRAY['unit_cost','inventory_cost','inventory_transaction_id','updated_at','updated_by'])
       = (to_jsonb(NEW) - ARRAY['unit_cost','inventory_cost','inventory_transaction_id','updated_at','updated_by']) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION '% line % participates in governed document conversion and cannot be changed directly',
    v_doc_type, v_line_id;
END;
$$;

CREATE TRIGGER trg_conversion_guard_quotation_lines
  BEFORE UPDATE OR DELETE ON public.sales_quotation_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_converted_sales_line();
CREATE TRIGGER trg_conversion_guard_order_lines
  BEFORE UPDATE OR DELETE ON public.sales_order_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_converted_sales_line();
CREATE TRIGGER trg_conversion_guard_delivery_lines
  BEFORE UPDATE OR DELETE ON public.delivery_receipt_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_converted_sales_line();
CREATE TRIGGER trg_conversion_guard_invoice_lines
  BEFORE UPDATE OR DELETE ON public.sales_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_converted_sales_line();

-- Converted headers cannot be rewritten through permissive legacy draft RLS.
-- Normal SI approval/post/void lifecycle stamps are deliberately still allowed.
CREATE OR REPLACE FUNCTION public.fn_guard_converted_sales_header()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT;
  v_linked BOOLEAN;
  v_allowed TEXT[];
  v_changed TEXT[];
BEGIN
  IF COALESCE(current_setting('pxl.document_conversion_write', true), '') = 'on'
     OR public.fn_demo_reset_bypass_authorized() THEN
    RETURN NEW;
  END IF;
  v_type := CASE TG_TABLE_NAME
    WHEN 'sales_orders' THEN 'sales_order'
    WHEN 'delivery_receipts' THEN 'delivery_receipt'
    WHEN 'sales_invoices' THEN 'sales_invoice'
  END;
  SELECT EXISTS (SELECT 1 FROM public.document_relationships
    WHERE target_document_type = v_type AND target_document_id = OLD.id)
  INTO v_linked;
  IF NOT v_linked THEN RETURN NEW; END IF;

  v_allowed := CASE v_type
    WHEN 'sales_order' THEN ARRAY['approval_status','fulfillment_status','approved_by','approved_at','updated_by','updated_at']
    WHEN 'sales_invoice' THEN ARRAY['status','approved_by','approved_at','posted_by','posted_at','journal_entry_id','void_reason_id','updated_by','updated_at']
    ELSE ARRAY['updated_by','updated_at']
  END;
  v_changed := ARRAY(
    SELECT key FROM jsonb_object_keys(to_jsonb(OLD)) key
    WHERE to_jsonb(OLD)->key IS DISTINCT FROM to_jsonb(NEW)->key
      AND key <> ALL(v_allowed)
  );
  IF array_length(v_changed, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'Converted % % commercial fields are immutable; use the governed lifecycle RPC', v_type, OLD.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_conversion_guard_order_header
  BEFORE UPDATE ON public.sales_orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_converted_sales_header();
CREATE TRIGGER trg_conversion_guard_delivery_header
  BEFORE UPDATE ON public.delivery_receipts
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_converted_sales_header();
CREATE TRIGGER trg_conversion_guard_invoice_header
  BEFORE UPDATE ON public.sales_invoices
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_converted_sales_header();

-- Approved Sales Orders remain commercially frozen, but the conversion engine
-- must be able to maintain its server-derived reservation projection. Browser
-- RLS still denies line UPDATE once the parent is no longer pending.
DROP TRIGGER IF EXISTS trg_guard_lines_sales_order_lines ON public.sales_order_lines;
CREATE TRIGGER trg_guard_lines_sales_order_lines
  BEFORE INSERT OR UPDATE OR DELETE ON public.sales_order_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_doc_lines(
    'sales_orders','sales_order_id','approval_status','pending','same_txn',
    'fulfilled_quantity,updated_at,updated_by');

CREATE OR REPLACE FUNCTION public.fn_refresh_sales_order_conversion(p_sales_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total NUMERIC;
  v_reserved NUMERIC;
BEGIN
  SELECT COALESCE(sum(quantity),0) INTO v_total
  FROM public.sales_order_lines WHERE sales_order_id = p_sales_order_id;

  SELECT COALESCE(sum(r.converted_quantity),0) INTO v_reserved
  FROM public.document_relationships r
  JOIN public.sales_order_lines sol ON sol.id = r.source_line_id
  WHERE sol.sales_order_id = p_sales_order_id
    AND r.source_document_type = 'sales_order' AND r.status = 'active';

  PERFORM set_config('pxl.document_conversion_write', 'on', true);
  UPDATE public.sales_order_lines sol
  SET fulfilled_quantity = COALESCE((
    SELECT sum(r.converted_quantity)
    FROM public.document_relationships r
    WHERE r.source_document_type = 'sales_order'
      AND r.source_line_id = sol.id AND r.status = 'active'
  ),0), updated_at = now(), updated_by = auth.uid()
  WHERE sol.sales_order_id = p_sales_order_id;

  UPDATE public.sales_orders
  SET fulfillment_status = CASE
      WHEN v_reserved <= 0 THEN 'open'
      WHEN v_reserved + 0.0001 >= v_total THEN 'fulfilled'
      ELSE 'partial'
    END,
    updated_at = now(), updated_by = auth.uid()
  WHERE id = p_sales_order_id AND fulfillment_status <> 'cancelled';
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_reverse_document_relationships(
  p_target_document_type TEXT,
  p_target_document_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_so_id UUID;
BEGIN
  FOR v_so_id IN
    SELECT DISTINCT sol.sales_order_id
    FROM public.document_relationships r
    JOIN public.sales_order_lines sol ON sol.id = r.source_line_id
    WHERE r.target_document_type = p_target_document_type
      AND r.target_document_id = p_target_document_id
      AND r.source_document_type = 'sales_order' AND r.status = 'active'
  LOOP
    UPDATE public.document_relationships
    SET status='reversed', reversed_at=now(), reversed_by=auth.uid(), reversal_reason=p_reason
    WHERE target_document_type=p_target_document_type
      AND target_document_id=p_target_document_id AND status='active';
    PERFORM public.fn_refresh_sales_order_conversion(v_so_id);
  END LOOP;

  UPDATE public.document_relationships
  SET status='reversed', reversed_at=now(), reversed_by=auth.uid(), reversal_reason=p_reason
  WHERE target_document_type=p_target_document_type
    AND target_document_id=p_target_document_id AND status='active';
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_sync_sales_conversion_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old JSONB := to_jsonb(OLD);
  v_new JSONB := to_jsonb(NEW);
BEGIN
  IF TG_TABLE_NAME = 'sales_orders'
     AND ((v_new->>'approval_status' = 'rejected' AND v_old->>'approval_status' <> 'rejected')
       OR (v_new->>'fulfillment_status' = 'cancelled' AND v_old->>'fulfillment_status' <> 'cancelled')) THEN
    PERFORM public.fn_reverse_document_relationships('sales_order', NEW.id,
      CASE WHEN v_new->>'approval_status'='rejected' THEN 'Sales Order rejected' ELSE 'Sales Order cancelled' END);
  ELSIF TG_TABLE_NAME = 'delivery_receipts'
     AND v_new->>'status' = 'cancelled' AND v_old->>'status' <> 'cancelled' THEN
    PERFORM public.fn_reverse_document_relationships('delivery_receipt', NEW.id, 'Delivery Receipt cancelled');
  ELSIF TG_TABLE_NAME = 'sales_invoices'
     AND v_new->>'status' = 'cancelled' AND v_old->>'status' <> 'cancelled' THEN
    PERFORM public.fn_reverse_document_relationships('sales_invoice', NEW.id, 'Sales Invoice voided');
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_conversion_lifecycle_sales_order
  AFTER UPDATE OF approval_status, fulfillment_status ON public.sales_orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_sync_sales_conversion_lifecycle();
CREATE TRIGGER trg_conversion_lifecycle_delivery_receipt
  AFTER UPDATE OF status ON public.delivery_receipts
  FOR EACH ROW EXECUTE FUNCTION public.fn_sync_sales_conversion_lifecycle();
CREATE TRIGGER trg_conversion_lifecycle_sales_invoice
  AFTER UPDATE OF status ON public.sales_invoices
  FOR EACH ROW EXECUTE FUNCTION public.fn_sync_sales_conversion_lifecycle();

CREATE OR REPLACE VIEW public.vw_sales_document_conversion_progress
WITH (security_invoker = true)
AS
SELECT q.company_id, q.branch_id,
  'sales_quotation'::TEXT source_document_type, q.id source_document_id,
  q.quotation_number source_document_number, q.status source_status,
  ql.id source_line_id, ql.line_number, ql.item_id, ql.description,
  'sales_order'::TEXT target_document_type,
  ql.quantity original_quantity,
  COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active'),0)::NUMERIC(18,4) converted_quantity,
  COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active' AND so.approval_status='approved'),0)::NUMERIC(18,4) completed_quantity,
  GREATEST(ql.quantity-COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active'),0),0)::NUMERIC(18,4) remaining_quantity
FROM public.sales_quotations q
JOIN public.sales_quotation_lines ql ON ql.quotation_id=q.id
LEFT JOIN public.document_relationships r ON r.source_document_type='sales_quotation' AND r.source_line_id=ql.id
LEFT JOIN public.sales_orders so ON so.id=r.target_document_id AND r.target_document_type='sales_order'
GROUP BY q.company_id,q.branch_id,q.id,q.quotation_number,q.status,ql.id
UNION ALL
SELECT so.company_id,so.branch_id,'sales_order',so.id,so.so_number,
  so.approval_status||'/'||so.fulfillment_status,sol.id,sol.line_number,sol.item_id,sol.description,
  'delivery_receipt_or_sales_invoice',sol.quantity,
  COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active'),0)::NUMERIC(18,4),
  COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active' AND
    ((r.target_document_type='delivery_receipt' AND dr.status='delivered') OR
     (r.target_document_type='sales_invoice' AND si.status IN ('approved','posted')))),0)::NUMERIC(18,4),
  GREATEST(sol.quantity-COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active'),0),0)::NUMERIC(18,4)
FROM public.sales_orders so
JOIN public.sales_order_lines sol ON sol.sales_order_id=so.id
LEFT JOIN public.document_relationships r ON r.source_document_type='sales_order' AND r.source_line_id=sol.id
LEFT JOIN public.delivery_receipts dr ON dr.id=r.target_document_id AND r.target_document_type='delivery_receipt'
LEFT JOIN public.sales_invoices si ON si.id=r.target_document_id AND r.target_document_type='sales_invoice'
GROUP BY so.company_id,so.branch_id,so.id,so.so_number,so.approval_status,so.fulfillment_status,sol.id
UNION ALL
SELECT dr.company_id,dr.branch_id,'delivery_receipt',dr.id,dr.dr_number,dr.status,
  drl.id,drl.line_number,drl.item_id,drl.description,'sales_invoice',drl.quantity,
  COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active'),0)::NUMERIC(18,4),
  COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active' AND si.status IN ('approved','posted')),0)::NUMERIC(18,4),
  GREATEST(drl.quantity-COALESCE(sum(r.converted_quantity) FILTER (WHERE r.status='active'),0),0)::NUMERIC(18,4)
FROM public.delivery_receipts dr
JOIN public.delivery_receipt_lines drl ON drl.dr_id=dr.id
LEFT JOIN public.document_relationships r ON r.source_document_type='delivery_receipt' AND r.source_line_id=drl.id
LEFT JOIN public.sales_invoices si ON si.id=r.target_document_id AND r.target_document_type='sales_invoice'
GROUP BY dr.company_id,dr.branch_id,dr.id,dr.dr_number,dr.status,drl.id;

CREATE OR REPLACE VIEW public.vw_sales_document_trace
WITH (security_invoker = true)
AS
SELECT r.company_id,r.branch_id,r.id relationship_id,r.relationship_type,r.status relationship_status,
  r.source_document_type,r.source_document_id,r.source_line_id,
  CASE r.source_document_type WHEN 'sales_quotation' THEN q.quotation_number WHEN 'sales_order' THEN so.so_number WHEN 'delivery_receipt' THEN dr.dr_number END source_document_number,
  CASE r.source_document_type WHEN 'sales_quotation' THEN q.status WHEN 'sales_order' THEN so.approval_status||'/'||so.fulfillment_status WHEN 'delivery_receipt' THEN dr.status END source_status,
  r.target_document_type,r.target_document_id,r.target_line_id,
  CASE r.target_document_type WHEN 'sales_order' THEN tso.so_number WHEN 'delivery_receipt' THEN tdr.dr_number WHEN 'sales_invoice' THEN si.si_number END target_document_number,
  CASE r.target_document_type WHEN 'sales_order' THEN tso.approval_status||'/'||tso.fulfillment_status WHEN 'delivery_receipt' THEN tdr.status WHEN 'sales_invoice' THEN si.status END target_status,
  r.converted_quantity quantity,r.converted_cost amount,r.created_at,r.reversed_at,r.reversal_reason
FROM public.document_relationships r
LEFT JOIN public.sales_quotations q ON r.source_document_type='sales_quotation' AND q.id=r.source_document_id
LEFT JOIN public.sales_orders so ON r.source_document_type='sales_order' AND so.id=r.source_document_id
LEFT JOIN public.delivery_receipts dr ON r.source_document_type='delivery_receipt' AND dr.id=r.source_document_id
LEFT JOIN public.sales_orders tso ON r.target_document_type='sales_order' AND tso.id=r.target_document_id
LEFT JOIN public.delivery_receipts tdr ON r.target_document_type='delivery_receipt' AND tdr.id=r.target_document_id
LEFT JOIN public.sales_invoices si ON r.target_document_type='sales_invoice' AND si.id=r.target_document_id
UNION ALL
SELECT r.company_id,r.branch_id,rl.id,'settlement',
  CASE WHEN r.status='cancelled' THEN 'reversed' ELSE 'active' END,
  'sales_invoice',si.id,NULL,si.si_number,si.status,
  'official_receipt',r.id,rl.id,r.receipt_number,r.status,
  NULL::NUMERIC,rl.payment_amount,r.created_at,
  CASE WHEN r.status='cancelled' THEN r.updated_at END,
  CASE WHEN r.status='cancelled' THEN 'Official Receipt voided' END
FROM public.receipt_lines rl
JOIN public.receipts r ON r.id=rl.receipt_id
JOIN public.sales_invoices si ON si.id=rl.invoice_id;

GRANT SELECT ON public.vw_sales_document_conversion_progress TO authenticated, service_role;
GRANT SELECT ON public.vw_sales_document_trace TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_resolve_sales_invoice_delivered_cost(
  p_sales_invoice_line_id UUID
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT r.converted_cost
      FROM public.document_relationships r
      WHERE r.target_document_type='sales_invoice'
        AND r.target_line_id=sil.id
        AND r.status='active'
    ),
    ROUND(COALESCE(drl.inventory_cost,0)
      * (sil.quantity/NULLIF(drl.quantity,0)),2)
  )
  FROM public.sales_invoice_lines sil
  JOIN public.delivery_receipt_lines drl ON drl.id=sil.source_line_id
  WHERE sil.id=p_sales_invoice_line_id
    AND sil.source_document_type='DR'
$$;

REVOKE ALL ON FUNCTION public.fn_resolve_sales_invoice_delivered_cost(UUID)
  FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION public.fn_resolve_sales_invoice_delivered_cost(UUID) IS
  'Private bridge from immutable conversion cost allocation to Sales Invoice posting. Legacy full-line source links fall back to proportional historical delivery cost.';

-- The certified posting body has accumulated later tax and costing packages, so
-- do not restate a stale copy. Replace its one inspected Delivery Receipt cost
-- read with the private relationship-cost resolver and fail the migration if
-- that exact live seam is no longer singular.
DO $partial_billing_cost$
DECLARE
  v_definition TEXT;
  v_needle CONSTANT TEXT := '(SELECT drl.inventory_cost';
  v_replacement CONSTANT TEXT :=
    '(SELECT public.fn_resolve_sales_invoice_delivered_cost(sil.id)';
  v_occurrences INTEGER;
BEGIN
  SELECT pg_get_functiondef(
    'public.fn_post_sales_invoice_costing_legacy_20260808(uuid)'::regprocedure
  ) INTO v_definition;
  v_occurrences := (length(v_definition)-length(replace(v_definition,v_needle,'')))
    / length(v_needle);
  IF v_occurrences <> 1 THEN
    RAISE EXCEPTION 'Expected one delivered-cost read in the current Sales Invoice posting body; found %',
      v_occurrences;
  END IF;
  EXECUTE replace(v_definition,v_needle,v_replacement);
END;
$partial_billing_cost$;

CREATE OR REPLACE FUNCTION public.fn_convert_sales_document(
  p_source_document_type TEXT,
  p_source_document_id UUID,
  p_target_document_type TEXT,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q public.sales_quotations%ROWTYPE;
  v_ql public.sales_quotation_lines%ROWTYPE;
  v_so public.sales_orders%ROWTYPE;
  v_sol public.sales_order_lines%ROWTYPE;
  v_dr public.delivery_receipts%ROWTYPE;
  v_drl public.delivery_receipt_lines%ROWTYPE;
  v_item public.items%ROWTYPE;
  v_customer public.customers%ROWTYPE;
  v_line JSONB;
  v_qty NUMERIC(18,4);
  v_reserved NUMERIC(18,4);
  v_existing_cost NUMERIC(18,2);
  v_converted_cost NUMERIC(18,2);
  v_discount NUMERIC(18,2);
  v_target_id UUID;
  v_target_line_id UUID;
  v_number TEXT;
  v_invoice_lines JSONB := '[]'::JSONB;
  v_line_no INTEGER := 0;
  v_total NUMERIC(18,2) := 0;
BEGIN
  p_source_document_type := lower(btrim(p_source_document_type));
  p_target_document_type := lower(btrim(p_target_document_type));
  IF jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines)=0 THEN
    RAISE EXCEPTION 'At least one source line and quantity are required';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) a
    GROUP BY a->>'source_line_id' HAVING count(*)>1) THEN
    RAISE EXCEPTION 'A source line may appear only once in a conversion request';
  END IF;
  IF (p_source_document_type,p_target_document_type) NOT IN (
    ('sales_quotation','sales_order'),('sales_order','delivery_receipt'),
    ('sales_order','sales_invoice'),('delivery_receipt','sales_invoice')) THEN
    RAISE EXCEPTION 'Unsupported sales document conversion: % -> %', p_source_document_type,p_target_document_type;
  END IF;

  PERFORM set_config('pxl.document_conversion_write','on',true);

  IF p_source_document_type='sales_quotation' THEN
    SELECT * INTO v_q FROM public.sales_quotations WHERE id=p_source_document_id FOR UPDATE;
    IF NOT FOUND OR NOT public.fn_can_access_company_branch(v_q.company_id,v_q.branch_id) THEN
      RAISE EXCEPTION 'Sales Quotation not found or access denied';
    END IF;
    IF v_q.status <> 'approved' OR v_q.validity_date < current_date THEN
      RAISE EXCEPTION 'Only a current approved Sales Quotation can be converted';
    END IF;
    v_number := public.fn_next_document_number(v_q.company_id,v_q.branch_id,'SO');
    INSERT INTO public.sales_orders(company_id,branch_id,quotation_id,customer_id,
      customer_name_snapshot,customer_tin_snapshot,so_number,so_date,expected_delivery_date,
      currency_code,reference_number,remarks,total_amount,approval_status,fulfillment_status,
      created_by,updated_by)
    VALUES(v_q.company_id,v_q.branch_id,v_q.id,v_q.customer_id,v_q.customer_name_snapshot,
      v_q.customer_tin_snapshot,v_number,COALESCE((p_header->>'date')::date,current_date),
      NULLIF(p_header->>'expected_delivery_date','')::date,v_q.currency_code,
      COALESCE(NULLIF(p_header->>'reference_number',''),v_q.quotation_number),
      NULLIF(p_header->>'remarks',''),0,'pending','open',auth.uid(),auth.uid()) RETURNING id INTO v_target_id;

    FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
      v_qty := NULLIF(v_line->>'quantity','')::numeric;
      SELECT * INTO v_ql FROM public.sales_quotation_lines
      WHERE id=NULLIF(v_line->>'source_line_id','')::uuid AND quotation_id=v_q.id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Quotation source line is invalid'; END IF;
      SELECT COALESCE(sum(converted_quantity),0) INTO v_reserved FROM public.document_relationships
       WHERE source_document_type='sales_quotation' AND source_line_id=v_ql.id AND status='active';
      IF v_qty IS NULL OR v_qty<=0 OR v_qty>v_ql.quantity-v_reserved+0.00001 THEN
        RAISE EXCEPTION 'Quotation line % has % remaining; requested %',v_ql.line_number,v_ql.quantity-v_reserved,v_qty;
      END IF;
      v_line_no:=v_line_no+1;
      v_discount:=round(v_ql.discount_amount*(v_qty/v_ql.quantity),2);
      INSERT INTO public.sales_order_lines(sales_order_id,company_id,quotation_line_id,item_id,
        description,quantity,fulfilled_quantity,uom_id,unit_price,discount_amount,net_amount,line_number,
        created_by,updated_by)
      VALUES(v_target_id,v_q.company_id,v_ql.id,v_ql.item_id,v_ql.description,v_qty,0,v_ql.uom_id,
        v_ql.unit_price,v_discount,round(v_qty*v_ql.unit_price-v_discount,2),v_line_no,auth.uid(),auth.uid())
      RETURNING id,net_amount INTO v_target_line_id,v_discount;
      v_total:=v_total+v_discount;
      INSERT INTO public.document_relationships(company_id,branch_id,source_document_type,
        source_document_id,source_line_id,target_document_type,target_document_id,target_line_id,
        source_quantity_snapshot,converted_quantity,created_by)
      VALUES(v_q.company_id,v_q.branch_id,'sales_quotation',v_q.id,v_ql.id,'sales_order',
        v_target_id,v_target_line_id,v_ql.quantity,v_qty,auth.uid());
    END LOOP;
    UPDATE public.sales_orders SET total_amount=v_total WHERE id=v_target_id;

  ELSIF p_source_document_type='sales_order' AND p_target_document_type='delivery_receipt' THEN
    SELECT * INTO v_so FROM public.sales_orders WHERE id=p_source_document_id FOR UPDATE;
    IF NOT FOUND OR NOT public.fn_can_access_company_branch(v_so.company_id,v_so.branch_id) THEN
      RAISE EXCEPTION 'Sales Order not found or access denied';
    END IF;
    IF v_so.approval_status<>'approved' OR v_so.fulfillment_status='cancelled' THEN
      RAISE EXCEPTION 'Only an approved, active Sales Order can be delivered';
    END IF;
    SELECT * INTO v_customer FROM public.customers WHERE id=v_so.customer_id;
    v_number:=public.fn_next_document_number(v_so.company_id,v_so.branch_id,'DR');
    INSERT INTO public.delivery_receipts(company_id,branch_id,sales_order_id,customer_id,
      customer_name_snapshot,dr_number,dr_date,shipping_method,tracking_number,driver_name,
      delivery_address,status,created_by,updated_by)
    VALUES(v_so.company_id,v_so.branch_id,v_so.id,v_so.customer_id,v_so.customer_name_snapshot,
      v_number,COALESCE((p_header->>'date')::date,current_date),
      COALESCE(NULLIF(p_header->>'shipping_method',''),'in_house'),NULLIF(p_header->>'tracking_number',''),
      NULLIF(p_header->>'driver_name',''),COALESCE(NULLIF(p_header->>'delivery_address',''),v_customer.delivery_address,v_customer.registered_address,''),
      'draft',auth.uid(),auth.uid()) RETURNING id INTO v_target_id;
    FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
      v_qty:=NULLIF(v_line->>'quantity','')::numeric;
      SELECT * INTO v_sol FROM public.sales_order_lines
       WHERE id=NULLIF(v_line->>'source_line_id','')::uuid AND sales_order_id=v_so.id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Sales Order source line is invalid'; END IF;
      SELECT COALESCE(sum(converted_quantity),0) INTO v_reserved FROM public.document_relationships
       WHERE source_document_type='sales_order' AND source_line_id=v_sol.id AND status='active';
      IF v_qty IS NULL OR v_qty<=0 OR v_qty>v_sol.quantity-v_reserved+0.00001 THEN
        RAISE EXCEPTION 'Sales Order line % has % remaining; requested %',v_sol.line_number,v_sol.quantity-v_reserved,v_qty;
      END IF;
      v_line_no:=v_line_no+1;
      INSERT INTO public.delivery_receipt_lines(dr_id,company_id,so_line_id,item_id,description,
        quantity,uom_id,line_number,warehouse_id,inventory_cost_layer_id,lot_number,serial_number,created_by,updated_by)
      VALUES(v_target_id,v_so.company_id,v_sol.id,v_sol.item_id,v_sol.description,v_qty,v_sol.uom_id,v_line_no,
        NULLIF(v_line->>'warehouse_id','')::uuid,NULLIF(v_line->>'inventory_cost_layer_id','')::uuid,
        NULLIF(btrim(v_line->>'lot_number'),''),NULLIF(btrim(v_line->>'serial_number'),''),auth.uid(),auth.uid())
      RETURNING id INTO v_target_line_id;
      INSERT INTO public.document_relationships(company_id,branch_id,source_document_type,
        source_document_id,source_line_id,target_document_type,target_document_id,target_line_id,
        source_quantity_snapshot,converted_quantity,created_by)
      VALUES(v_so.company_id,v_so.branch_id,'sales_order',v_so.id,v_sol.id,'delivery_receipt',
        v_target_id,v_target_line_id,v_sol.quantity,v_qty,auth.uid());
    END LOOP;
    PERFORM public.fn_refresh_sales_order_conversion(v_so.id);

  ELSE
    IF p_source_document_type='delivery_receipt' THEN
      SELECT * INTO v_dr FROM public.delivery_receipts WHERE id=p_source_document_id FOR UPDATE;
      IF NOT FOUND OR NOT public.fn_can_access_company_branch(v_dr.company_id,v_dr.branch_id) THEN
        RAISE EXCEPTION 'Delivery Receipt not found or access denied';
      END IF;
      IF v_dr.status<>'delivered' THEN RAISE EXCEPTION 'Only a delivered Delivery Receipt can be invoiced'; END IF;
      SELECT * INTO v_customer FROM public.customers WHERE id=v_dr.customer_id;
      FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
        v_qty:=NULLIF(v_line->>'quantity','')::numeric;
        SELECT * INTO v_drl FROM public.delivery_receipt_lines
         WHERE id=NULLIF(v_line->>'source_line_id','')::uuid AND dr_id=v_dr.id FOR UPDATE;
        IF NOT FOUND OR v_drl.so_line_id IS NULL THEN RAISE EXCEPTION 'Delivery source line is invalid or has no Sales Order price authority'; END IF;
        SELECT COALESCE(sum(converted_quantity),0) INTO v_reserved FROM public.document_relationships
         WHERE source_document_type='delivery_receipt' AND source_line_id=v_drl.id AND status='active';
        IF v_qty IS NULL OR v_qty<=0 OR v_qty>v_drl.quantity-v_reserved+0.00001 THEN
          RAISE EXCEPTION 'Delivery line % has % remaining; requested %',v_drl.line_number,v_drl.quantity-v_reserved,v_qty;
        END IF;
        SELECT * INTO v_sol FROM public.sales_order_lines WHERE id=v_drl.so_line_id;
        SELECT * INTO v_item FROM public.items WHERE id=v_drl.item_id;
        IF v_item.id IS NULL OR v_item.default_sales_vat_id IS NULL OR v_item.sales_account_id IS NULL THEN
          RAISE EXCEPTION 'Delivery line % item lacks Sales Invoice tax or revenue configuration',v_drl.line_number;
        END IF;
        v_line_no:=v_line_no+1;
        v_invoice_lines:=v_invoice_lines||jsonb_build_array(jsonb_build_object(
          'item_id',v_drl.item_id,'description',v_drl.description,'quantity',v_qty,'uom_id',v_drl.uom_id,
          'unit_price',v_sol.unit_price,'discount_amount',round(v_sol.discount_amount*(v_qty/v_sol.quantity),2),
          'vat_code_id',v_item.default_sales_vat_id,'revenue_account_id',v_item.sales_account_id,
          'warehouse_id',v_drl.warehouse_id,'source_document_type','DR','source_line_id',v_drl.id));
      END LOOP;
      v_target_id:=public.fn_save_sales_invoice(NULL,jsonb_build_object(
        'company_id',v_dr.company_id,'branch_id',v_dr.branch_id,'customer_id',v_dr.customer_id,
        'customer_name_snapshot',v_dr.customer_name_snapshot,'customer_tin_snapshot',v_customer.tin,
        'customer_address_snapshot',v_dr.delivery_address,'date',COALESCE((p_header->>'date')::date,current_date),
        'currency_code','PHP','reference',v_dr.dr_number,'memo',COALESCE(NULLIF(p_header->>'memo',''),'Billing of Delivery Receipt '||v_dr.dr_number)),v_invoice_lines);
      v_line_no:=0;
      FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
        v_line_no:=v_line_no+1; v_qty:=(v_line->>'quantity')::numeric;
        SELECT * INTO v_drl FROM public.delivery_receipt_lines WHERE id=(v_line->>'source_line_id')::uuid;
        SELECT id INTO v_target_line_id FROM public.sales_invoice_lines WHERE sales_invoice_id=v_target_id AND line_number=v_line_no;
        SELECT COALESCE(sum(converted_quantity),0),COALESCE(sum(converted_cost),0)
          INTO v_reserved,v_existing_cost
        FROM public.document_relationships
        WHERE source_document_type='delivery_receipt' AND source_line_id=v_drl.id
          AND status='active';
        v_converted_cost:=CASE
          WHEN v_qty+v_reserved+0.00001>=v_drl.quantity
            THEN GREATEST(COALESCE(v_drl.inventory_cost,0)-v_existing_cost,0)
          ELSE ROUND(COALESCE(v_drl.inventory_cost,0)*(v_qty/NULLIF(v_drl.quantity,0)),2)
        END;
        INSERT INTO public.document_relationships(company_id,branch_id,source_document_type,source_document_id,
          source_line_id,target_document_type,target_document_id,target_line_id,source_quantity_snapshot,converted_quantity,
          source_cost_snapshot,converted_cost,created_by)
        VALUES(v_dr.company_id,v_dr.branch_id,'delivery_receipt',v_dr.id,v_drl.id,'sales_invoice',v_target_id,
          v_target_line_id,v_drl.quantity,v_qty,COALESCE(v_drl.inventory_cost,0),v_converted_cost,auth.uid());
      END LOOP;
    ELSE
      SELECT * INTO v_so FROM public.sales_orders WHERE id=p_source_document_id FOR UPDATE;
      IF NOT FOUND OR NOT public.fn_can_access_company_branch(v_so.company_id,v_so.branch_id) THEN RAISE EXCEPTION 'Sales Order not found or access denied'; END IF;
      IF v_so.approval_status<>'approved' OR v_so.fulfillment_status='cancelled' THEN RAISE EXCEPTION 'Only an approved, active Sales Order can be invoiced'; END IF;
      SELECT * INTO v_customer FROM public.customers WHERE id=v_so.customer_id;
      FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
        v_qty:=NULLIF(v_line->>'quantity','')::numeric;
        SELECT * INTO v_sol FROM public.sales_order_lines WHERE id=(v_line->>'source_line_id')::uuid AND sales_order_id=v_so.id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Sales Order source line is invalid'; END IF;
        SELECT * INTO v_item FROM public.items WHERE id=v_sol.item_id;
        IF v_item.item_type='inventory_item' THEN RAISE EXCEPTION 'Inventory items must be delivered before invoicing; use Sales Order to Delivery Receipt'; END IF;
        SELECT COALESCE(sum(converted_quantity),0) INTO v_reserved FROM public.document_relationships
         WHERE source_document_type='sales_order' AND source_line_id=v_sol.id AND status='active';
        IF v_qty IS NULL OR v_qty<=0 OR v_qty>v_sol.quantity-v_reserved+0.00001 THEN RAISE EXCEPTION 'Sales Order line % has % remaining; requested %',v_sol.line_number,v_sol.quantity-v_reserved,v_qty; END IF;
        IF v_item.id IS NULL OR v_item.default_sales_vat_id IS NULL OR v_item.sales_account_id IS NULL THEN RAISE EXCEPTION 'Sales Order line % item lacks Sales Invoice tax or revenue configuration',v_sol.line_number; END IF;
        v_line_no:=v_line_no+1;
        v_invoice_lines:=v_invoice_lines||jsonb_build_array(jsonb_build_object(
          'item_id',v_sol.item_id,'description',v_sol.description,'quantity',v_qty,'uom_id',v_sol.uom_id,
          'unit_price',v_sol.unit_price,'discount_amount',round(v_sol.discount_amount*(v_qty/v_sol.quantity),2),
          'vat_code_id',v_item.default_sales_vat_id,'revenue_account_id',v_item.sales_account_id,
          'source_document_type','sales_order','source_line_id',v_sol.id));
      END LOOP;
      v_target_id:=public.fn_save_sales_invoice(NULL,jsonb_build_object(
        'company_id',v_so.company_id,'branch_id',v_so.branch_id,'customer_id',v_so.customer_id,
        'customer_name_snapshot',v_so.customer_name_snapshot,'customer_tin_snapshot',v_so.customer_tin_snapshot,
        'customer_address_snapshot',COALESCE(v_customer.delivery_address,v_customer.registered_address,''),
        'date',COALESCE((p_header->>'date')::date,current_date),'currency_code','PHP','reference',v_so.so_number,
        'memo',COALESCE(NULLIF(p_header->>'memo',''),'Direct service billing of Sales Order '||v_so.so_number)),v_invoice_lines);
      v_line_no:=0;
      FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
        v_line_no:=v_line_no+1;v_qty:=(v_line->>'quantity')::numeric;
        SELECT * INTO v_sol FROM public.sales_order_lines WHERE id=(v_line->>'source_line_id')::uuid;
        SELECT id INTO v_target_line_id FROM public.sales_invoice_lines WHERE sales_invoice_id=v_target_id AND line_number=v_line_no;
        INSERT INTO public.document_relationships(company_id,branch_id,source_document_type,source_document_id,
          source_line_id,target_document_type,target_document_id,target_line_id,source_quantity_snapshot,converted_quantity,created_by)
        VALUES(v_so.company_id,v_so.branch_id,'sales_order',v_so.id,v_sol.id,'sales_invoice',v_target_id,
          v_target_line_id,v_sol.quantity,v_qty,auth.uid());
      END LOOP;
      PERFORM public.fn_refresh_sales_order_conversion(v_so.id);
    END IF;
  END IF;
  RETURN v_target_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_set_converted_sales_order_decision(p_sales_order_id UUID,p_decision TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_so public.sales_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_so FROM public.sales_orders WHERE id=p_sales_order_id FOR UPDATE;
  IF NOT FOUND OR NOT public.fn_can_access_company_branch(v_so.company_id,v_so.branch_id) THEN RAISE EXCEPTION 'Sales Order not found or access denied'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.document_relationships WHERE target_document_type='sales_order' AND target_document_id=v_so.id) THEN RAISE EXCEPTION 'Sales Order is not a converted document'; END IF;
  IF v_so.approval_status<>'pending' OR p_decision NOT IN ('approved','rejected') THEN RAISE EXCEPTION 'Pending Sales Order decision must be approved or rejected'; END IF;
  PERFORM set_config('pxl.document_conversion_write','on',true);
  UPDATE public.sales_orders SET approval_status=p_decision,
    approved_by=CASE WHEN p_decision='approved' THEN auth.uid() ELSE approved_by END,
    approved_at=CASE WHEN p_decision='approved' THEN now() ELSE approved_at END,
    updated_by=auth.uid(),updated_at=now() WHERE id=v_so.id;
END;$$;

CREATE OR REPLACE FUNCTION public.fn_cancel_sales_quotation(p_quotation_id UUID,p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_q public.sales_quotations%ROWTYPE;
BEGIN
  SELECT * INTO v_q FROM public.sales_quotations WHERE id=p_quotation_id FOR UPDATE;
  IF NOT FOUND OR NOT public.fn_can_access_company_branch(v_q.company_id,v_q.branch_id) THEN RAISE EXCEPTION 'Sales Quotation not found or access denied'; END IF;
  IF EXISTS(SELECT 1 FROM public.document_relationships WHERE source_document_type='sales_quotation' AND source_document_id=v_q.id AND status='active') THEN RAISE EXCEPTION 'Sales Quotation has active downstream Sales Orders; cancel or reject them first'; END IF;
  IF NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'A cancellation reason is required'; END IF;
  UPDATE public.sales_quotations SET status='cancelled',remarks=concat_ws(E'\n',remarks,'Cancelled: '||btrim(p_reason)),updated_by=auth.uid(),updated_at=now() WHERE id=v_q.id;
END;$$;

CREATE OR REPLACE FUNCTION public.fn_cancel_sales_order(p_sales_order_id UUID,p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_so public.sales_orders%ROWTYPE;
BEGIN
  SELECT * INTO v_so FROM public.sales_orders WHERE id=p_sales_order_id FOR UPDATE;
  IF NOT FOUND OR NOT public.fn_can_access_company_branch(v_so.company_id,v_so.branch_id) THEN RAISE EXCEPTION 'Sales Order not found or access denied'; END IF;
  IF EXISTS(SELECT 1 FROM public.document_relationships WHERE source_document_type='sales_order' AND source_document_id=v_so.id AND status='active') THEN RAISE EXCEPTION 'Sales Order has active downstream deliveries or invoices; cancel or void them first'; END IF;
  IF NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'A cancellation reason is required'; END IF;
  PERFORM set_config('pxl.document_conversion_write','on',true);
  UPDATE public.sales_orders SET fulfillment_status='cancelled',remarks=concat_ws(E'\n',remarks,'Cancelled: '||btrim(p_reason)),updated_by=auth.uid(),updated_at=now() WHERE id=v_so.id;
END;$$;

CREATE OR REPLACE FUNCTION public.fn_update_converted_delivery_details(p_dr_id UUID,p_header JSONB,p_lines JSONB,p_status TEXT DEFAULT 'draft')
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_dr public.delivery_receipts%ROWTYPE;v_line JSONB;v_line_id UUID;
BEGIN
  SELECT * INTO v_dr FROM public.delivery_receipts WHERE id=p_dr_id FOR UPDATE;
  IF NOT FOUND OR NOT public.fn_can_access_company_branch(v_dr.company_id,v_dr.branch_id) THEN RAISE EXCEPTION 'Delivery Receipt not found or access denied'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.document_relationships WHERE target_document_type='delivery_receipt' AND target_document_id=v_dr.id) THEN RAISE EXCEPTION 'Delivery Receipt is not a converted document'; END IF;
  IF v_dr.status NOT IN ('draft','in_transit') OR p_status NOT IN ('draft','in_transit','delivered') THEN RAISE EXCEPTION 'Converted Delivery Receipt is not editable in status %',v_dr.status; END IF;
  PERFORM set_config('pxl.document_conversion_write','on',true);
  UPDATE public.delivery_receipts SET dr_date=COALESCE(NULLIF(p_header->>'date','')::date,dr_date),
    shipping_method=COALESCE(NULLIF(p_header->>'shipping_method',''),shipping_method),
    tracking_number=COALESCE(NULLIF(p_header->>'tracking_number',''),tracking_number),
    driver_name=COALESCE(NULLIF(p_header->>'driver_name',''),driver_name),
    delivery_address=COALESCE(NULLIF(p_header->>'delivery_address',''),delivery_address),
    status=p_status,delivered_at=CASE WHEN p_status='delivered' THEN now() ELSE delivered_at END,
    updated_by=auth.uid(),updated_at=now() WHERE id=v_dr.id;
  FOR v_line IN SELECT value FROM jsonb_array_elements(COALESCE(p_lines,'[]'::jsonb)) LOOP
    v_line_id:=NULLIF(v_line->>'line_id','')::uuid;
    IF NOT EXISTS(SELECT 1 FROM public.delivery_receipt_lines WHERE id=v_line_id AND dr_id=v_dr.id) THEN RAISE EXCEPTION 'Delivery line does not belong to this document'; END IF;
    UPDATE public.delivery_receipt_lines SET warehouse_id=COALESCE(NULLIF(v_line->>'warehouse_id','')::uuid,warehouse_id),
      inventory_cost_layer_id=NULLIF(v_line->>'inventory_cost_layer_id','')::uuid,
      lot_number=NULLIF(btrim(v_line->>'lot_number'),''),serial_number=NULLIF(btrim(v_line->>'serial_number'),''),
      updated_by=auth.uid(),updated_at=now() WHERE id=v_line_id;
  END LOOP;
  IF p_status='delivered' THEN PERFORM public.fn_post_delivery_receipt(v_dr.id); END IF;
END;$$;

-- The shared Delivery Receipt correction authority remains the only public
-- void path.  Converted targets need the same narrowly scoped internal-write
-- context used by conversion completion so their commercial immutability guard
-- admits the lifecycle stamps and exact inventory restoration performed by the
-- existing costing/correction implementation.
CREATE OR REPLACE FUNCTION public.fn_void_delivery_receipt(
  p_dr_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.document_relationships
    WHERE target_document_type='delivery_receipt'
      AND target_document_id=p_dr_id
  ) THEN
    PERFORM set_config('pxl.document_conversion_write','on',true);
  END IF;

  INSERT INTO inventory_costing_runtime_queue(
    backend_pid, local_txid, sequence_no, operation, company_id, warehouse_id,
    item_id, source_line_id, lot_number, serial_number, original_transaction_id
  )
  SELECT pg_backend_pid(), txid_current(), row_number() OVER (ORDER BY drl.line_number),
    'reverse', dr.company_id, drl.warehouse_id, drl.item_id, drl.id,
    it.lot_number, it.serial_number, drl.inventory_transaction_id
  FROM public.delivery_receipt_lines drl
  JOIN public.delivery_receipts dr ON dr.id=drl.dr_id
  JOIN public.inventory_transactions it ON it.id=drl.inventory_transaction_id
  WHERE drl.dr_id=p_dr_id AND drl.inventory_transaction_id IS NOT NULL;

  PERFORM public.fn_void_delivery_receipt_costing_legacy_20260808(
    p_dr_id,p_void_reason_id,p_memo
  );
  IF EXISTS (
    SELECT 1 FROM public.inventory_costing_runtime_queue
    WHERE backend_pid=pg_backend_pid() AND local_txid=txid_current()
      AND operation='reverse'
  ) THEN
    RAISE EXCEPTION 'Delivery Receipt void left inventory restoration unbound'
      USING ERRCODE='23514';
  END IF;
END;
$$;

-- The shared Sales Invoice correction authority likewise remains the only
-- public void path. Its memo is the governed void explanation, but the
-- conversion guard must not generally make commercial memo edits writable;
-- admit the existing correction core only inside its transaction instead.
CREATE OR REPLACE FUNCTION public.fn_void_sales_invoice(
  p_invoice_id UUID, p_void_reason_id UUID, p_memo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_is_cash_sale BOOLEAN;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.document_relationships
    WHERE target_document_type='sales_invoice'
      AND target_document_id=p_invoice_id
  ) THEN
    PERFORM set_config('pxl.document_conversion_write','on',true);
  END IF;

  SELECT COALESCE(is_cash_sale,false) INTO v_is_cash_sale
  FROM public.sales_invoices WHERE id=p_invoice_id;
  IF v_is_cash_sale THEN
    PERFORM public.fn_void_cash_sale(p_invoice_id,p_void_reason_id,p_memo);
    RETURN;
  END IF;
  PERFORM public.fn_void_sales_invoice_aud053_core(
    p_invoice_id,p_void_reason_id,p_memo
  );
  PERFORM public.fn_stamp_void_inventory_dimensions(p_invoice_id);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_guard_sales_invoice_source_authority() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_guard_converted_sales_line() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_guard_converted_sales_header() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_refresh_sales_order_conversion(UUID) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_reverse_document_relationships(TEXT,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_sync_sales_conversion_lifecycle() FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.fn_convert_sales_document(TEXT,UUID,TEXT,JSONB,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_convert_sales_document(TEXT,UUID,TEXT,JSONB,JSONB) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_set_converted_sales_order_decision(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_set_converted_sales_order_decision(UUID,TEXT) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_cancel_sales_quotation(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_cancel_sales_quotation(UUID,TEXT) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_cancel_sales_order(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_cancel_sales_order(UUID,TEXT) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_update_converted_delivery_details(UUID,JSONB,JSONB,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_update_converted_delivery_details(UUID,JSONB,JSONB,TEXT) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_void_delivery_receipt(UUID,UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_void_delivery_receipt(UUID,UUID,TEXT) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_void_sales_invoice(UUID,UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_void_sales_invoice(UUID,UUID,TEXT) TO authenticated,service_role;

COMMENT ON FUNCTION public.fn_convert_sales_document(TEXT,UUID,TEXT,JSONB,JSONB) IS
  'Single atomic, branch-scoped sales conversion authority. Locks source lines, reserves draft quantities, derives commercial fields server-side, and records lineage without posting.';
