from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Optional

from . import __version__
from .admin import list_admin_views, show_admin_view
from .backup import create_backup, restore_drill, verify_backup
from .errors import KshiftOpsError
from .health import aggregate as aggregate_health
from .maintenance import apply_maintenance, plan_maintenance
from .migrations import migrate, schema_status
from .postgres import PgConnection
from .rbac import grant_role, list_roles, revoke_role
from .retention import apply_retention, load_entries, plan_retention
from .util import current_source_commit


def _json(value: Any) -> None:
    json.dump(value, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def _pg(variable: str) -> PgConnection:
    return PgConnection.from_env(variable)


def _age_recipient(args: argparse.Namespace) -> Optional[str]:
    if args.age_recipient and args.age_recipient_file:
        raise KshiftOpsError("use only one of --age-recipient and --age-recipient-file")
    if args.age_recipient_file:
        try:
            value = Path(args.age_recipient_file).read_text(encoding="utf-8").strip()
        except OSError as error:
            raise KshiftOpsError("cannot read age recipient file") from error
        if not value:
            raise KshiftOpsError("age recipient file is empty")
        return value
    return args.age_recipient


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="kshift-ops", description="Kshift operations CLI")
    parser.add_argument("--version", action="version", version="%(prog)s " + __version__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    backup = subparsers.add_parser("backup", help="create, verify, retain and restore backups")
    backup_sub = backup.add_subparsers(dest="backup_command", required=True)

    create = backup_sub.add_parser("create", help="create a custom-format pg_dump backup")
    create.add_argument("--output", required=True, type=Path)
    create.add_argument("--kind", required=True)
    create.add_argument("--database-url-env", default="KSHIFT_DATABASE_URL")
    create.add_argument("--source-commit")
    create.add_argument("--age-recipient")
    create.add_argument("--age-recipient-file")
    create.add_argument("--allow-unencrypted", action="store_true")

    verify = backup_sub.add_parser("verify", help="verify backup metadata and SHA-256")
    verify.add_argument("--backup", required=True, type=Path)
    verify.add_argument("--metadata", required=True, type=Path)
    verify.add_argument("--age-identity", type=Path)

    restore = backup_sub.add_parser("restore-drill", help="restore into a disposable database")
    restore.add_argument("--backup", required=True, type=Path)
    restore.add_argument("--metadata", required=True, type=Path)
    restore.add_argument("--admin-database-url-env", default="KSHIFT_ADMIN_DATABASE_URL")
    restore.add_argument("--age-identity", type=Path)
    restore.add_argument("--evidence-directory", type=Path)
    restore.add_argument("--keep-scratch", action="store_true")

    retention = backup_sub.add_parser("prune", help="plan or apply the retention policy")
    retention.add_argument("--directory", required=True, type=Path)
    retention.add_argument("--apply", action="store_true")
    retention.add_argument("--yes", action="store_true")

    backup_sub.add_parser("list", help="show backup retention counts").add_argument(
        "--directory", required=True, type=Path
    )

    database = subparsers.add_parser("db", help="database migrations and integrity")
    db_sub = database.add_subparsers(dest="db_command", required=True)

    migrate_parser = db_sub.add_parser("migrate", help="run the authoritative server migration")
    migrate_parser.add_argument("--server-bin", default=os.environ.get("KSHIFT_SERVER_BIN", ""))
    migrate_parser.add_argument("--database-url-env", default="KSHIFT_OWNER_DATABASE_URL")
    migrate_parser.add_argument("--backup-database-url-env", default="KSHIFT_BACKUP_DATABASE_URL")
    migrate_parser.add_argument("--source-commit")
    migrate_parser.add_argument("--backup-output", type=Path)
    migrate_parser.add_argument("--age-recipient")
    migrate_parser.add_argument("--age-recipient-file")
    migrate_parser.add_argument("--allow-unencrypted-backup", action="store_true")
    migrate_parser.add_argument("--allow-no-backup", action="store_true")

    status_parser = db_sub.add_parser("status", help="show applied migrations")
    status_parser.add_argument("--database-url-env", default="KSHIFT_OWNER_DATABASE_URL")

    maintain = db_sub.add_parser("maintain", help="plan or delete expired operational rows")
    maintain.add_argument("--database-url-env", default="KSHIFT_OWNER_DATABASE_URL")
    maintain.add_argument("--receipt-days", type=int, default=7)
    maintain.add_argument("--event-days", type=int, default=7)
    maintain.add_argument("--apply", action="store_true")
    maintain.add_argument("--yes", action="store_true")

    rbac = subparsers.add_parser("rbac", help="manage project memberships")
    rbac_sub = rbac.add_subparsers(dest="rbac_command", required=True)
    for name in ("grant", "revoke"):
        command = rbac_sub.add_parser(name)
        command.add_argument("--database-url-env", default="KSHIFT_ADMIN_DATABASE_URL")
        command.add_argument("--project-id", required=True)
        command.add_argument("--user-id", required=True)
        if name == "grant":
            command.add_argument("--role", required=True, choices=("viewer", "editor", "admin"))
    rbac_list = rbac_sub.add_parser("list")
    rbac_list.add_argument("--database-url-env", default="KSHIFT_ADMIN_DATABASE_URL")
    rbac_list.add_argument("--project-id")

    admin = subparsers.add_parser("admin", help="read the restricted admin views")
    admin_sub = admin.add_subparsers(dest="admin_command", required=True)
    admin_sub.add_parser("tables", help="list allowed views")
    admin_show = admin_sub.add_parser("show")
    admin_show.add_argument("--database-url-env", default="KSHIFT_ADMIN_DATABASE_URL")
    admin_show.add_argument("--view", required=True)
    admin_show.add_argument("--limit", type=int, default=50)
    admin_show.add_argument("--offset", type=int, default=0)
    admin_show.add_argument("--search")

    health = subparsers.add_parser("health", help="check HTTP, database and disk health")
    health.add_argument("--http-url")
    health.add_argument("--server-bin", default=os.environ.get("KSHIFT_SERVER_BIN", ""))
    health.add_argument("--database-url-env")
    health.add_argument("--disk-path", type=Path)
    health.add_argument("--minimum-free-gib", type=float, default=10.0)
    health.add_argument("--timeout-seconds", type=float, default=5.0)

    return parser


def run(args: argparse.Namespace) -> Dict[str, Any]:
    if args.command == "backup":
        if args.backup_command == "create":
            commit = args.source_commit or current_source_commit()
            result = create_backup(
                output_directory=args.output.expanduser().resolve(),
                kind=args.kind,
                connection=_pg(args.database_url_env),
                source_commit=commit,
                age_recipient=_age_recipient(args),
                allow_unencrypted=args.allow_unencrypted,
            )
            return {
                "status": "passed",
                "backup": result.backup_path,
                "metadata": result.metadata_path,
                "sha256": result.sha256,
                "size": result.size,
                "encrypted": result.encrypted,
                "schema_version": result.schema_version,
            }
        if args.backup_command == "verify":
            return verify_backup(
                backup_path=args.backup.expanduser().resolve(),
                metadata_path=args.metadata.expanduser().resolve(),
                age_identity=args.age_identity.expanduser().resolve()
                if args.age_identity
                else None,
            )
        if args.backup_command == "restore-drill":
            result = restore_drill(
                backup_path=args.backup.expanduser().resolve(),
                metadata_path=args.metadata.expanduser().resolve(),
                admin_connection=_pg(args.admin_database_url_env),
                age_identity=args.age_identity.expanduser().resolve()
                if args.age_identity
                else None,
                evidence_directory=args.evidence_directory.expanduser().resolve()
                if args.evidence_directory
                else None,
                keep_scratch=args.keep_scratch,
            )
            return {
                "status": result.status,
                "evidence": result.evidence_path,
                "scratch_database": result.scratch_database,
                "schema_version": result.schema_version,
            }
        if args.backup_command in ("prune", "list"):
            directory = args.directory.expanduser().resolve()
            plan = plan_retention(load_entries(directory))
            if args.backup_command == "prune":
                if args.apply:
                    apply_retention(plan, confirmed=args.yes)
                    plan["status"] = "applied"
                else:
                    plan["status"] = "dry-run"
            else:
                plan["status"] = "listed"
            return plan

    if args.command == "db":
        connection = _pg(args.database_url_env)
        if args.db_command == "status":
            return schema_status(connection)
        if args.db_command == "maintain":
            if args.apply:
                return apply_maintenance(
                    connection=connection,
                    receipt_days=args.receipt_days,
                    event_days=args.event_days,
                    confirmed=args.yes,
                )
            return plan_maintenance(
                connection=connection,
                receipt_days=args.receipt_days,
                event_days=args.event_days,
            )
        if args.db_command == "migrate":
            if not args.server_bin:
                raise KshiftOpsError("--server-bin or KSHIFT_SERVER_BIN is required")
            commit = args.source_commit or current_source_commit()
            return migrate(
                connection=connection,
                server_bin=Path(args.server_bin),
                source_commit=commit,
                backup_output_directory=args.backup_output.expanduser().resolve()
                if args.backup_output
                else None,
                age_recipient=_age_recipient(args),
                allow_unencrypted_backup=args.allow_unencrypted_backup,
                allow_no_backup=args.allow_no_backup,
            )

    if args.command == "rbac":
        connection = _pg(args.database_url_env)
        if args.rbac_command == "grant":
            return grant_role(
                connection=connection,
                project_id=args.project_id,
                user_id=args.user_id,
                role=args.role,
            )
        if args.rbac_command == "revoke":
            return revoke_role(
                connection=connection,
                project_id=args.project_id,
                user_id=args.user_id,
            )
        return {"memberships": list_roles(connection=connection, project_id=args.project_id)}

    if args.command == "admin":
        if args.admin_command == "tables":
            return {"views": list_admin_views()}
        return show_admin_view(
            connection=_pg(args.database_url_env),
            view=args.view,
            limit=args.limit,
            offset=args.offset,
            search=args.search,
        )

    if args.command == "health":
        database = _pg(args.database_url_env or "KSHIFT_DATABASE_URL") if (args.database_url_env or args.server_bin) else None
        return aggregate_health(
            http_url=args.http_url,
            server_bin=Path(args.server_bin) if args.server_bin else None,
            database=database,
            disk_path=args.disk_path.expanduser().resolve() if args.disk_path else None,
            minimum_free_bytes=int(args.minimum_free_gib * 1024 * 1024 * 1024),
            timeout_seconds=args.timeout_seconds,
        )

    raise KshiftOpsError("unsupported command")


def main(argv: Optional[list] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = run(args)
    except KshiftOpsError as error:
        print("kshift-ops: {0}".format(error), file=sys.stderr)
        return 2
    _json(result)
    return 0 if result.get("status") not in ("failed", "error") else 1
