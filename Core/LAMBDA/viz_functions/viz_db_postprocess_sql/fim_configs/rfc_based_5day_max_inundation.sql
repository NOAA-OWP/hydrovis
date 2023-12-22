DROP TABLE IF EXISTS publish.rfc_based_5day_max_inundation;

SELECT  
	inun.hydro_id,
	inun.hydro_id::TEXT AS hydro_id_str,
	inun.feature_id,
	inun.feature_id::TEXT AS feature_id_str,
	inun.huc8,
	inun.branch,
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
	ST_COLLECT(geo.geom) as geom
INTO publish.rfc_based_5day_max_inundation
FROM ingest.rfc_based_5day_max_inundation as inun 
JOIN ingest.rfc_based_5day_max_inundation_geo as geo ON inun.feature_id = geo.feature_id AND inun.hydro_id = geo.hydro_id AND inun.huc8 = geo.huc8 AND inun.branch = geo.branch
JOIN publish.rfc_based_5day_max_streamflow rnr_flow ON rnr_flow.feature_id = inun.feature_id
LEFT JOIN derived.channels_conus as channels ON channels.feature_id = inun.feature_id
GROUP BY inun.hydro_id, inun.feature_id, inun.huc8, inun.branch, channels.strm_order, channels.name, channels.state, inun.forecast_discharge_cfs,
		 inun.rc_discharge_cfs,inun.rc_stage_ft,inun.max_rc_stage_ft,inun.max_rc_discharge_cfs,inun.fim_version;