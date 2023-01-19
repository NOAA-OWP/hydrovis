-- Create a past_hour ana table. This is an interim solution to Shawn's rate of change service.
CREATE TABLE IF NOT EXISTS cache.max_flows_ana (feature_id bigint, reference_time timestamp without time zone, MAXFLOW_1HOUR_cms double precision, MAXFLOW_1HOUR_cfs double precision);
DROP TABLE IF EXISTS cache.max_flows_ana_past_hour;
SELECT * INTO cache.max_flows_ana_past_hour FROM cache.max_flows_ana;

DROP TABLE IF EXISTS cache.max_flows_ana;

SELECT FORECASTS.FEATURE_ID,
    '1900-01-01 00:00:00'::timestamp without time zone AS reference_time,
    ROUND(MAX(FORECASTS.STREAMFLOW)::numeric, 2) AS MAXFLOW_1HOUR_cms,
	ROUND((MAX(FORECASTS.STREAMFLOW) * 35.315)::numeric, 2) AS MAXFLOW_1HOUR_cfs
INTO cache.max_flows_ana
FROM INGEST.NWM_CHANNEL_RT_ANA FORECASTS
GROUP BY FORECASTS.FEATURE_ID;