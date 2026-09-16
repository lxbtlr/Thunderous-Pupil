-- Multi-engine and multi-machine corrections.
--
-- Three things that were correct with one engine pair on one node, and stopped
-- being correct once 0018 added engine 'b' and burrata/manchego joined dubliner.
--
--   1. engine_pair hardcodes h vs v, so every 'b' run (q6 branching) is
--      ingested and then invisible. q6 win rates silently describe two of the
--      three engines measured.
--   2. every win-rate view groups by binary_id alone, pooling results across
--      machines. An ARM Neoverse-N1 result and a Xeon result land in the same
--      average, which is precisely the comparison that must not be pooled.
--   3. nothing records that a counter means different things on different
--      vendors. v4_burrata supplies 10 counters against v2's 14, and the ones
--      it shares do not measure the same events.
--
-- engine_pair itself is left alone: h vs v is the headline comparison and
-- eight views depend on its column names. The generic case gets a new view.
--
-- No math functions (see 0008), so everything here also runs under sql.js.

-- ---------------------------------------------------------------- 1. engines

-- Every unordered engine pair on the same cell, not just h/v. Column names are
-- a_*/b_* rather than h_*/v_*; ratio is a_median/b_median, so 'winner' names an
-- engine code rather than assuming which side is which.
CREATE VIEW engine_duel AS
WITH base AS (
    SELECT
        a.task_id, a.build_event_id, a.snapshot_id, a.trial,
        be.binary_id, bs.config_name,
        substr(hex(bs.repo_sha), 1, 8) AS head,
        d.dataset_id, d.sf_label, d.scale_factor,
        q.query_id, q.label AS query, t.threads,
        m.machine_id, m.stable_key AS node, ms.cpu_vendor,
        ea.code AS a_code, eb.code AS b_code,
        ea.paradigm AS a_paradigm, eb.paradigm AS b_paradigm,
        a.run_id AS a_run_id, b.run_id AS b_run_id,
        a.median_ns AS a_median_ns, b.median_ns AS b_median_ns,
        a.min_ns AS a_min_ns, b.min_ns AS b_min_ns,
        a.stddev_ns / NULLIF(a.mean_ns, 0) AS a_cv,
        b.stddev_ns / NULLIF(b.mean_ns, 0) AS b_cv
    FROM run a
    JOIN run b
      ON  b.task_id        = a.task_id
      AND b.build_event_id = a.build_event_id
      AND b.snapshot_id    = a.snapshot_id
      AND b.trial          = a.trial
      AND b.engine_id      > a.engine_id      -- one row per unordered pair
    JOIN engine ea ON ea.engine_id = a.engine_id
    JOIN engine eb ON eb.engine_id = b.engine_id
    JOIN task t              ON t.task_id = a.task_id
    JOIN query q             ON q.query_id = t.query_id
    JOIN dataset d           ON d.dataset_id = t.dataset_id
    JOIN build_event be      ON be.build_event_id = a.build_event_id
    JOIN build_spec bs       ON bs.spec_id = be.spec_id
    JOIN machine_snapshot ms ON ms.snapshot_id = a.snapshot_id
    JOIN machine m           ON m.machine_id = ms.machine_id
    WHERE a.quality = 'clean' AND b.quality = 'clean'
      AND a.median_ns > 0 AND b.median_ns > 0
),
derived AS (
    SELECT *,
           a_code || ' vs ' || b_code AS pair,
           a_median_ns / b_median_ns  AS a_over_b,
           (a_median_ns - b_median_ns) / ((a_median_ns + b_median_ns) / 2.0)
                                      AS rel_diff,
           (COALESCE(a_cv, 0) + COALESCE(b_cv, 0)) / 2.0 AS pooled_cv
    FROM base
)
SELECT *,
       rel_diff / NULLIF(pooled_cv, 0) AS z,
       CASE
           WHEN pooled_cv IS NULL OR pooled_cv = 0 THEN
                CASE WHEN a_over_b < 1 THEN a_code ELSE b_code END
           WHEN ABS(rel_diff / pooled_cv) < 2.0 THEN 'tie'
           WHEN rel_diff < 0 THEN a_code
           ELSE b_code
       END AS winner
FROM derived;

-- Win rate for any engine pair, per build AND per machine.
CREATE VIEW v_duel_win_rate AS
SELECT config_name, head, binary_id, node, cpu_vendor, snapshot_id,
       pair, a_code, b_code, query,
       COUNT(*)                                        AS cells,
       SUM(winner = a_code)                            AS a_wins,
       SUM(winner = b_code)                            AS b_wins,
       SUM(winner = 'tie')                             AS ties,
       ROUND(100.0 * SUM(winner = a_code) / COUNT(*), 1) AS a_win_pct,
       ROUND(AVG(rel_diff), 4)                         AS mean_rel_diff,
       ROUND(AVG(pooled_cv), 4)                        AS mean_cv,
       COUNT(DISTINCT dataset_id)                      AS scale_factors,
       COUNT(DISTINCT threads)                         AS thread_counts
FROM engine_duel
GROUP BY binary_id, snapshot_id, a_code, b_code, query_id;

-- --------------------------------------------------------------- 2. machines

-- Supersede the win-rate views so they no longer pool across hardware.
-- Same columns as before plus node/cpu_vendor; grouping gains snapshot_id.

DROP VIEW IF EXISTS v_win_rate_by_build;
CREATE VIEW v_win_rate_by_build AS
SELECT
    ep.config_name, ep.head, ep.binary_id, ep.node, ms.cpu_vendor, ep.snapshot_id,
    COUNT(*)                                            AS cells,
    SUM(ep.winner = 'h')                                AS h_wins,
    SUM(ep.winner = 'v')                                AS v_wins,
    SUM(ep.winner = 'tie')                              AS ties,
    ROUND(100.0 * SUM(ep.winner = 'h')   / COUNT(*), 1) AS h_win_pct,
    ROUND(100.0 * SUM(ep.winner = 'tie') / COUNT(*), 1) AS tie_pct,
    ROUND(AVG(ep.rel_diff), 4)                          AS mean_rel_diff,
    ROUND(AVG(ep.pooled_cv), 4)                         AS mean_cv,
    COUNT(DISTINCT ep.query_id)                         AS queries,
    COUNT(DISTINCT ep.dataset_id)                       AS scale_factors,
    COUNT(DISTINCT ep.threads)                          AS thread_counts
FROM engine_pair ep
JOIN machine_snapshot ms ON ms.snapshot_id = ep.snapshot_id
GROUP BY ep.binary_id, ep.snapshot_id;

DROP VIEW IF EXISTS v_build_balance;
CREATE VIEW v_build_balance AS
SELECT config_name, binary_id, node, snapshot_id, sf_label, scale_factor,
       COUNT(*)                 AS pairs,
       COUNT(DISTINCT query_id) AS queries,
       COUNT(DISTINCT threads)  AS thread_counts
FROM engine_pair
GROUP BY binary_id, snapshot_id, dataset_id;

DROP VIEW IF EXISTS v_win_rate_by_build_query;
CREATE VIEW v_win_rate_by_build_query AS
SELECT
    ep.config_name, ep.head, ep.binary_id, ep.node, ep.snapshot_id,
    ep.query, q.q_number,
    COUNT(*)                                            AS cells,
    SUM(ep.winner = 'h')                                AS h_wins,
    SUM(ep.winner = 'v')                                AS v_wins,
    SUM(ep.winner = 'tie')                              AS ties,
    ROUND(100.0 * SUM(ep.winner = 'h')   / COUNT(*), 1) AS h_win_pct,
    ROUND(100.0 * SUM(ep.winner = 'v')   / COUNT(*), 1) AS v_win_pct,
    ROUND(100.0 * SUM(ep.winner = 'tie') / COUNT(*), 1) AS tie_pct,
    ROUND(AVG(ep.rel_diff), 4)                          AS mean_rel_diff,
    ROUND(AVG(ep.pooled_cv), 4)                         AS mean_cv,
    COUNT(DISTINCT ep.dataset_id)                       AS scale_factors,
    COUNT(DISTINCT ep.threads)                          AS thread_counts
FROM engine_pair ep
JOIN query q ON q.query_id = ep.query_id
GROUP BY ep.binary_id, ep.snapshot_id, ep.query_id
ORDER BY ep.node, ep.config_name, q.q_number;

DROP VIEW IF EXISTS v_win_rate_by_sf;
CREATE VIEW v_win_rate_by_sf AS
SELECT config_name, binary_id, node, snapshot_id,
       sf_label, scale_factor, query, threads,
       COUNT(*)                AS cells,
       SUM(winner = 'h')       AS h_wins,
       SUM(winner = 'v')       AS v_wins,
       SUM(winner = 'tie')     AS ties,
       ROUND(AVG(h_over_v), 3) AS mean_ratio,
       ROUND(AVG(rel_diff), 4) AS mean_rel_diff
FROM engine_pair
GROUP BY binary_id, snapshot_id, dataset_id, query_id, threads;

DROP VIEW IF EXISTS v_win_rate_long;
CREATE VIEW v_win_rate_long AS
SELECT ep.config_name, ep.head, ep.binary_id, ep.node, ep.snapshot_id,
       ep.query, q.q_number, 'h' AS engine, 'compiled' AS paradigm,
       COUNT(*) AS cells, SUM(ep.winner = 'h') AS wins,
       SUM(ep.winner = 'tie') AS ties,
       ROUND(100.0 * SUM(ep.winner = 'h') / COUNT(*), 1) AS win_pct,
       ROUND(AVG(ep.pooled_cv), 4) AS mean_cv,
       COUNT(DISTINCT ep.dataset_id) AS scale_factors,
       COUNT(DISTINCT ep.threads)    AS thread_counts
FROM engine_pair ep JOIN query q ON q.query_id = ep.query_id
GROUP BY ep.binary_id, ep.snapshot_id, ep.query_id
UNION ALL
SELECT ep.config_name, ep.head, ep.binary_id, ep.node, ep.snapshot_id,
       ep.query, q.q_number, 'v' AS engine, 'vectorized' AS paradigm,
       COUNT(*) AS cells, SUM(ep.winner = 'v') AS wins,
       SUM(ep.winner = 'tie') AS ties,
       ROUND(100.0 * SUM(ep.winner = 'v') / COUNT(*), 1) AS win_pct,
       ROUND(AVG(ep.pooled_cv), 4) AS mean_cv,
       COUNT(DISTINCT ep.dataset_id) AS scale_factors,
       COUNT(DISTINCT ep.threads)    AS thread_counts
FROM engine_pair ep JOIN query q ON q.query_id = ep.query_id
GROUP BY ep.binary_id, ep.snapshot_id, ep.query_id;

-- Balanced panels are now WITHIN a machine: cells that every binary has on
-- that node. Comparing configs across nodes was never the question, and with
-- three different microarchitectures it is not answerable this way.
DROP VIEW IF EXISTS v_win_rate_balanced;
CREATE VIEW v_win_rate_balanced AS
WITH n_builds AS (
    SELECT snapshot_id, COUNT(DISTINCT binary_id) AS n
    FROM engine_pair GROUP BY snapshot_id
),
common AS (
    SELECT ep.snapshot_id, ep.query_id, ep.dataset_id, ep.threads
    FROM engine_pair ep
    JOIN n_builds nb ON nb.snapshot_id = ep.snapshot_id
    GROUP BY ep.snapshot_id, ep.query_id, ep.dataset_id, ep.threads
    HAVING COUNT(DISTINCT ep.binary_id) = MAX(nb.n)
),
totals AS (
    SELECT binary_id, snapshot_id, COUNT(*) AS cells_total
    FROM engine_pair GROUP BY binary_id, snapshot_id
)
SELECT ep.config_name, ep.head, ep.binary_id, ep.node, ep.snapshot_id,
       COUNT(*) AS cells_used, tt.cells_total,
       SUM(ep.winner = 'h')   AS h_wins,
       SUM(ep.winner = 'v')   AS v_wins,
       SUM(ep.winner = 'tie') AS ties,
       ROUND(100.0 * SUM(ep.winner = 'h') / COUNT(*), 1) AS h_win_pct,
       ROUND(AVG(ep.rel_diff), 4) AS mean_rel_diff
FROM engine_pair ep
JOIN common USING (snapshot_id, query_id, dataset_id, threads)
JOIN totals tt ON tt.binary_id = ep.binary_id AND tt.snapshot_id = ep.snapshot_id
GROUP BY ep.binary_id, ep.snapshot_id;

-- --------------------------------------------------------------- 3. counters

-- A counter's name being the same on two vendors does not make the event the
-- same. Intel's LLC-misses and ARM Neoverse-N1's nearest equivalent count
-- different things; pooling them is a category error that no join will catch.
--
-- Comparable: cycles and instructions are architecturally defined, task-clock
-- is a software event, and IPC derives from the first two. Everything else is
-- microarchitectural and stays in-vendor.
ALTER TABLE pmu_event ADD COLUMN cross_vendor_comparable INTEGER NOT NULL DEFAULT 0;

UPDATE pmu_event SET cross_vendor_comparable = 1
WHERE canonical_name IN ('cycles', 'instructions', 'task_clock', 'ipc', 'ghz');

-- Counters safe to compare across vendors. Use this instead of v_counters
-- whenever a query spans burrata and an x86 node.
CREATE VIEW v_counters_comparable AS
SELECT rc.run_id, pe.canonical_name AS event, pe.unit, pe.kind, rc.value,
       ms.cpu_vendor
FROM run_counter rc
JOIN pmu_event pe        ON pe.event_id = rc.event_id
JOIN run r               ON r.run_id = rc.run_id
JOIN machine_snapshot ms ON ms.snapshot_id = r.snapshot_id
WHERE pe.cross_vendor_comparable = 1;

-- How many counter columns each header version should produce, so tooling
-- reads the expectation from the vocabulary instead of hardcoding it. The
-- real counts are v1=15, v2/v3/v4=14, v4_manchego=13, v4_burrata=10.
CREATE VIEW v_header_expectations AS
SELECT header_version,
       COUNT(*)                                  AS total_cols,
       SUM(role = 'counter')                     AS counter_cols,
       SUM(role = 'timing')                      AS timing_cols
FROM csv_column
GROUP BY header_version;

-- Which events a given header version cannot supply. Joining a query that
-- needs mem_stall against burrata runs returns NULL, silently; this names it.
CREATE VIEW v_header_event_coverage AS
SELECT hv.header_version, pe.canonical_name AS event,
       CASE WHEN cc.event_id IS NULL THEN 0 ELSE 1 END AS present
FROM (SELECT DISTINCT header_version FROM csv_column) hv
CROSS JOIN pmu_event pe
LEFT JOIN csv_column cc
       ON cc.header_version = hv.header_version
      AND cc.event_id = pe.event_id
      AND cc.role = 'counter'
WHERE pe.kind IN ('counter', 'derived');
