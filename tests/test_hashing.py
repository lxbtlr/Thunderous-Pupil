"""
Digest pinning. If a refactor changes a hash, this fails loudly rather than
the corpus silently degrading into duplicate dimension rows.
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from corpus.hashing import spec_hash, task_hash, machine_fingerprint


def test_spec_hash_normalization():
    """ON/TRUE/1, case, flag order, and trailing slashes must not matter."""
    a = spec_hash(repo_url="local:db-engines/", repo_sha_hex="1F01D6A0" * 5,
                  repo_dirty=0, worktree_sha_hex=None, config_name="shard_huge",
                  cmake_defs={"numa_shard": "on"}, build_type="Release",
                  compiler="GCC", compiler_version="11.3.0", cxx_flags=["-O3", "-g"])
    b = spec_hash(repo_url="local:db-engines", repo_sha_hex="1f01d6a0" * 5,
                  repo_dirty=False, worktree_sha_hex="", config_name="shard_huge",
                  cmake_defs={"NUMA_SHARD": "TRUE"}, build_type="release",
                  compiler="gcc", compiler_version="11.3.0", cxx_flags=["-g", "-O3"])
    assert a == b


def test_spec_hash_distinguishes_configs():
    base = dict(repo_url="local:db-engines", repo_sha_hex="ab" * 20, repo_dirty=0,
                worktree_sha_hex=None, build_type="Release", compiler="gcc",
                compiler_version="11.3.0", cxx_flags=[])
    huge = spec_hash(config_name="default_huge", cmake_defs={}, **base)
    nohuge = spec_hash(config_name="default_nohuge",
                       cmake_defs={"NO_HUGE_PAGES": "ON"}, **base)
    interleave = spec_hash(config_name="default_huge",
                           cmake_defs={"INTERLEAVE_HT": "ON"}, **base)
    assert len({huge, nohuge, interleave}) == 3


def test_task_hash_pinned():
    """A known input must always give this digest."""
    d = task_hash(benchmark="tpch", q_number=9, manifest_sha256_hex="de" * 32,
                  threads=64, vector_size=None)
    assert d.hex() == PINNED_TASK, f"task_hash changed: {d.hex()}"


def test_fingerprint_ignores_derived_fields():
    base = {"cpu_model": "Xeon", "cores_physical": 88, "l3_bytes": 47185920}
    assert machine_fingerprint(base) == machine_fingerprint({**base, "microarch": "skx"})


def test_fingerprint_catches_thp_and_governor():
    base = {"cpu_model": "Xeon", "thp_state": "always", "cpu_governor": "performance"}
    assert machine_fingerprint(base) != machine_fingerprint({**base, "thp_state": "never"})
    assert machine_fingerprint(base) != machine_fingerprint({**base, "cpu_governor": "powersave"})


PINNED_TASK = "532b81a78932e3e81fbc13e56bfb3204b3d9c4946a13796faaac1cfa51119daa"

if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn(); print(f"  ok  {name}")
    print(f"\nPINNED_TASK frozen at {PINNED_TASK[:16]}...")
