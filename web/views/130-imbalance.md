# imbalance
tab: table

```sql
-- Read BEFORE comparing builds. A build missing a scale factor is not
-- comparable to one that has it; the crossover moves with data size.
SELECT * FROM v_build_balance ORDER BY node, config_name, scale_factor
```
