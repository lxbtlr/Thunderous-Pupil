# 2. bars: best mean time in sf
tab: chart

```sql
-- Best (minimum) observed time for each engine x query x machine.
-- adjust sf and or remove threads filters to make this query have a lot more data.


SELECT node, query, q_number, engine,
       build_event_id, config_name, head,
       ROUND(MIN(mean_ms), 3) AS best_ms,
       COUNT(*)               AS runs_considered
FROM v_runs
WHERE quality = 'clean'
  AND sf_label = 'sf1'
  AND threads  = 1
  AND q_number <> 5          -- q5 excluded; delete this line to include it
  AND mean_ms IS NOT NULL
GROUP BY node, q_number, engine
ORDER BY node, q_number, engine
```

```json
{
  "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
  "data": {
    "name": "table"
  },
  "facet": {
    "field": "query",
    "type": "nominal",
    "title": null,
    "sort": {
      "field": "q_number"
    }
  },
  "columns": 1,
  "spacing": 1,
  "spec": {
    "width": 420,
    "height": 180,
    "mark": {
      "type": "bar",
      "stroke": "#222",
      "strokeWidth": 0.006
    },
    "encoding": {
      "x": {
        "field": "node",
        "type": "nominal",
        "title": null,
        "axis": {
          "labelAngle": 0
        },
        "scale": {
          "paddingInner": 0.3,
          "paddingOuter": 0.15
        }
      },
      "y": {
        "field": "best_ms",
        "type": "quantitative",
        "title": "best ms"
      },
      "xOffset": {
        "field": "engine",
        "type": "nominal",
        "scale": {
          "paddingInner": 0.15
        }
      },
      "color": {
        "field": "engine",
        "type": "nominal",
        "scale": {
          "domain": ["b", "h", "v"],
          "range": ["#00BA38", "#F8766D", "#619CFF"]
        }
      },
      "tooltip": [
        {"field": "node"},
        {"field": "query"},
        {"field": "engine"},
        {"field": "best_ms"},
        {"field": "build_event_id", "type": "nominal", "title": "build"},
        {"field": "runs_considered"}
      ]
    }
  },
  "resolve": {
    "scale": {
      "y": "independent"
    },
    "axis": {
      "x": "independent"
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
      "category": ["#0b6", "#c50", "#06c", "#a2b", "#888", "#c33"]
    }
  }
}
```
