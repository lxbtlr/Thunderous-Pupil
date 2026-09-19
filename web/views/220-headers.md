# headers
tab: table

```sql
-- Counter columns each header layout supplies. burrata's PMU exposes fewer
-- events, so its .out is narrower than v4's.
SELECT * FROM v_header_expectations ORDER BY header_version
```
