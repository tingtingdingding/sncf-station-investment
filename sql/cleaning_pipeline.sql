-- =====================================================================
-- SNCF Case 2 (Group 11) - data cleaning pipeline (DuckDB)
-- Rebuilds every clean table from the raw Excel file, in order.
-- =====================================================================

-- =====================================================================
-- STEP 0 - Import the raw sheets as text (no automatic type guessing)
-- =====================================================================
INSTALL excel;
LOAD excel;

CREATE OR REPLACE TABLE raw_frequentation AS
SELECT * FROM read_xlsx('Donnees_SNCF_Projet_Dataviz_vf.xlsx',
     sheet = 'Frequentation_gares', header = true, all_varchar = true);

CREATE OR REPLACE TABLE raw_liste_gares AS
SELECT * FROM read_xlsx('Donnees_SNCF_Projet_Dataviz_vf.xlsx',
     sheet = 'Liste_gares', header = true, all_varchar = true);

CREATE OR REPLACE TABLE raw_regularite AS
SELECT * FROM read_xlsx('Donnees_SNCF_Projet_Dataviz_vf.xlsx',
     sheet = 'Regularite_TGV', header = true, all_varchar = true);

-- =====================================================================
-- CLEANING LOG - findings and decisions (exported for the team and the report)
-- =====================================================================
CREATE OR REPLACE TABLE cleaning_log (
    log_id      INTEGER PRIMARY KEY,
    logged_on   DATE,
    step        VARCHAR,
    table_name  VARCHAR,
    finding     VARCHAR,
    evidence    VARCHAR,
    impact      VARCHAR,
    action      VARCHAR,
    status      VARCHAR
);

INSERT INTO cleaning_log VALUES
(1, DATE '2026-11-07', '1.2 Key check', 'raw_frequentation',
 'Station name is not unique: two different stations are both called "Belleville" (UIC 87141804, Meurthe-et-Moselle; UIC 87486142, Vendee).',
 '3,021 rows; 3,021 distinct UIC; 3,020 distinct names',
 'Our current clean file renamed the Vendee station to "Bellevigny", but its Stations table has no UIC column, so all joins and counts rely on station names.',
 'Use code_uic_complet as the station key and keep it in every clean table; count stations with COUNTD(UIC), not names.',
 'Partly handled'),
(2, DATE '2026-11-07', '1.2 Key check', 'T_kpis (Case2_SNCF_data_clean.xlsx)',
 'KPI shows 3,020 stations while the source has 3,021 rows.',
 'The missing station is Monaco - Monte-Carlo (flagged outside France); 2024 passengers 3,059.1 M also exclude its 9.2 M.',
 'Not an error, but the exclusion is not stated on Slide 7; KPIs are stored as typed text, so they will not update if the data changes.',
 'State the Monaco exclusion in the limitations; compute KPIs in Tableau from the station table instead of typing them.',
 'To document'),
(3, DATE '2026-11-07', '1.2 Key check', 'raw_liste_gares',
 'The station reference list has one row per station per railway line, so UIC is not unique and no column combination is a clean key.',
 '6,469 rows; 6,062 distinct UIC; even UIC + line + section + kilometre point gives only 6,457 distinct values.',
 'Joining it directly to station ridership would duplicate stations and inflate passenger totals.',
 'Step 3: reduce the reference list to one row per UIC before any join.',
 'Open'),
(4, DATE '2026-11-07', '1.3 Join test', 'raw_frequentation x raw_liste_gares',
 'Joining ridership directly to the station reference list on UIC duplicates every station that sits on several railway lines.',
 '3,021 -> 3,314 rows; 2024 passengers 3,068.3 M -> 4,320.5 M (+41%)',
 'Totals, shares and rankings would all be wrong, and unevenly so, because some stations would be counted up to 6 times.',
 'Aggregate the reference list to one row per UIC (station grain) before any join.',
 'Open'),
(5, DATE '2026-11-07', '1.3 Value check', 'raw_liste_gares',
 'UIC 87783621 (Badaroux) has one row in Badaroux, Lozere and one in Haussignemont, Marne, 475 km apart: an error in the source.',
 'The other 338 repeated UICs are consistent: same name, coordinates within 3.9 km (median 86 m); 17 of them sit on a commune boundary (e.g. Mantes-Station).',
 'Badaroux is not in the ridership table, so no impact on our figures.',
 'Keep the Lozere row, which matches the station name; drop the Marne row.',
 'Noted'),
(6, DATE '2026-11-07', '1.3 Key choice', 'raw_frequentation x raw_liste_gares',
 'Station names cannot be used as a key: different stations share a name (e.g. Cernay, Pringy) and names are spelled differently across tables.',
 'Exact-name match: 1,858 of 3,021 stations (62%); UIC match: 2,983 of 3,021 (98.7%).',
 'Any join or count on names would silently lose about a third of stations.',
 'Join and count on UIC only; use names as display labels.',
 'Fixed'),
(7, DATE '2026-11-07', '1.4 Commune check', 'raw_liste_gares',
 '18 UICs list two communes; all but one stay within a single department (stations on a commune boundary, e.g. Clichy-Levallois).',
 '18 of 6,062 UICs; 12 of them are in the ridership table; only Badaroux spans two departments (see log 5).',
 'No impact on department-level analysis.',
 'When aggregating to one row per UIC, keep all communes as a list (STRING_AGG) instead of picking one; drop the Badaroux Marne row first.',
 'Decided'),
(8, DATE '2026-11-07', '1.4 Missing values', 'raw_frequentation',
 'Station category (A/B/C) is missing for 70 stations, segment for 125, SNCF region for 11.',
 'The 70 stations carry 0.4% of 2024 passengers (median about 390 a year); 22 had zero passengers in 2019; the largest is Monaco, outside France.',
 'Unlikely to change the departments-without-a-national-station count on Slide 4.',
 'Keep these stations with category = Unknown; fill the 11 missing regions from the postal code in step 6; mention in the limitations.',
 'Decided'),
(9, DATE '2026-11-07', '3 Aggregate reference list', 'stg_gares',
 'Station reference list aggregated to one row per UIC.',
 '6,469 rows -> 6,062 stations; 1 erroneous row removed (Badaroux, Marne); coordinates averaged, max spread 3.9 km; join to ridership keeps 3,021 rows and the exact 2024 total.',
 'Removes the +41% passenger inflation found in log 4.',
 'Name and department taken as the single value per UIC (checked: no conflicts); communes kept as a list; coordinates averaged; number of lines added as a connectivity indicator.',
 'Fixed'),
(10, DATE '2026-11-07', '3 Join test', 'stg_frequentation x stg_gares',
 '38 stations in the ridership table have no match in the reference list, including 4 national (A) stations such as Paris Montparnasse, CDG 2 TGV and Marne-la-Vallee Chessy.',
 '38 stations = 130.0 M passengers in 2024 (4.2%); Seine-et-Marne and Seine-Saint-Denis each have exactly one A station, and both are unmatched.',
 'Without a fix they vanish from the maps; if departments came from the reference list, 33 instead of 31 departments would show no national station.',
 'Step 6: take the department from the postal code for all stations; recover coordinates where an equivalent station exists in the reference list; list the rest in the limitations.',
 'Open'),
(11, DATE '2026-11-07', '3 Join test', 'stg_frequentation x stg_gares',
 '66 stations with a ridership record are flagged as non-passenger in the reference list.',
 '37 of them had zero passengers in 2024 (both sources agree); 29 had traffic, 94.5 K passengers in total.',
 'Negligible on totals.',
 'Use the ridership table as the source of truth for traffic; do not filter on the reference flag; handle zero-traffic stations in step 4.',
 'Decided'),
(12, DATE '2026-11-07', '4.1-4.2 Logic checks', 'stg_frequentation',
 'visitors_YYYY is not measured: it equals passengers / (1 - non_traveller_share) for 3,015 of 3,021 stations. Beaucroissant (new in 2024) shows 0 visitors for 910 passengers.',
 'No negative or missing passenger values; 3,015 of 3,021 stations match the formula.',
 'Showing visitors next to passengers would repeat the same trend as if it were separate evidence; the Beaucroissant visitors value is wrong.',
 'Drop visitors_YYYY from the clean tables; keep non_traveller_share as a station attribute; trust passengers.',
 'Decided'),
(13, DATE '2026-11-07', '4.3 Traffic status', 'stg_frequentation',
 'Stations classified by traffic pattern: a no traffic 2015-2024 (16), b new since 2019 (33), c no traffic in 2024 (61), d zero in 2019 and 2024 (19), e 2019 base under 1,000 (199), f regular (2,693).',
 'New stations carry 17.7 M passengers in 2024; national growth is 12.3% with all stations vs 11.6% on regular stations only; IDF growth rises from 7.3% to 8.3% once the new T11/T13 stations get their region.',
 'Station-level growth rates are undefined or unstable for a-e; excluding these stations from aggregates would understate network growth.',
 'Station-level growth: regular stations only. Aggregate growth (national, region, type, department): ratio of sums over all stations. Absolute change: all stations. The 1,000 threshold is a judgement call.',
 'Decided'),
(14, DATE '2026-11-07', '4.4 Single-year spikes', 'v_passengers_long',
 '23 station-years differ from both neighbouring years by a factor above 3 (neighbours at least 1,000): 20 in 2020 (Covid), plus Le Bosquet 2017, Vif 2022 and Le Teil 2023.',
 'Our metrics use 2015, 2019, 2022 and 2024; only Vif 2022 enters a metric (its 2022-2024 change would show -79%).',
 'No effect on totals; one wrong station-level momentum value.',
 'Keep all published values; flag the spikes; annotate Covid on the trend chart; exclude Vif from the 2022-2024 momentum.',
 'Decided'),
(15, DATE '2026-11-07', '5 Long table', 'fct_station_year',
 'Built the station x year fact table (passengers only) with Covid-year and spike flags.',
 '30,210 rows = 3,021 stations x 10 years; (uic, year) is unique; yearly totals identical to the wide table for all 10 years.',
 'Feeds the 2015-2024 trend chart; station attributes stay in the station table to avoid repeating them.',
 'Covid years = 2020 and 2021 (flag only, no rows removed); ratios such as growth and index are computed after aggregation in Tableau, never stored per row.',
 'Fixed'),
(16, DATE '2026-11-07', '5 Baseline choice', 'fct_station_year',
 '2018 is abnormally low: index 0.982 vs 1.000 in 2017 and 2019, with a drop in almost every region followed by a rebound in 2019 (spring 2018 rail strikes, 3 April - 28 June).',
 '77% of stations above 10,000 passengers declined in 2018; growth to 2024 is +14.4% from 2018, +12.3% from 2019, +13.0% from the 2017-2019 average.',
 'Using 2018 as the base would overstate growth, especially in the regions.',
 'Keep 2019 as the pre-Covid baseline; use the 2017-2019 average as a sensitivity check; annotate the 2018 strikes and Covid on the trend chart.',
 'Decided'),
(17, DATE '2026-11-07', '6.1 Department', 'int_station_admin',
 'Department taken from the postal code for all stations; names come from a code-to-name lookup built from the matched stations. Cross-check with the reference list: 9 disagreements (7 stations on a department border, 2 errors).',
 'Postal code covers 3,021 stations vs 2,983 for the reference list. Errors: the Pont-sur-Yonne postal code points to Calvados (fixed to Yonne); the reference list places Grasse in Marseille (see the coordinates step).',
 'Departments without a national station: 31 of 94 (33 if departments came from the reference list).',
 'Postal code is the primary source; manual corrections are stored in table fix_department with their reason.',
 'Fixed'),
(18, DATE '2026-11-07', '6.1 Region', 'int_station_admin',
 '11 stations had no SNCF region; filled with the most common region of the other stations in the same department.',
 'All 11 are new or small stations, e.g. the T11 and RER E stations, now assigned to DEX GIF.',
 'Brings the 14.1 M passengers of the new T11/T13 stations into the IDF growth figures.',
 'Imputation flagged in column region_imputed; category set to Unknown for the 70 stations without A/B/C.',
 'Fixed'),
(19, DATE '2026-11-07', '6.2 Coordinates', 'int_station_geo',
 'Coordinates attached by UIC; 7 unmatched stations recovered through the reference list (6 same station under another UIC, 1 proxy: Paris Montparnasse uses Montparnasse-Pasteur); Grasse coordinates removed (placed in Marseille).',
 'Coordinates now cover 98.9% of 2024 passengers in France; after the fixes no station lies more than 104 km from its department centre.',
 'Montparnasse (69 M) and CDG 2 (17 M) now appear on the maps.',
 'Matches stored in fix_geo_match, removals in fix_geo_remove; column geo_source records where each coordinate comes from.',
 'Fixed'),
(20, DATE '2026-11-07', '6.2 Coordinates', 'int_station_geo',
 '30 stations in France still have no coordinates: whole lines are absent from the reference list (T4 branch in Seine-Saint-Denis, Arcachon branch, Cannes-Grasse, Thionville-Apach), plus 2 national stations: Marne-la-Vallee Chessy and Trouville-Deauville.',
 '34.5 M passengers in 2024 (1.1%); not random: concentrated in Seine-Saint-Denis and on the Gironde coast.',
 'They count in all totals and department figures but are missing from point maps and from distance calculations.',
 'List them in the limitations; if external data is allowed, add their coordinates from the SNCF open-data station list with the source noted.',
 'Open'),
(21, DATE '2026-11-07', '6.2 Check of current team file', 'Case2_SNCF_data_clean.xlsx',
 'Current clean file: Marne-la-Vallee Chessy has the coordinates of the village of Chessy in the Rhone (name-based match), Grasse is placed in Marseille, Trouville-Deauville has no coordinates.',
 'Chessy point at 45.89 N, 4.62 E (near Lyon) instead of east of Paris; Grasse at 43.30 N, 5.38 E (Marseille).',
 'Two stations are drawn in the wrong place on the maps; distances to the nearest national station are affected.',
 'Use the UIC-based coordinates from the new pipeline; add coordinates for Chessy and Trouville-Deauville from the SNCF station list if external data is allowed, otherwise state it in the limitations.',
 'Open'),
(22, DATE '2026-11-07', '7 Station table', 'dim_station',
 'Final one-row-per-station table with department, region, category, coordinates and growth metrics. Rule refined: a station is "new" if it had no traffic in 2018 or 2019 (no full-year 2019 base).',
 'Nimes Pont-du-Gard opened in December 2019 (15 K passengers in 2019) and showed +7,600%; it is now classed as new. National growth: +12.2% as a ratio of sums, vs +47% as the average of station growth rates and +28% as the median.',
 'Averaging station growth rates would overstate network growth about fourfold.',
 'Growth metrics stored per station only where valid (NULL otherwise); every aggregate growth in Tableau is computed as SUM(2024) / SUM(2019) - 1.',
 'Fixed'),
(23, DATE '2026-11-07', '6.2 Coordinates (external)', 'fix_geo_coords',
 'Coordinates added for the 2 national stations missing from the reference list, from the official SNCF Gares de voyageurs dataset (data.gouv.fr).',
 'Marne-la-Vallee Chessy 48.869856, 2.78272 (UIC 87111849); Trouville-Deauville 49.360005, 0.084167 (UIC 87444372). The same dataset lists the village of Chessy (Rhone, UIC 87721761) at 45.885545, 4.6222625: the point used in our current file.',
 'All 100 national stations now have coordinates; distances to the nearest national station become reliable east of Paris and on the Calvados coast.',
 'Cite the source in the report; confirm with the team that this external source is acceptable.',
 'Fixed'),
(24, DATE '2026-11-07', '7 Access metric', 'mart_station',
 'Straight-line (great-circle) distance from each station to the nearest national (A) station, plus the name of that station.',
 '2,991 stations with a distance (29 without coordinates and Monaco excluded); max 120 km (Aumont-Aubrac, Lozere). Department top 20 matches Slide 4 except Loire (51.6 km) now in the list and Indre (48.8 km) out; ranking must use unrounded averages (Indre and Pyrenees-Orientales both round to 49 km).',
 'The wrong Chessy point near Lyon had cut Loire distances to 46 km and hidden it from the Slide 4 ranking.',
 'Department average = simple mean over stations (territorial coverage); passenger-weighted mean kept as a secondary view; distance is a proxy for travel time (limitation).',
 'Fixed');

UPDATE cleaning_log SET status = 'Fixed' WHERE log_id = 4;
UPDATE cleaning_log SET status = 'Fixed in new pipeline' WHERE log_id = 21;

-- =====================================================================
-- STEP 2a - Ridership: types, names, postal codes
-- =====================================================================
CREATE OR REPLACE TABLE stg_frequentation AS
SELECT

    CAST(TRY_CAST(code_uic_complet AS BIGINT) AS VARCHAR)            AS uic,
    TRIM(nom_gare)                                                   AS station_name,
    LPAD(CAST(TRY_CAST(code_postal AS INTEGER) AS VARCHAR), 5, '0')  AS postal_code,

    
    NULLIF(TRIM(direction_regionale_gares), '')  AS sncf_region,
    NULLIF(TRIM(segmentation_drg), '')           AS station_category,
    NULLIF(TRIM(segmentation_marketing), '')     AS station_segment,

    
    TRY_CAST(non_voyageurs AS DOUBLE)            AS non_traveller_share,
    TRY_CAST(total_voyageurs_2015 AS BIGINT)     AS passengers_2015,
    TRY_CAST(total_voyageurs_2016 AS BIGINT)     AS passengers_2016,
    TRY_CAST(totalvoyageurs2017   AS BIGINT)     AS passengers_2017,
    TRY_CAST(total_voyageurs_2018 AS BIGINT)     AS passengers_2018,
    TRY_CAST(total_voyageurs_2019 AS BIGINT)     AS passengers_2019,
    TRY_CAST(total_voyageurs_2020 AS BIGINT)     AS passengers_2020,
    TRY_CAST(total_voyageurs_2021 AS BIGINT)     AS passengers_2021,
    TRY_CAST(total_voyageurs_2022 AS BIGINT)     AS passengers_2022,
    TRY_CAST(total_voyageurs_2023 AS BIGINT)     AS passengers_2023,
    TRY_CAST(total_voyageurs_2024 AS BIGINT)     AS passengers_2024,
    TRY_CAST(total_voyageurs_non_voyageurs_2015 AS BIGINT) AS visitors_2015,
    TRY_CAST(total_voyageurs_non_voyageurs_2016 AS BIGINT) AS visitors_2016,
    TRY_CAST(total_voyageurs_non_voyageurs_2017 AS BIGINT) AS visitors_2017,
    TRY_CAST(total_voyageurs_non_voyageurs_2018 AS BIGINT) AS visitors_2018,
    TRY_CAST(total_voyageurs_non_voyageurs_2019 AS BIGINT) AS visitors_2019,
    TRY_CAST(total_voyageurs_non_voyageurs_2020 AS BIGINT) AS visitors_2020,
    TRY_CAST(total_voyageurs_non_voyageurs_2021 AS BIGINT) AS visitors_2021,
    TRY_CAST(total_voyageurs_non_voyageurs_2022 AS BIGINT) AS visitors_2022,
    TRY_CAST(total_voyageurs_non_voyageurs_2023 AS BIGINT) AS visitors_2023,
    TRY_CAST(total_voyageurs_non_voyageurs_2024 AS BIGINT) AS visitors_2024
FROM raw_frequentation;

-- =====================================================================
-- STEP 2b - Station reference list: types (still one row per station x line)
-- =====================================================================
CREATE OR REPLACE TABLE stg_liste_gares AS
SELECT
    CAST(TRY_CAST(code_uic AS BIGINT) AS VARCHAR)  AS uic,
    TRIM(libelle)                                  AS station_name,
    TRIM(commune)                                  AS commune,
    TRIM(departemen)                               AS department_name,
    TRIM(voyageurs) = 'O'                          AS is_passenger_station,
    TRIM(fret) = 'O'                               AS is_freight_point,
    TRIM(code_ligne)                               AS line_code,
    TRY_CAST(y_wgs84 AS DOUBLE)                    AS latitude,
    TRY_CAST(x_wgs84 AS DOUBLE)                    AS longitude,
    TRY_CAST(x_l93 AS DOUBLE)                      AS x_lambert93_m,
    TRY_CAST(y_l93 AS DOUBLE)                      AS y_lambert93_m
FROM raw_liste_gares;

-- =====================================================================
-- STEP 3 - Reference list aggregated to one row per UIC
-- =====================================================================
CREATE OR REPLACE TABLE stg_gares AS
SELECT
    uic,
    MIN(station_name)                                      AS station_name,
    STRING_AGG(DISTINCT commune, ' | ' ORDER BY commune)   AS communes,
    MIN(department_name)                                   AS department_name,
    BOOL_OR(is_passenger_station)                          AS is_passenger_station,
    BOOL_OR(is_freight_point)                              AS is_freight_point,
    COUNT(DISTINCT line_code)                              AS n_lines,
    AVG(latitude)                                          AS latitude,
    AVG(longitude)                                         AS longitude,
    AVG(x_lambert93_m)                                     AS x_lambert93_m,
    AVG(y_lambert93_m)                                     AS y_lambert93_m,
    ROUND(SQRT(POWER(MAX(x_lambert93_m) - MIN(x_lambert93_m), 2)
             + POWER(MAX(y_lambert93_m) - MIN(y_lambert93_m), 2)))  AS coord_spread_m,
    COUNT(*)                                               AS n_source_rows
FROM stg_liste_gares
WHERE NOT (uic = '87783621' AND department_name = 'MARNE')
GROUP BY uic;

-- =====================================================================
-- STEP 4 - Long view used for the validity checks
-- =====================================================================
CREATE OR REPLACE VIEW v_passengers_long AS
SELECT uic,
       station_name,
       CAST(RIGHT(year_col, 4) AS INTEGER) AS year,
       passengers
FROM (
    UNPIVOT (SELECT uic, station_name, COLUMNS('^passengers_') FROM stg_frequentation)
    ON COLUMNS('^passengers_')
    INTO NAME year_col VALUE passengers
);

-- =====================================================================
-- STEP 5 - Fact table: one row per station and year, with flags
-- =====================================================================
CREATE OR REPLACE TABLE fct_station_year AS
WITH long AS (
    SELECT uic,
           CAST(RIGHT(year_col, 4) AS INTEGER) AS year,
           passengers
    FROM (
        UNPIVOT (SELECT uic, COLUMNS('^passengers_') FROM stg_frequentation)
        ON COLUMNS('^passengers_')
        INTO NAME year_col VALUE passengers
    )
),
with_neighbours AS (
    SELECT *,
           LAG(passengers)  OVER (PARTITION BY uic ORDER BY year) AS prev_year,
           LEAD(passengers) OVER (PARTITION BY uic ORDER BY year) AS next_year
    FROM long
)
SELECT
    uic,
    year,
    passengers,
    year IN (2020, 2021) AS is_covid_year,
    COALESCE(
        prev_year >= 1000 AND next_year >= 1000
        AND (passengers > 3 * GREATEST(prev_year, next_year)
             OR passengers * 3 < LEAST(prev_year, next_year)),
        FALSE) AS is_spike
FROM with_neighbours;

-- =====================================================================
-- STEP 6a - Department (postal code), department names, region fill
-- =====================================================================
CREATE OR REPLACE TABLE lkp_department AS
SELECT LEFT(f.postal_code, 2)  AS department_code,
       MODE(g.department_name) AS department_name,
       COUNT(*)                AS n_stations_used
FROM stg_frequentation f
JOIN stg_gares g USING (uic)
GROUP BY LEFT(f.postal_code, 2);

CREATE OR REPLACE TABLE fix_department (
    uic             VARCHAR PRIMARY KEY,
    department_code VARCHAR,
    reason          VARCHAR
);
INSERT INTO fix_department VALUES
('87683136', '89', 'Pont-sur-Yonne: postal code 14130 points to Calvados; the station is in Yonne (reference list, commune Pont-sur-Yonne)');

CREATE OR REPLACE TABLE int_station_admin AS
WITH base AS (
    SELECT f.uic,
           f.station_name,
           f.postal_code,
           COALESCE(fx.department_code, LEFT(f.postal_code, 2)) AS department_code,
           f.sncf_region,
           f.station_category,
           f.station_segment
    FROM stg_frequentation f
    LEFT JOIN fix_department fx USING (uic)
),
region_by_department AS (
    SELECT department_code, MODE(sncf_region) AS region_mode
    FROM base
    WHERE sncf_region IS NOT NULL
    GROUP BY department_code
)
SELECT b.uic,
       b.station_name,
       b.postal_code,
       b.department_code,
       d.department_name,
       b.department_code = '98'                 AS is_outside_france,
       COALESCE(b.sncf_region, r.region_mode)   AS sncf_region,
       b.sncf_region IS NULL                    AS region_imputed,
       COALESCE(b.station_category, 'Unknown')  AS station_category,
       COALESCE(b.station_segment, 'Unknown')   AS station_segment
FROM base b
LEFT JOIN lkp_department d       USING (department_code)
LEFT JOIN region_by_department r USING (department_code);

-- =====================================================================
-- STEP 6b - Coordinates: UIC match, manual matches, removals
-- =====================================================================
CREATE OR REPLACE TABLE fix_geo_match (
    uic            VARCHAR PRIMARY KEY,  
    reference_uic  VARCHAR,               
    method         VARCHAR,               
    reason         VARCHAR
);
INSERT INTO fix_geo_match VALUES
('87391003', '87391011', 'Proxy',        'Paris Montparnasse: not in the reference list; uses Paris-Montparnasse-Pasteur, part of the same station complex'),
('87271494', '87001479', 'Same station', 'CDG 2 TGV: listed as Roissy-Aeroport-Charles-de-Gaulle 2-TGV (RER) under another UIC'),
('87474064', '87474791', 'Same station', 'Chateaulin: same name, same department, different UIC'),
('87701532', '87484063', 'Same station', 'Trelaze: same name, same department, different UIC'),
('87590299', '87520299', 'Same station', 'Nice Pont Michel: same name, same department, different UIC'),
('87565143', '87561143', 'Same station', 'Fontanil - Lycee de Drap: same name, same department, different UIC'),
('87691949', '87517912', 'Same station', 'Bidos: same name, same department, different UIC');

CREATE OR REPLACE TABLE fix_geo_remove (
    uic     VARCHAR PRIMARY KEY,
    reason  VARCHAR
);
INSERT INTO fix_geo_remove VALUES
('87757724', 'Grasse: reference coordinates point to Marseille (commune MARSEILLE), about 160 km away');

CREATE OR REPLACE TABLE int_station_geo AS
SELECT
    a.uic,
    CASE WHEN rm.uic IS NOT NULL THEN NULL ELSE g.latitude      END AS latitude,
    CASE WHEN rm.uic IS NOT NULL THEN NULL ELSE g.longitude     END AS longitude,
    CASE WHEN rm.uic IS NOT NULL THEN NULL ELSE g.x_lambert93_m END AS x_lambert93_m,
    CASE WHEN rm.uic IS NOT NULL THEN NULL ELSE g.y_lambert93_m END AS y_lambert93_m,
    g.n_lines,
    g.is_passenger_station AS reference_passenger_flag,
    CASE
        WHEN rm.uic IS NOT NULL        THEN 'Removed: wrong in source'
        WHEN fm.method = 'Proxy'       THEN 'Proxy station'
        WHEN fm.method = 'Same station' THEN 'Manual match'
        WHEN g.uic IS NOT NULL         THEN 'UIC match'
        ELSE 'Missing'
    END AS geo_source
FROM int_station_admin a
LEFT JOIN fix_geo_match  fm ON fm.uic = a.uic
LEFT JOIN stg_gares      g  ON g.uic  = COALESCE(fm.reference_uic, a.uic)
LEFT JOIN fix_geo_remove rm ON rm.uic = a.uic;

-- =====================================================================
-- STEP 6c - Coordinates for the 2 national stations missing from the reference list (external source)
-- =====================================================================
CREATE OR REPLACE TABLE fix_geo_coords (
    uic        VARCHAR PRIMARY KEY,
    latitude   DOUBLE,
    longitude  DOUBLE,
    source     VARCHAR
);

INSERT INTO fix_geo_coords VALUES
('87111849', 48.869856, 2.78272,  'SNCF Gares de voyageurs (data.gouv.fr), looked up 2026-11-07'),
('87444372', 49.360005, 0.084167, 'SNCF Gares de voyageurs (data.gouv.fr), looked up 2026-11-07');

UPDATE int_station_geo AS g
SET latitude   = f.latitude,
    longitude  = f.longitude,
    geo_source = 'Manual coordinates (external source)'
FROM fix_geo_coords AS f
WHERE g.uic = f.uic;

-- =====================================================================
-- STEP 7a - Final station table with growth metrics
-- =====================================================================
CREATE OR REPLACE TABLE dim_station AS
WITH spikes AS (
    SELECT uic,
           BOOL_OR(is_spike AND year = 2022) AS spike_2022,
           BOOL_OR(is_spike)                 AS has_spike
    FROM fct_station_year
    GROUP BY uic
),
base AS (
    SELECT
        a.uic, a.station_name, a.postal_code,
        a.department_code, a.department_name, a.sncf_region, a.region_imputed,
        a.station_category, a.station_segment, a.is_outside_france,
        g.latitude, g.longitude, g.x_lambert93_m, g.y_lambert93_m, g.geo_source, g.n_lines,
        f.non_traveller_share,
        f.passengers_2015, f.passengers_2018, f.passengers_2019, f.passengers_2022, f.passengers_2024,
        s.spike_2022, s.has_spike,
        CASE
            WHEN GREATEST(f.passengers_2015, f.passengers_2016, f.passengers_2017, f.passengers_2018, f.passengers_2019,
                          f.passengers_2020, f.passengers_2021, f.passengers_2022, f.passengers_2023, f.passengers_2024) = 0
                                                                  THEN 'a. No traffic 2015-2024'
            WHEN (f.passengers_2018 = 0 OR f.passengers_2019 = 0)
                 AND f.passengers_2024 > 0                    THEN 'b. New since 2019 (no full-year 2019 base)'
            WHEN f.passengers_2019 > 0 AND f.passengers_2024 = 0  THEN 'c. No traffic in 2024'
            WHEN f.passengers_2019 = 0 AND f.passengers_2024 = 0  THEN 'd. Zero in 2019 and 2024'
            WHEN f.passengers_2019 < 1000                         THEN 'e. Small 2019 base (< 1,000)'
            ELSE 'f. Regular'
        END AS traffic_status
    FROM int_station_admin a
    JOIN int_station_geo   g USING (uic)
    JOIN stg_frequentation f USING (uic)
    JOIN spikes            s USING (uic)
)
SELECT *,
    passengers_2024 - passengers_2019 AS abs_change_2019_2024,
    CASE WHEN traffic_status = 'f. Regular'
         THEN passengers_2024 / passengers_2019 - 1 END AS growth_2019_2024,
    CASE WHEN passengers_2022 >= 1000 AND passengers_2024 > 0 AND NOT spike_2022
         THEN passengers_2024 / passengers_2022 - 1 END AS growth_2022_2024,
    CASE WHEN passengers_2015 >= 1000 AND passengers_2019 >= 1000
         THEN POWER(passengers_2019 / passengers_2015, 1.0 / 4) - 1 END AS cagr_2015_2019
FROM base;

-- =====================================================================
-- STEP 7b - Distance to the nearest national (A) station; exported station table
-- =====================================================================
CREATE OR REPLACE TABLE int_station_access AS
WITH stations AS (
    SELECT uic, station_name, latitude, longitude
    FROM dim_station
    WHERE latitude IS NOT NULL AND NOT is_outside_france
),
national AS (
    SELECT uic AS national_uic, station_name AS national_name, latitude AS lat_n, longitude AS lon_n
    FROM dim_station
    WHERE station_category = 'A' AND latitude IS NOT NULL
),
pairs AS (
    SELECT s.uic, n.national_name,
           2 * 6371 * ASIN(SQRT(
               POWER(SIN(RADIANS(n.lat_n - s.latitude) / 2), 2)
             + COS(RADIANS(s.latitude)) * COS(RADIANS(n.lat_n))
             * POWER(SIN(RADIANS(n.lon_n - s.longitude) / 2), 2)
           )) AS km
    FROM stations s
    CROSS JOIN national n
)
SELECT uic,
       ARG_MIN(national_name, km) AS nearest_national_station,
       MIN(km)                    AS km_to_national_station
FROM pairs
GROUP BY uic;

CREATE OR REPLACE TABLE mart_station AS
SELECT d.*,
       a.nearest_national_station,
       ROUND(a.km_to_national_station, 1) AS km_to_national_station
FROM dim_station d
LEFT JOIN int_station_access a USING (uic);

-- =====================================================================
-- STEP 9a - Quality checks (every row must show passed = true)
-- =====================================================================
CREATE OR REPLACE VIEW v_quality_checks AS
SELECT 'mart_station: one row per station' AS check_name,
       (SELECT COUNT(*) FROM mart_station) = (SELECT COUNT(DISTINCT uic) FROM mart_station) AS passed
UNION ALL
SELECT 'mart_station: all 3,021 source stations kept',
       (SELECT COUNT(*) FROM mart_station) = (SELECT COUNT(*) FROM raw_frequentation)
UNION ALL
SELECT 'mart_station: 2024 passengers equal the raw file',
       (SELECT SUM(passengers_2024) FROM mart_station)
     = (SELECT SUM(CAST(total_voyageurs_2024 AS BIGINT)) FROM raw_frequentation)
UNION ALL
SELECT 'fct_station_year: one row per station and year',
       (SELECT COUNT(*) FROM fct_station_year) = (SELECT COUNT(DISTINCT (uic, year)) FROM fct_station_year)
UNION ALL
SELECT 'fct_station_year: every station exists in mart_station',
       (SELECT COUNT(*) FROM fct_station_year WHERE uic NOT IN (SELECT uic FROM mart_station)) = 0
UNION ALL
SELECT 'fct_station_year: 2019 and 2024 totals equal mart_station',
       (SELECT SUM(passengers) FROM fct_station_year WHERE year = 2019) = (SELECT SUM(passengers_2019) FROM mart_station)
   AND (SELECT SUM(passengers) FROM fct_station_year WHERE year = 2024) = (SELECT SUM(passengers_2024) FROM mart_station)
UNION ALL
SELECT 'Every French station has a department and a region',
       (SELECT COUNT(*) FROM mart_station
        WHERE NOT is_outside_france AND (department_name IS NULL OR sncf_region IS NULL)) = 0
UNION ALL
SELECT 'All 100 national stations have coordinates',
       (SELECT COUNT(*) FROM mart_station WHERE station_category = 'A' AND latitude IS NULL) = 0
UNION ALL
SELECT 'Station growth rates only for regular stations',
       (SELECT COUNT(*) FROM mart_station
        WHERE growth_2019_2024 IS NOT NULL AND traffic_status <> 'f. Regular') = 0
UNION ALL
SELECT 'Departments without a national station = 31',
       (SELECT COUNT(*) FROM (
            SELECT department_code FROM mart_station
            WHERE NOT is_outside_france
            GROUP BY department_code
            HAVING NOT BOOL_OR(station_category = 'A'))) = 31;


SELECT * FROM v_quality_checks;

-- =====================================================================
-- STEP 9b - Export for Tableau
-- =====================================================================
COPY (SELECT * EXCLUDE (x_lambert93_m, y_lambert93_m) FROM mart_station ORDER BY uic)
TO 'case2_stations.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM fct_station_year ORDER BY uic, year)
TO 'case2_station_year.csv' (HEADER, DELIMITER ',');

COPY (SELECT * FROM cleaning_log ORDER BY log_id)
TO 'case2_cleaning_log.csv' (HEADER, DELIMITER ',');
