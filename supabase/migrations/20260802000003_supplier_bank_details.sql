-- =============================================================================
-- Delivery Plan Phase 3 — supplier bank details and validated PV payee snapshots
-- =============================================================================

CREATE TABLE public.supplier_bank_accounts (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID NOT NULL REFERENCES public.companies(id),
  supplier_id         UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
  bank_id             UUID NOT NULL REFERENCES public.ref_banks(id),
  account_name        TEXT NOT NULL CHECK (NULLIF(btrim(account_name), '') IS NOT NULL),
  account_number      TEXT NOT NULL CHECK (
                        char_length(btrim(account_number)) BETWEEN 4 AND 34
                        AND account_number ~ '^[A-Za-z0-9 -]+$'
                      ),
  account_type        TEXT NOT NULL DEFAULT 'checking'
                      CHECK (account_type IN ('checking', 'savings')),
  bank_branch         TEXT,
  swift_code          TEXT,
  is_default          BOOLEAN NOT NULL DEFAULT false,
  is_active           BOOLEAN NOT NULL DEFAULT true,
  verification_status TEXT NOT NULL DEFAULT 'unverified'
                      CHECK (verification_status IN ('unverified', 'verified', 'rejected')),
  verified_by         UUID REFERENCES auth.users(id),
  verified_at         TIMESTAMPTZ,
  notes               TEXT,
  created_by          UUID REFERENCES auth.users(id),
  updated_by          UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (supplier_id, bank_id, account_number),
  CHECK (
    (verification_status = 'verified' AND verified_by IS NOT NULL AND verified_at IS NOT NULL)
    OR (verification_status <> 'verified' AND verified_by IS NULL AND verified_at IS NULL)
  )
);

CREATE UNIQUE INDEX supplier_bank_accounts_one_default
  ON public.supplier_bank_accounts(supplier_id)
  WHERE is_default AND is_active;
CREATE INDEX supplier_bank_accounts_company_supplier
  ON public.supplier_bank_accounts(company_id, supplier_id, is_active);

ALTER TABLE public.supplier_bank_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY supplier_bank_accounts_read ON public.supplier_bank_accounts
  FOR SELECT TO authenticated
  USING (fn_can_master_data_permission(company_id, 'suppliers', 'view'));
CREATE POLICY supplier_bank_accounts_insert ON public.supplier_bank_accounts
  FOR INSERT TO authenticated
  WITH CHECK (fn_can_master_data_permission(company_id, 'suppliers', 'create'));
CREATE POLICY supplier_bank_accounts_update ON public.supplier_bank_accounts
  FOR UPDATE TO authenticated
  USING (fn_can_master_data_permission(company_id, 'suppliers', 'edit'))
  WITH CHECK (fn_can_master_data_permission(company_id, 'suppliers', 'edit'));
CREATE POLICY supplier_bank_accounts_delete ON public.supplier_bank_accounts
  FOR DELETE TO authenticated
  USING (fn_can_master_data_permission(company_id, 'suppliers', 'delete'));

REVOKE ALL ON TABLE public.supplier_bank_accounts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.supplier_bank_accounts TO authenticated;
GRANT ALL ON TABLE public.supplier_bank_accounts TO service_role;

CREATE OR REPLACE FUNCTION public.fn_guard_supplier_bank_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supplier_company UUID;
  v_bank_active BOOLEAN;
BEGIN
  SELECT company_id INTO v_supplier_company
  FROM public.suppliers WHERE id = NEW.supplier_id;
  IF v_supplier_company IS NULL OR v_supplier_company <> NEW.company_id THEN
    RAISE EXCEPTION 'Supplier bank account must belong to the supplier company';
  END IF;

  SELECT is_active INTO v_bank_active FROM public.ref_banks WHERE id = NEW.bank_id;
  IF NOT COALESCE(v_bank_active, false) THEN
    RAISE EXCEPTION 'Supplier bank account must reference an active bank';
  END IF;

  NEW.account_name := btrim(NEW.account_name);
  NEW.account_number := regexp_replace(btrim(NEW.account_number), '\\s+', ' ', 'g');
  NEW.bank_branch := NULLIF(btrim(NEW.bank_branch), '');
  NEW.swift_code := upper(NULLIF(btrim(NEW.swift_code), ''));
  NEW.updated_by := auth.uid();

  IF NEW.verification_status = 'verified'
     AND (TG_OP = 'INSERT' OR OLD.verification_status <> 'verified') THEN
    NEW.verified_by := auth.uid();
    NEW.verified_at := now();
  ELSIF NEW.verification_status <> 'verified' THEN
    NEW.verified_by := NULL;
    NEW.verified_at := NULL;
  ELSIF OLD.account_name IS DISTINCT FROM NEW.account_name
        OR OLD.account_number IS DISTINCT FROM NEW.account_number
        OR OLD.bank_id IS DISTINCT FROM NEW.bank_id THEN
    NEW.verification_status := 'unverified';
    NEW.verified_by := NULL;
    NEW.verified_at := NULL;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_supplier_bank_account_guard
  BEFORE INSERT OR UPDATE ON public.supplier_bank_accounts
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_supplier_bank_account();
CREATE TRIGGER trg_supplier_bank_account_updated_at
  BEFORE UPDATE ON public.supplier_bank_accounts
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();
CREATE TRIGGER trg_audit_supplier_bank_accounts
  AFTER INSERT OR UPDATE OR DELETE ON public.supplier_bank_accounts
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

ALTER TABLE public.payment_vouchers
  ADD COLUMN supplier_bank_account_id UUID REFERENCES public.supplier_bank_accounts(id),
  ADD COLUMN payee_bank_name_snapshot TEXT,
  ADD COLUMN payee_account_name_snapshot TEXT,
  ADD COLUMN payee_account_number_snapshot TEXT,
  ADD COLUMN payee_bank_branch_snapshot TEXT,
  ADD COLUMN payee_swift_snapshot TEXT;

ALTER FUNCTION public.fn_save_payment_voucher(UUID, JSONB, JSONB)
  RENAME TO fn_save_payment_voucher_phase3_core;
REVOKE ALL ON FUNCTION public.fn_save_payment_voucher_phase3_core(UUID, JSONB, JSONB)
  FROM PUBLIC, anon, authenticated;

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
  v_id UUID;
  v_company_id UUID := NULLIF(p_header->>'company_id', '')::UUID;
  v_supplier_id UUID := NULLIF(p_header->>'supplier_id', '')::UUID;
  v_supplier_bank_id UUID := NULLIF(p_header->>'supplier_bank_account_id', '')::UUID;
  v_bank_name TEXT;
  v_account_name TEXT;
  v_account_number TEXT;
  v_bank_branch TEXT;
  v_effective_swift TEXT;
BEGIN
  IF v_supplier_bank_id IS NOT NULL THEN
    SELECT rb.bank_name, sba.account_name, sba.account_number, sba.bank_branch,
           COALESCE(sba.swift_code, rb.swift_code)
    INTO v_bank_name, v_account_name, v_account_number, v_bank_branch, v_effective_swift
    FROM public.supplier_bank_accounts sba
    JOIN public.ref_banks rb ON rb.id = sba.bank_id
    WHERE sba.id = v_supplier_bank_id
      AND sba.company_id = v_company_id
      AND sba.supplier_id = v_supplier_id
      AND sba.is_active;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Selected payee bank account is inactive or does not belong to this supplier and company';
    END IF;
  END IF;

  v_id := public.fn_save_payment_voucher_phase3_core(p_voucher_id, p_header, p_lines);

  UPDATE public.payment_vouchers SET
    supplier_bank_account_id = v_supplier_bank_id,
    payee_bank_name_snapshot = v_bank_name,
    payee_account_name_snapshot = v_account_name,
    payee_account_number_snapshot = v_account_number,
    payee_bank_branch_snapshot = v_bank_branch,
    payee_swift_snapshot = v_effective_swift,
    updated_by = auth.uid(), updated_at = now()
  WHERE id = v_id AND status = 'draft';

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_payment_voucher_payee_bank()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bank RECORD;
  v_payment_mode_code TEXT;
BEGIN
  IF NEW.status <> 'posted' OR OLD.status = 'posted' THEN
    RETURN NEW;
  END IF;

  SELECT code INTO v_payment_mode_code
  FROM public.ref_payment_modes
  WHERE id = NEW.payment_mode_id;
  IF v_payment_mode_code = 'BANK_XFER' AND NEW.supplier_bank_account_id IS NULL THEN
    RAISE EXCEPTION 'A verified supplier bank account is required for bank-transfer vouchers';
  END IF;
  IF NEW.supplier_bank_account_id IS NULL THEN RETURN NEW; END IF;

  SELECT sba.*, rb.bank_name, COALESCE(sba.swift_code, rb.swift_code) effective_swift
  INTO v_bank
  FROM public.supplier_bank_accounts sba
  JOIN public.ref_banks rb ON rb.id = sba.bank_id
  WHERE sba.id = NEW.supplier_bank_account_id
    AND sba.company_id = NEW.company_id
    AND sba.supplier_id = NEW.supplier_id
    AND sba.is_active;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Selected payee bank account is inactive or does not belong to this supplier and company';
  END IF;
  IF v_bank.verification_status <> 'verified' THEN
    RAISE EXCEPTION 'Selected payee bank account must be verified before posting the payment voucher';
  END IF;
  IF NEW.payee_bank_name_snapshot IS DISTINCT FROM v_bank.bank_name
     OR NEW.payee_account_name_snapshot IS DISTINCT FROM v_bank.account_name
     OR NEW.payee_account_number_snapshot IS DISTINCT FROM v_bank.account_number
     OR NEW.payee_bank_branch_snapshot IS DISTINCT FROM v_bank.bank_branch
     OR NEW.payee_swift_snapshot IS DISTINCT FROM v_bank.effective_swift THEN
    RAISE EXCEPTION 'Payee bank details changed after the voucher was saved; save the draft again before posting';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_payment_voucher_payee_bank
  BEFORE UPDATE OF status ON public.payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION public.fn_validate_payment_voucher_payee_bank();

REVOKE ALL ON FUNCTION public.fn_save_payment_voucher(UUID, JSONB, JSONB)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_save_payment_voucher(UUID, JSONB, JSONB)
  TO authenticated, service_role;

-- Trigger functions are invoked by PostgreSQL, never as client RPCs.
REVOKE ALL ON FUNCTION public.fn_guard_supplier_bank_account()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fn_validate_payment_voucher_payee_bank()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.supplier_bank_accounts IS
  'Company-scoped supplier payment instructions. Verification is explicit; payment vouchers retain immutable payee snapshots.';
COMMENT ON COLUMN public.payment_vouchers.supplier_bank_account_id IS
  'Validated supplier payment instruction selected for this voucher; payee fields are historical snapshots.';
