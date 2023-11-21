TRUNCATE {db_streamflow_table};
INSERT INTO {db_streamflow_table} (feature_id, hydro_id, huc8, branch, reference_time, discharge_cms, discharge_cfs, prc_status)
SELECT
    max_forecast.feature_id,
    crosswalk.hydro_id,
    crosswalk.huc8::integer,
    crosswalk.branch_id AS branch,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    max_forecast.maxflow_1hour_cms AS discharge_cms,
    max_forecast.maxflow_1hour_cfs AS discharge_cfs,
    'Pending' AS prc_status
FROM cache.max_flows_ana max_forecast
JOIN derived.recurrence_flows_conus rf ON rf.feature_id=max_forecast.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON max_forecast.feature_id = crosswalk.feature_id
WHERE 
    max_forecast.maxflow_1hour_cfs >= rf.high_water_threshold AND 
    rf.high_water_threshold > 0::double precision AND
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;