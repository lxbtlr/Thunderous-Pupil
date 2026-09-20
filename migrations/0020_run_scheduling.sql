-- 0020_run_scheduling.sql
-- Run-policy dimension on `run`.
--
-- build_event is keyed to the compiled artifact (spec + binary); a runtime
-- scheduling policy such as `chrt -f 1` is NOT a build characteristic and so
-- must not be minted as a distinct build_event_id (that would record two runs
-- of the identical binary as "different builds"). Policy is a property of how
-- a run is scheduled, so it lives on `run` and participates in the run natural
-- key. This lets deliberate re-runs of the same binary under a different
-- scheduler be recorded AND labeled, instead of silently deduping against the
-- earlier policy or being conflated with `trial`.
--
-- Change: run gains `scheduling TEXT NOT NULL DEFAULT 'default'` and the
-- natural key becomes
--     UNIQUE(task_id, build_event_id, snapshot_id, engine_id, trial, scheduling)
-- SQLite cannot alter a UNIQUE constraint, so `run` is rebuilt. Its FK
-- children (run_counter, run_quality_event, run_canary, run_timeline) and the
-- views reference it by name, so a drop-and-rename swap preserves them.
--
-- ingest_batch keeps UNIQUE(out_sha256): one .out file is one run under one
-- scheduling, so re-ingesting the same file under a second policy is an error,
-- not a feature. If a file truly needs re-reading under a new policy, clear
-- its stale ingest_batch row first.
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
    UNIQUE (task_id, build_event_id, snapshot_id, engine_id, trial, scheduling),
    CHECK (quality IN ('clean','suspect','excluded'))
) STRICT;

INSERT INTO run_new (run_id, task_id, build_event_id, snapshot_id, engine_id, trial,
                     scheduling, reps, median_ns, mean_ns, min_ns, max_ns, stddev_ns,
                     cpus, batch_id, source_row_ord, raw_name, started_at, quality)
SELECT run_id, task_id, build_event_id, snapshot_id, engine_id, trial,
       'default', reps, median_ns, mean_ns, min_ns, max_ns, stddev_ns,
       cpus, batch_id, source_row_ord, raw_name, started_at, quality
FROM run;

DROP TABLE run;

CREATE INDEX ix_run_task  ON run_new (task_id, engine_id);
CREATE INDEX ix_run_build ON run_new (build_event_id);
CREATE INDEX ix_run_batch ON run_new (batch_id);

-- RENAME without rewriting references in the 11 views that select FROM run;
-- with the default alter behaviour SQLite recompiles them mid-rename and hits
-- "no such table: main.run" (run does not exist until the rename completes).
PRAGMA legacy_alter_table = ON;
ALTER TABLE run_new RENAME TO run;
PRAGMA legacy_alter_table = OFF;

PRAGMA foreign_keys = ON;
