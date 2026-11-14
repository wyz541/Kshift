CREATE SCHEMA kshift;

CREATE TABLE kshift.schema_metadata (
    id smallint PRIMARY KEY CHECK (id = 1),
    schema_version integer NOT NULL CHECK (schema_version > 0),
    migration_digest text NOT NULL CHECK (length(migration_digest) = 64),
    applied_at timestamptz NOT NULL,
    postgres_version text NOT NULL
);

CREATE TABLE kshift.app_user (
    id uuid PRIMARY KEY,
    display_name text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 120),
    is_admin boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE kshift.project (
    id uuid PRIMARY KEY,
    name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
    time_zone text NOT NULL CHECK (length(time_zone) BETWEEN 1 AND 64),
    current_revision bigint NOT NULL DEFAULT 0 CHECK (current_revision >= 0),
    created_by uuid NOT NULL REFERENCES kshift.app_user(id),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);

CREATE TABLE kshift.project_member (
    project_id uuid NOT NULL REFERENCES kshift.project(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES kshift.app_user(id),
    role text NOT NULL CHECK (role IN ('viewer', 'editor', 'admin')),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    PRIMARY KEY (project_id, user_id)
);

CREATE INDEX project_member_user_idx
    ON kshift.project_member (user_id, project_id);

CREATE TABLE kshift.task (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES kshift.project(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
    description_markdown text NOT NULL DEFAULT '' CHECK (length(description_markdown) <= 20000),
    status text NOT NULL CHECK (status IN ('todo', 'in_progress', 'blocked', 'done')),
    priority smallint NOT NULL CHECK (priority BETWEEN 1 AND 5),
    planned_on date NOT NULL,
    starts_on date,
    due_on date,
    tags text[] NOT NULL DEFAULT ARRAY[]::text[],
    parent_task_id uuid REFERENCES kshift.task(id),
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    created_by uuid NOT NULL REFERENCES kshift.app_user(id),
    updated_by uuid NOT NULL REFERENCES kshift.app_user(id),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES kshift.app_user(id),
    CHECK (starts_on IS NULL OR starts_on <= planned_on),
    CHECK (due_on IS NULL OR due_on >= planned_on),
    CHECK (due_on IS NULL OR starts_on IS NULL OR due_on >= starts_on)
);

CREATE INDEX task_project_active_idx
    ON kshift.task (project_id, planned_on, created_at)
    WHERE deleted_at IS NULL;

CREATE TABLE kshift.task_assignee (
    task_id uuid NOT NULL REFERENCES kshift.task(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES kshift.app_user(id),
    PRIMARY KEY (task_id, user_id)
);

CREATE INDEX task_assignee_user_idx
    ON kshift.task_assignee (user_id, task_id);

CREATE TABLE kshift.task_dependency (
    task_id uuid NOT NULL REFERENCES kshift.task(id) ON DELETE CASCADE,
    depends_on_task_id uuid NOT NULL REFERENCES kshift.task(id),
    PRIMARY KEY (task_id, depends_on_task_id),
    CHECK (task_id <> depends_on_task_id)
);

CREATE TABLE kshift.audit_log (
    id uuid PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES kshift.project(id),
    actor_id uuid NOT NULL REFERENCES kshift.app_user(id),
    client_id uuid NOT NULL,
    command_id uuid NOT NULL,
    command_name text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    before_data jsonb,
    after_data jsonb,
    occurred_at timestamptz NOT NULL
);

CREATE INDEX audit_project_time_idx
    ON kshift.audit_log (project_id, occurred_at DESC);

CREATE INDEX audit_command_idx
    ON kshift.audit_log (client_id, command_id);

CREATE TABLE kshift.command_result (
    client_id uuid NOT NULL,
    command_id uuid NOT NULL,
    project_id uuid NOT NULL REFERENCES kshift.project(id),
    actor_id uuid NOT NULL REFERENCES kshift.app_user(id),
    request_digest bytea NOT NULL CHECK (octet_length(request_digest) = 32),
    response_payload bytea NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    PRIMARY KEY (client_id, command_id)
);

CREATE INDEX command_result_expiry_idx
    ON kshift.command_result (expires_at);

CREATE TABLE kshift.change_event (
    id bigserial PRIMARY KEY,
    project_id uuid NOT NULL REFERENCES kshift.project(id) ON DELETE CASCADE,
    revision bigint NOT NULL CHECK (revision > 0),
    schema_version integer NOT NULL CHECK (schema_version > 0),
    command_id uuid NOT NULL,
    payload bytea NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    UNIQUE (project_id, revision)
);

CREATE INDEX change_event_project_revision_idx
    ON kshift.change_event (project_id, revision);

CREATE INDEX change_event_expiry_idx
    ON kshift.change_event (expires_at);
