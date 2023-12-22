SELECT
    trace_feature_id as feature_id,
	minor_flow_cms as streamflow_cms,
    nws_station_id
FROM cache.rfc_categorical_flows AS rf
WHERE minor_flow_cms IS NOT NULL;