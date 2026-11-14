from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from .errors import KshiftOpsError
from .postgres import PgConnection
from .util import (
    CommandRunner,
    ensure_private_directory,
    isoformat_z,
    read_json,
    require_safe_name,
    require_sha256,
    require_source_commit,
    sha256_file,
    utc_now,
    write_json_atomic,
)

BACKUP_KINDS = {
    "scheduled-4h",
    "weekly",
    "monthly",
    "migration",
    "release",
    "manual",
}
SCRATCH_DATABASE_RE = re.compile(r"^kshift_restore_drill_[0-9]{8}T[0-9]{6}Z_[0-9a-f]{8}$")


@dataclass(frozen=True)
class CreateBackupResult:
    backup_path: str
    metadata_path: str
    sha256: str
    size: int
    encrypted: bool
    source_commit: str
    schema_version: int


@dataclass(frozen=True)
class RestoreDrillResult:
    status: str
    evidence_path: str
    scratch_database: str
    schema_version: int
    integrity_output: str


def _database_metadata(connection: PgConnection, runner: CommandRunner) -> Dict[str, Any]:
    query = """
SELECT json_build_object(
  'database_name', current_database(),
  'postgres_version', current_setting('server_version'),
  'server_version_num', current_setting('server_version_num')::integer,
  'schema_version', COALESCE((SELECT schema_version FROM kshift.schema_metadata WHERE id = 1), 0),
  'schema_digest', COALESCE((SELECT migration_digest FROM kshift.schema_metadata WHERE id = 1), '')
)::text;
""".strip()
    result = runner.run(
        ["psql", "--no-align", "--tuples-only", "--command", query],
        env=connection.environment(),
    )
    try:
        metadata = json.loads(result.stdout.strip())
    except json.JSONDecodeError as error:
        raise KshiftOpsError("database metadata query returned invalid JSON") from error
    if not isinstance(metadata, dict):
        raise KshiftOpsError("database metadata query returned a non-object")
    if int(metadata.get("server_version_num", 0)) < 180000:
        raise KshiftOpsError("Kshift requires PostgreSQL 18 or newer")
    return metadata


def create_backup(
    *,
    output_directory: Path,
    kind: str,
    connection: PgConnection,
    source_commit: str,
    age_recipient: Optional[str],
    allow_unencrypted: bool,
    runner: Optional[CommandRunner] = None,
    now: Optional[datetime] = None,
) -> CreateBackupResult:
    if kind not in BACKUP_KINDS:
        raise KshiftOpsError("unsupported backup kind: {0}".format(kind))
    commit = require_source_commit(source_commit)
    ensure_private_directory(output_directory)
    runner = runner or CommandRunner()
    created_at = now or utc_now()
    timestamp = created_at.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    stem = require_safe_name("kshift-backup-{0}-{1}".format(timestamp, kind), "backup name")
    encrypted = bool(age_recipient)
    extension = ".dump.age" if encrypted else ".dump"
    backup_path = output_directory / (stem + extension)
    metadata_path = output_directory / (stem + ".metadata.json")
    for path in (backup_path, metadata_path):
        if path.exists():
            raise KshiftOpsError("refusing to overwrite {0}".format(path))

    database_metadata = _database_metadata(connection, runner)
    temporary_root = Path(tempfile.mkdtemp(prefix=".kshift-backup-", dir=str(output_directory)))
    plaintext_path = temporary_root / "plaintext.dump"
    staged_path = temporary_root / backup_path.name
    try:
        dump_env = connection.environment()
        dump_env["PGAPPNAME"] = "kshift-backup"
        runner.run(
            [
                "pg_dump",
                "--format=custom",
                "--no-owner",
                "--no-acl",
                "--file",
                str(plaintext_path),
            ],
            env=dump_env,
        )
        if not plaintext_path.is_file() or plaintext_path.stat().st_size == 0:
            raise KshiftOpsError("pg_dump produced an empty backup")
        runner.run(["pg_restore", "--list", str(plaintext_path)], env=dump_env)
        plaintext_sha256 = sha256_file(plaintext_path)

        if encrypted:
            assert age_recipient is not None
            runner.run(
                [
                    "age",
                    "--encrypt",
                    "--recipient",
                    age_recipient,
                    "--output",
                    str(staged_path),
                    str(plaintext_path),
                ]
            )
            if not staged_path.is_file() or staged_path.stat().st_size == 0:
                raise KshiftOpsError("age produced an empty backup")
        else:
            if not allow_unencrypted:
                raise KshiftOpsError(
                    "backup encryption is required; set --age-recipient or use "
                    "--allow-unencrypted for a local drill"
                )
            shutil.copyfile(str(plaintext_path), str(staged_path))

        stored_sha256 = sha256_file(staged_path)
        stored_size = staged_path.stat().st_size
        os.chmod(staged_path, 0o600)
        os.replace(str(staged_path), str(backup_path))

        metadata = {
            "schema_version": "1.0",
            "product": "Kshift",
            "kind": kind,
            "status": "complete",
            "created_at": isoformat_z(created_at),
            "source_commit": commit,
            "database": {
                "name": database_metadata.get("database_name"),
                "postgres_version": database_metadata.get("postgres_version"),
                "server_version_num": database_metadata.get("server_version_num"),
            },
            "schema": {
                "version": int(database_metadata.get("schema_version", 0)),
                "digest": database_metadata.get("schema_digest", ""),
            },
            "backup": {
                "name": backup_path.name,
                "sha256": stored_sha256,
                "plaintext_sha256": plaintext_sha256,
                "size": stored_size,
                "encrypted": encrypted,
                "format": "pg_dump-custom",
            },
            "retention": {
                "rpo_seconds": 14400,
                "rto_seconds": 14400,
            },
            "checks": {
                "archive_list": "passed",
            },
        }
        write_json_atomic(metadata_path, metadata)
    except Exception:
        backup_path.unlink(missing_ok=True)
        metadata_path.unlink(missing_ok=True)
        raise
    finally:
        shutil.rmtree(str(temporary_root), ignore_errors=True)

    return CreateBackupResult(
        backup_path=str(backup_path),
        metadata_path=str(metadata_path),
        sha256=stored_sha256,
        size=stored_size,
        encrypted=encrypted,
        source_commit=commit,
        schema_version=int(database_metadata.get("schema_version", 0)),
    )


def verify_backup(
    *,
    backup_path: Path,
    metadata_path: Path,
    age_identity: Optional[Path],
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    runner = runner or CommandRunner()
    metadata = read_json(metadata_path)
    backup = metadata.get("backup")
    if not isinstance(backup, dict):
        raise KshiftOpsError("metadata has no backup object")
    expected_name = backup.get("name")
    if expected_name != backup_path.name:
        raise KshiftOpsError("backup filename does not match metadata")
    expected_sha = require_sha256(str(backup.get("sha256", "")), "metadata.backup.sha256")
    expected_size = backup.get("size")
    if not isinstance(expected_size, int) or expected_size < 1:
        raise KshiftOpsError("metadata.backup.size is invalid")
    if not backup_path.is_file():
        raise KshiftOpsError("backup file is missing: {0}".format(backup_path))
    if backup_path.stat().st_size != expected_size:
        raise KshiftOpsError("backup byte count does not match metadata")
    actual_sha = sha256_file(backup_path)
    if actual_sha != expected_sha:
        raise KshiftOpsError("backup SHA-256 does not match metadata")

    result: Dict[str, Any] = {
        "status": "passed",
        "sha256": actual_sha,
        "size": expected_size,
        "encrypted": bool(backup.get("encrypted")),
    }
    if bool(backup.get("encrypted")):
        if not age_identity:
            result["archive_list"] = "not-run-encrypted"
            return result
        with tempfile.TemporaryDirectory(prefix="kshift-verify-") as directory:
            plaintext = Path(directory) / "backup.dump"
            runner.run(
                [
                    "age",
                    "--decrypt",
                    "--identity",
                    str(age_identity),
                    "--output",
                    str(plaintext),
                    str(backup_path),
                ]
            )
            plaintext_sha = sha256_file(plaintext)
            expected_plain = require_sha256(
                str(backup.get("plaintext_sha256", "")), "metadata.backup.plaintext_sha256"
            )
            if plaintext_sha != expected_plain:
                raise KshiftOpsError("decrypted backup SHA-256 does not match metadata")
            runner.run(["pg_restore", "--list", str(plaintext)])
            result["archive_list"] = "passed"
    else:
        runner.run(["pg_restore", "--list", str(backup_path)])
        result["archive_list"] = "passed"
    return result


def restore_drill(
    *,
    backup_path: Path,
    metadata_path: Path,
    admin_connection: PgConnection,
    age_identity: Optional[Path],
    evidence_directory: Optional[Path],
    keep_scratch: bool,
    runner: Optional[CommandRunner] = None,
    now: Optional[datetime] = None,
) -> RestoreDrillResult:
    runner = runner or CommandRunner()
    started_at = now or utc_now()
    metadata = read_json(metadata_path)
    expected_name = metadata.get("backup", {}).get("name") if isinstance(metadata.get("backup"), dict) else None
    if expected_name != backup_path.name:
        raise KshiftOpsError("backup filename does not match metadata")
    verify_backup(
        backup_path=backup_path,
        metadata_path=metadata_path,
        age_identity=age_identity,
        runner=runner,
    )

    scratch_database = "kshift_restore_drill_{0}_{1}".format(
        started_at.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ"), os.urandom(4).hex()
    )
    if not SCRATCH_DATABASE_RE.fullmatch(scratch_database):
        raise KshiftOpsError("generated scratch database name failed safety validation")
    if evidence_directory is None:
        evidence_directory = metadata_path.parent / "restore-drills"
    ensure_private_directory(evidence_directory)
    evidence_path = evidence_directory / (
        "restore-drill-{0}.json".format(started_at.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    )
    if evidence_path.exists():
        evidence_path = evidence_directory / (
            "restore-drill-{0}-{1}.json".format(
                started_at.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ"), os.urandom(2).hex()
            )
        )

    integrity_output = ""
    evidence: Dict[str, Any] = {
        "schema_version": "1.0",
        "product": "Kshift",
        "kind": "pg_restore-drill",
        "status": "running",
        "started_at": isoformat_z(started_at),
        "backup": {
            "name": backup_path.name,
            "sha256": sha256_file(backup_path),
            "source_commit": metadata.get("source_commit"),
        },
        "scratch_database": scratch_database,
        "cleanup": "pending",
        "checks": [],
    }
    created = False
    try:
        with tempfile.TemporaryDirectory(prefix="kshift-restore-") as directory:
            plaintext = Path(directory) / "backup.dump"
            if bool(metadata.get("backup", {}).get("encrypted")):
                if not age_identity:
                    raise KshiftOpsError("restore of an encrypted backup requires --age-identity")
                runner.run(
                    [
                        "age",
                        "--decrypt",
                        "--identity",
                        str(age_identity),
                        "--output",
                        str(plaintext),
                        str(backup_path),
                    ]
                )
            else:
                shutil.copyfile(str(backup_path), str(plaintext))
            expected_plain = require_sha256(
                str(metadata["backup"].get("plaintext_sha256", "")),
                "metadata.backup.plaintext_sha256",
            )
            if sha256_file(plaintext) != expected_plain:
                raise KshiftOpsError("restore plaintext SHA-256 does not match metadata")
            runner.run(["pg_restore", "--list", str(plaintext)])
            evidence["checks"].append({"name": "archive-list", "status": "passed"})

            maintenance_env = admin_connection.environment("postgres")
            maintenance_env["PGAPPNAME"] = "kshift-restore-drill"
            runner.run(
                ["createdb", "--maintenance-db=postgres", scratch_database],
                env=maintenance_env,
            )
            created = True
            restore_env = admin_connection.environment(scratch_database)
            restore_env["PGAPPNAME"] = "kshift-restore-drill"
            runner.run(
                [
                    "pg_restore",
                    "--exit-on-error",
                    "--no-owner",
                    "--no-acl",
                    "--dbname",
                    scratch_database,
                    str(plaintext),
                ],
                env=restore_env,
            )
            evidence["checks"].append({"name": "pg-restore", "status": "passed"})

            sql_path = Path(
                os.environ.get(
                    "KSHIFT_VERIFY_SQL",
                    str(Path(__file__).resolve().parents[1] / "sql" / "verify_integrity.sql"),
                )
            )
            result = runner.run(
                ["psql", "--no-align", "--tuples-only", "--file", str(sql_path)],
                env=restore_env,
            )
            integrity_output = result.stdout.strip()
            evidence["checks"].append({"name": "integrity", "status": "passed"})

            version_query = "SELECT COALESCE((SELECT schema_version FROM kshift.schema_metadata WHERE id = 1), 0);"
            version_result = runner.run(
                ["psql", "--no-align", "--tuples-only", "--command", version_query],
                env=restore_env,
            )
            schema_version = int(version_result.stdout.strip())
            expected_schema = int(metadata.get("schema", {}).get("version", -1))
            if schema_version != expected_schema:
                raise KshiftOpsError(
                    "restored schema version {0} does not match metadata {1}".format(
                        schema_version, expected_schema
                    )
                )
            evidence["schema_version"] = schema_version
            evidence["checks"].append({"name": "schema-version", "status": "passed"})
            evidence["status"] = "passed"
    except Exception as error:
        evidence["status"] = "failed"
        evidence["error"] = str(error)
        raise
    finally:
        if created and not keep_scratch:
            try:
                maintenance_env = admin_connection.environment("postgres")
                runner.run(
                    ["dropdb", "--maintenance-db=postgres", "--if-exists", scratch_database],
                    env=maintenance_env,
                )
                evidence["cleanup"] = "passed"
            except Exception as cleanup_error:
                evidence["cleanup"] = "failed: {0}".format(cleanup_error)
        elif created:
            evidence["cleanup"] = "kept-by-request"
        else:
            evidence["cleanup"] = "not-created"
        evidence["completed_at"] = isoformat_z(utc_now())
        evidence["integrity_output"] = integrity_output
        write_json_atomic(evidence_path, evidence)

    return RestoreDrillResult(
        status=str(evidence["status"]),
        evidence_path=str(evidence_path),
        scratch_database=scratch_database,
        schema_version=int(evidence.get("schema_version", 0)),
        integrity_output=integrity_output,
    )
