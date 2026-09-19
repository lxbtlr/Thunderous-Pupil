# engine duel (incl. b)
tab: table

```sql
-- All unordered engine pairs, including 'b' (q6 branching), which
-- engine_pair cannot see. 'winner' names an engine code.
SELECT node, cpu_vendor, config_name, pair, query, sf_label, threads,
       ROUND(a_median_ns/1e6, 3) AS a_ms,
       ROUND(b_median_ns/1e6, 3) AS b_ms,
       ROUND(a_over_b, 3) AS a_over_b,
       ROUND(z, 2) AS z, winner
FROM engine_duel
ORDER BY node, query, pair, threads
```
