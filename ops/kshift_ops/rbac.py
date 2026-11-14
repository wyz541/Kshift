from __future__ import annotations

import re
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

from .errors import KshiftOpsError
from .postgres import PgConnection
from .util import CommandRunner, parse_csv_output

ROLE_PRECEDENCE = {"viewer": 1, "editor": 2, "admin": 3}
UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
    r"[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)


def validate_uuid(value: str, label: str) -> str:
    if not UUID_RE.fullmatch(value):
        raise KshiftOpsError("{0} must be a UUID".format(label))
    return value.lower()


def validate_role(value: str) -> str:
    if value not in ROLE_PRECEDENCE:
        raise KshiftOpsError("role must be viewer, editor or admin")
    return value


def _sql_path(name: str) -> Path:
    return Path(__file__).resolve().parents[1] / "sql" / name


def grant_role(
    *,
    connection: PgConnection,
    project_id: str,
    user_id: str,
    role: str,
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    project = validate_uuid(project_id, "project_id")
    user = validate_uuid(user_id, "user_id")
    validated_role = validate_role(role)
    runner = runner or CommandRunner()
    result = runner.run(
        [
            "psql",
            "--tuples-only",
            "--no-align",
            "--set=ON_ERROR_STOP=1",
            "--set=project_id={0}".format(project),
            "--set=user_id={0}".format(user),
            "--set=role={0}".format(validated_role),
            "--file",
            str(_sql_path("rbac_grant.sql")),
        ],
        env=connection.environment(),
    )
    if result.stdout.strip() != "granted":
        raise KshiftOpsError("project or user does not exist")
    return {"project_id": project, "user_id": user, "role": validated_role, "status": "granted"}


def revoke_role(
    *,
    connection: PgConnection,
    project_id: str,
    user_id: str,
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    project = validate_uuid(project_id, "project_id")
    user = validate_uuid(user_id, "user_id")
    runner = runner or CommandRunner()
    result = runner.run(
        [
            "psql",
            "--tuples-only",
            "--no-align",
            "--set=ON_ERROR_STOP=1",
            "--set=project_id={0}".format(project),
            "--set=user_id={0}".format(user),
            "--file",
            str(_sql_path("rbac_revoke.sql")),
        ],
        env=connection.environment(),
    )
    if result.stdout.strip() != "revoked":
        raise KshiftOpsError("project membership was not found")
    return {"project_id": project, "user_id": user, "status": "revoked"}


def list_roles(
    *,
    connection: PgConnection,
    project_id: Optional[str],
    runner: Optional[CommandRunner] = None,
) -> List[Dict[str, str]]:
    query = """
SELECT project_id::text, user_id::text, role::text, created_at::text, updated_at::text
FROM kshift.project_member
"""
    args = ["psql", "--csv"]
    if project_id is not None:
        query += " WHERE project_id = :'project_id'::uuid"
        args.append("--set=project_id={0}".format(validate_uuid(project_id, "project_id")))
    query += " ORDER BY project_id, user_id;"
    runner = runner or CommandRunner()
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as handle:
        handle.write(query)
        query_path = Path(handle.name)
    try:
        args.extend(["--file", str(query_path)])
        result = runner.run(args, env=connection.environment())
    finally:
        query_path.unlink(missing_ok=True)
    rows = parse_csv_output(result.stdout.strip())
    if not rows:
        return []
    headers = rows[0]
    expected = ["project_id", "user_id", "role", "created_at", "updated_at"]
    if headers != expected:
        raise KshiftOpsError("unexpected RBAC query columns")
    return [dict(zip(headers, row)) for row in rows[1:]]
