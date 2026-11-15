"""
Export four clean CSVs from recalls.db for Tableau Public.

Before running:
  1. In DB Browser, press Ctrl+S (Write Changes) so the views are saved
     into recalls.db, then close DB Browser (it can lock the file).
  2. Run from the same folder as recalls.db:  python export_for_tableau.py
"""
import os
import sqlite3

import pandas as pd

con = sqlite3.connect("recalls.db")
os.makedirs("tableau_data", exist_ok=True)

SUBGROUP_CASE = """
    CASE
        WHEN COMPNAME LIKE '%PROPULSION%'   THEN 'Propulsion'
        WHEN COMPNAME LIKE '%SOFTWARE%'     THEN 'Software'
        WHEN COMPNAME LIKE '%WIRING%'       THEN 'Wiring / fuses'
        WHEN COMPNAME LIKE '%INSTRUMENT%'   THEN 'Instrument / display'
        WHEN COMPNAME LIKE '%BODY CONTROL%' THEN 'Body control'
        WHEN COMPNAME LIKE '%12V/24V/48V%'  THEN '12V/24V/48V systems'
        WHEN COMPNAME LIKE '%ALTERNATOR%'   THEN 'Alternator'
        WHEN COMPNAME = 'ELECTRICAL SYSTEM' THEN 'General / unspecified'
        ELSE 'Other electrical'
    END
"""

exports = {
    # Chart 1: headline trend
    "electrical_share_by_year.csv": """
        SELECT recall_year,
               COUNT(DISTINCT CASE WHEN component_group = 'ELECTRICAL SYSTEM' THEN CAMPNO END) AS electrical,
               COUNT(DISTINCT CAMPNO) AS total,
               ROUND(100.0 * COUNT(DISTINCT CASE WHEN component_group = 'ELECTRICAL SYSTEM' THEN CAMPNO END)
                     / COUNT(DISTINCT CAMPNO), 1) AS pct_electrical
        FROM vehicle_core
        GROUP BY recall_year
        ORDER BY recall_year;""",

    # Chart 2: what is driving it (one row per year x subgroup)
    "electrical_subgroups_by_year.csv": f"""
        SELECT recall_year,
               {SUBGROUP_CASE} AS subgroup,
               COUNT(DISTINCT CAMPNO) AS campaigns
        FROM vehicle_core
        WHERE component_group = 'ELECTRICAL SYSTEM'
        GROUP BY recall_year, subgroup
        ORDER BY recall_year, campaigns DESC;""",

    # Chart 3: top component groups
    "component_groups.csv": """
        SELECT component_group, COUNT(DISTINCT CAMPNO) AS campaigns
        FROM vehicle_core
        GROUP BY component_group
        ORDER BY campaigns DESC
        LIMIT 20;""",

    # Chart 4: manufacturers (POTAFF collapsed to one row per campaign first)
    "manufacturers.csv": """
        WITH campaigns AS (
            SELECT CAMPNO,
                   CASE
                       WHEN mfg_clean LIKE 'MERCEDES-BENZ USA%' THEN 'MERCEDES-BENZ USA'
                       WHEN mfg_clean LIKE 'NAVISTAR%'          THEN 'NAVISTAR'
                       ELSE mfg_clean
                   END AS mfg,
                   MAX(POTAFF) AS potaff
            FROM vehicle_core
            GROUP BY CAMPNO, mfg
        )
        SELECT mfg AS manufacturer,
               COUNT(*) AS campaigns,
               SUM(potaff) AS vehicles_potentially_affected,
               ROUND(AVG(potaff)) AS avg_vehicles_per_campaign
        FROM campaigns
        GROUP BY mfg
        HAVING COUNT(*) >= 50
        ORDER BY campaigns DESC;""",
}

for filename, query in exports.items():
    try:
        df = pd.read_sql(query, con)
    except Exception as e:
        raise SystemExit(
            f"Failed on {filename}: {e}\n"
            "If this says 'no such table: vehicle_core', save the views in "
            "DB Browser (Ctrl+S) and try again."
        )
    if filename == "electrical_subgroups_by_year.csv":
        # A year with no recalls in a subgroup has no row in the query result,
        # which makes Tableau break the line. 0 campaigns is the true value, so fill it in.
        full = pd.MultiIndex.from_product(
            [sorted(df["recall_year"].unique()), sorted(df["subgroup"].unique())],
            names=["recall_year", "subgroup"],
        )
        df = df.set_index(["recall_year", "subgroup"]).reindex(full, fill_value=0).reset_index()
    df.to_csv(os.path.join("tableau_data", filename), index=False)
    print(f"Wrote tableau_data/{filename}  ({len(df)} rows)")

con.close()
