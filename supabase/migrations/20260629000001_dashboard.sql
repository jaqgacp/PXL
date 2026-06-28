-- ============================================================
-- Dashboard: Layouts and Widgets
-- ============================================================

-- ── Dashboard Layouts (Header) ───────────────────────────────
CREATE TABLE dashboard_layouts (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  layout_name         TEXT        NOT NULL,
  target_role         TEXT        NOT NULL,
  default_date_filter TEXT        NOT NULL DEFAULT 'current_month'
                                  CHECK (default_date_filter IN ('today','current_month','quarter_to_date','year_to_date')),
  is_default_view     BOOLEAN     NOT NULL DEFAULT false,
  description         TEXT,
  created_by          UUID        REFERENCES auth.users(id),
  updated_by          UUID        REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One layout name per user (users can have same name as others)
  UNIQUE (layout_name, created_by)
);

-- ── Dashboard Widgets (Line Items) ───────────────────────────
CREATE TABLE dashboard_widgets (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  dashboard_layout_id   UUID        NOT NULL REFERENCES dashboard_layouts(id) ON DELETE CASCADE,
  widget_type           TEXT        NOT NULL
                                    CHECK (widget_type IN ('summary_card','bar_chart','line_chart','pie_chart','data_table','aging_bar')),
  kpi_source            TEXT        NOT NULL,
  grid_pos_x            INTEGER     NOT NULL DEFAULT 0,
  grid_pos_y            INTEGER     NOT NULL DEFAULT 0,
  grid_width            INTEGER     NOT NULL DEFAULT 1,
  grid_height           INTEGER     NOT NULL DEFAULT 1,
  custom_filter_json    JSONB,
  created_by            UUID        REFERENCES auth.users(id),
  updated_by            UUID        REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_dashboard_layouts_role
  ON dashboard_layouts (target_role);

CREATE INDEX idx_dashboard_layouts_created_by
  ON dashboard_layouts (created_by);

CREATE INDEX idx_dashboard_widgets_layout
  ON dashboard_widgets (dashboard_layout_id);

-- ── updated_at trigger ────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_dashboard_layouts_updated_at
  BEFORE UPDATE ON dashboard_layouts
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_dashboard_widgets_updated_at
  BEFORE UPDATE ON dashboard_widgets
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ── Row Level Security ────────────────────────────────────────
ALTER TABLE dashboard_layouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE dashboard_widgets ENABLE ROW LEVEL SECURITY;

-- Users can see their own layouts and all default layouts
CREATE POLICY "read_own_or_default_layouts" ON dashboard_layouts
  FOR SELECT TO authenticated
  USING (created_by = auth.uid() OR is_default_view = true);

-- Users can only create/edit/delete their own layouts
CREATE POLICY "manage_own_layouts" ON dashboard_layouts
  FOR ALL TO authenticated
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());

-- Widgets follow layout access rules
CREATE POLICY "read_own_widgets" ON dashboard_widgets
  FOR SELECT TO authenticated
  USING (
    dashboard_layout_id IN (
      SELECT id FROM dashboard_layouts
      WHERE created_by = auth.uid() OR is_default_view = true
    )
  );

CREATE POLICY "manage_own_widgets" ON dashboard_widgets
  FOR ALL TO authenticated
  USING (
    dashboard_layout_id IN (
      SELECT id FROM dashboard_layouts WHERE created_by = auth.uid()
    )
  )
  WITH CHECK (
    dashboard_layout_id IN (
      SELECT id FROM dashboard_layouts WHERE created_by = auth.uid()
    )
  );

-- ── Seed: default executive layout ───────────────────────────
-- Inserted without created_by so it's visible to all authenticated users
INSERT INTO dashboard_layouts (layout_name, target_role, default_date_filter, is_default_view, description)
VALUES (
  'Executive Overview',
  'executive',
  'current_month',
  true,
  'Default executive dashboard: Cash Flow, AR/AP Aging, Tax Compliance, Revenue Trends'
);

INSERT INTO dashboard_widgets (dashboard_layout_id, widget_type, kpi_source, grid_pos_x, grid_pos_y, grid_width, grid_height)
SELECT
  id,
  unnest(ARRAY['summary_card','aging_bar','summary_card','bar_chart']),
  unnest(ARRAY['cash_flow_overview','ar_ap_aging','tax_compliance_snapshot','revenue_trends']),
  unnest(ARRAY[0, 1, 2, 3]),
  0, 1, 1
FROM dashboard_layouts
WHERE layout_name = 'Executive Overview';
