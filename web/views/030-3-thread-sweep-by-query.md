# 3. thread sweep by query
tab: chart

```sql
-- Runtime against thread count. One row per machine, one column per query,
-- one colour per engine. All measured thread counts.
--
-- The spec sets resolve.scale.x = independent, so each panel gets its own
-- x axis. dubliner sweeps to 384 threads, burrata only to 80; a shared axis
-- would pad burrata's panels with empty space out to 384.
--
-- GROUPING: every non-aggregate column in the SELECT is also in the GROUP BY.
-- SQLite allows a bare column in an aggregate query and just picks an
-- arbitrary row for it, so dropping one silently AVERAGES its series together
-- and mislabels the result. That is how you get one line per engine when you
-- expected one per (engine, build, scale factor).
--
-- As written you get one line per (engine, build, scale factor):
--   colour  = engine        dash = scale factor
--   opacity = config        detail keeps separate builds apart
-- That is a lot at once. Pin a dimension with one of the filters below to
-- thin it out -- fixing the scale factor is usually the first thing to do.
SELECT m.stable_key       AS node,
       q.label            AS query,
       q.q_number,
       e.code             AS engine,
       bs.config_name,
       be.build_event_id,
       d.sf_label,
       d.scale_factor,
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
  AND q.q_number <> 5          -- q5 excluded; delete this line to include it
  -- AND d.sf_label = 'sf10'
  -- AND bs.config_name = 'default_huge'
  -- AND be.build_event_id = (SELECT MAX(build_event_id) FROM build_event)
GROUP BY m.machine_id, q.query_id, e.engine_id,
         be.build_event_id, d.dataset_id, t.threads
ORDER BY m.stable_key, q.q_number, e.code, d.scale_factor, t.threads
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
    "height": 160,
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
  },
  "resolve": {
    "scale": {
      "x": "independent"
    }
  }
}
```
