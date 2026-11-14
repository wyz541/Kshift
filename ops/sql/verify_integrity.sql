\set ON_ERROR_STOP on
CREATE TEMP VIEW kshift_integrity_checks AS
SELECT * FROM (VALUES
  (
    'schema-metadata-present',
    EXISTS (SELECT 1 FROM kshift.schema_metadata WHERE id = 1)
  ),
  (
    'schema-version-positive',
    COALESCE((SELECT schema_version > 0 FROM kshift.schema_metadata WHERE id = 1), false)
  ),
  (
    'schema-digest-length',
    COALESCE((SELECT length(migration_digest) = 64 FROM kshift.schema_metadata WHERE id = 1), false)
  ),
  ('project-revision-nonnegative', NOT EXISTS (SELECT 1 FROM kshift.project WHERE current_revision < 0)),
  ('task-version-positive', NOT EXISTS (SELECT 1 FROM kshift.task WHERE version < 1)),
  (
    'command-result-expiry',
    NOT EXISTS (SELECT 1 FROM kshift.command_result WHERE expires_at <= created_at)
  ),
  (
    'change-event-expiry',
    NOT EXISTS (SELECT 1 FROM kshift.change_event WHERE expires_at <= created_at)
  ),
  (
    'change-event-payload',
    NOT EXISTS (SELECT 1 FROM kshift.change_event WHERE octet_length(payload) = 0)
  ),
  (
    'change-event-revision-positive',
    NOT EXISTS (SELECT 1 FROM kshift.change_event WHERE revision < 1)
  )
) AS checks(name, passed);

SELECT json_build_object(
  'status', CASE WHEN bool_and(passed) THEN 'passed' ELSE 'failed' END,
  'checks', json_agg(json_build_object('name', name, 'status', CASE WHEN passed THEN 'passed' ELSE 'failed' END) ORDER BY name)
)::text
FROM kshift_integrity_checks;

DO $$
DECLARE
  failure_names text;
BEGIN
  SELECT string_agg(name, ', ') INTO failure_names
  FROM kshift_integrity_checks
  WHERE NOT passed;
  IF failure_names IS NOT NULL THEN
    RAISE EXCEPTION 'integrity checks failed: %', failure_names;
  END IF;
END
$$;
