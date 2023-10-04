DROP TABLE IF EXISTS publish.srf_12hr_rapid_onset_flooding_probability;
SELECT
    channels.feature_id,
    channels.feature_id::TEXT AS feature_id_str,
    channels.name,
    channels.strm_order,
    channels.huc6,
    channels.state,
	rofp.nwm_vers,
	rofp.reference_time,
    rofp.rapid_onset_prob_1_6,
    rofp.rapid_onset_prob_7_12,
    rofp.rapid_onset_prob_all,
    rofp.high_water_threshold,
    ST_LENGTH(channels.geom)*0.000621371 AS reach_length_miles,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.srf_12hr_rapid_onset_flooding_probability
FROM ingest.srf_12hr_rapid_onset_flooding_probability as rofp
JOIN derived.channels_conus channels ON rofp.feature_id = channels.feature_id;