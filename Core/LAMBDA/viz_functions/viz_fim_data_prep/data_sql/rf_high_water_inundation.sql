SELECT
    rf.feature_id,
    ROUND(CAST(rf.high_water_threshold * 0.0283168 as numeric), 2) as streamflow_cms,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LPAD(crosswalk.huc8::text, 8, '0') as huc8,
    crosswalk.hydro_id
FROM derived.recurrence_flows_conus rf
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.feature_id = crosswalk.feature_id
WHERE 
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;