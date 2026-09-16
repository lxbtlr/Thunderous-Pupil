-- Header version 'v2' == the header at HEAD 0ac019a, after the profiler patch
-- "Update the profiler to not have two br-misses cols" removed the duplicate
-- `br. misses` column. v2 is the same as v1 except ord 17 ('br. misses' #2)
-- is gone, so stores/loads/mem_stall/task-clock shift down by one:
--   name, median, mean, min, max, stddev, CPUs, IPC, GHz, Bandwidth, cycles,
--   LLC-misses, LLC-misses2, l1-misses, instr., br. misses, all_rd,
--   stores, loads, mem_stall, task-clock,
-- The single 'br. misses' is at ord 15.
--
-- Ingesting post-patch output under 'v1' fails loudly (mismatched ordinal);
-- this migration exists so new runs land under 'v2' and old runs stay under
-- 'v1', each matched to the header that produced them.
INSERT INTO csv_column (header_version, col_ord, raw_header, event_id, role, timing_stat)
SELECT 'v2', c.col_ord, c.raw_header,
       (SELECT event_id FROM pmu_event WHERE canonical_name = c.ev),
       c.role, c.stat
FROM (
    SELECT  0 AS col_ord, 'name'         AS raw_header, NULL AS ev, 'name'    AS role, NULL     AS stat UNION ALL
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
    SELECT 12, 'LLC-misses2',  'llc_misses_2', 'counter', NULL     UNION ALL
    SELECT 13, 'l1-misses',    'l1_misses',    'counter', NULL     UNION ALL
    SELECT 14, 'instr.',       'instructions', 'counter', NULL     UNION ALL
    SELECT 15, 'br. misses',   'br_misses_1',  'counter', NULL     UNION ALL
    SELECT 16, 'all_rd',       'all_rd',       'counter', NULL     UNION ALL
    SELECT 17, 'stores',       'stores',       'counter', NULL     UNION ALL
    SELECT 18, 'loads',        'loads',        'counter', NULL     UNION ALL
    SELECT 19, 'mem_stall',    'mem_stall',    'counter', NULL     UNION ALL
    SELECT 20, 'task-clock',   'task_clock',   'counter', NULL
) c;
