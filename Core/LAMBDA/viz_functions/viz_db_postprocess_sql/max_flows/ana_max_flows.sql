-- Create a past_hour ana table. This is an interim solution to Shawn's rate of change service.
CREATE TABLE IF NOT EXISTS cache.max_flows_ana (feature_id bigint, reference_time timestamp without time zone, nwm_vers double precision, discharge_cms double precision, discharge_cfs double precision);
CREATE TABLE IF NOT EXISTS cache.max_flows_ana_past_hour (feature_id bigint, reference_time timestamp without time zone, nwm_vers double precision, discharge_cms double precision, discharge_cfs double precision);
TRUNCATE TABLE cache.max_flows_ana_past_hour;
INSERT INTO cache.max_flows_ana_past_hour
SELECT * FROM cache.max_flows_ana;

-- Regular ana max flows
DROP TABLE IF EXISTS cache.max_flows_ana;

SELECT forecasts.feature_id,
	forecasts.reference_time,
	forecasts.nwm_vers,
    ROUND(MAX(forecasts.streamflow)::numeric, 2) AS discharge_cms,
	ROUND((MAX(forecasts.streamflow) * 35.315)::numeric, 2) AS discharge_cfs
INTO cache.max_flows_ana
FROM ingest.nwm_channel_rt_ana forecasts
GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;