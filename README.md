# Where should SNCF invest in stations? (2019–2024)

Screening tool for SNCF Gares & Connexions' five-year station investment plan, built on SNCF open data.

**Group project** · EDHEC Business School, Data Visualisation course · November 2026

**Team:** Mahaut Lescure, Palig Narkizian, Cléa Vallanchon, Ting Xiao

**My part:** the data cleaning (the SQL pipeline in this repo) and integrating the team's charts into the final Tableau dashboard (layout and colour system).

**Live dashboard:** [Tableau Public](https://public.tableau.com/app/profile/ting.xiao7658/viz/1_SNCFCASE2_GROUP11_TABLEAUWORKBOOK/WheretoinvestinSNCFstations)

[![Tableau screening dashboard](https://public.tableau.com/views/1_SNCFCASE2_GROUP11_TABLEAUWORKBOOK/WheretoinvestinSNCFstations.png?:display_static_image=y&:showVizHome=n)](https://public.tableau.com/app/profile/ting.xiao7658/viz/1_SNCFCASE2_GROUP11_TABLEAUWORKBOOK/WheretoinvestinSNCFstations)

## The question

SNCF Gares & Connexions has to plan five years of station investment under budget pressure. The task is not to find the busiest stations: it is to see where traffic is growing, where access to the national network is thin, and which stations should be assessed first.

## Key results

| | |
|---|---|
| Stations cleaned and joined | 3,020 (France, 2015–2024) |
| Passenger entries in 2024 | 3,059 million, +12.2% vs 2019 |
| Share of 2024 traffic in the top 100 stations | 63% |
| "Under pressure" stations (top 25% traffic, growth above +12.2%) | 444, taking 80% of new passengers since 2019 |
| Fastest-growing regions, 2019–2024 | Nouvelle-Aquitaine +37.1%, Occitanie Sud +35.7% (Paris main stations +5.3%) |
| Departments without a national (A) station | 31 of 94 |

## How the data was cleaned

The source is a raw Excel workbook from the SNCF open-data portal (extracted 22 July 2026): annual ridership per station and a station reference list. Everything is rebuilt in DuckDB SQL from that file, in order, so any number can be traced back.

| Step | What it does |
|---|---|
| 0 | Import every sheet as text, with no automatic type guessing |
| 1 | Key, join and value checks; every finding goes into a `cleaning_log` table (24 entries) |
| 2–3 | Type the columns; collapse the reference list from one row per station × line to one row per station (UIC) |
| 4–5 | Validity checks; station × year fact table with Covid-year and single-year-spike flags |
| 6 | Department from postal code, region fill, coordinates (UIC match, manual matches, 2 national stations from the official SNCF source) |
| 7 | Final station table with growth metrics and straight-line distance to the nearest national station |
| 9 | Quality checks (every row must show `passed = true`), then export for Tableau |

Decisions worth knowing, from the cleaning log:

- **Station names cannot be a key.** Different stations share a name (two "Belleville", Cernay, Pringy), so everything joins on UIC.
- **The reference list duplicates stations.** It has one row per station per railway line, so a direct join multiplied every station on several lines. It is aggregated to one row per UIC first.
- **Some source values are wrong.** One UIC sat in two places 475 km apart; Marne-la-Vallée Chessy had the coordinates of a village called Chessy in the Rhône. Each case is logged with its fix or left open.
- **2019 is the baseline, not 2018.** 2018 is abnormally low almost everywhere (index 0.982 against 1.000 in 2017 and 2019), and 2020 is the Covid year.
- **Small bases are not classified.** Stations that were new or had fewer than 1,000 passengers in 2019 get no growth group, so a jump from 300 to 900 does not read as +200%.
- **visitors_YYYY is derived, not measured.** It equals passengers / (1 − non-traveller share) for 3,015 of 3,021 stations, so it is not used.

## Limits

High traffic is not congestion, and fast growth is not a capacity gap. Distance to a national station is straight-line, not travel time. The two thresholds (top 25%, +12.2%) are analytical choices and should be stress-tested before any money moves.

## Run it

The pipeline expects the course workbook `Donnees_SNCF_Projet_Dataviz_vf.xlsx` in the same folder (sheets `Frequentation_gares`, `Liste_gares` and `Regularite_TGV`). It is built from SNCF open data ([ressources.data.sncf.com](https://ressources.data.sncf.com), Explore v2.1 API) and is not redistributed here. With the [DuckDB CLI](https://duckdb.org/docs/installation/):

```
duckdb sncf.duckdb < sql/cleaning_pipeline.sql
```

Data: SNCF open data. Map in the dashboard image © Mapbox © OpenStreetMap.
