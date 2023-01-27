DROP TABLE IF EXISTS CACHE.MAX_FLOWS_SRF_HI;

SELECT forecasts.feature_id,
    '1900-01-01 00:00:00'::timestamp without time zone AS reference_time,
    round(max(forecasts.streamflow)::numeric, 2) AS maxflow_48hour_cms,
   round((max(forecasts.streamflow) * 35.315)::numeric, 2) AS maxflow_48hour_cfs
INTO CACHE.MAX_FLOWS_SRF_HI
FROM ingest.nwm_channel_rt_srf_hi forecasts
GROUP BY forecasts.feature_id;