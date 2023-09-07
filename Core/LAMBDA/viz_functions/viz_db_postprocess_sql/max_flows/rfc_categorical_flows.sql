DROP TABLE IF EXISTS cache.rfc_categorical_flows;

-- Create temporary routelink tables (dropped at end)
SELECT *
INTO ingest.nwm_routelink
FROM external.nwm_routelink;

SELECT 
	main.nwm_feature_id, 
	upstream.nwm_feature_id AS upstream_feature_id, 
	main.stream_length, 
	main.stream_order
INTO ingest.mod_routelink
FROM ingest.nwm_routelink AS main
JOIN ingest.nwm_routelink AS upstream
	ON main.nwm_feature_id = upstream.downstream_feature_id;

SELECT
	threshold.*
INTO ingest.thresholds
FROM external.threshold AS threshold
INNER JOIN external.nws_station AS station
	ON station.nws_station_id = location_id
	AND station.rfc_defined_fcst_point IS TRUE;

-- Start of main query
WITH RECURSIVE

/* ACTION FLOWS */
action_calc_usgs AS (
	SELECT location_id, rating_source, action_flow_calc as flow, 'action' as flow_category FROM ingest.thresholds WHERE action_flow_calc IS NOT null AND rating_source = 'USGS Rating Depot'
),
action_calc_nrldb AS (
	SELECT location_id, rating_source, action_flow_calc as flow, 'action' as flow_category FROM ingest.thresholds WHERE action_flow_calc IS NOT null AND rating_source = 'NRLDB' AND location_id NOT IN (SELECT location_id FROM action_calc_usgs)
),
action_nrldb AS (
	SELECT location_id, rating_source, action_flow as flow, 'action' as flow_category FROM ingest.thresholds WHERE action_flow IS NOT null AND rating_source = 'NONE' AND location_id NOT IN (SELECT location_id FROM action_calc_usgs UNION SELECT location_id FROM action_calc_nrldb)
),
all_action AS (
	SELECT * FROM action_calc_usgs
	UNION
	SELECT * FROM action_calc_nrldb
	UNION
	SELECT * FROM action_nrldb
),

/* MINOR FLOWS */
minor_calc_usgs AS (
	SELECT location_id, rating_source, minor_flow_calc as flow, 'minor' as flow_category FROM ingest.thresholds WHERE minor_flow_calc IS NOT null AND rating_source = 'USGS Rating Depot'
),
minor_calc_nrldb AS (
	SELECT location_id, rating_source, minor_flow_calc as flow, 'minor' as flow_category FROM ingest.thresholds WHERE minor_flow_calc IS NOT null AND rating_source = 'NRLDB' AND location_id NOT IN (SELECT location_id FROM minor_calc_usgs)
),
minor_nrldb AS (
	SELECT location_id, rating_source, minor_flow as flow, 'minor' as flow_category FROM ingest.thresholds WHERE minor_flow IS NOT null AND rating_source = 'NONE' AND location_id NOT IN (SELECT location_id FROM minor_calc_usgs UNION SELECT location_id FROM minor_calc_nrldb)
),
all_minor AS (
	SELECT * FROM minor_calc_usgs
	UNION
	SELECT * FROM minor_calc_nrldb
	UNION
	SELECT * FROM minor_nrldb
),

/* MODERATE FLOWS */
moderate_calc_usgs AS (
	SELECT location_id, rating_source, moderate_flow_calc as flow, 'moderate' as flow_category FROM ingest.thresholds WHERE moderate_flow_calc IS NOT null AND rating_source = 'USGS Rating Depot'
),
moderate_calc_nrldb AS (
	SELECT location_id, rating_source, moderate_flow_calc as flow, 'moderate' as flow_category FROM ingest.thresholds WHERE moderate_flow_calc IS NOT null AND rating_source = 'NRLDB' AND location_id NOT IN (SELECT location_id FROM moderate_calc_usgs)
),
moderate_nrldb AS (
	SELECT location_id, rating_source, moderate_flow as flow, 'moderate' as flow_category FROM ingest.thresholds WHERE moderate_flow IS NOT null AND rating_source = 'NONE' AND location_id NOT IN (SELECT location_id FROM moderate_calc_usgs UNION SELECT location_id FROM moderate_calc_nrldb)
),
all_moderate AS (
	SELECT * FROM moderate_calc_usgs
	UNION
	SELECT * FROM moderate_calc_nrldb
	UNION
	SELECT * FROM moderate_nrldb
),

/* MAJOR FLOWS */
major_calc_usgs AS (
	SELECT location_id, rating_source, major_flow_calc as flow, 'major' as flow_category FROM ingest.thresholds WHERE major_flow_calc IS NOT null AND rating_source = 'USGS Rating Depot'
),
major_calc_nrldb AS (
	SELECT location_id, rating_source, major_flow_calc as flow, 'major' as flow_category FROM ingest.thresholds WHERE major_flow_calc IS NOT null AND rating_source = 'NRLDB' AND location_id NOT IN (SELECT location_id FROM major_calc_usgs)
),
major_nrldb AS (
	SELECT location_id, rating_source, major_flow as flow, 'major' as flow_category FROM ingest.thresholds WHERE major_flow IS NOT null AND rating_source = 'NONE' AND location_id NOT IN (SELECT location_id FROM major_calc_usgs UNION SELECT location_id FROM major_calc_nrldb)
),
all_major AS (
	SELECT * FROM major_calc_usgs
	UNION
	SELECT * FROM major_calc_nrldb
	UNION
	SELECT * FROM major_nrldb
),

/* RECORD FLOWS */
record_calc_usgs AS (
	SELECT location_id, rating_source, record_flow_calc as flow, 'record' as flow_category FROM ingest.thresholds WHERE record_flow_calc IS NOT null AND rating_source = 'USGS Rating Depot'
),
record_calc_nrldb AS (
	SELECT location_id, rating_source, record_flow_calc as flow, 'record' as flow_category FROM ingest.thresholds WHERE record_flow_calc IS NOT null AND rating_source = 'NRLDB' AND location_id NOT IN (SELECT location_id FROM record_calc_usgs)
),
record_nrldb AS (
	SELECT location_id, rating_source, record_flow as flow, 'record' as flow_category FROM ingest.thresholds WHERE record_flow IS NOT null AND rating_source = 'NONE' AND location_id NOT IN (SELECT location_id FROM record_calc_usgs UNION SELECT location_id FROM record_calc_nrldb)
),
all_record AS (
	SELECT * FROM record_calc_usgs
	UNION
	SELECT * FROM record_calc_nrldb
	UNION
	SELECT * FROM record_nrldb
),

/* COMBINED FLOWS */
all_categorical_flows AS (
	SELECT * FROM all_action
	UNION
	SELECT * FROM all_minor
	UNION
	SELECT * FROM all_moderate
	UNION
	SELECT * FROM all_major
	UNION
	SELECT * FROM all_record
),

basis_sites AS (
	SELECT DISTINCT ON (site.location_id)
        site.location_id as nws_station_id,
        xwalk.nwm_feature_id,
		action.rating_source as action_source, 
		action.flow as action_flow,
		minor.rating_source as minor_source, 
		minor.flow as minor_flow,
		moderate.rating_source as moderate_source, 
		moderate.flow as moderate_flow,
		major.rating_source as major_source, 
		major.flow as major_flow,
		record.rating_source as record_source, 
		record.flow as record_flow
	FROM (SELECT DISTINCT location_id FROM all_categorical_flows) site
	LEFT JOIN all_categorical_flows AS action
		ON action.location_id = site.location_id
		AND action.flow_category = 'action'
	LEFT JOIN all_categorical_flows AS minor
		ON minor.location_id = site.location_id
		AND minor.flow_category = 'minor'
	LEFT JOIN all_categorical_flows AS moderate
		ON moderate.location_id = site.location_id
		AND moderate.flow_category = 'moderate'
	LEFT JOIN all_categorical_flows AS major
		ON major.location_id = site.location_id
		AND major.flow_category = 'major'
	LEFT JOIN all_categorical_flows AS record
		ON record.location_id = site.location_id
		AND record.flow_category = 'record'
	LEFT JOIN external.full_crosswalk_view AS xwalk
		ON xwalk.nws_station_id = site.location_id
	ORDER BY site.location_id, xwalk.nwm_feature_id
),

upstream_trace AS (
	SELECT 
		rl.nwm_feature_id as root_feature_id, 
		rl.nwm_feature_id as trace_feature_id, 
		rl.upstream_feature_id, 
		rl.stream_order, 
		rl.stream_length, 
		SUM(CAST(0 as float)) as trace_length
	FROM basis_sites
	INNER JOIN ingest.mod_routelink AS rl
		ON rl.nwm_feature_id = basis_sites.nwm_feature_id
	GROUP BY trace_feature_id, upstream_feature_id, stream_order, stream_length

	UNION

	SELECT upstream_trace.root_feature_id, iter.nwm_feature_id as trace_feature_id, iter.upstream_feature_id, iter.stream_order, iter.stream_length, upstream_trace.trace_length + iter.stream_length as trace_length
	FROM ingest.mod_routelink iter
	JOIN upstream_trace 
		ON iter.nwm_feature_id = upstream_trace.upstream_feature_id
		AND iter.stream_order = upstream_trace.stream_order
		AND upstream_trace.trace_length + iter.stream_length < 8047
),

downstream_trace AS (
	SELECT 
		rl.nwm_feature_id as root_feature_id, 
		rl.nwm_feature_id as trace_feature_id, 
		rl.downstream_feature_id, 
		rl.stream_order, 
		rl.stream_length, 
		SUM(CAST(0 as float)) as trace_length
	FROM basis_sites
	INNER JOIN ingest.nwm_routelink AS rl
		ON rl.nwm_feature_id = basis_sites.nwm_feature_id
	GROUP BY trace_feature_id, downstream_feature_id, stream_order, stream_length

	UNION

	SELECT downstream_trace.root_feature_id, iter.nwm_feature_id as trace_feature_id, iter.downstream_feature_id, iter.stream_order, iter.stream_length, downstream_trace.trace_length + iter.stream_length as trace_length
	FROM ingest.nwm_routelink iter
	JOIN downstream_trace 
		ON iter.nwm_feature_id = downstream_trace.downstream_feature_id
		AND iter.stream_order = downstream_trace.stream_order
		AND downstream_trace.trace_length + iter.stream_length < 8047
),

trace AS (
	SELECT 
		root_feature_id,
		trace_feature_id
	FROM downstream_trace
	
	UNION
	
	SELECT 
		root_feature_id,
		trace_feature_id
	FROM upstream_trace
)

SELECT
	trace.root_feature_id as nwm_feature_id,
	trace.trace_feature_id,
	basis_sites.nws_station_id,
	basis_sites.action_source,
	basis_sites.action_flow as action_flow_cfs,
    basis_sites.action_flow * 0.02831 as action_flow_cms,
	basis_sites.minor_source,
	basis_sites.minor_flow as minor_flow_cfs,
    basis_sites.minor_flow * 0.02831 as minor_flow_cms,
	basis_sites.moderate_source,
	basis_sites.moderate_flow as moderate_flow_cfs,
    basis_sites.moderate_flow * 0.02831 as moderate_flow_cms,
	basis_sites.major_source,
	basis_sites.major_flow as major_flow_cfs,
    basis_sites.major_flow * 0.02831 as major_flow_cms,
	basis_sites.record_source,
	basis_sites.record_flow as record_flow_cfs,
    basis_sites.record_flow * 0.02831 as record_flow_cms
INTO cache.rfc_categorical_flows
FROM trace
LEFT JOIN basis_sites
	ON basis_sites.nwm_feature_id = trace.root_feature_id;

DROP TABLE IF EXISTS ingest.mod_routelink;
DROP TABLE IF EXISTS ingest.nwm_routelink;
DROP TABLE IF EXISTS ingest.thresholds;