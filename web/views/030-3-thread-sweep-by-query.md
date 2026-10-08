# 3. thread sweep by query (speedup)

tab: chart

Scalability, not raw time: speedup over each series' own 1-thread run, log-log
against an ideal-linear reference. Pins one scale factor and one build.

```sql
-- THREAD SWEEP -- SPEEDUP FORM
--
-- Plots speedup relative to each series' OWN 1-thread run, not absolute ms.
-- That is the question a thread sweep is usually asked to answer: absolute
-- runtime conflates "this engine is fast" with "this engine scales", and the
-- second is what the sweep is for.
--

WITH cell AS (
    SELECT node, query, q_number, engine, paradigm,
           build_event_id, config_name, sf_label, threads,
           AVG(median_ms) AS median_ms,
           MAX(cv)        AS worst_cv,
           COUNT(*)       AS n_runs
    FROM v_runs
    WHERE quality = 'clean'
      AND median_ms IS NOT NULL
--and node = "dubliner"
      AND q_number <> 5          -- q5 excluded; delete this line to include it
      AND sf_label = 'sf100'      -- PIN: one data size, else you sweep two curves
      --AND build_event_id = (SELECT MAX(build_event_id) FROM build_event)
      AND ( config_name LIKE '%shard%' or config_name LIKE '%pin%')
      -- AND ingested_at >= datetime('now', '-7 days')
    GROUP BY node, q_number, engine, build_event_id, sf_label, threads
),
based AS (
    SELECT cell.*,
           MAX(CASE WHEN threads = 1 THEN median_ms END) OVER w AS base_ms,
           MIN(median_ms)                                OVER w AS best_ms,
           MAX(threads)                                  OVER w AS max_threads
    FROM cell
    WINDOW w AS (PARTITION BY node, q_number, engine, build_event_id, config_name, sf_label)
)
SELECT node, query, q_number, engine, paradigm,
       build_event_id, config_name, sf_label, threads,
       ROUND(median_ms, 3)                     AS median_ms,
       ROUND(base_ms / median_ms, 3)           AS speedup,
       -- speedup / threads: 1.0 is perfect, and the knee where this falls off
       -- is the useful thread count. Swap it onto y to read saturation.
       ROUND(base_ms / median_ms / threads, 3) AS efficiency,
       threads                                 AS ideal,
       ROUND(base_ms / best_ms, 3)             AS peak_speedup,
       max_threads,
       ROUND(worst_cv, 4)                      AS worst_cv,
       n_runs
FROM based
WHERE base_ms IS NOT NULL
ORDER BY node, q_number, engine, threads
```

```json
{
  "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
  "data": {
    "name": "table"
  },
  "transform": [
    {
      "calculate": "datum.engine === 'v' ? 'vectorized (v)' : 'compiled (h, b)'",
      "as": "engine_group"
    },
    {
      "calculate": "datum.node + '/' + datum.build_event_id",
      "as": "series"
    }
  ],
  "facet": {
    "row": {
      "field": "query",
      "type": "nominal",
      "title": null,
      "sort": {"field": "q_number"}
    },
    "column": {
      "field": "engine_group",
      "type": "nominal",
      "title": null,
      "sort": ["vectorized (v)", "compiled (h, b)"]
    }
  },
  "spacing": 14,
  "spec": {
    "width": 280,
    "height": 250,
    "layer": [
      {
        "mark": {
          "type": "line",
          "stroke": "#888",
          "strokeDash": [3, 3],
          "strokeWidth": 1,
          "opacity": 0.6
        },
        "encoding": {
          "y": {"field": "ideal", "type": "quantitative"}
        }
      },
      {
        "params": [
          {
            "name": "pick",
            "select": {"type": "point", "fields": ["config_name"]},
            "bind": "legend"
          },
          {
            "name": "nodeSel",
            "select": {"type": "point", "fields": ["node"]},
            "bind": {
              "input": "select",
              "options": [null, "dubliner", "burrata", "manchego", "roquefort"],
              "labels": ["all machines", "dubliner", "burrata", "manchego", "roquefort"],
              "name": "machine  "
            }
          }
        ],
        "mark": {
          "type": "line",
          "point": {"size": 26, "filled": true},
          "strokeWidth": 2
        },
        "encoding": {
          "y": {
            "field": "speedup",
            "type": "quantitative",
            "title": "speedup vs 1 thread",
            "scale": {"type": "log", "base": 2}
          },
          "color": {
            "field": "config_name",
            "type": "nominal",
            "title": "config"
          },
          "strokeDash": {
            "field": "engine",
            "type": "nominal",
            "title": "engine"
          },
          "detail": {
            "field": "series",
            "type": "nominal"
          },
          "opacity": {
            "condition": {
              "test": {
                "and": [
                  {"param": "pick"},
                  {"param": "nodeSel"}
                ]
              },
              "value": 1
            },
            "value": 0.06
          },
          "tooltip": [
            {"field": "node"},
            {"field": "query"},
            {"field": "engine"},
            {"field": "config_name", "title": "config"},
            {"field": "build_event_id", "title": "build"},
            {"field": "threads"},
            {"field": "speedup", "title": "speedup"},
            {"field": "efficiency", "title": "eff (speedup/thr)"},
            {"field": "median_ms", "title": "median ms"},
            {"field": "peak_speedup", "title": "peak speedup"},
            {"field": "worst_cv", "title": "worst cv"},
            {"field": "n_runs"}
          ]
        }
      }
    ],
    "encoding": {
      "x": {
        "field": "threads",
        "type": "quantitative",
        "title": "threads",
        "scale": {"type": "log", "base": 2},
        "axis": {"format": "d", "labelAngle": 0}
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
    "legend": {"labelFontSize": 11, "titleFontSize": 12},
    "view": {"stroke": "transparent"}
  }
}
```
