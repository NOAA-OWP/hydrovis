-- HUC8 Hotpsot Layer for Rapid Onset Flooding
DROP TABLE IF EXISTS PUBLISH.mrf_gfs_rapid_onset_flooding_hucs;
SELECT
	hucs.huc8,
	TO_CHAR(hucs.huc8, 'fm00000000') AS huc8_str,
	hucs.low_order_reach_count,
	hucs.total_low_order_reach_length,
	hucs.total_low_order_reach_miles,
	count(rof.feature_id) / hucs.low_order_reach_count AS nwm_features_flooded_percent,
	sum(rof.reach_length_miles) / hucs.total_low_order_reach_miles AS nwm_waterway_length_flooded_percent,
	avg(flood_start_hour) AS avg_rof_arrival_time,
	to_char(max(rof.reference_time)::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	hucs.geom
INTO publish.mrf_gfs_rapid_onset_flooding_hucs
FROM derived.huc8s_conus AS hucs
JOIN derived.featureid_huc_crosswalk AS crosswalk ON hucs.huc8 = crosswalk.huc8
JOIN publish.mrf_gfs_rapid_onset_flooding AS rof ON crosswalk.feature_id = rof.feature_id
GROUP BY hucs.huc8, hucs.low_order_reach_count, hucs.total_low_order_reach_length, hucs.total_low_order_reach_miles, hucs.geom