-- Header version 'v3' == the header emitted by the baseline branch binary
-- (HEAD 7c70c96 'Port canary system to baseline').
--
-- The baseline run.cpp profiler emits a DIFFERENT 21-column layout than v2:
--   v2:  ..., cycles, LLC-misses, LLC-misses2, l1-misses, instr., br. misses, ...
--   v3:  ..., cycles, LLC-misses, l1-misses,  l1-hits,  instr., br. misses, ...
--
-- Concretely, v2 ord 12 was 'LLC-misses2' and ord 13 'l1-misses'; baseline
-- dropped the duplicate-LLC column and instead reports 'l1-hits' at ord 13,
-- so l1-misses shifts from 13 down to 12. Everything from ord 14 onward is
-- identical to v2. Because parse_out validates BOTH position and text of the
-- header, baseline output must not be ingested under v2 -- it fails loudly.
-- This migration registers the baseline layout as 'v3' so baseline runs land
-- under the header that produced them (old v1/v2 runs are untouched).
--
-- l1-hits is a new counter with no existing pmu_event, so we add one.
INSERT INTO pmu_event (event_id, canonical_name, unit, kind, description)
SELECT 16, 'l1_hits', 'count', 'counter', 'L1 hits'
WHERE NOT EXISTS (SELECT 1 FROM pmu_event WHERE event_id = 16);

INSERT INTO csv_column (header_version, col_ord, raw_header, event_id, role, timing_stat)
SELECT 'v3', c.col_ord, c.raw_header,
       (SELECT event_id FROM pmu_event WHERE canonical_name = c.ev),
       c.role, c.stat
FROM (
    SELECT  0 AS col_ord, 'name'       AS raw_header, NULL            AS ev, 'name'    AS role, NULL     AS stat UNION ALL
    SELECT  1, 'median',       NULL,           'timing',  'median' UNION ALL
    SELECT  2, 'mean',         NULL,           'timing',  'mean'   UNION ALL
    SELECT  3, 'min',          NULL,           'timing',  'min'    UNION ALL
    SELECT  4, 'max',          NULL,           'timing',  'max'    UNION ALL
    SELECT  5, 'stddev',       NULL,           'timing',  'stddev' UNION ALL
    SELECT  6, 'CPUs',         NULL,           'ignore',  NULL     UNION ALL
    SELECT  7, 'IPC',          'ipc',          'counter', NULL     UNION ALL
    SELECT  8, 'GHz',          'ghz',          'counter', NULL     UNION ALL
    SELECT  9, 'Bandwidth',    'bandwidth',    'counter', NULL     UNION ALL
    SELECT 10, 'cycles',       'cycles',       'counter', NULL     UNION ALL
    SELECT 11, 'LLC-misses',   'llc_misses',   'counter', NULL     UNION ALL
    SELECT 12, 'l1-misses',    'l1_misses',    'counter', NULL     UNION ALL
    SELECT 13, 'l1-hits',      'l1_hits',      'counter', NULL     UNION ALL
    SELECT 14, 'instr.',       'instructions', 'counter', NULL     UNION ALL
    SELECT 15, 'br. misses',   'br_misses_1',  'counter', NULL     UNION ALL
    SELECT 16, 'all_rd',       'all_rd',       'counter', NULL     UNION ALL
    SELECT 17, 'stores',       'stores',       'counter', NULL     UNION ALL
    SELECT 18, 'loads',        'loads',        'counter', NULL     UNION ALL
    SELECT 19, 'mem_stall',    'mem_stall',    'counter', NULL     UNION ALL
    SELECT 20, 'task-clock',   'task_clock',   'counter', NULL
) c;
