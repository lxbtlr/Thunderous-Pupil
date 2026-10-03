-- Header version 'template': the layout-independent way to ingest run output.
--
-- Problem it solves: csv_column keys every column by ORDINAL inside a fixed
-- header_version, so every layout change -- a node that suddenly exposes one
-- more PMU event (mem_stall on manchego), a reorder in run.cpp -- needs a
-- hand-written migration before its runs can be ingested. That is a new
-- migration for what is, semantically, the same event in a different place.
--
-- header_token instead maps the header TEXT to its meaning, independent of
-- position. The 'template' header_version resolves each column of the run's
-- OWN header through this table at ingest time, so the column set, order and
-- presence may vary freely: a run ingests as long as every column it emits is
-- a known token.
--
-- The controlled vocabulary rule is preserved: this does NOT auto-create
-- events. Unknown header text is rejected, naming the column, and the fix is
-- still a migration that inserts the token. So the only migrations left are
-- for genuinely NEW events, not for re-arrangements of known ones.
--
-- Duplicate header texts (the historical doubled 'br. misses') stay fixed by
-- ORDINAL: resolve_text_map still emits a positional map, and run_counter is
-- keyed by (run_id, col_ord), so two columns that share a text land as two
-- distinct rows. header_token holds one row per text and does not need the
-- occurrence index.

CREATE TABLE header_token (
    raw_header  TEXT PRIMARY KEY,        -- verbatim header text, whitespace stripped
    event_id    INTEGER REFERENCES pmu_event,
    role        TEXT NOT NULL,           -- 'name','timing','counter','ignore'
    timing_stat TEXT,                    -- 'median','mean','min','max','stddev'
    note        TEXT,
    CHECK (role IN ('name','timing','counter','ignore'))
) STRICT;

-- Seed from the existing per-layout vocabulary. Keep only tokens that agree
-- with themselves across every header_version they appear in; a disagreement
-- is a real modelling bug and is deliberately left out so template mode fails
-- loudly on it rather than guessing.
INSERT INTO header_token (raw_header, event_id, role, timing_stat, note)
SELECT raw_header, event_id, role, timing_stat, NULL
FROM csv_column
GROUP BY raw_header
HAVING COUNT(DISTINCT COALESCE(event_id, -1) || '|' || role
                  || '|' || COALESCE(timing_stat, '')) = 1;

-- 'br. misses' is the one raw_header that historically meant two different
-- events: v1/v2 emitted the text TWICE (br_misses_1 then br_misses_2), so the
-- consistency filter above drops it. Every modern layout emits it once,
-- meaning br_misses_1, so template mode binds the text to br_misses_1. The
-- legacy doubled v1/v2 layout is still only ingestible through its fixed
-- v1/v2 header_version, never through template mode.
INSERT OR IGNORE INTO header_token (raw_header, event_id, role, timing_stat, note)
SELECT 'br. misses', event_id, 'counter', NULL,
       'modern single-occurrence meaning; v1/v2 emitted it twice'
FROM pmu_event WHERE canonical_name = 'br_misses_1';

-- Every concrete header signature ingested under template mode, so the shapes
-- present in the corpus remain discoverable without one migration per shape.
CREATE TABLE header_layout (
    signature_sha256 BLOB PRIMARY KEY,   -- sha256 of the '|'-joined signature
    header_version   TEXT NOT NULL,      -- the version under which it arrived
    signature        TEXT NOT NULL,      -- '|'-joined normalized header cells
    n_cols           INTEGER NOT NULL,
    first_seen_at    TEXT NOT NULL,
    note             TEXT
) STRICT;
