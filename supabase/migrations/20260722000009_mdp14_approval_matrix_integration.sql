-- MDP-14 - Approval Matrix Integration
--
-- Extends the existing approval_workflows / approval_workflow_steps /
-- approval_instances model with deterministic rule criteria, role-code routing,
-- a server-authoritative request lifecycle, concurrency controls, and an opt-in
-- approval gate for committed MDP-15 master-data imports.
--
-- No approval rules are seeded. Existing unconfigured operations therefore keep
-- their current behavior, while configured rules fail closed when their route has
-- no valid approver.

-- 1. Extend existing rule and step configuration.
ALTER TABLE approval_workflows
  ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id),
  ADD COLUMN IF NOT EXISTS action_type TEXT NOT NULL DEFAULT 'approve',
  ADD COLUMN IF NOT EXISTS currency_code TEXT REFERENCES currencies(currency_code),
  ADD COLUMN IF NOT EXISTS requester_role_code TEXT,
  ADD COLUMN IF NOT EXISTS requester_user_id UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS priority INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS effective_from TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS effective_to TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS enforce_requester_separation BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE approval_workflows
  DROP CONSTRAINT IF EXISTS approval_workflows_module_type_check;
ALTER TABLE approval_workflows
  ADD CONSTRAINT approval_workflows_module_type_check
  CHECK (module_type ~ '^[a-z][a-z0-9_]*$');

ALTER TABLE approval_workflows
  DROP CONSTRAINT IF EXISTS approval_workflows_action_type_check;
ALTER TABLE approval_workflows
  ADD CONSTRAINT approval_workflows_action_type_check
  CHECK (action_type = '*' OR action_type ~ '^[a-z][a-z0-9_]*$');

ALTER TABLE approval_workflows
  DROP CONSTRAINT IF EXISTS approval_workflows_requester_role_code_check;
ALTER TABLE approval_workflows
  ADD CONSTRAINT approval_workflows_requester_role_code_check
  CHECK (requester_role_code IS NULL OR requester_role_code ~ '^[a-z][a-z0-9_]*$');

ALTER TABLE approval_workflows
  DROP CONSTRAINT IF EXISTS approval_workflows_effective_dates_check;
ALTER TABLE approval_workflows
  ADD CONSTRAINT approval_workflows_effective_dates_check
  CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from);

ALTER TABLE approval_workflows
  DROP CONSTRAINT IF EXISTS approval_workflows_threshold_check;
ALTER TABLE approval_workflows
  ADD CONSTRAINT approval_workflows_threshold_check
  CHECK (
    (trigger_condition_type = 'amount_exceeds' AND threshold_value IS NOT NULL AND threshold_value >= 0)
    OR trigger_condition_type <> 'amount_exceeds'
  );

ALTER TABLE approval_workflows
  DROP CONSTRAINT IF EXISTS approval_workflows_company_id_module_type_document_type_trigger_condition_type_threshold_value_key;
ALTER TABLE approval_workflows
  DROP CONSTRAINT IF EXISTS approval_workflows_company_id_module_type_document_type_tri_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_approval_workflows_matrix_criteria
  ON approval_workflows (
    company_id,
    COALESCE(branch_id, '00000000-0000-0000-0000-000000000000'::UUID),
    module_type,
    lower(document_type),
    action_type,
    trigger_condition_type,
    COALESCE(threshold_value, -1),
    COALESCE(currency_code, ''),
    COALESCE(requester_role_code, ''),
    COALESCE(requester_user_id, '00000000-0000-0000-0000-000000000000'::UUID),
    COALESCE(effective_from, '-infinity'::TIMESTAMPTZ),
    COALESCE(effective_to, 'infinity'::TIMESTAMPTZ)
  );

CREATE INDEX IF NOT EXISTS idx_approval_workflows_resolution
  ON approval_workflows (company_id, module_type, is_active, effective_from, effective_to);

ALTER TABLE approval_workflow_steps
  ADD COLUMN IF NOT EXISTS approver_role_code TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE approval_workflow_steps
  DROP CONSTRAINT IF EXISTS approval_workflow_steps_approver_role_code_check;
ALTER TABLE approval_workflow_steps
  ADD CONSTRAINT approval_workflow_steps_approver_role_code_check
  CHECK (approver_role_code IS NULL OR approver_role_code ~ '^[a-z][a-z0-9_]*$');

DROP TRIGGER IF EXISTS trg_approval_workflow_steps_updated_at ON approval_workflow_steps;
CREATE TRIGGER trg_approval_workflow_steps_updated_at
  BEFORE UPDATE ON approval_workflow_steps
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE OR REPLACE FUNCTION fn_approval_rule_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_branch_company UUID;
BEGIN
  NEW.document_type := COALESCE(trim(NEW.document_type), '');
  NEW.action_type := lower(trim(NEW.action_type));
  NEW.module_type := lower(trim(NEW.module_type));
  NEW.currency_code := NULLIF(upper(trim(NEW.currency_code)), '');
  NEW.requester_role_code := NULLIF(lower(trim(NEW.requester_role_code)), '');

  IF NEW.branch_id IS NOT NULL THEN
    SELECT company_id INTO v_branch_company FROM branches WHERE id = NEW.branch_id;
    IF v_branch_company IS NULL OR v_branch_company <> NEW.company_id THEN
      RAISE EXCEPTION 'approval rule branch must belong to the rule company'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.requester_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM user_company_memberships m
    WHERE m.company_id = NEW.company_id AND m.user_id = NEW.requester_user_id
  ) THEN
    RAISE EXCEPTION 'approval rule requester user must belong to the rule company'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_approval_rule_guard ON approval_workflows;
CREATE TRIGGER trg_approval_rule_guard
  BEFORE INSERT OR UPDATE ON approval_workflows
  FOR EACH ROW EXECUTE FUNCTION fn_approval_rule_guard();

CREATE OR REPLACE FUNCTION fn_approval_step_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_workflow_company UUID;
BEGIN
  SELECT company_id INTO v_workflow_company
  FROM approval_workflows
  WHERE id = NEW.workflow_id;

  IF v_workflow_company IS NULL OR v_workflow_company <> NEW.company_id THEN
    RAISE EXCEPTION 'approval step company must match its workflow company'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.step_sequence < 1 THEN
    RAISE EXCEPTION 'approval step sequence must be positive' USING ERRCODE = '23514';
  END IF;

  NEW.approver_role_code := NULLIF(lower(trim(NEW.approver_role_code)), '');
  IF NEW.approver_type = 'role' AND NEW.approver_role_code IS NULL THEN
    RAISE EXCEPTION 'role approval steps require approver_role_code' USING ERRCODE = '23514';
  ELSIF NEW.approver_type IN ('user', 'dept_head') AND NEW.approver_user_id IS NULL THEN
    RAISE EXCEPTION '% approval steps require approver_user_id', NEW.approver_type
      USING ERRCODE = '23514';
  END IF;

  IF NEW.approver_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM user_company_memberships m
    WHERE m.company_id = NEW.company_id AND m.user_id = NEW.approver_user_id
  ) THEN
    RAISE EXCEPTION 'approval step user must belong to the workflow company'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_approval_step_guard ON approval_workflow_steps;
CREATE TRIGGER trg_approval_step_guard
  BEFORE INSERT OR UPDATE ON approval_workflow_steps
  FOR EACH ROW EXECUTE FUNCTION fn_approval_step_guard();

-- 2. Request header over the existing per-step approval instances.
CREATE TABLE IF NOT EXISTS approval_requests (
  id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                   UUID NOT NULL REFERENCES companies(id),
  branch_id                    UUID REFERENCES branches(id),
  workflow_id                  UUID NOT NULL REFERENCES approval_workflows(id),
  module_type                  TEXT NOT NULL CHECK (module_type ~ '^[a-z][a-z0-9_]*$'),
  action_type                  TEXT NOT NULL CHECK (action_type ~ '^[a-z][a-z0-9_]*$'),
  source_document_type         TEXT NOT NULL,
  source_document_id           UUID NOT NULL,
  source_document_no           TEXT NOT NULL,
  source_document_amount       NUMERIC(15,2),
  currency_code                TEXT REFERENCES currencies(currency_code),
  record_version               TEXT NOT NULL,
  record_snapshot              JSONB NOT NULL DEFAULT '{}'::JSONB,
  status                       TEXT NOT NULL DEFAULT 'pending'
                                 CHECK (status IN (
                                   'pending','partially_approved','approved','rejected',
                                   'withdrawn','cancelled','superseded'
                                 )),
  current_step_sequence        INTEGER NOT NULL CHECK (current_step_sequence > 0),
  requester_id                 UUID NOT NULL REFERENCES auth.users(id),
  requester_role_code          TEXT NOT NULL,
  request_reason               TEXT,
  decision_reason              TEXT,
  submitted_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at                   TIMESTAMPTZ,
  consumed_at                  TIMESTAMPTZ,
  consumed_by                  UUID REFERENCES auth.users(id),
  consumption_idempotency_key  TEXT,
  created_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (jsonb_typeof(record_snapshot) = 'object')
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_approval_requests_actionable_source
  ON approval_requests (company_id, module_type, action_type, source_document_type, source_document_id)
  WHERE status IN ('pending','partially_approved');

CREATE INDEX IF NOT EXISTS idx_approval_requests_inbox
  ON approval_requests (company_id, status, current_step_sequence, submitted_at);
CREATE INDEX IF NOT EXISTS idx_approval_requests_source
  ON approval_requests (company_id, source_document_type, source_document_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_approval_requests_updated_at ON approval_requests;
CREATE TRIGGER trg_approval_requests_updated_at
  BEFORE UPDATE ON approval_requests
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE approval_instances
  ADD COLUMN IF NOT EXISTS request_id UUID REFERENCES approval_requests(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS approver_role_code TEXT;

ALTER TABLE approval_instances
  DROP CONSTRAINT IF EXISTS approval_instances_status_check;
ALTER TABLE approval_instances
  ADD CONSTRAINT approval_instances_status_check
  CHECK (status IN (
    'waiting','pending','approved','rejected','cancelled','superseded','escalated','bypassed'
  ));

ALTER TABLE approval_instances
  DROP CONSTRAINT IF EXISTS approval_instances_approver_role_code_check;
ALTER TABLE approval_instances
  ADD CONSTRAINT approval_instances_approver_role_code_check
  CHECK (approver_role_code IS NULL OR approver_role_code ~ '^[a-z][a-z0-9_]*$');

CREATE UNIQUE INDEX IF NOT EXISTS uq_approval_instances_request_step
  ON approval_instances (request_id, step_sequence)
  WHERE request_id IS NOT NULL;

-- Rule edits, route edits, requests, and per-step decisions all reuse the
-- established MDP-02 audit mechanism.
DROP TRIGGER IF EXISTS trg_audit_approval_workflow_steps ON approval_workflow_steps;
CREATE TRIGGER trg_audit_approval_workflow_steps
  AFTER INSERT OR UPDATE OR DELETE ON approval_workflow_steps
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

DROP TRIGGER IF EXISTS trg_audit_approval_requests ON approval_requests;
CREATE TRIGGER trg_audit_approval_requests
  AFTER INSERT OR UPDATE OR DELETE ON approval_requests
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

DROP TRIGGER IF EXISTS trg_audit_approval_instances ON approval_instances;
CREATE TRIGGER trg_audit_approval_instances
  AFTER INSERT OR UPDATE OR DELETE ON approval_instances
  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();

-- 3. Deterministic rule matching and authorization helpers.
CREATE OR REPLACE FUNCTION fn_resolve_approval_rule(
  p_company_id       UUID,
  p_branch_id        UUID,
  p_module_type      TEXT,
  p_document_type    TEXT,
  p_action_type      TEXT,
  p_amount           NUMERIC DEFAULT NULL,
  p_currency_code    TEXT DEFAULT NULL,
  p_requester_id     UUID DEFAULT NULL,
  p_as_of            TIMESTAMPTZ DEFAULT NOW()
)
RETURNS TABLE (
  workflow_id       UUID,
  workflow_name     TEXT,
  step_count        INTEGER,
  specificity_score INTEGER,
  precedence        JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_requester_id UUID := COALESCE(p_requester_id, auth.uid());
  v_requester_role TEXT;
BEGIN
  IF p_company_id IS NULL OR v_requester_id IS NULL THEN
    RETURN;
  END IF;

  SELECT m.role INTO v_requester_role
  FROM user_company_memberships m
  WHERE m.company_id = p_company_id
    AND m.user_id = v_requester_id;

  IF v_requester_role IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH matching AS (
    SELECT aw.*,
           (
             (aw.branch_id IS NOT NULL)::INTEGER
             + (COALESCE(trim(aw.document_type), '') <> '')::INTEGER
             + (aw.action_type <> '*')::INTEGER
             + (aw.requester_user_id IS NOT NULL)::INTEGER
             + (aw.requester_role_code IS NOT NULL)::INTEGER
             + (aw.currency_code IS NOT NULL)::INTEGER
             + (aw.trigger_condition_type <> 'always')::INTEGER
           ) AS score,
           (SELECT count(*)::INTEGER
              FROM approval_workflow_steps s
             WHERE s.workflow_id = aw.id AND s.is_active) AS active_steps
    FROM approval_workflows aw
    WHERE aw.company_id = p_company_id
      AND aw.is_active
      AND aw.module_type = lower(trim(p_module_type))
      AND (aw.branch_id IS NULL OR aw.branch_id = p_branch_id)
      AND (
        COALESCE(trim(aw.document_type), '') = ''
        OR lower(trim(aw.document_type)) = lower(trim(p_document_type))
      )
      AND (aw.action_type = '*' OR aw.action_type = lower(trim(p_action_type)))
      AND (aw.requester_user_id IS NULL OR aw.requester_user_id = v_requester_id)
      AND (aw.requester_role_code IS NULL OR aw.requester_role_code = v_requester_role)
      AND (aw.currency_code IS NULL OR aw.currency_code = upper(trim(p_currency_code)))
      AND (aw.effective_from IS NULL OR aw.effective_from <= p_as_of)
      AND (aw.effective_to IS NULL OR aw.effective_to >= p_as_of)
      AND (
        aw.trigger_condition_type <> 'amount_exceeds'
        OR COALESCE(p_amount, 0) > aw.threshold_value
      )
  )
  SELECT m.id,
         m.workflow_name,
         m.active_steps,
         m.score,
         jsonb_build_object(
           'specificity_score', m.score,
           'branch_specific', m.branch_id IS NOT NULL,
           'document_specific', COALESCE(trim(m.document_type), '') <> '',
           'action_specific', m.action_type <> '*',
           'requester_user_specific', m.requester_user_id IS NOT NULL,
           'requester_role_specific', m.requester_role_code IS NOT NULL,
           'currency_specific', m.currency_code IS NOT NULL,
           'condition_specific', m.trigger_condition_type <> 'always',
           'priority', m.priority,
           'effective_from', m.effective_from
         )
  FROM matching m
  ORDER BY
    m.score DESC,
    (m.branch_id IS NOT NULL) DESC,
    (COALESCE(trim(m.document_type), '') <> '') DESC,
    (m.action_type <> '*') DESC,
    (m.requester_user_id IS NOT NULL) DESC,
    (m.requester_role_code IS NOT NULL) DESC,
    (m.currency_code IS NOT NULL) DESC,
    (m.trigger_condition_type <> 'always') DESC,
    CASE WHEN m.trigger_condition_type = 'amount_exceeds' THEN m.threshold_value END DESC NULLS LAST,
    m.priority DESC,
    m.effective_from DESC NULLS LAST,
    m.created_at ASC,
    m.id ASC
  LIMIT 1;
END;
$$;

COMMENT ON FUNCTION fn_resolve_approval_rule(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, TEXT, UUID, TIMESTAMPTZ) IS
  'MDP-14 deterministic approval resolution. Rules are ordered by constrained-criteria count, then branch, document, action, requester user, requester role, currency, condition, highest matching amount threshold, explicit priority, newest effective start, creation time, and UUID.';

-- Preserve the DEC-010 four-argument helper as a compatibility adapter.
CREATE OR REPLACE FUNCTION fn_required_approval_workflow(
  p_company_id UUID,
  p_module_type TEXT,
  p_document_label TEXT,
  p_amount NUMERIC
)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.workflow_id
  FROM fn_resolve_approval_rule(
    p_company_id, NULL, p_module_type, p_document_label, 'approve',
    p_amount, NULL, auth.uid(), NOW()
  ) r;
$$;

CREATE OR REPLACE FUNCTION fn_approval_source_permission_action(p_action_type TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(COALESCE(p_action_type, ''))
    WHEN 'create' THEN 'create'
    WHEN 'delete' THEN 'delete'
    WHEN 'archive' THEN 'delete'
    WHEN 'import' THEN 'import'
    WHEN 'export' THEN 'export'
    WHEN 'activate' THEN 'edit'
    WHEN 'deactivate' THEN 'edit'
    ELSE 'edit'
  END;
$$;

CREATE OR REPLACE FUNCTION fn_can_submit_approval_request(
  p_company_id UUID,
  p_module_type TEXT,
  p_document_type TEXT,
  p_action_type TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_module_type = 'master_data' THEN
    RETURN fn_can_master_data_permission(
      p_company_id,
      p_document_type,
      fn_approval_source_permission_action(p_action_type)
    );
  END IF;

  RETURN is_company_member(p_company_id)
    AND fn_can_perform(p_company_id, 'edit', p_document_type);
END;
$$;

CREATE OR REPLACE FUNCTION fn_can_decide_approval_request(
  p_company_id UUID,
  p_module_type TEXT,
  p_document_type TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_module_type = 'master_data' THEN
    RETURN fn_can_master_data_permission(p_company_id, p_document_type, 'approve');
  END IF;

  -- For transaction modules, the configured workflow step is the approver-role
  -- assignment. Existing company membership remains the identity boundary.
  RETURN is_company_member(p_company_id);
END;
$$;

CREATE OR REPLACE FUNCTION fn_is_valid_approval_candidate(
  p_user_id             UUID,
  p_company_id          UUID,
  p_branch_id           UUID,
  p_approver_type       TEXT,
  p_approver_user_id    UUID,
  p_approver_role_code  TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.users u
    JOIN public.user_company_memberships m
      ON m.user_id = u.id AND m.company_id = p_company_id
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until < NOW())
      AND (
        (p_approver_type IN ('user','dept_head') AND p_approver_user_id = u.id)
        OR (p_approver_type = 'role' AND m.role = p_approver_role_code)
      )
      AND (
        p_branch_id IS NULL
        OR m.role IN ('owner','admin')
        OR NOT EXISTS (
          SELECT 1 FROM public.user_company_branch_scopes s
          WHERE s.user_id = u.id AND s.company_id = p_company_id AND s.is_active
        )
        OR EXISTS (
          SELECT 1 FROM public.user_company_branch_scopes s
          WHERE s.user_id = u.id
            AND s.company_id = p_company_id
            AND s.branch_id = p_branch_id
            AND s.is_active
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION fn_approval_step_has_candidate(
  p_step_id UUID,
  p_branch_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM approval_workflow_steps s
    JOIN user_company_memberships m ON m.company_id = s.company_id
    WHERE s.id = p_step_id
      AND s.is_active
      AND fn_is_valid_approval_candidate(
        m.user_id, s.company_id, p_branch_id, s.approver_type,
        s.approver_user_id, s.approver_role_code
      )
  );
$$;

CREATE OR REPLACE FUNCTION fn_has_enforced_master_data_sod_conflict(
  p_company_id UUID,
  p_master_key TEXT,
  p_action_type TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH actor_role AS (
    SELECT m.role
    FROM user_company_memberships m
    WHERE m.company_id = p_company_id AND m.user_id = auth.uid()
  ), codes AS (
    SELECT p_master_key || '.' || fn_approval_source_permission_action(p_action_type) AS source_code,
           p_master_key || '.approve' AS approval_code
  )
  SELECT EXISTS (
    SELECT 1
    FROM master_data_sod_conflicts c
    CROSS JOIN actor_role ar
    CROSS JOIN codes x
    JOIN master_data_role_permissions left_grant
      ON left_grant.role_code = ar.role
     AND left_grant.permission_code = c.left_permission_code
     AND left_grant.is_allowed
    JOIN master_data_role_permissions right_grant
      ON right_grant.role_code = ar.role
     AND right_grant.permission_code = c.right_permission_code
     AND right_grant.is_allowed
    WHERE c.is_active
      AND c.enforcement_mode = 'enforced'
      AND (
        (c.left_permission_code = x.source_code AND c.right_permission_code = x.approval_code)
        OR (c.right_permission_code = x.source_code AND c.left_permission_code = x.approval_code)
      )
  );
$$;

-- 4. Reusable decision, submission, lifecycle, status, and inbox RPCs.
CREATE OR REPLACE FUNCTION fn_get_approval_decision(
  p_company_id       UUID,
  p_branch_id        UUID,
  p_module_type      TEXT,
  p_document_type    TEXT,
  p_action_type      TEXT,
  p_amount           NUMERIC DEFAULT NULL,
  p_currency_code    TEXT DEFAULT NULL,
  p_as_of            TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rule RECORD;
  v_route_valid BOOLEAN;
BEGIN
  IF NOT is_company_member(p_company_id) THEN
    RAISE EXCEPTION 'approval decision denied outside company scope' USING ERRCODE = '42501';
  END IF;

  IF p_branch_id IS NOT NULL AND NOT fn_can_access_company_branch(p_company_id, p_branch_id) THEN
    RAISE EXCEPTION 'approval decision denied outside branch scope' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_rule
  FROM fn_resolve_approval_rule(
    p_company_id, p_branch_id, p_module_type, p_document_type, p_action_type,
    p_amount, p_currency_code, auth.uid(), p_as_of
  );

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'approval_required', false,
      'workflow_id', NULL,
      'workflow_name', NULL,
      'step_count', 0,
      'valid_approver_available', true,
      'final_actionable', true,
      'status', 'not_required'
    );
  END IF;

  SELECT NOT EXISTS (
    SELECT 1
    FROM approval_workflow_steps s
    WHERE s.workflow_id = v_rule.workflow_id
      AND s.is_active
      AND NOT fn_approval_step_has_candidate(s.id, p_branch_id)
  ) AND v_rule.step_count > 0
  INTO v_route_valid;

  RETURN jsonb_build_object(
    'approval_required', true,
    'workflow_id', v_rule.workflow_id,
    'workflow_name', v_rule.workflow_name,
    'step_count', v_rule.step_count,
    'valid_approver_available', v_route_valid,
    'final_actionable', false,
    'status', 'not_submitted',
    'precedence', v_rule.precedence
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_submit_approval_request(
  p_company_id             UUID,
  p_branch_id              UUID,
  p_module_type            TEXT,
  p_document_type          TEXT,
  p_action_type            TEXT,
  p_source_document_id     UUID,
  p_source_document_no     TEXT,
  p_record_version         TEXT,
  p_source_document_amount NUMERIC DEFAULT NULL,
  p_currency_code          TEXT DEFAULT NULL,
  p_record_snapshot        JSONB DEFAULT '{}'::JSONB,
  p_request_reason         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rule RECORD;
  v_role TEXT;
  v_request approval_requests%ROWTYPE;
  v_first_sequence INTEGER;
  v_step RECORD;
  v_branch_company UUID;
  v_preview master_data_import_batches%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authenticated requester required' USING ERRCODE = '42501';
  END IF;

  IF NOT fn_can_submit_approval_request(
    p_company_id, lower(trim(p_module_type)), p_document_type, lower(trim(p_action_type))
  ) THEN
    RAISE EXCEPTION 'not authorized to submit % approval for %', p_action_type, p_document_type
      USING ERRCODE = '42501';
  END IF;

  IF p_branch_id IS NOT NULL THEN
    SELECT company_id INTO v_branch_company FROM branches WHERE id = p_branch_id;
    IF v_branch_company IS NULL OR v_branch_company <> p_company_id THEN
      RAISE EXCEPTION 'approval request branch must belong to the request company'
        USING ERRCODE = '23514';
    END IF;
    IF NOT fn_can_access_company_branch(p_company_id, p_branch_id) THEN
      RAISE EXCEPTION 'approval submission denied outside branch scope' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF p_source_document_id IS NULL OR NULLIF(trim(p_source_document_no), '') IS NULL THEN
    RAISE EXCEPTION 'approval source id and number are required' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(p_record_version), '') IS NULL THEN
    RAISE EXCEPTION 'approval record version is required' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(jsonb_typeof(p_record_snapshot), 'null') <> 'object' THEN
    RAISE EXCEPTION 'approval record snapshot must be a JSON object' USING ERRCODE = '22023';
  END IF;

  SELECT m.role INTO v_role
  FROM user_company_memberships m
  WHERE m.company_id = p_company_id AND m.user_id = auth.uid();

  SELECT * INTO v_rule
  FROM fn_resolve_approval_rule(
    p_company_id, p_branch_id, p_module_type, p_document_type, p_action_type,
    p_source_document_amount, p_currency_code, auth.uid(), NOW()
  );

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'approval_required', false,
      'request_id', NULL,
      'status', 'not_required',
      'final_actionable', true,
      'idempotent_replay', false
    );
  END IF;

  IF v_rule.step_count = 0 THEN
    RAISE EXCEPTION 'approval workflow % has no active approval steps', v_rule.workflow_name
      USING ERRCODE = '55000';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM approval_workflow_steps s
    WHERE s.workflow_id = v_rule.workflow_id
      AND s.is_active
      AND NOT fn_approval_step_has_candidate(s.id, p_branch_id)
  ) THEN
    RAISE EXCEPTION 'approval workflow % has an approval step without a valid approver', v_rule.workflow_name
      USING ERRCODE = '55000';
  END IF;

  -- MDP-15 import requests must be anchored to a successful preview. The input
  -- hash is rechecked again by the commit wrapper after final approval.
  IF lower(trim(p_module_type)) = 'master_data' AND lower(trim(p_action_type)) = 'import' THEN
    SELECT * INTO v_preview
    FROM master_data_import_batches b
    WHERE b.id = p_source_document_id
      AND b.company_id = p_company_id
      AND b.master_key = p_document_type
      AND b.mode = 'preview'
      AND b.status = 'validated'
      AND b.error_count = 0;

    IF NOT FOUND OR v_preview.input_hash <> p_record_version THEN
      RAISE EXCEPTION 'master-data import approval requires a matching validated preview batch'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  -- Same-version submissions are idempotent. A changed version supersedes the
  -- outstanding request and creates a new route atomically.
  SELECT r.* INTO v_request
  FROM approval_requests r
  WHERE r.company_id = p_company_id
    AND r.module_type = lower(trim(p_module_type))
    AND r.action_type = lower(trim(p_action_type))
    AND r.source_document_type = p_document_type
    AND r.source_document_id = p_source_document_id
    AND r.status IN ('pending','partially_approved','approved')
  ORDER BY r.created_at DESC, r.id DESC
  LIMIT 1
  FOR UPDATE;

  IF FOUND
     AND v_request.workflow_id = v_rule.workflow_id
     AND v_request.record_version = p_record_version
  THEN
    RETURN jsonb_build_object(
      'approval_required', true,
      'request_id', v_request.id,
      'workflow_id', v_request.workflow_id,
      'status', v_request.status,
      'current_step_sequence', v_request.current_step_sequence,
      'final_actionable', v_request.status = 'approved',
      'idempotent_replay', true
    );
  END IF;

  IF FOUND AND v_request.status IN ('pending','partially_approved') THEN
    UPDATE approval_requests
       SET status = 'superseded',
           decision_reason = 'source version changed before final approval',
           decided_at = NOW()
     WHERE id = v_request.id;

    UPDATE approval_instances
       SET status = 'superseded', acted_at = NOW(),
           remarks = COALESCE(remarks, 'source version changed before final approval')
     WHERE request_id = v_request.id AND status IN ('waiting','pending');
  END IF;

  SELECT min(s.step_sequence) INTO v_first_sequence
  FROM approval_workflow_steps s
  WHERE s.workflow_id = v_rule.workflow_id AND s.is_active;

  INSERT INTO approval_requests (
    company_id, branch_id, workflow_id, module_type, action_type,
    source_document_type, source_document_id, source_document_no,
    source_document_amount, currency_code, record_version, record_snapshot,
    status, current_step_sequence, requester_id, requester_role_code,
    request_reason
  ) VALUES (
    p_company_id, p_branch_id, v_rule.workflow_id,
    lower(trim(p_module_type)), lower(trim(p_action_type)),
    p_document_type, p_source_document_id, trim(p_source_document_no),
    p_source_document_amount, NULLIF(upper(trim(p_currency_code)), ''),
    trim(p_record_version), COALESCE(p_record_snapshot, '{}'::JSONB),
    'pending', v_first_sequence, auth.uid(), v_role, NULLIF(trim(p_request_reason), '')
  ) RETURNING * INTO v_request;

  FOR v_step IN
    SELECT s.*
    FROM approval_workflow_steps s
    WHERE s.workflow_id = v_rule.workflow_id AND s.is_active
    ORDER BY s.step_sequence, s.id
  LOOP
    INSERT INTO approval_instances (
      company_id, workflow_id, workflow_step_id, request_id,
      source_document_type, source_document_id, source_document_no,
      source_document_amount, step_sequence,
      required_approver_type, required_approver_id, approver_role_code,
      status, created_by
    ) VALUES (
      p_company_id, v_rule.workflow_id, v_step.id, v_request.id,
      p_document_type, p_source_document_id, trim(p_source_document_no),
      p_source_document_amount, v_step.step_sequence,
      v_step.approver_type,
      CASE WHEN v_step.approver_type IN ('user','dept_head') THEN v_step.approver_user_id END,
      CASE WHEN v_step.approver_type = 'role' THEN v_step.approver_role_code END,
      CASE WHEN v_step.step_sequence = v_first_sequence THEN 'pending' ELSE 'waiting' END,
      auth.uid()
    );
  END LOOP;

  RETURN jsonb_build_object(
    'approval_required', true,
    'request_id', v_request.id,
    'workflow_id', v_request.workflow_id,
    'status', v_request.status,
    'current_step_sequence', v_request.current_step_sequence,
    'final_actionable', false,
    'idempotent_replay', false,
    'precedence', v_rule.precedence
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_approve_approval_request(
  p_request_id UUID,
  p_current_record_version TEXT,
  p_remarks TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request approval_requests%ROWTYPE;
  v_rule approval_workflows%ROWTYPE;
  v_instance approval_instances%ROWTYPE;
  v_next_sequence INTEGER;
BEGIN
  SELECT r.* INTO v_request
  FROM approval_requests r
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND OR NOT is_company_member(v_request.company_id) THEN
    RAISE EXCEPTION 'approval request not found in caller company scope' USING ERRCODE = '42501';
  END IF;
  IF v_request.status NOT IN ('pending','partially_approved') THEN
    RAISE EXCEPTION 'approval request is not actionable (status %)', v_request.status
      USING ERRCODE = '55000';
  END IF;

  IF p_current_record_version IS DISTINCT FROM v_request.record_version THEN
    UPDATE approval_requests
       SET status = 'superseded',
           decision_reason = 'source version changed before approval',
           decided_at = NOW()
     WHERE id = v_request.id;
    UPDATE approval_instances
       SET status = 'superseded', acted_at = NOW(),
           remarks = COALESCE(remarks, 'source version changed before approval')
     WHERE request_id = v_request.id AND status IN ('waiting','pending');
    RETURN jsonb_build_object(
      'request_id', v_request.id,
      'status', 'superseded',
      'final_actionable', false,
      'error', 'stale_record'
    );
  END IF;

  SELECT * INTO v_rule FROM approval_workflows WHERE id = v_request.workflow_id;
  SELECT i.* INTO v_instance
  FROM approval_instances i
  WHERE i.request_id = v_request.id
    AND i.step_sequence = v_request.current_step_sequence
    AND i.status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval request has no pending instance for current step'
      USING ERRCODE = '55000';
  END IF;
  IF NOT fn_can_decide_approval_request(
    v_request.company_id, v_request.module_type, v_request.source_document_type
  ) THEN
    RAISE EXCEPTION 'not authorized to approve %', v_request.source_document_type
      USING ERRCODE = '42501';
  END IF;
  IF v_request.branch_id IS NOT NULL
     AND NOT fn_can_access_company_branch(v_request.company_id, v_request.branch_id)
  THEN
    RAISE EXCEPTION 'approval denied outside branch scope' USING ERRCODE = '42501';
  END IF;
  IF NOT fn_is_valid_approval_candidate(
    auth.uid(), v_request.company_id, v_request.branch_id,
    v_instance.required_approver_type, v_instance.required_approver_id,
    v_instance.approver_role_code
  ) THEN
    RAISE EXCEPTION 'current user is not the configured approver for step %', v_instance.step_sequence
      USING ERRCODE = '42501';
  END IF;
  IF v_rule.enforce_requester_separation AND auth.uid() = v_request.requester_id THEN
    RAISE EXCEPTION 'segregation of duties prevents requester self-approval'
      USING ERRCODE = '42501';
  END IF;
  IF v_request.module_type = 'master_data'
     AND fn_has_enforced_master_data_sod_conflict(
       v_request.company_id, v_request.source_document_type, v_request.action_type
     )
  THEN
    RAISE EXCEPTION 'enforced master-data SOD conflict prevents approval'
      USING ERRCODE = '42501';
  END IF;

  UPDATE approval_instances
     SET status = 'approved',
         actual_approver_id = auth.uid(),
         acted_at = NOW(),
         remarks = NULLIF(trim(p_remarks), '')
   WHERE id = v_instance.id;

  SELECT min(i.step_sequence) INTO v_next_sequence
  FROM approval_instances i
  WHERE i.request_id = v_request.id AND i.status = 'waiting';

  IF v_next_sequence IS NULL THEN
    UPDATE approval_requests
       SET status = 'approved',
           decision_reason = NULLIF(trim(p_remarks), ''),
           decided_at = NOW()
     WHERE id = v_request.id;

    RETURN jsonb_build_object(
      'request_id', v_request.id,
      'status', 'approved',
      'current_step_sequence', v_request.current_step_sequence,
      'next_required_approval', NULL,
      'final_actionable', true
    );
  END IF;

  UPDATE approval_instances
     SET status = 'pending'
   WHERE request_id = v_request.id AND step_sequence = v_next_sequence AND status = 'waiting';
  UPDATE approval_requests
     SET status = 'partially_approved', current_step_sequence = v_next_sequence
   WHERE id = v_request.id;

  RETURN jsonb_build_object(
    'request_id', v_request.id,
    'status', 'partially_approved',
    'current_step_sequence', v_next_sequence,
    'next_required_approval', v_next_sequence,
    'final_actionable', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_reject_approval_request(
  p_request_id UUID,
  p_current_record_version TEXT,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request approval_requests%ROWTYPE;
  v_rule approval_workflows%ROWTYPE;
  v_instance approval_instances%ROWTYPE;
BEGIN
  IF NULLIF(trim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'rejection reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT r.* INTO v_request
  FROM approval_requests r
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND OR NOT is_company_member(v_request.company_id) THEN
    RAISE EXCEPTION 'approval request not found in caller company scope' USING ERRCODE = '42501';
  END IF;
  IF v_request.status NOT IN ('pending','partially_approved') THEN
    RAISE EXCEPTION 'approval request is not actionable (status %)', v_request.status
      USING ERRCODE = '55000';
  END IF;

  IF p_current_record_version IS DISTINCT FROM v_request.record_version THEN
    UPDATE approval_requests
       SET status = 'superseded', decision_reason = 'source version changed before rejection',
           decided_at = NOW()
     WHERE id = v_request.id;
    UPDATE approval_instances
       SET status = 'superseded', acted_at = NOW()
     WHERE request_id = v_request.id AND status IN ('waiting','pending');
    RETURN jsonb_build_object(
      'request_id', v_request.id, 'status', 'superseded',
      'final_actionable', false, 'error', 'stale_record'
    );
  END IF;

  SELECT * INTO v_rule FROM approval_workflows WHERE id = v_request.workflow_id;
  SELECT i.* INTO v_instance
  FROM approval_instances i
  WHERE i.request_id = v_request.id
    AND i.step_sequence = v_request.current_step_sequence
    AND i.status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval request has no pending instance for current step'
      USING ERRCODE = '55000';
  END IF;
  IF NOT fn_can_decide_approval_request(
    v_request.company_id, v_request.module_type, v_request.source_document_type
  ) OR NOT fn_is_valid_approval_candidate(
    auth.uid(), v_request.company_id, v_request.branch_id,
    v_instance.required_approver_type, v_instance.required_approver_id,
    v_instance.approver_role_code
  ) THEN
    RAISE EXCEPTION 'current user is not authorized to reject this approval step'
      USING ERRCODE = '42501';
  END IF;
  IF v_request.branch_id IS NOT NULL
     AND NOT fn_can_access_company_branch(v_request.company_id, v_request.branch_id)
  THEN
    RAISE EXCEPTION 'rejection denied outside branch scope' USING ERRCODE = '42501';
  END IF;
  IF v_rule.enforce_requester_separation AND auth.uid() = v_request.requester_id THEN
    RAISE EXCEPTION 'segregation of duties prevents requester self-rejection'
      USING ERRCODE = '42501';
  END IF;
  IF v_request.module_type = 'master_data'
     AND fn_has_enforced_master_data_sod_conflict(
       v_request.company_id, v_request.source_document_type, v_request.action_type
     )
  THEN
    RAISE EXCEPTION 'enforced master-data SOD conflict prevents rejection'
      USING ERRCODE = '42501';
  END IF;

  UPDATE approval_instances
     SET status = 'rejected', actual_approver_id = auth.uid(),
         acted_at = NOW(), remarks = trim(p_reason)
   WHERE id = v_instance.id;
  UPDATE approval_instances
     SET status = 'cancelled', acted_at = NOW(), remarks = 'request rejected at an earlier step'
   WHERE request_id = v_request.id AND status = 'waiting';
  UPDATE approval_requests
     SET status = 'rejected', decision_reason = trim(p_reason), decided_at = NOW()
   WHERE id = v_request.id;

  RETURN jsonb_build_object(
    'request_id', v_request.id,
    'status', 'rejected',
    'final_actionable', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_withdraw_approval_request(
  p_request_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request approval_requests%ROWTYPE;
BEGIN
  SELECT r.* INTO v_request
  FROM approval_requests r
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND OR NOT is_company_member(v_request.company_id) THEN
    RAISE EXCEPTION 'approval request not found in caller company scope' USING ERRCODE = '42501';
  END IF;
  IF v_request.status NOT IN ('pending','partially_approved') THEN
    RAISE EXCEPTION 'approval request is not withdrawable (status %)', v_request.status
      USING ERRCODE = '55000';
  END IF;
  IF auth.uid() <> v_request.requester_id AND NOT can_admin_company(v_request.company_id) THEN
    RAISE EXCEPTION 'only the requester or a company administrator may withdraw the request'
      USING ERRCODE = '42501';
  END IF;

  UPDATE approval_instances
     SET status = 'cancelled', acted_at = NOW(),
         remarks = COALESCE(NULLIF(trim(p_reason), ''), 'request withdrawn')
   WHERE request_id = v_request.id AND status IN ('waiting','pending');
  UPDATE approval_requests
     SET status = 'withdrawn',
         decision_reason = COALESCE(NULLIF(trim(p_reason), ''), 'request withdrawn'),
         decided_at = NOW()
   WHERE id = v_request.id;

  RETURN jsonb_build_object(
    'request_id', v_request.id,
    'status', 'withdrawn',
    'final_actionable', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_approval_request_status(p_request_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request approval_requests%ROWTYPE;
BEGIN
  SELECT r.* INTO v_request FROM approval_requests r WHERE r.id = p_request_id;
  IF NOT FOUND OR NOT is_company_member(v_request.company_id) THEN
    RAISE EXCEPTION 'approval request not found in caller company scope' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'request_id', v_request.id,
    'workflow_id', v_request.workflow_id,
    'company_id', v_request.company_id,
    'branch_id', v_request.branch_id,
    'module_type', v_request.module_type,
    'action_type', v_request.action_type,
    'source_document_type', v_request.source_document_type,
    'source_document_id', v_request.source_document_id,
    'source_document_no', v_request.source_document_no,
    'status', v_request.status,
    'current_step_sequence', v_request.current_step_sequence,
    'requester_id', v_request.requester_id,
    'submitted_at', v_request.submitted_at,
    'decided_at', v_request.decided_at,
    'consumed_at', v_request.consumed_at,
    'final_actionable', v_request.status = 'approved' AND v_request.consumed_at IS NULL,
    'history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'step_sequence', i.step_sequence,
        'status', i.status,
        'required_approver_type', i.required_approver_type,
        'approver_role_code', i.approver_role_code,
        'actual_approver_id', i.actual_approver_id,
        'acted_at', i.acted_at,
        'remarks', i.remarks
      ) ORDER BY i.step_sequence)
      FROM approval_instances i WHERE i.request_id = v_request.id
    ), '[]'::JSONB)
  );
END;
$$;

CREATE OR REPLACE FUNCTION fn_approval_inbox(p_company_id UUID DEFAULT NULL)
RETURNS TABLE (
  request_id UUID,
  company_id UUID,
  branch_id UUID,
  workflow_name TEXT,
  module_type TEXT,
  action_type TEXT,
  source_document_type TEXT,
  source_document_id UUID,
  source_document_no TEXT,
  source_document_amount NUMERIC,
  currency_code TEXT,
  status TEXT,
  current_step_sequence INTEGER,
  requester_id UUID,
  record_version TEXT,
  submitted_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.id, r.company_id, r.branch_id, w.workflow_name,
         r.module_type, r.action_type, r.source_document_type,
         r.source_document_id, r.source_document_no, r.source_document_amount,
         r.currency_code, r.status, r.current_step_sequence, r.requester_id,
         r.record_version, r.submitted_at
  FROM approval_requests r
  JOIN approval_workflows w ON w.id = r.workflow_id
  JOIN approval_instances i
    ON i.request_id = r.id
   AND i.step_sequence = r.current_step_sequence
   AND i.status = 'pending'
  WHERE r.status IN ('pending','partially_approved')
    AND (p_company_id IS NULL OR r.company_id = p_company_id)
    AND is_company_member(r.company_id)
    AND fn_can_decide_approval_request(r.company_id, r.module_type, r.source_document_type)
    AND fn_is_valid_approval_candidate(
      auth.uid(), r.company_id, r.branch_id,
      i.required_approver_type, i.required_approver_id, i.approver_role_code
    )
  ORDER BY r.submitted_at, r.id;
$$;

-- 5. Bounded master-data integration: committed MDP-15 imports.
-- Keep the completed MDP-15 implementation intact as an internal core and put
-- the MDP-14 decision/consumption check at its existing public signature.
DO $$
BEGIN
  IF to_regprocedure('public.fn_import_master_data_mdp15_core(uuid,text,jsonb,boolean,text,jsonb)') IS NULL THEN
    ALTER FUNCTION fn_import_master_data(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB)
      RENAME TO fn_import_master_data_mdp15_core;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_import_master_data(
  p_company_id       UUID,
  p_master_key       TEXT,
  p_rows             JSONB,
  p_preview          BOOLEAN DEFAULT true,
  p_idempotency_key  TEXT DEFAULT NULL,
  p_options          JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rule RECORD;
  v_request approval_requests%ROWTYPE;
  v_request_id UUID;
  v_hash TEXT;
  v_result JSONB;
BEGIN
  IF p_preview THEN
    RETURN fn_import_master_data_mdp15_core(
      p_company_id, p_master_key, p_rows, true, p_idempotency_key, p_options
    );
  END IF;

  SELECT * INTO v_rule
  FROM fn_resolve_approval_rule(
    p_company_id, NULL, 'master_data', p_master_key, 'import',
    NULL, NULL, auth.uid(), NOW()
  );

  IF NOT FOUND THEN
    RETURN fn_import_master_data_mdp15_core(
      p_company_id, p_master_key, p_rows, false, p_idempotency_key, p_options
    );
  END IF;

  BEGIN
    v_request_id := NULLIF(p_options ->> 'approval_request_id', '')::UUID;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'approval_request_id must be a UUID' USING ERRCODE = '22023';
  END;
  IF v_request_id IS NULL THEN
    RAISE EXCEPTION 'approval request % is required before committing this master-data import',
      v_rule.workflow_name USING ERRCODE = '55000';
  END IF;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'company_id', p_company_id,
    'master_key', p_master_key,
    'rows', COALESCE(p_rows, 'null'::JSONB)
  )::TEXT, 'UTF8'), 'sha256'), 'hex');

  SELECT r.* INTO v_request
  FROM approval_requests r
  WHERE r.id = v_request_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_request.company_id <> p_company_id
     OR v_request.workflow_id <> v_rule.workflow_id
     OR v_request.module_type <> 'master_data'
     OR v_request.action_type <> 'import'
     OR v_request.source_document_type <> p_master_key
     OR v_request.requester_id <> auth.uid()
  THEN
    RAISE EXCEPTION 'approval request does not match this master-data import'
      USING ERRCODE = '42501';
  END IF;
  IF v_request.status <> 'approved' THEN
    RAISE EXCEPTION 'approval request is not approved (status %)', v_request.status
      USING ERRCODE = '55000';
  END IF;
  IF v_request.record_version <> v_hash THEN
    RAISE EXCEPTION 'approved import payload is stale or changed' USING ERRCODE = '55000';
  END IF;
  IF v_request.consumed_at IS NOT NULL
     AND (
       p_idempotency_key IS NULL
       OR v_request.consumption_idempotency_key IS DISTINCT FROM p_idempotency_key
     )
  THEN
    RAISE EXCEPTION 'approval request was already consumed by another import commit'
      USING ERRCODE = '55000';
  END IF;

  v_result := fn_import_master_data_mdp15_core(
    p_company_id, p_master_key, p_rows, false, p_idempotency_key, p_options
  );

  IF v_result ->> 'status' = 'imported' THEN
    UPDATE approval_requests
       SET consumed_at = COALESCE(consumed_at, NOW()),
           consumed_by = COALESCE(consumed_by, auth.uid()),
           consumption_idempotency_key = COALESCE(consumption_idempotency_key, p_idempotency_key)
     WHERE id = v_request.id;
  END IF;

  RETURN v_result || jsonb_build_object('approval_request_id', v_request.id);
END;
$$;

-- 6. RLS and grants. Configuration remains admin-maintained; request state is
-- read through tenant scope and mutated only through the server-authoritative RPCs.
ALTER TABLE approval_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS auth_read_approval_workflows ON approval_workflows;
CREATE POLICY auth_read_approval_workflows
  ON approval_workflows FOR SELECT TO authenticated
  USING (is_company_member(company_id));

DROP POLICY IF EXISTS auth_insert_approval_workflows ON approval_workflows;
CREATE POLICY auth_insert_approval_workflows
  ON approval_workflows FOR INSERT TO authenticated
  WITH CHECK (can_admin_company(company_id));
DROP POLICY IF EXISTS auth_update_approval_workflows ON approval_workflows;
CREATE POLICY auth_update_approval_workflows
  ON approval_workflows FOR UPDATE TO authenticated
  USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id));
DROP POLICY IF EXISTS auth_delete_approval_workflows ON approval_workflows;
CREATE POLICY auth_delete_approval_workflows
  ON approval_workflows FOR DELETE TO authenticated
  USING (can_admin_company(company_id));

DROP POLICY IF EXISTS auth_read_workflow_steps ON approval_workflow_steps;
CREATE POLICY auth_read_workflow_steps
  ON approval_workflow_steps FOR SELECT TO authenticated
  USING (is_company_member(company_id));
DROP POLICY IF EXISTS auth_insert_workflow_steps ON approval_workflow_steps;
CREATE POLICY auth_insert_workflow_steps
  ON approval_workflow_steps FOR INSERT TO authenticated
  WITH CHECK (can_admin_company(company_id));
DROP POLICY IF EXISTS auth_update_workflow_steps ON approval_workflow_steps;
CREATE POLICY auth_update_workflow_steps
  ON approval_workflow_steps FOR UPDATE TO authenticated
  USING (can_admin_company(company_id)) WITH CHECK (can_admin_company(company_id));
DROP POLICY IF EXISTS auth_delete_workflow_steps ON approval_workflow_steps;
CREATE POLICY auth_delete_workflow_steps
  ON approval_workflow_steps FOR DELETE TO authenticated
  USING (can_admin_company(company_id));

DROP POLICY IF EXISTS auth_read_approval_instances ON approval_instances;
CREATE POLICY auth_read_approval_instances
  ON approval_instances FOR SELECT TO authenticated
  USING (is_company_member(company_id));
DROP POLICY IF EXISTS auth_insert_approval_instances ON approval_instances;
DROP POLICY IF EXISTS auth_update_approval_instances ON approval_instances;
DROP POLICY IF EXISTS auth_delete_approval_instances ON approval_instances;

DROP POLICY IF EXISTS approval_requests_read ON approval_requests;
CREATE POLICY approval_requests_read
  ON approval_requests FOR SELECT TO authenticated
  USING (is_company_member(company_id));

REVOKE ALL ON TABLE approval_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE approval_requests TO authenticated;
GRANT ALL ON TABLE approval_requests TO service_role;

REVOKE INSERT, UPDATE, DELETE ON TABLE approval_instances FROM authenticated;
GRANT SELECT ON TABLE approval_instances TO authenticated;

REVOKE ALL ON FUNCTION fn_import_master_data_mdp15_core(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_import_master_data_mdp15_core(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB)
  TO service_role;

REVOKE ALL ON FUNCTION fn_approval_rule_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_approval_step_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_approval_source_permission_action(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_can_submit_approval_request(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_can_decide_approval_request(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_is_valid_approval_candidate(UUID, UUID, UUID, TEXT, UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_approval_step_has_candidate(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_has_enforced_master_data_sod_conflict(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_resolve_approval_rule(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, TEXT, UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_get_approval_decision(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_submit_approval_request(UUID, UUID, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, NUMERIC, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_approve_approval_request(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_reject_approval_request(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_withdraw_approval_request(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_get_approval_request_status(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_approval_inbox(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_import_master_data(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_resolve_approval_rule(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, TEXT, UUID, TIMESTAMPTZ) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_get_approval_decision(UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, TEXT, TIMESTAMPTZ) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_submit_approval_request(UUID, UUID, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, NUMERIC, TEXT, JSONB, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_approve_approval_request(UUID, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_reject_approval_request(UUID, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_withdraw_approval_request(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_get_approval_request_status(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_approval_inbox(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_import_master_data(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB) TO authenticated, service_role;

COMMENT ON TABLE approval_requests IS
  'MDP-14 approval request header: immutable source version, matched workflow, lifecycle state, requester context, and bounded action consumption evidence.';
COMMENT ON TABLE approval_instances IS
  'Existing approval step instances extended by MDP-14 with request linkage, waiting/pending sequence state, and role-code assignment.';
COMMENT ON FUNCTION fn_submit_approval_request(UUID, UUID, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, NUMERIC, TEXT, JSONB, TEXT) IS
  'MDP-14 submits an idempotent, version-bound approval request after server-side rule, permission, branch, route, and approver validation.';
COMMENT ON FUNCTION fn_approve_approval_request(UUID, TEXT, TEXT) IS
  'MDP-14 atomically approves the current step with row locking, role/user resolution, branch scope, SOD, version, and lifecycle enforcement.';
COMMENT ON FUNCTION fn_reject_approval_request(UUID, TEXT, TEXT) IS
  'MDP-14 rejects the current approval step and closes all later waiting steps.';
COMMENT ON FUNCTION fn_withdraw_approval_request(UUID, TEXT) IS
  'MDP-14 allows the requester or company administrator to withdraw an actionable request.';
COMMENT ON FUNCTION fn_import_master_data(UUID, TEXT, JSONB, BOOLEAN, TEXT, JSONB) IS
  'MDP-14 compatibility wrapper around the frozen MDP-15 core. Preview and unconfigured commits are unchanged; configured commits require and consume a matching approved request.';
