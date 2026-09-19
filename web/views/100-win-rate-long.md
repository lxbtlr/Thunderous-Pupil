# win rate long
tab: table

```sql
-- One row per (build, machine, query, engine). Ties appear on BOTH engine
-- rows, so wins+ties will not sum to cells across the pair -- a tie belongs
-- to the cell, not to either engine.
SELECT * FROM v_win_rate_long ORDER BY node, config_name, q_number, engine
```
