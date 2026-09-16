"""
NFS-safe SQLite access.

The canonical database lives on /tank (NFS). It is never written in place.

  READS   open the /tank file directly, read-only. Safe: writers publish by
          atomic rename within the same directory, so a reader's open file
          descriptor keeps pointing at the old inode until it closes.

  WRITES  take an exclusive lock, copy the database to node-local scratch,
          mutate the local copy (WAL is fine there), then copy back to a
          temporary name in the same /tank directory and os.replace() it.
          A job that dies mid-ingest leaves the canonical file untouched.

Why not write directly over NFS: WAL mode requires shared memory and does not
work over NFS at all, and POSIX advisory locking through lockd is unreliable
in exactly the way that corrupts SQLite silently.
"""

from __future__ import annotations

import contextlib
import errno
import json
import os
import shutil
import socket
import sqlite3
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_DB = "/tank/alexb/vldb-db/corpus.sqlite"
LOCK_TIMEOUT_S = 900          # ingest of one .out is seconds; 15 min is generous
STALE_LOCK_S = 3600


def db_path() -> Path:
    return Path(os.environ.get("CORPUS_DB", DEFAULT_DB))


def scratch_dir() -> Path:
    for var in ("CORPUS_SCRATCH", "SLURM_TMPDIR", "TMPDIR"):
        v = os.environ.get(var)
        if v and Path(v).is_dir():
            return Path(v)
    return Path("/tmp")


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _configure(conn: sqlite3.Connection, *, writable: bool) -> None:
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")       # off by default in SQLite
    if writable:
        conn.execute("PRAGMA journal_mode = WAL")  # local scratch only
        conn.execute("PRAGMA synchronous = NORMAL")


@contextlib.contextmanager
def read_only(path: Path | None = None):
    """Open the canonical database read-only, directly over NFS."""
    p = path or db_path()
    if not p.exists():
        raise FileNotFoundError(f"no corpus database at {p}; run migrate.py")
    conn = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
    _configure(conn, writable=False)
    try:
        yield conn
    finally:
        conn.close()


class LockHeld(RuntimeError):
    pass


@contextlib.contextmanager
def _exclusive_lock(lock_file: Path, timeout: float = LOCK_TIMEOUT_S):
    """
    O_CREAT|O_EXCL lockfile rather than flock: exclusive create is far more
    reliable over NFS than advisory locking. Contents identify the holder so a
    stuck lock can be diagnosed rather than merely stolen.
    """
    payload = json.dumps(
        {"host": socket.gethostname(), "pid": os.getpid(),
         "job": os.environ.get("SLURM_JOB_ID"), "at": utcnow()}
    )
    deadline = time.time() + timeout
    fd = None
    while True:
        try:
            fd = os.open(str(lock_file), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            break
        except OSError as e:
            if e.errno != errno.EEXIST:
                raise
            try:
                age = time.time() - lock_file.stat().st_mtime
                if age > STALE_LOCK_S:
                    holder = lock_file.read_text()
                    lock_file.unlink(missing_ok=True)
                    print(f"corpus: broke stale lock ({int(age)}s): {holder}")
                    continue
            except FileNotFoundError:
                continue
            if time.time() > deadline:
                raise LockHeld(
                    f"corpus database locked by {lock_file.read_text()}; "
                    f"waited {timeout:.0f}s"
                )
            time.sleep(2.0)
    try:
        os.write(fd, payload.encode())
        os.close(fd)
        fd = None
        yield
    finally:
        if fd is not None:
            os.close(fd)
        lock_file.unlink(missing_ok=True)


@contextlib.contextmanager
def writing(path: Path | None = None, *, create: bool = False):
    """
    Exclusive copy-modify-swap write. Yields a connection to a LOCAL copy.
    Commits and publishes on clean exit; discards everything on exception.
    """
    canonical = path or db_path()
    canonical.parent.mkdir(parents=True, exist_ok=True)
    lock_file = canonical.with_suffix(canonical.suffix + ".lock")

    with _exclusive_lock(lock_file):
        work_dir = Path(tempfile.mkdtemp(prefix="corpus-", dir=scratch_dir()))
        local = work_dir / canonical.name
        try:
            if canonical.exists():
                shutil.copy2(canonical, local)
            elif not create:
                raise FileNotFoundError(
                    f"no corpus database at {canonical}; run migrate.py"
                )

            conn = sqlite3.connect(local, isolation_level="DEFERRED")
            _configure(conn, writable=True)
            try:
                yield conn
                conn.commit()
            except BaseException:
                conn.rollback()
                raise
            finally:
                # Fold the WAL back in so the published file is self-contained.
                conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                conn.close()

            # Publish: stage into the SAME directory so rename is atomic.
            staged = canonical.with_suffix(canonical.suffix + f".new.{os.getpid()}")
            shutil.copy2(local, staged)
            with open(staged, "rb") as f:
                os.fsync(f.fileno())
            os.replace(staged, canonical)
        finally:
            shutil.rmtree(work_dir, ignore_errors=True)


def one(conn: sqlite3.Connection, sql: str, params=()):
    row = conn.execute(sql, params).fetchone()
    return row[0] if row else None


def get_or_create(conn, table, match: dict, insert: dict, pk: str) -> tuple[int, bool]:
    """Idempotent dimension resolution. Returns (id, created)."""
    where = " AND ".join(f"{k} IS ?" if v is None else f"{k} = ?" for k, v in match.items())
    existing = one(conn, f"SELECT {pk} FROM {table} WHERE {where}", tuple(match.values()))
    if existing is not None:
        return int(existing), False
    cols = ", ".join(insert)
    marks = ", ".join("?" * len(insert))
    cur = conn.execute(f"INSERT INTO {table} ({cols}) VALUES ({marks})", tuple(insert.values()))
    return int(cur.lastrowid), True
