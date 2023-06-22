DROP TABLE IF EXISTS publish.stage_based_catfim_moderate;

SELECT DISTINCT
	inun.hydro_id,
	inun.hydro_id_str::TEXT AS hydro_id_str,
	inun.branch,
	inun.feature_id,
	inun.feature_id_str::TEXT AS feature_id_str,
	inun.hand_stage_ft,
	inun.fim_version,
	inun.huc8,
	inun.geom,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time, 
	channels.strm_order, 
    channels.name,
	inun.nws_station_id,
	station.name as station_name,
	station.wfo,
	station.rfc,
	station.state,
	'moderate' as stage_category

INTO publish.stage_based_catfim_moderate
FROM ingest.stage_based_catfim_moderate AS inun
LEFT JOIN derived.channels_conus as channels
	ON channels.feature_id = inun.feature_id
LEFT JOIN external.nws_station AS station
	ON station.nws_station_id = inun.nws_station_id;