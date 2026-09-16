-- Comparison views.
--
-- Replaces the placeholder engine_pair from 0005 with one that carries
-- dispersion, so "who won" is answered against each cell's own noise rather
-- than a threshold someone guessed.
--
-- PORTABILITY: uses NO math functions. LN, EXP, POW, SQRT, LOG all live in
-- SQLite's optional SQLITE_ENABLE_MATH_FUNCTIONS module and are absent from
-- many builds, including the default sql.js WASM build that the static web
-- page loads. Only core scalars, aggregates and window functions (3.25+)
-- appear below, so these views behave identically in the CLI, in Python, and
-- in a browser.

DROP VIEW IF EXISTS engine_pair;

CREATE VIEW engine_pair AS
WITH base AS (
    SELECT
        h.task_id, h.build_event_id, h.snapshot_id, h.trial,
        be.binary_id,
        bs.spec_id, bs.config_name, bs.cmake_defs,
        substr(hex(bs.repo_sha), 1, 8) AS head,
        d.dataset_id, d.sf_label, d.scale_factor,
        q.query_id, q.label AS query, t.threads,
        m.stable_key AS node,
        h.run_id AS h_run_id,  v.run_id AS v_run_id,
        h.median_ns AS h_median_ns, v.median_ns AS v_median_ns,
        h.min_ns    AS h_min_ns,    v.min_ns    AS v_min_ns,
        COALESCE(h.reps, 1) AS h_reps, COALESCE(v.reps, 1) AS v_reps,
        h.stddev_ns / NULLIF(h.mean_ns, 0) AS h_cv,
        v.stddev_ns / NULLIF(v.mean_ns, 0) AS v_cv
    FROM run h
    JOIN run v
      ON  v.task_id        = h.task_id
      AND v.build_event_id = h.build_event_id
      AND v.snapshot_id    = h.snapshot_id
      AND v.trial          = h.trial
    JOIN engine eh ON eh.engine_id = h.engine_id AND eh.code = 'h'
    JOIN engine ev ON ev.engine_id = v.engine_id AND ev.code = 'v'
    JOIN task t              ON t.task_id = h.task_id
    JOIN query q             ON q.query_id = t.query_id
    JOIN dataset d           ON d.dataset_id = t.dataset_id
    JOIN build_event be      ON be.build_event_id = h.build_event_id
    JOIN build_spec bs       ON bs.spec_id = be.spec_id
    JOIN machine_snapshot ms ON ms.snapshot_id = h.snapshot_id
    JOIN machine m           ON m.machine_id = ms.machine_id
    WHERE h.quality = 'clean' AND v.quality = 'clean'
      AND h.median_ns > 0 AND v.median_ns > 0
),
derived AS (
    SELECT *,
           h_median_ns / v_median_ns AS h_over_v,
           -- Symmetric relative difference, standing in for ln(h/v). Both are
           -- sign-symmetric under swapping the engines and both are ~0 when
           -- the two agree; this one needs no logarithm. They differ only for
           -- large gaps, where you would be reading the ratio anyway.
           (h_median_ns - v_median_ns) / ((h_median_ns + v_median_ns) / 2.0)
                                     AS rel_diff,
           CASE WHEN h_min_ns > 0 AND v_min_ns > 0
                THEN h_min_ns / v_min_ns END AS h_over_v_min,
           -- Mean of the two coefficients of variation. RMS would need SQRT;
           -- for two similar values the difference is under 3%, which is far
           -- below the precision this threshold deserves.
           (COALESCE(h_cv, 0) + COALESCE(v_cv, 0)) / 2.0 AS pooled_cv
    FROM base
)
SELECT *,
       rel_diff / NULLIF(pooled_cv, 0) AS z,
       CASE
           WHEN pooled_cv IS NULL OR pooled_cv = 0 THEN
                CASE WHEN h_over_v < 1 THEN 'h' ELSE 'v' END
           WHEN ABS(rel_diff / pooled_cv) < 2.0 THEN 'tie'
           WHEN rel_diff < 0 THEN 'h'
           ELSE 'v'
       END AS winner
FROM derived;


-- Median of a ratio, per binary. The median is the right central estimate for
-- ratios and needs no logarithm: because the median commutes with monotone
-- transforms, median(h/v) is exactly exp(median(ln(h/v))). It is also robust
-- to the one wild cell that a geometric mean would still feel.
--
-- The arithmetic mean of ratios is what to avoid: a 2x win and a 2x loss
-- average to 1.25, implying v is ahead when they exactly cancel.
CREATE VIEW v_ratio_median AS
WITH ranked AS (
    SELECT binary_id, h_over_v,
           ROW_NUMBER() OVER (PARTITION BY binary_id ORDER BY h_over_v) AS rn,
           COUNT(*)    OVER (PARTITION BY binary_id)                    AS cnt
    FROM engine_pair
)
SELECT binary_id, AVG(h_over_v) AS median_ratio, MAX(cnt) AS cells
FROM ranked
WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)   -- integer division: handles both parities
GROUP BY binary_id;


-- Win rate per build. Grouped on binary_id, not build_event_id: two build
-- events producing identical bits are one competitor, and separating them
-- splits a config's evidence for no reason. Group by build_event_id only when
-- asking whether two builds of one recipe disagree -- that is
-- spec_reproducibility's job.
CREATE VIEW v_win_rate_by_build AS
SELECT
    ep.config_name, ep.head, ep.binary_id,
    COUNT(*)                                          AS cells,
    SUM(ep.winner = 'h')                              AS h_wins,
    SUM(ep.winner = 'v')                              AS v_wins,
    SUM(ep.winner = 'tie')                            AS ties,
    ROUND(100.0 * SUM(ep.winner = 'h')   / COUNT(*), 1) AS h_win_pct,
    ROUND(100.0 * SUM(ep.winner = 'tie') / COUNT(*), 1) AS tie_pct,
    ROUND(rm.median_ratio, 3)                         AS median_ratio,
    ROUND(AVG(ep.pooled_cv), 4)                       AS mean_cv,
    COUNT(DISTINCT ep.query_id)                       AS queries,
    COUNT(DISTINCT ep.dataset_id)                     AS scale_factors,
    COUNT(DISTINCT ep.threads)                        AS thread_counts
FROM engine_pair ep
LEFT JOIN v_ratio_median rm ON rm.binary_id = ep.binary_id
GROUP BY ep.binary_id;


-- Sampling imbalance. Read BEFORE any cross-build comparison: a build missing
-- an entire scale factor is not comparable to one that has it, because the
-- crossover moves with data size. The win-rate difference would reflect the
-- sampling, not the config.
CREATE VIEW v_build_balance AS
SELECT config_name, binary_id, sf_label, scale_factor,
       COUNT(*)                 AS pairs,
       COUNT(DISTINCT query_id) AS queries,
       COUNT(DISTINCT threads)  AS thread_counts
FROM engine_pair
GROUP BY binary_id, dataset_id;


-- Win rate on a balanced panel: only (query, dataset, threads) cells that
-- every binary has, so builds face identical workload mixes.
--
-- Compare cells_used against cells_total. If a build collapses from 400 cells
-- to 30, the panel is too thin to conclude anything -- which is itself the
-- finding, and better than a confident wrong number.
CREATE VIEW v_win_rate_balanced AS
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
    SELECT binary_id, COUNT(*) AS cells_total FROM engine_pair GROUP BY binary_id
)
SELECT
    ep.config_name, ep.head, ep.binary_id,
    COUNT(*)              AS cells_used,
    tt.cells_total,
    SUM(ep.winner = 'h')   AS h_wins,
    SUM(ep.winner = 'v')   AS v_wins,
    SUM(ep.winner = 'tie') AS ties,
    ROUND(100.0 * SUM(ep.winner = 'h') / COUNT(*), 1) AS h_win_pct,
    ROUND(AVG(ep.rel_diff), 4) AS mean_rel_diff
FROM engine_pair ep
JOIN common USING (query_id, dataset_id, threads)
JOIN totals tt ON tt.binary_id = ep.binary_id
GROUP BY ep.binary_id;


-- Where each build's crossover sits. This is the shape the eventual model has
-- to predict, so it is worth looking at directly rather than only aggregated.
CREATE VIEW v_win_rate_by_sf AS
SELECT config_name, binary_id, sf_label, scale_factor, query, threads,
       COUNT(*)               AS cells,
       SUM(winner = 'h')      AS h_wins,
       SUM(winner = 'v')      AS v_wins,
       SUM(winner = 'tie')    AS ties,
       ROUND(AVG(h_over_v), 3) AS mean_ratio,
       ROUND(AVG(rel_diff), 4) AS mean_rel_diff
FROM engine_pair
GROUP BY binary_id, dataset_id, query_id, threads;
