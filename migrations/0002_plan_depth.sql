CREATE TABLE kshift.plan_snapshot (
    project_id uuid PRIMARY KEY REFERENCES kshift.project(id) ON DELETE CASCADE,
    revision bigint NOT NULL CHECK (revision > 0),
    payload jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE kshift.plan_state (
    project_id uuid NOT NULL REFERENCES kshift.project(id) ON DELETE CASCADE,
    revision bigint NOT NULL CHECK (revision >= 0),
    payload jsonb NOT NULL,
    actor_id uuid NOT NULL REFERENCES kshift.app_user(id),
    action text NOT NULL,
    summary text NOT NULL,
    restored_from_revision bigint,
    content_sha256 text NOT NULL CHECK (length(content_sha256) = 64),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (project_id, revision)
);

CREATE INDEX plan_state_project_time_idx
    ON kshift.plan_state (project_id, created_at DESC);

CREATE TABLE kshift.plan_attachment (
    project_id uuid NOT NULL REFERENCES kshift.project(id) ON DELETE CASCADE,
    sha256 text NOT NULL CHECK (length(sha256) = 64),
    media_type text NOT NULL,
    byte_size bigint NOT NULL CHECK (byte_size >= 0 AND byte_size <= 10485760),
    filename text NOT NULL,
    content bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (project_id, sha256),
    CHECK (octet_length(content) = byte_size)
);
