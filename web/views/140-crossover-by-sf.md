# crossover by sf
tab: table

```sql
-- The shape the model has to predict, seen directly.
SELECT * FROM v_win_rate_by_sf
ORDER BY node, config_name, scale_factor, query, threads
```
