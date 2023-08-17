SELECT
    max_forecast.feature_id,
    max_forecast.maxflow_48hour_cms AS streamflow_cms
FROM cache.max_flows_srf_prvi max_forecast
JOIN derived.recurrence_flows_prvi rf ON rf.feature_id=max_forecast.feature_id
WHERE 
    max_forecast.maxflow_48hour_cfs >= rf.high_water_threshold AND 
    rf.high_water_threshold > 0::double precision
