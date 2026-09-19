# builds
tab: table

```sql
SELECT be.build_event_id, bs.config_name,
       substr(hex(bs.repo_sha),1,8) AS head, bs.repo_dirty, bs.cmake_defs,
       substr(hex(b.content_sha256),1,12) AS binary_sha, be.built_at
FROM build_event be
JOIN build_spec bs ON bs.spec_id = be.spec_id
JOIN binary b      ON b.binary_id = be.binary_id
ORDER BY be.built_at DESC
```
