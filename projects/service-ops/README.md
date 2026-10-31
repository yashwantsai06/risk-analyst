# Service Operations MI: NYC 311 case study

Live dashboard: https://yashwantsai06.github.io/risk-analyst/projects/service-ops/

An operational reporting dashboard built on 1,964,678 real service requests
(NYC Open Data, 311 Service Requests, April to September 2026).

## Layout

| Path | What it does |
|---|---|
| `sql/01_staging.sql` | Raw staging table, loaded as text |
| `sql/02_model.sql` | Star schema (fact + agency, channel, borough, complaint dimensions) and data-quality flags |
| `sql/03_kpi_views.sql` | Resolution bands, reporting cubes, exact medians |
| `pipeline/build.py` | Loads the CSVs into SQLite, runs the SQL, exports `data.json` |
| `data.json` | Pre-aggregated cubes the dashboard filters in the browser |
| `index.html` | Dashboard and written case study (plain JavaScript and SVG) |

## Rebuild

Download the monthly CSVs from the NYC Open Data API (dataset `erm2-nwe9`,
columns `unique_key, created_date, closed_date, agency, complaint_type, borough,
open_data_channel_type, status`) into a folder, then:

```bash
python3 pipeline/build.py <csv_folder> <output.db>
```

Raw data is not committed.
