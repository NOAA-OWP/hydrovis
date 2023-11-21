DROP TABLE IF EXISTS cache.max_flows_ana_hi;


SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
	ROUND(MAX(forecasts.streamflow)::numeric, 2) AS discharge_cms,
	ROUND((MAX(forecasts.streamflow) * 35.315)::numeric, 2) AS discharge_cfs
INTO cache.max_flows_ana_hi
FROM ingest.nwm_channel_rt_ana_hi forecasts
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;