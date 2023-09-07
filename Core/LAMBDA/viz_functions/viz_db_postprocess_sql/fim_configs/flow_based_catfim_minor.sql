DROP TABLE IF EXISTS publish.flow_based_catfim_minor;


SELECT DISTINCT
	inun.hydro_id,
	inun.hydro_id_str::TEXT AS hydro_id_str,
	inun.branch,
	inun.feature_id,
	inun.feature_id_str::TEXT AS feature_id_str,
	inun.nws_station_id,
	inun.streamflow_cfs,
	inun.fim_stage_ft,
	inun.max_rc_stage_ft,
	inun.max_rc_discharge_cfs,
	inun.fim_version,
	inun.huc8,
	inun.geom,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time, 
	channels.strm_order, 
    channels.name,
	station.name as station_name,
	station.wfo,
	station.rfc,
	station.state,
	flow.minor_source as rating_source,
	'minor' as flow_category

INTO publish.flow_based_catfim_minor
FROM ingest.flow_based_catfim_minor AS inun 
LEFT JOIN derived.channels_conus as channels ON channels.feature_id = inun.feature_id
LEFT JOIN external.nws_station AS station
	ON station.nws_station_id = inun.nws_station_id
LEFT JOIN cache.rfc_categorical_flows AS flow
	ON flow.nws_station_id = inun.nws_station_id
	AND flow.trace_feature_id = inun.feature_id;