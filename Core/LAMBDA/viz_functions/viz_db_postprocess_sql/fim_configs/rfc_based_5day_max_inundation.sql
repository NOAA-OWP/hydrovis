DROP TABLE IF EXISTS publish.rfc_based_5day_max_inundation;

SELECT  
	inun.hydro_id,
	inun.hydro_id_str::TEXT AS hydro_id_str,
	inun.branch,
	inun.feature_id,
	inun.feature_id_str::TEXT AS feature_id_str,
	inun.streamflow_cfs,
	inun.fim_stage_ft,
	inun.max_rc_stage_ft,
	inun.max_rc_discharge_cfs,
	inun.fim_version,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	inun.huc8,
	inun.geom,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time, 
	channels.strm_order, 
    channels.name,
	channels.state,
    rnr_flow.influental_forecast_text AS inherited_rfc_forecasts,
    rnr_flow.viz_status AS max_status
INTO publish.rfc_based_5day_max_inundation
FROM ingest.rfc_based_5day_max_inundation as inun 
JOIN publish.rfc_based_5day_max_streamflow rnr_flow ON rnr_flow.feature_id = inun.feature_id
LEFT JOIN derived.channels_conus as channels ON channels.feature_id = inun.feature_id;