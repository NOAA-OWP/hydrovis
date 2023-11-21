DROP TABLE IF EXISTS cache.max_flows_ana_14day;

SELECT max_14day_forecast.feature_id,
	max_14day_forecast.reference_time,
	max_14day_forecast.nwm_vers,
	ROUND(max_14day_forecast.streamflow::numeric, 2) AS discharge_cms,
	ROUND((max_14day_forecast.streamflow * 35.315)::numeric, 2) AS discharge_cfs
INTO cache.max_flows_ana_14day
FROM ingest.nwm_channel_rt_ana_14day_max AS max_14day_forecast