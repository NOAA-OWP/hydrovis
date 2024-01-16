-- Copy the fim_flows table on RDS to Redshift -  this allows querying the hand cache on redshift by joining to this table.
TRUNCATE {rs_fim_table}_flows;
INSERT INTO {rs_fim_table}_flows (hand_id, feature_id, hydro_id, huc8, branch, reference_time, discharge_cms, discharge_cfs, prc_status)
SELECT
    hand_id, feature_id, hydro_id, huc8, branch, reference_time, discharge_cms, discharge_cfs, prc_status
FROM {postgis_fim_table}_flows;