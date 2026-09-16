"""
Parser for run_tpch CSV output.

The .out file IS the CSV -- no tldr text mixed in. Quirks handled here, all of
them pinned by tests/fixtures/:
  * `name` looks like 'q1 h  t16': query number, engine letter, 't'-prefixed
    threads, separated by runs of spaces.
  * The header has a trailing comma, producing an empty final field.
  * 'br. misses' appears TWICE. Columns are therefore addressed by ORDINAL,
    never by name. See csv_column in the schema.
  * Headers carry stray whitespace.
  * Repeated headers appear when files are concatenated; they are skipped.
"""

from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass, field

NAME_RE = re.compile(r"^\s*q(?P<q>\d+)\s+(?P<engine>[a-z])\s+t(?P<threads>\d+)\s*$")

TIMING_STATS = ("median", "mean", "min", "max", "stddev")

UNIT_TO_NS = {"s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1.0}


class ParseError(ValueError):
    pass


@dataclass
class Row:
    row_ord: int
    raw_name: str
    q_number: int
    engine: str
    threads: int
    timings_ns: dict = field(default_factory=dict)
    cpus: int | None = None
    counters: dict = field(default_factory=dict)   # col_ord -> float


def normalize_header(cells: list[str]) -> list[str]:
    out = [c.strip() for c in cells]
    while out and out[-1] == "":
        out.pop()
    return out


def header_signature(cells: list[str]) -> str:
    return "|".join(normalize_header(cells))


def parse_name(raw: str):
    m = NAME_RE.match(raw)
    if not m:
        raise ParseError(f"unparseable name field: {raw!r}")
    return int(m.group("q")), m.group("engine"), int(m.group("threads"))


def parse_out(text: str, column_map: dict, *, timing_unit: str = "s"):
    """
    column_map: {col_ord: {"role":..., "timing_stat":..., "event_id":...}}
                as loaded from the csv_column table.

    Returns (rows, header_cells). Raises on any column the map does not cover:
    an unrecognized header means run.cpp changed and the vocabulary needs a
    migration, not a guess.
    """
    if timing_unit not in UNIT_TO_NS:
        raise ParseError(f"unknown timing unit {timing_unit!r}")
    scale = UNIT_TO_NS[timing_unit]

    reader = csv.reader(io.StringIO(text))
    header = None
    rows: list[Row] = []
    row_ord = 0

    for cells in reader:
        cells = normalize_header(cells)
        if not cells:
            continue
        if cells[0] == "name":
            if header is None:
                header = cells
                # Validate BOTH position and text. Keying on ordinal alone
                # lets a column renamed in place slip through, which is the
                # exact drift this check exists to catch.
                problems = []
                for i, h in enumerate(header):
                    spec = column_map.get(i)
                    if spec is None:
                        problems.append(f"[{i}] {h!r} not in csv_column")
                    elif spec["raw_header"] != h:
                        problems.append(
                            f"[{i}] header is {h!r}, csv_column expects "
                            f"{spec['raw_header']!r}")
                missing = [i for i in column_map if i >= len(header)]
                if missing:
                    problems.append(
                        f"csv_column expects {len(column_map)} columns, "
                        f"header has {len(header)}")
                if problems:
                    raise ParseError(
                        "header does not match csv_column '"
                        + "; ".join(problems)
                        + "' -- run.cpp changed the output format; add a "
                          "vocabulary migration with a new header_version "
                          "rather than ingesting under the old one"
                    )
            elif cells != header:
                raise ParseError("concatenated files with differing headers")
            continue

        if header is None:
            raise ParseError("data row before any header")
        if len(cells) < len(header):
            cells = cells + [""] * (len(header) - len(cells))

        q, engine, threads = parse_name(cells[0])
        r = Row(row_ord=row_ord, raw_name=cells[0], q_number=q,
                engine=engine, threads=threads)

        for i, spec in column_map.items():
            if i >= len(cells):
                continue
            val = cells[i].strip()
            role = spec["role"]
            if role == "name":
                continue
            if val == "":
                continue
            if role == "timing":
                r.timings_ns[spec["timing_stat"]] = float(val) * scale
            elif role == "counter":
                r.counters[i] = float(val)
            elif role == "ignore":
                if header[i].strip() == "CPUs":
                    r.cpus = int(float(val))

        rows.append(r)
        row_ord += 1

    if header is None:
        raise ParseError("no header row found; is this really run_tpch output?")
    return rows, header
