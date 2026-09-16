-- Seed vocabulary. Everything here is a deliberate, reviewable decision.

INSERT INTO engine (code, name, paradigm) VALUES
    ('h', 'hyper/huge',  'compiled'),
    ('v', 'vectorwise',  'vectorized');

INSERT INTO query (benchmark, q_number, label) VALUES
    ('tpch',  1, 'q1'),
    ('tpch',  3, 'q3'),
    ('tpch',  5, 'q5'),
    ('tpch',  6, 'q6'),
    ('tpch',  9, 'q9'),
    ('tpch', 18, 'q18');

INSERT INTO pmu_event (canonical_name, unit, kind, description) VALUES
    ('cycles',        'count', 'counter', 'CPU cycles'),
    ('instructions',  'count', 'counter', 'retired instructions'),
    ('llc_misses',    'count', 'counter', 'last-level cache misses (col 1)'),
    ('llc_misses_2',  'count', 'counter', 'second LLC miss counter; exact event TBD'),
    ('l1_misses',     'count', 'counter', 'L1 misses'),
    ('br_misses_1',   'count', 'counter', 'branch misses, first occurrence'),
    ('br_misses_2',   'count', 'counter', 'branch misses, second occurrence; exact event TBD'),
    ('all_rd',        'count', 'counter', 'all reads; exact event TBD'),
    ('stores',        'count', 'counter', 'store uops'),
    ('loads',         'count', 'counter', 'load uops'),
    ('mem_stall',     'count', 'counter', 'memory stall cycles'),
    ('task_clock',    'ms',    'counter', 'perf task-clock'),
    ('ipc',           'ratio', 'derived', 'instructions/cycles; recompute rather than trust'),
    ('ghz',           'GHz',   'derived', 'effective clock; = cycles / task_clock'),
    ('bandwidth',     'GB/s',  'derived', 'harness-computed memory bandwidth');

-- Header version 'v1' == the header at HEAD 1f01d6a:
--   name, median, mean, min, max, stddev, CPUs, IPC, GHz, Bandwidth, cycles,
--   LLC-misses, LLC-misses2, l1-misses, instr., br. misses, all_rd,
--   br. misses, stores, loads, mem_stall, task-clock,
-- Note col 15 and col 17 share the raw header 'br. misses'. They are
-- distinguished by ordinal, NOT by name, and mapped to distinct events.
-- 'CPUs' is a config echo and lands on run.cpus, not in run_counter.
INSERT INTO csv_column (header_version, col_ord, raw_header, event_id, role, timing_stat)
SELECT 'v1', c.col_ord, c.raw_header,
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
    SELECT 17, 'br. misses',   'br_misses_2',  'counter', NULL     UNION ALL
    SELECT 18, 'stores',       'stores',       'counter', NULL     UNION ALL
    SELECT 19, 'loads',        'loads',        'counter', NULL     UNION ALL
    SELECT 20, 'mem_stall',    'mem_stall',    'counter', NULL     UNION ALL
    SELECT 21, 'task-clock',   'task_clock',   'counter', NULL
) c;
