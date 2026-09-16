"""Binary characterization: content hash, GNU build-id, .text size, ldd deps."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

from .hashing import file_sha256


def _run(cmd) -> str:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def gnu_build_id(path) -> bytes | None:
    out = _run(["readelf", "-n", str(path)])
    m = re.search(r"Build ID:\s*([0-9a-fA-F]+)", out)
    return bytes.fromhex(m.group(1)) if m else None


def text_size(path) -> int | None:
    out = _run(["readelf", "-S", "-W", str(path)])
    for line in out.splitlines():
        if re.search(r"\s\.text\s", line):
            parts = line.split()
            try:
                return int(parts[parts.index(".text") + 4], 16)
            except (ValueError, IndexError):
                return None
    return None


def is_stripped(path) -> bool | None:
    out = _run(["file", "-b", str(path)])
    if not out:
        return None
    return "not stripped" not in out


def dyn_deps(path) -> dict:
    """
    Resolved shared libraries and their versions. oneTBB belongs here: a TBB
    bump moves numbers and is invisible in the source hash.
    """
    deps = {}
    for line in _run(["ldd", str(path)]).splitlines():
        m = re.match(r"\s*(\S+)\s*=>\s*(\S+)", line)
        if not m:
            continue
        soname, resolved = m.group(1), m.group(2)
        if resolved in ("not", ""):
            deps[soname] = None
            continue
        real = Path(resolved)
        try:
            real = real.resolve()
        except OSError:
            pass
        ver = re.search(r"\.so[.\d]*\.([\d.]+)$", real.name)
        deps[soname] = {"path": str(real), "version": ver.group(1) if ver else real.name}
    return deps


def characterize(path) -> dict:
    p = Path(path)
    return {
        "content_sha256": file_sha256(p),
        "gnu_build_id": gnu_build_id(p),
        "size_bytes": p.stat().st_size,
        "text_size_bytes": text_size(p),
        "stripped": is_stripped(p),
        "dyn_deps": dyn_deps(p),
    }
