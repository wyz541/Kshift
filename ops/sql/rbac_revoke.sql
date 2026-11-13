\set ON_ERROR_STOP on
WITH deleted AS (
  DELETE FROM kshift.project_member
  WHERE project_id = :'project_id'::uuid
    AND user_id = :'user_id'::uuid
  RETURNING 1
)
SELECT CASE WHEN count(*) = 1 THEN 'revoked' ELSE 'not-found' END AS result
FROM deleted;
