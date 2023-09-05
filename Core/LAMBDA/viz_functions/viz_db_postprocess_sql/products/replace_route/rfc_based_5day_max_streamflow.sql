DROP TABLE IF EXISTS publish.rfc_based_5day_max_streamflow;

WITH RECURSIVE

max_flows_station_xwalk AS (
	SELECT 
		mf.feature_id,
		xwalk.nws_station_id,
		station.rfc_defined_fcst_point,
		mf.reference_time,
		mf.time_of_max,
		mf.maxflow_5day_cfs as streamflow,
		mf.maxflow_5day_cms as streamflow_cms,
		rl.downstream_feature_id,
		rl.stream_order,
		rl.stream_length,
		CASE
			WHEN rl.nhd_waterbody_comid IS NOT NULL
			THEN TRUE
			ELSE FALSE
		END AS is_waterbody
	FROM cache.max_flows_rnr mf
	LEFT JOIN external.nwm_routelink rl
		ON rl.nwm_feature_id = mf.feature_id
	LEFT JOIN rnr.nwm_crosswalk xwalk
		ON xwalk.nwm_feature_id = mf.feature_id
		AND nws_station_id IS NOT NULL
		AND nws_station_id NOT LIKE '%TEST%'
	LEFT JOIN external.nws_station station
		ON station.nws_station_id = xwalk.nws_station_id
),

usgs_threshold AS (
	SELECT DISTINCT ON (location_id) 
		location_id as nws_station_id,
		rating_source,
		action_flow_calc as action_flow,
		minor_flow_calc as minor_flow,
		moderate_flow_calc as moderate_flow,
		major_flow_calc as major_flow
	FROM external.threshold
	WHERE rating_source = 'USGS Rating Depot' AND location_id IN (SELECT nws_station_id FROM max_flows_station_xwalk)
), nrldb_threshold AS (
	SELECT DISTINCT ON (location_id)
		location_id as nws_station_id,
		rating_source,
		action_flow_calc as action_flow,
		minor_flow_calc as minor_flow,
		moderate_flow_calc as moderate_flow,
		major_flow_calc as major_flow
	FROM external.threshold
	WHERE rating_source = 'NRLDB' AND location_id IN (SELECT nws_station_id FROM max_flows_station_xwalk) AND location_id NOT IN (SELECT nws_station_id FROM usgs_threshold)
), native_threshold AS (
	SELECT DISTINCT ON (location_id)
		location_id as nws_station_id,
		rating_source,
		action_flow,
		minor_flow,
		moderate_flow,
		major_flow
	FROM external.threshold
	WHERE rating_source = 'NONE' AND location_id IN (SELECT nws_station_id FROM max_flows_station_xwalk) AND location_id NOT IN (SELECT nws_station_id FROM usgs_threshold UNION SELECT nws_station_id FROM nrldb_threshold)
), threshold AS (
	SELECT * FROM usgs_threshold
	UNION
	SELECT * FROM nrldb_threshold
	UNION
	SELECT * FROM native_threshold
),

fcst AS (
	SELECT DISTINCT ON (lid, product_time) 
		lid, 
		product_time as issue_time
	FROM rnr.domain_forecasts
),

root_status_trace_reaches AS (
	SELECT DISTINCT ON (feature_id)
		feature_id, 
		mf.nws_station_id,
		rfc_defined_fcst_point,
		downstream_feature_id,
		stream_order,
		stream_length,
		is_waterbody,
		issue_time,
		rating_source,
		CASE
			WHEN rfc_defined_fcst_point AND issue_time IS NULL
			THEN 'No Forecast'
			WHEN major_flow IS NOT NULL AND streamflow > major_flow
			THEN 'Major'
			WHEN moderate_flow IS NOT NULL AND streamflow > moderate_flow
			THEN 'Moderate'
			WHEN minor_flow IS NOT NULL AND streamflow > minor_flow
			THEN 'Minor'
			WHEN action_flow IS NOT NULL AND streamflow > action_flow
			THEN 'Action'
			WHEN issue_time IS NOT NULL AND action_flow IS NULL AND minor_flow IS NULL AND moderate_flow IS NULL AND major_flow IS NULL
			THEN 'All Thresholds Undefined'
			WHEN mf.nws_station_id IS NOT NULL
			THEN 'No Flooding'
			ELSE ''
		END as max_status
	FROM max_flows_station_xwalk mf
	LEFT JOIN fcst
		ON fcst.lid = mf.nws_station_id
	LEFT JOIN threshold
		ON threshold.nws_station_id = mf.nws_station_id
	WHERE rfc_defined_fcst_point IS TRUE OR issue_time IS NOT NULL
	ORDER BY feature_id, issue_time, rfc_defined_fcst_point DESC
),

status_trace AS (
	SELECT 
		feature_id as root_feature_id,
		nws_station_id::text as influential_forecast_point,
		issue_time,
		FALSE AS is_waterbody,
		FALSE AS is_below_waterbody,
		feature_id as trace_feature_id,
		downstream_feature_id,
		stream_order AS root_stream_order,
		stream_order,
		max_status,
		rating_source,
		stream_length,
		SUM(CAST(0 as float)) as distance_from_forecast_point
	FROM root_status_trace_reaches
	GROUP BY
		influential_forecast_point,
		issue_time,
		is_waterbody,
		is_below_waterbody,
		trace_feature_id, 
		downstream_feature_id,
		root_stream_order, 
		stream_order, 
		max_status,
		rating_source,
		stream_length

	UNION

	SELECT 
		root.root_feature_id,
		root.influential_forecast_point, 
		root.issue_time,
		iter.is_waterbody,
		root.is_waterbody OR root.is_below_waterbody AS is_below_waterbody,
		iter.feature_id as trace_feature_id,
		iter.downstream_feature_id, 
		root.root_stream_order, 
		iter.stream_order,
		root.max_status,
		root.rating_source,
		iter.stream_length, 
		root.distance_from_forecast_point + iter.stream_length as distance_from_forecast_point
	FROM max_flows_station_xwalk iter
	JOIN status_trace root
		ON iter.feature_id = root.downstream_feature_id
		AND iter.stream_order <= root.stream_order + 1
		AND iter.feature_id NOT IN (SELECT feature_id FROM root_status_trace_reaches)
),

agg_trace AS (
	SELECT
		trace_feature_id,
		BOOL_AND(is_waterbody) as is_waterbody,
		BOOL_AND(is_below_waterbody) as is_below_waterbody,
		MAX(stream_order) as stream_order,
		influential_forecast_point,
		STRING_AGG(
			CASE
				WHEN max_status = 'All Thresholds Undefined'
				THEN max_status || ' at ' || influential_forecast_point || ' (' || root_feature_id || ' [' || root_stream_order || ']) despite forecast issued ' || issue_time || ' ' || ROUND(CAST(distance_from_forecast_point * 0.000621 as numeric), 1) || ' miles upstream'
				WHEN issue_time IS NOT NULL
				THEN max_status || ' (' || rating_source || ') issued ' || issue_time || ' at ' || influential_forecast_point || ' (' || root_feature_id || ' [' || root_stream_order || ']) ' || ROUND(CAST(distance_from_forecast_point * 0.000621 as numeric), 1) || ' miles upstream'
				ELSE max_status || ' at ' || influential_forecast_point || ' (' || root_feature_id || ' [' || root_stream_order || ']) ' || ROUND(CAST(distance_from_forecast_point * 0.000621 as numeric), 1) || ' miles upstream'
			END,
			'; '
			ORDER BY distance_from_forecast_point
		) AS influental_forecast_text,
		(ARRAY_AGG(
			max_status
			ORDER BY distance_from_forecast_point
		))[1] AS viz_status
	FROM status_trace
	GROUP BY trace_feature_id, influential_forecast_point
)

SELECT DISTINCT ON (mf.feature_id)
	mf.feature_id,
	channel.feature_id::TEXT AS feature_id_str,
	mf.nws_station_id,
	CASE 
		WHEN mf.rfc_defined_fcst_point
		THEN 'Yes'
		ELSE 'No'
	END as has_forecast_point,
	channel.name,
	channel.huc6,
	TO_CHAR(mf.time_of_max, 'YYYY-MM-DD HH24:MI:SS UTC') as time_of_max,
	mf.reference_time,
	mf.streamflow,
	mf.streamflow_cms,
	mf.stream_order,
	CASE WHEN agg.is_waterbody THEN 'yes' ELSE 'no' END AS is_waterbody,
	CASE WHEN agg.is_below_waterbody THEN 'yes' ELSE 'no' END as is_downstream_of_waterbody,
	agg.influental_forecast_text,
	CASE
		WHEN agg.viz_status IS NULL
		THEN 'Undetermined'
		ELSE agg.viz_status
	END as viz_status,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	channel.geom
INTO publish.rfc_based_5day_max_streamflow
FROM max_flows_station_xwalk mf
LEFT JOIN agg_trace agg
	ON agg.trace_feature_id = mf.feature_id
LEFT JOIN derived.channels_conus channel 
	ON channel.feature_id = mf.feature_id;