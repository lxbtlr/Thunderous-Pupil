-- Engine code 'b' == the q6 'branching' variant of the hyper engine
-- (q6_hyper_branching in run.cpp, key "6b"). Same compiled paradigm as 'h'
-- (hyper/huge); it is only emitted for query 6. Baseline runs without -e
-- produce v/h/b for q6, so the corpus needs 'b' in the engine vocabulary.

INSERT INTO engine (code, name, paradigm)
SELECT 'b', 'hyper branching (q6)', 'compiled'
WHERE NOT EXISTS (SELECT 1 FROM engine WHERE code = 'b');
