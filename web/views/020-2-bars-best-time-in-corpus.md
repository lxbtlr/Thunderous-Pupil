# 2. bars: best time in corpus
tab: chart

```sql
-- Best (minimum) observed time for each engine x query x machine.
--
-- NOTE ON SCOPE: as written this minimises across EVERYTHING else -- every
-- scale factor, thread count, build and trial in the corpus. Since sf1 is
-- always faster than sf100, the winner is effectively "sf1 at its best thread
-- count", which may not be the comparison you want.
--
-- To hold the data size fixed and take the best thread count (usually the
-- intended reading), uncomment the sf_label line.
-- To restrict to one build, uncomment the config_name line.
--
-- Unlike the other views this one deliberately minimises ACROSS builds and
-- scale factors -- that is what 'best in corpus' means. config_name is
-- therefore omitted from the SELECT rather than left as a bare column that
-- would show an arbitrary build's name next to another build's number.
SELECT m.stable_key AS node,
       q.label      AS query,
       q.q_number,
       e.code       AS engine,
       ROUND(MIN(r.min_ns) / 1e6, 3) AS best_ms,
       COUNT(*)                      AS runs_considered,
       MIN(t.threads)                AS threads_at_min
FROM run r
JOIN task t              ON t.task_id = r.task_id
JOIN query q             ON q.query_id = t.query_id
JOIN dataset d           ON d.dataset_id = t.dataset_id
JOIN engine e            ON e.engine_id = r.engine_id
JOIN build_event be      ON be.build_event_id = r.build_event_id
JOIN build_spec bs       ON bs.spec_id = be.spec_id
JOIN machine_snapshot ms ON ms.snapshot_id = r.snapshot_id
JOIN machine m           ON m.machine_id = ms.machine_id
WHERE r.quality = 'clean'
  AND r.min_ns IS NOT NULL
  AND q.q_number <> 5          -- q5 excluded; delete this line to include it
  -- AND d.sf_label = 'sf1'
  -- AND bs.config_name = 'default_huge'
GROUP BY m.machine_id, q.query_id, e.engine_id
ORDER BY m.stable_key, q.q_number, e.code
```

```json
{
  "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
  "data": {
    "name": "table"
  },
  "width": 300,
  "height": 300,
  "mark": {
    "type": "bar"
  },
  "encoding": {
    "x": {
      "field": "query",
      "type": "nominal",
      "title": null,
      "sort": {
        "field": "q_number"
      }
    },
    "y": {
      "field": "best_ms",
      "type": "quantitative",
      "title": "best ms (min over corpus)"
    },
    "xOffset": {
      "field": "engine",
      "type": "nominal"
    },
    "color": {
      "field": "engine",
      "type": "nominal"
    },
    "column": {
      "field": "node",
      "type": "nominal",
      "title": null
    },
    "tooltip": [
      {
        "field": "node"
      },
      {
        "field": "query"
      },
      {
        "field": "engine"
      },
      {
        "field": "best_ms"
      },
      {
        "field": "threads_at_min"
      },
      {
        "field": "runs_considered"
      }
    ]
  },
  "config": {
    "background": null,
    "font": "ui-monospace, Menlo, Consolas, monospace",
    "axis": {
      "labelFontSize": 11,
      "titleFontSize": 12,
      "grid": true,
      "gridColor": "#8884",
      "domainColor": "#8886",
      "tickColor": "#8886"
    },
    "legend": {
      "labelFontSize": 11,
      "titleFontSize": 12
    },
    "view": {
      "stroke": "transparent"
    },
    "range": {
      "category": [
        "#0b5",
        "#c50",
        "#06c",
        "#a2b",
        "#888",
        "#c33"
      ]
    }
  }
}
```
