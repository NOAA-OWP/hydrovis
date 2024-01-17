-- This is a generic / standardized query to create a publish.fim table for fim_config product processing (works for NWM configurations, but may not work for special fim configurations like RnR or CatFIM)
DROP TABLE IF EXISTS {db_publish_table};

SELECT  
	flows.hydro_id,
	flows.hydro_id::TEXT AS hydro_id_str,
	flows.feature_id,
	flows.feature_id::TEXT AS feature_id_str,
	LPAD(flows.huc8::TEXT, 8, '0') AS huc8,
	flows.branch::TEXT AS branch,
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
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS valid_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	geo.geom as geom
INTO {db_publish_table}
FROM {db_fim_table} as inun
JOIN {db_fim_table}_flows as flows ON inun.hand_id = flows.hand_id
JOIN {db_fim_table}_geo as geo ON inun.hand_id = geo.hand_id
LEFT JOIN derived.channels_{domain} as channels ON channels.feature_id = flows.feature_id
GROUP BY flows.hydro_id, flows.feature_id, flows.huc8, flows.branch, channels.strm_order, channels.name, channels.state, inun.forecast_discharge_cfs, inun.forecast_stage_ft,
		 inun.rc_discharge_cfs,inun.rc_stage_ft,inun.max_rc_stage_ft,inun.max_rc_discharge_cfs,inun.fim_version;