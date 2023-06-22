SELECT
    trace_feature_id as feature_id,
	adj_major_stage_m as hand_stage_m,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id,
    nws_station_id
FROM cache.rfc_categorical_stages AS rf
LEFT JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.trace_feature_id = crosswalk.feature_id
WHERE crosswalk.huc8 IS NOT NULL AND crosswalk.lake_id = -999 AND adj_major_stage_m IS NOT NULL;