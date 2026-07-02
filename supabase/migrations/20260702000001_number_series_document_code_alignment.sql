-- ══════════════════════════════════════════════════════════════════════════════
-- NUMBER SERIES: align table schema with fn_next_document_number
--
-- Defect (PXL-AUD-022): fn_next_document_number (20260629000012, replayed in
-- 20260630000021_gap_fill) selects number_series.document_code, current_sequence,
-- padding, and suffix — but no migration ever created those columns. plpgsql
-- compiles lazily, so every RPC document save (SI/OR/VB/PV/...) fails at runtime
-- with "column does not exist" on any database built purely from migrations.
-- NumberSeriesPage still writes the legacy shape (document_type_id, next_number,
-- number_length), and useTransactionReadiness probes document_code first with a
-- legacy fallback, so the three layers disagreed on the schema.
--
-- This migration is idempotent so it is safe on environments where the columns
-- were added manually outside migrations (schema drift).
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Add the document_code-shape columns ────────────────────────────────────

ALTER TABLE number_series
  ADD COLUMN IF NOT EXISTS document_code    TEXT,
  ADD COLUMN IF NOT EXISTS current_sequence BIGINT,
  ADD COLUMN IF NOT EXISTS padding          INTEGER,
  ADD COLUMN IF NOT EXISTS suffix           TEXT;

-- ── 2. Backfill from the legacy shape ─────────────────────────────────────────

UPDATE number_series ns
SET document_code = rdt.document_code
FROM ref_document_types rdt
WHERE rdt.id = ns.document_type_id
  AND ns.document_code IS NULL;

UPDATE number_series
SET current_sequence = GREATEST(COALESCE(next_number, starting_number, 1) - 1, 0)
WHERE current_sequence IS NULL;

UPDATE number_series
SET padding = COALESCE(number_length, 6)
WHERE padding IS NULL;

-- ── 3. Keep both shapes synchronized ──────────────────────────────────────────
-- The setup UI writes document_type_id/next_number/number_length; the numbering
-- RPC reads and advances document_code/current_sequence/padding. This trigger
-- derives each shape from the other so neither writer can strand the reader.

CREATE OR REPLACE FUNCTION fn_sync_number_series_shape()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Derive document_code from the legacy FK, and vice versa.
  IF NEW.document_code IS NULL AND NEW.document_type_id IS NOT NULL THEN
    SELECT rdt.document_code INTO NEW.document_code
    FROM ref_document_types rdt WHERE rdt.id = NEW.document_type_id;
  END IF;
  IF NEW.document_type_id IS NULL AND NEW.document_code IS NOT NULL THEN
    SELECT rdt.id INTO NEW.document_type_id
    FROM ref_document_types rdt WHERE rdt.document_code = NEW.document_code;
  END IF;

  NEW.padding := COALESCE(NEW.padding, NEW.number_length, 6);

  IF TG_OP = 'INSERT' THEN
    NEW.current_sequence := COALESCE(
      NEW.current_sequence,
      GREATEST(COALESCE(NEW.next_number, NEW.starting_number, 1) - 1, 0)
    );
    NEW.next_number := COALESCE(NEW.next_number, NEW.current_sequence + 1);
  ELSE
    -- RPC advanced current_sequence → mirror to next_number for the setup UI.
    IF NEW.current_sequence IS DISTINCT FROM OLD.current_sequence THEN
      NEW.next_number := COALESCE(NEW.current_sequence, 0) + 1;
    -- Setup UI changed next_number → mirror to current_sequence for the RPC.
    ELSIF NEW.next_number IS DISTINCT FROM OLD.next_number THEN
      NEW.current_sequence := GREATEST(COALESCE(NEW.next_number, 1) - 1, 0);
    END IF;
    NEW.current_sequence := COALESCE(NEW.current_sequence,
      GREATEST(COALESCE(NEW.next_number, NEW.starting_number, 1) - 1, 0));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_number_series_shape ON number_series;
CREATE TRIGGER trg_sync_number_series_shape
  BEFORE INSERT OR UPDATE ON number_series
  FOR EACH ROW EXECUTE FUNCTION fn_sync_number_series_shape();

-- ── 4. One active series per company/branch/document code ─────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS uq_number_series_active_doc_code
  ON number_series (company_id, branch_id, document_code)
  WHERE is_active = true;
