# balanced panel
tab: table

```sql
-- Only cells every build has, computed WITHIN a machine. If cells_used
-- collapses against cells_total, the panel is too thin to conclude anything
-- -- which is itself the finding.
SELECT * FROM v_win_rate_balanced ORDER BY node, config_name
```
