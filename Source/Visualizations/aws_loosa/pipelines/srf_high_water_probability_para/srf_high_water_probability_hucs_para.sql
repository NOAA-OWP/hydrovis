DROP TABLE IF EXISTS publish.srf_high_water_probability_hucs_para;
SELECT
	hucs.huc10,
	TO_CHAR(hucs.huc10, 'fm0000000000') AS huc10_str,
	hucs.total_nwm_features,
	round(cast(count(bp.feature_id) / hucs.total_nwm_features * 100 as numeric), 2) AS nwm_features_flooded_percent,
	round(avg(bp.srf_prob), 0) AS avg_prob,
	to_char(CAST(max(bp.reference_time) AS timestamp) , 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	hucs.geom
INTO publish.srf_high_water_probability_hucs_para
FROM derived.huc10s_conus AS hucs
JOIN derived.featureid_huc_crosswalk AS crosswalk ON hucs.huc10 = crosswalk.huc10
JOIN publish.srf_high_water_probability_para AS bp ON crosswalk.feature_id = bp.feature_id
GROUP BY hucs.huc10, hucs.total_nwm_features, hucs.geom