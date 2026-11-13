import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from kshift_ops.backup import create_backup, verify_backup
from kshift_ops.errors import KshiftOpsError
from kshift_ops.postgres import PgConnection


class FakeRunner:
    def __init__(self):
        self.commands = []

    def run(self, command, *, env=None, input_text=None, check=True):
        self.commands.append(list(command))
        if command[0] == "psql":
            payload = {
                "database_name": "kshift",
                "postgres_version": "18.7",
                "server_version_num": 180007,
                "schema_version": 1,
                "schema_digest": "a" * 64,
            }
            return type("Result", (), {"stdout": json.dumps(payload), "stderr": "", "returncode": 0})()
        if command[0] == "pg_dump":
            output = Path(command[command.index("--file") + 1])
            output.write_bytes(b"custom-dump-fixture")
            return type("Result", (), {"stdout": "", "stderr": "", "returncode": 0})()
        return type("Result", (), {"stdout": "", "stderr": "", "returncode": 0})()


class PostgresUrlTests(unittest.TestCase):
    def test_password_is_not_repeated_in_redacted_url(self) -> None:
        connection = PgConnection.from_uri(
            "postgresql://kshift_app:fixture-password@db.internal:5433/kshift?sslmode=require"
        )
        self.assertEqual(
            connection.redacted(), "postgresql://kshift_app@db.internal:5433/kshift"
        )
        self.assertEqual(connection.environment()["PGPASSWORD"], "fixture-password")
        self.assertEqual(connection.environment()["PGSSLMODE"], "require")

    def test_non_postgres_url_is_rejected(self) -> None:
        with self.assertRaises(KshiftOpsError):
            PgConnection.from_uri("https://example.invalid/kshift")


class BackupTests(unittest.TestCase):
    def test_backup_metadata_and_digest(self) -> None:
        connection = PgConnection.from_uri("postgresql://postgres:fixture-password@localhost/kshift")
        with tempfile.TemporaryDirectory() as directory:
            result = create_backup(
                output_directory=Path(directory),
                kind="manual",
                connection=connection,
                source_commit="a" * 40,
                age_recipient=None,
                allow_unencrypted=True,
                runner=FakeRunner(),
                now=datetime(2026, 11, 13, 2, 0, tzinfo=timezone.utc),
            )
            metadata = json.loads(Path(result.metadata_path).read_text(encoding="utf-8"))
            self.assertEqual(metadata["schema"]["version"], 1)
            self.assertEqual(metadata["source_commit"], "a" * 40)
            self.assertEqual(metadata["backup"]["size"], 19)
            verified = verify_backup(
                backup_path=Path(result.backup_path),
                metadata_path=Path(result.metadata_path),
                age_identity=None,
                runner=FakeRunner(),
            )
            self.assertEqual(verified["status"], "passed")

    def test_unencrypted_backup_requires_explicit_override(self) -> None:
        connection = PgConnection.from_uri("postgresql://postgres:fixture-password@localhost/kshift")
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(KshiftOpsError):
                create_backup(
                    output_directory=Path(directory),
                    kind="manual",
                    connection=connection,
                    source_commit="a" * 40,
                    age_recipient=None,
                    allow_unencrypted=False,
                    runner=FakeRunner(),
                )


if __name__ == "__main__":
    unittest.main()
