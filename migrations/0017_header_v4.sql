-- Header version 'v4' == the header emitted by the baseline branch binary
-- at HEAD 0ad7684 ('Fix mmap + tbb vm bloat issue').
--
-- vs v3, run.cpp reordered the perf-event columns: in v3 the order after
-- l1-hits was  instr., br. misses, all_rd, stores, loads ; in v4 it is
--      stores, loads, all_rd, instr., br. misses
-- (columns 14..18). Everything else (0..13, 19..20) is identical to v3.
--
-- Per-machine variants: the profiler only emits a counter column when the
-- node's PMU exposes the event, so the header differs by hardware --
--   v4          (21 cols): full x86 set  ... br. misses, mem_stall, task-clock
--   v4_manchego (20 cols): Intel 4509Y, mem_stall event not probed
--   v4_burrata  (17 cols): ARM Neoverse-N1, only a subset of counters
-- A run must be ingested under the exact header that produced it (the parser
-- validates position AND text), so each machine layout gets its own version.

INSERT INTO csv_column (header_version, col_ord, raw_header, event_id, role, timing_stat)
SELECT 'v4', c.col_ord, c.raw_header,
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
    SELECT 14, 'stores',       'stores',       'counter', NULL     UNION ALL
    SELECT 15, 'loads',        'loads',        'counter', NULL     UNION ALL
    SELECT 16, 'all_rd',       'all_rd',       'counter', NULL     UNION ALL
    SELECT 17, 'instr.',       'instructions', 'counter', NULL     UNION ALL
    SELECT 18, 'br. misses',   'br_misses_1',  'counter', NULL     UNION ALL
    SELECT 19, 'mem_stall',    'mem_stall',    'counter', NULL     UNION ALL
    SELECT 20, 'task-clock',   'task_clock',   'counter', NULL
) c;

-- v4_manchego: same as v4 but WITHOUT mem_stall (event not probed on the
-- Intel 4509Y), so task-clock shifts from ord 20 to ord 19.
INSERT INTO csv_column (header_version, col_ord, raw_header, event_id, role, timing_stat)
SELECT 'v4_manchego', c.col_ord, c.raw_header,
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
    SELECT 14, 'stores',       'stores',       'counter', NULL     UNION ALL
    SELECT 15, 'loads',        'loads',        'counter', NULL     UNION ALL
    SELECT 16, 'all_rd',       'all_rd',       'counter', NULL     UNION ALL
    SELECT 17, 'instr.',       'instructions', 'counter', NULL     UNION ALL
    SELECT 18, 'br. misses',   'br_misses_1',  'counter', NULL     UNION ALL
    SELECT 19, 'task-clock',   'task_clock',   'counter', NULL
) c;

-- v4_burrata: ARM Neoverse-N1 layout (17 cols).
INSERT INTO csv_column (header_version, col_ord, raw_header, event_id, role, timing_stat)
SELECT 'v4_burrata', c.col_ord, c.raw_header,
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
    SELECT 11, 'instr.',       'instructions', 'counter', NULL     UNION ALL
    SELECT 12, 'br. misses',   'br_misses_1',  'counter', NULL     UNION ALL
    SELECT 13, 'LLC-misses',   'llc_misses',   'counter', NULL     UNION ALL
    SELECT 14, 'l1-misses',    'l1_misses',    'counter', NULL     UNION ALL
    SELECT 15, 'mem_stall',    'mem_stall',    'counter', NULL     UNION ALL
    SELECT 16, 'task-clock',   'task_clock',   'counter', NULL
) c;
