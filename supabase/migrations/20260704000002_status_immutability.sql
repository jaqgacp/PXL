-- ============================================================================
-- PXL-DA-011: Status-aware immutability on every transactional header/line
-- table.
--
-- Extends the PXL-AUD-005 pattern (SI/OR/VB/PV line guards, which remain in
-- place unchanged) to all remaining transactional documents with two generic
-- SECURITY DEFINER trigger functions:
--
--   fn_guard_doc_lines(parent_table, fk_col, status_col, editable_csv[, flag])
--     Blocks INSERT/UPDATE/DELETE on a line table unless the parent document
--     status is in the editable set. Optional 'same_txn' flag permits
--     mutations when the parent row was created/last written by the current
--     transaction — required for journal_entry_lines because every posting
--     writer inserts the JE header as 'posted' and then its lines in the
--     same transaction.
--
--   fn_guard_doc_header(status_col, editable_csv, extras_csv, frozen_csv[, flag])
--     On UPDATE of a document whose status is outside the editable set, only
--     the status column, updated_at/updated_by, and the per-table extras
--     (controlled lifecycle metadata: posting stamps, JE linkage, void
--     reason, release/clear dates, application progress) may change; every
--     business column is immutable. Unchanged full-payload re-saves are
--     tolerated because only genuinely changed columns are checked.
--     Statuses in the frozen set allow no changes at all beyond
--     updated_at/updated_by (posted schedule entries). DELETE outside the
--     editable set is always blocked (DEC-002: reverse or void, never
--     delete).
--
-- Status transitions themselves remain governed by the DEC-009 role
-- lifecycle triggers and DEC-010 approval SoD triggers; these guards make
-- the surviving row content immutable regardless of role.
--
-- NOTE for future migrations: data backfills that must rewrite non-draft
-- documents or their lines need `SET session_replication_role = replica`
-- (or ALTER TABLE ... DISABLE TRIGGER) around the backfill, as these guards
-- fire for superuser too.
-- ============================================================================

-- A visible row whose xmin transaction is still in progress can only have
-- been written by the current transaction (or one of its subtransactions —
-- plpgsql EXCEPTION blocks and pgTAP assertions run in subtransactions, so
-- a plain xmin = txid_current() comparison is not enough): PostgreSQL never
-- exposes another transaction's uncommitted rows.
CREATE OR REPLACE FUNCTION fn_row_written_by_current_txn(p_xmin_raw BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_cur  BIGINT := txid_current();
  v_cand BIGINT;
BEGIN
  IF p_xmin_raw IS NULL OR p_xmin_raw < 3 THEN
    RETURN FALSE;  -- bootstrap/frozen xids are never ours
  END IF;
  -- Subtransaction xids are assigned after their parent, so the raw xmin
  -- may be numerically greater than txid_current(); extend it with the
  -- current epoch as-is. A raw xmin actually written in a previous epoch
  -- yields a candidate beyond the next assignable xid, which makes
  -- txid_status raise — handled below as "not ours".
  v_cand := ((v_cur >> 32) << 32) | p_xmin_raw;
  RETURN COALESCE(txid_status(v_cand) = 'in progress', FALSE);
EXCEPTION WHEN OTHERS THEN
  RETURN FALSE;  -- xid too old or from a previous epoch: definitely not ours
END;
$$;

COMMENT ON FUNCTION fn_row_written_by_current_txn(BIGINT) IS
  'True when a visible row''s raw xmin belongs to the current (sub)transaction. Used by the PXL-DA-011 immutability guards for same-transaction exceptions.';

CREATE OR REPLACE FUNCTION fn_guard_doc_lines()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_table TEXT   := TG_ARGV[0];
  v_fk_col       TEXT   := TG_ARGV[1];
  v_status_col   TEXT   := TG_ARGV[2];
  v_editable     TEXT[] := string_to_array(TG_ARGV[3], ',');
  v_same_txn_ok  BOOLEAN := TG_NARGS > 4 AND TG_ARGV[4] = 'same_txn';
  v_ids          UUID[];
  v_id           UUID;
  v_status       TEXT;
  v_xmin         BIGINT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_ids := ARRAY[(to_jsonb(NEW)->>v_fk_col)::UUID];
  ELSIF TG_OP = 'DELETE' THEN
    v_ids := ARRAY[(to_jsonb(OLD)->>v_fk_col)::UUID];
  ELSE
    v_ids := ARRAY[(to_jsonb(OLD)->>v_fk_col)::UUID];
    IF to_jsonb(NEW)->>v_fk_col IS DISTINCT FROM to_jsonb(OLD)->>v_fk_col THEN
      v_ids := v_ids || (to_jsonb(NEW)->>v_fk_col)::UUID;
    END IF;
  END IF;

  FOREACH v_id IN ARRAY v_ids LOOP
    IF v_id IS NULL THEN
      RAISE EXCEPTION '% rows must reference a parent document (% is null).',
        TG_TABLE_NAME, v_fk_col;
    END IF;

    EXECUTE format('SELECT %I::text, xmin::text::bigint FROM %I WHERE id = $1',
                   v_status_col, v_parent_table)
      INTO v_status, v_xmin USING v_id;

    IF v_status IS NULL THEN
      RAISE EXCEPTION 'Parent % row % not found for % mutation.',
        v_parent_table, v_id, TG_TABLE_NAME;
    END IF;

    IF v_status = ANY (v_editable) THEN
      CONTINUE;
    END IF;

    IF v_same_txn_ok AND fn_row_written_by_current_txn(v_xmin) THEN
      CONTINUE;
    END IF;

    RAISE EXCEPTION '% cannot be changed: parent % % is "%" (line changes allowed only in: %).',
      TG_TABLE_NAME, v_parent_table, v_id, v_status, array_to_string(v_editable, ', ');
  END LOOP;

  RETURN COALESCE(NEW, OLD);
END;
$$;

COMMENT ON FUNCTION fn_guard_doc_lines() IS
  'Generic status-aware line immutability guard (PXL-DA-011). Args: parent table, FK column, parent status column, CSV of editable statuses, optional same_txn flag.';

CREATE OR REPLACE FUNCTION fn_guard_doc_header()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status_col  TEXT   := TG_ARGV[0];
  v_editable    TEXT[] := string_to_array(TG_ARGV[1], ',');
  v_extra       TEXT[] := CASE WHEN TG_NARGS > 2 AND TG_ARGV[2] <> ''
                               THEN string_to_array(TG_ARGV[2], ',')
                               ELSE ARRAY[]::TEXT[] END;
  v_frozen      TEXT[] := CASE WHEN TG_NARGS > 3 AND TG_ARGV[3] <> ''
                               THEN string_to_array(TG_ARGV[3], ',')
                               ELSE ARRAY[]::TEXT[] END;
  v_same_txn_ok BOOLEAN := TG_NARGS > 4 AND TG_ARGV[4] = 'same_txn';
  v_old         JSONB;
  v_new         JSONB;
  v_old_status  TEXT;
  v_allowed     TEXT[];
  v_offending   TEXT[];
  v_xmin        BIGINT;
BEGIN
  v_old := to_jsonb(OLD);
  v_old_status := v_old->>v_status_col;

  IF v_old_status = ANY (v_editable) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_same_txn_ok THEN
    EXECUTE format('SELECT xmin::text::bigint FROM %I WHERE id = $1', TG_TABLE_NAME)
      INTO v_xmin USING OLD.id;
    IF fn_row_written_by_current_txn(v_xmin) THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '% % cannot be deleted in status "%" (deletable only in: %); void or reverse instead.',
      TG_TABLE_NAME, OLD.id, v_old_status, array_to_string(v_editable, ', ');
  END IF;

  IF v_old_status = ANY (v_frozen) THEN
    v_allowed := ARRAY['updated_at', 'updated_by'];
  ELSE
    v_allowed := ARRAY[v_status_col, 'updated_at', 'updated_by'] || v_extra;
  END IF;

  v_new := to_jsonb(NEW);
  v_offending := ARRAY(
    SELECT k FROM jsonb_object_keys(v_old) AS k
    WHERE v_old->k IS DISTINCT FROM v_new->k
      AND k <> ALL (v_allowed)
  );

  IF array_length(v_offending, 1) IS NOT NULL THEN
    RAISE EXCEPTION '% % is "%" and immutable: column(s) [%] cannot change (allowed: %).',
      TG_TABLE_NAME, OLD.id, v_old_status,
      array_to_string(v_offending, ', '), array_to_string(v_allowed, ', ');
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_guard_doc_header() IS
  'Generic status-aware header immutability guard (PXL-DA-011). Args: status column, CSV editable statuses, CSV extra allowed columns when locked, CSV frozen statuses, optional same_txn flag.';

-- ============================================================================
-- Line guards. SI/OR/VB/PV line tables keep their dedicated PXL-AUD-005
-- triggers; everything else uses the generic guard.
-- ============================================================================

DROP TRIGGER IF EXISTS trg_guard_lines_sales_quotation_lines ON sales_quotation_lines;
CREATE TRIGGER trg_guard_lines_sales_quotation_lines
  BEFORE INSERT OR UPDATE OR DELETE ON sales_quotation_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('sales_quotations', 'quotation_id', 'status', 'draft,pending', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_sales_order_lines ON sales_order_lines;
CREATE TRIGGER trg_guard_lines_sales_order_lines
  BEFORE INSERT OR UPDATE OR DELETE ON sales_order_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('sales_orders', 'sales_order_id', 'approval_status', 'pending', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_delivery_receipt_lines ON delivery_receipt_lines;
CREATE TRIGGER trg_guard_lines_delivery_receipt_lines
  BEFORE INSERT OR UPDATE OR DELETE ON delivery_receipt_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('delivery_receipts', 'dr_id', 'status', 'draft,in_transit', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_credit_memo_lines ON credit_memo_lines;
CREATE TRIGGER trg_guard_lines_credit_memo_lines
  BEFORE INSERT OR UPDATE OR DELETE ON credit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('credit_memos', 'credit_memo_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_debit_memo_lines ON debit_memo_lines;
CREATE TRIGGER trg_guard_lines_debit_memo_lines
  BEFORE INSERT OR UPDATE OR DELETE ON debit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('debit_memos', 'debit_memo_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_cash_purchase_lines ON cash_purchase_lines;
CREATE TRIGGER trg_guard_lines_cash_purchase_lines
  BEFORE INSERT OR UPDATE OR DELETE ON cash_purchase_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('cash_purchases', 'cp_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_check_voucher_lines ON check_voucher_lines;
CREATE TRIGGER trg_guard_lines_check_voucher_lines
  BEFORE INSERT OR UPDATE OR DELETE ON check_voucher_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('check_vouchers', 'cv_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_purchase_order_lines ON purchase_order_lines;
CREATE TRIGGER trg_guard_lines_purchase_order_lines
  BEFORE INSERT OR UPDATE OR DELETE ON purchase_order_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('purchase_orders', 'po_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_purchase_return_lines ON purchase_return_lines;
CREATE TRIGGER trg_guard_lines_purchase_return_lines
  BEFORE INSERT OR UPDATE OR DELETE ON purchase_return_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('purchase_returns', 'return_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_receiving_report_lines ON receiving_report_lines;
CREATE TRIGGER trg_guard_lines_receiving_report_lines
  BEFORE INSERT OR UPDATE OR DELETE ON receiving_report_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('receiving_reports', 'rr_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_supplier_debit_memo_lines ON supplier_debit_memo_lines;
CREATE TRIGGER trg_guard_lines_supplier_debit_memo_lines
  BEFORE INSERT OR UPDATE OR DELETE ON supplier_debit_memo_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('supplier_debit_memos', 'sdm_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_vendor_credit_lines ON vendor_credit_lines;
CREATE TRIGGER trg_guard_lines_vendor_credit_lines
  BEFORE INSERT OR UPDATE OR DELETE ON vendor_credit_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('vendor_credits', 'vc_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_stock_adjustment_lines ON stock_adjustment_lines;
CREATE TRIGGER trg_guard_lines_stock_adjustment_lines
  BEFORE INSERT OR UPDATE OR DELETE ON stock_adjustment_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('stock_adjustments', 'adjustment_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_stock_transfer_lines ON stock_transfer_lines;
CREATE TRIGGER trg_guard_lines_stock_transfer_lines
  BEFORE INSERT OR UPDATE OR DELETE ON stock_transfer_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('stock_transfers', 'transfer_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_goods_issue_lines ON goods_issue_lines;
CREATE TRIGGER trg_guard_lines_goods_issue_lines
  BEFORE INSERT OR UPDATE OR DELETE ON goods_issue_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('goods_issues', 'issue_id', 'status', 'draft', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_physical_count_sheet_lines ON physical_count_sheet_lines;
CREATE TRIGGER trg_guard_lines_physical_count_sheet_lines
  BEFORE INSERT OR UPDATE OR DELETE ON physical_count_sheet_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('physical_count_sheets', 'count_sheet_id', 'status', 'draft,counting,variance_review', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_lines_bank_recon_items ON bank_recon_items;
CREATE TRIGGER trg_guard_lines_bank_recon_items
  BEFORE INSERT OR UPDATE OR DELETE ON bank_recon_items
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('bank_reconciliations', 'reconciliation_id', 'status', 'draft', 'same_txn');

-- Journal entry lines: every posting writer inserts the JE header as
-- 'posted' and then its lines within the same transaction, so the guard
-- carries the same_txn exception. Post-hoc tampering from a different
-- transaction is blocked for any non-draft JE.
DROP TRIGGER IF EXISTS trg_guard_lines_journal_entry_lines ON journal_entry_lines;
CREATE TRIGGER trg_guard_lines_journal_entry_lines
  BEFORE INSERT OR UPDATE OR DELETE ON journal_entry_lines
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_lines('journal_entries', 'je_id', 'status', 'draft', 'same_txn');

-- ============================================================================
-- Header guards.
-- ============================================================================

DROP TRIGGER IF EXISTS trg_guard_header_sales_invoices ON sales_invoices;
CREATE TRIGGER trg_guard_header_sales_invoices
  BEFORE UPDATE OR DELETE ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,approved_by,approved_at,void_reason_id,memo', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_vendor_bills ON vendor_bills;
CREATE TRIGGER trg_guard_header_vendor_bills
  BEFORE UPDATE OR DELETE ON vendor_bills
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,approved_by,approved_at,void_reason_id,memo', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_receipts ON receipts;
CREATE TRIGGER trg_guard_header_receipts
  BEFORE UPDATE OR DELETE ON receipts
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,void_reason_id,memo', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_payment_vouchers ON payment_vouchers;
CREATE TRIGGER trg_guard_header_payment_vouchers
  BEFORE UPDATE OR DELETE ON payment_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,date_released,released_by,date_cleared,cleared_by,remarks', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_check_vouchers ON check_vouchers;
CREATE TRIGGER trg_guard_header_check_vouchers
  BEFORE UPDATE OR DELETE ON check_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'cleared_date,stale_date', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_petty_cash_vouchers ON petty_cash_vouchers;
CREATE TRIGGER trg_guard_header_petty_cash_vouchers
  BEFORE UPDATE OR DELETE ON petty_cash_vouchers
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'replenishment_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_petty_cash_replenishments ON petty_cash_replenishments;
CREATE TRIGGER trg_guard_header_petty_cash_replenishments
  BEFORE UPDATE OR DELETE ON petty_cash_replenishments
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', '', '', 'same_txn');

-- CM/DM: fn_save_credit_memo/fn_save_debit_memo apply/post an *approved*
-- memo by zeroing totals, rewriting lines, and recomputing — so total
-- columns stay lifecycle-mutable; the lines themselves remain guarded.
DROP TRIGGER IF EXISTS trg_guard_header_credit_memos ON credit_memos;
CREATE TRIGGER trg_guard_header_credit_memos
  BEFORE UPDATE OR DELETE ON credit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,total_net_amount,total_vat_amount,total_amount,total_taxable_amount,total_zero_rated_amount,total_exempt_amount', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_debit_memos ON debit_memos;
CREATE TRIGGER trg_guard_header_debit_memos
  BEFORE UPDATE OR DELETE ON debit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,total_net_amount,total_vat_amount,total_amount,total_taxable_amount,total_zero_rated_amount,total_exempt_amount', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_vendor_credits ON vendor_credits;
CREATE TRIGGER trg_guard_header_vendor_credits
  BEFORE UPDATE OR DELETE ON vendor_credits
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,remaining_balance', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_supplier_debit_memos ON supplier_debit_memos;
CREATE TRIGGER trg_guard_header_supplier_debit_memos
  BEFORE UPDATE OR DELETE ON supplier_debit_memos
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', '', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_cash_purchases ON cash_purchases;
CREATE TRIGGER trg_guard_header_cash_purchases
  BEFORE UPDATE OR DELETE ON cash_purchases
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_purchase_orders ON purchase_orders;
CREATE TRIGGER trg_guard_header_purchase_orders
  BEFORE UPDATE OR DELETE ON purchase_orders
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'approved_by,approved_at', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_purchase_returns ON purchase_returns;
CREATE TRIGGER trg_guard_header_purchase_returns
  BEFORE UPDATE OR DELETE ON purchase_returns
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_receiving_reports ON receiving_reports;
CREATE TRIGGER trg_guard_header_receiving_reports
  BEFORE UPDATE OR DELETE ON receiving_reports
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'confirmed_by,confirmed_at', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_sales_quotations ON sales_quotations;
CREATE TRIGGER trg_guard_header_sales_quotations
  BEFORE UPDATE OR DELETE ON sales_quotations
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft,pending', 'approved_by,approved_at', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_sales_orders ON sales_orders;
CREATE TRIGGER trg_guard_header_sales_orders
  BEFORE UPDATE OR DELETE ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('approval_status', 'pending', 'fulfillment_status,approved_by,approved_at', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_delivery_receipts ON delivery_receipts;
CREATE TRIGGER trg_guard_header_delivery_receipts
  BEFORE UPDATE OR DELETE ON delivery_receipts
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft,in_transit', 'delivered_at', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_goods_issues ON goods_issues;
CREATE TRIGGER trg_guard_header_goods_issues
  BEFORE UPDATE OR DELETE ON goods_issues
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,fiscal_period_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_stock_adjustments ON stock_adjustments;
CREATE TRIGGER trg_guard_header_stock_adjustments
  BEFORE UPDATE OR DELETE ON stock_adjustments
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,fiscal_period_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_stock_transfers ON stock_transfers;
CREATE TRIGGER trg_guard_header_stock_transfers
  BEFORE UPDATE OR DELETE ON stock_transfers
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,fiscal_period_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_physical_count_sheets ON physical_count_sheets;
CREATE TRIGGER trg_guard_header_physical_count_sheets
  BEFORE UPDATE OR DELETE ON physical_count_sheets
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft,counting,variance_review', 'journal_entry_id,posted_at,posted_by,fiscal_period_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_fund_transfers ON fund_transfers;
CREATE TRIGGER trg_guard_header_fund_transfers
  BEFORE UPDATE OR DELETE ON fund_transfers
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,fiscal_period_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_inter_branch_transfers ON inter_branch_transfers;
CREATE TRIGGER trg_guard_header_inter_branch_transfers
  BEFORE UPDATE OR DELETE ON inter_branch_transfers
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,fiscal_period_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_bank_adjustments ON bank_adjustments;
CREATE TRIGGER trg_guard_header_bank_adjustments
  BEFORE UPDATE OR DELETE ON bank_adjustments
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'journal_entry_id,posted_at,posted_by,fiscal_period_id', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_bank_reconciliations ON bank_reconciliations;
CREATE TRIGGER trg_guard_header_bank_reconciliations
  BEFORE UPDATE OR DELETE ON bank_reconciliations
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'finalized_at,finalized_by', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_cash_count_sheets ON cash_count_sheets;
CREATE TRIGGER trg_guard_header_cash_count_sheets
  BEFORE UPDATE OR DELETE ON cash_count_sheets
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', '', '', 'same_txn');

-- Journal entries: posted JEs may only transition to 'reversed' with
-- reversal linkage; the same_txn exception covers writers that create and
-- finalize (or roll back) a posted JE within one posting transaction.
DROP TRIGGER IF EXISTS trg_guard_header_journal_entries ON journal_entries;
CREATE TRIGGER trg_guard_header_journal_entries
  BEFORE UPDATE OR DELETE ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'reversed_by_je_id', '', 'same_txn');

-- Schedules stay maintainable while active (posting bumps posted_periods);
-- completed/cancelled schedules are locked.
DROP TRIGGER IF EXISTS trg_guard_header_amortization_schedules ON amortization_schedules;
CREATE TRIGGER trg_guard_header_amortization_schedules
  BEFORE UPDATE OR DELETE ON amortization_schedules
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'active', 'posted_periods', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_revenue_recognition_schedules ON revenue_recognition_schedules;
CREATE TRIGGER trg_guard_header_revenue_recognition_schedules
  BEFORE UPDATE OR DELETE ON revenue_recognition_schedules
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'active', 'posted_periods', '', 'same_txn');

-- Schedule entries: pending/skipped rows may move (pending<->skipped, post),
-- but a posted entry is frozen entirely — its JE is the only reversal path.
DROP TRIGGER IF EXISTS trg_guard_header_amortization_entries ON amortization_entries;
CREATE TRIGGER trg_guard_header_amortization_entries
  BEFORE UPDATE OR DELETE ON amortization_entries
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'pending,skipped', '', 'posted', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_asset_depreciation_entries ON asset_depreciation_entries;
CREATE TRIGGER trg_guard_header_asset_depreciation_entries
  BEFORE UPDATE OR DELETE ON asset_depreciation_entries
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'pending,skipped', '', 'posted', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_revenue_recognition_entries ON revenue_recognition_entries;
CREATE TRIGGER trg_guard_header_revenue_recognition_entries
  BEFORE UPDATE OR DELETE ON revenue_recognition_entries
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'pending,skipped', '', 'posted', 'same_txn');

-- Fixed assets: draft/active assets are maintainable (transfers change
-- branch/department); disposed, impaired, and fully depreciated assets only
-- accept lifecycle transitions (e.g. fully_depreciated -> disposed).
DROP TRIGGER IF EXISTS trg_guard_header_fixed_assets ON fixed_assets;
CREATE TRIGGER trg_guard_header_fixed_assets
  BEFORE UPDATE OR DELETE ON fixed_assets
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft,active', 'disposed_at', '', 'same_txn');

-- Tax returns and computations: business figures freeze once the return
-- leaves draft; filing metadata may still be recorded. vat_returns is
-- excluded here — its immutability is already enforced by the PXL-DA-015
-- snapshot guard and reconciliation triggers.
DROP TRIGGER IF EXISTS trg_guard_header_ewt_returns ON ewt_returns;
CREATE TRIGGER trg_guard_header_ewt_returns
  BEFORE UPDATE OR DELETE ON ewt_returns
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'filed_date,reference_no,remarks', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_fwt_returns ON fwt_returns;
CREATE TRIGGER trg_guard_header_fwt_returns
  BEFORE UPDATE OR DELETE ON fwt_returns
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'filed_date,reference_no,remarks', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_pt_returns ON pt_returns;
CREATE TRIGGER trg_guard_header_pt_returns
  BEFORE UPDATE OR DELETE ON pt_returns
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'filed_date,reference_no,remarks', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_itr_filings ON itr_filings;
CREATE TRIGGER trg_guard_header_itr_filings
  BEFORE UPDATE OR DELETE ON itr_filings
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'filed_date,reference_no,remarks', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_mcit_computations ON mcit_computations;
CREATE TRIGGER trg_guard_header_mcit_computations
  BEFORE UPDATE OR DELETE ON mcit_computations
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'remarks', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_income_tax_computations ON income_tax_computations;
CREATE TRIGGER trg_guard_header_income_tax_computations
  BEFORE UPDATE OR DELETE ON income_tax_computations
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'remarks', '', 'same_txn');

DROP TRIGGER IF EXISTS trg_guard_header_book_tax_reconciliation ON book_tax_reconciliation;
CREATE TRIGGER trg_guard_header_book_tax_reconciliation
  BEFORE UPDATE OR DELETE ON book_tax_reconciliation
  FOR EACH ROW EXECUTE FUNCTION fn_guard_doc_header('status', 'draft', 'remarks', '', 'same_txn');
