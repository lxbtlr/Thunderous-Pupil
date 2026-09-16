#!/usr/bin/env python3
"""
Apply numbered migrations in order, inside the NFS-safe write path.

Deliberately trivial: a schema_migrations table and a loop. With six
migrations and one operator, Alembic would cost more than it saves, and a
plain .sql file is something you can read in ten seconds and the agent can
propose without you having to trust generated Python.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from corpus.db import db_path, utcnow, writing  # noqa: E402

MIGRATIONS = Path(__file__).resolve().parent / "migrations"


def main():
    files = sorted(MIGRATIONS.glob("[0-9][0-9][0-9][0-9]_*.sql"))
    if not files:
        sys.exit(f"no migrations found in {MIGRATIONS}")

    with writing(create=True) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version    TEXT PRIMARY KEY,
                applied_at TEXT NOT NULL,
                sha256     TEXT NOT NULL
            ) STRICT
        """)
        done = {r[0] for r in conn.execute("SELECT version FROM schema_migrations")}
        applied = 0
        for f in files:
            version = f.stem
            if version in done:
                continue
            import hashlib
            sql = f.read_text()
            conn.executescript(sql)
            conn.execute(
                "INSERT INTO schema_migrations (version, applied_at, sha256) VALUES (?,?,?)",
                (version, utcnow(), hashlib.sha256(sql.encode()).hexdigest()),
            )
            print(f"applied {version}")
            applied += 1

    print(f"{applied} migration(s) applied; database at {db_path()}")


if __name__ == "__main__":
    main()
