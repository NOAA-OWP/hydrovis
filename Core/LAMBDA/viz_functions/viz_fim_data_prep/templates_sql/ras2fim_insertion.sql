WITH feature_streamflows as (
    {streamflow_sql}
)

INSERT INTO {db_fim_table}(
    hydro_id, feature_id, huc8, branch, forecast_discharge_cfs,
    rc_discharge_cfs, rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft,
    max_rc_stage_ft, max_rc_discharge_cfs, fim_version, reference_time, prc_method
)

SELECT
    gc.feature_id as hydro_id,
    gc.feature_id as feature_id,
    fhc.huc8,
    NULL as branch,
    fs.discharge_cfs as forecast_discharge_cfs,
	gc.discharge_cfs as rc_discharge_cfs,
	gc.previous_discharge_cfs as rc_previous_discharge_cfs,
    gc.stage_ft as rc_stage_ft,
	gc.previous_stage_ft as rc_previous_stage_ft,
    mgc.max_rc_stage_ft,
    mgc.max_rc_discharge_cfs,
    CONCAT ('ras2fim_', gc.version) as fim_version,
    '{reference_time}' as reference_time,
    'Ras2FIM' AS prc_method
FROM ras2fim.geocurves gc
JOIN feature_streamflows fs ON fs.feature_id = gc.feature_id
JOIN derived.featureid_huc_crosswalk fhc ON fs.feature_id = fhc.feature_id
JOIN ras2fim.max_geocurves mgc ON gc.feature_id = mgc.feature_id
JOIN {db_fim_table} fim ON gc.feature_id = fim.feature_id
WHERE gc.discharge_cfs >= fs.discharge_cfs AND gc.previous_discharge_cfs < fs.discharge_cfs
      AND fim.feature_id IS NULL;


INSERT INTO {db_fim_table}_geo (hydro_id, feature_id, rc_stage_ft, geom_part, geom)
SELECT fim.hydro_id, fim.feature_id, fim.rc_stage_ft, row_number() OVER ()::integer AS geom_part, ST_Transform(gc.geom, 3857) as geom
FROM {db_fim_table} AS fim
JOIN ras2fim.geocurves AS gc ON fim.feature_id = gc.feature_id AND fim.rc_stage_ft = gc.stage_ft;