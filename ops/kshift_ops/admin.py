from __future__ import annotations

from dataclasses import asdict, dataclass
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

from .errors import KshiftOpsError
from .postgres import PgConnection
from .util import CommandRunner, parse_csv_output


@dataclass(frozen=True)
class AdminView:
    name: str
    description: str
    order_by: str
    search_column: Optional[str]

    def as_dict(self) -> Dict[str, Any]:
        return asdict(self)


ADMIN_VIEWS = {
    "project_overview": AdminView(
        "project_overview", "Project revision and task counts", "project_id", "project_name"
    ),
    "member_overview": AdminView(
        "member_overview", "Project memberships and roles", "project_id, user_id", "display_name"
    ),
    "task_overview": AdminView(
        "task_overview", "Project-safe task metadata", "project_id, task_id", "title"
    ),
    "command_receipts": AdminView(
        "command_receipts", "Idempotent command outcomes", "project_id, created_at", "command_id"
    ),
    "change_events": AdminView(
        "change_events", "Outbox event metadata without payloads", "project_id, revision", "command_id"
    ),
    "schema_migrations": AdminView(
        "schema_migrations", "Applied migration digests", "schema_version", "postgres_version"
    ),
}


def list_admin_views() -> List[Dict[str, Any]]:
    return [ADMIN_VIEWS[key].as_dict() for key in sorted(ADMIN_VIEWS)]


def show_admin_view(
    *,
    connection: PgConnection,
    view: str,
    limit: int,
    offset: int,
    search: Optional[str],
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    if view not in ADMIN_VIEWS:
        raise KshiftOpsError("view is not in the restricted allowlist: {0}".format(view))
    if limit < 1 or limit > 200:
        raise KshiftOpsError("limit must be between 1 and 200")
    if offset < 0:
        raise KshiftOpsError("offset must be zero or greater")
    spec = ADMIN_VIEWS[view]
    query = "SELECT * FROM kshift.{0}".format(spec.name)
    args = [
        "psql",
        "--csv",
        "--set=limit={0}".format(limit),
        "--set=offset={0}".format(offset),
    ]
    if search is not None and search != "":
        if spec.search_column is None:
            raise KshiftOpsError("view does not support search: {0}".format(view))
        query += " WHERE {0} ILIKE '%' || :'search' || '%'".format(spec.search_column)
        args.append("--set=search={0}".format(search))
    query += " ORDER BY {0} LIMIT :limit OFFSET :offset;".format(spec.order_by)
    runner = runner or CommandRunner()
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as handle:
        handle.write(query + "\n")
        query_path = Path(handle.name)
    try:
        args.extend(["--file", str(query_path)])
        result = runner.run(args, env=connection.environment())
    finally:
        query_path.unlink(missing_ok=True)
    rows = parse_csv_output(result.stdout.strip())
    if not rows:
        return {"view": view, "columns": [], "rows": []}
    return {"view": view, "columns": rows[0], "rows": rows[1:]}
