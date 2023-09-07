SELECT
    trace_feature_id as feature_id,
	adj_major_stage_m as hand_stage_m,
    nws_station_id
FROM cache.rfc_categorical_stages AS rf
WHERE adj_major_stage_m IS NOT NULL;