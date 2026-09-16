"""
Content hashes. Every one of these is computed in more than one place, so the
normalization rules live here and nowhere else.

Two implementations that disagree about whether flags are sorted before
hashing will create duplicate dimension rows that split every h-vs-v
comparison in half while looking perfectly healthy. tests/test_hashing.py
pins known inputs to known digests; if a refactor changes a digest, that test
fails loudly rather than the corpus degrading silently.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

HASH_VERSION = "1"


def _canon(obj) -> str:
    """Deterministic JSON: sorted keys, no whitespace, sorted lists of scalars."""
    def norm(o):
        if isinstance(o, dict):
            return {str(k): norm(v) for k, v in sorted(o.items(), key=lambda kv: str(kv[0]))}
        if isinstance(o, (list, tuple)):
            items = [norm(v) for v in o]
            if all(isinstance(v, str) for v in items):
                return sorted(items)
            return items
        if isinstance(o, bool):
            return o
        if isinstance(o, float) and o.is_integer():
            return int(o)
        return o
    return json.dumps(norm(obj), sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _digest(kind: str, obj) -> bytes:
    h = hashlib.sha256()
    h.update(f"{kind}\x00{HASH_VERSION}\x00".encode())
    h.update(_canon(obj).encode())
    return h.digest()


def spec_hash(*, repo_url, repo_sha_hex, repo_dirty, worktree_sha_hex,
              config_name, cmake_defs, build_type, compiler,
              compiler_version, cxx_flags) -> bytes:
    return _digest("build_spec", {
        "repo_url": repo_url.rstrip("/"),
        "repo_sha": repo_sha_hex.lower(),
        "repo_dirty": bool(repo_dirty),
        "worktree_sha": (worktree_sha_hex or "").lower(),
        "config_name": config_name,
        # ON/OFF/1/TRUE all mean the same thing to CMake; they must not mean
        # different things to the hash.
        "cmake_defs": {k.upper(): _cmake_bool(v) for k, v in (cmake_defs or {}).items()},
        "build_type": (build_type or "").lower(),
        "compiler": (compiler or "").lower(),
        "compiler_version": compiler_version or "",
        "cxx_flags": list(cxx_flags or []),
    })


def _cmake_bool(v):
    s = str(v).strip().upper()
    if s in ("ON", "TRUE", "YES", "1", "Y"):
        return "ON"
    if s in ("OFF", "FALSE", "NO", "0", "N", ""):
        return "OFF"
    return str(v)


def task_hash(*, benchmark, q_number, manifest_sha256_hex, threads, vector_size) -> bytes:
    return _digest("task", {
        "benchmark": benchmark,
        "q_number": int(q_number),
        "dataset": manifest_sha256_hex.lower(),
        "threads": int(threads),
        "vector_size": int(vector_size) if vector_size is not None else None,
    })


def dataset_manifest(data_dir: str | Path, *, content: bool = False):
    """
    Identify a TPC-H directory by its contents, not its path.

    Default is (relative name, size, mtime_ns), which is cheap and catches
    regeneration. content=True hashes every file, which is honest but slow at
    sf100 -- worth doing once when the data is first registered.
    """
    root = Path(data_dir).resolve()
    entries = []
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        st = p.stat()
        e = {"n": str(p.relative_to(root)), "b": st.st_size}
        if content:
            h = hashlib.sha256()
            with open(p, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 22), b""):
                    h.update(chunk)
            e["h"] = h.hexdigest()
        else:
            e["m"] = st.st_mtime_ns
        entries.append(e)
    manifest = {"mode": "content" if content else "stat", "files": entries}
    return _digest("dataset", manifest), manifest


FINGERPRINT_FIELDS = (
    "cpu_vendor", "cpu_model", "cpu_sockets", "cores_physical", "threads_logical",
    "base_mhz", "max_mhz", "l1d_bytes", "l2_bytes", "l3_bytes", "numa_nodes",
    "ram_bytes", "simd_flags", "os_name", "kernel_version", "libc_version",
    "smt_enabled", "cpu_governor", "thp_state",
)


def machine_fingerprint(snapshot: dict) -> bytes:
    """
    Deliberately excludes microarch (derived, may be relabelled by a parser
    update) and anything volatile. Includes thp_state and cpu_governor, which
    move performance and do change under you.
    """
    return _digest("snapshot", {k: snapshot.get(k) for k in FINGERPRINT_FIELDS})


def file_sha256(path: str | Path) -> bytes:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.digest()


def text_sha256(s: str) -> bytes:
    return hashlib.sha256(s.encode()).digest()
