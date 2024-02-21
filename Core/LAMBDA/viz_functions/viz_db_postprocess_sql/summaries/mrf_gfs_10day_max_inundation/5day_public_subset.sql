-- We'll temporarily increase work_mem to 512MB, to help with performance on PostGIS spatial joins (default is 4MB)
SET work_mem TO '512MB';
--
DROP TABLE IF EXISTS publish.mrf_gfs_max_inundation_5day_public;

SELECT
    inun.feature_id_str,
    ST_Intersection(inun.geom, fim_domain.geom) as geom,
    inun.streamflow_cfs,
    inun.reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.mrf_gfs_max_inundation_5day_public
FROM publish.mrf_gfs_max_inundation_5day as inun
JOIN derived.public_fim_domain as fim_domain ON ST_Intersects(inun.geom, fim_domain.geom)