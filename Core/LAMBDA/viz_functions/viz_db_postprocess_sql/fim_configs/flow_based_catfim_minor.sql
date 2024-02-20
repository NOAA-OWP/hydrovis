DROP TABLE IF EXISTS publish.flow_based_catfim_minor;

WITH one_poly_per_station AS (
	SELECT 
		nws_station_id,
		streamflow_cfs,
		fim_version,
		ST_Union(geom) as geom
	FROM ingest.flow_based_catfim_minor
	GROUP BY 
		nws_station_id,
		streamflow_cfs,
		fim_version
), station_no_multi_polygons AS (
	SELECT
		nws_station_id,
		streamflow_cfs,
		fim_version,
		(ST_Dump(geom)).geom AS geom
	FROM one_poly_per_station
), inun AS (
	SELECT 
		nws_station_id, 
		streamflow_cfs,
		STRING_AGG(DISTINCT fim_version, ', ') as fim_version,
		ST_Simplify(ST_BuildArea(ST_Collect(geom)), 1) as geom
	FROM station_no_multi_polygons
	GROUP BY 
		nws_station_id,
		streamflow_cfs,
		fim_version
)

SELECT
	station.nws_station_id,
	station.name AS station_name,
	station.wfo,
	station.rfc,
	station.state,
	inun.streamflow_cfs,
	'minor' AS flow_category,
	flow.minor_source as rating_source,
	inun.fim_version,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	inun.geom
INTO publish.flow_based_catfim_minor
FROM inun
LEFT JOIN external.nws_station AS station
	ON station.nws_station_id = inun.nws_station_id
LEFT JOIN (SELECT DISTINCT ON (nws_station_id) * FROM cache.rfc_categorical_flows) AS flow
	ON flow.nws_station_id = inun.nws_station_id;