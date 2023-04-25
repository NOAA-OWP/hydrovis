DROP TABLE IF EXISTS publish.srf_high_water_probability;
SELECT 
    channels.strm_order, 
    channels.name, 
    channels.huc6, 
    channels.nwm_vers,
    channels.geom,
    bp.*,
    bp.feature_id::TEXT AS feature_id_str,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time
INTO publish.srf_high_water_probability
FROM derived.channels_conus AS channels
JOIN cache.srf_high_water_probability AS bp ON channels.feature_id = bp.feature_id;
DROP TABLE IF EXISTS cache.srf_high_water_probability;