# engine share by machine
tab: chart

Stacked share of cells each engine wins, per machine. Ties are their own band,
so a tall grey band means the corpus cannot separate the engines at all there.

```sql
-- engine_duel already carries cpu_vendor; joining machine_snapshot again
-- makes the column ambiguous.
SELECT node, cpu_vendor, query, winner, COUNT(*) AS cells
FROM engine_duel
WHERE pair = 'h vs v'
GROUP BY snapshot_id, query_id, winner
ORDER BY node, query
```

```json
{
  "width": 300, "height": 260,
  "mark": "bar",
  "encoding": {
    "x": {"field": "query", "type": "nominal", "title": null},
    "y": {"field": "cells", "type": "quantitative", "stack": "normalize",
          "title": "share of cells"},
    "color": {"field": "winner", "type": "nominal",
              "scale": {"domain": ["h", "v", "tie"],
                        "range": ["#0b5", "#c50", "#888"]}},
    "column": {"field": "node", "type": "nominal", "title": null},
    "tooltip": [{"field": "node"}, {"field": "query"},
                {"field": "winner"}, {"field": "cells"}]
  }
}
```
