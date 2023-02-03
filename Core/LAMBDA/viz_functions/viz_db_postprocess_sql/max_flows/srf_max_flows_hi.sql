DROP TABLE IF EXISTS cache.max_flows_srf_hi;

SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
    round(max(forecasts.streamflow)::numeric, 2) AS maxflow_48hour_cms,
   round((max(forecasts.streamflow) * 35.315)::numeric, 2) AS maxflow_48hour_cfs
INTO cache.max_flows_srf_hi
FROM ingest.nwm_channel_rt_srf_hi forecasts
GROUP BY forecasts.feature_id;