# coverage
tab: table

```sql
SELECT m.stable_key AS node, bs.config_name, d.sf_label,
       COUNT(DISTINCT t.query_id) AS queries,
       COUNT(DISTINCT t.threads)  AS thread_counts,
       COUNT(DISTINCT r.engine_id) AS engines,
       COUNT(*) AS runs,
       MAX(ib.ingested_at) AS last_ingest
FROM run r
JOIN task t              ON t.task_id = r.task_id
JOIN dataset d           ON d.dataset_id = t.dataset_id
JOIN ingest_batch ib     ON ib.batch_id = r.batch_id
JOIN build_event be      ON be.build_event_id = r.build_event_id
JOIN build_spec bs       ON bs.spec_id = be.spec_id
JOIN machine_snapshot ms ON ms.snapshot_id = r.snapshot_id
JOIN machine m           ON m.machine_id = ms.machine_id
GROUP BY m.machine_id, bs.config_name, d.dataset_id
ORDER BY node, config_name, d.scale_factor
```
