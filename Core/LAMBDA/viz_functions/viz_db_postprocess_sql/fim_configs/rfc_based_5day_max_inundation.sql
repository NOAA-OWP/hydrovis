DROP TABLE IF EXISTS publish.rfc_based_5day_max_inundation;

SELECT  
	flows.hydro_id,
	flows.hydro_id::TEXT AS hydro_id_str,
	flows.feature_id,
	flows.feature_id::TEXT AS feature_id_str,
	flows.huc8,
	flows.branch,
	channels.strm_order, 
    channels.name,
	channels.state,
	inun.forecast_discharge_cfs as streamflow_cfs,
	inun.rc_discharge_cfs,
	inun.forecast_stage_ft as fim_stage_ft,
	inun.rc_stage_ft,
	inun.max_rc_stage_ft,
	inun.max_rc_discharge_cfs,
	inun.fim_version,
	rnr_flow.influental_forecast_text AS inherited_rfc_forecasts,
    rnr_flow.viz_status AS max_status,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	geo.geom
INTO publish.rfc_based_5day_max_inundation
FROM fim_ingest.rfc_based_5day_max_inundation as inun
JOIN fim_ingest.rfc_based_5day_max_inundation_geo as geo ON inun.hand_id = geo.hand_id
JOIN fim_ingest.rfc_based_5day_max_inundation_flows as flows ON inun.hand_id = flows.hand_id
JOIN publish.rfc_based_5day_max_streamflow rnr_flow ON rnr_flow.feature_id = flows.feature_id
LEFT JOIN derived.channels_conus as channels ON channels.feature_id = flows.feature_id;