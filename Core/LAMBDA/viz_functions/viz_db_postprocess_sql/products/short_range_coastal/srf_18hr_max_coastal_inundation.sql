DROP TABLE IF EXISTS publish.srf_18hr_max_coastal_inundation;

WITH coastal_inundation AS (
    SELECT * FROM ingest.srf_18hr_max_coastal_inundation_pacific
    UNION
    SELECT * FROM ingest.srf_18hr_max_coastal_inundation_atlgulf
)
SELECT
    coastal_inundation.*,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.srf_18hr_max_coastal_inundation
FROM coastal_inundation;