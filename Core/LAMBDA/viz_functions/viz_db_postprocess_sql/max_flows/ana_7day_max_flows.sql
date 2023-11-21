DROP TABLE IF EXISTS cache.max_flows_ana_7day;

SELECT max_7day_forecast.feature_id,
	max_7day_forecast.reference_time,
	max_7day_forecast.nwm_vers,
	ROUND(max_7day_forecast.streamflow::numeric, 2)  AS discharge_cms,
	ROUND((max_7day_forecast.streamflow * 35.315)::numeric, 2)  AS discharge_cfs
INTO cache.max_flows_ana_7day
FROM ingest.nwm_channel_rt_ana_7day_max AS max_7day_forecast;