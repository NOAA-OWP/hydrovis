DROP TABLE IF EXISTS CACHE.MAX_FLOWS_MRF;

SELECT forecasts.feature_id,
    '1900-01-01 00:00:00'::timestamp without time zone AS reference_time,
    round(max(CASE WHEN forecasts.forecast_hour <= 72 THEN forecasts.streamflow ELSE NULL END)::numeric, 2) AS maxflow_3day_cms,
    round(max(CASE WHEN forecasts.forecast_hour <= 120 THEN forecasts.streamflow ELSE NULL END)::numeric, 2) AS maxflow_5day_cms,
    round(max(forecasts.streamflow)::numeric, 2) AS maxflow_10day_cms,
    round((max(CASE WHEN forecasts.forecast_hour <= 72 THEN forecasts.streamflow ELSE NULL END) * 35.315)::numeric, 2) AS maxflow_3day_cfs,
    round((max(CASE WHEN forecasts.forecast_hour <= 120 THEN forecasts.streamflow ELSE NULL END) * 35.315)::numeric, 2) AS maxflow_5day_cfs,
    round((max(forecasts.streamflow) * 35.315)::numeric, 2) AS maxflow_10day_cfs
INTO CACHE.MAX_FLOWS_MRF
FROM ingest.nwm_channel_rt_mrf_mem1 forecasts
GROUP BY forecasts.feature_id;