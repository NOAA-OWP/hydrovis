DROP TABLE IF EXISTS publish.ana_inundation_public;

SELECT
    inun.feature_id_str,
    ST_Intersection(inun.geom, fim_domain.geom) as geom,
    inun.streamflow_cfs,
    inun.reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.ana_inundation_public
FROM publish.ana_inundation as inun
JOIN derived.public_fim_domain as fim_domain ON ST_Intersects(inun.geom, fim_domain.geom)