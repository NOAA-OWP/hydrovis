DROP TABLE IF EXISTS publish.rfc_based_5day_max_inundation_public;

SELECT
    inun.feature_id_str,
    ST_Intersection(inun.geom, fim_domain.geom) as geom,
    inun.streamflow_cfs,
    inun.reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.rfc_based_5day_max_inundation_public
FROM publish.rfc_based_5day_max_inundation as inun
JOIN derived.public_fim_domain as fim_domain ON ST_Intersects(inun.geom, fim_domain.geom);

INSERT INTO publish.rfc_based_5day_max_inundation_public (
    reference_time, 
    update_time
) VALUES (
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), 
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC')
);