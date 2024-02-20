SELECT
    trace_feature_id as feature_id,
	adj_moderate_stage_m as stage_m,
    nws_station_id,
    0 as interval_ft
FROM cache.rfc_categorical_stages AS rf
WHERE adj_moderate_stage_m IS NOT NULL;