-- We'll temporarily increase work_mem to 512MB, to help with performance on PostGIS spatial joins (default is 4MB)
SET work_mem TO '1024MB';
DROP TABLE IF EXISTS publish.mrf_nbm_max_inundation_5day_public;

SELECT
    inun.feature_id_str,
    ST_Intersection(inun.geom, fim_domain.geom) as geom,
    inun.streamflow_cfs,
    inun.reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.mrf_nbm_max_inundation_5day_public
FROM publish.mrf_nbm_max_inundation_5day as inun
JOIN derived.channels_conus channels 
    ON channels.feature_id = inun.feature_id 
    AND channels.public_fim_domain = TRUE
JOIN derived.public_fim_domain AS fim_domain ON TRUE;

INSERT INTO publish.mrf_nbm_max_inundation_5day_public (
    reference_time, 
    update_time
) VALUES (
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), 
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC')
);