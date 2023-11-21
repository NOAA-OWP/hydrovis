CREATE TABLE IF NOT EXISTS cache.max_flows_srf_prvi
(
    feature_id bigint,
    reference_time text,
    nwm_vers double precision,
    discharge_cms numeric,
    discharge_cfs numeric
);

TRUNCATE TABLE cache.max_flows_srf_prvi;
INSERT INTO cache.max_flows_srf_prvi(feature_id, reference_time, nwm_vers, discharge_cms, discharge_cfs)
    SELECT forecasts.feature_id,
        forecasts.reference_time,
        forecasts.nwm_vers,
        ROUND(MAX(forecasts.streamflow)::numeric, 2) AS discharge_cms,
        ROUND((MAX(forecasts.streamflow) * 35.315)::numeric, 2) AS discharge_cfs
    FROM ingest.nwm_channel_rt_srf_prvi forecasts
    GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;