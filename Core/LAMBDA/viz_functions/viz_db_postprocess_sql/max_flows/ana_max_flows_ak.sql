-- Create a past_hour ana table. This is an interim solution to Shawn's rate of change service.
CREATE TABLE IF NOT EXISTS cache.max_flows_ana_ak
(
    feature_id bigint,
    reference_time text,
    nwm_vers double precision,
    discharge_cms numeric,
    discharge_cfs numeric
);
CREATE TABLE IF NOT EXISTS cache.max_flows_ana_past_hour_ak 
(
    feature_id bigint, 
    reference_time text, 
    nwm_vers double precision, 
    discharge_cms double precision, 
    discharge_cfs double precision
);

TRUNCATE TABLE cache.max_flows_ana_past_hour_ak;
INSERT INTO cache.max_flows_ana_past_hour_ak
SELECT * FROM cache.max_flows_ana_ak;

-- Regular ana max flows for alaska
TRUNCATE TABLE cache.max_flows_ana_ak;

INSERT INTO cache.max_flows_ana_ak(feature_id, reference_time, nwm_vers, discharge_cms, discharge_cfs)
    SELECT forecasts.feature_id,
        forecasts.reference_time,
        forecasts.nwm_vers,
        ROUND(MAX(forecasts.streamflow)::numeric, 2) AS discharge_cms,
        ROUND((MAX(forecasts.streamflow) * 35.315)::numeric, 2) AS discharge_cfs
    FROM ingest.nwm_channel_rt_ana_ak forecasts
    GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;