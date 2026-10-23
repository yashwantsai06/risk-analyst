-- 03_kpi_views.sql
-- Reporting layer. Resolution time is only measured on requests with a
-- trustworthy duration (dq_flag = 'ok'); zero-duration closures are
-- counted separately because they are auto-closures, not real fixes.

DROP VIEW IF EXISTS v_resolution_band;
CREATE VIEW v_resolution_band AS
SELECT *,
    CASE
        WHEN dq_flag <> 'ok'         THEN NULL
        WHEN hours_to_close < 4      THEN 0   -- under 4 hours
        WHEN hours_to_close < 24     THEN 1   -- same day
        WHEN hours_to_close < 48     THEN 2   -- within 48h SLA
        WHEN hours_to_close < 168    THEN 3   -- within 7 days
        WHEN hours_to_close < 720    THEN 4   -- within 30 days
        ELSE 5                                -- over 30 days
    END AS band
FROM fact_request;

-- Weekly cube that feeds the dashboard filters (agency x channel x borough).
DROP VIEW IF EXISTS v_cube_weekly;
CREATE VIEW v_cube_weekly AS
SELECT week_start, agency_group, channel, borough,
       COUNT(*)                                   AS n,
       SUM(is_closed)                             AS closed,
       SUM(dq_flag = 'zero_duration')             AS zero_dur,
       SUM(band = 0) AS b0, SUM(band = 1) AS b1, SUM(band = 2) AS b2,
       SUM(band = 3) AS b3, SUM(band = 4) AS b4, SUM(band = 5) AS b5
FROM v_resolution_band
GROUP BY 1, 2, 3, 4;

-- When do requests arrive? Day-of-week x hour.
DROP VIEW IF EXISTS v_cube_heatmap;
CREATE VIEW v_cube_heatmap AS
SELECT dow, hour, agency_group, channel, COUNT(*) AS n
FROM fact_request
GROUP BY 1, 2, 3, 4;

-- Complaint mix with resolution profile.
DROP VIEW IF EXISTS v_cube_complaint;
CREATE VIEW v_cube_complaint AS
SELECT complaint_group, agency_group, channel,
       COUNT(*) AS n,
       SUM(band = 0) AS b0, SUM(band = 1) AS b1, SUM(band = 2) AS b2,
       SUM(band = 3) AS b3, SUM(band = 4) AS b4, SUM(band = 5) AS b5
FROM v_resolution_band
GROUP BY 1, 2, 3;

-- Data-quality summary for the case study.
DROP VIEW IF EXISTS v_data_quality;
CREATE VIEW v_data_quality AS
SELECT dq_flag, is_closed, COUNT(*) AS n
FROM fact_request
GROUP BY 1, 2;

-- Exact medians for headline findings (SQLite has no MEDIAN, so use row ranks).
DROP VIEW IF EXISTS v_median_by_agency;
CREATE VIEW v_median_by_agency AS
WITH ok AS (
    SELECT agency_group, hours_to_close,
           ROW_NUMBER() OVER (PARTITION BY agency_group ORDER BY hours_to_close) AS rn,
           COUNT(*)     OVER (PARTITION BY agency_group)                         AS cnt
    FROM fact_request
    WHERE dq_flag = 'ok'
)
SELECT agency_group, cnt AS measured, ROUND(AVG(hours_to_close), 1) AS median_hours
FROM ok
WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
GROUP BY agency_group;

DROP VIEW IF EXISTS v_median_by_channel;
CREATE VIEW v_median_by_channel AS
WITH ok AS (
    SELECT channel, hours_to_close,
           ROW_NUMBER() OVER (PARTITION BY channel ORDER BY hours_to_close) AS rn,
           COUNT(*)     OVER (PARTITION BY channel)                         AS cnt
    FROM fact_request
    WHERE dq_flag = 'ok'
)
SELECT channel, cnt AS measured, ROUND(AVG(hours_to_close), 1) AS median_hours
FROM ok
WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
GROUP BY channel;
