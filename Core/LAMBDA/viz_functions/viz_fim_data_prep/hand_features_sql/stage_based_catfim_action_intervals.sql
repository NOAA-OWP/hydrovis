WITH main AS (
	SELECT
		trace_feature_id as feature_id,
		rf.nws_station_id,
		generate_series(
			(adj_action_stage_m + 0.3048)::numeric,
			COALESCE(adj_minor_stage_m, adj_moderate_stage_m, adj_major_stage_m, adj_action_stage_m + 1.524)::numeric,
			0.3048
		) as stage_m
	FROM cache.rfc_categorical_stages AS rf
	WHERE adj_action_stage_m IS NOT NULL
), groupings AS (
	SELECT DISTINCT nws_station_id, stage_m
	FROM main
	ORDER BY nws_station_id, stage_m
), group_labeled AS (
	SELECT nws_station_id, stage_m, row_number() OVER (PARTITION BY nws_station_id ORDER BY stage_m) as interval_ft
	FROM groupings
)

SELECT
	crosswalk.hand_id,
	crosswalk.feature_id,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id,
	ROUND(CAST(rf.stage_m as numeric), 2) AS stage_m,
    rf.nws_station_id,
    l.interval_ft
FROM main AS rf
LEFT JOIN group_labeled l
	ON l.nws_station_id = rf.nws_station_id
	AND l.stage_m = rf.stage_m
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.feature_id = crosswalk.feature_id
LEFT OUTER JOIN ingest.stage_based_catfim_action_intervals_job_num AS fim ON rf.feature_id = fim.feature_id AND rf.nws_station_id = fim.nws_station_id
WHERE l.interval_ft > lower_interval AND l.interval_ft <= upper_interval AND
    rf.stage_m IS NOT NULL AND
	crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999 AND
    fim.feature_id IS NULL;