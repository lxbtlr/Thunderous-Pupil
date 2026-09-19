# noisy
tab: table

```sql
-- This sets your tie threshold. If typical cv is 0.005 the |z|<2 band is
-- about 1%; at 0.03 it is 6%. It differs by machine.
SELECT node, config_name, sf_label, query, engine, threads, cv, median_ms
FROM v_runs
WHERE cv IS NOT NULL AND quality = 'clean' AND cv > 0.02
ORDER BY cv DESC LIMIT 200
```
