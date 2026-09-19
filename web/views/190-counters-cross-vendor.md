# counters cross-vendor
tab: table

```sql
-- Only counters that mean the same thing on ARM and x86.
SELECT r.node, r.config_name, r.sf_label, r.query, r.engine, r.threads,
       r.median_ms,
       MAX(CASE WHEN c.event='cycles'       THEN c.value END) AS cycles,
       MAX(CASE WHEN c.event='instructions' THEN c.value END) AS instructions,
       MAX(CASE WHEN c.event='task_clock'   THEN c.value END) AS task_clock,
       ROUND(MAX(CASE WHEN c.event='instructions' THEN c.value END) /
             NULLIF(MAX(CASE WHEN c.event='cycles' THEN c.value END),0), 3) AS ipc
FROM v_runs r
JOIN v_counters_comparable c ON c.run_id = r.run_id
GROUP BY r.run_id
ORDER BY r.node, r.query, r.threads
```
