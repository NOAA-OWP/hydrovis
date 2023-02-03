DROP TABLE IF EXISTS cache.max_flows_ana_prvi;


SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
	ROUND(MAX(forecasts.streamflow)::numeric, 2) AS maxflow_1hour_cms,
	ROUND((MAX(forecasts.streamflow) * 35.315)::numeric, 2) AS maxflow_1hour_cfs
INTO cache.max_flows_ana_prvi
FROM ingest.nwm_channel_rt_ana_prvi forecasts
GROUP BY forecasts.feature_id;