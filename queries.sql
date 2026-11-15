-- NHTSA recall project: cleanup + first analysis queries (SQLite)
-- Run in DB Browser for SQLite, the sqlite3 CLI, or via pandas.read_sql.

-- ============================================================
-- 0. CHECKS BEFORE ANALYSIS
-- ============================================================

-- What recall types are in the file? Confirm codes against RCL.txt.
-- (Expect vehicles, tires, equipment, child seats.) EQUIPMENT being your
-- #1 component group means non-vehicle recalls are mixed in.
SELECT RCLTYPECD, COUNT(DISTINCT CAMPNO) AS campaigns
FROM recalls
GROUP BY RCLTYPECD
ORDER BY campaigns DESC;

-- How far does the data go? 2026 is a partial year, so exclude or label it.
SELECT MIN(RCDATE) AS first_report, MAX(RCDATE) AS last_report FROM recalls;

-- ============================================================
-- 1. CLEAN VIEWS
-- ============================================================

-- Vehicle recalls only, with manufacturer names merged.
-- Your first run showed "CHRYSLER (FCA US, LLC)" and "CHRYSLER (FCA US LLC)"
-- as separate manufacturers; this CASE fixes that kind of split.
-- Extend it after checking query 0b below.
DROP VIEW IF EXISTS vehicle_rows;
CREATE VIEW vehicle_rows AS
SELECT
    *,
    CASE
        WHEN MFGNAME LIKE 'CHRYSLER%' OR MFGNAME LIKE 'FCA%'      THEN 'STELLANTIS (CHRYSLER/FCA)'
        WHEN MFGNAME LIKE 'FORD MOTOR%'                           THEN 'FORD'
        WHEN MFGNAME LIKE 'GENERAL MOTORS%'                       THEN 'GENERAL MOTORS'
        WHEN MFGNAME LIKE 'TOYOTA%'                               THEN 'TOYOTA'
        WHEN MFGNAME LIKE 'HONDA%'                                THEN 'HONDA'
        WHEN MFGNAME LIKE 'NISSAN%'                               THEN 'NISSAN'
        WHEN MFGNAME LIKE 'VOLKSWAGEN%'                           THEN 'VOLKSWAGEN GROUP'
        WHEN MFGNAME LIKE 'BMW%'                                  THEN 'BMW'
        WHEN MFGNAME LIKE 'HYUNDAI%'                              THEN 'HYUNDAI'
        WHEN MFGNAME LIKE 'KIA%'                                  THEN 'KIA'
        WHEN MFGNAME LIKE 'TESLA%'                                THEN 'TESLA'
        ELSE MFGNAME
    END AS mfg_clean
FROM recalls
WHERE RCLTYPECD = 'V'      -- verify 'V' = vehicle in RCL.txt / query 0
  AND recall_year <= 2025; -- drop partial year

-- 0b. Review the biggest manufacturer names that still need merging.
SELECT mfg_clean, COUNT(DISTINCT CAMPNO) AS campaigns
FROM vehicle_rows
GROUP BY mfg_clean
ORDER BY campaigns DESC
LIMIT 40;

-- ============================================================
-- 2. ANALYSIS QUERIES
-- ============================================================

-- Q1. Recall campaigns by year (vehicles only)
SELECT recall_year, COUNT(DISTINCT CAMPNO) AS campaigns
FROM vehicle_rows
GROUP BY recall_year
ORDER BY recall_year;

-- Q2. Which component groups drive vehicle recalls?
SELECT component_group, COUNT(DISTINCT CAMPNO) AS campaigns
FROM vehicle_rows
GROUP BY component_group
ORDER BY campaigns DESC
LIMIT 15;

-- Q3. Is the electrical-system share of recalls growing?
-- (CTE + window function; a good "SQL skills" showcase for the README.)
WITH by_year AS (
    SELECT
        recall_year,
        COUNT(DISTINCT CASE WHEN component_group = 'ELECTRICAL SYSTEM' THEN CAMPNO END) AS electrical,
        COUNT(DISTINCT CAMPNO) AS total
    FROM vehicle_rows
    GROUP BY recall_year
)
SELECT
    recall_year,
    electrical,
    total,
    ROUND(100.0 * electrical / total, 1) AS pct_electrical,
    ROUND(100.0 * electrical / total
          - LAG(100.0 * electrical / total) OVER (ORDER BY recall_year), 1) AS change_vs_prior_yr
FROM by_year
ORDER BY recall_year;

-- Q4. Manufacturer comparison: campaigns AND vehicles affected.
-- POTAFF repeats on every row of a campaign, so collapse to one row per
-- campaign BEFORE summing or you will overcount. (Verify this against a
-- few campaigns: SELECT CAMPNO, POTAFF FROM recalls WHERE CAMPNO = '...';)
WITH campaigns AS (
    SELECT CAMPNO, mfg_clean, MAX(POTAFF) AS potaff
    FROM vehicle_rows
    GROUP BY CAMPNO, mfg_clean
)
SELECT
    mfg_clean,
    COUNT(*) AS campaigns,
    SUM(potaff) AS vehicles_potentially_affected,
    ROUND(AVG(potaff)) AS avg_vehicles_per_campaign
FROM campaigns
GROUP BY mfg_clean
ORDER BY campaigns DESC
LIMIT 15;

-- Q5. Do-not-drive / park-outside recalls: how common, and who issues them?
SELECT mfg_clean,
       COUNT(DISTINCT CASE WHEN DO_NOT_DRIVE = 'Yes' THEN CAMPNO END) AS do_not_drive_campaigns
FROM vehicle_rows
GROUP BY mfg_clean
HAVING do_not_drive_campaigns > 0
ORDER BY do_not_drive_campaigns DESC
LIMIT 10;
-- If this returns nothing, check DISTINCT DO_NOT_DRIVE values; the coding
-- may be 'Y'/'N' or blank, and the field is only populated for recent years.

SELECT COMPNAME, COUNT(DISTINCT CAMPNO) AS campaigns
FROM vehicle_rows
WHERE component_group = 'EQUIPMENT'
GROUP BY COMPNAME
ORDER BY campaigns DESC
LIMIT 15;

--Creating a cleaner view (no longer includes specialty vehicles like RVs)
CREATE VIEW vehicle_core AS
SELECT * FROM vehicle_rows
WHERE component_group <> 'EQUIPMENT';

--Rerun of Q3 and Q4 with vehicle_core instead of vehicle_rows:
--Q3:
WITH by_year AS (
    SELECT
        recall_year,
        COUNT(DISTINCT CASE WHEN component_group = 'ELECTRICAL SYSTEM' THEN CAMPNO END) AS electrical,
        COUNT(DISTINCT CAMPNO) AS total
    FROM vehicle_core
    GROUP BY recall_year
)
SELECT
    recall_year,
    electrical,
    total,
    ROUND(100.0 * electrical / total, 1) AS pct_electrical,
    ROUND(100.0 * electrical / total
          - LAG(100.0 * electrical / total) OVER (ORDER BY recall_year), 1) AS change_vs_prior_yr
FROM by_year
ORDER BY recall_year;

--Q4:
WITH campaigns AS (
    SELECT CAMPNO, mfg_clean, MAX(POTAFF) AS potaff
    FROM vehicle_core
    GROUP BY CAMPNO, mfg_clean
)
SELECT
    mfg_clean,
    COUNT(*) AS campaigns,
    SUM(potaff) AS vehicles_potentially_affected,
    ROUND(AVG(potaff)) AS avg_vehicles_per_campaign
FROM campaigns
GROUP BY mfg_clean
ORDER BY campaigns DESC
LIMIT 15;


--What is driving the increase of electrical recalls?
SELECT COMPNAME,
       COUNT(DISTINCT CASE WHEN recall_year BETWEEN 2010 AND 2013 THEN CAMPNO END) AS early,
       COUNT(DISTINCT CASE WHEN recall_year BETWEEN 2022 AND 2025 THEN CAMPNO END) AS recent
FROM vehicle_core
WHERE component_group = 'ELECTRICAL SYSTEM'
GROUP BY COMPNAME
ORDER BY recent DESC
LIMIT 15;


--Verification of Q4 totals:
SELECT CAMPNO, COUNT(*) AS row_count, MIN(POTAFF) AS min_potaff, MAX(POTAFF) AS max_potaff
FROM vehicle_core
GROUP BY CAMPNO
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 10;

--Electrical Subcomponent query that shows what is driving the increase:
SELECT COMPNAME,
       COUNT(DISTINCT CASE WHEN recall_year BETWEEN 2010 AND 2013 THEN CAMPNO END) AS early,
       COUNT(DISTINCT CASE WHEN recall_year BETWEEN 2022 AND 2025 THEN CAMPNO END) AS recent
FROM vehicle_core
WHERE component_group = 'ELECTRICAL SYSTEM'
GROUP BY COMPNAME
ORDER BY recent DESC
LIMIT 15;

--Grouping the subcomponent names into more readable buckets:
SELECT
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
  END AS subgroup,
  COUNT(DISTINCT CASE WHEN recall_year BETWEEN 2010 AND 2013 THEN CAMPNO END) AS early,
  COUNT(DISTINCT CASE WHEN recall_year BETWEEN 2022 AND 2025 THEN CAMPNO END) AS recent
FROM vehicle_core
WHERE component_group = 'ELECTRICAL SYSTEM'
GROUP BY subgroup
ORDER BY recent DESC;

--Query to check whether or not propulsion is an EV trend or not:
SELECT recall_year,
       COUNT(DISTINCT CAMPNO) AS propulsion_campaigns
FROM vehicle_core
WHERE component_group = 'ELECTRICAL SYSTEM'
  AND COMPNAME LIKE '%PROPULSION%'
GROUP BY recall_year
ORDER BY recall_year;

