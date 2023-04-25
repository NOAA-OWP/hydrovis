DROP TABLE IF EXISTS cache.max_flows_srf_alaska;

SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
    ROUND(MAX(forecasts.streamflow)::numeric, 2) AS maxflow_15hour_cms,
	ROUND((MAX(forecasts.streamflow) * 35.315)::numeric, 2) AS maxflow_15hour_cfs
INTO cache.max_flows_srf_alaska
FROM ingest.nwm_channel_rt_srf_alaska forecasts
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;