from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Any, Dict, Optional

from .errors import KshiftOpsError
from .postgres import PgConnection
from .util import CommandRunner


def _count(connection: PgConnection, runner: CommandRunner, query: str) -> int:
    result = runner.run(
        ["psql", "--no-align", "--tuples-only", "--command", query],
        env=connection.environment(),
    )
    try:
        return int(result.stdout.strip())
    except ValueError as error:
        raise KshiftOpsError("maintenance count query returned a non-integer") from error


def plan_maintenance(
    *,
    connection: PgConnection,
    receipt_days: int,
    event_days: int,
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    if receipt_days < 1 or event_days < 1:
        raise KshiftOpsError("retention days must be positive")
    runner = runner or CommandRunner()
    receipts = _count(
        connection,
        runner,
        "SELECT count(*) FROM kshift.command_result "
        "WHERE expires_at < now() - interval '{0} days';".format(receipt_days),
    )
    events = _count(
        connection,
        runner,
        "SELECT count(*) FROM kshift.change_event "
        "WHERE created_at < now() - interval '{0} days';".format(event_days),
    )
    return {
        "status": "dry-run",
        "receipt_days": receipt_days,
        "event_days": event_days,
        "command_receipts_to_delete": receipts,
        "change_events_to_delete": events,
    }


def apply_maintenance(
    *,
    connection: PgConnection,
    receipt_days: int,
    event_days: int,
    confirmed: bool,
    runner: Optional[CommandRunner] = None,
) -> Dict[str, Any]:
    if not confirmed:
        raise KshiftOpsError("maintenance deletion requires --apply --yes")
    plan = plan_maintenance(
        connection=connection,
        receipt_days=receipt_days,
        event_days=event_days,
        runner=runner,
    )
    runner = runner or CommandRunner()
    sql = """
BEGIN;
DELETE FROM kshift.command_result
WHERE created_at < now() - interval '{receipt_days} days';
DELETE FROM kshift.change_event
WHERE expires_at <= now() OR created_at < now() - interval '{event_days} days';
COMMIT;
""".format(receipt_days=int(receipt_days), event_days=int(event_days))
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as handle:
        handle.write(sql)
        path = Path(handle.name)
    try:
        runner.run(
            ["psql", "--set=ON_ERROR_STOP=1", "--file", str(path)],
            env=connection.environment(),
        )
    finally:
        path.unlink(missing_ok=True)
    plan["status"] = "applied"
    return plan
