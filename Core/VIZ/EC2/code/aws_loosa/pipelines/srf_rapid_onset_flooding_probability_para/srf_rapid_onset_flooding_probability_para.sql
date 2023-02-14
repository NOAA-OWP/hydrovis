DROP TABLE IF EXISTS publish.srf_rapid_onset_flooding_probability_para;
SELECT 
    channels.strm_order, 
    channels.name, 
    channels.huc6, 
    channels.nwm_vers,
    channels.geom,
    rofp.*,
    rofp.feature_id::TEXT AS feature_id_str,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    ST_LENGTH(channels.geom)*0.000621371 AS reach_length_miles
INTO publish.srf_rapid_onset_flooding_probability_para
FROM derived.channels_conus AS channels
JOIN cache.srf_rapid_onset_flooding_probability_para AS rofp ON channels.feature_id = rofp.feature_id;
DROP TABLE IF EXISTS cache.srf_rapid_onset_flooding_probability_para;