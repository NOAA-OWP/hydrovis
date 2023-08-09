SELECT
    max_forecast.feature_id,
    max_forecast.max_flow_7day_cms AS streamflow_cms
FROM cache.max_flows_ana_7day max_forecast
JOIN derived.recurrence_flows_conus rf ON rf.feature_id=max_forecast.feature_id
WHERE 
    max_forecast.max_flow_7day_cfs >= rf.high_water_threshold
