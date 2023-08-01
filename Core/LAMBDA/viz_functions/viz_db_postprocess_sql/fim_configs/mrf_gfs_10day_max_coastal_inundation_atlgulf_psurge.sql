INSERT INTO ingest.mrf_gfs_10day_max_coastal_inundation_atlgulf_psurge (
	geom, reference_time, huc8)
	VALUES (NULL, to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), '-9999');

DROP TABLE IF EXISTS publish.mrf_gfs_10day_max_coastal_inundation_atlgulf_psurge;

SELECT
    inundation.*,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.mrf_gfs_10day_max_coastal_inundation_atlgulf_psurge
FROM ingest.mrf_gfs_10day_max_coastal_inundation_atlgulf_psurge AS inundation;