-- Create a past_hour ana table. This is an interim solution to Shawn's rate of change service.
CREATE TABLE IF NOT EXISTS cache.max_flows_ana_para (feature_id bigint, reference_time timestamp without time zone, nwm_vers double precision, maxflow_1hour_cms double precision, maxflow_1hour_cfs double precision);
DROP TABLE IF EXISTS cache.max_flows_ana_past_hour_para;
SELECT * INTO cache.max_flows_ana_past_hour_para FROM cache.max_flows_ana_para;

DROP TABLE IF EXISTS cache.max_flows_ana_para;

SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
    ROUND(MAX(forecasts.streamflow)::numeric, 2) AS maxflow_1hour_cms,
	ROUND((MAX(forecasts.streamflow) * 35.315)::numeric, 2) AS maxflow_1hour_cfs
INTO cache.max_flows_ana_para
FROM ingest.nwm_channel_rt_ana_para forecasts
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;