# 1. bars: sf1, 1 thread
tab: chart

```sql
-- ==========================================================================
-- CONTROLLING WHICH BUILD IS PLOTTED
--
-- By default this includes EVERY build_event. If you have more than one
-- config (default_huge, shard_nohuge, ...) each query/engine/machine will
-- appear once per build and the bars will be averaged together, which is
-- almost never what you want.
--
-- Pick one:
--   a) one named config  -> uncomment the config_name line
--   b) one exact build   -> uncomment the build_event_id line, get ids from
--                           the 'builds' table view or: vocab builds
--   c) latest build only -> uncomment the sub-select line
--   d) keep them all and compare -> leave commented, and change the chart's
--      "column" encoding from node to config_name (or add a row facet)
-- ==========================================================================
SELECT m.stable_key           AS node,
       q.label                AS query,
       q.q_number,
       e.code                 AS engine,
       bs.config_name,
       be.build_event_id,
       ROUND(AVG(r.median_ns) / 1e6, 3) AS median_ms,
       COUNT(*)                         AS n_runs
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
  AND d.sf_label = 'sf1'
  AND t.threads  = 1
  AND q.q_number <> 5          -- q5 excluded; delete this line to include it
  -- AND bs.config_name = 'default_huge'
  -- AND be.build_event_id = 1
  -- AND be.build_event_id = (SELECT MAX(build_event_id) FROM build_event)
GROUP BY m.machine_id, q.query_id, e.engine_id, be.build_event_id
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
      "field": "median_ms",
      "type": "quantitative",
      "title": "median ms"
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
        "field": "config_name"
      },
      {
        "field": "median_ms"
      },
      {
        "field": "n_runs"
      }
    ],
    "opacity": {
      "field": "config_name",
      "type": "nominal",
      "title": "config",
      "scale": {
        "range": [
          1.0,
          0.55,
          0.3
        ]
      }
    }
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
