-- Controlled vocabulary. Extending this is a migration, never an ingest
-- side effect: the moment events auto-populate from data you get 'cycles',
-- 'cpu-cycles' and 'CPU_CLK_UNHALTED.THREAD' as three separate things.

CREATE TABLE pmu_event (
    event_id       INTEGER PRIMARY KEY,
    canonical_name TEXT NOT NULL UNIQUE,
    unit           TEXT NOT NULL,
    -- 'counter'  : raw PMU count
    -- 'derived'  : recomputable from counters (IPC, GHz, Bandwidth).
    --              Stored for convenience; prefer recomputing at analysis time.
    -- 'config'   : an echo of the invocation, not a measurement
    kind           TEXT NOT NULL,
    description    TEXT,
    CHECK (kind IN ('counter','derived','config'))
) STRICT;

-- Maps run_tpch CSV headers to events. Keyed on source column ORDINAL, which
-- is what disambiguates the duplicate 'br. misses' column without anyone
-- having to decide yet what the second one actually is.
CREATE TABLE csv_column (
    header_version TEXT NOT NULL,        -- bump when run.cpp changes the header
    col_ord        INTEGER NOT NULL,     -- 0-based index in the raw header
    raw_header     TEXT NOT NULL,        -- verbatim, whitespace stripped
    event_id       INTEGER REFERENCES pmu_event,  -- NULL for name/timing columns
    role           TEXT NOT NULL,        -- 'name','timing','counter','ignore'
    timing_stat    TEXT,                 -- 'median','mean','min','max','stddev'
    PRIMARY KEY (header_version, col_ord),
    CHECK (role IN ('name','timing','counter','ignore'))
) STRICT;
