# h vs v
tab: table

```sql
-- z is the effect size in units of each cell's own noise.
-- |z| < 2 means the difference is not resolvable at this precision.
SELECT node, config_name, sf_label, query, threads,
       ROUND(h_median_ns/1e6, 3) AS h_ms,
       ROUND(v_median_ns/1e6, 3) AS v_ms,
       ROUND(h_over_v, 3)  AS h_over_v,
       ROUND(rel_diff, 4)  AS rel_diff,
       ROUND(pooled_cv, 4) AS pooled_cv,
       ROUND(z, 2)         AS z,
       winner
FROM engine_pair
ORDER BY node, query, scale_factor, threads
```
