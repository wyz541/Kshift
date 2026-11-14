import tempfile
import unittest
from pathlib import Path

from kshift_ops.health import check_server
from kshift_ops.postgres import PgConnection


class HealthyRunner:
    def run(self, command, *, env=None, input_text=None, check=True):
        return type("Result", (), {"stdout": '{"healthy":true}', "stderr": "", "returncode": 0})()


class HealthTests(unittest.TestCase):
    def test_server_check_uses_the_server_binary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            server = Path(directory) / "kshift-server"
            server.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            server.chmod(0o755)
            result = check_server(
                server,
                PgConnection.from_uri("postgresql://kshift_app:fixture@db/kshift"),
                HealthyRunner(),
            )
            self.assertEqual(result["status"], "passed")
            self.assertIn("healthy", result["output"])


if __name__ == "__main__":
    unittest.main()
