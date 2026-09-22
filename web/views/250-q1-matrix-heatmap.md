# q1 matrix: heatmap
tab: chart

The 132-build query-1 matrix. config_name is parsed back into its four factors
(compiler, VW_USE_CRC32, VW_POS_16, group-lookup variant). One panel per
machine x engine x sf x thread count, each with its OWN colour scale, so a
slow panel cannot flatten the contrast on a fast one. The compiled (h) and
vectorized (v) engines always get separate panels -- their medians differ by
about 2x, so sharing one would stack their labels. 1.00 is always that
panel's best config. Labels are the raw median in ms.

```sql
-- ==========================================================================
-- q1 BUILD MATRIX
--
-- config_name is <compiler>_crc<c>_pos<p>_grp<g>_<machine>, e.g.
--   gcc16_crc0_pos0_grpnone_dubliner
-- so the four build factors are recovered by string surgery below.
--
-- ONE ROW PER DRAWN CELL -- do not break this.
-- The chart positions a mark by (panel, cell_label, compiler). The GROUP BY
-- below is exactly those three things expanded, so the result set cannot
-- contain two rows for one cell. If you add a column to the GROUP BY that is
-- not part of panel/cell_label/compiler, every such row is drawn at the SAME
-- x/y and the rects and their labels stack on top of each other. Overlapping
-- text in this chart always means duplicate rows, never a font problem.
--
-- This corpus has THREE dimensions that will do that if you let them:
--   engine   h (compiled) and v (vectorized) both run q1 -- this is the one
--            that bit us: two engines, one cell, two labels on top of
--            each other, and the h/v medians differ by ~2x so it smeared.
--   threads  1 / 2 / 4 / 8
--   sf_label sf1 here, but the corpus carries 21 scale factors
-- All three are in `panel`, so each gets its own row of the chart instead.
-- Nothing checks this for you -- if you add a dimension, put it in `panel`.
--
-- KNOBS
--   * to collapse panels rather than stack them, pin the dimension in the
--     WHERE clause below and drop it from `panel`.
-- ==========================================================================
WITH q1 AS (
    SELECT *
    FROM v_runs
    WHERE q_number = 1
      AND quality = 'clean'
      AND config_name LIKE '%\_crc%' ESCAPE '\'
      AND config_name LIKE '%\_grp%' ESCAPE '\'
      -- AND sf_label = 'sf1'
      AND threads = 1      -- the corpus has 1/2/4/8; unpin to get a panel each
      -- AND engine   = 'v'
),
split_head AS (
    SELECT q1.*,
           substr(config_name, 1, instr(config_name, '_crc') - 1) AS compiler,
           substr(config_name, instr(config_name, '_crc') + 4, 1) AS crc,
           substr(config_name, instr(config_name, '_pos') + 4, 1) AS pos,
           substr(config_name, instr(config_name, '_grp') + 4)    AS grp_tail
    FROM q1
),
split_tail AS (
    SELECT split_head.*,
           substr(grp_tail, 1, instr(grp_tail, '_') - 1) AS grp,
           substr(grp_tail, instr(grp_tail, '_') + 1)    AS built_for
    FROM split_head
),
cell AS (
    SELECT node || '   ' || paradigm || ' (' || engine || ')'
                 || '   sf=' || sf_label
                 || '   ' || threads || ' thr'            AS panel,
           compiler,
           crc,
           pos,
           grp,
           node,
           engine,
           sf_label,
           threads,
           'crc' || crc || ' pos' || pos                 AS flags,
           grp || ' crc' || crc || ' pos' || pos         AS cell_label,
           (CASE grp WHEN 'none' THEN 0 WHEN 'og' THEN 1
                     WHEN 'ga'   THEN 2 ELSE 9 END) * 10
             + CAST(crc AS INTEGER) * 2
             + CAST(pos AS INTEGER)                      AS cell_ord,
           ROUND(AVG(median_ms), 3)                      AS median_ms,
           ROUND(AVG(cv), 4)                             AS cv,
           COUNT(*)                                      AS n_runs,
           COUNT(DISTINCT build_event_id)                AS n_builds,
           MAX(built_for)                                AS built_for,
           COUNT(DISTINCT built_for)                     AS n_built_for
    FROM split_tail
    -- exactly panel + cell_label + compiler, expanded. Nothing else.
    GROUP BY node, engine, sf_label, threads, grp, crc, pos, compiler
)
SELECT *,
       ROUND(median_ms / MIN(median_ms) OVER (PARTITION BY panel), 3) AS rel_to_best,
       ROUND((median_ms - MIN(median_ms) OVER (PARTITION BY panel))
             / NULLIF(MAX(median_ms) OVER (PARTITION BY panel)
                    - MIN(median_ms) OVER (PARTITION BY panel), 0), 4) AS shade,
       CASE WHEN n_built_for > 1   THEN 'MIXED'
            WHEN built_for <> node THEN 'MISMATCH'
            ELSE 'ok' END                                             AS placement
FROM cell
ORDER BY panel, cell_ord, compiler
```

```json
{
  "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
  "facet": {
    "row": {
      "field": "panel",
      "type": "nominal",
      "title": null,
      "header": {
        "labelAngle": 0,
        "labelAlign": "left",
        "labelFontWeight": "bold",
        "labelLimit": 320
      }
    }
  },
  "resolve": {
    "scale": {
      "color": "independent"
    },
    "legend": {
      "color": "independent"
    }
  },
  "spec": {
    "width": 468,
    "height": 96,
    "layer": [
      {
        "mark": {
          "type": "rect",
          "stroke": "#8883"
        },
        "encoding": {
          "color": {
            "field": "rel_to_best",
            "type": "quantitative",
            "title": "x best in panel",
            "scale": {
              "scheme": "viridis",
              "reverse": true
            },
            "legend": {
              "gradientLength": 80
            }
          }
        }
      },
      {
        "mark": {
          "type": "text",
          "fontSize": 9,
          "baseline": "middle"
        },
        "encoding": {
          "text": {
            "field": "median_ms",
            "type": "quantitative",
            "format": ".3s"
          },
          "color": {
            "condition": {
              "test": "datum.shade > 0.55",
              "value": "#fff"
            },
            "value": "#000"
          }
        }
      }
    ],
    "encoding": {
      "x": {
        "field": "cell_label",
        "type": "nominal",
        "title": null,
        "sort": {
          "field": "cell_ord",
          "op": "min"
        },
        "axis": {
          "labelAngle": -40
        }
      },
      "y": {
        "field": "compiler",
        "type": "nominal",
        "title": null,
        "sort": [
          "gcc9",
          "gcc16",
          "clang22"
        ]
      },
      "tooltip": [
        {
          "field": "panel"
        },
        {
          "field": "compiler"
        },
        {
          "field": "grp"
        },
        {
          "field": "flags"
        },
        {
          "field": "median_ms"
        },
        {
          "field": "rel_to_best"
        },
        {
          "field": "cv"
        },
        {
          "field": "n_runs"
        },
        {
          "field": "n_builds"
        },
        {
          "field": "placement"
        }
      ]
    }
  },
  "config": {
    "background": null,
    "font": "ui-monospace, Menlo, Consolas, monospace",
    "axis": {
      "labelFontSize": 10,
      "titleFontSize": 11,
      "grid": false,
      "domainColor": "#8886",
      "tickColor": "#8886"
    },
    "legend": {
      "labelFontSize": 10,
      "titleFontSize": 10
    },
    "header": {
      "labelFontSize": 12,
      "titleFontSize": 11
    },
    "view": {
      "stroke": "transparent"
    }
  }
}
```
