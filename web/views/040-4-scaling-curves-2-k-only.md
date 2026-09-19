# 4. scaling curves (2^k only)
tab: chart

```sql
-- Log-log scaling. A straight line of slope -1 is perfect scaling;
-- flattening is where adding threads stops paying.
--
-- GROUPING: every non-aggregate column in the SELECT is also in the GROUP BY.
-- SQLite allows a bare column in an aggregate query and just picks an
-- arbitrary row for it, so dropping one silently AVERAGES its series together
-- and mislabels the result. That is how you get one line per engine when you
-- expected one per (engine, build, scale factor).
--
-- Restricted to power-of-two thread counts via (threads & (threads-1)) = 0,
-- which is true only when exactly one bit is set. Drop that line to include
-- every measured thread count.
SELECT m.stable_key AS node,
       q.label      AS query,
       q.q_number,
       e.code       AS engine,
       bs.config_name,
       d.sf_label,
       be.build_event_id,
       t.threads,
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
  AND (t.threads & (t.threads - 1)) = 0     -- powers of two only
  AND q.q_number <> 5          -- q5 excluded; delete this line to include it
  -- AND bs.config_name = 'default_huge'
  -- AND d.sf_label = 'sf10'
GROUP BY m.machine_id, q.query_id, e.engine_id,
         be.build_event_id, d.dataset_id, t.threads
ORDER BY m.stable_key, q.q_number, t.threads
```

```json
{
  "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
  "data": {
    "name": "table"
  },
  "facet": {
    "row": {
      "field": "node",
      "type": "nominal",
      "title": null
    },
    "column": {
      "field": "query",
      "type": "nominal",
      "title": null,
      "sort": {
        "field": "q_number"
      }
    }
  },
  "spec": {
    "width": 190,
    "height": 165,
    "mark": {
      "type": "line",
      "point": true
    },
    "encoding": {
      "x": {
        "field": "threads",
        "type": "quantitative",
        "scale": {
          "type": "log",
          "base": 2
        },
        "title": "threads"
      },
      "y": {
        "field": "median_ms",
        "type": "quantitative",
        "scale": {
          "type": "log"
        },
        "title": "median ms"
      },
      "color": {
        "field": "engine",
        "type": "nominal"
      },
      "strokeDash": {
        "field": "sf_label",
        "type": "nominal",
        "title": "scale"
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
          "field": "sf_label"
        },
        {
          "field": "threads"
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
      },
      "detail": {
        "field": "build_event_id",
        "type": "nominal"
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
