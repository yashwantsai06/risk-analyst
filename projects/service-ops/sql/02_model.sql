-- 02_model.sql
-- Star schema: one fact row per request, four small dimensions.
-- Cleaning rules live here so every report uses the same definitions.

-- ---------- dimensions ----------

DROP TABLE IF EXISTS dim_agency;
CREATE TABLE dim_agency AS
WITH ranked AS (
    SELECT agency, COUNT(*) AS n,
           ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rnk
    FROM stg_requests
    GROUP BY agency
)
SELECT agency,
       n AS requests,
       -- keep the 8 busiest agencies, roll the long tail into "Other"
       CASE WHEN rnk <= 8 THEN agency ELSE 'Other' END AS agency_group
FROM ranked;

DROP TABLE IF EXISTS dim_channel;
CREATE TABLE dim_channel AS
SELECT DISTINCT
       open_data_channel_type AS channel_raw,
       CASE UPPER(COALESCE(open_data_channel_type, ''))
            WHEN 'PHONE'   THEN 'Phone'
            WHEN 'ONLINE'  THEN 'Online'
            WHEN 'MOBILE'  THEN 'Mobile app'
            WHEN 'UNKNOWN' THEN 'Unknown'
            WHEN ''        THEN 'Unknown'
            ELSE 'Other'
       END AS channel
FROM stg_requests;

DROP TABLE IF EXISTS dim_borough;
CREATE TABLE dim_borough AS
SELECT DISTINCT
       borough AS borough_raw,
       CASE UPPER(COALESCE(borough, ''))
            WHEN 'MANHATTAN'     THEN 'Manhattan'
            WHEN 'BROOKLYN'      THEN 'Brooklyn'
            WHEN 'QUEENS'        THEN 'Queens'
            WHEN 'BRONX'         THEN 'Bronx'
            WHEN 'STATEN ISLAND' THEN 'Staten Island'
            ELSE 'Unspecified'
       END AS borough
FROM stg_requests;

DROP TABLE IF EXISTS dim_complaint;
CREATE TABLE dim_complaint AS
WITH ranked AS (
    SELECT complaint_type, COUNT(*) AS n,
           ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rnk
    FROM stg_requests
    GROUP BY complaint_type
)
SELECT complaint_type,
       n AS requests,
       CASE WHEN rnk <= 25 THEN complaint_type ELSE 'Other' END AS complaint_group
FROM ranked;

-- ---------- fact ----------

DROP TABLE IF EXISTS fact_request;
CREATE TABLE fact_request AS
SELECT
    s.unique_key,
    s.created_date,
    NULLIF(s.closed_date, '')                                   AS closed_date,
    date(s.created_date, 'weekday 0', '-6 days')                AS week_start,   -- Monday
    CAST(strftime('%w', s.created_date) AS INTEGER)             AS dow,          -- 0 = Sunday
    CAST(strftime('%H', s.created_date) AS INTEGER)             AS hour,
    a.agency_group,
    c.channel,
    b.borough,
    k.complaint_group,
    CASE WHEN UPPER(s.status) = 'CLOSED' THEN 1 ELSE 0 END      AS is_closed,
    CASE
        WHEN UPPER(s.status) = 'CLOSED' AND NULLIF(s.closed_date, '') IS NOT NULL
        THEN (julianday(s.closed_date) - julianday(s.created_date)) * 24.0
    END                                                         AS hours_to_close
FROM stg_requests s
JOIN dim_agency    a ON a.agency          = s.agency
JOIN dim_channel   c ON c.channel_raw IS s.open_data_channel_type
JOIN dim_borough   b ON b.borough_raw IS s.borough
JOIN dim_complaint k ON k.complaint_type  = s.complaint_type;

-- Data-quality flags, kept as columns so they can be reported, not silently dropped.
ALTER TABLE fact_request ADD COLUMN dq_flag TEXT;
UPDATE fact_request SET dq_flag =
    CASE
        WHEN is_closed = 0                            THEN 'open'
        WHEN hours_to_close IS NULL                   THEN 'closed_no_date'
        WHEN hours_to_close < 0                       THEN 'closed_before_created'
        WHEN hours_to_close = 0                       THEN 'zero_duration'
        ELSE 'ok'
    END;

CREATE INDEX ix_fact_week ON fact_request (week_start);
