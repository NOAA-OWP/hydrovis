WITH main AS (
	SELECT
		trace_feature_id as feature_id,
		rf.nws_station_id,
		generate_series(
			(adj_moderate_stage_m + 0.3048)::numeric,
			COALESCE(adj_major_stage_m, adj_moderate_stage_m + 1.524)::numeric,
			0.3048
		) as stage_m
	FROM cache.rfc_categorical_stages AS rf
	WHERE adj_moderate_stage_m IS NOT NULL
), groupings AS (
	SELECT DISTINCT nws_station_id, stage_m
	FROM main
	ORDER BY nws_station_id, stage_m
), group_labeled AS (
	SELECT nws_station_id, stage_m, row_number() OVER (PARTITION BY nws_station_id ORDER BY stage_m) as interval_ft
	FROM groupings
)

SELECT 
	feature_id, 
	main.stage_m, 
	main.nws_station_id, 
	interval_ft
FROM main
LEFT JOIN group_labeled l
	ON l.nws_station_id = main.nws_station_id
	AND l.stage_m = main.stage_m
WHERE interval_ft > {lower_interval} AND interval_ft <= {upper_interval};