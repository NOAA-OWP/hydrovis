SELECT
    max_forecast.feature_id,
    max_forecast.maxflow_48hour_cms AS streamflow_cms,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id,
    conditions.start_flow as ras2fim_start_streamflow_cms,
    conditions.end_flow as ras2fim_end_streamflow_cms
FROM cache.max_flows_srf_prvi max_forecast
JOIN derived.recurrence_flows_prvi rf ON rf.feature_id=max_forecast.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.feature_id = crosswalk.feature_id
LEFT JOIN derived.ras2fim_conditions AS conditions ON max_forecast.feature_id = conditions.feature_id
WHERE 
    max_forecast.maxflow_48hour_cfs >= rf.high_water_threshold AND 
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;
