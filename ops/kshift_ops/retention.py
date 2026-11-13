from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional

from .errors import KshiftOpsError
from .util import parse_iso8601, read_json

RETENTION_LIMITS = {
    "scheduled-4h": 42,
    "weekly": 12,
    "monthly": 12,
}


@dataclass(frozen=True)
class RetentionEntry:
    metadata_path: Path
    backup_path: Path
    kind: str
    created_at: str
    status: str

    @property
    def deletable(self) -> bool:
        return self.status == "complete" and self.kind in RETENTION_LIMITS


def entry_from_metadata(metadata_path: Path) -> RetentionEntry:
    metadata = read_json(metadata_path)
    stored = metadata.get("backup", {})
    name = stored.get("name") if isinstance(stored, dict) else None
    if not isinstance(name, str) or not name:
        raise KshiftOpsError("metadata has no backup.name: {0}".format(metadata_path))
    backup_path = metadata_path.parent / name
    kind = metadata.get("kind")
    created_at = metadata.get("created_at")
    status = metadata.get("status")
    if not all(isinstance(value, str) and value for value in (kind, created_at, status)):
        raise KshiftOpsError("metadata is missing kind, created_at or status: {0}".format(metadata_path))
    parse_iso8601(created_at)
    return RetentionEntry(metadata_path, backup_path, kind, created_at, status)


def load_entries(directory: Path) -> List[RetentionEntry]:
    entries: List[RetentionEntry] = []
    for path in sorted(directory.glob("*.metadata.json")):
        try:
            entries.append(entry_from_metadata(path))
        except KshiftOpsError:
            entries.append(
                RetentionEntry(
                    metadata_path=path,
                    backup_path=path.with_suffix(""),
                    kind="invalid",
                    created_at="1970-01-01T00:00:00Z",
                    status="invalid",
                )
            )
    return entries


def plan_retention(entries: Iterable[RetentionEntry]) -> Dict[str, object]:
    grouped: Dict[str, List[RetentionEntry]] = {key: [] for key in RETENTION_LIMITS}
    protected: List[RetentionEntry] = []
    for entry in entries:
        if entry.deletable:
            grouped[entry.kind].append(entry)
        else:
            protected.append(entry)

    deletes: List[RetentionEntry] = []
    keep: List[RetentionEntry] = []
    for kind, limit in RETENTION_LIMITS.items():
        ordered = sorted(
            grouped[kind], key=lambda item: parse_iso8601(item.created_at), reverse=True
        )
        keep.extend(ordered[:limit])
        deletes.extend(ordered[limit:])
    keep.extend(protected)
    keep.sort(key=lambda item: item.metadata_path.name)
    deletes.sort(key=lambda item: item.metadata_path.name)
    return {
        "counts": {kind: len(grouped[kind]) for kind in RETENTION_LIMITS},
        "limits": RETENTION_LIMITS,
        "keep": [str(item.metadata_path) for item in keep],
        "delete": [
            {
                "metadata": str(item.metadata_path),
                "backup": str(item.backup_path),
                "kind": item.kind,
            }
            for item in deletes
        ],
        "protected": [str(item.metadata_path) for item in protected],
    }


def apply_retention(plan: Dict[str, object], *, confirmed: bool) -> None:
    if not confirmed:
        raise KshiftOpsError("retention deletion requires --apply --yes")
    items = plan.get("delete")
    if not isinstance(items, list):
        raise KshiftOpsError("invalid retention plan")
    for item in items:
        if not isinstance(item, dict):
            raise KshiftOpsError("invalid retention item")
        metadata_value = item.get("metadata")
        backup_value = item.get("backup")
        if not isinstance(metadata_value, str) or not isinstance(backup_value, str):
            raise KshiftOpsError("invalid retention item path")
        metadata_path = Path(metadata_value)
        backup_path = Path(backup_value)
        for path in (backup_path, metadata_path):
            try:
                path.unlink()
            except FileNotFoundError:
                continue
