WITH feature_streamflows as (
    {streamflow_sql}
)

INSERT INTO {db_fim_table}
SELECT
    gc.feature_id as hydro_id,
    gc.feature_id::TEXT as hydro_id_str,
    ST_Transform(gc.geom, 3857) as geom,
    gc.feature_id as feature_id,
    gc.feature_id::TEXT as feature_id_str,
    ROUND((fs.streamflow_cms * 35.315)::numeric, 2) as streamflow_cfs,
    gc.stage_ft as fim_stage_ft,
    mgc.max_rc_stage_ft,
    mgc.max_rc_discharge_cfs,
    CONCAT ('ras2fim_', gc.version) as fim_version,
    '{reference_time}' as reference_time,
    fhc.huc8,
    NULL as branch
FROM ras2fim.geocurves gc
JOIN feature_streamflows fs ON fs.feature_id = gc.feature_id
JOIN derived.featureid_huc_crosswalk fhc ON fs.feature_id = fhc.feature_id
JOIN ras2fim.max_geocurves mgc ON gc.feature_id = mgc.feature_id
WHERE gc.discharge_cms >= fs.streamflow_cms AND gc.previous_discharge_cms < fs.streamflow_cms