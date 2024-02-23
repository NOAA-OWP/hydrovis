SELECT
	crosswalk.hand_id,
	crosswalk.feature_id,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id,
	ROUND(CAST((rf.adj_major_stage_m + ({ft_from_major} * 0.3048)) as numeric), 2) AS stage_m,
    rf.nws_station_id,
    ft_from_major AS interval_ft
FROM cache.rfc_categorical_stages AS rf
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.trace_feature_id = crosswalk.feature_id
LEFT OUTER JOIN ingest.stage_based_catfim_major_intervals_ft_from_major AS fim ON rf.trace_feature_id = fim.feature_id AND rf.nws_station_id = fim.nws_station_id
WHERE rf.adj_major_stage_m IS NOT NULL AND
	crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999 AND
    fim.feature_id IS NULL;