-- Canary rework: job-level probe (0014).
--
-- The canary no longer brackets every cell inside run_tpch. It is now a
-- standalone executable (src/tools/canary.cpp, CMake target `canary`) run by
-- the run-job prologue (phase=before) and epilogue (phase=after), exactly like
-- capture_env.sh brackets a job for run-environment. Observations therefore
-- link to the job's ingest_batch, not to a per-cell run.
--
-- v_canary_run (per-cell) is obsolete and replaced by v_canary_batch
-- (per-job). canary_observation.run_id is retained as nullable for any future
-- per-cell use, but job-level canaries set batch_id and leave run_id NULL.

ALTER TABLE canary_observation ADD COLUMN batch_id INTEGER REFERENCES ingest_batch;

CREATE INDEX ix_canary_obs_batch ON canary_observation (batch_id, canary_id, phase);

DROP VIEW IF EXISTS v_canary_run;

-- Per-batch canary health: the before/after spread for each kind at the job
-- level. The auto:canary-v1 quality rule reads this to flag batches whose
-- bracketing canary deviates from the (future, null-calibrated) baseline.
CREATE VIEW v_canary_batch AS
SELECT
    o.batch_id,
    ib.out_file,
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
JOIN ingest_batch ib      ON ib.batch_id = o.batch_id
JOIN canary c             ON c.canary_id = o.canary_id
JOIN machine_snapshot ms  ON ms.snapshot_id = o.snapshot_id
JOIN machine m            ON m.machine_id = ms.machine_id
GROUP BY o.batch_id, c.canary_id;
