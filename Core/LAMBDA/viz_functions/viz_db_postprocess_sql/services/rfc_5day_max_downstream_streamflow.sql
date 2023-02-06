DROP TABLE IF EXISTS PUBLISH.rfc_5day_max_downstream_streamflow;
	
SELECT ingest.rnr_max_flows.feature_id, 
	ingest.rnr_max_flows.feature_id::TEXT AS feature_id_str,
	Name, 
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	STRING_AGG(FORECAST_NWS_LID || ' @ ' || FORECAST_ISSUE_TIME || ' (' || FORECAST_MAX_STATUS || ')', ', ') AS INHERITED_RFC_FORECASTS,
	MAX(forecast_max_value) * 35.31467 AS MAX_FLOW,
	INITCAP(MAX(REPLACE(VIZ_MAX_STATUS, '_', ' '))) AS MAX_STATUS,
	INITCAP(MAX(WATERBODY_STATUS)) AS WATERBODY_STATUS,
	MAX(VIZ_STATUS_LID) AS VIZ_STATUS_LID,
	Strm_Order,
	huc6,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	geom
INTO PUBLISH.rfc_5day_max_downstream_streamflow
FROM INGEST.RNR_MAX_FLOWS
left join derived.channels_conus ON INGEST.RNR_MAX_FLOWS.feature_id = derived.channels_conus.feature_id
GROUP BY INGEST.RNR_MAX_FLOWS.FEATURE_ID, feature_id_str, Name, reference_time, Strm_Order, huc6, geom;