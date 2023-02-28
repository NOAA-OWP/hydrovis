SELECT
    max_forecast.feature_id,
    max_forecast.max_flow_7day_cms AS streamflow_cms,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id
FROM cache.max_flows_ana_14day max_forecast
JOIN derived.recurrence_flows_conus rf ON rf.feature_id=max_forecast.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.feature_id = crosswalk.feature_id
WHERE 
    max_forecast.max_flow_7day_cfs >= rf.high_water_threshold AND 
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;
