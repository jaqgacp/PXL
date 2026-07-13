-- Company-controlled transaction-workspace appearance.
-- The value lives on Company master data so transaction pages consume a
-- governed preference rather than defining document-specific colors.

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS workspace_accent_color TEXT NOT NULL DEFAULT '#14532D';

ALTER TABLE companies
  DROP CONSTRAINT IF EXISTS companies_workspace_accent_color_check;

ALTER TABLE companies
  ADD CONSTRAINT companies_workspace_accent_color_check
  CHECK (workspace_accent_color ~ '^#[0-9A-Fa-f]{6}$');

COMMENT ON COLUMN companies.workspace_accent_color IS
  'Company-selected accent used by reusable transaction workspaces; stored as a six-digit hexadecimal color.';
