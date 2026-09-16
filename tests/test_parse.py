"""Parser behaviour pinned against a real-shaped run_tpch header."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from corpus.parse import parse_out, parse_name, ParseError

FIX = pathlib.Path(__file__).parent / "fixtures" / "default_huge_sample.out"

COLMAP = {i: {"col_ord": i, "raw_header": h, "role": r, "timing_stat": s,
              "event_id": (i if r == "counter" else None)}
          for i, (h, r, s) in enumerate([
              ("name", "name", None), ("median", "timing", "median"),
              ("mean", "timing", "mean"), ("min", "timing", "min"),
              ("max", "timing", "max"), ("stddev", "timing", "stddev"),
              ("CPUs", "ignore", None), ("IPC", "counter", None),
              ("GHz", "counter", None), ("Bandwidth", "counter", None),
              ("cycles", "counter", None), ("LLC-misses", "counter", None),
              ("LLC-misses2", "counter", None), ("l1-misses", "counter", None),
              ("instr.", "counter", None), ("br. misses", "counter", None),
              ("all_rd", "counter", None), ("br. misses", "counter", None),
              ("stores", "counter", None), ("loads", "counter", None),
              ("mem_stall", "counter", None), ("task-clock", "counter", None)])}


def test_name_field():
    assert parse_name("q1 h  t16") == (1, "h", 16)
    assert parse_name("q18 v  t88") == (18, "v", 88)


def test_trailing_comma_and_dup_columns():
    rows, header = parse_out(FIX.read_text(), COLMAP)
    assert len(header) == 22, "trailing empty field must be dropped"
    assert header[15] == header[17] == "br. misses"
    r = rows[0]
    assert r.counters[15] != r.counters[17], "duplicates must stay distinct"


def test_timing_unit_conversion():
    rows, _ = parse_out(FIX.read_text(), COLMAP, timing_unit="s")
    assert abs(rows[0].timings_ns["median"] - 0.412e9) < 1
    rows_ms, _ = parse_out(FIX.read_text(), COLMAP, timing_unit="ms")
    assert abs(rows_ms[0].timings_ns["median"] - 0.412e6) < 1


def test_cpus_is_config_not_counter():
    rows, _ = parse_out(FIX.read_text(), COLMAP)
    assert rows[0].cpus == 16
    assert 6 not in rows[0].counters


def test_renamed_column_rejected():
    bad = FIX.read_text().replace("mem_stall", "frobnicator", 1)
    try:
        parse_out(bad, COLMAP)
    except ParseError as e:
        assert "frobnicator" in str(e)
    else:
        raise AssertionError("renamed column must be rejected")


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn(); print(f"  ok  {name}")
