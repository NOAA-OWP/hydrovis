SELECT
    max_forecast.feature_id,
    max_forecast.discharge_cms AS streamflow_cms
FROM cache.max_flows_mrf_nbm_10day max_forecast
JOIN derived.recurrence_flows_conus rf ON rf.feature_id=max_forecast.feature_id
WHERE 
    max_forecast.discharge_cfs >= rf.high_water_threshold AND 
    rf.high_water_threshold > 0::double precision
