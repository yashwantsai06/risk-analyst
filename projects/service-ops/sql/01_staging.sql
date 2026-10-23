-- 01_staging.sql
-- Raw NYC 311 extract, loaded as text exactly as downloaded.
-- One row per service request, Apr–Sep 2026.

DROP TABLE IF EXISTS stg_requests;
CREATE TABLE stg_requests (
    unique_key              TEXT,
    created_date            TEXT,
    closed_date             TEXT,
    agency                  TEXT,
    complaint_type          TEXT,
    borough                 TEXT,
    open_data_channel_type  TEXT,
    status                  TEXT
);
