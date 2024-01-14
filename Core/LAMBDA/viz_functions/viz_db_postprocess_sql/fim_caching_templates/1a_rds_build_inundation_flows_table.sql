-- This populates a standardized fim_flows table, filtered to high water threshold, on RDS. This is essentially the domain of a given fim run.
-- the prc_status columns is updated throughout the fim run with a status reflecting how fim is calculated for each reach (from ras2fim cache, from hand cache, hand processing, etc.)
-- This table is copied to Redshift in the next step (in order to query the cache there), but this table on RDS is the authoritative source as far as the prc_status column goes.
TRUNCATE {db_fim_table}_flows;
INSERT INTO {db_fim_table}_flows (feature_id, hand_id, hydro_id, huc8, branch, reference_time, discharge_cms, discharge_cfs, prc_status)
SELECT
    max_forecast.feature_id,
    crosswalk.hand_id,
    crosswalk.hydro_id,
    crosswalk.huc8::integer,
    crosswalk.branch_id AS branch,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    max_forecast.discharge_cms,
    max_forecast.discharge_cfs,
    'Pending' AS prc_status
FROM {max_flows_table} max_forecast
JOIN derived.recurrence_flows_{domain} rf ON rf.feature_id=max_forecast.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON max_forecast.feature_id = crosswalk.feature_id
WHERE 
    max_forecast.discharge_cfs >= rf.high_water_threshold AND 
    rf.high_water_threshold > 0::double precision AND
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;