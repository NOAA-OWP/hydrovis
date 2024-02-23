DROP TABLE IF EXISTS ingest.flow_based_catfim_action;
SELECT
    crosswalk.hand_id,
    crosswalk.hydro_id,
    crosswalk.hydro_id::text AS hydro_id_str,
    crosswalk.feature_id,
    crosswalk.feature_id::text AS feature_id_str,
    ROUND(CAST(rf.action_flow_cms as numeric), 2) AS streamflow_cms,
    ROUND(CAST(rf.action_flow_cms * 35.315 as numeric), 2) AS streamflow_cfs,
    gc.discharge_cfs AS rc_discharge_cfs,
    gc.previous_discharge_cfs AS rc_previous_discharge_cfs,
    gc.stage_ft as rc_stage_ft,
    gc.previous_stage_ft as rc_previous_stage_ft,
    mgc.max_rc_stage_ft,
    mgc.max_rc_discharge_cfs,
    CONCAT ('ras2fim_', gc.version) as fim_version,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    crosswalk.huc8 as huc8,
    crosswalk.branch_id as branch,
    nws_station_id,
    ST_Transform(gc.geom, 3857) AS geom
INTO ingest.flow_based_catfim_action
FROM ras2fim.geocurves AS gc
JOIN cache.rfc_categorical_stages AS rf ON gc.feature_id = rf.trace_feature_id
JOIN ras2fim.max_geocurves mgc ON gc.feature_id = mgc.feature_id
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON rf.trace_feature_id = crosswalk.feature_id
WHERE adj_action_stage_m IS NOT NULL AND
	crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999 AND
    ((rf.adj_action_stage_m <= gc.stage_m AND rf.adj_action_stage_m > gc.previous_stage_m)
	 OR rf.adj_action_stage_m > mgc.max_rc_stage_m);