CREATE TABLE IF NOT EXISTS cache.max_flows_ana_7day
(
    feature_id bigint,
    reference_time text,
    nwm_vers double precision,
    discharge_cms numeric,
    discharge_cfs numeric
);

TRUNCATE TABLE cache.max_flows_ana_7day;

INSERT INTO cache.max_flows_ana_7day(feature_id, reference_time, nwm_vers, discharge_cms, discharge_cfs)
	SELECT max_7day_forecast.feature_id,
		max_7day_forecast.reference_time,
		max_7day_forecast.nwm_vers,
		ROUND(max_7day_forecast.streamflow::numeric, 2)  AS discharge_cms,
		ROUND((max_7day_forecast.streamflow * 35.315)::numeric, 2)  AS discharge_cfs
	FROM ingest.nwm_channel_rt_ana_7day_max AS max_7day_forecast;