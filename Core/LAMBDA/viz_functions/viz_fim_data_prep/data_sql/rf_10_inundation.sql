SELECT
    rf.feature_id,
    ROUND(CAST(rf.rf_10_0_17c * 0.0283168 as numeric), 2) as streamflow_cms,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id
FROM derived.recurrence_flows_conus rf
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.feature_id = crosswalk.feature_id
WHERE 
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;