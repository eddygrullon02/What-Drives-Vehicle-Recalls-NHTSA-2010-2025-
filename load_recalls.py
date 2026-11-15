"""
Step 1 of the NHTSA recall project: download -> clean -> load into SQLite.

Run:  pip install pandas
      python load_recalls.py

Data dictionary (field order/meaning): https://static.nhtsa.gov/odi/ffdd/rcl/RCL.txt
Open it and CONFIRM the COLUMNS list below matches before trusting results.
The flat file is tab-delimited, has NO header row, and dates are YYYYMMDD.
"""
import io
import sqlite3
import urllib.request
import zipfile

import pandas as pd

# POST_2010 covers 2010 onward; add FLAT_RCL_PRE_2010.zip later if you want a longer trend.
URL = "https://static.nhtsa.gov/odi/ffdd/rcl/FLAT_RCL_POST_2010.zip"

# Field order per RCL.txt (verify!). Field names as published by NHTSA.
COLUMNS = [
    "RECORD_ID", "CAMPNO", "MAKETXT", "MODELTXT", "YEARTXT", "MFGCAMPNO",
    "COMPNAME", "MFGNAME", "BGMAN", "ENDMAN", "RCLTYPECD", "POTAFF",
    "ODATE", "INFLUENCED_BY", "MFGTXT", "RCDATE", "DATEA", "RPNO", "FMVSS",
    "DESC_DEFECT", "CONEQUENCE_DEFECT", "CORRECTIVE_ACTION", "NOTES",
    "RCL_CMPT_ID", "MFR_COMP_NAME", "MFR_COMP_DESC", "MFR_COMP_PTNO",
    "DO_NOT_DRIVE", "PARK_OUTSIDE",
]

# --- 1. Download and read -------------------------------------------------
print("Downloading...")
raw = urllib.request.urlopen(URL).read()
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    txt_name = [n for n in z.namelist() if n.lower().endswith(".txt")][0]
    print("Reading", txt_name)
    df = pd.read_csv(
        z.open(txt_name), sep="\t", header=None, dtype=str,
        encoding="latin-1", quoting=3, on_bad_lines="skip",
    )

print("Raw shape:", df.shape)
if df.shape[1] != len(COLUMNS):
    raise SystemExit(
        f"File has {df.shape[1]} columns but COLUMNS has {len(COLUMNS)}. "
        "Compare against RCL.txt and fix the list before continuing."
    )
df.columns = COLUMNS

# --- 2. Clean -------------------------------------------------------------
for col in ["ODATE", "RCDATE", "DATEA"]:
    df[col] = pd.to_datetime(df[col], format="%Y%m%d", errors="coerce")

df["POTAFF"] = pd.to_numeric(df["POTAFF"], errors="coerce")
df["YEARTXT"] = pd.to_numeric(df["YEARTXT"], errors="coerce")
df.loc[df["YEARTXT"] == 9999, "YEARTXT"] = pd.NA   # 9999 = year not specified
df["recall_year"] = df["RCDATE"].dt.year

# Normalize text fields so GROUP BY doesn't split "FORD" and "Ford "
for col in ["MAKETXT", "MODELTXT", "MFGNAME", "COMPNAME"]:
    df[col] = df[col].str.strip().str.upper()

# Component text looks like "AIR BAGS:FRONTAL:DRIVER SIDE"; keep the top level
df["component_group"] = df["COMPNAME"].str.split(":").str[0]

# Note: one campaign (CAMPNO) can have many rows (one per make/model/year).
# Keep that in mind: COUNT(DISTINCT CAMPNO) = recalls, COUNT(*) = rows.
print("Duplicate RECORD_IDs:", df["RECORD_ID"].duplicated().sum())
print("Null RCDATE:", df["RCDATE"].isna().sum())

# --- 3. Load into SQLite --------------------------------------------------
con = sqlite3.connect("recalls.db")
df.to_sql("recalls", con, if_exists="replace", index=False)
print("Loaded", len(df), "rows into recalls.db")

# --- 4. Sanity-check queries (the start of your analysis) ------------------
queries = {
    "Recall campaigns per year": """
        SELECT recall_year, COUNT(DISTINCT CAMPNO) AS campaigns
        FROM recalls WHERE recall_year IS NOT NULL
        GROUP BY recall_year ORDER BY recall_year;""",
    "Top 10 component groups by campaigns": """
        SELECT component_group, COUNT(DISTINCT CAMPNO) AS campaigns
        FROM recalls GROUP BY component_group
        ORDER BY campaigns DESC LIMIT 10;""",
    "Top 10 manufacturers by campaigns": """
        SELECT MFGNAME, COUNT(DISTINCT CAMPNO) AS campaigns
        FROM recalls GROUP BY MFGNAME
        ORDER BY campaigns DESC LIMIT 10;""",
}
for title, q in queries.items():
    print("\n==", title)
    print(pd.read_sql(q, con).to_string(index=False))

con.close()
