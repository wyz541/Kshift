\set ON_ERROR_STOP on

GRANT USAGE ON SCHEMA kshift TO kshift_app, kshift_backup, kshift_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA kshift TO kshift_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA kshift TO kshift_app;
GRANT SELECT ON ALL TABLES IN SCHEMA kshift TO kshift_backup;
GRANT SELECT ON kshift.app_user, kshift.project TO kshift_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON kshift.project_member TO kshift_admin;

CREATE OR REPLACE VIEW kshift.project_overview AS
SELECT
  project.id AS project_id,
  project.name AS project_name,
  project.current_revision,
  project.created_at,
  project.updated_at,
  count(DISTINCT task.id)::bigint AS task_count,
  count(DISTINCT member.user_id)::bigint AS member_count
FROM kshift.project
LEFT JOIN kshift.task ON task.project_id = project.id AND task.deleted_at IS NULL
LEFT JOIN kshift.project_member member ON member.project_id = project.id
GROUP BY project.id, project.name, project.current_revision, project.created_at, project.updated_at;

CREATE OR REPLACE VIEW kshift.member_overview AS
SELECT
  member.project_id,
  project.name AS project_name,
  member.user_id,
  app_user.display_name,
  member.role,
  member.created_at,
  member.updated_at,
  app_user.is_active
FROM kshift.project_member member
JOIN kshift.project ON project.id = member.project_id
JOIN kshift.app_user ON app_user.id = member.user_id;

CREATE OR REPLACE VIEW kshift.task_overview AS
SELECT
  task.project_id,
  task.id AS task_id,
  task.title,
  task.status,
  task.priority,
  task.planned_on,
  task.version,
  task.updated_at
FROM kshift.task
WHERE task.deleted_at IS NULL;

CREATE OR REPLACE VIEW kshift.command_receipts AS
SELECT
  result.project_id,
  result.client_id,
  result.command_id,
  result.actor_id,
  result.created_at,
  result.expires_at
FROM kshift.command_result result;

CREATE OR REPLACE VIEW kshift.change_events AS
SELECT
  event.id,
  event.project_id,
  event.revision,
  event.schema_version,
  event.command_id,
  octet_length(event.payload)::bigint AS payload_bytes,
  event.created_at,
  event.expires_at
FROM kshift.change_event event;

CREATE OR REPLACE VIEW kshift.schema_migrations AS
SELECT schema_version, migration_digest, applied_at, postgres_version
FROM kshift.schema_metadata
WHERE id = 1;

REVOKE ALL ON kshift.project_overview, kshift.member_overview, kshift.task_overview,
  kshift.command_receipts, kshift.change_events, kshift.schema_migrations FROM PUBLIC;
GRANT SELECT ON kshift.project_overview, kshift.member_overview, kshift.task_overview,
  kshift.command_receipts, kshift.change_events, kshift.schema_migrations TO kshift_admin;
