DROP TABLE IF EXISTS publish.srf_18hr_max_inundation_extent;

SELECT  
	inun.hydro_id,
	inun.hydro_id_str::TEXT AS hydro_id_str,
	inun.branch,
	inun.feature_id,
	inun.feature_id_str::TEXT AS feature_id_str,
	inun.streamflow_cfs,
	inun.hand_stage_ft,
	inun.max_rc_stage_ft,
	inun.max_rc_discharge_cfs,
	inun.fim_version,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	inun.huc8,
	inun.geom,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time, 
	derived.channels_conus.strm_order, 
    derived.channels_conus.name
INTO publish.srf_18hr_max_inundation_extent
FROM ingest.srf_18hr_max_inundation_extent as inun 
left join derived.channels_conus ON derived.channels_conus.feature_id = inun.feature_id;