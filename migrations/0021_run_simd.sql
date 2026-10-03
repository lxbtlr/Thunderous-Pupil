-- 0021_run_simd.sql
-- Runtime SIMD-experiment dimension on `run`.
--
-- The runtime SIMD feature toggles read by run_tpch at startup
-- (SIMDsel / SIMDjoin / SIMDproj / SIMDhash, exported as env vars before the
-- timed region) greatly affect runtime performance. They are per-run runtime
-- configuration of the SAME compiled binary, so — like `scheduling` (0020) —
-- they are NOT a build characteristic and must not mint a distinct
-- build_event_id. They live on `run` and participate in the run natural key so
-- the same binary run with different SIMD toggles is recorded AND labeled
-- instead of silently deduping against the earlier configuration.
--
-- Change: run gains four 0/1 columns
--     simd_sel  INTEGER NOT NULL DEFAULT 0
--     simd_join INTEGER NOT NULL DEFAULT 0
--     simd_proj INTEGER NOT NULL DEFAULT 0
--     simd_hash INTEGER NOT NULL DEFAULT 0
-- and the natural key becomes
--     UNIQUE(task_id, build_event_id, snapshot_id, engine_id, trial,
--            scheduling, simd_sel, simd_join, simd_proj, simd_hash)
--
-- Rebuild pattern identical to 0020 (SQLite cannot alter a UNIQUE; FK
-- children + views reference `run` by name, so drop-and-rename with
-- legacy_alter_table preserves them).
--
-- No math functions (see 0008), so this also runs under sql.js.

PRAGMA foreign_keys = OFF;

CREATE TABLE run_new (
    run_id          INTEGER PRIMARY KEY,
    task_id         INTEGER NOT NULL REFERENCES task,
    build_event_id  INTEGER NOT NULL REFERENCES build_event,
    snapshot_id     INTEGER NOT NULL REFERENCES machine_snapshot,
    engine_id       INTEGER NOT NULL REFERENCES engine,
    trial           INTEGER NOT NULL DEFAULT 0,
    scheduling      TEXT NOT NULL DEFAULT 'default',  -- e.g. 'default' | 'chrt-f1'
    simd_sel        INTEGER NOT NULL DEFAULT 0,       -- SIMDsel env toggle
    simd_join       INTEGER NOT NULL DEFAULT 0,       -- SIMDjoin env toggle
    simd_proj       INTEGER NOT NULL DEFAULT 0,       -- SIMDproj env toggle
    simd_hash       INTEGER NOT NULL DEFAULT 0,       -- SIMDhash env toggle
    reps            INTEGER,
    median_ns       REAL,
    mean_ns         REAL,
    min_ns          REAL,
    max_ns          REAL,
    stddev_ns       REAL,
    cpus            INTEGER,
    batch_id        INTEGER NOT NULL REFERENCES ingest_batch,
    source_row_ord  INTEGER NOT NULL,
    raw_name        TEXT NOT NULL,
    started_at      TEXT,
    quality         TEXT NOT NULL DEFAULT 'clean',
    UNIQUE (task_id, build_event_id, snapshot_id, engine_id, trial, scheduling,
            simd_sel, simd_join, simd_proj, simd_hash),
    CHECK (quality IN ('clean','suspect','excluded'))
) STRICT;

INSERT INTO run_new (run_id, task_id, build_event_id, snapshot_id, engine_id, trial,
                     scheduling, simd_sel, simd_join, simd_proj, simd_hash,
                     reps, median_ns, mean_ns, min_ns, max_ns, stddev_ns,
                     cpus, batch_id, source_row_ord, raw_name, started_at, quality)
SELECT run_id, task_id, build_event_id, snapshot_id, engine_id, trial,
       scheduling, 0, 0, 0, 0,
       reps, median_ns, mean_ns, min_ns, max_ns, stddev_ns,
       cpus, batch_id, source_row_ord, raw_name, started_at, quality
FROM run;

DROP TABLE run;

CREATE INDEX ix_run_task  ON run_new (task_id, engine_id);
CREATE INDEX ix_run_build ON run_new (build_event_id);
CREATE INDEX ix_run_batch ON run_new (batch_id);

-- RENAME without rewriting references in the views that select FROM run.
PRAGMA legacy_alter_table = ON;
ALTER TABLE run_new RENAME TO run;
PRAGMA legacy_alter_table = OFF;

PRAGMA foreign_keys = ON;
