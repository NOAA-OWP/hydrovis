SELECT
    crosswalk.hand_id,
    max_forecast.feature_id,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id,
    ROUND(CAST(max_forecast.rf_10_0_17c * 0.0283168 as numeric), 2) AS streamflow_cms
FROM derived.recurrence_flows_conus AS max_forecast
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON max_forecast.feature_id = crosswalk.feature_id
WHERE 
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;