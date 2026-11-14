\set ON_ERROR_STOP on
WITH changed AS (
  INSERT INTO kshift.project_member (project_id, user_id, role, created_at, updated_at)
  SELECT :'project_id'::uuid, :'user_id'::uuid, :'role'::text, now(), now()
  WHERE EXISTS (SELECT 1 FROM kshift.project WHERE id = :'project_id'::uuid)
    AND EXISTS (SELECT 1 FROM kshift.app_user WHERE id = :'user_id'::uuid)
  ON CONFLICT (project_id, user_id)
  DO UPDATE SET role = EXCLUDED.role, updated_at = now()
  RETURNING 1
)
SELECT CASE WHEN count(*) = 1 THEN 'granted' ELSE 'missing-project-or-user' END AS result
FROM changed;
