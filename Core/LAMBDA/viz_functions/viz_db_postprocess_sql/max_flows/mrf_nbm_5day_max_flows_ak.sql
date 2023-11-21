DROP TABLE IF EXISTS cache.max_flows_mrf_nbm_5day_ak;
SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
    round(max(forecasts.streamflow)::numeric, 2) AS discharge_cms,
    round(max(forecasts.streamflow * 35.315)::numeric, 2) AS discharge_cfs
INTO cache.max_flows_mrf_nbm_5day_ak
FROM ingest.nwm_channel_rt_mrf_nbm_ak forecasts
WHERE forecasts.forecast_hour > 72 AND forecasts.forecast_hour <= 120
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;