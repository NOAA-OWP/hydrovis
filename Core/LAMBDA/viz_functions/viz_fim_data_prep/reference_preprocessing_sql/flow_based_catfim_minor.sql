DROP TABLE IF EXISTS ingest.flow_based_catfim_minor;
SELECT
    crosswalk.hand_id,
    crosswalk.hydro_id,
    crosswalk.feature_id,
    ROUND(CAST(rf.minor_flow_cms * 35.315 as numeric), 2) AS forecast_discharge_cfs,
    gc.discharge_cfs AS rc_discharge_cfs,
    gc.previous_discharge_cfs AS rc_previous_discharge_cfs,
    gc.stage_ft AS forecast_stage_ft,
    gc.stage_ft as rc_stage_ft,
    gc.previous_stage_ft as rc_previous_stage_ft,
    mgc.max_rc_stage_ft,
    mgc.max_rc_discharge_cfs,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    CONCAT ('ras2fim_', gc.version) as fim_version,
    nws_station_id,
    'Inserted FROM Ras2FIM Cache' AS prc_method,
    ST_Transform(gc.geom, 3857) AS geom
INTO ingest.flow_based_catfim_minor
FROM ras2fim.geocurves AS gc
JOIN cache.rfc_categorical_flows AS rf ON gc.feature_id = rf.trace_feature_id
JOIN ras2fim.max_geocurves mgc ON gc.feature_id = mgc.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.trace_feature_id = crosswalk.feature_id
WHERE minor_flow_cms IS NOT NULL AND
	crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999 AND
    ((rf.minor_flow_cms <= gc.discharge_cms AND rf.minor_flow_cms > gc.previous_discharge_cms)
	 OR rf.minor_flow_cms > mgc.max_rc_discharge_cms);

SELECT UpdateGeometrySRID('ingest', 'flow_based_catfim_minor', 'geom', 3857);