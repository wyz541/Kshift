from __future__ import annotations

import json
import shutil
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Optional

from .errors import KshiftOpsError
from .migrations import validate_server_bin
from .postgres import PgConnection
from .util import CommandRunner


def check_http(url: str, timeout_seconds: float, runner: Optional[CommandRunner] = None) -> Dict[str, Any]:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            body = response.read(65536).decode("utf-8", errors="replace")
            status = response.status
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
        return {"status": "failed", "url": url, "error": str(error)}
    result: Dict[str, Any] = {"status": "passed" if status == 200 else "failed", "http_status": status}
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        payload = None
    if isinstance(payload, dict):
        result["payload_status"] = payload.get("status")
    return result


def check_server(
    server_bin: Path,
    connection: PgConnection,
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    runner = runner or CommandRunner()
    executable = validate_server_bin(server_bin)
    env = connection.environment()
    env["KSHIFT_DATABASE_URL"] = connection.uri()
    result = runner.run([str(executable), "check"], env=env)
    return {"status": "passed", "output": result.stdout.strip()}


def check_database(
    connection: PgConnection, runner: Optional[CommandRunner] = None
) -> Dict[str, Any]:
    runner = runner or CommandRunner()
    query = """
SELECT json_build_object(
  'database_name', current_database(),
  'postgres_version', current_setting('server_version'),
  'schema_version', COALESCE((SELECT schema_version FROM kshift.schema_metadata WHERE id = 1), 0),
  'schema_digest', COALESCE((SELECT migration_digest FROM kshift.schema_metadata WHERE id = 1), '')
)::text;
""".strip()
    result = runner.run(
        ["psql", "--no-align", "--tuples-only", "--command", query],
        env=connection.environment(),
    )
    try:
        payload = json.loads(result.stdout.strip())
    except json.JSONDecodeError as error:
        raise KshiftOpsError("health database query returned invalid JSON") from error
    if not isinstance(payload, dict):
        raise KshiftOpsError("health database query returned a non-object")
    payload["status"] = "passed"
    return payload


def check_disk(path: Path, minimum_free_bytes: int) -> Dict[str, Any]:
    usage = shutil.disk_usage(str(path))
    status = "passed" if usage.free >= minimum_free_bytes else "failed"
    return {
        "status": status,
        "path": str(path),
        "free_bytes": usage.free,
        "minimum_free_bytes": minimum_free_bytes,
    }


def aggregate(
    *,
    http_url: Optional[str],
    server_bin: Optional[Path],
    database: Optional[PgConnection],
    disk_path: Optional[Path],
    minimum_free_bytes: int,
    timeout_seconds: float,
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    checks: Dict[str, Any] = {}
    if http_url:
        checks["http"] = check_http(http_url, timeout_seconds, runner)
    if server_bin:
        if database is None:
            raise KshiftOpsError("server health check needs a database connection")
        checks["server"] = check_server(server_bin, database, runner)
    elif database:
        checks["database"] = check_database(database, runner)
    if disk_path:
        checks["disk"] = check_disk(disk_path, minimum_free_bytes)
    if not checks:
        raise KshiftOpsError("health check needs --http-url, --database-url-env or --disk-path")
    status = "passed" if all(value.get("status") == "passed" for value in checks.values()) else "failed"
    return {"status": status, "checks": checks}
