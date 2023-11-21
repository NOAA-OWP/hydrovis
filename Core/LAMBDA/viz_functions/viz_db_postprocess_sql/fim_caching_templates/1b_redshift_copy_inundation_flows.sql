TRUNCATE {rs_streamflow_table};
INSERT INTO fim.ana_inundation_status (feature_id, hydro_id, huc8, branch, reference_time, discharge_cms, discharge_cfs, prc_status)
SELECT
    *
FROM external_viz_ingest.ana_inundation_flows;