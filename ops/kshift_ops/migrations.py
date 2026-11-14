from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, Optional

from .backup import create_backup
from .errors import KshiftOpsError
from .postgres import PgConnection
from .util import CommandRunner, parse_csv_output, require_source_commit, utc_now


def validate_server_bin(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if not resolved.is_file():
        raise KshiftOpsError("server binary is missing: {0}".format(resolved))
    if not os.access(str(resolved), os.X_OK):
        raise KshiftOpsError("server binary is not executable: {0}".format(resolved))
    return resolved


def migrate(
    *,
    connection: PgConnection,
    server_bin: Path,
    source_commit: str,
    backup_output_directory: Optional[Path],
    age_recipient: Optional[str],
    allow_unencrypted_backup: bool,
    allow_no_backup: bool,
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    runner = runner or CommandRunner()
    commit = require_source_commit(source_commit)
    executable = validate_server_bin(server_bin)
    result: Dict[str, Any] = {
        "status": "migration-started",
        "source_commit": commit,
        "server_bin": str(executable),
    }

    if backup_output_directory is None and not allow_no_backup:
        raise KshiftOpsError(
            "migration requires --backup-output; use --allow-no-backup only for disposable data"
        )
    if backup_output_directory is not None:
        backup = create_backup(
            output_directory=backup_output_directory,
            kind="migration",
            connection=connection,
            source_commit=commit,
            age_recipient=age_recipient,
            allow_unencrypted=allow_unencrypted_backup,
            runner=runner,
        )
        result["pre_migration_backup"] = backup.metadata_path

    server_env = connection.environment()
    server_env["KSHIFT_DATABASE_URL"] = connection.uri()
    migrate_result = runner.run([str(executable), "migrate"], env=server_env)
    check_result = runner.run([str(executable), "check"], env=server_env)
    result.update(
        {
            "status": "migrated",
            "migration_output": migrate_result.stdout.strip(),
            "check_output": check_result.stdout.strip(),
            "completed_at": utc_now().isoformat().replace("+00:00", "Z"),
        }
    )
    return result


def schema_status(connection: PgConnection, runner: Optional[CommandRunner] = None) -> Dict[str, Any]:
    runner = runner or CommandRunner()
    query = (
        "SELECT schema_version::text, migration_digest, applied_at::text, postgres_version "
        "FROM kshift.schema_metadata WHERE id = 1;"
    )
    result = runner.run(
        ["psql", "--csv", "--command", query],
        env=connection.environment(),
    )
    rows = parse_csv_output(result.stdout.strip())
    if not rows:
        raise KshiftOpsError("schema metadata is missing; run kshift-server migrate")
    headers = rows[0]
    values = rows[1] if len(rows) > 1 else None
    if values is None:
        raise KshiftOpsError("schema metadata is missing; run kshift-server migrate")
    return {
        "status": "passed",
        "schema_version": values[headers.index("schema_version")],
        "migration_digest": values[headers.index("migration_digest")],
        "applied_at": values[headers.index("applied_at")],
        "postgres_version": values[headers.index("postgres_version")],
    }
