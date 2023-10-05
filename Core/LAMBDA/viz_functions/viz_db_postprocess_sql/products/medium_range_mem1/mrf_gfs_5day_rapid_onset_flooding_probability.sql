DROP TABLE IF EXISTS publish.mrf_gfs_5day_rapid_onset_flooding_probability;
SELECT
    channels.feature_id,
    channels.feature_id::TEXT AS feature_id_str,
    channels.name,
    channels.strm_order,
    channels.huc6,
    channels.state,
	rofp.nwm_vers,
	rofp.reference_time,
    rofp.rapid_onset_prob_day1,
    rofp.rapid_onset_prob_day2,
    rofp.rapid_onset_prob_day3,
    rofp.rapid_onset_prob_day4_5,
    rofp.rapid_onset_prob_all,
    rf.high_water_threshold,
    ST_LENGTH(channels.geom)*0.000621371 AS reach_length_miles,
    to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
    channels.geom
INTO publish.mrf_gfs_5day_rapid_onset_flooding_probability
FROM ingest.mrf_gfs_5day_rapid_onset_flooding_probability as rofp
JOIN derived.channels_conus channels ON rofp.feature_id = channels.feature_id
JOIN derived.recurrence_flows_conus rf ON rofp.feature_id = rf.feature_id;