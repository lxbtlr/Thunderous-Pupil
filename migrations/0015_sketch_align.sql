-- 0015_sketch_align.sql
-- Align the Tier-1/Tier-2 tables with the agreed schema sketch:
--   run_environment   (renamed from environment_observation; + raw_text so
--                       re-parsing is free; stays BATCH-keyed per decision 1.b)
--   run_timeline      (renamed from run_timeline_event; + sweep view)
--   run_canary        (renamed from canary_observation; + deviation_from_median,
--                       keeps the five raw moments per decision 2)
--   canary            (+ name, binary_sha256, task_spec)
--   null_sample       (new — Tier-3 noise floor)
--   quality_rule      (new — self-describing grades)
--
-- Decisions:
--   1.b  environment stays batch-keyed (only canary + timeline go per-run)
--   2.   keep the five raw moments; deviation_from_median is derived (column
--        + view) against the null_sample noise floor
--   3.   binary_sha256 identifies the canary BINARY build that produced the
--        version (on canary, not on the observation)

-- 1. run_environment: rename + raw content so re-parsing is free.
ALTER TABLE environment_observation RENAME TO run_environment;
ALTER TABLE run_environment ADD COLUMN raw_text TEXT;  -- full <out>.env-<phase> sidecar

-- 2. run_timeline: rename to match the sketch.
ALTER TABLE run_timeline_event RENAME TO run_timeline;

-- 3. run_canary: rename + derived deviation column (raw moments retained).
ALTER TABLE canary_observation RENAME TO run_canary;
ALTER TABLE run_canary ADD COLUMN deviation_from_median REAL;  -- NULL until null_sample exists

-- 4. canary: identify the canary binary build + frozen task spec.
ALTER TABLE canary ADD COLUMN name TEXT;
ALTER TABLE canary ADD COLUMN binary_sha256 BLOB;  -- sha of the canary executable producing this version
ALTER TABLE canary ADD COLUMN task_spec TEXT;      -- frozen task description
UPDATE canary SET name = canary_version || ' ' || kind,
                  task_spec = workload;

-- 5. null_sample: Tier-3 noise floor — the canary under zero work, so a run's
--    real time can be separated from measurement overhead. One row per trial
--    of (binary, task, snapshot).
CREATE TABLE null_sample (
    null_sample_id INTEGER PRIMARY KEY,
    binary_id      INTEGER NOT NULL REFERENCES binary(binary_id),
    task_id        INTEGER NOT NULL REFERENCES task(task_id),
    snapshot_id    INTEGER NOT NULL REFERENCES machine_snapshot(snapshot_id),
    trial          INTEGER NOT NULL,
    wall_ns        REAL NOT NULL,
    taken_at       TEXT NOT NULL,
    UNIQUE (binary_id, task_id, snapshot_id, trial)
) STRICT;

-- 6. quality_rule: vocabulary behind run_quality_event.rule, so grades are
--    self-describing (the corpus can say WHAT rule, at WHAT version, graded a
--    cell — not just a bare string).
CREATE TABLE quality_rule (
    rule_id     INTEGER PRIMARY KEY,
    rule        TEXT NOT NULL UNIQUE,
    version     TEXT NOT NULL,
    description TEXT NOT NULL
) STRICT;
INSERT INTO quality_rule (rule, version, description) VALUES
  ('auto:canary-v1', 'v1',
   'batch bracketed by canary-v1; flags when before/after drift or deviation from the null-calibrated floor exceeds threshold'),
  ('auto:cv-v1',     'v1',
   'coefficient-of-variation on run moments; flags unstable cells'),
  ('human:alexb',    'v1',
   'manual review by alexb');

-- ── Recreate views invalidated by the renames ─────────────────────────────
DROP VIEW IF EXISTS v_env_delta;
CREATE VIEW v_env_delta AS
WITH b AS (SELECT * FROM environment_fact WHERE env_obs_id IN
             (SELECT env_obs_id FROM run_environment WHERE phase='before')),
     a AS (SELECT * FROM environment_fact WHERE env_obs_id IN
             (SELECT env_obs_id FROM run_environment WHERE phase='after'))
SELECT a.key,
       a.env_obs_id AS after_obs_id,
       b.value_num  AS before_num,
       a.value_num  AS after_num,
       ROUND(100.0 * (a.value_num - b.value_num) / NULLIF(b.value_num, 0), 3) AS delta_pct,
       a.value_text AS after_text
FROM a JOIN b USING (key)
WHERE a.value_num IS NOT NULL AND b.value_num IS NOT NULL;

DROP VIEW IF EXISTS v_cell_timeline;
CREATE VIEW v_cell_timeline AS
SELECT r.run_id, r.raw_name,
       t.batch_id,
       MAX(CASE WHEN t.event='measure_start' THEN t.at_ms END) AS measure_start_ms,
       MAX(CASE WHEN t.event='measure_end'   THEN t.at_ms END) AS measure_end_ms,
       MAX(CASE WHEN t.event='measure_end'   THEN t.at_ms END) -
       MAX(CASE WHEN t.event='measure_start' THEN t.at_ms END) AS cell_window_ms
FROM run_timeline t
JOIN run r ON r.run_id = t.run_id
WHERE t.event IN ('measure_start','measure_end')
GROUP BY r.run_id;

DROP VIEW IF EXISTS v_canary_batch;
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
FROM run_canary o
JOIN ingest_batch ib      ON ib.batch_id = o.batch_id
JOIN canary c             ON c.canary_id = o.canary_id
JOIN machine_snapshot ms  ON ms.snapshot_id = o.snapshot_id
JOIN machine m            ON m.machine_id = ms.machine_id
GROUP BY o.batch_id, c.canary_id;

-- ── New views matching the sketch ─────────────────────────────────────────
-- Named-column environment snapshot per (batch, phase), matching the sketch's
-- run_environment columns. capture_env.sh emits granular keys; this pivots the
-- relevant ones. thp_state is text, the rest numeric.
CREATE VIEW v_env_snapshot AS
WITH e AS (
    SELECT env_obs_id, batch_id, phase, captured_at
    FROM run_environment
),
f AS (SELECT env_obs_id, key, value_num, value_text FROM environment_fact)
SELECT
    e.batch_id, e.phase, e.captured_at,
    MAX(CASE WHEN f.key='psi_cpu_some_avg10'        THEN f.value_num END) AS psi_cpu_avg10,
    MAX(CASE WHEN f.key='psi_io_some_avg10'         THEN f.value_num END) AS psi_io_avg10,
    MAX(CASE WHEN f.key='meminfo_MemAvailable_kB'   THEN f.value_num END) AS mem_available_kb,
    MAX(CASE WHEN f.key='meminfo_Dirty_kB'          THEN f.value_num END) AS dirty_kb,
    MAX(CASE WHEN f.key='stat_ctxt'                 THEN f.value_num END) AS ctxt_switches,
    MAX(CASE WHEN f.key='stat_steal_ticks'          THEN f.value_num END) AS steal_ticks,
    MAX(CASE WHEN f.key='proc_count'                THEN f.value_num END) AS proc_count,
    MAX(CASE WHEN f.key='freq_min_khz'              THEN f.value_num/1000.0 END) AS freq_mhz_min,
    MAX(CASE WHEN f.key='freq_mean_khz'             THEN f.value_num/1000.0 END) AS freq_mhz_mean,
    MAX(CASE WHEN f.key='freq_max_khz'              THEN f.value_num/1000.0 END) AS freq_mhz_max,
    MAX(CASE WHEN f.key='thp_enabled'               THEN f.value_text END) AS thp_state,
    MAX(CASE WHEN f.key='meminfo_AnonHugePages_kB'  THEN f.value_num END) AS anon_hugepages_kb,
    MAX(CASE WHEN f.key='meminfo_HugePages_Free'    THEN f.value_num END) AS hugepages_free,
    MAX(CASE WHEN f.key='numa_miss'                 THEN f.value_num END) AS numa_miss,
    MAX(CASE WHEN f.key='numa_foreign'              THEN f.value_num END) AS numa_foreign
FROM e LEFT JOIN f USING (env_obs_id)
GROUP BY e.batch_id, e.phase;

-- Derived canary deviation vs the null_sample noise floor. Provisional: keyed
-- on the machine snapshot; NULL until null_sample rows exist (Tier 3). Uses the
-- floor mean as a stand-in for the median until null calibration lands.
CREATE VIEW v_run_canary_deviation AS
WITH floor AS (
    SELECT snapshot_id, AVG(wall_ns) AS null_avg_ns, COUNT(*) AS null_n
    FROM null_sample GROUP BY snapshot_id
)
SELECT rc.obs_id, rc.batch_id, rc.run_id,
       c.canary_version, c.kind, rc.phase,
       rc.median_ns, fl.null_avg_ns, fl.null_n,
       ROUND(100.0 * (rc.median_ns - fl.null_avg_ns) / NULLIF(fl.null_avg_ns, 0), 3)
         AS deviation_from_median_pct
FROM run_canary rc
JOIN canary c   ON c.canary_id = rc.canary_id
LEFT JOIN floor fl ON fl.snapshot_id = rc.snapshot_id;

-- Timeline sweep view: per-task ordering across a batch and the gap between
-- consecutive runs of the same task. at_ms is monotonic (process-relative), so
-- within a single batch (one process baseline) the gap is correct; across
-- jobs it is only meaningful once epoch start is populated.
CREATE VIEW v_run_timeline_sweep AS
WITH starts AS (
    SELECT r.run_id, r.raw_name, r.task_id,
           MAX(CASE WHEN t.event='measure_start' THEN t.at_ms END) AS start_ms,
           MAX(CASE WHEN t.event='measure_start' THEN 1 ELSE 0 END) AS has_start
    FROM run_timeline t
    JOIN run r ON r.run_id = t.run_id
    GROUP BY r.run_id
)
SELECT run_id, raw_name, task_id, start_ms,
       ROUND((start_ms - LAG(start_ms) OVER (PARTITION BY task_id ORDER BY start_ms)) / 1000.0, 3)
         AS gap_since_prev_run_s,
       ROW_NUMBER() OVER (PARTITION BY task_id ORDER BY start_ms) AS sweep_position
FROM starts
WHERE has_start = 1;
