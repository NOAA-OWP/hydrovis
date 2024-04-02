CREATE TABLE IF NOT EXISTS cache.max_flows_ana_14day
(
    feature_id bigint,
    reference_time text,
    nwm_vers double precision,
    discharge_cms numeric,
    discharge_cfs numeric
);

TRUNCATE TABLE cache.max_flows_ana_14day;

INSERT INTO cache.max_flows_ana_14day(feature_id, reference_time, nwm_vers, discharge_cms, discharge_cfs)
    SELECT max_14day_forecast.feature_id,
        max_14day_forecast.reference_time,
        REPLACE(max_14day_forecast.nwm_vers, 'v', '')::double precision as nwm_vers, --TODO, not sure why this isn't happening on the ingest side like everything else.
        ROUND(max_14day_forecast.streamflow::numeric, 2) AS discharge_cms,
        ROUND((max_14day_forecast.streamflow * 35.315)::numeric, 2) AS discharge_cfs
    FROM ingest.nwm_channel_rt_ana_14day_max AS max_14day_forecast;