-- Header version 'v4_dubliner' == the header emitted by the query1 SIMD-sweep
-- builds on dubliner (Xeon Gold 6238L).
--
-- dubliner's profiler does not expose the memory-bandwidth uncore events
-- (all_rd, stores, loads), so the emitted header is the v3 column layout with
-- those three columns omitted (18 cols instead of 21):
--      name median mean min max stddev CPUs IPC GHz Bandwidth cycles
--      LLC-misses l1-misses l1-hits instr. br. misses mem_stall task-clock
-- It keeps l1-hits (unlike v4_burrata) and mem_stall/task-clock (unlike
-- v4_manchego), so it is a distinct layout and gets its own header_version.
--
-- event_id mapping matches v3 (same events, just fewer columns).

INSERT INTO csv_column (header_version, col_ord, raw_header, event_id, role, timing_stat)
SELECT 'v4_dubliner', c.col_ord, c.raw_header,
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
    SELECT 16, 'mem_stall',    'mem_stall',    'counter', NULL     UNION ALL
    SELECT 17, 'task-clock',   'task_clock',   'counter', NULL
) c;
