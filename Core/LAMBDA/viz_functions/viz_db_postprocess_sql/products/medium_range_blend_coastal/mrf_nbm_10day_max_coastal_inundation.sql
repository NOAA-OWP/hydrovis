DROP TABLE IF EXISTS publish.mrf_nbm_10day_max_coastal_inundation;

WITH coastal_inundation AS (
    SELECT * FROM ingest.mrf_nbm_10day_max_coastal_inundation_pacific
    UNION
    SELECT * FROM ingest.mrf_nbm_10day_max_coastal_inundation_atlgulf
)
SELECT
    coastal_inundation.*,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.mrf_nbm_10day_max_coastal_inundation
FROM coastal_inundation;