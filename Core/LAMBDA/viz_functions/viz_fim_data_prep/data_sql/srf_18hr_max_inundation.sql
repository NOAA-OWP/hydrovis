SELECT
    max_forecast.feature_id,
    max_forecast.maxflow_18hour_cms AS streamflow_cms
FROM cache.max_flows_srf max_forecast
JOIN derived.recurrence_flows_conus rf ON rf.feature_id=max_forecast.feature_id
WHERE 
    max_forecast.maxflow_18hour_cfs >= rf.high_water_threshold
