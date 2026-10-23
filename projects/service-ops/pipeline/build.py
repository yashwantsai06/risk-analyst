"""Build the NYC 311 service-operations dataset for the dashboard.

Usage:
    python3 build.py <raw_csv_dir> <sqlite_db_path>

Loads every CSV in <raw_csv_dir> into SQLite, runs the SQL in ../sql in order,
and writes ../data.json (pre-aggregated cubes the dashboard filters in the browser).
"""
import csv
import glob
import json
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SQL_DIR = os.path.join(HERE, "..", "sql")
OUT = os.path.join(HERE, "..", "data.json")
COLS = ["unique_key", "created_date", "closed_date", "agency", "complaint_type",
        "borough", "open_data_channel_type", "status"]


def run_sql(con, name):
    with open(os.path.join(SQL_DIR, name), encoding="utf-8") as f:
        con.executescript(f.read())


def rows(con, sql):
    cur = con.execute(sql)
    names = [d[0] for d in cur.description]
    return names, cur.fetchall()


def main(raw_dir, db_path):
    if os.path.exists(db_path):
        os.remove(db_path)
    con = sqlite3.connect(db_path)
    run_sql(con, "01_staging.sql")

    total = 0
    for path in sorted(glob.glob(os.path.join(raw_dir, "*.csv"))):
        with open(path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            batch = [tuple(r.get(c, "") for c in COLS) for r in reader]
        con.executemany(f"INSERT INTO stg_requests VALUES ({','.join('?' * len(COLS))})", batch)
        total += len(batch)
        print(f"loaded {os.path.basename(path)}: {len(batch):,}")
    con.commit()
    print(f"staged {total:,} rows")

    run_sql(con, "02_model.sql")
    run_sql(con, "03_kpi_views.sql")
    con.commit()

    out = {}
    for key, view in [("weekly", "v_cube_weekly"), ("heatmap", "v_cube_heatmap"),
                      ("complaints", "v_cube_complaint")]:
        names, data = rows(con, f"SELECT * FROM {view}")
        out[key] = {"cols": names, "rows": data}
        print(f"{view}: {len(data):,} rows")

    _, dq = rows(con, "SELECT dq_flag, is_closed, n FROM v_data_quality")
    _, med_a = rows(con, "SELECT * FROM v_median_by_agency ORDER BY measured DESC")
    _, med_c = rows(con, "SELECT * FROM v_median_by_channel ORDER BY measured DESC")
    _, span = rows(con, "SELECT MIN(created_date), MAX(created_date), COUNT(*) FROM fact_request")
    out["meta"] = {
        "source": "NYC Open Data, 311 Service Requests (erm2-nwe9)",
        "first": span[0][0], "last": span[0][1], "total": span[0][2],
        "data_quality": dq, "median_by_agency": med_a, "median_by_channel": med_c,
    }

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"))
    print(f"wrote {OUT} ({os.path.getsize(OUT) / 1024:.0f} KB)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
