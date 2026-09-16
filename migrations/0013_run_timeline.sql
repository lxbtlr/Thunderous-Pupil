-- 0013_run_timeline.sql
-- Tier-2 run-timeline: start/stop markers for everything, so the GAPS between
-- stages are recoverable after the fact (they are genuine confounders: a run
-- starting 2 s after the previous one is thermally hotter than one after a
-- 5-minute gap; run 1 of 200 and run 190 of 200 are not equivalent).
--
-- Two sources, kept separate in `source`:
--   run.cpp  — monotonic within-process stage markers emitted to stderr:
--              proc_start, load_end, measure_start/measure_end (per cell),
--              proc_end. Their deltas are the load time and each cell's wall
--              time including warmup/settle, independent of the CSV timings.
--   slurm    — job-submit / job-start / job-end wall-clock times, captured
--              from sacct in the epilogue sidecar <out>.timeline-slurm.
--
-- Measure events are linked to the run whose label they match (q1 h  t16 ...).

CREATE TABLE run_timeline_event (
    event_id   INTEGER PRIMARY KEY,
    batch_id   INTEGER NOT NULL REFERENCES ingest_batch(batch_id),
    run_id     INTEGER REFERENCES run(run_id),    -- linked cell, for measure events
    event      TEXT NOT NULL,                     -- proc_start|load_end|measure_start|measure_end|proc_end|job_submit|job_start|job_end
    label      TEXT,                              -- cell label for measure events
    at_ms      INTEGER,                           -- monotonic ms (run.cpp) or epoch ms (slurm)
    wall_clock TEXT,                              -- ISO timestamp, when available
    source     TEXT NOT NULL DEFAULT 'run.cpp'    -- run.cpp | slurm
) STRICT;

CREATE INDEX ix_timeline_batch ON run_timeline_event (batch_id);
CREATE INDEX ix_timeline_run   ON run_timeline_event (run_id);

-- Per-cell: the measured window as the timeline saw it (load_end -> measure_end),
-- plus proc_start->load_end (load time) on the batch level.
CREATE VIEW v_cell_timeline AS
SELECT r.run_id, r.raw_name,
       t.batch_id,
       MAX(CASE WHEN t.event='measure_start' THEN t.at_ms END) AS measure_start_ms,
       MAX(CASE WHEN t.event='measure_end'   THEN t.at_ms END) AS measure_end_ms,
       MAX(CASE WHEN t.event='measure_end'   THEN t.at_ms END) -
       MAX(CASE WHEN t.event='measure_start' THEN t.at_ms END) AS cell_window_ms
FROM run_timeline_event t
JOIN run r ON r.run_id = t.run_id
WHERE t.event IN ('measure_start','measure_end')
GROUP BY r.run_id;
