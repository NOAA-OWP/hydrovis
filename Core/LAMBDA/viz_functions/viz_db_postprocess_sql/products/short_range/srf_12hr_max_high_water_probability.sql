DROP TABLE IF EXISTS publish.srf_12hr_max_high_water_prob;
SELECT
    channels.feature_id,
    channels.feature_id::TEXT AS feature_id_str,
    channels.name,
    channels.strm_order,
    channels.huc6,
    channels.state,
	hwp.nwm_vers,
	hwp.reference_time,
    hwp.srf_prob,
    hwp.high_water_threshold,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.srf_12hr_max_high_water_prob
FROM ingest.srf_12hr_max_high_water_prob as hwp
JOIN derived.channels_conus channels ON hwp.feature_id = channels.feature_id;