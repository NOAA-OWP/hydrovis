-- HUC10 Hotpsot Layer
DROP TABLE IF EXISTS publish.srf_12hr_max_high_water_probability_hucs;
SELECT
	hucs.huc10,
	TO_CHAR(hucs.huc10, 'fm0000000000') AS huc10_str,
	hucs.total_nwm_features,
	(count(hwp.feature_id)::double precision / hucs.total_nwm_features::double precision)*100 AS nwm_features_flooded_percent,
	avg(srf_prob) as avg_prob,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	hucs.geom
INTO publish.srf_12hr_max_high_water_probability_hucs
FROM derived.huc10s_conus AS hucs
JOIN derived.featureid_huc_crosswalk AS crosswalk ON hucs.huc10 = crosswalk.huc10
JOIN publish.srf_12hr_max_high_water_probability AS hwp ON crosswalk.feature_id = hwp.feature_id
GROUP BY hucs.huc10, total_nwm_features, hucs.geom