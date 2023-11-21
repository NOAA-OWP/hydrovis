DROP TABLE IF EXISTS cache.max_flows_mrf_nbm_10day;
SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
    round(max(forecasts.streamflow)::numeric, 2) AS discharge_cms,
    round(max(forecasts.streamflow * 35.315)::numeric, 2) AS discharge_cfs
INTO cache.max_flows_mrf_nbm_10day
FROM ingest.nwm_channel_rt_mrf_nbm forecasts
WHERE forecasts.forecast_hour > 120
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;