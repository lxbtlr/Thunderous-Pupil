-- Canary reference measurements bracketing every timed cell.
--
-- A tiny frozen workload (canary-v1@<git commit>, see include/canary.hpp) run
-- immediately before and after each timed cell. Its runtime is a direct
-- statement about machine behaviour at that moment: if the canary beside a
-- measurement is slow, the measurement is suspect no matter how clean ambient
-- state looked; if it is normal, ambient weirdness is probably irrelevant.
--
-- Two kinds respond to different machine misbehaviour:
--   'compute'  cache-resident, compute-bound  -> clock / thermal / ALU contention
--   'memory'   memory-bound (pointer chase)   -> DRAM latency / NUMA / scrubbing
-- The ratio between them tells which kind of problem occurred.
--
-- canary_version is "<workload-version>@<git-commit>" so a canary is both
-- version-controlled and reproducible. A changed workload is a NEW canary
-- (its history restarts), the same discipline as probe.version.

CREATE TABLE canary (
    canary_id       INTEGER PRIMARY KEY,
    canary_version  TEXT NOT NULL,   -- 'canary-v1@20665a7'
    kind            TEXT NOT NULL,   -- 'compute' | 'memory'
    workload        TEXT NOT NULL,   -- frozen parameter description
    frozen_since    TEXT NOT NULL,   -- ISO-8601 UTC
    UNIQUE (canary_version, kind)
) STRICT;

CREATE TABLE canary_observation (
    obs_id      INTEGER PRIMARY KEY,
    canary_id   INTEGER NOT NULL REFERENCES canary,
    snapshot_id INTEGER NOT NULL REFERENCES machine_snapshot,
    run_id      INTEGER REFERENCES run,     -- the bracketed cell, when resolved
    phase       TEXT NOT NULL,              -- 'before' | 'after'
    median_ns   REAL NOT NULL,
    mean_ns     REAL NOT NULL,
    min_ns      REAL NOT NULL,
    max_ns      REAL NOT NULL,
    stddev_ns   REAL NOT NULL,
    reps        INTEGER NOT NULL,
    threads     INTEGER NOT NULL,
    observed_at TEXT NOT NULL,
    CHECK (phase IN ('before','after'))
) STRICT;

CREATE INDEX ix_canary_obs_snap ON canary_observation (snapshot_id, canary_id, phase);
CREATE INDEX ix_canary_obs_run  ON canary_observation (run_id);

-- Per-run canary health: the before/after spread for each kind. The
-- auto:canary-v1 quality rule reads this to flag runs whose bracketing canary
-- deviates from the (future, null-calibrated) baseline.
CREATE VIEW v_canary_run AS
SELECT
    o.run_id,
    r.raw_name,
    r.quality,
    c.canary_version,
    c.kind,
    m.stable_key AS node,
    MAX(CASE WHEN o.phase = 'before' THEN o.median_ns END) AS before_ns,
    MAX(CASE WHEN o.phase = 'after'  THEN o.median_ns END) AS after_ns,
    ROUND(100.0 * (
        MAX(CASE WHEN o.phase = 'after'  THEN o.median_ns END) -
        MAX(CASE WHEN o.phase = 'before' THEN o.median_ns END)) /
        NULLIF(MAX(CASE WHEN o.phase = 'before' THEN o.median_ns END), 0), 2)
      AS before_after_pct
FROM canary_observation o
JOIN run r              ON r.run_id = o.run_id
JOIN canary c           ON c.canary_id = o.canary_id
JOIN machine_snapshot ms ON ms.snapshot_id = o.snapshot_id
JOIN machine m           ON m.machine_id = ms.machine_id
GROUP BY o.run_id, c.canary_id;
