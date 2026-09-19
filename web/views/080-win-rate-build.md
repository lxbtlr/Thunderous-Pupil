# win rate / build
tab: table

```sql
-- Grouped by (binary, machine) since 0019: pooling an ARM result with a
-- Xeon one was the bug that view fixed.
SELECT * FROM v_win_rate_by_build ORDER BY node, config_name
```
