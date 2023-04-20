DROP TABLE IF EXISTS publish.ana_anomaly_para;
SELECT 
    channels.strm_order, 
    channels.name, 
    channels.huc6, 
    channels.nwm_vers,
    channels.geom,
    anom.*,
    anom.feature_id::TEXT AS feature_id_str,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.ana_anomaly_para
FROM derived.channels_conus AS channels
JOIN cache.ana_anomaly_para AS anom ON channels.feature_id = anom.feature_id;
DROP TABLE IF EXISTS cache.ana_anomaly_para;