import os
import tempfile
import unittest
from pathlib import Path

from kshift_ops.admin import show_admin_view
from kshift_ops.backup import create_backup, restore_drill
from kshift_ops.maintenance import plan_maintenance
from kshift_ops.migrations import migrate, schema_status
from kshift_ops.postgres import PgConnection
from kshift_ops.rbac import grant_role, list_roles
from kshift_ops.util import CommandRunner


ADMIN_URL_ENV = "KSHIFT_TEST_ADMIN_DATABASE_URL"
SOURCE_COMMIT = "a" * 40
R1_MIGRATION = Path(__file__).resolve().parents[2] / "migrations" / "0001_initial.sql"
OPS_SQL = Path(__file__).resolve().parents[1] / "sql"


@unittest.skipUnless(os.environ.get(ADMIN_URL_ENV), "PostgreSQL integration URL is not set")
class PostgresIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.admin_connection = PgConnection.from_env(ADMIN_URL_ENV)
        cls.runner = CommandRunner()

    def setUp(self):
        self.database_name = "kshift_test_" + os.urandom(6).hex()
        self.runner.run(
            ["createdb", "--maintenance-db=postgres", self.database_name],
            env=self.admin_connection.environment("postgres"),
        )
        self.database = type(self.admin_connection)(
            host=self.admin_connection.host,
            port=self.admin_connection.port,
            user=self.admin_connection.user,
            password=self.admin_connection.password,
            database=self.database_name,
            query=self.admin_connection.query,
        )
        self.runner.run(
            ["psql", "--file", str(R1_MIGRATION), "--set=ON_ERROR_STOP=1"],
            env=self.database.environment(),
        )
        self.runner.run(
            ["psql", "--file", str(OPS_SQL / "bootstrap.sql"), "--set=ON_ERROR_STOP=1"],
            env=self.database.environment(),
        )
        self.runner.run(
            ["psql", "--file", str(OPS_SQL / "admin_views.sql"), "--set=ON_ERROR_STOP=1"],
            env=self.database.environment(),
        )
        self.runner.run(
            [
                "psql",
                "--command",
                """
INSERT INTO kshift.schema_metadata
  (id, schema_version, migration_digest, applied_at, postgres_version)
VALUES (1, 1, repeat('b', 64), now(), '18.7');
""",
                "--set=ON_ERROR_STOP=1",
            ],
            env=self.database.environment(),
        )
        self._seed()

    def tearDown(self):
        self.runner.run(
            ["dropdb", "--maintenance-db=postgres", "--if-exists", self.database_name],
            env=self.admin_connection.environment("postgres"),
        )

    def _seed(self):
        sql = """
INSERT INTO kshift.app_user (id, display_name, is_admin) VALUES
('11111111-1111-4111-8111-111111111111', 'Alice', true),
('22222222-2222-4222-8222-222222222222', 'Bob', false),
('33333333-3333-4333-8333-333333333333', 'Carol', false),
('44444444-4444-4444-8444-444444444444', 'Dave', false);
INSERT INTO kshift.project (id, name, time_zone, created_by, created_at, updated_at) VALUES
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Alpha', 'Asia/Shanghai', '11111111-1111-4111-8111-111111111111', now(), now()),
('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Beta', 'Asia/Shanghai', '11111111-1111-4111-8111-111111111111', now(), now());
INSERT INTO kshift.project_member (project_id, user_id, role, created_at, updated_at) VALUES
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'admin', now(), now()),
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222', 'editor', now(), now()),
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '33333333-3333-4333-8333-333333333333', 'viewer', now(), now());
INSERT INTO kshift.task
  (id, project_id, title, status, priority, planned_on, created_by, updated_by, created_at, updated_at)
VALUES
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'One', 'todo', 2, current_date, '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', now(), now()),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Two', 'todo', 2, current_date, '11111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', now(), now());
"""
        self.runner.run(
            ["psql", "--command", sql, "--set=ON_ERROR_STOP=1"],
            env=self.database.environment(),
        )

    def test_admin_role_can_read_restricted_views(self):
        sql = (
            "BEGIN; SET LOCAL ROLE kshift_admin; "
            "SELECT count(*) FROM kshift.project_overview; "
            "SELECT count(*) FROM kshift.member_overview; COMMIT;"
        )
        result = self.runner.run(
            ["psql", "--no-align", "--tuples-only", "--command", sql],
            env=self.database.environment(),
        )
        lines = [line.strip() for line in result.stdout.splitlines()]
        self.assertIn("2", lines)
        self.assertIn("3", lines)

    def test_rbac_grant_revoke_and_admin_pagination(self):
        grant_role(
            connection=self.database,
            project_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            user_id="44444444-4444-4444-8444-444444444444",
            role="viewer",
            runner=self.runner,
        )
        memberships = list_roles(
            connection=self.database,
            project_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            runner=self.runner,
        )
        self.assertEqual(len(memberships), 4)
        page = show_admin_view(
            connection=self.database,
            view="task_overview",
            limit=10,
            offset=0,
            search="One",
            runner=self.runner,
        )
        self.assertEqual(page["rows"][0][2], "One")

    def test_schema_status_uses_server_metadata(self):
        status = schema_status(self.database, self.runner)
        self.assertEqual(status["schema_version"], "1")
        self.assertEqual(status["migration_digest"], "b" * 64)

    def test_server_migration_wrapper_uses_authoritative_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            server = Path(directory) / "kshift-server"
            server.write_text("#!/bin/sh\nprintf 'ok\\n'\n", encoding="utf-8")
            server.chmod(0o755)
            result = migrate(
                connection=self.database,
                server_bin=server,
                source_commit=SOURCE_COMMIT,
                backup_output_directory=None,
                age_recipient=None,
                allow_unencrypted_backup=False,
                allow_no_backup=True,
                runner=self.runner,
            )
            self.assertEqual(result["status"], "migrated")
            self.assertIn("ok", result["check_output"])

    def test_maintenance_plan_uses_r1_tables(self):
        plan = plan_maintenance(
            connection=self.database,
            receipt_days=7,
            event_days=7,
            runner=self.runner,
        )
        self.assertEqual(plan["status"], "dry-run")
        self.assertGreaterEqual(plan["command_receipts_to_delete"], 0)
        self.assertGreaterEqual(plan["change_events_to_delete"], 0)

    def test_encrypted_backup_and_restore_drill(self):
        with tempfile.TemporaryDirectory() as directory:
            identity = Path(directory) / "age-identity.txt"
            self.runner.run(["age-keygen", "--output", str(identity)])
            recipient = self.runner.run(["age-keygen", "-y", str(identity)]).stdout.strip()
            backup = create_backup(
                output_directory=Path(directory) / "backups",
                kind="manual",
                connection=self.database,
                source_commit=SOURCE_COMMIT,
                age_recipient=recipient,
                allow_unencrypted=False,
                runner=self.runner,
            )
            self.assertTrue(backup.encrypted)
            drill = restore_drill(
                backup_path=Path(backup.backup_path),
                metadata_path=Path(backup.metadata_path),
                admin_connection=self.admin_connection,
                age_identity=identity,
                evidence_directory=Path(directory) / "evidence",
                keep_scratch=False,
                runner=self.runner,
            )
            self.assertEqual(drill.status, "passed")
            self.assertEqual(drill.schema_version, 1)

    def test_unencrypted_backup_and_restore_drill(self):
        with tempfile.TemporaryDirectory() as directory:
            backup = create_backup(
                output_directory=Path(directory),
                kind="manual",
                connection=self.database,
                source_commit=SOURCE_COMMIT,
                age_recipient=None,
                allow_unencrypted=True,
                runner=self.runner,
            )
            drill = restore_drill(
                backup_path=Path(backup.backup_path),
                metadata_path=Path(backup.metadata_path),
                admin_connection=self.admin_connection,
                age_identity=None,
                evidence_directory=Path(directory) / "evidence",
                keep_scratch=True,
                runner=self.runner,
            )
            try:
                self.assertEqual(drill.status, "passed")
                self.assertEqual(drill.schema_version, 1)
                restored = self.runner.run(
                    [
                        "psql",
                        "--no-align",
                        "--tuples-only",
                        "--command",
                        "SELECT count(*) FROM kshift.task;",
                    ],
                    env=self.admin_connection.environment(drill.scratch_database),
                )
                self.assertEqual(restored.stdout.strip(), "2")
            finally:
                self.runner.run(
                    [
                        "dropdb",
                        "--maintenance-db=postgres",
                        "--if-exists",
                        drill.scratch_database,
                    ],
                    env=self.admin_connection.environment("postgres"),
                )


if __name__ == "__main__":
    unittest.main()
