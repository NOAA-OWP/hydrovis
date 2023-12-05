TRUNCATE {db_fim_table}_flows;
INSERT INTO {db_fim_table}_flows (feature_id, hydro_id, huc8, branch, reference_time, discharge_cms, discharge_cfs, prc_status)
SELECT
    max_forecast.feature_id,
    crosswalk.hydro_id,
    crosswalk.huc8::integer,
    crosswalk.branch_id AS branch,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    max_forecast.discharge_cms,
    max_forecast.discharge_cfs,
    'Pending' AS prc_status
FROM {max_flows_table} max_forecast
JOIN derived.recurrence_flows_conus rf ON rf.feature_id=max_forecast.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON max_forecast.feature_id = crosswalk.feature_id
WHERE 
    max_forecast.discharge_cfs >= rf.high_water_threshold AND 
    rf.high_water_threshold > 0::double precision AND
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;