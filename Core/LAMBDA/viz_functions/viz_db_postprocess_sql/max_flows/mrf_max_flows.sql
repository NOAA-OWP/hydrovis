DROP TABLE IF EXISTS cache.max_flows_mrf;

SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
    round(max(CASE WHEN forecasts.forecast_hour <= 72 THEN forecasts.streamflow ELSE NULL END)::numeric, 2) AS maxflow_3day_cms,
    round(max(CASE WHEN forecasts.forecast_hour <= 120 THEN forecasts.streamflow ELSE NULL END)::numeric, 2) AS maxflow_5day_cms,
    round(max(forecasts.streamflow)::numeric, 2) AS maxflow_10day_cms,
    round((max(CASE WHEN forecasts.forecast_hour <= 72 THEN forecasts.streamflow ELSE NULL END) * 35.315)::numeric, 2) AS maxflow_3day_cfs,
    round((max(CASE WHEN forecasts.forecast_hour <= 120 THEN forecasts.streamflow ELSE NULL END) * 35.315)::numeric, 2) AS maxflow_5day_cfs,
    round((max(forecasts.streamflow) * 35.315)::numeric, 2) AS maxflow_10day_cfs
INTO cache.max_flows_mrf
FROM ingest.nwm_channel_rt_mrf_mem1 forecasts
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;