DROP TABLE IF EXISTS publish.mrf_5day_coastal_inundation_extent;

WITH coastal_inundation AS (
    SELECT * FROM ingest.mrf_5day_coastal_pacific
    UNION
    SELECT * FROM ingest.mrf_5day_coastal_atlgulf
)
SELECT
    coastal_inundation.*,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.mrf_5day_coastal_inundation_extent
FROM coastal_inundation;