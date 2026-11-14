from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Dict, Mapping, Optional
from urllib.parse import parse_qs, quote, unquote, urlsplit

from .errors import KshiftOpsError

SUPPORTED_QUERY_OPTIONS = {
    "application_name": "PGAPPNAME",
    "connect_timeout": "PGCONNECT_TIMEOUT",
    "sslmode": "PGSSLMODE",
    "sslrootcert": "PGSSLROOTCERT",
    "sslcert": "PGSSLCERT",
    "sslkey": "PGSSLKEY",
}


@dataclass(frozen=True)
class PgConnection:
    host: str
    port: int
    user: str
    password: Optional[str]
    database: str
    query: Mapping[str, str]

    @classmethod
    def from_env(cls, variable: str) -> "PgConnection":
        value = os.environ.get(variable, "").strip()
        if not value:
            raise KshiftOpsError("environment variable {0} is required".format(variable))
        return cls.from_uri(value)

    @classmethod
    def from_uri(cls, value: str) -> "PgConnection":
        parsed = urlsplit(value)
        if parsed.scheme not in ("postgres", "postgresql"):
            raise KshiftOpsError("database URL must use postgresql:// or postgres://")
        if not parsed.hostname:
            raise KshiftOpsError("database URL must contain a host")
        database = unquote(parsed.path.lstrip("/"))
        if not database:
            raise KshiftOpsError("database URL must contain a database name")
        query: Dict[str, str] = {}
        for key, values in parse_qs(parsed.query, keep_blank_values=True).items():
            if key in SUPPORTED_QUERY_OPTIONS and values:
                query[key] = values[-1]
        return cls(
            host=parsed.hostname,
            port=parsed.port or 5432,
            user=unquote(parsed.username or ""),
            password=unquote(parsed.password) if parsed.password is not None else None,
            database=database,
            query=query,
        )

    def environment(self, database: Optional[str] = None) -> Dict[str, str]:
        env = dict(os.environ)
        env.update(
            {
                "PGHOST": self.host,
                "PGPORT": str(self.port),
                "PGUSER": self.user,
                "PGDATABASE": database or self.database,
            }
        )
        if self.password is None:
            env.pop("PGPASSWORD", None)
        else:
            env["PGPASSWORD"] = self.password
        for key, value in self.query.items():
            env[SUPPORTED_QUERY_OPTIONS[key]] = value
        return env

    def uri(self, database: Optional[str] = None) -> str:
        user = quote(self.user, safe="")
        password = ":{0}".format(quote(self.password, safe="")) if self.password is not None else ""
        query = ""
        if self.query:
            from urllib.parse import urlencode

            query = "?" + urlencode(self.query)
        return "postgresql://{0}{1}@{2}:{3}/{4}{5}".format(
            user, password, self.host, self.port, quote(database or self.database, safe=""), query
        )

    def redacted(self, database: Optional[str] = None) -> str:
        return "postgresql://{0}@{1}:{2}/{3}".format(
            self.user or "<user>", self.host, self.port, database or self.database
        )
