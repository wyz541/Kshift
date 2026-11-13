import tempfile
import unittest
from pathlib import Path

from kshift_ops.errors import KshiftOpsError
from kshift_ops.migrations import validate_server_bin


class ServerBinaryTests(unittest.TestCase):
    def test_accepts_an_executable_server_binary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            server = Path(directory) / "kshift-server"
            server.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            server.chmod(0o755)
            self.assertEqual(validate_server_bin(server), server.resolve())

    def test_rejects_a_missing_server_binary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(KshiftOpsError):
                validate_server_bin(Path(directory) / "missing-server")


if __name__ == "__main__":
    unittest.main()
