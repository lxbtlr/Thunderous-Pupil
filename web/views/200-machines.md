# machines
tab: table

```sql
SELECT m.stable_key AS node, m.partition, ms.snapshot_id,
       ms.cpu_vendor, ms.cpu_model, ms.cores_physical, ms.threads_logical,
       ms.numa_nodes, ms.l3_bytes, ms.kernel_version, ms.observed_from
FROM machine_snapshot ms
JOIN machine m ON m.machine_id = ms.machine_id
ORDER BY node, ms.observed_from DESC
```
