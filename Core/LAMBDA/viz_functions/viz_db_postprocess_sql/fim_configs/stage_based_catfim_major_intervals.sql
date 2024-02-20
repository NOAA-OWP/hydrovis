DROP TABLE IF EXISTS {target_table};

WITH one_poly_per_station AS (
	SELECT 
		nws_station_id,
		fim_stage_ft,
		interval_ft,
		fim_version,
		ST_Union(geom) as geom
	FROM ingest.stage_based_catfim_major_intervals_{ft_from_major}
	GROUP BY 
		nws_station_id,
		fim_stage_ft,
		interval_ft,
		fim_version
), station_no_multi_polygons AS (
	SELECT
		nws_station_id,
		fim_stage_ft,
		interval_ft,
		fim_version,
		(ST_Dump(geom)).geom AS geom
	FROM one_poly_per_station
), inun AS (
	SELECT 
		nws_station_id, 
		fim_stage_ft,
		interval_ft,
		STRING_AGG(DISTINCT fim_version, ', ') as fim_version,
		ST_Simplify(ST_BuildArea(ST_Collect(geom)), 1) as geom
	FROM station_no_multi_polygons
	GROUP BY 
		nws_station_id,
		fim_stage_ft,
		interval_ft,
		fim_version
)

SELECT
	station.nws_station_id,
	station.name AS station_name,
	station.wfo,
	station.rfc,
	station.state,
	inun.fim_stage_ft,
	inun.interval_ft,
	'major' AS stage_category,
	inun.fim_version,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	inun.geom
INTO {target_table}
FROM inun
LEFT JOIN external.nws_station AS station
	ON station.nws_station_id = inun.nws_station_id;