-- Facts. Grain is the CELL: one (task, build, snapshot, engine) measurement,
-- because run_tpch aggregates repetitions internally and emits moments.
-- If run.cpp is later patched to emit per-repetition rows, add a child table;
-- do not reshape this one.

CREATE TABLE ingest_batch (
    batch_id       INTEGER PRIMARY KEY,
    out_file       TEXT NOT NULL,
    out_sha256     BLOB NOT NULL,
    header_version TEXT NOT NULL,
    slurm_job_id   TEXT,
    label          TEXT,                 -- '<label>_<TS>' from the .out name
    -- Unit the harness reports timings in. VERIFY against run.cpp before
    -- trusting any absolute number; ratios are safe either way.
    timing_unit    TEXT NOT NULL,        -- 's' | 'ms' | 'us' | 'ns'
    ingested_at    TEXT NOT NULL,
    tool_version   TEXT NOT NULL,
    UNIQUE (out_sha256)
) STRICT;

CREATE TABLE run (
    run_id          INTEGER PRIMARY KEY,
    task_id         INTEGER NOT NULL REFERENCES task,
    build_event_id  INTEGER NOT NULL REFERENCES build_event,
    snapshot_id     INTEGER NOT NULL REFERENCES machine_snapshot,
    engine_id       INTEGER NOT NULL REFERENCES engine,
    -- Distinguishes deliberate re-measurement of an identical cell from an
    -- accidental duplicate ingest. Bumped by the caller, never auto.
    trial           INTEGER NOT NULL DEFAULT 0,

    reps            INTEGER,             -- run_tpch -r
    median_ns       REAL,
    mean_ns         REAL,
    min_ns          REAL,
    max_ns          REAL,
    stddev_ns       REAL,
    cpus            INTEGER,             -- CSV 'CPUs' column: config echo

    batch_id        INTEGER NOT NULL REFERENCES ingest_batch,
    source_row_ord  INTEGER NOT NULL,    -- row index in the .out, for traceback
    raw_name        TEXT NOT NULL,       -- verbatim 'q1 h  t16'
    started_at      TEXT,

    quality         TEXT NOT NULL DEFAULT 'clean',
    UNIQUE (task_id, build_event_id, snapshot_id, engine_id, trial),
    CHECK (quality IN ('clean','suspect','excluded'))
) STRICT;

CREATE INDEX ix_run_task ON run (task_id, engine_id);
CREATE INDEX ix_run_build ON run (build_event_id);
CREATE INDEX ix_run_batch ON run (batch_id);

CREATE TABLE run_counter (
    run_id    INTEGER NOT NULL REFERENCES run ON DELETE CASCADE,
    col_ord   INTEGER NOT NULL,          -- source column, disambiguates duplicates
    event_id  INTEGER NOT NULL REFERENCES pmu_event,
    value     REAL NOT NULL,
    PRIMARY KEY (run_id, col_ord)
) STRICT;

CREATE INDEX ix_counter_event ON run_counter (event_id);

CREATE TABLE run_quality_event (
    event_pk    INTEGER PRIMARY KEY,
    run_id      INTEGER NOT NULL REFERENCES run,
    quality     TEXT NOT NULL,
    reason      TEXT,
    rule        TEXT NOT NULL,           -- 'auto:cv-v1', 'human:alexb'
    decided_at  TEXT NOT NULL
) STRICT;

-- Convenience: cells with both engines present, ready for comparison.
CREATE VIEW engine_pair AS
SELECT h.task_id, h.build_event_id, h.snapshot_id,
       h.median_ns AS h_median_ns,
       v.median_ns AS v_median_ns,
       h.median_ns / v.median_ns AS h_over_v
FROM run h
JOIN run v
  ON v.task_id = h.task_id
 AND v.build_event_id = h.build_event_id
 AND v.snapshot_id = h.snapshot_id
 AND v.trial = h.trial
JOIN engine eh ON eh.engine_id = h.engine_id AND eh.code = 'h'
JOIN engine ev ON ev.engine_id = v.engine_id AND ev.code = 'v'
WHERE h.quality = 'clean' AND v.quality = 'clean';
