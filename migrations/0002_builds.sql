-- Build provenance: recipe, artifact, and the act of turning one into the other.
-- Note: the engine (h/v) is NOT a build property here. One run_tpch binary runs
-- both engines, so engine lives on the run.

CREATE TABLE build_spec (
    spec_id          INTEGER PRIMARY KEY,
    repo_url         TEXT NOT NULL,
    repo_sha         BLOB NOT NULL,       -- 20 raw bytes, git rev-parse HEAD
    repo_dirty       INTEGER NOT NULL DEFAULT 0,
    worktree_sha     BLOB,                -- sha256 of porcelain status + diff
    -- The four canonical configs plus INTERLEAVE_HT live here.
    config_name      TEXT,                -- 'default_huge','shard_nohuge',...
    cmake_defs       TEXT NOT NULL DEFAULT '{}',   -- JSON {"NUMA_SHARD":"ON",...}
    build_type       TEXT,
    compiler         TEXT,
    compiler_version TEXT,
    cxx_flags        TEXT NOT NULL DEFAULT '[]',   -- JSON array
    spec_hash        BLOB NOT NULL UNIQUE,
    created_at       TEXT NOT NULL,
    CHECK (json_valid(cmake_defs) AND json_valid(cxx_flags))
) STRICT;

CREATE INDEX ix_spec_repo ON build_spec (repo_sha);

CREATE TABLE binary (
    binary_id            INTEGER PRIMARY KEY,
    content_sha256       BLOB NOT NULL UNIQUE,
    gnu_build_id         BLOB,
    size_bytes           INTEGER,
    text_size_bytes      INTEGER,
    stripped             INTEGER,
    -- oneTBB version belongs here: a TBB bump moves numbers and is invisible
    -- in the source hash.
    dyn_deps             TEXT NOT NULL DEFAULT '{}',   -- JSON
    first_seen_at        TEXT NOT NULL,
    CHECK (json_valid(dyn_deps))
) STRICT;

CREATE TABLE build_event (
    build_event_id   INTEGER PRIMARY KEY,
    spec_id          INTEGER NOT NULL REFERENCES build_spec,
    binary_id        INTEGER NOT NULL REFERENCES binary,
    build_dir        TEXT,               -- build/tmp.5sXF1VEG
    binary_path      TEXT,
    buildcmds_text   TEXT,               -- verbatim buildcmds.txt
    built_on_machine INTEGER REFERENCES machine,
    built_at         TEXT NOT NULL,
    UNIQUE (spec_id, binary_id, built_at)
) STRICT;

CREATE INDEX ix_build_event_spec ON build_event (spec_id, built_at DESC);
CREATE INDEX ix_build_event_binary ON build_event (binary_id);

-- Same recipe, same commit, different bits => codegen nondeterminism.
CREATE VIEW spec_reproducibility AS
SELECT be.spec_id, bs.config_name,
       COUNT(DISTINCT be.binary_id) AS distinct_binaries,
       COUNT(*) AS build_events
FROM build_event be JOIN build_spec bs ON bs.spec_id = be.spec_id
GROUP BY be.spec_id, bs.config_name
HAVING COUNT(DISTINCT be.binary_id) > 1;
