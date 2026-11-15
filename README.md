# What Drives Vehicle Recalls? An NHTSA Recall Analysis (2010–2025)

**Interactive dashboard:** [View on Tableau Public](https://public.tableau.com/app/profile/eddy.grullon/viz/WhatDrivesVehicleRecalls/Dashboard1)

![Dashboard preview](images/dashboard.png)

An end-to-end analysis of U.S. vehicle safety recalls, built with Python, SQL, and Tableau. It asks which vehicle systems and manufacturers drive recalls, and how that mix has changed over the last 15 years.

## Key findings

- **Electrical systems are the largest source of vehicle recalls.** They account for 1,888 recall campaigns from 2010 to 2025, about twice the next category (Structure, 935).
- **Their share of recalls nearly doubled.** Electrical recalls were 13.2% of vehicle recall campaigns in 2010–2013 and 24.4% in 2023–2025. Individual years are noisy (spikes in 2013 and 2020, a peak of 25.6% in 2024), so the comparison uses multi-year blocks.
- **The growth is concentrated in four electrical subcategories** (2010–2013 vs. 2022–2025): wiring/fuses (53 → 194), propulsion-related (3 → 191), instrument/display (15 → 86), and software (23 → 80).
- **Propulsion-related recalls rose gradually, not in a single jump.** They stayed at 1–3 per year through 2019, then climbed from 9 in 2020 to 60 in 2025. That is consistent with growing EV and hybrid adoption, but the data does not identify the powertrain type, so this is a hypothesis and not a finding.
- **Manufacturers differ in how many recalls they issue versus how large they are.** Ford has the most campaigns (692). Toyota has far fewer (238) but about 252,000 vehicles per campaign on average, versus about 35,000 for BMW (355 campaigns). RV and commercial-vehicle makers file many very small recalls (Forest River: about 620 vehicles per campaign). This describes recall patterns and is not a measure of quality.

## Questions explored

1. How many vehicle recalls are issued each year, and is the volume changing?
2. Which vehicle systems account for the most recalls?
3. Is the electrical system's share of recalls growing, and which subcategories drive it?
4. How do manufacturers compare in recall count and recall size?

## Data

- **Source:** [NHTSA Office of Defects Investigation, Recalls flat file](https://www.nhtsa.gov/nhtsa-datasets-and-apis) (`FLAT_RCL_POST_2010.zip`), with the layout described in NHTSA's data dictionary (`RCL.txt`). U.S. government data, publicly available.
- **Coverage:** recall reports from January 2010 through November 12, 2026. The analysis uses complete years only (2010–2025).
- **Size:** about 248,000 rows. Each recall campaign spans many rows (one per make, model, and model year).
- **Final analysis set:** 11,099 vehicle recall campaigns, after the filters described below.

## Method

1. **Load.** Downloaded the tab-delimited flat file (no header row), assigned column names from NHTSA's data dictionary, and checked that the column count matched.
2. **Clean.** Parsed `YYYYMMDD` dates, treated model year `9999` as unspecified, trimmed and upper-cased text fields, and split the component name at `:` to get a top-level component group (for example `ELECTRICAL SYSTEM`).
3. **Store.** Loaded the cleaned data into SQLite.
4. **Fix the unit of analysis.** One campaign (`CAMPNO`) appears on many rows, so every count uses `COUNT(DISTINCT CAMPNO)`. The potentially-affected vehicle count (`POTAFF`) repeats on each row of a campaign, so I confirmed it is constant within a campaign (spot-checked on the ten largest campaigns) and collapsed it to one value per campaign before summing.
5. **Filter.** Kept vehicle recalls only (`RCLTYPECD = 'V'`), dropped 2026 as a partial year, excluded the `EQUIPMENT` component group (mostly RV appliances and labeling issues), and merged manufacturer name variants (for example `CHRYSLER (FCA US, LLC)` and `CHRYSLER (FCA US LLC)`). This reduced 13,045 vehicle campaigns to 11,099.
6. **Analyze in SQL.** Used CTEs, `CASE` grouping of electrical subcomponents, and a window function (`LAG`) for year-over-year change in the electrical share.
7. **Visualize.** Exported summary tables to CSV and built a four-chart dashboard in Tableau Public.

## Tools

Python (pandas), SQL (SQLite: views, CTEs, window functions), DB Browser for SQLite, Tableau Public.

## Repository contents

| File | Purpose |
|---|---|
| `load_recalls.py` | Downloads the NHTSA file, cleans it, and loads it into `recalls.db` |
| `queries.sql` | Views and analysis queries |
| `export_for_tableau.py` | Writes the four CSVs used by the dashboard |
| `images/dashboard.png` | Dashboard screenshot |

The SQLite database (`recalls.db`) is not included because of its size. Run `load_recalls.py` to rebuild it.

## How to reproduce

```bash
pip install pandas
python load_recalls.py          # downloads the data and builds recalls.db
```

Open `recalls.db` in DB Browser for SQLite, run the view definitions in `queries.sql` (`vehicle_rows`, then `vehicle_core`), and write the changes to the database. Then:

```bash
python export_for_tableau.py    # writes CSVs to tableau_data/
```

Connect Tableau Public to the CSVs in `tableau_data/` to rebuild the dashboard.

## Limitations

- **Classification may have changed over time.** NHTSA's component categories become more specific in recent years (the "general/unspecified" electrical bucket fell from 49 campaigns in 2023 to 4 in 2025 while specific subcategories rose). The overall electrical share is the more reliable result, because moving a recall between electrical subcategories does not change it. The subcategory breakdown, especially propulsion, may partly reflect more specific coding.
- **Vehicle counts are per campaign.** A vehicle covered by several recalls is counted once for each, so totals are not unique vehicles.
- **No normalization for sales volume.** Manufacturers that sell more vehicles will tend to have more recalls.
- **Recalls are not defect rates.** A recall reflects a filing, and policies on when to recall differ across manufacturers.
- **Mixed vehicle types.** Trucks, buses, and RVs are included alongside passenger vehicles.
- **Subcategory counts overlap.** A campaign can list several components, so the subcategory counts do not sum to the electrical total, and subcategories are assigned by keyword matching (first match wins).
- **Some equipment categories remain.** The `EQUIPMENT` group was excluded, but a few related groups (for example adaptive/mobility equipment) stay in the data.
- **Association, not causation.** The analysis describes trends in recall filings and does not establish their causes.

## Author

Eddy Grullon
