SELECT 
	trace_feature_id as feature_id, 
	rf.nws_station_id, 
	(adj_major_stage_m + ({ft_from_major} * 0.3048))::numeric as stage_m,
	{ft_from_major} as interval_ft
FROM cache.rfc_categorical_stages AS rf;