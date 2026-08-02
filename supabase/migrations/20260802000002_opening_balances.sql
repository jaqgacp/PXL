-- =============================================================================
-- Delivery Plan Phase 3 / PAD-002 — governed opening balances
--
-- One cut-over document owns the opening trial balance and the supporting AR,
-- AP, inventory, and bank detail.  The subledger control lines are derived from
-- those details, so a user cannot load a control-account amount that disagrees
-- with its supporting schedule.  Posting uses the existing Accounting Kernel
-- persistence helpers; this migration does not change the Kernel or its guard.
-- =============================================================================

CREATE TABLE public.opening_balance_batches (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID NOT NULL REFERENCES public.companies(id),
  branch_id         UUID REFERENCES public.branches(id),
  batch_number      TEXT NOT NULL,
  cutover_date      DATE NOT NULL,
  description       TEXT,
  currency_code     TEXT NOT NULL DEFAULT 'PHP' CHECK (currency_code = 'PHP'),
  status            TEXT NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'posted', 'reversed')),
  journal_entry_id  UUID REFERENCES public.journal_entries(id),
  reversal_je_id    UUID REFERENCES public.journal_entries(id),
  posted_at         TIMESTAMPTZ,
  posted_by         UUID REFERENCES auth.users(id),
  reversed_at       TIMESTAMPTZ,
  reversed_by       UUID REFERENCES auth.users(id),
  reversal_reason   TEXT,
  created_by        UUID REFERENCES auth.users(id),
  updated_by        UUID REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, batch_number),
  CHECK (
    (status = 'draft' AND journal_entry_id IS NULL AND posted_at IS NULL AND posted_by IS NULL)
    OR (status = 'posted' AND journal_entry_id IS NOT NULL AND posted_at IS NOT NULL AND posted_by IS NOT NULL
        AND reversal_je_id IS NULL AND reversed_at IS NULL AND reversed_by IS NULL)
    OR (status = 'reversed' AND journal_entry_id IS NOT NULL AND posted_at IS NOT NULL AND posted_by IS NOT NULL
        AND reversal_je_id IS NOT NULL AND reversed_at IS NOT NULL AND reversed_by IS NOT NULL
        AND NULLIF(btrim(reversal_reason), '') IS NOT NULL)
  )
);

CREATE UNIQUE INDEX opening_balance_one_posted_per_company
  ON public.opening_balance_batches(company_id)
  WHERE status = 'posted';

CREATE TABLE public.opening_balance_gl_lines (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id       UUID NOT NULL REFERENCES public.opening_balance_batches(id) ON DELETE CASCADE,
  company_id     UUID NOT NULL REFERENCES public.companies(id),
  line_number    INTEGER NOT NULL CHECK (line_number > 0),
  account_id     UUID NOT NULL REFERENCES public.chart_of_accounts(id),
  description    TEXT,
  debit_amount   NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (debit_amount >= 0),
  credit_amount  NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (credit_amount >= 0),
  created_by     UUID REFERENCES auth.users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (batch_id, line_number),
  UNIQUE (batch_id, account_id),
  CHECK ((debit_amount > 0) <> (credit_amount > 0))
);

CREATE TABLE public.opening_balance_ar_lines (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id              UUID NOT NULL REFERENCES public.opening_balance_batches(id) ON DELETE CASCADE,
  company_id            UUID NOT NULL REFERENCES public.companies(id),
  line_number           INTEGER NOT NULL CHECK (line_number > 0),
  customer_id           UUID NOT NULL REFERENCES public.customers(id),
  legacy_invoice_number TEXT NOT NULL,
  invoice_date          DATE NOT NULL,
  due_date              DATE,
  original_amount       NUMERIC(15,2) NOT NULL CHECK (original_amount > 0),
  memo                  TEXT,
  created_by            UUID REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (batch_id, line_number),
  UNIQUE (batch_id, customer_id, legacy_invoice_number)
);

CREATE TABLE public.opening_balance_ap_lines (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id               UUID NOT NULL REFERENCES public.opening_balance_batches(id) ON DELETE CASCADE,
  company_id             UUID NOT NULL REFERENCES public.companies(id),
  line_number            INTEGER NOT NULL CHECK (line_number > 0),
  supplier_id            UUID NOT NULL REFERENCES public.suppliers(id),
  legacy_bill_number     TEXT NOT NULL,
  supplier_invoice_number TEXT,
  bill_date              DATE NOT NULL,
  due_date               DATE,
  original_amount        NUMERIC(15,2) NOT NULL CHECK (original_amount > 0),
  memo                   TEXT,
  created_by             UUID REFERENCES auth.users(id),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (batch_id, line_number),
  UNIQUE (batch_id, supplier_id, legacy_bill_number)
);

CREATE TABLE public.opening_balance_inventory_lines (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id       UUID NOT NULL REFERENCES public.opening_balance_batches(id) ON DELETE CASCADE,
  company_id     UUID NOT NULL REFERENCES public.companies(id),
  line_number    INTEGER NOT NULL CHECK (line_number > 0),
  warehouse_id   UUID NOT NULL REFERENCES public.warehouses(id),
  item_id        UUID NOT NULL REFERENCES public.items(id),
  quantity       NUMERIC(15,4) NOT NULL CHECK (quantity > 0),
  unit_cost      NUMERIC(18,6) NOT NULL CHECK (unit_cost > 0),
  total_cost     NUMERIC(18,2) GENERATED ALWAYS AS (round(quantity * unit_cost, 2)) STORED,
  lot_number     TEXT,
  serial_number  TEXT,
  memo           TEXT,
  created_by     UUID REFERENCES auth.users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (batch_id, line_number),
  UNIQUE (batch_id, warehouse_id, item_id, lot_number, serial_number)
);

CREATE TABLE public.opening_balance_bank_lines (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id       UUID NOT NULL REFERENCES public.opening_balance_batches(id) ON DELETE CASCADE,
  company_id     UUID NOT NULL REFERENCES public.companies(id),
  line_number    INTEGER NOT NULL CHECK (line_number > 0),
  bank_account_id UUID NOT NULL REFERENCES public.bank_accounts(id),
  amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
  memo           TEXT,
  created_by     UUID REFERENCES auth.users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (batch_id, line_number),
  UNIQUE (batch_id, bank_account_id)
);

CREATE INDEX opening_balance_batches_company_date
  ON public.opening_balance_batches(company_id, cutover_date DESC);
CREATE INDEX opening_balance_ar_customer
  ON public.opening_balance_ar_lines(company_id, customer_id, due_date);
CREATE INDEX opening_balance_ap_supplier
  ON public.opening_balance_ap_lines(company_id, supplier_id, due_date);
CREATE INDEX opening_balance_inventory_item
  ON public.opening_balance_inventory_lines(company_id, warehouse_id, item_id);
CREATE UNIQUE INDEX opening_balance_inventory_natural_key
  ON public.opening_balance_inventory_lines(
    batch_id, warehouse_id, item_id,
    COALESCE(lot_number, ''), COALESCE(serial_number, '')
  );

-- RLS is default-deny for mutations.  Application writes go only through the
-- save/post/reverse RPCs below; members may read their own company's cut-over.
ALTER TABLE public.opening_balance_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opening_balance_gl_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opening_balance_ar_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opening_balance_ap_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opening_balance_inventory_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opening_balance_bank_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY opening_balance_batches_read ON public.opening_balance_batches
  FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY opening_balance_gl_lines_read ON public.opening_balance_gl_lines
  FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY opening_balance_ar_lines_read ON public.opening_balance_ar_lines
  FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY opening_balance_ap_lines_read ON public.opening_balance_ap_lines
  FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY opening_balance_inventory_lines_read ON public.opening_balance_inventory_lines
  FOR SELECT TO authenticated USING (is_company_member(company_id));
CREATE POLICY opening_balance_bank_lines_read ON public.opening_balance_bank_lines
  FOR SELECT TO authenticated USING (is_company_member(company_id));

REVOKE ALL ON TABLE
  public.opening_balance_batches,
  public.opening_balance_gl_lines,
  public.opening_balance_ar_lines,
  public.opening_balance_ap_lines,
  public.opening_balance_inventory_lines,
  public.opening_balance_bank_lines
FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE
  public.opening_balance_batches,
  public.opening_balance_gl_lines,
  public.opening_balance_ar_lines,
  public.opening_balance_ap_lines,
  public.opening_balance_inventory_lines,
  public.opening_balance_bank_lines
TO authenticated;
GRANT ALL ON TABLE
  public.opening_balance_batches,
  public.opening_balance_gl_lines,
  public.opening_balance_ar_lines,
  public.opening_balance_ap_lines,
  public.opening_balance_inventory_lines,
  public.opening_balance_bank_lines
TO service_role;

CREATE OR REPLACE FUNCTION public.fn_guard_opening_balance_batch()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transition TEXT := COALESCE(current_setting('pxl.opening_balance_transition', true), '');
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN
      RAISE EXCEPTION 'Posted opening balances are immutable; reverse the batch instead';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.status = 'draft' AND NEW.status = 'draft' THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'draft' AND NEW.status = 'posted' AND v_transition = 'post' THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'posted' AND NEW.status = 'reversed' AND v_transition = 'reverse' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Opening-balance lifecycle transition % -> % is not allowed', OLD.status, NEW.status;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_guard_opening_balance_line()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch_id UUID;
  v_status TEXT;
BEGIN
  v_batch_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.batch_id ELSE NEW.batch_id END;
  SELECT status INTO v_status FROM public.opening_balance_batches WHERE id = v_batch_id;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Posted opening-balance detail is immutable; reverse the batch instead';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER trg_opening_balance_batch_guard
  BEFORE UPDATE OR DELETE ON public.opening_balance_batches
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_opening_balance_batch();
CREATE TRIGGER trg_opening_balance_batch_updated_at
  BEFORE UPDATE ON public.opening_balance_batches
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE TRIGGER trg_opening_balance_gl_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.opening_balance_gl_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_opening_balance_line();
CREATE TRIGGER trg_opening_balance_ar_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.opening_balance_ar_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_opening_balance_line();
CREATE TRIGGER trg_opening_balance_ap_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.opening_balance_ap_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_opening_balance_line();
CREATE TRIGGER trg_opening_balance_inventory_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.opening_balance_inventory_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_opening_balance_line();
CREATE TRIGGER trg_opening_balance_bank_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.opening_balance_bank_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_opening_balance_line();

CREATE TRIGGER trg_audit_opening_balance_batches
  AFTER INSERT OR UPDATE OR DELETE ON public.opening_balance_batches
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();
CREATE TRIGGER trg_audit_opening_balance_gl_lines
  AFTER INSERT OR UPDATE OR DELETE ON public.opening_balance_gl_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();
CREATE TRIGGER trg_audit_opening_balance_ar_lines
  AFTER INSERT OR UPDATE OR DELETE ON public.opening_balance_ar_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();
CREATE TRIGGER trg_audit_opening_balance_ap_lines
  AFTER INSERT OR UPDATE OR DELETE ON public.opening_balance_ap_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();
CREATE TRIGGER trg_audit_opening_balance_inventory_lines
  AFTER INSERT OR UPDATE OR DELETE ON public.opening_balance_inventory_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();
CREATE TRIGGER trg_audit_opening_balance_bank_lines
  AFTER INSERT OR UPDATE OR DELETE ON public.opening_balance_bank_lines
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

INSERT INTO public.ref_posting_source_types (
  document_type, source_table, document_number_column, document_date_column,
  status_column, route_path, display_name, allows_multiple_journal_entries,
  is_active
) VALUES (
  'OPENING', 'public.opening_balance_batches'::regclass, 'batch_number',
  'cutover_date', 'status', '/opening-balances', 'Opening Balance', true, true
)
ON CONFLICT (document_type) DO UPDATE SET
  source_table = EXCLUDED.source_table,
  document_number_column = EXCLUDED.document_number_column,
  document_date_column = EXCLUDED.document_date_column,
  status_column = EXCLUDED.status_column,
  route_path = EXCLUDED.route_path,
  display_name = EXCLUDED.display_name,
  allows_multiple_journal_entries = EXCLUDED.allows_multiple_journal_entries,
  is_active = EXCLUDED.is_active;

CREATE OR REPLACE FUNCTION public.fn_save_opening_balance(
  p_batch_id UUID,
  p_header JSONB,
  p_gl_lines JSONB DEFAULT '[]'::JSONB,
  p_ar_lines JSONB DEFAULT '[]'::JSONB,
  p_ap_lines JSONB DEFAULT '[]'::JSONB,
  p_inventory_lines JSONB DEFAULT '[]'::JSONB,
  p_bank_lines JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch_id UUID;
  v_company_id UUID := NULLIF(p_header->>'company_id', '')::UUID;
  v_branch_id UUID := NULLIF(p_header->>'branch_id', '')::UUID;
  v_cutover_date DATE := NULLIF(p_header->>'cutover_date', '')::DATE;
  v_batch_number TEXT := upper(btrim(COALESCE(NULLIF(p_header->>'batch_number', ''), '')));
  v_status TEXT;
BEGIN
  IF v_company_id IS NULL OR v_cutover_date IS NULL THEN
    RAISE EXCEPTION 'Company and cut-over date are required';
  END IF;
  IF NOT can_admin_company(v_company_id) THEN
    RAISE EXCEPTION 'Only a company owner or administrator can maintain opening balances';
  END IF;
  IF COALESCE(NULLIF(p_header->>'currency_code', ''), 'PHP') <> 'PHP' THEN
    RAISE EXCEPTION 'Opening balances currently support PHP only';
  END IF;
  IF v_branch_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.branches WHERE id = v_branch_id AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Opening-balance branch does not belong to the company';
  END IF;
  IF jsonb_typeof(COALESCE(p_gl_lines, '[]')) <> 'array'
     OR jsonb_typeof(COALESCE(p_ar_lines, '[]')) <> 'array'
     OR jsonb_typeof(COALESCE(p_ap_lines, '[]')) <> 'array'
     OR jsonb_typeof(COALESCE(p_inventory_lines, '[]')) <> 'array'
     OR jsonb_typeof(COALESCE(p_bank_lines, '[]')) <> 'array' THEN
    RAISE EXCEPTION 'Every opening-balance line collection must be a JSON array';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_company_id::TEXT || ':opening-balance', 0));

  IF p_batch_id IS NULL THEN
    IF v_batch_number = '' THEN
      SELECT 'OB-' || to_char(v_cutover_date, 'YYYYMMDD') || '-' ||
             lpad((count(*) + 1)::TEXT, 3, '0')
      INTO v_batch_number
      FROM public.opening_balance_batches
      WHERE company_id = v_company_id;
    END IF;
    INSERT INTO public.opening_balance_batches (
      company_id, branch_id, batch_number, cutover_date, description,
      currency_code, status, created_by, updated_by
    ) VALUES (
      v_company_id, v_branch_id, v_batch_number, v_cutover_date,
      NULLIF(p_header->>'description', ''), 'PHP', 'draft', auth.uid(), auth.uid()
    ) RETURNING id INTO v_batch_id;
  ELSE
    SELECT id, status INTO v_batch_id, v_status
    FROM public.opening_balance_batches
    WHERE id = p_batch_id AND company_id = v_company_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Opening-balance batch not found or access denied'; END IF;
    IF v_status <> 'draft' THEN RAISE EXCEPTION 'Only a draft opening-balance batch can be edited'; END IF;
    IF v_batch_number = '' THEN
      SELECT batch_number INTO v_batch_number FROM public.opening_balance_batches WHERE id = v_batch_id;
    END IF;
    UPDATE public.opening_balance_batches SET
      branch_id = v_branch_id,
      batch_number = v_batch_number,
      cutover_date = v_cutover_date,
      description = NULLIF(p_header->>'description', ''),
      updated_by = auth.uid()
    WHERE id = v_batch_id;
  END IF;

  DELETE FROM public.opening_balance_gl_lines WHERE batch_id = v_batch_id;
  DELETE FROM public.opening_balance_ar_lines WHERE batch_id = v_batch_id;
  DELETE FROM public.opening_balance_ap_lines WHERE batch_id = v_batch_id;
  DELETE FROM public.opening_balance_inventory_lines WHERE batch_id = v_batch_id;
  DELETE FROM public.opening_balance_bank_lines WHERE batch_id = v_batch_id;

  INSERT INTO public.opening_balance_gl_lines (
    batch_id, company_id, line_number, account_id, description,
    debit_amount, credit_amount, created_by
  )
  SELECT v_batch_id, v_company_id, ord::INTEGER,
         NULLIF(line->>'account_id', '')::UUID,
         NULLIF(line->>'description', ''),
         COALESCE(NULLIF(line->>'debit_amount', '')::NUMERIC, 0),
         COALESCE(NULLIF(line->>'credit_amount', '')::NUMERIC, 0), auth.uid()
  FROM jsonb_array_elements(COALESCE(p_gl_lines, '[]')) WITH ORDINALITY AS x(line, ord);

  INSERT INTO public.opening_balance_ar_lines (
    batch_id, company_id, line_number, customer_id, legacy_invoice_number,
    invoice_date, due_date, original_amount, memo, created_by
  )
  SELECT v_batch_id, v_company_id, ord::INTEGER,
         NULLIF(line->>'customer_id', '')::UUID,
         btrim(line->>'legacy_invoice_number'),
         NULLIF(line->>'invoice_date', '')::DATE,
         NULLIF(line->>'due_date', '')::DATE,
         NULLIF(line->>'original_amount', '')::NUMERIC,
         NULLIF(line->>'memo', ''), auth.uid()
  FROM jsonb_array_elements(COALESCE(p_ar_lines, '[]')) WITH ORDINALITY AS x(line, ord);

  INSERT INTO public.opening_balance_ap_lines (
    batch_id, company_id, line_number, supplier_id, legacy_bill_number,
    supplier_invoice_number, bill_date, due_date, original_amount, memo, created_by
  )
  SELECT v_batch_id, v_company_id, ord::INTEGER,
         NULLIF(line->>'supplier_id', '')::UUID,
         btrim(line->>'legacy_bill_number'),
         NULLIF(line->>'supplier_invoice_number', ''),
         NULLIF(line->>'bill_date', '')::DATE,
         NULLIF(line->>'due_date', '')::DATE,
         NULLIF(line->>'original_amount', '')::NUMERIC,
         NULLIF(line->>'memo', ''), auth.uid()
  FROM jsonb_array_elements(COALESCE(p_ap_lines, '[]')) WITH ORDINALITY AS x(line, ord);

  INSERT INTO public.opening_balance_inventory_lines (
    batch_id, company_id, line_number, warehouse_id, item_id, quantity,
    unit_cost, lot_number, serial_number, memo, created_by
  )
  SELECT v_batch_id, v_company_id, ord::INTEGER,
         NULLIF(line->>'warehouse_id', '')::UUID,
         NULLIF(line->>'item_id', '')::UUID,
         NULLIF(line->>'quantity', '')::NUMERIC,
         NULLIF(line->>'unit_cost', '')::NUMERIC,
         NULLIF(line->>'lot_number', ''), NULLIF(line->>'serial_number', ''),
         NULLIF(line->>'memo', ''), auth.uid()
  FROM jsonb_array_elements(COALESCE(p_inventory_lines, '[]')) WITH ORDINALITY AS x(line, ord);

  INSERT INTO public.opening_balance_bank_lines (
    batch_id, company_id, line_number, bank_account_id, amount, memo, created_by
  )
  SELECT v_batch_id, v_company_id, ord::INTEGER,
         NULLIF(line->>'bank_account_id', '')::UUID,
         NULLIF(line->>'amount', '')::NUMERIC,
         NULLIF(line->>'memo', ''), auth.uid()
  FROM jsonb_array_elements(COALESCE(p_bank_lines, '[]')) WITH ORDINALITY AS x(line, ord);

  RETURN v_batch_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_opening_balance_summary(p_batch_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch public.opening_balance_batches%ROWTYPE;
  v_gl_debit NUMERIC(15,2);
  v_gl_credit NUMERIC(15,2);
  v_ar NUMERIC(15,2);
  v_ap NUMERIC(15,2);
  v_inventory NUMERIC(15,2);
  v_bank NUMERIC(15,2);
BEGIN
  SELECT * INTO v_batch FROM public.opening_balance_batches WHERE id = p_batch_id;
  IF NOT FOUND OR NOT is_company_member(v_batch.company_id) THEN
    RAISE EXCEPTION 'Opening-balance batch not found or access denied';
  END IF;

  SELECT COALESCE(sum(debit_amount), 0), COALESCE(sum(credit_amount), 0)
    INTO v_gl_debit, v_gl_credit
  FROM public.opening_balance_gl_lines WHERE batch_id = p_batch_id;
  SELECT COALESCE(sum(original_amount), 0) INTO v_ar
  FROM public.opening_balance_ar_lines WHERE batch_id = p_batch_id;
  SELECT COALESCE(sum(original_amount), 0) INTO v_ap
  FROM public.opening_balance_ap_lines WHERE batch_id = p_batch_id;
  SELECT COALESCE(sum(total_cost), 0) INTO v_inventory
  FROM public.opening_balance_inventory_lines WHERE batch_id = p_batch_id;
  SELECT COALESCE(sum(amount), 0) INTO v_bank
  FROM public.opening_balance_bank_lines WHERE batch_id = p_batch_id;

  RETURN jsonb_build_object(
    'gl_debit', v_gl_debit, 'gl_credit', v_gl_credit,
    'ar_total', v_ar, 'ap_total', v_ap,
    'inventory_total', v_inventory, 'bank_total', v_bank,
    'total_debit', round(v_gl_debit + v_ar + v_inventory + v_bank, 2),
    'total_credit', round(v_gl_credit + v_ap, 2),
    'variance', round((v_gl_debit + v_ar + v_inventory + v_bank) - (v_gl_credit + v_ap), 2)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_post_opening_balance(p_batch_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch public.opening_balance_batches%ROWTYPE;
  v_summary JSONB;
  v_ar_account UUID;
  v_ap_account UUID;
  v_inventory_account UUID;
  v_je_id UUID;
  v_tx_id UUID;
  v_line RECORD;
  v_line_no INTEGER := 1;
  v_control_accounts UUID[] := ARRAY[]::UUID[];
BEGIN
  SELECT * INTO v_batch
  FROM public.opening_balance_batches
  WHERE id = p_batch_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Opening-balance batch not found'; END IF;
  IF NOT can_admin_company(v_batch.company_id) THEN
    RAISE EXCEPTION 'Only a company owner or administrator can post opening balances';
  END IF;
  IF v_batch.status = 'posted' THEN RETURN v_batch.journal_entry_id; END IF;
  IF v_batch.status <> 'draft' THEN RAISE EXCEPTION 'Only a draft opening-balance batch can be posted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_batch.company_id::TEXT || ':opening-balance', 0));

  IF EXISTS (
    SELECT 1 FROM public.opening_balance_batches
    WHERE company_id = v_batch.company_id AND status = 'posted' AND id <> v_batch.id
  ) THEN RAISE EXCEPTION 'This company already has a posted opening-balance batch'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE company_id = v_batch.company_id AND status IN ('posted', 'reversed')
  ) THEN RAISE EXCEPTION 'Opening balances must be posted before operational journals exist'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.inventory_transactions WHERE company_id = v_batch.company_id
  ) THEN RAISE EXCEPTION 'Opening balances must be posted before inventory movements exist'; END IF;

  PERFORM fn_require_open_fiscal_period(v_batch.company_id, v_batch.cutover_date, true);

  IF EXISTS (
    SELECT 1 FROM public.opening_balance_gl_lines l
    LEFT JOIN public.chart_of_accounts a ON a.id = l.account_id
    WHERE l.batch_id = v_batch.id
      AND (a.id IS NULL OR a.company_id <> v_batch.company_id OR NOT a.is_active OR NOT a.is_postable)
  ) THEN RAISE EXCEPTION 'Every opening GL account must be active, postable, and owned by the company'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.opening_balance_ar_lines l
    LEFT JOIN public.customers c ON c.id = l.customer_id
    WHERE l.batch_id = v_batch.id AND (c.id IS NULL OR c.company_id <> v_batch.company_id OR NOT c.is_active)
  ) THEN RAISE EXCEPTION 'Every opening AR customer must be active and owned by the company'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.opening_balance_ar_lines
    WHERE batch_id = v_batch.id
      AND (invoice_date > v_batch.cutover_date OR (due_date IS NOT NULL AND due_date < invoice_date))
  ) THEN RAISE EXCEPTION 'Opening AR invoice dates cannot follow cut-over and due dates cannot precede invoice dates'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.opening_balance_ap_lines l
    LEFT JOIN public.suppliers s ON s.id = l.supplier_id
    WHERE l.batch_id = v_batch.id AND (s.id IS NULL OR s.company_id <> v_batch.company_id OR NOT s.is_active)
  ) THEN RAISE EXCEPTION 'Every opening AP supplier must be active and owned by the company'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.opening_balance_ap_lines
    WHERE batch_id = v_batch.id
      AND (bill_date > v_batch.cutover_date OR (due_date IS NOT NULL AND due_date < bill_date))
  ) THEN RAISE EXCEPTION 'Opening AP bill dates cannot follow cut-over and due dates cannot precede bill dates'; END IF;
  IF EXISTS (
    SELECT 1
    FROM public.opening_balance_inventory_lines l
    LEFT JOIN public.items i ON i.id = l.item_id
    LEFT JOIN public.warehouses w ON w.id = l.warehouse_id
    LEFT JOIN public.stock_balances sb ON sb.warehouse_id = l.warehouse_id AND sb.item_id = l.item_id
    WHERE l.batch_id = v_batch.id
      AND (i.id IS NULL OR i.company_id <> v_batch.company_id OR NOT i.is_active
           OR i.item_type <> 'inventory_item'
           OR w.id IS NULL OR w.company_id <> v_batch.company_id OR NOT w.is_active
           OR COALESCE(sb.qty_on_hand, 0) <> 0 OR COALESCE(sb.total_cost, 0) <> 0)
  ) THEN RAISE EXCEPTION 'Every opening inventory line must use an active company item/warehouse with zero existing stock'; END IF;
  IF EXISTS (
    SELECT 1
    FROM public.opening_balance_bank_lines l
    LEFT JOIN public.bank_accounts b ON b.id = l.bank_account_id
    LEFT JOIN public.chart_of_accounts a ON a.id = b.gl_account_id
    WHERE l.batch_id = v_batch.id
      AND (b.id IS NULL OR b.company_id <> v_batch.company_id OR NOT b.is_active
           OR COALESCE(b.opening_balance, 0) <> 0
           OR a.id IS NULL OR a.company_id <> v_batch.company_id OR NOT a.is_active OR NOT a.is_postable)
  ) THEN RAISE EXCEPTION 'Every opening bank line must use an active mapped company bank account with zero legacy opening_balance'; END IF;

  IF EXISTS (SELECT 1 FROM public.opening_balance_ar_lines WHERE batch_id = v_batch.id) THEN
    v_ar_account := fn_resolve_posting_account(v_batch.company_id, 'AR_TRADE', v_batch.cutover_date,
      'AR control account is required before loading opening receivables');
    v_control_accounts := array_append(v_control_accounts, v_ar_account);
  END IF;
  IF EXISTS (SELECT 1 FROM public.opening_balance_ap_lines WHERE batch_id = v_batch.id) THEN
    v_ap_account := fn_resolve_posting_account(v_batch.company_id, 'AP_TRADE', v_batch.cutover_date,
      'AP control account is required before loading opening payables');
    v_control_accounts := array_append(v_control_accounts, v_ap_account);
  END IF;
  IF EXISTS (SELECT 1 FROM public.opening_balance_inventory_lines WHERE batch_id = v_batch.id) THEN
    v_inventory_account := fn_resolve_posting_account(v_batch.company_id, 'INVENTORY_CONTROL', v_batch.cutover_date,
      'Inventory control account is required before loading opening stock');
    v_control_accounts := array_append(v_control_accounts, v_inventory_account);
  END IF;
  SELECT array_cat(v_control_accounts, COALESCE(array_agg(DISTINCT b.gl_account_id), ARRAY[]::UUID[]))
  INTO v_control_accounts
  FROM public.opening_balance_bank_lines l
  JOIN public.bank_accounts b ON b.id = l.bank_account_id
  WHERE l.batch_id = v_batch.id;

  IF EXISTS (
    SELECT 1 FROM public.opening_balance_gl_lines
    WHERE batch_id = v_batch.id AND account_id = ANY(v_control_accounts)
  ) THEN
    RAISE EXCEPTION 'AR, AP, inventory, and bank control accounts are derived from detail and cannot be entered as other GL lines';
  END IF;

  v_summary := public.fn_opening_balance_summary(v_batch.id);
  IF abs((v_summary->>'variance')::NUMERIC) > 0.005 THEN
    RAISE EXCEPTION 'Opening balances are not balanced: debit % <> credit % (variance %)',
      v_summary->>'total_debit', v_summary->>'total_credit', v_summary->>'variance';
  END IF;
  IF (v_summary->>'total_debit')::NUMERIC <= 0 THEN
    RAISE EXCEPTION 'Opening balances contain no financial amount';
  END IF;

  v_je_id := fn_create_posted_journal_entry(
    v_batch.company_id,
    v_batch.branch_id,
    fn_derive_journal_number('OPENING', v_batch.batch_number, v_batch.company_id, v_batch.branch_id),
    v_batch.cutover_date,
    COALESCE(v_batch.description, 'Opening balances at cut-over'),
    'OPENING', v_batch.id,
    NULL, 'posted', 0, 0, 'system', 'opening', false, false, true
  );

  FOR v_line IN
    SELECT * FROM public.opening_balance_gl_lines
    WHERE batch_id = v_batch.id ORDER BY line_number
  LOOP
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_line.account_id,
      COALESCE(v_line.description, 'Opening balance'),
      v_line.debit_amount, v_line.credit_amount, 'base', v_line.id,
      v_batch.branch_id, NULL, NULL, NULL, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  IF v_ar_account IS NOT NULL THEN
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_ar_account, 'Opening accounts receivable',
      (v_summary->>'ar_total')::NUMERIC, 0, 'control', NULL,
      v_batch.branch_id, NULL, NULL, NULL, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;
  IF v_ap_account IS NOT NULL THEN
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_ap_account, 'Opening accounts payable',
      0, (v_summary->>'ap_total')::NUMERIC, 'control', NULL,
      v_batch.branch_id, NULL, NULL, NULL, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;
  IF v_inventory_account IS NOT NULL THEN
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_inventory_account, 'Opening inventory at cost',
      (v_summary->>'inventory_total')::NUMERIC, 0, 'control', NULL,
      v_batch.branch_id, NULL, NULL, NULL, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END IF;
  FOR v_line IN
    SELECT b.gl_account_id, sum(l.amount)::NUMERIC(15,2) amount
    FROM public.opening_balance_bank_lines l
    JOIN public.bank_accounts b ON b.id = l.bank_account_id
    WHERE l.batch_id = v_batch.id
    GROUP BY b.gl_account_id ORDER BY b.gl_account_id
  LOOP
    PERFORM fn_add_posting_line_push(
      v_je_id, v_line_no, v_line.gl_account_id, 'Opening bank balance',
      v_line.amount, 0, 'control', NULL,
      v_batch.branch_id, NULL, NULL, NULL, NULL, NULL
    );
    v_line_no := v_line_no + 1;
  END LOOP;

  PERFORM fn_finalize_journal_entry(v_je_id);

  FOR v_line IN
    SELECT * FROM public.opening_balance_inventory_lines
    WHERE batch_id = v_batch.id ORDER BY line_number
  LOOP
    v_tx_id := fn_receive_inventory(jsonb_build_object(
      'company_id', v_batch.company_id,
      'warehouse_id', v_line.warehouse_id,
      'item_id', v_line.item_id,
      'qty', v_line.quantity,
      'unit_cost', v_line.unit_cost,
      'receipt_date', v_batch.cutover_date,
      'reference_doc_type', 'OPENING',
      'reference_doc_id', v_batch.id,
      'lot_number', v_line.lot_number,
      'serial_number', v_line.serial_number,
      'notes', COALESCE(v_line.memo, 'Opening inventory')
    ));
    UPDATE public.inventory_transactions
    SET journal_entry_id = v_je_id
    WHERE id = v_tx_id;
  END LOOP;

  PERFORM set_config('pxl.opening_balance_transition', 'post', true);
  UPDATE public.opening_balance_batches SET
    status = 'posted', journal_entry_id = v_je_id,
    posted_at = now(), posted_by = auth.uid(), updated_by = auth.uid()
  WHERE id = v_batch.id;

  RETURN v_je_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_reverse_opening_balance(
  p_batch_id UUID,
  p_reversal_date DATE,
  p_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch public.opening_balance_batches%ROWTYPE;
  v_line RECORD;
  v_reversal_id UUID;
  v_qty_after NUMERIC(15,4);
BEGIN
  SELECT * INTO v_batch
  FROM public.opening_balance_batches
  WHERE id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Opening-balance batch not found'; END IF;
  IF NOT can_admin_company(v_batch.company_id) THEN
    RAISE EXCEPTION 'Only a company owner or administrator can reverse opening balances';
  END IF;
  IF v_batch.status = 'reversed' THEN RETURN v_batch.reversal_je_id; END IF;
  IF v_batch.status <> 'posted' THEN
    RAISE EXCEPTION 'Only a posted opening-balance batch can be reversed';
  END IF;
  IF p_reversal_date IS NULL OR p_reversal_date < v_batch.cutover_date THEN
    RAISE EXCEPTION 'Reversal date must be on or after the cut-over date';
  END IF;
  IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A reversal reason is required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_batch.company_id::TEXT || ':opening-balance', 0));
  PERFORM fn_require_open_fiscal_period(v_batch.company_id, p_reversal_date, true);

  -- A cut-over correction is safe only before the company has begun operating.
  -- Once any later posting or inventory movement exists, the correction must be
  -- made by ordinary operational documents rather than erasing the stand-up.
  IF EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE company_id = v_batch.company_id
      AND status IN ('posted', 'reversed')
      AND id <> v_batch.journal_entry_id
  ) THEN
    RAISE EXCEPTION 'Opening balances cannot be reversed after operational journals exist';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.inventory_transactions
    WHERE company_id = v_batch.company_id
      AND NOT (reference_doc_type = 'OPENING' AND reference_doc_id = v_batch.id)
  ) THEN
    RAISE EXCEPTION 'Opening balances cannot be reversed after operational inventory movements exist';
  END IF;

  v_reversal_id := fn_reverse_posted_journal_entry(
    v_batch.journal_entry_id,
    p_reversal_date,
    'OPENING',
    v_batch.id,
    fn_derive_journal_number(
      'OPENING', v_batch.batch_number || '-REV', v_batch.company_id, v_batch.branch_id
    ),
    'Reversal — ' || btrim(p_reason)
  );

  FOR v_line IN
    SELECT l.*, i.costing_method
    FROM public.opening_balance_inventory_lines l
    JOIN public.items i ON i.id = l.item_id
    WHERE l.batch_id = v_batch.id
    ORDER BY l.line_number
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.stock_balances sb
      WHERE sb.company_id = v_batch.company_id
        AND sb.warehouse_id = v_line.warehouse_id
        AND sb.item_id = v_line.item_id
        AND sb.qty_on_hand >= v_line.quantity
        AND sb.total_cost >= v_line.total_cost
      FOR UPDATE
    ) THEN
      RAISE EXCEPTION 'Opening inventory is no longer intact for item % in warehouse %',
        v_line.item_id, v_line.warehouse_id;
    END IF;

    IF v_line.costing_method IN ('fifo', 'specific_identification') THEN
      PERFORM fn_consume_cost_layers(
        v_batch.company_id, v_line.warehouse_id, v_line.item_id,
        v_line.quantity, v_line.lot_number, v_line.serial_number
      );
    END IF;

    UPDATE public.stock_balances
    SET qty_on_hand = qty_on_hand - v_line.quantity,
        total_cost = total_cost - v_line.total_cost,
        wac_unit_cost = CASE
          WHEN qty_on_hand - v_line.quantity > 0
            THEN round((total_cost - v_line.total_cost) / (qty_on_hand - v_line.quantity), 6)
          ELSE 0
        END,
        updated_at = now()
    WHERE company_id = v_batch.company_id
      AND warehouse_id = v_line.warehouse_id
      AND item_id = v_line.item_id
    RETURNING qty_on_hand INTO v_qty_after;

    INSERT INTO public.inventory_transactions (
      company_id, warehouse_id, item_id, transaction_type, transaction_date,
      qty, unit_cost, total_cost, qty_on_hand_after, costing_method,
      reference_doc_type, reference_doc_id, journal_entry_id,
      lot_number, serial_number, notes, created_by
    ) VALUES (
      v_batch.company_id, v_line.warehouse_id, v_line.item_id,
      'adjustment_out', p_reversal_date, -v_line.quantity, v_line.unit_cost,
      -v_line.total_cost, v_qty_after, v_line.costing_method,
      'OPENING_REVERSAL', v_batch.id, v_reversal_id,
      v_line.lot_number, v_line.serial_number,
      'Opening-balance reversal: ' || btrim(p_reason), auth.uid()
    );
  END LOOP;

  PERFORM set_config('pxl.opening_balance_transition', 'reverse', true);
  UPDATE public.opening_balance_batches SET
    status = 'reversed', reversal_je_id = v_reversal_id,
    reversed_at = now(), reversed_by = auth.uid(), reversal_reason = btrim(p_reason),
    updated_by = auth.uid()
  WHERE id = v_batch.id;

  RETURN v_reversal_id;
END;
$$;

-- Opening receivables and payables must remain operational after cut-over.
-- Existing settlement lines retain their accounting meaning (invoice/bill
-- application) while exactly one source reference identifies either a native
-- document or an opening item.
ALTER TABLE public.receipt_lines
  ADD COLUMN opening_ar_line_id UUID REFERENCES public.opening_balance_ar_lines(id);
ALTER TABLE public.payment_voucher_lines
  ADD COLUMN opening_ap_line_id UUID REFERENCES public.opening_balance_ap_lines(id);

ALTER TABLE public.receipt_lines
  DROP CONSTRAINT receipt_lines_line_type_invoice_consistency,
  ADD CONSTRAINT receipt_lines_line_source_consistency CHECK (
    (line_type = 'invoice_application'
      AND num_nonnulls(invoice_id, opening_ar_line_id) = 1)
    OR (line_type = 'customer_advance'
      AND invoice_id IS NULL AND opening_ar_line_id IS NULL)
  );
ALTER TABLE public.payment_voucher_lines
  DROP CONSTRAINT payment_voucher_lines_line_type_bill_consistency,
  ADD CONSTRAINT payment_voucher_lines_line_source_consistency CHECK (
    (line_type = 'bill_application'
      AND num_nonnulls(vendor_bill_id, opening_ap_line_id) = 1)
    OR (line_type = 'supplier_down_payment'
      AND vendor_bill_id IS NULL AND opening_ap_line_id IS NULL)
  );

CREATE UNIQUE INDEX receipt_lines_one_opening_item_per_receipt
  ON public.receipt_lines(receipt_id, opening_ar_line_id)
  WHERE opening_ar_line_id IS NOT NULL;
CREATE INDEX receipt_lines_opening_ar_application
  ON public.receipt_lines(opening_ar_line_id)
  WHERE opening_ar_line_id IS NOT NULL;
CREATE UNIQUE INDEX payment_voucher_lines_one_opening_item_per_voucher
  ON public.payment_voucher_lines(payment_voucher_id, opening_ap_line_id)
  WHERE opening_ap_line_id IS NOT NULL;
CREATE INDEX payment_voucher_lines_opening_ap_application
  ON public.payment_voucher_lines(opening_ap_line_id)
  WHERE opening_ap_line_id IS NOT NULL;

-- Preserve the mature native-document save routines and layer only the opening
-- item continuation on top. The core receives regular invoices/bills; opening
-- applications are validated and inserted through this SECURITY DEFINER edge.
ALTER FUNCTION public.fn_save_receipt(UUID, JSONB, JSONB)
  RENAME TO fn_save_receipt_pre_opening_core;
REVOKE ALL ON FUNCTION public.fn_save_receipt_pre_opening_core(UUID, JSONB, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_save_receipt(
  p_receipt_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt_id UUID;
  v_company_id UUID := NULLIF(p_header->>'company_id', '')::UUID;
  v_customer_id UUID := NULLIF(p_header->>'customer_id', '')::UUID;
  v_receipt_date DATE := NULLIF(p_header->>'receipt_date', '')::DATE;
  v_regular_lines JSONB;
  v_line JSONB;
  v_opening_id UUID;
  v_original NUMERIC(15,2);
  v_other_applied NUMERIC(15,2);
  v_payment NUMERIC(15,2);
  v_cwt NUMERIC(15,2);
  v_forex NUMERIC(15,2);
BEGIN
  IF jsonb_typeof(COALESCE(p_lines, '[]'::JSONB)) <> 'array' THEN
    RAISE EXCEPTION 'Receipt lines must be a JSON array';
  END IF;

  SELECT COALESCE(jsonb_agg(value ORDER BY ord), '[]'::JSONB)
  INTO v_regular_lines
  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB))
       WITH ORDINALITY AS x(value, ord)
  WHERE NULLIF(value->>'opening_ar_line_id', '') IS NULL;

  FOR v_line IN
    SELECT value
    FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) AS x(value)
    WHERE NULLIF(value->>'opening_ar_line_id', '') IS NOT NULL
  LOOP
    v_opening_id := NULLIF(v_line->>'opening_ar_line_id', '')::UUID;
    v_payment := COALESCE(NULLIF(v_line->>'payment_amount', '')::NUMERIC, 0);
    v_cwt := COALESCE(NULLIF(v_line->>'cwt_amount', '')::NUMERIC, 0);
    v_forex := COALESCE(NULLIF(v_line->>'forex_adjustment', '')::NUMERIC, 0);

    IF COALESCE(NULLIF(v_line->>'line_type', ''), 'invoice_application') <> 'invoice_application'
       OR NULLIF(v_line->>'invoice_id', '') IS NOT NULL THEN
      RAISE EXCEPTION 'An opening receivable must be an invoice application with no sales-invoice reference';
    END IF;
    IF v_payment + v_cwt <= 0 THEN CONTINUE; END IF;
    IF v_forex <> 0 THEN
      RAISE EXCEPTION 'Opening receivables are PHP-only and do not permit forex adjustments';
    END IF;

    SELECT l.original_amount INTO v_original
    FROM public.opening_balance_ar_lines l
    JOIN public.opening_balance_batches b ON b.id = l.batch_id
    WHERE l.id = v_opening_id
      AND l.company_id = v_company_id
      AND l.customer_id = v_customer_id
      AND b.status = 'posted'
      AND b.cutover_date <= v_receipt_date
    FOR UPDATE OF l;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Opening receivable does not belong to this posted company/customer cut-over';
    END IF;

    SELECT COALESCE(sum(rl.payment_amount + rl.cwt_amount), 0)
    INTO v_other_applied
    FROM public.receipt_lines rl
    JOIN public.receipts r ON r.id = rl.receipt_id
    WHERE rl.opening_ar_line_id = v_opening_id
      AND r.status NOT IN ('bounced', 'cancelled')
      AND rl.receipt_id <> COALESCE(p_receipt_id, '00000000-0000-0000-0000-000000000000'::UUID);
    IF v_payment + v_cwt > v_original - v_other_applied + 0.02 THEN
      RAISE EXCEPTION 'Receipt application exceeds opening invoice % outstanding balance', v_opening_id;
    END IF;

    PERFORM public.fn_validate_receipt_line_cwt(
      v_company_id, v_payment, v_cwt,
      NULLIF(v_line->>'atc_code_id', '')::UUID,
      NULLIF(v_line->>'cwt_tax_base', '')::NUMERIC,
      NULLIF(v_line->>'cwt_variance_reason', ''), v_receipt_date
    );
  END LOOP;

  v_receipt_id := public.fn_save_receipt_pre_opening_core(
    p_receipt_id, p_header, v_regular_lines
  );

  INSERT INTO public.receipt_lines (
    receipt_id, company_id, invoice_id, opening_ar_line_id, line_type,
    payment_amount, cwt_amount, forex_adjustment, atc_code_id,
    cwt_tax_base, cwt_variance_reason, created_by, updated_by
  )
  SELECT v_receipt_id, v_company_id, NULL, NULLIF(value->>'opening_ar_line_id', '')::UUID,
         'invoice_application',
         COALESCE(NULLIF(value->>'payment_amount', '')::NUMERIC, 0),
         COALESCE(NULLIF(value->>'cwt_amount', '')::NUMERIC, 0), 0,
         NULLIF(value->>'atc_code_id', '')::UUID,
         NULLIF(value->>'cwt_tax_base', '')::NUMERIC,
         NULLIF(value->>'cwt_variance_reason', ''), auth.uid(), auth.uid()
  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) AS x(value)
  WHERE NULLIF(value->>'opening_ar_line_id', '') IS NOT NULL
    AND (COALESCE(NULLIF(value->>'payment_amount', '')::NUMERIC, 0)
       + COALESCE(NULLIF(value->>'cwt_amount', '')::NUMERIC, 0)) > 0;

  UPDATE public.receipts SET
    total_amount = COALESCE((SELECT sum(payment_amount) FROM public.receipt_lines WHERE receipt_id = v_receipt_id), 0),
    total_cwt = COALESCE((SELECT sum(cwt_amount) FROM public.receipt_lines WHERE receipt_id = v_receipt_id), 0),
    updated_at = now(), updated_by = auth.uid()
  WHERE id = v_receipt_id;

  RETURN v_receipt_id;
END;
$$;

ALTER FUNCTION public.fn_save_payment_voucher(UUID, JSONB, JSONB)
  RENAME TO fn_save_payment_voucher_pre_opening_core;
REVOKE ALL ON FUNCTION public.fn_save_payment_voucher_pre_opening_core(UUID, JSONB, JSONB)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_save_payment_voucher(
  p_voucher_id UUID,
  p_header JSONB,
  p_lines JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_voucher_id UUID;
  v_company_id UUID := NULLIF(p_header->>'company_id', '')::UUID;
  v_supplier_id UUID := NULLIF(p_header->>'supplier_id', '')::UUID;
  v_voucher_date DATE := NULLIF(p_header->>'voucher_date', '')::DATE;
  v_regular_lines JSONB;
  v_line JSONB;
  v_opening_id UUID;
  v_original NUMERIC(15,2);
  v_other_applied NUMERIC(15,2);
  v_payment NUMERIC(15,2);
  v_ewt NUMERIC(15,2);
BEGIN
  IF jsonb_typeof(COALESCE(p_lines, '[]'::JSONB)) <> 'array' THEN
    RAISE EXCEPTION 'Payment-voucher lines must be a JSON array';
  END IF;

  SELECT COALESCE(jsonb_agg(value ORDER BY ord), '[]'::JSONB)
  INTO v_regular_lines
  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB))
       WITH ORDINALITY AS x(value, ord)
  WHERE NULLIF(value->>'opening_ap_line_id', '') IS NULL;

  FOR v_line IN
    SELECT value
    FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) AS x(value)
    WHERE NULLIF(value->>'opening_ap_line_id', '') IS NOT NULL
  LOOP
    v_opening_id := NULLIF(v_line->>'opening_ap_line_id', '')::UUID;
    v_payment := COALESCE(NULLIF(v_line->>'payment_amount', '')::NUMERIC, 0);
    v_ewt := COALESCE(NULLIF(v_line->>'ewt_amount', '')::NUMERIC, 0);

    IF COALESCE(NULLIF(v_line->>'line_type', ''), 'bill_application') <> 'bill_application'
       OR NULLIF(v_line->>'vendor_bill_id', '') IS NOT NULL THEN
      RAISE EXCEPTION 'An opening payable must be a bill application with no vendor-bill reference';
    END IF;
    IF v_payment + v_ewt <= 0 THEN CONTINUE; END IF;

    SELECT l.original_amount INTO v_original
    FROM public.opening_balance_ap_lines l
    JOIN public.opening_balance_batches b ON b.id = l.batch_id
    WHERE l.id = v_opening_id
      AND l.company_id = v_company_id
      AND l.supplier_id = v_supplier_id
      AND b.status = 'posted'
      AND b.cutover_date <= v_voucher_date
    FOR UPDATE OF l;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Opening payable does not belong to this posted company/supplier cut-over';
    END IF;

    SELECT COALESCE(sum(pvl.payment_amount + pvl.ewt_amount), 0)
    INTO v_other_applied
    FROM public.payment_voucher_lines pvl
    JOIN public.payment_vouchers pv ON pv.id = pvl.payment_voucher_id
    WHERE pvl.opening_ap_line_id = v_opening_id
      AND pv.status <> 'cancelled'
      AND pvl.payment_voucher_id <> COALESCE(p_voucher_id, '00000000-0000-0000-0000-000000000000'::UUID);
    IF v_payment + v_ewt > v_original - v_other_applied + 0.02 THEN
      RAISE EXCEPTION 'Payment application exceeds opening bill % outstanding balance', v_opening_id;
    END IF;

    PERFORM public.fn_validate_payment_voucher_line_ewt(
      v_company_id, v_payment, v_ewt,
      NULLIF(v_line->>'atc_code_id', '')::UUID,
      NULLIF(v_line->>'ewt_tax_base', '')::NUMERIC,
      NULLIF(v_line->>'ewt_variance_reason', ''), v_voucher_date
    );
  END LOOP;

  v_voucher_id := public.fn_save_payment_voucher_pre_opening_core(
    p_voucher_id, p_header, v_regular_lines
  );

  INSERT INTO public.payment_voucher_lines (
    payment_voucher_id, company_id, vendor_bill_id, opening_ap_line_id,
    line_type, payment_amount, ewt_amount, atc_code_id, ewt_tax_base,
    ewt_income_nature, ewt_variance_reason, created_by, updated_by
  )
  SELECT v_voucher_id, v_company_id, NULL, NULLIF(value->>'opening_ap_line_id', '')::UUID,
         'bill_application',
         COALESCE(NULLIF(value->>'payment_amount', '')::NUMERIC, 0),
         COALESCE(NULLIF(value->>'ewt_amount', '')::NUMERIC, 0),
         NULLIF(value->>'atc_code_id', '')::UUID,
         NULLIF(value->>'ewt_tax_base', '')::NUMERIC,
         NULLIF(value->>'ewt_income_nature', ''),
         NULLIF(value->>'ewt_variance_reason', ''), auth.uid(), auth.uid()
  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) AS x(value)
  WHERE NULLIF(value->>'opening_ap_line_id', '') IS NOT NULL
    AND (COALESCE(NULLIF(value->>'payment_amount', '')::NUMERIC, 0)
       + COALESCE(NULLIF(value->>'ewt_amount', '')::NUMERIC, 0)) > 0;

  UPDATE public.payment_vouchers SET
    total_amount = COALESCE((SELECT sum(payment_amount) FROM public.payment_voucher_lines WHERE payment_voucher_id = v_voucher_id), 0),
    total_ewt = COALESCE((SELECT sum(ewt_amount) FROM public.payment_voucher_lines WHERE payment_voucher_id = v_voucher_id), 0),
    updated_at = now(), updated_by = auth.uid()
  WHERE id = v_voucher_id;

  RETURN v_voucher_id;
END;
$$;

-- Posting rechecks every application while holding deterministic source locks.
-- Draft-time validation improves feedback; this function is the concurrency
-- boundary that makes two simultaneous settlements fail closed.
CREATE OR REPLACE FUNCTION public.fn_validate_settlement_posting(
  p_document_type TEXT,
  p_source_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT := upper(btrim(COALESCE(p_document_type, '')));
  v_company_id UUID;
  v_counterparty_id UUID;
  v_header_cash NUMERIC;
  v_header_tax NUMERIC;
  v_line_cash NUMERIC;
  v_line_tax NUMERIC;
  v_application RECORD;
  v_document_total NUMERIC;
  v_other_applied NUMERIC;
BEGIN
  IF v_type = 'OR' THEN
    SELECT company_id, customer_id, total_amount, total_cwt
    INTO v_company_id, v_counterparty_id, v_header_cash, v_header_tax
    FROM public.receipts WHERE id = p_source_id;

    SELECT COALESCE(sum(payment_amount), 0), COALESCE(sum(cwt_amount), 0)
    INTO v_line_cash, v_line_tax
    FROM public.receipt_lines WHERE receipt_id = p_source_id;

    IF EXISTS (
      SELECT 1 FROM public.receipt_lines
      WHERE receipt_id = p_source_id
        AND ((line_type = 'invoice_application'
              AND num_nonnulls(invoice_id, opening_ar_line_id) <> 1)
          OR (line_type = 'customer_advance'
              AND (invoice_id IS NOT NULL OR opening_ar_line_id IS NOT NULL)))
    ) THEN
      RAISE EXCEPTION 'Receipt line type and source reference are inconsistent';
    END IF;

    PERFORM 1 FROM public.sales_invoices si
    WHERE si.id IN (SELECT invoice_id FROM public.receipt_lines
      WHERE receipt_id = p_source_id AND invoice_id IS NOT NULL)
    ORDER BY si.id FOR UPDATE;
    PERFORM 1 FROM public.opening_balance_ar_lines l
    WHERE l.id IN (SELECT opening_ar_line_id FROM public.receipt_lines
      WHERE receipt_id = p_source_id AND opening_ar_line_id IS NOT NULL)
    ORDER BY l.id FOR UPDATE;

    IF EXISTS (
      SELECT 1 FROM public.receipt_lines rl
      JOIN public.sales_invoices si ON si.id = rl.invoice_id
      WHERE rl.receipt_id = p_source_id
        AND (rl.company_id IS DISTINCT FROM v_company_id
          OR si.company_id IS DISTINCT FROM v_company_id
          OR si.customer_id IS DISTINCT FROM v_counterparty_id)
    ) OR EXISTS (
      SELECT 1 FROM public.receipt_lines rl
      JOIN public.opening_balance_ar_lines l ON l.id = rl.opening_ar_line_id
      JOIN public.opening_balance_batches b ON b.id = l.batch_id
      WHERE rl.receipt_id = p_source_id
        AND (rl.company_id IS DISTINCT FROM v_company_id
          OR l.company_id IS DISTINCT FROM v_company_id
          OR l.customer_id IS DISTINCT FROM v_counterparty_id
          OR b.status <> 'posted')
    ) THEN
      RAISE EXCEPTION 'Receipt application belongs to another company/customer or inactive cut-over';
    END IF;

    FOR v_application IN
      SELECT invoice_id, sum(payment_amount + cwt_amount) AS applied
      FROM public.receipt_lines
      WHERE receipt_id = p_source_id AND invoice_id IS NOT NULL
      GROUP BY invoice_id
    LOOP
      SELECT total_amount INTO v_document_total
      FROM public.sales_invoices WHERE id = v_application.invoice_id;
      SELECT COALESCE(sum(rl.payment_amount + rl.cwt_amount), 0)
      INTO v_other_applied
      FROM public.receipt_lines rl JOIN public.receipts r ON r.id = rl.receipt_id
      WHERE rl.invoice_id = v_application.invoice_id
        AND rl.receipt_id <> p_source_id AND r.status = 'posted';
      IF v_application.applied + v_other_applied > v_document_total + 0.02 THEN
        RAISE EXCEPTION 'Receipt applications exceed invoice % outstanding balance', v_application.invoice_id;
      END IF;
    END LOOP;

    FOR v_application IN
      SELECT opening_ar_line_id, sum(payment_amount + cwt_amount) AS applied
      FROM public.receipt_lines
      WHERE receipt_id = p_source_id AND opening_ar_line_id IS NOT NULL
      GROUP BY opening_ar_line_id
    LOOP
      SELECT original_amount INTO v_document_total
      FROM public.opening_balance_ar_lines WHERE id = v_application.opening_ar_line_id;
      SELECT COALESCE(sum(rl.payment_amount + rl.cwt_amount), 0)
      INTO v_other_applied
      FROM public.receipt_lines rl JOIN public.receipts r ON r.id = rl.receipt_id
      WHERE rl.opening_ar_line_id = v_application.opening_ar_line_id
        AND rl.receipt_id <> p_source_id AND r.status = 'posted';
      IF v_application.applied + v_other_applied > v_document_total + 0.02 THEN
        RAISE EXCEPTION 'Receipt applications exceed opening invoice % outstanding balance',
          v_application.opening_ar_line_id;
      END IF;
    END LOOP;

  ELSIF v_type = 'PV' THEN
    SELECT company_id, supplier_id, total_amount, total_ewt
    INTO v_company_id, v_counterparty_id, v_header_cash, v_header_tax
    FROM public.payment_vouchers WHERE id = p_source_id;

    SELECT COALESCE(sum(payment_amount), 0), COALESCE(sum(ewt_amount), 0)
    INTO v_line_cash, v_line_tax
    FROM public.payment_voucher_lines WHERE payment_voucher_id = p_source_id;

    IF EXISTS (
      SELECT 1 FROM public.payment_voucher_lines
      WHERE payment_voucher_id = p_source_id
        AND ((line_type = 'bill_application'
              AND num_nonnulls(vendor_bill_id, opening_ap_line_id) <> 1)
          OR (line_type = 'supplier_down_payment'
              AND (vendor_bill_id IS NOT NULL OR opening_ap_line_id IS NOT NULL)))
    ) THEN
      RAISE EXCEPTION 'Payment-voucher line type and source reference are inconsistent';
    END IF;

    PERFORM 1 FROM public.vendor_bills vb
    WHERE vb.id IN (SELECT vendor_bill_id FROM public.payment_voucher_lines
      WHERE payment_voucher_id = p_source_id AND vendor_bill_id IS NOT NULL)
    ORDER BY vb.id FOR UPDATE;
    PERFORM 1 FROM public.opening_balance_ap_lines l
    WHERE l.id IN (SELECT opening_ap_line_id FROM public.payment_voucher_lines
      WHERE payment_voucher_id = p_source_id AND opening_ap_line_id IS NOT NULL)
    ORDER BY l.id FOR UPDATE;

    IF EXISTS (
      SELECT 1 FROM public.payment_voucher_lines pvl
      JOIN public.vendor_bills vb ON vb.id = pvl.vendor_bill_id
      WHERE pvl.payment_voucher_id = p_source_id
        AND (pvl.company_id IS DISTINCT FROM v_company_id
          OR vb.company_id IS DISTINCT FROM v_company_id
          OR vb.supplier_id IS DISTINCT FROM v_counterparty_id)
    ) OR EXISTS (
      SELECT 1 FROM public.payment_voucher_lines pvl
      JOIN public.opening_balance_ap_lines l ON l.id = pvl.opening_ap_line_id
      JOIN public.opening_balance_batches b ON b.id = l.batch_id
      WHERE pvl.payment_voucher_id = p_source_id
        AND (pvl.company_id IS DISTINCT FROM v_company_id
          OR l.company_id IS DISTINCT FROM v_company_id
          OR l.supplier_id IS DISTINCT FROM v_counterparty_id
          OR b.status <> 'posted')
    ) THEN
      RAISE EXCEPTION 'Payment-voucher application belongs to another company/supplier or inactive cut-over';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.payment_voucher_lines pvl
      WHERE pvl.payment_voucher_id = p_source_id
        AND pvl.vendor_bill_id IS NOT NULL
        AND public.fn_vendor_bill_has_accrued_ewt(pvl.vendor_bill_id)
        AND (COALESCE(pvl.ewt_amount, 0) > 0 OR pvl.atc_code_id IS NOT NULL OR pvl.ewt_tax_base IS NOT NULL)
    ) THEN
      RAISE EXCEPTION 'Payment voucher cannot withhold EWT for a vendor bill that already accrued EWT at source.';
    END IF;

    FOR v_application IN
      SELECT vendor_bill_id,
        sum(payment_amount + CASE WHEN public.fn_vendor_bill_has_accrued_ewt(vendor_bill_id)
          THEN 0 ELSE ewt_amount END) AS applied
      FROM public.payment_voucher_lines
      WHERE payment_voucher_id = p_source_id AND vendor_bill_id IS NOT NULL
      GROUP BY vendor_bill_id
    LOOP
      SELECT total_amount - public.fn_vendor_bill_accrued_ewt_amount(id)
      INTO v_document_total FROM public.vendor_bills WHERE id = v_application.vendor_bill_id;
      SELECT COALESCE(sum(pvl.payment_amount + CASE
        WHEN public.fn_vendor_bill_has_accrued_ewt(v_application.vendor_bill_id) THEN 0
        ELSE pvl.ewt_amount END), 0)
      INTO v_other_applied
      FROM public.payment_voucher_lines pvl
      JOIN public.payment_vouchers pv ON pv.id = pvl.payment_voucher_id
      WHERE pvl.vendor_bill_id = v_application.vendor_bill_id
        AND pvl.payment_voucher_id <> p_source_id AND pv.status = 'posted';
      IF v_application.applied + v_other_applied > v_document_total + 0.02 THEN
        RAISE EXCEPTION 'Payment-voucher applications exceed bill % outstanding balance',
          v_application.vendor_bill_id;
      END IF;
    END LOOP;

    FOR v_application IN
      SELECT opening_ap_line_id, sum(payment_amount + ewt_amount) AS applied
      FROM public.payment_voucher_lines
      WHERE payment_voucher_id = p_source_id AND opening_ap_line_id IS NOT NULL
      GROUP BY opening_ap_line_id
    LOOP
      SELECT original_amount INTO v_document_total
      FROM public.opening_balance_ap_lines WHERE id = v_application.opening_ap_line_id;
      SELECT COALESCE(sum(pvl.payment_amount + pvl.ewt_amount), 0)
      INTO v_other_applied
      FROM public.payment_voucher_lines pvl
      JOIN public.payment_vouchers pv ON pv.id = pvl.payment_voucher_id
      WHERE pvl.opening_ap_line_id = v_application.opening_ap_line_id
        AND pvl.payment_voucher_id <> p_source_id AND pv.status = 'posted';
      IF v_application.applied + v_other_applied > v_document_total + 0.02 THEN
        RAISE EXCEPTION 'Payment-voucher applications exceed opening bill % outstanding balance',
          v_application.opening_ap_line_id;
      END IF;
    END LOOP;
  ELSE
    RAISE EXCEPTION 'Unsupported settlement posting type %', v_type;
  END IF;

  IF v_header_cash IS NULL THEN
    RAISE EXCEPTION 'Posting source %.% does not exist', v_type, p_source_id;
  END IF;
  IF abs(v_header_cash - v_line_cash) > 0.02 THEN
    RAISE EXCEPTION '% header cash amount % does not match line amount %',
      v_type, v_header_cash, v_line_cash;
  END IF;
  IF abs(COALESCE(v_header_tax, 0) - v_line_tax) > 0.02 THEN
    RAISE EXCEPTION '% header withholding % does not match line withholding %',
      v_type, COALESCE(v_header_tax, 0), v_line_tax;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_save_receipt(UUID, JSONB, JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_save_payment_voucher(UUID, JSONB, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_save_receipt(UUID, JSONB, JSONB)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_save_payment_voucher(UUID, JSONB, JSONB)
  TO authenticated, service_role;

-- Opening AR/AP schedules participate in the existing aging and subsidiary
-- ledger surfaces without masquerading as sales or purchase transactions.
CREATE OR REPLACE FUNCTION public.fn_ar_aging_asof(
  p_company_id UUID,
  p_as_of DATE,
  p_customer_id UUID DEFAULT NULL
)
RETURNS TABLE (
  invoice_id UUID, si_number TEXT, invoice_date DATE, due_date DATE,
  customer_id UUID, customer_name TEXT, original_amount NUMERIC,
  balance_due NUMERIC, days_overdue INTEGER
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT si.id, si.si_number, si.date, si.due_date, si.customer_id,
         si.customer_name_snapshot, si.total_amount,
         (si.total_amount - COALESCE(pay.applied, 0) - COALESCE(cm.applied, 0))::NUMERIC(15,2),
         COALESCE(p_as_of - si.due_date, 0)
  FROM sales_invoices si
  LEFT JOIN LATERAL (
    SELECT SUM(rl.payment_amount + rl.cwt_amount) AS applied
    FROM receipt_lines rl JOIN receipts r ON r.id = rl.receipt_id
    WHERE rl.invoice_id = si.id AND r.status = 'posted' AND r.receipt_date <= p_as_of
  ) pay ON true
  LEFT JOIN LATERAL (
    SELECT SUM(c.total_amount) AS applied FROM credit_memos c
    WHERE c.invoice_id = si.id AND c.status = 'applied' AND c.cm_date <= p_as_of
  ) cm ON true
  WHERE is_company_member(p_company_id)
    AND si.company_id = p_company_id AND si.status = 'posted' AND si.date <= p_as_of
    AND (p_customer_id IS NULL OR si.customer_id = p_customer_id)
    AND (si.total_amount - COALESCE(pay.applied, 0) - COALESCE(cm.applied, 0)) > 0.005
  UNION ALL
  SELECT l.id, l.legacy_invoice_number, l.invoice_date, l.due_date,
         l.customer_id, c.registered_name, l.original_amount,
         (l.original_amount - COALESCE(pay.applied, 0))::NUMERIC(15,2),
         COALESCE(p_as_of - l.due_date, 0)
  FROM opening_balance_ar_lines l
  JOIN opening_balance_batches b ON b.id = l.batch_id
  JOIN customers c ON c.id = l.customer_id
  LEFT JOIN LATERAL (
    SELECT sum(rl.payment_amount + rl.cwt_amount) AS applied
    FROM receipt_lines rl JOIN receipts r ON r.id = rl.receipt_id
    WHERE rl.opening_ar_line_id = l.id AND r.status = 'posted' AND r.receipt_date <= p_as_of
  ) pay ON true
  WHERE is_company_member(p_company_id)
    AND l.company_id = p_company_id AND b.status = 'posted' AND b.cutover_date <= p_as_of
    AND (p_customer_id IS NULL OR l.customer_id = p_customer_id)
    AND l.original_amount - COALESCE(pay.applied, 0) > 0.005
  ORDER BY 6, 3, 2;
$$;

CREATE OR REPLACE FUNCTION public.fn_ap_aging_asof(
  p_company_id UUID,
  p_as_of DATE,
  p_supplier_id UUID DEFAULT NULL
)
RETURNS TABLE (
  bill_id UUID, bill_number TEXT, bill_date DATE, due_date DATE,
  supplier_id UUID, supplier_name TEXT, original_amount NUMERIC,
  balance_due NUMERIC, days_overdue INTEGER
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT vb.id, vb.bill_number, vb.bill_date, vb.due_date, vb.supplier_id,
         vb.supplier_name_snapshot, vb.total_amount,
         (vb.total_amount - COALESCE(accrued.ewt_amount, 0) - COALESCE(pay.applied, 0) - COALESCE(vc.applied, 0))::NUMERIC(15,2),
         COALESCE(p_as_of - vb.due_date, 0)
  FROM vendor_bills vb
  LEFT JOIN LATERAL (SELECT fn_vendor_bill_accrued_ewt_amount(vb.id) AS ewt_amount) accrued ON true
  LEFT JOIN LATERAL (
    SELECT SUM(pvl.payment_amount + CASE WHEN COALESCE(accrued.ewt_amount, 0) > 0 THEN 0 ELSE pvl.ewt_amount END) AS applied
    FROM payment_voucher_lines pvl JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
    WHERE pvl.vendor_bill_id = vb.id AND pv.status = 'posted' AND pv.voucher_date <= p_as_of
  ) pay ON true
  LEFT JOIN LATERAL (
    SELECT SUM(vca.applied_amount) AS applied
    FROM vendor_credit_applications vca JOIN vendor_credits c ON c.id = vca.vendor_credit_id
    WHERE vca.vendor_bill_id = vb.id AND vca.reversed_at IS NULL
      AND vca.applied_date <= p_as_of AND c.status IN ('open', 'applied')
  ) vc ON true
  WHERE is_company_member(p_company_id)
    AND vb.company_id = p_company_id AND vb.status = 'posted' AND vb.bill_date <= p_as_of
    AND (p_supplier_id IS NULL OR vb.supplier_id = p_supplier_id)
    AND (vb.total_amount - COALESCE(accrued.ewt_amount, 0) - COALESCE(pay.applied, 0) - COALESCE(vc.applied, 0)) > 0.005
  UNION ALL
  SELECT l.id, l.legacy_bill_number, l.bill_date, l.due_date,
         l.supplier_id, s.registered_name, l.original_amount,
         (l.original_amount - COALESCE(pay.applied, 0))::NUMERIC(15,2),
         COALESCE(p_as_of - l.due_date, 0)
  FROM opening_balance_ap_lines l
  JOIN opening_balance_batches b ON b.id = l.batch_id
  JOIN suppliers s ON s.id = l.supplier_id
  LEFT JOIN LATERAL (
    SELECT sum(pvl.payment_amount + pvl.ewt_amount) AS applied
    FROM payment_voucher_lines pvl JOIN payment_vouchers pv ON pv.id = pvl.payment_voucher_id
    WHERE pvl.opening_ap_line_id = l.id AND pv.status = 'posted' AND pv.voucher_date <= p_as_of
  ) pay ON true
  WHERE is_company_member(p_company_id)
    AND l.company_id = p_company_id AND b.status = 'posted' AND b.cutover_date <= p_as_of
    AND (p_supplier_id IS NULL OR l.supplier_id = p_supplier_id)
    AND l.original_amount - COALESCE(pay.applied, 0) > 0.005
  ORDER BY 6, 3, 2;
$$;

CREATE OR REPLACE VIEW public.vw_customer_ledger
WITH (security_invoker = true)
AS
SELECT si.company_id, si.customer_id, si.date AS transaction_date,
       'SI'::TEXT AS doc_type, si.si_number AS doc_number,
       COALESCE(si.memo, 'Sales Invoice') AS description,
       si.total_amount AS debit_amount, 0::NUMERIC AS credit_amount,
       si.created_at, 'SI'::TEXT AS source_doc_type, si.id AS source_doc_id
FROM public.sales_invoices si WHERE si.status = 'posted'
UNION ALL
SELECT r.company_id, r.customer_id, r.receipt_date, 'OR', r.receipt_number,
       COALESCE(r.remarks, 'Official Receipt'), 0::NUMERIC, r.total_amount + r.total_cwt,
       r.created_at, 'OR', r.id
FROM public.receipts r WHERE r.status = 'posted'
UNION ALL
SELECT cm.company_id, cm.customer_id, cm.cm_date, 'CM', cm.cm_number,
       COALESCE(cm.remarks, 'Credit Memo'), 0::NUMERIC, cm.total_amount,
       cm.created_at, 'CM', cm.id
FROM public.credit_memos cm WHERE cm.status IN ('approved', 'applied')
UNION ALL
SELECT dm.company_id, dm.customer_id, dm.dm_date, 'DM', dm.dm_number,
       COALESCE(dm.remarks, 'Debit Memo'), dm.total_amount, 0::NUMERIC,
       dm.created_at, 'DM', dm.id
FROM public.debit_memos dm WHERE dm.status IN ('approved', 'paid')
UNION ALL
SELECT l.company_id, l.customer_id, b.cutover_date, 'OPENING', l.legacy_invoice_number,
       COALESCE(l.memo, 'Opening accounts receivable'), l.original_amount, 0::NUMERIC,
       l.created_at, 'OPENING', l.id
FROM public.opening_balance_ar_lines l
JOIN public.opening_balance_batches b ON b.id = l.batch_id
WHERE b.status = 'posted';

CREATE OR REPLACE VIEW public.vw_supplier_ledger
WITH (security_invoker = true)
AS
SELECT vb.company_id, vb.supplier_id, vb.bill_date AS transaction_date,
       'vendor_bill'::TEXT AS document_type, vb.id AS document_id,
       vb.bill_number AS document_number, vb.supplier_invoice_number AS external_ref,
       vb.memo AS description, 0::NUMERIC AS debit_amount, vb.total_amount AS credit_amount,
       vb.created_at, 'VB'::TEXT AS source_doc_type, vb.id AS source_doc_id
FROM public.vendor_bills vb WHERE vb.status = 'posted'
UNION ALL
SELECT pv.company_id, pv.supplier_id, pv.voucher_date, 'payment_voucher', pv.id,
       pv.voucher_number, pv.reference_number, pv.remarks,
       pv.total_amount + pv.total_ewt, 0::NUMERIC, pv.created_at, 'PV', pv.id
FROM public.payment_vouchers pv WHERE pv.status = 'posted'
UNION ALL
SELECT vc.company_id, vc.supplier_id, vc.credit_date, 'vendor_credit', vc.id,
       vc.vc_number, vc.supplier_cm_no, vc.remarks,
       vc.total_amount, 0::NUMERIC, vc.created_at, 'VC', vc.id
FROM public.vendor_credits vc WHERE vc.status IN ('open', 'applied')
UNION ALL
SELECT l.company_id, l.supplier_id, b.cutover_date, 'opening_balance', l.id,
       l.legacy_bill_number, l.supplier_invoice_number,
       COALESCE(l.memo, 'Opening accounts payable'), 0::NUMERIC, l.original_amount,
       l.created_at, 'OPENING', l.id
FROM public.opening_balance_ap_lines l
JOIN public.opening_balance_batches b ON b.id = l.batch_id
WHERE b.status = 'posted';

GRANT SELECT ON public.vw_customer_ledger, public.vw_supplier_ledger TO authenticated;

REVOKE ALL ON FUNCTION public.fn_save_opening_balance(UUID, JSONB, JSONB, JSONB, JSONB, JSONB, JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_opening_balance_summary(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_post_opening_balance(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_reverse_opening_balance(UUID, DATE, TEXT) FROM PUBLIC, anon;
-- Trigger functions are invoked by PostgreSQL, never as client RPCs.
REVOKE ALL ON FUNCTION public.fn_guard_opening_balance_batch()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_guard_opening_balance_line()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_save_opening_balance(UUID, JSONB, JSONB, JSONB, JSONB, JSONB, JSONB)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_opening_balance_summary(UUID)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_post_opening_balance(UUID)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_reverse_opening_balance(UUID, DATE, TEXT)
  TO authenticated, service_role;

COMMENT ON TABLE public.opening_balance_batches IS
  'PAD-002 governed cut-over document. Posted rows are immutable; subledger control lines are derived by construction.';
COMMENT ON FUNCTION public.fn_post_opening_balance(UUID) IS
  'Posts one balanced entry_class=opening journal through the Accounting Kernel and materializes opening subledgers atomically.';
COMMENT ON FUNCTION public.fn_reverse_opening_balance(UUID, DATE, TEXT) IS
  'Reverses an untouched cut-over through the Accounting Kernel and creates equal-and-opposite inventory movements; operational activity blocks reversal.';
