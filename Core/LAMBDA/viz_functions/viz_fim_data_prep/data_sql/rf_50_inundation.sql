SELECT
    rf.feature_id,
    ROUND(CAST(rf.rf_50_0_17c * 0.0283168 as numeric), 2) as streamflow_cms,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id,
    conditions.start_flow as ras2fim_start_streamflow_cms,
    conditions.end_flow as ras2fim_end_streamflow_cms
FROM derived.recurrence_flows_conus rf
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.feature_id = crosswalk.feature_id
LEFT JOIN derived.ras2fim_conditions AS conditions ON rf.feature_id = conditions.feature_id
WHERE
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;