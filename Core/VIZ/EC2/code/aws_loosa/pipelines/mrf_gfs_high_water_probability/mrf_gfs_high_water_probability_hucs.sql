DROP TABLE IF EXISTS publish.mrf_gfs_high_water_probability_hucs;
SELECT
	hucs.huc8,
	TO_CHAR(hucs.huc8, 'fm00000000') AS huc8_str,
	hucs.total_nwm_features,
	round(cast(count(bp.feature_id) / hucs.total_nwm_features * 100 as numeric), 2) AS nwm_features_flooded_percent,
	round(avg(bp.hours_3_to_120), 0) AS avg_prob,
	to_char(CAST(max(bp.reference_time) AS timestamp) , 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	hucs.geom
INTO publish.mrf_gfs_high_water_probability_hucs
FROM derived.huc8s_conus AS hucs
JOIN derived.featureid_huc_crosswalk AS crosswalk ON hucs.huc8 = crosswalk.huc8
JOIN publish.mrf_gfs_high_water_probability AS bp ON crosswalk.feature_id = bp.feature_id
GROUP BY hucs.huc8, hucs.total_nwm_features, hucs.geom