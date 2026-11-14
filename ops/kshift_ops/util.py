from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

from .errors import KshiftOpsError

SAFE_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


def utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def isoformat_z(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_iso8601(value: str) -> datetime:
    normalised = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalised)
    if parsed.tzinfo is None:
        raise KshiftOpsError("timestamp must include a timezone")
    return parsed.astimezone(timezone.utc)


def read_json(path: Path) -> Dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise KshiftOpsError("cannot read JSON {0}: {1}".format(path, error)) from error
    if not isinstance(value, dict):
        raise KshiftOpsError("JSON root must be an object: {0}".format(path))
    return value


def write_json_atomic(path: Path, value: Mapping[str, Any], mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".{0}.".format(path.name), dir=str(path.parent), text=True
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_path, mode)
        os.replace(str(temporary_path), str(path))
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_safe_name(value: str, label: str) -> str:
    if not SAFE_NAME_RE.fullmatch(value):
        raise KshiftOpsError(
            "{0} must contain only letters, digits, dot, underscore and dash".format(label)
        )
    return value


def require_sha256(value: str, label: str) -> str:
    if not SHA256_RE.fullmatch(value):
        raise KshiftOpsError("{0} must be a lowercase SHA-256 digest".format(label))
    return value


def require_source_commit(value: str) -> str:
    if not GIT_COMMIT_RE.fullmatch(value):
        raise KshiftOpsError("source commit must be 40 lowercase hexadecimal characters")
    return value


def current_source_commit(working_directory: Optional[Path] = None) -> str:
    override = os.environ.get("KSHIFT_SOURCE_COMMIT", "").strip()
    if override:
        return require_source_commit(override)
    command = ["git", "rev-parse", "HEAD"]
    try:
        result = subprocess.run(
            command,
            cwd=str(working_directory) if working_directory else None,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise KshiftOpsError(
            "cannot determine source commit; set KSHIFT_SOURCE_COMMIT"
        ) from error
    return require_source_commit(result.stdout.strip())


class CommandRunner:
    """Small subprocess wrapper that never includes connection URLs in errors."""

    def run(
        self,
        command: Sequence[str],
        *,
        env: Optional[Mapping[str, str]] = None,
        input_text: Optional[str] = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess:
        try:
            result = subprocess.run(
                list(command),
                env=dict(env) if env is not None else None,
                input=input_text,
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as error:
            raise KshiftOpsError("cannot execute {0}: {1}".format(command[0], error)) from error
        if check and result.returncode != 0:
            stderr = (result.stderr or "").strip()
            stdout = (result.stdout or "").strip()
            detail = stderr or stdout or "exit status {0}".format(result.returncode)
            raise KshiftOpsError("{0} failed: {1}".format(command[0], detail))
        return result


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        os.chmod(path, 0o700)
    except PermissionError as error:
        raise KshiftOpsError("cannot secure directory permissions: {0}".format(path)) from error


def parse_csv_output(text: str) -> List[List[str]]:
    import csv
    import io

    return list(csv.reader(io.StringIO(text)))
