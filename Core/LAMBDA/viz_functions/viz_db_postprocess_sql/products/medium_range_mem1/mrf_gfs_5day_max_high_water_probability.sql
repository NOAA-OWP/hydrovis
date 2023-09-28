DROP TABLE IF EXISTS publish.mrf_gfs_5day_max_high_water_probability;
SELECT
    channels.feature_id,
    channels.feature_id::TEXT AS feature_id_str,
    channels.name,
    channels.strm_order,
    channels.huc6,
    channels.state,
	hwp.nwm_vers,
	hwp.reference_time,
    hwp.hours_3_to_24,
	hwp.hours_27_to_48,
	hwp.hours_51_to_72,
	hwp.hours_75_to_120,
	hwp.hours_3_to_120,
    hwp.high_water_threshold,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.mrf_gfs_5day_max_high_water_probability
FROM ingest.mrf_gfs_5day_max_high_water_probability as hwp
JOIN derived.channels_conus channels ON hwp.feature_id = channels.feature_id;