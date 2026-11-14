import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from kshift_ops.retention import load_entries, plan_retention


class RetentionTests(unittest.TestCase):
    def _entry(self, root: Path, index: int, kind: str) -> None:
        created = datetime(2026, 11, 1, tzinfo=timezone.utc) + timedelta(hours=index)
        name = "backup-{0:03d}.dump".format(index)
        (root / name).write_bytes(b"fixture")
        metadata = {
            "kind": kind,
            "created_at": created.isoformat().replace("+00:00", "Z"),
            "status": "complete",
            "backup": {"name": name},
        }
        (root / (name + ".metadata.json")).write_text(
            json.dumps(metadata), encoding="utf-8"
        )

    def test_retains_exact_policy_counts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for index in range(45):
                self._entry(root, index, "scheduled-4h")
            for index in range(14):
                self._entry(root, 100 + index, "weekly")
            for index in range(13):
                self._entry(root, 200 + index, "monthly")
            self._entry(root, 300, "migration")

            plan = plan_retention(load_entries(root))
            self.assertEqual(plan["counts"]["scheduled-4h"], 45)
            self.assertEqual(len(plan["delete"]), 3 + 2 + 1)
            self.assertEqual(len(plan["keep"]), 42 + 12 + 12 + 1)
            protected = [Path(value).name for value in plan["protected"]]
            self.assertIn("backup-300.dump.metadata.json", protected)

    def test_newest_backups_are_kept(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for index in range(45):
                self._entry(root, index, "scheduled-4h")
            plan = plan_retention(load_entries(root))
            deleted = {Path(item["backup"]).name for item in plan["delete"]}
            self.assertEqual(deleted, {"backup-000.dump", "backup-001.dump", "backup-002.dump"})


if __name__ == "__main__":
    unittest.main()
