-- Machines and their configurations, plus raw system-info captures.

CREATE TABLE machine (
    machine_id   INTEGER PRIMARY KEY,
    stable_key   TEXT NOT NULL UNIQUE,   -- slurm node name: 'dubliner'
    partition    TEXT,                   -- 'cheese'
    label        TEXT,
    first_seen   TEXT NOT NULL           -- ISO-8601 UTC
) STRICT;

CREATE TABLE machine_snapshot (
    snapshot_id       INTEGER PRIMARY KEY,
    machine_id        INTEGER NOT NULL REFERENCES machine,
    fingerprint       BLOB NOT NULL,     -- sha256 over the descriptive fields below

    cpu_vendor        TEXT,
    cpu_model         TEXT,
    microarch         TEXT,
    cpu_sockets       INTEGER,
    cores_physical    INTEGER,
    threads_logical   INTEGER,
    base_mhz          INTEGER,
    max_mhz           INTEGER,
    l1d_bytes         INTEGER,
    l2_bytes          INTEGER,
    l3_bytes          INTEGER,
    numa_nodes        INTEGER,
    ram_bytes         INTEGER,
    simd_flags        TEXT,              -- JSON array, subset of interest
    max_simd_bits     INTEGER,
    os_name           TEXT,
    kernel_version    TEXT,
    libc_version      TEXT,
    smt_enabled       INTEGER,           -- 0/1
    cpu_governor      TEXT,
    thp_state         TEXT,              -- transparent_hugepage/enabled
    observed_from     TEXT NOT NULL,
    observed_to       TEXT,
    UNIQUE (machine_id, fingerprint)
) STRICT;

CREATE INDEX ix_snapshot_machine ON machine_snapshot (machine_id, observed_from DESC);

-- Verbatim tool output. Parsers are wrong at least once; re-parsing a stored
-- blob is free, re-visiting a reconfigured machine is not.
CREATE TABLE spec_capture (
    capture_id   INTEGER PRIMARY KEY,
    snapshot_id  INTEGER NOT NULL REFERENCES machine_snapshot,
    tool         TEXT NOT NULL,          -- 'lscpu','lstopo','numactl','proc_cpuinfo',
                                         -- 'sysfs_cache','meminfo','dmidecode'
    tool_args    TEXT,
    exit_code    INTEGER,
    raw_text     TEXT,
    raw_sha256   BLOB,
    captured_at  TEXT NOT NULL,
    UNIQUE (snapshot_id, tool, raw_sha256)
) STRICT;

CREATE TABLE spec_fact (
    capture_id     INTEGER NOT NULL REFERENCES spec_capture ON DELETE CASCADE,
    key            TEXT NOT NULL,        -- 'cpu.model_name', 'cache.l3.bytes'
    value_text     TEXT,
    value_num      REAL,
    -- 'trusted' | 'virtualized' | 'unavailable' | 'contradicted'
    trust          TEXT NOT NULL DEFAULT 'trusted',
    parser_version TEXT NOT NULL,
    PRIMARY KEY (capture_id, key, parser_version)
) STRICT;
