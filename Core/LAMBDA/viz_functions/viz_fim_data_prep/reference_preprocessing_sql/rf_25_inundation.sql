-- We want RAS2FIM cached features used for aep_fim, so first, copy those features into a publish table in the vizdb (this will be copied to EGIS before hand runs as well)

DROP TABLE IF EXISTS publish.rf_25_inundation;
SELECT
    crosswalk.hydro_id,
    crosswalk.hydro_id::text AS hydro_id_str,
    ST_Transform(gc.geom, 3857) AS geom,
    crosswalk.feature_id,
    crosswalk.feature_id::text AS feature_id_str,
    ROUND(CAST(fs.rf_25_0_17c as numeric), 2) AS streamflow_cfs,
    gc.stage_ft as fim_stage_ft,
    mgc.max_rc_stage_ft,
    mgc.max_rc_discharge_cfs,
    '{fim_version}' as fim_version,
    gc.model_version,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    crosswalk.huc8 as huc8,
    crosswalk.branch_id as branch
INTO publish.rf_25_inundation
FROM ras2fim.{ras2fim_version_db}__geocurves gc
JOIN derived.recurrence_flows_conus fs ON fs.feature_id = gc.feature_id
JOIN ras2fim.{ras2fim_version_db}__max_geocurves mgc ON gc.feature_id = mgc.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON gc.feature_id = crosswalk.feature_id
WHERE gc.discharge_cfs >= fs.rf_25_0_17c AND gc.previous_discharge_cfs < fs.rf_25_0_17c;