TRUNCATE {rs_fim_table}_flows;
INSERT INTO {rs_fim_table}_flows (feature_id, hydro_id, huc8, branch, reference_time, discharge_cms, discharge_cfs, prc_status)
SELECT
    feature_id, hydro_id, huc8, branch, reference_time, discharge_cms, discharge_cfs, prc_status
FROM external_viz_{db_fim_table}_flows;