-- PXL-AUD-046: make receipt header totals line-authoritative for cash.
--
-- receipts.total_amount must mean actual cash received for both standard ORs
-- and cash-sale ORs. Cash-sale receipts previously stored gross invoice amount
-- in the header while receipt_lines.payment_amount and the JE cash line stored
-- the net cash amount.

CREATE OR REPLACE FUNCTION fn_sync_receipt_totals_from_lines()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_receipt_id UUID;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.receipt_id IS DISTINCT FROM NEW.receipt_id THEN
    WITH totals AS (
      SELECT
        COALESCE(ROUND(SUM(payment_amount), 2), 0)::NUMERIC(15,2) AS total_amount,
        COALESCE(ROUND(SUM(cwt_amount), 2), 0)::NUMERIC(15,2) AS total_cwt
      FROM receipt_lines
      WHERE receipt_id = OLD.receipt_id
    )
    UPDATE receipts r
    SET total_amount = totals.total_amount,
        total_cwt = totals.total_cwt,
        updated_at = NOW(),
        updated_by = COALESCE(auth.uid(), r.updated_by)
    FROM totals
    WHERE r.id = OLD.receipt_id
      AND r.status = 'draft';
  END IF;

  v_receipt_id := COALESCE(NEW.receipt_id, OLD.receipt_id);

  WITH totals AS (
    SELECT
      COALESCE(ROUND(SUM(payment_amount), 2), 0)::NUMERIC(15,2) AS total_amount,
      COALESCE(ROUND(SUM(cwt_amount), 2), 0)::NUMERIC(15,2) AS total_cwt
    FROM receipt_lines
    WHERE receipt_id = v_receipt_id
  )
  UPDATE receipts r
  SET total_amount = totals.total_amount,
      total_cwt = totals.total_cwt,
      updated_at = NOW(),
      updated_by = COALESCE(auth.uid(), r.updated_by)
  FROM totals
  WHERE r.id = v_receipt_id
    AND r.status = 'draft';

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_receipt_totals_from_lines ON receipt_lines;
CREATE TRIGGER trg_sync_receipt_totals_from_lines
AFTER INSERT OR UPDATE OF receipt_id, payment_amount, cwt_amount OR DELETE
ON receipt_lines
FOR EACH ROW
EXECUTE FUNCTION fn_sync_receipt_totals_from_lines();

-- Repair existing posted cash-sale receipts: header cash amount and CWT must
-- match the line applications, while total_amount + total_cwt remains the
-- gross amount cleared from AR.
WITH cash_sale_receipt_totals AS (
  SELECT
    rl.receipt_id,
    COALESCE(ROUND(SUM(rl.payment_amount), 2), 0)::NUMERIC(15,2) AS total_amount,
    COALESCE(ROUND(SUM(rl.cwt_amount), 2), 0)::NUMERIC(15,2) AS total_cwt
  FROM receipt_lines rl
  JOIN sales_invoices si ON si.id = rl.invoice_id
  WHERE si.is_cash_sale = true
  GROUP BY rl.receipt_id
)
UPDATE receipts r
SET total_amount = t.total_amount,
    total_cwt = t.total_cwt,
    updated_at = NOW()
FROM cash_sale_receipt_totals t
WHERE r.id = t.receipt_id
  AND (r.total_amount IS DISTINCT FROM t.total_amount
       OR r.total_cwt IS DISTINCT FROM t.total_cwt);

REVOKE ALL ON FUNCTION fn_sync_receipt_totals_from_lines() FROM PUBLIC, anon, authenticated;
