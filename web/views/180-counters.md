# counters
tab: table

```sql
-- Raw counters, one row per run. Within a single vendor only: ARM's nearest
-- LLC-miss event does not count what Intel's counts. Use the
-- 'counters cross-vendor' view when spanning burrata and an x86 node.
SELECT * FROM v_run_counters_wide
ORDER BY config_name, sf_label, query, threads
```
