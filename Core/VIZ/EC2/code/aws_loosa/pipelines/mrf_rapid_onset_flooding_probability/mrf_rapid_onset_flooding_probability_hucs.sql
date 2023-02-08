DROP TABLE IF EXISTS publish.mrf_rapid_onset_flooding_probability_hucs;
SELECT
	hucs.huc8,
	TO_CHAR(hucs.huc8, 'fm00000000') AS huc8_str,
	ROUND(CAST(hucs.low_order_reach_count AS numeric), 2) AS low_order_reach_count,
	ROUND(CAST(hucs.total_low_order_reach_miles AS numeric), 2) AS total_low_order_reach_miles,
	COUNT(rofp.feature_id) AS rapid_onset_reach_cnt,
	ROUND(CAST(SUM(rofp.reach_length_miles) AS numeric), 2) AS rapid_onset_reach_length_sum,
	ROUND(CAST(SUM(rofp.rapid_onset_prob_all * rofp.reach_length_miles) / SUM(rofp.reach_length_miles) AS numeric), 2) AS weighted_mean,
	ROUND(CAST(COUNT(rofp.feature_id) / hucs.low_order_reach_count * 100 AS numeric), 2) AS pct_reachs_rapid_onset,
	ROUND(CAST(SUM(rofp.reach_length_miles) / hucs.total_low_order_reach_miles * 100 AS numeric), 2) AS pct_reach_length_rapid_onset,
	to_char(CAST(max(rofp.reference_time) AS timestamp) , 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	hucs.geom
INTO publish.mrf_rapid_onset_flooding_probability_hucs
FROM derived.huc8s_conus AS hucs
JOIN derived.featureid_huc_crosswalk AS crosswalk ON hucs.huc8 = crosswalk.huc8
JOIN publish.mrf_rapid_onset_flooding_probability AS rofp ON crosswalk.feature_id = rofp.feature_id
GROUP BY hucs.huc8, hucs.low_order_reach_count, hucs.total_low_order_reach_length, hucs.total_low_order_reach_miles, hucs.geom