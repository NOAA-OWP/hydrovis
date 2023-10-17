-- HUC10 Hotpsot Layer for Rapid Onset Flooding
DROP TABLE IF EXISTS publish.srf_48hr_rapid_onset_flooding_hucs_hi;
SELECT
	hucs.huc10,
	TO_CHAR(hucs.huc10, 'fm0000000000') AS huc10_str,
	hucs.low_order_reach_count,
	hucs.total_low_order_reach_length,
	hucs.total_low_order_reach_miles,
	count(rof.feature_id) / hucs.low_order_reach_count AS nwm_features_flooded_percent,
	sum(rof.reach_length_miles) / hucs.total_low_order_reach_miles AS nwm_waterway_length_flooded_percent,
	avg(flood_start_hour) AS avg_rof_arrival_time,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	hucs.geom
INTO publish.srf_48hr_rapid_onset_flooding_hucs_hi
FROM derived.huc10s_hi AS hucs
JOIN derived.featureid_huc_crosswalk AS crosswalk ON hucs.huc10 = crosswalk.huc10
JOIN publish.srf_48hr_rapid_onset_flooding_hi AS rof ON crosswalk.feature_id = rof.feature_id
GROUP BY hucs.huc10, hucs.low_order_reach_count, hucs.total_low_order_reach_length, hucs.total_low_order_reach_miles, hucs.geom