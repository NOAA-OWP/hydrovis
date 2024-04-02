CREATE TABLE IF NOT EXISTS cache.max_flows_mrf_gfs_3day_ak
(
    feature_id bigint,
    reference_time text,
    nwm_vers double precision,
    discharge_cms numeric,
    discharge_cfs numeric
);

TRUNCATE TABLE cache.max_flows_mrf_gfs_3day_ak;
INSERT INTO cache.max_flows_mrf_gfs_3day_ak(feature_id, reference_time, nwm_vers, discharge_cms, discharge_cfs)
    SELECT forecasts.feature_id,
        forecasts.reference_time,
        forecasts.nwm_vers,
        round(max(forecasts.streamflow)::numeric, 2) AS discharge_cms,
        round(max(forecasts.streamflow * 35.315)::numeric, 2) AS discharge_cfs
    FROM ingest.nwm_channel_rt_mrf_gfs_ak_mem1 forecasts
    WHERE forecasts.forecast_hour <= 72
    GROUP BY forecasts.feature_id, forecasts.reference_time, forecasts.nwm_vers;