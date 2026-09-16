-- Flat convenience views.
--
-- These were previously created by bin/publish-db, so they existed only in the
-- published copy and were missing from the canonical database -- any query
-- against v_runs from the CLI failed with "no such table". Convenience views
-- are schema; they belong in a migration, defined once, inherited by every
-- copy.
--
-- No math functions (see 0008): core scalars only, so these behave identically
-- under sql.js in the browser.

DROP VIEW IF EXISTS v_runs;
CREATE VIEW v_runs AS
SELECT
    r.run_id,
    bs.config_name,
    bs.cmake_defs,
    substr(hex(bs.repo_sha), 1, 8) AS head,
    be.build_event_id,
    be.binary_id,
    d.sf_label,
    d.scale_factor,
    q.label   AS query,
    q.q_number,
    e.code    AS engine,
    e.paradigm,
    t.threads,
    r.reps,
    ROUND(r.median_ns / 1e6, 3) AS median_ms,
    ROUND(r.mean_ns   / 1e6, 3) AS mean_ms,
    ROUND(r.min_ns    / 1e6, 3) AS min_ms,
    ROUND(r.max_ns    / 1e6, 3) AS max_ms,
    -- Coefficient of variation: the number that should set your tie threshold.
    ROUND(r.stddev_ns / NULLIF(r.mean_ns, 0), 4) AS cv,
    r.cpus,
    m.stable_key AS node,
    ms.snapshot_id,
    r.quality,
    r.trial,
    ib.ingested_at,
    ib.label AS batch_label
FROM run r
JOIN task t              ON t.task_id = r.task_id
JOIN query q             ON q.query_id = t.query_id
JOIN dataset d           ON d.dataset_id = t.dataset_id
JOIN engine e            ON e.engine_id = r.engine_id
JOIN build_event be      ON be.build_event_id = r.build_event_id
JOIN build_spec bs       ON bs.spec_id = be.spec_id
JOIN machine_snapshot ms ON ms.snapshot_id = r.snapshot_id
JOIN machine m           ON m.machine_id = ms.machine_id
JOIN ingest_batch ib     ON ib.batch_id = r.batch_id;

DROP VIEW IF EXISTS v_counters;
CREATE VIEW v_counters AS
SELECT
    rc.run_id,
    pe.canonical_name AS event,
    pe.unit,
    -- 'counter' is a raw PMU count; 'derived' (IPC, GHz, Bandwidth) is the
    -- harness's own arithmetic and is better recomputed from the raw counts.
    pe.kind,
    rc.col_ord,
    rc.value
FROM run_counter rc
JOIN pmu_event pe ON pe.event_id = rc.event_id;

-- Wide counter view: one row per run, raw counters as columns, with IPC
-- recomputed from cycles and instructions rather than taken from the harness.
DROP VIEW IF EXISTS v_run_counters_wide;
CREATE VIEW v_run_counters_wide AS
SELECT
    r.run_id, r.config_name, r.sf_label, r.query, r.engine, r.threads,
    r.median_ms,
    MAX(CASE WHEN c.event = 'cycles'        THEN c.value END) AS cycles,
    MAX(CASE WHEN c.event = 'instructions'  THEN c.value END) AS instructions,
    MAX(CASE WHEN c.event = 'llc_misses'    THEN c.value END) AS llc_misses,
    MAX(CASE WHEN c.event = 'l1_misses'     THEN c.value END) AS l1_misses,
    MAX(CASE WHEN c.event = 'br_misses_1'   THEN c.value END) AS br_misses,
    MAX(CASE WHEN c.event = 'stores'        THEN c.value END) AS stores,
    MAX(CASE WHEN c.event = 'loads'         THEN c.value END) AS loads,
    MAX(CASE WHEN c.event = 'mem_stall'     THEN c.value END) AS mem_stall,
    MAX(CASE WHEN c.event = 'task_clock'    THEN c.value END) AS task_clock,
    ROUND(MAX(CASE WHEN c.event = 'instructions' THEN c.value END) /
          NULLIF(MAX(CASE WHEN c.event = 'cycles' THEN c.value END), 0), 3)
        AS ipc_recomputed,
    ROUND(MAX(CASE WHEN c.event = 'ipc' THEN c.value END), 3) AS ipc_reported
FROM v_runs r
JOIN v_counters c ON c.run_id = r.run_id
GROUP BY r.run_id;
