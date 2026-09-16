-- Win rate at (build x query) grain, wide and long.
--
-- CAVEAT worth keeping in view: aggregating across scale factors and thread
-- counts within a query re-introduces the imbalance problem at finer grain. If
-- one build has more sf100 cells for q9 than another does, its q9 win rate
-- shifts for reasons that are about sampling, not about the config. The
-- scale_factors and thread_counts columns are there so that is visible in the
-- same row rather than needing a separate lookup.
--
-- No math functions (see 0008).

-- Median ratio per (binary, query). Median rather than geometric mean: it
-- commutes with monotone transforms, so median(h/v) is exactly what
-- exp(median(ln(h/v))) would give, with no logarithm, and it shrugs off the
-- one wild cell a geometric mean would still feel.
CREATE VIEW v_ratio_median_by_query AS
WITH ranked AS (
    SELECT binary_id, query_id, h_over_v,
           ROW_NUMBER() OVER (PARTITION BY binary_id, query_id
                              ORDER BY h_over_v) AS rn,
           COUNT(*)    OVER (PARTITION BY binary_id, query_id) AS cnt
    FROM engine_pair
)
SELECT binary_id, query_id,
       AVG(h_over_v) AS median_ratio,
       MAX(cnt)      AS cells
FROM ranked
WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
GROUP BY binary_id, query_id;


-- WIDE: one row per (build, query). Both engines side by side.
CREATE VIEW v_win_rate_by_build_query AS
SELECT
    ep.config_name,
    ep.head,
    ep.binary_id,
    ep.query,
    q.q_number,
    COUNT(*)                                            AS cells,
    SUM(ep.winner = 'h')                                AS h_wins,
    SUM(ep.winner = 'v')                                AS v_wins,
    SUM(ep.winner = 'tie')                              AS ties,
    ROUND(100.0 * SUM(ep.winner = 'h')   / COUNT(*), 1) AS h_win_pct,
    ROUND(100.0 * SUM(ep.winner = 'v')   / COUNT(*), 1) AS v_win_pct,
    ROUND(100.0 * SUM(ep.winner = 'tie') / COUNT(*), 1) AS tie_pct,
    ROUND(rm.median_ratio, 3)                           AS median_ratio,
    ROUND(AVG(ep.rel_diff), 4)                          AS mean_rel_diff,
    ROUND(AVG(ep.pooled_cv), 4)                         AS mean_cv,
    -- Imbalance, in the same row as the number it would distort.
    COUNT(DISTINCT ep.dataset_id)                       AS scale_factors,
    COUNT(DISTINCT ep.threads)                          AS thread_counts
FROM engine_pair ep
JOIN query q ON q.query_id = ep.query_id
LEFT JOIN v_ratio_median_by_query rm
       ON rm.binary_id = ep.binary_id AND rm.query_id = ep.query_id
GROUP BY ep.binary_id, ep.query_id
ORDER BY ep.config_name, q.q_number;


-- LONG: one row per (build, query, engine). Ties are reported on both rows,
-- so wins + ties will not sum to cells across the pair -- that is intended;
-- a tie is a property of the cell, not of either engine.
--
-- This is the shape to plot from, and the shape a classification target takes.
CREATE VIEW v_win_rate_long AS
SELECT ep.config_name, ep.head, ep.binary_id, ep.query, q.q_number,
       'h' AS engine, e.paradigm,
       COUNT(*)             AS cells,
       SUM(ep.winner = 'h') AS wins,
       SUM(ep.winner = 'tie') AS ties,
       ROUND(100.0 * SUM(ep.winner = 'h') / COUNT(*), 1) AS win_pct,
       ROUND(AVG(ep.pooled_cv), 4) AS mean_cv,
       COUNT(DISTINCT ep.dataset_id) AS scale_factors,
       COUNT(DISTINCT ep.threads)    AS thread_counts
FROM engine_pair ep
JOIN query q  ON q.query_id = ep.query_id
JOIN engine e ON e.code = 'h'
GROUP BY ep.binary_id, ep.query_id

UNION ALL

SELECT ep.config_name, ep.head, ep.binary_id, ep.query, q.q_number,
       'v' AS engine, e.paradigm,
       COUNT(*)             AS cells,
       SUM(ep.winner = 'v') AS wins,
       SUM(ep.winner = 'tie') AS ties,
       ROUND(100.0 * SUM(ep.winner = 'v') / COUNT(*), 1) AS win_pct,
       ROUND(AVG(ep.pooled_cv), 4) AS mean_cv,
       COUNT(DISTINCT ep.dataset_id) AS scale_factors,
       COUNT(DISTINCT ep.threads)    AS thread_counts
FROM engine_pair ep
JOIN query q  ON q.query_id = ep.query_id
JOIN engine e ON e.code = 'v'
GROUP BY ep.binary_id, ep.query_id;


-- Balanced version at (build x query) grain: only cells every build has.
-- Use this when comparing the SAME query ACROSS builds, where uneven sampling
-- is the thing most likely to fool you.
CREATE VIEW v_win_rate_by_build_query_balanced AS
WITH n_builds AS (
    SELECT COUNT(DISTINCT binary_id) AS n FROM engine_pair
),
common AS (
    SELECT query_id, dataset_id, threads
    FROM engine_pair
    GROUP BY query_id, dataset_id, threads
    HAVING COUNT(DISTINCT binary_id) = (SELECT n FROM n_builds)
),
totals AS (
    SELECT binary_id, query_id, COUNT(*) AS cells_total
    FROM engine_pair GROUP BY binary_id, query_id
)
SELECT ep.config_name, ep.head, ep.binary_id, ep.query, q.q_number,
       COUNT(*)      AS cells_used,
       tt.cells_total,
       SUM(ep.winner = 'h')   AS h_wins,
       SUM(ep.winner = 'v')   AS v_wins,
       SUM(ep.winner = 'tie') AS ties,
       ROUND(100.0 * SUM(ep.winner = 'h') / COUNT(*), 1) AS h_win_pct,
       ROUND(AVG(ep.rel_diff), 4) AS mean_rel_diff
FROM engine_pair ep
JOIN query q ON q.query_id = ep.query_id
JOIN common USING (query_id, dataset_id, threads)
JOIN totals tt ON tt.binary_id = ep.binary_id AND tt.query_id = ep.query_id
GROUP BY ep.binary_id, ep.query_id
ORDER BY ep.config_name, q.q_number;
