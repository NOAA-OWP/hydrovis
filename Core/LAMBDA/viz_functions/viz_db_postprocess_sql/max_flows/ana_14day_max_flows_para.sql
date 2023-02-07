DROP TABLE IF EXISTS cache.max_flows_ana_14day_para;

SELECT max_7day_forecast.feature_id,
	max_7day_forecast.reference_time,
	max_7day_forecast.nwm_vers,
	ROUND(max_7day_forecast.streamflow::numeric, 2)  AS max_flow_7day_cms,
	ROUND(max_14day_forecast.streamflow::numeric, 2) AS max_flow_14day_cms,
	ROUND((max_7day_forecast.streamflow * 35.315)::numeric, 2)  AS max_flow_7day_cfs,
	ROUND((max_14day_forecast.streamflow * 35.315)::numeric, 2) AS max_flow_14day_cfs
INTO cache.max_flows_ana_14day_para
FROM ingest.nwm_channel_rt_ana_7day_max_para AS max_7day_forecast
JOIN ingest.nwm_channel_rt_ana_14day_max_para AS max_14day_forecast ON (max_7day_forecast.feature_id = max_14day_forecast.feature_id);