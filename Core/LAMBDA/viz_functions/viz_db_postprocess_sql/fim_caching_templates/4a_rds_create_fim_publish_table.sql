DROP TABLE IF EXISTS {db_publish_table};

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
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS valid_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	ST_COLLECT(geo.geom) as geom
INTO {db_publish_table}
FROM {db_fim_table} as inun 
JOIN {db_fim_table}_geo as geo ON inun.feature_id = geo.feature_id AND inun.hydro_id = geo.hydro_id AND inun.huc8 = geo.huc8 AND inun.branch = geo.branch
LEFT JOIN derived.channels_{domain} as channels ON channels.feature_id = inun.feature_id
GROUP BY inun.hydro_id, inun.feature_id, inun.huc8, inun.branch, channels.strm_order, channels.name, channels.state, inun.forecast_discharge_cfs, inun.forecast_stage_ft,
		 inun.rc_discharge_cfs,inun.rc_stage_ft,inun.max_rc_stage_ft,inun.max_rc_discharge_cfs,inun.fim_version;