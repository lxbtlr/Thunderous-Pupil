# orphan cells
tab: table

```sql
-- Cells measured for fewer than two engines: worth nothing for comparison.
-- Expect rows mid-campaign; only meaningful once a batch finishes.
SELECT m.stable_key AS node, bs.config_name, d.sf_label, q.label AS query,
       t.threads, GROUP_CONCAT(e.code) AS engines_present, COUNT(*) AS n
FROM run r
JOIN task t              ON t.task_id = r.task_id
JOIN query q             ON q.query_id = t.query_id
JOIN dataset d           ON d.dataset_id = t.dataset_id
JOIN engine e            ON e.engine_id = r.engine_id
JOIN build_event be      ON be.build_event_id = r.build_event_id
JOIN build_spec bs       ON bs.spec_id = be.spec_id
JOIN machine_snapshot ms ON ms.snapshot_id = r.snapshot_id
JOIN machine m           ON m.machine_id = ms.machine_id
WHERE r.quality = 'clean'
GROUP BY r.task_id, r.build_event_id, r.snapshot_id, r.trial
HAVING COUNT(DISTINCT r.engine_id) < 2
```
