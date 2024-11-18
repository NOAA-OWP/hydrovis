DROP TABLE IF EXISTS publish.rfc_based_5day_max_inundation_public;

SELECT
    inun.feature_id_str,
    inun.geom,
    inun.streamflow_cfs,
    inun.reference_time,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.rfc_based_5day_max_inundation_public
FROM publish.rfc_based_5day_max_inundation as inun
JOIN derived.channels_conus channels 
    ON channels.feature_id = inun.feature_id 
    AND channels.public_fim_domain = TRUE;

INSERT INTO publish.rfc_based_5day_max_inundation_public (
    reference_time, 
    update_time
) VALUES (
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), 
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC')
);