-- What is being run, engine-independent.

-- A concrete TPC-H directory, identified by a manifest hash rather than by
-- path. /tank/alexb/swole/tpch/sf10 is a location, not an identity.
CREATE TABLE dataset (
    dataset_id     INTEGER PRIMARY KEY,
    benchmark      TEXT NOT NULL DEFAULT 'tpch',
    sf_label       TEXT NOT NULL,        -- 'sf10', 'sf001'
    scale_factor   REAL NOT NULL,
    data_dir       TEXT NOT NULL,        -- last known path, informational only
    manifest_sha256 BLOB NOT NULL UNIQUE, -- over sorted (name, size, mtime)
    file_count     INTEGER,
    total_bytes    INTEGER,
    manifest_json  TEXT NOT NULL,        -- full listing, so drift is diffable
    registered_at  TEXT NOT NULL,
    CHECK (json_valid(manifest_json))
) STRICT;

CREATE TABLE query (
    query_id   INTEGER PRIMARY KEY,
    benchmark  TEXT NOT NULL DEFAULT 'tpch',
    q_number   INTEGER NOT NULL,         -- 1,3,5,6,9,18
    label      TEXT NOT NULL,            -- 'q1'
    UNIQUE (benchmark, q_number)
) STRICT;

-- The comparable unit: everything held constant while the engine varies.
CREATE TABLE task (
    task_id      INTEGER PRIMARY KEY,
    query_id     INTEGER NOT NULL REFERENCES query,
    dataset_id   INTEGER NOT NULL REFERENCES dataset,
    threads      INTEGER NOT NULL,
    vector_size  INTEGER,                -- run_tpch -v; NULL if unspecified
    task_hash    BLOB NOT NULL UNIQUE,
    UNIQUE (query_id, dataset_id, threads, vector_size)
) STRICT;

CREATE INDEX ix_task_query ON task (query_id, dataset_id);

CREATE TABLE engine (
    engine_id  INTEGER PRIMARY KEY,
    code       TEXT NOT NULL UNIQUE,     -- 'h' | 'v'
    name       TEXT NOT NULL,
    paradigm   TEXT NOT NULL             -- 'compiled' | 'vectorized'
) STRICT;
