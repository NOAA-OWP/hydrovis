SELECT
    trace_feature_id as feature_id,
	record_flow_cms as streamflow_cms,
    nws_station_id
FROM cache.rfc_categorical_flows AS rf
WHERE record_flow_cms IS NOT NULL;