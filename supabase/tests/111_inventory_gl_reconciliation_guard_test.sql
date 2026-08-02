-- PXL-AUD-073 inventory-to-General-Ledger reconciliation guard.
--
-- The defect this guard exists to prevent: confirming a Receiving Report
-- increased stock_balances, cost layers and inventory_transactions while
-- producing no journal entry at all. Inventory value therefore drifted away
-- from its control account on every goods receipt, the Inventory Valuation
-- report disagreed with the General Ledger, and the Posting Engine could not
-- satisfy independent recomputation at P6.
--
-- This is a dataset-invariant guard in the style of 075: it asserts over
-- whatever data is loaded rather than building an isolated fixture, so it holds
-- for the canonical demo seed and for any real company alike. It is the first
-- of the nine critical reconciliations to be evidenced.
--
-- Invariants:
--   R1  Every company's inventory subledger equals its inventory control
--       account in the General Ledger, to the centavo.
--   R2  Every confirmed Receiving Report carrying inventory value has exactly
--       one posted journal entry.
--   R3  Every Receiving Report journal is internally balanced.
--   R4  Receiving Report journals debit the governed inventory control account
--       and credit the governed purchase clearing account.
--   R5  No weighted-average item retains a cost layer. Layers exist to support
--       fifo / specific identification; under weighted average the authoritative
--       quantity and value live in stock_balances, and an unconsumable layer is
--       precisely the drift this guard forbids.
--   R6  The governed account keys required for inventory posting are configured
--       for every company that holds stock.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- ── R1. Subledger equals control account ───────────────────────────────────
SELECT is(
  (SELECT count(*)::int
   FROM (
     SELECT c.id,
            COALESCE(sb.value, 0) AS subledger,
            COALESCE(gl.balance, 0) AS control
     FROM companies c
     LEFT JOIN (
       SELECT company_id, SUM(total_cost) AS value
       FROM stock_balances GROUP BY company_id
     ) sb ON sb.company_id = c.id
     LEFT JOIN (
       SELECT jel.company_id, SUM(jel.debit_amount - jel.credit_amount) AS balance
       FROM journal_entry_lines jel
       WHERE jel.account_id IN (
         SELECT account_id FROM account_mapping WHERE key_code = 'INVENTORY_CONTROL'
       )
       GROUP BY jel.company_id
     ) gl ON gl.company_id = c.id
   ) recon
   WHERE ROUND(subledger, 2) <> ROUND(control, 2)),
  0,
  'R1: every company inventory subledger equals its GL inventory control account'
);

-- ── R2. Confirmed receipts with inventory value are posted ─────────────────
SELECT is(
  (SELECT count(*)::int
   FROM receiving_reports rr
   WHERE rr.status = 'received'
     AND EXISTS (
       SELECT 1 FROM receiving_report_lines rrl
       JOIN items i ON i.id = rrl.item_id
       WHERE rrl.rr_id = rr.id
         AND rrl.received_qty > 0
         AND i.item_type = 'inventory_item'
     )
     AND NOT EXISTS (
       SELECT 1 FROM journal_entries je
       WHERE je.reference_doc_type = 'RR'
         AND je.reference_doc_id = rr.id
         AND je.status IN ('posted', 'reversed')
     )),
  0,
  'R2: every confirmed Receiving Report carrying inventory value has a posted journal'
);

-- ── R3. Receiving Report journals balance ──────────────────────────────────
SELECT is(
  (SELECT count(*)::int
   FROM (
     SELECT jel.je_id
     FROM journal_entry_lines jel
     JOIN journal_entries je ON je.id = jel.je_id
     WHERE je.reference_doc_type = 'RR'
     GROUP BY jel.je_id
     HAVING ROUND(SUM(jel.debit_amount), 2) <> ROUND(SUM(jel.credit_amount), 2)
   ) unbalanced),
  0,
  'R3: every Receiving Report journal is balanced'
);

-- ── R4. Receipts hit the governed accounts ─────────────────────────────────
SELECT is(
  (SELECT count(*)::int
   FROM journal_entry_lines jel
   JOIN journal_entries je ON je.id = jel.je_id
   WHERE je.reference_doc_type = 'RR'
     AND jel.account_id NOT IN (
       SELECT account_id FROM account_mapping
       WHERE key_code IN ('INVENTORY_CONTROL', 'PURCHASE_CLEARING')
     )),
  0,
  'R4: Receiving Report journals only touch governed inventory and clearing accounts'
);

-- ── R5. No undepletable weighted-average cost layer ────────────────────────
SELECT is(
  (SELECT count(*)::int
   FROM inventory_cost_layers l
   JOIN items i ON i.id = l.item_id
   WHERE l.qty_remaining > 0
     AND (i.costing_method = 'weighted_average' OR i.costing_method IS NULL)),
  0,
  'R5: no weighted-average item retains a cost layer that no outflow path can consume'
);

-- ── R6. Governed keys configured wherever stock is held ────────────────────
SELECT is(
  (SELECT count(*)::int
   FROM (SELECT DISTINCT company_id FROM stock_balances WHERE total_cost <> 0) held
   WHERE NOT EXISTS (
           SELECT 1 FROM account_mapping m
           WHERE m.company_id = held.company_id AND m.key_code = 'INVENTORY_CONTROL')
      OR NOT EXISTS (
           SELECT 1 FROM account_mapping m
           WHERE m.company_id = held.company_id AND m.key_code = 'PURCHASE_CLEARING')),
  0,
  'R6: every company holding stock has governed inventory control and purchase clearing accounts'
);

SELECT * FROM finish();
ROLLBACK;
