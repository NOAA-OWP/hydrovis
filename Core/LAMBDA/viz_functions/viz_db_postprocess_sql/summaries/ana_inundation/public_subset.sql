DROP TABLE IF EXISTS publish.ana_inundation_public;

SELECT
    inun.feature_id_str,
    inun.geom,
    inun.streamflow_cfs,
    inun.reference_time,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.ana_inundation_public
FROM publish.ana_inundation as inun
JOIN derived.channels_conus channels 
    ON channels.feature_id = inun.feature_id 
    AND channels.public_fim_domain = TRUE;