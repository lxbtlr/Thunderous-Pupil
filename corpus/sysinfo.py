"""
Machine identification from tools that do not require root.

dmidecode is attempted but NOT required: on dubliner it fails on both
/sys/firmware/dmi/tables/smbios_entry_point and /dev/mem without root or
CAP_SYS_RAWIO. Everything that actually matters -- cache sizes, NUMA topology,
core counts, SIMD support -- comes from lscpu and sysfs instead.
"""

from __future__ import annotations

import json
import platform
import re
import subprocess
from pathlib import Path

PARSER_VERSION = "1"

SIMD_OF_INTEREST = (
    "sse4_2", "avx", "avx2", "avx512f", "avx512bw", "avx512dq",
    "avx512vl", "avx512cd", "amx_tile", "neon", "sve",
)

TOOLS = [
    ("lscpu", ["lscpu"]),
    ("lscpu_json", ["lscpu", "-J"]),
    ("numactl", ["numactl", "--hardware"]),
    ("lstopo", ["lstopo-no-graphics", "--of", "console"]),
    ("proc_cpuinfo", ["cat", "/proc/cpuinfo"]),
    ("meminfo", ["cat", "/proc/meminfo"]),
    ("dmidecode", ["dmidecode", "-t", "memory"]),   # expected to fail; kept anyway
]


def capture_all() -> list[dict]:
    out = []
    for name, cmd in TOOLS:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            out.append({"tool": name, "args": " ".join(cmd[1:]),
                        "exit_code": r.returncode,
                        "text": r.stdout if r.returncode == 0 else (r.stdout + r.stderr)})
        except (OSError, subprocess.SubprocessError) as e:
            out.append({"tool": name, "args": " ".join(cmd[1:]),
                        "exit_code": -1, "text": f"<not run: {e}>"})
    for name, path in (("sysfs_cache", "/sys/devices/system/cpu/cpu0/cache"),
                       ("thp", "/sys/kernel/mm/transparent_hugepage/enabled"),
                       ("governor", "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")):
        out.append({"tool": name, "args": path, "exit_code": 0,
                    "text": _read_tree(Path(path))})
    return out


def _read_tree(p: Path) -> str:
    if p.is_file():
        try:
            return p.read_text().strip()
        except OSError as e:
            return f"<unreadable: {e}>"
    if not p.is_dir():
        return "<absent>"
    lines = []
    for f in sorted(p.rglob("*")):
        if f.is_file():
            try:
                lines.append(f"{f}: {f.read_text().strip()}")
            except OSError:
                pass
    return "\n".join(lines)


def _lscpu_kv(text: str) -> dict:
    kv = {}
    for line in text.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            kv[k.strip()] = v.strip()
    return kv


def _bytes_from(s: str | None) -> int | None:
    if not s:
        return None
    m = re.search(r"([\d.]+)\s*([KMG])?i?B?", s)
    if not m:
        return None
    n = float(m.group(1))
    return int(n * {None: 1, "K": 1 << 10, "M": 1 << 20, "G": 1 << 30}[m.group(2)])


def parse_snapshot(captures: list[dict]) -> dict:
    by = {c["tool"]: c["text"] for c in captures}
    kv = _lscpu_kv(by.get("lscpu", ""))
    flags = set(by.get("proc_cpuinfo", "").split())

    simd = sorted(f for f in SIMD_OF_INTEREST if f in flags)
    if any(f.startswith("avx512") for f in simd):
        simd_bits = 512
    elif "avx2" in simd or "avx" in simd:
        simd_bits = 256
    elif "sse4_2" in simd:
        simd_bits = 128
    else:
        simd_bits = None

    mem_kb = re.search(r"MemTotal:\s+(\d+)", by.get("meminfo", ""))

    def i(key):
        v = kv.get(key)
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return None

    cores_per_socket = i("Core(s) per socket")
    sockets = i("Socket(s)")
    threads_per_core = i("Thread(s) per core")

    return {
        "cpu_vendor": kv.get("Vendor ID"),
        "cpu_model": kv.get("Model name"),
        "microarch": kv.get("Model name"),
        "cpu_sockets": sockets,
        "cores_physical": (cores_per_socket * sockets) if cores_per_socket and sockets else None,
        "threads_logical": i("CPU(s)"),
        "base_mhz": i("CPU min MHz"),
        "max_mhz": i("CPU max MHz"),
        "l1d_bytes": _bytes_from(kv.get("L1d cache")),
        "l2_bytes": _bytes_from(kv.get("L2 cache")),
        "l3_bytes": _bytes_from(kv.get("L3 cache")),
        "numa_nodes": i("NUMA node(s)"),
        "ram_bytes": int(mem_kb.group(1)) * 1024 if mem_kb else None,
        "simd_flags": json.dumps(simd),
        "max_simd_bits": simd_bits,
        "os_name": " ".join(platform.linux_distribution()) if hasattr(platform, "linux_distribution") else platform.system(),
        "kernel_version": platform.release(),
        "libc_version": " ".join(platform.libc_ver()),
        "smt_enabled": 1 if (threads_per_core or 1) > 1 else 0,
        "cpu_governor": by.get("governor", "").strip() or None,
        "thp_state": by.get("thp", "").strip() or None,
    }
