-- PXL-DA-008 / PXL-AUD-014: make operational VAT amounts server-authoritative.
--
-- Every shipped UI mutation for these document families already uses a
-- SECURITY DEFINER save/lifecycle RPC. Those RPCs derive line net/VAT/total
-- amounts from quantity, price, discount, VAT classification, and the rate in
-- tax_codes; they also rebuild the header totals. Legacy table grants and RLS
-- write policies nevertheless allowed an authenticated PostgREST caller to
-- bypass the RPCs and submit arbitrary VAT amounts for a VAT-registered
-- company. The registration triggers reject wrong-direction/inactive codes and
-- non-VAT-company VAT, but deliberately do not duplicate the amount engine.
--
-- Close that second mutation path. Reads remain RLS-scoped; all writes now go
-- through the existing public RPC contracts. service_role retains its normal
-- administrative access, while application callers cannot create, alter,
-- delete, or truncate accounting source evidence directly.
--
-- The two simple register views are automatically updatable. They previously
-- inherited blanket application write grants and ran with their postgres
-- owner's RLS posture, creating both a mutation bypass and a cross-company
-- read bypass. Make them security-invoker views and read-only to the app too.

DO $$
DECLARE
  v_policy RECORD;
BEGIN
  FOR v_policy IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = ANY (ARRAY[
        'sales_invoices', 'sales_invoice_lines',
        'vendor_bills', 'vendor_bill_lines',
        'credit_memos', 'credit_memo_lines',
        'debit_memos', 'debit_memo_lines',
        'cash_purchases', 'cash_purchase_lines',
        'vendor_credits', 'vendor_credit_lines'
      ])
      AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
  LOOP
    EXECUTE format(
      'DROP POLICY %I ON %I.%I',
      v_policy.policyname,
      v_policy.schemaname,
      v_policy.tablename
    );
  END LOOP;
END;
$$;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE
ON TABLE
  sales_invoices,
  sales_invoice_lines,
  vendor_bills,
  vendor_bill_lines,
  credit_memos,
  credit_memo_lines,
  debit_memos,
  debit_memo_lines,
  cash_purchases,
  cash_purchase_lines,
  vendor_credits,
  vendor_credit_lines
FROM PUBLIC, anon, authenticated;

ALTER VIEW vw_sales_invoice_register SET (security_invoker = true);
ALTER VIEW vw_vendor_bill_register SET (security_invoker = true);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE
ON TABLE
  vw_sales_invoice_register,
  vw_vendor_bill_register
FROM PUBLIC, anon, authenticated;
