-- 0012_run_environment.sql
-- Tier-2 ambient state: a before/after snapshot of the machine's runtime
-- environment around each job. One observation per phase per ingest batch
-- (a batch == one slurm job == one .out file). The before/after DELTA is the
-- signal: a run that started clean and ended dirty is a different story from
-- one that was dirty throughout.
--
-- Captured by scripts/capture_env.sh into <out>.env-before / <out>.env-after
-- and ingested alongside the runs. Linked to the machine snapshot the run was
-- measured under, so ambient state and machine identity travel together.

CREATE TABLE environment_observation (
    env_obs_id   INTEGER PRIMARY KEY,
    batch_id     INTEGER NOT NULL REFERENCES ingest_batch(batch_id),
    snapshot_id  INTEGER NOT NULL REFERENCES machine_snapshot(snapshot_id),
    phase        TEXT NOT NULL CHECK (phase IN ('before', 'after')),
    captured_at  TEXT NOT NULL,
    raw_sha256   BLOB,                        -- sha256 of the <out>.env-<phase> sidecar
    UNIQUE (batch_id, phase)
) STRICT;

CREATE INDEX ix_env_obs_snap ON environment_observation (snapshot_id);

CREATE TABLE environment_fact (
    env_obs_id  INTEGER NOT NULL REFERENCES environment_observation(env_obs_id),
    key         TEXT NOT NULL,
    value_text  TEXT,
    value_num   REAL,                          -- numeric form, NULL if not numeric
    PRIMARY KEY (env_obs_id, key)
) STRICT;

CREATE INDEX ix_env_fact_key ON environment_fact (key);

-- Convenience: the before/after delta for every numeric fact, per batch.
-- delta_pct = (after - before) / before * 100; NULL where before is 0/NA.
CREATE VIEW v_env_delta AS
WITH b AS (SELECT * FROM environment_fact WHERE env_obs_id IN
             (SELECT env_obs_id FROM environment_observation WHERE phase='before')),
     a AS (SELECT * FROM environment_fact WHERE env_obs_id IN
             (SELECT env_obs_id FROM environment_observation WHERE phase='after'))
SELECT a.key,
       a.env_obs_id AS after_obs_id,
       b.value_num  AS before_num,
       a.value_num  AS after_num,
       ROUND(100.0 * (a.value_num - b.value_num) / NULLIF(b.value_num, 0), 3) AS delta_pct,
       a.value_text AS after_text
FROM a JOIN b USING (key)
WHERE a.value_num IS NOT NULL AND b.value_num IS NOT NULL;
