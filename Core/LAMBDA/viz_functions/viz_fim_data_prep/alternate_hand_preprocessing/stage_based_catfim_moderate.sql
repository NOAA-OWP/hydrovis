DROP TABLE IF EXISTS ingest.stage_based_catfim_moderate;
SELECT
    crosswalk.hand_id,
    crosswalk.hydro_id,
    crosswalk.feature_id,
    ROUND(CAST(rf.adj_moderate_stage_m * 35.315 as numeric), 2) AS forecast_stage_ft,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    CONCAT ('ras2fim_', gc.version) as fim_version,
    nws_station_id,
    'Inserted FROM Ras2FIM Cache' AS prc_method,
    ST_Transform(gc.geom, 3857) AS geom
INTO ingest.stage_based_catfim_moderate
FROM ras2fim.geocurves AS gc
JOIN cache.rfc_categorical_stages AS rf ON gc.feature_id = rf.trace_feature_id
JOIN ras2fim.max_geocurves mgc ON gc.feature_id = mgc.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.trace_feature_id = crosswalk.feature_id
WHERE adj_moderate_stage_m IS NOT NULL AND
	crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999 AND
    ((rf.adj_moderate_stage_m <= gc.stage_m AND rf.adj_moderate_stage_m > gc.previous_stage_m)
	 OR rf.adj_moderate_stage_m > mgc.max_rc_stage_m);

SELECT UpdateGeometrySRID('ingest', 'stage_based_catfim_moderate', 'geom', 3857);