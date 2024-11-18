DROP TABLE IF EXISTS publish.mrf_gfs_max_inundation_5day_public;

SELECT
    inun.feature_id_str,
    inun.geom,
    inun.streamflow_cfs,
    inun.reference_time,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.mrf_gfs_max_inundation_5day_public
FROM publish.mrf_gfs_max_inundation_5day as inun
JOIN derived.channels_conus AS channels 
    ON inun.feature_id = channels.feature_id 
    AND public_fim_domain = True;