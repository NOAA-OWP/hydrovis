DROP TABLE IF EXISTS publish.rfc_5day_max_downstream_streamflow;
	
SELECT ingest.rnr_max_flows.feature_id, 
	ingest.rnr_max_flows.feature_id::TEXT AS feature_id_str,
	Name, 
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	STRING_AGG(forecast_nws_lid || ' @ ' || forecast_issue_time || ' (' || forecast_max_status || ')', ', ') AS inherited_rfc_forecasts,
	MAX(forecast_max_value) * 35.31467 AS max_flow,
	INITCAP(MAX(REPLACE(viz_max_status, '_', ' '))) AS max_status,
	INITCAP(MAX(waterbody_status)) AS waterbody_status,
	MAX(viz_status_lid) AS viz_status_lid,
	strm_order,
	huc6,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	geom
INTO publish.rfc_5day_max_downstream_streamflow
FROM ingest.rnr_max_flows
left join derived.channels_conus ON ingest.rnr_max_flows.feature_id = derived.channels_conus.feature_id
GROUP BY ingest.rnr_max_flows.feature_id, feature_id_str, Name, reference_time, strm_order, huc6, geom;