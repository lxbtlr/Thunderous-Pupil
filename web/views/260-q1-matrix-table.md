# q1 matrix: cells

One row per (compiler, crc, pos, grp, machine) cell of the query-1 build
matrix, with the config_name factors parsed out. Sort by rel_to_best to rank
configs within a machine, or by coverage to find cells that never ran. A full
matrix is 132 rows; fewer means missing builds or missing runs.

```sql
-- Same parser as the q1 heatmap, without the normalisation, plus a
-- coverage column so gaps in the 132-cell matrix are visible rather than
-- silently absent.
WITH q1 AS (
    SELECT *
    FROM v_runs
    WHERE q_number = 1
      AND config_name LIKE '%\_crc%' ESCAPE '\'
      AND config_name LIKE '%\_grp%' ESCAPE '\'
),
split_head AS (
    SELECT q1.*,
           substr(config_name, 1, instr(config_name, '_crc') - 1) AS compiler,
           substr(config_name, instr(config_name, '_crc') + 4, 1) AS crc,
           substr(config_name, instr(config_name, '_pos') + 4, 1) AS pos,
           substr(config_name, instr(config_name, '_grp') + 4)    AS grp_tail
    FROM q1
),
split_tail AS (
    SELECT split_head.*,
           substr(grp_tail, 1, instr(grp_tail, '_') - 1) AS grp,
           substr(grp_tail, instr(grp_tail, '_') + 1)    AS built_for
    FROM split_head
),
cell AS (
    SELECT node,
           built_for,
           compiler,
           crc,
           pos,
           grp,
           engine,
           sf_label,
           threads,
           config_name,
           ROUND(AVG(CASE WHEN quality = 'clean' THEN median_ms END), 3) AS median_ms,
           ROUND(MIN(CASE WHEN quality = 'clean' THEN min_ms   END), 3) AS min_ms,
           ROUND(AVG(CASE WHEN quality = 'clean' THEN cv       END), 4) AS cv,
           SUM(quality = 'clean')                       AS clean_runs,
           SUM(quality <> 'clean')                      AS dirty_runs,
           COUNT(DISTINCT build_event_id)               AS n_builds,
           COUNT(DISTINCT binary_id)                    AS n_binaries,
           MAX(head)                                    AS head
    FROM split_tail
    GROUP BY node, built_for, compiler, crc, pos, grp, engine, sf_label,
             threads, config_name
)
SELECT *,
       ROUND(median_ms / MIN(median_ms) OVER (
                 PARTITION BY node, engine, sf_label, threads), 3) AS rel_to_best,
       CASE WHEN clean_runs = 0            THEN 'no clean runs'
            WHEN built_for <> node         THEN 'ran on wrong node'
            WHEN n_binaries > 1            THEN 'config built >1 binary'
            ELSE 'ok' END                                          AS flag
FROM cell
ORDER BY node, rel_to_best
```
